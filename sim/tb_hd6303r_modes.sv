// SPDX-License-Identifier: MIT
module tb_hd6303r_modes;
  import mc6801_peripheral_bus_stub_pkg::*;

  logic clk;
  logic reset_n;
  logic [15:0] external_address [0:2];
  logic [7:0] external_data [0:2];
  logic external_write [0:2];
  logic external_valid [0:2];
  logic [7:0] port1_out [0:2];
  logic [7:0] port1_oe [0:2];
  integer checks;

  generate
    for (genvar device_index = 0; device_index < 3; device_index = device_index + 1) begin : mode_devices
      localparam logic [2:0] DEVICE_MODE =
        (device_index == 0) ? 3'd1 : ((device_index == 1) ? 3'd2 : 3'd4);
      /* verilator lint_off PINCONNECTEMPTY */
      hd6303r_mcu #(.OPERATING_MODE(DEVICE_MODE)) dut (
        .clk_i(clk), .reset_n_i(reset_n), .standby_n_i(1'b1),
        .clock_enable_i(1'b1), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
        .standby_power_ok_i(1'b1), .port1_i(8'h3c), .port2_i(5'h1f),
        .external_data_i(8'h5a), .external_address_o(external_address[device_index]),
        .external_data_o(external_data[device_index]),
        .external_write_o(external_write[device_index]),
        .external_bus_valid_o(external_valid[device_index]),
        .external_opcode_fetch_o(), .port1_o(port1_out[device_index]),
        .port1_oe_o(port1_oe[device_index]), .port2_o(), .port2_oe_o(),
        .sci_tx_o(), .sci_clock_o(), .timer_irq_o(), .sci_irq_o(),
        .opcode_fetch_o(), .retire_o(), .illegal_o(), .undefined_o(),
        .waiting_o(), .sleeping_o(), .interrupt_ack_o(), .debug_address_o(),
        .debug_pc_o(), .debug_sp_o(), .debug_a_o(), .debug_b_o(),
        .debug_x_o(), .debug_ccr_o(), .debug_timer_o(),
        .debug_output_compare_o(), .debug_input_capture_o(), .debug_tcsr_o(),
        .debug_trcsr_o(), .debug_receive_data_o(), .debug_opcode_o()
      );
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

  task automatic expect_external(
    input integer device_index,
    input logic expected,
    input string label_value
  );
    begin
      if ((external_valid[device_index] !== expected) ||
          (external_address[device_index] !== stub_address) ||
          (external_data[device_index] !== stub_data) ||
          (external_write[device_index] !== stub_write)) begin
        $fatal(1, "%0s device=%0d address=%04x external=%0b",
               label_value, device_index, stub_address,
               external_valid[device_index]);
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
    if ((mode_devices[0].dut.device.active_mode !== 3'd1) ||
        (mode_devices[1].dut.device.active_mode !== 3'd2) ||
        (mode_devices[2].dut.device.active_mode !== 3'd4)) begin
      $fatal(1, "HD6303R legal mode did not latch at reset");
    end
    checks = checks + 3;

    present(16'hfffe, 1'b0, 8'h00);
    for (integer index = 0; index < 3; index = index + 1)
      expect_external(index, 1'b1, "external reset vector");

    // New non-multiplexed Mode 1 turns the Port 1 registers into external
    // memory locations. Modes 2 and 4 retain those internal registers.
    present(16'h0000, 1'b0, 8'h00);
    expect_external(0, 1'b1, "Mode 1 P1DDR exclusion");
    expect_external(1, 1'b0, "Mode 2 P1DDR");
    expect_external(2, 1'b0, "Mode 4 P1DDR");
    present(16'h0002, 1'b0, 8'h00);
    expect_external(0, 1'b1, "Mode 1 PORT1 exclusion");
    expect_external(1, 1'b0, "Mode 2 PORT1");
    expect_external(2, 1'b0, "Mode 4 PORT1");

    // Port 3/4 registers are external bus locations in every legal HD6303R
    // expanded configuration.
    for (integer address_index = 0; address_index < 5; address_index = address_index + 1) begin
      case (address_index)
        0: present(16'h0004, 1'b0, 8'h00);
        1: present(16'h0005, 1'b0, 8'h00);
        2: present(16'h0006, 1'b0, 8'h00);
        3: present(16'h0007, 1'b0, 8'h00);
        default: present(16'h000f, 1'b0, 8'h00);
      endcase
      for (integer index = 0; index < 3; index = index + 1)
        expect_external(index, 1'b1, "expanded port-register exclusion");
    end

    present(16'h0080, 1'b0, 8'h00);
    for (integer index = 0; index < 3; index = index + 1)
      expect_external(index, 1'b0, "internal RAM base");
    present(16'h1280, 1'b0, 8'h00);
    for (integer index = 0; index < 3; index = index + 1)
      expect_external(index, 1'b1, "no Motorola Mode-4 RAM mirror");
    present(16'hf800, 1'b0, 8'h00);
    for (integer index = 0; index < 3; index = index + 1)
      expect_external(index, 1'b1, "mask ROM disabled");

    present(16'ha55a, 1'b0, 8'h00);
    if ((port1_out[0] !== 8'h5a) || (port1_oe[0] !== 8'hff) ||
        (port1_oe[1] !== 8'h00) || (port1_oe[2] !== 8'h00)) begin
      $fatal(1, "HD6303R Mode-1 Port 1 lower-address function out=%02x oe=%02x mode2oe=%02x mode4oe=%02x",
             port1_out[0], port1_oe[0], port1_oe[1], port1_oe[2]);
    end
    checks = checks + 1;

    present(16'h0003, 1'b0, 8'h00);
    if ((mode_devices[0].dut.device.core_data_in[7:5] !== 3'd1) ||
        (mode_devices[1].dut.device.core_data_in[7:5] !== 3'd2) ||
        (mode_devices[2].dut.device.core_data_in[7:5] !== 3'd4)) begin
      $fatal(1, "HD6303R mode latch readback");
    end
    checks = checks + 3;
    present(16'h0003, 1'b1, 8'h20);
    advance();
    if (mode_devices[2].dut.device.active_mode !== 3'd4)
      $fatal(1, "Hitachi expanded Mode 4 leaked Motorola Mode-5 transition");
    checks = checks + 1;

    $display("HD6303R MODES PASS: %0d Mode-1/2/4 decode, ROMless, RAM, and port checks",
             checks);
    $finish;
  end
endmodule
