"""
DLF (Diagnostic Log Format) Parser for QXDM Files

This module parses Qualcomm QXDM diagnostic log files in DLF format.
DLF is a binary format containing cellular network protocol traces from Qualcomm modems.

Based on the mobile_sentinel project and QXDM documentation.
"""

import struct
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional
import io


class QXDMPacket:
    """Represents a parsed QXDM diagnostic packet"""
    
    def __init__(self, timestamp: datetime, message_id: int, payload: bytes, packet_number: int):
        self.time = timestamp
        self.timestamp = timestamp
        self.message_id = message_id
        self.payload = payload
        self.packet_number = packet_number
        self.raw_data = payload
        
    def haslayer(self, layer_name):
        """Compatibility method for scapy-like interface"""
        if layer_name == 'Raw':
            return True
        return False
    
    def __getitem__(self, layer_name):
        """Compatibility method for scapy-like interface"""
        if layer_name == 'Raw':
            return RawLayer(self.payload)
        return None


class RawLayer:
    """Wrapper to provide scapy-like Raw layer interface"""
    
    def __init__(self, data: bytes):
        self.load = data


class DLFParser:
    """Parser for QXDM DLF (Diagnostic Log Format) files"""
    
    # QXDM epoch: January 6, 1980 00:00:00 GPS time
    QXDM_EPOCH = datetime(1980, 1, 6, 0, 0, 0)
    
    def __init__(self):
        self.packets_parsed = 0
        self.errors = []
        
    def parse_qxdm_timestamp(self, timestamp_bytes: bytes) -> datetime:
        """
        Parse QXDM 64-bit timestamp to Python datetime
        
        QXDM timestamps are typically stored as:
        - 64-bit value representing 1.25ms ticks since GPS epoch (Jan 6, 1980)
        - Or seconds since epoch with microsecond precision
        
        Args:
            timestamp_bytes: 8 bytes containing timestamp
            
        Returns:
            Python datetime object
        """
        try:
            if len(timestamp_bytes) >= 8:
                timestamp_value = struct.unpack('<Q', timestamp_bytes[0:8])[0]
                
                if timestamp_value > 0:
                    milliseconds = timestamp_value * 1.25
                    delta = timedelta(milliseconds=milliseconds)
                    return self.QXDM_EPOCH + delta
            
            return datetime.now()
            
        except Exception as e:
            self.errors.append(f"Timestamp parse error: {e}")
            return datetime.now()
    
    def calculate_crc16(self, data: bytes) -> int:
        """
        Calculate CRC16 for DIAG packets (DM CRC-CCITT)
        
        DLF format doesn't include CRC, but we add it for compatibility
        with DIAG protocol parsers.
        """
        crc_table = [
            0x0000, 0x1189, 0x2312, 0x329B, 0x4624, 0x57AD, 0x6536, 0x74BF,
            0x8C48, 0x9DC1, 0xAF5A, 0xBED3, 0xCA6C, 0xDBE5, 0xE97E, 0xF8F7,
            0x1081, 0x0108, 0x3393, 0x221A, 0x56A5, 0x472C, 0x75B7, 0x643E,
            0x9CC9, 0x8D40, 0xBFDB, 0xAE52, 0xDAED, 0xCB64, 0xF9FF, 0xE876,
            0x2102, 0x308B, 0x0210, 0x1399, 0x6726, 0x76AF, 0x4434, 0x55BD,
            0xAD4A, 0xBCC3, 0x8E58, 0x9FD1, 0xEB6E, 0xFAE7, 0xC87C, 0xD9F5,
            0x3183, 0x200A, 0x1291, 0x0318, 0x77A7, 0x662E, 0x54B5, 0x453C,
            0xBDCB, 0xAC42, 0x9ED9, 0x8F50, 0xFBEF, 0xEA66, 0xD8FD, 0xC974,
            0x4204, 0x538D, 0x6116, 0x709F, 0x0420, 0x15A9, 0x2732, 0x36BB,
            0xCE4C, 0xDFC5, 0xED5E, 0xFCD7, 0x8868, 0x99E1, 0xAB7A, 0xBAF3,
            0x5285, 0x430C, 0x7197, 0x601E, 0x14A1, 0x0528, 0x37B3, 0x263A,
            0xDECD, 0xCF44, 0xFDDF, 0xEC56, 0x98E9, 0x8960, 0xBBFB, 0xAA72,
            0x6306, 0x728F, 0x4014, 0x519D, 0x2522, 0x34AB, 0x0630, 0x17B9,
            0xEF4E, 0xFEC7, 0xCC5C, 0xDDD5, 0xA96A, 0xB8E3, 0x8A78, 0x9BF1,
            0x7387, 0x620E, 0x5095, 0x411C, 0x35A3, 0x242A, 0x16B1, 0x0738,
            0xFFCF, 0xEE46, 0xDCDD, 0xCD54, 0xB9EB, 0xA862, 0x9AF9, 0x8B70,
            0x8408, 0x9581, 0xA71A, 0xB693, 0xC22C, 0xD3A5, 0xE13E, 0xF0B7,
            0x0840, 0x19C9, 0x2B52, 0x3ADB, 0x4E64, 0x5FED, 0x6D76, 0x7CFF,
            0x9489, 0x8500, 0xB79B, 0xA612, 0xD2AD, 0xC324, 0xF1BF, 0xE036,
            0x18C1, 0x0948, 0x3BD3, 0x2A5A, 0x5EE5, 0x4F6C, 0x7DF7, 0x6C7E,
            0xA50A, 0xB483, 0x8618, 0x9791, 0xE32E, 0xF2A7, 0xC03C, 0xD1B5,
            0x2942, 0x38CB, 0x0A50, 0x1BD9, 0x6F66, 0x7EEF, 0x4C74, 0x5DFD,
            0xB58B, 0xA402, 0x9699, 0x8710, 0xF3AF, 0xE226, 0xD0BD, 0xC134,
            0x39C3, 0x284A, 0x1AD1, 0x0B58, 0x7FE7, 0x6E6E, 0x5CF5, 0x4D7C,
            0xC60C, 0xD785, 0xE51E, 0xF497, 0x8028, 0x91A1, 0xA33A, 0xB2B3,
            0x4A44, 0x5BCD, 0x6956, 0x78DF, 0x0C60, 0x1DE9, 0x2F72, 0x3EFB,
            0xD68D, 0xC704, 0xF59F, 0xE416, 0x90A9, 0x8120, 0xB3BB, 0xA232,
            0x5AC5, 0x4B4C, 0x79D7, 0x685E, 0x1CE1, 0x0D68, 0x3FF3, 0x2E7A,
            0xE70E, 0xF687, 0xC41C, 0xD595, 0xA12A, 0xB0A3, 0x8238, 0x93B1,
            0x6B46, 0x7ACF, 0x4854, 0x59DD, 0x2D62, 0x3CEB, 0x0E70, 0x1FF9,
            0xF78F, 0xE606, 0xD49D, 0xC514, 0xB1AB, 0xA022, 0x92B9, 0x8330,
            0x7BC7, 0x6A4E, 0x58D5, 0x495C, 0x3DE3, 0x2C6A, 0x1EF1, 0x0F78
        ]
        
        crc = 0xFFFF
        for byte in data:
            crc = (crc >> 8) ^ crc_table[(crc ^ byte) & 0xFF]
        
        return crc ^ 0xFFFF
    
    def parse_dlf_file(self, file_path: str) -> List[QXDMPacket]:
        """
        Parse a DLF file and extract all diagnostic packets
        
        DLF Format:
        - 2 bytes: packet length (little-endian, includes these 2 bytes)
        - N bytes: packet data (QXDM header + payload)
        
        QXDM Header (typically 12 bytes):
        - 2 bytes: length
        - 1 byte: command code / message ID low byte
        - 1 byte: message ID high byte (for extended IDs)
        - 8 bytes: timestamp
        
        Args:
            file_path: Path to the DLF file
            
        Returns:
            List of QXDMPacket objects
        """
        packets = []
        self.packets_parsed = 0
        self.errors = []
        
        try:
            with open(file_path, 'rb') as f:
                file_content = f.read()
                
            buffer = io.BytesIO(file_content)
            packet_number = 0
            
            while True:
                length_bytes = buffer.read(2)
                
                if len(length_bytes) < 2:
                    break
                
                packet_length = struct.unpack('<H', length_bytes)[0]
                
                if packet_length < 2 or packet_length > 65535:
                    self.errors.append(f"Invalid packet length at position {buffer.tell()-2}: {packet_length}")
                    break
                
                packet_data = buffer.read(packet_length - 2)
                
                if len(packet_data) < packet_length - 2:
                    self.errors.append(f"Incomplete packet at position {buffer.tell()}")
                    break
                
                try:
                    packet = self.parse_packet(packet_data, packet_number)
                    if packet:
                        packets.append(packet)
                        packet_number += 1
                        self.packets_parsed += 1
                        
                except Exception as e:
                    self.errors.append(f"Packet parse error at #{packet_number}: {e}")
                    continue
            
            print(f"DLF Parser: Extracted {len(packets)} packets from {file_path}")
            if self.errors:
                print(f"DLF Parser: {len(self.errors)} errors encountered")
                
        except Exception as e:
            self.errors.append(f"File read error: {e}")
            print(f"ERROR: Failed to parse DLF file {file_path}: {e}")
        
        return packets
    
    def parse_packet(self, packet_data: bytes, packet_number: int) -> Optional[QXDMPacket]:
        """
        Parse individual QXDM packet from DLF data
        
        Args:
            packet_data: Raw packet bytes (without length header)
            packet_number: Sequential packet number
            
        Returns:
            QXDMPacket object or None if parsing fails
        """
        if len(packet_data) < 4:
            return None
        
        message_id = packet_data[0]
        if len(packet_data) > 1:
            message_id_high = packet_data[1]
            message_id = message_id | (message_id_high << 8)
        
        timestamp = datetime.now()
        if len(packet_data) >= 12:
            timestamp_bytes = packet_data[4:12]
            timestamp = self.parse_qxdm_timestamp(timestamp_bytes)
        
        payload = packet_data
        
        packet = QXDMPacket(
            timestamp=timestamp,
            message_id=message_id,
            payload=payload,
            packet_number=packet_number
        )
        
        return packet
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get parsing statistics"""
        return {
            'packets_parsed': self.packets_parsed,
            'errors': len(self.errors),
            'error_messages': self.errors[:10]
        }
