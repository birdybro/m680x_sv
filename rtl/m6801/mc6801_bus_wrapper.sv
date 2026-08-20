// SPDX-License-Identifier: MIT
// MC6801 device-oriented four-subphase E/AS bus wrapper.
//
// Motorola MC6801RM(AD2) sections 3.3.1-3.3.5 and 3.4.1-3.4.5,
// especially figures 3-23 and 3-28, define the digital ordering represented
// here. phase_clk_i runs at four times E. The wrapper presents address, AS
// close, E-high data, and E-fall subphases without attempting to encode the
// document's nanosecond setup, hold, skew, pad, or oscillator specifications.
module mc6801_bus_wrapper #(
  parameter logic [2:0]  OPERATING_MODE = 3'd2,
  parameter logic [15:0] INTERNAL_PROGRAM_START = 16'hf800,
  parameter logic [15:0] INTERNAL_PROGRAM_BYTES = 16'd2048
) (
  input  logic        phase_clk_i,
  input  logic        phase_reset_n_i,
  input  logic        reset_n_i,
  input  logic        clock_enable_i,
  input  logic        nmi_n_i,
  input  logic        irq1_n_i,
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
  output logic        opcode_fetch_o,
  output logic        retire_o,
  output logic        illegal_o,
  output logic        undefined_o,
  output logic        waiting_o,
  output logic        interrupt_ack_o,
  output logic [2:0]  operating_mode_o,
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
  logic expanded_multiplexed;
  logic expanded_nonmultiplexed;
  logic single_chip;
  logic [15:0] cycle_address;
  logic cycle_write;
  logic [15:0] pin_address;
  logic pin_write;
  logic [7:0] raw_port3;
  logic [7:0] raw_port3_oe;
  logic [7:0] raw_port4;
  logic [7:0] raw_port4_oe;
  logic raw_os3_n;

  assign device_clock_enable = clock_enable_i &&
    (bus_phase == PHASE_E_FALL);
  assign bus_phase_o = bus_phase;
  assign e_o = phase_reset_n_i && bus_phase[1];
  assign pin_address = waiting_o ? debug_sp_o : cycle_address;
  assign pin_write = waiting_o ? 1'b0 : cycle_write;

  always_ff @(posedge phase_clk_i or negedge phase_reset_n_i) begin
    if (!phase_reset_n_i) begin
      bus_phase <= PHASE_ADDRESS;
    end else if (clock_enable_i) begin
      bus_phase <= bus_phase + 2'd1;
    end
  end

  always_comb begin
    case (operating_mode_o)
      3'd0, 3'd1, 3'd2, 3'd3, 3'd6: begin
        expanded_multiplexed = 1'b1;
        expanded_nonmultiplexed = 1'b0;
        single_chip = 1'b0;
      end
      3'd5: begin
        expanded_multiplexed = 1'b0;
        expanded_nonmultiplexed = 1'b1;
        single_chip = 1'b0;
      end
      default: begin
        expanded_multiplexed = 1'b0;
        expanded_nonmultiplexed = 1'b0;
        single_chip = 1'b1;
      end
    endcase

    port3_o = raw_port3;
    port3_oe_o = raw_port3_oe;
    port4_o = raw_port4;
    port4_oe_o = raw_port4_oe;
    sc1_o = 1'b1;
    sc1_oe_o = !single_chip;
    sc2_o = single_chip ? (!bus_phase[1] || raw_os3_n) : !pin_write;

    if (!reset_n_i) begin
      // The manual specifies high AS/RW/address pull states and a released
      // Port-3 bus during RESET. Pull strength is an electrical integration
      // concern, so only the actively controlled digital pins are stated here.
      port3_oe_o = 8'h00;
      sc1_o = 1'b1;
      sc2_o = 1'b1;
    end else if (expanded_multiplexed) begin
      // AS is transparent/high during PHASE_ADDRESS and closes before E rises.
      // Port 3 then remains released until the documented E-high data phase.
      sc1_o = bus_phase == PHASE_ADDRESS;
      port4_o = pin_address[15:8];
      if (bus_phase == PHASE_ADDRESS) begin
        port3_o = pin_address[7:0];
        port3_oe_o = 8'hff;
      end else if (bus_phase == PHASE_AS_CLOSE) begin
        port3_oe_o = 8'h00;
      end else begin
        port3_o = raw_port3;
        port3_oe_o = waiting_o ? 8'h00 : raw_port3_oe;
      end
    end else if (expanded_nonmultiplexed) begin
      // IOS is the active-low internal decode of 0100-01FF. Port 3 drives
      // write data only during E, including writes to internal locations.
      port4_o = pin_address[7:0];
      sc1_o = !((pin_address >= 16'h0100) &&
                (pin_address <= 16'h01ff));
      if (!bus_phase[1] || waiting_o) port3_oe_o = 8'h00;
    end
  end

  /* verilator lint_off PINCONNECTEMPTY */
  mc6801_mcu #(
    .OPERATING_MODE(OPERATING_MODE),
    .INTERNAL_PROGRAM_START(INTERNAL_PROGRAM_START),
    .INTERNAL_PROGRAM_BYTES(INTERNAL_PROGRAM_BYTES)
  ) device (
    .clk_i(phase_clk_i), .reset_n_i(reset_n_i), .standby_reset_n_i(1'b1),
    .clock_enable_i(device_clock_enable), .nmi_n_i(nmi_n_i),
    .irq1_n_i(irq1_n_i), .standby_power_ok_i(1'b1), .port1_i(port1_i),
    .port2_i(port2_i), .port3_i(port3_i), .port4_i(port4_i),
    .is3_n_i(sc1_i), .program_data_i(program_data_i),
    .external_data_i(port3_i), .program_address_o(program_address_o),
    .program_read_o(program_read_o), .external_address_o(cycle_address),
    .external_data_o(), .external_write_o(cycle_write),
    .external_bus_valid_o(), .external_opcode_fetch_o(), .port1_o(port1_o),
    .port1_oe_o(port1_oe_o), .port2_o(port2_o), .port2_oe_o(port2_oe_o),
    .port3_o(raw_port3), .port3_oe_o(raw_port3_oe), .port4_o(raw_port4),
    .port4_oe_o(raw_port4_oe), .os3_n_o(raw_os3_n), .sci_tx_o(),
    .sci_clock_o(), .timer_irq_o(), .sci_irq_o(),
    .opcode_fetch_o(opcode_fetch_o), .retire_o(retire_o),
    .illegal_o(illegal_o), .undefined_o(undefined_o), .waiting_o(waiting_o),
    .sleeping_o(), .interrupt_ack_o(interrupt_ack_o),
    .operating_mode_o(operating_mode_o), .debug_address_o(debug_address_o),
    .debug_pc_o(debug_pc_o), .debug_sp_o(debug_sp_o), .debug_a_o(debug_a_o),
    .debug_b_o(debug_b_o), .debug_x_o(debug_x_o), .debug_ccr_o(debug_ccr_o),
    .debug_timer_o(), .debug_output_compare_o(), .debug_input_capture_o(),
    .debug_tcsr_o(), .debug_trcsr_o(), .debug_receive_data_o(),
    .debug_opcode_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */
endmodule
