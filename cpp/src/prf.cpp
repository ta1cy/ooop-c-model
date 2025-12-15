#include "prf.h"

PRF::PRF() {
    reset();
}

void PRF::reset() {
    regs.fill(0);
    valid_bits.set(); // All valid initially
    
    for (int i = 0; i < ROB_DEPTH; i++) {
        ckpt_valid[i].valid_bits.set();
        ckpt_regs[i].fill(0);
    }
}

void PRF::tick(bool flush, bool recover, rob_tag_t recover_tag,
               const WBPkt& wb_alu, const WBPkt& wb_lsu, const WBPkt& wb_bru,
               bool alloc_inval, preg_t alloc_preg,
               bool checkpoint_take, rob_tag_t checkpoint_tag) {
    if (recover) {
        valid_bits = ckpt_valid[recover_tag].valid_bits;
        regs = ckpt_regs[recover_tag];
        regs[0] = 0;
        valid_bits.set(0);
        return;
    }
    
    if (flush) {
        regs[0] = 0;
        valid_bits.set(0);
        return;
    }
    
    // Helper to apply WB
    auto do_wb = [&](const WBPkt& wb) {
        if (wb.valid && wb.rd_used && wb.prd != 0) {
            regs[wb.prd] = wb.data;
        }
    };
    
    // Apply writebacks
    do_wb(wb_alu);
    do_wb(wb_lsu);
    do_wb(wb_bru);
    
    // Update valid bits
    auto valid_next = valid_bits;
    
    if (alloc_inval && alloc_preg != 0) {
        valid_next.reset(alloc_preg);
    }
    
    auto apply_wb_valid = [](std::bitset<N_PHYS_REGS>& vb, const WBPkt& wb) {
        if (wb.valid && wb.rd_used && wb.prd != 0) {
            vb.set(wb.prd);
        }
    };
    
    apply_wb_valid(valid_next, wb_alu);
    apply_wb_valid(valid_next, wb_lsu);
    apply_wb_valid(valid_next, wb_bru);
    
    valid_next.set(0);
    valid_bits = valid_next;
    
    // Checkpoint
    if (checkpoint_take) {
        ckpt_valid[checkpoint_tag].valid_bits = valid_next;
        ckpt_regs[checkpoint_tag] = regs;
        
        // Apply WB to checkpoint
        auto apply_ckpt_wb = [&](const WBPkt& wb) {
            if (wb.valid && wb.rd_used && wb.prd != 0) {
                ckpt_regs[checkpoint_tag][wb.prd] = wb.data;
            }
        };
        
        apply_ckpt_wb(wb_alu);
        apply_ckpt_wb(wb_lsu);
        apply_ckpt_wb(wb_bru);
        
        ckpt_regs[checkpoint_tag][0] = 0;
    }
    
    regs[0] = 0;
    valid_bits.set(0);
}
