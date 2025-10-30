#!/usr/bin/env python3
"""
InfluxDB Testing Script

This script:
1. Connects to AWS Timestream for InfluxDB
2. Creates buckets for energy metrics and sensor data
3. Inserts sample records into each bucket
4. Queries and displays the data

Usage:
    python test_influxdb.py

Requirements:
    pip install influxdb-client
"""

import os
import sys
from datetime import datetime, timedelta
from influxdb_client import InfluxDBClient, Point, WritePrecision, BucketRetentionRules
from influxdb_client.client.write_api import SYNCHRONOUS
import random

# Configuration
INFLUXDB_URL = os.getenv("INFLUXDB_URL", "https://Lhk52q7uoe-lktzzbuyksah47.timestream-influxdb.us-east-1.on.aws")
INFLUXDB_TOKEN = os.getenv("INFLUXDB_TOKEN", "")
INFLUXDB_ORG = os.getenv("INFLUXDB_ORG", "superapp-org")

# Bucket configurations
BUCKETS = [
    {
        "name": "energy_metrics",
        "description": "Energy consumption and power metrics",
        "retention_hours": 720  # 30 days
    },
    {
        "name": "sensor_data", 
        "description": "Environmental sensor readings",
        "retention_hours": 720  # 30 days
    },
    {
        "name": "test_bucket",
        "description": "General testing bucket",
        "retention_hours": 168  # 7 days
    }
]


def validate_config():
    """Validate configuration before proceeding"""
    if not INFLUXDB_TOKEN:
        print("❌ ERROR: INFLUXDB_TOKEN not set!")
        print("\nPlease set your token:")
        print("  export INFLUXDB_TOKEN='your-token-here'")
        print("\nOr see GET_INFLUXDB_TOKEN.md for instructions")
        sys.exit(1)
    
    print("✓ Configuration validated")
    print(f"  URL: {INFLUXDB_URL}")
    print(f"  Org: {INFLUXDB_ORG}")
    print(f"  Token: {'*' * 20}... (hidden)")
    print()


def connect_to_influxdb():
    """Create and test InfluxDB connection"""
    print("Connecting to InfluxDB...")
    try:
        client = InfluxDBClient(
            url=INFLUXDB_URL,
            token=INFLUXDB_TOKEN,
            org=INFLUXDB_ORG,
            timeout=30_000
        )
        
        health = client.health()
        print(f"✅ Connected successfully!")
        print(f"   Status: {health.status}")
        print()
        return client
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        sys.exit(1)


def create_buckets(client):
    """Create buckets if they don't exist"""
    buckets_api = client.buckets_api()
    
    print("Creating buckets...")
    created_count = 0
    
    for bucket_config in BUCKETS:
        bucket_name = bucket_config["name"]
        
        try:
            # Check if bucket exists
            existing_bucket = buckets_api.find_bucket_by_name(bucket_name)
            
            if existing_bucket:
                print(f"  ℹ️  Bucket '{bucket_name}' already exists")
            else:
                # Create retention rule
                retention_rules = BucketRetentionRules(
                    type="expire",
                    every_seconds=bucket_config["retention_hours"] * 3600
                )
                
                # Create bucket
                buckets_api.create_bucket(
                    bucket_name=bucket_name,
                    description=bucket_config["description"],
                    org=INFLUXDB_ORG,
                    retention_rules=retention_rules
                )
                print(f"  ✅ Created bucket '{bucket_name}'")
                print(f"     Retention: {bucket_config['retention_hours']} hours")
                created_count += 1
                
        except Exception as e:
            print(f"  ❌ Error with bucket '{bucket_name}': {e}")
    
    print(f"\n✓ Buckets ready ({created_count} created, {len(BUCKETS) - created_count} existing)")
    print()


def insert_energy_metrics(write_api, num_points=20):
    """Insert sample energy metrics"""
    print(f"Inserting {num_points} energy metric records...")
    
    points = []
    base_time = datetime.utcnow() - timedelta(hours=2)
    
    for i in range(num_points):
        timestamp = base_time + timedelta(minutes=i * 6)
        location = random.choice(["datacenter-1", "datacenter-2", "office-a"])
        
        point = (
            Point("energy_consumption")
            .tag("location", location)
            .tag("source", "test_script")
            .tag("region", "us-east-1")
            .field("power_kw", round(random.uniform(50, 200), 2))
            .field("voltage", round(random.uniform(220, 240), 2))
            .field("current", round(random.uniform(10, 40), 2))
            .field("temperature_c", round(random.uniform(20, 40), 2))
            .field("efficiency", round(random.uniform(85, 98), 2))
            .time(timestamp, WritePrecision.NS)
        )
        points.append(point)
    
    try:
        write_api.write(bucket="energy_metrics", org=INFLUXDB_ORG, record=points)
        print(f"  ✅ Wrote {num_points} energy metric points")
        print(f"     Measurement: energy_consumption")
        print(f"     Fields: power_kw, voltage, current, temperature_c, efficiency")
        print(f"     Locations: datacenter-1, datacenter-2, office-a")
        return True
    except Exception as e:
        print(f"  ❌ Failed to write energy metrics: {e}")
        return False


