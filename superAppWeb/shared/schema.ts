import { z } from "zod";

// AWS Bedrock Claude 3 Request/Response
export const bedrockPromptSchema = z.object({
  prompt: z.string().min(1, "Prompt is required").max(10000, "Prompt too long"),
});

export type BedrockPrompt = z.infer<typeof bedrockPromptSchema>;

export interface BedrockResponse {
  response: string;
  timestamp: string;
}

// AWS Timestream Query Response
export interface TimestreamRecord {
  [key: string]: string | number | null;
}

export interface TimestreamQueryResponse {
  records: TimestreamRecord[];
  columnInfo: Array<{
    name: string;
    type: string;
  }>;
  queryStatus: string;
  lastUpdated: string;
}

// Connection Status
export interface AWSConnectionStatus {
  bedrock: 'connected' | 'connecting' | 'error';
  timestream: 'connected' | 'connecting' | 'error';
  message?: string;
}
