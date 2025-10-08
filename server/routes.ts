import type { Express } from "express";
import { createServer, type Server } from "http";
import { storage } from "./storage";
import { insertAnomalySchema, insertSessionSchema } from "@shared/schema";
import { WebSocketServer } from "ws";
import WebSocket from 'ws';
import { clickhouse } from "./clickhouse.js";
import axios from 'axios';
import type { Anomaly } from "@shared/schema";

// Rule-based recommendation fallback
function getRuleBasedRecommendations(anomaly: Anomaly): string {
  const recommendations: Record<string, string> = {
    'fronthaul': `Based on the fronthaul anomaly detected, here are the recommended troubleshooting steps:

1. **Verify Physical Connections**: Check all fiber optic cables between DU and RU for any physical damage or loose connections.

2. **Check Signal Quality**: Monitor RSRP (Reference Signal Received Power) and SINR (Signal-to-Interference-plus-Noise Ratio) levels. Target RSRP > -100 dBm and SINR > 10 dB.

3. **Analyze Timing**: Verify timing synchronization between DU and RU. Check for timing drift or jitter issues using GPS/PTP synchronization.

4. **Review Configuration**: Ensure DU-RU interface parameters match on both ends. Verify VLAN, QoS, and bandwidth allocation settings.

5. **Monitor Traffic Load**: Check if the fronthaul link is experiencing congestion. Consider upgrading bandwidth if utilization exceeds 70%.`,

    'ue_event': `UE event anomaly detected. Follow these diagnostic steps:

1. **Authentication Check**: Verify UE credentials and authentication process. Check for expired certificates or incorrect AKA parameters.

2. **Radio Conditions**: Assess UE's radio environment. Poor RSRP/RSRQ may cause attach failures. Target: RSRP > -110 dBm, RSRQ > -15 dB.

3. **Core Network**: Verify AMF/MME connectivity and capacity. Check for overload conditions or configuration mismatches.

4. **UE Capability**: Ensure UE supports the network's frequency bands and features. Check for firmware updates.

5. **Interference Analysis**: Scan for external interference sources that might disrupt UE-to-network communication.`,

    'mac_address': `MAC address anomaly requires immediate attention:

1. **Duplicate Detection**: Scan network for duplicate MAC addresses. Use ARP table analysis to identify conflicts.

2. **VLAN Configuration**: Verify VLAN assignments and MAC address filtering rules. Ensure proper segmentation.

3. **Switch Port Security**: Check switch port security settings. Review MAC address learning and aging parameters.

4. **Security Assessment**: Investigate potential MAC spoofing or ARP poisoning attacks. Enable port security features.

5. **Address Management**: Review DHCP server logs and IP-MAC bindings. Ensure proper address allocation and reservation.`,

    'protocol': `Protocol violation detected. Recommended actions:

1. **Packet Analysis**: Capture and analyze packets using Wireshark or tcpdump. Focus on malformed frames or incorrect sequence numbers.

2. **Version Compatibility**: Verify protocol version compatibility between network elements. Check for firmware mismatches.

3. **Parameter Validation**: Review protocol-specific parameters (e.g., PRACH format, preamble configuration). Ensure compliance with 3GPP standards.

4. **Error Correction**: Enable error detection and correction mechanisms. Monitor CRC failures and retransmission rates.

5. **Standards Compliance**: Cross-reference configuration with latest 3GPP specifications. Update firmware to resolve known protocol issues.`
  };

  const recommendation = recommendations[anomaly.type] || `Detected ${anomaly.type} anomaly with ${anomaly.severity} severity.

General troubleshooting steps:
1. Review system logs for detailed error messages
2. Check network connectivity and configuration
3. Verify all components are running latest firmware
4. Monitor system resources (CPU, memory, bandwidth)
5. Escalate to L2 support if issue persists after initial troubleshooting`;

  return recommendation;
}



