//////////////////////////////////////////////////////////////////////////////////
// Module Name: rob
// Description: Reorder Buffer (Phase 4).
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"
`include "checkpoint_types.sv"

module rob #(
  parameter int DEPTH = `ROB_DEPTH
)(
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic                   flush_i,

  input  logic                   recover_i,
  input  logic [ooop_types::ROB_W-1:0] recover_tag_i,

  input  logic                   checkpoint_take_i,
  input  logic [ooop_types::ROB_W-1:0] checkpoint_tag_i,

  // allocate from dispatch
  input  logic                   alloc_valid_i,
  input  ooop_types::rename_pkt_t alloc_pkt_i,
  output logic                   ready_o,

  // done-mark sources
  input  ooop_types::wb_pkt_t     wb_alu_i,
  input  ooop_types::wb_pkt_t     wb_lsu_i,
  input  ooop_types::wb_pkt_t     wb_bru_i,

  // commit -> free list / rename
  output logic                   free_req_o,
  output logic [ooop_types::PREG_W-1:0] free_preg_o,

  // live ROB tags bitmap
  output logic [ooop_types::ROB_DEPTH-1:0] live_tag_o
);

  import ooop_types::*;
  import checkpoint_types::*;

  typedef struct packed {
    logic              valid;
    logic              done;
    logic [ROB_W-1:0]  tag;
    logic              rd_used;
    logic [PREG_W-1:0] old_prd;
  } rob_ent_t;

  rob_ent_t entries[DEPTH];

  logic [ROB_W-1:0] head, tail;
  logic [ROB_W:0]   count;

  rob_ptrs_snapshot_t ckpt_ptrs[DEPTH];
  logic [DEPTH-1:0]   ckpt_pending;

  // NEW: declare these at module scope (Vivado-friendly)
  logic do_commit;
  logic do_alloc;

  assign ready_o = (count < DEPTH);

  function automatic logic wb_hits(input wb_pkt_t wb, input logic [ROB_W-1:0] tag);
    wb_hits = wb.valid && (wb.rob_tag == tag);
  endfunction

  // commit/free logic (combinational)
  always @* begin
    free_req_o  = 1'b0;
    free_preg_o = '0;

    if ((count != 0) && entries[head].valid && entries[head].done) begin
      if (entries[head].rd_used && (entries[head].old_prd != '0)) begin
        free_req_o  = 1'b1;
        free_preg_o = entries[head].old_prd;
      end
    end
  end

  // live tag bitmap
  integer k;
  always @* begin
    live_tag_o = '0;
    for (k = 0; k < DEPTH; k = k + 1)
      if (entries[k].valid)
        live_tag_o[entries[k].tag] = 1'b1;
  end

  integer i, j;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      head <= '0;
      tail <= '0;
      count <= '0;
      ckpt_pending <= '0;
      do_commit <= 1'b0;
      do_alloc  <= 1'b0;
      for (i = 0; i < DEPTH; i++) begin
        entries[i]   <= '0;
        ckpt_ptrs[i] <= '0;
      end

    end else if (recover_i) begin
      logic [ROB_W-1:0] ckpt_tail;
      logic [ROB_W-1:0] idx;

      ckpt_tail = ckpt_ptrs[recover_tag_i].tail;
      idx = ckpt_tail;

      for (j = 0; j < DEPTH; j++) begin
        if (idx == tail) j = DEPTH;
        else begin
          entries[idx] <= '0;
          idx = idx + 1'b1;
        end
      end

      tail         <= ckpt_tail;
      count        <= ckpt_ptrs[recover_tag_i].count;
      ckpt_pending <= '0;
      do_commit    <= 1'b0;
      do_alloc     <= 1'b0;

    end else if (flush_i) begin
      head <= '0;
      tail <= '0;
      count <= '0;
      ckpt_pending <= '0;
      do_commit <= 1'b0;
      do_alloc  <= 1'b0;
      for (i = 0; i < DEPTH; i++)
        entries[i] <= '0;

    end else begin
      // record checkpoint intent
      if (checkpoint_take_i)
        ckpt_pending[checkpoint_tag_i] <= 1'b1;

      // mark done from WB
      for (i = 0; i < DEPTH; i++)
        if (entries[i].valid && !entries[i].done)
          if (wb_hits(wb_alu_i, entries[i].tag) ||
              wb_hits(wb_lsu_i, entries[i].tag) ||
              wb_hits(wb_bru_i, entries[i].tag))
            entries[i].done <= 1'b1;

      // compute actions (still inside always_ff, but no declarations)
      do_commit <= (count != 0) && entries[head].valid && entries[head].done;
      do_alloc  <= alloc_valid_i && ready_o;

      // commit
      if ((count != 0) && entries[head].valid && entries[head].done) begin
        entries[head] <= '0;
        head <= head + 1'b1;
      end

      // allocate
      if (alloc_valid_i && ready_o) begin
        entries[tail].valid   <= 1'b1;
        entries[tail].done    <= 1'b0;
        entries[tail].tag     <= alloc_pkt_i.rob_tag;
        entries[tail].rd_used <= alloc_pkt_i.rd_used;
        entries[tail].old_prd <= alloc_pkt_i.old_prd;

        if (ckpt_pending[alloc_pkt_i.rob_tag]) begin
          ckpt_ptrs[alloc_pkt_i.rob_tag].tail  <= tail + 1'b1;
          ckpt_ptrs[alloc_pkt_i.rob_tag].count <= count + 1'b1;
          ckpt_pending[alloc_pkt_i.rob_tag]    <= 1'b0;
        end

        tail <= tail + 1'b1;
      end

      // correct count update (must be based on current-cycle conditions)
      // NOTE: use the same expressions as above to avoid 1-cycle lag from do_* regs
      unique case ({(alloc_valid_i && ready_o),
                    ((count != 0) && entries[head].valid && entries[head].done)})
        2'b10: count <= count + 1'b1; // alloc only
        2'b01: count <= count - 1'b1; // commit only
        default: count <= count;      // both or neither
      endcase
    end
  end

endmodule
