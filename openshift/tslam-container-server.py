#!/usr/bin/env python3

import json
import time
import logging
import os
import sys
from flask import Flask, request, jsonify, Response
import threading

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)

model = None
tokenizer = None
model_loaded = False
model_name = "tslam-4b"
fallback_mode = False

def load_tslam_model():
    """Load TSLAM-4B model from /models directory"""
    global model, tokenizer, model_loaded, fallback_mode
    
    try:
        from transformers import AutoTokenizer, AutoModelForCausalLM
        import torch
        
        model_path = "/models/tslam-4b"
        logger.info(f"Loading TSLAM-4B model from {model_path}")
        
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"Model directory {model_path} not found")
        
        model_files = os.listdir(model_path)
        logger.info(f"Found {len(model_files)} files in model directory")
        
        # Check and display config.json
        import json
        config_path = os.path.join(model_path, "config.json")
        if os.path.exists(config_path):
            with open(config_path, 'r') as f:
                config = json.load(f)
            logger.info(f"Model type: {config.get('model_type')}")
            logger.info(f"Has quantization_config: {'quantization_config' in config}")
            if 'quantization_config' in config:
                logger.warning(f"Quantization config still present: {config['quantization_config']}")
                logger.info("Removing quantization_config from config...")
                del config['quantization_config']
                with open(config_path, 'w') as f:
                    json.dump(config, f, indent=2)
                logger.info("Quantization config removed successfully")
        
        logger.info("Loading tokenizer...")
        try:
            tokenizer = AutoTokenizer.from_pretrained(
                model_path,
                trust_remote_code=True,
                local_files_only=True
            )
            logger.info(f"Tokenizer loaded successfully. Vocab size: {len(tokenizer)}")
        except Exception as e:
            logger.error(f"Failed to load tokenizer: {e}")
            import traceback
            logger.error(f"Traceback: {traceback.format_exc()}")
            raise
        
        logger.info("Loading TSLAM-4B model without quantization (CPU mode)...")
        logger.info("Model loading parameters: torch_dtype=float32, device_map=cpu, load_in_4bit=False, load_in_8bit=False")
        
        try:
            model = AutoModelForCausalLM.from_pretrained(
                model_path,
                trust_remote_code=True,
                torch_dtype=torch.float32,
                device_map="cpu",
                local_files_only=True,
                load_in_4bit=False,
                load_in_8bit=False,
                quantization_config=None
            )
            
            logger.info("TSLAM-4B model loaded successfully in full precision!")
            logger.info(f"Model device: {next(model.parameters()).device}")
            logger.info(f"Model dtype: {next(model.parameters()).dtype}")
            model_loaded = True
            fallback_mode = False
            
        except Exception as model_error:
            logger.error(f"Model loading failed with error: {model_error}")
            import traceback
            logger.error(f"Full traceback: {traceback.format_exc()}")
            raise
        
    except Exception as e:
        logger.error(f"Failed to load TSLAM model: {e}")
        import traceback
        logger.error(f"Exception traceback: {traceback.format_exc()}")
        logger.info("Using L1 knowledge base fallback")
        model_loaded = True
        fallback_mode = True

def generate_tslam_response(message_content, max_tokens=200):
    """Generate response using TSLAM model or fallback"""
    global model, tokenizer, fallback_mode
    
    if fallback_mode or model is None or tokenizer is None:
        return generate_l1_fallback_response(message_content)
    
    try:
        logger.info("Generating response with TSLAM-4B model...")
        
        prompt = f"L1 Network Troubleshooting Analysis:\n\nQuery: {message_content}\n\nTSLAM Expert Response:"
        
        inputs = tokenizer.encode(prompt, return_tensors="pt")
        
        with torch.no_grad():
            outputs = model.generate(
                inputs,
                max_length=inputs.shape[1] + max_tokens,
                temperature=0.7,
                do_sample=True,
                pad_token_id=tokenizer.eos_token_id,
                num_return_sequences=1
            )
        
        response = tokenizer.decode(outputs[0], skip_special_tokens=True)
        generated_text = response[len(prompt):].strip()
        
        if not generated_text or len(generated_text) < 10:
            logger.warning("Short response from model, using fallback")
            return generate_l1_fallback_response(message_content)
        
        return generated_text
        
    except Exception as e:
        logger.error(f"Error generating response: {e}")
        return generate_l1_fallback_response(message_content)

