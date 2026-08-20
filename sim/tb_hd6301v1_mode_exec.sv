// SPDX-License-Identifier: MIT
module tb_hd6301v1_mode_exec;
  logic clk;
  // The device deliberately combines asynchronous CPU reset with the
  // manufacturer-documented E-synchronous DDR reset boundary.
  /* verilator lint_off SYNCASYNCNET */
  logic reset_n;
  /* verilator lint_on SYNCASYNCNET */
  logic monitor_enable;
  logic [15:0] program_address [0:6];
  logic program_read [0:6];
  logic [15:0] external_address [0:6];
  logic external_write [0:6];
  logic external_valid [0:6];
  logic retire [0:6];
  logic illegal [0:6];
  logic undefined_value [0:6];
  logic [15:0] debug_pc [0:6];
  logic [7:0] debug_a [0:6];
  logic [7:0] memory [0:65535];
  integer retire_count [0:6];
  integer external_vector_reads [0:6];
  integer program_reads [0:6];
  integer external_program_reads [0:6];
  integer checks;

  generate
    for (genvar device_index = 0; device_index < 7; device_index = device_index + 1) begin : mode_devices
      localparam logic [2:0] DEVICE_MODE =
        (device_index == 0) ? 3'd0 :
        (device_index == 1) ? 3'd1 :
        (device_index == 2) ? 3'd2 :
        (device_index == 3) ? 3'd4 :
        (device_index == 4) ? 3'd5 :
        (device_index == 5) ? 3'd6 : 3'd7;
      /* verilator lint_off PINCONNECTEMPTY */
      hd6301v1_mcu #(.OPERATING_MODE(DEVICE_MODE)) dut (
        .clk_i(clk), .reset_n_i(reset_n), .standby_n_i(1'b1),
        .clock_enable_i(1'b1), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
        .standby_power_ok_i(1'b1), .port1_i(8'hff), .port2_i(5'h1f),
        .port3_i(8'hff), .port4_i(8'hff), .is3_n_i(1'b1),
        .program_address_o(program_address[device_index]),
        .program_read_o(program_read[device_index]),
        .program_data_i(memory[program_address[device_index]]),
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
        .interrupt_ack_o(), .debug_address_o(), .debug_pc_o(debug_pc[device_index]),
        .debug_sp_o(), .debug_a_o(debug_a[device_index]), .debug_b_o(),
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
      for (integer index = 0; index < 7; index = index + 1) begin
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
    for (integer index = 0; index < 7; index = index + 1) begin
      retire_count[index] = 0;
      external_vector_reads[index] = 0;
      program_reads[index] = 0;
      external_program_reads[index] = 0;
    end
    for (integer address_index = 0; address_index < 65536; address_index = address_index + 1)
      memory[address_index] = 8'h01;

    // Every legal mode executes the same program. Its storage source differs
    // by mode, but the register/RAM architectural result must not.
    memory[16'hf000] = 8'h8e; memory[16'hf001] = 8'h00;
    memory[16'hf002] = 8'hff;
    memory[16'hf003] = 8'h86; memory[16'hf004] = 8'ha5;
    memory[16'hf005] = 8'h97; memory[16'hf006] = 8'h80;
    memory[16'hf007] = 8'h96; memory[16'hf008] = 8'h80;
    memory[16'hf009] = 8'h20; memory[16'hf00a] = 8'hfe;
    memory[16'hfffe] = 8'hf0; memory[16'hffff] = 8'h00;

    #1; reset_n = 1'b0; #1; reset_n = 1'b1;
    monitor_enable = 1'b1;
    for (integer cycle_index = 0; cycle_index < 80; cycle_index = cycle_index + 1)
      tick();

    for (integer index = 0; index < 7; index = index + 1) begin
      if ((retire_count[index] < 5) || (debug_a[index] !== 8'ha5) ||
          (debug_pc[index] < 16'hf009) || illegal[index] || undefined_value[index]) begin
        $fatal(1, "HD6301V1 mode execution device=%0d retire=%0d pc=%04x a=%02x",
               index, retire_count[index], debug_pc[index], debug_a[index]);
      end
      if (external_vector_reads[index] !== ((index <= 3) ? 2 : 0)) begin
        $fatal(1, "HD6301V1 vector source device=%0d reads=%0d",
               index, external_vector_reads[index]);
      end
      if ((index == 0) || (index >= 4)) begin
        if ((program_reads[index] == 0) || (external_program_reads[index] != 0))
          $fatal(1, "HD6301V1 internal program source device=%0d", index);
      end else begin
        if ((program_reads[index] != 0) || (external_program_reads[index] == 0))
          $fatal(1, "HD6301V1 external program source device=%0d", index);
      end
      checks = checks + 4;
    end

    $display("HD6301V1 MODE EXEC PASS: %0d seven-mode execution and source checks", checks);
    $finish;
  end
endmodule
