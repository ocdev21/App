#!/bin/bash
# Startup script for superapp that handles sqlite3 version issue
# This overrides the old built-in sqlite3 with the newer pysqlite3-binary

python3 - <<'PYTHON_SCRIPT'
# Override old sqlite3 with newer pysqlite3
import sys
try:
    __import__('pysqlite3')
    sys.modules['sqlite3'] = sys.modules.pop('pysqlite3')
    print("✓ Successfully overridden sqlite3 with pysqlite3")
except ImportError:
    print(" pysqlite3 not found, using built-in sqlite3")
PYTHON_SCRIPT

# Now run the actual application
exec python3 crew_code37.py
