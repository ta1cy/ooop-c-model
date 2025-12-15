# C++ and Python Models for OOOP

This directory contains cycle-accurate behavioral models of the OOOP (Out-Of-Order Processor) design for debugging and verification.

## Python Model (Recommended for Quick Debugging)

### Location
`python_model/ooop_sim.py` - Complete single-file implementation

### Usage
```bash
cd python_model
python3 ooop_sim.py ../trace/25instMem-test.txt [max_cycles]
```

### Features
- ✅ Single-file, easy to modify
- ✅ Cycle-accurate execution
- ✅ All major pipeline stages (Fetch, Decode, Rename, Dispatch, Execute, Commit)
- ✅ Out-of-order execution with RS
- ✅ Register renaming (RAT + Free List)
- ✅ ROB for in-order commit
- ✅ Branch prediction and recovery (always not-taken)
- ✅ Checkpointing for precise recovery
- ✅ Load/Store unit with memory
- ✅ Final register dump (a0/a1)

### Running Tests
```bash
# Test with different traces
python3 ooop_sim.py ../trace/25instMem-test.txt 10000
python3 ooop_sim.py ../trace/25instMem-r.txt 10000
python3 ooop_sim.py ../trace/25instMem-swr.txt 10000
python3 ooop_sim.py ../trace/25instMem-jswr.txt 10000
```

### Expected Output
```
Loaded 296 bytes
Cycle 1000, Commits 70
...
============================================================
FINAL @ cycle=5000 commits=70
a0 (x10) = 0x00000000 (0)
a1 (x11) = 0x00000000 (0)
============================================================
```

### Debugging
The Python model is designed for easy debugging:
1. Add `print()` statements anywhere
2. Inspect state variables directly
3. Single-step through execution
4. Modify and rerun instantly (no compilation)

## C++ Model (In Progress)

### Location
`cpp/` - Multi-file object-oriented implementation

### Structure
```
cpp/
├── Makefile
├── include/
│   ├── types.h              # Type definitions
│   ├── core.h               # Top-level core
│   ├── fetch.h
│   ├── decode.h
│   ├── rename.h
│   ├── dispatch.h
│   ├── rs.h
│   ├── rob.h
│   ├── prf.h
│   ├── map_table.h
│   ├── free_list.h
│   ├── rob_tag_alloc.h
│   ├── alu_fu.h
│   ├── branch_fu.h
│   ├── lsu_fu.h
│   ├── icache.h
│   ├── dmem.h
│   └── recovery_ctrl.h
└── src/
    ├── main.cpp
    ├── core.cpp
    ├── (... implementations for each module ...)
    └── types.cpp
```

### Build (When Complete)
```bash
cd cpp
make
./ooop_sim ../trace/25instMem-test.txt 10000
```

### Status
- ✅ Project structure created
- ✅ Header files defined
- ✅ Type system defined
- ✅ ICache, Fetch, Decode implemented
- ✅ MapTable, FreeList, ROBTagAlloc implemented
- ✅ PRF implemented
- ⏳ Remaining modules in progress

### Completing the C++ Model

To finish the C++ implementation, complete these source files:
1. `src/dispatch.cpp` - Dispatch logic with FIFO
2. `src/rs.cpp` - Reservation station with wakeup
3. `src/rob.cpp` - Reorder buffer
4. `src/alu_fu.cpp` - ALU functional unit
5. `src/branch_fu.cpp` - Branch functional unit
6. `src/lsu_fu.cpp` - Load/Store functional unit
7. `src/dmem.cpp` - Data memory
8. `src/recovery_ctrl.cpp` - Recovery controller
9. `src/core.cpp` - Top-level integration

Each should match the corresponding Verilog module behavior exactly.

## Trace File Format

### Instruction Memory Files (`*instMem-*.txt`)
Byte-oriented hex format (little-endian):
```
37    # Byte 0
04    # Byte 1
01    # Byte 2
00    # Byte 3
# These 4 bytes form one 32-bit instruction
```

### Expected Results Files (`25*.txt`)
Disassembly with expected final register values:
```
# r-type:
    0:        123452b7        lui x5 0x12345
    ...

# a0 = 0
# a1 = 303305280
```

## Verification Strategy

1. **Python Model First**: Use for rapid prototyping and understanding
2. **Compare Against Verilog**: Run same tests, compare outputs
3. **Debug Discrepancies**: Python model is easier to inspect
4. **C++ Model**: For performance-critical verification loops

## Model Comparison

| Feature | Python | C++ | Verilog |
|---------|--------|-----|---------|
| Speed | Slow | Fast | Fastest |
| Debug | Easy | Medium | Hard |
| Modify | Instant | Recompile | Resynth |
| Visibility | Full | Good | Limited |
| Use Case | Debug | Verify | Implement |

## Common Debugging Workflow

1. Run Verilog simulation → Get wrong result
2. Run Python model with same trace
3. Compare cycle-by-cycle:
   - Pipeline contents
   - Register values
   - Memory state
4. Identify divergence point
5. Fix Verilog bug
6. Repeat

## Adding Print Statements (Python)

```python
# In Core.tick(), add after any stage:
if self.cycle == 100:  # At specific cycle
    print(f"Fetch PC: {hex(self.fetch.pc)}")
    print(f"ROB count: {self.rob_count}")
    print(f"RS ALU: {[e['rob_tag'] if e else None for e in self.rs_alu]}")
```

## License

Same as main project.
