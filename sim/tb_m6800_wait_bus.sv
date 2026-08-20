// SPDX-License-Identifier: MIT
module tb_m6800_wait_bus #(
  parameter logic [1:0] TEST_ARCHITECTURE = 2'd0
);
  logic clk;
  logic reset_n;
  logic clock_enable;
  logic [7:0] data_in;
  logic [15:0] address;
  logic write_enable;
  logic bus_valid;
  logic opcode_fetch;
  logic waiting_state;
  logic [15:0] debug_sp;
  logic [7:0] memory [0:65535];
  integer cycle_count;
  integer index;
  integer checks;

  /* verilator lint_off PINCONNECTEMPTY */
  m6800_core #(.ARCHITECTURE(TEST_ARCHITECTURE)) dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(clock_enable),
    .bus_ready_i(1'b1), .irq_n_i(1'b1), .irq_vector_i(16'hfff8),
    .nmi_n_i(1'b1), .instruction_address_error_i(1'b0), .data_i(data_in),
    .address_o(address), .data_o(), .write_o(write_enable),
    .bus_valid_o(bus_valid), .opcode_fetch_o(opcode_fetch), .retire_o(),
    .illegal_o(), .undefined_o(), .waiting_o(waiting_state), .sleeping_o(),
    .interrupt_ack_o(), .interrupt_vector_o(), .debug_a_o(), .debug_b_o(),
    .debug_x_o(), .debug_sp_o(debug_sp), .debug_pc_o(), .debug_ccr_o(),
    .debug_opcode_o(), .debug_instruction_cycles_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  assign data_in = memory[address];
  always #5 clk = ~clk;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic check_wait_bus;
    begin
      if (!waiting_state || write_enable || opcode_fetch || debug_sp != 16'h01f8) begin
        $fatal(1, "WAI state/profile=%0d sp=%04x valid=%b write=%b fetch=%b",
               TEST_ARCHITECTURE, debug_sp, bus_valid, write_enable, opcode_fetch);
      end
      case (TEST_ARCHITECTURE)
        2'd0: begin
          if (bus_valid) $fatal(1, "MC6800 WAI must release normalized bus");
        end
        2'd1: begin
          if (!bus_valid || address != 16'h01f8) begin
            $fatal(1, "MC6801 WAI expected repeated post-stack SP read actual=%04x/%b",
                   address, bus_valid);
          end
        end
        default: begin
          if (bus_valid || address != 16'hffff) begin
            $fatal(1, "HD6301 WAI expected idle FFFF actual=%04x/%b",
                   address, bus_valid);
          end
        end
      endcase
      checks = checks + 1;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    clock_enable = 1'b1;
    checks = 0;
    for (index = 0; index < 65536; index = index + 1) memory[index] = 8'h00;
    memory[16'hfffe] = 8'h10;
    memory[16'hffff] = 8'h00;
    memory[16'h1000] = 8'h8e;  // LDS #$01ff
    memory[16'h1001] = 8'h01;
    memory[16'h1002] = 8'hff;
    memory[16'h1003] = 8'h3e;  // WAI

    #1;
    reset_n = 1'b0;
    #1;
    reset_n = 1'b1;

    cycle_count = 0;
    while (!waiting_state) begin
      if (cycle_count >= 24) $fatal(1, "WAI entry timeout profile=%0d", TEST_ARCHITECTURE);
      tick();
      cycle_count = cycle_count + 1;
    end

    check_wait_bus();
    repeat (4) begin
      tick();
      check_wait_bus();
    end

    clock_enable = 1'b0;
    tick();
    check_wait_bus();

    $display("M6800-lineage WAI BUS PASS profile=%0d checks=%0d", TEST_ARCHITECTURE, checks);
    $finish;
  end
endmodule
