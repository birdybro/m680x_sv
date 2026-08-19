// SPDX-License-Identifier: MIT
module tb_hd63705_peripheral_diff;
  import hd63705_peripheral_vectors_pkg::*;
  import hd63705_peripheral_bus_stub_pkg::*;

  logic clk;
  // The DUT applies the same reset to asynchronous peripheral state and the
  // verification-only core boundary; this warning is testbench topology only.
  /* verilator lint_off SYNCASYNCNET */
  logic reset_n;
  /* verilator lint_on SYNCASYNCNET */
  logic int_n;
  logic int2_n;
  logic timer_pin;
  logic [7:0] port_a_in;
  logic [7:0] port_b_in;
  logic [7:0] port_c_in;
  logic [6:0] port_d_in;
  logic [7:0] program_data;
  logic [13:0] program_address;
  logic program_read;
  logic [7:0] port_a_out;
  logic [7:0] port_b_out;
  logic [7:0] port_c_out;
  logic [6:0] port_d_out;
  logic [7:0] port_a_oe;
  logic [7:0] port_b_oe;
  logic [7:0] port_c_oe;
  logic [6:0] port_d_oe;
  logic sci_tx;
  logic sci_clock;
  logic timer_irq;
  logic sci_irq;
  logic int_irq;
  logic int2_irq;
  logic [15:0] irq_vector;
  logic [15:0] debug_address;
  logic [4:0] debug_ccr;
  logic [7:0] debug_timer;
  logic [7:0] debug_tcr;
  logic [7:0] debug_mr;
  logic [7:0] debug_scr;
  logic [7:0] debug_ssr;
  logic [7:0] debug_sdr;
  hd63705_peripheral_vector_t expected;
  integer cycle_index;

  /* verilator lint_off PINCONNECTEMPTY */
  hd63705v0_mcu dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(1'b1),
    .standby_n_i(1'b1), .int_n_i(int_n), .int2_n_i(int2_n),
    .timer_i(timer_pin), .port_a_i(port_a_in), .port_b_i(port_b_in),
    .port_c_i(port_c_in), .port_d_i(port_d_in), .port_a_o(port_a_out),
    .port_b_o(port_b_out), .port_c_o(port_c_out), .port_d_o(port_d_out),
    .port_a_oe_o(port_a_oe), .port_b_oe_o(port_b_oe),
    .port_c_oe_o(port_c_oe), .port_d_oe_o(port_d_oe),
    .program_address_o(program_address), .program_read_o(program_read),
    .program_data_i(program_data), .eprom_mode_i(1'b0),
    .eprom_address_i(12'h000), .eprom_data_i(8'h00),
    .eprom_chip_enable_n_i(1'b1), .eprom_output_enable_n_i(1'b1),
    .eprom_program_voltage_i(1'b0), .eprom_data_o(), .eprom_data_oe_o(),
    .eprom_program_data_o(), .eprom_program_o(), .sci_tx_o(sci_tx),
    .sci_clock_o(sci_clock), .timer_irq_o(timer_irq), .sci_irq_o(sci_irq),
    .int_irq_o(int_irq), .int2_irq_o(int2_irq), .irq_vector_o(irq_vector),
    .opcode_fetch_o(), .retire_o(), .illegal_o(), .undefined_o(),
    .waiting_o(), .stopped_o(), .interrupt_ack_o(),
    .debug_address_o(debug_address), .debug_pc_o(), .debug_sp_o(),
    .debug_a_o(), .debug_x_o(), .debug_ccr_o(debug_ccr), .debug_opcode_o(),
    .debug_instruction_cycles_o(), .debug_timer_o(debug_timer),
    .debug_tcr_o(debug_tcr), .debug_mr_o(debug_mr), .debug_scr_o(debug_scr),
    .debug_ssr_o(debug_ssr), .debug_sdr_o(debug_sdr)
  );
  /* verilator lint_on PINCONNECTEMPTY */

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
    int_n = 1'b1;
    int2_n = 1'b1;
    timer_pin = 1'b0;
    port_a_in = 8'hff;
    port_b_in = 8'hff;
    port_c_in = 8'hff;
    port_d_in = 7'h7f;
    program_data = 8'hff;
    stub_address = 16'h0000;
    stub_data = 8'h00;
    stub_write = 1'b0;
    stub_valid = 1'b0;
    stub_interrupt_mask = 1'b1;
    stub_waiting = 1'b0;
    stub_stopped = 1'b0;
    #1;
    reset_n = 1'b0;
    #1;
    reset_n = 1'b1;

    for (cycle_index = 0; cycle_index < HD63705_PERIPHERAL_VECTOR_COUNT;
         cycle_index = cycle_index + 1) begin
      expected = hd63705_peripheral_vector(cycle_index[9:0]);
      stub_address = expected.address;
      stub_data = expected.data;
      stub_write = expected.write;
      stub_valid = expected.valid;
      stub_interrupt_mask = expected.interrupt_mask;
      stub_waiting = expected.waiting;
      stub_stopped = expected.stopped;
      int_n = expected.int_n;
      int2_n = expected.int2_n;
      timer_pin = expected.timer_pin;
      port_a_in = expected.port_a;
      port_b_in = expected.port_b;
      port_c_in = expected.port_c;
      port_d_in = expected.port_d;
      program_data = expected.program_data;
      #1;
      if ((expected.valid && !expected.write &&
           dut.core_data_in !== expected.read_data) ||
          program_address !== expected.address[13:0] ||
          program_read !== expected.program_bus ||
          debug_address !== {2'b00, expected.address[13:0]} ||
          debug_ccr !== {1'b0, expected.interrupt_mask, 3'b000}) begin
        $fatal(1, "HD63705 peripheral bus mismatch cycle=%0d address=%04x read=%02x/%02x program=%b/%b",
               cycle_index, expected.address, dut.core_data_in, expected.read_data,
               program_read, expected.program_bus);
      end
      tick();
      if (port_a_out !== expected.port_a_output || port_a_oe !== expected.port_a_oe ||
          port_b_out !== expected.port_b_output || port_b_oe !== expected.port_b_oe ||
          port_c_out !== expected.port_c_output || port_c_oe !== expected.port_c_oe ||
          port_d_out !== expected.port_d_output || port_d_oe !== expected.port_d_oe ||
          debug_timer !== expected.timer_data || debug_tcr !== expected.tcr ||
          debug_mr !== expected.mr || debug_scr !== expected.scr ||
          debug_ssr !== expected.ssr || debug_sdr !== expected.sdr ||
          timer_irq !== expected.timer_irq || sci_irq !== expected.sci_irq ||
          int_irq !== expected.int_irq || int2_irq !== expected.int2_irq ||
          dut.irq_request !== expected.irq_request || irq_vector !== expected.irq_vector ||
          sci_tx !== expected.sci_tx || sci_clock !== expected.sci_clock) begin
        $display("  ports A=%02x/%02x oe=%02x/%02x B=%02x/%02x oe=%02x/%02x C=%02x/%02x oe=%02x/%02x D=%02x/%02x oe=%02x/%02x",
                 port_a_out, expected.port_a_output, port_a_oe, expected.port_a_oe,
                 port_b_out, expected.port_b_output, port_b_oe, expected.port_b_oe,
                 port_c_out, expected.port_c_output, port_c_oe, expected.port_c_oe,
                 port_d_out, expected.port_d_output, port_d_oe, expected.port_d_oe);
        $display("  irq timer=%b/%b sci=%b/%b int=%b/%b int2=%b/%b any=%b/%b tx=%b/%b ck=%b/%b",
                 timer_irq, expected.timer_irq, sci_irq, expected.sci_irq,
                 int_irq, expected.int_irq, int2_irq, expected.int2_irq,
                 dut.irq_request, expected.irq_request, sci_tx, expected.sci_tx,
                 sci_clock, expected.sci_clock);
        $fatal(1, "HD63705 peripheral state mismatch cycle=%0d TDR=%02x/%02x TCR=%02x/%02x MR=%02x/%02x SCR=%02x/%02x SSR=%02x/%02x vector=%04x/%04x",
               cycle_index, debug_timer, expected.timer_data, debug_tcr, expected.tcr,
               debug_mr, expected.mr, debug_scr, expected.scr, debug_ssr,
               expected.ssr, irq_vector, expected.irq_vector);
      end
    end
    $display("HD63705V0 PERIPHERAL DIFFERENTIAL PASS: seed=%08x cycles=%0d",
             32'h63705000, HD63705_PERIPHERAL_VECTOR_COUNT);
    $finish;
  end
endmodule
