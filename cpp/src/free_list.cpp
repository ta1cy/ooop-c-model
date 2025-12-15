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
