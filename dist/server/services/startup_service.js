import { log } from '../vite';
import { clickhouse } from '../clickhouse';
export class StartupService {
    async initializeServices() {
        log('Initializing L1 Network Troubleshooting System...');
        await this.initializeClickHouse();
        log('All startup services initialized successfully');
    }
    async initializeClickHouse() {
        log('Connecting to ClickHouse database...');
        try {
            await clickhouse.testConnection();
            log('ClickHouse connection established');
            log('Connected to: chi-clickhouse-single-clickhouse-0-0-0.l1-app-ai.svc.cluster.local:9000');
            log('Database: l1_anomaly_detection');
            await this.displayDatabaseInfo();
        }
        catch (error) {
            log(`ERROR: ClickHouse connection failed: ${error}`);
            log('Application will continue without database features');
        }
    }
    async displayDatabaseInfo() {
        if (!clickhouse.isAvailable()) {
            return;
        }
        try {
            const databaseQuery = "SELECT name FROM system.databases WHERE name = 'l1_anomaly_detection'";
            const databaseResult = await clickhouse.query(databaseQuery);
            if (databaseResult && databaseResult.length > 0) {
                log('Database: l1_anomaly_detection [EXISTS]');
                const tablesQuery = `
          SELECT name, engine, total_rows, total_bytes 
          FROM system.tables 
          WHERE database = 'l1_anomaly_detection' 
          ORDER BY name
        `;
                const tablesResult = await clickhouse.query(tablesQuery);
                if (tablesResult && tablesResult.length > 0) {
                    log(`Found ${tablesResult.length} tables:`);
                    let totalRows = 0;
                    let totalBytes = 0;
                    tablesResult.forEach((row) => {
                        const [name, engine, rows, bytes] = row;
                        totalRows += rows || 0;
                        totalBytes += bytes || 0;
                        const rowsStr = rows ? rows.toLocaleString() : '0';
                        const sizeStr = this.formatBytes(bytes || 0);
                        log(`   • ${name} (${engine}): ${rowsStr} rows, ${sizeStr}`);
                    });
                    log(`Total: ${totalRows.toLocaleString()} rows, ${this.formatBytes(totalBytes)}`);
                }
                else {
                    log('No tables found - database is empty');
                    log('TIP: Run setup_clickhouse_tables.py to create schema');
                }
            }
            else {
                log('ERROR: Database l1_anomaly_detection not found');
                log('TIP: Create database: CREATE DATABASE l1_anomaly_detection');
            }
            await this.displayRecentActivity();
        }
        catch (error) {
            log(`WARNING: Could not retrieve database info: ${error}`);
        }
    }
    async displayRecentActivity() {
        if (!clickhouse.isAvailable()) {
            return;
        }
        try {
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
                log('Recent anomaly activity (last 7 days):');
                recentResult.forEach((row) => {
                    const [count, date] = row;
                    log(`   • ${date}: ${count} anomalies detected`);
                });
            }
            const activeSessionsQuery = `
        SELECT COUNT(*) as count 
        FROM l1_anomaly_detection.sessions 
        WHERE status = 'active'
      `;
            const sessionsResult = await clickhouse.query(activeSessionsQuery);
            if (sessionsResult && sessionsResult.length > 0) {
                const activeCount = sessionsResult[0][0];
                if (activeCount > 0) {
                    log(`Active analysis sessions: ${activeCount}`);
                }
            }
        }
        catch (error) {
            log('No recent activity data available');
        }
    }
    formatBytes(bytes) {
        if (bytes === 0)
            return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }
    getClickHouseClient() {
        return clickhouse.getClient();
    }
    isClickHouseAvailable() {
        return clickhouse.isAvailable();
    }
}
//# sourceMappingURL=startup_service.js.map