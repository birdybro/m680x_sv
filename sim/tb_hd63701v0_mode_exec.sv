// SPDX-License-Identifier: MIT
module tb_hd63701v0_mode_exec;
  logic clk;
  logic reset_n;
  logic monitor_enable;
  logic [15:0] program_address [0:5];
  logic program_read [0:5];
  logic [15:0] external_address [0:5];
  logic external_write [0:5];
  logic external_valid [0:5];
  logic retire [0:5];
  logic illegal [0:5];
  logic undefined_value [0:5];
  logic interrupt_ack [0:5];
  logic [15:0] debug_pc [0:5];
  logic [15:0] debug_sp [0:5];
  logic [7:0] debug_a [0:5];
  logic [7:0] memory [0:65535];
  integer retire_count [0:5];
  integer external_vector_reads [0:5];
  integer program_reads [0:5];
  integer external_program_reads [0:5];
  integer trap_program_reads [0:5];
  integer trap_external_reads [0:5];
  integer trap_acknowledges [0:5];
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
        .standby_power_ok_i(1'b1), .port1_i(8'hff), .port2_i(5'h1f),
        .port3_i(8'hff), .port4_i(8'hff), .is3_n_i(1'b1),
        .program_address_o(program_address[device_index]),
        .program_read_o(program_read[device_index]),
        .program_data_i(memory[program_address[device_index]]),
        .prom_mode_i(1'b0), .prom_program_voltage_i(1'b0),
        .prom_address_o(), .prom_data_o(), .prom_data_oe_o(),
        .prom_program_data_o(), .prom_program_o(),
        .external_address_o(external_address[device_index]),
        .external_data_o(),
        .external_write_o(external_write[device_index]),
        .external_bus_valid_o(external_valid[device_index]),
        .external_opcode_fetch_o(),
        .external_data_i(memory[external_address[device_index]]),
        .port1_o(), .port1_oe_o(), .port2_o(), .port2_oe_o(),
        .port3_o(), .port3_oe_o(), .port4_o(), .port4_oe_o(), .os3_n_o(),
        .sci_tx_o(), .sci_clock_o(), .timer_irq_o(), .sci_irq_o(),
        .opcode_fetch_o(), .retire_o(retire[device_index]),
        .illegal_o(illegal[device_index]),
        .undefined_o(undefined_value[device_index]), .waiting_o(), .sleeping_o(),
        .interrupt_ack_o(interrupt_ack[device_index]), .debug_address_o(),
        .debug_pc_o(debug_pc[device_index]), .debug_sp_o(debug_sp[device_index]),
        .debug_a_o(debug_a[device_index]), .debug_b_o(),
        .debug_x_o(), .debug_ccr_o(), .debug_timer_o(),
        .debug_output_compare_o(), .debug_input_capture_o(), .debug_tcsr_o(),
        .debug_trcsr_o(), .debug_receive_data_o(), .debug_opcode_o()
      );
      /* verilator lint_on PINCONNECTEMPTY */
    end
  endgenerate

  always #5 clk <= ~clk;

  always @(posedge clk) begin
    if (monitor_enable) begin
      for (integer index = 0; index < 6; index = index + 1) begin
        if (retire[index]) retire_count[index] <= retire_count[index] + 1;
        if (external_valid[index] && !external_write[index] &&
            (external_address[index] >= 16'hfffe)) begin
          external_vector_reads[index] <= external_vector_reads[index] + 1;
        end
        if (program_read[index]) program_reads[index] <= program_reads[index] + 1;
        if (external_valid[index] && !external_write[index] &&
            (external_address[index] >= 16'hf000) &&
            (external_address[index] < 16'hfffe)) begin
          external_program_reads[index] <= external_program_reads[index] + 1;
        end
        if (program_read[index] &&
            ((program_address[index] == 16'hffee) ||
             (program_address[index] == 16'hffef))) begin
          trap_program_reads[index] <= trap_program_reads[index] + 1;
        end
        if (external_valid[index] && !external_write[index] &&
            ((external_address[index] == 16'hffee) ||
             (external_address[index] == 16'hffef))) begin
          trap_external_reads[index] <= trap_external_reads[index] + 1;
        end
        if (interrupt_ack[index])
          trap_acknowledges[index] <= trap_acknowledges[index] + 1;
      end
    end
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
    monitor_enable = 1'b0;
    checks = 0;
    for (integer index = 0; index < 6; index = index + 1) begin
      retire_count[index] = 0;
      external_vector_reads[index] = 0;
      program_reads[index] = 0;
      external_program_reads[index] = 0;
      trap_program_reads[index] = 0;
      trap_external_reads[index] = 0;
      trap_acknowledges[index] = 0;
    end
    for (integer address_index = 0; address_index < 65536; address_index = address_index + 1)
      memory[address_index] = 8'h01;

    // Every legal mode executes from the documented program source and uses
    // the shared physical RAM at its V0-specific lower boundary.
    memory[16'hf000] = 8'h8e; memory[16'hf001] = 8'h00;
    memory[16'hf002] = 8'hff;
    memory[16'hf003] = 8'h86; memory[16'hf004] = 8'ha5;
    memory[16'hf005] = 8'h97; memory[16'hf006] = 8'h40;
    memory[16'hf007] = 8'h96; memory[16'hf008] = 8'h40;
    memory[16'hf009] = 8'h7e; memory[16'hf00a] = 8'h00;
    memory[16'hf00b] = 8'h1f;
    memory[16'hf100] = 8'h86; memory[16'hf101] = 8'h5a;
    memory[16'hf102] = 8'h20; memory[16'hf103] = 8'hfe;
    memory[16'hffee] = 8'hf1; memory[16'hffef] = 8'h00;
    memory[16'hfffe] = 8'hf0; memory[16'hffff] = 8'h00;

    #1; reset_n = 1'b0; #1; reset_n = 1'b1;
    monitor_enable = 1'b1;
    for (integer cycle_index = 0; cycle_index < 120; cycle_index = cycle_index + 1)
      tick();

    for (integer index = 0; index < 6; index = index + 1) begin
      if ((retire_count[index] < 7) || (debug_a[index] !== 8'h5a) ||
          (debug_pc[index] < 16'hf102) || (debug_pc[index] > 16'hf104) ||
          illegal[index] || undefined_value[index]) begin
        $fatal(1, "HD63701V0 mode execution device=%0d retire=%0d pc=%04x a=%02x",
               index, retire_count[index], debug_pc[index], debug_a[index]);
      end
      // Modes 1/2 expose both reset-vector reads and the two documented
      // address-TRAP dummy reads at FFFF. Mode 0 hands later FFFF reads to
      // internal EPROM after its initial external reset-vector pair.
      if (external_vector_reads[index] !==
          ((index == 0) ? 2 : (((index == 1) || (index == 2)) ? 4 : 0))) begin
        $fatal(1, "HD63701V0 vector source device=%0d reads=%0d",
               index, external_vector_reads[index]);
      end
      if ((index == 0) || (index >= 3)) begin
        if ((program_reads[index] == 0) || (external_program_reads[index] != 0))
          $fatal(1, "HD63701V0 internal program source device=%0d", index);
      end else begin
        if ((program_reads[index] != 0) || (external_program_reads[index] == 0))
          $fatal(1, "HD63701V0 external program source device=%0d", index);
      end
      if ((trap_acknowledges[index] != 1) ||
          (debug_sp[index] !== 16'h00f8)) begin
        $fatal(1, "HD63701V0 address TRAP device=%0d ack=%0d sp=%04x",
               index, trap_acknowledges[index], debug_sp[index]);
      end
      if ((index == 1) || (index == 2)) begin
        if ((trap_external_reads[index] != 2) || (trap_program_reads[index] != 0))
          $fatal(1, "HD63701V0 external TRAP vector device=%0d ext=%0d rom=%0d",
                 index, trap_external_reads[index], trap_program_reads[index]);
      end else if ((trap_program_reads[index] != 2) ||
                   (trap_external_reads[index] != 0)) begin
        $fatal(1, "HD63701V0 EPROM TRAP vector device=%0d ext=%0d rom=%0d",
               index, trap_external_reads[index], trap_program_reads[index]);
      end
      checks = checks + 5;
    end

    $display("HD63701V0 MODE EXEC PASS: %0d six-mode execution, source, and TRAP checks",
             checks);
    $finish;
  end
endmodule
