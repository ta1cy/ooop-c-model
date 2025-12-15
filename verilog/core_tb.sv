`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"

module core_tb;

  import ooop_types::*;

  // --------------------------------------------
  // knobs
  // --------------------------------------------
  localparam int MAX_CYCLES       = 20000;
  localparam int PRINT_EVERY      = 25;
  localparam int STALL_THRESHOLD  = 200;   // cycles with zero commits -> declare "done/stuck"

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
  // cycle + commit counters
  // --------------------------------------------
  longint unsigned cycle_count;
  longint unsigned commit_count;
  int unsigned     stall_ctr;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cycle_count  <= 0;
      commit_count <= 0;
      stall_ctr    <= 0;
    end else begin
      cycle_count <= cycle_count + 1;

      // ROB commit proxy: core_top exposes free_req/free_preg from ROB
      if (dut.free_req) begin
        commit_count <= commit_count + 1;
        stall_ctr    <= 0;
      end else begin
        if (stall_ctr != 32'hFFFF_FFFF)
          stall_ctr <= stall_ctr + 1;
      end

      // lightweight heartbeat
      if ((cycle_count % PRINT_EVERY) == 0) begin
        $display("[tb] cyc=%0d commits=%0d stall_ctr=%0d ic_en=%0d ic_addr=0x%08h ic_rvalid=%0d flush=%0d recover=%0d",
                 cycle_count, commit_count, stall_ctr,
                 dut.ic_en, dut.ic_addr, dut.ic_rvalid,
                 dut.flush_i, dut.recover_i);
      end
    end
  end

  // --------------------------------------------
  // helper: dump final a0/a1 from RAT -> PRF
  // --------------------------------------------
  task automatic dump_a0a1();
    logic [PREG_W-1:0] p_a0, p_a1;
    logic [31:0]        v_a0, v_a1;
    begin
      // ---- RAT read (arch->phys) ----
      // If your map_table uses a different array name than "rat", change "rat" here.
      p_a0 = dut.rename_u.mt0.rat[10]; // x10 = a0
      p_a1 = dut.rename_u.mt0.rat[11]; // x11 = a1

      // ---- PRF read (phys->value) ----
      // If your prf uses a different array name than "regs", change "regs" here.
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
  // stop conditions
  // --------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      // nothing
    end else begin
      if (stall_ctr >= STALL_THRESHOLD) begin
        $display("\n[tb] STOP: no commits for %0d cycles (stall threshold hit).", STALL_THRESHOLD);
        dump_a0a1();
        $finish;
      end

      if (cycle_count >= MAX_CYCLES) begin
        $display("\n[tb] STOP: hit MAX_CYCLES=%0d.", MAX_CYCLES);
        dump_a0a1();
        $finish;
      end
    end
  end

endmodule
