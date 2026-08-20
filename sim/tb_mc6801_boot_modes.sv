// SPDX-License-Identifier: MIT
module tb_mc6801_boot_modes;
  logic clk;
  logic reset_n;
  logic [7:0] external0 [0:65535];
  logic [7:0] program0 [0:65535];
  logic [15:0] address0;
  logic [7:0] data_out0;
  logic write0;
  logic valid0;
  logic [15:0] program_address0;
  logic program_read0;
  logic retire0;
  logic [7:0] opcode0;
  logic [7:0] a0;
  logic [15:0] address4;
  logic valid4;
  logic program_read4;
  logic retire4;
  logic [7:0] opcode4;
  logic [7:0] a4;
  integer index;
  integer cycles;
  integer mode0_vector_reads;
  integer mode4_retires;
  logic mode0_complete;
  logic mode4_complete;
  logic mode0_internal_vector_seen;
  logic mode0_monitor_enable;

  /* verilator lint_off PINCONNECTEMPTY */
  mc6801_mcu #(.OPERATING_MODE(3'd0)) mode0 (
    .clk_i(clk), .reset_n_i(reset_n), .standby_reset_n_i(1'b1),
    .clock_enable_i(1'b1), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
    .standby_power_ok_i(1'b1), .port1_i(8'hff), .port2_i(5'h1f),
    .port3_i(8'hff), .port4_i(8'hff), .is3_n_i(1'b1),
    .program_data_i(program0[program_address0]),
    .external_data_i(external0[address0]),
    .program_address_o(program_address0), .program_read_o(program_read0),
    .external_address_o(address0), .external_data_o(data_out0),
    .external_write_o(write0), .external_bus_valid_o(valid0),
    .external_opcode_fetch_o(), .port1_o(), .port1_oe_o(), .port2_o(),
    .port2_oe_o(), .port3_o(), .port3_oe_o(), .port4_o(), .port4_oe_o(),
    .os3_n_o(), .sci_tx_o(), .sci_clock_o(), .timer_irq_o(), .sci_irq_o(),
    .opcode_fetch_o(), .retire_o(retire0), .illegal_o(), .undefined_o(),
    .waiting_o(), .sleeping_o(), .interrupt_ack_o(), .operating_mode_o(), .debug_address_o(),
    .debug_pc_o(), .debug_sp_o(), .debug_a_o(a0), .debug_b_o(), .debug_x_o(),
    .debug_ccr_o(), .debug_timer_o(), .debug_output_compare_o(),
    .debug_input_capture_o(), .debug_tcsr_o(), .debug_trcsr_o(),
    .debug_receive_data_o(), .debug_opcode_o(opcode0)
  );

  mc6801_mcu #(.OPERATING_MODE(3'd4)) mode4 (
    .clk_i(clk), .reset_n_i(reset_n), .standby_reset_n_i(1'b1),
    .clock_enable_i(1'b1), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
    .standby_power_ok_i(1'b1), .port1_i(8'hff), .port2_i(5'h1f),
    .port3_i(8'hff), .port4_i(8'hff), .is3_n_i(1'b1),
    .program_data_i(8'hff), .external_data_i(8'hff),
    .program_address_o(), .program_read_o(program_read4),
    .external_address_o(address4), .external_data_o(), .external_write_o(),
    .external_bus_valid_o(valid4), .external_opcode_fetch_o(), .port1_o(),
    .port1_oe_o(), .port2_o(), .port2_oe_o(), .port3_o(), .port3_oe_o(),
    .port4_o(), .port4_oe_o(), .os3_n_o(), .sci_tx_o(), .sci_clock_o(),
    .timer_irq_o(), .sci_irq_o(), .opcode_fetch_o(), .retire_o(retire4),
    .illegal_o(), .undefined_o(), .waiting_o(), .sleeping_o(),
    .interrupt_ack_o(), .operating_mode_o(), .debug_address_o(), .debug_pc_o(), .debug_sp_o(),
    .debug_a_o(a4), .debug_b_o(), .debug_x_o(), .debug_ccr_o(),
    .debug_timer_o(), .debug_output_compare_o(), .debug_input_capture_o(),
    .debug_tcsr_o(), .debug_trcsr_o(), .debug_receive_data_o(),
    .debug_opcode_o(opcode4)
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always #5 clk <= ~clk;

  always @(posedge clk) begin
    if (mode0_monitor_enable && valid0 && !write0 &&
        ((address0 == 16'hfffe) || (address0 == 16'hffff))) begin
      mode0_vector_reads <= mode0_vector_reads + 1;
    end
    if (valid0 && write0) external0[address0] <= data_out0;
  end

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    mode0_vector_reads = 0;
    mode4_retires = 0;
    mode0_complete = 1'b0;
    mode4_complete = 1'b0;
    mode0_internal_vector_seen = 1'b0;
    mode0_monitor_enable = 1'b0;
    for (index = 0; index < 65536; index = index + 1) begin
      external0[index] = 8'h01;
      program0[index] = 8'hff;
    end

    // Mode 0 obtains control from the external reset vector, then the program
    // reads the same address from internal ROM.
    external0[16'hfffe] = 8'h02;
    external0[16'hffff] = 8'h00;
    external0[16'h0200] = 8'hb6; // LDAA $FFFE
    external0[16'h0201] = 8'hff;
    external0[16'h0202] = 8'hfe;
    external0[16'h0203] = 8'h20;
    external0[16'h0204] = 8'hfe;
    program0[16'hfffe] = 8'ha5;

    // Mode 4 decodes FFFE:FFFF and the program through physical RAM aliases.
    mode4.ram[8'h7e] = 8'h00;
    mode4.ram[8'h7f] = 8'h80;
    mode4.ram[8'h00] = 8'h86; // LDAA #$5A
    mode4.ram[8'h01] = 8'h5a;
    mode4.ram[8'h02] = 8'hb7; // STAA $1288 (mirrors physical byte 08)
    mode4.ram[8'h03] = 8'h12;
    mode4.ram[8'h04] = 8'h88;
    mode4.ram[8'h05] = 8'hb6; // LDAA $0088
    mode4.ram[8'h06] = 8'h00;
    mode4.ram[8'h07] = 8'h88;
    mode4.ram[8'h08] = 8'h00;
    mode4.ram[8'h09] = 8'h20;
    mode4.ram[8'h0a] = 8'hfe;

    #1; reset_n = 1'b0; #1;
    if (!valid0 || address0 != 16'hfffe || program_read0 || valid4 || program_read4 ||
        address4 != 16'hfffe) begin
      $fatal(1, "mode0/mode4 reset-vector source at assertion");
    end
    tick();
    reset_n = 1'b1;
    mode0_monitor_enable = 1'b1;

    for (cycles = 0; cycles < 80; cycles = cycles + 1) begin
      tick();
      if (program_read0 && (program_address0 == 16'hfffe))
        mode0_internal_vector_seen = 1'b1;
      if (retire0 && opcode0 == 8'hb6) begin
        if (a0 != 8'ha5) $fatal(1, "mode0 later internal vector read %02x", a0);
        mode0_complete = 1'b1;
      end
      if (retire4) begin
        mode4_retires = mode4_retires + 1;
        if (mode4_retires == 3) begin
          if (opcode4 != 8'hb6 || a4 != 8'h5a || mode4.ram[8'h08] != 8'h5a)
            $fatal(1, "mode4 mirrored execution/data path");
          mode4_complete = 1'b1;
        end
      end
      if (mode0_complete && mode4_complete) cycles = 80;
    end

    if (!mode0_complete || !mode4_complete || !mode0_internal_vector_seen ||
        mode0_vector_reads != 2) begin
      $fatal(1, "mode boot completion mode0=%0b mode4=%0b internal=%0b vector_reads=%0d",
             mode0_complete, mode4_complete, mode0_internal_vector_seen,
             mode0_vector_reads);
    end
    if (valid4 || program_read4)
      $fatal(1, "mode4 exposed external/program transaction after boot");
    $display("MC6801 MODE BOOT PASS: Mode 0 external-to-internal vector handoff and Mode 4 RAM mirror");
    $finish;
  end
endmodule
