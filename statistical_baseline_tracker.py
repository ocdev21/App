#!/usr/bin/env python3
"""
Statistical Baseline Tracker for L1 Anomaly Detection
Maintains baselines for normal behavior and calculates adaptive thresholds
"""

import numpy as np
from collections import defaultdict, deque
from typing import Dict, List, Any, Optional, Tuple
import json


class StatisticalBaselineTracker:
    """
    Tracks statistical baselines for network behavior
    Enables adaptive thresholds instead of hardcoded values
    """
    
    def __init__(self, window_size: int = 1000):
        self.window_size = window_size
        
        self.baselines = {
            'rach': {
                'success_rate': deque(maxlen=window_size),
                'attempt_count': deque(maxlen=window_size),
                'avg_attempts_per_file': deque(maxlen=100)
            },
            'handover': {
                'success_rate': deque(maxlen=window_size),
                'attempt_count': deque(maxlen=window_size),
                'avg_duration': deque(maxlen=window_size)
            },
            'harq': {
                'retransmission_rate': deque(maxlen=window_size),
                'avg_retx_per_window': deque(maxlen=window_size),
                'max_consecutive_retx': deque(maxlen=window_size)
            },
            'crc': {
                'error_rate': deque(maxlen=window_size),
                'errors_per_1000_packets': deque(maxlen=100)
            },
            'rrc': {
                'connection_success_rate': deque(maxlen=window_size),
                'setup_attempts': deque(maxlen=window_size)
            },
            'timing_advance': {
                'violation_rate': deque(maxlen=window_size),
                'avg_ta_adjustments': deque(maxlen=window_size)
            },
            'power_control': {
                'adjustment_frequency': deque(maxlen=window_size),
                'avg_power_changes': deque(maxlen=window_size)
            },
            'general': {
                'packet_inter_arrival_time': deque(maxlen=window_size),
                'packet_size': deque(maxlen=window_size),
                'jitter': deque(maxlen=window_size)
            }
        }
        
        self.adaptive_thresholds = self._initialize_default_thresholds()
        self.statistics = defaultdict(lambda: {'count': 0, 'sum': 0, 'sum_sq': 0})
    
    def _initialize_default_thresholds(self) -> Dict[str, Dict[str, float]]:
        """Initialize conservative default thresholds"""
        return {
            'rach': {
                'max_attempts_threshold': 10,
                'min_success_rate': 0.80,
                'excessive_attempts_multiplier': 2.0
            },
            'handover': {
                'min_success_rate': 0.85,
                'max_failure_rate': 0.15
            },
            'harq': {
                'max_retx_per_window': 5,
                'max_retx_rate': 0.20,
                'excessive_retx_multiplier': 2.5
            },
            'crc': {
                'max_error_rate': 0.01,
                'errors_per_1000_threshold': 10
            },
            'rrc': {
                'min_success_rate': 0.90,
                'max_rejection_rate': 0.10
            },
            'timing_advance': {
                'max_violation_rate': 0.05,
                'ta_range_min': -31,
                'ta_range_max': 31
            },
            'power_control': {
                'max_adjustment_frequency': 0.30,
                'power_delta_threshold': 10
            }
        }
    
    def update_baseline(self, anomaly_type: str, metric_name: str, value: float):
        """Update baseline with new observation"""
        if anomaly_type in self.baselines and metric_name in self.baselines[anomaly_type]:
            self.baselines[anomaly_type][metric_name].append(value)
            
            key = f"{anomaly_type}_{metric_name}"
            self.statistics[key]['count'] += 1
            self.statistics[key]['sum'] += value
            self.statistics[key]['sum_sq'] += value * value
    
    def get_adaptive_threshold(self, anomaly_type: str, metric_name: str, 
                             num_std: float = 2.0) -> Optional[float]:
        """
        Calculate adaptive threshold based on historical data
        Returns: threshold value or None if insufficient data
        """
        if anomaly_type not in self.baselines:
            return None
            
        if metric_name not in self.baselines[anomaly_type]:
            return None
            
        data = list(self.baselines[anomaly_type][metric_name])
        
        if len(data) < 30:
            if anomaly_type in self.adaptive_thresholds:
                if metric_name in self.adaptive_thresholds[anomaly_type]:
                    return self.adaptive_thresholds[anomaly_type][metric_name]
            return None
        
        mean = np.mean(data)
        std = np.std(data)
        
        threshold = mean + (num_std * std)
        
        return threshold
    
    def is_anomalous(self, anomaly_type: str, metric_name: str, value: float,
                    severity_multiplier: float = 1.0) -> Tuple[bool, float, str]:
        """
        Determine if a value is anomalous compared to baseline
        Returns: (is_anomalous, deviation_score, severity_level)
        """
        threshold = self.get_adaptive_threshold(anomaly_type, metric_name)
        
        if threshold is None:
            default_thresholds = {
                'success_rate': 0.80,
                'error_rate': 0.05,
                'retransmission_rate': 0.15,
                'attempt_count': 10
            }
            threshold = default_thresholds.get(metric_name, 1.0)
        
        data = list(self.baselines[anomaly_type].get(metric_name, []))
        
        if len(data) >= 30:
            mean = np.mean(data)
            std = np.std(data)
            
            if std > 0:
                z_score = abs((value - mean) / std)
                deviation_score = z_score / 3.0
            else:
                deviation_score = abs(value - mean)
        else:
            deviation_score = abs(value - threshold) / threshold if threshold > 0 else 0
        
        is_anomalous = False
        severity = 'low'
        
        if 'rate' in metric_name:
            if 'success' in metric_name:
                is_anomalous = value < threshold
            else:
                is_anomalous = value > threshold
        else:
            is_anomalous = value > threshold
        
        if is_anomalous:
            if deviation_score > 2.0 * severity_multiplier:
                severity = 'critical'
            elif deviation_score > 1.5 * severity_multiplier:
                severity = 'high'
            elif deviation_score > 1.0 * severity_multiplier:
                severity = 'medium'
            else:
                severity = 'low'
        
        return is_anomalous, min(deviation_score, 1.0), severity
    
    def get_baseline_summary(self, anomaly_type: str) -> Dict[str, Any]:
        """Get summary statistics for an anomaly type"""
        if anomaly_type not in self.baselines:
            return {}
            
        summary = {}
        for metric_name, data in self.baselines[anomaly_type].items():
            if len(data) > 0:
                summary[metric_name] = {
                    'mean': float(np.mean(data)),
                    'std': float(np.std(data)),
                    'min': float(np.min(data)),
                    'max': float(np.max(data)),
                    'count': len(data),
                    'current_threshold': self.get_adaptive_threshold(anomaly_type, metric_name)
                }
        
        return summary
    
    def reset_baselines(self):
        """Clear all baseline data"""
        for anomaly_type in self.baselines:
            for metric_name in self.baselines[anomaly_type]:
                self.baselines[anomaly_type][metric_name].clear()
        self.statistics.clear()
