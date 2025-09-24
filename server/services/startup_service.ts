import { log } from '../vite';
import { clickhouse } from '../clickhouse';

export class StartupService {

  async initializeServices(): Promise<void> {
    log('🚀 Initializing L1 Network Troubleshooting System...');
    
    // Initialize ClickHouse connection
    await this.initializeClickHouse();
    
    log('✅ All startup services initialized successfully');
  }

  private async initializeClickHouse(): Promise<void> {
    log('🔗 Connecting to ClickHouse database...');

    try {
      // Test connection using shared ClickHouse client
      await clickhouse.testConnection();
      
      log('✅ ClickHouse connection established');
      log('📊 Connected to: chi-clickhouse-single-clickhouse-0-0-0.l1-app-ai.svc.cluster.local:9000');
      log('💾 Database: l1_anomaly_detection');

      // Display database information
      await this.displayDatabaseInfo();

    } catch (error) {
      log(`❌ ClickHouse connection failed: ${error}`);
      log('📋 Application will continue without database features');
    }
  }

  private async displayDatabaseInfo(): Promise<void> {
    if (!clickhouse.isAvailable()) {
      return;
    }

    try {
      // Get database information
      const databaseQuery = "SELECT name FROM system.databases WHERE name = 'l1_anomaly_detection'";
      const databaseResult = await clickhouse.query(databaseQuery);
      
      if (databaseResult && databaseResult.length > 0) {
        log('🗄️  Database: l1_anomaly_detection [EXISTS]');
        
        // Get table information
        const tablesQuery = `
          SELECT name, engine, total_rows, total_bytes 
          FROM system.tables 
          WHERE database = 'l1_anomaly_detection' 
          ORDER BY name
        `;
        const tablesResult = await clickhouse.query(tablesQuery);
        
        if (tablesResult && tablesResult.length > 0) {
          log(`📋 Found ${tablesResult.length} tables:`);
          
          let totalRows = 0;
          let totalBytes = 0;
          
          tablesResult.forEach((row: any[]) => {
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
    if (!clickhouse.isAvailable()) {
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
      
      const recentResult = await clickhouse.query(recentAnomaliesQuery);
      
      if (recentResult && recentResult.length > 0) {
        log('📈 Recent anomaly activity (last 7 days):');
        recentResult.forEach((row: any[]) => {
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
      
      const sessionsResult = await clickhouse.query(activeSessionsQuery);
      if (sessionsResult && sessionsResult.length > 0) {
        const activeCount = sessionsResult[0][0];
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

  public getClickHouseClient() {
    return clickhouse.getClient();
  }

  public isClickHouseAvailable(): boolean {
    return clickhouse.isAvailable();
  }
}