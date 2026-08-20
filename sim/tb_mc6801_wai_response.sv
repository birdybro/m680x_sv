// SPDX-License-Identifier: MIT
module tb_mc6801_wai_response;
  logic clk;
  logic reset_n;
  logic irq_n;
  logic [15:0] irq_vector;
  logic nmi_n;
  logic [7:0] data_in;
  logic [15:0] address;
  logic [7:0] data_out;
  logic write_enable;
  logic bus_valid;
  logic opcode_fetch;
  logic waiting_state;
  logic interrupt_ack;
  logic [1:0] interrupt_vector;
  logic [15:0] debug_sp;
  logic [15:0] debug_pc;
  logic [7:0] memory [0:65535];
  integer checks;
  integer cycles;
  integer index;

  /* verilator lint_off PINCONNECTEMPTY */
  m6800_core #(.ARCHITECTURE(2'd1)) dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(1'b1),
    .bus_ready_i(1'b1), .irq_n_i(irq_n), .irq_vector_i(irq_vector),
    .nmi_n_i(nmi_n), .instruction_address_error_i(1'b0), .data_i(data_in),
    .address_o(address), .data_o(data_out), .write_o(write_enable),
    .bus_valid_o(bus_valid), .opcode_fetch_o(opcode_fetch), .retire_o(),
    .illegal_o(), .undefined_o(), .waiting_o(waiting_state), .sleeping_o(),
    .interrupt_ack_o(interrupt_ack), .interrupt_vector_o(interrupt_vector),
    .debug_a_o(), .debug_b_o(), .debug_x_o(), .debug_sp_o(debug_sp),
    .debug_pc_o(debug_pc), .debug_ccr_o(), .debug_opcode_o(),
    .debug_instruction_cycles_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */

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

  task automatic check_value(input logic condition, input string message);
    begin
      checks = checks + 1;
      if (!condition) $fatal(1, "MC6801 WAI response: %s", message);
    end
  endtask

  task automatic reset_to_wait;
    begin
      irq_n = 1'b1;
      irq_vector = 16'hfff0;
      nmi_n = 1'b1;
      reset_n = 1'b0;
      tick();
      reset_n = 1'b1;
      cycles = 0;
      while (!waiting_state) begin
        if (cycles >= 32) $fatal(1, "MC6801 WAI entry timeout");
        tick();
        cycles = cycles + 1;
      end
      check_value(debug_sp == 16'h01f8, "WAI stack pointer");
      check_value(bus_valid && !write_enable && address == 16'h01f8,
                  "steady WAI stack-pointer read");
    end
  endtask

  task automatic verify_response(
    input integer expected_cycles,
    input logic [15:0] expected_vector_address,
    input logic [15:0] expected_handler,
    input logic [1:0] expected_vector_class
  );
    integer stack_read_cycles;
    begin
      stack_read_cycles = expected_cycles - 2;
      cycles = 0;
      do begin
        check_value(bus_valid && !write_enable && !opcode_fetch,
                    "response cycle must be a non-fetch read");
        if (cycles < stack_read_cycles) begin
          check_value(address == 16'h01f8,
                      "response internal cycle must retain post-stack SP");
        end else begin
          checks = checks + 1;
          if (address != expected_vector_address +
              ((cycles == stack_read_cycles) ? 16'h0000 : 16'h0001)) begin
            $fatal(1, "MC6801 WAI response vector cycle=%0d address=%04x vector=%04x",
                   cycles, address, expected_vector_address);
          end
        end
        tick();
        cycles = cycles + 1;
        if (cycles > 8) $fatal(1, "MC6801 WAI response timeout");
      end while (!interrupt_ack);
      check_value(cycles == expected_cycles, "five/six-cycle latency");
      check_value(interrupt_vector == expected_vector_class,
                  "interrupt class at acknowledgement");
      check_value(debug_pc == expected_handler && debug_sp == 16'h01f8 &&
                  bus_valid && opcode_fetch && address == expected_handler,
                  "first handler opcode fetch without restacking");
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    irq_n = 1'b1;
    irq_vector = 16'hfff0;
    nmi_n = 1'b1;
    checks = 0;
    for (index = 0; index < 65536; index = index + 1) memory[index] = 8'h01;
    memory[16'hfffe] = 8'h10;
    memory[16'hffff] = 8'h00;
    memory[16'hfff0] = 8'h12;
    memory[16'hfff1] = 8'h00;
    memory[16'hfff8] = 8'h13;
    memory[16'hfff9] = 8'h00;
    memory[16'hfffc] = 8'h14;
    memory[16'hfffd] = 8'h00;
    memory[16'h1000] = 8'h8e;  // LDS #$01ff
    memory[16'h1001] = 8'h01;
    memory[16'h1002] = 8'hff;
    memory[16'h1003] = 8'h0e;  // CLI
    memory[16'h1004] = 8'h3e;  // WAI

    #1;
    reset_to_wait();
    nmi_n = 1'b0;
    verify_response(5, 16'hfffc, 16'h1400, 2'b10);

    reset_to_wait();
    irq_vector = 16'hfff0;  // IRQ2 peripheral class
    irq_n = 1'b0;
    verify_response(5, 16'hfff0, 16'h1200, 2'b01);

    reset_to_wait();
    irq_vector = 16'hfff8;  // synchronized external IRQ1
    irq_n = 1'b0;
    verify_response(6, 16'hfff8, 16'h1300, 2'b01);

    $display("MC6801 WAI RESPONSE PASS: %0d exact NMI/IRQ2/IRQ1 trace checks", checks);
    $finish;
  end
endmodule
