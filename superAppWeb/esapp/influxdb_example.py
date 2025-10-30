"""
ESApp - InfluxDB Integration Example
Demonstrates how to write energy metrics to InfluxDB from ECS Fargate
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
    
    logger.info("ESApp starting with InfluxDB integration...")
    
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
                
                # Simulate energy readings
                voltage = 220 + random.uniform(-5, 5)
                current = 10 + random.uniform(-2, 2)
                power = voltage * current
                energy_kwh = power / 1000
                
                # Log to console
                logger.info(f"[{iteration}] ESApp Energy Reading: "
                          f"V={voltage:.2f}V, I={current:.2f}A, "
                          f"P={power:.2f}W, E={energy_kwh:.3f}kWh")
                
                # Write energy metrics to InfluxDB
                success = writer.write_points([
                    {
                        "measurement": "energy_voltage",
                        "fields": {"value": voltage},
                        "tags": {
                            "app": "esapp",
                            "unit": "volts",
                            "location": "aws-us-east-1"
                        }
                    },
                    {
                        "measurement": "energy_current",
                        "fields": {"value": current},
                        "tags": {
                            "app": "esapp",
                            "unit": "amperes",
                            "location": "aws-us-east-1"
                        }
                    },
                    {
                        "measurement": "energy_power",
                        "fields": {"value": power},
                        "tags": {
                            "app": "esapp",
                            "unit": "watts",
                            "location": "aws-us-east-1"
                        }
                    },
                    {
                        "measurement": "energy_consumption",
                        "fields": {"value": energy_kwh},
                        "tags": {
                            "app": "esapp",
                            "unit": "kwh",
                            "location": "aws-us-east-1"
                        }
                    }
                ])
                
                if success:
                    logger.info(f"✓ Wrote energy metrics to InfluxDB")
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
        logger.info("ESApp stopped by user")
        sys.exit(0)
    
    except Exception as e:
        logger.error(f"Unexpected error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
