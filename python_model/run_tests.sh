#!/bin/bash

# Test script for OOOP Python Model
# Runs all test traces and reports results

echo "========================================"
echo "OOOP Python Model Test Suite"
echo "========================================"
echo ""

cd "$(dirname "$0")"

TRACES=(
    "../trace/25instMem-test.txt"
    "../trace/25instMem-r.txt"
    "../trace/25instMem-swr.txt"
    "../trace/25instMem-jswr.txt"
)

NAMES=(
    "General Test"
    "R-Type Test"
    "Store/Write Test"
    "Jump/Store/Write Test"
)

MAX_CYCLES=10000

for i in "${!TRACES[@]}"; do
    trace="${TRACES[$i]}"
    name="${NAMES[$i]}"
    
    echo "----------------------------------------"
    echo "Test $((i+1)): $name"
    echo "File: $trace"
    echo "----------------------------------------"
    
    if [ ! -f "$trace" ]; then
        echo "ERROR: Trace file not found!"
        echo ""
        continue
    fi
    
    python3 ooop_sim.py "$trace" "$MAX_CYCLES" 2>&1 | tail -n 10
    echo ""
done

echo "========================================"
echo "Test Suite Complete"
echo "========================================"
