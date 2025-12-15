//////////////////////////////////////////////////////////////////////////////////
// Module Name: fetch
// Description: fetch stage. fetches one instruction at a time from icache.
// Additional Comments:
//   - uses ready/valid handshake
//   - flush_i redirects PC and drops in-flight output
//////////////////////////////////////////////////////////////////////////////////

module fetch (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        flush_i,
  input  logic [31:0] flush_pc_i,

  input  logic        ready_in,
  output logic        valid_out,
  output logic [31:0] pc_out,
  output logic [31:0] instr_out,

  // icache interface
  output logic        icache_en_o,
  output logic [31:0] icache_addr_o,
  input  logic [31:0] icache_rdata_i,
  input  logic        icache_rvalid_i
);

  typedef enum logic [1:0] {S_IDLE, S_REQ, S_HAVE} state_t;
  state_t state;

  logic [31:0] pc_q;
  logic [31:0] instr_q;

  always @(posedge clk) begin
    if (!rst_n) begin
      state   <= S_IDLE;
      pc_q    <= 32'h0000_0000;
      instr_q <= 32'h0000_0013;
    end else begin
      if (flush_i) begin
        state <= S_IDLE;
        pc_q  <= flush_pc_i;
      end else begin
        case (state)
          S_IDLE: begin
            state <= S_REQ;
          end

          S_REQ: begin
            if (icache_rvalid_i) begin
              instr_q <= icache_rdata_i;
              state   <= S_HAVE;
            end
          end

          S_HAVE: begin
            if (ready_in) begin
              pc_q  <= pc_q + 32'd4;
              state <= S_REQ;
            end
          end

          default: state <= S_IDLE;
        endcase
      end
    end
  end

  assign icache_en_o   = (state == S_REQ);
  assign icache_addr_o = pc_q;

  assign valid_out = (state == S_HAVE);
  assign pc_out    = pc_q;
  assign instr_out = instr_q;

endmodule
