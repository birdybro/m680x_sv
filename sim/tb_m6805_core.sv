// SPDX-License-Identifier: MIT
module tb_m6805_core;
  logic clk;
  logic reset_n;
  logic clock_enable;
  logic bus_ready;
  logic irq_n;
  logic [7:0] data_in;
  logic [15:0] address;
  logic [7:0] data_out;
  logic write_enable;
  logic bus_valid;
  logic opcode_fetch;
  logic retire;
  logic illegal;
  logic undefined_value;
  logic waiting_state;
  logic stopped_state;
  logic interrupt_ack;
  logic [7:0] debug_a;
  logic [7:0] debug_x;
  logic [15:0] debug_sp;
  logic [15:0] debug_pc;
  logic [4:0] debug_ccr;
  logic [7:0] debug_opcode;
  logic [3:0] debug_cycles;
  logic [7:0] memory [0:65535];
  logic [15:0] trace_address [0:15];
  logic [7:0] trace_data [0:15];
  logic trace_write [0:15];
  logic trace_valid [0:15];
  logic trace_opcode_fetch [0:15];
  integer index;
  integer cycle_count;
  integer reset_cycle;
  integer cases;

  m6805_core dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(clock_enable),
    .bus_ready_i(bus_ready), .irq_n_i(irq_n), .interrupt_pin_n_i(irq_n),
    .irq_vector_i(16'hfffa), .data_i(data_in),
    .address_o(address), .data_o(data_out), .write_o(write_enable),
    .bus_valid_o(bus_valid), .opcode_fetch_o(opcode_fetch), .retire_o(retire),
    .illegal_o(illegal), .undefined_o(undefined_value), .waiting_o(waiting_state),
    .stopped_o(stopped_state), .interrupt_ack_o(interrupt_ack),
    .debug_a_o(debug_a), .debug_x_o(debug_x), .debug_sp_o(debug_sp),
    .debug_pc_o(debug_pc), .debug_ccr_o(debug_ccr), .debug_opcode_o(debug_opcode),
    .debug_instruction_cycles_o(debug_cycles)
  );

  assign data_in = memory[address];
  always #5 clk <= ~clk;
  always @(posedge clk) begin
    if (clock_enable && bus_ready && bus_valid && write_enable) memory[address] <= data_out;
  end

  task automatic tick;
    begin @(posedge clk); #1; end
  endtask

  task automatic run_instruction(input integer expected_cycles, input logic [7:0] expected_opcode);
    begin
      cycle_count = 0;
      do begin
        trace_address[cycle_count] = address;
        trace_data[cycle_count] = write_enable ? data_out : data_in;
        trace_write[cycle_count] = write_enable;
        trace_valid[cycle_count] = bus_valid;
        trace_opcode_fetch[cycle_count] = opcode_fetch;
        tick();
        cycle_count = cycle_count + 1;
        if (cycle_count > 15) $fatal(1, "M6805 opcode %02x did not retire", expected_opcode);
      end while (!retire);
      if (cycle_count != expected_cycles || debug_cycles != expected_cycles[3:0] ||
          debug_opcode != expected_opcode || !opcode_fetch) begin
        $fatal(1, "M6805 opcode %02x timing mismatch %0d/%0d", expected_opcode, cycle_count, expected_cycles);
      end
      cases = cases + 1;
    end
  endtask

  task automatic run_interrupt;
    begin
      cycle_count = 0;
      do begin
        trace_address[cycle_count] = address;
        trace_data[cycle_count] = write_enable ? data_out : data_in;
        trace_write[cycle_count] = write_enable;
        trace_valid[cycle_count] = bus_valid;
        trace_opcode_fetch[cycle_count] = opcode_fetch;
        tick();
        cycle_count = cycle_count + 1;
        if (cycle_count > 14) $fatal(1, "M6805 IRQ did not acknowledge");
      end while (!interrupt_ack);
      if (cycle_count != 11) $fatal(1, "M6805 IRQ timing %0d/11", cycle_count);
      cases = cases + 1;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    clock_enable = 1'b1;
    bus_ready = 1'b1;
    irq_n = 1'b1;
    cases = 0;
    for (index = 0; index < 65536; index = index + 1) memory[index] = 8'h00;
    memory[16'hfffe] = 8'h10;
    memory[16'hffff] = 8'h00;
    memory[16'hfffa] = 8'h12;
    memory[16'hfffb] = 8'h00;
    memory[16'hfffc] = 8'h13;
    memory[16'hfffd] = 8'h00;
    memory[16'h1000] = 8'h9a; // CLI
    memory[16'h1001] = 8'ha6; // LDA #$7f
    memory[16'h1002] = 8'h7f;
    memory[16'h1003] = 8'hab; // ADD #$01
    memory[16'h1004] = 8'h01;
    memory[16'h1005] = 8'hb7; // STA $20
    memory[16'h1006] = 8'h20;
    memory[16'h1007] = 8'had; // BSR $100b
    memory[16'h1008] = 8'h02;
    memory[16'h1009] = 8'h9d; // NOP
    memory[16'h100b] = 8'h4c; // INCA
    memory[16'h100c] = 8'h81; // RTS
    memory[16'h1200] = 8'h80; // RTI
    memory[16'h1300] = 8'h80; // SWI handler first opcode: RTI

    #1;
    reset_n = 1'b0;
    #1;
    if (!bus_valid || address != 16'hfffe || write_enable) $fatal(1, "M6805 reset high vector");
    reset_n = 1'b1;
    for (reset_cycle = 0; reset_cycle < 8; reset_cycle = reset_cycle + 1) begin
      if (!bus_valid || write_enable || opcode_fetch ||
          ((reset_cycle < 6) && (address != 16'hfffe)) ||
          ((reset_cycle == 6) && (address != 16'hffff)) ||
          ((reset_cycle == 7) && (address != 16'h0000))) begin
        $fatal(1, "M6805 reset cycle %0d address=%04x valid=%b write=%b fetch=%b",
               reset_cycle + 1, address, bus_valid, write_enable, opcode_fetch);
      end
      tick();
    end
    if (debug_pc != 16'h1000 || debug_sp != 16'h007f || !debug_ccr[3]) begin
      $fatal(1, "M6805 reset state");
    end
    cases = cases + 1;

    clock_enable = 1'b0;
    tick();
    if (debug_pc != 16'h1000 || address != 16'h1000) $fatal(1, "M6805 clock-enable stall");
    clock_enable = 1'b1;
    bus_ready = 1'b0;
    tick();
    if (debug_pc != 16'h1000 || address != 16'h1000) $fatal(1, "M6805 ready stall");
    bus_ready = 1'b1;
    cases = cases + 2;

    run_instruction(2, 8'h9a);
    run_instruction(2, 8'ha6);
    run_instruction(2, 8'hab);
    if (debug_a != 8'h80 || !debug_ccr[4] || !debug_ccr[2] || debug_ccr[1] || debug_ccr[0]) begin
      $fatal(1, "M6805 ADD result/flags");
    end
    run_instruction(5, 8'hb7);
    if (memory[16'h0020] != 8'h80 ||
        trace_address[2] != 16'h007f || trace_write[2] ||
        trace_address[3] != 16'h0020 || trace_write[3] || trace_data[3] != 8'h00 ||
        !trace_write[4] || trace_address[4] != 16'h0020 || trace_data[4] != 8'h80) begin
      $fatal(1, "M6805 direct store trace");
    end
    run_instruction(8, 8'had);
    if (debug_pc != 16'h100b || debug_sp != 16'h007d ||
        memory[16'h007f] != 8'h09 || memory[16'h007e] != 8'h10 ||
        !trace_valid[0] || trace_write[0] || !trace_opcode_fetch[0] || trace_address[0] != 16'h1007 ||
        !trace_valid[1] || trace_write[1] || trace_opcode_fetch[1] || trace_address[1] != 16'h1008 ||
        !trace_valid[2] || trace_write[2] || trace_address[2] != 16'h1009 ||
        !trace_valid[3] || trace_write[3] || trace_address[3] != 16'h1009 ||
        !trace_valid[4] || trace_write[4] || trace_address[4] != 16'h100b || trace_data[4] != 8'h4c ||
        !trace_valid[5] || !trace_write[5] || trace_address[5] != 16'h007f || trace_data[5] != 8'h09 ||
        !trace_valid[6] || !trace_write[6] || trace_address[6] != 16'h007e || trace_data[6] != 8'h10 ||
        !trace_valid[7] || trace_write[7] || trace_address[7] != 16'h007d) begin
      $fatal(1, "M6805 BSR stack order");
    end
    run_instruction(4, 8'h4c);
    if (!trace_valid[0] || trace_write[0] || !trace_opcode_fetch[0] || trace_address[0] != 16'h100b ||
        !trace_valid[1] || trace_write[1] || trace_opcode_fetch[1] || trace_address[1] != 16'h100c ||
        !trace_valid[2] || trace_write[2] || trace_address[2] != 16'h100d ||
        !trace_valid[3] || trace_write[3] || trace_address[3] != 16'h100d) begin
      $fatal(1, "M6805 accumulator inherent trace");
    end
    run_instruction(6, 8'h81);
    if (debug_pc != 16'h1009 || debug_sp != 16'h007f || debug_a != 8'h81) begin
      $fatal(1, "M6805 RTS restore");
    end
    if (!trace_valid[0] || trace_write[0] || !trace_opcode_fetch[0] || trace_address[0] != 16'h100c ||
        !trace_valid[1] || trace_write[1] || trace_opcode_fetch[1] || trace_address[1] != 16'h100d ||
        !trace_valid[2] || trace_write[2] || trace_address[2] != 16'h007d ||
        !trace_valid[3] || trace_write[3] || trace_address[3] != 16'h007e || trace_data[3] != 8'h10 ||
        !trace_valid[4] || trace_write[4] || trace_address[4] != 16'h007f || trace_data[4] != 8'h09 ||
        !trace_valid[5] || trace_write[5] || trace_address[5] != 16'h0060) begin
      $fatal(1, "M6805 RTS exact trace");
    end
    run_instruction(2, 8'h9d);
    if (!trace_valid[0] || trace_write[0] || !trace_opcode_fetch[0] || trace_address[0] != 16'h1009 ||
        !trace_valid[1] || trace_write[1] || trace_opcode_fetch[1] || trace_address[1] != 16'h100a) begin
      $fatal(1, "M6805 simple inherent trace");
    end

    irq_n = 1'b0;
    run_interrupt();
    if (debug_pc != 16'h1200 || debug_sp != 16'h007a || !debug_ccr[3] ||
        !trace_valid[0] || trace_write[0] || !trace_opcode_fetch[0] ||
        trace_address[0] != 16'h100a || trace_data[0] != 8'h00 ||
        !trace_valid[1] || trace_write[1] || trace_opcode_fetch[1] ||
        trace_address[1] != 16'h100a || trace_data[1] != 8'h00 ||
        !trace_valid[2] || !trace_write[2] || trace_address[2] != 16'h007f || trace_data[2] != 8'h0a ||
        !trace_valid[3] || !trace_write[3] || trace_address[3] != 16'h007e || trace_data[3] != 8'h10 ||
        !trace_valid[4] || !trace_write[4] || trace_address[4] != 16'h007d || trace_data[4] != 8'h00 ||
        !trace_valid[5] || !trace_write[5] || trace_address[5] != 16'h007c || trace_data[5] != 8'h81 ||
        !trace_valid[6] || !trace_write[6] || trace_address[6] != 16'h007b || trace_data[6] != 8'hf4 ||
        !trace_valid[7] || trace_write[7] || trace_address[7] != 16'h007a ||
        !trace_valid[8] || trace_write[8] || trace_address[8] != 16'hfffa || trace_data[8] != 8'h12 ||
        !trace_valid[9] || trace_write[9] || trace_address[9] != 16'hfffb || trace_data[9] != 8'h00 ||
        !trace_valid[10] || trace_write[10] || trace_address[10] != 16'hfffc) begin
      $fatal(1, "M6805 IRQ frame/vector trace");
    end
    irq_n = 1'b1;
    run_instruction(9, 8'h80);
    if (debug_pc != 16'h100a || debug_sp != 16'h007f || debug_a != 8'h81 ||
        debug_x != 8'h00 || debug_ccr[3] || illegal || undefined_value ||
        waiting_state || stopped_state) begin
      $fatal(1, "M6805 RTI state restore");
    end
    if (!trace_valid[0] || trace_write[0] || !trace_opcode_fetch[0] || trace_address[0] != 16'h1200 ||
        !trace_valid[1] || trace_write[1] || trace_opcode_fetch[1] || trace_address[1] != 16'h1201 ||
        !trace_valid[2] || trace_write[2] || trace_address[2] != 16'h007a ||
        !trace_valid[3] || trace_write[3] || trace_address[3] != 16'h007b || trace_data[3] != 8'hf4 ||
        !trace_valid[4] || trace_write[4] || trace_address[4] != 16'h007c || trace_data[4] != 8'h81 ||
        !trace_valid[5] || trace_write[5] || trace_address[5] != 16'h007d || trace_data[5] != 8'h00 ||
        !trace_valid[6] || trace_write[6] || trace_address[6] != 16'h007e || trace_data[6] != 8'h10 ||
        !trace_valid[7] || trace_write[7] || trace_address[7] != 16'h007f || trace_data[7] != 8'h0a ||
        !trace_valid[8] || trace_write[8] || trace_address[8] != 16'h0060) begin
      $fatal(1, "M6805 RTI exact trace");
    end

    memory[16'h100a] = 8'h20; // BRA $100c
    memory[16'h100b] = 8'h00;
    run_instruction(4, 8'h20);
    if (debug_pc != 16'h100c ||
        !trace_valid[0] || trace_write[0] || !trace_opcode_fetch[0] || trace_address[0] != 16'h100a ||
        !trace_valid[1] || trace_write[1] || trace_opcode_fetch[1] || trace_address[1] != 16'h100b ||
        !trace_valid[2] || trace_write[2] || trace_address[2] != 16'h100c ||
        !trace_valid[3] || trace_write[3] || trace_address[3] != 16'h100c) begin
      $fatal(1, "M6805 relative branch exact trace");
    end

    memory[16'h100c] = 8'h83; // SWI
    run_instruction(11, 8'h83);
    if (debug_pc != 16'h1300 || debug_sp != 16'h007a ||
        !trace_valid[0] || trace_write[0] || !trace_opcode_fetch[0] ||
        trace_address[0] != 16'h100c ||
        !trace_valid[1] || trace_write[1] || trace_opcode_fetch[1] ||
        trace_address[1] != 16'h100d ||
        !trace_valid[2] || !trace_write[2] || trace_address[2] != 16'h007f || trace_data[2] != 8'h0d ||
        !trace_valid[3] || !trace_write[3] || trace_address[3] != 16'h007e || trace_data[3] != 8'h10 ||
        !trace_valid[4] || !trace_write[4] || trace_address[4] != 16'h007d || trace_data[4] != 8'h00 ||
        !trace_valid[5] || !trace_write[5] || trace_address[5] != 16'h007c || trace_data[5] != 8'h81 ||
        !trace_valid[6] || !trace_write[6] || trace_address[6] != 16'h007b || trace_data[6] != 8'hf4 ||
        !trace_valid[7] || trace_write[7] || trace_address[7] != 16'h007a ||
        !trace_valid[8] || trace_write[8] || trace_address[8] != 16'hfffc || trace_data[8] != 8'h13 ||
        !trace_valid[9] || trace_write[9] || trace_address[9] != 16'hfffd || trace_data[9] != 8'h00 ||
        !trace_valid[10] || trace_write[10] || trace_opcode_fetch[10] ||
        trace_address[10] != 16'h1300 || trace_data[10] != 8'h80) begin
      $fatal(1, "M6805 SWI frame/vector/handler-prefetch trace");
    end

    run_instruction(9, 8'h80);
    if (debug_pc != 16'h100d || debug_sp != 16'h007f) begin
      $fatal(1, "M6805 post-SWI RTI restore");
    end

    memory[16'h100d] = 8'h10; // BSET0 $20
    memory[16'h100e] = 8'h20;
    run_instruction(7, 8'h10);
    if (memory[16'h0020] != 8'h81 ||
        !trace_valid[0] || trace_write[0] || !trace_opcode_fetch[0] || trace_address[0] != 16'h100d ||
        !trace_valid[1] || trace_write[1] || trace_address[1] != 16'h100e ||
        !trace_valid[2] || trace_write[2] || trace_address[2] != 16'h007f ||
        !trace_valid[3] || trace_write[3] || trace_address[3] != 16'h0020 || trace_data[3] != 8'h80 ||
        !trace_valid[4] || trace_write[4] || trace_address[4] != 16'h0020 || trace_data[4] != 8'h80 ||
        !trace_valid[5] || trace_write[5] || trace_address[5] != 16'h0020 || trace_data[5] != 8'h80 ||
        !trace_valid[6] || !trace_write[6] || trace_address[6] != 16'h0020 || trace_data[6] != 8'h81) begin
      $fatal(1, "M6805 BSET table-G2 trace");
    end

    memory[16'h100f] = 8'h00; // BRSET0 $20,$1014
    memory[16'h1010] = 8'h20;
    memory[16'h1011] = 8'h02;
    run_instruction(10, 8'h00);
    if (debug_pc != 16'h1014 || !debug_ccr[0] ||
        !trace_valid[0] || trace_write[0] || !trace_opcode_fetch[0] || trace_address[0] != 16'h100f ||
        !trace_valid[1] || trace_write[1] || trace_address[1] != 16'h1010 ||
        !trace_valid[2] || trace_write[2] || trace_address[2] != 16'h007f ||
        !trace_valid[3] || trace_write[3] || trace_address[3] != 16'h0020 || trace_data[3] != 8'h81 ||
        !trace_valid[4] || trace_write[4] || trace_address[4] != 16'h0020 || trace_data[4] != 8'h81 ||
        !trace_valid[5] || trace_write[5] || trace_address[5] != 16'h0020 || trace_data[5] != 8'h81 ||
        !trace_valid[6] || trace_write[6] || trace_address[6] != 16'h0020 || trace_data[6] != 8'h81 ||
        !trace_valid[7] || trace_write[7] || trace_address[7] != 16'h1011 || trace_data[7] != 8'h02 ||
        !trace_valid[8] || trace_write[8] || trace_address[8] != 16'h1012 ||
        !trace_valid[9] || trace_write[9] || trace_address[9] != 16'h1012) begin
      $fatal(1, "M6805 BRSET table-G2 trace");
    end

    memory[16'h0021] = 8'h5a;
    memory[16'h1014] = 8'hb6; // LDA $21
    memory[16'h1015] = 8'h21;
    run_instruction(4, 8'hb6);
    if (debug_a != 8'h5a ||
        !trace_valid[0] || trace_write[0] || trace_address[0] != 16'h1014 ||
        !trace_valid[1] || trace_write[1] || trace_address[1] != 16'h1015 ||
        !trace_valid[2] || trace_write[2] || trace_address[2] != 16'h007f ||
        !trace_valid[3] || trace_write[3] || trace_address[3] != 16'h0021 || trace_data[3] != 8'h5a) begin
      $fatal(1, "M6805 direct read table-G2 trace");
    end

    memory[16'h1016] = 8'hb7; // STA $22
    memory[16'h1017] = 8'h22;
    run_instruction(5, 8'hb7);
    if (memory[16'h0022] != 8'h5a ||
        trace_address[0] != 16'h1016 || trace_write[0] ||
        trace_address[1] != 16'h1017 || trace_write[1] ||
        trace_address[2] != 16'h007f || trace_write[2] ||
        trace_address[3] != 16'h0022 || trace_write[3] ||
        trace_address[4] != 16'h0022 || !trace_write[4] || trace_data[4] != 8'h5a) begin
      $fatal(1, "M6805 direct store table-G2 trace");
    end

    memory[16'h1018] = 8'h3c; // INC $22
    memory[16'h1019] = 8'h22;
    run_instruction(6, 8'h3c);
    if (memory[16'h0022] != 8'h5b ||
        trace_address[0] != 16'h1018 || trace_write[0] ||
        trace_address[1] != 16'h1019 || trace_write[1] ||
        trace_address[2] != 16'h007f || trace_write[2] ||
        trace_address[3] != 16'h0022 || trace_write[3] || trace_data[3] != 8'h5a ||
        trace_address[4] != 16'h0022 || trace_write[4] || trace_data[4] != 8'h5a ||
        trace_address[5] != 16'h0022 || !trace_write[5] || trace_data[5] != 8'h5b) begin
      $fatal(1, "M6805 direct RMW table-G2 trace");
    end

    memory[16'h101a] = 8'h3d; // TST $22
    memory[16'h101b] = 8'h22;
    run_instruction(6, 8'h3d);
    if (trace_address[0] != 16'h101a || trace_write[0] ||
        trace_address[1] != 16'h101b || trace_write[1] ||
        trace_address[2] != 16'h007f || trace_write[2] ||
        trace_address[3] != 16'h0022 || trace_write[3] || trace_data[3] != 8'h5b ||
        trace_address[4] != 16'h0022 || trace_write[4] || trace_data[4] != 8'h5b ||
        trace_address[5] != 16'h0022 || trace_write[5] || trace_data[5] != 8'h5b) begin
      $fatal(1, "M6805 direct TST table-G2 trace");
    end

    memory[16'h101c] = 8'hbc; // JMP $30
    memory[16'h101d] = 8'h30;
    run_instruction(3, 8'hbc);
    if (debug_pc != 16'h0030 || trace_address[0] != 16'h101c || trace_write[0] ||
        trace_address[1] != 16'h101d || trace_write[1] ||
        trace_address[2] != 16'h007f || trace_write[2]) begin
      $fatal(1, "M6805 direct JMP table-G2 trace");
    end

    memory[16'h0030] = 8'hbd; // JSR $40
    memory[16'h0031] = 8'h40;
    memory[16'h0040] = 8'h81;
    run_instruction(7, 8'hbd);
    if (debug_pc != 16'h0040 || debug_sp != 16'h007d ||
        trace_address[0] != 16'h0030 || trace_write[0] ||
        trace_address[1] != 16'h0031 || trace_write[1] ||
        trace_address[2] != 16'h007f || trace_write[2] ||
        trace_address[3] != 16'h0040 || trace_write[3] || trace_data[3] != 8'h81 ||
        trace_address[4] != 16'h007f || !trace_write[4] || trace_data[4] != 8'h32 ||
        trace_address[5] != 16'h007e || !trace_write[5] || trace_data[5] != 8'h00 ||
        trace_address[6] != 16'h007d || trace_write[6]) begin
      $fatal(1, "M6805 direct JSR table-G2 trace");
    end

    run_instruction(6, 8'h81);
    if (debug_pc != 16'h0032 || debug_sp != 16'h007f) begin
      $fatal(1, "M6805 direct JSR return");
    end
    memory[16'h0032] = 8'hae; // LDX #$20
    memory[16'h0033] = 8'h20;
    run_instruction(2, 8'hae);

    memory[16'h0034] = 8'hf6; // LDA ,X
    run_instruction(4, 8'hf6);
    if (debug_a != 8'h81 || trace_address[0] != 16'h0034 || trace_write[0] ||
        trace_address[1] != 16'h0035 || trace_write[1] ||
        trace_address[2] != 16'h007f || trace_write[2] ||
        trace_address[3] != 16'h0020 || trace_write[3] || trace_data[3] != 8'h81) begin
      $fatal(1, "M6805 indexed-no-offset read table-G2 trace");
    end

    memory[16'h0035] = 8'he6; // LDA $02,X
    memory[16'h0036] = 8'h02;
    run_instruction(5, 8'he6);
    if (debug_a != 8'h5b || trace_address[0] != 16'h0035 || trace_write[0] ||
        trace_address[1] != 16'h0036 || trace_write[1] ||
        trace_address[2] != 16'h007f || trace_write[2] ||
        trace_address[3] != 16'h007f || trace_write[3] ||
        trace_address[4] != 16'h0022 || trace_write[4] || trace_data[4] != 8'h5b) begin
      $fatal(1, "M6805 indexed-8 read table-G2 trace");
    end

    memory[16'h0037] = 8'h7c; // INC ,X
    run_instruction(6, 8'h7c);
    if (memory[16'h0020] != 8'h82 || trace_address[0] != 16'h0037 || trace_write[0] ||
        trace_address[1] != 16'h0038 || trace_write[1] ||
        trace_address[2] != 16'h007f || trace_write[2] ||
        trace_address[3] != 16'h0020 || trace_write[3] || trace_data[3] != 8'h81 ||
        trace_address[4] != 16'h0020 || trace_write[4] || trace_data[4] != 8'h81 ||
        trace_address[5] != 16'h0020 || !trace_write[5] || trace_data[5] != 8'h82) begin
      $fatal(1, "M6805 indexed-no-offset RMW table-G2 trace");
    end

    memory[16'h0038] = 8'hed; // JSR $20,X -> $0040
    memory[16'h0039] = 8'h20;
    run_instruction(8, 8'hed);
    if (debug_pc != 16'h0040 || debug_sp != 16'h007d ||
        trace_address[0] != 16'h0038 || trace_write[0] ||
        trace_address[1] != 16'h0039 || trace_write[1] ||
        trace_address[2] != 16'h007f || trace_write[2] ||
        trace_address[3] != 16'h007f || trace_write[3] ||
        trace_address[4] != 16'h0040 || trace_write[4] || trace_data[4] != 8'h81 ||
        trace_address[5] != 16'h007f || !trace_write[5] || trace_data[5] != 8'h3a ||
        trace_address[6] != 16'h007e || !trace_write[6] || trace_data[6] != 8'h00 ||
        trace_address[7] != 16'h007d || trace_write[7]) begin
      $fatal(1, "M6805 indexed-8 JSR table-G2 trace");
    end

    memory[16'h0040] = 8'h81; // Return from indexed-8 JSR.
    run_instruction(6, 8'h81);
    if (debug_pc != 16'h003a || debug_sp != 16'h007f) begin
      $fatal(1, "M6805 indexed-8 JSR return");
    end

    memory[16'h003a] = 8'hc7; // STA $1234
    memory[16'h003b] = 8'h12;
    memory[16'h003c] = 8'h34;
    memory[16'h1234] = 8'ha5;
    run_instruction(6, 8'hc7);
    if (memory[16'h1234] != 8'h5b ||
        trace_address[0] != 16'h003a || trace_write[0] ||
        trace_address[1] != 16'h003b || trace_write[1] ||
        trace_address[2] != 16'h003c || trace_write[2] ||
        trace_address[3][7:0] != 8'hff || trace_write[3] ||
        trace_address[4] != 16'h1234 || trace_write[4] || trace_data[4] != 8'ha5 ||
        trace_address[5] != 16'h1234 || !trace_write[5] || trace_data[5] != 8'h5b) begin
      $fatal(1, "M6805 extended store table-G2 trace");
    end

    memory[16'h003d] = 8'hcd; // JSR $0050
    memory[16'h003e] = 8'h00;
    memory[16'h003f] = 8'h50;
    memory[16'h0050] = 8'h81;
    run_instruction(8, 8'hcd);
    if (debug_pc != 16'h0050 || debug_sp != 16'h007d ||
        trace_address[0] != 16'h003d || trace_write[0] ||
        trace_address[1] != 16'h003e || trace_write[1] ||
        trace_address[2] != 16'h003f || trace_write[2] ||
        trace_address[3][7:0] != 8'hff || trace_write[3] ||
        trace_address[4] != 16'h0050 || trace_write[4] || trace_data[4] != 8'h81 ||
        trace_address[5] != 16'h007f || !trace_write[5] || trace_data[5] != 8'h40 ||
        trace_address[6] != 16'h007e || !trace_write[6] || trace_data[6] != 8'h00 ||
        trace_address[7] != 16'h007d || trace_write[7]) begin
      $fatal(1, "M6805 extended JSR table-G2 trace");
    end

    run_instruction(6, 8'h81);
    if (debug_pc != 16'h0040 || debug_sp != 16'h007f) begin
      $fatal(1, "M6805 extended JSR return");
    end

    memory[16'h0120] = 8'ha9;
    memory[16'h0040] = 8'hd6; // LDA $0100,X
    memory[16'h0041] = 8'h01;
    memory[16'h0042] = 8'h00;
    run_instruction(6, 8'hd6);
    if (debug_a != 8'ha9 ||
        trace_address[0] != 16'h0040 || trace_write[0] ||
        trace_address[1] != 16'h0041 || trace_write[1] ||
        trace_address[2] != 16'h0042 || trace_write[2] ||
        trace_address[3][7:0] != 8'hff || trace_write[3] ||
        trace_address[4][7:0] != 8'hff || trace_write[4] ||
        trace_address[5] != 16'h0120 || trace_write[5] || trace_data[5] != 8'ha9) begin
      $fatal(1, "M6805 indexed-16 read table-G2 trace");
    end

    memory[16'h0043] = 8'hdc; // JMP $0008,X -> $0028
    memory[16'h0044] = 8'h00;
    memory[16'h0045] = 8'h08;
    run_instruction(5, 8'hdc);
    if (debug_pc != 16'h0028 ||
        trace_address[0] != 16'h0043 || trace_write[0] ||
        trace_address[1] != 16'h0044 || trace_write[1] ||
        trace_address[2] != 16'h0045 || trace_write[2] ||
        trace_address[3][7:0] != 8'hff || trace_write[3] ||
        trace_address[4][7:0] != 8'hff || trace_write[4]) begin
      $fatal(1, "M6805 indexed-16 JMP table-G2 trace");
    end

    $display("M6805 CORE PASS: %0d directed reset, bus, stack, and interrupt checks", cases);
    $finish;
  end
endmodule
