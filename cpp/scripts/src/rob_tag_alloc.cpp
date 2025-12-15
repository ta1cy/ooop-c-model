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
