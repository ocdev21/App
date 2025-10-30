#!/usr/bin/env python3
"""
ESApp - Energy Application
Continuous background task running on ECS Fargate
"""

import time
from datetime import datetime

def main():
    """Main entry point for esapp"""
    print("=" * 50)
    print("ESApp - Energy Application")
    print("=" * 50)
    print(f"Started at: {datetime.now().isoformat()}")
    print("")
    
    iteration = 0
    while True:
        iteration += 1
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ESApp iteration {iteration}")
        time.sleep(30)  # Run every 30 seconds

if __name__ == "__main__":
    main()
