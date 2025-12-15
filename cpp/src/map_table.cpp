#include "map_table.h"

MapTable::MapTable() {
    reset();
}

void MapTable::reset() {
    // Initialize RAT: x0-x31 map to P0-P31
    for (int i = 0; i < N_ARCH_REGS; i++) {
        rat[i] = i;
    }
    
    for (int i = 0; i < ROB_DEPTH; i++) {
        for (int j = 0; j < N_ARCH_REGS; j++) {
            ckpt_rat[i].rat[j] = j;
        }
    }
}

void MapTable::tick(bool flush, bool recover, rob_tag_t recover_tag,
                    bool we, reg_t we_arch, preg_t we_new_phys,
                    bool checkpoint_take, rob_tag_t checkpoint_tag) {
    if (flush) {
        // Flush: no-op (recovery handles it)
        return;
    }
    
    if (recover) {
        // Restore from checkpoint
        rat = ckpt_rat[recover_tag].rat;
        return;
    }
    
    // Build next RAT
    auto rat_next = rat;
    if (we && we_arch != 0) {
        rat_next[we_arch] = we_new_phys;
    }
    
    // Update RAT
    rat = rat_next;
    
    // Checkpoint after update
    if (checkpoint_take) {
        ckpt_rat[checkpoint_tag].rat = rat_next;
    }
}
