import type { Express } from "express";
import { createServer, type Server } from "http";
import { z } from "zod";
import { invokeClaude3, invokeClaude3Streaming } from "./aws/bedrock";
import { queryUEReports, parseTimestreamResponse, setupTimestreamDB } from "./aws/timestream";
import { bedrockPromptSchema } from "@shared/schema";

export async function registerRoutes(app: Express): Promise<Server> {
  
  /**
   * POST /api/bedrock/chat-stream
   * Send prompt to Claude 3 and get streaming AI response
   */
  app.post("/api/bedrock/chat-stream", async (req, res) => {
    try {
      // Validate request body
      const result = bedrockPromptSchema.safeParse(req.body);
      
      if (!result.success) {
        return res.status(400).json({
          error: "Invalid request",
          details: result.error.errors,
        });
      }

      const { prompt } = result.data;
      
      // Set headers for Server-Sent Events
      res.setHeader('Content-Type', 'text/event-stream');
      res.setHeader('Cache-Control', 'no-cache');
      res.setHeader('Connection', 'keep-alive');
      
      // Stream Claude 3 response
      await invokeClaude3Streaming(prompt, (chunk) => {
        res.write(`data: ${JSON.stringify({ chunk })}\n\n`);
      });
      
      // Send completion marker
      res.write(`data: [DONE]\n\n`);
      res.end();
    } catch (error) {
      console.error("Bedrock streaming error:", error);
      
      if (!res.headersSent) {
        res.status(500).json({
          error: error instanceof Error ? error.message : "Failed to stream response from Claude 3",
        });
      } else {
        res.write(`data: ${JSON.stringify({ error: error instanceof Error ? error.message : "Stream error" })}\n\n`);
        res.end();
      }
    }
  });

  /**
   * POST /api/bedrock/chat
   * Send prompt to Claude 3 and get AI response
   */
  app.post("/api/bedrock/chat", async (req, res) => {
    try {
      // Validate request body
      const result = bedrockPromptSchema.safeParse(req.body);
      
      if (!result.success) {
        return res.status(400).json({
          error: "Invalid request",
          details: result.error.errors,
        });
      }

      const { prompt } = result.data;
      
      // Invoke Claude 3
      const response = await invokeClaude3(prompt);
      
      res.json({
        response,
        timestamp: new Date().toISOString(),
      });
    } catch (error) {
      console.error("Bedrock chat error:", error);
      
      res.status(500).json({
        error: error instanceof Error ? error.message : "Failed to get response from Claude 3",
      });
    }
  });

  /**
   * GET /api/timestream/query
   * Query UEReports table from Timestream database
   */
  app.get("/api/timestream/query", async (req, res) => {
    try {
      const response = await queryUEReports();
      const parsedData = parseTimestreamResponse(response);
      
      res.json({
        records: parsedData.records,
        columnInfo: parsedData.columnInfo,
        queryStatus: parsedData.queryStatus === 100 ? "complete" : "processing",
        lastUpdated: new Date().toISOString(),
      });
    } catch (error) {
      console.error("Timestream query error:", error);
      
      res.status(500).json({
        error: error instanceof Error ? error.message : "Failed to query Timestream database",
      });
    }
  });

  /**
   * POST /api/timestream/setup
   * Create Timestream database and UEReports table if they don't exist
   */
  app.post("/api/timestream/setup", async (req, res) => {
    try {
      const result = await setupTimestreamDB();
      
      res.json(result);
    } catch (error) {
      console.error("Timestream setup error:", error);
      
      res.status(500).json({
        error: error instanceof Error ? error.message : "Failed to setup Timestream database",
      });
    }
  });

  /**
   * GET /api/health
   * Health check endpoint to verify AWS connectivity
   */
  app.get("/api/health", async (req, res) => {
    const health = {
      status: "ok",
      timestamp: new Date().toISOString(),
      aws: {
        region: process.env.AWS_REGION || "not configured",
        accessKeyConfigured: !!process.env.AWS_ACCESS_KEY_ID,
        secretKeyConfigured: !!process.env.AWS_SECRET_ACCESS_KEY,
        timestreamDatabase: process.env.TIMESTREAM_DATABASE_NAME || "SuperAppDB",
      },
    };
    
    res.json(health);
  });

  const httpServer = createServer(app);
  return httpServer;
}
