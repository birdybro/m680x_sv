// SPDX-License-Identifier: MIT
module tb_m6805_opcodes #(
  parameter logic TEST_HITACHI = 1'b0
);
  import m6805_opcode_vectors_pkg::*;
  localparam int unsigned VECTOR_COUNT = TEST_HITACHI ? HD6305_VECTOR_COUNT : M6805_VECTOR_COUNT;

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
  opcode_vector_t expected_vector;
  opcode_access_t expected_access;
  integer vector_index;
  integer memory_index;
  integer setup_instruction;
  integer cycle_count;
  integer access_count;

  m6805_core #(.HITACHI_PROFILE(TEST_HITACHI)) dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(1'b1), .bus_ready_i(1'b1),
    .irq_n_i(1'b1), .interrupt_pin_n_i(1'b1), .irq_vector_i(16'hfffa),
    .data_i(data_in), .address_o(address), .data_o(data_out),
    .write_o(write_enable), .bus_valid_o(bus_valid), .opcode_fetch_o(opcode_fetch),
    .retire_o(retire), .illegal_o(illegal), .undefined_o(undefined_value),
    .waiting_o(waiting_state), .stopped_o(stopped_state), .interrupt_ack_o(interrupt_ack),
    .debug_a_o(debug_a), .debug_x_o(debug_x), .debug_sp_o(debug_sp), .debug_pc_o(debug_pc),
    .debug_ccr_o(debug_ccr), .debug_opcode_o(debug_opcode),
    .debug_instruction_cycles_o(debug_cycles)
  );

  assign data_in = memory[address];
  always #5 clk <= ~clk;
  always @(posedge clk) if (bus_valid && write_enable) memory[address] <= data_out;

  task automatic tick;
    begin @(posedge clk); #1; end
  endtask

  task automatic run_setup_instruction;
    integer setup_cycles;
    begin
      setup_cycles = 0;
      do begin
        tick();
        setup_cycles = setup_cycles + 1;
        if (setup_cycles > 10) $fatal(1, "M6805 fixture instruction did not retire");
      end while (!retire);
    end
  endtask

  task automatic initialize_fixture(input logic [7:0] opcode);
    begin
      #1;
      reset_n = 1'b0;
      #1;
      for (memory_index = 0; memory_index < 65536; memory_index = memory_index + 1) begin
        memory[memory_index] = 8'h00;
      end
      memory[16'hfffe] = 8'h10;
      memory[16'hffff] = 8'h00;
      memory[16'hfffa] = 8'h21;
      memory[16'hfffb] = 8'h00;
      memory[16'hfffc] = 8'h22;
      memory[16'hfffd] = 8'h00;
      memory[16'h0010] = 8'hb6;
      memory[16'h0020] = 8'h86;
      memory[16'h0030] = 8'h96;
      memory[16'h0031] = 8'h97;
      memory[16'h1020] = 8'h86;
      memory[16'h1040] = 8'he6;
      memory[16'h0060] = 8'he0;
      memory[16'h0061] = 8'h12;
      memory[16'h0062] = 8'h20;
      memory[16'h0063] = 8'h10;
      memory[16'h0064] = 8'h09;
      memory[16'h1000] = 8'hae; // LDX #$20
      memory[16'h1001] = 8'h20;
      memory[16'h1002] = 8'ha6; // LDA #$12
      memory[16'h1003] = 8'h12;
      memory[16'h1004] = 8'h9a; // CLI, producing CCR=0
      memory[16'h1005] = opcode;
      memory[16'h1006] = 8'h10;
      memory[16'h1007] = 8'h20;
      memory[16'h1008] = 8'h30;
      reset_n = 1'b1;
      tick();
      tick();
      for (setup_instruction = 0; setup_instruction < 3; setup_instruction = setup_instruction + 1) begin
        run_setup_instruction();
      end
      if (debug_pc != 16'h1005 || debug_a != 8'h12 || debug_x != 8'h20 ||
          debug_sp != 16'h007f || debug_ccr != 5'h00) begin
        $fatal(1, "M6805 fixture setup failed opcode=%02x A=%02x X=%02x SP=%04x PC=%04x CCR=%02x current=%02x",
          opcode, debug_a, debug_x, debug_sp, debug_pc, debug_ccr, debug_opcode);
      end
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    #1;
    for (vector_index = 0; vector_index < VECTOR_COUNT; vector_index = vector_index + 1) begin
      expected_vector = TEST_HITACHI ? hd6305_vector(vector_index) : m6805_vector(vector_index);
      initialize_fixture(expected_vector.opcode);
      cycle_count = 0;
      access_count = 0;
      do begin
        if (bus_valid) begin
          if (access_count >= expected_vector.access_count) begin
            $fatal(1, "M6805 opcode %02x unexpected access %0d", expected_vector.opcode, access_count);
          end
          expected_access = TEST_HITACHI ?
            hd6305_access(vector_index[7:0], access_count[7:0]) :
            m6805_access(vector_index[7:0], access_count[7:0]);
          if ((access_count == 0) && !opcode_fetch) $fatal(1, "first access is not opcode fetch");
          if (write_enable != expected_access.write_enable || address != expected_access.address ||
              (write_enable ? data_out : data_in) != expected_access.data) begin
            $fatal(1, "M6805 opcode %02x access %0d expected=%0d/%04x/%02x actual=%0d/%04x/%02x",
              expected_vector.opcode, access_count, expected_access.write_enable,
              expected_access.address, expected_access.data, write_enable, address,
              write_enable ? data_out : data_in);
          end
          access_count = access_count + 1;
        end
        tick();
        cycle_count = cycle_count + 1;
        if (cycle_count > 15) $fatal(1, "M6805 opcode %02x did not retire", expected_vector.opcode);
      end while (!retire);
      if (cycle_count != int'(expected_vector.cycles) || debug_cycles != expected_vector.cycles ||
          access_count != int'(expected_vector.access_count) || debug_opcode != expected_vector.opcode ||
          debug_a != expected_vector.a || debug_x != expected_vector.x ||
          debug_sp != expected_vector.sp || debug_pc != expected_vector.pc ||
          ((debug_ccr ^ expected_vector.ccr) & expected_vector.ccr_mask) != 5'h00 ||
          waiting_state != expected_vector.waiting_state || stopped_state != expected_vector.stopped_state ||
          illegal || undefined_value || interrupt_ack) begin
        $fatal(1, "M6805 opcode %02x mismatch cycles=%0d/%0d A=%02x/%02x X=%02x/%02x SP=%04x/%04x PC=%04x/%04x CCR=%02x/%02x accesses=%0d/%0d wait=%0d/%0d stop=%0d/%0d illegal=%0d undefined=%0d",
          expected_vector.opcode, cycle_count, expected_vector.cycles,
          debug_a, expected_vector.a, debug_x, expected_vector.x,
          debug_sp, expected_vector.sp, debug_pc, expected_vector.pc,
          debug_ccr, expected_vector.ccr, access_count, expected_vector.access_count,
          waiting_state, expected_vector.waiting_state, stopped_state, expected_vector.stopped_state,
          illegal, undefined_value);
      end
    end
    $display("M6805-FAMILY OPCODE PASS: hitachi=%0d, %0d documented encodings, architectural bus accesses and cycle totals",
      TEST_HITACHI, VECTOR_COUNT);
    $finish;
  end
endmodule
