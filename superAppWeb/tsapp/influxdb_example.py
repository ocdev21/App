"""
TSApp - InfluxDB Integration Example
Demonstrates how to write time-series data to InfluxDB from ECS Fargate
"""

import time
import random
import logging
from datetime import datetime
import sys
import os

# Add parent directory to path to import shared module
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from shared.influxdb_client import InfluxDBWriter, InfluxDBConfig, write_metric

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def main():
    """Main application loop with InfluxDB integration"""
    
    logger.info("TSApp starting with InfluxDB integration...")
    
    try:
        # Initialize InfluxDB writer
        config = InfluxDBConfig()
        logger.info(f"InfluxDB Config: {config}")
        
        with InfluxDBWriter(config) as writer:
            # Health check
            if not writer.health_check():
                logger.error("InfluxDB health check failed!")
                sys.exit(1)
            
            logger.info("✓ Connected to InfluxDB successfully")
            
            iteration = 0
            while True:
                iteration += 1
                
                # Simulate sensor readings
                temperature = 20 + random.uniform(-5, 10)
                humidity = 50 + random.uniform(-10, 20)
                pressure = 1013 + random.uniform(-5, 5)
                
                # Log to console
                logger.info(f"[{iteration}] TSApp Sensor Reading: "
                          f"T={temperature:.2f}°C, H={humidity:.1f}%, "
                          f"P={pressure:.1f}hPa")
                
                # Write sensor data to InfluxDB
                success = writer.write_points([
                    {
                        "measurement": "temperature",
                        "fields": {"value": temperature},
                        "tags": {
                            "app": "tsapp",
                            "sensor": "DHT22",
                            "unit": "celsius",
                            "location": "aws-us-east-1"
                        }
                    },
                    {
                        "measurement": "humidity",
                        "fields": {"value": humidity},
                        "tags": {
                            "app": "tsapp",
                            "sensor": "DHT22",
                            "unit": "percent",
                            "location": "aws-us-east-1"
                        }
                    },
                    {
                        "measurement": "pressure",
                        "fields": {"value": pressure},
                        "tags": {
                            "app": "tsapp",
                            "sensor": "BMP280",
                            "unit": "hPa",
                            "location": "aws-us-east-1"
                        }
                    }
                ])
                
                if success:
                    logger.info(f"✓ Wrote sensor data to InfluxDB")
                else:
                    logger.warning("✗ Failed to write to InfluxDB")
                
                # Sleep for 30 seconds
                time.sleep(30)
                
    except ValueError as e:
        logger.error(f"Configuration error: {e}")
        logger.error("Required environment variables:")
        logger.error("  - INFLUXDB_URL or INFLUXDB_V2_URL")
        logger.error("  - INFLUXDB_TOKEN or INFLUXDB_V2_TOKEN")
        logger.error("  - INFLUXDB_ORG or INFLUXDB_V2_ORG")
        sys.exit(1)
    
    except KeyboardInterrupt:
        logger.info("TSApp stopped by user")
        sys.exit(0)
    
    except Exception as e:
        logger.error(f"Unexpected error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
