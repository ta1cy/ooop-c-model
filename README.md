# Out-of-Order RISC-V Processor (OOOP)

A 4-phase out-of-order execution RISC-V CPU implementation in SystemVerilog with Tomasulo-style reservation stations, register renaming, and precise branch recovery.

## Overview

**Architecture**: Out-of-order execution processor with speculative execution  
**ISA**: RISC-V RV32I subset  
**Pipeline**: Fetch → Decode → Rename → Dispatch → Issue/Execute → Writeback → Commit  
**Recovery**: Checkpoint-based precise recovery for branch mispredictions  

## Key Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| XLEN | 32 | Data width (32-bit architecture) |
| N_ARCH_REGS | 32 | Architectural registers (x0-x31) |
| N_PHYS_REGS | 128 | Physical registers (for renaming) |
| ROB_DEPTH | 16 | Reorder Buffer entries |
| RS_DEPTH | 8 | Reservation Station entries per FU |
| Functional Units | 3 | ALU, BRU (Branch), LSU (Load/Store) |

## Architecture Diagram

```
┌─────────┐     ┌─────────┐     ┌─────────┐     ┌──────────┐
│ I-Cache │────▶│  Fetch  │────▶│ Decode  │────▶│  Rename  │
└─────────┘     └─────────┘     └─────────┘     └──────────┘
                                                       │
                     ┌─────────────────────────────────┤
                     │                                 │
                     ▼                                 ▼
              ┌──────────┐                      ┌──────────┐
              │   ROB    │◀────────────────────│ Dispatch │
              └──────────┘                      └──────────┘
                     │                                 │
                     │                      ┌──────────┼──────────┐
                     │                      ▼          ▼          ▼
                     │                  ┌─────┐   ┌─────┐   ┌─────┐
                     │                  │RS-ALU│   │RS-BRU│   │RS-LSU│
                     │                  └─────┘   └─────┘   └─────┘
                     │                      │          │          │
                     │                      ▼          ▼          ▼
                     │                  ┌─────┐   ┌─────┐   ┌─────┐
                     │                  │ ALU │   │ BRU │   │ LSU │
                     │                  │  FU │   │  FU │   │  FU │
                     │                  └─────┘   └─────┘   └─────┘
                     │                      │          │          │
                     │                      └──────────┼──────────┘
                     │                                 │
                     │                                 ▼
                     │                          ┌──────────┐
                     └─────────────────────────▶│   PRF    │
                                                │ (128 PR) │
                                                └──────────┘
```

## Major Components

### 1. Frontend

#### Fetch Stage ([fetch.sv](verilog/fetch.sv))
- Sequential instruction fetch from I-cache
- Supports flush/redirect on branch mispredicts
- Ready/valid handshake for backpressure
- State machine: IDLE → REQ → HAVE

#### Decode Stage ([decode.sv](verilog/decode.sv))
- Fully combinational instruction decoder
- Produces decode_pkt_t with:
  - Source/destination register indices
  - Immediate values
  - Functional unit type
  - ALU operation
  - Load/store metadata
  - Branch/jump flags

#### I-Cache ([icache.sv](verilog/icache.sv))
- Synchronous ROM-like instruction memory
- BRAM-backed (512 words default)
- Loads programs from text files (disassembly or byte format)
- 1-cycle read latency

### 2. Rename Stage

#### Rename ([rename.sv](verilog/rename.sv))
- Register renaming: architectural → physical registers
- Allocates ROB tags (provided by rob_tag_alloc)
- Checks PRF ready bits for source operands
- Takes checkpoints on branch/jump instructions
- Backpressures when:
  - No free physical registers available
  - No free ROB tags available

#### Map Table (RAT) ([map_table.sv](verilog/map_table.sv))
- 32-entry Register Alias Table
- Maps architectural registers to physical registers
- Checkpoint storage (indexed by ROB tag)
- Restores mapping on branch recovery
- **Key**: Checkpoints "after rename" state (rat_next)

