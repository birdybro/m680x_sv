// SPDX-License-Identifier: MIT
module tb_mc6801_peripheral_diff #(
  parameter logic [2:0] TEST_MODE = 3'd2
);
  import mc6801_peripheral_vectors_pkg::*;
  import mc6801_peripheral_bus_stub_pkg::*;

  logic clk;
  logic reset_n;
  logic irq1_n;
  logic standby_power_ok;
  logic [7:0] port1_in;
  logic [4:0] port2_in;
  logic [7:0] external_data_in;
  logic [15:0] external_address;
  logic [7:0] external_data_out;
  logic external_write;
  logic external_valid;
  logic external_fetch;
  logic [7:0] port1_out;
  logic [7:0] port1_oe;
  logic [4:0] port2_out;
  logic [4:0] port2_oe;
  logic sci_tx;
  logic sci_clock;
  logic timer_irq;
  logic sci_irq;
  logic opcode_fetch;
  logic retire;
  logic illegal;
  logic undefined_value;
  logic waiting_state;
  logic sleeping_state;
  logic interrupt_ack;
  logic [15:0] debug_address;
  logic [15:0] debug_pc;
  logic [15:0] debug_sp;
  logic [7:0] debug_a;
  logic [7:0] debug_b;
  logic [15:0] debug_x;
  logic [5:0] debug_ccr;
  logic [15:0] debug_timer;
  logic [15:0] debug_compare;
  logic [15:0] debug_capture;
  logic [7:0] debug_tcsr;
  logic [7:0] debug_trcsr;
  logic [7:0] debug_receive;
  logic [7:0] debug_opcode;
  mc6801_peripheral_vector_t expected;
  integer cycle_index;

  mc6801_mcu #(.OPERATING_MODE(TEST_MODE)) dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(1'b1),
    .nmi_n_i(1'b1), .irq1_n_i(irq1_n),
    .standby_power_ok_i(standby_power_ok), .port1_i(port1_in),
    .port2_i(port2_in), .external_data_i(external_data_in),
    .external_address_o(external_address), .external_data_o(external_data_out),
    .external_write_o(external_write), .external_bus_valid_o(external_valid),
    .external_opcode_fetch_o(external_fetch), .port1_o(port1_out),
    .port1_oe_o(port1_oe), .port2_o(port2_out), .port2_oe_o(port2_oe),
    .sci_tx_o(sci_tx), .sci_clock_o(sci_clock), .timer_irq_o(timer_irq),
    .sci_irq_o(sci_irq), .opcode_fetch_o(opcode_fetch), .retire_o(retire),
    .illegal_o(illegal), .undefined_o(undefined_value), .waiting_o(waiting_state),
    .sleeping_o(sleeping_state),
    .interrupt_ack_o(interrupt_ack), .debug_address_o(debug_address),
    .debug_pc_o(debug_pc), .debug_sp_o(debug_sp), .debug_a_o(debug_a),
    .debug_b_o(debug_b), .debug_x_o(debug_x), .debug_ccr_o(debug_ccr),
    .debug_timer_o(debug_timer), .debug_output_compare_o(debug_compare),
    .debug_input_capture_o(debug_capture), .debug_tcsr_o(debug_tcsr),
    .debug_trcsr_o(debug_trcsr), .debug_receive_data_o(debug_receive),
    .debug_opcode_o(debug_opcode)
  );

  always #5 clk <= ~clk;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    irq1_n = 1'b1;
    standby_power_ok = 1'b1;
    port1_in = 8'hff;
    port2_in = 5'h1f;
    external_data_in = 8'h00;
    stub_address = 16'h0000;
    stub_data = 8'h00;
    stub_write = 1'b0;
    stub_valid = 1'b0;
    stub_interrupt_mask = 1'b1;
    #1;
    reset_n = 1'b0;
    #1;
    reset_n = 1'b1;

    for (cycle_index = 0; cycle_index < MC6801_PERIPHERAL_VECTOR_COUNT;
         cycle_index = cycle_index + 1) begin
      expected = mc6801_peripheral_vector(TEST_MODE, cycle_index[9:0]);
      stub_address = expected.address;
      stub_data = expected.data;
      stub_write = expected.write;
      stub_valid = expected.valid;
      stub_interrupt_mask = expected.interrupt_mask;
      external_data_in = expected.external_data;
      port1_in = expected.port1;
      port2_in = expected.port2;
      irq1_n = expected.irq1_n;
      standby_power_ok = expected.standby_power_ok;
      #1;
      if ((!expected.write && dut.cpu.data_i !== expected.read_data) ||
          external_address !== expected.address ||
          external_data_out !== expected.data ||
          external_write !== expected.write ||
          external_valid !== expected.external_bus || external_fetch || opcode_fetch ||
          debug_address !== expected.address ||
          debug_ccr !== {1'b0, expected.interrupt_mask, 4'b0000}) begin
        $fatal(1, "MC6801 peripheral bus mismatch mode=%0d cycle=%0d read=%02x/%02x external=%b/%b",
          TEST_MODE, cycle_index, dut.cpu.data_i, expected.read_data,
          external_valid, expected.external_bus);
      end
      tick();
      if (debug_timer !== expected.timer || debug_compare !== expected.output_compare ||
          debug_capture !== expected.input_capture || debug_tcsr !== expected.tcsr ||
          debug_trcsr !== expected.trcsr || debug_receive !== expected.receive_data ||
          port1_out !== expected.port1_output || port1_oe !== expected.port1_oe ||
          port2_out !== expected.port2_output || port2_oe !== expected.port2_oe ||
          timer_irq !== expected.timer_irq || sci_irq !== expected.sci_irq ||
          !dut.irq_n !== expected.irq_request ||
          dut.core_irq_vector !== expected.irq_vector ||
          dut.irq1_pending !== expected.irq1_pending ||
          dut.irq2_pending !== expected.irq2_pending ||
          dut.rame !== expected.rame || dut.standby_power !== expected.standby_power ||
          sci_tx !== expected.sci_tx || sci_clock !== expected.sci_clock ||
          retire || illegal || undefined_value || waiting_state || sleeping_state ||
          interrupt_ack ||
          debug_pc !== 16'h0000 || debug_sp !== 16'h0000 || debug_a !== 8'h00 ||
          debug_b !== 8'h00 || debug_x !== 16'h0000 || debug_opcode !== 8'h00) begin
        $fatal(1, "MC6801 peripheral state mismatch mode=%0d cycle=%0d timer=%04x/%04x TCSR=%02x/%02x TRCSR=%02x/%02x vector=%04x/%04x",
          TEST_MODE, cycle_index, debug_timer, expected.timer,
          debug_tcsr, expected.tcsr, debug_trcsr, expected.trcsr,
          dut.core_irq_vector, expected.irq_vector);
      end
    end
    $display("MC6801/MC6803 PERIPHERAL DIFFERENTIAL PASS: mode=%0d seed=%08x cycles=%0d",
      TEST_MODE, TEST_MODE == 3'd2 ? 32'h68030002 : 32'h68030003,
      MC6801_PERIPHERAL_VECTOR_COUNT);
    $finish;
  end
endmodule
