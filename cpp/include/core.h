#ifndef CORE_H
#define CORE_H

#include "types.h"
#include "icache.h"
#include "fetch.h"
#include "decode.h"
#include "rename.h"
#include "dispatch.h"
#include "rs.h"
#include "rob.h"
#include "prf.h"
#include "map_table.h"
#include "free_list.h"
#include "rob_tag_alloc.h"
#include "alu_fu.h"
#include "branch_fu.h"
#include "lsu_fu.h"
#include "dmem.h"
#include "recovery_ctrl.h"
#include <memory>

class Core {
private:
    // Components
    std::unique_ptr<ICache> icache;
    std::unique_ptr<Fetch> fetch;
    std::unique_ptr<Decode> decode;
    std::unique_ptr<MapTable> map_table;
    std::unique_ptr<FreeList> free_list;
    std::unique_ptr<ROBTagAlloc> rob_tag_alloc;
    std::unique_ptr<Rename> rename;
    std::unique_ptr<Dispatch> dispatch;
    std::unique_ptr<RS> rs_alu;
    std::unique_ptr<RS> rs_bru;
    std::unique_ptr<RS> rs_lsu;
    std::unique_ptr<ROB> rob;
    std::unique_ptr<PRF> prf;
    std::unique_ptr<ALUFU> alu_fu;
    std::unique_ptr<BranchFU> branch_fu;
    std::unique_ptr<LSUFU> lsu_fu;
    std::unique_ptr<DMem> dmem;
    std::unique_ptr<RecoveryCtrl> recovery_ctrl;
    
    // Pipeline registers (skid buffers would go here)
    FetchPkt f2d_pkt;
    bool f2d_valid;
    
    DecodePkt d2r_pkt;
    bool d2r_valid;
    
    RenamePkt r2d_pkt;
    bool r2d_valid;
    
    // Stats
    uint64_t cycle_count;
    uint64_t commit_count;

public:
    Core();
    ~Core();
    
    bool loadProgram(const std::string& filename);
    void reset();
    void tick();
    void run(uint64_t max_cycles);
    
    // Get results
    uint32_t getArchRegValue(reg_t arch_reg) const;
    uint64_t getCycleCount() const { return cycle_count; }
    uint64_t getCommitCount() const { return commit_count; }
};

#endif // CORE_H