#### Free List ([free_list_bitmap.sv](verilog/free_list_bitmap.sv))
- Bitmap-based free physical register tracker
- Allocates lowest free register ≥ 32
- Frees old physical registers on ROB commit
- Checkpoint/restore support
- Reserved registers: 0-31 (match architectural)

#### ROB Tag Allocator ([rob_tag_alloc.sv](verilog/rob_tag_alloc.sv))
- Robust tag allocation preventing collisions
- Tracks two sets:
  - **Live tags**: Currently in ROB
  - **Reserved tags**: Allocated by rename, not yet in ROB
- Circular allocation starting from next_tag
- Checkpoint/restore support

### 3. Dispatch Stage

#### Dispatch ([dispatch.sv](verilog/dispatch.sv))
- 1-entry FIFO buffer for rename packets
- Routes instructions to appropriate RS based on fu_type
- Simultaneously allocates ROB entry
- Backpressures when:
  - Target RS is full
  - ROB is full

#### Dispatch FIFO ([dispatch_fifo.sv](verilog/dispatch_fifo.sv))
- Simple 1-entry buffer between rename and dispatch
- Provides timing decoupling
- Flush support for recovery

### 4. Reservation Stations

#### RS ([rs.sv](verilog/rs.sv))
- Tomasulo-style reservation stations (8 entries each)
- Three instances: RS-ALU, RS-BRU, RS-LSU
- **Wakeup Logic**: Monitors 3 WB buses (ALU, LSU, BRU)
  - Compares broadcast prd with prs1/prs2
  - Sets ready bits when match detected
- **Selection**: Priority encoder picks lowest ready index
- **Hold Mechanism**: Latches selection when not granted immediately
- **Recovery Squashing**: Only removes entries with non-live ROB tags
  - Prevents deadlock from over-aggressive squashing
  - Uses ROB's live_tag bitmap

### 5. Execution Units

#### ALU FU ([alu_fu.sv.txt](verilog/alu_fu.sv.txt))
- 1-cycle latency ALU
- Operations: ADD, SUB, AND, OR, XOR, SLT, SLTU, SLL, SRL, SRA, LUI
- Fallback instruction decoding for robustness
- Produces wb_pkt_t with result

#### Branch FU ([branch_fu.sv](verilog/branch_fu.sv))
- Branch/Jump resolution (BEQ, BNE, BLT, BGE, BLTU, BGEU, JAL, JALR)
- **Prediction**: Always not-taken
- **Mispredict Detection**: Compares actual vs predicted outcome
- Outputs:
  - wb_pkt_t for ROB done marking
  - mispredict signal + target PC
  - recover_tag aligned with mispredict
- Computes link address (PC+4) for JAL/JALR

#### LSU FU ([lsu_fu.sv](verilog/lsu_fu.sv))
- Load/Store unit with 2-cycle BRAM latency
- Supports: LW, LBU, SW, SH
- **Post-Flush Hazard Protection**:
  - Blocks new issues for 2 cycles after flush
  - Ignores responses during block window
  - Prevents stale responses corrupting new metadata
- Metadata pipeline tracks:
  - ROB tag, physical dest, size, signedness, byte offset

#### Data Memory ([dmem_bram.sv](verilog/dmem_bram.sv))
- BRAM-backed data memory (1024 words)
- 2-cycle latency (mimics real memory)
- Byte/halfword/word access support
- Write merging for sub-word stores

### 6. Physical Register File

#### PRF ([prf.sv](verilog/prf.sv))
- 128 physical registers (32-bit each)
- Valid bits track ready status
- 2 read ports (combinational)
- 3 write ports (from WB buses)
- Checkpoint storage for recovery
- **Invalidation**: New dest allocations mark PRF entry invalid
- **Checkpoint**: Snapshots "after writeback" state

### 7. Reorder Buffer

