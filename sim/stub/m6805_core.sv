// SPDX-License-Identifier: MIT
// Verification-only bus source used to exercise HD63705V0 peripherals.
module m6805_core #(
  parameter logic        HITACHI_PROFILE = 1'b0,
  parameter logic [15:0] PC_MASK = 16'hffff,
  parameter logic [15:0] STACK_BASE = 16'h0060,
  parameter logic [15:0] STACK_MASK = 16'h001f,
  parameter logic [15:0] STACK_TOP = 16'h007f,
  parameter logic [15:0] SWI_VECTOR = 16'hfffc,
  parameter logic [15:0] RESET_VECTOR = 16'hfffe
) (
  input  logic        clk_i,
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic        reset_n_i,
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic        clock_enable_i,
  input  logic        bus_ready_i,
  input  logic        irq_n_i,
  input  logic        interrupt_pin_n_i,
  input  logic [15:0] irq_vector_i,
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
  output logic        stopped_o,
  output logic        interrupt_ack_o,
  output logic [7:0]  debug_a_o,
  output logic [7:0]  debug_x_o,
  output logic [15:0] debug_sp_o,
  output logic [15:0] debug_pc_o,
  output logic [4:0]  debug_ccr_o,
  output logic [7:0]  debug_opcode_o,
  output logic [3:0]  debug_instruction_cycles_o
);
  import hd63705_peripheral_bus_stub_pkg::*;

  logic unused_inputs;
  always_comb begin
    unused_inputs = ^{HITACHI_PROFILE, PC_MASK, STACK_BASE, STACK_MASK, STACK_TOP,
      SWI_VECTOR, RESET_VECTOR, clk_i, clock_enable_i, bus_ready_i,
      irq_n_i, interrupt_pin_n_i, irq_vector_i, data_i};
    address_o = stub_address;
    data_o = stub_data;
    write_o = stub_write;
    bus_valid_o = stub_valid;
    opcode_fetch_o = 1'b0 & unused_inputs;
    retire_o = 1'b0;
    illegal_o = 1'b0;
    undefined_o = 1'b0;
    waiting_o = stub_waiting;
    stopped_o = stub_stopped;
    interrupt_ack_o = 1'b0;
    debug_a_o = 8'h00;
    debug_x_o = 8'h00;
    debug_sp_o = 16'h00ff;
    debug_pc_o = 16'h0000;
    debug_ccr_o = {1'b0, stub_interrupt_mask, 3'b000};
    debug_opcode_o = 8'h00;
    debug_instruction_cycles_o = 4'h0;
  end
endmodule
