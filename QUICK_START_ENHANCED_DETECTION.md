# Quick Start Guide: Enhanced L1 Anomaly Detection

## 🚀 Getting Started in 3 Steps

### Step 1: Update Database Schema (One-time)
```bash
# Option A: Using ClickHouse client
clickhouse-client --host clickhouse-clickhouse-single --port 9000 --query="ALTER TABLE l1_anomaly_detection.anomalies ADD COLUMN IF NOT EXISTS packet_context String DEFAULT ''"

# Option B: Using SQL file
clickhouse-client --host clickhouse-clickhouse-single --port 9000 < add_packet_context_column.sql
```

### Step 2: Run Enhanced Analysis
```bash
# Process your PCAP/log files with all new features
python folder_anomaly_analyzer_clickhouse.py /app/input_files
```

### Step 3: View Results in Dashboard
1. Open the web application at `http://localhost:5000`
2. Navigate to Dashboard → Anomalies
3. See all detected anomalies including:
   - RACH Failures
   - Handover Failures
   - HARQ Retransmissions
   - CRC Errors
   - RRC Connection Failures
   - Timing Advance Violations
   - Power Control Anomalies
4. Click "Recommend" for AI-powered troubleshooting with packet context

---

## 🎯 What You Get

### 7 New Anomaly Types Automatically Detected
Every PCAP file is now analyzed for:
1. **RACH Failures** - Connection establishment issues
2. **Handover Failures** - Mobility problems
3. **HARQ Retransmissions** - Radio quality issues
4. **CRC Errors** - Data corruption
5. **RRC Connection Failures** - Control plane issues
6. **Timing Advance Violations** - Synchronization problems
7. **Power Control Anomalies** - Power management issues

### Packet Context for Every Anomaly
- Anomaly packet + 2 packets before + 2 packets after
- Full layer-by-layer details (Ethernet, IP, UDP, payload)
- Timestamps and packet sizes
- Stored in database for AI analysis

---

## 📊 Sample Output

```
Processing PCAP: network_capture.pcap
Loaded 15847 packets
  Running advanced L1 anomaly detection...
  Advanced detection found 12 additional anomalies:
    - RACH Failure: 3
    - Handover Failure: 2
    - HARQ Retransmissions: 4
    - CRC Error: 1
    - RRC Connection Failure: 2
  
SUCCESS: 12 high-confidence anomalies stored in ClickHouse database
```

---

## 🔍 Verifying It Works

### Check Database
```sql
-- Count anomalies with packet context
SELECT COUNT(*) FROM anomalies WHERE packet_context != '';

-- See anomaly type distribution
SELECT anomaly_type, COUNT(*) as count 
FROM anomalies 
GROUP BY anomaly_type 
ORDER BY count DESC;

-- View sample packet context
SELECT id, anomaly_type, LEFT(packet_context, 500) as context_preview
FROM anomalies 
WHERE packet_context != '' 
LIMIT 3;
```

### Check Console Output
Look for these messages when running the analyzer:
- ✓ "Running advanced L1 anomaly detection..."
- ✓ "Advanced detection found X additional anomalies"
- ✓ Breakdown by anomaly type (RACH, Handover, etc.)

---

## 📁 Key Files Reference

| File | Purpose |
|------|---------|
| `add_packet_context_column.sql` | Database schema update |
| `folder_anomaly_analyzer_clickhouse.py` | Main analyzer with new detection (lines 135-625) |
| `NEW_ANOMALY_TYPES_DOCUMENTATION.md` | Detailed docs for all 7 types |
| `IMPLEMENTATION_SUMMARY.md` | Complete implementation overview |
| `replit.md` | System architecture (updated) |

---

## 💡 Tips

### Performance
- First run may be slower (loading ML models)
- PCAP files are cached during analysis
- Packet context adds minimal overhead (~10-15%)

### Troubleshooting
- If Scapy errors: `pip install scapy`
- If column errors: Run the SQL script from Step 1
- If no new anomalies: Check PCAP contains L1 signaling data

### Best Practices
- Process files in batches for efficiency
- Review AI recommendations for root cause analysis
- Export anomaly reports for historical tracking

---

## 🎓 Learn More

- **NEW_ANOMALY_TYPES_DOCUMENTATION.md** - Deep dive into each anomaly type
- **IMPLEMENTATION_SUMMARY.md** - Technical implementation details
- **3GPP Standards** - TS 36.321, TS 36.331, TS 36.213

---

## ✅ Success Checklist

- [ ] Database schema updated (packet_context column added)
- [ ] Scapy installed (`pip list | grep scapy`)
- [ ] Ran analyzer on sample PCAP file
- [ ] Saw "Advanced detection found X anomalies" message
- [ ] Verified anomalies in database with `SELECT` query
- [ ] Viewed results in dashboard
- [ ] Tested AI recommendations with packet context

**Ready to go! Your L1 troubleshooting system now has advanced anomaly detection with comprehensive packet context analysis.**
