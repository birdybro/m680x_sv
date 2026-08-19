// SPDX-License-Identifier: MIT
module m6800_core_formal #(
  parameter logic [1:0] ARCHITECTURE = 2'd0
);
  (* anyseq *) logic clk;
  logic reset_n;
  logic past_valid = 1'b0;
  (* anyseq *) logic clock_enable;
  (* anyseq *) logic bus_ready;
  (* anyseq *) logic irq_n;
  (* anyseq *) logic nmi_n;
  (* anyseq *) logic instruction_address_error;
  (* anyseq *) logic [7:0] data_in;
  logic [15:0] address;
  logic [7:0] data_out;
  logic write_enable;
  logic bus_valid;
  logic opcode_fetch;
  logic retire;
  logic illegal;
  logic undefined_value;
  logic waiting_state;
  logic sleeping_state;
  logic interrupt_ack;
  logic [1:0] interrupt_vector;
  logic [7:0] debug_a;
  logic [7:0] debug_b;
  logic [15:0] debug_x;
  logic [15:0] debug_sp;
  logic [15:0] debug_pc;
  logic [5:0] debug_ccr;
  logic [7:0] debug_opcode;
  logic [3:0] debug_cycles;

  assign reset_n = past_valid;
  always @(posedge clk) past_valid <= 1'b1;

  m6800_core #(.ARCHITECTURE(ARCHITECTURE)) dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(clock_enable),
    .bus_ready_i(bus_ready), .irq_n_i(irq_n), .nmi_n_i(nmi_n),
    .instruction_address_error_i(instruction_address_error), .data_i(data_in),
    .address_o(address), .data_o(data_out), .write_o(write_enable),
    .bus_valid_o(bus_valid), .opcode_fetch_o(opcode_fetch), .retire_o(retire),
    .illegal_o(illegal), .undefined_o(undefined_value), .waiting_o(waiting_state),
    .sleeping_o(sleeping_state), .interrupt_ack_o(interrupt_ack),
    .interrupt_vector_o(interrupt_vector), .debug_a_o(debug_a), .debug_b_o(debug_b),
    .debug_x_o(debug_x), .debug_sp_o(debug_sp), .debug_pc_o(debug_pc),
    .debug_ccr_o(debug_ccr), .debug_opcode_o(debug_opcode),
    .debug_instruction_cycles_o(debug_cycles)
  );

  always @* begin
    assert (!write_enable || bus_valid);
    assert (!opcode_fetch || (bus_valid && !write_enable));
    assert (!(waiting_state && sleeping_state));
    assert ((interrupt_vector != 2'b11) || (ARCHITECTURE == 2'd2));
  end

  always @(posedge clk) begin
    if (past_valid && $past(past_valid) &&
        (!$past(clock_enable) || ($past(bus_valid) && !$past(bus_ready)))) begin
      assert ({debug_a, debug_b, debug_x, debug_sp, debug_pc, debug_ccr,
               debug_opcode, debug_cycles} ==
              $past({debug_a, debug_b, debug_x, debug_sp, debug_pc, debug_ccr,
                     debug_opcode, debug_cycles}));
      assert ({address, data_out, write_enable, bus_valid, opcode_fetch, retire,
               illegal, undefined_value, waiting_state, sleeping_state,
               interrupt_ack, interrupt_vector} ==
              $past({address, data_out, write_enable, bus_valid, opcode_fetch, retire,
                     illegal, undefined_value, waiting_state, sleeping_state,
                     interrupt_ack, interrupt_vector}));
    end
  end
endmodule
