#ifndef RENAME_H
#define RENAME_H

#include "types.h"
#include "map_table.h"
#include "free_list.h"

class Rename {
private:
    MapTable* map_table;
    FreeList* free_list;

public:
    Rename(MapTable* mt, FreeList* fl);
    
    // Combinational rename logic
    RenamePkt rename(const DecodePkt& pkt_in, bool valid_in,
                     const std::bitset<N_PHYS_REGS>& prf_valid,
                     bool tag_ok, rob_tag_t rob_tag,
                     bool ready_in);
    
    // Check if can proceed
    bool getReadyOut(const DecodePkt& pkt_in, bool has_free, bool tag_ok, bool ready_in) const;
    bool getValidOut(const DecodePkt& pkt_in, bool valid_in, bool has_free, bool tag_ok) const;
    
    // Allocation signals
    bool getAllocReq(const DecodePkt& pkt_in, bool fire) const;
    bool getCheckpointTake(const DecodePkt& pkt_in, bool fire) const;
};

#endif // RENAME_H
