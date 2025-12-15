#ifndef OOOP_TYPES_H
#define OOOP_TYPES_H

#include <cstdint>
#include <array>
#include <bitset>

// Global constants matching ooop_defs.vh
constexpr int XLEN = 32;
constexpr int N_ARCH_REGS = 32;
constexpr int N_PHYS_REGS = 128;
constexpr int ROB_DEPTH = 16;
constexpr int RS_DEPTH = 8;

// Derived widths
constexpr int REG_W = 5;   // log2(32)
constexpr int PREG_W = 7;  // log2(128)
constexpr int ROB_W = 4;   // log2(16)
constexpr int RS_W = 3;    // log2(8)

// Type aliases
using xlen_t = uint32_t;
using reg_t = uint8_t;
using preg_t = uint8_t;
using rob_tag_t = uint8_t;

// Enums matching ooop_types.sv
enum class FUType : uint8_t {
    ALU = 0,
    BRU = 1,
    LSU = 2,
    NONE = 3
};

enum class ALUOp : uint8_t {
    ADD = 0,
    SUB = 1,
    AND = 2,
    OR = 3,
    XOR = 4,
    SLT = 5,
    SLTU = 6,
    SLL = 7,
    SRL = 8,
    SRA = 9,
    SLTIU = 10,
    LUI = 11
};

enum class LSSize : uint8_t {
    B = 0,  // Byte
    H = 1,  // Halfword
    W = 2   // Word
};

// Packet structures
struct FetchPkt {
    bool valid;
    xlen_t pc;
    uint32_t instr;
};

struct DecodePkt {
    bool valid;
    xlen_t pc;
    uint32_t instr;
    
    reg_t rs1;
    reg_t rs2;
    reg_t rd;
    
    bool rs1_used;
    bool rs2_used;
    
    xlen_t imm;
    bool imm_used;
    
    FUType fu_type;
    ALUOp alu_op;
    
    bool rd_used;
    
    bool is_load;
    bool is_store;
    LSSize ls_size;
    bool unsigned_load;
    
    bool is_branch;
    bool is_jump;
};

struct RenamePkt {
    bool valid;
    xlen_t pc;
    uint32_t instr;
    
    reg_t rs1;
    reg_t rs2;
    reg_t rd;
    
    xlen_t imm;
    bool imm_used;
    
    FUType fu_type;
    ALUOp alu_op;
    
    bool rd_used;
    
    bool is_load;
    bool is_store;
    LSSize ls_size;
    bool unsigned_load;
    
    bool is_branch;
    bool is_jump;
    
    preg_t prs1;
    preg_t prs2;
    preg_t prd;
    
    bool prs1_ready;
    bool prs2_ready;
    
    preg_t old_prd;
    rob_tag_t rob_tag;
};

struct RSEntry {
    bool valid;
    
    xlen_t pc;
    uint32_t instr;
    
    FUType fu_type;
    ALUOp alu_op;
    
    xlen_t imm;
    bool imm_used;
    
    bool rd_used;
    
    bool is_load;
    bool is_store;
    LSSize ls_size;
    bool unsigned_load;
    
    bool is_branch;
    bool is_jump;
    
    preg_t prs1;
    preg_t prs2;
    preg_t prd;
    
    bool prs1_ready;
    bool prs2_ready;
    
    rob_tag_t rob_tag;
};

struct WBPkt {
    bool valid;
    rob_tag_t rob_tag;
    preg_t prd;
    xlen_t data;
    bool rd_used;
};

// Checkpoint structures
struct RATSnapshot {
    std::array<preg_t, N_ARCH_REGS> rat;
};

struct FreelistSnapshot {
    std::bitset<N_PHYS_REGS> free_map;
};

struct PRFValidSnapshot {
    std::bitset<N_PHYS_REGS> valid_bits;
};

struct ROBPtrsSnapshot {
    rob_tag_t tail;
    uint8_t count;
};

#endif // OOOP_TYPES_H
