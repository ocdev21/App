
# L1 Troubleshooting System

## Overview

This is a comprehensive L1 Network Troubleshooting System with AI-powered anomaly detection and real-time streaming recommendations.

## Features

- **Advanced Anomaly Detection**: Fronthaul Analysis, UE Event Processing, MAC Layer Analysis
- **AI-Powered Recommendations**: TSLAM-4B Integration with streaming responses
- **Real-Time Dashboard**: Live metrics and trend analysis
- **Dual Database Support**: PostgreSQL and ClickHouse integration

## Getting Started

```bash
npm install
pip install -r requirements_mistral.txt
npm run dev
```

Access the application at http://0.0.0.0:5000

## Architecture

- **Frontend**: React + TypeScript + Vite
- **Backend**: Express.js with WebSocket support
- **AI**: TSLAM-4B model integration
- **Database**: PostgreSQL + ClickHouse analytics

## Recent Changes

- **AI Service & Dashboard Enhancements (Oct 8, 2025)**: Unified port architecture and enhanced dashboard visualization
  - **Port Consolidation**: AI inference service now uses port 5000 (unified with webapp)
  - **Rule-Based Fallback**: Comprehensive fallback recommendations for all anomaly types when AI service unavailable
    - Fronthaul: Physical connections, signal quality, timing sync, configuration checks
    - UE Events: Authentication, radio conditions, core network verification
    - MAC Address: Duplicate detection, VLAN config, security assessment
    - Protocol: Packet analysis, version compatibility, standards compliance
  - **Dashboard Improvements**: All endpoints now work without ClickHouse dependency
    - Metrics, trends, and breakdown endpoints use MemStorage fallback
    - Fixed Anomaly Trends chart: displays 7-day trend data with enhanced formatting
    - Redesigned Anomaly Types chart: professional donut chart with color-coded legend
    - Shows type name, count, and percentage for each anomaly category
- **UI Simplification & Real Data Integration (Oct 8, 2025)**: Streamlined interface with clean, focused design and live database metrics
  - **Removed Dark Mode**: Eliminated ThemeContext, dark mode toggle, and all dark: variant classes for consistent light theme
  - **Dashboard Cleanup**: Removed time-range filter buttons (1h, 24h, 7d, 30d) for simplified metrics view
  - **Real-Time Dashboard Metrics**: Connected all metric cards to live database data
    - Total Anomalies, Sessions Analyzed, Detection Rate, Files Processed now pull from ClickHouse/DB
    - Week-over-week percentage changes calculated from real historical data (7-day comparison)
    - When ClickHouse available: Real calculations; When unavailable: MemStorage fallback
  - **Anomalies Table Redesign**: Complete redesign matching DataTables reference design
    - Clean table with 6 columns: Timestamp, Type, Description, Severity, Source, Actions
    - "Display X results" dropdown (10/25/50/100 options) on left
    - "Search:" input field on right
    - Sortable column headers (click to sort, no visual arrows)
    - Plain text cells (removed badge styling)
    - Alternating row colors (white/gray-50)
    - Simple pagination showing "Showing X to Y of Z entries"
    - Actions column with Get Recommendations (blue) and Details (white) buttons
    - Get Recommendations opens RecommendationsPopup for AI-powered streaming suggestions
    - Details opens ExplainableAIModal showing SHAP-based anomaly explanations
    - Removed: Sort arrows, Sort by controls, bulk actions, checkboxes, type/severity filters
- **ClickHouse DateTime Fix (Oct 7, 2025)**: Fixed datetime serialization errors in ML anomaly insertion
  - Removed strftime() conversions in anomaly timestamp, session start_time, and end_time
  - Now uses Python datetime objects directly for ClickHouse DateTime columns
  - Eliminates AttributeError: 'str' object has no attribute 'timestamp' errors
  - Verified all ClickHouse insert operations use correct datetime handling
- **ClickHouse Schema Alignment (Oct 7, 2025)**: Unified ML schema across all components
  - Fixed server/storage.ts, server/services/clickhouse_client.py to use ML column names
  - Updated anomalies table: anomaly_type, file_path, du_mac, ru_mac (instead of type, source_file, mac_address)
  - Aligned Python ClickHouse client table creation with ML insert schema
- **ML Sensitivity Tuning (Oct 7, 2025)**: Enhanced anomaly detection with 4 major improvements:
  - Lowered contamination threshold from 0.1 to 0.05 for 2x more sensitive detection
  - Added time-series features: inter-arrival std deviation, true response time calculation, packet rate
  - Changed voting threshold from 2/4 to 1/4 algorithms (single algorithm flag = anomaly)
  - Added statistical baselines: mean and std deviation for packet timing and sizes
  - Upgraded from 12D to 16D feature vectors for better accuracy
- **ML Analysis Fixes (Oct 3, 2025)**: Fixed folder_anomaly_analyzer_clickhouse.py to correctly use UEEventAnalyzer methods and ClickHouse insert format
- **Python Dependencies (Oct 3, 2025)**: Added complete ML dependencies to Dockerfile (clickhouse-connect, scapy, scikit-learn, pandas, numpy, joblib)
- **Emoji Cleanup (Sept 26, 2025)**: Removed all emojis and visual icons from print statements, logs, and output throughout the entire project for clean, professional output
- **Persistent Storage**: Implemented complete PVC configuration with dual volume mounts for ML models and input files
- **OpenShift AI Integration**: Enhanced deployment for Red Hat OpenShift AI platform with namespace l1-app-ai
