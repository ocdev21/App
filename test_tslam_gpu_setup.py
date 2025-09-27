#!/usr/bin/env python3

"""
Test script for TSLAM GPU inference setup
Validates the complete pipeline from L1 app to GPU nodes
"""

import asyncio
import json
import requests
import sys
from datetime import datetime

async def test_complete_pipeline():
    """Test the complete TSLAM GPU pipeline"""
    
    print("TSLAM GPU Setup Validation Test")
    print("=" * 50)
    
    # Test configurations
    configs = {
        "vllm_service": "http://tslam-vllm-service.l1-app-ai.svc.cluster.local:8000",
        "l1_app": "http://l1-troubleshooting-ai-service.l1-app-ai.svc.cluster.local",
        "namespace": "l1-app-ai"
    }
    
    print(f"Testing at: {datetime.now().isoformat()}")
    print(f"Target namespace: {configs['namespace']}")
    print()
    
    # Test 1: vLLM Service Health
    print("Test 1: vLLM Service Health Check")
    print("-" * 30)
    try:
        response = requests.get(f"{configs['vllm_service']}/health", timeout=10)
        if response.status_code == 200:
            print("✓ vLLM service is healthy")
        else:
            print(f"✗ vLLM service error: {response.status_code}")
    except Exception as e:
        print(f"✗ vLLM service connection failed: {e}")
    
    print()
    
    # Test 2: Model Availability
    print("Test 2: TSLAM Model Availability")
    print("-" * 30)
    try:
        response = requests.get(f"{configs['vllm_service']}/v1/models", timeout=10)
        if response.status_code == 200:
            models = response.json()
            model_names = [m['id'] for m in models.get('data', [])]
            if 'tslam-4b' in model_names:
                print("✓ TSLAM-4B model is available")
                print(f"  Available models: {model_names}")
            else:
                print(f"✗ TSLAM-4B model not found. Available: {model_names}")
        else:
            print(f"✗ Models endpoint error: {response.status_code}")
    except Exception as e:
        print(f"✗ Models endpoint connection failed: {e}")
    
    print()
    
    # Test 3: Inference Test
    print("Test 3: TSLAM Inference Test")
    print("-" * 30)
    try:
        test_payload = {
            "model": "tslam-4b",
            "messages": [
                {"role": "system", "content": "You are TSLAM-4B, a network troubleshooting AI."},
                {"role": "user", "content": "Analyze: DU-RU latency timeout detected"}
            ],
            "max_tokens": 50,
            "temperature": 0.1
        }
        
        response = requests.post(
            f"{configs['vllm_service']}/v1/chat/completions",
            json=test_payload,
            timeout=30
        )
        
        if response.status_code == 200:
            result = response.json()
            content = result['choices'][0]['message']['content']
            print("✓ TSLAM inference successful")
            print(f"  Response preview: {content[:100]}...")
        else:
            print(f"✗ Inference failed: {response.status_code}")
            print(f"  Error: {response.text[:200]}")
    except Exception as e:
        print(f"✗ Inference test failed: {e}")
    
    print()
    
    # Test 4: L1 App Health
    print("Test 4: L1 Application Health")
    print("-" * 30)
    try:
        response = requests.get(f"{configs['l1_app']}/health", timeout=10)
        if response.status_code == 200:
            print("✓ L1 application is healthy")
        else:
            print(f"✗ L1 app error: {response.status_code}")
    except Exception as e:
        print(f"✗ L1 app connection failed: {e}")
    
    print()
    print("=" * 50)
    print("Test Summary:")
    print("- Deploy your TSLAM model to PVC")
    print("- Run the vLLM GPU deployment")
    print("- Test WebSocket streaming from L1 dashboard")
    print("- All components should show ✓ for full functionality")
    print()
    print("Next steps:")
    print("1. Run: ./openshift/deploy-tslam-gpu.sh")
    print("2. Upload your TSLAM model files")
    print("3. Access your L1 dashboard for real AI-powered troubleshooting!")

if __name__ == "__main__":
    asyncio.run(test_complete_pipeline())