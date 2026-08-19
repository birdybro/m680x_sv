// SPDX-License-Identifier: MIT
module tb_m6800_opcodes #(
  parameter logic [1:0] TEST_ARCHITECTURE = 2'd0
);
  import m6800_opcode_vectors_pkg::*;

  localparam int unsigned VECTOR_COUNT =
    (TEST_ARCHITECTURE == 2'd0) ? M6800_VECTOR_COUNT :
    ((TEST_ARCHITECTURE == 2'd1) ? M6801_VECTOR_COUNT : HD6301_VECTOR_COUNT);

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
  logic sleeping_state;
  logic interrupt_ack;
  logic [1:0] interrupt_vector;
  logic [7:0] debug_a;
  logic [7:0] debug_b;
  logic [15:0] debug_x;
  logic [15:0] debug_sp;
  logic [15:0] debug_pc;
  logic [5:0] debug_ccr;
  logic [7:0] debug_opcode;
  logic [3:0] debug_cycles;
  logic [7:0] memory [0:65535];
  opcode_vector_t expected_vector;
  opcode_access_t expected_access;
  integer vector_index;
  integer memory_index;
  integer cycle_count;
  integer access_count;
  integer setup_instruction;

  m6800_core #(.ARCHITECTURE(TEST_ARCHITECTURE)) dut (
    .clk_i(clk),
    .reset_n_i(reset_n),
    .clock_enable_i(1'b1),
    .bus_ready_i(1'b1),
    .irq_n_i(1'b1),
    .irq_vector_i(16'hfff8),
    .nmi_n_i(1'b1),
    .instruction_address_error_i(1'b0),
    .data_i(data_in),
    .address_o(address),
    .data_o(data_out),
    .write_o(write_enable),
    .bus_valid_o(bus_valid),
    .opcode_fetch_o(opcode_fetch),
    .retire_o(retire),
    .illegal_o(illegal),
    .undefined_o(undefined_value),
    .waiting_o(waiting_state),
    .sleeping_o(sleeping_state),
    .interrupt_ack_o(interrupt_ack),
    .interrupt_vector_o(interrupt_vector),
    .debug_a_o(debug_a),
    .debug_b_o(debug_b),
    .debug_x_o(debug_x),
    .debug_sp_o(debug_sp),
    .debug_pc_o(debug_pc),
    .debug_ccr_o(debug_ccr),
    .debug_opcode_o(debug_opcode),
    .debug_instruction_cycles_o(debug_cycles)
  );

  assign data_in = memory[address];
  always #5 clk <= ~clk;

  always @(posedge clk) begin
    if (bus_valid && write_enable) memory[address] <= data_out;
  end

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic run_setup_instruction;
    integer setup_cycles;
    begin
      setup_cycles = 0;
      do begin
        tick();
        setup_cycles = setup_cycles + 1;
        if (setup_cycles > 12) $fatal(1, "setup instruction did not retire");
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
      memory[16'hfffa] = 8'h30;
      memory[16'hfffb] = 8'h00;
      memory[16'hfffc] = 8'h31;
      memory[16'hfffd] = 8'h00;
      memory[16'h0010] = 8'h43;
      memory[16'h0011] = 8'h42;
      memory[16'h0020] = 8'h73;
      memory[16'h0021] = 8'h72;
      memory[16'h1020] = 8'h73;
      memory[16'h1021] = 8'h72;
      memory[16'h2010] = 8'h43;
      memory[16'h2011] = 8'h42;
      memory[16'h4001] = 8'hc0;
      memory[16'h4002] = 8'h34;
      memory[16'h4003] = 8'h12;
      memory[16'h4004] = 8'h20;
      memory[16'h4005] = 8'h00;
      memory[16'h4006] = 8'h10;
      memory[16'h4007] = 8'h11;

      // Establish the model fixture state using only architectural instructions.
      memory[16'h1000] = 8'h8e; // LDS #$4000
      memory[16'h1001] = 8'h40;
      memory[16'h1002] = 8'h00;
      memory[16'h1003] = 8'hce; // LDX #$2000
      memory[16'h1004] = 8'h20;
      memory[16'h1005] = 8'h00;
      memory[16'h1006] = 8'h86; // LDAA #$00
      memory[16'h1007] = 8'h00;
      memory[16'h1008] = 8'h06; // TAP: CCR = 0
      memory[16'h1009] = 8'h86; // LDAA #$12
      memory[16'h100a] = 8'h12;
      memory[16'h100b] = 8'hc6; // LDAB #$34
      memory[16'h100c] = 8'h34;
      memory[16'h100d] = opcode;
      memory[16'h100e] = 8'h10;
      memory[16'h100f] = 8'h20;
      memory[16'h1010] = 8'h30;

      tick();
      reset_n = 1'b1;
      tick();
      tick();
      for (setup_instruction = 0; setup_instruction < 6; setup_instruction = setup_instruction + 1) begin
        run_setup_instruction();
      end
      if (debug_pc != 16'h100d || debug_a != 8'h12 || debug_b != 8'h34 ||
          debug_x != 16'h2000 || debug_sp != 16'h4000 || debug_ccr != 6'h00) begin
        $fatal(1, "fixture setup failed for opcode %02x", opcode);
      end
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    for (vector_index = 0; vector_index < VECTOR_COUNT; vector_index = vector_index + 1) begin
      expected_vector = (TEST_ARCHITECTURE == 2'd0) ?
        m6800_vector(vector_index) : ((TEST_ARCHITECTURE == 2'd1) ?
        m6801_vector(vector_index) : hd6301_vector(vector_index));
      initialize_fixture(expected_vector.opcode);
      cycle_count = 0;
      access_count = 0;
      do begin
        if (bus_valid) begin
          if (access_count >= expected_vector.access_count) begin
            $fatal(1, "opcode %02x emitted unexpected access %0d addr=%04x",
              expected_vector.opcode, access_count, address);
          end
          expected_access = (TEST_ARCHITECTURE == 2'd0) ?
            m6800_access(vector_index[7:0], access_count[7:0]) :
            ((TEST_ARCHITECTURE == 2'd1) ?
            m6801_access(vector_index[7:0], access_count[7:0]) :
            hd6301_access(vector_index[7:0], access_count[7:0]));
          if ((access_count == 0) && !opcode_fetch) begin
            $fatal(1, "opcode %02x first access was not marked as fetch", expected_vector.opcode);
          end
          if (write_enable != expected_access.write_enable || address != expected_access.address ||
              (write_enable ? data_out : data_in) != expected_access.data) begin
            $fatal(1, "opcode %02x access %0d expected=%0d/%04x/%02x actual=%0d/%04x/%02x",
              expected_vector.opcode, access_count, expected_access.write_enable,
              expected_access.address, expected_access.data, write_enable, address,
              write_enable ? data_out : data_in);
          end
          access_count = access_count + 1;
        end
        tick();
        cycle_count = cycle_count + 1;
        if (cycle_count > 15) $fatal(1, "opcode %02x did not retire", expected_vector.opcode);
      end while (!retire);

      if (cycle_count != int'(expected_vector.cycles) || debug_cycles != expected_vector.cycles ||
          access_count != int'(expected_vector.access_count) || debug_opcode != expected_vector.opcode ||
          debug_a != expected_vector.a || debug_b != expected_vector.b || debug_x != expected_vector.x ||
          debug_sp != expected_vector.sp || debug_pc != expected_vector.pc ||
          ((debug_ccr ^ expected_vector.ccr) & expected_vector.ccr_mask) != 6'h00 ||
          waiting_state != expected_vector.waiting_state || illegal || undefined_value || interrupt_ack ||
          sleeping_state != expected_vector.sleeping_state ||
          interrupt_vector != 2'b00) begin
        $fatal(1, "opcode %02x final mismatch cycles=%0d/%0d A=%02x/%02x B=%02x/%02x X=%04x/%04x SP=%04x/%04x PC=%04x/%04x CCR=%02x/%02x mask=%02x access=%0d/%0d wait=%0d/%0d illegal=%0d undefined=%0d",
          expected_vector.opcode, cycle_count, expected_vector.cycles,
          debug_a, expected_vector.a, debug_b, expected_vector.b,
          debug_x, expected_vector.x, debug_sp, expected_vector.sp,
          debug_pc, expected_vector.pc, debug_ccr, expected_vector.ccr,
          expected_vector.ccr_mask, access_count, expected_vector.access_count,
          waiting_state, expected_vector.waiting_state, illegal, undefined_value);
      end
    end
    $display("M6800-FAMILY OPCODE PASS: architecture=%0d, %0d documented encodings, architectural bus accesses and cycle totals",
      TEST_ARCHITECTURE, VECTOR_COUNT);
    $finish;
  end
endmodule