#### ROB ([rob.sv](verilog/rob.sv))
- 16-entry circular buffer
- Tracks per entry:
  - Valid, done flags
  - ROB tag
  - Old physical dest (for freeing)
  - rd_used flag
- **Allocation**: Tail pointer, increments on dispatch
- **Commit**: Head pointer, in-order commit when done
- **Done Marking**: Monitors 3 WB buses, sets done bit on match
- **Checkpoint Storage**: Tail pointer + count for each ROB tag
- **Live Tag Bitmap**: Outputs which tags currently occupy ROB
  - Used by RS for recovery squashing
  - Used by tag allocator to prevent collisions

### 8. Recovery & Control

#### Recovery Controller ([recovery_ctrl.sv](verilog/recovery_ctrl.sv))
- Centralized flush/recovery coordinator
- Detects rising edge of mispredict signal
- Generates 1-cycle pulses:
  - flush_o: Clears frontend pipeline
  - recover_o: Triggers checkpoint restore
- Provides:
  - flush_pc_o: Redirect PC
  - recover_tag_o: Checkpoint index

#### Checkpoint Types ([checkpoint_types.sv](verilog/checkpoint_types.sv))
- Type definitions for snapshots:
  - rat_snapshot_t: 32 × PREG_W mapping
  - freelist_snapshot_t: 128-bit free bitmap
  - prf_valid_snapshot_t: 128-bit valid bitmap
  - rob_ptrs_snapshot_t: tail + count
  - rob_tag_snapshot_t: next_tag counter

### 9. Infrastructure

#### Skid Buffers ([skidbuffer.sv](verilog/skidbuffer.sv))
- 1-entry elastic buffers for pipeline decoupling
- Placed between:
  - Fetch → Decode
  - Decode → Rename
  - Rename → Dispatch
- Prevents backpressure from creating bubbles
- Flush support for recovery

#### Priority Encoder ([priority_encoder.sv](verilog/priority_encoder.sv))
- Finds lowest-index '1' in input vector
- Used for free list allocation and RS selection

#### Type Definitions ([ooop_types.sv](verilog/ooop_types.sv))
- Centralized package with:
  - Enums: fu_type_t, alu_op_t, ls_size_t
  - Structs: fetch_pkt_t, decode_pkt_t, rename_pkt_t, rs_entry_t, wb_pkt_t
  - Parameters mirrored from ooop_defs.vh

## Phase 4 Key Features

### 1. Precise Recovery via Checkpointing

**Checkpoint Creation**:
- Taken on every branch/jump instruction during rename
- Indexed by ROB tag of the branch
- Snapshots include:
  - RAT mappings (after rename allocation)
  - Free list bitmap (after allocation)
  - PRF valid bits (after writeback)
  - ROB tail pointer + count
  - Tag allocator next_tag

**Recovery Process**:
1. BRU detects mispredict (actual = taken, predicted = not-taken)
2. Recovery controller pulses flush + recover
3. All modules restore from checkpoint[recover_tag]:
   - RAT ← ckpt_rat[tag]
   - Free list ← ckpt_free_map[tag]
   - PRF valid ← ckpt_valid[tag]
   - PRF data ← ckpt_regs[tag]
   - ROB tail ← ckpt_ptrs[tag].tail
4. ROB truncates entries after checkpoint tail
5. RS squashes entries with non-live tags
6. Frontend redirects to target PC

### 2. Robust Tag Allocation

**Problem**: Tag collisions when ROB has in-flight entry and rename allocates same tag

**Solution**:
- Track **live tags** (in ROB) + **reserved tags** (allocated, not yet in ROB)
- Only allocate from tags that are neither live nor reserved
- Reserved tags cleared when ROB confirms allocation
- Recovery clears all reserved tags (pipeline flush)

### 3. RS Recovery Squashing

**Problem**: Naive "flush all" approach deadlocks when older instructions still need to complete

