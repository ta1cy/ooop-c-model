#ifndef PRF_H
#define PRF_H

#include "types.h"
#include <array>
#include <bitset>

class PRF {
private:
    std::array<xlen_t, N_PHYS_REGS> regs;
    std::bitset<N_PHYS_REGS> valid_bits;
    
    std::array<PRFValidSnapshot, ROB_DEPTH> ckpt_valid;
    std::array<std::array<xlen_t, N_PHYS_REGS>, ROB_DEPTH> ckpt_regs;

public:
    PRF();
    void reset();
    
    void tick(bool flush, bool recover, rob_tag_t recover_tag,
              const WBPkt& wb_alu, const WBPkt& wb_lsu, const WBPkt& wb_bru,
              bool alloc_inval, preg_t alloc_preg,
              bool checkpoint_take, rob_tag_t checkpoint_tag);
    
    // Combinational reads
    xlen_t read(preg_t addr) const { return regs[addr]; }
    bool isValid(preg_t addr) const { return valid_bits[addr]; }
    
    const std::bitset<N_PHYS_REGS>& getValidBits() const { return valid_bits; }
};

#endif // PRF_H
