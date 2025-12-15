#!/usr/bin/env python3
"""
Compare Verilog and Python model outputs
Helps identify where simulations diverge

Usage: python3 compare_outputs.py verilog_output.txt python_output.txt
"""

import sys
import re

def parse_output(filename):
    """Extract cycle and register values from output file"""
    results = {
        'cycles': 0,
        'commits': 0,
        'a0': 0,
        'a1': 0,
        'trace': []
    }
    
    with open(filename, 'r') as f:
        for line in f:
            # Match cycle info
            m = re.search(r'cycle[=:]?\s*(\d+)', line, re.I)
            if m:
                results['cycles'] = int(m.group(1))
            
            # Match commits
            m = re.search(r'commit[s]?[=:]?\s*(\d+)', line, re.I)
            if m:
                results['commits'] = int(m.group(1))
            
            # Match a0
            m = re.search(r'a0.*?(?:0x)?([0-9a-fA-F]+)', line, re.I)
            if m:
                results['a0'] = int(m.group(1), 16)
            
            # Match a1  
            m = re.search(r'a1.*?(?:0x)?([0-9a-fA-F]+)', line, re.I)
            if m:
                results['a1'] = int(m.group(1), 16)
            
            # Store trace lines (for cycle-by-cycle comparison)
            if 'cycle' in line.lower() or '[' in line:
                results['trace'].append(line.strip())
    
    return results

def compare_results(verilog, python):
    """Compare two result dictionaries"""
    print("="*60)
    print("COMPARISON RESULTS")
    print("="*60)
    
    # Compare final values
    print("\\nFinal Values:")
    print(f"{'Metric':<15} {'Verilog':<20} {'Python':<20} {'Match':<10}")
    print("-"*60)
    
    def cmp(name, v_val, p_val):
        match = "✅ PASS" if v_val == p_val else "❌ FAIL"
        print(f"{name:<15} {str(v_val):<20} {str(p_val):<20} {match:<10}")
        return v_val == p_val
    
    all_match = True
    all_match &= cmp("Cycles", verilog['cycles'], python['cycles'])
    all_match &= cmp("Commits", verilog['commits'], python['commits'])
    all_match &= cmp("a0 (x10)", f"0x{verilog['a0']:08x}", f"0x{python['a0']:08x}")
    all_match &= cmp("a1 (x11)", f"0x{verilog['a1']:08x}", f"0x{python['a1']:08x}")
    
    print("="*60)
    if all_match:
        print("✅ ALL TESTS PASSED - Models match!")
    else:
        print("❌ MISMATCH DETECTED - Debug needed")
        print("\\nSuggested Debug Steps:")
        print("1. Add cycle-by-cycle logging to both models")
        print("2. Find first cycle where outputs diverge")
        print("3. Inspect pipeline state at that cycle")
        print("4. Check for:")
        print("   - Wrong instruction decode")
        print("   - Incorrect register renaming")
        print("   - ROB/RS allocation bug")
        print("   - WB broadcast mismatch")
        print("   - Recovery/checkpoint error")
    print("="*60)
    
    return all_match

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <verilog_output.txt> <python_output.txt>")
        print()
        print("Example:")
        print(f"  {sys.argv[0]} verilog.log python.log")
        sys.exit(1)
    
    verilog_file = sys.argv[1]
    python_file = sys.argv[2]
    
    print(f"Loading Verilog output: {verilog_file}")
    verilog = parse_output(verilog_file)
    
    print(f"Loading Python output:  {python_file}")
    python = parse_output(python_file)
    
    print()
    compare_results(verilog, python)
