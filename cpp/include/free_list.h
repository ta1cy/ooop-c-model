#ifndef FREE_LIST_H
#define FREE_LIST_H

#include "types.h"
#include <bitset>
#include <array>

class FreeList {
private:
    std::bitset<N_PHYS_REGS> free_map;
    std::array<FreelistSnapshot, ROB_DEPTH> ckpt_free_map;

public:
    FreeList();
    void reset();
    
    void tick(bool flush, bool recover, rob_tag_t recover_tag,
              bool alloc_req, bool free_req, preg_t free_preg,
              bool checkpoint_take, rob_tag_t checkpoint_tag);
    
    // Outputs
    bool hasFree() const;
    preg_t getAllocPreg() const;
    bool getAllocGnt() const;
    
private:
    preg_t findFree() const;
    bool alloc_gnt_q;
    preg_t alloc_preg_q;
};

#endif // FREE_LIST_H
