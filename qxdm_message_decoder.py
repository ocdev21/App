"""
QXDM Message Decoder - Maps Qualcomm diagnostic message IDs to L1 protocol types

This module provides mapping between QXDM/DIAG message IDs and Layer 1 network protocols
for use in anomaly detection.

Message ID ranges (hexadecimal):
- 0x1000-0x10FF: LTE/4G OTA messages
- 0x0000-0x00FF: General diagnostic messages
- 0xB000-0xB0FF: RRC and signaling messages
"""

from typing import Dict, Set, Optional, List
from enum import Enum


class ProtocolType(Enum):
    """L1 Protocol types for anomaly detection"""
    RACH = "rach"
    HANDOVER = "handover"
    RRC = "rrc"
    MAC = "mac"
    HARQ = "harq"
    CRC = "crc"
    TIMING_ADVANCE = "timing_advance"
    POWER_CONTROL = "power_control"
    PHYSICAL_LAYER = "physical_layer"
    UNKNOWN = "unknown"


class QXDMMessageDecoder:
    """Decoder for QXDM diagnostic message IDs"""
    
    # LTE/4G RRC message IDs
    RRC_MESSAGE_IDS = {
        0xB0C0, 0xB0C1, 0xB0C2,  # RRC OTA messages
        0xB0E0, 0xB0E1, 0xB0E2,  # RRC connection setup/release
        0xB097,  # RRC MIB
        0xB0A0, 0xB0A1,  # RRC system information
    }
    
    # MAC layer message IDs
    MAC_MESSAGE_IDS = {
        0xB060, 0xB061, 0xB062,  # MAC DL/UL transport blocks
        0xB063, 0xB064,  # MAC RACH
        0xB065,  # MAC padding BSR
    }
    
    # Physical layer message IDs
    PHYSICAL_LAYER_IDS = {
        0xB110, 0xB111, 0xB112,  # PDSCH/PUSCH
        0xB113, 0xB114,  # PUCCH
        0xB120, 0xB121,  # PHICH
        0xB130,  # PCFICH
    }
    
    # RACH/PRACH related message IDs
    RACH_MESSAGE_IDS = {
        0xB063,  # MAC RACH attempt
        0xB064,  # MAC RACH response
        0xB0C5,  # RRC connection request
        0xB132,  # PRACH config
    }
    
    # Handover related message IDs
    HANDOVER_MESSAGE_IDS = {
        0xB0C6,  # RRC connection reconfiguration
        0xB0C7,  # RRC connection reconfiguration complete
        0xB0D0,  # Handover command
        0xB0D1,  # Handover complete
        0xB0D2,  # Handover failure
    }
    
    # HARQ related message IDs
    HARQ_MESSAGE_IDS = {
        0xB139,  # HARQ DL
        0xB13A,  # HARQ UL
        0xB060,  # MAC DL (contains HARQ info)
        0xB061,  # MAC UL (contains HARQ info)
    }
    
    # Power control message IDs
    POWER_CONTROL_IDS = {
        0xB140, 0xB141,  # TPC commands
        0xB142,  # Power headroom report
        0xB143,  # UL power control
    }
    
    # Timing advance message IDs
    TIMING_ADVANCE_IDS = {
        0xB150,  # Timing advance command
        0xB151,  # TA adjustment
    }
    
    def __init__(self):
        """Initialize the message decoder with protocol mappings"""
        self.message_to_protocol = self._build_message_mapping()
        self.protocol_keywords = self._build_keyword_mapping()
        
    def _build_message_mapping(self) -> Dict[int, List[ProtocolType]]:
        """Build mapping from message ID to protocol types"""
        mapping = {}
        
        for msg_id in self.RACH_MESSAGE_IDS:
            mapping.setdefault(msg_id, []).append(ProtocolType.RACH)
            
        for msg_id in self.HANDOVER_MESSAGE_IDS:
            mapping.setdefault(msg_id, []).append(ProtocolType.HANDOVER)
            
        for msg_id in self.RRC_MESSAGE_IDS:
            mapping.setdefault(msg_id, []).append(ProtocolType.RRC)
            
        for msg_id in self.MAC_MESSAGE_IDS:
            mapping.setdefault(msg_id, []).append(ProtocolType.MAC)
            
        for msg_id in self.HARQ_MESSAGE_IDS:
            mapping.setdefault(msg_id, []).append(ProtocolType.HARQ)
            
        for msg_id in self.POWER_CONTROL_IDS:
            mapping.setdefault(msg_id, []).append(ProtocolType.POWER_CONTROL)
            
        for msg_id in self.TIMING_ADVANCE_IDS:
            mapping.setdefault(msg_id, []).append(ProtocolType.TIMING_ADVANCE)
            
        return mapping
    
    def _build_keyword_mapping(self) -> Dict[ProtocolType, List[bytes]]:
        """Build mapping from protocol type to payload keywords"""
        return {
            ProtocolType.RACH: [b'RACH', b'PRACH', b'rach', b'prach', b'Random Access'],
            ProtocolType.HANDOVER: [b'handover', b'Handover', b'HO', b'reconfiguration'],
            ProtocolType.RRC: [b'RRC', b'rrc', b'Connection', b'Setup', b'Reject'],
            ProtocolType.HARQ: [b'HARQ', b'harq', b'retx', b'retransmission', b'NACK', b'nack'],
            ProtocolType.CRC: [b'CRC', b'crc', b'checksum'],
            ProtocolType.POWER_CONTROL: [b'TPC', b'tpc', b'Power', b'power'],
            ProtocolType.TIMING_ADVANCE: [b'TA', b'TimingAdvance', b'timing'],
        }
    
    def get_protocol_types(self, message_id: int, payload: bytes) -> List[ProtocolType]:
        """
        Determine protocol type(s) for a given message ID and payload
        
        Args:
            message_id: QXDM message ID
            payload: Packet payload bytes
            
        Returns:
            List of ProtocolType enums
        """
        protocols = []
        
        if message_id in self.message_to_protocol:
            protocols.extend(self.message_to_protocol[message_id])
        
        for protocol_type, keywords in self.protocol_keywords.items():
            for keyword in keywords:
                if keyword in payload:
                    if protocol_type not in protocols:
                        protocols.append(protocol_type)
                    break
        
        if not protocols:
            protocols.append(ProtocolType.UNKNOWN)
        
        return protocols
    
    def is_l1_relevant(self, message_id: int) -> bool:
        """Check if message ID is relevant for L1 anomaly detection"""
        all_relevant_ids = (
            self.RACH_MESSAGE_IDS |
            self.HANDOVER_MESSAGE_IDS |
            self.RRC_MESSAGE_IDS |
            self.MAC_MESSAGE_IDS |
            self.HARQ_MESSAGE_IDS |
            self.POWER_CONTROL_IDS |
            self.TIMING_ADVANCE_IDS
        )
        return message_id in all_relevant_ids
    
    def get_protocol_indicators(self, payload: bytes, message_id: Optional[int] = None) -> Dict[str, bool]:
        """
        Extract L1 protocol indicators from payload using message ID when available
        
        Args:
            payload: Packet payload bytes
            message_id: Optional QXDM message ID for accurate protocol detection
            
        Returns:
            Dictionary of protocol indicators
        """
        indicators = {
            'has_rach': False,
            'has_handover': False,
            'has_rrc': False,
            'has_harq': False,
            'has_crc': False,
            'has_power_control': False,
            'has_timing_advance': False,
            'failure_indicators': [],
            'error_indicators': []
        }
        
        # If message ID is provided, use it for accurate protocol detection
        if message_id is not None:
            # Use message ID mappings for primary detection
            if message_id in self.RACH_MESSAGE_IDS:
                indicators['has_rach'] = True
                
            if message_id in self.HANDOVER_MESSAGE_IDS:
                indicators['has_handover'] = True
                
            if message_id in self.RRC_MESSAGE_IDS:
                indicators['has_rrc'] = True
                
            if message_id in self.HARQ_MESSAGE_IDS:
                indicators['has_harq'] = True
                
            if message_id in self.POWER_CONTROL_IDS:
                indicators['has_power_control'] = True
                
            if message_id in self.TIMING_ADVANCE_IDS:
                indicators['has_timing_advance'] = True
        
        # Also check payload content for additional context (secondary detection)
        payload_lower = payload.lower()
        
        if not indicators['has_rach'] and (b'rach' in payload_lower or b'prach' in payload_lower):
            indicators['has_rach'] = True
            
        if not indicators['has_handover'] and (b'handover' in payload_lower or b'ho' in payload_lower):
            indicators['has_handover'] = True
            
        if not indicators['has_rrc'] and b'rrc' in payload_lower:
            indicators['has_rrc'] = True
            
        if not indicators['has_harq'] and (b'harq' in payload_lower or b'retx' in payload_lower or b'nack' in payload_lower):
            indicators['has_harq'] = True
            
        if b'crc' in payload_lower:
            indicators['has_crc'] = True
            
        if not indicators['has_power_control'] and (b'tpc' in payload_lower or b'power' in payload_lower):
            indicators['has_power_control'] = True
            
        if not indicators['has_timing_advance'] and (b'ta' in payload_lower or b'timing' in payload_lower):
            indicators['has_timing_advance'] = True
        
        # Extract error/failure indicators from payload
        failure_keywords = [b'fail', b'error', b'reject', b'timeout', b'abort', b'deny']
        for keyword in failure_keywords:
            if keyword in payload_lower:
                indicators['failure_indicators'].append(keyword.decode('utf-8', errors='ignore'))
        
        error_keywords = [b'error', b'err', b'invalid', b'corrupt']
        for keyword in error_keywords:
            if keyword in payload_lower:
                indicators['error_indicators'].append(keyword.decode('utf-8', errors='ignore'))
        
        return indicators
    
    def get_message_description(self, message_id: int) -> str:
        """Get human-readable description of message ID"""
        descriptions = {
            0xB0C0: "LTE RRC OTA Message",
            0xB0C5: "RRC Connection Request",
            0xB0C6: "RRC Connection Reconfiguration",
            0xB0D0: "Handover Command",
            0xB0D1: "Handover Complete",
            0xB0D2: "Handover Failure",
            0xB063: "MAC RACH Attempt",
            0xB064: "MAC RACH Response",
            0xB139: "HARQ DL",
            0xB13A: "HARQ UL",
            0xB140: "TPC Command",
            0xB150: "Timing Advance Command",
        }
        
        return descriptions.get(message_id, f"QXDM Message 0x{message_id:04X}")
