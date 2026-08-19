// SPDX-License-Identifier: MIT
module tb_hd6301_trap;
  logic clk;
  logic reset_n;
  logic instruction_address_error;
  logic [7:0] data_in;
  logic [15:0] address;
  logic [7:0] data_out;
  logic write_enable;
  logic bus_valid;
  logic opcode_fetch;
  logic retire;
  logic illegal;
  logic interrupt_ack;
  logic [1:0] interrupt_vector;
  logic [15:0] debug_sp;
  logic [15:0] debug_pc;
  logic [5:0] debug_ccr;
  logic [7:0] memory [0:65535];
  logic [15:0] trace_address [0:15];
  logic [7:0] trace_data [0:15];
  logic trace_write [0:15];
  logic trace_valid [0:15];
  logic trace_fetch [0:15];
  integer index;
  integer cycles;
  integer cases;

  // Only state used by this focused manufacturer-trace regression is observed.
  /* verilator lint_off PINCONNECTEMPTY */
  m6800_core #(.ARCHITECTURE(2'd2)) dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(1'b1), .bus_ready_i(1'b1),
    .irq_n_i(1'b1), .nmi_n_i(1'b1),
    .instruction_address_error_i(instruction_address_error), .data_i(data_in),
    .address_o(address), .data_o(data_out), .write_o(write_enable),
    .bus_valid_o(bus_valid), .opcode_fetch_o(opcode_fetch), .retire_o(retire),
    .illegal_o(illegal), .undefined_o(), .waiting_o(), .sleeping_o(),
    .interrupt_ack_o(interrupt_ack), .interrupt_vector_o(interrupt_vector),
    .debug_a_o(), .debug_b_o(), .debug_x_o(), .debug_sp_o(debug_sp),
    .debug_pc_o(debug_pc), .debug_ccr_o(debug_ccr), .debug_opcode_o(),
    .debug_instruction_cycles_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  assign data_in = memory[address];
  always #5 clk <= ~clk;
  always @(posedge clk) begin
    if (bus_valid && write_enable) memory[address] <= data_out;
  end

  task automatic tick;
    begin @(posedge clk); #1; end
  endtask

  task automatic reset_to(input logic [15:0] target);
    begin
      instruction_address_error = 1'b0;
      memory[16'hfffe] = target[15:8];
      memory[16'hffff] = target[7:0];
      #1;
      reset_n = 1'b0;
      #1;
      reset_n = 1'b1;
      tick();
      tick();
      if (debug_pc != target || !debug_ccr[4]) begin
        $fatal(1, "HD6301 TRAP reset vector or interrupt mask");
      end
    end
  endtask

  task automatic run_instruction(input integer expected_cycles, input logic [7:0] opcode);
    begin
      cycles = 0;
      do begin
        tick();
        cycles = cycles + 1;
        if (opcode == 8'h8e && !debug_ccr[4]) begin
          $fatal(1, "HD6301 LDS changed interrupt mask at cycle %0d", cycles);
        end
        if (cycles > 16) $fatal(1, "HD6301 instruction %02x did not retire", opcode);
      end while (!retire);
      if (cycles != expected_cycles) $fatal(1, "HD6301 instruction %02x cycles", opcode);
    end
  endtask

  task automatic run_trap(input logic [15:0] retry_pc);
    begin
      cycles = 0;
      do begin
        trace_address[cycles] = address;
        trace_data[cycles] = write_enable ? data_out : data_in;
        trace_write[cycles] = write_enable;
        trace_valid[cycles] = bus_valid;
        trace_fetch[cycles] = opcode_fetch;
        tick();
        cycles = cycles + 1;
        if (cycles > 15) $fatal(1, "HD6301 TRAP did not acknowledge");
      end while (!interrupt_ack);
      if (cycles != 13 || interrupt_vector != 2'b11 || illegal || retire ||
          debug_pc != 16'h1200 || debug_sp != 16'h01f8 ||
          debug_ccr != 6'b010000) begin
        $fatal(1, "HD6301 TRAP architectural result cycles=%0d pc=%04x", cycles, debug_pc);
      end
      if (!trace_fetch[0] || trace_address[0] != retry_pc ||
          trace_address[1] != retry_pc + 16'h0001 ||
          trace_address[2] != 16'hffff || trace_address[3] != 16'hffff ||
          trace_address[4] != 16'h01ff || trace_data[4] != retry_pc[7:0] ||
          trace_address[5] != 16'h01fe || trace_data[5] != retry_pc[15:8] ||
          trace_address[6] != 16'h01fd || trace_data[6] != 8'h00 ||
          trace_address[7] != 16'h01fc || trace_data[7] != 8'h00 ||
          trace_address[8] != 16'h01fb || trace_data[8] != 8'h00 ||
          trace_address[9] != 16'h01fa || trace_data[9] != 8'h00 ||
          trace_address[10] != 16'h01f9 || trace_data[10] != 8'hd0 ||
          trace_address[11] != 16'hffee || trace_data[11] != 8'h12 ||
          trace_address[12] != 16'hffef || trace_data[12] != 8'h00) begin
        for (index = 0; index < 13; index = index + 1) begin
          $display("TRAP case %0d cycle %0d address=%04x write=%b data=%02x valid=%b fetch=%b",
                   cases, index, trace_address[index], trace_write[index],
                   trace_data[index], trace_valid[index], trace_fetch[index]);
        end
        $fatal(1, "HD6301 TRAP documented bus sequence");
      end
      for (index = 0; index < 13; index = index + 1) begin
        if (!trace_valid[index] || (index != 0 && trace_fetch[index]) ||
            (trace_write[index] != (index >= 4 && index <= 10))) begin
          $fatal(1, "HD6301 TRAP bus validity cycle %0d", index);
        end
      end
      cases = cases + 1;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    instruction_address_error = 1'b0;
    cases = 0;
    for (index = 0; index < 65536; index = index + 1) memory[index] = 8'h01;
    memory[16'hffee] = 8'h12;
    memory[16'hffef] = 8'h00;
    memory[16'h1200] = 8'h3b; // RTI

    memory[16'h1000] = 8'h8e; // LDS #$01ff
    memory[16'h1001] = 8'h01;
    memory[16'h1002] = 8'hff;
    memory[16'h1003] = 8'h00; // undefined opcode
    reset_to(16'h1000);
    run_instruction(3, 8'h8e);
    run_trap(16'h1003);
    run_instruction(10, 8'h3b);
    if (debug_pc != 16'h1003 || debug_sp != 16'h01ff) begin
      $fatal(1, "HD6301 TRAP RTI did not retry undefined opcode");
    end
    run_trap(16'h1003);

    memory[16'h1100] = 8'h8e; // LDS #$01ff
    memory[16'h1101] = 8'h01;
    memory[16'h1102] = 8'hff;
    memory[16'h1103] = 8'h01; // valid NOP, trapped only by device address decode
    reset_to(16'h1100);
    run_instruction(3, 8'h8e);
    instruction_address_error = 1'b1;
    run_trap(16'h1103);
    instruction_address_error = 1'b0;

    $display("HD6301 TRAP PASS: %0d opcode-retry and address-error traces", cases);
    $finish;
  end
endmodule
