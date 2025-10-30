#!/usr/bin/env python3
"""
TSApp - Timestream Application
Continuous background task running on ECS Fargate
"""

import time
from datetime import datetime

def main():
    """Main entry point for tsapp"""
    print("=" * 50)
    print("TSApp - Timestream Application")
    print("=" * 50)
    print(f"Started at: {datetime.now().isoformat()}")
    print("")
    
    iteration = 0
    while True:
        iteration += 1
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] TSApp iteration {iteration}")
        time.sleep(30)  # Run every 30 seconds

if __name__ == "__main__":
    main()
