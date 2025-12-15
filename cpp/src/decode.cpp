#include "decode.h"

Decode::Decode() {}

DecodePkt Decode::decode(bool valid_in, xlen_t pc_in, uint32_t instr_in) {
    DecodePkt pkt = {};
    
    if (!valid_in) {
        return pkt;
    }
    
    pkt.valid = true;
    pkt.pc = pc_in;
    pkt.instr = instr_in;
    
    // Extract fields
    uint8_t opcode = instr_in & 0x7F;
    uint8_t funct3 = (instr_in >> 12) & 0x7;
    uint8_t funct7 = (instr_in >> 25) & 0x7F;
    
    pkt.rd = (instr_in >> 7) & 0x1F;
    pkt.rs1 = (instr_in >> 15) & 0x1F;
    pkt.rs2 = (instr_in >> 20) & 0x1F;
    
    // Default values
    pkt.rd_used = false;
    pkt.rs1_used = false;
    pkt.rs2_used = false;
    pkt.fu_type = FUType::ALU;
    pkt.alu_op = ALUOp::ADD;
    pkt.imm = 0;
    pkt.imm_used = false;
    pkt.is_load = false;
    pkt.is_store = false;
    pkt.ls_size = LSSize::W;
    pkt.unsigned_load = false;
    pkt.is_branch = false;
    pkt.is_jump = false;
    
    // Immediate formats
    int32_t imm_i = static_cast<int32_t>(instr_in) >> 20;
    int32_t imm_s = ((static_cast<int32_t>(instr_in) >> 20) & ~0x1F) | ((instr_in >> 7) & 0x1F);
    int32_t imm_b = ((static_cast<int32_t>(instr_in & 0x80000000) >> 19) |
                     ((instr_in << 4) & 0x800) |
                     ((instr_in >> 20) & 0x7E0) |
                     ((instr_in >> 7) & 0x1E));
    int32_t imm_u = instr_in & 0xFFFFF000;
    int32_t imm_j = ((static_cast<int32_t>(instr_in & 0x80000000) >> 11) |
                     (instr_in & 0xFF000) |
                     ((instr_in >> 9) & 0x800) |
                     ((instr_in >> 20) & 0x7FE));
    
    switch (opcode) {
        case 0x37: // LUI
            pkt.fu_type = FUType::ALU;
            pkt.alu_op = ALUOp::LUI;
            pkt.rd_used = (pkt.rd != 0);
            pkt.imm = imm_u;
            pkt.imm_used = true;
            break;
            
        case 0x6F: // JAL
            pkt.fu_type = FUType::BRU;
            pkt.is_jump = true;
            pkt.rd_used = (pkt.rd != 0);
            pkt.imm = imm_j;
            pkt.imm_used = true;
            break;
            
        case 0x13: // OP-IMM
            pkt.fu_type = FUType::ALU;
            pkt.rs1_used = true;
            pkt.rd_used = (pkt.rd != 0);
            pkt.imm = imm_i;
            pkt.imm_used = true;
            
            switch (funct3) {
                case 0x0: pkt.alu_op = ALUOp::ADD; break;    // ADDI
                case 0x6: pkt.alu_op = ALUOp::OR; break;     // ORI
                case 0x7: pkt.alu_op = ALUOp::AND; break;    // ANDI
                case 0x3: pkt.alu_op = ALUOp::SLTIU; break;  // SLTIU
                case 0x5:
                    if (funct7 == 0x20) pkt.alu_op = ALUOp::SRA;  // SRAI
                    else pkt.alu_op = ALUOp::SRL;  // SRLI
                    break;
                default: pkt.alu_op = ALUOp::ADD; break;
            }
            break;
            
        case 0x33: // OP
            pkt.fu_type = FUType::ALU;
            pkt.rs1_used = true;
            pkt.rs2_used = true;
            pkt.rd_used = (pkt.rd != 0);
            
            switch (funct3) {
                case 0x0:
                    if (funct7 == 0x20) pkt.alu_op = ALUOp::SUB;  // SUB
                    else pkt.alu_op = ALUOp::ADD;  // ADD
                    break;
                case 0x7: pkt.alu_op = ALUOp::AND; break;  // AND
                case 0x6: pkt.alu_op = ALUOp::OR; break;   // OR
                case 0x5: pkt.alu_op = ALUOp::SRA; break;  // SRA
                default: pkt.alu_op = ALUOp::ADD; break;
            }
            break;
            
        case 0x03: // LOAD
            pkt.fu_type = FUType::LSU;
            pkt.rs1_used = true;
            pkt.rd_used = (pkt.rd != 0);
            pkt.is_load = true;
            pkt.imm = imm_i;
            pkt.imm_used = true;
            
            switch (funct3) {
                case 0x2: // LW
                    pkt.ls_size = LSSize::W;
                    pkt.unsigned_load = false;
                    break;
                case 0x4: // LBU
                    pkt.ls_size = LSSize::B;
                    pkt.unsigned_load = true;
                    break;
                default:
                    pkt.ls_size = LSSize::W;
                    pkt.unsigned_load = false;
                    break;
            }
            break;
            
        case 0x23: // STORE
            pkt.fu_type = FUType::LSU;
            pkt.rs1_used = true;
            pkt.rs2_used = true;
            pkt.is_store = true;
            pkt.imm = imm_s;
            pkt.imm_used = true;
            
            switch (funct3) {
                case 0x2: pkt.ls_size = LSSize::W; break;  // SW
                case 0x1: pkt.ls_size = LSSize::H; break;  // SH
                default: pkt.ls_size = LSSize::W; break;
            }
            break;
            
        case 0x63: // BRANCH
            pkt.fu_type = FUType::BRU;
            pkt.is_branch = true;
            pkt.rs1_used = true;
            pkt.rs2_used = true;
            pkt.imm = imm_b;
            pkt.imm_used = true;
            break;
            
        case 0x67: // JALR
            pkt.fu_type = FUType::BRU;
            pkt.is_jump = true;
            pkt.rs1_used = true;
            pkt.rd_used = (pkt.rd != 0);
            pkt.imm = imm_i;
            pkt.imm_used = true;
            break;
            
        default:
            // Unknown instruction - treat as NOP
            pkt.valid = true;
            break;
    }
    
    return pkt;
}
