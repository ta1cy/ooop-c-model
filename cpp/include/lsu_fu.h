#ifndef LSU_FU_H
#define LSU_FU_H

#include "types.h"
#include <array>

class LSUFU {
private:
    struct Meta {
        bool v;
        bool is_load;
        bool rd_used;
        rob_tag_t rob_tag;
        preg_t prd;
        LSSize size;
        bool uns;
        uint8_t off;
    };
    
    Meta m0_q;
    Meta m1_q;
    uint8_t block_cnt;

public:
    LSUFU();
    void reset();
    
    void tick(bool flush, bool issue_valid, const RSEntry& entry,
              xlen_t src1, xlen_t src2, bool dmem_rvalid, uint32_t dmem_rdata);
    
    // Outputs
    WBPkt getWB(bool dmem_rvalid, uint32_t dmem_rdata) const;
    
    // DMEM control
    bool getDMemEn() const;
    bool getDMemWE() const;
    uint32_t getDMemAddr() const;
    uint32_t getDMemWData() const;
    LSSize getDMemSize() const;
    
private:
    bool allow_issue;
    RSEntry entry_latched;
    xlen_t src1_latched;
    xlen_t src2_latched;
    
    uint32_t extractLoad(uint32_t rdata, const Meta& m) const;
};

#endif // LSU_FU_H
