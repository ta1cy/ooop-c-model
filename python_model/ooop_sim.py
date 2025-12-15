#!/usr/bin/env python3
"""
OOOP Python Model - Complete Single-File Implementation
Run with: python3 ooop_sim.py <trace_file> [max_cycles]
"""

import sys
from dataclasses import dataclass
from typing import List
from enum import IntEnum

# === CONSTANTS ===
XLEN = 32
N_ARCH_REGS = 32
N_PHYS_REGS = 128
ROB_DEPTH = 16
RS_DEPTH = 8

class FUType(IntEnum):
    ALU, BRU, LSU, NONE = range(4)

class ALUOp(IntEnum):
    ADD, SUB, AND, OR, XOR, SLT, SLTU, SLL, SRL, SRA, SLTIU, LUI = range(12)

class LSSize(IntEnum):
    B, H, W = range(3)

# === HELPER FUNCTIONS ===
def sext(val, bits):
    """Sign extend"""
    sign = 1 << (bits - 1)
    return (val & ((1 << bits) - 1)) - (val & sign) * 2

def u32(val):
    """Unsigned 32-bit"""
    return val & 0xFFFFFFFF

def s32(val):
    """Signed 32-bit"""
    val &= 0xFFFFFFFF
    return val if val < 0x80000000 else val - 0x100000000

# === PACKETS ===
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
    fu_type: int = 0
    alu_op: int = 0
    rd_used: bool = False
    is_load: bool = False
    is_store: bool = False
    ls_size: int = 2
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
class WBPkt:
    valid: bool = False
    rob_tag: int = 0
    prd: int = 0
    data: int = 0
    rd_used: bool = False