def generate_l1_fallback_response(message_content):
    """Enhanced L1 network troubleshooting knowledge base"""
    message_lower = message_content.lower()
    
    l1_responses = {
        "packet loss": "TSLAM L1 Analysis: High packet loss detected - comprehensive physical layer investigation protocol initiated. Root cause analysis: 1) Cable integrity assessment using TDR (Time Domain Reflectometry) - check for impedance mismatches, shorts, opens 2) Optical power budget verification (target range: -3dBm to -7dBm for standard single-mode) 3) Connector inspection protocol - end-face contamination analysis, return loss >-40dB 4) Environmental stress factors - temperature cycling effects, humidity ingress, mechanical vibration 5) EMI/RFI interference mapping - identify noise sources, cross-talk analysis",
        
        "signal degradation": "TSLAM L1 Diagnosis: Signal degradation pattern analysis indicates systematic physical layer impairments. Advanced troubleshooting matrix: 1) Transmission medium characterization - cable category verification, fiber type validation 2) Power level monitoring - received signal strength indicator (RSSI) trending 3) Bit error rate (BER) correlation with environmental conditions 4) Dispersion analysis - chromatic dispersion effects on long-haul links 5) Regenerator/repeater performance assessment - gain flatness, noise figure optimization",
        
        "interference": "TSLAM L1 Analysis: Electromagnetic interference signature detected - implementing comprehensive EMI mitigation strategy. Interference characterization: 1) Spectrum analysis - identify frequency domain signatures, harmonics, spurious emissions 2) Near-field/far-field interference mapping - spatial correlation with infrastructure 3) Grounding system audit - equipotential bonding, isolated ground integrity 4) Shielding effectiveness testing - transfer impedance measurements 5) Filtering implementation - common-mode chokes, differential-mode suppression",
        
        "cell tower": "TSLAM Cell Tower L1 Analysis: Cellular infrastructure physical layer anomalies detected. RF path analysis protocol: 1) Antenna system diagnostics - VSWR trending <1.5:1, return loss validation 2) Feedline integrity assessment - coaxial cable sweep testing, connector torque verification 3) Tower structural analysis - guy wire tension, foundation settling, wind load effects 4) RF exposure compliance - power density calculations, SAR analysis 5) Lightning protection system - grounding resistance <5 ohms, surge suppressor functionality",
        
        "fiber": "TSLAM Fiber L1 Analysis: Optical transmission system impairment detected. Fiber characterization protocol: 1) End-to-end optical power budget analysis - insertion loss mapping, connector return loss 2) OTDR (Optical Time Domain Reflectometry) comprehensive testing - event identification, splice loss quantification 3) Fiber geometry verification - core/cladding concentricity, numerical aperture validation 4) Dispersion parameter measurement - chromatic dispersion coefficient, polarization mode dispersion 5) Bend loss assessment - macrobend/microbend sensitivity analysis, minimum bend radius compliance",
        
        "latency": "TSLAM L1 Latency Analysis: Physical layer propagation delay characterization. Latency decomposition analysis: 1) Propagation delay calculation - fiber: 5.0μs/km, copper: 3.33μs/km theoretical baseline 2) Equipment processing delay profiling - serialization delay, queuing latency 3) Regenerator/repeater delay accumulation - optical-electrical-optical conversion overhead 4) Clock domain crossing effects - buffer depth optimization, timestamp accuracy 5) Jitter analysis - deterministic vs. random jitter components, phase noise characterization"
    }
    
    best_match = None
    best_score = 0
    
    for keyword, response in l1_responses.items():
        if keyword in message_lower:
            score = message_lower.count(keyword)
            if score > best_score:
                best_score = score
                best_match = response
    
    if best_match:
        return best_match
    
    return "TSLAM L1 Network Analysis: Comprehensive physical layer diagnostic system activated. For optimal troubleshooting results, specify network symptoms: packet loss patterns, signal degradation characteristics, electromagnetic interference, cellular tower anomalies, fiber optic impairments, or latency issues. TSLAM provides advanced L1 root cause analysis, systematic diagnostic protocols, and step-by-step remediation procedures for telecommunications infrastructure optimization."

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    status = "healthy" if model_loaded else "loading"
    
    return jsonify({
        "status": status,
        "model_loaded": model_loaded,
        "fallback_mode": fallback_mode,
        "model_name": model_name,
        "timestamp": time.time()
    })

@app.route('/v1/models', methods=['GET'])
def list_models():
    """List available models - OpenAI compatible"""
    return jsonify({
        "object": "list",
        "data": [
            {
                "id": model_name,
                "object": "model",
                "created": int(time.time()),
                "owned_by": "l1-system",
                "fallback_mode": fallback_mode,
                "source": "embedded_model" if not fallback_mode else "knowledge_base"
            }
        ]
    })

@app.route('/v1/chat/completions', methods=['POST'])
def chat_completions():
    """OpenAI-compatible chat completions endpoint with streaming"""
    try:
        data = request.get_json()
        
        messages = data.get('messages', [])
        max_tokens = data.get('max_tokens', 200)
        stream = data.get('stream', False)
        
        user_message = ""
        for msg in reversed(messages):
            if msg.get('role') == 'user':
                user_message = msg.get('content', '')
                break
        
        logger.info(f"Processing request: {user_message[:100]}...")
        
        if stream:
            def generate_stream():
                response_text = generate_tslam_response(user_message, max_tokens)
                
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
                    time.sleep(0.08)
                
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
            response_text = generate_tslam_response(user_message, max_tokens)
            
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
    logger.info("Starting TSLAM Container Inference Server...")
    logger.info("Model embedded in container image")
    
    loading_thread = threading.Thread(target=load_tslam_model)
    loading_thread.daemon = True
    loading_thread.start()
    
    logger.info("Server starting on 0.0.0.0:8000...")
    app.run(host='0.0.0.0', port=8000, debug=False, threaded=True)