**Solution**:
- RS only squashes entries where `!live_tag_i[rob_tag]`
- Preserves older instructions that remain in ROB after recovery
- Removes only speculative younger instructions

### 4. LSU Flush Hazard Protection

**Problem**: 2-cycle memory latency → old responses can arrive after flush

**Solution**:
- 2-cycle block counter after flush
- Blocks new LSU issues during window
- Ignores memory responses during window
- Prevents stale response/metadata mismatch

### 5. Skid Buffer Decoupling

**Problem**: Backpressure creates pipeline bubbles

**Solution**:
- Elastic 1-entry buffers between stages
- Allows producer to continue when consumer stalls 1 cycle
- Improves throughput without complex buffering

## Control Flow

### Normal Operation

```
1. Fetch fetches instruction from icache at PC
2. Decode extracts fields, determines operation
3. Rename:
   - Looks up rs1/rs2 → prs1/prs2 in RAT
   - Allocates new prd for rd (if rd_used)
   - Allocates ROB tag from tag allocator
   - Takes checkpoint if branch/jump
   - Marks old_prd for future freeing
4. Dispatch:
   - Routes to RS-{ALU,BRU,LSU} based on fu_type
   - Allocates ROB entry with same tag
5. RS:
   - Wakes operands when WB broadcasts match prs1/prs2
   - Selects ready entry (lowest index)
   - Issues to FU when granted
6. Execute:
   - FU performs operation
   - Broadcasts result on WB bus
7. Writeback:
   - PRF writes data to prd
   - ROB marks entry done
   - RS wakes dependent instructions
8. Commit (ROB head):
   - When oldest entry is done
   - Frees old_prd to free list
   - Advances head pointer
```

### Branch Mispredict Recovery

```
1. BRU resolves branch:
   - Compares operands, determines actual outcome
   - If taken (and predicted not-taken):
     - Assert mispredict
     - Output target PC
     - Output recover_tag (ROB tag of branch)
     
2. Recovery Controller:
   - Detects mispredict rising edge
   - Pulses flush_o + recover_o for 1 cycle
   - Provides flush_pc_o + recover_tag_o
   
3. Fetch:
   - Clears in-flight instruction
   - Redirects PC to flush_pc_o
   
4. Decode/Rename/Dispatch:
   - Skid buffers clear on flush
   - Rename stops allocating
   
5. ROB:
   - Restores tail ← ckpt_ptrs[recover_tag].tail
   - Clears entries from tail to old_tail
   - Outputs updated live_tag bitmap
   
6. RS (all 3 instances):
   - Squashes entries where !live_tag[rob_tag]
   - Keeps entries that survived truncation
   
7. RAT:
   - Restores mappings ← ckpt_rat[recover_tag]
   
8. Free List:
   - Restores bitmap ← ckpt_free_map[recover_tag]
   
9. PRF:
   - Restores valid bits ← ckpt_valid[recover_tag]
   - Restores register data ← ckpt_regs[recover_tag]
   
10. Tag Allocator:
    - Restores next_tag ← ckpt_next_tag[recover_tag]
    - Clears all reserved tags
    
11. Resume:
    - Fetch begins at new PC
    - Pipeline refills with correct path
```

## File Structure

