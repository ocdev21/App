"""
InfluxDB Client for AWS Applications
Supports both synchronous and asynchronous operations
Reads credentials from environment variables for ECS deployment
"""

import os
import logging
from typing import Optional, List, Dict, Any
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class InfluxDBConfig:
    """Configuration for InfluxDB connection"""
    
    def __init__(self):
        # Primary configuration - reads from environment
        self.url = os.getenv('INFLUXDB_URL', os.getenv('INFLUXDB_V2_URL', 'http://localhost:8086'))
        self.token = os.getenv('INFLUXDB_TOKEN', os.getenv('INFLUXDB_V2_TOKEN'))
        self.org = os.getenv('INFLUXDB_ORG', os.getenv('INFLUXDB_V2_ORG'))
        self.bucket = os.getenv('INFLUXDB_BUCKET', 'superAppDB')
        
        # Optional configuration
        self.timeout = int(os.getenv('INFLUXDB_V2_TIMEOUT', '30000'))  # milliseconds
        self.verify_ssl = os.getenv('INFLUXDB_V2_VERIFY_SSL', 'true').lower() == 'true'
        
        # Validate required fields
        self._validate()
    
    def _validate(self):
        """Validate that required configuration is present"""
        if not self.url:
            raise ValueError("INFLUXDB_URL or INFLUXDB_V2_URL must be set")
        if not self.token:
            raise ValueError("INFLUXDB_TOKEN or INFLUXDB_V2_TOKEN must be set")
        if not self.org:
            raise ValueError("INFLUXDB_ORG or INFLUXDB_V2_ORG must be set")
    
    def __repr__(self):
        return f"InfluxDBConfig(url={self.url}, org={self.org}, bucket={self.bucket})"


class InfluxDBWriter:
    """Synchronous InfluxDB writer for simple applications"""
    
    def __init__(self, config: Optional[InfluxDBConfig] = None):
        try:
            from influxdb_client import InfluxDBClient, Point
            from influxdb_client.client.write_api import SYNCHRONOUS
        except ImportError:
            raise ImportError(
                "influxdb-client not installed. Install with: pip install influxdb-client"
            )
        
        self.config = config or InfluxDBConfig()
        self.Point = Point
        
        # Initialize client
        self.client = InfluxDBClient(
            url=self.config.url,
            token=self.config.token,
            org=self.config.org,
            timeout=self.config.timeout,
            verify_ssl=self.config.verify_ssl,
            enable_gzip=True  # Reduce bandwidth
        )
        
        self.write_api = self.client.write_api(write_options=SYNCHRONOUS)
        logger.info(f"Connected to InfluxDB: {self.config}")
    
    def write_point(self, 
                   measurement: str,
                   fields: Dict[str, Any],
                   tags: Optional[Dict[str, str]] = None,
                   bucket: Optional[str] = None) -> bool:
        """
        Write a single data point to InfluxDB
        
        Args:
            measurement: Measurement name (e.g., "temperature", "sensor_reading")
            fields: Field key-value pairs (e.g., {"value": 23.5, "status": 1})
            tags: Tag key-value pairs (e.g., {"sensor_id": "TMP01", "location": "warehouse"})
            bucket: Bucket name (defaults to config.bucket)
        
        Returns:
            True if successful, False otherwise
        
        Example:
            writer.write_point(
                measurement="temperature",
                fields={"value": 23.5},
                tags={"sensor": "TMP01", "location": "warehouse"}
            )
        """
        try:
            point = self.Point(measurement)
            
            # Add tags
            if tags:
                for key, value in tags.items():
                    point = point.tag(key, str(value))
            
            # Add fields
            for key, value in fields.items():
                point = point.field(key, value)
            
            # Add timestamp
            point = point.time(datetime.utcnow())
            
            # Write to InfluxDB
            self.write_api.write(
                bucket=bucket or self.config.bucket,
                record=point
            )
            
            logger.debug(f"Wrote point: {measurement} {tags} {fields}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to write point: {e}")
            return False
    
    def write_points(self,
                    points: List[Dict[str, Any]],
                    bucket: Optional[str] = None) -> bool:
        """
        Write multiple points in batch
        
        Args:
            points: List of point dictionaries with keys: measurement, fields, tags
            bucket: Bucket name (defaults to config.bucket)
        
        Returns:
            True if successful, False otherwise
        
        Example:
            writer.write_points([
                {
                    "measurement": "temperature",
                    "fields": {"value": 23.5},
                    "tags": {"sensor": "TMP01"}
                },
                {
                    "measurement": "humidity",
                    "fields": {"value": 65.2},
                    "tags": {"sensor": "HUM01"}
                }
            ])
        """
        try:
            records = []
            for point_data in points:
                point = self.Point(point_data["measurement"])
                
                # Add tags
                for key, value in point_data.get("tags", {}).items():
                    point = point.tag(key, str(value))
                
                # Add fields
                for key, value in point_data["fields"].items():
                    point = point.field(key, value)
                
                # Add timestamp
                point = point.time(datetime.utcnow())
                records.append(point)
            
            # Write all points
            self.write_api.write(
                bucket=bucket or self.config.bucket,
                record=records
            )
            
            logger.info(f"Wrote {len(records)} points to InfluxDB")
            return True
            
        except Exception as e:
            logger.error(f"Failed to write points: {e}")
            return False
    
    def health_check(self) -> bool:
        """Check if InfluxDB connection is healthy"""
        try:
            health = self.client.ping()
            logger.info(f"InfluxDB health check: {health}")
            return True
        except Exception as e:
            logger.error(f"InfluxDB health check failed: {e}")
            return False
    
    def close(self):
        """Close the InfluxDB client connection"""
        try:
            self.write_api.close()
            self.client.close()
            logger.info("InfluxDB connection closed")
        except Exception as e:
            logger.error(f"Error closing InfluxDB connection: {e}")
    
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()


