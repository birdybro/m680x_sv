// SPDX-License-Identifier: MIT
// Formal-only unconstrained bus source for proving MCU decode invariants.
module m6800_core #(
  parameter logic [1:0] ARCHITECTURE = 2'd0
) (
  input logic clk_i, reset_n_i, clock_enable_i, bus_ready_i, irq_n_i,
  input logic [15:0] irq_vector_i,
  input logic nmi_n_i, instruction_address_error_i,
  input logic [7:0] data_i,
  output logic [15:0] address_o,
  output logic [7:0] data_o,
  output logic write_o, bus_valid_o, opcode_fetch_o, retire_o, illegal_o,
  output logic undefined_o, waiting_o, sleeping_o, interrupt_ack_o,
  output logic [1:0] interrupt_vector_o,
  output logic [7:0] debug_a_o, debug_b_o,
  output logic [15:0] debug_x_o, debug_sp_o, debug_pc_o,
  output logic [5:0] debug_ccr_o,
  output logic [7:0] debug_opcode_o,
  output logic [3:0] debug_instruction_cycles_o
);
  (* anyseq *) logic [15:0] any_address;
  (* anyseq *) logic [7:0] any_data;
  (* anyseq *) logic any_write;
  (* anyseq *) logic any_valid;
  logic unused_inputs;

  always_comb begin
    unused_inputs = ^{ARCHITECTURE, clk_i, reset_n_i, clock_enable_i,
      bus_ready_i, irq_n_i, irq_vector_i, nmi_n_i,
      instruction_address_error_i, data_i};
    address_o = any_address;
    data_o = any_data;
    write_o = any_write;
    bus_valid_o = any_valid;
    opcode_fetch_o = 1'b0 & unused_inputs;
    retire_o = 1'b0;
    illegal_o = 1'b0;
    undefined_o = 1'b0;
    waiting_o = 1'b0;
    sleeping_o = 1'b0;
    interrupt_ack_o = 1'b0;
    interrupt_vector_o = 2'b00;
    debug_a_o = 8'h00;
    debug_b_o = 8'h00;
    debug_x_o = 16'h0000;
    debug_sp_o = 16'h0000;
    debug_pc_o = 16'h0000;
    debug_ccr_o = 6'b010000;
    debug_opcode_o = 8'h00;
    debug_instruction_cycles_o = 4'h0;
  end
endmodule
