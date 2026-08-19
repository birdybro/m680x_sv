// SPDX-License-Identifier: MIT
module hd63705v0_mcu_formal;
  (* anyseq *) logic clk;
  logic reset_n;
  logic past_valid = 1'b0;
  (* anyseq *) logic clock_enable;
  (* anyseq *) logic standby_n;
  (* anyseq *) logic int_n;
  (* anyseq *) logic int2_n;
  (* anyseq *) logic timer_pin;
  (* anyseq *) logic [7:0] port_a_in;
  (* anyseq *) logic [7:0] port_b_in;
  (* anyseq *) logic [7:0] port_c_in;
  (* anyseq *) logic [6:0] port_d_in;
  (* anyseq *) logic [7:0] program_data;
  (* anyseq *) logic eprom_mode;
  (* anyseq *) logic [11:0] eprom_address;
  (* anyseq *) logic [7:0] eprom_data_in;
  (* anyseq *) logic eprom_ce_n;
  (* anyseq *) logic eprom_oe_n;
  (* anyseq *) logic eprom_vpp;
  logic [7:0] port_a_out;
  logic [7:0] port_b_out;
  logic [7:0] port_c_out;
  logic [6:0] port_d_out;
  logic [7:0] port_a_oe;
  logic [7:0] port_b_oe;
  logic [7:0] port_c_oe;
  logic [6:0] port_d_oe;
  logic [13:0] program_address;
  logic program_read;
  logic [7:0] eprom_data_out;
  logic eprom_data_oe;
  logic [7:0] eprom_program_data;
  logic eprom_program;
  logic [15:0] irq_vector;
  logic [15:0] debug_address;
  logic [15:0] debug_pc;
  logic [15:0] debug_sp;
  logic [7:0] debug_a;
  logic [7:0] debug_x;
  logic [4:0] debug_ccr;
  logic [7:0] debug_opcode;
  logic [7:0] debug_timer;
  logic [7:0] debug_tcr;
  logic [7:0] debug_mr;
  logic [7:0] debug_scr;
  logic [7:0] debug_ssr;
  logic [7:0] debug_sdr;
  logic waiting_state;
  logic stopped_state;
  logic sci_clock;
  logic sci_tx;

  assign reset_n = past_valid;
  always @(posedge clk) past_valid <= 1'b1;

  /* verilator lint_off PINCONNECTEMPTY */
  hd63705v0_mcu dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(clock_enable),
    .standby_n_i(standby_n), .int_n_i(int_n), .int2_n_i(int2_n),
    .timer_i(timer_pin), .port_a_i(port_a_in), .port_b_i(port_b_in),
    .port_c_i(port_c_in), .port_d_i(port_d_in), .port_a_o(port_a_out),
    .port_b_o(port_b_out), .port_c_o(port_c_out), .port_d_o(port_d_out),
    .port_a_oe_o(port_a_oe), .port_b_oe_o(port_b_oe),
    .port_c_oe_o(port_c_oe), .port_d_oe_o(port_d_oe),
    .program_address_o(program_address), .program_read_o(program_read),
    .program_data_i(program_data), .eprom_mode_i(eprom_mode),
    .eprom_address_i(eprom_address), .eprom_data_i(eprom_data_in),
    .eprom_chip_enable_n_i(eprom_ce_n),
    .eprom_output_enable_n_i(eprom_oe_n),
    .eprom_program_voltage_i(eprom_vpp), .eprom_data_o(eprom_data_out),
    .eprom_data_oe_o(eprom_data_oe),
    .eprom_program_data_o(eprom_program_data), .eprom_program_o(eprom_program),
    .sci_tx_o(sci_tx), .sci_clock_o(sci_clock), .timer_irq_o(),
    .sci_irq_o(), .int_irq_o(), .int2_irq_o(), .irq_vector_o(irq_vector),
    .opcode_fetch_o(), .retire_o(), .illegal_o(), .undefined_o(),
    .waiting_o(waiting_state), .stopped_o(stopped_state),
    .interrupt_ack_o(), .debug_address_o(debug_address),
    .debug_pc_o(debug_pc), .debug_sp_o(debug_sp), .debug_a_o(debug_a),
    .debug_x_o(debug_x), .debug_ccr_o(debug_ccr),
    .debug_opcode_o(debug_opcode), .debug_instruction_cycles_o(),
    .debug_timer_o(debug_timer), .debug_tcr_o(debug_tcr),
    .debug_mr_o(debug_mr), .debug_scr_o(debug_scr),
    .debug_ssr_o(debug_ssr), .debug_sdr_o(debug_sdr)
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always @* begin
    assert (debug_address[15:14] == 2'b00);
    assert (debug_pc[15:14] == 2'b00);
    assert (debug_sp[15:8] == 8'h00);
    assert (debug_sp[7:6] == 2'b11);
    assert (debug_tcr[3] == 1'b0);
    assert (debug_mr[4:0] == 5'h1f);
    assert (debug_ssr[3:0] == 4'h7);
    assert (irq_vector == 16'h1ffa || irq_vector == 16'h1ff8 ||
            irq_vector == 16'h1ff6 || irq_vector == 16'h1ff4);
    if (eprom_mode) begin
      assert (program_address[13:12] == 2'b01);
      assert (program_read == (eprom_vpp && !eprom_oe_n));
      assert (eprom_data_oe == (eprom_vpp && !eprom_oe_n));
      assert ({port_a_oe, port_b_oe, port_c_oe, port_d_oe} == '0);
    end else if (program_read) begin
      assert (program_address >= 14'h1000 && program_address <= 14'h1fff);
    end
    if (!standby_n || !reset_n) begin
      assert ({port_a_oe, port_b_oe, port_c_oe, port_d_oe} == '0);
    end
    if (eprom_program) begin
      assert (eprom_mode && eprom_vpp && !eprom_ce_n && eprom_oe_n);
      assert (eprom_program_data == eprom_data_in);
    end
    assert (eprom_data_out == program_data);
  end

  always @(posedge clk) begin
    if (past_valid && $past(past_valid) && !$past(clock_enable) &&
        reset_n && $past(reset_n) && standby_n && $past(standby_n) &&
        !eprom_mode && !$past(eprom_mode)) begin
      assert ({port_a_out, port_b_out, port_c_out, port_d_out,
               debug_pc, debug_sp, debug_a, debug_x, debug_ccr, debug_opcode,
               debug_timer, debug_tcr, debug_mr, debug_scr, debug_ssr,
               debug_sdr, waiting_state, stopped_state, sci_clock, sci_tx} ==
              $past({port_a_out, port_b_out, port_c_out, port_d_out,
                     debug_pc, debug_sp, debug_a, debug_x, debug_ccr,
                     debug_opcode, debug_timer, debug_tcr, debug_mr,
                     debug_scr, debug_ssr, debug_sdr, waiting_state,
                     stopped_state, sci_clock, sci_tx}));
    end
  end
endmodule
