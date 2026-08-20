// SPDX-License-Identifier: MIT
module tb_mc6801_modes;
  import mc6801_peripheral_bus_stub_pkg::*;

  logic clk;
  logic reset_n;
  logic [15:0] program_address [0:9];
  logic program_read [0:9];
  logic [15:0] external_address [0:9];
  logic [7:0] external_data [0:9];
  logic external_write [0:9];
  logic external_valid [0:9];
  logic [7:0] port3_out [0:9];
  logic [7:0] port3_oe [0:9];
  logic [7:0] port4_out [0:9];
  logic [7:0] port4_oe [0:9];
  integer checks;

  generate
    for (genvar mode_index = 0; mode_index < 8; mode_index = mode_index + 1) begin : mode_devices
      /* verilator lint_off PINCONNECTEMPTY */
      mc6801_mcu #(.OPERATING_MODE(mode_index)) device (
        .clk_i(clk), .reset_n_i(reset_n), .standby_reset_n_i(1'b1),
        .clock_enable_i(1'b1), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
        .standby_power_ok_i(1'b1), .port1_i(8'h3c), .port2_i(5'h15),
        .port3_i(8'h69), .port4_i(8'h96), .is3_n_i(1'b1),
        .program_data_i(8'ha5), .external_data_i(8'h5a),
        .program_address_o(program_address[mode_index]),
        .program_read_o(program_read[mode_index]),
        .external_address_o(external_address[mode_index]),
        .external_data_o(external_data[mode_index]),
        .external_write_o(external_write[mode_index]),
        .external_bus_valid_o(external_valid[mode_index]),
        .external_opcode_fetch_o(), .port1_o(), .port1_oe_o(),
        .port2_o(), .port2_oe_o(), .port3_o(port3_out[mode_index]),
        .port3_oe_o(port3_oe[mode_index]), .port4_o(port4_out[mode_index]),
        .port4_oe_o(port4_oe[mode_index]), .os3_n_o(), .sci_tx_o(),
        .sci_clock_o(), .timer_irq_o(), .sci_irq_o(), .opcode_fetch_o(),
        .retire_o(), .illegal_o(), .undefined_o(), .waiting_o(),
        .sleeping_o(), .interrupt_ack_o(), .debug_address_o(), .debug_pc_o(),
        .debug_sp_o(), .debug_a_o(), .debug_b_o(), .debug_x_o(), .debug_ccr_o(),
        .debug_timer_o(), .debug_output_compare_o(), .debug_input_capture_o(),
        .debug_tcsr_o(), .debug_trcsr_o(), .debug_receive_data_o(),
        .debug_opcode_o()
      );
      /* verilator lint_on PINCONNECTEMPTY */
    end
  endgenerate

  // Mode 1R and Mode 6R use two representative documented ROM mask options.
  /* verilator lint_off PINCONNECTEMPTY */
  mc6801_mcu #(.OPERATING_MODE(3'd1), .INTERNAL_PROGRAM_START(16'hd800)) mode1r (
    .clk_i(clk), .reset_n_i(reset_n), .standby_reset_n_i(1'b1),
    .clock_enable_i(1'b1), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
    .standby_power_ok_i(1'b1), .port1_i(8'h3c), .port2_i(5'h15),
    .port3_i(8'h69), .port4_i(8'h96), .is3_n_i(1'b1),
    .program_data_i(8'ha5), .external_data_i(8'h5a),
    .program_address_o(program_address[8]), .program_read_o(program_read[8]),
    .external_address_o(external_address[8]), .external_data_o(external_data[8]),
    .external_write_o(external_write[8]), .external_bus_valid_o(external_valid[8]),
    .external_opcode_fetch_o(), .port1_o(), .port1_oe_o(), .port2_o(),
    .port2_oe_o(), .port3_o(port3_out[8]), .port3_oe_o(port3_oe[8]),
    .port4_o(port4_out[8]), .port4_oe_o(port4_oe[8]), .os3_n_o(),
    .sci_tx_o(), .sci_clock_o(), .timer_irq_o(), .sci_irq_o(),
    .opcode_fetch_o(), .retire_o(), .illegal_o(), .undefined_o(), .waiting_o(),
    .sleeping_o(), .interrupt_ack_o(), .debug_address_o(), .debug_pc_o(),
    .debug_sp_o(), .debug_a_o(), .debug_b_o(), .debug_x_o(), .debug_ccr_o(),
    .debug_timer_o(), .debug_output_compare_o(), .debug_input_capture_o(),
    .debug_tcsr_o(), .debug_trcsr_o(), .debug_receive_data_o(), .debug_opcode_o()
  );

  mc6801_mcu #(.OPERATING_MODE(3'd6), .INTERNAL_PROGRAM_START(16'he800)) mode6r (
    .clk_i(clk), .reset_n_i(reset_n), .standby_reset_n_i(1'b1),
    .clock_enable_i(1'b1), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
    .standby_power_ok_i(1'b1), .port1_i(8'h3c), .port2_i(5'h15),
    .port3_i(8'h69), .port4_i(8'h96), .is3_n_i(1'b1),
    .program_data_i(8'ha5), .external_data_i(8'h5a),
    .program_address_o(program_address[9]), .program_read_o(program_read[9]),
    .external_address_o(external_address[9]), .external_data_o(external_data[9]),
    .external_write_o(external_write[9]), .external_bus_valid_o(external_valid[9]),
    .external_opcode_fetch_o(), .port1_o(), .port1_oe_o(), .port2_o(),
    .port2_oe_o(), .port3_o(port3_out[9]), .port3_oe_o(port3_oe[9]),
    .port4_o(port4_out[9]), .port4_oe_o(port4_oe[9]), .os3_n_o(),
    .sci_tx_o(), .sci_clock_o(), .timer_irq_o(), .sci_irq_o(),
    .opcode_fetch_o(), .retire_o(), .illegal_o(), .undefined_o(), .waiting_o(),
    .sleeping_o(), .interrupt_ack_o(), .debug_address_o(), .debug_pc_o(),
    .debug_sp_o(), .debug_a_o(), .debug_b_o(), .debug_x_o(), .debug_ccr_o(),
    .debug_timer_o(), .debug_output_compare_o(), .debug_input_capture_o(),
    .debug_tcsr_o(), .debug_trcsr_o(), .debug_receive_data_o(), .debug_opcode_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always #5 clk <= ~clk;

  task automatic present(
    input logic [15:0] address_value,
    input logic write_value,
    input logic [7:0] data_value
  );
    begin
      @(negedge clk);
      stub_address = address_value;
      stub_write = write_value;
      stub_data = data_value;
      stub_valid = 1'b1;
      #1;
    end
  endtask

  task automatic advance;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic expect_select(
    input integer device_index,
    input logic expected_external,
    input logic expected_program,
    input string label_value
  );
    begin
      if (external_valid[device_index] != expected_external ||
          program_read[device_index] != expected_program ||
          external_address[device_index] != stub_address ||
          program_address[device_index] != stub_address ||
          external_data[device_index] != stub_data ||
          external_write[device_index] != stub_write) begin
        $fatal(1, "%0s select device=%0d address=%04x external=%0b program=%0b",
               label_value, device_index, stub_address,
               external_valid[device_index], program_read[device_index]);
      end
      checks = checks + 1;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    stub_address = 16'h0000;
    stub_data = 8'h00;
    stub_write = 1'b0;
    stub_valid = 1'b0;
    stub_interrupt_mask = 1'b1;
    checks = 0;

    #1; reset_n = 1'b0;
    advance();
    reset_n = 1'b1;
    advance();

    // Vector-source selection, including Mode 0's two-read exception and the
    // external-vector R options.
    present(16'hfffe, 1'b0, 8'h00);
    expect_select(0, 1'b1, 1'b0, "mode0 reset vector high");
    expect_select(1, 1'b1, 1'b0, "mode1 external vector");
    expect_select(2, 1'b1, 1'b0, "mode2 external vector");
    expect_select(3, 1'b1, 1'b0, "mode3 external vector");
    expect_select(4, 1'b0, 1'b0, "mode4 mirrored RAM vector");
    expect_select(5, 1'b0, 1'b1, "mode5 internal vector");
    expect_select(6, 1'b0, 1'b1, "mode6 internal vector");
    expect_select(7, 1'b0, 1'b1, "mode7 internal vector");
    expect_select(8, 1'b1, 1'b0, "mode1R external vector");
    expect_select(9, 1'b1, 1'b0, "mode6R external vector");
    advance();
    present(16'hffff, 1'b0, 8'h00);
    expect_select(0, 1'b1, 1'b0, "mode0 reset vector low");
    advance();
    present(16'hfffe, 1'b0, 8'h00);
    expect_select(0, 1'b0, 1'b1, "mode0 later internal vector");

    // Register exclusions differ between multiplexed, single-chip, and
    // partial-address modes.
    present(16'h0004, 1'b0, 8'h00);
    for (integer mode_index = 0; mode_index < 4; mode_index = mode_index + 1)
      expect_select(mode_index, 1'b1, 1'b0, "mode0-3 Port3 exclusion");
    expect_select(4, 1'b0, 1'b0, "mode4 Port3 register");
    expect_select(5, 1'b0, 1'b0, "mode5 unselected Port3 address");
    expect_select(6, 1'b1, 1'b0, "mode6 Port3 exclusion");
    expect_select(7, 1'b0, 1'b0, "mode7 Port3 register");

    present(16'h0005, 1'b0, 8'h00);
    for (integer mode_index = 0; mode_index < 4; mode_index = mode_index + 1)
      expect_select(mode_index, 1'b1, 1'b0, "mode0-3 Port4 exclusion");
    for (integer mode_index = 4; mode_index < 8; mode_index = mode_index + 1)
      expect_select(mode_index, 1'b0, 1'b0, "mode4-7 Port4 register");

    // RAM is internal in every mode except Mode 3; Mode 4 mirrors its physical
    // 128 bytes through every page whose low address byte is 80-FF.
    present(16'h0080, 1'b0, 8'h00);
    for (integer mode_index = 0; mode_index < 8; mode_index = mode_index + 1)
      expect_select(mode_index, mode_index == 3, 1'b0, "base RAM window");
    present(16'h1280, 1'b1, 8'ha5);
    advance();
    present(16'h0080, 1'b0, 8'h00);
    if (mode_devices[4].device.core_data_in != 8'ha5)
      $fatal(1, "mode4 RAM mirror 0080=%02x", mode_devices[4].device.core_data_in);
    present(16'hff80, 1'b0, 8'h00);
    if (mode_devices[4].device.core_data_in != 8'ha5)
      $fatal(1, "mode4 RAM mirror ff80=%02x", mode_devices[4].device.core_data_in);
    checks = checks + 2;

    // Normal and relocated mask-ROM windows, plus Mode 5's selected and
    // physically observable but unselected address regions.
    present(16'hf800, 1'b0, 8'h00);
    expect_select(0, 1'b0, 1'b1, "mode0 ROM");
    expect_select(1, 1'b0, 1'b1, "mode1 ROM");
    expect_select(2, 1'b1, 1'b0, "mode2 no ROM");
    expect_select(3, 1'b1, 1'b0, "mode3 no ROM");
    expect_select(4, 1'b0, 1'b0, "mode4 ROM disabled");
    expect_select(5, 1'b0, 1'b1, "mode5 ROM");
    expect_select(6, 1'b0, 1'b1, "mode6 ROM");
    expect_select(7, 1'b0, 1'b1, "mode7 ROM");
    expect_select(8, 1'b1, 1'b0, "mode1R old ROM external");
    expect_select(9, 1'b1, 1'b0, "mode6R old ROM external");
    present(16'hd800, 1'b0, 8'h00);
    expect_select(8, 1'b0, 1'b1, "mode1R relocated ROM");
    present(16'he800, 1'b0, 8'h00);
    expect_select(9, 1'b0, 1'b1, "mode6R relocated ROM");
    present(16'h0100, 1'b0, 8'h00);
    expect_select(5, 1'b1, 1'b0, "mode5 selected window low");
    present(16'h01ff, 1'b0, 8'h00);
    expect_select(5, 1'b1, 1'b0, "mode5 selected window high");
    present(16'h0200, 1'b0, 8'h00);
    expect_select(5, 1'b0, 1'b0, "mode5 unselected read region");
    expect_select(7, 1'b0, 1'b0, "mode7 unusable region");
    if (mode_devices[5].device.core_data_in != 8'h5a)
      $fatal(1, "mode5 unselected read did not sample Port3 data bus");
    checks = checks + 1;

    // Mode 0 alone drives internal read data onto Port 3 during E.
    present(16'h0002, 1'b0, 8'h00);
    if (port3_oe[0] != 8'hff || port3_out[0] != 8'h3c || port3_oe[1] != 8'h00)
      $fatal(1, "mode0 internal read visibility");
    checks = checks + 1;

    // Modes 4 and 7 expose Port 3/4 GPIO. Modes 5 and 6 use the Port 4 DDR to
    // enable low or high address bits instead of GPIO output-latch data.
    present(16'h0004, 1'b1, 8'hff); advance();
    present(16'h0006, 1'b1, 8'h3c); advance();
    present(16'h0005, 1'b1, 8'hf0); advance();
    present(16'h0007, 1'b1, 8'ha5); advance();
    if (port3_oe[4] != 8'hff || port3_out[4] != 8'h3c ||
        port3_oe[7] != 8'hff || port3_out[7] != 8'h3c ||
        port4_oe[4] != 8'hf0 || port4_out[4] != 8'ha5 ||
        port4_oe[7] != 8'hf0 || port4_out[7] != 8'ha5)
      $fatal(1, "mode4/7 GPIO register behavior");
    checks = checks + 1;
    present(16'h01a5, 1'b0, 8'h00);
    if (port4_oe[5] != 8'hf0 || port4_out[5] != 8'ha5 ||
        port4_oe[6] != 8'hf0 || port4_out[6] != 8'h01)
      $fatal(1, "mode5/6 partial address output");
    checks = checks + 1;

    // Setting PCO through the Port 2 data register changes Mode 4 to Mode 5
    // until reset, after which the original hardware-selected mode returns.
    present(16'h0003, 1'b1, 8'h20); advance();
    if (mode_devices[4].device.active_mode != 3'd5)
      $fatal(1, "mode4 did not transition to mode5");
    present(16'h0003, 1'b0, 8'h00);
    if (mode_devices[4].device.core_data_in[7:5] != 3'd5)
      $fatal(1, "mode4 transition not visible in Port2 mode bits");
    present(16'h0100, 1'b0, 8'h00);
    expect_select(4, 1'b1, 1'b0, "transitioned mode5 external window");
    #1; reset_n = 1'b0; #1;
    if (mode_devices[4].device.active_mode != 3'd4)
      $fatal(1, "reset did not restore hardware-selected mode4");
    checks = checks + 3;

    $display("MC6801 MODES PASS: %0d Mode 0-7/1R/6R decode, vector, RAM, ROM, and port checks",
             checks);
    $finish;
  end
endmodule
