#!/usr/bin/env python3
"""
ML Anomaly Detection Module with Joblib Persistence
Provides MLAnomalyDetector class for PCAP analysis with model persistence
"""

import os
import numpy as np
import joblib
from datetime import datetime
from collections import defaultdict
import warnings
warnings.filterwarnings('ignore')

try:
    from scapy.all import rdpcap, Ether
    from sklearn.ensemble import IsolationForest
    from sklearn.svm import OneClassSVM
    from sklearn.cluster import DBSCAN
    from sklearn.neighbors import LocalOutlierFactor
    from sklearn.preprocessing import StandardScaler
    SCAPY_AVAILABLE = True
    ML_AVAILABLE = True
except ImportError as e:
    print(f"WARNING: ML/Scapy libraries not available: {e}")
    SCAPY_AVAILABLE = False
    ML_AVAILABLE = False

class MLAnomalyDetector:
    """ML-based anomaly detection for PCAP files with model persistence"""
    
    def __init__(self, models_dir="/pvc/models", feature_history_dir="/pvc/feature_history", retrain_threshold=10):
        """Initialize detector with incremental learning support"""
        self.models_dir = models_dir
        self.feature_history_dir = feature_history_dir
        self.retrain_threshold = retrain_threshold
        
        os.makedirs(models_dir, exist_ok=True)
        os.makedirs(feature_history_dir, exist_ok=True)
        
        # Equipment MAC addresses (from folder_anomaly_analyzer_clickhouse.py)
        self.DU_MAC = "00:11:22:33:44:67"
        self.RU_MAC = "6c:ad:ad:00:03:2a"
        
        # Time window for analysis (100ms)
        self.time_window = 0.1
        
        if ML_AVAILABLE and SCAPY_AVAILABLE:
            self.models = self.load_or_create_models()
            self.metadata = self.load_metadata()
            self.models_trained = self.check_if_models_trained()
            print(f"MLAnomalyDetector initialized with models in {models_dir}")
            print(f"Incremental learning: {self.metadata['files_processed']} files processed, threshold={retrain_threshold}")
        else:
            print("WARNING: MLAnomalyDetector created in limited mode (no ML/Scapy)")
            self.models = {}
            self.metadata = {}
            self.models_trained = False
    
    def load_or_create_models(self):
        """Load existing models or create new ones with joblib persistence"""
        model_files = {
            'isolation_forest': f"{self.models_dir}/isolation_forest.pkl",
            'one_class_svm': f"{self.models_dir}/one_class_svm.pkl", 
            'dbscan': f"{self.models_dir}/dbscan.pkl",
            'scaler': f"{self.models_dir}/scaler.pkl"
        }
        
        models = {}
        
        for model_name, pkl_file in model_files.items():
            if os.path.exists(pkl_file):
                try:
                    print(f"Loading {model_name} from {pkl_file}")
                    models[model_name] = joblib.load(pkl_file)
                    print(f"Successfully loaded {model_name}")
                except Exception as e:
                    print(f"ERROR: Failed to load {model_name}: {e}")
                    models[model_name] = self.create_fresh_model(model_name)
            else:
                print(f"Creating new {model_name}")
                models[model_name] = self.create_fresh_model(model_name)
        
        return models
    
    def create_fresh_model(self, model_name):
        """Create a fresh model instance with tuned parameters"""
        if model_name == 'isolation_forest':
            return IsolationForest(
                contamination=0.05,  # More sensitive: 5% instead of 10%
                random_state=42,
                n_estimators=100
            )
        elif model_name == 'one_class_svm':
            return OneClassSVM(
                nu=0.05,  # More sensitive: 5% instead of 10%
                gamma='auto',
                kernel='rbf'
            )
        elif model_name == 'dbscan':
            return DBSCAN(
                eps=0.5, 
                min_samples=5
            )
        elif model_name == 'scaler':
            return StandardScaler()
        else:
            return None
    
    def load_metadata(self):
        """Load or create metadata for incremental learning tracking"""
        metadata_file = f"{self.models_dir}/metadata.json"
        if os.path.exists(metadata_file):
            try:
                import json
                with open(metadata_file, 'r') as f:
                    metadata = json.load(f)
                print(f"Loaded metadata: {metadata['files_processed']} files processed")
                return metadata
            except Exception as e:
                print(f"WARNING: Failed to load metadata: {e}")
        
        # Create new metadata
        return {
            'files_processed': 0,
            'last_retrain': None,
            'model_versions': {},
            'created_at': datetime.now().isoformat()
        }
    
    def check_if_models_trained(self):
        """Check if models have been trained (not just initialized)"""
        metadata_file = f"{self.models_dir}/metadata.json"
        if os.path.exists(metadata_file):
            try:
                import json
                with open(metadata_file, 'r') as f:
                    metadata = json.load(f)
                return metadata.get('last_retrain') is not None
            except:
                pass
        return False
    
    def save_metadata(self):
        """Save metadata to file"""
        import json
        try:
            with open(f"{self.models_dir}/metadata.json", 'w') as f:
                json.dump(self.metadata, f, indent=2)
        except Exception as e:
            print(f"WARNING: Failed to save metadata: {e}")
    
    def save_features_for_training(self, features_array):
        """Accumulate features for incremental learning"""
        feature_file = f"{self.feature_history_dir}/accumulated_features.npy"
        try:
            if os.path.exists(feature_file):
                # Load existing features and append new ones
                existing_features = np.load(feature_file, allow_pickle=True)
                combined_features = np.vstack([existing_features, features_array])
                np.save(feature_file, combined_features)
                print(f"Accumulated features: {len(combined_features)} total windows")
            else:
                # Save new features
                np.save(feature_file, features_array)
                print(f"Saved {len(features_array)} feature windows for training")
        except Exception as e:
            print(f"WARNING: Failed to save features: {e}")
    
    def retrain_models(self):
        """Retrain models on all accumulated features"""
        feature_file = f"{self.feature_history_dir}/accumulated_features.npy"
        
        if not os.path.exists(feature_file):
            print("No accumulated features found for retraining")
            return
        
        try:
            # Load all accumulated features
            all_features = np.load(feature_file, allow_pickle=True)
            print(f"Retraining models on {len(all_features)} accumulated feature windows")
            
            # Retrain scaler
            self.models['scaler'].fit(all_features)
            features_scaled = self.models['scaler'].transform(all_features)
            
            # Retrain ML models
            self.models['isolation_forest'].fit(features_scaled)
            self.models['one_class_svm'].fit(features_scaled)
            
            # Reset file counter and clear accumulated features BEFORE saving
            self.metadata['files_processed'] = 0
            os.remove(feature_file)
            
            # Save retrained models with timestamp update
            self.save_models(update_retrain_timestamp=True)
            
            print("Models retrained successfully! Counter reset to 0")
            
        except Exception as e:
            print(f"ERROR: Failed to retrain models: {e}")
    
    def save_models(self, update_retrain_timestamp=False):
        """Save trained models as .pkl files using joblib"""
        if not self.models:
            print("WARNING: No models to save")
            return
        
        print(f"Saving models to {self.models_dir}/")
        
        try:
            for model_name, model in self.models.items():
                pkl_file = f"{self.models_dir}/{model_name}.pkl"
                joblib.dump(model, pkl_file)
                print(f"Saved {model_name} to {pkl_file}")
            
            # Update in-memory metadata if retraining occurred
            if update_retrain_timestamp:
                self.metadata['last_retrain'] = datetime.now().isoformat()
            
            # Save metadata as JSON (use in-memory metadata)
            import json
            with open(f"{self.models_dir}/metadata.json", 'w') as f:
                json.dump(self.metadata, f, indent=2)
            print("All models and metadata saved successfully!")
            
        except Exception as e:
            print(f"ERROR: Error saving models: {e}")
    
    def analyze_pcap(self, pcap_file):
        """Analyze PCAP file and return anomalies (main interface method)"""
        if not SCAPY_AVAILABLE or not ML_AVAILABLE:
            return {
                'error': 'Scapy or ML libraries not available',
                'anomalies': []
            }
        
        try:
            print(f"Analyzing PCAP: {os.path.basename(pcap_file)}")
            
            # Load packets
            packets = rdpcap(pcap_file)
            print(f"Loaded {len(packets)} packets")
            
            if len(packets) < 10:
                return {
                    'warning': f'Too few packets ({len(packets)}) for reliable ML analysis',
                    'anomalies': []
                }
            
            # Extract features using the same logic as unified_l1_analyzer
            features, packet_metadata = self.extract_pcap_features_basic(packets)
            
            if len(features) < 3:
                return {
                    'warning': f'Insufficient feature windows ({len(features)}) for ML analysis',
                    'anomalies': []
                }
            
            # Run ML analysis with ensemble voting (includes incremental learning)
            anomalies = self.run_ml_ensemble_analysis(features, packet_metadata)
            
            return {
                'total_packets': len(packets),
                'feature_windows': len(features),
                'anomalies': anomalies,
                'analysis_time': datetime.now().isoformat()
            }
            
        except Exception as e:
            print(f"ERROR: Error analyzing PCAP {pcap_file}: {e}")
            return {
                'error': str(e),
                'anomalies': []
            }
    
    def extract_pcap_features_basic(self, packets):
        """Extract enhanced 16-dimensional features from PCAP packets with time-series analysis"""
        features = []
        packet_metadata = []
        
        # Group packets by time windows (100ms)
        time_windows = defaultdict(list)
        start_time = packets[0].time if packets else 0
        
        for i, packet in enumerate(packets):
            try:
                window_index = int((packet.time - start_time) / self.time_window)
                time_windows[window_index].append((i, packet))
            except:
                continue
        
        print(f"Created {len(time_windows)} time windows of {self.time_window}s each")
        print(f"Looking for DU MAC: {self.DU_MAC} and RU MAC: {self.RU_MAC}")
        
        # Extract features for each time window
        for window_idx, window_packets in time_windows.items():
            try:
                window_features = self.extract_window_features(window_packets)
                if window_features:
                    features.append(window_features)
                    packet_metadata.append({
                        'window_index': window_idx,
                        'packet_count': len(window_packets),
                        'start_packet': window_packets[0][0] if window_packets else 0,
                        'end_packet': window_packets[-1][0] if window_packets else 0
                    })
            except Exception as e:
                print(f"Warning: Failed to extract features for window {window_idx}: {e}")
                continue
        
        return features, packet_metadata
    
    def extract_window_features(self, window_packets):
        """Extract enhanced 16-dimensional feature vector with time-series and statistical features"""
        if not window_packets:
            return None
        
        du_count = 0
        ru_count = 0
        inter_arrival_times = []
        packet_sizes = []
        response_times = []
        missing_responses = 0
        du_timestamps = []
        ru_timestamps = []
        
        previous_time = None
        
        for packet_idx, packet in window_packets:
            try:
                if packet.haslayer(Ether):
                    eth_layer = packet[Ether]
                    src_mac = eth_layer.src.lower()
                    dst_mac = eth_layer.dst.lower()
                    
                    # Count DU and RU packets and track timestamps
                    if src_mac == self.DU_MAC.lower():
                        du_count += 1
                        du_timestamps.append(packet.time)
                    elif src_mac == self.RU_MAC.lower():
                        ru_count += 1
                        ru_timestamps.append(packet.time)
                    
                    # Calculate inter-arrival times
                    if previous_time is not None:
                        inter_arrival = packet.time - previous_time
                        if inter_arrival > 0:
                            inter_arrival_times.append(inter_arrival)
                    previous_time = packet.time
                    
                    # Collect packet sizes
                    packet_sizes.append(len(packet))
                
            except Exception:
                continue
        
        # Calculate derived metrics
        total_packets = len(window_packets)
        communication_ratio = ru_count / du_count if du_count > 0 else 0
        missing_responses = max(0, du_count - ru_count)
        
        # Enhanced time-series features
        avg_inter_arrival = np.mean(inter_arrival_times) if inter_arrival_times else 0
        std_inter_arrival = np.std(inter_arrival_times) if len(inter_arrival_times) > 1 else 0
        jitter = std_inter_arrival  # Jitter is std deviation of inter-arrival times
        max_gap = max(inter_arrival_times) if inter_arrival_times else 0
        min_gap = min(inter_arrival_times) if inter_arrival_times else 0
        
        # Response time analysis (time between DU request and RU response)
        avg_response_time = 0
        if du_timestamps and ru_timestamps:
            response_gaps = []
            for du_time in du_timestamps:
                # Find closest RU response after this DU packet
                later_ru = [ru for ru in ru_timestamps if ru > du_time]
                if later_ru:
                    response_gaps.append(min(later_ru) - du_time)
            avg_response_time = np.mean(response_gaps) if response_gaps else 0
        
        response_violations = 1 if avg_response_time > 0.001 else 0  # 1ms threshold
        
        # Statistical baselines for packet sizes
        avg_size = np.mean(packet_sizes) if packet_sizes else 0
        std_size = np.std(packet_sizes) if len(packet_sizes) > 1 else 0
        size_variance = np.var(packet_sizes) if len(packet_sizes) > 1 else 0
        
        # Packet rate (packets per second)
        window_duration = window_packets[-1][1].time - window_packets[0][1].time if len(window_packets) > 1 else 0.1
        packet_rate = total_packets / window_duration if window_duration > 0 else 0
        
        # Return enhanced 16-dimensional feature vector
        return [
            du_count,
            ru_count, 
            communication_ratio,
            missing_responses,
            avg_inter_arrival,
            std_inter_arrival,  # NEW: Standard deviation of inter-arrival times
            jitter,
            max_gap,
            min_gap,
            avg_response_time,  # ENHANCED: True response time calculation
            response_violations,
            avg_size,
            std_size,  # NEW: Standard deviation of packet sizes
            size_variance,
            packet_rate,  # NEW: Packet rate (pps)
            total_packets  # NEW: Total packet count in window
        ]
    
    def run_ml_ensemble_analysis(self, features, packet_metadata):
        """Run ML ensemble analysis with incremental learning"""
        print(f"Running ML ensemble analysis on {len(features)} feature windows")
        
        # Convert to numpy array
        features_array = np.array(features)
        
        # Save features for incremental learning
        self.save_features_for_training(features_array)
        
        # Increment file counter BEFORE threshold check
        self.metadata['files_processed'] += 1
        
        # Check if we should retrain models (after incrementing counter)
        if self.metadata['files_processed'] >= self.retrain_threshold:
            print(f"Retraining threshold ({self.retrain_threshold}) reached, retraining models...")
            self.retrain_models()
        
        # Use trained models for inference OR train new models if not trained
        if self.models_trained:
            # INFERENCE MODE: Use existing models (no retraining)
            features_scaled = self.models['scaler'].transform(features_array)
            print("Features normalized with existing scaler (inference mode)")
            
            iso_predictions = self.models['isolation_forest'].predict(features_scaled)
            svm_predictions = self.models['one_class_svm'].predict(features_scaled)
            dbscan_labels = self.models['dbscan'].fit_predict(features_scaled)  # DBSCAN always needs fit_predict
        else:
            # TRAINING MODE: First-time training
            print("First-time training mode - fitting models on current data")
            features_scaled = self.models['scaler'].fit_transform(features_array)
            
            iso_predictions = self.models['isolation_forest'].fit_predict(features_scaled)
            svm_predictions = self.models['one_class_svm'].fit_predict(features_scaled)
            dbscan_labels = self.models['dbscan'].fit_predict(features_scaled)
            
            # Mark as trained and save with timestamp
            self.models_trained = True
            self.save_models(update_retrain_timestamp=True)
        
        # LOF requires a separate instance (doesn't persist well)
        lof = LocalOutlierFactor(n_neighbors=min(20, len(features)), contamination=0.05)
        lof_predictions = lof.fit_predict(features_scaled)
        
        # Save metadata (counter already incremented earlier)
        self.save_metadata()
        
        print(f"ML analysis complete (Files processed: {self.metadata['files_processed']})")
        
        # Enhanced ensemble voting (≥1 algorithm flags = anomaly, more sensitive)
        anomalies = []
        for i in range(len(features)):
            votes = 0
            algorithm_votes = {}
            
            if iso_predictions[i] == -1:
                votes += 1
                algorithm_votes['isolation_forest'] = True
            if svm_predictions[i] == -1:
                votes += 1  
                algorithm_votes['one_class_svm'] = True
            if dbscan_labels[i] == -1:
                votes += 1
                algorithm_votes['dbscan'] = True
            if lof_predictions[i] == -1:
                votes += 1
                algorithm_votes['lof'] = True
            
            # More sensitive: ≥1 algorithm flags anomaly (was ≥2)
            if votes >= 1:
                # Capture packet details for error_log
                error_log = f"Packet #{packet_metadata[i]['start_packet']}: DU packets={int(features[i][0])}, RU packets={int(features[i][1])}, Communication ratio={float(features[i][2]):.3f}, Missing responses={int(features[i][3])}, Avg response time={float(features[i][9])*1000:.2f}ms, Jitter={float(features[i][6])*1000:.2f}ms"
                
                anomaly = {
                    'window_index': i,
                    'packet_number': packet_metadata[i]['start_packet'],
                    'confidence': votes / 4.0,  # 0.25 to 1.0
                    'algorithms_voting': algorithm_votes,
                    'feature_values': features[i],
                    'missing_responses': int(features[i][3]),
                    'communication_ratio': float(features[i][2]),
                    'timing_violation': features[i][10] > 0,  # Updated index for response_violations
                    'avg_response_time': float(features[i][9]),  # New: actual response time
                    'packet_rate': float(features[i][14]),  # New: packet rate
                    'std_inter_arrival': float(features[i][5]),  # New: timing variation
                    'error_log': error_log  # NEW: Packet details for LLM analysis
                }
                anomalies.append(anomaly)
                print(f"WARNING: Anomaly in window {i}: {votes}/4 algorithms agree, confidence={votes/4.0:.2f}")
        
        print(f"Found {len(anomalies)} anomalies (>=1 algorithm agreement, enhanced sensitivity)")
        return anomalies

# Test function for standalone usage
def main():
    """Test the MLAnomalyDetector"""
    if len(sys.argv) != 2:
        print("Usage: python ml_anomaly_detection.py <pcap_file>")
        return
    
    pcap_file = sys.argv[1]
    detector = MLAnomalyDetector()
    result = detector.analyze_pcap(pcap_file)
    
    print("\n" + "="*50)
    print("ML ANOMALY DETECTION RESULTS")
    print("="*50)
    print(f"Total packets: {result.get('total_packets', 'N/A')}")
    print(f"Feature windows: {result.get('feature_windows', 'N/A')}")
    print(f"Anomalies found: {len(result.get('anomalies', []))}")
    
    for i, anomaly in enumerate(result.get('anomalies', [])[:5]):
        print(f"\nAnomaly {i+1}:")
        print(f"  Packet: {anomaly['packet_number']}")
        print(f"  Confidence: {anomaly['confidence']:.2f}")
        print(f"  Missing responses: {anomaly['missing_responses']}")
        print(f"  Communication ratio: {anomaly['communication_ratio']:.3f}")

if __name__ == "__main__":
    import sys
    main()