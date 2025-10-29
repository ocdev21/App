"""
AWS Bedrock Claude 3 Integration Module
Provides streaming and non-streaming chat functionality for SageMaker notebooks
"""

import json
import boto3
from typing import Generator, Dict, Any, Optional
from botocore.exceptions import ClientError


class BedrockClient:
    """Client for interacting with AWS Bedrock Claude 3 models"""
    
    def __init__(self, region_name: str = "us-east-1"):
        """
        Initialize Bedrock client
        
        Args:
            region_name: AWS region (default: us-east-1)
        """
        self.region_name = region_name
        self.model_id = "anthropic.claude-3-sonnet-20240229-v1:0"
        
        # Initialize Bedrock Runtime client
        self.client = boto3.client(
            service_name='bedrock-runtime',
            region_name=region_name
        )
    
    def invoke_streaming(
        self,
        prompt: str,
        max_tokens: int = 4096,
        temperature: float = 0.7,
        top_p: float = 0.9
    ) -> Generator[str, None, None]:
        """
        Invoke Claude 3 with streaming response
        
        Args:
            prompt: User prompt to send to Claude
            max_tokens: Maximum tokens in response
            temperature: Sampling temperature (0-1)
            top_p: Nucleus sampling parameter
            
        Yields:
            Text chunks as they arrive from Claude
            
        Raises:
            ClientError: If AWS API call fails
        """
        # Prepare request payload (Anthropic message format)
        payload = {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": max_tokens,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": prompt
                        }
                    ]
                }
            ],
            "temperature": temperature,
            "top_p": top_p
        }
        
        try:
            # Invoke model with streaming
            response = self.client.invoke_model_with_response_stream(
                modelId=self.model_id,
                contentType="application/json",
                accept="application/json",
                body=json.dumps(payload)
            )
            
            # Process streaming response
            for event in response['body']:
                if 'chunk' in event:
                    chunk_data = json.loads(event['chunk']['bytes'].decode('utf-8'))
                    
                    # Extract text from content_block_delta events
                    if chunk_data.get('type') == 'content_block_delta':
                        delta = chunk_data.get('delta', {})
                        
                        # Handle text_delta type (standard Claude 3 response)
                        if delta.get('type') == 'text_delta' and 'text' in delta:
                            yield delta['text']
                        # Handle direct text field (alternative format)
                        elif 'text' in delta:
                            yield delta['text']
                    
                    # Log completion reason
                    elif chunk_data.get('type') == 'message_delta':
                        delta = chunk_data.get('delta', {})
                        if 'stop_reason' in delta:
                            pass  # Silently complete (don't print to notebook)
        
        except ClientError as e:
            error_code = e.response['Error']['Code']
            
            if error_code == 'AccessDeniedException':
                raise Exception(
                    "AWS credentials don't have permission to access Bedrock. "
                    "Ensure SageMaker execution role has 'bedrock:InvokeModelWithResponseStream' permission."
                )
            elif error_code == 'ResourceNotFoundException':
                raise Exception(
                    f"Claude 3 model not available in {self.region_name}. "
                    "Try us-east-1 or us-west-2."
                )
            elif error_code == 'ThrottlingException':
                raise Exception(
                    "Bedrock rate limit exceeded. Please try again in a moment."
                )
            else:
                raise Exception(f"Bedrock API error: {str(e)}")
    
    def invoke(
        self,
        prompt: str,
        max_tokens: int = 4096,
        temperature: float = 0.7,
        top_p: float = 0.9
    ) -> str:
        """
        Invoke Claude 3 and return complete response
        
        Args:
            prompt: User prompt to send to Claude
            max_tokens: Maximum tokens in response
            temperature: Sampling temperature (0-1)
            top_p: Nucleus sampling parameter
            
        Returns:
            Complete response text from Claude
            
        Raises:
            ClientError: If AWS API call fails
        """
        # Prepare request payload (Anthropic message format)
        payload = {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": max_tokens,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": prompt
                        }
                    ]
                }
            ],
            "temperature": temperature,
            "top_p": top_p
        }
        
        try:
            # Invoke model (non-streaming)
            response = self.client.invoke_model(
                modelId=self.model_id,
                contentType="application/json",
                accept="application/json",
                body=json.dumps(payload)
            )
            
            # Parse response
            response_body = json.loads(response['body'].read().decode('utf-8'))
            
            # Extract text from response
            if 'content' in response_body and len(response_body['content']) > 0:
                return response_body['content'][0]['text']
            else:
                raise Exception("No response content from Claude 3")
        
        except ClientError as e:
            error_code = e.response['Error']['Code']
            
            if error_code == 'AccessDeniedException':
                raise Exception(
                    "AWS credentials don't have permission to access Bedrock. "
                    "Ensure SageMaker execution role has 'bedrock:InvokeModel' permission."
                )
            elif error_code == 'ResourceNotFoundException':
                raise Exception(
                    f"Claude 3 model not available in {self.region_name}. "
                    "Try us-east-1 or us-west-2."
                )
            elif error_code == 'ThrottlingException':
                raise Exception(
                    "Bedrock rate limit exceeded. Please try again in a moment."
                )
            else:
                raise Exception(f"Bedrock API error: {str(e)}")
    
    def test_connection(self) -> Dict[str, Any]:
        """
        Test connection to Bedrock by invoking model with a simple prompt
        
        Returns:
            Dict with status and details
        """
        try:
            response = self.invoke("Say 'Hello from SageMaker!' in one sentence.", max_tokens=100)
            return {
                "status": "success",
                "message": "Successfully connected to Bedrock",
                "response": response,
                "region": self.region_name,
                "model_id": self.model_id
            }
        except Exception as e:
            return {
                "status": "error",
                "message": str(e),
                "region": self.region_name,
                "model_id": self.model_id
            }


# Example usage
if __name__ == "__main__":
    # Initialize client
    bedrock = BedrockClient(region_name="us-east-1")
    
    # Test connection
    print("Testing Bedrock connection...")
    result = bedrock.test_connection()
    print(f"Status: {result['status']}")
    print(f"Message: {result['message']}")
    
    if result['status'] == 'success':
        print(f"Response: {result['response']}")
        
        # Test streaming
        print("\nTesting streaming response...")
        prompt = "Explain quantum computing in 2 sentences."
        print(f"Prompt: {prompt}")
        print("Response: ", end="", flush=True)
        
        for chunk in bedrock.invoke_streaming(prompt, max_tokens=200):
            print(chunk, end="", flush=True)
        print("\n")
