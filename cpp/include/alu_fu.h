#ifndef ALU_FU_H
#define ALU_FU_H

#include "types.h"

class ALUFU {
private:
    bool v_q;
    RSEntry e_q;
    xlen_t a_q;
    xlen_t b_q;

public:
    ALUFU();
    void reset();
    
    void tick(bool flush, bool issue_valid, const RSEntry& entry,
              xlen_t src1, xlen_t src2);
    
    // Output
    WBPkt getWB() const;
    
private:
    xlen_t execute(const RSEntry& entry, xlen_t a, xlen_t b) const;
};

#endif // ALU_FU_H
