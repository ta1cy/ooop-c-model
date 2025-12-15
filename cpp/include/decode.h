#ifndef DECODE_H
#define DECODE_H

#include "types.h"

class Decode {
public:
    Decode();
    
    // Combinational decode
    DecodePkt decode(bool valid_in, xlen_t pc_in, uint32_t instr_in);
};

#endif // DECODE_H
