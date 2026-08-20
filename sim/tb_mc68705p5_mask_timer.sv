// SPDX-License-Identifier: MIT
module tb_mc68705p5_mask_timer;
  import mc68705p5_peripheral_bus_stub_pkg::*;

  logic clk;
  logic reset_n;
  logic timer_pin;
  logic bootstrap_mode;
  logic timer_irq;
  logic [7:0] debug_timer;
  logic [7:0] debug_tcr;
  integer edge_index;
  integer checks;

  /* verilator lint_off PINCONNECTEMPTY */
  mc68705p5_mcu #(.MASK_OPTION(8'h6a)) dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(1'b1),
    .int_n_i(1'b1), .timer_i(timer_pin), .port_a_i(8'hff),
    .port_b_i(8'hff), .port_c_i(4'hf), .port_a_o(), .port_b_o(),
    .port_c_o(), .port_a_oe_o(), .port_b_oe_o(), .port_c_oe_o(),
    .program_address_o(), .program_read_o(), .program_data_i(8'hff),
    .vpp_present_i(1'b0), .bootstrap_voltage_i(1'b1),
    .bootstrap_mode_o(bootstrap_mode), .eprom_latch_enable_o(),
    .eprom_program_enable_o(), .eprom_program_address_o(),
    .eprom_program_data_o(), .timer_irq_o(timer_irq), .external_irq_o(),
    .opcode_fetch_o(), .retire_o(), .illegal_o(), .undefined_o(),
    .waiting_o(), .stopped_o(), .interrupt_ack_o(), .debug_address_o(),
    .debug_pc_o(), .debug_sp_o(), .debug_a_o(), .debug_x_o(),
    .debug_ccr_o(), .debug_opcode_o(), .debug_instruction_cycles_o(),
    .debug_timer_o(debug_timer), .debug_timer_control_o(debug_tcr),
    .debug_program_control_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always #5 clk <= ~clk;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic write_register(input logic [10:0] address_value,
                                input logic [7:0] data_value);
    begin
      stub_address = {5'h00, address_value};
      stub_data = data_value;
      stub_write = 1'b1;
      stub_valid = 1'b1;
      tick();
      stub_valid = 1'b0;
      stub_write = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    timer_pin = 1'b0;
    stub_address = 16'h0000;
    stub_data = 8'h00;
    stub_write = 1'b0;
    stub_valid = 1'b0;
    stub_interrupt_mask = 1'b1;
    checks = 0;
    #1;
    reset_n = 1'b0;
    #1;
    reset_n = 1'b1;
    tick();
    if (debug_tcr != 8'h7f || debug_timer != 8'hff || bootstrap_mode) begin
      $fatal(1, "P5 MOR reset/secure state tcr=%02x tdr=%02x boot=%b",
             debug_tcr, debug_timer, bootstrap_mode);
    end
    checks = checks + 1;

    // TOPT exposes only TIR/TIM; all six lower TCR bits read one and ignore writes.
    write_register(11'h009, 8'h00);
    if (debug_tcr != 8'h3f) $fatal(1, "P5 MOR-controlled TCR write %02x", debug_tcr);
    checks = checks + 1;
    write_register(11'h008, 8'h02);

    // MOR selects external positive transitions divided by four.  The reset
    // all-ones prescaler gives an immediate count, then four events per count.
    for (edge_index = 0; edge_index < 5; edge_index = edge_index + 1) begin
      timer_pin = 1'b1;
      tick();
      timer_pin = 1'b0;
      tick();
      if (edge_index == 0 && debug_timer != 8'h01) begin
        $fatal(1, "P5 MOR first timer event %02x", debug_timer);
      end
    end
    if (debug_timer != 8'h00 || !timer_irq || !debug_tcr[7]) begin
      $fatal(1, "P5 MOR timer underflow tdr=%02x tcr=%02x irq=%b",
             debug_timer, debug_tcr, timer_irq);
    end
    checks = checks + 2;

    write_register(11'h009, 8'h40);
    if (timer_irq || debug_tcr != 8'h7f) begin
      $fatal(1, "P5 MOR timer request/mask clear tcr=%02x irq=%b",
             debug_tcr, timer_irq);
    end
    checks = checks + 1;
    $display("MC68705P5 MOR TIMER PASS: %0d fixed-option checks", checks);
    $finish;
  end
endmodule
