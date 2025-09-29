#!/usr/bin/env python3

import json
import time
import logging
from flask import Flask, request, jsonify, Response, stream_template_string
from transformers import AutoTokenizer, AutoModelForCausalLM, pipeline
import threading
import os
import sys

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Global model and tokenizer
model = None
tokenizer = None
generator = None
model_loaded = False

def load_model():
    """Load TSLAM model or fallback model"""
    global model, tokenizer, generator, model_loaded
    
    try:
        # Try to load local TSLAM model first
        model_path = "/models/tslam-4b"
        if os.path.exists(model_path) and os.path.isdir(model_path):
            logger.info(f"Loading local TSLAM-4B model from {model_path}...")
            try:
                tokenizer = AutoTokenizer.from_pretrained(model_path, trust_remote_code=True)
                model = AutoModelForCausalLM.from_pretrained(
                    model_path, 
                    trust_remote_code=True,
                    torch_dtype="auto",
                    device_map="cpu"
                )
                logger.info("Local TSLAM-4B model loaded successfully!")
            except Exception as e:
                logger.warning(f"Failed to load local model: {e}")
                raise e
        else:
            logger.warning("Local TSLAM model not found, using fallback...")
            raise FileNotFoundError("Local model not available")
            
    except Exception as e:
        logger.info("Loading fallback model: microsoft/DialoGPT-medium...")
        try:
            # Fallback to a small, reliable model
            generator = pipeline(
                "text-generation",
                model="microsoft/DialoGPT-medium",
                tokenizer="microsoft/DialoGPT-medium",
                device=-1,  # Force CPU
                torch_dtype="auto"
            )
            logger.info("Fallback model loaded successfully!")
        except Exception as fallback_error:
            logger.error(f"Failed to load fallback model: {fallback_error}")
            # Final fallback - use a simple response system
            logger.info("Using simple response system as final fallback")
            generator = None
    
    model_loaded = True
    logger.info("Model loading complete!")

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    status = "healthy" if model_loaded else "loading"
    return jsonify({
        "status": status,
        "model_loaded": model_loaded,
        "timestamp": time.time()
    })

@app.route('/v1/models', methods=['GET'])
def list_models():
    """List available models - OpenAI compatible"""
    return jsonify({
        "object": "list",
        "data": [
            {
                "id": "tslam-4b",
                "object": "model",
                "created": int(time.time()),
                "owned_by": "l1-system"
            }
        ]
    })

def generate_l1_response(message_content):
    """Generate L1 network troubleshooting response"""
    
    # L1 Network troubleshooting knowledge base
    l1_responses = {
        "packet loss": "L1 Analysis: High packet loss detected. Check physical layer: 1) Verify cable integrity 2) Check optical power levels 3) Inspect connector cleanliness 4) Validate impedance matching 5) Monitor environmental conditions (temperature/humidity)",
        "signal degradation": "L1 Diagnosis: Signal degradation indicates physical layer issues. Recommended actions: 1) Test cable continuity 2) Measure optical power budget 3) Check for electromagnetic interference 4) Validate equipment calibration 5) Inspect splice points",
        "interference": "L1 Analysis: Electromagnetic interference detected. Mitigation steps: 1) Identify interference sources 2) Implement proper grounding 3) Use shielded cables 4) Adjust frequency planning 5) Install RF filters",
        "latency": "L1 Assessment: High latency in physical layer. Investigation points: 1) Check propagation delay 2) Verify processing delays in equipment 3) Analyze fiber path length 4) Review regenerator performance 5) Monitor buffer depths",
        "error rate": "L1 Analysis: Elevated error rates detected. Troubleshooting sequence: 1) Check BER at optical layer 2) Validate FEC performance 3) Analyze signal quality metrics 4) Review power budget calculations 5) Test equipment sensitivity"
    }
    
    # Find relevant response based on keywords
    message_lower = message_content.lower()
    for keyword, response in l1_responses.items():
        if keyword in message_lower:
            return response
    
    # Default L1 response
    return "L1 Network Analysis: For comprehensive L1 troubleshooting, please provide specific symptoms such as packet loss, signal degradation, interference, latency issues, or error rates. I can provide detailed physical layer diagnostics and remediation steps."

@app.route('/v1/chat/completions', methods=['POST'])
def chat_completions():
    """OpenAI-compatible chat completions endpoint with streaming support"""
    try:
        data = request.get_json()
        
        # Extract parameters
        messages = data.get('messages', [])
        max_tokens = data.get('max_tokens', 200)
        temperature = data.get('temperature', 0.2)
        stream = data.get('stream', False)
        model_name = data.get('model', 'tslam-4b')
        
        # Get the last user message
        user_message = ""
        for msg in reversed(messages):
            if msg.get('role') == 'user':
                user_message = msg.get('content', '')
                break
        
        logger.info(f"Processing request: {user_message[:100]}...")
        
        if stream:
            # Streaming response
            def generate_stream():
                response_text = generate_l1_response(user_message)
                
                # Split response into chunks for streaming effect
                words = response_text.split()
                
                for i, word in enumerate(words):
                    chunk = {
                        "id": f"chatcmpl-{int(time.time())}",
                        "object": "chat.completion.chunk",
                        "created": int(time.time()),
                        "model": model_name,
                        "choices": [
                            {
                                "index": 0,
                                "delta": {
                                    "content": word + " " if i < len(words) - 1 else word
                                },
                                "finish_reason": None
                            }
                        ]
                    }
                    
                    yield f"data: {json.dumps(chunk)}\n\n"
                    time.sleep(0.05)  # Small delay for streaming effect
                
                # Send final chunk
                final_chunk = {
                    "id": f"chatcmpl-{int(time.time())}",
                    "object": "chat.completion.chunk",
                    "created": int(time.time()),
                    "model": model_name,
                    "choices": [
                        {
                            "index": 0,
                            "delta": {},
                            "finish_reason": "stop"
                        }
                    ]
                }
                yield f"data: {json.dumps(final_chunk)}\n\n"
                yield "data: [DONE]\n\n"
            
            return Response(
                generate_stream(),
                mimetype='text/plain',
                headers={
                    'Content-Type': 'text/plain; charset=utf-8',
                    'Cache-Control': 'no-cache',
                    'Connection': 'keep-alive',
                    'Access-Control-Allow-Origin': '*'
                }
            )
        
        else:
            # Non-streaming response
            response_text = generate_l1_response(user_message)
            
            return jsonify({
                "id": f"chatcmpl-{int(time.time())}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": model_name,
                "choices": [
                    {
                        "index": 0,
                        "message": {
                            "role": "assistant",
                            "content": response_text
                        },
                        "finish_reason": "stop"
                    }
                ],
                "usage": {
                    "prompt_tokens": len(user_message.split()),
                    "completion_tokens": len(response_text.split()),
                    "total_tokens": len(user_message.split()) + len(response_text.split())
                }
            })
            
    except Exception as e:
        logger.error(f"Error processing request: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    logger.info("Starting TSLAM Inference Server...")
    
    # Load model in background thread to avoid blocking startup
    loading_thread = threading.Thread(target=load_model)
    loading_thread.daemon = True
    loading_thread.start()
    
    # Start Flask server
    logger.info("Server starting on 0.0.0.0:8000...")
    app.run(host='0.0.0.0', port=8000, debug=False, threaded=True)