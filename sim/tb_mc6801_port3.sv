// SPDX-License-Identifier: MIT
// Directed MC6801/HD6301V1/HD63701V0 Port-3 handshake/DDR-read regression.
module tb_mc6801_port3;
  import mc6801_peripheral_bus_stub_pkg::*;

  logic clk;
  logic reset_n;
  logic is3_n;
  logic [7:0] port3_in;
  logic mc_os3_n;
  logic hd_os3_n;
  logic v0_os3_n;
  integer checks;

  /* verilator lint_off PINCONNECTEMPTY */
  mc6801_mcu #(.OPERATING_MODE(3'd7)) mc6801 (
    .clk_i(clk), .reset_n_i(reset_n), .standby_reset_n_i(1'b1),
    .clock_enable_i(1'b1), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
    .standby_power_ok_i(1'b1), .port1_i(8'hff), .port2_i(5'h1f),
    .port3_i(port3_in), .port4_i(8'hff), .is3_n_i(is3_n),
    .program_data_i(8'hff), .external_data_i(8'hff),
    .program_address_o(), .program_read_o(), .external_address_o(),
    .external_data_o(), .external_write_o(), .external_bus_valid_o(),
    .external_opcode_fetch_o(), .port1_o(), .port1_oe_o(), .port2_o(),
    .port2_oe_o(), .port3_o(), .port3_oe_o(), .port4_o(), .port4_oe_o(),
    .os3_n_o(mc_os3_n), .sci_tx_o(), .sci_clock_o(), .timer_irq_o(),
    .sci_irq_o(), .opcode_fetch_o(), .retire_o(), .illegal_o(),
    .undefined_o(), .waiting_o(), .sleeping_o(), .interrupt_ack_o(),
    .operating_mode_o(), .debug_address_o(), .debug_pc_o(), .debug_sp_o(),
    .debug_a_o(), .debug_b_o(), .debug_x_o(), .debug_ccr_o(),
    .debug_timer_o(), .debug_output_compare_o(), .debug_input_capture_o(),
    .debug_tcsr_o(), .debug_trcsr_o(), .debug_receive_data_o(),
    .debug_opcode_o()
  );

  hd6301v1_mcu #(.OPERATING_MODE(3'd7)) hd6301 (
    .clk_i(clk), .reset_n_i(reset_n), .standby_n_i(1'b1),
    .clock_enable_i(1'b1), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
    .standby_power_ok_i(1'b1), .port1_i(8'hff), .port2_i(5'h1f),
    .port3_i(port3_in), .port4_i(8'hff), .is3_n_i(is3_n),
    .program_data_i(8'hff), .external_data_i(8'hff),
    .program_address_o(), .program_read_o(), .external_address_o(),
    .external_data_o(), .external_write_o(), .external_bus_valid_o(),
    .external_opcode_fetch_o(), .port1_o(), .port1_oe_o(), .port2_o(),
    .port2_oe_o(), .port3_o(), .port3_oe_o(), .port4_o(), .port4_oe_o(),
    .os3_n_o(hd_os3_n), .sci_tx_o(), .sci_clock_o(), .timer_irq_o(),
    .sci_irq_o(), .opcode_fetch_o(), .retire_o(), .illegal_o(),
    .undefined_o(), .waiting_o(), .sleeping_o(), .interrupt_ack_o(),
    .debug_address_o(), .debug_pc_o(), .debug_sp_o(), .debug_a_o(),
    .debug_b_o(), .debug_x_o(), .debug_ccr_o(), .debug_timer_o(),
    .debug_output_compare_o(), .debug_input_capture_o(), .debug_tcsr_o(),
    .debug_trcsr_o(), .debug_receive_data_o(), .debug_opcode_o()
  );

  hd63701v0_mcu #(.OPERATING_MODE(3'd7)) hd63701 (
    .clk_i(clk), .reset_n_i(reset_n), .standby_n_i(1'b1),
    .clock_enable_i(1'b1), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
    .standby_power_ok_i(1'b1), .port1_i(8'hff), .port2_i(5'h1f),
    .port3_i(port3_in), .port4_i(8'hff), .is3_n_i(is3_n),
    .program_data_i(8'hff), .prom_mode_i(1'b0),
    .prom_program_voltage_i(1'b0), .prom_address_o(), .prom_data_o(),
    .prom_data_oe_o(), .prom_program_data_o(), .prom_program_o(),
    .external_data_i(8'hff), .program_address_o(), .program_read_o(),
    .external_address_o(), .external_data_o(), .external_write_o(),
    .external_bus_valid_o(), .external_opcode_fetch_o(), .port1_o(),
    .port1_oe_o(), .port2_o(), .port2_oe_o(), .port3_o(), .port3_oe_o(),
    .port4_o(), .port4_oe_o(), .os3_n_o(v0_os3_n), .sci_tx_o(),
    .sci_clock_o(), .timer_irq_o(), .sci_irq_o(), .opcode_fetch_o(),
    .retire_o(), .illegal_o(), .undefined_o(), .waiting_o(), .sleeping_o(),
    .interrupt_ack_o(), .debug_address_o(), .debug_pc_o(), .debug_sp_o(),
    .debug_a_o(), .debug_b_o(), .debug_x_o(), .debug_ccr_o(),
    .debug_timer_o(), .debug_output_compare_o(), .debug_input_capture_o(),
    .debug_tcsr_o(), .debug_trcsr_o(), .debug_receive_data_o(),
    .debug_opcode_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always #5 clk <= ~clk;

  task automatic check(input logic condition, input string label_value);
    begin
      if (!condition) $fatal(1, "Port-3 check failed: %0s", label_value);
      checks = checks + 1;
    end
  endtask

  task automatic advance;
    begin
      @(posedge clk);
      #1;
    end
  endtask

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

  task automatic write_register(
    input logic [15:0] address_value,
    input logic [7:0] data_value
  );
    begin
      present(address_value, 1'b1, data_value);
      advance();
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    is3_n = 1'b1;
    port3_in = 8'h96;
    stub_address = 16'h0000;
    stub_data = 8'h00;
    stub_write = 1'b0;
    stub_valid = 1'b0;
    stub_opcode_fetch = 1'b0;
    stub_interrupt_mask = 1'b1;
    stub_sleeping = 1'b0;
    stub_waiting = 1'b0;
    stub_sp = 16'h0000;
    checks = 0;

    #1;
    reset_n = 1'b0;
    advance();
    advance();
    reset_n = 1'b1;
    advance();

    present(16'h000f, 1'b0, 8'h00);
    check(mc6801.core_data_in == 8'h27, "MC6801 P3CSR reset value");
    check(hd6301.device.core_data_in == 8'h27 &&
          hd63701.device.core_data_in == 8'h27,
          "Hitachi P3CSR reset value");

    // Enable IS3 IRQ and the input latch, then synchronize one falling edge.
    write_register(16'h000f, 8'h48);
    @(negedge clk);
    is3_n = 1'b0;
    advance();
    advance();
    check(mc6801.port3_is3_flag && mc6801.port3_latch_valid,
          "MC6801 IS3 edge flags and latches Port 3");
    check(hd6301.device.port3_is3_flag && hd6301.device.port3_latch_valid &&
          hd63701.device.port3_is3_flag && hd63701.device.port3_latch_valid,
          "Hitachi IS3 edge flags and latches Port 3");

    // Reading P3CSR arms the documented clear sequence. A P3DDR read must not
    // complete that sequence, release the latch, or generate OS3.
    present(16'h000f, 1'b0, 8'h00);
    check(mc6801.core_data_in == 8'hef, "MC6801 flagged P3CSR read value");
    check(hd6301.device.core_data_in == 8'hef &&
          hd63701.device.core_data_in == 8'hef,
          "Hitachi flagged P3CSR read value");
    advance();
    present(16'h0004, 1'b0, 8'h00);
    check(mc6801.core_data_in == 8'h96,
          "MC6801 P3DDR read aliases latched Port-3 data");
    check(hd6301.device.core_data_in == 8'hff &&
          hd63701.device.core_data_in == 8'hff,
          "Hitachi write-only P3DDR reads all ones");
    check(mc_os3_n && hd_os3_n && v0_os3_n,
          "P3DDR read never selects OS3");
    advance();
    check(mc6801.port3_is3_flag && mc6801.port3_latch_valid &&
          mc6801.port3_clear_armed,
          "MC6801 P3DDR read has no handshake side effects");
    check(hd6301.device.port3_is3_flag && hd6301.device.port3_latch_valid &&
          hd6301.device.port3_clear_armed && hd63701.device.port3_is3_flag &&
          hd63701.device.port3_latch_valid && hd63701.device.port3_clear_armed,
          "Hitachi P3DDR read has no handshake side effects");

    present(16'h0006, 1'b0, 8'h00);
    check(mc6801.core_data_in == 8'h96 && hd6301.device.core_data_in == 8'h96 &&
          hd63701.device.core_data_in == 8'h96,
          "Port-3 data read returns captured byte");
    check(!mc_os3_n && !hd_os3_n && !v0_os3_n,
          "OSS=0 selects OS3 on Port-3 read");
    advance();
    check(!mc6801.port3_is3_flag && !mc6801.port3_latch_valid &&
          !mc6801.port3_clear_armed,
          "MC6801 Port-3 read completes flag and latch clear");
    check(!hd6301.device.port3_is3_flag && !hd6301.device.port3_latch_valid &&
          !hd6301.device.port3_clear_armed && !hd63701.device.port3_is3_flag &&
          !hd63701.device.port3_latch_valid && !hd63701.device.port3_clear_armed,
          "Hitachi Port-3 read completes flag and latch clear");

    // Capture another byte, change the pins, then disable the latch. The
    // formerly captured byte must stop hiding the live pins immediately.
    @(negedge clk);
    is3_n = 1'b1;
    advance();
    advance();
    @(negedge clk);
    port3_in = 8'ha5;
    is3_n = 1'b0;
    advance();
    advance();
    check(mc6801.port3_latch_valid && hd6301.device.port3_latch_valid &&
          hd63701.device.port3_latch_valid,
          "second IS3 edge captures Port 3");
    @(negedge clk);
    port3_in = 8'h3c;
    write_register(16'h000f, 8'h40);
    check(!mc6801.port3_latch_valid && !hd6301.device.port3_latch_valid &&
          !hd63701.device.port3_latch_valid,
          "clearing latch-enable makes the input path transparent");
    present(16'h0004, 1'b0, 8'h00);
    check(mc6801.core_data_in == 8'h3c,
          "MC6801 P3DDR alias observes live pins after latch disable");
    check(hd6301.device.core_data_in == 8'hff &&
          hd63701.device.core_data_in == 8'hff,
          "Hitachi P3DDR remains write-only after latch disable");

    // OSS selects read or write DATA-register accesses only. DDR accesses are
    // excluded above and both strobe polarities are exercised here.
    present(16'h0006, 1'b1, 8'h69);
    check(mc_os3_n && hd_os3_n && v0_os3_n,
          "OSS=0 excludes Port-3 write from OS3");
    write_register(16'h000f, 8'h10);
    present(16'h0006, 1'b0, 8'h00);
    check(mc_os3_n && hd_os3_n && v0_os3_n,
          "OSS=1 excludes Port-3 read from OS3");
    present(16'h0006, 1'b1, 8'h69);
    check(!mc_os3_n && !hd_os3_n && !v0_os3_n,
          "OSS=1 selects Port-3 write for OS3");

    $display("MC6801/HD6301V1/HD63701V0 Port-3 regression passed (%0d checks)",
             checks);
    $finish;
  end
endmodule
