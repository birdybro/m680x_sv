// SPDX-License-Identifier: MIT
module mc68705p5_mcu_formal;
  (* anyseq *) logic clk;
  logic reset_n;
  logic past_valid = 1'b0;
  (* anyseq *) logic clock_enable;
  (* anyseq *) logic int_n;
  (* anyseq *) logic timer_pin;
  (* anyseq *) logic [7:0] port_a_in;
  (* anyseq *) logic [7:0] port_b_in;
  (* anyseq *) logic [3:0] port_c_in;
  (* anyseq *) logic [7:0] program_data;
  (* anyseq *) logic vpp_present;
  (* anyseq *) logic bootstrap_voltage;
  logic [7:0] port_a_out;
  logic [7:0] port_b_out;
  logic [3:0] port_c_out;
  logic [7:0] port_a_oe;
  logic [7:0] port_b_oe;
  logic [3:0] port_c_oe;
  logic [10:0] program_address;
  logic program_read;
  logic bootstrap_mode;
  logic eprom_latch_enable;
  logic eprom_program_enable;
  logic [10:0] eprom_program_address;
  logic [7:0] eprom_program_data;
  logic [15:0] debug_address;
  logic [15:0] debug_pc;
  logic [15:0] debug_sp;
  logic [7:0] debug_a;
  logic [7:0] debug_x;
  logic [4:0] debug_ccr;
  logic [7:0] debug_opcode;
  logic [7:0] debug_timer;
  logic [7:0] debug_tcr;
  logic [7:0] debug_pcr;
  logic timer_irq;

  assign reset_n = past_valid;
  always @(posedge clk) past_valid <= 1'b1;

  /* verilator lint_off PINCONNECTEMPTY */
  mc68705p5_mcu dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(clock_enable),
    .int_n_i(int_n), .timer_i(timer_pin), .port_a_i(port_a_in),
    .port_b_i(port_b_in), .port_c_i(port_c_in), .port_a_o(port_a_out),
    .port_b_o(port_b_out), .port_c_o(port_c_out), .port_a_oe_o(port_a_oe),
    .port_b_oe_o(port_b_oe), .port_c_oe_o(port_c_oe),
    .program_address_o(program_address), .program_read_o(program_read),
    .program_data_i(program_data), .vpp_present_i(vpp_present),
    .bootstrap_voltage_i(bootstrap_voltage), .bootstrap_mode_o(bootstrap_mode),
    .eprom_latch_enable_o(eprom_latch_enable),
    .eprom_program_enable_o(eprom_program_enable),
    .eprom_program_address_o(eprom_program_address),
    .eprom_program_data_o(eprom_program_data), .timer_irq_o(timer_irq),
    .external_irq_o(), .opcode_fetch_o(), .retire_o(), .illegal_o(),
    .undefined_o(), .waiting_o(), .stopped_o(), .interrupt_ack_o(),
    .debug_address_o(debug_address), .debug_pc_o(debug_pc),
    .debug_sp_o(debug_sp), .debug_a_o(debug_a), .debug_x_o(debug_x),
    .debug_ccr_o(debug_ccr), .debug_opcode_o(debug_opcode),
    .debug_instruction_cycles_o(), .debug_timer_o(debug_timer),
    .debug_timer_control_o(debug_tcr), .debug_program_control_o(debug_pcr)
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always @* begin
    assert (debug_address[15:11] == 5'h00);
    assert (debug_pc[15:11] == 5'h00);
    assert (debug_sp[15:7] == 9'h000);
    assert (debug_sp[6:5] == 2'b11);
    assert (debug_tcr[3] == 1'b0);
    assert (timer_irq == (debug_tcr[7] && !debug_tcr[6]));
    assert (debug_pcr[7:3] == 5'h1f);
    assert (debug_pcr[2] == !vpp_present);
    if (past_valid) assert (debug_pcr[1] || !debug_pcr[0]);
    assert (eprom_latch_enable == (vpp_present && !debug_pcr[0]));
    assert (eprom_program_enable ==
            (vpp_present && !debug_pcr[1] && !debug_pcr[0]));
    if (program_address != debug_address[10:0]) begin
      assert (bootstrap_mode);
      assert ((debug_address[10:0] == 11'h7fe &&
               program_address == 11'h7f6) ||
              (debug_address[10:0] == 11'h7ff &&
               program_address == 11'h7f7));
    end
    if (program_read) begin
      assert ((program_address >= 11'h080 && program_address <= 11'h783) ||
              (program_address >= 11'h785));
    end
    if (program_read && vpp_present &&
        !((program_address >= 11'h785) && (program_address <= 11'h7f7))) begin
      assert (debug_pcr[0]);
    end
    if (!reset_n) begin
      assert (debug_timer == 8'hff);
      assert (debug_tcr == 8'h40);
    end
  end

  always @(posedge clk) begin
    if (past_valid && $past(past_valid) && !$past(clock_enable) &&
        reset_n && $past(reset_n)) begin
      assert ({port_a_out, port_b_out, port_c_out, port_a_oe, port_b_oe,
               port_c_oe, debug_pc, debug_sp, debug_a, debug_x, debug_ccr,
               debug_opcode, debug_timer, debug_tcr,
               eprom_program_address, eprom_program_data} ==
              $past({port_a_out, port_b_out, port_c_out, port_a_oe, port_b_oe,
                     port_c_oe, debug_pc, debug_sp, debug_a, debug_x,
                     debug_ccr, debug_opcode, debug_timer, debug_tcr,
                     eprom_program_address, eprom_program_data}));
    end
  end
endmodule