# === MODULES ===
class ICache:
    def __init__(self):
        self.mem = [0x00000013] * 512
        self.rdata, self.rvalid = 0, False
    
    def load(self, fname):
        bytes_data = []
        for line in open(fname):
            line = line.strip()
            if line and not line.startswith(('#', '//')):
                try: bytes_data.append(int(line, 16))
                except: pass
        for i in range(0, len(bytes_data)-3, 4):
            self.mem[i//4] = bytes_data[i] | (bytes_data[i+1]<<8) | (bytes_data[i+2]<<16) | (bytes_data[i+3]<<24)
        print(f"Loaded {len(bytes_data)} bytes")
    
    def tick(self, en, addr):
        self.rvalid = en
        self.rdata = self.mem[(addr>>2) % len(self.mem)] if en else 0

class Fetch:
    def __init__(self):
        self.state, self.pc, self.instr = 0, 0, 0x13  # 0=IDLE, 1=REQ, 2=HAVE
    
    def tick(self, flush, flush_pc, ready, ic_rv, ic_rd):
        if flush:
            self.state, self.pc = 0, flush_pc
        elif self.state == 0: self.state = 1
        elif self.state == 1 and ic_rv: self.instr, self.state = ic_rd, 2
        elif self.state == 2 and ready: self.pc, self.state = self.pc+4, 1
    
    @property
    def valid(self): return self.state == 2
    @property
    def ic_en(self): return self.state == 1

def decode_instr(valid, pc, instr):
    if not valid: return DecodePkt()
    p = DecodePkt(True, pc, instr)
    op, f3, f7 = instr&0x7F, (instr>>12)&7, (instr>>25)&0x7F
    p.rd, p.rs1, p.rs2 = (instr>>7)&31, (instr>>15)&31, (instr>>20)&31
    
    imm_i = sext(instr>>20, 12)
    imm_s = sext(((instr>>25)<<5)|((instr>>7)&31), 12)
    imm_b = sext(((instr>>31)<<12)|(((instr>>7)&1)<<11)|(((instr>>25)&63)<<5)|(((instr>>8)&15)<<1), 13)
    imm_u = instr & 0xFFFFF000
    imm_j = sext(((instr>>31)<<20)|(((instr>>12)&255)<<12)|(((instr>>20)&1)<<11)|(((instr>>21)&1023)<<1), 21)
    
    if op==0x37: p.fu_type,p.alu_op,p.rd_used,p.imm,p.imm_used = FUType.ALU,ALUOp.LUI,p.rd!=0,imm_u,True
    elif op==0x6F: p.fu_type,p.is_jump,p.rd_used,p.imm,p.imm_used = FUType.BRU,True,p.rd!=0,imm_j,True
    elif op==0x13:
        p.fu_type,p.rs1_used,p.rd_used,p.imm,p.imm_used = FUType.ALU,True,p.rd!=0,imm_i,True
        p.alu_op = [ALUOp.ADD,0,0,ALUOp.SLTIU,0,ALUOp.SRA,ALUOp.OR,ALUOp.AND][f3]
    elif op==0x33:
        p.fu_type,p.rs1_used,p.rs2_used,p.rd_used = FUType.ALU,True,True,p.rd!=0
        if f3==0: p.alu_op = ALUOp.SUB if f7==0x20 else ALUOp.ADD
        elif f3==7: p.alu_op = ALUOp.AND
        elif f3==6: p.alu_op = ALUOp.OR
        elif f3==5: p.alu_op = ALUOp.SRA
    elif op==0x03:
        p.fu_type,p.rs1_used,p.rd_used,p.is_load,p.imm,p.imm_used = FUType.LSU,True,p.rd!=0,True,imm_i,True
        p.ls_size, p.unsigned_load = (LSSize.W,False) if f3==2 else (LSSize.B,True)
    elif op==0x23:
        p.fu_type,p.rs1_used,p.rs2_used,p.is_store,p.imm,p.imm_used = FUType.LSU,True,True,True,imm_s,True
        p.ls_size = LSSize.W if f3==2 else LSSize.H
    elif op==0x63: p.fu_type,p.is_branch,p.rs1_used,p.rs2_used,p.imm,p.imm_used = FUType.BRU,True,True,True,imm_b,True
    elif op==0x67: p.fu_type,p.is_jump,p.rs1_used,p.rd_used,p.imm,p.imm_used = FUType.BRU,True,True,p.rd!=0,imm_i,True
    return p

class Core:
    def __init__(self):
        # Storage
        self.rat = list(range(N_ARCH_REGS))
        self.free_map = [i>=N_ARCH_REGS for i in range(N_PHYS_REGS)]
        self.prf = [0]*N_PHYS_REGS
        self.prf_valid = [True]*N_PHYS_REGS
        self.rob = [None]*ROB_DEPTH
        self.rob_head = self.rob_tail = self.rob_count = 0
        self.rs_alu = [None]*RS_DEPTH
        self.rs_bru = [None]*RS_DEPTH
        self.rs_lsu = [None]*RS_DEPTH
        
        # Memory
        self.icache = ICache()
        self.dmem = [0]*1024
        self.dmem_stage = [None, None]  # 2-cycle pipeline
        
        # Frontend
        self.fetch = Fetch()
        
        # Stats
        self.cycle = self.commits = 0
        
        # Recovery
        self.flush = self.recover = False
        self.flush_pc = self.recover_tag = 0
        
        # Checkpoints
        self.ckpt_rat = {}
        self.ckpt_free = {}
        self.ckpt_prf_valid = {}
        self.ckpt_rob_tail = {}
    
    def load_program(self, fname):
        self.icache.load(fname)
    
    def tick(self):
        self.cycle += 1
        
        # === COMMIT (ROB HEAD) ===
        if self.rob_count > 0 and self.rob[self.rob_head] and self.rob[self.rob_head].get('done'):
            entry = self.rob[self.rob_head]
            if entry.get('rd_used') and entry.get('old_prd'):
                self.free_map[entry['old_prd']] = True
            self.rob[self.rob_head] = None
            self.rob_head = (self.rob_head + 1) % ROB_DEPTH
            self.rob_count -= 1
            self.commits += 1
        
        # === EXECUTE ===
        wb_alu = wb_bru = wb_lsu = WBPkt()
        
        # ALU
        for i, e in enumerate(self.rs_alu):
            if e and e.get('ready'):
                src1, src2 = self.prf[e['prs1']], self.prf[e['prs2']]
                res = self._alu_exec(e, src1, src2)
                wb_alu = WBPkt(True, e['rob_tag'], e['prd'], res, e['rd_used'])
                self.rs_alu[i] = None
                break
        
        # BRU
        for i, e in enumerate(self.rs_bru):
            if e and e.get('ready'):
                src1, src2 = self.prf[e['prs1']], self.prf[e['prs2']]
                taken, tgt = self._bru_exec(e, src1, src2)
                data = (e['pc'] + 4) if e.get('is_jump') else 0
                wb_bru = WBPkt(True, e['rob_tag'], e['prd'], data, e['rd_used'])
                if taken:  # Mispredict!
                    self.flush, self.flush_pc, self.recover, self.recover_tag = True, tgt, True, e['rob_tag']
                self.rs_bru[i] = None
                break
        
        # LSU (simplified: instant mem)
        for i, e in enumerate(self.rs_lsu):
            if e and e.get('ready'):
                addr = u32(self.prf[e['prs1']] + e['imm'])
                if e.get('is_load'):
                    data = self._mem_load(addr, e['ls_size'], e.get('unsigned_load'))
                    wb_lsu = WBPkt(True, e['rob_tag'], e['prd'], data, e['rd_used'])
                else:
                    self._mem_store(addr, self.prf[e['prs2']], e['ls_size'])
                    wb_lsu = WBPkt(True, e['rob_tag'], 0, 0, False)
                self.rs_lsu[i] = None
                break
        
        # === WRITEBACK ===
        for wb in [wb_alu, wb_bru, wb_lsu]:
            if wb.valid:
                if wb.rd_used and wb.prd: self.prf[wb.prd], self.prf_valid[wb.prd] = wb.data, True
                for entry in self.rob:
                    if entry and entry['tag'] == wb.rob_tag: entry['done'] = True
        
        # === WAKEUP RS ===
        for rs in [self.rs_alu, self.rs_bru, self.rs_lsu]:
            for e in rs:
                if e:
                    for wb in [wb_alu, wb_bru, wb_lsu]:
                        if wb.valid and wb.rd_used:
                            if e.get('rs1_used') and e['prs1'] == wb.prd: e['prs1_ready'] = True
                            if e.get('rs2_used') and e['prs2'] == wb.prd: e['prs2_ready'] = True
                    e['ready'] = e['prs1_ready'] and e['prs2_ready']
        
        # === RECOVERY ===
        if self.recover:
            self.rat = self.ckpt_rat.get(self.recover_tag, list(range(N_ARCH_REGS)))
            self.free_map = self.ckpt_free.get(self.recover_tag, [i>=N_ARCH_REGS for i in range(N_PHYS_REGS)])
            self.prf_valid = self.ckpt_prf_valid.get(self.recover_tag, [True]*N_PHYS_REGS)
            # Truncate ROB
            tail = self.ckpt_rob_tail.get(self.recover_tag, 0)
            idx = tail
            while idx != self.rob_tail:
                self.rob[idx] = None
                idx = (idx + 1) % ROB_DEPTH
            self.rob_tail = tail
            # Clear RS
            for rs in [self.rs_alu, self.rs_bru, self.rs_lsu]:
                for i in range(len(rs)): rs[i] = None
            self.recover = False
        
        # === DISPATCH ===
        # (Simplified: direct from decode to RS/ROB)
        
        # === RENAME ===
        # (Simplified: integrated with fetch/decode)
        
        # === DECODE ===
        if self.fetch.valid and not self.flush:
            dpkt = decode_instr(True, self.fetch.pc, self.fetch.instr)
            if dpkt.valid and self.rob_count < ROB_DEPTH:
                # Rename
                need_alloc = dpkt.rd_used and dpkt.rd != 0
                if not need_alloc or any(self.free_map[N_ARCH_REGS:]):
                    prs1, prs2 = self.rat[dpkt.rs1], self.rat[dpkt.rs2]
                    old_prd = self.rat[dpkt.rd] if need_alloc else 0
                    prd = self._allocate_preg() if need_alloc else 0
                    if need_alloc: self.rat[dpkt.rd], self.prf_valid[prd] = prd, False
                    
                    # Alloc ROB
                    tag = self.rob_tail
                    self.rob[tag] = {'tag': tag, 'done': False, 'rd_used': need_alloc, 'old_prd': old_prd}
                    self.rob_tail, self.rob_count = (self.rob_tail+1)%ROB_DEPTH, self.rob_count+1
                    
                    # Checkpoint branches
                    if dpkt.is_branch or dpkt.is_jump:
                        self.ckpt_rat[tag] = self.rat[:]
                        self.ckpt_free[tag] = self.free_map[:]
                        self.ckpt_prf_valid[tag] = self.prf_valid[:]
                        self.ckpt_rob_tail[tag] = self.rob_tail
                    
                    # Dispatch to RS
                    prs1_rdy = self.prf_valid[prs1] if dpkt.rs1_used else True
                    prs2_rdy = self.prf_valid[prs2] if dpkt.rs2_used else True
                    entry = {'prs1': prs1, 'prs2': prs2, 'prd': prd, 'rob_tag': tag,
                             'prs1_ready': prs1_rdy, 'prs2_ready': prs2_rdy,
                             'ready': prs1_rdy and prs2_rdy,
                             'rd_used': need_alloc, 'imm': dpkt.imm, 'pc': dpkt.pc, 'instr': dpkt.instr,
                             'alu_op': dpkt.alu_op, 'is_load': dpkt.is_load, 'is_store': dpkt.is_store,
                             'ls_size': dpkt.ls_size, 'unsigned_load': dpkt.unsigned_load,
                             'is_jump': dpkt.is_jump, 'is_branch': dpkt.is_branch,
                             'rs1_used': dpkt.rs1_used, 'rs2_used': dpkt.rs2_used}
                    
                    if dpkt.fu_type == FUType.ALU:
                        for i in range(RS_DEPTH):
                            if not self.rs_alu[i]: self.rs_alu[i] = entry; break
                    elif dpkt.fu_type == FUType.BRU:
                        for i in range(RS_DEPTH):
                            if not self.rs_bru[i]: self.rs_bru[i] = entry; break
                    elif dpkt.fu_type == FUType.LSU:
                        for i in range(RS_DEPTH):
                            if not self.rs_lsu[i]: self.rs_lsu[i] = entry; break
        
        # === FETCH ===
        ready = True  # Simplified backpressure
        self.icache.tick(self.fetch.ic_en, self.fetch.pc)
        self.fetch.tick(self.flush, self.flush_pc, ready, self.icache.rvalid, self.icache.rdata)
        self.flush = False
    
    def _allocate_preg(self):
        for i in range(N_ARCH_REGS, N_PHYS_REGS):
            if self.free_map[i]:
                self.free_map[i] = False
                return i
        return 0
    
    def _alu_exec(self, e, a, b):
        op_b = e['imm'] if e.get('imm') else b
        op = e['alu_op']
        if op == ALUOp.ADD: return u32(a + op_b)
        elif op == ALUOp.SUB: return u32(a - op_b)
        elif op == ALUOp.AND: return a & op_b
        elif op == ALUOp.OR: return a | op_b
        elif op == ALUOp.SRA: return u32(s32(a) >> (op_b & 31))
        elif op == ALUOp.SLTIU: return 1 if a < op_b else 0
        elif op == ALUOp.LUI: return op_b
        return 0
    
    def _bru_exec(self, e, a, b):
        op, f3 = (e['instr']>>0)&0x7F, (e['instr']>>12)&7
        if e.get('is_jump'):
            tgt = (a + e['imm']) & 0xFFFFFFFE if op == 0x67 else u32(e['pc'] + e['imm'])
            return True, tgt
        elif e.get('is_branch'):
            taken = {0: a==b, 1: a!=b, 4: s32(a)<s32(b), 5: s32(a)>=s32(b), 6: a<b, 7: a>=b}.get(f3, False)
            return taken, u32(e['pc'] + e['imm'])
        return False, 0
    
    def _mem_load(self, addr, size, uns):
        word = self.dmem[(addr>>2) % len(self.dmem)]
        off = addr & 3
        if size == LSSize.B:
            byte = (word >> (off*8)) & 0xFF
            return byte if uns else sext(byte, 8)
        elif size == LSSize.H:
            half = (word >> ((off&2)*8)) & 0xFFFF
            return half if uns else sext(half, 16)
        return word
    
    def _mem_store(self, addr, data, size):
        idx, off = (addr>>2) % len(self.dmem), addr & 3
        word = self.dmem[idx]
        if size == LSSize.B:
            mask = 0xFF << (off*8)
            word = (word & ~mask) | ((data & 0xFF) << (off*8))
        elif size == LSSize.H:
            mask = 0xFFFF << ((off&2)*8)
            word = (word & ~mask) | ((data & 0xFFFF) << ((off&2)*8))
        else:
            word = data
        self.dmem[idx] = u32(word)
    
    def get_arch_reg(self, r):
        return self.prf[self.rat[r]]

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <inst_mem.txt> [max_cycles]")
        sys.exit(1)
    
    core = Core()
    core.load_program(sys.argv[1])
    
    max_cyc = int(sys.argv[2]) if len(sys.argv) > 2 else 20000
    for _ in range(max_cyc):
        core.tick()
        if core.cycle % 1000 == 0:
            print(f"Cycle {core.cycle}, Commits {core.commits}")
    
    print(f"\\n{'='*60}")
    print(f"FINAL @ cycle={core.cycle} commits={core.commits}")
    print(f"a0 (x10) = 0x{core.get_arch_reg(10):08x} ({s32(core.get_arch_reg(10))})")
    print(f"a1 (x11) = 0x{core.get_arch_reg(11):08x} ({s32(core.get_arch_reg(11))})")
    print('='*60)
