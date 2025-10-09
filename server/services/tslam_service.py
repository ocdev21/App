#!/usr/bin/env python3

import sys
import json
import time
import os
import requests
import socket
from datetime import datetime

# Optional AI dependencies - graceful fallback if not available
try:
    from transformers import AutoTokenizer, AutoModelForCausalLM
    import torch
    AI_AVAILABLE = True
except ImportError:
    AI_AVAILABLE = False
    print("AI packages (transformers/torch) not available - using rule-based recommendations", file=sys.stderr)

class TSLAMService:
    def __init__(self):
        self.model_path = os.getenv('TSLAM_MODEL_PATH', '/home/users/praveen.joe/TSLAM-4B')
        self.model = None
        self.tokenizer = None
        self.ai_mode = AI_AVAILABLE
        
        if self.ai_mode:
            self.load_model()
        else:
            print("Running in rule-based mode (no AI dependencies)", file=sys.stderr)

    def load_model(self):
        """Load TSLAM 4B model optimized for Tesla P40"""
        if not AI_AVAILABLE:
            print("AI packages not available - using rule-based recommendations", file=sys.stderr)
            return
            
        try:
            print("Loading TSLAM 4B model from /home/users/praveen.joe/TSLAM-4B...", file=sys.stderr)

            # Load tokenizer
            self.tokenizer = AutoTokenizer.from_pretrained(self.model_path)
            if self.tokenizer.pad_token is None:
                self.tokenizer.pad_token = self.tokenizer.eos_token

            # Load model with Tesla P40 optimizations
            self.model = AutoModelForCausalLM.from_pretrained(
                self.model_path,
                torch_dtype=torch.float16,  # Optimized for Tesla P40
                device_map="cuda:0" if torch.cuda.is_available() else "cpu",
                load_in_4bit=True,  # 4-bit quantization for memory efficiency
                max_memory={"0": "22GB"} if torch.cuda.is_available() else None,  # Leave 2GB for other processes
                trust_remote_code=True
            )
            print("TSLAM model loaded successfully on Tesla P40", file=sys.stderr)

        except Exception as e:
            print(f"Error loading TSLAM model: {e}", file=sys.stderr)
            print("Model loading failed - using rule-based recommendations", file=sys.stderr)
            self.model = None
            self.tokenizer = None
            self.ai_mode = False

    def get_troubleshooting_prompt(self, anomaly_id, description):
        """Generate enhanced troubleshooting prompt for TSLAM model"""
        prompt = f"""You are a specialized 5G L1 network troubleshooting AI expert with deep knowledge of 5G RAN fronthaul, UE procedures, MAC layer operations, and L1 protocols.

Your responses must be:
- Technically accurate and actionable
- Structured with clear priority levels (Critical, Important, Optional)
- Include specific commands, tools, and configuration changes
- Focus on root cause analysis and prevention

Anomaly ID: {anomaly_id}
Description: {description}

ANALYSIS REQUIRED:
Provide troubleshooting in this structure:

1. ROOT CAUSE ANALYSIS
2. IMMEDIATE ACTIONS (Critical)
3. DETAILED INVESTIGATION (Important)
4. RESOLUTION STEPS
5. PREVENTION MEASURES (Optional)

Use markdown formatting, code blocks for commands, and be specific.

Analysis:"""

        return prompt

    def get_rule_based_recommendations(self, anomaly_id, description):
        """Generate rule-based troubleshooting recommendations"""
        recommendations = {
            'fronthaul': {
                'high_latency': """## Fronthaul Latency Analysis
**Root Cause**: DU-RU link congestion or synchronization issues
**Immediate Actions**: 
1. Check network interface utilization on DU and RU
2. Verify eCPRI link quality and error rates
3. Monitor buffer usage on both ends

**Detailed Investigation**:
1. Use tcpdump to capture eCPRI traffic
2. Check for packet loss and jitter
3. Verify timing synchronization (GPS/PTP)
4. Analyze CPU utilization on DU

**Resolution Steps**:
1. Increase eCPRI link bandwidth if available
2. Optimize packet scheduling parameters
3. Update DU/RU firmware if issues persist
4. Consider load balancing across multiple RUs

**Prevention**: Regular monitoring of fronthaul KPIs and proactive capacity planning""",
                
                'sync_error': """## Fronthaul Synchronization Issues
**Root Cause**: Timing reference problems or clock drift
**Immediate Actions**:
1. Verify GPS signal strength and quality
2. Check PTP synchronization status
3. Monitor phase and frequency alignment

**Detailed Investigation**:
1. Use PTP monitoring tools
2. Check for timing loop conflicts
3. Verify grandmaster clock stability
4. Monitor environmental factors affecting GPS

**Resolution Steps**:
1. Reconfigure PTP parameters
2. Replace faulty timing equipment
3. Implement backup timing sources
4. Optimize network for timing distribution

**Prevention**: Redundant timing sources and continuous monitoring"""
            },
            
            'backhaul': {
                'congestion': """## Backhaul Congestion Analysis
**Root Cause**: Insufficient backhaul capacity or routing issues
**Immediate Actions**:
1. Check link utilization across all backhaul segments
2. Identify congested nodes and bottlenecks
3. Implement traffic prioritization if available

**Detailed Investigation**:
1. Analyze traffic patterns and peak hours
2. Check for routing loops or suboptimal paths
3. Monitor QoS enforcement effectiveness
4. Verify capacity planning assumptions

**Resolution Steps**:
1. Add additional backhaul capacity
2. Optimize routing and load balancing
3. Implement advanced QoS policies
4. Consider traffic offloading strategies

**Prevention**: Proactive capacity monitoring and automated scaling"""
            },
            
            'midhaul': {
                'high_delay': """## Midhaul Delay Issues
**Root Cause**: Processing delays or transport network issues
**Immediate Actions**:
1. Check processing delays at CU-DU interface
2. Monitor transport network latency
3. Verify F1 interface performance

**Detailed Investigation**:
1. Analyze end-to-end latency budget
2. Check for queuing delays
3. Monitor CU processing efficiency
4. Verify transport QoS implementation

**Resolution Steps**:
1. Optimize CU processing algorithms
2. Implement low-latency transport modes
3. Adjust buffer sizes and scheduling
4. Consider edge computing deployment

**Prevention**: Regular latency monitoring and optimization"""
            }
        }
        
        # Determine recommendation based on description
        description_lower = description.lower()
        anomaly_type = None
        issue_type = None
        
        # Detect anomaly type
        if 'fronthaul' in description_lower:
            anomaly_type = 'fronthaul'
            if 'latency' in description_lower or 'delay' in description_lower:
                issue_type = 'high_latency'
            elif 'sync' in description_lower or 'timing' in description_lower:
                issue_type = 'sync_error'
        elif 'backhaul' in description_lower:
            anomaly_type = 'backhaul'
            if 'congestion' in description_lower or 'capacity' in description_lower:
                issue_type = 'congestion'
        elif 'midhaul' in description_lower:
            anomaly_type = 'midhaul'
            if 'delay' in description_lower or 'latency' in description_lower:
                issue_type = 'high_delay'
        
        # Get specific recommendation or generic one
        if anomaly_type and issue_type and anomaly_type in recommendations and issue_type in recommendations[anomaly_type]:
            return recommendations[anomaly_type][issue_type]
        else:
            # Generic recommendation
            return f"""## Network Troubleshooting Guide
**Anomaly ID**: {anomaly_id}
**Description**: {description}

**General Investigation Steps**:
1. **Check Interface Status**: Verify all network interfaces are up and operational
2. **Monitor Traffic**: Analyze traffic patterns and identify anomalies
3. **Check Logs**: Review system logs for error messages and warnings
4. **Verify Configuration**: Ensure all network configurations are correct
5. **Test Connectivity**: Perform ping and traceroute tests

**Standard Resolution Approach**:
1. Isolate the affected network segment
2. Check for hardware failures or misconfigurations
3. Apply known fixes for similar issues
4. Monitor for resolution and document changes
5. Implement preventive measures

**Escalation Criteria**:
- Service impacting issues lasting > 15 minutes
- Multiple concurrent anomalies
- Unknown or novel error patterns
- Hardware replacement required

**Contact Information**:
- L2 Support: For complex routing and protocol issues
- Vendor Support: For equipment-specific problems
- NOC: For service-impacting incidents"""

    def generate_streaming_response(self, anomaly_id, description):
        """Generate real-time streaming response (AI or rule-based)"""
        if not self.ai_mode or self.model is None or self.tokenizer is None:
            # Use rule-based recommendations
            print(f"Generating rule-based recommendations for: {description}", file=sys.stderr)
            recommendation = self.get_rule_based_recommendations(anomaly_id, description)
            
            # Stream the recommendation with realistic timing
            words = recommendation.split()
            for word in words:
                print(word + ' ', end='', flush=True)
                time.sleep(0.05)  # 20 words per second for readability
            print()  # Final newline
            return

        # AI mode - original TSLAM functionality
        try:
            prompt = self.get_troubleshooting_prompt(anomaly_id, description)
            print(f"Generating AI recommendations for: {description}", file=sys.stderr)

            # Tokenize input for Tesla P40
            inputs = self.tokenizer(prompt, return_tensors="pt", truncation=True, max_length=2048)
            if torch.cuda.is_available():
                inputs = {k: v.to('cuda:0') for k, v in inputs.items()}

            # Generate streaming response token by token
            with torch.no_grad():
                generated_ids = inputs['input_ids']

                for step in range(800):  # Max 800 tokens for comprehensive analysis
                    # Generate next token
                    outputs = self.model(
                        input_ids=generated_ids,
                        attention_mask=torch.ones_like(generated_ids),
                        use_cache=True
                    )

                    # Get logits for next token prediction
                    next_token_logits = outputs.logits[:, -1, :] / 0.7  # Temperature scaling

                    # Apply top-p sampling for better quality
                    sorted_logits, sorted_indices = torch.sort(next_token_logits, descending=True)
                    cumulative_probs = torch.cumsum(torch.softmax(sorted_logits, dim=-1), dim=-1)
                    sorted_indices_to_remove = cumulative_probs > 0.9
                    sorted_indices_to_remove[..., 1:] = sorted_indices_to_remove[..., :-1].clone()
                    sorted_indices_to_remove[..., 0] = 0
                    indices_to_remove = sorted_indices[sorted_indices_to_remove]
                    next_token_logits[:, indices_to_remove] = -float('Inf')

                    # Sample next token
                    next_token_probs = torch.softmax(next_token_logits, dim=-1)
                    next_token = torch.multinomial(next_token_probs, num_samples=1)

                    # Decode and output token
                    token_text = self.tokenizer.decode(next_token[0], skip_special_tokens=True)
                    print(token_text, end='', flush=True)

                    # Append token to generated sequence
                    generated_ids = torch.cat([generated_ids, next_token], dim=-1)

                    # Stop if EOS token or end of analysis
                    if next_token.item() == self.tokenizer.eos_token_id:
                        break

                    # Streaming delay for real-time effect
                    time.sleep(0.02)  # 50 tokens per second

        except Exception as e:
            print(f"TSLAM inference error: {e}", file=sys.stderr)
            print("Falling back to rule-based recommendations", file=sys.stderr)
            # Fall back to rule-based recommendations
            recommendation = self.get_rule_based_recommendations(anomaly_id, description)
            words = recommendation.split()
            for word in words:
                print(word + ' ', end='', flush=True)
                time.sleep(0.05)
            print()

    def generate_fallback_message(self, anomaly_id, description):
        """Generate fallback message - now uses rule-based recommendations"""
        print("Using rule-based troubleshooting recommendations", file=sys.stderr)
        recommendation = self.get_rule_based_recommendations(anomaly_id, description)
        
        # Stream the recommendation
        words = recommendation.split()
        for word in words:
            print(word + ' ', end='', flush=True)
            time.sleep(0.05)
        print()

def main():
    if len(sys.argv) != 3:
        print("Usage: python tslam_service.py <anomaly_id> <description>", file=sys.stderr)
        sys.exit(1)

    anomaly_id = sys.argv[1]
    description = sys.argv[2]

    service = TSLAMService()
    service.generate_streaming_response(anomaly_id, description)

if __name__ == "__main__":
    main()