import {
  TimestreamWriteClient,
  CreateDatabaseCommand,
  CreateTableCommand,
  DescribeDatabaseCommand,
  DescribeTableCommand,
  ResourceNotFoundException,
} from "@aws-sdk/client-timestream-write";
import {
  TimestreamQueryClient,
  QueryCommand,
  QueryCommandOutput,
} from "@aws-sdk/client-timestream-query";

const DATABASE_NAME = process.env.TIMESTREAM_DATABASE_NAME || "SuperAppDB";
const TABLE_NAME = "UEReports";

// Initialize Timestream clients
const getWriteClient = () => {
  const region = process.env.AWS_REGION;
  
  if (!region) {
    throw new Error("AWS_REGION environment variable is not set");
  }

  return new TimestreamWriteClient({
    region,
    credentials: {
      accessKeyId: process.env.AWS_ACCESS_KEY_ID!,
      secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY!,
    },
  });
};

const getQueryClient = () => {
  const region = process.env.AWS_REGION;
  
  if (!region) {
    throw new Error("AWS_REGION environment variable is not set");
  }

  return new TimestreamQueryClient({
    region,
    credentials: {
      accessKeyId: process.env.AWS_ACCESS_KEY_ID!,
      secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY!,
    },
  });
};

/**
 * Check if database exists
 */
async function databaseExists(client: TimestreamWriteClient): Promise<boolean> {
  try {
    await client.send(new DescribeDatabaseCommand({ DatabaseName: DATABASE_NAME }));
    return true;
  } catch (error) {
    if (error instanceof ResourceNotFoundException) {
      return false;
    }
    throw error;
  }
}

/**
 * Check if table exists
 */
async function tableExists(client: TimestreamWriteClient): Promise<boolean> {
  try {
    await client.send(
      new DescribeTableCommand({
        DatabaseName: DATABASE_NAME,
        TableName: TABLE_NAME,
      })
    );
    return true;
  } catch (error) {
    if (error instanceof ResourceNotFoundException) {
      return false;
    }
    throw error;
  }
}

/**
 * Create Timestream database if it doesn't exist
 */
async function createDatabaseIfNotExists(client: TimestreamWriteClient): Promise<void> {
  const exists = await databaseExists(client);
  
  if (!exists) {
    console.log(`Creating Timestream database: ${DATABASE_NAME}`);
    await client.send(
      new CreateDatabaseCommand({
        DatabaseName: DATABASE_NAME,
        Tags: [
          { Key: "Environment", Value: "Production" },
          { Key: "Application", Value: "SuperApp" },
          { Key: "IAMRole", Value: "superapp-timestream-admin" },
        ],
      })
    );
    console.log(`Database ${DATABASE_NAME} created successfully`);
  } else {
    console.log(`Database ${DATABASE_NAME} already exists`);
  }
}

/**
 * Create UEReports table if it doesn't exist
 */
async function createTableIfNotExists(client: TimestreamWriteClient): Promise<void> {
  const exists = await tableExists(client);
  
  if (!exists) {
    console.log(`Creating Timestream table: ${TABLE_NAME}`);
    await client.send(
      new CreateTableCommand({
        DatabaseName: DATABASE_NAME,
        TableName: TABLE_NAME,
        RetentionProperties: {
          MemoryStoreRetentionPeriodInHours: 24,
          MagneticStoreRetentionPeriodInDays: 7,
        },
        Tags: [
          { Key: "Environment", Value: "Production" },
          { Key: "Application", Value: "SuperApp" },
          { Key: "IAMRole", Value: "superapp-timestream-admin" },
        ],
      })
    );
    console.log(`Table ${TABLE_NAME} created successfully`);
  } else {
    console.log(`Table ${TABLE_NAME} already exists`);
  }
}

/**
 * Setup Timestream database and table
 */
export async function setupTimestreamDB(): Promise<{ success: boolean; message: string }> {
  try {
    const writeClient = getWriteClient();
    
    await createDatabaseIfNotExists(writeClient);
    await createTableIfNotExists(writeClient);
    
    return {
      success: true,
      message: `Timestream database '${DATABASE_NAME}' and table '${TABLE_NAME}' are ready`,
    };
  } catch (error) {
    console.error("Timestream setup error:", error);
    
    if (error instanceof Error) {
      if (error.message.includes("AccessDeniedException")) {
        throw new Error("AWS credentials don't have permission to access Timestream. Ensure IAM role 'superapp-timestream-admin' has proper permissions.");
      }
      throw error;
    }
    
    throw new Error("Failed to setup Timestream database");
  }
}

/**
 * Query UEReports table from Timestream
 */
export async function queryUEReports(): Promise<QueryCommandOutput> {
  try {
    const queryClient = getQueryClient();
    
    // Query to get latest records from UEReports table
    const query = `
      SELECT * FROM "${DATABASE_NAME}"."${TABLE_NAME}"
      ORDER BY time DESC
      LIMIT 100
    `;
    
    const command = new QueryCommand({
      QueryString: query,
    });
    
    const response = await queryClient.send(command);
    return response;
  } catch (error) {
    console.error("Timestream query error:", error);
    
    if (error instanceof Error) {
      if (error.message.includes("ResourceNotFoundException")) {
        // Database or table doesn't exist yet - setup and return empty result
        await setupTimestreamDB();
        // Return empty result structure
        return {
          Rows: [],
          ColumnInfo: [],
          QueryStatus: { ProgressPercentage: 100 },
          $metadata: {},
        };
      } else if (error.message.includes("AccessDeniedException")) {
        throw new Error("AWS credentials don't have permission to query Timestream. Ensure IAM role 'superapp-timestream-query' has proper permissions.");
      }
      throw error;
    }
    
    throw new Error("Failed to query Timestream database");
  }
}

/**
 * Parse Timestream query response into readable format
 */
export function parseTimestreamResponse(response: QueryCommandOutput) {
  const records: Array<Record<string, any>> = [];
  const columnInfo = response.ColumnInfo?.map(col => ({
    name: col.Name || "",
    type: col.Type?.ScalarType || "UNKNOWN",
  })) || [];

  response.Rows?.forEach(row => {
    const record: Record<string, any> = {};
    row.Data?.forEach((datum, index) => {
      const columnName = columnInfo[index]?.name || `column_${index}`;
      record[columnName] = datum.ScalarValue || null;
    });
    records.push(record);
  });

  return {
    records,
    columnInfo,
    queryStatus: response.QueryStatus?.ProgressPercentage || 0,
  };
}
