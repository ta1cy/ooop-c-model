#ifndef ROB_TAG_ALLOC_H
#define ROB_TAG_ALLOC_H

#include "types.h"
#include <bitset>
#include <array>

class ROBTagAlloc {
private:
    rob_tag_t next_tag;
    std::bitset<ROB_DEPTH> reserved;
    std::array<rob_tag_t, ROB_DEPTH> ckpt_next_tag;

public:
    ROBTagAlloc();
    void reset();
    
    void tick(bool flush, bool recover, rob_tag_t recover_tag,
              bool alloc_req, const std::bitset<ROB_DEPTH>& live_tag,
              bool rob_alloc_fire, rob_tag_t rob_alloc_tag,
              bool checkpoint_take, rob_tag_t checkpoint_tag);
    
    // Outputs
    bool getAllocOk() const;
    rob_tag_t getTag() const;
    
private:
    rob_tag_t findFreeTag(const std::bitset<ROB_DEPTH>& used) const;
    bool alloc_ok_q;
    rob_tag_t tag_q;
};

#endif // ROB_TAG_ALLOC_H
