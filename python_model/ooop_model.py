#!/usr/bin/env python3
"""
OOOP (Out-Of-Order Processor) Python Model
100% cycle-accurate match to Verilog design
For debugging and verification
"""

import sys
from dataclasses import dataclass, field
from typing import List, Optional
from enum import Enum, IntEnum

# Constants matching ooop_defs.vh
XLEN = 32
N_ARCH_REGS = 32
N_PHYS_REGS = 128
ROB_DEPTH = 16
RS_DEPTH = 8

class FUType(IntEnum):
    ALU = 0
    BRU = 1
    LSU = 2
    NONE = 3

class ALUOp(IntEnum):
    ADD = 0
    SUB = 1
    AND = 2
    OR = 3
    XOR = 4
    SLT = 5
    SLTU = 6
    SLL = 7
    SRL = 8
    SRA = 9
    SLTIU = 10
    LUI = 11

class LSSize(IntEnum):
    B = 0
    H = 1
    W = 2

@dataclass
class DecodePkt:
    valid: bool = False
    pc: int = 0
    instr: int = 0
    rs1: int = 0
    rs2: int = 0
    rd: int = 0
    rs1_used: bool = False
    rs2_used: bool = False
    imm: int = 0
    imm_used: bool = False
    fu_type: FUType = FUType.ALU
    alu_op: ALUOp = ALUOp.ADD
    rd_used: bool = False
    is_load: bool = False
    is_store: bool = False
    ls_size: LSSize = LSSize.W
    unsigned_load: bool = False
    is_branch: bool = False
    is_jump: bool = False

@dataclass
class RenamePkt(DecodePkt):
    prs1: int = 0
    prs2: int = 0
    prd: int = 0
    prs1_ready: bool = False
    prs2_ready: bool = False
    old_prd: int = 0
    rob_tag: int = 0

@dataclass
class RSEntry(RenamePkt):
    pass

@dataclass
class WBPkt:
    valid: bool = False
    rob_tag: int = 0
    prd: int = 0
    data: int = 0
    rd_used: bool = False

def sign_extend(value: int, bits: int) -> int:
    """Sign extend a value"""
    sign_bit = 1 << (bits - 1)
    if value & sign_bit:
        return value | (~((1 << bits) - 1) & 0xFFFFFFFF)
    return value & ((1 << bits) - 1)

def to_signed(value: int) -> int:
    """Convert unsigned 32-bit to signed"""
    if value >= 0x80000000:
        return value - 0x100000000
    return value

def to_unsigned(value: int) -> int:
    """Ensure value is unsigned 32-bit"""
    return value & 0xFFFFFFFF

