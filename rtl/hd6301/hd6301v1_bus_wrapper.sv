// SPDX-License-Identifier: MIT
// HD6301V1 all-mode device-oriented four-subphase bus wrapper.
//
// Hitachi #U07, HD6301V1 sections 2.1, 2.8, 2.10, 2.12 and figures
// 5-1/5-2 define the digital ordering represented here. Modes 0/2/4/6 use
// multiplexed Port 3, Mode 1 has dedicated address pins, Mode 5 has a
// non-multiplexed partial bus, and Mode 7 retains GPIO/strobe roles.
module hd6301v1_bus_wrapper #(
  parameter logic [2:0] OPERATING_MODE = 3'd7
) (
  input  logic        phase_clk_i,
  input  logic        phase_reset_n_i,
  input  logic        reset_n_i,
  input  logic        standby_n_i,
  input  logic        clock_enable_i,
  input  logic        nmi_n_i,
  input  logic        irq1_n_i,
  input  logic        standby_power_ok_i,
  input  logic [7:0]  program_data_i,
  output logic [15:0] program_address_o,
  output logic        program_read_o,
  input  logic [7:0]  port1_i,
  output logic [7:0]  port1_o,
  output logic [7:0]  port1_oe_o,
  input  logic [4:0]  port2_i,
  output logic [4:0]  port2_o,
  output logic [4:0]  port2_oe_o,
  input  logic [7:0]  port3_i,
  output logic [7:0]  port3_o,
  output logic [7:0]  port3_oe_o,
  input  logic [7:0]  port4_i,
  output logic [7:0]  port4_o,
  output logic [7:0]  port4_oe_o,
  input  logic        sc1_i,
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
  logic [1:0] reset_low_e_cycles;
  logic reset_counter_clear;
  logic reset_bus_released;
  logic device_clock_enable;
  logic multiplexed_mode;
  logic mode1_nonmultiplexed;
  logic mode5_nonmultiplexed;
  logic single_chip_mode;
  logic full_upper_address;
  logic [15:0] cycle_address;
  logic [15:0] pin_address;
  logic cycle_write;
  logic pin_write;
  logic [7:0] raw_port1;
  logic [7:0] raw_port1_oe;
  logic [7:0] raw_port3;
  logic [7:0] raw_port3_oe;
  logic [7:0] raw_port4;
  logic [7:0] raw_port4_oe;
  logic raw_os3_n;
  logic os3_active;
  logic os3_reset_n;

  assign multiplexed_mode = (OPERATING_MODE == 3'd0) ||
    (OPERATING_MODE == 3'd2) || (OPERATING_MODE == 3'd4) ||
    (OPERATING_MODE == 3'd6);
  assign mode1_nonmultiplexed = OPERATING_MODE == 3'd1;
  assign mode5_nonmultiplexed = OPERATING_MODE == 3'd5;
  assign single_chip_mode = OPERATING_MODE == 3'd7;
  assign full_upper_address = (OPERATING_MODE == 3'd0) ||
    (OPERATING_MODE == 3'd1) || (OPERATING_MODE == 3'd2) ||
    (OPERATING_MODE == 3'd4);
  assign pin_address = ((sleeping_o || waiting_o) && !single_chip_mode) ?
    16'hffff : cycle_address;
  assign pin_write = (sleeping_o || waiting_o) ? 1'b0 : cycle_write;
  assign device_clock_enable = clock_enable_i &&
    (bus_phase == PHASE_E_FALL);
  assign reset_bus_released = !phase_reset_n_i ||
    (!reset_n_i && (reset_low_e_cycles == 2'd3));
  assign reset_counter_clear = !phase_reset_n_i || reset_n_i;
  assign bus_phase_o = bus_phase;
  assign e_o = phase_reset_n_i && !standby_active_o && bus_phase[1];
  assign os3_reset_n = phase_reset_n_i && reset_n_i;

  always_ff @(posedge phase_clk_i or negedge phase_reset_n_i) begin
    if (!phase_reset_n_i) begin
      bus_phase <= PHASE_ADDRESS;
    end else if (clock_enable_i) begin
      bus_phase <= bus_phase + 2'd1;
    end
  end

  always_ff @(posedge phase_clk_i or negedge os3_reset_n) begin
    if (!os3_reset_n) begin
      os3_active <= 1'b0;
    end else if (clock_enable_i) begin
      if (standby_active_o) begin
        os3_active <= 1'b0;
      end else if (bus_phase == PHASE_AS_CLOSE) begin
        // Figures 5-5/3-11-5 bound OS3 between consecutive E rising edges.
        os3_active <= single_chip_mode && !raw_os3_n;
      end
    end
  end

  always_ff @(posedge phase_clk_i or posedge reset_counter_clear) begin
    if (reset_counter_clear) begin
      reset_low_e_cycles <= 2'd0;
    end else if (clock_enable_i && (bus_phase == PHASE_E_FALL) &&
                 (reset_low_e_cycles != 2'd3)) begin
      reset_low_e_cycles <= reset_low_e_cycles + 2'd1;
    end
  end

  // HD6301V1 samples STBY at an enabled E boundary. Keep a pin-level copy of
  // the MCU state so E and bus ownership change on that same boundary.
  always_ff @(posedge phase_clk_i or negedge reset_n_i) begin
    if (!reset_n_i) begin
      standby_active_o <= 1'b0;
    end else if (device_clock_enable) begin
      standby_active_o <= !standby_n_i;
    end
  end

  always_comb begin
    port1_o = raw_port1;
    port1_oe_o = raw_port1_oe;
    port3_o = raw_port3;
    port3_oe_o = raw_port3_oe;
    port4_o = raw_port4;
    port4_oe_o = raw_port4_oe;
    sc1_o = 1'b1;
    sc1_oe_o = multiplexed_mode || mode5_nonmultiplexed;
    sc2_o = single_chip_mode ? !os3_active : !pin_write;

    if (reset_bus_released || standby_active_o) begin
      port1_oe_o = 8'h00;
      port3_oe_o = 8'h00;
      port4_oe_o = 8'h00;
      sc1_o = 1'b1;
      sc2_o = 1'b1;
    end else if (single_chip_mode) begin
      // Raw Mode-7 GPIO and IS3/OS3 behavior is already produced by the MCU.
      sc1_oe_o = 1'b0;
    end else if (mode1_nonmultiplexed) begin
      port1_o = pin_address[7:0];
      port1_oe_o = 8'hff;
      port4_o = pin_address[15:8];
      port4_oe_o = 8'hff;
      port3_oe_o = (bus_phase[1] && !sleeping_o && !waiting_o) ?
        raw_port3_oe : 8'h00;
      sc1_oe_o = 1'b0;
    end else if (mode5_nonmultiplexed) begin
      port4_o = pin_address[7:0];
      sc1_o = pin_address[15:8] != 8'h01;
      port3_oe_o = (bus_phase[1] && !sleeping_o && !waiting_o) ?
        raw_port3_oe : 8'h00;
    end else if (multiplexed_mode) begin
      sc1_o = bus_phase == PHASE_ADDRESS;
      port4_o = pin_address[15:8];
      if (full_upper_address) port4_oe_o = 8'hff;
      if (bus_phase == PHASE_ADDRESS) begin
        port3_o = pin_address[7:0];
        port3_oe_o = 8'hff;
      end else if (bus_phase == PHASE_AS_CLOSE) begin
        port3_oe_o = 8'h00;
      end else begin
        port3_o = raw_port3;
        port3_oe_o = (sleeping_o || waiting_o) ? 8'h00 : raw_port3_oe;
      end
    end else begin
      // Mode 3 is explicitly not defined for HD6301V1.
      port1_oe_o = 8'h00;
      port3_oe_o = 8'h00;
      port4_oe_o = 8'h00;
      sc1_oe_o = 1'b0;
      sc2_o = 1'b1;
    end
  end

  /* verilator lint_off PINCONNECTEMPTY */
  hd6301v1_mcu #(.OPERATING_MODE(OPERATING_MODE)) device (
    .clk_i(phase_clk_i), .reset_n_i(reset_n_i), .standby_n_i(standby_n_i),
    .clock_enable_i(device_clock_enable), .nmi_n_i(nmi_n_i),
    .irq1_n_i(irq1_n_i), .standby_power_ok_i(standby_power_ok_i),
    .port1_i(port1_i), .port2_i(port2_i), .port3_i(port3_i),
    .port4_i(port4_i), .is3_n_i(sc1_i),
    .program_address_o(program_address_o), .program_read_o(program_read_o),
    .program_data_i(program_data_i), .external_address_o(cycle_address),
    .external_data_o(), .external_write_o(cycle_write),
    .external_bus_valid_o(), .external_opcode_fetch_o(),
    .external_data_i(port3_i), .port1_o(raw_port1),
    .port1_oe_o(raw_port1_oe), .port2_o(port2_o),
    .port2_oe_o(port2_oe_o), .port3_o(raw_port3),
    .port3_oe_o(raw_port3_oe), .port4_o(raw_port4),
    .port4_oe_o(raw_port4_oe), .os3_n_o(raw_os3_n),
    .sci_tx_o(sci_tx_o), .sci_clock_o(sci_clock_o),
    .timer_irq_o(timer_irq_o), .sci_irq_o(sci_irq_o),
    .opcode_fetch_o(opcode_fetch_o), .retire_o(retire_o),
    .illegal_o(illegal_o), .undefined_o(undefined_o),
    .waiting_o(waiting_o), .sleeping_o(sleeping_o),
    .interrupt_ack_o(interrupt_ack_o), .debug_address_o(debug_address_o),
    .debug_pc_o(debug_pc_o), .debug_sp_o(debug_sp_o),
    .debug_a_o(debug_a_o), .debug_b_o(debug_b_o), .debug_x_o(debug_x_o),
    .debug_ccr_o(debug_ccr_o), .debug_timer_o(),
    .debug_output_compare_o(), .debug_input_capture_o(), .debug_tcsr_o(),
    .debug_trcsr_o(), .debug_receive_data_o(), .debug_opcode_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */
endmodule