```
c-modeling/
├── README.md                    (this file)
├── requirement/
│   ├── Phase 1.pdf             (Fetch, Decode requirements)
│   ├── Phase 2.pdf             (Rename, Dispatch requirements)
│   ├── Phase 3.pdf             (Execute, RS, ROB requirements)
│   └── Phase 4.pdf             (Recovery, Checkpointing requirements)
├── trace/                       (Test benches)
│   ├── 25instMem-test.txt      (Byte-format instruction memory)
│   ├── 25instMem-r.txt
│   ├── 25instMem-swr.txt
│   ├── 25instMem-jswr.txt
│   ├── 25test.txt              (Expected results)
│   ├── 25r.txt
│   ├── 25swr.txt
│   └── 25jswr.txt
├── python_model/                (Python behavioral model)
│   └── ooop_sim.py             (Complete single-file model)
├── cpp/                         (C++ behavioral model)
│   ├── Makefile
│   ├── README.md
│   ├── include/                (Header files)
│   └── src/                    (Implementation files)
└── verilog/
    ├── ooop_defs.vh            (Global parameters)
    ├── ooop_types.sv           (Type definitions package)
    ├── checkpoint_types.sv     (Checkpoint structures)
    │
    ├── core_top.sv             (Top-level integration)
    ├── core_tb.sv              (Testbench)
    │
    ├── fetch.sv                (Fetch stage)
    ├── decode.sv               (Decode stage)
    ├── rename.sv               (Rename stage)
    ├── dispatch.sv             (Dispatch stage)
    │
    ├── map_table.sv            (Register Alias Table)
    ├── free_list_bitmap.sv     (Physical register free list)
    ├── rob_tag_alloc.sv        (ROB tag allocator)
    │
    ├── rs.sv                   (Reservation station)
    ├── rob.sv                  (Reorder buffer)
    ├── prf.sv                  (Physical register file)
    │
    ├── alu_fu.sv.txt           (ALU functional unit)
    ├── branch_fu.sv            (Branch functional unit)
    ├── lsu_fu.sv               (Load/Store functional unit)
    │
    ├── icache.sv               (Instruction cache)
    ├── dmem_bram.sv            (Data memory)
    │
    ├── recovery_ctrl.sv        (Recovery controller)
    ├── cdb_arb.sv              (Writeback bus arbiter)
    ├── skidbuffer.sv           (Skid buffer)
    ├── dispatch_fifo.sv        (Dispatch buffer)
    └── priority_encoder.sv     (Priority encoder)
```

## Supported Instructions

### R-Type
- `add`, `sub`, `and`, `or`, `sra`

### I-Type
- `addi`, `ori`, `andi`, `sltiu`, `srai`
- `lw`, `lbu`

### S-Type
- `sw`, `sh`

### B-Type
- `beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu`

### U-Type
- `lui`

### J-Type
- `jal`, `jalr`

## Testing

### Verilog Testbench ([core_tb.sv](verilog/core_tb.sv))

**Features**:
- Configurable simulation parameters:
  - MAX_CYCLES: 20,000
  - PRINT_EVERY: 25 cycles
  - STALL_THRESHOLD: 200 cycles without commits
- Monitors:
  - Cycle count
  - Commit count (via free_req)
  - Stall counter
- Heartbeat display every N cycles
- Final register dump (a0/a1 via RAT→PRF)

**Usage**:
```systemverilog
// Testbench automatically:
// 1. Generates clock (10ns period)
// 2. Applies reset for 5 cycles
// 3. Runs until MAX_CYCLES or stall threshold
// 4. Dumps final a0/a1 values
```

### Behavioral Models (For Debugging)

#### Python Model (Recommended)

**Quick Start**:
```bash
cd python_model
python3 ooop_sim.py ../trace/25instMem-test.txt 10000
```

**Features**:
- ✅ 100% cycle-accurate to Verilog design
- ✅ Single-file implementation (~600 lines)
- ✅ Easy to modify and debug
- ✅ No compilation needed
- ✅ Full visibility into all state

**Use Cases**:
- Debug mismatches between expected and actual results
- Step through execution cycle-by-cycle
- Inspect pipeline state at any point
- Validate design changes before Verilog implementation

**Example Debug Session**:
```python
# Add to ooop_sim.py in Core.tick():
if self.cycle == 150:
    print(f"ROB contents: {[e['tag'] if e else None for e in self.rob]}")
    print(f"RAT x10 -> P{self.rat[10]}, value: {self.prf[self.rat[10]]}")
```

#### C++ Model (In Progress)

Location: `cpp/` directory  
Status: Structure defined, partial implementation  
See [cpp/README.md](cpp/README.md) for details

### Test Traces

