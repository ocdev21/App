#!/usr/bin/env python3
"""
ML-based UE Event Anomaly Detection
Uses machine learning ensemble to detect sophisticated patterns in UE attach/detach events
"""

import numpy as np
from sklearn.ensemble import IsolationForest
from sklearn.cluster import DBSCAN
from sklearn.svm import OneClassSVM
from sklearn.neighbors import LocalOutlierFactor
from sklearn.preprocessing import StandardScaler
from collections import defaultdict
from datetime import datetime
import json

class MLUEEventAnalyzer:
    def __init__(self):
        self.scaler = StandardScaler()
        
    def extract_features(self, ue_events):
        """Extract ML features from UE events grouped by UE ID"""
        ue_sessions = defaultdict(list)
        
        # Group events by UE ID
        for event in ue_events:
            ue_id = event['ue_id']
            ue_sessions[ue_id].append(event)
        
        features = []
        ue_ids = []
        event_metadata = []
        
        for ue_id, events in ue_sessions.items():
            events.sort(key=lambda x: x['timestamp'])
            
            # Feature 1-2: Event counts
            attach_events = [e for e in events if e['event_type'] == 'attach']
            detach_events = [e for e in events if e['event_type'] == 'detach']
            
            # Feature 3-6: Failure counts
            failed_attaches = len([e for e in events if e.get('event_subtype') == 'failed_attach'])
            attach_timeouts = len([e for e in events if e.get('event_subtype') == 'attach_timeout'])
            abnormal_detaches = len([e for e in events if e.get('event_subtype') == 'abnormal_detach'])
            forced_detaches = len([e for e in events if e.get('event_subtype') == 'forced_detach'])
            
            # Feature 7: Failure rate
            total_attaches = len(attach_events)
            failure_rate = (failed_attaches + attach_timeouts) / max(total_attaches, 1)
            
            # Feature 8-10: Timing features
            if len(events) > 1:
                time_diffs = []
                for i in range(1, len(events)):
                    diff = (events[i]['timestamp'] - events[i-1]['timestamp']).total_seconds()
                    time_diffs.append(diff)
                
                avg_time_diff = np.mean(time_diffs)
                std_time_diff = np.std(time_diffs)
                min_time_diff = np.min(time_diffs)
            else:
                avg_time_diff = 0
                std_time_diff = 0
                min_time_diff = 0
            
            # Feature 11: Attach/Detach ratio
            attach_detach_ratio = len(attach_events) / max(len(detach_events), 1)
            
            # Feature 12: Event sequence entropy (measure of randomness)
            event_types = [e['event_type'] for e in events]
            unique_types = set(event_types)
            entropy = 0
            for event_type in unique_types:
                prob = event_types.count(event_type) / len(event_types)
                entropy -= prob * np.log2(prob) if prob > 0 else 0
            
            # Feature 13: Rapid event count (events < 1 second apart)
            rapid_events = sum(1 for diff in time_diffs if diff < 1.0) if len(events) > 1 else 0
            
            # Feature 14: Session duration (seconds)
            session_duration = (events[-1]['timestamp'] - events[0]['timestamp']).total_seconds() if len(events) > 1 else 0
            
            # Feature 15: Events per minute
            events_per_minute = len(events) / max(session_duration / 60, 1) if session_duration > 0 else len(events)
            
            # Feature 16: Abnormal event ratio
            total_abnormal = abnormal_detaches + forced_detaches + failed_attaches + attach_timeouts
            abnormal_ratio = total_abnormal / max(len(events), 1)
            
            feature_vector = [
                len(attach_events),      # 1: Attach count
                len(detach_events),      # 2: Detach count
                failed_attaches,         # 3: Failed attach count
                attach_timeouts,         # 4: Attach timeout count
                abnormal_detaches,       # 5: Abnormal detach count
                forced_detaches,         # 6: Forced detach count
                failure_rate,            # 7: Failure rate
                avg_time_diff,           # 8: Average time between events
                std_time_diff,           # 9: Std dev of time between events
                min_time_diff,           # 10: Minimum time between events
                attach_detach_ratio,     # 11: Attach/Detach ratio
                entropy,                 # 12: Event sequence entropy
                rapid_events,            # 13: Rapid event count
                session_duration,        # 14: Session duration
                events_per_minute,       # 15: Events per minute
                abnormal_ratio           # 16: Abnormal event ratio
            ]
            
            features.append(feature_vector)
            ue_ids.append(ue_id)
            event_metadata.append({
                'ue_id': ue_id,
                'total_events': len(events),
                'first_event': events[0],
                'last_event': events[-1],
                'failed_attaches': failed_attaches,
                'abnormal_detaches': abnormal_detaches
            })
        
        return np.array(features), ue_ids, event_metadata
    
    def detect_anomalies(self, ue_events, source_file):
        """Detect anomalies using ML ensemble"""
        if len(ue_events) == 0:
            return []
        
        # Extract features
        features, ue_ids, metadata = self.extract_features(ue_events)
        
        if len(features) < 2:
            print("  ML: Not enough UE sessions for ML analysis (need at least 2)")
            return []
        
        # Normalize features
        features_scaled = self.scaler.fit_transform(features)
        
        # Run 4 ML algorithms
        algorithms = {
            'isolation_forest': IsolationForest(contamination=0.05, random_state=42),
            'dbscan': DBSCAN(eps=0.5, min_samples=2),
            'one_class_svm': OneClassSVM(nu=0.05, kernel='rbf', gamma='auto'),
            'lof': LocalOutlierFactor(n_neighbors=min(5, len(features)), contamination=0.05)
        }
        
        predictions = {}
        
        # Isolation Forest
        predictions['isolation_forest'] = algorithms['isolation_forest'].fit_predict(features_scaled)
        
        # DBSCAN (outliers are labeled -1)
        dbscan_labels = algorithms['dbscan'].fit_predict(features_scaled)
        predictions['dbscan'] = np.array([-1 if label == -1 else 1 for label in dbscan_labels])
        
        # One-Class SVM
        predictions['one_class_svm'] = algorithms['one_class_svm'].fit_predict(features_scaled)
        
        # LOF (outliers are labeled -1)
        predictions['lof'] = algorithms['lof'].fit_predict(features_scaled)
        
        # Ensemble voting (1 or more algorithms flag = anomaly)
        anomaly_votes = np.zeros(len(features))
        for algo_name, pred in predictions.items():
            anomaly_votes += (pred == -1).astype(int)
        
        # Find anomalies (1+ votes)
        anomaly_indices = np.where(anomaly_votes >= 1)[0]
        
        anomalies = []
        for idx in anomaly_indices:
            ue_id = ue_ids[idx]
            meta = metadata[idx]
            votes = int(anomaly_votes[idx])
            confidence = votes / len(algorithms)
            
            # Determine anomaly description based on features
            feature_vec = features[idx]
            failed_attaches = int(feature_vec[2])
            attach_timeouts = int(feature_vec[3])
            abnormal_detaches = int(feature_vec[4])
            forced_detaches = int(feature_vec[5])
            failure_rate = feature_vec[6]
            
            description_parts = []
            if failed_attaches > 0:
                description_parts.append(f"{failed_attaches} failed attach(es)")
            if attach_timeouts > 0:
                description_parts.append(f"{attach_timeouts} timeout(s)")
            if abnormal_detaches > 0:
                description_parts.append(f"{abnormal_detaches} abnormal detach(es)")
            if forced_detaches > 0:
                description_parts.append(f"{forced_detaches} forced detach(es)")
            if failure_rate > 0.5:
                description_parts.append(f"high failure rate ({failure_rate:.1%})")
            
            description = f"ML detected UE {ue_id} anomaly: {', '.join(description_parts)}" if description_parts else f"ML detected unusual behavior for UE {ue_id}"
            
            # Create error_log with ML-detected event pattern summary
            error_log = f"UE {ue_id} ML Pattern: Failed attaches={failed_attaches}, Timeouts={attach_timeouts}, Abnormal detaches={abnormal_detaches}, Forced detaches={forced_detaches}, Failure rate={failure_rate:.1%}, Total events={meta['total_events']}"
            
            anomaly = {
                'file': source_file,
                'file_type': 'TEXT',
                'packet_number': 1,
                'line_number': meta['first_event']['line_number'],
                'anomaly_type': 'ML-UE Event Pattern',
                'ue_id': ue_id,
                'confidence': confidence,
                'ml_votes': votes,
                'error_log': error_log,  # Event pattern for LLM analysis
                'details': [
                    f"ML Confidence: {confidence:.2%} ({votes}/4 algorithms agree)",
                    f"Failed attaches: {failed_attaches}",
                    f"Attach timeouts: {attach_timeouts}",
                    f"Abnormal detaches: {abnormal_detaches}",
                    f"Forced detaches: {forced_detaches}",
                    f"Failure rate: {failure_rate:.1%}",
                    f"Total events analyzed: {meta['total_events']}"
                ],
                'description': description
            }
            anomalies.append(anomaly)
        
        if anomalies:
            print(f"  ML: Detected {len(anomalies)} UE anomalies (ensemble voting)")
        
        return anomalies
