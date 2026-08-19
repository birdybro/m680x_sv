// SPDX-License-Identifier: MIT
module mc6800_bus_wrapper_formal;
  (* anyseq *) logic clk;
  logic reset_n;
  logic past_valid = 1'b0;
  (* anyseq *) logic clock_enable;
  (* anyseq *) logic irq_n;
  (* anyseq *) logic nmi_n;
  (* anyseq *) logic halt_n;
  (* anyseq *) logic tsc;
  (* anyseq *) logic dbe;
  (* anyseq *) logic [7:0] data_in;
  logic [15:0] address;
  logic address_oe;
  logic [7:0] data_out;
  logic data_oe;
  logic read_not_write;
  logic read_not_write_oe;
  logic vma;
  logic ba;
  logic opcode_fetch;
  logic retire;
  logic illegal;
  logic undefined_value;
  logic waiting_state;
  logic interrupt_ack;
  logic [1:0] interrupt_vector;
  logic halted;
  logic [15:0] debug_pc;
  logic [15:0] debug_sp;
  logic [7:0] debug_a;
  logic [7:0] debug_b;
  logic [15:0] debug_x;
  logic [5:0] debug_ccr;

  assign reset_n = past_valid;
  always @(posedge clk) past_valid <= 1'b1;

  mc6800_bus_wrapper dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(clock_enable),
    .irq_n_i(irq_n), .nmi_n_i(nmi_n), .halt_n_i(halt_n), .tsc_i(tsc),
    .dbe_i(dbe), .data_i(data_in), .address_o(address),
    .address_oe_o(address_oe), .data_o(data_out), .data_oe_o(data_oe),
    .read_not_write_o(read_not_write),
    .read_not_write_oe_o(read_not_write_oe), .vma_o(vma), .ba_o(ba),
    .opcode_fetch_o(opcode_fetch), .retire_o(retire), .illegal_o(illegal),
    .undefined_o(undefined_value), .waiting_o(waiting_state),
    .interrupt_ack_o(interrupt_ack), .interrupt_vector_o(interrupt_vector),
    .halted_o(halted), .debug_pc_o(debug_pc), .debug_sp_o(debug_sp),
    .debug_a_o(debug_a), .debug_b_o(debug_b), .debug_x_o(debug_x),
    .debug_ccr_o(debug_ccr)
  );

  always @* begin
    if (tsc) begin
      assert (!address_oe);
      assert (!read_not_write_oe);
      assert (!vma);
      assert (!ba);
      assert (!data_oe);
    end
    if (ba) begin
      assert (!address_oe);
      assert (!read_not_write_oe);
      assert (!vma);
      assert (!data_oe);
    end
    if (!reset_n) begin
      assert (!vma);
      assert (!ba);
      assert (!data_oe);
    end
    if (!dbe) assert (!data_oe);
    if (data_oe) begin
      assert (vma);
      assert (address_oe);
      assert (read_not_write_oe);
      assert (!read_not_write);
    end
    if (halted && reset_n && !tsc) assert (ba);
    if (waiting_state && reset_n && !tsc) assert (ba);
  end

  always @(posedge clk) begin
    if (past_valid && $past(past_valid) &&
        ($past(tsc) || !$past(clock_enable) || $past(halted))) begin
      assert ({debug_a, debug_b, debug_x, debug_sp, debug_pc, debug_ccr} ==
              $past({debug_a, debug_b, debug_x, debug_sp, debug_pc, debug_ccr}));
    end
  end
endmodule