def insert_sensor_data(write_api, num_points=20):
    """Insert sample sensor data"""
    print(f"Inserting {num_points} sensor data records...")
    
    points = []
    base_time = datetime.utcnow() - timedelta(hours=2)
    
    for i in range(num_points):
        timestamp = base_time + timedelta(minutes=i * 6)
        sensor_id = f"sensor-{random.randint(1, 5)}"
        zone = random.choice(["zone-a", "zone-b", "zone-c"])
        
        point = (
            Point("environmental_reading")
            .tag("sensor_id", sensor_id)
            .tag("zone", zone)
            .tag("source", "test_script")
            .field("temperature", round(random.uniform(18, 30), 2))
            .field("humidity", round(random.uniform(30, 70), 2))
            .field("pressure", round(random.uniform(990, 1020), 2))
            .field("co2_ppm", round(random.uniform(400, 1000), 1))
            .time(timestamp, WritePrecision.NS)
        )
        points.append(point)
    
    try:
        write_api.write(bucket="sensor_data", org=INFLUXDB_ORG, record=points)
        print(f"  ✅ Wrote {num_points} sensor data points")
        print(f"     Measurement: environmental_reading")
        print(f"     Fields: temperature, humidity, pressure, co2_ppm")
        print(f"     Sensors: sensor-1 through sensor-5")
        return True
    except Exception as e:
        print(f"  ❌ Failed to write sensor data: {e}")
        return False


def insert_test_data(write_api, num_points=10):
    """Insert general test data"""
    print(f"Inserting {num_points} test records...")
    
    points = []
    base_time = datetime.utcnow() - timedelta(hours=1)
    
    for i in range(num_points):
        timestamp = base_time + timedelta(minutes=i * 5)
        
        point = (
            Point("test_measurement")
            .tag("test_id", f"test-{i}")
            .tag("source", "test_script")
            .field("value", random.randint(1, 100))
            .field("status", random.choice(["active", "inactive", "pending"]))
            .time(timestamp, WritePrecision.NS)
        )
        points.append(point)
    
    try:
        write_api.write(bucket="test_bucket", org=INFLUXDB_ORG, record=points)
        print(f"  ✅ Wrote {num_points} test points")
        print(f"     Measurement: test_measurement")
        return True
    except Exception as e:
        print(f"  ❌ Failed to write test data: {e}")
        return False


def query_and_display(query_api):
    """Query and display sample data from each bucket"""
    print("\nQuerying data from buckets...")
    print("=" * 60)
    
    # Query energy metrics
    print("\n📊 Energy Metrics (latest 5 records):")
    flux_query = f'''
    from(bucket: "energy_metrics")
      |> range(start: -24h)
      |> filter(fn: (r) => r._measurement == "energy_consumption")
      |> filter(fn: (r) => r._field == "power_kw")
      |> sort(columns: ["_time"], desc: true)
      |> limit(n: 5)
    '''
    
    try:
        tables = query_api.query(flux_query, org=INFLUXDB_ORG)
        count = 0
        for table in tables:
            for record in table.records:
                count += 1
                print(f"  {record.get_time().strftime('%Y-%m-%d %H:%M:%S')} | "
                      f"Location: {record.values.get('location', 'N/A')} | "
                      f"Power: {record.get_value():.2f} kW")
        if count == 0:
            print("  (No data found)")
    except Exception as e:
        print(f"  ❌ Query failed: {e}")
    
    # Query sensor data
    print("\n🌡️  Sensor Data (latest 5 records):")
    flux_query = f'''
    from(bucket: "sensor_data")
      |> range(start: -24h)
      |> filter(fn: (r) => r._measurement == "environmental_reading")
      |> filter(fn: (r) => r._field == "temperature")
      |> sort(columns: ["_time"], desc: true)
      |> limit(n: 5)
    '''
    
    try:
        tables = query_api.query(flux_query, org=INFLUXDB_ORG)
        count = 0
        for table in tables:
            for record in table.records:
                count += 1
                print(f"  {record.get_time().strftime('%Y-%m-%d %H:%M:%S')} | "
                      f"Sensor: {record.values.get('sensor_id', 'N/A')} | "
                      f"Temp: {record.get_value():.1f}°C")
        if count == 0:
            print("  (No data found)")
    except Exception as e:
        print(f"  ❌ Query failed: {e}")
    
    print("\n" + "=" * 60)


def main():
    """Main execution flow"""
    print("\n" + "=" * 60)
    print("InfluxDB Testing Script - superAppDB")
    print("=" * 60 + "\n")
    
    # Step 1: Validate configuration
    validate_config()
    
    # Step 2: Connect to InfluxDB
    client = connect_to_influxdb()
    
    try:
        # Step 3: Create buckets
        create_buckets(client)
        
        # Step 4: Insert data
        write_api = client.write_api(write_options=SYNCHRONOUS)
        
        print("Writing data to buckets...")
        success_count = 0
        
        if insert_energy_metrics(write_api, num_points=20):
            success_count += 1
        
        if insert_sensor_data(write_api, num_points=20):
            success_count += 1
        
        if insert_test_data(write_api, num_points=10):
            success_count += 1
        
        print(f"\n✓ Completed writing to {success_count}/3 buckets")
        
        # Step 5: Query and display data
        query_api = client.query_api()
        query_and_display(query_api)
        
        # Summary
        print("\n✅ Testing completed successfully!")
        print("\nWhat was tested:")
        print("  • Connection to InfluxDB")
        print("  • Bucket creation (energy_metrics, sensor_data, test_bucket)")
        print("  • Writing energy consumption data")
        print("  • Writing environmental sensor data")
        print("  • Writing test data")
        print("  • Querying data with Flux")
        
        print("\nNext steps:")
        print("  • View data in InfluxDB UI: " + INFLUXDB_URL)
        print("  • Run queries in SageMaker notebooks")
        print("  • Integrate with your applications (esapp, tsapp)")
        
    finally:
        client.close()
        print("\n✓ Connection closed")


if __name__ == "__main__":
    main()
