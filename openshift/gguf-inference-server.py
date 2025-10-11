#!/usr/bin/env python3

import json
import time
import logging
import os
import psutil
from flask import Flask, request, jsonify, Response
from ctransformers import AutoModelForCausalLM

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)

model = None
model_loaded = False
model_name = "mistral-7b-instruct-gguf"
load_time = 0

def log_memory_usage(stage):
    """Log current memory usage"""
    process = psutil.Process(os.getpid())
    mem_info = process.memory_info()
    mem_mb = mem_info.rss / (1024 * 1024)
    logger.info(f"[{stage}] Memory usage: {mem_mb:.2f} MB")

def load_gguf_model():
    """Load Mistral GGUF model using ctransformers with detailed logging"""
    global model, model_loaded, load_time
    
    try:
        model_path = "/pvc/models/mistral.gguf"
        logger.info("=" * 60)
        logger.info("STARTING MODEL INITIALIZATION")
        logger.info("=" * 60)
        
        start_time = time.time()
        
        logger.info(f"Step 1: Checking model file at {model_path}")
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"Model file {model_path} not found")
        
        model_size = os.path.getsize(model_path) / (1024**3)
        logger.info(f"Step 2: Model file found - Size: {model_size:.2f} GB ({os.path.getsize(model_path):,} bytes)")
        
        log_memory_usage("Before model load")
        
        logger.info("Step 3: Initializing ctransformers AutoModelForCausalLM")
        logger.info("  - Model type: Mistral")
        logger.info("  - GPU layers: 0 (CPU only)")
        logger.info("  - CPU threads: 8")
        logger.info("  - Context length: 4096 tokens")
        logger.info("  - Max new tokens: 512")
        
        logger.info("Step 4: Loading GGUF model into memory (this may take 30-60 seconds)...")
        load_start = time.time()
        
        model = AutoModelForCausalLM.from_pretrained(
            model_path,
            model_type="mistral",
            gpu_layers=0,
            threads=8,
            context_length=4096,
            max_new_tokens=512
        )
        
        load_duration = time.time() - load_start
        logger.info(f"Step 5: Model loaded in {load_duration:.2f} seconds")
        
        log_memory_usage("After model load")
        
        logger.info("Step 6: Model initialization complete!")
        logger.info("  - Backend: ctransformers (llama.cpp)")
        logger.info("  - Format: GGUF Q4_K_M quantized")
        logger.info("  - Context window: 4096 tokens")
        logger.info("  - CPU threads: 8")
        logger.info("  - Expected inference speed: ~10-15 tokens/sec on CPU")
        
        load_time = time.time() - start_time
        logger.info(f"Total initialization time: {load_time:.2f} seconds")
        logger.info("=" * 60)
        logger.info("MODEL READY FOR INFERENCE")
        logger.info("=" * 60)
        
        model_loaded = True
        
    except Exception as e:
        logger.error("=" * 60)
        logger.error("MODEL INITIALIZATION FAILED")
        logger.error("=" * 60)
        logger.error(f"Error: {e}")
        import traceback
        logger.error(f"Traceback:\n{traceback.format_exc()}")
        model_loaded = False

def generate_response(message_content, max_tokens=500, stream=False):
    """Generate response using GGUF model with detailed logging"""
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
        
        logger.info("-" * 60)
        logger.info("INFERENCE REQUEST")
        logger.info(f"Query: {message_content[:100]}{'...' if len(message_content) > 100 else ''}")
        logger.info(f"Max tokens: {max_tokens}")
        logger.info(f"Streaming: {stream}")
        logger.info(f"Prompt length: {len(prompt)} characters")
        
        inference_start = time.time()
        
        if stream:
            logger.info("Starting streaming generation...")
            return model(
                prompt,
                max_new_tokens=max_tokens,
                temperature=0.7,
                top_p=0.95,
                stream=True
            )
        else:
            logger.info("Starting non-streaming generation...")
            response = model(
                prompt,
                max_new_tokens=max_tokens,
                temperature=0.7,
                top_p=0.95
            )
            
            inference_time = time.time() - inference_start
            tokens_generated = len(response.split())
            tokens_per_sec = tokens_generated / inference_time if inference_time > 0 else 0
            
            logger.info(f"Generation complete in {inference_time:.2f} seconds")
            logger.info(f"Tokens generated: {tokens_generated}")
            logger.info(f"Speed: {tokens_per_sec:.2f} tokens/sec")
            logger.info(f"Response length: {len(response)} characters")
            logger.info("-" * 60)
            
            return response.strip()
            
    except Exception as e:
        logger.error(f"Error generating response: {e}")
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        return None

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    logger.info("Health check requested")
    return jsonify({
        "status": "healthy" if model_loaded else "loading",
        "model_loaded": model_loaded,
        "model_name": model_name,
        "backend": "ctransformers",
        "format": "GGUF Q4_K_M",
        "device": "CPU",
        "load_time_seconds": round(load_time, 2),
        "timestamp": time.time()
    })

@app.route('/v1/models', methods=['GET'])
def list_models():
    """List available models - OpenAI compatible"""
    logger.info("Model list requested")
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
        
        logger.info(f"Chat completion request - Stream: {stream}, Max tokens: {max_tokens}")
        
        user_message = ""
        for msg in reversed(messages):
            if msg.get('role') == 'user':
                user_message = msg.get('content', '')
                break
        
        if not user_message:
            logger.warning("No user message found in request")
            return jsonify({"error": "No user message found"}), 400
        
        if not model_loaded:
            logger.error("Model not loaded, rejecting request")
            return jsonify({"error": "Model not loaded"}), 503
        
        if stream:
            def stream_response():
                try:
                    token_count = 0
                    stream_start = time.time()
                    response_gen = generate_response(user_message, max_tokens, stream=True)
                    
                    if response_gen:
                        for token in response_gen:
                            token_count += 1
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
                        
                        stream_duration = time.time() - stream_start
                        logger.info(f"Streaming complete: {token_count} tokens in {stream_duration:.2f}s ({token_count/stream_duration:.2f} tok/s)")
                        
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
                logger.error("Failed to generate response")
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
    logger.info("=" * 60)
    logger.info("GGUF INFERENCE SERVER STARTUP")
    logger.info("=" * 60)
    logger.info(f"Python version: {os.sys.version}")
    logger.info(f"PID: {os.getpid()}")
    
    load_gguf_model()
    
    if model_loaded:
        logger.info("Server ready to accept requests on 0.0.0.0:8000")
    else:
        logger.warning("Server starting despite model load failure...")
    
    app.run(host='0.0.0.0', port=8000, threaded=True)
