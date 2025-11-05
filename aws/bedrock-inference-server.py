#!/usr/bin/env python3
"""
Amazon Bedrock Inference Server for L1 Troubleshooting System
Uses Amazon Nova Pro model for network anomaly analysis and recommendations
Compatible with existing API endpoints - drop-in replacement for GGUF server
"""

import json
import time
import logging
import os
from flask import Flask, request, jsonify, Response
import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Bedrock configuration
bedrock_runtime = None
model_ready = False
model_id = "amazon.nova-pro-v1:0"  # Amazon Nova Pro - optimized for telecom
aws_region = os.getenv('AWS_REGION', 'us-east-1')

# Model configuration
MAX_TOKENS = 800
TEMPERATURE = 0.2
TOP_P = 0.9

def initialize_bedrock_client():
    """Initialize Amazon Bedrock Runtime client"""
    global bedrock_runtime, model_ready
    
    try:
        logger.info("=" * 60)
        logger.info("INITIALIZING AMAZON BEDROCK CLIENT")
        logger.info("=" * 60)
        
        logger.info(f"Step 1: Configuring Bedrock client for region: {aws_region}")
        logger.info(f"Step 2: Model ID: {model_id}")
        
        # Configure boto3 client with retry logic
        config = Config(
            region_name=aws_region,
            retries={
                'max_attempts': 3,
                'mode': 'adaptive'
            },
            connect_timeout=10,
            read_timeout=60
        )
        
        logger.info("Step 3: Creating Bedrock Runtime client...")
        bedrock_runtime = boto3.client(
            service_name='bedrock-runtime',
            config=config
        )
        
        # Test connection by listing available models (optional verification)
        logger.info("Step 4: Verifying Bedrock access...")
        try:
            # Simple test to verify credentials and permissions
            # Note: This requires bedrock:ListFoundationModels permission (optional)
            bedrock_client = boto3.client('bedrock', config=config)
            response = bedrock_client.list_foundation_models(
                byProvider='Amazon'
            )
            logger.info(f"Step 5: Successfully connected to Bedrock. Found {len(response.get('modelSummaries', []))} Amazon models")
        except Exception as e:
            logger.info(f"Step 5: Skipping model list verification: {str(e)[:100]}")
            logger.info("  This is normal - bedrock:InvokeModel permission is sufficient")
        
        model_ready = True
        logger.info("Step 6: Bedrock client initialized successfully!")
        logger.info(f"  Model: {model_id}")
        logger.info(f"  Region: {aws_region}")
        logger.info(f"  Max Tokens: {MAX_TOKENS}")
        logger.info(f"  Temperature: {TEMPERATURE}")
        logger.info("=" * 60)
        
    except Exception as e:
        logger.error(f"Failed to initialize Bedrock client: {e}")
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        logger.error("Please ensure:")
        logger.error("  1. AWS credentials are properly configured (IAM role or env vars)")
        logger.error("  2. Bedrock model access is enabled in AWS Console")
        logger.error("  3. IAM role has bedrock:InvokeModel permission")
        model_ready = False

def generate_bedrock_response(prompt, max_tokens=None, temperature=None, stream=False):
    """Generate response using Amazon Bedrock Nova Pro model"""
    global bedrock_runtime, model_ready
    
    if not model_ready or bedrock_runtime is None:
        logger.error("Bedrock client not initialized")
        raise RuntimeError("Bedrock client not ready")
    
    try:
        # Prepare request body for Nova Pro
        request_body = {
            "messages": [
                {
                    "role": "user",
                    "content": [{"text": prompt}]
                }
            ],
            "inferenceConfig": {
                "max_new_tokens": max_tokens or MAX_TOKENS,
                "temperature": temperature or TEMPERATURE,
                "top_p": TOP_P
            }
        }
        
        logger.info(f"Invoking Bedrock model: {model_id}")
        logger.info(f"Prompt length: {len(prompt)} characters")
        
        if stream:
            # Streaming response
            response = bedrock_runtime.invoke_model_with_response_stream(
                modelId=model_id,
                contentType="application/json",
                accept="application/json",
                body=json.dumps(request_body)
            )
            
            # Process stream
            stream_obj = response.get('body')
            if stream_obj:
                for event in stream_obj:
                    chunk = event.get('chunk')
                    if chunk:
                        chunk_data = json.loads(chunk.get('bytes').decode())
                        
                        # Extract text from Nova response format
                        if 'contentBlockDelta' in chunk_data:
                            delta = chunk_data['contentBlockDelta'].get('delta', {})
                            if 'text' in delta:
                                yield delta['text']
                        
                        # Handle completion
                        if chunk_data.get('stopReason'):
                            logger.info(f"Stream completed. Stop reason: {chunk_data['stopReason']}")
                            break
        else:
            # Non-streaming response
            response = bedrock_runtime.invoke_model(
                modelId=model_id,
                contentType="application/json",
                accept="application/json",
                body=json.dumps(request_body)
            )
            
            response_body = json.loads(response['body'].read())
            
            # Extract text from Nova response format
            if 'output' in response_body and 'message' in response_body['output']:
                message = response_body['output']['message']
                if 'content' in message and len(message['content']) > 0:
                    text = message['content'][0].get('text', '')
                    logger.info(f"Generated response: {len(text)} characters")
                    return text
            
            logger.warning("Unexpected response format from Bedrock")
            return ""
            
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        logger.error(f"Bedrock API error [{error_code}]: {error_message}")
        
        if error_code == 'AccessDeniedException':
            logger.error("Access denied. Check IAM permissions for bedrock:InvokeModel")
        elif error_code == 'ResourceNotFoundException':
            logger.error(f"Model not found: {model_id}. Ensure model access is enabled in Bedrock console")
        elif error_code == 'ThrottlingException':
            logger.error("Rate limit exceeded. Consider using exponential backoff")
        
        raise
    except Exception as e:
        logger.error(f"Error generating Bedrock response: {e}")
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        raise

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    status = {
        "status": "healthy" if model_ready else "unhealthy",
        "service": "bedrock-inference-server",
        "model": model_id,
        "region": aws_region,
        "ready": model_ready
    }
    status_code = 200 if model_ready else 503
    return jsonify(status), status_code

