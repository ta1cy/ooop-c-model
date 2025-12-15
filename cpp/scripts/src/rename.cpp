#include "rename.h"

Rename::Rename(MapTable* mt, FreeList* fl) : map_table(mt), free_list(fl) {}

RenamePkt Rename::rename(const DecodePkt& pkt_in, bool valid_in,
                        const std::bitset<N_PHYS_REGS>& prf_valid,
                        bool tag_ok, rob_tag_t rob_tag,
                        bool ready_in) {
    RenamePkt pkt = {};
    
    if (!valid_in) {
        return pkt;
    }
    
    // Check if need dest allocation
    bool need_alloc = pkt_in.rd_used && (pkt_in.rd != 0);
    bool has_free = free_list->hasFree();
    
    // Can proceed?
    bool alloc_ok = (!need_alloc) || has_free;
    bool can_proceed = alloc_ok && tag_ok;
    
    pkt.valid = can_proceed;
    pkt.pc = pkt_in.pc;
    pkt.instr = pkt_in.instr;
    pkt.rs1 = pkt_in.rs1;
    pkt.rs2 = pkt_in.rs2;
    pkt.rd = pkt_in.rd;
    pkt.imm = pkt_in.imm;
    pkt.imm_used = pkt_in.imm_used;
    pkt.fu_type = pkt_in.fu_type;
    pkt.alu_op = pkt_in.alu_op;
    pkt.rd_used = need_alloc;
    pkt.is_load = pkt_in.is_load;
    pkt.is_store = pkt_in.is_store;
    pkt.ls_size = pkt_in.ls_size;
    pkt.unsigned_load = pkt_in.unsigned_load;
    pkt.is_branch = pkt_in.is_branch;
    pkt.is_jump = pkt_in.is_jump;
    
    // Rename sources
    pkt.prs1 = map_table->lookupRS1(pkt_in.rs1);
    pkt.prs2 = map_table->lookupRS2(pkt_in.rs2);
    
    // Check ready
    auto preg_ready = [&](preg_t p) {
        return (p == 0) || prf_valid.test(p);
    };
    pkt.prs1_ready = preg_ready(pkt.prs1);
    pkt.prs2_ready = preg_ready(pkt.prs2);
    
    // Rename dest
    if (need_alloc) {
        pkt.prd = free_list->getAllocPreg();
        pkt.old_prd = map_table->lookupRDOld(pkt_in.rd);
    } else {
        pkt.prd = 0;
        pkt.old_prd = 0;
    }
    
    pkt.rob_tag = rob_tag;
    
    return pkt;
}

bool Rename::getReadyOut(const DecodePkt& pkt_in, bool has_free, bool tag_ok, bool ready_in) const {
    bool need_alloc = pkt_in.rd_used && (pkt_in.rd != 0);
    bool alloc_ok = (!need_alloc) || has_free;
    return ready_in && alloc_ok && tag_ok;
}

bool Rename::getValidOut(const DecodePkt& pkt_in, bool valid_in, bool has_free, bool tag_ok) const {
    bool need_alloc = pkt_in.rd_used && (pkt_in.rd != 0);
    bool alloc_ok = (!need_alloc) || has_free;
    return valid_in && alloc_ok && tag_ok;
}

bool Rename::getAllocReq(const DecodePkt& pkt_in, bool fire) const {
    bool need_alloc = pkt_in.rd_used && (pkt_in.rd != 0);
    return fire && need_alloc;
}

bool Rename::getCheckpointTake(const DecodePkt& pkt_in, bool fire) const {
    return fire && (pkt_in.is_branch || pkt_in.is_jump);
}
