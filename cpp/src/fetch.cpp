#include "fetch.h"

Fetch::Fetch() : state(State::IDLE), pc_q(0), instr_q(0x00000013) {}

void Fetch::reset() {
    state = State::IDLE;
    pc_q = 0;
    instr_q = 0x00000013;
}

void Fetch::tick(bool flush, xlen_t flush_pc, bool ready_in,
                 bool icache_rvalid, uint32_t icache_rdata) {
    if (flush) {
        state = State::IDLE;
        pc_q = flush_pc;
    } else {
        switch (state) {
            case State::IDLE:
                state = State::REQ;
                break;
                
            case State::REQ:
                if (icache_rvalid) {
                    instr_q = icache_rdata;
                    state = State::HAVE;
                }
                break;
                
            case State::HAVE:
                if (ready_in) {
                    pc_q += 4;
                    state = State::REQ;
                }
                break;
        }
    }
}

bool Fetch::getValidOut() const {
    return (state == State::HAVE);
}

bool Fetch::getICacheEn() const {
    return (state == State::REQ);
}
