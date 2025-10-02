#!/usr/bin/env python3

import json
import time
import logging
import os
from flask import Flask, request, jsonify, Response
from transformers import AutoTokenizer, AutoModelForCausalLM, BitsAndBytesConfig
import torch

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)

model = None
tokenizer = None
model_loaded = False
model_name = "llama-3.1-8b-instruct"

def load_llama_model():
    """Load Llama 3.1 8B model with 4-bit quantization for CPU"""
    global model, tokenizer, model_loaded
    
    try:
        model_path = "/models/llama-3.1-8b"
        logger.info(f"Loading Llama 3.1 8B model from {model_path}")
        
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"Model directory {model_path} not found")
        
        required_files = ['config.json', 'tokenizer.json', 'tokenizer_config.json']
        for file in required_files:
            if not os.path.exists(os.path.join(model_path, file)):
                logger.warning(f"Missing {file} in model directory")
        
        logger.info("Loading tokenizer...")
        tokenizer = AutoTokenizer.from_pretrained(
            model_path,
            local_files_only=True,
            trust_remote_code=True
        )
        
        logger.info("Loading model with 4-bit quantization on CPU...")
        
        quantization_config = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_compute_dtype=torch.float32,
            bnb_4bit_use_double_quant=True,
            bnb_4bit_quant_type="nf4"
        )
        
        model = AutoModelForCausalLM.from_pretrained(
            model_path,
            quantization_config=quantization_config,
            device_map="cpu",
            low_cpu_mem_usage=True,
            local_files_only=True,
            trust_remote_code=True
        )
        
        logger.info("Llama 3.1 8B model loaded successfully with 4-bit quantization!")
        logger.info(f"Model device: {next(model.parameters()).device}")
        logger.info(f"Model dtype: {next(model.parameters()).dtype}")
        model_loaded = True
        
    except Exception as e:
        logger.error(f"Failed to load Llama model: {e}")
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        model_loaded = False

def generate_llama_response(message_content, max_tokens=500, stream=False):
    """Generate response using Llama 3.1 8B model"""
    global model, tokenizer
    
    if not model_loaded or model is None or tokenizer is None:
        logger.error("Model not loaded, cannot generate response")
        return None
    
    try:
        system_prompt = """You are an expert L1 Network Troubleshooting AI assistant specializing in telecommunications infrastructure. 
Analyze network anomalies at the physical layer and provide specific, actionable technical recommendations."""
        
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": message_content}
        ]
        
        prompt = tokenizer.apply_chat_template(
            messages,
            tokenize=False,
            add_generation_prompt=True
        )
        
        logger.info(f"Generating response for query: {message_content[:100]}...")
        
        inputs = tokenizer(prompt, return_tensors="pt", return_attention_mask=True)
        
        with torch.no_grad():
            outputs = model.generate(
                **inputs,
                max_new_tokens=max_tokens,
                temperature=0.7,
                do_sample=True,
                top_p=0.95,
                pad_token_id=tokenizer.eos_token_id,
                eos_token_id=tokenizer.eos_token_id
            )
        
        response = tokenizer.decode(outputs[0], skip_special_tokens=True)
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
        "backend": "transformers-4bit",
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
            "backend": "transformers-4bit"
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
                response_text = generate_llama_response(user_message, max_tokens, stream=True)
                if response_text:
                    words = response_text.split()
                    for i, word in enumerate(words):
                        chunk_data = {
                            "id": f"chatcmpl-{int(time.time()*1000)}",
                            "object": "chat.completion.chunk",
                            "created": int(time.time()),
                            "model": model_name,
                            "choices": [{
                                "index": 0,
                                "delta": {"content": word + " "},
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
            
            return Response(stream_response(), mimetype='text/event-stream')
        else:
            response_text = generate_llama_response(user_message, max_tokens)
            
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
    logger.info("Starting Llama 3.1 8B Inference Server...")
    load_llama_model()
    
    if model_loaded:
        logger.info("Model loaded successfully, starting Flask server on port 8000...")
    else:
        logger.warning("Model failed to load, server starting anyway...")
    
    app.run(host='0.0.0.0', port=8000, threaded=True)
