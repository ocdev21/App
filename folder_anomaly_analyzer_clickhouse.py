#!/usr/bin/env python3
"""
Folder-based L1 Anomaly Detection System with ClickHouse Integration
Processes all PCAP and HDF5-converted text files in a directory with database storage
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

    def scan_folder(self, folder_path="/pvc/input_files"):
        """Scan folder for network files"""
        print(f"\nSCANNING FOLDER: {folder_path}")
        print("-" * 40)

        # Supported file patterns
        pcap_patterns = ['*.pcap', '*.cap', '*.pcapng']
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
            print("   Supported: .pcap, .cap, .pcapng, .txt, .log")
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

    def store_session_in_clickhouse(self, session_data):
        """Store analysis session in ClickHouse"""
        if not self.clickhouse_available or self.client is None:
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
        if not self.clickhouse_available or self.client is None or not anomalies:
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
                    str(anomaly.get('error_log', ''))  # NEW: Packet/event data for LLM analysis
                ]
                anomaly_records.append(record)

            # Bulk insert anomalies
            self.client.insert('anomalies', anomaly_records, column_names=[
                'id', 'file_path', 'file_type', 'packet_number', 'anomaly_type',
                'severity', 'description', 'details', 'ue_id', 'du_mac', 
                'ru_mac', 'timestamp', 'status', 'error_log'
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
                # Use ML anomaly detector for PCAP files with PVC-based incremental learning
                detector = MLAnomalyDetector(
                    models_dir="/pvc/models",
                    feature_history_dir="/pvc/feature_history",
                    retrain_threshold=10
                )
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

                self.pcap_files_processed += 1

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
        if self.clickhouse_available and self.client is not None:
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

def watch_folder(analyzer, folder_path, dummy_mode=False, check_interval=10):
    """Watch folder for new files and process them automatically"""
    import time
    
    processed_files = set()
    print(f"\n🔍 WATCH MODE: Monitoring {folder_path} for new files...")
    print(f"   Check interval: {check_interval} seconds")
    print("   Press Ctrl+C to stop\n")
    
    while True:
        try:
            # Scan for all files
            found_files = analyzer.scan_folder(folder_path)
            
            # Filter out already processed files
            new_files = []
            for file_info in found_files:
                if file_info['path'] not in processed_files:
                    new_files.append(file_info)
                    processed_files.add(file_info['path'])
            
            # Process new files
            if new_files:
                print(f"\n📁 Detected {len(new_files)} new file(s):")
                for f in new_files:
                    print(f"   - {f['name']} ({f['type']}, {f['size']/1024:.1f} KB)")
                
                session_id = int(datetime.now().timestamp())
                all_anomalies = []
                start_time = datetime.now()
                
                # Process each new file
                for file_info in new_files:
                    file_anomalies = analyzer.process_single_file(file_info)
                    all_anomalies.extend(file_anomalies)
                
                # Store results
                if not dummy_mode and analyzer.clickhouse_available:
                    session_data = {
                        'id': session_id,
                        'session_name': f"Watch Mode: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
                        'folder_path': folder_path,
                        'total_files': len(new_files),
                        'pcap_files': sum(1 for f in new_files if f['type'] == 'PCAP'),
                        'text_files': sum(1 for f in new_files if f['type'] == 'TEXT'),
                        'total_anomalies': len(all_anomalies),
                        'start_time': start_time,
                        'end_time': datetime.now(),
                        'duration_seconds': int((datetime.now() - start_time).total_seconds())
                    }
                    analyzer.store_session_in_clickhouse(session_data)
                    analyzer.store_anomalies_in_clickhouse(all_anomalies, session_id)
                
                print(f"✅ Processed {len(new_files)} file(s), found {len(all_anomalies)} anomalies")
                print(f"   Total files processed: {len(processed_files)}")
            
            # Wait before next check
            time.sleep(check_interval)
            
        except KeyboardInterrupt:
            print("\n\n⏹️  Watch mode stopped by user")
            print(f"Total files processed: {len(processed_files)}")
            break
        except Exception as e:
            print(f"ERROR in watch loop: {e}")
            time.sleep(check_interval)

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

    # Parse command line arguments
    import argparse
    parser = argparse.ArgumentParser(description='L1 Anomaly Detection System')
    parser.add_argument('folder_path', nargs='?', default='/pvc/input_files', help='Folder to process')
    parser.add_argument('--watch', action='store_true', help='Watch mode: continuously monitor for new files')
    parser.add_argument('--interval', type=int, default=10, help='Watch mode check interval in seconds (default: 10)')
    parser.add_argument('--dummy', action='store_true', help='Dummy mode: skip database writes')
    parser.add_argument('--input-dir', type=str, help='Alternative way to specify input directory')
    
    args = parser.parse_args()
    
    # Use input-dir if provided
    folder_path = args.input_dir if args.input_dir else args.folder_path
    dummy_mode = args.dummy
    
    if dummy_mode:
        print("\nRUNNING IN DUMMY MODE - Database writes disabled")
        print("Results will only be shown in console and report file")
    
    if args.watch:
        print(f"\n🔄 WATCH MODE ENABLED - Continuous monitoring")
    
    print(f"\nUsing folder: {folder_path}")

    if not os.path.exists(folder_path):
        print(f"\nERROR: Folder '{folder_path}' does not exist")
        if folder_path == "/pvc/input_files":
            print("TIP: Upload PCAP/text files to /pvc/input_files directory")
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

    # Choose mode: watch or single-run
    if args.watch:
        # WATCH MODE: Continuously monitor for new files
        watch_folder(analyzer, folder_path, dummy_mode, args.interval)
    else:
        # SINGLE-RUN MODE: Process existing files once
        # Scan folder for files
        found_files = analyzer.scan_folder(folder_path)

        if not found_files:
            print("\nNo files found to process")
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
            'start_time': datetime.now(),
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

        session_data['end_time'] = end_time
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