class InfluxDBQuery:
    """Query InfluxDB data"""
    
    def __init__(self, config: Optional[InfluxDBConfig] = None):
        try:
            from influxdb_client import InfluxDBClient
        except ImportError:
            raise ImportError(
                "influxdb-client not installed. Install with: pip install influxdb-client"
            )
        
        self.config = config or InfluxDBConfig()
        
        # Initialize client
        self.client = InfluxDBClient(
            url=self.config.url,
            token=self.config.token,
            org=self.config.org,
            timeout=self.config.timeout,
            verify_ssl=self.config.verify_ssl
        )
        
        self.query_api = self.client.query_api()
        logger.info(f"Query client connected to InfluxDB: {self.config}")
    
    def query(self, 
             query_string: str,
             bucket: Optional[str] = None) -> List[Dict[str, Any]]:
        """
        Execute a Flux query
        
        Args:
            query_string: Flux query string
            bucket: Bucket name (used in query if not specified in query_string)
        
        Returns:
            List of result dictionaries
        
        Example:
            results = query_client.query(
                'from(bucket: "superAppDB") |> range(start: -1h) |> limit(n: 10)'
            )
        """
        try:
            bucket_name = bucket or self.config.bucket
            
            # If query doesn't specify bucket, add it
            if 'from(bucket:' not in query_string and 'from( bucket:' not in query_string:
                query_string = f'from(bucket: "{bucket_name}") |> {query_string}'
            
            tables = self.query_api.query(query_string)
            
            results = []
            for table in tables:
                for record in table.records:
                    results.append({
                        'time': record.get_time(),
                        'measurement': record.get_measurement(),
                        'field': record.get_field(),
                        'value': record.get_value(),
                        'tags': record.values
                    })
            
            logger.info(f"Query returned {len(results)} records")
            return results
            
        except Exception as e:
            logger.error(f"Query failed: {e}")
            return []
    
    def close(self):
        """Close the InfluxDB client connection"""
        try:
            self.client.close()
            logger.info("Query client closed")
        except Exception as e:
            logger.error(f"Error closing query client: {e}")
    
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()


# Convenience function for simple use cases
def write_metric(measurement: str,
                value: float,
                tags: Optional[Dict[str, str]] = None,
                bucket: Optional[str] = None) -> bool:
    """
    Quick helper to write a single metric value
    
    Example:
        write_metric("cpu_usage", 75.5, tags={"host": "server01"})
    """
    with InfluxDBWriter() as writer:
        return writer.write_point(
            measurement=measurement,
            fields={"value": value},
            tags=tags,
            bucket=bucket
        )


if __name__ == "__main__":
    # Example usage
    print("InfluxDB Client Module")
    print("=" * 50)
    
    # Check if credentials are set
    try:
        config = InfluxDBConfig()
        print(f"\n✓ Configuration loaded: {config}")
        
        # Test connection
        with InfluxDBWriter(config) as writer:
            if writer.health_check():
                print("✓ Connection successful!")
                
                # Write a test point
                success = writer.write_point(
                    measurement="test_metric",
                    fields={"value": 123.45},
                    tags={"source": "python_module", "test": "true"}
                )
                
                if success:
                    print("✓ Test write successful!")
            else:
                print("✗ Health check failed")
                
    except ValueError as e:
        print(f"\n✗ Configuration error: {e}")
        print("\nRequired environment variables:")
        print("  - INFLUXDB_URL (or INFLUXDB_V2_URL)")
        print("  - INFLUXDB_TOKEN (or INFLUXDB_V2_TOKEN)")
        print("  - INFLUXDB_ORG (or INFLUXDB_V2_ORG)")
        print("  - INFLUXDB_BUCKET (optional, defaults to 'superAppDB')")
