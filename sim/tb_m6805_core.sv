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
  integer index;
  integer cycle_count;
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
        tick();
        cycle_count = cycle_count + 1;
        if (cycle_count > 12) $fatal(1, "M6805 IRQ did not acknowledge");
      end while (!interrupt_ack);
      if (cycle_count != 8) $fatal(1, "M6805 IRQ timing %0d/8", cycle_count);
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

    #1;
    reset_n = 1'b0;
    #1;
    if (!bus_valid || address != 16'hfffe || write_enable) $fatal(1, "M6805 reset high vector");
    reset_n = 1'b1;
    tick();
    if (address != 16'hffff || !bus_valid) $fatal(1, "M6805 reset low vector");
    tick();
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
    if (memory[16'h0020] != 8'h80 || !trace_write[2] || trace_address[2] != 16'h0020) begin
      $fatal(1, "M6805 direct store trace");
    end
    run_instruction(8, 8'had);
    if (debug_pc != 16'h100b || debug_sp != 16'h007d ||
        memory[16'h007f] != 8'h09 || memory[16'h007e] != 8'h10) begin
      $fatal(1, "M6805 BSR stack order");
    end
    run_instruction(4, 8'h4c);
    run_instruction(6, 8'h81);
    if (debug_pc != 16'h1009 || debug_sp != 16'h007f || debug_a != 8'h81) begin
      $fatal(1, "M6805 RTS restore");
    end
    run_instruction(2, 8'h9d);

    irq_n = 1'b0;
    run_interrupt();
    if (debug_pc != 16'h1200 || debug_sp != 16'h007a || !debug_ccr[3] ||
        !trace_valid[0] || trace_address[0] != 16'h100a ||
        !trace_write[1] || trace_address[1] != 16'h007f || trace_data[1] != 8'h0a ||
        trace_address[2] != 16'h007e || trace_data[2] != 8'h10 ||
        trace_address[3] != 16'h007d || trace_data[3] != 8'h00 ||
        trace_address[4] != 16'h007c || trace_data[4] != 8'h81 ||
        trace_address[5] != 16'h007b || trace_address[6] != 16'hfffa ||
        trace_address[7] != 16'hfffb) begin
      $fatal(1, "M6805 IRQ frame/vector trace");
    end
    irq_n = 1'b1;
    run_instruction(9, 8'h80);
    if (debug_pc != 16'h100a || debug_sp != 16'h007f || debug_a != 8'h81 ||
        debug_x != 8'h00 || debug_ccr[3] || illegal || undefined_value ||
        waiting_state || stopped_state) begin
      $fatal(1, "M6805 RTI state restore");
    end

    $display("M6805 CORE PASS: %0d directed reset, bus, stack, and interrupt checks", cases);
    $finish;
  end
endmodule
