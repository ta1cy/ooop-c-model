#ifndef BRANCH_FU_H
#define BRANCH_FU_H

#include "types.h"

class BranchFU {
private:
    WBPkt wb_q;
    bool mp_q;
    xlen_t tgt_q;
    rob_tag_t rtag_q;

public:
    BranchFU();
    void reset();
    
    void tick(bool flush, bool issue_valid, const RSEntry& entry,
              xlen_t src1, xlen_t src2);
    
    // Outputs
    WBPkt getWB() const { return wb_q; }
    bool getMispredict() const { return mp_q; }
    xlen_t getTargetPC() const { return tgt_q; }
    rob_tag_t getRecoverTag() const { return rtag_q; }
    
private:
    bool computeTaken(const RSEntry& entry, xlen_t src1, xlen_t src2) const;
    xlen_t computeTarget(const RSEntry& entry, xlen_t src1) const;
};

#endif // BRANCH_FU_H