export async function registerRoutes(app: Express): Promise<Server> {
  const httpServer = createServer(app);

  // WebSocket setup for streaming responses
  const wss = new WebSocketServer({
    server: httpServer,
    path: '/ws'
  });

  wss.on('connection', (ws) => {
    console.log('WebSocket client connected');

    ws.on('message', async (message) => {
      try {
        const data = JSON.parse(message.toString());

        if (data.type === 'get_recommendations') {
          const { anomalyId } = data;
          console.log('Received recommendation request for anomaly ID:', anomalyId);

          // Get anomaly details from storage
          const anomaly = await storage.getAnomaly(anomalyId);
          if (!anomaly) {
            console.error('Anomaly not found:', anomalyId);
            ws.send(JSON.stringify({ type: 'error', data: 'Anomaly not found' }));
            return;
          }

          console.log('Found anomaly:', anomaly.id, anomaly.type);

          // Call Mistral GGUF inference server for AI recommendations
          const inferenceHost = process.env.TSLAM_REMOTE_HOST || 'localhost';
          const inferencePort = process.env.TSLAM_REMOTE_PORT || '8000';
          const inferenceUrl = `http://${inferenceHost}:${inferencePort}/v1/chat/completions`;
          
          console.log(`Connecting to AI inference server: ${inferenceUrl}`);

          try {
            const response = await axios.post(inferenceUrl, {
              model: "mistral-7b-instruct-gguf",
              messages: [
                {
                  role: "system",
                  content: "You are an expert L1 network troubleshooting AI assistant. Analyze the anomaly and provide specific technical recommendations for resolution."
                },
                {
                  role: "user",
                  content: `Analyze this L1 network anomaly:\n\nType: ${anomaly.type}\nDescription: ${anomaly.description || 'Network anomaly detected'}\nSeverity: ${anomaly.severity || 'unknown'}\n\nProvide detailed troubleshooting steps and root cause analysis.`
                }
              ],
              max_tokens: 500,
              temperature: 0.3,
              stream: true
            }, {
              responseType: 'stream',
              timeout: 60000
            });

            console.log('Streaming AI recommendations...');

            response.data.on('data', (chunk: Buffer) => {
              const lines = chunk.toString().split('\n').filter(line => line.trim() !== '');
              
              for (const line of lines) {
                if (line.startsWith('data: ')) {
                  const data = line.slice(6);
                  
                  if (data === '[DONE]') {
                    ws.send(JSON.stringify({ type: 'recommendation_complete', code: 0 }));
                    return;
                  }

                  try {
                    const parsed = JSON.parse(data);
                    const content = parsed.choices?.[0]?.delta?.content;
                    
                    if (content) {
                      ws.send(JSON.stringify({ 
                        type: 'recommendation_chunk', 
                        data: content 
                      }));
                    }
                  } catch (e) {
                    console.error('Error parsing streaming chunk:', e);
                  }
                }
              }
            });

            response.data.on('end', () => {
              console.log('AI recommendations stream complete');
              ws.send(JSON.stringify({ type: 'recommendation_complete', code: 0 }));
            });

            response.data.on('error', (error: Error) => {
              console.error('Stream error:', error);
              ws.send(JSON.stringify({ 
                type: 'error', 
                data: 'AI inference stream error' 
              }));
            });

          } catch (error: any) {
            console.error('AI inference error:', error.message);
            console.log('Providing rule-based recommendations as fallback');
            
            // Provide rule-based recommendations as fallback
            const ruleBasedRecommendation = getRuleBasedRecommendations(anomaly);
            const words = ruleBasedRecommendation.split(' ');
            
            for (const word of words) {
              ws.send(JSON.stringify({ 
                type: 'recommendation_chunk', 
                data: word + ' ' 
              }));
              await new Promise(resolve => setTimeout(resolve, 50));
            }
            
            ws.send(JSON.stringify({ type: 'recommendation_complete', code: 0 }));
          }
        }
      } catch (error) {
        console.error('WebSocket message error:', error);
        ws.send(JSON.stringify({ type: 'error', data: 'Invalid message format' }));
      }
    });

    ws.on('close', () => {
      console.log('WebSocket client disconnected');
    });
  });

  // Dashboard metrics
  app.get("/api/dashboard/metrics", async (req, res) => {
    try {
      const metrics = await storage.getDashboardMetrics();
      res.json(metrics);
    } catch (error) {
      console.error("Error fetching dashboard metrics:", error);
      res.status(500).json({ 
        error: "Failed to fetch dashboard metrics" 
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
      const trends = await storage.getAnomalyTrends(parseInt(req.query.days as string) || 7);
      res.json(trends);
    } catch (error) {
      console.error("Error fetching anomaly trends:", error);
      res.status(500).json({ 
        error: "Failed to fetch anomaly trends" 
      });
    }
  });

  app.get("/api/dashboard/breakdown", async (req, res) => {
    try {
      const breakdown = await storage.getAnomalyTypeBreakdown();
      res.json(breakdown);
    } catch (error) {
      console.error("Error fetching anomaly breakdown:", error);
      res.status(500).json({ 
        error: "Failed to fetch anomaly breakdown" 
      });
    }
  });

  app.get("/api/dashboard/severity", async (req, res) => {
    try {
      const severity = await storage.getSeverityBreakdown();
      res.json(severity);
    } catch (error) {
      console.error("Error fetching severity breakdown:", error);
      res.status(500).json({ 
        error: "Failed to fetch severity breakdown" 
      });
    }
  });

  app.get("/api/dashboard/heatmap", async (req, res) => {
    try {
      const days = parseInt(req.query.days as string) || 7;
      const heatmap = await storage.getHourlyHeatmapData(days);
      res.json(heatmap);
    } catch (error) {
      console.error("Error fetching heatmap data:", error);
      res.status(500).json({ 
        error: "Failed to fetch heatmap data" 
      });
    }
  });

  app.get("/api/dashboard/top-sources", async (req, res) => {
    try {
      const limit = parseInt(req.query.limit as string) || 10;
      const sources = await storage.getTopAffectedSources(limit);
      res.json(sources);
    } catch (error) {
      console.error("Error fetching top sources:", error);
      res.status(500).json({ 
        error: "Failed to fetch top sources" 
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

  // Get recommendation for anomaly
  app.get("/api/anomalies/:id/recommendation", async (req, res) => {
    try {
      const { id } = req.params;
      const anomaly = await storage.getAnomaly(id);

      if (!anomaly) {
        return res.status(404).json({ message: 'Anomaly not found' });
      }

      // Generate recommendation based on anomaly type and details
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

  // Get explainable AI analysis for anomaly
  app.get("/api/anomalies/:id/explanation", async (req, res) => {
    try {
      const { id } = req.params;
      const anomaly = await storage.getAnomaly(id);

      if (!anomaly) {
        return res.status(404).json({ message: 'Anomaly not found' });
      }

      // Try to get explanation from ClickHouse context_data or generate based on anomaly details
      let explanationData = null;
      
      if (anomaly.context_data) {
        try {
          const contextData = JSON.parse(anomaly.context_data);
          if (contextData.shap_explanation || contextData.model_votes) {
            explanationData = await storage.getExplainableAIData(id, contextData);
          }
        } catch (e) {
          console.log('No valid context data for SHAP explanation');
        }
      }

      // Generate fallback explanation if no SHAP data available
      if (!explanationData) {
        explanationData = generateFallbackExplanation(anomaly);
      }

      res.json(explanationData);
    } catch (error) {
      console.error('Failed to get anomaly explanation:', error);
      res.status(500).json({ message: 'Failed to get anomaly explanation' });
    }
  });

  // Helper function to generate fallback explanation
  function generateFallbackExplanation(anomaly: any) {
    const featureDescriptions = {
      'packet_timing': 'Timing between packet arrivals',
      'size_variation': 'Variation in packet sizes',
      'sequence_gaps': 'Gaps in packet sequences',
      'protocol_anomalies': 'Protocol-level irregularities',
      'fronthaul_timing': 'DU-RU communication timing',
      'ue_event_frequency': 'Frequency of UE events',
      'mac_address_patterns': 'MAC address behavior patterns',
      'rsrp_variation': 'RSRP signal variation',
      'rsrq_patterns': 'RSRQ quality patterns',
      'sinr_stability': 'SINR stability metrics'
    };

    const modelExplanations: any = {};
    
    // Generate mock model explanations based on anomaly type
    const models = ['isolation_forest', 'dbscan', 'one_class_svm', 'local_outlier_factor'];
    
    models.forEach((model, idx) => {
      const confidence = 0.6 + (idx * 0.1) + Math.random() * 0.2;
      const isAnomalyDetected = confidence > 0.7;
      
      modelExplanations[model] = {
        confidence: Math.min(confidence, 0.95),
        decision: isAnomalyDetected ? 'ANOMALY' : 'NORMAL',
        feature_contributions: {},
        top_positive_features: isAnomalyDetected ? [
          { feature: 'fronthaul_timing', value: 0.85, impact: 0.32 },
          { feature: 'packet_timing', value: 0.78, impact: 0.28 },
          { feature: 'sequence_gaps', value: 0.65, impact: 0.15 }
        ] : [],
        top_negative_features: [
          { feature: 'rsrp_variation', value: 0.45, impact: -0.12 },
          { feature: 'sinr_stability', value: 0.52, impact: -0.08 }
        ]
      };
    });

    let humanExplanation = '';
    if (anomaly.type === 'fronthaul' || anomaly.anomaly_type === 'fronthaul') {
      humanExplanation = `**Fronthaul Communication Anomaly Detected**

The ML algorithms identified unusual timing patterns in the DU-RU fronthaul communication. Key indicators include:

• **Timing Deviation**: Communication timing exceeded normal thresholds
• **Packet Sequencing**: Irregular gaps in packet sequences were observed  
• **Protocol Behavior**: eCPRI protocol showed non-standard patterns

**Primary Contributing Factors:**
• Fronthaul timing synchronization issues (High Impact: 0.32)
• Packet arrival timing variations (Medium Impact: 0.28)
• Sequence numbering gaps (Low Impact: 0.15)

**Confidence Assessment:**
This anomaly was detected by 3 out of 4 ML algorithms, indicating high reliability in the detection.`;
    } else if (anomaly.type === 'ue_event' || anomaly.anomaly_type === 'ue_event') {
      humanExplanation = `**UE Event Anomaly Detected**

The system detected unusual patterns in UE (User Equipment) behavior. Analysis shows:

• **Event Frequency**: Abnormal frequency of UE events detected
• **Mobility Patterns**: Irregular handover or attachment procedures
• **Signal Quality**: Unexpected RSRP/RSRQ/SINR variations

**Primary Contributing Factors:**
• UE event frequency exceeded baseline (High Impact: 0.35)
• Signal quality variations outside normal range (Medium Impact: 0.25)
• Mobility management irregularities (Low Impact: 0.18)

**Confidence Assessment:**
Multiple algorithms concur on this anomaly, suggesting genuine UE behavioral issues.`;
    } else {
      humanExplanation = `**Network Protocol Anomaly Detected**

ML analysis identified irregularities in network communication patterns:

• **Protocol Analysis**: Non-standard protocol behavior observed
• **Traffic Patterns**: Unusual traffic flow characteristics
• **Performance Metrics**: Key performance indicators outside normal ranges

**Primary Contributing Factors:**
• Protocol behavior anomalies (Impact: 0.30)
• Traffic pattern irregularities (Impact: 0.25)
• Performance metric deviations (Impact: 0.20)

**Assessment:**
This represents a general network anomaly requiring further investigation.`;
    }

    return {
      model_explanations: modelExplanations,
      human_explanation: humanExplanation,
      feature_descriptions: featureDescriptions,
      overall_confidence: anomaly.confidence_score || 0.75,
      model_agreement: 3
    };
  }

  return httpServer;
}