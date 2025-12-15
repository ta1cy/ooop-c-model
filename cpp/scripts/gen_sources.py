#!/usr/bin/env python3
"""
Generator script for OOOP C++ Model source files
Creates all remaining .cpp implementation files
"""

import os

# Base directory
base_dir = "."
src_dir = os.path.join(base_dir, "src")

# Ensure src directory exists
os.makedirs(src_dir, exist_ok=True)

# File templates
templates = {
    "rob_tag_alloc.cpp": """#include "rob_tag_alloc.h"

ROBTagAlloc::ROBTagAlloc() : next_tag(0), alloc_ok_q(false), tag_q(0) {
    reset();
}

void ROBTagAlloc::reset() {
    next_tag = 0;
    reserved.reset();
    for (int i = 0; i < ROB_DEPTH; i++) {
        ckpt_next_tag[i] = 0;
    }
}

void ROBTagAlloc::tick(bool flush, bool recover, rob_tag_t recover_tag,
                       bool alloc_req, const std::bitset<ROB_DEPTH>& live_tag,
                       bool rob_alloc_fire, rob_tag_t rob_alloc_tag,
                       bool checkpoint_take, rob_tag_t checkpoint_tag) {
    if (flush) {
        reserved.reset();
        return;
    }
    
    if (recover) {
        next_tag = ckpt_next_tag[recover_tag];
        reserved.reset();
        return;
    }
    
    // Clear reserved when ROB confirms allocation
    if (rob_alloc_fire) {
        reserved.reset(rob_alloc_tag);
    }
    
    // Find free tag
    std::bitset<ROB_DEPTH> used = live_tag | reserved;
    rob_tag_t free_tag = findFreeTag(used);
    bool found = (free_tag < ROB_DEPTH) && !used.test(free_tag);
    
    alloc_ok_q = found;
    tag_q = free_tag;
    
    // Allocate if requested
    if (alloc_req && found) {
        reserved.set(free_tag);
        next_tag = (free_tag + 1) & (ROB_DEPTH - 1);
    }
    
    // Checkpoint
    if (checkpoint_take) {
        rob_tag_t next_tag_after = (free_tag + 1) & (ROB_DEPTH - 1);
        if (alloc_req && found) {
            ckpt_next_tag[checkpoint_tag] = next_tag_after;
        } else {
            ckpt_next_tag[checkpoint_tag] = next_tag;
        }
    }
}

bool ROBTagAlloc::getAllocOk() const {
    return alloc_ok_q;
}

rob_tag_t ROBTagAlloc::getTag() const {
    return tag_q;
}

rob_tag_t ROBTagAlloc::findFreeTag(const std::bitset<ROB_DEPTH>& used) const {
    for (int k = 0; k < ROB_DEPTH; k++) {
        rob_tag_t cand = (next_tag + k) & (ROB_DEPTH - 1);
        if (!used.test(cand)) {
            return cand;
        }
    }
    return next_tag;
}
""",

    "rename.cpp": """#include "rename.h"

Rename::Rename(MapTable* mt, FreeList* fl) : map_table(mt), free_list(fl) {}

RenamePkt Rename::rename(const DecodePkt& pkt_in, bool valid_in,
                        const std::bitset<N_PHYS_REGS>& prf_valid,
                        bool tag_ok, rob_tag_t rob_tag,
                        bool ready_in) {
    RenamePkt pkt = {};
    
    if (!valid_in) {
        return pkt;
    }
    
    // Check if need dest allocation
    bool need_alloc = pkt_in.rd_used && (pkt_in.rd != 0);
    bool has_free = free_list->hasFree();
    
    // Can proceed?
    bool alloc_ok = (!need_alloc) || has_free;
    bool can_proceed = alloc_ok && tag_ok;
    
    pkt.valid = can_proceed;
    pkt.pc = pkt_in.pc;
    pkt.instr = pkt_in.instr;
    pkt.rs1 = pkt_in.rs1;
    pkt.rs2 = pkt_in.rs2;
    pkt.rd = pkt_in.rd;
    pkt.imm = pkt_in.imm;
    pkt.imm_used = pkt_in.imm_used;
    pkt.fu_type = pkt_in.fu_type;
    pkt.alu_op = pkt_in.alu_op;
    pkt.rd_used = need_alloc;
    pkt.is_load = pkt_in.is_load;
    pkt.is_store = pkt_in.is_store;
    pkt.ls_size = pkt_in.ls_size;
    pkt.unsigned_load = pkt_in.unsigned_load;
    pkt.is_branch = pkt_in.is_branch;
    pkt.is_jump = pkt_in.is_jump;
    
    // Rename sources
    pkt.prs1 = map_table->lookupRS1(pkt_in.rs1);
    pkt.prs2 = map_table->lookupRS2(pkt_in.rs2);
    
    // Check ready
    auto preg_ready = [&](preg_t p) {
        return (p == 0) || prf_valid.test(p);
    };
    pkt.prs1_ready = preg_ready(pkt.prs1);
    pkt.prs2_ready = preg_ready(pkt.prs2);
    
    // Rename dest
    if (need_alloc) {
        pkt.prd = free_list->getAllocPreg();
        pkt.old_prd = map_table->lookupRDOld(pkt_in.rd);
    } else {
        pkt.prd = 0;
        pkt.old_prd = 0;
    }
    
    pkt.rob_tag = rob_tag;
    
    return pkt;
}

bool Rename::getReadyOut(const DecodePkt& pkt_in, bool has_free, bool tag_ok, bool ready_in) const {
    bool need_alloc = pkt_in.rd_used && (pkt_in.rd != 0);
    bool alloc_ok = (!need_alloc) || has_free;
    return ready_in && alloc_ok && tag_ok;
}

bool Rename::getValidOut(const DecodePkt& pkt_in, bool valid_in, bool has_free, bool tag_ok) const {
    bool need_alloc = pkt_in.rd_used && (pkt_in.rd != 0);
    bool alloc_ok = (!need_alloc) || has_free;
    return valid_in && alloc_ok && tag_ok;
}

bool Rename::getAllocReq(const DecodePkt& pkt_in, bool fire) const {
    bool need_alloc = pkt_in.rd_used && (pkt_in.rd != 0);
    return fire && need_alloc;
}

bool Rename::getCheckpointTake(const DecodePkt& pkt_in, bool fire) const {
    return fire && (pkt_in.is_branch || pkt_in.is_jump);
}
""",
}

# Write files
for filename, content in templates.items():
    filepath = os.path.join(src_dir, filename)
    print(f"Creating {filepath}...")
    with open(filepath, 'w') as f:
        f.write(content)

print("\\nGeneration complete!")
print("Remaining files need manual implementation:")
print("  - dispatch.cpp")
print("  - rs.cpp")
print("  - rob.cpp")
print("  - prf.cpp")
print("  - alu_fu.cpp")
print("  - branch_fu.cpp")
print("  - lsu_fu.cpp")
print("  - dmem.cpp")
print("  - recovery_ctrl.cpp")
print("  - core.cpp")
