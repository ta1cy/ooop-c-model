#ifndef DISPATCH_H
#define DISPATCH_H

#include "types.h"

class Dispatch {
private:
    bool fifo_full;
    RenamePkt fifo_storage;

public:
    Dispatch();
    void reset();
    
    void tick(bool flush, bool valid_in, const RenamePkt& pkt_in,
              bool rs_alu_ready, bool rs_bru_ready, bool rs_lsu_ready,
              bool rob_ready);
    
    // Outputs
    bool getReadyOut() const;
    bool getOutValid() const { return fifo_full; }
    RenamePkt getOutPkt() const { return fifo_storage; }
    
    // RS insert signals
    bool getRSALUValid() const;
    bool getRSBRUValid() const;
    bool getRSLSUValid() const;
    RSEntry buildRSEntry(const RenamePkt& pkt) const;
    
    // ROB alloc signals
    bool getROBAllocValid() const;
    
private:
    bool rsSpaceOk(const RenamePkt& pkt, bool rs_alu_ready,
                   bool rs_bru_ready, bool rs_lsu_ready) const;
};

#endif // DISPATCH_H