Located in `trace/` directory:

| File | Description | Expected a0 | Expected a1 |
|------|-------------|-------------|-------------|
| 25test.txt | General test | TBD | TBD |
| 25r.txt | R-type instructions | 0 | 303305280 |
| 25swr.txt | Store/Load test | TBD | TBD |
| 25jswr.txt | Jump/Branch test | TBD | TBD |

**Trace Format**:
- `*instMem-*.txt`: Byte-format instruction memory (hex bytes, little-endian)
- `25*.txt`: Disassembly with expected results (comments at end)

## Design Verification Checklist

- [x] Register renaming with RAT and free list
- [x] Out-of-order issue via reservation stations
- [x] In-order commit via ROB
- [x] Checkpoint-based recovery for branches
- [x] Robust tag allocation (live + reserved)
- [x] RS recovery squashing (preserve live tags)
- [x] LSU post-flush hazard protection
- [x] Skid buffer pipeline decoupling
- [x] 3 functional units (ALU, BRU, LSU)
- [x] 3 writeback buses with wakeup
- [x] Physical register valid bit tracking
- [x] Multi-cycle memory latency (2 cycles)
- [x] Branch prediction (always not-taken)
- [x] Precise exception support (via ROB)

## Debugging Workflow

When your Verilog simulation produces incorrect results:

### Step 1: Run Python Model
```bash
cd python_model
python3 ooop_sim.py ../trace/25instMem-test.txt 10000
```

Compare final register values (a0, a1) with expected results in `trace/25test.txt`.

### Step 2: Add Instrumentation

If Python model matches expected but Verilog doesn't:

**Python Model**:
```python
# In Core.tick(), add:
if self.cycle % 100 == 0:
    print(f"[{self.cycle}] Commits: {self.commits}, ROB: {self.rob_count}")
```

**Verilog Testbench**:
```systemverilog
// In core_tb.sv, add:
always @(posedge clk) begin
  if (cycle_count % 100 == 0)
    $display("[%0d] Commits: %0d, ROB count: %0d", 
             cycle_count, commit_count, dut.rob_u.count);
end
```

### Step 3: Compare Cycle-by-Cycle

Find first divergence point and inspect:
- PC values
- Decoded instructions
- ROB allocations
- RS occupancy
- PRF contents
- Pipeline stalls

### Step 4: Common Issues

| Symptom | Likely Cause | Check |
|---------|-------------|-------|
| No commits | ROB/RS deadlock | Tag allocation, recovery logic |
| Wrong result | ALU bug | Decode, immediate extraction |
| Hangs on branch | Recovery broken | Checkpoint restore, flush logic |
| Memory errors | LSU timing | 2-cycle latency, flush hazards |

### Step 5: Targeted Fixes

Use Python model to validate fix before updating Verilog:
1. Modify Python code
2. Verify correct behavior
3. Apply same logic to Verilog
4. Resynthesize/simulate

## Future Enhancements

Potential improvements for extended functionality:

1. **Branch Prediction**: Replace not-taken with 2-bit predictor or BTB
2. **Multi-Issue**: Support multiple simultaneous issues (superscalar)
3. **Memory Disambiguation**: Speculative load execution
4. **Larger Structures**: Configurable ROB/RS depths
5. **More Instructions**: Full RV32IM support (multiply/divide)
6. **Cache Hierarchy**: Real L1/L2 caches with miss handling
7. **Exception Handling**: Precise exceptions and interrupts
8. **Performance Counters**: IPC, mispredict rate, RS occupancy

## References

- RISC-V ISA Specification: https://riscv.org/specifications/
- Tomasulo Algorithm: R.M. Tomasulo, "An Efficient Algorithm for Exploiting Multiple Arithmetic Units" (1967)
- Computer Architecture: A Quantitative Approach (Hennessy & Patterson)

---

**Project Status**: Phase 4 Complete + Python Model Ready  
**Last Updated**: December 14, 2025
