import {
  BedrockRuntimeClient,
  InvokeModelCommand,
  InvokeModelWithResponseStreamCommand,
} from "@aws-sdk/client-bedrock-runtime";

// Initialize Bedrock client
const getBedrockClient = () => {
  const region = process.env.AWS_REGION;
  
  if (!region) {
    throw new Error("AWS_REGION environment variable is not set");
  }

  // On ECS, don't specify credentials - let AWS SDK use the task role automatically
  // For local development, provide credentials via env vars
  const config: any = { region };
  
  if (process.env.AWS_ACCESS_KEY_ID && process.env.AWS_SECRET_ACCESS_KEY) {
    config.credentials = {
      accessKeyId: process.env.AWS_ACCESS_KEY_ID,
      secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
    };
  }

  return new BedrockRuntimeClient(config);
};

export interface BedrockResponse {
  completion: string;
  stop_reason: string;
}

/**
 * Invoke GPT-OSS-120B via AWS Bedrock with true streaming
 * @param prompt - User prompt to send to GPT-OSS-120B
 * @param onChunk - Callback for each streamed chunk from Bedrock
 * @returns Complete GPT-OSS-120B response
 */
export async function invokeClaude3Streaming(
  prompt: string,
  onChunk: (chunk: string) => void
): Promise<string> {
  try {
    const client = getBedrockClient();
    
    // OpenAI GPT-OSS-120B model ID
    const modelId = "openai.gpt-oss-120b-1:0";
    
    // Prepare the request payload for GPT-OSS-120B (OpenAI format)
    const payload = {
      messages: [
        {
          role: "system",
          content: "You are a helpful AI assistant."
        },
        {
          role: "user",
          content: prompt,
        },
      ],
      max_tokens: 4096,
      temperature: 0.7,
      stream: true,
    };

    const command = new InvokeModelWithResponseStreamCommand({
      modelId,
      contentType: "application/json",
      accept: "application/json",
      body: JSON.stringify(payload),
    });

    const response = await client.send(command);
    
    let fullText = "";
    
    // Process the streaming response (OpenAI format)
    if (response.body) {
      for await (const event of response.body) {
        if (event.chunk?.bytes) {
          const chunkData = JSON.parse(new TextDecoder().decode(event.chunk.bytes));
          
          // Handle OpenAI streaming format
          if (chunkData.choices && chunkData.choices.length > 0) {
            const delta = chunkData.choices[0].delta;
            if (delta?.content) {
              const text = delta.content;
              fullText += text;
              onChunk(text);
            }
          }
        }
      }
    }
    
    if (!fullText) {
      throw new Error("No response content from GPT-OSS-120B");
    }
    
    return fullText;
  } catch (error) {
    console.error("Bedrock GPT-OSS-120B streaming error:", error);
    
    if (error instanceof Error) {
      // Provide more helpful error messages
      if (error.message.includes("AccessDeniedException")) {
        throw new Error("AWS credentials don't have permission to access Bedrock. Ensure IAM role 'superapp-bedrock-access' has proper permissions.");
      } else if (error.message.includes("ResourceNotFoundException")) {
        throw new Error("GPT-OSS-120B model not available in this region. Try us-west-2.");
      } else if (error.message.includes("ThrottlingException")) {
        throw new Error("Bedrock rate limit exceeded. Please try again in a moment.");
      }
      throw error;
    }
    
    throw new Error("Failed to invoke GPT-OSS-120B");
  }
}

/**
 * Invoke GPT-OSS-120B via AWS Bedrock (non-streaming)
 * @param prompt - User prompt to send to GPT-OSS-120B
 * @returns GPT-OSS-120B response
 */
export async function invokeClaude3(prompt: string): Promise<string> {
  try {
    const client = getBedrockClient();
    
    // OpenAI GPT-OSS-120B model ID
    const modelId = "openai.gpt-oss-120b-1:0";
    
    // Prepare the request payload for GPT-OSS-120B (OpenAI format)
    const payload = {
      messages: [
        {
          role: "system",
          content: "You are a helpful AI assistant."
        },
        {
          role: "user",
          content: prompt,
        },
      ],
      max_tokens: 4096,
      temperature: 0.7,
    };

    const command = new InvokeModelCommand({
      modelId,
      contentType: "application/json",
      accept: "application/json",
      body: JSON.stringify(payload),
    });

    const response = await client.send(command);
    
    // Parse the response (OpenAI format)
    const responseBody = JSON.parse(new TextDecoder().decode(response.body));
    
    // Extract the text from GPT-OSS-120B response
    if (responseBody.choices && responseBody.choices.length > 0) {
      return responseBody.choices[0].message.content;
    }
    
    throw new Error("No response content from GPT-OSS-120B");
  } catch (error) {
    console.error("Bedrock GPT-OSS-120B invocation error:", error);
    
    if (error instanceof Error) {
      // Provide more helpful error messages
      if (error.message.includes("AccessDeniedException")) {
        throw new Error("AWS credentials don't have permission to access Bedrock. Ensure IAM role 'superapp-bedrock-access' has proper permissions.");
      } else if (error.message.includes("ResourceNotFoundException")) {
        throw new Error("GPT-OSS-120B model not available in this region. Try us-west-2.");
      } else if (error.message.includes("ThrottlingException")) {
        throw new Error("Bedrock rate limit exceeded. Please try again in a moment.");
      }
      throw error;
    }
    
    throw new Error("Failed to invoke GPT-OSS-120B");
  }
}
