# L1 Troubleshooting System

## Overview
This project delivers a comprehensive L1 Network Troubleshooting System featuring AI-powered anomaly detection and real-time streaming recommendations. Its primary purpose is to provide immediate insights and actionable recommendations for network issues. Key capabilities include advanced anomaly detection across fronthaul, UE event processing, and MAC layer analysis, coupled with AI-powered recommendations delivered via TSLAM-4B integration. The system also offers a real-time dashboard for live metrics and trend analysis, supported by a dual database architecture using PostgreSQL and ClickHouse. The ambition is to provide a robust, efficient, and intelligent solution for network health monitoring and problem resolution.

## User Preferences
I prefer iterative development, with a focus on clear, maintainable code. I value detailed explanations for complex changes and architectural decisions. Please ask before making any major structural changes or adding new external dependencies. When implementing new features, prioritize a clean and intuitive user interface. I also prefer all output and logging to be clean and professional, without emojis or unnecessary visual clutter. Do not make changes to folder `Z` and file `Y`.

## System Architecture

### UI/UX Decisions
The frontend is built with React, TypeScript, and Vite, emphasizing a clean, professional, and simplified user interface. The design incorporates rounded, pill-shaped buttons for actions like "Recommend" and "Details," and popup windows feature distinct blue headers. Table rows have a light yellow hover effect and visible borders, with a grey header row for clarity. The system uses standalone browser windows for recommendations and detailed anomaly explanations for improved user experience. All dark mode features and related styling have been removed to maintain a consistent light theme.

**Recommendations Display**: AI recommendations are displayed in an auto-growing content area with word wrapping enabled to prevent text overflow. The display automatically expands from 200px to 800px based on content length, with scrolling enabled for longer content. It uses dashboard-consistent styling with `border-gray-200` borders and includes an animated streaming indicator during AI response generation.

**Dashboard Metrics Cards**: Change indicators use non-breaking spaces (&nbsp;) to keep "from last week" text together on a single line. Cache control headers (`Cache-Control: no-cache, no-store, must-revalidate`) are set on all static file responses to ensure UI updates are immediately visible to users.

### Technical Implementations
The backend is an Express.js server with WebSocket support, handling API requests and data streaming. AI-powered recommendations are integrated using the TSLAM-4B model with an enhanced prompt engineering structure. Anomaly detection employs a hybrid approach for UE events, combining rule-based and ML-based detection (Isolation Forest, DBSCAN, One-Class SVM, LOF) with a 16-dimensional feature extraction. The system utilizes Server-Sent Events (SSE) for streaming AI recommendations to the frontend, ensuring reliable, one-way communication. All metrics and dashboard charts dynamically fetch data from the chosen database, with a robust fallback mechanism to in-memory storage (`MemStorage`) with time-distributed dummy data if the primary database is unavailable or returns no results. Comprehensive rule-based fallback recommendations are provided for all anomaly types when the AI service is not accessible.

**ClickHouse DateTime Handling**: All DateTime columns in ClickHouse use Python datetime objects directly (not None/null values). The ML analyzer uses `datetime.now()` for timestamp fields to ensure proper serialization.

**AI Prompt Engineering**: The LLM uses a structured prompt system with enhanced context including anomaly ID, type, severity, timestamp, source file, technical details (error_log), network entities (MAC address, UE ID), and packet info. The prompt requests a 5-section analysis: (1) Root Cause Analysis, (2) Critical Immediate Actions, (3) Important Investigation Steps, (4) Resolution Steps, and (5) Optional Prevention Measures. LLM parameters: max_tokens=800, temperature=0.2, top_p=0.9, presence_penalty=0.1 for deterministic, detailed responses.

**Anomalies Table Pagination**: The frontend fetches up to 10,000 anomaly records from the API (using `?limit=10000` parameter) and implements client-side pagination, filtering, and sorting. This ensures all database records are available for display and the pagination correctly shows the total count from the database.

### Feature Specifications
- **Advanced Anomaly Detection**: Incorporates fronthaul analysis, UE event processing, and MAC layer analysis. Features include ML-based UE event detection with ensemble voting, enhanced rule-based UE attach/detach failure detection with flexible pattern matching and lower thresholds, and sensitive ML anomaly detection with lowered contamination thresholds and 16D feature vectors. **NEW (October 2025)**: Added 7 advanced L1 anomaly types: (1) RACH Failures - random access channel connection failures, (2) Handover Failures - mobility issues during cell transitions, (3) HARQ Retransmissions - excessive retransmissions indicating poor radio quality, (4) CRC Errors - data corruption detection, (5) RRC Connection Failures - control plane issues, (6) Timing Advance Violations - synchronization problems, (7) Power Control Anomalies - transmit power management issues. All anomaly detection now includes packet context extraction (anomaly packet + 2 before + 2 after) stored in database for enhanced analysis.

