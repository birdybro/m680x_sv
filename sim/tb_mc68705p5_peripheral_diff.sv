// SPDX-License-Identifier: MIT
module tb_mc68705p5_peripheral_diff;
  import mc68705p5_peripheral_vectors_pkg::*;
  import mc68705p5_peripheral_bus_stub_pkg::*;

  logic clk;
  logic reset_n;
  logic int_n;
  logic timer_pin;
  logic [7:0] port_a_in;
  logic [7:0] port_b_in;
  logic [3:0] port_c_in;
  logic [7:0] program_data;
  logic vpp_present;
  logic bootstrap_voltage;
  logic [7:0] port_a_out;
  logic [7:0] port_b_out;
  logic [3:0] port_c_out;
  logic [7:0] port_a_oe;
  logic [7:0] port_b_oe;
  logic [3:0] port_c_oe;
  logic [10:0] program_address;
  logic program_read;
  logic bootstrap_mode;
  logic eprom_latch_enable;
  logic eprom_program_enable;
  logic [10:0] eprom_program_address;
  logic [7:0] eprom_program_data;
  logic timer_irq;
  logic external_irq;
  logic [15:0] debug_address;
  logic [4:0] debug_ccr;
  logic [7:0] debug_timer;
  logic [7:0] debug_tcr;
  logic [7:0] debug_pcr;
  mc68705p5_peripheral_vector_t expected;
  integer cycle_index;
  integer pcr_checks;

  /* verilator lint_off PINCONNECTEMPTY */
  mc68705p5_mcu dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(1'b1),
    .int_n_i(int_n), .timer_i(timer_pin), .port_a_i(port_a_in),
    .port_b_i(port_b_in), .port_c_i(port_c_in), .port_a_o(port_a_out),
    .port_b_o(port_b_out), .port_c_o(port_c_out), .port_a_oe_o(port_a_oe),
    .port_b_oe_o(port_b_oe), .port_c_oe_o(port_c_oe),
    .program_address_o(program_address), .program_read_o(program_read),
    .program_data_i(program_data), .vpp_present_i(vpp_present),
    .bootstrap_voltage_i(bootstrap_voltage), .bootstrap_mode_o(bootstrap_mode),
    .eprom_latch_enable_o(eprom_latch_enable),
    .eprom_program_enable_o(eprom_program_enable),
    .eprom_program_address_o(eprom_program_address),
    .eprom_program_data_o(eprom_program_data), .timer_irq_o(timer_irq),
    .external_irq_o(external_irq), .opcode_fetch_o(), .retire_o(),
    .illegal_o(), .undefined_o(), .waiting_o(), .stopped_o(),
    .interrupt_ack_o(), .debug_address_o(debug_address), .debug_pc_o(),
    .debug_sp_o(), .debug_a_o(), .debug_x_o(), .debug_ccr_o(debug_ccr),
    .debug_opcode_o(), .debug_instruction_cycles_o(),
    .debug_timer_o(debug_timer), .debug_timer_control_o(debug_tcr),
    .debug_program_control_o(debug_pcr)
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always #5 clk <= ~clk;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic check_pcr_write(
    input logic       test_vpp,
    input logic [1:0] write_value,
    input logic [7:0] expected_pcr,
    input logic       expected_latch,
    input logic       expected_program,
    input logic       expected_read
  );
    begin
      vpp_present = test_vpp;
      stub_address = 16'h000b;
      stub_data = {6'h00, write_value};
      stub_write = 1'b1;
      stub_valid = 1'b1;
      tick();
      stub_address = 16'h0080;
      stub_write = 1'b0;
      program_data = 8'ha5;
      #1;
      if (debug_pcr !== expected_pcr ||
          eprom_latch_enable !== expected_latch ||
          eprom_program_enable !== expected_program ||
          program_read !== expected_read ||
          dut.core_data_in !== (expected_read ? 8'ha5 : 8'hff)) begin
        $fatal(1, "MC68705P5 PCR table VPP=%b write=%02x PCR=%02x/%02x latch=%b/%b program=%b/%b read=%b/%b data=%02x",
               test_vpp, {6'h00, write_value}, debug_pcr, expected_pcr,
               eprom_latch_enable, expected_latch, eprom_program_enable,
               expected_program, program_read, expected_read, dut.core_data_in);
      end
      pcr_checks = pcr_checks + 1;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    int_n = 1'b1;
    timer_pin = 1'b0;
    port_a_in = 8'hff;
    port_b_in = 8'hff;
    port_c_in = 4'hf;
    program_data = 8'hff;
    vpp_present = 1'b0;
    bootstrap_voltage = 1'b0;
    stub_address = 16'h0000;
    stub_data = 8'h00;
    stub_write = 1'b0;
    stub_valid = 1'b0;
    stub_interrupt_mask = 1'b1;
    pcr_checks = 0;
    #1;
    reset_n = 1'b0;
    #1;
    reset_n = 1'b1;

    for (cycle_index = 0; cycle_index < MC68705P5_PERIPHERAL_VECTOR_COUNT;
         cycle_index = cycle_index + 1) begin
      expected = mc68705p5_peripheral_vector(cycle_index[9:0]);
      stub_address = expected.address;
      stub_data = expected.data;
      stub_write = expected.write;
      stub_valid = expected.valid;
      stub_interrupt_mask = expected.interrupt_mask;
      int_n = expected.int_n;
      timer_pin = expected.timer_pin;
      port_a_in = expected.port_a;
      port_b_in = expected.port_b;
      port_c_in = expected.port_c;
      program_data = expected.program_data;
      vpp_present = expected.vpp_present;
      bootstrap_voltage = expected.bootstrap_voltage;
      #1;
      if ((expected.valid && !expected.write &&
           dut.core_data_in !== expected.read_data) ||
          program_address !== expected.program_address ||
          program_read !== expected.program_read ||
          debug_address !== {5'h00, expected.address[10:0]} ||
          debug_ccr !== {1'b0, expected.interrupt_mask, 3'b000}) begin
        $fatal(1, "MC68705P5 peripheral bus mismatch cycle=%0d address=%04x read=%02x/%02x program_address=%03x/%03x read_select=%b/%b",
               cycle_index, expected.address, dut.core_data_in, expected.read_data,
               program_address, expected.program_address, program_read,
               expected.program_read);
      end
      tick();
      if (port_a_out !== expected.port_a_output || port_a_oe !== expected.port_a_oe ||
          port_b_out !== expected.port_b_output || port_b_oe !== expected.port_b_oe ||
          port_c_out !== expected.port_c_output || port_c_oe !== expected.port_c_oe ||
          debug_timer !== expected.timer_data || debug_tcr !== expected.tcr ||
          debug_pcr !== expected.pcr || timer_irq !== expected.timer_irq ||
          external_irq !== expected.external_irq ||
          bootstrap_mode !== expected.bootstrap_mode ||
          !dut.irq_n !== expected.irq_request ||
          dut.core_irq_vector !== expected.irq_vector ||
          eprom_latch_enable !== expected.eprom_latch_enable ||
          eprom_program_enable !== expected.eprom_program_enable ||
          eprom_program_address !== expected.eprom_program_address ||
          eprom_program_data !== expected.eprom_program_data) begin
        $display("  ports A=%02x/%02x oe=%02x/%02x B=%02x/%02x oe=%02x/%02x C=%x/%x oe=%x/%x",
                 port_a_out, expected.port_a_output, port_a_oe, expected.port_a_oe,
                 port_b_out, expected.port_b_output, port_b_oe, expected.port_b_oe,
                 port_c_out, expected.port_c_output, port_c_oe, expected.port_c_oe);
        $display("  irq timer=%b/%b external=%b/%b any=%b/%b vector=%04x/%04x",
                 timer_irq, expected.timer_irq, external_irq, expected.external_irq,
                 !dut.irq_n, expected.irq_request, dut.core_irq_vector,
                 expected.irq_vector);
        $fatal(1, "MC68705P5 peripheral state mismatch cycle=%0d TDR=%02x/%02x TCR=%02x/%02x PCR=%02x/%02x program=%b/%b %03x/%03x %02x/%02x",
               cycle_index, debug_timer, expected.timer_data, debug_tcr, expected.tcr,
               debug_pcr, expected.pcr, eprom_program_enable,
               expected.eprom_program_enable, eprom_program_address,
               expected.eprom_program_address, eprom_program_data,
               expected.eprom_program_data);
      end
    end

    // Exercise all four software encodings with and without VPP. Writes of
    // PGE=0,PLE=1 are coerced to PGE=1, so neither invalid table row is
    // reachable through the PCR programming interface.
    stub_valid = 1'b0;
    reset_n = 1'b0;
    #1;
    reset_n = 1'b1;
    check_pcr_write(1'b0, 2'b00, 8'hfc, 1'b0, 1'b0, 1'b1);
    check_pcr_write(1'b0, 2'b01, 8'hff, 1'b0, 1'b0, 1'b1);
    check_pcr_write(1'b0, 2'b10, 8'hfe, 1'b0, 1'b0, 1'b1);
    check_pcr_write(1'b0, 2'b11, 8'hff, 1'b0, 1'b0, 1'b1);
    check_pcr_write(1'b1, 2'b00, 8'hf8, 1'b1, 1'b1, 1'b0);
    check_pcr_write(1'b1, 2'b01, 8'hfb, 1'b0, 1'b0, 1'b1);
    check_pcr_write(1'b1, 2'b10, 8'hfa, 1'b1, 1'b0, 1'b0);
    check_pcr_write(1'b1, 2'b11, 8'hfb, 1'b0, 1'b0, 1'b1);

    $display("MC68705P5 PERIPHERAL DIFFERENTIAL PASS: seed=%08x cycles=%0d PCR states=%0d",
             32'h68705a05, MC68705P5_PERIPHERAL_VECTOR_COUNT, pcr_checks);
    $finish;
  end
endmodule
