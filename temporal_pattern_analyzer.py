#!/usr/bin/env python3
"""
Temporal Pattern Analyzer for L1 Anomaly Detection
Detects patterns over time using sliding windows and trend analysis
"""

import numpy as np
from collections import deque, defaultdict
from typing import Dict, List, Any, Optional, Tuple
from datetime import datetime, timedelta


class TemporalPatternAnalyzer:
    """
    Analyzes temporal patterns in network traffic
    Detects degradation, bursts, and time-based anomalies
    """
    
    def __init__(self, window_duration: float = 10.0):
        """
        Args:
            window_duration: Duration of sliding window in seconds
        """
        self.window_duration = window_duration
        self.event_history = defaultdict(list)
        self.metric_history = defaultdict(lambda: deque(maxlen=1000))
        
    def add_event(self, event_type: str, timestamp: float, metadata: Dict = None):
        """Record an event for temporal analysis"""
        self.event_history[event_type].append({
            'timestamp': timestamp,
            'metadata': metadata or {}
        })
    
    def analyze_event_rate(self, event_type: str, timestamps: List[float]) -> Dict[str, Any]:
        """
        Analyze the rate of events over time
        Detects bursts and unusual patterns
        """
        if len(timestamps) < 2:
            return {'rate': 0, 'burst_detected': False}
            
        timestamps = sorted(timestamps)
        duration = timestamps[-1] - timestamps[0]
        
        if duration == 0:
            return {'rate': len(timestamps), 'burst_detected': True, 'burst_severity': 'high'}
        
        overall_rate = len(timestamps) / duration
        
        window_rates = []
        for i in range(0, len(timestamps) - 1):
            window_start = timestamps[i]
            window_end = window_start + self.window_duration
            
            events_in_window = sum(1 for t in timestamps if window_start <= t < window_end)
            window_rate = events_in_window / self.window_duration
            window_rates.append(window_rate)
        
        if len(window_rates) > 0:
            max_window_rate = max(window_rates)
            avg_window_rate = np.mean(window_rates)
            std_window_rate = np.std(window_rates)
            
            burst_detected = max_window_rate > (avg_window_rate + 2 * std_window_rate) if std_window_rate > 0 else False
            
            if burst_detected:
                burst_ratio = max_window_rate / avg_window_rate if avg_window_rate > 0 else 1
                if burst_ratio > 5:
                    burst_severity = 'critical'
                elif burst_ratio > 3:
                    burst_severity = 'high'
                elif burst_ratio > 2:
                    burst_severity = 'medium'
                else:
                    burst_severity = 'low'
            else:
                burst_severity = 'none'
        else:
            burst_detected = False
            burst_severity = 'none'
            max_window_rate = overall_rate
            avg_window_rate = overall_rate
        
        return {
            'overall_rate': overall_rate,
            'max_window_rate': max_window_rate,
            'avg_window_rate': avg_window_rate,
            'burst_detected': burst_detected,
            'burst_severity': burst_severity,
            'total_events': len(timestamps),
            'duration': duration
        }
    
    def detect_degradation_trend(self, metric_name: str, values: List[float], 
                                 timestamps: List[float]) -> Dict[str, Any]:
        """
        Detect gradual degradation in a metric over time
        Returns trend analysis and degradation indicators
        """
        if len(values) < 5:
            return {'trend': 'insufficient_data', 'degrading': False}
        
        x = np.arange(len(values))
        y = np.array(values)
        
        coeffs = np.polyfit(x, y, 1)
        slope = coeffs[0]
        
        if slope > 0.01:
            trend = 'improving'
            degrading = False
        elif slope < -0.01:
            trend = 'degrading'
            degrading = True
        else:
            trend = 'stable'
            degrading = False
        
        recent_mean = np.mean(values[-min(5, len(values)):])
        overall_mean = np.mean(values)
        recent_deviation = (recent_mean - overall_mean) / overall_mean if overall_mean != 0 else 0
        
        if degrading and abs(recent_deviation) > 0.2:
            severity = 'high'
        elif degrading and abs(recent_deviation) > 0.1:
            severity = 'medium'
        else:
            severity = 'low'
        
        return {
            'trend': trend,
            'degrading': degrading,
            'slope': slope,
            'recent_deviation': recent_deviation,
            'severity': severity,
            'recent_mean': recent_mean,
            'overall_mean': overall_mean
        }
    
    def detect_periodic_patterns(self, timestamps: List[float], 
                                tolerance: float = 0.1) -> Dict[str, Any]:
        """
        Detect periodic patterns in event occurrence
        Useful for identifying scheduled or cyclic issues
        """
        if len(timestamps) < 3:
            return {'periodic': False}
        
        timestamps = sorted(timestamps)
        intervals = np.diff(timestamps)
        
        if len(intervals) < 2:
            return {'periodic': False}
        
        mean_interval = np.mean(intervals)
        std_interval = np.std(intervals)
        cv = std_interval / mean_interval if mean_interval > 0 else float('inf')
        
        is_periodic = cv < tolerance
        
        return {
            'periodic': is_periodic,
            'mean_interval': mean_interval,
            'std_interval': std_interval,
            'coefficient_of_variation': cv,
            'confidence': 1.0 - min(cv, 1.0)
        }
    
    def analyze_temporal_correlation(self, events_a: List[float], 
                                    events_b: List[float],
                                    max_lag: float = 5.0) -> Dict[str, Any]:
        """
        Analyze temporal correlation between two event types
        Detects if one event type tends to follow another
        """
        if len(events_a) < 3 or len(events_b) < 3:
            return {'correlated': False}
        
        following_pairs = []
        
        for t_a in events_a:
            for t_b in events_b:
                lag = t_b - t_a
                if 0 < lag <= max_lag:
                    following_pairs.append(lag)
        
        if len(following_pairs) < 3:
            return {
                'correlated': False,
                'correlation_strength': 0
            }
        
        correlation_strength = len(following_pairs) / min(len(events_a), len(events_b))
        
        return {
            'correlated': correlation_strength > 0.3,
            'correlation_strength': correlation_strength,
            'typical_lag': np.median(following_pairs),
            'lag_std': np.std(following_pairs),
            'pair_count': len(following_pairs)
        }
    
    def sliding_window_analysis(self, data_points: List[Tuple[float, float]], 
                               window_size: int = 10) -> List[Dict[str, Any]]:
        """
        Perform sliding window analysis on time-series data
        Returns window-level statistics for each position
        """
        if len(data_points) < window_size:
            return []
        
        windows = []
        
        for i in range(len(data_points) - window_size + 1):
            window_data = data_points[i:i+window_size]
            timestamps = [d[0] for d in window_data]
            values = [d[1] for d in window_data]
            
            window_analysis = {
                'start_time': timestamps[0],
                'end_time': timestamps[-1],
                'mean': np.mean(values),
                'std': np.std(values),
                'min': np.min(values),
                'max': np.max(values),
                'range': np.max(values) - np.min(values),
                'trend': 'increasing' if values[-1] > values[0] else 'decreasing'
            }
            
            windows.append(window_analysis)
        
        return windows
    
    def detect_state_transitions(self, metric_values: List[float], 
                                threshold: float = 0.5) -> List[Dict[str, Any]]:
        """
        Detect state transitions (e.g., normal -> degraded -> failed)
        """
        if len(metric_values) < 2:
            return []
        
        transitions = []
        current_state = 'normal' if metric_values[0] < threshold else 'abnormal'
        
        for i in range(1, len(metric_values)):
            new_state = 'normal' if metric_values[i] < threshold else 'abnormal'
            
            if new_state != current_state:
                transitions.append({
                    'position': i,
                    'from_state': current_state,
                    'to_state': new_state,
                    'value': metric_values[i]
                })
                current_state = new_state
        
        return transitions
