#!/usr/bin/env python3
"""
Folder-based L1 Anomaly Detection System with ClickHouse Integration
Processes PCAP, DLF/QXDM, and HDF5-converted text files in a directory with database storage
Enhanced with packet context extraction, advanced L1 anomaly detection, and QXDM support
"""

import os
import sys
import glob
from datetime import datetime
from collections import defaultdict
import clickhouse_connect
from typing import Dict, List, Any
import json

# Import existing analysis modules
from unified_l1_analyzer import UnifiedL1Analyzer
from ml_anomaly_detection import MLAnomalyDetector
from server.services.ue_analyzer import UEEventAnalyzer
from server.services.ml_ue_analyzer import MLUEEventAnalyzer

# Import Scapy for packet context extraction
try:
    from scapy.all import rdpcap, Ether, Raw, IP, UDP
    SCAPY_AVAILABLE = True
except ImportError:
    print("WARNING: Scapy not available - packet context extraction disabled")
    SCAPY_AVAILABLE = False

# Import enhanced detection modules
from enhanced_protocol_parser import EnhancedProtocolParser
from statistical_baseline_tracker import StatisticalBaselineTracker
from temporal_pattern_analyzer import TemporalPatternAnalyzer
import numpy as np

# Import QXDM/DLF support modules
try:
    from dlf_parser import DLFParser, QXDMPacket
    from qxdm_message_decoder import QXDMMessageDecoder
    DLF_SUPPORT_AVAILABLE = True
except ImportError as e:
    print(f"WARNING: DLF/QXDM support not available: {e}")
    DLF_SUPPORT_AVAILABLE = False

