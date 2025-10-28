"""
Ollama LLM Service Client
Calls Ollama via HTTP API instead of CLI subprocess
"""

import os
import requests
import logging

logger = logging.getLogger(__name__)


class OllamaMistralLLM:
    def __init__(self, model_name="mistral"):
        """
        Initialize Ollama LLM Service client
        
        Args:
            model_name: Name of the model to use (default: "mistral")
        """
        self.model_name = model_name
        # Get Ollama service URL from environment or use default
        self.base_url = os.getenv('OLLAMA_HOST', 'http://ollama-service:11434')
        logger.info(f"Initialized OllamaMistralLLM with model={model_name}, service={self.base_url}")
    
    def generate(self, prompt, max_tokens=512):
        """
        Call Ollama LLM Service using HTTP API
        """
        try:
            # Call Ollama HTTP API
            response = requests.post(
                f"{self.base_url}/api/generate",
                json={
                    "model": self.model_name,
                    "prompt": prompt,
                    "stream": False,
                    "options": {
                        "num_predict": max_tokens
                    }
                },
                timeout=60
            )
            
            # Check response status
            if response.status_code != 200:
                raise RuntimeError(
                    f"Ollama API Error: HTTP {response.status_code} - {response.text}"
                )
            
            # Parse JSON response
            result = response.json()
            generated_text = result.get('response', '').strip()
            
            if not generated_text:
                raise RuntimeError("Ollama returned empty response")
            
            return generated_text
            
        except requests.exceptions.Timeout:
            raise RuntimeError(f"Ollama API timeout after 60s for model {self.model_name}")
        except requests.exceptions.ConnectionError:
            raise RuntimeError(
                f"Cannot connect to Ollama service at {self.base_url}. "
                "Is the ollama-service pod running?"
            )
        except Exception as e:
            raise RuntimeError(f"Ollama Error: {str(e)}")
    
    def test_connection(self):
        """
        Test connection to Ollama service
        
        Returns:
            bool: True if connection is successful, False otherwise
        """
        try:
            response = requests.get(f"{self.base_url}/api/tags", timeout=5)
            if response.status_code == 200:
                models = response.json()
                logger.info(f"✅ Connected to Ollama at {self.base_url}")
                logger.info(f"Available models: {[m['name'] for m in models.get('models', [])]}")
                return True
            else:
                logger.error(f"❌ Connection failed: HTTP {response.status_code}")
                return False
        except Exception as e:
            logger.error(f"❌ Connection test failed: {e}")
            return False


# Instantiate global LLM
llm = OllamaMistralLLM()


# Example usage
if __name__ == "__main__":
    # Configure logging
    logging.basicConfig(level=logging.INFO)
    
    # Test connection
    print("Testing connection to Ollama service...")
    if llm.test_connection():
        print("\n" + "="*60)
        print("Testing LLM generation...")
        print("="*60)
        
        # Test generation
        prompt = "Explain RAN network optimization in one sentence."
        print(f"\nPrompt: {prompt}")
        print(f"\nGenerating response...")
        
        response = llm.generate(prompt)
        print(f"\nResponse:\n{response}")
        print("="*60)
    else:
        print("❌ Connection test failed. Check if ollama-service is running.")
