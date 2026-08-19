// SPDX-License-Identifier: MIT
// This focused source intentionally contains one top for each CPU lineage.
/* verilator lint_off DECLFILENAME */
module tb_m6800_interrupt_delay #(
  parameter logic [1:0] TEST_ARCHITECTURE = 2'd1
);
  logic clk;
  logic reset_n;
  logic [7:0] data_in;
  logic [15:0] address;
  logic [7:0] data_out;
  logic write_enable;
  logic bus_valid;
  logic retire;
  logic interrupt_ack;
  logic [7:0] debug_opcode;
  logic [15:0] debug_pc;
  logic [7:0] memory [0:65535];
  integer index;
  integer cycles;
  integer following;

  // Only the state required by this focused regression is observed.
  /* verilator lint_off PINCONNECTEMPTY */
  m6800_core #(.ARCHITECTURE(TEST_ARCHITECTURE)) dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(1'b1), .bus_ready_i(1'b1),
    .irq_n_i(1'b0), .nmi_n_i(1'b1), .instruction_address_error_i(1'b0),
    .data_i(data_in), .address_o(address),
    .data_o(data_out), .write_o(write_enable), .bus_valid_o(bus_valid),
    .opcode_fetch_o(), .retire_o(retire), .illegal_o(), .undefined_o(),
    .waiting_o(), .sleeping_o(), .interrupt_ack_o(interrupt_ack),
    .interrupt_vector_o(), .debug_a_o(), .debug_b_o(), .debug_x_o(),
    .debug_sp_o(), .debug_pc_o(debug_pc), .debug_ccr_o(),
    .debug_opcode_o(debug_opcode), .debug_instruction_cycles_o()
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
      memory[16'hfffe] = target[15:8];
      memory[16'hffff] = target[7:0];
      #1;
      reset_n = 1'b0;
      tick();
      reset_n = 1'b1;
      tick();
      tick();
      if (debug_pc != target) $fatal(1, "M6801-lineage delay reset");
    end
  endtask

  task automatic run_instruction(input logic [7:0] opcode);
    begin
      cycles = 0;
      do begin
        tick();
        cycles = cycles + 1;
        if (cycles > 16) $fatal(1, "opcode %02x interrupted or did not retire", opcode);
      end while (!retire);
      if (debug_opcode != opcode || interrupt_ack) $fatal(1, "opcode %02x delay execution", opcode);
    end
  endtask

  task automatic expect_delayed_irq;
    begin
      following = (TEST_ARCHITECTURE == 2'd2) ? 2 : 1;
      for (index = 0; index < following; index = index + 1) run_instruction(8'h01);
      cycles = 0;
      do begin
        tick();
        cycles = cycles + 1;
        if (cycles > 20) $fatal(1, "delayed IRQ did not acknowledge");
      end while (!interrupt_ack);
      if (debug_pc != 16'h1200) $fatal(1, "delayed IRQ vector");
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    for (index = 0; index < 65536; index = index + 1) memory[index] = 8'h01;
    memory[16'hfff8] = 8'h12;
    memory[16'hfff9] = 8'h00;
    #1;

    memory[16'h1000] = 8'h0e; // CLI
    reset_to(16'h1000);
    run_instruction(8'h0e);
    expect_delayed_irq();

    memory[16'h1100] = 8'h86; // LDAA #$00
    memory[16'h1101] = 8'h00;
    memory[16'h1102] = 8'h06; // TAP clears I through the same buffer
    reset_to(16'h1100);
    run_instruction(8'h86);
    run_instruction(8'h06);
    expect_delayed_irq();

    $display("M6801-LINEAGE INTERRUPT DELAY PASS: architecture=%0d CLI and TAP", TEST_ARCHITECTURE);
    $finish;
  end
endmodule

module tb_m6805_interrupt_delay;
  logic clk;
  logic reset_n;
  logic [7:0] data_in;
  logic [15:0] address;
  logic [7:0] data_out;
  logic write_enable;
  logic bus_valid;
  logic retire;
  logic interrupt_ack;
  logic [7:0] debug_opcode;
  logic [15:0] debug_pc;
  logic [7:0] memory [0:65535];
  integer index;
  integer cycles;

  // Only the state required by this focused regression is observed.
  /* verilator lint_off PINCONNECTEMPTY */
  m6805_core #(.HITACHI_PROFILE(1'b1)) dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(1'b1), .bus_ready_i(1'b1),
    .irq_n_i(1'b0), .interrupt_pin_n_i(1'b0), .irq_vector_i(16'hfffa),
    .data_i(data_in), .address_o(address), .data_o(data_out),
    .write_o(write_enable), .bus_valid_o(bus_valid), .opcode_fetch_o(),
    .retire_o(retire), .illegal_o(), .undefined_o(), .waiting_o(), .stopped_o(),
    .interrupt_ack_o(interrupt_ack), .debug_a_o(), .debug_x_o(), .debug_sp_o(),
    .debug_pc_o(debug_pc), .debug_ccr_o(), .debug_opcode_o(debug_opcode),
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

  task automatic run_instruction(input logic [7:0] opcode);
    begin
      cycles = 0;
      do begin
        tick();
        cycles = cycles + 1;
        if (cycles > 16) $fatal(1, "HD6305 opcode %02x interrupted", opcode);
      end while (!retire);
      if (debug_opcode != opcode || interrupt_ack) $fatal(1, "HD6305 delay instruction");
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    for (index = 0; index < 65536; index = index + 1) memory[index] = 8'h9d;
    memory[16'hfffe] = 8'h10;
    memory[16'hffff] = 8'h00;
    memory[16'hfffa] = 8'h12;
    memory[16'hfffb] = 8'h00;
    memory[16'h1000] = 8'h9a; // CLI
    #1;
    reset_n = 1'b0;
    tick();
    reset_n = 1'b1;
    tick();
    tick();
    run_instruction(8'h9a);
    run_instruction(8'h9d);
    cycles = 0;
    do begin
      tick();
      cycles = cycles + 1;
      if (cycles > 16) $fatal(1, "HD6305 delayed IRQ did not acknowledge");
    end while (!interrupt_ack);
    if (debug_pc != 16'h1200) $fatal(1, "HD6305 delayed IRQ vector");
    $display("HD6305 INTERRUPT DELAY PASS: instruction following CLI retired");
    $finish;
  end
endmodule
/* verilator lint_on DECLFILENAME */