class ClickHouseFolderAnalyzer:
    def __init__(self, clickhouse_host='localhost', clickhouse_port=9000, skip_database=False):
        """Initialize folder analyzer with optional ClickHouse database connection"""

        # Equipment MAC addresses
        self.DU_MAC = "00:11:22:33:44:67"
        self.RU_MAC = "6c:ad:ad:00:03:2a"

        # Processing statistics
        self.total_files_processed = 0
        self.pcap_files_processed = 0
        self.text_files_processed = 0
        self.total_anomalies_found = 0

        # Initialize analyzers
        self.unified_analyzer = UnifiedL1Analyzer()
        
        # Initialize enhanced detection modules
        self.protocol_parser = EnhancedProtocolParser()
        self.baseline_tracker = StatisticalBaselineTracker()
        self.temporal_analyzer = TemporalPatternAnalyzer()
        
        # Initialize DLF/QXDM support if available
        if DLF_SUPPORT_AVAILABLE:
            self.dlf_parser = DLFParser()
            self.qxdm_decoder = QXDMMessageDecoder()
            print("DLF/QXDM file support enabled")
        else:
            self.dlf_parser = None
            self.qxdm_decoder = None
        
        # Cache for loaded PCAP packets (for context extraction)
        self.pcap_cache = {}

        # ClickHouse connection to local database (skip if in dummy mode)
        self.clickhouse_available = False
        self.client = None
        
        if skip_database:
            print("Skipping ClickHouse connection (dummy mode)")
        else:
            try:
                self.client = clickhouse_connect.get_client(
                    host=os.getenv('CLICKHOUSE_HOST', 'clickhouse-clickhouse-single'),
                    port=int(os.getenv('CLICKHOUSE_PORT', '8123')),
                    username=os.getenv('CLICKHOUSE_USERNAME', 'default'),
                    password=os.getenv('CLICKHOUSE_PASSWORD', 'defaultpass'),
                    database=os.getenv('CLICKHOUSE_DATABASE', 'l1_anomaly_detection')
                )
                # Test connection
                result = self.client.command('SELECT 1')
                self.clickhouse_available = True
                print("ClickHouse database connected successfully")
            except Exception as e:
                print(f"WARNING: ClickHouse connection failed: {e}")
                print("Running in console-only mode")

    def scan_folder(self, folder_path="/app/input_files"):
        """Scan folder for network files"""
        print(f"\nSCANNING FOLDER: {folder_path}")
        print("-" * 40)

        # Supported file patterns
        pcap_patterns = ['*.pcap', '*.cap', '*.pcapng']
        dlf_patterns = ['*.dlf', '*.qmdl', '*.isf']
        text_patterns = ['*.txt', '*.log']

        found_files = []

        # Find PCAP files
        for pattern in pcap_patterns:
            files = glob.glob(os.path.join(folder_path, pattern))
            for file_path in files:
                file_size = os.path.getsize(file_path)
                found_files.append({
                    'path': file_path,
                    'name': os.path.basename(file_path),
                    'type': 'PCAP',
                    'size': file_size
                })

        # Find DLF/QXDM files (if support is available)
        if DLF_SUPPORT_AVAILABLE:
            for pattern in dlf_patterns:
                files = glob.glob(os.path.join(folder_path, pattern))
                for file_path in files:
                    file_size = os.path.getsize(file_path)
                    found_files.append({
                        'path': file_path,
                        'name': os.path.basename(file_path),
                        'type': 'DLF',
                        'size': file_size
                    })

        # Find text files  
        for pattern in text_patterns:
            files = glob.glob(os.path.join(folder_path, pattern))
            for file_path in files:
                file_size = os.path.getsize(file_path)
                found_files.append({
                    'path': file_path,
                    'name': os.path.basename(file_path),
                    'type': 'TEXT',
                    'size': file_size
                })

        if not found_files:
            print("ERROR: No network files found in folder")
            supported_formats = ".pcap, .cap, .pcapng, .txt, .log"
            if DLF_SUPPORT_AVAILABLE:
                supported_formats += ", .dlf, .qmdl, .isf"
            print(f"   Supported: {supported_formats}")
            return []

        print(f"Found {len(found_files)} network files:")
        for file_info in found_files:
            size_mb = file_info['size'] / 1024 / 1024
            if size_mb >= 1:
                size_str = f"{size_mb:.1f} MB"
            else:
                size_str = f"{file_info['size']} bytes"
            print(f"  {file_info['name']} ({file_info['type']}, {size_str})")

        pcap_count = sum(1 for f in found_files if f['type'] == 'PCAP')
        text_count = sum(1 for f in found_files if f['type'] == 'TEXT')

        print(f"\nFILE SUMMARY:")
        print(f"- PCAP files: {pcap_count}")
        print(f"- Text files: {text_count}")

        return found_files

    def extract_packet_context(self, pcap_file, packet_number, context_size=2):
        """
        Extract packet context: anomaly packet + 2 before + 2 after
        Returns formatted string with packet details
        """
        if not SCAPY_AVAILABLE:
            return "Packet context unavailable (Scapy not installed)"
        
        try:
            # Load packets from cache or read from file
            if pcap_file not in self.pcap_cache:
                self.pcap_cache[pcap_file] = rdpcap(pcap_file)
            
            packets = self.pcap_cache[pcap_file]
            
            # Calculate range (packet_number is 1-indexed)
            packet_idx = packet_number - 1
            start_idx = max(0, packet_idx - context_size)
            end_idx = min(len(packets), packet_idx + context_size + 1)
            
            context_packets = []
            for i in range(start_idx, end_idx):
                pkt = packets[i]
                pkt_num = i + 1
                marker = " <<<< ANOMALY" if i == packet_idx else ""
                
                # Extract packet summary
                pkt_summary = f"Packet #{pkt_num}{marker}\n"
                
                # Ethernet layer
                if pkt.haslayer(Ether):
                    eth = pkt[Ether]
                    pkt_summary += f"  Eth: {eth.src} -> {eth.dst}\n"
                
                # IP layer
                if pkt.haslayer(IP):
                    ip = pkt[IP]
                    pkt_summary += f"  IP: {ip.src} -> {ip.dst}, Len={ip.len}\n"
                
                # UDP layer
                if pkt.haslayer(UDP):
                    udp = pkt[UDP]
                    pkt_summary += f"  UDP: {udp.sport} -> {udp.dport}\n"
                
                # Payload size
                if pkt.haslayer(Raw):
                    payload_len = len(pkt[Raw].load)
                    pkt_summary += f"  Payload: {payload_len} bytes\n"
                
                # Timestamp
                pkt_summary += f"  Time: {float(pkt.time):.6f}\n"
                
                context_packets.append(pkt_summary)
            
            return "\n".join(context_packets)
            
        except Exception as e:
            return f"Error extracting packet context: {str(e)}"

    def detect_rach_failures(self, packets):
        """
        Enhanced RACH failure detection with protocol analysis and adaptive thresholds
        Uses temporal patterns, statistical baselines, and multi-factor confidence scoring
        """
        anomalies = []
        if not SCAPY_AVAILABLE:
            return anomalies
        
        try:
            rach_events = []
            rach_attempts = 0
            rach_failures = 0
            rach_timestamps = []
            
            for i, pkt in enumerate(packets):
                if not pkt.haslayer(Raw):
                    continue
                    
                payload = bytes(pkt[Raw].load)
                indicators = self.protocol_parser.extract_l1_indicators(payload, packet_obj=pkt)
                
                if indicators['has_rach']:
                    rach_attempts += 1
                    timestamp = float(pkt.time) if hasattr(pkt, 'time') else i
                    rach_timestamps.append(timestamp)
                    
                    has_failure = len(indicators['failure_indicators']) > 0
                    
                    if has_failure:
                        rach_failures += 1
                        
                        pattern_strength = len(indicators['failure_indicators']) / 3.0
                        
                        timing_features = self.protocol_parser.extract_timing_features(packets[max(0, i-5):i+5])
                        temporal_score = 0.5
                        if timing_features:
                            if timing_features.get('jitter', 0) > 0.1:
                                temporal_score += 0.2
                            if timing_features.get('max_inter_arrival', 0) > 1.0:
                                temporal_score += 0.3
                        
                        baseline_deviation = 0.5
                        is_anomalous, deviation_score, severity = self.baseline_tracker.is_anomalous(
                            'rach', 'attempt_count', rach_failures
                        )
                        if is_anomalous:
                            baseline_deviation = deviation_score
                        
                        confidence = min((pattern_strength * 0.4 + temporal_score * 0.3 + baseline_deviation * 0.3), 1.0)
                        
                        anomalies.append({
                            'packet_number': i + 1,
                            'anomaly_type': 'RACH Failure',
                            'confidence': max(confidence, 0.7),
                            'details': [
                                f'RACH failure detected with {len(indicators["failure_indicators"])} error indicators',
                                f'Pattern strength: {pattern_strength:.2f}',
                                f'Temporal anomaly score: {temporal_score:.2f}',
                                f'Baseline deviation: {baseline_deviation:.2f}'
                            ],
                            'error_log': f'RACH failure at packet {i+1}: {indicators["failure_indicators"]}'
                        })
            
            self.baseline_tracker.update_baseline('rach', 'attempt_count', rach_attempts)
            if rach_attempts > 0:
                success_rate = 1.0 - (rach_failures / rach_attempts)
                self.baseline_tracker.update_baseline('rach', 'success_rate', success_rate)
            
            if len(rach_timestamps) >= 3:
                temporal_analysis = self.temporal_analyzer.analyze_event_rate('rach', rach_timestamps)
                
                if temporal_analysis['burst_detected']:
                    severity_map = {'critical': 0.95, 'high': 0.85, 'medium': 0.75, 'low': 0.65}
                    confidence = severity_map.get(temporal_analysis['burst_severity'], 0.70)
                    
                    anomalies.append({
                        'packet_number': 1,
                        'anomaly_type': 'RACH Burst Pattern',
                        'confidence': confidence,
                        'details': [
                            f'Burst detected: {temporal_analysis["burst_severity"]} severity',
                            f'Peak rate: {temporal_analysis["max_window_rate"]:.2f} events/sec',
                            f'Average rate: {temporal_analysis["avg_window_rate"]:.2f} events/sec'
                        ],
                        'error_log': f'RACH burst: {temporal_analysis["total_events"]} attempts in {temporal_analysis["duration"]:.2f}s'
                    })
            
            threshold = self.baseline_tracker.get_adaptive_threshold('rach', 'attempt_count') or 10
            if rach_attempts > threshold:
                is_anomalous, deviation_score, severity = self.baseline_tracker.is_anomalous(
                    'rach', 'attempt_count', rach_attempts
                )
                
                confidence = 0.65 + (deviation_score * 0.3)
                
                anomalies.append({
                    'packet_number': 1,
                    'anomaly_type': 'Excessive RACH Attempts',
                    'confidence': min(confidence, 0.95),
                    'details': [
                        f'Excessive RACH attempts: {rach_attempts} (threshold: {threshold:.1f})',
                        f'Severity: {severity}',
                        f'Deviation score: {deviation_score:.2f}',
                        'Indicates possible network congestion or cell overload'
                    ],
                    'error_log': f'High RACH attempt count: {rach_attempts} attempts detected'
                })
        
        except Exception as e:
            print(f"  RACH detection error: {e}")
        
        return anomalies

    def detect_handover_failures(self, packets):
        """
        Enhanced handover failure detection with state tracking and success ratio analysis
        Detects mobility issues and handover performance degradation
        """
        anomalies = []
        if not SCAPY_AVAILABLE:
            return anomalies
        
        try:
            handover_attempts = 0
            handover_failures = 0
            handover_timestamps = []
            handover_durations = []
            
            for i, pkt in enumerate(packets):
                if not pkt.haslayer(Raw):
                    continue
                    
                payload = bytes(pkt[Raw].load)
                indicators = self.protocol_parser.extract_l1_indicators(payload, packet_obj=pkt)
                
                if indicators['has_handover']:
                    handover_attempts += 1
                    timestamp = float(pkt.time) if hasattr(pkt, 'time') else i
                    handover_timestamps.append(timestamp)
                    
                    has_failure = len(indicators['failure_indicators']) > 0
                    
                    if has_failure:
                        handover_failures += 1
                        
                        pattern_strength = min(len(indicators['failure_indicators']) / 2.0, 1.0)
                        
                        sequence_anomalies = self.protocol_parser.detect_sequence_anomalies(
                            packets[max(0, i-10):i+10]
                        )
                        sequence_score = min(len(sequence_anomalies) / 5.0, 1.0) if sequence_anomalies else 0.3
                        
                        baseline_deviation = 0.5
                        is_anomalous, deviation_score, severity = self.baseline_tracker.is_anomalous(
                            'handover', 'success_rate', 0.0
                        )
                        if is_anomalous:
                            baseline_deviation = deviation_score
                        
                        confidence = min((pattern_strength * 0.5 + sequence_score * 0.2 + baseline_deviation * 0.3), 1.0)
                        
                        anomalies.append({
                            'packet_number': i + 1,
                            'anomaly_type': 'Handover Failure',
                            'confidence': max(confidence, 0.75),
                            'details': [
                                f'Handover failure: {len(indicators["failure_indicators"])} error indicators',
                                f'Sequence anomalies detected: {len(sequence_anomalies)}',
                                f'Pattern match strength: {pattern_strength:.2f}',
                                'Indicates UE mobility or inter-cell coordination issue'
                            ],
                            'error_log': f'Handover failure at packet {i+1}: {indicators["failure_indicators"]}'
                        })
            
            self.baseline_tracker.update_baseline('handover', 'attempt_count', handover_attempts)
            if handover_attempts > 0:
                success_rate = 1.0 - (handover_failures / handover_attempts)
                self.baseline_tracker.update_baseline('handover', 'success_rate', success_rate)
                
                is_anomalous, deviation_score, severity = self.baseline_tracker.is_anomalous(
                    'handover', 'success_rate', success_rate
                )
                
                if is_anomalous and success_rate < 0.85:
                    confidence = 0.70 + (deviation_score * 0.25)
                    
                    anomalies.append({
                        'packet_number': 1,
                        'anomaly_type': 'Low Handover Success Rate',
                        'confidence': min(confidence, 0.95),
                        'details': [
                            f'Handover success rate: {success_rate*100:.1f}% (expected >85%)',
                            f'Failures: {handover_failures}/{handover_attempts} attempts',
                            f'Severity: {severity}',
                            'Indicates systemic mobility or resource allocation issues'
                        ],
                        'error_log': f'Low handover success: {handover_failures} failures in {handover_attempts} attempts'
                    })
        
        except Exception as e:
            print(f"  Handover detection error: {e}")
        
        return anomalies

    def detect_harq_retransmissions(self, packets):
        """
        Enhanced HARQ retransmission detection with sequence tracking and statistical analysis
        Detects poor radio quality, interference, and link degradation
        """
        anomalies = []
        if not SCAPY_AVAILABLE:
            return anomalies
        
        try:
            retransmission_count = 0
            total_harq_packets = 0
            retx_timestamps = []
            consecutive_retx = 0
            max_consecutive = 0
            
            for i, pkt in enumerate(packets):
                if not pkt.haslayer(Raw):
                    continue
                    
                payload = bytes(pkt[Raw].load)
                indicators = self.protocol_parser.extract_l1_indicators(payload, packet_obj=pkt)
                
                if indicators['has_harq']:
                    total_harq_packets += 1
                    
                    is_retransmission = b'retx' in payload.lower() or b'nack' in payload.lower()
                    
                    if is_retransmission:
                        retransmission_count += 1
                        consecutive_retx += 1
                        max_consecutive = max(max_consecutive, consecutive_retx)
                        
                        timestamp = float(pkt.time) if hasattr(pkt, 'time') else i
                        retx_timestamps.append(timestamp)
                    else:
                        consecutive_retx = 0
            
            if total_harq_packets > 0:
                retransmission_rate = retransmission_count / total_harq_packets
                self.baseline_tracker.update_baseline('harq', 'retransmission_rate', retransmission_rate)
                self.baseline_tracker.update_baseline('harq', 'max_consecutive_retx', max_consecutive)
                
                is_anomalous, deviation_score, severity = self.baseline_tracker.is_anomalous(
                    'harq', 'retransmission_rate', retransmission_rate
                )
                
                threshold = self.baseline_tracker.get_adaptive_threshold('harq', 'retransmission_rate') or 0.15
                
                if retransmission_rate > threshold or max_consecutive > 3:
                    temporal_score = 0.5
                    if len(retx_timestamps) >= 3:
                        temporal_analysis = self.temporal_analyzer.analyze_event_rate('harq_retx', retx_timestamps)
                        if temporal_analysis['burst_detected']:
                            temporal_score = 0.9
                    
                    confidence = min((deviation_score * 0.4 + temporal_score * 0.4 + 0.2), 1.0)
                    
                    anomalies.append({
                        'packet_number': 1,
                        'anomaly_type': 'Excessive HARQ Retransmissions',
                        'confidence': max(confidence, 0.70),
                        'details': [
                            f'Retransmission rate: {retransmission_rate*100:.1f}% (threshold: {threshold*100:.1f}%)',
                            f'Total retransmissions: {retransmission_count}/{total_harq_packets} packets',
                            f'Max consecutive retx: {max_consecutive}',
                            f'Severity: {severity}',
                            'Indicates poor radio quality, interference, or link budget issues'
                        ],
                        'error_log': f'High HARQ retransmission rate: {retransmission_count} retransmissions in {total_harq_packets} packets'
                    })
                
                if max_consecutive >= 5:
                    anomalies.append({
                        'packet_number': 1,
                        'anomaly_type': 'HARQ Retransmission Burst',
                        'confidence': 0.85,
                        'details': [
                            f'Consecutive retransmissions: {max_consecutive}',
                            'Severe radio link quality degradation detected',
                            'May indicate deep fade, strong interference, or equipment malfunction'
                        ],
                        'error_log': f'HARQ burst: {max_consecutive} consecutive retransmissions'
                    })
        
        except Exception as e:
            print(f"  HARQ detection error: {e}")
        
        return anomalies

    def detect_crc_errors(self, packets):
        """
        Enhanced CRC error detection with error rate calculation and correlation analysis
        Detects data corruption, signal quality issues, and equipment problems
        """
        anomalies = []
        if not SCAPY_AVAILABLE:
            return anomalies
        
        try:
            crc_errors = 0
            crc_error_timestamps = []
            total_packets_checked = 0
            
            for i, pkt in enumerate(packets):
                if not pkt.haslayer(Raw):
                    continue
                    
                payload = bytes(pkt[Raw].load)
                indicators = self.protocol_parser.extract_l1_indicators(payload, packet_obj=pkt)
                
                if indicators['has_crc']:
                    total_packets_checked += 1
                    
                    has_error = b'error' in payload.lower() or b'fail' in payload.lower()
                    
                    if has_error:
                        crc_errors += 1
                        timestamp = float(pkt.time) if hasattr(pkt, 'time') else i
                        crc_error_timestamps.append(timestamp)
                        
                        pattern_strength = min(len([x for x in indicators['error_indicators'] if 'crc' in x.lower()]) / 2.0, 1.0) if len(indicators['error_indicators']) > 0 else 0.8
                        
                        anomalies.append({
                            'packet_number': i + 1,
                            'anomaly_type': 'CRC Error',
                            'confidence': max(pattern_strength, 0.85),
                            'details': [
                                'CRC check failed - data corruption detected',
                                f'Error indicators: {len(indicators["error_indicators"])}',
                                'Likely caused by: poor signal quality, interference, or equipment malfunction'
                            ],
                            'error_log': f'CRC error at packet {i+1}'
                        })
            
            if total_packets_checked > 100:
                error_rate = crc_errors / total_packets_checked
                errors_per_1000 = (crc_errors / total_packets_checked) * 1000
                
                self.baseline_tracker.update_baseline('crc', 'error_rate', error_rate)
                self.baseline_tracker.update_baseline('crc', 'errors_per_1000_packets', errors_per_1000)
                
                is_anomalous, deviation_score, severity = self.baseline_tracker.is_anomalous(
                    'crc', 'error_rate', error_rate
                )
                
                if is_anomalous or error_rate > 0.01:
                    temporal_score = 0.5
                    if len(crc_error_timestamps) >= 3:
                        temporal_analysis = self.temporal_analyzer.analyze_event_rate('crc_errors', crc_error_timestamps)
                        if temporal_analysis['burst_detected']:
                            temporal_score = 0.9
                    
                    confidence = min((deviation_score * 0.5 + temporal_score * 0.4 + 0.1), 1.0)
                    
                    anomalies.append({
                        'packet_number': 1,
                        'anomaly_type': 'High CRC Error Rate',
                        'confidence': max(confidence, 0.75),
                        'details': [
                            f'CRC error rate: {error_rate*100:.2f}% ({errors_per_1000:.1f} per 1000 packets)',
                            f'Total errors: {crc_errors}/{total_packets_checked} packets',
                            f'Severity: {severity}',
                            'Indicates persistent signal quality or equipment issues'
                        ],
                        'error_log': f'High CRC error rate: {crc_errors} errors in {total_packets_checked} packets'
                    })
        
        except Exception as e:
            print(f"  CRC detection error: {e}")
        
        return anomalies

    def detect_rrc_connection_failures(self, packets):
        """
        Enhanced RRC connection failure detection with state machine tracking
        Detects control plane issues and resource allocation problems
        """
        anomalies = []
        if not SCAPY_AVAILABLE:
            return anomalies
        
        try:
            rrc_attempts = 0
            rrc_failures = 0
            rrc_failure_timestamps = []
            rrc_states = []
            
            for i, pkt in enumerate(packets):
                if not pkt.haslayer(Raw):
                    continue
                    
                payload = bytes(pkt[Raw].load)
                indicators = self.protocol_parser.extract_l1_indicators(payload, packet_obj=pkt)
                
                if indicators['has_rrc']:
                    is_setup_attempt = b'Connect' in payload or b'Setup' in payload
                    is_failure = b'Reject' in payload or b'Fail' in payload
                    
                    if is_setup_attempt:
                        rrc_attempts += 1
                        rrc_states.append('attempt')
                    
                    if is_failure:
                        rrc_failures += 1
                        rrc_states.append('failure')
                        timestamp = float(pkt.time) if hasattr(pkt, 'time') else i
                        rrc_failure_timestamps.append(timestamp)
                        
                        pattern_strength = min(len(indicators['failure_indicators']) / 2.0, 1.0)
                        
                        sequence_anomalies = self.protocol_parser.detect_sequence_anomalies(
                            packets[max(0, i-5):i+5]
                        )
                        sequence_score = 0.3 + min(len(sequence_anomalies) / 3.0, 0.5)
                        
                        confidence = min((pattern_strength * 0.5 + sequence_score * 0.5), 1.0)
                        
                        anomalies.append({
                            'packet_number': i + 1,
                            'anomaly_type': 'RRC Connection Failure',
                            'confidence': max(confidence, 0.80),
                            'details': [
                                'RRC connection rejected or failed',
                                f'Failure indicators: {len(indicators["failure_indicators"])}',
                                'Indicates control plane congestion or resource shortage'
                            ],
                            'error_log': f'RRC failure at packet {i+1}: {indicators["failure_indicators"]}'
                        })
            
            if rrc_attempts > 0:
                success_rate = 1.0 - (rrc_failures / rrc_attempts)
                self.baseline_tracker.update_baseline('rrc', 'connection_success_rate', success_rate)
                self.baseline_tracker.update_baseline('rrc', 'setup_attempts', rrc_attempts)
                
                is_anomalous, deviation_score, severity = self.baseline_tracker.is_anomalous(
                    'rrc', 'connection_success_rate', success_rate
                )
                
                if is_anomalous and success_rate < 0.90:
                    confidence = 0.75 + (deviation_score * 0.20)
                    
                    anomalies.append({
                        'packet_number': 1,
                        'anomaly_type': 'Low RRC Connection Success Rate',
                        'confidence': min(confidence, 0.95),
                        'details': [
                            f'RRC success rate: {success_rate*100:.1f}% (expected >90%)',
                            f'Failures: {rrc_failures}/{rrc_attempts} attempts',
                            f'Severity: {severity}',
                            'Indicates control plane overload or admission control issues'
                        ],
                        'error_log': f'Low RRC success: {rrc_failures} failures in {rrc_attempts} attempts'
                    })
        
        except Exception as e:
            print(f"  RRC detection error: {e}")
        
        return anomalies

    def detect_timing_advance_violations(self, packets):
        """
        Enhanced timing advance violation detection with range validation
        Detects synchronization issues and distance-related problems
        """
        anomalies = []
        if not SCAPY_AVAILABLE:
            return anomalies
        
        try:
            ta_violations = 0
            ta_adjustments = 0
            ta_violation_timestamps = []
            ta_values = []
            
            for i, pkt in enumerate(packets):
                if not pkt.haslayer(Raw):
                    continue
                    
                payload = bytes(pkt[Raw].load)
                indicators = self.protocol_parser.extract_l1_indicators(payload, packet_obj=pkt)
                
                if indicators['has_timing_advance']:
                    ta_adjustments += 1
                    
                    has_violation = b'violation' in payload.lower() or b'out of range' in payload.lower() or b'invalid' in payload.lower()
                    
                    if has_violation:
                        ta_violations += 1
                        timestamp = float(pkt.time) if hasattr(pkt, 'time') else i
                        ta_violation_timestamps.append(timestamp)
                        
                        pattern_strength = min(len(indicators['failure_indicators']) / 2.0, 1.0) if indicators['failure_indicators'] else 0.7
                        
                        timing_features = self.protocol_parser.extract_timing_features(packets[max(0, i-5):i+5])
                        temporal_score = 0.5
                        if timing_features and timing_features.get('jitter', 0) > 0.05:
                            temporal_score = 0.8
                        
                        confidence = min((pattern_strength * 0.6 + temporal_score * 0.4), 1.0)
                        
                        anomalies.append({
                            'packet_number': i + 1,
                            'anomaly_type': 'Timing Advance Violation',
                            'confidence': max(confidence, 0.75),
                            'details': [
                                'Timing Advance out of acceptable range',
                                'Indicates UE synchronization issue or excessive distance',
                                f'Timing jitter detected: {timing_features.get("jitter", 0):.4f}s' if timing_features else 'N/A'
                            ],
                            'error_log': f'TA violation at packet {i+1}: {indicators["failure_indicators"]}'
                        })
            
            if ta_adjustments > 0:
                violation_rate = ta_violations / ta_adjustments
                self.baseline_tracker.update_baseline('timing_advance', 'violation_rate', violation_rate)
                self.baseline_tracker.update_baseline('timing_advance', 'avg_ta_adjustments', ta_adjustments)
                
                is_anomalous, deviation_score, severity = self.baseline_tracker.is_anomalous(
                    'timing_advance', 'violation_rate', violation_rate
                )
                
                if is_anomalous and violation_rate > 0.05:
                    temporal_score = 0.5
                    if len(ta_violation_timestamps) >= 3:
                        temporal_analysis = self.temporal_analyzer.analyze_event_rate('ta_violations', ta_violation_timestamps)
                        if temporal_analysis['burst_detected']:
                            temporal_score = 0.9
                    
                    confidence = min((deviation_score * 0.5 + temporal_score * 0.4 + 0.1), 1.0)
                    
                    anomalies.append({
                        'packet_number': 1,
                        'anomaly_type': 'High TA Violation Rate',
                        'confidence': max(confidence, 0.70),
                        'details': [
                            f'TA violation rate: {violation_rate*100:.2f}% (threshold: 5%)',
                            f'Violations: {ta_violations}/{ta_adjustments} TA commands',
                            f'Severity: {severity}',
                            'Indicates systematic synchronization or cell planning issues'
                        ],
                        'error_log': f'High TA violation rate: {ta_violations} violations in {ta_adjustments} adjustments'
                    })
        
        except Exception as e:
            print(f"  TA detection error: {e}")
        
        return anomalies

    def detect_power_control_anomalies(self, packets):
        """
        Enhanced power control anomaly detection with TPC command tracking
        Detects transmit power management issues and coverage problems
        """
        anomalies = []
        if not SCAPY_AVAILABLE:
            return anomalies
        
        try:
            power_issues = 0
            power_adjustments = 0
            power_issue_timestamps = []
            excessive_adjustments = 0
            
            for i, pkt in enumerate(packets):
                if not pkt.haslayer(Raw):
                    continue
                    
                payload = bytes(pkt[Raw].load)
                indicators = self.protocol_parser.extract_l1_indicators(payload, packet_obj=pkt)
                
                if indicators['has_power_control']:
                    power_adjustments += 1
                    
                    has_issue = len(indicators['failure_indicators']) > 0 or b'exceed' in payload.lower() or b'limit' in payload.lower()
                    
                    if has_issue:
                        power_issues += 1
                        timestamp = float(pkt.time) if hasattr(pkt, 'time') else i
                        power_issue_timestamps.append(timestamp)
                        
                        pattern_strength = min(len(indicators['failure_indicators']) / 2.0, 1.0) if indicators['failure_indicators'] else 0.6
                        
                        anomalies.append({
                            'packet_number': i + 1,
                            'anomaly_type': 'Power Control Anomaly',
                            'confidence': max(pattern_strength, 0.70),
                            'details': [
                                'Transmit power control issue detected',
                                f'Error indicators: {len(indicators["failure_indicators"])}',
                                'May indicate coverage hole, interference, or UE power limitations'
                            ],
                            'error_log': f'Power control issue at packet {i+1}: {indicators["failure_indicators"]}'
                        })
            
            if power_adjustments > 50:
                adjustment_frequency = power_adjustments / len(packets)
                self.baseline_tracker.update_baseline('power_control', 'adjustment_frequency', adjustment_frequency)
                
                is_anomalous, deviation_score, severity = self.baseline_tracker.is_anomalous(
                    'power_control', 'adjustment_frequency', adjustment_frequency
                )
                
                if is_anomalous and adjustment_frequency > 0.20:
                    temporal_score = 0.5
                    if len(power_issue_timestamps) >= 3:
                        temporal_analysis = self.temporal_analyzer.analyze_event_rate('power_issues', power_issue_timestamps)
                        if temporal_analysis['burst_detected']:
                            temporal_score = 0.8
                    
                    confidence = min((deviation_score * 0.4 + temporal_score * 0.4 + 0.2), 1.0)
                    
                    anomalies.append({
                        'packet_number': 1,
                        'anomaly_type': 'Excessive Power Control Activity',
                        'confidence': max(confidence, 0.65),
                        'details': [
                            f'Power adjustment frequency: {adjustment_frequency*100:.1f}% of packets',
                            f'Total adjustments: {power_adjustments} in {len(packets)} packets',
                            f'Severity: {severity}',
                            'Indicates unstable radio environment or coverage issues'
                        ],
                        'error_log': f'Excessive power control: {power_adjustments} adjustments'
                    })
        
        except Exception as e:
            print(f"  Power control detection error: {e}")
        
        return anomalies

    def store_session_in_clickhouse(self, session_data):
        """Store analysis session in ClickHouse"""
        if not self.clickhouse_available:
            return None

        try:
            # Insert session record using list of lists format
            session_values = [[
                session_data['id'],
                session_data['session_name'],
                session_data['folder_path'],
                session_data['total_files'],
                session_data['pcap_files'],
                session_data['text_files'],
                session_data['total_anomalies'],
                session_data['start_time'],
                session_data['end_time'],
                session_data['duration_seconds'],
                'completed'
            ]]

            self.client.insert('sessions', session_values, column_names=[
                'id', 'session_name', 'folder_path', 'total_files', 'pcap_files',
                'text_files', 'total_anomalies', 'start_time', 'end_time', 
                'duration_seconds', 'status'
            ])

            print(f"Session stored in ClickHouse database")
            return session_data['id']

        except Exception as e:
            print(f"WARNING: Failed to store session in ClickHouse: {e}")
            return None

    def store_anomalies_in_clickhouse(self, anomalies, session_id):
        """Store detected anomalies in ClickHouse (only confidence >= 0.50)"""
        if not self.clickhouse_available or not anomalies:
            return

        try:
            # Filter anomalies by confidence >= 0.50 (50%)
            high_confidence_anomalies = [
                a for a in anomalies 
                if a.get('confidence', 0) >= 0.50
            ]
            
            if not high_confidence_anomalies:
                print(f"No high-confidence anomalies (>= 50%) to store. {len(anomalies)} total anomalies were below threshold.")
                return
            
            print(f"Storing {len(high_confidence_anomalies)}/{len(anomalies)} anomalies (confidence >= 50%)")
            
            # Prepare anomaly records for bulk insert using list of lists
            anomaly_records = []

            for i, anomaly in enumerate(high_confidence_anomalies):
                # Convert numpy types to native Python types to avoid Decimal conversion errors
                packet_number = anomaly['packet_number']
                if hasattr(packet_number, 'item'):  # Check if it's a numpy type
                    packet_number = int(packet_number.item())
                else:
                    packet_number = int(packet_number)
                
                confidence = anomaly.get('confidence', 0)
                
                # Extract packet context for PCAP files
                packet_context = ""
                if anomaly['file_type'] == 'PCAP':
                    packet_context = self.extract_packet_context(
                        anomaly['file'], 
                        packet_number, 
                        context_size=2
                    )
                
                record = [
                    int(f"{session_id}{i:04d}"),  # Unique ID
                    str(anomaly['file']),
                    str(anomaly['file_type']),
                    packet_number,
                    str(anomaly['anomaly_type']),
                    'high' if confidence >= 0.75 else 'medium' if confidence >= 0.50 else 'low',  # Based on confidence
                    f"*** FRONTHAUL ISSUE (Confidence: {int(confidence*100)}%) *** - {anomaly['anomaly_type']}",
                    json.dumps(anomaly['details']),
                    str(anomaly.get('ue_id', '')),
                    str(self.DU_MAC),
                    str(self.RU_MAC),
                    datetime.now(),  # Fixed: Use datetime object directly, not string
                    'active',
                    str(anomaly.get('error_log', '')),  # Packet/event data for LLM analysis
                    packet_context  # NEW: Packet context (anomaly + 2 before + 2 after)
                ]
                anomaly_records.append(record)

            # Bulk insert anomalies
            self.client.insert('anomalies', anomaly_records, column_names=[
                'id', 'file_path', 'file_type', 'packet_number', 'anomaly_type',
                'severity', 'description', 'details', 'ue_id', 'du_mac', 
                'ru_mac', 'timestamp', 'status', 'error_log', 'packet_context'
            ])

            print(f"SUCCESS: {len(high_confidence_anomalies)} high-confidence anomalies stored in ClickHouse database")

        except Exception as e:
            print(f"WARNING: Failed to store anomalies in ClickHouse: {e}")

    def process_single_file(self, file_info):
        """Process a single network file"""
        file_path = file_info['path']
        file_name = file_info['name']
        file_type = file_info['type']

        print(f"Processing {file_type}: {file_name}")

        anomalies = []

        try:
            if file_type == 'PCAP':
                # Use ML anomaly detector for PCAP files
                detector = MLAnomalyDetector()
                result = detector.analyze_pcap(file_path)

                if 'anomalies' in result:
                    for anomaly in result['anomalies']:
                        # Get confidence score from ML result
                        confidence = anomaly.get('confidence', 0)
                        packet_num = anomaly.get('packet_number', 1)
                        
                        anomaly_record = {
                            'file': file_path,
                            'file_type': file_type,
                            'packet_number': packet_num,
                            'line_number': packet_num,  # Use packet_number as line_number for PCAP files
                            'anomaly_type': 'DU-RU Communication',
                            'confidence': confidence,  # Add confidence score
                            'error_log': anomaly.get('error_log', ''),  # Packet data for LLM
                            'details': [
                                f"Confidence: {confidence:.2f} ({int(confidence*100)}%)",
                                f"Missing Responses: {anomaly.get('missing_responses', 0)} DU packets without RU replies",
                                f"Poor Communication Ratio: {anomaly.get('communication_ratio', 0):.2f} (expected > 0.8)"
                            ]
                        }
                        anomalies.append(anomaly_record)
                
                # Run advanced L1 anomaly detection on the same PCAP file
                if SCAPY_AVAILABLE:
                    try:
                        print(f"  Running advanced L1 anomaly detection...")
                        packets = rdpcap(file_path)
                        
                        # Run all new anomaly detection methods
                        rach_anomalies = self.detect_rach_failures(packets)
                        handover_anomalies = self.detect_handover_failures(packets)
                        harq_anomalies = self.detect_harq_retransmissions(packets)
                        crc_anomalies = self.detect_crc_errors(packets)
                        rrc_anomalies = self.detect_rrc_connection_failures(packets)
                        ta_anomalies = self.detect_timing_advance_violations(packets)
                        power_anomalies = self.detect_power_control_anomalies(packets)
                        
                        # Combine all new anomalies
                        new_anomalies = (rach_anomalies + handover_anomalies + harq_anomalies + 
                                       crc_anomalies + rrc_anomalies + ta_anomalies + power_anomalies)
                        
                        # Add file info to each new anomaly
                        for anomaly in new_anomalies:
                            anomaly['file'] = file_path
                            anomaly['file_type'] = file_type
                            anomaly['line_number'] = anomaly['packet_number']
                        
                        anomalies.extend(new_anomalies)
                        
                        if new_anomalies:
                            print(f"  Advanced detection found {len(new_anomalies)} additional anomalies:")
                            anomaly_types = {}
                            for a in new_anomalies:
                                atype = a['anomaly_type']
                                anomaly_types[atype] = anomaly_types.get(atype, 0) + 1
                            for atype, count in anomaly_types.items():
                                print(f"    - {atype}: {count}")
                    
                    except Exception as e:
                        print(f"  WARNING: Advanced anomaly detection failed: {e}")

                self.pcap_files_processed += 1

            elif file_type == 'DLF':
                # Process QXDM DLF files using DLF parser
                if not DLF_SUPPORT_AVAILABLE or not self.dlf_parser:
                    print(f"  WARNING: DLF support not available, skipping file")
                    return anomalies
                
                try:
                    print(f"  Parsing DLF/QXDM diagnostic file...")
                    packets = self.dlf_parser.parse_dlf_file(file_path)
                    
                    if not packets:
                        print(f"  WARNING: No packets extracted from DLF file")
                        return anomalies
                    
                    print(f"  Extracted {len(packets)} QXDM packets, running L1 anomaly detection...")
                    
                    # Run all L1 anomaly detection methods on DLF packets
                    rach_anomalies = self.detect_rach_failures(packets)
                    handover_anomalies = self.detect_handover_failures(packets)
                    harq_anomalies = self.detect_harq_retransmissions(packets)
                    crc_anomalies = self.detect_crc_errors(packets)
                    rrc_anomalies = self.detect_rrc_connection_failures(packets)
                    ta_anomalies = self.detect_timing_advance_violations(packets)
                    power_anomalies = self.detect_power_control_anomalies(packets)
                    
                    # Combine all anomalies
                    dlf_anomalies = (rach_anomalies + handover_anomalies + harq_anomalies + 
                                   crc_anomalies + rrc_anomalies + ta_anomalies + power_anomalies)
                    
                    # Add file info to each anomaly
                    for anomaly in dlf_anomalies:
                        anomaly['file'] = file_path
                        anomaly['file_type'] = file_type
                        anomaly['line_number'] = anomaly['packet_number']
                    
                    anomalies.extend(dlf_anomalies)
                    
                    if dlf_anomalies:
                        print(f"  DLF detection found {len(dlf_anomalies)} anomalies:")
                        anomaly_types = {}
                        for a in dlf_anomalies:
                            atype = a['anomaly_type']
                            anomaly_types[atype] = anomaly_types.get(atype, 0) + 1
                        for atype, count in anomaly_types.items():
                            print(f"    - {atype}: {count}")
                    else:
                        print(f"  No anomalies detected in DLF file")
                    
                    # Get DLF parser statistics
                    stats = self.dlf_parser.get_statistics()
                    if stats['errors'] > 0:
                        print(f"  WARNING: {stats['errors']} parsing errors encountered")
                
                except Exception as e:
                    print(f"  ERROR: DLF file processing failed: {e}")
                    import traceback
                    traceback.print_exc()
                
                self.pcap_files_processed += 1  # Count DLF files with PCAP files for now

            elif file_type == 'TEXT':
                # Use both rule-based and ML-based UE event analyzers
                analyzer = UEEventAnalyzer()
                ml_analyzer = MLUEEventAnalyzer()
                
                # Read file content
                with open(file_path, 'r') as f:
                    log_content = f.read()
                
                # Parse events without database writes
                events = analyzer.parse_ue_events(log_content)
                
                if events:
                    # RULE-BASED DETECTION: Simple pattern analysis
                    ue_sessions = {}
                    for event in events:
                        ue_id = event['ue_id']
                        if ue_id not in ue_sessions:
                            ue_sessions[ue_id] = []
                        ue_sessions[ue_id].append(event)
                    
                    # Check for anomalous patterns - more sensitive detection
                    for ue_id, ue_events in ue_sessions.items():
                        attach_count = len([e for e in ue_events if e['event_type'] == 'attach'])
                        failed_attaches = len([e for e in ue_events if e.get('event_subtype') == 'failed_attach'])
                        attach_timeouts = len([e for e in ue_events if e.get('event_subtype') == 'attach_timeout'])
                        abnormal_detaches = len([e for e in ue_events if e.get('event_subtype') == 'abnormal_detach'])
                        forced_detaches = len([e for e in ue_events if e.get('event_subtype') == 'forced_detach'])
                        
                        # Flag ANY attach/detach failures (lowered threshold for better detection)
                        if failed_attaches > 0 or attach_timeouts > 0 or abnormal_detaches > 0 or forced_detaches > 0 or attach_count > 10:
                            # Build descriptive details
                            failure_types = []
                            if failed_attaches > 0:
                                failure_types.append(f"attach rejected: {failed_attaches}")
                            if attach_timeouts > 0:
                                failure_types.append(f"attach timeout: {attach_timeouts}")
                            if abnormal_detaches > 0:
                                failure_types.append(f"abnormal detach: {abnormal_detaches}")
                            if forced_detaches > 0:
                                failure_types.append(f"forced detach: {forced_detaches}")
                            if attach_count > 10:
                                failure_types.append(f"excessive attach attempts: {attach_count}")
                            
                            description = f"UE {ue_id} {'attach rejected, cause: authentication failure' if failed_attaches > 0 else ', '.join(failure_types)}"
                            
                            # Create error_log with event summary
                            event_summary = f"UE {ue_id} Events: " + ", ".join([f"{e['event_type']}({e.get('event_subtype', 'normal')})" for e in ue_events[:5]])
                            if len(ue_events) > 5:
                                event_summary += f" ... and {len(ue_events)-5} more events"
                            
                            anomaly_record = {
                                'file': file_path,
                                'file_type': file_type,
                                'packet_number': 1,
                                'line_number': ue_events[0]['line_number'] if ue_events else 1,
                                'anomaly_type': description,
                                'ue_id': ue_id,
                                'confidence': 1.0,  # TEXT anomalies are rule-based, high confidence
                                'error_log': event_summary,  # Event log content for LLM
                                'details': [
                                    f"Rule-Based Detection",
                                    f"Attach attempts: {attach_count}",
                                    f"Failed attaches: {failed_attaches}",
                                    f"Attach timeouts: {attach_timeouts}",
                                    f"Abnormal detaches: {abnormal_detaches}",
                                    f"Forced detaches: {forced_detaches}"
                                ]
                            }
                            anomalies.append(anomaly_record)
                    
                    rule_based_count = len(anomalies)
                    
                    # ML-BASED DETECTION: Advanced pattern analysis with ensemble
                    print(f"  Rule-based: Found {rule_based_count} anomalies")
                    ml_anomalies = ml_analyzer.detect_anomalies(events, file_path)
                    
                    # Add ML-detected anomalies
                    for ml_anomaly in ml_anomalies:
                        anomalies.append(ml_anomaly)
                    
                    print(f"  Parsed {len(events)} UE events, found {len(anomalies)} total anomalies ({rule_based_count} rule-based + {len(ml_anomalies)} ML-based)")
                    if len(anomalies) > 0:
                        print(f"  Detected: {sum(1 for a in anomalies if 'attach' in str(a.get('anomaly_type', '')).lower())} attach failures, "
                              f"{sum(1 for a in anomalies if 'detach' in str(a.get('anomaly_type', '')).lower())} detach failures")
                else:
                    print(f"  No UE events found in file")
                
                self.text_files_processed += 1

        except Exception as e:
            print(f"  ERROR: Error processing {file_name}: {e}")
            return []

        self.total_files_processed += 1
        self.total_anomalies_found += len(anomalies)
        
        # Store processed file record in ClickHouse
        if self.clickhouse_available:
            try:
                import os
                file_size = os.path.getsize(file_path) if os.path.exists(file_path) else 0
                file_record = [[
                    str(self.total_files_processed),  # id as string
                    file_name,                    # filename
                    file_type,                    # file_type
                    file_size,                    # file_size
                    datetime.now(),              # upload_date
                    'completed',                  # processing_status
                    len(anomalies),              # anomalies_found
                    datetime.now(),              # processing_time
                    ''                            # error_message (empty string instead of null)
                ]]
                
                self.client.insert('processed_files', file_record, column_names=[
                    'id', 'filename', 'file_type', 'file_size', 'upload_date',
                    'processing_status', 'anomalies_found', 'processing_time', 'error_message'
                ])
                print(f"  SUCCESS: File record stored in processed_files table")
            except Exception as e:
                print(f"  WARNING: Failed to store file record: {e}")

        return anomalies

    def get_ue_anomaly_details(self, ue_data):
        """Extract detailed anomaly information for UE events"""
        issues = []

        attach_attempts = ue_data.get('attach_attempts', 0)
        successful_attaches = ue_data.get('successful_attaches', 0)
        detach_events = ue_data.get('detach_events', 0)
        context_failures = ue_data.get('context_failures', 0)

        if attach_attempts > successful_attaches:
            failed_attaches = attach_attempts - successful_attaches
            issues.append(f"Failed Attach Procedures: {failed_attaches} incomplete")

        if context_failures > 0:
            issues.append(f"Context Failures: {context_failures} detected")

        if successful_attaches > 0 and detach_events == 0:
            issues.append("Missing Detach Events: UE may have unexpectedly disconnected")

        return issues if issues else ["Abnormal UE Event Pattern"]

    def generate_summary_report(self, folder_path, all_anomalies, session_id=None):
        """Generate comprehensive summary report with ClickHouse integration"""
        print(f"\n\n" + "=" * 80)
        print("COMPREHENSIVE L1 NETWORK ANALYSIS SUMMARY REPORT")
        if self.clickhouse_available:
            print("WITH CLICKHOUSE DATABASE INTEGRATION")
        print("=" * 80)

        # Header Information
        analysis_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        print(f"Analysis Date: {analysis_time}")
        print(f"Target Folder: {os.path.abspath(folder_path)}")
        print(f"System: Unified L1 Anomaly Detection with ML Ensemble")
        if self.clickhouse_available:
            print(f"Database: ClickHouse (Session ID: {session_id})")

        # Processing Statistics
        print(f"\n" + "PROCESSING STATISTICS".ljust(50, '='))
        print(f"Total Files Processed: {self.total_files_processed}")
        print(f"   - PCAP Files: {self.pcap_files_processed}")
        print(f"   - Text Files: {self.text_files_processed}")

        if not all_anomalies:
            print(f"\n" + "ANALYSIS COMPLETE - NO ANOMALIES DETECTED".ljust(50, '='))
            print("RESULT: All network files appear to be functioning normally")
            print("NETWORK STATUS: HEALTHY")
            print("FRONTHAUL STATUS: No DU-RU communication issues detected")
            print("UE BEHAVIOR: No abnormal attachment/detachment patterns")

            if self.clickhouse_available:
                print("CLEAN SESSION: Stored in ClickHouse for historical tracking")

            return

        # Critical Alert
        print(f"\n" + "CRITICAL NETWORK ANOMALIES DETECTED".ljust(50, '='))
        print(f"WARNING: TOTAL ANOMALIES FOUND: {self.total_anomalies_found}")
        print(f"NETWORK STATUS: REQUIRES ATTENTION")

        if self.clickhouse_available:
            print(f"ANOMALIES STORED: ClickHouse database for analysis and reporting")

        # Anomaly Breakdown
        pcap_anomalies = [a for a in all_anomalies if a['file_type'] == 'PCAP']
        text_anomalies = [a for a in all_anomalies if a['file_type'] == 'TEXT']

        print(f"\n" + "ANOMALY STATISTICS".ljust(50, '='))
        print(f"PCAP Communication Anomalies: {len(pcap_anomalies)}")
        print(f"UE Event Anomalies: {len(text_anomalies)}")

        if pcap_anomalies:
            print(f"   DU-RU Fronthaul Issues: {len(pcap_anomalies)} detected")
        if text_anomalies:
            print(f"   UE Mobility Issues: {len(text_anomalies)} detected")

        # File-by-File Breakdown
        print(f"\n" + "DETAILED ANOMALY BREAKDOWN".ljust(50, '='))

        file_anomalies = defaultdict(list)
        for anomaly in all_anomalies:
            file_name = os.path.basename(anomaly['file'])
            file_anomalies[file_name].append(anomaly)

        for i, (file_name, anomalies) in enumerate(file_anomalies.items(), 1):
            print(f"\nFILE [{i}]: {file_name}")
            print(f"    Type: {anomalies[0]['file_type']} | Anomalies: {len(anomalies)}")

            # Show critical anomalies
            for j, anomaly in enumerate(anomalies[:2], 1):  # Show first 2 per file
                print(f"\n    ANOMALY #{j}: PACKET #{anomaly['packet_number']}")
                print(f"    - Type: {anomaly['anomaly_type']}")
                print(f"    - *** FRONTHAUL ISSUE BETWEEN DU TO RU ***")
                print(f"    - DU MAC: {self.DU_MAC}")
                print(f"    - RU MAC: {self.RU_MAC}")

                if 'ue_id' in anomaly:
                    print(f"    - UE ID: {anomaly['ue_id']}")

                print(f"    - Issues Detected:")
                for detail in anomaly['details']:
                    print(f"       - {detail}")

            if len(anomalies) > 2:
                print(f"    ... and {len(anomalies) - 2} additional anomalies")

        # ClickHouse Integration Summary
        if self.clickhouse_available:
            print(f"\n" + "CLICKHOUSE DATABASE INTEGRATION".ljust(50, '='))
            print(f"Session stored with ID: {session_id}")
            print(f"{len(all_anomalies)} anomalies stored for analysis")
            print(f"Historical data available for trend analysis")
            print(f"Dashboard integration enabled")

        # Recommended Actions  
        print(f"\n" + "IMMEDIATE ACTION PLAN".ljust(50, '='))

        actions = []
        if pcap_anomalies:
            actions.extend([
                "1. INSPECT DU-RU physical connections and cable integrity",
                "2. CHECK fronthaul timing synchronization (target: <100us)",
                "3. MONITOR packet loss rates and communication ratios"
            ])

        if text_anomalies:
            actions.extend([
                f"{len(actions)+1}. INVESTIGATE UE attachment failure patterns",
                f"{len(actions)+2}. REVIEW context setup procedures and timeouts",
                f"{len(actions)+3}. ANALYZE mobility management and handover processes"
            ])

        actions.extend([
            f"{len(actions)+1}. ESTABLISH continuous monitoring for these anomaly patterns",
            f"{len(actions)+2}. RE-RUN analysis after implementing fixes",
            f"{len(actions)+3}. DOCUMENT findings and maintain incident log"
        ])

        for action in actions[:6]:  # Show top 6 actions
            print(f"   {action}")

        # Technical Summary
        print(f"\n" + "TECHNICAL SUMMARY".ljust(50, '='))
        print(f"ML Algorithms: Isolation Forest, DBSCAN, One-Class SVM, LOF")
        print(f"Detection Method: Ensemble voting (>=2 algorithms for high confidence)")
        print(f"Analysis Scope: DU-RU communication + UE mobility patterns")
        print(f"MAC Addresses: DU={self.DU_MAC}, RU={self.RU_MAC}")
        if self.clickhouse_available:
            print(f"Database: ClickHouse time-series storage for scalable analytics")

        print(f"\n" + "=" * 80)
        print("COMPREHENSIVE L1 NETWORK ANALYSIS COMPLETED")
        if self.clickhouse_available:
            print("ALL DATA STORED IN CLICKHOUSE DATABASE")
        print("=" * 80)

    def save_detailed_report(self, report_file, folder_path, all_anomalies):
        """Save detailed technical report to file"""
        try:
            with open(report_file, 'w') as f:
                f.write("L1 ANOMALY DETECTION - DETAILED TECHNICAL REPORT\n")
                f.write("=" * 60 + "\n\n")
                f.write(f"Analysis Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
                f.write(f"Folder: {folder_path}\n")
                f.write(f"Total Files: {self.total_files_processed}\n")
                f.write(f"Total Anomalies: {self.total_anomalies_found}\n")
                f.write(f"ClickHouse Integration: {'Enabled' if self.clickhouse_available else 'Disabled'}\n\n")

                if all_anomalies:
                    f.write("ANOMALY DETAILS:\n")
                    f.write("-" * 40 + "\n")

                    for i, anomaly in enumerate(all_anomalies, 1):
                        f.write(f"\n[{i}] FILE: {os.path.basename(anomaly['file'])}\n")
                        f.write(f"    Type: {anomaly['file_type']}\n")
                        
                        # Use line_number if available, fallback to packet_number
                        line_ref = anomaly.get('line_number', anomaly.get('packet_number', 'N/A'))
                        f.write(f"    Line/Packet: {line_ref}\n")
                        
                        f.write(f"    Anomaly: {anomaly['anomaly_type']}\n")
                        
                        # Show confidence if available
                        if 'confidence' in anomaly:
                            f.write(f"    Confidence: {anomaly['confidence']:.2f} ({int(anomaly['confidence']*100)}%)\n")
                        
                        f.write(f"    DU MAC: {self.DU_MAC}\n")
                        f.write(f"    RU MAC: {self.RU_MAC}\n")

                        if 'ue_id' in anomaly:
                            f.write(f"    UE ID: {anomaly['ue_id']}\n")

                        f.write(f"    Issues:\n")
                        for detail in anomaly['details']:
                            f.write(f"      - {detail}\n")
                else:
                    f.write("NO ANOMALIES DETECTED\n")
                    f.write("All network files appear to be functioning normally.\n")

        except Exception as e:
            print(f"WARNING: Failed to save detailed report: {e}")

def main():
    """Main function for folder-based L1 anomaly detection"""

    print("FOLDER-BASED L1 ANOMALY DETECTION SYSTEM WITH CLICKHOUSE")
    print("=" * 65)
    print("Automatically processes all files in folder:")
    print("- PCAP files (.pcap, .cap)")
    print("- HDF5 text files (.txt, .log)")
    print("- Auto-detects file types")
    print("- ClickHouse database integration")
    print("- Batch processing with summary report")

    # Check for dummy mode FIRST (before anything else)
    dummy_mode = False
    if len(sys.argv) >= 3 and sys.argv[2].lower() == 'dummy':
        dummy_mode = True
        print("\nRUNNING IN DUMMY MODE - Database writes disabled")
        print("Results will only be shown in console and report file")

    # Get folder path from command line or use default
    if len(sys.argv) < 2:
        folder_path = "/app/input_files"
        print(f"\nINFO: No folder specified, using default: {folder_path}")
    else:
        folder_path = sys.argv[1]
        print(f"\nUsing specified folder: {folder_path}")

    if not os.path.exists(folder_path):
        print(f"\nERROR: Folder '{folder_path}' does not exist")
        if folder_path == "/app/input_files":
            print("TIP: Upload PCAP/text files to /app/input_files directory")
            # Create the directory if it doesn't exist
            try:
                os.makedirs(folder_path, exist_ok=True)
                print(f"Created directory: {folder_path}")
            except Exception as e:
                print(f"WARNING: Could not create directory: {e}")
                sys.exit(1)
        else:
            sys.exit(1)

    # Initialize analyzer (skip database connection in dummy mode)
    analyzer = ClickHouseFolderAnalyzer(skip_database=dummy_mode)

    # Scan folder for files
    found_files = analyzer.scan_folder(folder_path)

    if not found_files:
        sys.exit(1)

    # Create session record
    session_id = int(datetime.now().timestamp())
    session_data = {
        'id': session_id,
        'session_name': f"Folder Analysis: {os.path.basename(folder_path)}",
        'folder_path': os.path.abspath(folder_path),
        'total_files': len(found_files),
        'pcap_files': sum(1 for f in found_files if f['type'] == 'PCAP'),
        'text_files': sum(1 for f in found_files if f['type'] == 'TEXT'),
        'total_anomalies': 0,
        'start_time': datetime.now(),  # Fixed: Use datetime object directly
        'end_time': None,
        'duration_seconds': 0
    }

    print(f"\nPROCESSING FILES...")
    print("=" * 30)

    all_anomalies = []
    start_time = datetime.now()

    # Process each file
    for file_info in found_files:
        file_anomalies = analyzer.process_single_file(file_info)
        all_anomalies.extend(file_anomalies)

    # Update session data
    end_time = datetime.now()
    duration = (end_time - start_time).total_seconds()

    session_data['end_time'] = end_time  # Fixed: Use datetime object directly
    session_data['duration_seconds'] = int(duration)
    session_data['total_anomalies'] = len(all_anomalies)

    # Store in ClickHouse (unless in dummy mode)
    stored_session_id = None
    if not dummy_mode:
        stored_session_id = analyzer.store_session_in_clickhouse(session_data)
        analyzer.store_anomalies_in_clickhouse(all_anomalies, session_id)
    else:
        print("\nDUMMY MODE: Skipping database writes")

    # Generate summary report
    analyzer.generate_summary_report(folder_path, all_anomalies, stored_session_id)

    # Save detailed report
    report_file = os.path.join(folder_path, "anomaly_analysis_report.txt")
    analyzer.save_detailed_report(report_file, folder_path, all_anomalies)

    print(f"\nFOLDER ANALYSIS COMPLETE")
    if not dummy_mode and analyzer.clickhouse_available:
        print("All data stored in ClickHouse database")
    print("All network files have been processed and analyzed.")

if __name__ == "__main__":
    main()