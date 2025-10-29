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

  return new BedrockRuntimeClient({
    region,
    credentials: {
      accessKeyId: process.env.AWS_ACCESS_KEY_ID!,
      secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY!,
    },
  });
};

export interface ClaudeResponse {
  completion: string;
  stop_reason: string;
}

/**
 * Invoke Claude 3 via AWS Bedrock with true streaming
 * @param prompt - User prompt to send to Claude 3
 * @param onChunk - Callback for each streamed chunk from Bedrock
 * @returns Complete Claude's response
 */
export async function invokeClaude3Streaming(
  prompt: string,
  onChunk: (chunk: string) => void
): Promise<string> {
  try {
    const client = getBedrockClient();
    
    // Claude 3 Sonnet model ID
    const modelId = "anthropic.claude-3-sonnet-20240229-v1:0";
    
    // Prepare the request payload for Claude 3
    const payload = {
      anthropic_version: "bedrock-2023-05-31",
      max_tokens: 4096,
      messages: [
        {
          role: "user",
          content: prompt,
        },
      ],
      temperature: 0.7,
      top_p: 0.9,
    };

    const command = new InvokeModelWithResponseStreamCommand({
      modelId,
      contentType: "application/json",
      accept: "application/json",
      body: JSON.stringify(payload),
    });

    const response = await client.send(command);
    
    let fullText = "";
    
    // Process the streaming response
    if (response.body) {
      for await (const event of response.body) {
        if (event.chunk?.bytes) {
          const chunkData = JSON.parse(new TextDecoder().decode(event.chunk.bytes));
          
          // Handle different event types from Claude 3
          if (chunkData.type === 'content_block_delta' && chunkData.delta?.text) {
            const text = chunkData.delta.text;
            fullText += text;
            onChunk(text);
          } else if (chunkData.type === 'message_delta' && chunkData.delta?.stop_reason) {
            // Stream complete
            console.log('Stream completed with reason:', chunkData.delta.stop_reason);
          }
        }
      }
    }
    
    if (!fullText) {
      throw new Error("No response content from Claude 3");
    }
    
    return fullText;
  } catch (error) {
    console.error("Bedrock Claude 3 streaming error:", error);
    
    if (error instanceof Error) {
      // Provide more helpful error messages
      if (error.message.includes("AccessDeniedException")) {
        throw new Error("AWS credentials don't have permission to access Bedrock. Ensure IAM role 'superapp-bedrock-access' has proper permissions.");
      } else if (error.message.includes("ResourceNotFoundException")) {
        throw new Error("Claude 3 model not available in this region. Try us-east-1 or us-west-2.");
      } else if (error.message.includes("ThrottlingException")) {
        throw new Error("Bedrock rate limit exceeded. Please try again in a moment.");
      }
      throw error;
    }
    
    throw new Error("Failed to invoke Claude 3");
  }
}

/**
 * Invoke Claude 3 via AWS Bedrock
 * @param prompt - User prompt to send to Claude 3
 * @returns Claude's response
 */
export async function invokeClaude3(prompt: string): Promise<string> {
  try {
    const client = getBedrockClient();
    
    // Claude 3 Sonnet model ID
    const modelId = "anthropic.claude-3-sonnet-20240229-v1:0";
    
    // Prepare the request payload for Claude 3
    const payload = {
      anthropic_version: "bedrock-2023-05-31",
      max_tokens: 4096,
      messages: [
        {
          role: "user",
          content: prompt,
        },
      ],
      temperature: 0.7,
      top_p: 0.9,
    };

    const command = new InvokeModelCommand({
      modelId,
      contentType: "application/json",
      accept: "application/json",
      body: JSON.stringify(payload),
    });

    const response = await client.send(command);
    
    // Parse the response
    const responseBody = JSON.parse(new TextDecoder().decode(response.body));
    
    // Extract the text from Claude's response
    if (responseBody.content && responseBody.content.length > 0) {
      return responseBody.content[0].text;
    }
    
    throw new Error("No response content from Claude 3");
  } catch (error) {
    console.error("Bedrock Claude 3 invocation error:", error);
    
    if (error instanceof Error) {
      // Provide more helpful error messages
      if (error.message.includes("AccessDeniedException")) {
        throw new Error("AWS credentials don't have permission to access Bedrock. Ensure IAM role 'superapp-bedrock-access' has proper permissions.");
      } else if (error.message.includes("ResourceNotFoundException")) {
        throw new Error("Claude 3 model not available in this region. Try us-east-1 or us-west-2.");
      } else if (error.message.includes("ThrottlingException")) {
        throw new Error("Bedrock rate limit exceeded. Please try again in a moment.");
      }
      throw error;
    }
    
    throw new Error("Failed to invoke Claude 3");
  }
}
