#ifndef RS_H
#define RS_H

#include "types.h"
#include <array>
#include <bitset>

class RS {
private:
    static constexpr int DEPTH = RS_DEPTH;
    std::array<RSEntry, DEPTH> entries;
    std::array<bool, DEPTH> occupied;
    
    bool hold_valid_q;
    int hold_idx_q;

public:
    RS();
    void reset();
    
    void tick(bool flush, bool recover, const std::bitset<ROB_DEPTH>& live_tag,
              bool insert_valid, const RSEntry& insert_entry,
              const WBPkt& wb_alu, const WBPkt& wb_lsu, const WBPkt& wb_bru,
              bool issue_ready);
    
    // Outputs
    bool getReady() const;
    bool getIssueValid() const;
    RSEntry getIssueEntry() const;
    
private:
    int findFree() const;
    int findReady() const;
    bool matchWB(const WBPkt& wb, preg_t preg) const;
};

#endif // RS_H
