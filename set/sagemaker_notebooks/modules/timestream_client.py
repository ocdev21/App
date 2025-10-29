"""
AWS Timestream Integration Module
Provides database creation and query functionality for SageMaker notebooks
"""

import boto3
import pandas as pd
from typing import List, Dict, Any, Optional
from botocore.exceptions import ClientError
from datetime import datetime


class TimestreamClient:
    """Client for interacting with AWS Timestream database"""
    
    def __init__(
        self,
        database_name: str = "SuperAppDB",
        table_name: str = "UEReports",
        region_name: str = "us-east-1"
    ):
        """
        Initialize Timestream client
        
        Args:
            database_name: Name of Timestream database
            table_name: Name of Timestream table
            region_name: AWS region (default: us-east-1)
        """
        self.database_name = database_name
        self.table_name = table_name
        self.region_name = region_name
        
        # Initialize clients
        self.write_client = boto3.client(
            service_name='timestream-write',
            region_name=region_name
        )
        self.query_client = boto3.client(
            service_name='timestream-query',
            region_name=region_name
        )
    
    def create_database(self) -> Dict[str, Any]:
        """
        Create Timestream database if it doesn't exist
        
        Returns:
            Dict with status and database ARN
        """
        try:
            response = self.write_client.create_database(
                DatabaseName=self.database_name
            )
            return {
                "status": "created",
                "message": f"Database '{self.database_name}' created successfully",
                "arn": response['Database']['Arn']
            }
        except ClientError as e:
            if e.response['Error']['Code'] == 'ConflictException':
                return {
                    "status": "exists",
                    "message": f"Database '{self.database_name}' already exists"
                }
            else:
                raise Exception(f"Failed to create database: {str(e)}")
    
    def create_table(self) -> Dict[str, Any]:
        """
        Create Timestream table if it doesn't exist
        
        Returns:
            Dict with status and table ARN
        """
        try:
            response = self.write_client.create_table(
                DatabaseName=self.database_name,
                TableName=self.table_name,
                RetentionProperties={
                    'MemoryStoreRetentionPeriodInHours': 24,
                    'MagneticStoreRetentionPeriodInDays': 7
                }
            )
            return {
                "status": "created",
                "message": f"Table '{self.table_name}' created successfully",
                "arn": response['Table']['Arn']
            }
        except ClientError as e:
            if e.response['Error']['Code'] == 'ConflictException':
                return {
                    "status": "exists",
                    "message": f"Table '{self.table_name}' already exists"
                }
            else:
                raise Exception(f"Failed to create table: {str(e)}")
    
    def setup_database(self) -> Dict[str, Any]:
        """
        Setup database and table (creates if they don't exist)
        
        Returns:
            Dict with setup status
        """
        db_result = self.create_database()
        table_result = self.create_table()
        
        return {
            "database": db_result,
            "table": table_result,
            "ready": True
        }
    
    def query(self, query_string: Optional[str] = None) -> pd.DataFrame:
        """
        Query Timestream table and return results as pandas DataFrame
        
        Args:
            query_string: Custom SQL query (default: SELECT * FROM table LIMIT 100)
            
        Returns:
            pandas DataFrame with query results
        """
        if query_string is None:
            query_string = f"SELECT * FROM {self.database_name}.{self.table_name} ORDER BY time DESC LIMIT 100"
        
        try:
            response = self.query_client.query(QueryString=query_string)
            return self._parse_response_to_dataframe(response)
        
        except ClientError as e:
            error_code = e.response['Error']['Code']
            
            if error_code == 'ResourceNotFoundException':
                raise Exception(
                    f"Database or table not found. Run setup_database() first."
                )
            else:
                raise Exception(f"Query failed: {str(e)}")
    
    def _parse_response_to_dataframe(self, response: Dict[str, Any]) -> pd.DataFrame:
        """
        Parse Timestream query response to pandas DataFrame
        
        Args:
            response: Timestream query response
            
        Returns:
            pandas DataFrame
        """
        column_info = response['ColumnInfo']
        rows = response.get('Rows', [])
        
        if not rows:
            # Return empty DataFrame with correct column names
            columns = [col['Name'] for col in column_info]
            return pd.DataFrame(columns=columns)
        
        # Extract column names
        columns = [col['Name'] for col in column_info]
        
        # Parse rows
        data = []
        for row in rows:
            row_data = {}
            for i, col in enumerate(columns):
                if i < len(row['Data']):
                    cell = row['Data'][i]
                    if 'ScalarValue' in cell:
                        row_data[col] = cell['ScalarValue']
                    else:
                        row_data[col] = None
                else:
                    row_data[col] = None
            data.append(row_data)
        
        return pd.DataFrame(data)
    
    def write_records(
        self,
        records: List[Dict[str, Any]],
        current_time: Optional[int] = None
    ) -> Dict[str, Any]:
        """
        Write records to Timestream table
        
        Args:
            records: List of records to write
            current_time: Current time in milliseconds (default: now)
            
        Returns:
            Dict with write status
            
        Example record format:
        {
            'Dimensions': [
                {'Name': 'device_id', 'Value': 'device-001'},
                {'Name': 'location', 'Value': 'datacenter-1'}
            ],
            'MeasureName': 'cpu_usage',
            'MeasureValue': '75.5',
            'MeasureValueType': 'DOUBLE'
        }
        """
        if current_time is None:
            current_time = int(datetime.now().timestamp() * 1000)
        
        # Add timestamp to each record
        for record in records:
            if 'Time' not in record:
                record['Time'] = str(current_time)
            if 'TimeUnit' not in record:
                record['TimeUnit'] = 'MILLISECONDS'
        
        try:
            response = self.write_client.write_records(
                DatabaseName=self.database_name,
                TableName=self.table_name,
                Records=records
            )
            return {
                "status": "success",
                "message": f"Successfully wrote {len(records)} record(s)",
                "records_processed": response.get('RecordsIngested', {})
            }
        except ClientError as e:
            raise Exception(f"Failed to write records: {str(e)}")
    
    def test_connection(self) -> Dict[str, Any]:
        """
        Test connection to Timestream by describing the table
        
        Returns:
            Dict with status and details
        """
        try:
            response = self.write_client.describe_table(
                DatabaseName=self.database_name,
                TableName=self.table_name
            )
            return {
                "status": "success",
                "message": f"Successfully connected to Timestream",
                "database": self.database_name,
                "table": self.table_name,
                "region": self.region_name,
                "table_status": response['Table']['TableStatus']
            }
        except ClientError as e:
            if e.response['Error']['Code'] == 'ResourceNotFoundException':
                return {
                    "status": "not_found",
                    "message": f"Table '{self.table_name}' not found. Run setup_database() first.",
                    "database": self.database_name,
                    "table": self.table_name
                }
            else:
                return {
                    "status": "error",
                    "message": str(e),
                    "database": self.database_name,
                    "table": self.table_name
                }


# Example usage
if __name__ == "__main__":
    # Initialize client
    timestream = TimestreamClient(
        database_name="SuperAppDB",
        table_name="UEReports",
        region_name="us-east-1"
    )
    
    # Setup database
    print("Setting up Timestream database...")
    result = timestream.setup_database()
    print(f"Database: {result['database']['message']}")
    print(f"Table: {result['table']['message']}")
    
    # Test connection
    print("\nTesting Timestream connection...")
    test_result = timestream.test_connection()
    print(f"Status: {test_result['status']}")
    print(f"Message: {test_result['message']}")
    
    if test_result['status'] == 'success':
        # Query data
        print("\nQuerying data...")
        df = timestream.query()
        print(f"Found {len(df)} records")
        if len(df) > 0:
            print(df.head())
        else:
            print("No data in table. Use write_records() to add sample data.")
