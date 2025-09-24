import { log } from '../vite';

interface ClickHouseConnection {
  command: (query: string) => Promise<any>;
  query: (query: string) => Promise<any>;
}

export class StartupService {
  private clickhouseClient: ClickHouseConnection | null = null;

  async initializeServices(): Promise<void> {
    log('🚀 Initializing L1 Network Troubleshooting System...');
    
    // Initialize ClickHouse connection
    await this.initializeClickHouse();
    
    log('✅ All startup services initialized successfully');
  }

  private async initializeClickHouse(): Promise<void> {
    log('🔗 Connecting to ClickHouse database...');

    try {
      // Connect to ClickHouse using HTTP API (Node.js compatible)
      const clickhouseHost = process.env.CLICKHOUSE_HOST || 'chi-clickhouse-single-clickhouse-0-0-0.l1-app-ai.svc.cluster.local';
      const clickhousePort = parseInt(process.env.CLICKHOUSE_PORT || '8123');
      const clickhouseUser = process.env.CLICKHOUSE_USERNAME || 'default';
      const clickhousePassword = process.env.CLICKHOUSE_PASSWORD || 'defaultpass';
      const clickhouseDatabase = process.env.CLICKHOUSE_DATABASE || 'l1_anomaly_detection';

      // Create HTTP client for ClickHouse
      this.clickhouseClient = {
        baseUrl: `http://${clickhouseHost}:${clickhousePort}`,
        auth: Buffer.from(`${clickhouseUser}:${clickhousePassword}`).toString('base64'),
        database: clickhouseDatabase,
        command: async (query: string) => {
          const response = await fetch(`${this.clickhouseClient!.baseUrl}/?database=${this.clickhouseClient!.database}`, {
            method: 'POST',
            headers: {
              'Authorization': `Basic ${this.clickhouseClient!.auth}`,
              'Content-Type': 'text/plain'
            },
            body: query
          });
          
          if (!response.ok) {
            throw new Error(`ClickHouse HTTP ${response.status}: ${response.statusText}`);
          }
          
          return await response.text();
        },
        query: async (query: string) => {
          const response = await fetch(`${this.clickhouseClient!.baseUrl}/?database=${this.clickhouseClient!.database}&default_format=JSONCompact`, {
            method: 'POST',
            headers: {
              'Authorization': `Basic ${this.clickhouseClient!.auth}`,
              'Content-Type': 'text/plain'
            },
            body: query
          });
          
          if (!response.ok) {
            throw new Error(`ClickHouse HTTP ${response.status}: ${response.statusText}`);
          }
          
          const result = await response.json();
          return { result_rows: result.data || [] };
        }
      } as any;

      // Test connection
      await this.clickhouseClient.command('SELECT 1');
      
      log('✅ ClickHouse connection established');
      log(`📊 Connected to: ${clickhouseHost}:${clickhousePort}`);
      log(`💾 Database: ${clickhouseDatabase}`);

      // Display database information
      await this.displayDatabaseInfo();

    } catch (error) {
      log(`❌ ClickHouse connection failed: ${error}`);
      log('📋 Application will continue without database features');
      this.clickhouseClient = null;
    }
  }

  private async displayDatabaseInfo(): Promise<void> {
    if (!this.clickhouseClient) {
      return;
    }

    try {
      // Get database information
      const databaseQuery = "SELECT name FROM system.databases WHERE name = 'l1_anomaly_detection'";
      const databaseResult = await this.clickhouseClient.query(databaseQuery);
      
      if (databaseResult.result_rows && databaseResult.result_rows.length > 0) {
        log('🗄️  Database: l1_anomaly_detection [EXISTS]');
        
        // Get table information
        const tablesQuery = `
          SELECT name, engine, total_rows, total_bytes 
          FROM system.tables 
          WHERE database = 'l1_anomaly_detection' 
          ORDER BY name
        `;
        const tablesResult = await this.clickhouseClient.query(tablesQuery);
        
        if (tablesResult.result_rows && tablesResult.result_rows.length > 0) {
          log(`📋 Found ${tablesResult.result_rows.length} tables:`);
          
          let totalRows = 0;
          let totalBytes = 0;
          
          tablesResult.result_rows.forEach((row: any[]) => {
            const [name, engine, rows, bytes] = row;
            totalRows += rows || 0;
            totalBytes += bytes || 0;
            
            const rowsStr = rows ? rows.toLocaleString() : '0';
            const sizeStr = this.formatBytes(bytes || 0);
            log(`   • ${name} (${engine}): ${rowsStr} rows, ${sizeStr}`);
          });
          
          log(`📊 Total: ${totalRows.toLocaleString()} rows, ${this.formatBytes(totalBytes)}`);
        } else {
          log('📋 No tables found - database is empty');
          log('💡 Run setup_clickhouse_tables.py to create schema');
        }
      } else {
        log('❗ Database l1_anomaly_detection not found');
        log('💡 Create database: CREATE DATABASE l1_anomaly_detection');
      }

      // Display recent activity
      await this.displayRecentActivity();

    } catch (error) {
      log(`⚠️  Could not retrieve database info: ${error}`);
    }
  }

  private async displayRecentActivity(): Promise<void> {
    if (!this.clickhouseClient) {
      return;
    }

    try {
      // Check for recent anomalies
      const recentAnomaliesQuery = `
        SELECT COUNT(*) as count, toDate(timestamp) as date
        FROM l1_anomaly_detection.anomalies 
        WHERE timestamp >= now() - INTERVAL 7 DAY
        GROUP BY date
        ORDER BY date DESC
        LIMIT 7
      `;
      
      const recentResult = await this.clickhouseClient.query(recentAnomaliesQuery);
      
      if (recentResult.result_rows && recentResult.result_rows.length > 0) {
        log('📈 Recent anomaly activity (last 7 days):');
        recentResult.result_rows.forEach((row: any[]) => {
          const [count, date] = row;
          log(`   • ${date}: ${count} anomalies detected`);
        });
      }

      // Check for active sessions
      const activeSessionsQuery = `
        SELECT COUNT(*) as count 
        FROM l1_anomaly_detection.sessions 
        WHERE status = 'active'
      `;
      
      const sessionsResult = await this.clickhouseClient.query(activeSessionsQuery);
      if (sessionsResult.result_rows && sessionsResult.result_rows.length > 0) {
        const activeCount = sessionsResult.result_rows[0][0];
        if (activeCount > 0) {
          log(`🔄 Active analysis sessions: ${activeCount}`);
        }
      }

    } catch (error) {
      // Silently handle if tables don't exist yet
      log('💡 No recent activity data available');
    }
  }

  private formatBytes(bytes: number): string {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  }

  public getClickHouseClient(): ClickHouseConnection | null {
    return this.clickhouseClient;
  }

  public isClickHouseAvailable(): boolean {
    return this.clickhouseClient !== null;
  }
}