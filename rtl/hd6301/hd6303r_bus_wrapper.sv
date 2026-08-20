// SPDX-License-Identifier: MIT
// HD6303R device-oriented four-subphase expanded-bus wrapper.
//
// Hitachi #U07, HD6301V1/HD6303R sections 2.1, 2.4, 2.8, 2.12 and
// figures 5-1/5-2 define the digital ordering represented here. Mode 1 has
// dedicated address and data pins; Modes 2 and 4 multiplex A0-A7/D0-D7 on
// Port 3. Nanosecond, pad, oscillator, and reset-entry delay characteristics
// remain outside this subphase abstraction.
module hd6303r_bus_wrapper #(
  parameter logic [2:0] OPERATING_MODE = 3'd2
) (
  input  logic        phase_clk_i,
  input  logic        phase_reset_n_i,
  input  logic        reset_n_i,
  input  logic        standby_n_i,
  input  logic        clock_enable_i,
  input  logic        nmi_n_i,
  input  logic        irq1_n_i,
  input  logic        standby_power_ok_i,
  input  logic [7:0]  port1_i,
  output logic [7:0]  port1_o,
  output logic [7:0]  port1_oe_o,
  input  logic [4:0]  port2_i,
  output logic [4:0]  port2_o,
  output logic [4:0]  port2_oe_o,
  input  logic [7:0]  port3_i,
  output logic [7:0]  port3_o,
  output logic [7:0]  port3_oe_o,
  output logic [7:0]  port4_o,
  output logic [7:0]  port4_oe_o,
  output logic        sc1_o,
  output logic        sc1_oe_o,
  output logic        sc2_o,
  output logic        e_o,
  output logic [1:0]  bus_phase_o,
  output logic        standby_active_o,
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
  output logic [5:0]  debug_ccr_o
);
  localparam logic [1:0] PHASE_ADDRESS = 2'd0;
  localparam logic [1:0] PHASE_AS_CLOSE = 2'd1;
  localparam logic [1:0] PHASE_E_FALL = 2'd3;

  logic [1:0] bus_phase;
  logic device_clock_enable;
  logic multiplexed_mode;
  logic mode1_nonmultiplexed;
  logic [15:0] cycle_address;
  logic [7:0] cycle_data;
  logic cycle_write;
  logic [15:0] pin_address;
  logic pin_write;
  logic [7:0] raw_port1;
  logic [7:0] raw_port1_oe;

  assign multiplexed_mode = (OPERATING_MODE == 3'd2) ||
    (OPERATING_MODE == 3'd4);
  assign mode1_nonmultiplexed = OPERATING_MODE == 3'd1;
  // HD6301V1/HD6303R table 2-12-1 keeps E active in SLP while forcing the
  // expanded buses to the idle read state: address FFFF and R/W high.
  assign pin_address = sleeping_o ? 16'hffff : cycle_address;
  assign pin_write = sleeping_o ? 1'b0 : cycle_write;
  assign device_clock_enable = clock_enable_i &&
    (bus_phase == PHASE_E_FALL);
  assign bus_phase_o = bus_phase;
  assign e_o = phase_reset_n_i && !standby_active_o && bus_phase[1];

  always_ff @(posedge phase_clk_i or negedge phase_reset_n_i) begin
    if (!phase_reset_n_i) begin
      bus_phase <= PHASE_ADDRESS;
    end else if (clock_enable_i) begin
      bus_phase <= bus_phase + 2'd1;
    end
  end

  always_comb begin
    port1_o = raw_port1;
    port1_oe_o = raw_port1_oe;
    port3_o = cycle_data;
    port3_oe_o = 8'h00;
    port4_o = pin_address[15:8];
    port4_oe_o = 8'hff;
    sc1_o = 1'b1;
    sc1_oe_o = multiplexed_mode;
    sc2_o = !pin_write;

    if (!reset_n_i || standby_active_o) begin
      port1_oe_o = 8'h00;
      port3_oe_o = 8'h00;
      port4_oe_o = 8'h00;
      sc1_o = 1'b1;
      sc2_o = 1'b1;
    end else if (mode1_nonmultiplexed) begin
      port1_o = pin_address[7:0];
      port1_oe_o = 8'hff;
      if (bus_phase[1] && pin_write) port3_oe_o = 8'hff;
    end else if (multiplexed_mode) begin
      sc1_o = bus_phase == PHASE_ADDRESS;
      if (bus_phase == PHASE_ADDRESS) begin
        port3_o = pin_address[7:0];
        port3_oe_o = 8'hff;
      end else if (bus_phase == PHASE_AS_CLOSE) begin
        port3_oe_o = 8'h00;
      end else if (pin_write) begin
        port3_oe_o = 8'hff;
      end
    end else begin
      // The HD6303R mask option makes every other hardware mode unavailable.
      port1_oe_o = 8'h00;
      port3_oe_o = 8'h00;
      port4_oe_o = 8'h00;
      sc1_oe_o = 1'b0;
      sc2_o = 1'b1;
    end
  end

  /* verilator lint_off PINCONNECTEMPTY */
  hd6303r_mcu #(.OPERATING_MODE(OPERATING_MODE)) device (
    .clk_i(phase_clk_i), .reset_n_i(reset_n_i), .standby_n_i(standby_n_i),
    .clock_enable_i(device_clock_enable), .nmi_n_i(nmi_n_i),
    .irq1_n_i(irq1_n_i), .standby_power_ok_i(standby_power_ok_i),
    .port1_i(port1_i), .port2_i(port2_i), .external_data_i(port3_i),
    .external_address_o(cycle_address), .external_data_o(cycle_data),
    .external_write_o(cycle_write), .external_bus_valid_o(),
    .external_opcode_fetch_o(),
    .port1_o(raw_port1), .port1_oe_o(raw_port1_oe), .port2_o(port2_o),
    .port2_oe_o(port2_oe_o), .sci_tx_o(sci_tx_o),
    .sci_clock_o(sci_clock_o), .timer_irq_o(timer_irq_o),
    .sci_irq_o(sci_irq_o), .opcode_fetch_o(opcode_fetch_o),
    .retire_o(retire_o), .illegal_o(illegal_o), .undefined_o(undefined_o),
    .waiting_o(waiting_o), .sleeping_o(sleeping_o),
    .interrupt_ack_o(interrupt_ack_o), .standby_active_o(standby_active_o),
    .debug_address_o(debug_address_o), .debug_pc_o(debug_pc_o),
    .debug_sp_o(debug_sp_o), .debug_a_o(debug_a_o), .debug_b_o(debug_b_o),
    .debug_x_o(debug_x_o), .debug_ccr_o(debug_ccr_o), .debug_timer_o(),
    .debug_output_compare_o(), .debug_input_capture_o(), .debug_tcsr_o(),
    .debug_trcsr_o(), .debug_receive_data_o(), .debug_opcode_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */
endmodule