class ICache:
    def __init__(self, depth=512):
        self.depth = depth
        self.mem = [0x00000013] * depth  # NOP
        self.rdata = 0
        self.rvalid = False
    
    def load_program(self, filename):
        """Load program from byte file"""
        with open(filename, 'r') as f:
            bytes_data = []
            for line in f:
                line = line.strip()
                if not line or line.startswith('#') or line.startswith('//'):
                    continue
                try:
                    bytes_data.append(int(line, 16))
                except:
                    continue
        
        # Pack into words (little-endian)
        for i in range(0, len(bytes_data) - 3, 4):
            word = (bytes_data[i] | 
                   (bytes_data[i+1] << 8) |
                   (bytes_data[i+2] << 16) |
                   (bytes_data[i+3] << 24))
            self.mem[i // 4] = word
        
        print(f"[icache] Loaded {len(bytes_data)} bytes ({len(bytes_data)//4} words)")
        return True
    
    def tick(self, en, addr):
        if en:
            word_idx = addr >> 2
            if word_idx < self.depth:
                self.rdata = self.mem[word_idx]
                self.rvalid = True
            else:
                self.rdata = 0x00000013
                self.rvalid = True
        else:
            self.rvalid = False

class Fetch:
    def __init__(self):
        self.state = 'IDLE'  # IDLE, REQ, HAVE
        self.pc = 0
        self.instr = 0x00000013
    
    def reset(self):
        self.state = 'IDLE'
        self.pc = 0
        self.instr = 0x00000013
    
    def tick(self, flush, flush_pc, ready_in, icache_rvalid, icache_rdata):
        if flush:
            self.state = 'IDLE'
            self.pc = flush_pc
        elif self.state == 'IDLE':
            self.state = 'REQ'
        elif self.state == 'REQ':
            if icache_rvalid:
                self.instr = icache_rdata
                self.state = 'HAVE'
        elif self.state == 'HAVE':
            if ready_in:
                self.pc += 4
                self.state = 'REQ'
    
    def get_valid_out(self):
        return self.state == 'HAVE'
    
    def get_icache_en(self):
        return self.state == 'REQ'

class Decode:
    @staticmethod
    def decode(valid_in, pc, instr):
        pkt = DecodePkt()
        
        if not valid_in:
            return pkt
        
        pkt.valid = True
        pkt.pc = pc
        pkt.instr = instr
        
        opcode = instr & 0x7F
        funct3 = (instr >> 12) & 0x7
        funct7 = (instr >> 25) & 0x7F
        
        pkt.rd = (instr >> 7) & 0x1F
        pkt.rs1 = (instr >> 15) & 0x1F
        pkt.rs2 = (instr >> 20) & 0x1F
        
        # Immediates
        imm_i = sign_extend(instr >> 20, 12)
        imm_s = sign_extend(((instr >> 25) << 5) | ((instr >> 7) & 0x1F), 12)
        imm_b = sign_extend(
            ((instr >> 31) << 12) |
            (((instr >> 7) & 1) << 11) |
            (((instr >> 25) & 0x3F) << 5) |
            (((instr >> 8) & 0xF) << 1), 13)
        imm_u = instr & 0xFFFFF000
        imm_j = sign_extend(
            ((instr >> 31) << 20) |
            (((instr >> 12) & 0xFF) << 12) |
            (((instr >> 20) & 1) << 11) |
            (((instr >> 21) & 0x3FF) << 1), 21)
        
        if opcode == 0x37:  # LUI
            pkt.fu_type = FUType.ALU
            pkt.alu_op = ALUOp.LUI
            pkt.rd_used = (pkt.rd != 0)
            pkt.imm = imm_u
            pkt.imm_used = True
        elif opcode == 0x6F:  # JAL
            pkt.fu_type = FUType.BRU
            pkt.is_jump = True
            pkt.rd_used = (pkt.rd != 0)
            pkt.imm = imm_j
            pkt.imm_used = True
        elif opcode == 0x13:  # OP-IMM
            pkt.fu_type = FUType.ALU
            pkt.rs1_used = True
            pkt.rd_used = (pkt.rd != 0)
            pkt.imm = imm_i
            pkt.imm_used = True
            if funct3 == 0x0: pkt.alu_op = ALUOp.ADD
            elif funct3 == 0x6: pkt.alu_op = ALUOp.OR
            elif funct3 == 0x7: pkt.alu_op = ALUOp.AND
            elif funct3 == 0x3: pkt.alu_op = ALUOp.SLTIU
            elif funct3 == 0x5: pkt.alu_op = ALUOp.SRA
        elif opcode == 0x33:  # OP
            pkt.fu_type = FUType.ALU
            pkt.rs1_used = True
            pkt.rs2_used = True
            pkt.rd_used = (pkt.rd != 0)
            if funct3 == 0x0:
                pkt.alu_op = ALUOp.SUB if funct7 == 0x20 else ALUOp.ADD
            elif funct3 == 0x7: pkt.alu_op = ALUOp.AND
            elif funct3 == 0x6: pkt.alu_op = ALUOp.OR
            elif funct3 == 0x5: pkt.alu_op = ALUOp.SRA
        elif opcode == 0x03:  # LOAD
            pkt.fu_type = FUType.LSU
            pkt.rs1_used = True
            pkt.rd_used = (pkt.rd != 0)
            pkt.is_load = True
            pkt.imm = imm_i
            pkt.imm_used = True
            if funct3 == 0x2:
                pkt.ls_size = LSSize.W
                pkt.unsigned_load = False
            elif funct3 == 0x4:
                pkt.ls_size = LSSize.B
                pkt.unsigned_load = True
        elif opcode == 0x23:  # STORE
            pkt.fu_type = FUType.LSU
            pkt.rs1_used = True
            pkt.rs2_used = True
            pkt.is_store = True
            pkt.imm = imm_s
            pkt.imm_used = True
            pkt.ls_size = LSSize.W if funct3 == 0x2 else LSSize.H
        elif opcode == 0x63:  # BRANCH
            pkt.fu_type = FUType.BRU
            pkt.is_branch = True
            pkt.rs1_used = True
            pkt.rs2_used = True
            pkt.imm = imm_b
            pkt.imm_used = True
        elif opcode == 0x67:  # JALR
            pkt.fu_type = FUType.BRU
            pkt.is_jump = True
            pkt.rs1_used = True
            pkt.rd_used = (pkt.rd != 0)
            pkt.imm = imm_i
            pkt.imm_used = True
        
        return pkt

# Continue in next file...
print("Python model part 1 created. Creating part 2...")
