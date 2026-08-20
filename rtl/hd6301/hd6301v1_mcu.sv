// SPDX-License-Identifier: MIT
// HD6301V1 normalized single-chip Mode-7 digital integration.
//
// The 4-KiB mask-ROM image is an FPGA integration input rather than part of
// this clean-room core. program_read_o selects documented F000-FFFF accesses;
// RAM, registers, GPIO, timer, SCI, strobes, and TRAP decode remain internal.
module hd6301v1_mcu (
  input  logic        clk_i,
  input  logic        reset_n_i,
  input  logic        standby_n_i,
  input  logic        clock_enable_i,
  input  logic        nmi_n_i,
  input  logic        irq1_n_i,
  input  logic        standby_power_ok_i,
  input  logic [7:0]  port1_i,
  input  logic [4:0]  port2_i,
  input  logic [7:0]  port3_i,
  input  logic [7:0]  port4_i,
  input  logic        is3_n_i,
  output logic [15:0] program_address_o,
  output logic        program_read_o,
  input  logic [7:0]  program_data_i,
  output logic [7:0]  port1_o,
  output logic [7:0]  port1_oe_o,
  output logic [4:0]  port2_o,
  output logic [4:0]  port2_oe_o,
  output logic [7:0]  port3_o,
  output logic [7:0]  port3_oe_o,
  output logic [7:0]  port4_o,
  output logic [7:0]  port4_oe_o,
  output logic        os3_n_o,
  output logic        sci_tx_o,
  output logic        sci_clock_o,
  output logic        timer_irq_o,
  output logic        sci_irq_o,
  output logic        opcode_fetch_o,
  output logic        retire_o,
  output logic        illegal_o,
  output logic        undefined_o,
  output logic        waiting_o,
  output logic        sleeping_o,
  output logic        interrupt_ack_o,
  output logic [15:0] debug_address_o,
  output logic [15:0] debug_pc_o,
  output logic [15:0] debug_sp_o,
  output logic [7:0]  debug_a_o,
  output logic [7:0]  debug_b_o,
  output logic [15:0] debug_x_o,
  output logic [5:0]  debug_ccr_o,
  output logic [15:0] debug_timer_o,
  output logic [15:0] debug_output_compare_o,
  output logic [15:0] debug_input_capture_o,
  output logic [7:0]  debug_tcsr_o,
  output logic [7:0]  debug_trcsr_o,
  output logic [7:0]  debug_receive_data_o,
  output logic [7:0]  debug_opcode_o
);
  logic standby_active;
  logic program_read_internal;
  logic [7:0] port1_oe_internal;
  logic [4:0] port2_oe_internal;
  logic [7:0] port3_oe_internal;
  logic [7:0] port4_oe_internal;
  logic os3_n_internal;
  logic timer_irq_internal;
  logic sci_irq_internal;

  // HD6301V1 samples STBY synchronously with E. Once accepted, the device
  // remains in reset state until a later enabled E boundary samples STBY high.
  always_ff @(posedge clk_i or negedge reset_n_i) begin
    if (!reset_n_i) begin
      standby_active <= 1'b0;
    end else if (clock_enable_i) begin
      standby_active <= !standby_n_i;
    end
  end

  assign program_read_o = program_read_internal && !standby_active;
  assign port1_oe_o = port1_oe_internal & {8{!standby_active}};
  assign port2_oe_o = port2_oe_internal & {5{!standby_active}};
  assign port3_oe_o = port3_oe_internal & {8{!standby_active}};
  assign port4_oe_o = port4_oe_internal & {8{!standby_active}};
  assign os3_n_o = standby_active || os3_n_internal;
  assign timer_irq_o = timer_irq_internal && !standby_active;
  assign sci_irq_o = sci_irq_internal && !standby_active;

  // Mode 7 has no external memory bus; these common integration outputs are
  // intentionally left unconnected at this device-specific boundary.
  /* verilator lint_off PINCONNECTEMPTY */
  mc6801_mcu #(
    .OPERATING_MODE(3'd7),
    .HITACHI_CPU(1'b1),
    .HD6301_MODE7(1'b1),
    .SCI_TRANSFER_FRAMING_ERROR(1'b0),
    .TIMER_COUNTER_DOUBLE_WRITE(1'b1),
    .TIMER_OVERFLOW_AT_ZERO(1'b1),
    .PORT_DDR_ASYNC_RESET(1'b0)
  ) device (
    .clk_i(clk_i),
    .reset_n_i(reset_n_i),
    .standby_reset_n_i(!standby_active),
    .clock_enable_i(clock_enable_i),
    .nmi_n_i(nmi_n_i),
    .irq1_n_i(irq1_n_i),
    .standby_power_ok_i(standby_power_ok_i),
    .port1_i(port1_i),
    .port2_i(port2_i),
    .port3_i(port3_i),
    .port4_i(port4_i),
    .is3_n_i(is3_n_i),
    .program_data_i(program_data_i),
    .external_data_i(8'hff),
    .program_address_o(program_address_o),
    .program_read_o(program_read_internal),
    .external_address_o(),
    .external_data_o(),
    .external_write_o(),
    .external_bus_valid_o(),
    .external_opcode_fetch_o(),
    .port1_o(port1_o),
    .port1_oe_o(port1_oe_internal),
    .port2_o(port2_o),
    .port2_oe_o(port2_oe_internal),
    .port3_o(port3_o),
    .port3_oe_o(port3_oe_internal),
    .port4_o(port4_o),
    .port4_oe_o(port4_oe_internal),
    .os3_n_o(os3_n_internal),
    .sci_tx_o(sci_tx_o),
    .sci_clock_o(sci_clock_o),
    .timer_irq_o(timer_irq_internal),
    .sci_irq_o(sci_irq_internal),
    .opcode_fetch_o(opcode_fetch_o),
    .retire_o(retire_o),
    .illegal_o(illegal_o),
    .undefined_o(undefined_o),
    .waiting_o(waiting_o),
    .sleeping_o(sleeping_o),
    .interrupt_ack_o(interrupt_ack_o),
    .debug_address_o(debug_address_o),
    .debug_pc_o(debug_pc_o),
    .debug_sp_o(debug_sp_o),
    .debug_a_o(debug_a_o),
    .debug_b_o(debug_b_o),
    .debug_x_o(debug_x_o),
    .debug_ccr_o(debug_ccr_o),
    .debug_timer_o(debug_timer_o),
    .debug_output_compare_o(debug_output_compare_o),
    .debug_input_capture_o(debug_input_capture_o),
    .debug_tcsr_o(debug_tcsr_o),
    .debug_trcsr_o(debug_trcsr_o),
    .debug_receive_data_o(debug_receive_data_o),
    .debug_opcode_o(debug_opcode_o)
  );
  /* verilator lint_on PINCONNECTEMPTY */
endmodule
