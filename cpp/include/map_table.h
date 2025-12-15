#ifndef MAP_TABLE_H
#define MAP_TABLE_H

#include "types.h"
#include <array>

class MapTable {
private:
    std::array<preg_t, N_ARCH_REGS> rat;
    std::array<RATSnapshot, ROB_DEPTH> ckpt_rat;

public:
    MapTable();
    void reset();
    
    void tick(bool flush, bool recover, rob_tag_t recover_tag,
              bool we, reg_t we_arch, preg_t we_new_phys,
              bool checkpoint_take, rob_tag_t checkpoint_tag);
    
    // Combinational reads
    preg_t lookupRS1(reg_t rs1) const { return rat[rs1]; }
    preg_t lookupRS2(reg_t rs2) const { return rat[rs2]; }
    preg_t lookupRDOld(reg_t rd) const { return rat[rd]; }
};

#endif // MAP_TABLE_H
