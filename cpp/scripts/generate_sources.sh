#!/bin/bash

# Script to generate all remaining C++ implementation files for OOOP model

echo "Generating C++ model source files..."

# This script creates placeholder implementations
# Each file will need to be filled with the actual logic

cat > ../cpp/src/free_list.cpp << 'EOF'
#include "free_list.h"

FreeList::FreeList() : alloc_gnt_q(false), alloc_preg_q(0) {
    reset();
}

void FreeList::reset() {
    free_map.reset();
    // Set P32-P127 as free (P0-P31 are reserved for architectural regs)
    for (int i = N_ARCH_REGS; i < N_PHYS_REGS; i++) {
        free_map.set(i);
    }
    
    for (int i = 0; i < ROB_DEPTH; i++) {
        ckpt_free_map[i].free_map = free_map;
    }
}

void FreeList::tick(bool flush, bool recover, rob_tag_t recover_tag,
                    bool alloc_req, bool free_req, preg_t free_preg,
                    bool checkpoint_take, rob_tag_t checkpoint_tag) {
    if (flush) {
        return;
    }
    
    if (recover) {
        free_map = ckpt_free_map[recover_tag].free_map;
        return;
    }
    
    // Free on commit
    if (free_req && free_preg != 0) {
        free_map.set(free_preg);
    }
    
    // Allocate on rename
    preg_t found_preg = findFree();
    bool can_alloc = hasFree();
    alloc_gnt_q = alloc_req && can_alloc;
    
    if (alloc_gnt_q) {
        free_map.reset(found_preg);
        alloc_preg_q = found_preg;
    }
    
    // Checkpoint
    if (checkpoint_take) {
        auto next_map = free_map;
        if (free_req && free_preg != 0) {
            next_map.set(free_preg);
        }
        if (alloc_gnt_q) {
            next_map.reset(found_preg);
        }
        ckpt_free_map[checkpoint_tag].free_map = next_map;
    }
}

bool FreeList::hasFree() const {
    for (int i = N_ARCH_REGS; i < N_PHYS_REGS; i++) {
        if (free_map.test(i)) return true;
    }
    return false;
}

preg_t FreeList::getAllocPreg() const {
    return alloc_preg_q;
}

bool FreeList::getAllocGnt() const {
    return alloc_gnt_q;
}

preg_t FreeList::findFree() const {
    for (int i = N_ARCH_REGS; i < N_PHYS_REGS; i++) {
        if (free_map.test(i)) {
            return static_cast<preg_t>(i);
        }
    }
    return 0;
}
EOF

echo "Created free_list.cpp"

cat > ../cpp/src/rob_tag_alloc.cpp << 'EOF'
#include "rob_tag_alloc.h"

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
    bool found = !used.test(free_tag);
    
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
EOF

echo "Created rob_tag_alloc.cpp"

echo "Done! Now compile with: cd cpp && make"
