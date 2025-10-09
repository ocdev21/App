#!/usr/bin/env python3

import os
import json
import requests
import asyncio
import aiohttp
from datetime import datetime

class RemoteTSLAMClient:
    def __init__(self, remote_host="tslam-vllm-service.l1-app-ai.svc.cluster.local", remote_port=8000):
        self.remote_host = remote_host
        self.remote_port = remote_port
        self.base_url = f"http://{remote_host}:{remote_port}"
        self.inference_endpoint = f"{self.base_url}/v1/chat/completions"
        
    async def stream_analysis(self, prompt, websocket):
        """Stream analysis from vLLM TSLAM server using OpenAI API format"""
        try:
            # Enhanced system prompt for network troubleshooting
            system_prompt = """You are a specialized 5G L1 network troubleshooting AI expert with deep knowledge of 5G RAN fronthaul, UE procedures, MAC layer operations, and L1 protocols.

Your responses must be:
- Technically accurate and actionable
- Structured with clear priority levels (Critical, Important, Optional)
- Include specific commands, tools, and configuration changes
- Focus on root cause analysis and prevention"""
            
            payload = {
                "model": "tslam-4b",
                "messages": [
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": prompt}
                ],
                "stream": True,
                "max_tokens": 800,
                "temperature": 0.2,
                "top_p": 0.9,
                "presence_penalty": 0.1
            }
            
            # Send streaming request to vLLM
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    self.inference_endpoint,
                    json=payload,
                    headers={"Content-Type": "application/json"}
                ) as response:
                    
                    if response.status != 200:
                        error_msg = f"vLLM server error: {response.status}"
                        await websocket.send(json.dumps({
                            "type": "error",
                            "content": error_msg,
                            "timestamp": datetime.now().isoformat()
                        }))
                        return
                    
                    # Stream response chunks
                    async for line in response.content:
                        line_text = line.decode('utf-8').strip()
                        
                        if line_text.startswith('data: '):
                            data_text = line_text[6:]  # Remove 'data: ' prefix
                            
                            if data_text == '[DONE]':
                                await websocket.send(json.dumps({
                                    "type": "recommendation_complete",
                                    "timestamp": datetime.now().isoformat()
                                }))
                                break
                            
                            try:
                                chunk_data = json.loads(data_text)
                                delta = chunk_data.get('choices', [{}])[0].get('delta', {})
                                content = delta.get('content', '')
                                
                                if content:
                                    await websocket.send(json.dumps({
                                        "type": "recommendation_chunk",
                                        "content": content,
                                        "timestamp": datetime.now().isoformat()
                                    }))
                            except json.JSONDecodeError:
                                # Skip invalid JSON chunks
                                continue
                                
        except Exception as e:
            error_response = {
                "type": "error",
                "content": f"vLLM TSLAM connection failed: {str(e)}",
                "timestamp": datetime.now().isoformat()
            }
            await websocket.send(json.dumps(error_response))
    
    def health_check(self):
        """Check if vLLM TSLAM server is available"""
        try:
            response = requests.get(f"{self.base_url}/health", timeout=5)
            return response.status_code == 200
        except:
            return False
    
    def get_model_info(self):
        """Get available models from vLLM server"""
        try:
            response = requests.get(f"{self.base_url}/v1/models", timeout=5)
            if response.status_code == 200:
                return response.json()
            return None
        except:
            return None

# Test function for the new vLLM client
async def test_vllm_connection():
    """Test vLLM TSLAM connection"""
    client = RemoteTSLAMClient()
    
    print(f"Testing vLLM TSLAM connection to {client.base_url}")
    print(f"Health check: {'✓' if client.health_check() else '✗'}")
    
    model_info = client.get_model_info()
    if model_info:
        print(f"Available models: {[m['id'] for m in model_info.get('data', [])]}")
    else:
        print("Could not retrieve model information")

if __name__ == "__main__":
    asyncio.run(test_vllm_connection())