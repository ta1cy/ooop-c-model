#ifndef DMEM_H
#define DMEM_H

#include "types.h"
#include <array>

class DMem {
private:
    static constexpr int DEPTH_WORDS = 1024;
    std::array<uint32_t, DEPTH_WORDS> mem;
    
    bool v1_q;
    bool v2_q;
    uint32_t rdata1_q;
    uint32_t rdata2_q;

public:
    DMem();
    void reset();
    
    void tick(bool en, bool we, uint32_t addr, uint32_t wdata, LSSize size);
    
    // Outputs (2-cycle latency)
    bool getRValid() const { return v2_q; }
    uint32_t getRData() const { return rdata2_q; }
    
private:
    uint32_t writeMerge(uint32_t old_word, uint32_t new_word,
                        LSSize size, uint8_t off) const;
};

#endif // DMEM_H
