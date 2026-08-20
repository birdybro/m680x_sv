// SPDX-License-Identifier: MIT
// HD63701V0 normalized Mode-0/1/2/5/6/7 digital integration.
//
// The 4-KiB EPROM image is supplied by the FPGA integration. PROM mode exposes
// the documented digital 27256-style address, data, CE/OE, and program request;
// voltage magnitude and pulse algorithms remain outside this module. The
// manual contradicts itself about address-error behavior in the
// executable 0040-007F RAM range; this wrapper permits execution throughout
// RAM and confines the low address trap to 0000-003F.
module hd63701v0_mcu #(
  parameter logic [2:0] OPERATING_MODE = 3'd7
) (
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
  input  logic        prom_mode_i,
  input  logic        prom_program_voltage_i,
  output logic [14:0] prom_address_o,
  output logic [7:0]  prom_data_o,
  output logic        prom_data_oe_o,
  output logic [7:0]  prom_program_data_o,
  output logic        prom_program_o,
  output logic [15:0] external_address_o,
  output logic [7:0]  external_data_o,
  output logic        external_write_o,
  output logic        external_bus_valid_o,
  output logic        external_opcode_fetch_o,
  input  logic [7:0]  external_data_i,
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
  localparam logic [14:0] PROM_LAST_ADDRESS = 15'h0fff;
  localparam logic [15:0] MCU_EPROM_BASE = 16'hf000;

  logic program_read_internal;
  logic [15:0] program_address_internal;
  logic external_bus_valid_internal;
  logic external_opcode_fetch_internal;
  logic [7:0] port1_oe_internal;
  logic [4:0] port2_oe_internal;
  logic [7:0] port3_oe_internal;
  logic [7:0] port3_internal;
  logic [7:0] port4_oe_internal;
  logic os3_n_internal;
  logic timer_irq_internal;
  logic sci_irq_internal;
  logic sci_tx_internal;
  logic sci_clock_internal;
  logic opcode_fetch_internal;
  logic retire_internal;
  logic illegal_internal;
  logic undefined_internal;
  logic waiting_internal;
  logic sleeping_internal;
  logic interrupt_ack_internal;
  logic prom_internal_address;
  logic prom_read_select;
  logic prom_verify_select;
  logic device_reset_n;

  // Figure 3-2 maps A14, A13:A10, A9, A8, and A7:A0 to P41, P45:P42,
  // IRQ/A9, P40, and Port 1 respectively. P47 and P46 are active-low CE/OE.
  assign prom_address_o = {port4_i[1], port4_i[5:2], irq1_n_i,
                           port4_i[0], port1_i};
  assign prom_internal_address = prom_address_o <= PROM_LAST_ADDRESS;
  assign prom_read_select = prom_mode_i && !prom_program_voltage_i &&
                            !port4_i[7] && !port4_i[6];
  assign prom_verify_select = prom_mode_i && prom_program_voltage_i &&
                              port4_i[7] && !port4_i[6];
  assign prom_data_o = prom_internal_address ? program_data_i : 8'hff;
  assign prom_data_oe_o = prom_read_select || prom_verify_select;
  assign prom_program_data_o = port3_i;
  assign prom_program_o = prom_mode_i && prom_program_voltage_i &&
                          !port4_i[7] && port4_i[6] &&
                          prom_internal_address;
  assign device_reset_n = reset_n_i && !prom_mode_i;

  // HD63701V0 accepts STBY asynchronously. The normalized boundary models
  // the resulting reset state and high-impedance ports; oscillator start-up
  // delay and standby voltage thresholds remain electrical integration facts.
  assign program_address_o = prom_mode_i ?
    (MCU_EPROM_BASE | {4'h0, prom_address_o[11:0]}) :
    program_address_internal;
  assign program_read_o = prom_mode_i ?
    ((prom_read_select || prom_verify_select) && prom_internal_address) :
    (program_read_internal && standby_n_i);
  assign external_bus_valid_o = external_bus_valid_internal && standby_n_i &&
                                !prom_mode_i;
  assign external_opcode_fetch_o = external_opcode_fetch_internal &&
                                   standby_n_i && !prom_mode_i;
  assign port1_oe_o = port1_oe_internal & {8{standby_n_i && !prom_mode_i}};
  assign port2_oe_o = port2_oe_internal & {5{standby_n_i && !prom_mode_i}};
  assign port3_o = prom_mode_i ? prom_data_o : port3_internal;
  assign port3_oe_o = prom_mode_i ? {8{prom_data_oe_o}} :
    (port3_oe_internal & {8{standby_n_i}});
  assign port4_oe_o = port4_oe_internal & {8{standby_n_i && !prom_mode_i}};
  assign os3_n_o = prom_mode_i || !standby_n_i || os3_n_internal;
  assign timer_irq_o = timer_irq_internal && standby_n_i && !prom_mode_i;
  assign sci_irq_o = sci_irq_internal && standby_n_i && !prom_mode_i;
  assign sci_tx_o = prom_mode_i ? 1'b1 : sci_tx_internal;
  assign sci_clock_o = prom_mode_i ? 1'b0 : sci_clock_internal;
  assign opcode_fetch_o = opcode_fetch_internal && !prom_mode_i;
  assign retire_o = retire_internal && !prom_mode_i;
  assign illegal_o = illegal_internal && !prom_mode_i;
  assign undefined_o = undefined_internal && !prom_mode_i;
  assign waiting_o = waiting_internal && !prom_mode_i;
  assign sleeping_o = sleeping_internal && !prom_mode_i;
  assign interrupt_ack_o = interrupt_ack_internal && !prom_mode_i;

  /* verilator lint_off PINCONNECTEMPTY */
  mc6801_mcu #(
    .OPERATING_MODE(OPERATING_MODE),
    .HITACHI_CPU(1'b1),
    .HD6301_MODE7(1'b1),
    .HITACHI_NEW_MODES(1'b1),
    .HITACHI_ADDRESS_TRAP(1'b1),
    .SCI_TRANSFER_FRAMING_ERROR(1'b1),
    .SCI_BIPHASE_SUPPORTED(1'b0),
    .TIMER_COUNTER_DOUBLE_WRITE(1'b1),
    .TIMER_OVERFLOW_AT_ZERO(1'b1),
    .PORT_DDR_ASYNC_RESET(1'b1),
    .INTERNAL_RAM_START(16'h0040),
    .INTERNAL_RAM_BYTES(16'd192),
    .INTERNAL_PROGRAM_START(16'hf000),
    .INTERNAL_PROGRAM_BYTES(16'd4096),
    .MODE57_ADDRESS_TRAP_LOW_END(16'h003f)
  ) device (
    .clk_i(clk_i), .reset_n_i(device_reset_n),
    .standby_reset_n_i(standby_n_i), .clock_enable_i(clock_enable_i),
    .nmi_n_i(nmi_n_i), .irq1_n_i(irq1_n_i),
    .standby_power_ok_i(standby_power_ok_i), .port1_i(port1_i),
    .port2_i(port2_i), .port3_i(port3_i), .port4_i(port4_i),
    .is3_n_i(is3_n_i), .program_data_i(program_data_i),
    .external_data_i(external_data_i),
    .program_address_o(program_address_internal),
    .program_read_o(program_read_internal),
    .external_address_o(external_address_o),
    .external_data_o(external_data_o), .external_write_o(external_write_o),
    .external_bus_valid_o(external_bus_valid_internal),
    .external_opcode_fetch_o(external_opcode_fetch_internal),
    .port1_o(port1_o),
    .port1_oe_o(port1_oe_internal), .port2_o(port2_o),
    .port2_oe_o(port2_oe_internal), .port3_o(port3_internal),
    .port3_oe_o(port3_oe_internal), .port4_o(port4_o),
    .port4_oe_o(port4_oe_internal), .os3_n_o(os3_n_internal),
    .sci_tx_o(sci_tx_internal), .sci_clock_o(sci_clock_internal),
    .timer_irq_o(timer_irq_internal), .sci_irq_o(sci_irq_internal),
    .opcode_fetch_o(opcode_fetch_internal), .retire_o(retire_internal),
    .illegal_o(illegal_internal), .undefined_o(undefined_internal),
    .waiting_o(waiting_internal), .sleeping_o(sleeping_internal),
    .interrupt_ack_o(interrupt_ack_internal), .operating_mode_o(),
    .debug_address_o(debug_address_o), .debug_pc_o(debug_pc_o),
    .debug_sp_o(debug_sp_o), .debug_a_o(debug_a_o), .debug_b_o(debug_b_o),
    .debug_x_o(debug_x_o), .debug_ccr_o(debug_ccr_o),
    .debug_timer_o(debug_timer_o),
    .debug_output_compare_o(debug_output_compare_o),
    .debug_input_capture_o(debug_input_capture_o), .debug_tcsr_o(debug_tcsr_o),
    .debug_trcsr_o(debug_trcsr_o), .debug_receive_data_o(debug_receive_data_o),
    .debug_opcode_o(debug_opcode_o)
  );
  /* verilator lint_on PINCONNECTEMPTY */
endmodule
