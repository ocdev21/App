#!/usr/bin/env python3
"""
Test script for ML-based UE Event Anomaly Detection
"""

import sys
from datetime import datetime, timedelta
sys.path.append('.')

from server.services.ml_ue_analyzer import MLUEEventAnalyzer

def create_test_events():
    """Create sample UE events for testing"""
    base_time = datetime.now()
    
    # Normal UE behavior (UE 100)
    normal_events = [
        {
            'ue_id': '100',
            'event_type': 'attach',
            'event_subtype': 'successful_attach',
            'timestamp': base_time,
            'line_number': 1
        },
        {
            'ue_id': '100',
            'event_type': 'detach',
            'event_subtype': 'normal_detach',
            'timestamp': base_time + timedelta(minutes=30),
            'line_number': 2
        }
    ]
    
    # Anomalous UE behavior (UE 200 - multiple failures)
    anomalous_events = [
        {
            'ue_id': '200',
            'event_type': 'attach',
            'event_subtype': 'failed_attach',
            'timestamp': base_time + timedelta(seconds=1),
            'line_number': 3
        },
        {
            'ue_id': '200',
            'event_type': 'attach',
            'event_subtype': 'failed_attach',
            'timestamp': base_time + timedelta(seconds=2),
            'line_number': 4
        },
        {
            'ue_id': '200',
            'event_type': 'attach',
            'event_subtype': 'attach_timeout',
            'timestamp': base_time + timedelta(seconds=3),
            'line_number': 5
        },
        {
            'ue_id': '200',
            'event_type': 'attach',
            'event_subtype': 'successful_attach',
            'timestamp': base_time + timedelta(seconds=30),
            'line_number': 6
        },
        {
            'ue_id': '200',
            'event_type': 'detach',
            'event_subtype': 'abnormal_detach',
            'timestamp': base_time + timedelta(seconds=35),
            'line_number': 7
        }
    ]
    
    # Another anomalous UE (UE 300 - rapid events)
    rapid_events = []
    for i in range(15):
        rapid_events.append({
            'ue_id': '300',
            'event_type': 'attach' if i % 2 == 0 else 'detach',
            'event_subtype': 'failed_attach' if i % 2 == 0 else 'forced_detach',
            'timestamp': base_time + timedelta(seconds=i*0.5),
            'line_number': 8 + i
        })
    
    return normal_events + anomalous_events + rapid_events

def test_ml_ue_analyzer():
    """Test ML-based UE event anomaly detection"""
    print("=" * 60)
    print("TESTING ML-BASED UE EVENT ANOMALY DETECTION")
    print("=" * 60)
    
    # Create analyzer
    analyzer = MLUEEventAnalyzer()
    
    # Create test events
    print("\n1. Creating test UE events...")
    events = create_test_events()
    print(f"   Created {len(events)} test events for 3 UEs")
    print(f"   - UE 100: Normal behavior (2 events)")
    print(f"   - UE 200: Anomalous behavior (5 events with failures)")
    print(f"   - UE 300: Rapid events (15 events in 7.5 seconds)")
    
    # Run ML detection
    print("\n2. Running ML anomaly detection...")
    anomalies = analyzer.detect_anomalies(events, 'test_log.txt')
    
    # Display results
    print(f"\n3. ML Detection Results:")
    print(f"   Total anomalies detected: {len(anomalies)}")
    
    if anomalies:
        print("\n" + "=" * 60)
        print("DETECTED ANOMALIES:")
        print("=" * 60)
        
        for i, anomaly in enumerate(anomalies, 1):
            print(f"\nAnomaly #{i}:")
            print(f"  UE ID: {anomaly['ue_id']}")
            print(f"  Type: {anomaly['anomaly_type']}")
            print(f"  Confidence: {anomaly['confidence']:.1%}")
            print(f"  ML Votes: {anomaly['ml_votes']}/4 algorithms")
            print(f"  Description: {anomaly['description']}")
            print(f"  Details:")
            for detail in anomaly['details']:
                print(f"    - {detail}")
    else:
        print("   No anomalies detected (this is unexpected!)")
    
    print("\n" + "=" * 60)
    print("TEST COMPLETED")
    print("=" * 60)
    
    # Verify results
    if len(anomalies) >= 2:
        print("\n✅ TEST PASSED: ML analyzer successfully detected anomalous UE behavior")
        print(f"   Expected: 2+ anomalies (UE 200 and UE 300)")
        print(f"   Detected: {len(anomalies)} anomalies")
        return True
    else:
        print(f"\n❌ TEST FAILED: Expected 2+ anomalies, detected {len(anomalies)}")
        return False

if __name__ == "__main__":
    success = test_ml_ue_analyzer()
    sys.exit(0 if success else 1)
