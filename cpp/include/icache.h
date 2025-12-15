#ifndef ICACHE_H
#define ICACHE_H

#include "types.h"
#include <vector>
#include <string>

class ICache {
private:
    static constexpr int DEPTH_WORDS = 512;
    std::array<uint32_t, DEPTH_WORDS> mem;
    
    uint32_t rdata_q;
    bool rvalid_q;

public:
    ICache();
    
    // Load program from text file (byte format)
    bool loadProgram(const std::string& filename);
    
    // BRAM-style interface
    void tick(bool en, uint32_t addr);
    
    // Outputs (available after tick)
    uint32_t getRData() const { return rdata_q; }
    bool getRValid() const { return rvalid_q; }
};

#endif // ICACHE_H
