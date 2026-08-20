// SPDX-License-Identifier: MIT
module tb_mc6801_sci_biphase;
  import mc6801_peripheral_bus_stub_pkg::*;

  logic clk;
  logic reset_n;
  logic [4:0] port2_in;
  logic sci_tx;
  logic [7:0] debug_trcsr;
  logic [7:0] debug_receive;
  integer checks;
  logic receive_level;
  localparam logic [7:0] RECEIVE_BYTE = 8'ha7;
  localparam logic [7:0] TRANSMIT_BYTE = 8'h4d;
  localparam logic [7:0] FRAMING_BYTE = 8'h5a;

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
    .port2_oe_o(), .port3_o(), .port3_oe_o(), .port4_o(), .port4_oe_o(),
    .os3_n_o(), .sci_tx_o(sci_tx), .sci_clock_o(), .timer_irq_o(),
    .sci_irq_o(), .opcode_fetch_o(), .retire_o(), .illegal_o(),
    .undefined_o(), .waiting_o(), .sleeping_o(), .interrupt_ack_o(), .operating_mode_o(),
    .debug_address_o(), .debug_pc_o(), .debug_sp_o(), .debug_a_o(),
    .debug_b_o(), .debug_x_o(), .debug_ccr_o(), .debug_timer_o(),
    .debug_output_compare_o(), .debug_input_capture_o(), .debug_tcsr_o(),
    .debug_trcsr_o(debug_trcsr), .debug_receive_data_o(debug_receive),
    .debug_opcode_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always #5 clk <= ~clk;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic reset_device;
    begin
      reset_n = 1'b0;
      #1;
      reset_n = 1'b1;
      tick();
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

  function automatic logic transmit_bit(input integer bit_index);
    begin
      if (bit_index == 0) transmit_bit = 1'b0;
      else if (bit_index == 9) transmit_bit = 1'b1;
      else transmit_bit = TRANSMIT_BYTE[bit_index - 1];
    end
  endfunction

  task automatic send_biphase_bit(input logic bit_value);
    begin
      // Bi-phase-M always transitions at the bit boundary and adds a
      // transition at the half-bit point for a logical one.
      receive_level = !receive_level;
      port2_in[3] = receive_level;
      repeat (8) idle_cycle();
      if (bit_value) receive_level = !receive_level;
      port2_in[3] = receive_level;
      repeat (8) idle_cycle();
    end
  endtask

  initial begin
    logic boundary_level;
    logic mid_level;
    integer bit_index;
    integer timeout;

    clk = 1'b0;
    reset_n = 1'b1;
    port2_in = 5'h1f;
    stub_address = 16'h0000;
    stub_data = 8'h00;
    stub_write = 1'b0;
    stub_valid = 1'b0;
    stub_interrupt_mask = 1'b1;
    checks = 0;

    reset_device();
    // Reset selects RMCR=00: internal clock, fastest rate, bi-phase format.
    read_register(16'h0011);
    write_register(16'h0013, TRANSMIT_BYTE);
    write_register(16'h0011, 8'h02);
    timeout = 0;
    while ((dut.tx_bits_remaining != 4'd10) && (timeout < 192)) begin
      idle_cycle();
      timeout = timeout + 1;
    end
    if (dut.tx_bits_remaining != 4'd10)
      $fatal(1, "bi-phase transmitter did not leave nine-mark preamble");
    checks = checks + 1;

    for (bit_index = 0; bit_index < 10; bit_index = bit_index + 1) begin
      boundary_level = sci_tx;
      repeat (8) idle_cycle();
      mid_level = boundary_level ^ transmit_bit(bit_index);
      if (sci_tx !== mid_level)
        $fatal(1, "bi-phase TX bit=%0d midpoint actual=%0b expected=%0b",
               bit_index, sci_tx, mid_level);
      checks = checks + 1;
      repeat (8) idle_cycle();
      if (sci_tx !== !mid_level)
        $fatal(1, "bi-phase TX bit=%0d boundary actual=%0b expected=%0b",
               bit_index, sci_tx, !mid_level);
      checks = checks + 1;
    end

    reset_device();
    port2_in = 5'h1f;
    receive_level = 1'b1;
    write_register(16'h0011, 8'h08);
    send_biphase_bit(1'b1);
    send_biphase_bit(1'b1);
    send_biphase_bit(1'b0);
    for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
      send_biphase_bit(RECEIVE_BYTE[bit_index]);
    send_biphase_bit(1'b1);
    if ((debug_trcsr[7:6] !== 2'b10) || (debug_receive !== RECEIVE_BYTE))
      $fatal(1, "bi-phase RX trcsr=%02x rdr=%02x", debug_trcsr, debug_receive);
    checks = checks + 1;

    read_register(16'h0011);
    read_register(16'h0012);
    send_biphase_bit(1'b1);
    send_biphase_bit(1'b1);
    send_biphase_bit(1'b0);
    for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
      send_biphase_bit(FRAMING_BYTE[bit_index]);
    send_biphase_bit(1'b0);
    // The next boundary completes measurement of the long, invalid stop bit.
    send_biphase_bit(1'b1);
    if ((debug_trcsr[7:6] !== 2'b01) || (debug_receive !== 8'h5a))
      $fatal(1, "bi-phase framing error trcsr=%02x rdr=%02x",
             debug_trcsr, debug_receive);
    checks = checks + 1;

    reset_device();
    port2_in = 5'h1f;
    receive_level = 1'b1;
    write_register(16'h0011, 8'h09);
    repeat (10) send_biphase_bit(1'b1);
    if (debug_trcsr[0] !== 1'b0)
      $fatal(1, "bi-phase ten-mark wake-up did not clear WU");
    checks = checks + 1;

    $display("MC6801 BI-PHASE SCI PASS: %0d transition, frame, receive, and wake checks",
             checks);
    $finish;
  end
endmodule
