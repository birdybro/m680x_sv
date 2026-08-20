// SPDX-License-Identifier: MIT
// HD6303R normalized expanded-multiplexed Mode-2 integration.
//
// The Hitachi HD6301V1/HD6303R handbook identifies the HD6303R as the same
// die with mask ROM disabled and states that HD6301V1 information otherwise
// applies. Mode 2 supplies the documented internal register block and 128-byte
// RAM while leaving program memory and all vectors on the external bus.
module hd6303r_mcu (
  input  logic        clk_i,
  input  logic        reset_n_i,
  input  logic        standby_n_i,
  input  logic        clock_enable_i,
  input  logic        nmi_n_i,
  input  logic        irq1_n_i,
  input  logic        standby_power_ok_i,
  input  logic [7:0]  port1_i,
  input  logic [4:0]  port2_i,
  input  logic [7:0]  external_data_i,
  output logic [15:0] external_address_o,
  output logic [7:0]  external_data_o,
  output logic        external_write_o,
  output logic        external_bus_valid_o,
  output logic        external_opcode_fetch_o,
  output logic [7:0]  port1_o,
  output logic [7:0]  port1_oe_o,
  output logic [4:0]  port2_o,
  output logic [4:0]  port2_oe_o,
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
  logic external_bus_valid_internal;
  logic [7:0] port1_oe_internal;
  logic [4:0] port2_oe_internal;
  logic timer_irq_internal;
  logic sci_irq_internal;

  // The HD6303R shares the HD6301V1 E-synchronous standby boundary.
  always_ff @(posedge clk_i or negedge reset_n_i) begin
    if (!reset_n_i) begin
      standby_active <= 1'b0;
    end else if (clock_enable_i) begin
      standby_active <= !standby_n_i;
    end
  end

  assign external_bus_valid_o = external_bus_valid_internal && !standby_active;
  assign port1_oe_o = port1_oe_internal & {8{!standby_active}};
  assign port2_oe_o = port2_oe_internal & {5{!standby_active}};
  assign timer_irq_o = timer_irq_internal && !standby_active;
  assign sci_irq_o = sci_irq_internal && !standby_active;

  // HD6303R Mode 2 has neither on-chip program ROM nor Port 3/4 GPIO.
  /* verilator lint_off PINCONNECTEMPTY */
  mc6801_mcu #(
    .OPERATING_MODE(3'd2),
    .HITACHI_CPU(1'b1),
    .SCI_TRANSFER_FRAMING_ERROR(1'b0),
    .SCI_BIPHASE_SUPPORTED(1'b0),
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
    .port3_i(8'hff),
    .port4_i(8'hff),
    .is3_n_i(1'b1),
    .program_data_i(8'hff),
    .external_data_i(external_data_i),
    .program_address_o(),
    .program_read_o(),
    .external_address_o(external_address_o),
    .external_data_o(external_data_o),
    .external_write_o(external_write_o),
    .external_bus_valid_o(external_bus_valid_internal),
    .external_opcode_fetch_o(external_opcode_fetch_o),
    .port1_o(port1_o),
    .port1_oe_o(port1_oe_internal),
    .port2_o(port2_o),
    .port2_oe_o(port2_oe_internal),
    .port3_o(),
    .port3_oe_o(),
    .port4_o(),
    .port4_oe_o(),
    .os3_n_o(),
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
