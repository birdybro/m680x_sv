// SPDX-License-Identifier: MIT
// Verification-only bus source used to exercise MC6801 peripherals without a CPU.
module m6800_core #(
  parameter logic [1:0] ARCHITECTURE = 2'd0
) (
  input  logic        clk_i,
  input  logic        reset_n_i,
  input  logic        clock_enable_i,
  input  logic        bus_ready_i,
  input  logic        irq_n_i,
  input  logic [15:0] irq_vector_i,
  input  logic        nmi_n_i,
  input  logic        instruction_address_error_i,
  input  logic [7:0]  data_i,
  output logic [15:0] address_o,
  output logic [7:0]  data_o,
  output logic        write_o,
  output logic        bus_valid_o,
  output logic        opcode_fetch_o,
  output logic        retire_o,
  output logic        illegal_o,
  output logic        undefined_o,
  output logic        waiting_o,
  output logic        sleeping_o,
  output logic        interrupt_ack_o,
  output logic [1:0]  interrupt_vector_o,
  output logic [7:0]  debug_a_o,
  output logic [7:0]  debug_b_o,
  output logic [15:0] debug_x_o,
  output logic [15:0] debug_sp_o,
  output logic [15:0] debug_pc_o,
  output logic [5:0]  debug_ccr_o,
  output logic [7:0]  debug_opcode_o,
  output logic [3:0]  debug_instruction_cycles_o
);
  import mc6801_peripheral_bus_stub_pkg::*;

  logic unused_inputs;
  always_comb begin
    unused_inputs = ^{ARCHITECTURE, clk_i, reset_n_i, clock_enable_i, bus_ready_i,
      irq_n_i, irq_vector_i, nmi_n_i, instruction_address_error_i, data_i};
    address_o = stub_address;
    data_o = stub_data;
    write_o = stub_write;
    bus_valid_o = stub_valid;
    opcode_fetch_o = (stub_opcode_fetch && stub_valid && !stub_write) |
      (1'b0 & unused_inputs);
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
    debug_ccr_o = {1'b0, stub_interrupt_mask, 4'b0000};
    debug_opcode_o = 8'h00;
    debug_instruction_cycles_o = 4'h0;
  end
endmodule
