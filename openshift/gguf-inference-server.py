#!/usr/bin/env python3

import json
import time
import logging
import os
from flask import Flask, request, jsonify, Response
from ctransformers import AutoModelForCausalLM

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)

model = None
model_loaded = False
model_name = "mistral-7b-instruct-gguf"

def load_gguf_model():
    """Load Mistral GGUF model using ctransformers"""
    global model, model_loaded
    
    try:
        model_path = "/models/mistral.gguf"
        logger.info(f"Loading Mistral GGUF model from {model_path}")
        
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"Model file {model_path} not found")
        
        model_size = os.path.getsize(model_path) / (1024**3)
        logger.info(f"Model file size: {model_size:.2f} GB")
        
        logger.info("Loading GGUF model with ctransformers (CPU optimized)...")
        
        model = AutoModelForCausalLM.from_pretrained(
            model_path,
            model_type="mistral",
            gpu_layers=0,
            threads=8,
            context_length=4096,
            max_new_tokens=512
        )
        
        logger.info("Mistral GGUF model loaded successfully!")
        logger.info(f"Context length: 4096 tokens")
        logger.info(f"CPU threads: 8")
        model_loaded = True
        
    except Exception as e:
        logger.error(f"Failed to load GGUF model: {e}")
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        model_loaded = False

def generate_response(message_content, max_tokens=500, stream=False):
    """Generate response using GGUF model"""
    global model
    
    if not model_loaded or model is None:
        logger.error("Model not loaded, cannot generate response")
        return None
    
    try:
        system_prompt = """You are an expert L1 Network Troubleshooting AI assistant specializing in telecommunications infrastructure. 
Analyze network anomalies at the physical layer and provide specific, actionable technical recommendations."""
        
        prompt = f"""<s>[INST] {system_prompt}

User Query: {message_content}

Provide detailed L1 network analysis with specific troubleshooting steps. [/INST]"""
        
        logger.info(f"Generating response for query: {message_content[:100]}...")
        
        if stream:
            return model(
                prompt,
                max_new_tokens=max_tokens,
                temperature=0.7,
                top_p=0.95,
                stream=True
            )
        else:
            response = model(
                prompt,
                max_new_tokens=max_tokens,
                temperature=0.7,
                top_p=0.95
            )
            return response.strip()
            
    except Exception as e:
        logger.error(f"Error generating response: {e}")
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        return None

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy" if model_loaded else "loading",
        "model_loaded": model_loaded,
        "model_name": model_name,
        "backend": "ctransformers",
        "format": "GGUF Q4_K_M",
        "device": "CPU",
        "timestamp": time.time()
    })

@app.route('/v1/models', methods=['GET'])
def list_models():
    """List available models - OpenAI compatible"""
    return jsonify({
        "object": "list",
        "data": [{
            "id": model_name,
            "object": "model",
            "created": int(time.time()),
            "owned_by": "l1-system",
            "backend": "ctransformers-gguf"
        }]
    })

@app.route('/v1/chat/completions', methods=['POST'])
def chat_completions():
    """OpenAI-compatible chat completions endpoint"""
    try:
        data = request.get_json()
        messages = data.get('messages', [])
        max_tokens = data.get('max_tokens', 500)
        stream = data.get('stream', False)
        
        user_message = ""
        for msg in reversed(messages):
            if msg.get('role') == 'user':
                user_message = msg.get('content', '')
                break
        
        if not user_message:
            return jsonify({"error": "No user message found"}), 400
        
        if not model_loaded:
            return jsonify({"error": "Model not loaded"}), 503
        
        if stream:
            def stream_response():
                try:
                    response_gen = generate_response(user_message, max_tokens, stream=True)
                    if response_gen:
                        for token in response_gen:
                            chunk_data = {
                                "id": f"chatcmpl-{int(time.time()*1000)}",
                                "object": "chat.completion.chunk",
                                "created": int(time.time()),
                                "model": model_name,
                                "choices": [{
                                    "index": 0,
                                    "delta": {"content": token},
                                    "finish_reason": None
                                }]
                            }
                            yield f"data: {json.dumps(chunk_data)}\n\n"
                        
                        final_chunk = {
                            "id": f"chatcmpl-{int(time.time()*1000)}",
                            "object": "chat.completion.chunk",
                            "created": int(time.time()),
                            "model": model_name,
                            "choices": [{
                                "index": 0,
                                "delta": {},
                                "finish_reason": "stop"
                            }]
                        }
                        yield f"data: {json.dumps(final_chunk)}\n\n"
                        yield "data: [DONE]\n\n"
                except Exception as e:
                    logger.error(f"Streaming error: {e}")
                    error_chunk = {
                        "error": {
                            "message": str(e),
                            "type": "generation_error"
                        }
                    }
                    yield f"data: {json.dumps(error_chunk)}\n\n"
            
            return Response(stream_response(), mimetype='text/event-stream')
        else:
            response_text = generate_response(user_message, max_tokens, stream=False)
            
            if response_text is None:
                return jsonify({"error": "Failed to generate response"}), 500
            
            return jsonify({
                "id": f"chatcmpl-{int(time.time()*1000)}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": model_name,
                "choices": [{
                    "index": 0,
                    "message": {"role": "assistant", "content": response_text},
                    "finish_reason": "stop"
                }],
                "usage": {
                    "prompt_tokens": len(user_message.split()),
                    "completion_tokens": len(response_text.split()),
                    "total_tokens": len(user_message.split()) + len(response_text.split())
                }
            })
            
    except Exception as e:
        logger.error(f"Error in chat_completions: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    logger.info("Starting GGUF Inference Server with ctransformers...")
    load_gguf_model()
    
    if model_loaded:
        logger.info("GGUF model loaded successfully, starting Flask server on port 8000...")
    else:
        logger.warning("Model failed to load, server starting anyway...")
    
    app.run(host='0.0.0.0', port=8000, threaded=True)
