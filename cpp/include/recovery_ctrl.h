#ifndef RECOVERY_CTRL_H
#define RECOVERY_CTRL_H

#include "types.h"

class RecoveryCtrl {
private:
    bool mp_q;
    bool flush_q;
    bool recover_q;
    xlen_t flush_pc_q;
    rob_tag_t recover_tag_q;

public:
    RecoveryCtrl();
    void reset();
    
    void tick(bool mispredict, xlen_t target_pc, rob_tag_t recover_tag);
    
    // Outputs
    bool getFlush() const { return flush_q; }
    xlen_t getFlushPC() const { return flush_pc_q; }
    bool getRecover() const { return recover_q; }
    rob_tag_t getRecoverTag() const { return recover_tag_q; }
};

#endif // RECOVERY_CTRL_H
