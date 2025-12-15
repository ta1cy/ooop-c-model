#ifndef FETCH_H
#define FETCH_H

#include "types.h"

class Fetch {
private:
    enum class State {
        IDLE,
        REQ,
        HAVE
    };
    
    State state;
    xlen_t pc_q;
    uint32_t instr_q;

public:
    Fetch();
    void reset();
    
    void tick(bool flush, xlen_t flush_pc, bool ready_in,
              bool icache_rvalid, uint32_t icache_rdata);
    
    // Outputs
    bool getValidOut() const;
    xlen_t getPCOut() const { return pc_q; }
    uint32_t getInstrOut() const { return instr_q; }
    
    // ICache control
    bool getICacheEn() const;
    xlen_t getICacheAddr() const { return pc_q; }
};

#endif // FETCH_H
