#ifndef ROB_H
#define ROB_H

#include "types.h"
#include <array>
#include <bitset>

class ROB {
private:
    struct Entry {
        bool valid;
        bool done;
        rob_tag_t tag;
        bool rd_used;
        preg_t old_prd;
    };
    
    static constexpr int DEPTH = ROB_DEPTH;
    std::array<Entry, DEPTH> entries;
    
    rob_tag_t head;
    rob_tag_t tail;
    uint8_t count;
    
    std::array<ROBPtrsSnapshot, DEPTH> ckpt_ptrs;
    std::bitset<DEPTH> ckpt_pending;

public:
    ROB();
    void reset();
    
    void tick(bool flush, bool recover, rob_tag_t recover_tag,
              bool alloc_valid, const RenamePkt& alloc_pkt,
              const WBPkt& wb_alu, const WBPkt& wb_lsu, const WBPkt& wb_bru,
              bool checkpoint_take, rob_tag_t checkpoint_tag);
    
    // Outputs
    bool getReady() const { return count < DEPTH; }
    bool getFreeReq() const;
    preg_t getFreePreg() const;
    std::bitset<DEPTH> getLiveTag() const;
    
private:
    bool wbHits(const WBPkt& wb, rob_tag_t tag) const;
};

#endif // ROB_H