**Enhanced Detection System (October 2025)**: The L1 anomaly detection has been significantly upgraded from simple byte-pattern matching to a sophisticated, multi-layered detection system:
  - **Protocol-Aware Analysis**: `enhanced_protocol_parser.py` extracts real packet features including MAC/IP/UDP headers, sequence numbers, timing metrics, and L1-specific indicators instead of relying on text string searches in binary data.
  - **Statistical Baseline Tracking**: `statistical_baseline_tracker.py` maintains adaptive thresholds for all anomaly types by tracking success rates, error rates, and performance metrics over time (1000-sample rolling windows). Replaces hardcoded thresholds with data-driven baselines that adapt to network conditions.
  - **Temporal Pattern Analysis**: `temporal_pattern_analyzer.py` detects time-based patterns including burst detection, degradation trends, periodic patterns, and cross-correlation between anomaly types. Uses sliding window analysis (10-second default) for event rate monitoring.
  - **Multi-Factor Confidence Scoring**: Each anomaly now has a confidence score (0.0-1.0) calculated from: (1) Pattern match strength (40%), (2) Statistical deviation from baseline (30%), (3) Temporal consistency (30%). Higher confidence scores indicate more reliable detections.
  - **Enhanced L1 Detection Methods**: All 7 anomaly types now use protocol-aware analysis with adaptive thresholds:
    - RACH: Tracks attempt/failure ratios, detects burst patterns, uses jitter analysis for timing anomalies
    - Handover: State tracking, success rate monitoring, sequence anomaly detection for out-of-order packets
    - HARQ: Consecutive retransmission tracking, rate-based detection with adaptive thresholds (default 15%)
    - CRC: Error rate calculation (per 1000 packets), burst detection, correlation with signal quality indicators
    - RRC: Connection success rate monitoring (90% threshold), state machine tracking for setup/reject patterns
    - Timing Advance: Violation rate tracking (5% threshold), jitter correlation, range validation
    - Power Control: TPC command frequency analysis, excessive adjustment detection (20% threshold), power limit tracking
  - **Cross-Correlation**: The system can detect related anomaly chains (e.g., RACH failures preceding RRC rejections indicating cell overload).
  - **Filtering & Search**: The web UI now supports advanced filtering by date range (Date From/To), description text search, and severity level with a "Clear All Filters" button.
- **AI-Powered Recommendations**: Integrates TSLAM-4B for real-time, streaming AI recommendations, with an `error_log` column and new `packet_context` column in the anomalies table providing comprehensive context for LLM analysis.
- **Real-Time Dashboard**: Displays live metrics (Total Anomalies, Sessions Analyzed, Detection Rate, Files Processed), trend analysis, anomaly type breakdowns (donut chart), severity breakdowns, and top affected sources (bar chart). **Enhanced with 3 new widgets (October 2025)**: (1) Network Health Score - circular progress indicator showing 0-100 health score with status (healthy/warning/critical) and key factors (anomaly rate, critical count, resolution rate), (2) Detection Algorithm Performance - pie chart visualizing distribution across ML algorithms (Isolation Forest, DBSCAN, One-Class SVM, LOF), (3) System Performance Metrics - cards showing files/minute throughput, average processing time, ML inference latency, and database query performance.
- **Persistent Storage**: Configured with PVC and dual volume mounts for ML models and input files, supporting deployment on Red Hat OpenShift AI. Additional volume mounts at `/app/data/logs/bouncer_logs` created during container startup for pod log collection.

### System Design Choices
The system uses a unified port architecture, with the AI inference service and web application both accessible on port 5000. Data queries are optimized to use explicit column names rather than `SELECT *` for efficiency and to prevent errors. ClickHouse datetime handling has been standardized to use Python datetime objects directly, and ML schema across all components is aligned.

## File Format Support

The system supports multiple network diagnostic file formats:

### PCAP Files (.pcap, .cap, .pcapng)
Standard packet capture files from Wireshark, tcpdump, and similar tools. Processed using Scapy for packet analysis and anomaly detection across all 7 L1 protocol types.

### QXDM/DLF Files (.dlf, .qmdl, .isf) - NEW
**Qualcomm QXDM diagnostic log files** containing detailed cellular network protocol traces from Qualcomm-based modems. The system includes:
- **DLF Parser** (`dlf_parser.py`): Reads binary DLF format, extracts diagnostic packets with 2-byte length headers, parses QXDM headers (timestamps, message IDs), and converts to standardized packet format
- **QXDM Message Decoder** (`qxdm_message_decoder.py`): Maps QXDM message IDs (0x1000-0x10FF for LTE/4G) to L1 protocol types (RACH, RRC, MAC, HARQ, Power Control, etc.)
- **Protocol-Aware Detection**: Uses QXDM message IDs for more accurate L1 indicator extraction compared to simple pattern matching
- **Unified Processing**: DLF packets flow through the same enhanced anomaly detection pipeline as PCAP files (7 L1 types, multi-factor confidence scoring, adaptive thresholds, temporal analysis)

DLF files are automatically detected by file extension and processed through the same detection methods without requiring external conversion tools.

### Text Logs (.txt, .log)
UE event logs in HDF5-converted text format for rule-based and ML-based UE attach/detach failure detection.

## External Dependencies
- **Databases**:
    - PostgreSQL
    - ClickHouse
- **AI Model**:
    - TSLAM-4B (integrated for AI recommendations)
- **Frontend Libraries**:
    - React
    - TypeScript
    - Vite
- **Backend Framework**:
    - Express.js
- **Python Libraries (for ML/Data Processing)**:
    - `clickhouse-connect`
    - `scapy`
    - `scikit-learn`
    - `pandas`
    - `numpy`
    - `joblib`