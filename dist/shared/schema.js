import { sql } from "drizzle-orm";
import { pgTable, text, varchar, timestamp, integer, decimal, jsonb } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
export const anomalies = pgTable("anomalies", {
    id: varchar("id").primaryKey().default(sql `gen_random_uuid()`),
    timestamp: timestamp("timestamp").notNull().default(sql `now()`),
    type: text("type").notNull(),
    description: text("description").notNull(),
    severity: text("severity").notNull(),
    source_file: text("source_file").notNull(),
    packet_number: integer("packet_number").default(1),
    mac_address: text("mac_address"),
    ue_id: text("ue_id"),
    details: jsonb("details"),
    status: text("status").notNull().default('open'),
    recommendation: text("recommendation"),
    error_log: text("error_log"),
    packet_context: text("packet_context"),
});
export const sessions = pgTable("sessions", {
    id: varchar("id").primaryKey().default(sql `gen_random_uuid()`),
    session_id: text("session_id").notNull().unique(),
    start_time: timestamp("start_time").notNull(),
    end_time: timestamp("end_time"),
    packets_analyzed: integer("packets_analyzed").default(0),
    anomalies_detected: integer("anomalies_detected").default(0),
    source_file: text("source_file").notNull(),
});
export const metrics = pgTable("metrics", {
    id: varchar("id").primaryKey().default(sql `gen_random_uuid()`),
    metric_name: text("metric_name").notNull(),
    metric_value: decimal("metric_value").notNull(),
    timestamp: timestamp("timestamp").notNull().default(sql `now()`),
    category: text("category").notNull(),
});
export const processedFiles = pgTable("processed_files", {
    id: varchar("id").primaryKey().default(sql `gen_random_uuid()`),
    filename: text("filename").notNull(),
    file_type: text("file_type").notNull(),
    file_size: integer("file_size").notNull(),
    upload_date: timestamp("upload_date").notNull().default(sql `now()`),
    processing_status: text("processing_status").notNull().default('pending'),
    anomalies_found: integer("anomalies_found").default(0),
    processing_time: integer("processing_time"),
    error_message: text("error_message"),
});
export const insertAnomalySchema = createInsertSchema(anomalies).omit({
    id: true,
    timestamp: true,
});
export const insertSessionSchema = createInsertSchema(sessions).omit({
    id: true,
});
export const insertMetricSchema = createInsertSchema(metrics).omit({
    id: true,
    timestamp: true,
});
export const insertProcessedFileSchema = createInsertSchema(processedFiles).omit({
    id: true,
    upload_date: true,
});
//# sourceMappingURL=schema.js.map