// SPDX-License-Identifier: MIT
module tb_mc6801_sci_external;
  import mc6801_peripheral_bus_stub_pkg::*;

  logic clk;
  logic reset_n;
  logic [4:0] port2_in;
  logic [4:0] port2_oe;
  logic sci_tx;
  logic [7:0] debug_trcsr;
  logic [7:0] debug_receive;
  integer checks;
  localparam logic [7:0] RECEIVE_BYTE = 8'hc3;
  localparam logic [7:0] TRANSMIT_BYTE = 8'ha6;

  /* verilator lint_off PINCONNECTEMPTY */
  mc6801_mcu #(.OPERATING_MODE(3'd2)) dut (
    .clk_i(clk), .reset_n_i(reset_n), .standby_reset_n_i(1'b1),
    .clock_enable_i(1'b1), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
    .standby_power_ok_i(1'b1), .port1_i(8'hff), .port2_i(port2_in),
    .port3_i(8'hff), .port4_i(8'hff), .is3_n_i(1'b1),
    .program_data_i(8'hff), .external_data_i(8'hff),
    .program_address_o(), .program_read_o(), .external_address_o(),
    .external_data_o(), .external_write_o(), .external_bus_valid_o(),
    .external_opcode_fetch_o(), .port1_o(), .port1_oe_o(), .port2_o(),
    .port2_oe_o(port2_oe), .port3_o(), .port3_oe_o(), .port4_o(),
    .port4_oe_o(), .os3_n_o(), .sci_tx_o(sci_tx), .sci_clock_o(),
    .timer_irq_o(), .sci_irq_o(), .opcode_fetch_o(), .retire_o(),
    .illegal_o(), .undefined_o(), .waiting_o(), .sleeping_o(),
    .interrupt_ack_o(), .operating_mode_o(), .debug_address_o(), .debug_pc_o(), .debug_sp_o(),
    .debug_a_o(), .debug_b_o(), .debug_x_o(), .debug_ccr_o(),
    .debug_timer_o(), .debug_output_compare_o(), .debug_input_capture_o(),
    .debug_tcsr_o(), .debug_trcsr_o(debug_trcsr),
    .debug_receive_data_o(debug_receive), .debug_opcode_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always #5 clk <= ~clk;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic write_register(input logic [15:0] address, input logic [7:0] data);
    begin
      @(negedge clk);
      stub_address = address;
      stub_data = data;
      stub_write = 1'b1;
      stub_valid = 1'b1;
      tick();
    end
  endtask

  task automatic read_register(input logic [15:0] address);
    begin
      @(negedge clk);
      stub_address = address;
      stub_write = 1'b0;
      stub_valid = 1'b1;
      tick();
    end
  endtask

  task automatic idle_cycle;
    begin
      @(negedge clk);
      stub_valid = 1'b0;
      stub_write = 1'b0;
      tick();
    end
  endtask

  task automatic external_bit(input logic receive_level);
    integer edge_index;
    logic [2:0] expected_phase;
    begin
      for (edge_index = 1; edge_index <= 8; edge_index = edge_index + 1) begin
        port2_in[3:2] = {receive_level, 1'b0};
        idle_cycle();
        port2_in[3:2] = {receive_level, 1'b1};
        idle_cycle();
        expected_phase = edge_index[2:0];
        if (dut.sci_external_subcycles !== expected_phase) begin
          $fatal(1, "external SCI divider edge=%0d phase=%0d",
                 edge_index, dut.sci_external_subcycles);
        end
        checks = checks + 1;
      end
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    port2_in = 5'h1f;
    stub_address = 16'h0000;
    stub_data = 8'h00;
    stub_write = 1'b0;
    stub_valid = 1'b0;
    stub_interrupt_mask = 1'b1;
    checks = 0;

    #1; reset_n = 1'b0; #1; reset_n = 1'b1;
    tick();

    // CC1:CC0=11 selects external NRZ. SS1:SS0=11 is deliberately used to
    // prove that the timer-derived speed selection is ignored in this mode.
    write_register(16'h0001, 8'h04);
    write_register(16'h0010, 8'h0f);
    if (port2_oe !== 5'h00)
      $fatal(1, "external SCI clock did not force P22 to input");
    checks = checks + 1;

    read_register(16'h0011);
    write_register(16'h0013, 8'ha6);
    write_register(16'h0011, 8'h0a);
    repeat (32) idle_cycle();
    if (debug_trcsr[5] || dut.tx_preamble_remaining != 4'd9 ||
        dut.sci_external_subcycles != 3'd0) begin
      $fatal(1, "stationary external clock advanced SCI state");
    end
    checks = checks + 1;

    repeat (9) external_bit(1'b1);
    for (integer bit_index = 0; bit_index < 10; bit_index = bit_index + 1) begin
      logic receive_level;
      logic expected_transmit;
      if (bit_index == 0) receive_level = 1'b0;
      else if (bit_index == 9) receive_level = 1'b1;
      else receive_level = RECEIVE_BYTE[bit_index - 1];
      external_bit(receive_level);
      if (bit_index == 0) expected_transmit = 1'b0;
      else if (bit_index == 9) expected_transmit = 1'b1;
      else expected_transmit = TRANSMIT_BYTE[bit_index - 1];
      if (sci_tx !== expected_transmit) begin
        $fatal(1, "external SCI transmit bit=%0d actual=%0b expected=%0b",
               bit_index, sci_tx, expected_transmit);
      end
      checks = checks + 1;
    end

    if (debug_trcsr[7:5] !== 3'b101 || debug_receive !== 8'hc3) begin
      $fatal(1, "external SCI receive trcsr=%02x rdr=%02x",
             debug_trcsr, debug_receive);
    end
    checks = checks + 1;
    $display("MC6801 EXTERNAL SCI PASS: %0d P22 direction, 8x divider, TX, and RX checks",
             checks);
    $finish;
  end
endmodule
