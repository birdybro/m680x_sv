// SPDX-License-Identifier: MIT
module tb_random_m6805 #(
  parameter logic TEST_HITACHI = 1'b0
);
  import random_programs_pkg::*;

  logic clk;
  logic reset_n;
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
  random_m6805_state_t expected;
  integer program_index;
  integer instruction_index;
  integer byte_index;
  integer memory_index;
  integer cycle_count;
  integer total_retirements;

  m6805_core #(.HITACHI_PROFILE(TEST_HITACHI)) dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(1'b1), .bus_ready_i(1'b1),
    .irq_n_i(1'b1), .interrupt_pin_n_i(1'b1), .irq_vector_i(16'hfffa),
    .data_i(data_in), .address_o(address), .data_o(data_out),
    .write_o(write_enable), .bus_valid_o(bus_valid), .opcode_fetch_o(opcode_fetch),
    .retire_o(retire), .illegal_o(illegal), .undefined_o(undefined_value),
    .waiting_o(waiting_state), .stopped_o(stopped_state), .interrupt_ack_o(interrupt_ack),
    .debug_a_o(debug_a), .debug_x_o(debug_x), .debug_sp_o(debug_sp),
    .debug_pc_o(debug_pc), .debug_ccr_o(debug_ccr), .debug_opcode_o(debug_opcode),
    .debug_instruction_cycles_o(debug_cycles)
  );

  assign data_in = memory[address];
  always #5 clk <= ~clk;
  always @(posedge clk) if (bus_valid && write_enable) memory[address] <= data_out;

  task automatic tick;
    begin @(posedge clk); #1; end
  endtask

  function automatic logic [7:0] selected_program_byte(
    input logic [7:0] selected_program, input logic [7:0] selected_byte
  );
    begin
      selected_program_byte = TEST_HITACHI ?
        hd6305_program_byte(selected_program, selected_byte) :
        m6805_program_byte(selected_program, selected_byte);
    end
  endfunction

  function automatic random_m6805_state_t selected_expected(
    input logic [7:0] selected_program, input logic [7:0] selected_instruction
  );
    begin
      selected_expected = TEST_HITACHI ?
        hd6305_expected(selected_program, selected_instruction) :
        m6805_expected(selected_program, selected_instruction);
    end
  endfunction

  task automatic initialize_program(input logic [7:0] selected_program);
    begin
      #1;
      reset_n = 1'b0;
      #1;
      for (memory_index = 0; memory_index < 65536; memory_index = memory_index + 1) begin
        memory[memory_index] = 8'h00;
      end
      memory[16'hfffe] = 8'h10;
      memory[16'hffff] = 8'h00;
      for (byte_index = 0; byte_index < RANDOM_MAX_PROGRAM_BYTES; byte_index = byte_index + 1) begin
        memory[16'h1000 + byte_index[15:0]] =
          selected_program_byte(selected_program, byte_index[7:0]);
      end
      reset_n = 1'b1;
      tick();
      tick();
      if (debug_pc != 16'h1000 || debug_sp != 16'h007f) begin
        $fatal(1, "random M6805 reset mismatch PC=%04x SP=%04x", debug_pc, debug_sp);
      end
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    total_retirements = 0;
    #1;
    for (program_index = 0; program_index < RANDOM_PROGRAM_COUNT; program_index = program_index + 1) begin
      initialize_program(program_index[7:0]);
      for (instruction_index = 0; instruction_index < RANDOM_INSTRUCTIONS_PER_PROGRAM;
           instruction_index = instruction_index + 1) begin
        expected = selected_expected(program_index[7:0], instruction_index[7:0]);
        if (!bus_valid || !opcode_fetch || write_enable) begin
          $fatal(1, "random M6805 hitachi=%0d program=%0d instruction=%0d did not begin with an opcode fetch",
            TEST_HITACHI, program_index, instruction_index);
        end
        cycle_count = 0;
        do begin
          tick();
          cycle_count = cycle_count + 1;
          if (cycle_count > 12) begin
            $fatal(1, "random M6805 program=%0d instruction=%0d failed to retire",
              program_index, instruction_index);
          end
        end while (!retire);
        if (cycle_count != int'(expected.cycles) || debug_cycles != expected.cycles ||
            debug_a != expected.a || debug_x != expected.x || debug_sp != expected.sp ||
            debug_pc != expected.pc || debug_ccr != expected.ccr || illegal || undefined_value ||
            waiting_state || stopped_state || interrupt_ack) begin
          $fatal(1, "random M6805 hitachi=%0d program=%0d instruction=%0d opcode=%02x cycles=%0d/%0d A=%02x/%02x X=%02x/%02x SP=%04x/%04x PC=%04x/%04x CCR=%02x/%02x",
            TEST_HITACHI, program_index, instruction_index, debug_opcode,
            cycle_count, expected.cycles, debug_a, expected.a, debug_x, expected.x,
            debug_sp, expected.sp, debug_pc, expected.pc, debug_ccr, expected.ccr);
        end
        total_retirements = total_retirements + 1;
      end
    end
    $display("M6805-FAMILY RANDOM PASS: hitachi=%0d, %0d programs, %0d retirements",
      TEST_HITACHI, RANDOM_PROGRAM_COUNT, total_retirements);
    $finish;
  end
endmodule
