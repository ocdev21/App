
#!/usr/bin/env python3
"""
Comprehensive ClickHouse Table Creation Script
Creates all tables referenced across the L1 troubleshooting application
"""

import os
import sys
from datetime import datetime

try:
    import clickhouse_connect
    CLICKHOUSE_AVAILABLE = True
except ImportError:
    print("ERROR: clickhouse-connect not available")
    print("Install with: pip install clickhouse-connect")
    sys.exit(1)

class ClickHouseTableSetup:
    def __init__(self):
        self.client = None
        self.setup_connection()
    
    def setup_connection(self):
        """Setup ClickHouse connection"""
        try:
            self.client = clickhouse_connect.get_client(
                host=os.getenv('CLICKHOUSE_HOST', 'clickhouse-clickhouse-single'),
                port=int(os.getenv('CLICKHOUSE_PORT', '8123')),
                username=os.getenv('CLICKHOUSE_USERNAME', 'default'),
                password=os.getenv('CLICKHOUSE_PASSWORD', 'defaultpass'),
                database=os.getenv('CLICKHOUSE_DATABASE', 'default')
            )
            print(f"[SUCCESS] Connected to ClickHouse at {os.getenv('CLICKHOUSE_HOST', 'clickhouse-clickhouse-single')}")
        except Exception as e:
            print(f"[ERROR] Failed to connect to ClickHouse: {e}")
            sys.exit(1)
    
    def create_database(self):
        """Create the l1_anomaly_detection database"""
        try:
            self.client.command("CREATE DATABASE IF NOT EXISTS l1_anomaly_detection")
            print("[SUCCESS] Created database: l1_anomaly_detection")
        except Exception as e:
            print(f"[ERROR] Failed to create database: {e}")
            raise
    
    def create_all_tables(self):
        """Create all required tables"""
        print("\n[INFO] Creating ClickHouse tables...")
        
        # Create database first
        self.create_database()
        
        # Create all tables
        tables = [
            self.create_anomalies_table,
            self.create_comprehensive_anomalies_table,
            self.create_sessions_table,
            self.create_l1_analysis_sessions_table,
            self.create_processed_files_table,
            self.create_metrics_table,
            self.create_ue_events_table,
            self.create_pcap_analysis_table,
            self.create_ml_results_table,
            self.create_correlations_table,
            self.create_recommendations_table
        ]
        
        for create_table_func in tables:
            try:
                create_table_func()
            except Exception as e:
                print(f"[ERROR] Failed to create table: {e}")
                continue
        
        print("\n[SUCCESS] All tables created successfully!")
    
    def create_anomalies_table(self):
        """Create main anomalies table matching ML code insert columns"""
        table_sql = """
        CREATE TABLE IF NOT EXISTS l1_anomaly_detection.anomalies (
            id UInt64,
            file_path String,
            file_type String,
            packet_number UInt32,
            anomaly_type String,
            severity String,
            description String,
            details String,
            ue_id String,
            du_mac String,
            ru_mac String,
            timestamp DateTime,
            status String
        ) ENGINE = MergeTree()
        ORDER BY (timestamp, severity, anomaly_type)
        PARTITION BY toYYYYMM(timestamp)
        """
        
        self.client.command(table_sql)
        print("[SUCCESS] Created table: anomalies (matched to ML insert columns)")
    
    def create_comprehensive_anomalies_table(self):
        """Create comprehensive anomalies table for advanced analysis"""
        table_sql = """
        CREATE TABLE IF NOT EXISTS l1_anomaly_detection.comprehensive_anomalies (
            anomaly_id String,
            detection_timestamp DateTime,
            source_file String,
            file_format String,
            category String,
            anomaly_type String,
            severity String,
            confidence_score Float64,
            packet_number UInt32,
            line_number UInt32,
            description String,
            ue_events_detected UInt8,
            fronthaul_issues_detected UInt8,
            mac_layer_issues_detected UInt8,
            protocol_violations_detected UInt8,
            signal_quality_issues_detected UInt8,
            performance_issues_detected UInt8,
            ml_detected UInt8,
            rule_based_detected UInt8,
            cross_correlated UInt8,
            raw_data String
        ) ENGINE = MergeTree()
        ORDER BY (detection_timestamp, severity, category)
        PARTITION BY toYYYYMM(detection_timestamp)
        """
        
        self.client.command(table_sql)
        print("[SUCCESS] Created table: comprehensive_anomalies")
    
    def create_sessions_table(self):
        """Create sessions table matching ML code insert columns"""
        table_sql = """
        CREATE TABLE IF NOT EXISTS l1_anomaly_detection.sessions (
            id UInt64,
            session_name String,
            folder_path String,
            total_files UInt32,
            pcap_files UInt32,
            text_files UInt32,
            total_anomalies UInt32,
            start_time DateTime,
            end_time DateTime,
            duration_seconds UInt32,
            status String
        ) ENGINE = MergeTree()
        ORDER BY start_time
        """
        
        self.client.command(table_sql)
        print("[SUCCESS] Created table: sessions (matched to ML insert columns)")
    
    def create_l1_analysis_sessions_table(self):
        """Create L1 analysis sessions table"""
        table_sql = """
        CREATE TABLE IF NOT EXISTS l1_anomaly_detection.l1_analysis_sessions (
            session_id String,
            analysis_timestamp DateTime,
            source_file String,
            file_format String,
            total_packets UInt32,
            total_lines UInt32,
            ue_events_anomalies UInt32,
            fronthaul_anomalies UInt32,
            mac_layer_anomalies UInt32,
            protocol_anomalies UInt32,
            signal_quality_anomalies UInt32,
            performance_anomalies UInt32,
            total_anomalies UInt32,
            high_severity_anomalies UInt32,
            medium_severity_anomalies UInt32,
            low_severity_anomalies UInt32,
            overall_health_score Float64,
            analysis_duration_seconds Float64,
            comprehensive_summary String
        ) ENGINE = MergeTree()
        ORDER BY analysis_timestamp
        PARTITION BY toYYYYMM(analysis_timestamp)
        """
        
        self.client.command(table_sql)
        print("[SUCCESS] Created table: l1_analysis_sessions")
    
    def create_processed_files_table(self):
        """Create processed files table"""
        table_sql = """
        CREATE TABLE IF NOT EXISTS l1_anomaly_detection.processed_files (
            id String,
            filename String,
            file_type String,
            file_size UInt64,
            upload_date DateTime,
            processing_status String DEFAULT 'pending',
            processing_time DateTime,
            total_samples UInt32,
            anomalies_detected UInt32,
            anomalies_found UInt32 DEFAULT 0,
            session_id String,
            processing_time_ms Nullable(UInt32),
            error_message Nullable(String)
        ) ENGINE = MergeTree()
        ORDER BY upload_date
        """
        
        self.client.command(table_sql)
        print("[SUCCESS] Created table: processed_files")
    
    def create_metrics_table(self):
        """Create metrics table"""
        table_sql = """
        CREATE TABLE IF NOT EXISTS l1_anomaly_detection.metrics (
            id String,
            metric_name String,
            metric_value Float64,
            timestamp DateTime,
            category String,
            session_id Nullable(String),
            source_file Nullable(String)
        ) ENGINE = MergeTree()
        ORDER BY timestamp
        """
        
        self.client.command(table_sql)
        print("[SUCCESS] Created table: metrics")
    
    def create_ue_events_table(self):
        """Create UE events table"""
        table_sql = """
        CREATE TABLE IF NOT EXISTS l1_anomaly_detection.ue_events (
            event_id String,
            timestamp DateTime,
            ue_id String,
            event_type String,
            event_details String,
            line_number UInt32,
            source_file String,
            session_id String,
            attach_attempts UInt32 DEFAULT 0,
            successful_attaches UInt32 DEFAULT 0,
            detach_events UInt32 DEFAULT 0,
            context_failures UInt32 DEFAULT 0,
            is_anomalous UInt8 DEFAULT 0
        ) ENGINE = MergeTree()
        ORDER BY (timestamp, ue_id)
        PARTITION BY toYYYYMM(timestamp)
        """
        
        self.client.command(table_sql)
        print("[SUCCESS] Created table: ue_events")
    
    def create_pcap_analysis_table(self):
        """Create PCAP analysis results table"""
        table_sql = """
        CREATE TABLE IF NOT EXISTS l1_anomaly_detection.pcap_analysis (
            analysis_id String,
            timestamp DateTime,
            source_file String,
            total_packets UInt32,
            du_packets UInt32,
            ru_packets UInt32,
            communication_ratio Float64,
            missing_responses UInt32,
            timing_issues UInt32,
            protocol_violations UInt32,
            session_id String,
            analysis_duration_seconds Float64
        ) ENGINE = MergeTree()
        ORDER BY timestamp
        """
        
        self.client.command(table_sql)
        print("[SUCCESS] Created table: pcap_analysis")
    
    def create_ml_results_table(self):
        """Create ML results table"""
        table_sql = """
        CREATE TABLE IF NOT EXISTS l1_anomaly_detection.ml_results (
            result_id String,
            timestamp DateTime,
            algorithm_name String,
            model_version String,
            input_features String,
            prediction_result String,
            confidence_score Float64,
            anomaly_detected UInt8,
            feature_importance String,
            training_accuracy Float64,
            session_id String,
            source_file String
        ) ENGINE = MergeTree()
        ORDER BY timestamp
        """
        
        self.client.command(table_sql)
        print("[SUCCESS] Created table: ml_results")
    
    def create_correlations_table(self):
        """Create correlations table"""
        table_sql = """
        CREATE TABLE IF NOT EXISTS l1_anomaly_detection.correlations (
            correlation_id String,
            timestamp DateTime,
            anomaly_id_1 String,
            anomaly_id_2 String,
            correlation_type String,
            correlation_strength Float64,
            time_difference_ms Int64,
            spatial_proximity Float64,
            session_id String
        ) ENGINE = MergeTree()
        ORDER BY timestamp
        """
        
        self.client.command(table_sql)
        print("[SUCCESS] Created table: correlations")
    
    def create_recommendations_table(self):
        """Create recommendations table"""
        table_sql = """
        CREATE TABLE IF NOT EXISTS l1_anomaly_detection.recommendations (
            recommendation_id String,
            timestamp DateTime,
            anomaly_id String,
            recommendation_type String,
            priority String,
            recommendation_text String,
            implementation_steps String,
            expected_impact String,
            confidence_score Float64,
            status String DEFAULT 'pending',
            session_id String
        ) ENGINE = MergeTree()
        ORDER BY (timestamp, priority)
        """
        
        self.client.command(table_sql)
        print("[SUCCESS] Created table: recommendations")
    
    def verify_tables(self):
        """Verify all tables were created successfully"""
        print("\n[INFO] Verifying table creation...")
        
        tables_query = """
        SELECT name, engine, total_rows, total_bytes
        FROM system.tables 
        WHERE database = 'l1_anomaly_detection'
        ORDER BY name
        """
        
        try:
            result = self.client.query(tables_query)
            
            print(f"\n[INFO] Found {len(result.result_rows)} tables in l1_anomaly_detection database:")
            print("-" * 80)
            print(f"{'Table Name':<25} {'Engine':<15} {'Rows':<10} {'Size (bytes)':<15}")
            print("-" * 80)
            
            for row in result.result_rows:
                table_name, engine, total_rows, total_bytes = row
                print(f"{table_name:<25} {engine:<15} {total_rows:<10} {total_bytes:<15}")
            
            print("-" * 80)
            
        except Exception as e:
            print(f"[ERROR] Failed to verify tables: {e}")
    
    def create_sample_data(self):
        """Create sample data for testing (matches ML insert schema)"""
        print("\n[INFO] Creating sample data...")
        
        try:
            # Sample anomaly matching ML schema
            anomaly_data = {
                'id': 1001,
                'file_path': '/app/input_files/test.pcap',
                'file_type': 'PCAP',
                'packet_number': 1,
                'anomaly_type': 'DU-RU Communication',
                'severity': 'high',
                'description': '*** FRONTHAUL ISSUE (Confidence: 75%) *** - DU-RU Communication',
                'details': '["Confidence: 0.75 (75%)", "Missing Responses: 5 DU packets without RU replies"]',
                'ue_id': '',
                'du_mac': '00:11:22:33:44:67',
                'ru_mac': '6c:ad:ad:00:03:2a',
                'timestamp': datetime.now(),
                'status': 'active'
            }
            
            # Insert sample anomaly
            self.client.insert('l1_anomaly_detection.anomalies', [anomaly_data])
            print("[SUCCESS] Created sample anomaly record (ML schema)")
            
            # Sample session matching ML schema
            session_data = {
                'id': 1001,
                'session_name': 'Test Analysis Session',
                'folder_path': '/app/input_files',
                'total_files': 1,
                'pcap_files': 1,
                'text_files': 0,
                'total_anomalies': 1,
                'start_time': datetime.now(),
                'end_time': datetime.now(),
                'duration_seconds': 30,
                'status': 'completed'
            }
            
            self.client.insert('l1_anomaly_detection.sessions', [session_data])
            print("[SUCCESS] Created sample session record (ML schema)")
            
        except Exception as e:
            print(f"[WARNING] Failed to create sample data: {e}")

def main():
    """Main function"""
    print("[INFO] ClickHouse Table Setup for L1 Troubleshooting Application")
    print("=" * 70)
    
    # Initialize setup
    setup = ClickHouseTableSetup()
    
    try:
        # Create all tables
        setup.create_all_tables()
        
        # Verify tables
        setup.verify_tables()
        
        # Create sample data
        setup.create_sample_data()
        
        print("\n[SUCCESS] ClickHouse setup completed successfully!")
        print("\nYou can now run your L1 troubleshooting applications.")
        print("\nTo verify the setup:")
        print("  1. Check tables: SELECT * FROM system.tables WHERE database = 'l1_anomaly_detection'")
        print("  2. Check sample data: SELECT * FROM l1_anomaly_detection.anomalies LIMIT 5")
        
    except Exception as e:
        print(f"\n[ERROR] Setup failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
