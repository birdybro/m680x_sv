// SPDX-License-Identifier: MIT
module tb_hd63701v0_modes;
  import mc6801_peripheral_bus_stub_pkg::*;

  logic clk;
  logic reset_n;
  logic [15:0] external_address [0:5];
  logic [7:0] external_data [0:5];
  logic external_write [0:5];
  logic external_valid [0:5];
  logic [15:0] program_address [0:5];
  logic program_read [0:5];
  logic [7:0] port1_out [0:5];
  logic [7:0] port1_oe [0:5];
  logic [7:0] port4_out [0:5];
  logic [7:0] port4_oe [0:5];
  logic address_error [0:5];
  integer checks;

  generate
    for (genvar device_index = 0; device_index < 6; device_index = device_index + 1) begin : mode_devices
      localparam logic [2:0] DEVICE_MODE =
        (device_index == 0) ? 3'd0 :
        (device_index == 1) ? 3'd1 :
        (device_index == 2) ? 3'd2 :
        (device_index == 3) ? 3'd5 :
        (device_index == 4) ? 3'd6 : 3'd7;
      /* verilator lint_off PINCONNECTEMPTY */
      hd63701v0_mcu #(.OPERATING_MODE(DEVICE_MODE)) dut (
        .clk_i(clk), .reset_n_i(reset_n), .standby_n_i(1'b1),
        .clock_enable_i(1'b1), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
        .standby_power_ok_i(1'b1), .port1_i(8'h3c), .port2_i(5'h1f),
        .port3_i(8'hc3), .port4_i(8'h5a), .is3_n_i(1'b1),
        .program_address_o(program_address[device_index]),
        .program_read_o(program_read[device_index]), .program_data_i(8'ha5),
        .external_address_o(external_address[device_index]),
        .external_data_o(external_data[device_index]),
        .external_write_o(external_write[device_index]),
        .external_bus_valid_o(external_valid[device_index]),
        .external_opcode_fetch_o(), .external_data_i(8'h5a),
        .port1_o(port1_out[device_index]), .port1_oe_o(port1_oe[device_index]),
        .port2_o(), .port2_oe_o(), .port3_o(), .port3_oe_o(),
        .port4_o(port4_out[device_index]), .port4_oe_o(port4_oe[device_index]),
        .os3_n_o(), .sci_tx_o(), .sci_clock_o(), .timer_irq_o(), .sci_irq_o(),
        .opcode_fetch_o(), .retire_o(), .illegal_o(), .undefined_o(),
        .waiting_o(), .sleeping_o(), .interrupt_ack_o(), .debug_address_o(),
        .debug_pc_o(), .debug_sp_o(), .debug_a_o(), .debug_b_o(),
        .debug_x_o(), .debug_ccr_o(), .debug_timer_o(),
        .debug_output_compare_o(), .debug_input_capture_o(), .debug_tcsr_o(),
        .debug_trcsr_o(), .debug_receive_data_o(), .debug_opcode_o()
      );
      assign address_error[device_index] = dut.device.instruction_address_error;
      /* verilator lint_on PINCONNECTEMPTY */
    end
  endgenerate

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

  task automatic expect_source(
    input integer device_index,
    input logic expected_external,
    input logic expected_program,
    input string label_value
  );
    begin
      if ((external_valid[device_index] !== expected_external) ||
          (program_read[device_index] !== expected_program) ||
          (external_address[device_index] !== stub_address) ||
          (program_address[device_index] !== stub_address) ||
          (external_data[device_index] !== stub_data) ||
          (external_write[device_index] !== stub_write)) begin
        $fatal(1, "%0s device=%0d address=%04x external=%0b program=%0b",
               label_value, device_index, stub_address,
               external_valid[device_index], program_read[device_index]);
      end
      checks = checks + 1;
    end
  endtask

  task automatic expect_address_error(
    input integer device_index,
    input logic expected,
    input string label_value
  );
    begin
      if (address_error[device_index] !== expected) begin
        $fatal(1, "%0s device=%0d address=%04x address_error=%0b",
               label_value, device_index, stub_address,
               address_error[device_index]);
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
    stub_opcode_fetch = 1'b0;
    stub_interrupt_mask = 1'b1;
    checks = 0;

    #1; reset_n = 1'b0;
    advance();
    reset_n = 1'b1;
    advance();
    if ((mode_devices[0].dut.device.active_mode !== 3'd0) ||
        (mode_devices[1].dut.device.active_mode !== 3'd1) ||
        (mode_devices[2].dut.device.active_mode !== 3'd2) ||
        (mode_devices[3].dut.device.active_mode !== 3'd5) ||
        (mode_devices[4].dut.device.active_mode !== 3'd6) ||
        (mode_devices[5].dut.device.active_mode !== 3'd7)) begin
      $fatal(1, "HD63701V0 legal mode did not latch at reset");
    end
    checks = checks + 6;

    present(16'hfffe, 1'b0, 8'h00);
    for (integer index = 0; index < 6; index = index + 1)
      expect_source(index, index <= 2, index >= 3, "reset vector high");
    present(16'hffff, 1'b0, 8'h00);
    for (integer index = 0; index < 6; index = index + 1)
      expect_source(index, index <= 2, index >= 3, "reset vector low");
    advance();
    if (external_valid[0] || !program_read[0])
      $fatal(1, "HD63701V0 Mode-0 reset-vector handoff");
    checks = checks + 1;

    present(16'hf000, 1'b0, 8'h00);
    for (integer index = 0; index < 6; index = index + 1)
      expect_source(index, (index == 1) || (index == 2),
                    (index == 0) || (index >= 3), "EPROM selection");

    present(16'h0040, 1'b0, 8'h00);
    for (integer index = 0; index < 6; index = index + 1)
      expect_source(index, 1'b0, 1'b0, "internal RAM base");

    present(16'h0000, 1'b0, 8'h00);
    for (integer index = 0; index < 6; index = index + 1)
      expect_source(index, index == 1, 1'b0, "Mode-1 Port-1 exclusion");

    present(16'h0004, 1'b0, 8'h00);
    for (integer index = 0; index < 6; index = index + 1)
      expect_source(index, (index <= 2) || (index == 4), 1'b0,
                    "Port-3 register map");

    present(16'h0005, 1'b0, 8'h00);
    for (integer index = 0; index < 6; index = index + 1)
      expect_source(index, index <= 2, 1'b0, "Port-4 register map");

    present(16'h0100, 1'b0, 8'h00);
    for (integer index = 0; index < 6; index = index + 1)
      expect_source(index, index < 5, 1'b0, "partial external window");

    present(16'h0200, 1'b0, 8'h00);
    for (integer index = 0; index < 6; index = index + 1)
      expect_source(index, (index <= 2) || (index == 4), 1'b0,
                    "expanded external space");

    present(16'ha55a, 1'b0, 8'h00);
    if ((port1_out[1] !== 8'h5a) || (port1_oe[1] !== 8'hff))
      $fatal(1, "HD63701V0 Mode-1 lower-address function");
    for (integer index = 0; index < 3; index = index + 1) begin
      if ((port4_out[index] !== 8'ha5) || (port4_oe[index] !== 8'hff))
        $fatal(1, "HD63701V0 full-address Port-4 function device=%0d", index);
    end
    checks = checks + 4;

    stub_opcode_fetch = 1'b1;
    present(16'h001f, 1'b0, 8'h00);
    for (integer index = 0; index < 6; index = index + 1)
      expect_address_error(index, 1'b1, "register-window instruction fetch");
    present(16'h0020, 1'b0, 8'h00);
    for (integer index = 0; index < 6; index = index + 1)
      expect_address_error(index, (index == 3) || (index == 5),
                           "low non-memory instruction fetch");
    present(16'h0040, 1'b0, 8'h00);
    for (integer index = 0; index < 6; index = index + 1)
      expect_address_error(index, 1'b0, "physical RAM instruction fetch");
    present(16'h0100, 1'b0, 8'h00);
    for (integer index = 0; index < 6; index = index + 1)
      expect_address_error(index, index == 5,
                           "Mode-7 non-memory instruction fetch");
    present(16'h0200, 1'b0, 8'h00);
    for (integer index = 0; index < 6; index = index + 1)
      expect_address_error(index, (index == 3) || (index == 5),
                           "partial-decode instruction fetch");
    stub_opcode_fetch = 1'b0;

    $display("HD63701V0 MODES PASS: %0d legal-mode EPROM, RAM, register, bus, and TRAP checks",
             checks);
    $finish;
  end
endmodule
