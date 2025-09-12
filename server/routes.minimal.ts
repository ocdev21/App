import type { Express } from "express";
import { createServer, type Server } from "http";
import { storage } from "./storage";
import { insertAnomalySchema, insertProcessedFileSchema, insertSessionSchema } from "@shared/schema";
import multer from "multer";
import { spawn } from "child_process";
import path from "path";
import { clickhouse } from "./clickhouse.js";

const upload = multer({
  storage: multer.diskStorage({
    destination: '/tmp',
    filename: (req, file, cb) => {
      cb(null, `${Date.now()}-${file.originalname}`);
    }
  }),
  limits: { fileSize: 3 * 1024 * 1024 * 1024 } // 3GB limit
});

export async function registerRoutes(app: Express): Promise<Server> {
  const httpServer = createServer(app);

  // Dashboard metrics
  app.get("/api/dashboard/metrics", async (req, res) => {
    try {
      if (!clickhouse.isAvailable()) {
        return res.status(503).json({ 
          error: "ClickHouse database unavailable - Real data access required" 
        });
      }

      const metrics = await storage.getDashboardMetrics();
      res.json(metrics);
    } catch (error) {
      console.error("Error fetching dashboard metrics:", error);
      res.status(500).json({ 
        error: "Failed to fetch real dashboard metrics from ClickHouse" 
      });
    }
  });

  // Dashboard metrics with percentage changes
  app.get("/api/dashboard/metrics-with-changes", async (req, res) => {
    try {
      const metricsWithChanges = await storage.getDashboardMetricsWithChanges();
      res.json(metricsWithChanges);
    } catch (error) {
      console.error("Error fetching dashboard metrics with changes:", error);
      res.status(500).json({ 
        error: "Failed to fetch dashboard metrics with percentage changes" 
      });
    }
  });

  app.get("/api/dashboard/trends", async (req, res) => {
    try {
      if (!clickhouse.isAvailable()) {
        return res.status(503).json({ 
          error: "ClickHouse database unavailable - Real data access required" 
        });
      }

      const trends = await storage.getAnomalyTrends(parseInt(req.query.days as string) || 7);
      res.json(trends);
    } catch (error) {
      console.error("Error fetching anomaly trends:", error);
      res.status(500).json({ 
        error: "Failed to fetch real anomaly trends from ClickHouse" 
      });
    }
  });

  app.get("/api/dashboard/breakdown", async (req, res) => {
    try {
      if (!clickhouse.isAvailable()) {
        return res.status(503).json({ 
          error: "ClickHouse database unavailable - Real data access required" 
        });
      }

      const breakdown = await storage.getAnomalyTypeBreakdown();
      res.json(breakdown);
    } catch (error) {
      console.error("Error fetching anomaly breakdown:", error);
      res.status(500).json({ 
        error: "Failed to fetch real anomaly breakdown from ClickHouse" 
      });
    }
  });

  // Anomalies endpoints
  app.get("/api/anomalies", async (req, res) => {
    try {
      const limit = parseInt(req.query.limit as string) || 50;
      const offset = parseInt(req.query.offset as string) || 0;
      const type = req.query.type as string;
      const severity = req.query.severity as string;

      const anomalies = await storage.getAnomalies(limit, offset, type, severity);
      res.json(anomalies);
    } catch (error) {
      console.error('Error fetching anomalies:', error);
      res.status(500).json({ message: "Failed to fetch anomalies" });
    }
  });

  app.get("/api/anomalies/:id", async (req, res) => {
    try {
      const anomaly = await storage.getAnomaly(req.params.id);
      if (!anomaly) {
        return res.status(404).json({ message: "Anomaly not found" });
      }
      res.json(anomaly);
    } catch (error) {
      console.error('Error fetching anomaly:', error);
      res.status(500).json({ message: "Failed to fetch anomaly" });
    }
  });

  app.post("/api/anomalies", async (req, res) => {
    try {
      const validatedData = insertAnomalySchema.parse(req.body);
      const anomaly = await storage.createAnomaly(validatedData);
      res.status(201).json(anomaly);
    } catch (error) {
      console.error('Error creating anomaly:', error);
      res.status(400).json({ message: "Invalid anomaly data" });
    }
  });

  app.patch("/api/anomalies/:id/status", async (req, res) => {
    try {
      const { status } = req.body;
      const anomaly = await storage.updateAnomalyStatus(req.params.id, status);
      if (!anomaly) {
        return res.status(404).json({ message: "Anomaly not found" });
      }
      res.json(anomaly);
    } catch (error) {
      console.error('Error updating anomaly status:', error);
      res.status(500).json({ message: "Failed to update anomaly status" });
    }
  });

  // Files endpoints
  app.get("/api/files", async (req, res) => {
    try {
      const files = await storage.getProcessedFiles();
      res.json(files);
    } catch (error) {
      console.error('Error fetching files:', error);
      res.status(500).json({ message: "Failed to fetch files" });
    }
  });

  app.post("/api/files/upload", upload.single('file'), async (req, res) => {
    try {
      if (!req.file) {
        return res.status(400).json({ message: "No file uploaded" });
      }

      const { originalname, size, buffer } = req.file;
      const fileType = originalname.endsWith('.pcap') || originalname.endsWith('.pcapng') ? 'pcap' : 'log';

      // Create file record
      const file = await storage.createProcessedFile({
        filename: originalname,
        file_type: fileType,
        file_size: size,
        processing_status: 'pending',
        anomalies_found: 0,
      });

      // Start processing asynchronously
      setImmediate(async () => {
        try {
          await storage.updateFileStatus(file.id, 'processing');

          const startTime = Date.now();
          let anomaliesFound = 0;

          if (fileType === 'pcap') {
            // Check file size and choose appropriate processor
            const fileSizeGB = size / (1024 * 1024 * 1024);
            const processorScript = fileSizeGB > 0.5 ? 
              'server/services/large_pcap_processor.py' : 
              'server/services/pcap_processor.py';
            
            console.log(`File size: ${fileSizeGB.toFixed(2)}GB, using ${processorScript}`);
            
            // Process PCAP file
            const pythonProcess = spawn('python3', [
              path.join(process.cwd(), processorScript),
              '--file-id', file.id,
              '--filename', originalname,
              ...(fileSizeGB > 0.5 ? ['--chunk-size', '5000'] : [])
            ]);

            // File is already saved to disk by multer
            const tempPath = req.file.path;

            pythonProcess.stdin.write(tempPath);
            pythonProcess.stdin.end();

            pythonProcess.on('close', async (code) => {
              const processingTime = Date.now() - startTime;
              if (code === 0) {
                await storage.updateFileStatus(file.id, 'completed', anomaliesFound, processingTime);
              } else {
                await storage.updateFileStatus(file.id, 'failed', 0, processingTime, 'Processing failed');
              }
              // Cleanup temp file
              const fs = require('fs');
              fs.unlinkSync(tempPath);
            });
          } else {
            // Process log file
            const pythonProcess = spawn('python3', [
              path.join(process.cwd(), 'server/services/ue_analyzer.py'),
              '--file-id', file.id,
              '--filename', originalname
            ]);

            pythonProcess.stdin.write(buffer.toString());
            pythonProcess.stdin.end();

            pythonProcess.on('close', async (code) => {
              const processingTime = Date.now() - startTime;
              if (code === 0) {
                await storage.updateFileStatus(file.id, 'completed', anomaliesFound, processingTime);
              } else {
                await storage.updateFileStatus(file.id, 'failed', 0, processingTime, 'Processing failed');
              }
            });
          }
        } catch (error: any) {
          console.error('File processing error:', error);
          await storage.updateFileStatus(file.id, 'failed', 0, 0, error?.message || 'Unknown error');
        }
      });

      res.status(201).json(file);
    } catch (error) {
      console.error('Error uploading file:', error);
      res.status(500).json({ message: "Failed to upload file" });
    }
  });

  // Sessions endpoints
  app.get("/api/sessions", async (req, res) => {
    try {
      const sessions = await storage.getSessions();
      res.json(sessions);
    } catch (error) {
      console.error('Error fetching sessions:', error);
      res.status(500).json({ message: "Failed to fetch sessions" });
    }
  });

  app.post("/api/sessions", async (req, res) => {
    try {
      const validatedData = insertSessionSchema.parse(req.body);
      const session = await storage.createSession(validatedData);
      res.status(201).json(session);
    } catch (error) {
      console.error('Error creating session:', error);
      res.status(400).json({ message: "Invalid session data" });
    }
  });

  // Basic recommendation endpoint (without LLM)
  app.get("/api/anomalies/:id/recommendation", async (req, res) => {
    try {
      const { id } = req.params;
      const anomaly = await storage.getAnomaly(id);

      if (!anomaly) {
        return res.status(404).json({ message: 'Anomaly not found' });
      }

      // Generate static recommendation based on anomaly type
      let recommendation = '';

      if (anomaly.type === 'fronthaul') {
        recommendation = 'Check physical connections between DU and RU. Verify fronthaul timing synchronization is within 100μs threshold. Monitor packet loss rates and communication ratios.';
      } else if (anomaly.type === 'ue_event') {
        recommendation = 'Investigate UE attachment procedures. Review context setup timeouts and verify mobility management configuration. Check for mobility handover issues.';
      } else {
        recommendation = 'Analyze network logs for pattern recognition. Implement continuous monitoring for this anomaly type. Document findings for future reference.';
      }

      res.json({ recommendation });
    } catch (error) {
      console.error('Failed to get recommendation:', error);
      res.status(500).json({ message: 'Failed to get recommendation' });
    }
  });

  return httpServer;
}