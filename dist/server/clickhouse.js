import { createClient } from '@clickhouse/client';
class ClickHouseDB {
    client;
    isConnected = false;
    constructor() {
        const clickhouseHost = process.env.CLICKHOUSE_HOST || 'clickhouse-clickhouse-single';
        const clickhousePort = process.env.CLICKHOUSE_PORT || '8123';
        const clickhouseUser = process.env.CLICKHOUSE_USER || 'default';
        const clickhousePassword = process.env.CLICKHOUSE_PASSWORD || 'defaultpass';
        const clickhouseDatabase = process.env.CLICKHOUSE_DATABASE || 'l1_anomaly_detection';
        const config = {
            url: `http://${clickhouseUser}:${clickhousePassword}@${clickhouseHost}:${clickhousePort}/${clickhouseDatabase}`,
            database: clickhouseDatabase,
        };
        console.log('Connecting to ClickHouse server at:', `${clickhouseHost}:${clickhousePort}`);
        this.client = createClient(config);
    }
    async testConnection() {
        try {
            const result = await this.client.query({
                query: 'SELECT 1 as test',
            });
            await this.client.query({
                query: 'SELECT count() FROM l1_anomaly_detection.anomalies LIMIT 1'
            });
            console.log('ClickHouse connection successful - Real data access enabled');
            this.isConnected = true;
            return true;
        }
        catch (error) {
            console.error('ERROR: ClickHouse connection failed:', error.message);
            console.error('ERROR: REAL DATA ONLY: Cannot fallback to sample data');
            console.error('Please ensure ClickHouse pod is running with l1_anomaly_detection database');
            this.isConnected = false;
            throw error;
        }
    }
    async queryWithParams(sql, queryParams) {
        try {
            const result = await this.client.query({
                query: sql,
                query_params: queryParams,
            });
            const data = await result.json();
            return data.data || [];
        }
        catch (error) {
            console.error('ClickHouse Query Error:', error);
            throw error;
        }
    }
    async query(sql, params = []) {
        try {
            let processedQuery = sql;
            if (params && params.length > 0) {
                let paramIndex = 0;
                processedQuery = sql.replace(/\?/g, () => {
                    const value = params[paramIndex++];
                    if (value === null || value === undefined)
                        return 'NULL';
                    return typeof value === 'string' ? `'${value.replace(/'/g, "''")}'` : String(value);
                });
            }
            console.log('Executing ClickHouse Query:', processedQuery);
            const result = await this.client.query({
                query: processedQuery,
                clickhouse_settings: {
                    use_client_time_zone: 1
                }
            });
            const data = await result.json();
            return data.data || [];
        }
        catch (error) {
            console.error('ClickHouse Query Error:', error);
            throw error;
        }
    }
    async insert(table, data) {
        if (!this.isConnected && !(await this.testConnection())) {
            throw new Error('ClickHouse not available');
        }
        try {
            await this.client.insert({
                table,
                values: data,
                format: 'JSONEachRow',
            });
        }
        catch (error) {
            console.error('ClickHouse Insert Error:', error);
            throw error;
        }
    }
    async command(sql) {
        if (!this.isConnected && !(await this.testConnection())) {
            throw new Error('ClickHouse not available');
        }
        try {
            await this.client.command({ query: sql });
        }
        catch (error) {
            console.error('ClickHouse Command Error:', error);
            throw error;
        }
    }
    getClient() {
        return this.client;
    }
    isAvailable() {
        return this.isConnected;
    }
}
export const clickhouse = new ClickHouseDB();
export default clickhouse;
//# sourceMappingURL=clickhouse.js.map