@app.route('/v1/models', methods=['GET'])
def list_models():
    """List available models (OpenAI API compatibility)"""
    return jsonify({
        "object": "list",
        "data": [
            {
                "id": model_id,
                "object": "model",
                "created": int(time.time()),
                "owned_by": "amazon",
                "permission": [],
                "root": model_id,
                "parent": None
            }
        ]
    })

@app.route('/v1/chat/completions', methods=['POST'])
def chat_completions():
    """
    OpenAI-compatible chat completions endpoint
    Supports both streaming and non-streaming responses
    """
    try:
        if not model_ready:
            return jsonify({
                "error": {
                    "message": "Bedrock client not ready",
                    "type": "server_error",
                    "code": "service_unavailable"
                }
            }), 503
        
        data = request.get_json()
        
        # Extract parameters
        messages = data.get('messages', [])
        stream = data.get('stream', False)
        max_tokens = data.get('max_tokens', MAX_TOKENS)
        temperature = data.get('temperature', TEMPERATURE)
        
        # Build prompt from messages
        prompt = ""
        for msg in messages:
            role = msg.get('role', 'user')
            content = msg.get('content', '')
            if role == 'system':
                prompt += f"System: {content}\n\n"
            elif role == 'user':
                prompt += f"{content}\n"
            elif role == 'assistant':
                prompt += f"Assistant: {content}\n"
        
        logger.info(f"Received chat completion request (stream={stream})")
        
        if stream:
            # Streaming response (SSE format)
            def generate_stream():
                try:
                    for text_chunk in generate_bedrock_response(prompt, max_tokens, temperature, stream=True):
                        chunk_data = {
                            "id": f"chatcmpl-{int(time.time())}",
                            "object": "chat.completion.chunk",
                            "created": int(time.time()),
                            "model": model_id,
                            "choices": [{
                                "index": 0,
                                "delta": {"content": text_chunk},
                                "finish_reason": None
                            }]
                        }
                        yield f"data: {json.dumps(chunk_data)}\n\n"
                    
                    # Send completion marker
                    final_chunk = {
                        "id": f"chatcmpl-{int(time.time())}",
                        "object": "chat.completion.chunk",
                        "created": int(time.time()),
                        "model": model_id,
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
                            "type": "server_error"
                        }
                    }
                    yield f"data: {json.dumps(error_chunk)}\n\n"
            
            return Response(generate_stream(), mimetype='text/event-stream')
        
        else:
            # Non-streaming response
            response_text = generate_bedrock_response(prompt, max_tokens, temperature, stream=False)
            
            return jsonify({
                "id": f"chatcmpl-{int(time.time())}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": model_id,
                "choices": [{
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": response_text
                    },
                    "finish_reason": "stop"
                }],
                "usage": {
                    "prompt_tokens": len(prompt.split()),
                    "completion_tokens": len(response_text.split()),
                    "total_tokens": len(prompt.split()) + len(response_text.split())
                }
            })
            
    except Exception as e:
        logger.error(f"Chat completion error: {e}")
        return jsonify({
            "error": {
                "message": str(e),
                "type": "server_error",
                "code": "internal_error"
            }
        }), 500

if __name__ == '__main__':
    logger.info("=" * 60)
    logger.info("AMAZON BEDROCK INFERENCE SERVER")
    logger.info("L1 Network Troubleshooting System")
    logger.info("=" * 60)
    logger.info(f"Model: {model_id}")
    logger.info(f"Region: {aws_region}")
    logger.info("=" * 60)
    
    # Initialize Bedrock client
    initialize_bedrock_client()
    
    if model_ready:
        logger.info("✓ Server ready to accept requests on 0.0.0.0:8000")
    else:
        logger.warning("⚠ Server starting despite initialization issues...")
        logger.warning("  API calls will fail until Bedrock access is configured")
    
    logger.info("=" * 60)
    app.run(host='0.0.0.0', port=8000, threaded=True)
