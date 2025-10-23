#!/usr/bin/env python3
"""
Enhanced Protocol Parser for L1 Anomaly Detection
Provides protocol-aware packet analysis instead of simple byte matching
Supports both PCAP (scapy) and QXDM/DLF packets
"""

import struct
from datetime import datetime
from typing import Dict, List, Any, Optional, Tuple
import numpy as np

try:
    from scapy.all import Ether, IP, UDP, TCP, Raw
    SCAPY_AVAILABLE = True
except ImportError:
    SCAPY_AVAILABLE = False

try:
    from qxdm_message_decoder import QXDMMessageDecoder
    QXDM_DECODER_AVAILABLE = True
except ImportError:
    QXDM_DECODER_AVAILABLE = False


class EnhancedProtocolParser:
    """
    Protocol-aware parser for extracting meaningful L1 network metrics
    Supports both PCAP (scapy) and QXDM/DLF packets
    """
    
    def __init__(self):
        self.packet_cache = {}
        self.qxdm_decoder = QXDMMessageDecoder() if QXDM_DECODER_AVAILABLE else None
        
    def extract_packet_features(self, packet, packet_index: int) -> Dict[str, Any]:
        """
        Extract comprehensive features from a single packet
        Returns features for ML analysis and anomaly detection
        """
        features = {
            'packet_index': packet_index,
            'timestamp': float(packet.time) if hasattr(packet, 'time') else 0,
            'size': len(packet),
            'has_ethernet': packet.haslayer(Ether),
            'has_ip': packet.haslayer(IP),
            'has_udp': packet.haslayer(UDP),
            'has_tcp': packet.haslayer(TCP),
            'payload_size': 0,
            'src_mac': None,
            'dst_mac': None,
            'src_ip': None,
            'dst_ip': None,
            'src_port': None,
            'dst_port': None,
            'ip_ttl': None,
            'tcp_flags': None,
            'udp_length': None
        }
        
        if packet.haslayer(Ether):
            features['src_mac'] = packet[Ether].src
            features['dst_mac'] = packet[Ether].dst
            
        if packet.haslayer(IP):
            features['src_ip'] = packet[IP].src
            features['dst_ip'] = packet[IP].dst
            features['ip_ttl'] = packet[IP].ttl
            
        if packet.haslayer(UDP):
            features['src_port'] = packet[UDP].sport
            features['dst_port'] = packet[UDP].dport
            features['udp_length'] = packet[UDP].len
            
        if packet.haslayer(TCP):
            features['src_port'] = packet[TCP].sport
            features['dst_port'] = packet[TCP].dport
            features['tcp_flags'] = packet[TCP].flags
            
        if packet.haslayer(Raw):
            features['payload_size'] = len(packet[Raw].load)
            features['payload'] = bytes(packet[Raw].load)
        
        return features
    
    def extract_timing_features(self, packets: List) -> Dict[str, Any]:
        """
        Extract timing-based features from packet sequence
        """
        if len(packets) < 2:
            return {}
            
        timestamps = [float(p.time) for p in packets if hasattr(p, 'time')]
        
        if len(timestamps) < 2:
            return {}
            
        inter_arrival_times = np.diff(timestamps)
        
        return {
            'mean_inter_arrival': float(np.mean(inter_arrival_times)),
            'std_inter_arrival': float(np.std(inter_arrival_times)),
            'min_inter_arrival': float(np.min(inter_arrival_times)),
            'max_inter_arrival': float(np.max(inter_arrival_times)),
            'jitter': float(np.std(inter_arrival_times)),
            'total_duration': timestamps[-1] - timestamps[0],
            'packet_rate': len(packets) / (timestamps[-1] - timestamps[0]) if timestamps[-1] > timestamps[0] else 0
        }
    
    def detect_sequence_anomalies(self, packets: List, seq_field: str = 'id') -> List[Dict]:
        """
        Detect sequence number anomalies (gaps, duplicates, out-of-order)
        """
        anomalies = []
        
        if not packets or len(packets) < 2:
            return anomalies
            
        seq_numbers = []
        for i, pkt in enumerate(packets):
            if pkt.haslayer(IP):
                seq_numbers.append((i, pkt[IP].id))
        
        if len(seq_numbers) < 2:
            return anomalies
            
        for i in range(1, len(seq_numbers)):
            pkt_idx_prev, seq_prev = seq_numbers[i-1]
            pkt_idx_curr, seq_curr = seq_numbers[i]
            
            gap = seq_curr - seq_prev
            
            if gap > 10:
                anomalies.append({
                    'type': 'sequence_gap',
                    'packet_index': pkt_idx_curr,
                    'gap_size': gap,
                    'severity': 'high' if gap > 100 else 'medium'
                })
            elif gap == 0:
                anomalies.append({
                    'type': 'sequence_duplicate',
                    'packet_index': pkt_idx_curr,
                    'severity': 'medium'
                })
            elif gap < 0:
                anomalies.append({
                    'type': 'sequence_out_of_order',
                    'packet_index': pkt_idx_curr,
                    'reorder_distance': abs(gap),
                    'severity': 'low'
                })
        
        return anomalies
    
    def extract_l1_indicators(self, payload: bytes, packet_obj=None) -> Dict[str, Any]:
        """
        Extract L1-specific indicators from packet payload
        Uses improved pattern matching and value extraction
        
        Args:
            payload: Raw packet payload bytes
            packet_obj: Optional packet object (for QXDM message ID extraction)
            
        Returns:
            Dictionary of L1 protocol indicators
        """
        # If this is a QXDM packet and decoder is available, use it for better accuracy
        if packet_obj and hasattr(packet_obj, 'message_id') and self.qxdm_decoder:
            message_id = packet_obj.message_id
            qxdm_indicators = self.qxdm_decoder.get_protocol_indicators(payload, message_id=message_id)
            return qxdm_indicators
        
        # Otherwise use pattern matching
        indicators = {
            'has_rach': False,
            'has_handover': False,
            'has_harq': False,
            'has_crc': False,
            'has_rrc': False,
            'has_timing_advance': False,
            'has_power_control': False,
            'error_indicators': [],
            'failure_indicators': []
        }
        
        payload_lower = payload.lower()
        
        rach_patterns = [b'rach', b'prach', b'preamble']
        handover_patterns = [b'handover', b'ho_', b'mobility']
        harq_patterns = [b'harq', b'retx', b'nack', b'ack']
        crc_patterns = [b'crc', b'checksum', b'fcs']
        rrc_patterns = [b'rrc', b'connection', b'setup', b'release']
        ta_patterns = [b'ta', b'timingadvance', b'timing']
        power_patterns = [b'tpc', b'powercontrol', b'power']
        
        error_patterns = [b'error', b'fail', b'reject', b'timeout', b'violation', b'invalid']
        
        for pattern in rach_patterns:
            if pattern in payload_lower:
                indicators['has_rach'] = True
                break
                
        for pattern in handover_patterns:
            if pattern in payload_lower:
                indicators['has_handover'] = True
                break
                
        for pattern in harq_patterns:
            if pattern in payload_lower:
                indicators['has_harq'] = True
                break
                
        for pattern in crc_patterns:
            if pattern in payload_lower:
                indicators['has_crc'] = True
                break
                
        for pattern in rrc_patterns:
            if pattern in payload_lower:
                indicators['has_rrc'] = True
                break
                
        for pattern in ta_patterns:
            if pattern in payload_lower:
                indicators['has_timing_advance'] = True
                break
                
        for pattern in power_patterns:
            if pattern in payload_lower:
                indicators['has_power_control'] = True
                break
        
        for pattern in error_patterns:
            if pattern in payload_lower:
                indicators['error_indicators'].append(pattern.decode('utf-8', errors='ignore'))
                
        if len(indicators['error_indicators']) > 0:
            indicators['failure_indicators'] = indicators['error_indicators']
        
        return indicators
    
    def calculate_communication_metrics(self, packets: List, du_mac: str, ru_mac: str) -> Dict[str, Any]:
        """
        Calculate DU-RU communication quality metrics
        """
        du_packets = []
        ru_packets = []
        du_to_ru_pairs = []
        
        for i, pkt in enumerate(packets):
            if pkt.haslayer(Ether):
                src_mac = pkt[Ether].src
                dst_mac = pkt[Ether].dst
                
                if src_mac.lower() == du_mac.lower():
                    du_packets.append((i, pkt))
                elif src_mac.lower() == ru_mac.lower():
                    ru_packets.append((i, pkt))
        
        for du_idx, du_pkt in du_packets:
            for ru_idx, ru_pkt in ru_packets:
                if ru_idx > du_idx and (ru_idx - du_idx) <= 5:
                    response_time = float(ru_pkt.time) - float(du_pkt.time)
                    du_to_ru_pairs.append({
                        'du_packet': du_idx,
                        'ru_packet': ru_idx,
                        'response_time': response_time
                    })
                    break
        
        metrics = {
            'total_du_packets': len(du_packets),
            'total_ru_packets': len(ru_packets),
            'matched_pairs': len(du_to_ru_pairs),
            'unmatched_du_packets': len(du_packets) - len(du_to_ru_pairs),
            'communication_ratio': len(du_to_ru_pairs) / len(du_packets) if du_packets else 0,
            'avg_response_time': np.mean([p['response_time'] for p in du_to_ru_pairs]) if du_to_ru_pairs else 0,
            'response_time_std': np.std([p['response_time'] for p in du_to_ru_pairs]) if du_to_ru_pairs else 0
        }
        
        return metrics
