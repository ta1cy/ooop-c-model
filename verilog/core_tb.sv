// ===== File: core_tb.sv =====
`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"

module core_tb;

  import ooop_types::*;

  // --------------------------------------------
  // knobs
  // --------------------------------------------
  localparam int MAX_CYCLES       = 300;
  localparam int PRINT_EVERY      = 25;
  localparam int STALL_THRESHOLD  = 200;

  // NEW: write a0/a1 snapshot every N cycles into a separate file
  localparam int A0A1_EVERY       = 1;   // 1 = every cycle, 5/10/25 = lighter

  // if 1: dump full architectural regs (RAT->PRF) every cycle (very heavy)
  localparam bit DUMP_ARCH_EVERY_CYCLE = 1'b1;

  // --------------------------------------------
  // clock / reset
  // --------------------------------------------
  logic clk;
  logic rst_n;

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
  end

  // --------------------------------------------
  // DUT
  // --------------------------------------------
  core_top dut (
    .clk  (clk),
    .rst_n(rst_n)
  );

  // --------------------------------------------
  // log files
  // --------------------------------------------
  integer log_fd;
  integer a0a1_fd; // NEW

// --------------------------------------------
// TB-visible architectural a0 / a1
// --------------------------------------------
logic [31:0] a0_arch, a1_arch;
logic [PREG_W-1:0] a0_preg, a1_preg;
always_comb begin
  a0_preg = dut.rename_u.mt0.rat[10];   // x10 = a0
  a1_preg = dut.rename_u.mt0.rat[11];   // x11 = a1

  a0_arch = dut.prf_u.regs[a0_preg];
  a1_arch = dut.prf_u.regs[a1_preg];
end
    
  task automatic log_open();
    log_fd = $fopen("core_cycle_dump.log", "w");
    if (log_fd == 0) begin
      $display("[tb] ERROR: could not open core_cycle_dump.log");
      $finish;
    end
    $fwrite(log_fd, "=== core per-cycle dump ===\n");

    // NEW: a0/a1 trace file (CSV)
    a0a1_fd = $fopen("a0a1_trace.csv", "w");
    if (a0a1_fd == 0) begin
      $display("[tb] ERROR: could not open a0a1_trace.csv");
      $finish;
    end
    $fwrite(a0a1_fd, "cycle,commits,p_a0,a0_hex,a0_signed,p_a1,a1_hex,a1_signed\n");
  endtask

  task automatic log_close();
    if (log_fd)  $fclose(log_fd);
    if (a0a1_fd) $fclose(a0a1_fd); // NEW
  endtask

  // --------------------------------------------
  // helpers: dump all architectural regs via RAT->PRF
  // --------------------------------------------
  task automatic dump_arch_regs_to_file();
    int r;
    logic [PREG_W-1:0] p;
    logic [31:0]       v;
    begin
      $fwrite(log_fd, "---- ARCH REGS @ cyc=%0d ----\n", cycle_count);

      for (r = 0; r < 32; r = r + 1) begin
        p = dut.rename_u.mt0.rat[r];
        v = dut.prf_u.regs[p];
        if (r == 0) v = 32'h0;

        $fwrite(log_fd, "x%0d(P%0d)=0x%08h%s", r, p, v, ((r % 4) == 3) ? "\n" : "  ");
      end
      $fwrite(log_fd, "\n");
    end
  endtask

  // --------------------------------------------
  // cycle + commit counters
  // --------------------------------------------
  int unsigned cycle_count;
  int unsigned commit_count;
  int unsigned     stall_ctr;

  // --------------------------------------------
  // NEW: periodic a0/a1 trace row
  // --------------------------------------------
  task automatic dump_a0a1_row();
    logic [PREG_W-1:0] p_a0, p_a1;
    logic [31:0]        v_a0, v_a1;
    begin
      p_a0 = dut.rename_u.mt0.rat[10];
      p_a1 = dut.rename_u.mt0.rat[11];

      v_a0 = dut.prf_u.regs[p_a0];
      v_a1 = dut.prf_u.regs[p_a1];

      $fwrite(a0a1_fd, "%0d,%0d,%0d,0x%08h,%0d,%0d,0x%08h,%0d\n",
              cycle_count, commit_count,
              p_a0, v_a0, $signed(v_a0),
              p_a1, v_a1, $signed(v_a1));
    end
  endtask

  // --------------------------------------------
  // SIGNAL MAP (all pulled from dut.* hierarchy)
  // --------------------------------------------
  task automatic dump_cycle_to_file();
    begin
      // --------- top-level recovery / control ----------
      $fwrite(log_fd,
        "C%0d | commit=%0d stall=%0d | flush=%0b flush_pc=0x%08h recover=%0b rtag=%0d | mp=%0b tgt=0x%08h mp_tag=%0d\n",
        cycle_count, commit_count, stall_ctr,
        dut.flush_i, dut.flush_pc_i, dut.recover_i, dut.recover_tag_i,
        dut.bru_mispredict, dut.bru_target_pc, dut.bru_recover_tag
      );

      // --------- icache / fetch ----------
      $fwrite(log_fd,
        "  IC: en=%0b addr=0x%08h rvalid=%0b rdata=0x%08h | FETCH: pc_q=0x%08h out_v=%0b out_pc=0x%08h out_insn=0x%08h req_pend=%0b req_pc=0x%08h ready_in=%0b\n",
        dut.ic_en, dut.ic_addr, dut.ic_rvalid, dut.ic_rdata,
        dut.fetch_u.pc_q, dut.fetch_u.out_valid, dut.fetch_u.out_pc, dut.fetch_u.out_instr,
        dut.fetch_u.req_pending, dut.fetch_u.req_pc, dut.f_ready_raw
      );

      // --------- fetch->decode skid ----------
      $fwrite(log_fd,
        "  F2D: f_valid_raw=%0b f_ready_raw=%0b | skid: valid_out=%0b ready_in=%0b skid_valid=%0b | f_pc=0x%08h f_instr=0x%08h\n",
        dut.f_valid_raw, dut.f_ready_raw,
        dut.f2d_valid, dut.f2d_ready, dut.skid_f2d_u.skid_valid,
        dut.f_pc, dut.f_instr
      );

      // --------- decode + decode->rename skid ----------
      $fwrite(log_fd,
        "  DEC: d_valid_raw=%0b d_ready_raw=%0b | D2R: d_valid=%0b d_ready=%0b skid_valid=%0b\n",
        dut.d_valid_raw, dut.d_ready_raw,
        dut.d_valid, dut.d_ready, dut.skid_d2r_u.skid_valid
      );
      $fwrite(log_fd, "  DEC_PKT: %p\n", dut.d_pkt);

      // --------- rename + rename->dispatch skid ----------
      $fwrite(log_fd,
        "  RENAME: r_valid_raw=%0b r_ready_raw=%0b | R2D: r_valid=%0b r_ready=%0b skid_valid=%0b | tag_ok=%0b rob_tag=%0d | alloc_inval=%0b alloc_preg=%0d | ckpt_take=%0b ckpt_tag=%0d\n",
        dut.r_valid_raw, dut.r_ready_raw,
        dut.r_valid, dut.r_ready, dut.skid_r2d_u.skid_valid,
        dut.tag_ok, dut.rob_tag,
        dut.alloc_inval, dut.alloc_preg,
        dut.checkpoint_take, dut.checkpoint_tag
      );
      $fwrite(log_fd, "  RENAME_PKT: %p\n", dut.r_pkt);
      
      // --------- MAP table state (on rename operations or recovery) ----------
      if (dut.r_valid && dut.r_ready && dut.r_pkt.rd_used) begin
        $fwrite(log_fd, "  MAP_TABLE: x1->P%0d x5->P%0d x6->P%0d x7->P%0d x8->P%0d x10->P%0d x11->P%0d x29->P%0d x30->P%0d\n",
          dut.rename_u.mt0.rat[1],
          dut.rename_u.mt0.rat[5],
          dut.rename_u.mt0.rat[6],
          dut.rename_u.mt0.rat[7],
          dut.rename_u.mt0.rat[8],
          dut.rename_u.mt0.rat[10],
          dut.rename_u.mt0.rat[11],
          dut.rename_u.mt0.rat[29],
          dut.rename_u.mt0.rat[30]
        );
      end

      // --------- dispatch + fifo ----------
      $fwrite(log_fd,
        "  DISP: in_v=%0b in_r=%0b | fifo: full=%0b out_v=%0b out_r=%0b | rs_ready: alu=%0b bru=%0b lsu=%0b | rob_ready=%0b | rob_alloc_v=%0b\n",
        dut.r_valid, dut.r_ready,
        dut.dispatch_u.fifo_u.full, dut.dispatch_u.f_out_valid, dut.dispatch_u.f_out_ready,
        dut.rs_alu_ready, dut.rs_bru_ready, dut.rs_lsu_ready,
        dut.rob_ready,
        dut.rob_alloc_v
      );
      $fwrite(log_fd, "  ROB_ALLOC_PKT: %p\n", dut.rob_alloc_pkt);

      // --------- RS inserts ----------
      $fwrite(log_fd,
        "  RS_INS: alu_v=%0b tag=%0d prs1=%0d(%0b) prs2=%0d(%0b) prd=%0d rd_used=%0b | bru_v=%0b tag=%0d prs1=%0d(%0b) prs2=%0d(%0b) prd=%0d rd_used=%0b | lsu_v=%0b tag=%0d prs1=%0d(%0b) prs2=%0d(%0b) prd=%0d rd_used=%0b\n",
        dut.rs_alu_ins_v, dut.rs_alu_ins_e.rob_tag, dut.rs_alu_ins_e.prs1, dut.rs_alu_ins_e.prs1_ready, dut.rs_alu_ins_e.prs2, dut.rs_alu_ins_e.prs2_ready, dut.rs_alu_ins_e.prd, dut.rs_alu_ins_e.rd_used,
        dut.rs_bru_ins_v, dut.rs_bru_ins_e.rob_tag, dut.rs_bru_ins_e.prs1, dut.rs_bru_ins_e.prs1_ready, dut.rs_bru_ins_e.prs2, dut.rs_bru_ins_e.prs2_ready, dut.rs_bru_ins_e.prd, dut.rs_bru_ins_e.rd_used,
        dut.rs_lsu_ins_v, dut.rs_lsu_ins_e.rob_tag, dut.rs_lsu_ins_e.prs1, dut.rs_lsu_ins_e.prs1_ready, dut.rs_lsu_ins_e.prs2, dut.rs_lsu_ins_e.prs2_ready, dut.rs_lsu_ins_e.prd, dut.rs_lsu_ins_e.rd_used
      );

      // --------- RS issue outputs + top-level single-issue select ----------
      $fwrite(log_fd,
        "  RS_ISS: alu_issue_v=%0b tag=%0d | bru_issue_v=%0b tag=%0d | lsu_issue_v=%0b tag=%0d | sel: iss_alu=%0b iss_bru=%0b iss_lsu=%0b sel_tag=%0d\n",
        dut.alu_issue_v, dut.alu_issue_e.rob_tag,
        dut.bru_issue_v, dut.bru_issue_e.rob_tag,
        dut.lsu_issue_v, dut.lsu_issue_e.rob_tag,
        dut.iss_alu, dut.iss_bru, dut.iss_lsu, dut.iss_e.rob_tag
      );
      $fwrite(log_fd, "  ISSUE_ENTRY: %p\n", dut.iss_e);

     // --------- PRF reads + valid summary ----------
      $fwrite(log_fd,
        "  PRF: raddr1=%0d rdata1=0x%08h | raddr2=%0d rdata2=0x%08h | prf_v[P0]=%0b prf_v[P32]=%0b\n",
        dut.prf_raddr1, dut.prf_rdata1,
        dut.prf_raddr2, dut.prf_rdata2,
        dut.prf_valid[0],
        dut.prf_valid[32]
      );
      
      // --------- PRF valid bits for recently written registers ----------
      if (dut.wb_alu.valid) begin
        if (dut.wb_alu.rd_used) begin
          $fwrite(log_fd, "  PRF_VALID_UPDATES: ALU(P%0d->%0b)\n", dut.wb_alu.prd, dut.prf_valid[dut.wb_alu.prd]);
        end
      end
      if (dut.wb_bru.valid) begin
        if (dut.wb_bru.rd_used) begin
          $fwrite(log_fd, "  PRF_VALID_UPDATES: BRU(P%0d->%0b)\n", dut.wb_bru.prd, dut.prf_valid[dut.wb_bru.prd]);
        end
      end
      if (dut.wb_lsu.valid) begin
        if (dut.wb_lsu.rd_used) begin
          $fwrite(log_fd, "  PRF_VALID_UPDATES: LSU(P%0d->%0b)\n", dut.wb_lsu.prd, dut.prf_valid[dut.wb_lsu.prd]);
        end
      end
      if (dut.alloc_inval) begin
        $fwrite(log_fd, "  PRF_VALID_UPDATES: ALLOC(P%0d->0)\n", dut.alloc_preg);
      end
      
      // --------- PRF valid bits during recovery (checking for invalid ready bits) ----------
      if (dut.recover_i) begin
        $fwrite(log_fd, "  PRF_VALID_SUMMARY: ");
        for (int p = 32; p < 64; p++) begin
          if (!dut.prf_valid[p]) begin
            $fwrite(log_fd, "P%0d=0 ", p);
          end
        end
        $fwrite(log_fd, "\n");
      end
      
      if ((cycle_count >= 5) && (cycle_count <= 7)) begin
        $fwrite(log_fd,
          "  *** P32 PROBE (C5-7): prf_valid[32]=%0b | wb_alu.valid=%0b wb_alu.prd=%0d wb_alu.rob_tag=%0d | r_alloc_inval=%0b alloc_preg=%0d\n",
          dut.prf_valid[32],
          dut.wb_alu.valid, dut.wb_alu.prd, dut.wb_alu.rob_tag,
          dut.alloc_inval, dut.alloc_preg
        );
      end

      // --------- FU outputs (WB packets) ----------
      $fwrite(log_fd, "  WB_ALU: %p\n", dut.wb_alu);
      $fwrite(log_fd, "  WB_BRU: %p\n", dut.wb_bru);
      $fwrite(log_fd, "  WB_LSU: %p\n", dut.wb_lsu);

      // --------- DMEM interface ----------
      $fwrite(log_fd,
        "  DMEM: en=%0b we=%0b addr=0x%08h wdata=0x%08h size=%0d | rvalid=%0b rdata=0x%08h\n",
        dut.dmem_en, dut.dmem_we, dut.dmem_addr, dut.dmem_wdata, dut.dmem_size,
        dut.dmem_rvalid, dut.dmem_rdata
      );

      // --------- ROB internal pointers/state (hierarchical) ----------
      $fwrite(log_fd,
        "  ROB: head=%0d tail=%0d count=%0d | commit_fire=%0b commit_o=%0b free_req=%0b free_preg=%0d | live_tag=0x%0h\n",
        dut.rob_u.head, dut.rob_u.tail, dut.rob_u.count,
        dut.rob_u.commit_fire, dut.rob_commit, dut.free_req, dut.free_preg,
        dut.rob_live_tag
      );

      // optional: dump head entry details (if valid)
      if (dut.rob_u.count != 0 && dut.rob_u.entries[dut.rob_u.head].valid) begin
        $fwrite(log_fd,
          "  ROB_HEAD: valid=%0b done=%0b tag=%0d rd_used=%0b old_prd=%0d\n",
          dut.rob_u.entries[dut.rob_u.head].valid,
          dut.rob_u.entries[dut.rob_u.head].done,
          dut.rob_u.entries[dut.rob_u.head].tag,
          dut.rob_u.entries[dut.rob_u.head].rd_used,
          dut.rob_u.entries[dut.rob_u.head].old_prd
        );
      end

      // --------- RECOVERY STATE DUMP (if recovering) ----------
      if (dut.recover_i) begin
        $fwrite(log_fd,
          "  *** RECOVERY TAG=%0d *** ROB_CKPT: head=%0d tail=%0d count=%0d | ckpt_pending=0x%0h\n",
          dut.recover_tag_i,
          dut.rob_u.ckpt_ptrs[dut.recover_tag_i].head,
          dut.rob_u.ckpt_ptrs[dut.recover_tag_i].tail,
          dut.rob_u.ckpt_ptrs[dut.recover_tag_i].count,
          dut.rob_u.ckpt_pending
        );
        
        // RAT checkpoint restoration
        $fwrite(log_fd, "  RAT_CKPT_RESTORE[%0d]: ", dut.recover_tag_i);
        for (int r = 0; r < 8; r++) begin
          $fwrite(log_fd, "x%0d->P%0d ", r, dut.rename_u.mt0.ckpt_rat[dut.recover_tag_i][r]);
        end
        $fwrite(log_fd, "... x28->P%0d x29->P%0d x30->P%0d x31->P%0d\n",
          dut.rename_u.mt0.ckpt_rat[dut.recover_tag_i][28],
          dut.rename_u.mt0.ckpt_rat[dut.recover_tag_i][29],
          dut.rename_u.mt0.ckpt_rat[dut.recover_tag_i][30],
          dut.rename_u.mt0.ckpt_rat[dut.recover_tag_i][31]
        );
        
        // Current RAT state before recovery
        $fwrite(log_fd, "  RAT_CURRENT (pre-recover): ");
        for (int r = 0; r < 8; r++) begin
          $fwrite(log_fd, "x%0d->P%0d ", r, dut.rename_u.mt0.rat[r]);
        end
        $fwrite(log_fd, "... x28->P%0d x29->P%0d x30->P%0d x31->P%0d\n",
          dut.rename_u.mt0.rat[28],
          dut.rename_u.mt0.rat[29],
          dut.rename_u.mt0.rat[30],
          dut.rename_u.mt0.rat[31]
        );
        
        // Free list checkpoint state (bitmap)
        $fwrite(log_fd, "  FREE_LIST_CKPT[%0d]: bitmap=0x%0h has_free=%0b\n",
          dut.recover_tag_i,
          dut.rename_u.fl0.ckpt_free_map[dut.recover_tag_i],
          dut.rename_u.fl0.has_free_o
        );
        
        $fwrite(log_fd, "  FREE_LIST_CURRENT (pre-recover): bitmap=0x%0h has_free=%0b\n",
          dut.rename_u.fl0.free_map,
          dut.rename_u.fl0.has_free_o
        );
      end

      // --------- ROB all entries (when count > 0 and near deadlock) ----------
      if (dut.rob_u.count > 12) begin
        $fwrite(log_fd, "  ROB_ENTRIES:");
        for (int idx = 0; idx < 16; idx++) begin
          if (dut.rob_u.entries[idx].valid) begin
            $fwrite(log_fd, " [%0d:v=%0b,d=%0b,t=%0d]",
              idx,
              dut.rob_u.entries[idx].valid,
              dut.rob_u.entries[idx].done,
              dut.rob_u.entries[idx].tag
            );
          end
        end
        $fwrite(log_fd, "\n");
      end

      // --------- RS internal hold state (useful for deadlock) ----------
      $fwrite(log_fd,
        "  RS_HOLD: alu(hold=%0b idx=%0d) bru(hold=%0b idx=%0d) lsu(hold=%0b idx=%0d)\n",
        dut.rs_alu_u.hold_valid_q, dut.rs_alu_u.hold_idx_q,
        dut.rs_bru_u.hold_valid_q, dut.rs_bru_u.hold_idx_q,
        dut.rs_lsu_u.hold_valid_q, dut.rs_lsu_u.hold_idx_q
      );

      // --------- RS detailed entries (when near full or recovering) ----------
      if (dut.rob_u.count > 12) begin
        $fwrite(log_fd, "  RS_ALU_ENTRIES:");
        for (int idx = 0; idx < 8; idx++) begin
          if (dut.rs_alu_u.entries[idx].valid) begin
            $fwrite(log_fd, " [%0d:t=%0d,r=%0b,p1r=%0b,p2r=%0b]",
              idx,
              dut.rs_alu_u.entries[idx].rob_tag,
              dut.rs_alu_u.ready_mask[idx],
              dut.rs_alu_u.entries[idx].prs1_ready,
              dut.rs_alu_u.entries[idx].prs2_ready
            );
          end
        end
        $fwrite(log_fd, "\n");

        $fwrite(log_fd, "  RS_BRU_ENTRIES:");
        for (int idx = 0; idx < 8; idx++) begin
          if (dut.rs_bru_u.entries[idx].valid) begin
            $fwrite(log_fd, " [%0d:t=%0d,r=%0b,p1r=%0b,p2r=%0b,isj=%0b]",
              idx,
              dut.rs_bru_u.entries[idx].rob_tag,
              dut.rs_bru_u.ready_mask[idx],
              dut.rs_bru_u.entries[idx].prs1_ready,
              dut.rs_bru_u.entries[idx].prs2_ready,
              dut.rs_bru_u.entries[idx].is_jalr
            );
          end
        end
        $fwrite(log_fd, "\n");

        $fwrite(log_fd, "  RS_LSU_ENTRIES:");
        for (int idx = 0; idx < 8; idx++) begin
          if (dut.rs_lsu_u.entries[idx].valid) begin
            $fwrite(log_fd, " [%0d:t=%0d,r=%0b,ld=%0b,st=%0b]",
              idx,
              dut.rs_lsu_u.entries[idx].rob_tag,
              dut.rs_lsu_u.ready_mask[idx],
              dut.rs_lsu_u.entries[idx].is_load,
              dut.rs_lsu_u.entries[idx].is_store
            );
          end
        end
        $fwrite(log_fd, "\n");
      end
      
      // --------- Branch FU debug (when branch/jump executing) ----------
      if (dut.bru_issue_v) begin
        $fwrite(log_fd,
          "  BRU_EXEC: pc=0x%08h isj=%0b isjr=%0b isbr=%0b src1=0x%08h src2=0x%08h imm=0x%08h\n",
          dut.bru_issue_e.pc,
          dut.bru_issue_e.is_jump,
          dut.bru_issue_e.is_jalr,
          dut.bru_issue_e.is_branch,
          dut.prf_rdata1,
          dut.prf_rdata2,
          dut.bru_issue_e.imm
        );
        $fwrite(log_fd,
          "  BRU_RESULT: calc_tgt=0x%08h mp=%0b mp_tgt=0x%08h mp_tag=%0d\n",
          dut.branch_fu_u.target_pc,
          dut.bru_mispredict,
          dut.bru_target_pc,
          dut.bru_recover_tag
        );
      end
      
      // --------- Pipeline stage valid/ready during flush ----------
      if (dut.flush_i) begin
        $fwrite(log_fd,
          "  PIPE_FLUSH: fetch_v=%0b dec_v=%0b ren_v=%0b disp_v=%0b f2d_v=%0b d2r_v=%0b r2d_v=%0b\n",
          dut.fetch_u.out_valid,
          dut.d_valid_raw,
          dut.r_valid_raw,
          dut.r_valid,
          dut.f2d_valid,
          dut.d_valid,
          dut.r_valid
        );
      end

      // optional: massive dump of arch regs
      if (DUMP_ARCH_EVERY_CYCLE) begin
        dump_arch_regs_to_file();
      end

      $fwrite(log_fd, "\n");
    end
  endtask

  // --------------------------------------------
  // helper: dump final a0/a1 from RAT -> PRF
  // --------------------------------------------
  task automatic dump_a0a1();
    logic [PREG_W-1:0] p_a0, p_a1;
    logic [31:0]        v_a0, v_a1;
    begin
      p_a0 = dut.rename_u.mt0.rat[10];
      p_a1 = dut.rename_u.mt0.rat[11];

      v_a0 = dut.prf_u.regs[p_a0];
      v_a1 = dut.prf_u.regs[p_a1];

      $display("============================================================");
      $display("[tb] FINAL @ cycle=%0d commits=%0d", cycle_count, commit_count);
      $display("[tb] a0(x10) -> P%0d = 0x%08h (%0d)", p_a0, v_a0, $signed(v_a0));
      $display("[tb] a1(x11) -> P%0d = 0x%08h (%0d)", p_a1, v_a1, $signed(v_a1));
      $display("============================================================");
    end
  endtask

  // --------------------------------------------
  // main cycle accounting + per-cycle printing
  // --------------------------------------------
  initial begin
    log_open();
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cycle_count  <= 0;
      commit_count <= 0;
      stall_ctr    <= 0;
    end else begin
      cycle_count <= cycle_count + 1;

      if (dut.rob_commit) begin
        commit_count <= commit_count + 1;
        stall_ctr    <= 0;
      end else begin
        if (stall_ctr != 32'hFFFF_FFFF)
          stall_ctr <= stall_ctr + 1;
      end

      // PER-CYCLE FULL DUMP (to file)
      dump_cycle_to_file();

      // NEW: lightweight a0/a1 snapshot every N cycles
      if ((cycle_count % A0A1_EVERY) == 0) begin
        dump_a0a1_row();
      end

      // console heartbeat
      if ((cycle_count % PRINT_EVERY) == 0) begin
        $display("[tb] cyc=%0d commits=%0d stall_ctr=%0d ic_en=%0d ic_addr=0x%08h ic_rvalid=%0d flush=%0d recover=%0d",
                 cycle_count, commit_count, stall_ctr,
                 dut.ic_en, dut.ic_addr, dut.ic_rvalid,
                 dut.flush_i, dut.recover_i);
      end
    end
  end

  // --------------------------------------------
  // stop conditions
  // --------------------------------------------
  always_ff @(posedge clk) begin
    if (rst_n) begin
      if (stall_ctr >= STALL_THRESHOLD) begin
        $display("\n[tb] STOP: no commits for %0d cycles (stall threshold hit).", STALL_THRESHOLD);
        dump_a0a1();
        log_close();
        $finish;
      end

      if (cycle_count >= MAX_CYCLES) begin
        $display("\n[tb] STOP: hit MAX_CYCLES=%0d.", MAX_CYCLES);
        dump_a0a1();
        log_close();
        $finish;
      end
    end
  end

  final begin
    log_close();
  end

endmodule
