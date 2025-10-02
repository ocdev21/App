#!/usr/bin/env python3

import json
import time
import logging
import os
from flask import Flask, request, jsonify, Response
from transformers import AutoTokenizer, AutoModelForCausalLM
import torch

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)

model = None
tokenizer = None
model_loaded = False
model_name = "mistral-7b-instruct"

def load_mistral_model():
    """Load Mistral-7B model using transformers"""
    global model, tokenizer, model_loaded
    
    try:
        model_path = "/models/mistral-7b"
        logger.info(f"Loading Mistral-7B model from {model_path}")
        
        if not os.path.exists(model_path):
            # Fallback: try to load from HuggingFace
            model_path = "mistralai/Mistral-7B-Instruct-v0.2"
            logger.info(f"Local model not found, loading from HuggingFace: {model_path}")
        
        logger.info("Loading tokenizer...")
        tokenizer = AutoTokenizer.from_pretrained(
            model_path,
            trust_remote_code=True
        )
        
        logger.info("Loading model on CPU (this may take a few minutes)...")
        model = AutoModelForCausalLM.from_pretrained(
            model_path,
            torch_dtype=torch.float32,
            device_map="cpu",
            low_cpu_mem_usage=True,
            trust_remote_code=True
        )
        
        logger.info("Mistral-7B model loaded successfully on CPU!")
        logger.info(f"Model device: {next(model.parameters()).device}")
        model_loaded = True
        
    except Exception as e:
        logger.error(f"Failed to load Mistral model: {e}")
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        model_loaded = False

def generate_mistral_response(message_content, max_tokens=500, stream=False):
    """Generate response using Mistral model"""
    global model, tokenizer
    
    if not model_loaded or model is None or tokenizer is None:
        logger.error("Model not loaded, cannot generate response")
        return None
    
    try:
        # L1 network troubleshooting prompt
        system_prompt = """You are an expert L1 Network Troubleshooting AI assistant specializing in telecommunications infrastructure. 
Analyze network anomalies at the physical layer and provide specific, actionable technical recommendations."""
        
        # Format for Mistral Instruct
        prompt = f"""<s>[INST] {system_prompt}

User Query: {message_content}

Provide detailed L1 network analysis with specific troubleshooting steps. [/INST]"""
        
        logger.info(f"Generating response for query: {message_content[:100]}...")
        
        inputs = tokenizer(prompt, return_tensors="pt")
        
        if stream:
            # Streaming generation
            from transformers import TextIteratorStreamer
            from threading import Thread
            
            streamer = TextIteratorStreamer(tokenizer, skip_special_tokens=True)
            generation_kwargs = {
                **inputs,
                "max_new_tokens": max_tokens,
                "temperature": 0.7,
                "do_sample": True,
                "top_p": 0.95,
                "streamer": streamer
            }
            
            thread = Thread(target=model.generate, kwargs=generation_kwargs)
            thread.start()
            
            # Skip the prompt part and yield only generated text
            prompt_text = tokenizer.decode(inputs['input_ids'][0], skip_special_tokens=True)
            full_text = ""
            for new_text in streamer:
                full_text += new_text
                if len(full_text) > len(prompt_text):
                    yield full_text[len(prompt_text):]
            
        else:
            # Non-streaming generation
            with torch.no_grad():
                outputs = model.generate(
                    **inputs,
                    max_new_tokens=max_tokens,
                    temperature=0.7,
                    do_sample=True,
                    top_p=0.95,
                    pad_token_id=tokenizer.eos_token_id
                )
            
            response = tokenizer.decode(outputs[0], skip_special_tokens=True)
            # Remove the prompt from response
            prompt_text = tokenizer.decode(inputs['input_ids'][0], skip_special_tokens=True)
            generated_text = response[len(prompt_text):].strip()
            
            return generated_text
            
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
        "backend": "transformers",
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
            "backend": "transformers"
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
        
        # Extract user message
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
                    for chunk_text in generate_mistral_response(user_message, max_tokens, stream=True):
                        chunk_data = {
                            "id": f"chatcmpl-{int(time.time()*1000)}",
                            "object": "chat.completion.chunk",
                            "created": int(time.time()),
                            "model": model_name,
                            "choices": [{
                                "index": 0,
                                "delta": {"content": chunk_text},
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
            
            return Response(stream_response(), mimetype='text/event-stream')
        else:
            response_text = generate_mistral_response(user_message, max_tokens, stream=False)
            
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
    logger.info("Starting Mistral Inference Server...")
    load_mistral_model()
    
    if model_loaded:
        logger.info("Model loaded, starting Flask server...")
    else:
        logger.warning("Model failed to load, server starting anyway...")
    
    app.run(host='0.0.0.0', port=8000, threaded=True)
