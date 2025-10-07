
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
