// SPDX-License-Identifier: MIT
module mc6801_mcu_formal;
  (* anyseq *) logic clk;
  logic reset_n;
  logic past_valid = 1'b0;
  (* anyseq *) logic clock_enable;
  (* anyseq *) logic nmi_n;
  (* anyseq *) logic irq1_n;
  (* anyseq *) logic standby_power_ok;
  (* anyseq *) logic [7:0] port1_in;
  (* anyseq *) logic [4:0] port2_in;
  (* anyseq *) logic [7:0] external_data_in;
  logic [15:0] external_address;
  logic [7:0] external_data_out;
  logic external_write;
  logic external_valid;
  logic external_fetch;
  logic [7:0] port1_out;
  logic [7:0] port1_oe;
  logic [4:0] port2_out;
  logic [4:0] port2_oe;
  logic sci_tx;
  logic sci_clock;
  logic timer_irq;
  logic sci_irq;
  logic opcode_fetch;
  logic retire;
  logic illegal;
  logic undefined_value;
  logic waiting_state;
  logic sleeping_state;
  logic interrupt_ack;
  logic [15:0] debug_address;
  logic [15:0] debug_pc;
  logic [15:0] debug_sp;
  logic [7:0] debug_a;
  logic [7:0] debug_b;
  logic [15:0] debug_x;
  logic [5:0] debug_ccr;
  logic [15:0] debug_timer;
  logic [15:0] debug_compare;
  logic [15:0] debug_capture;
  logic [7:0] debug_tcsr;
  logic [7:0] debug_trcsr;
  logic [7:0] debug_receive_data;
  logic [7:0] debug_opcode;

  assign reset_n = past_valid;
  always @(posedge clk) past_valid <= 1'b1;

  /* verilator lint_off PINCONNECTEMPTY */
  mc6801_mcu #(.OPERATING_MODE(3'd3)) dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(clock_enable),
    .nmi_n_i(nmi_n), .irq1_n_i(irq1_n),
    .standby_power_ok_i(standby_power_ok), .port1_i(port1_in),
    .port2_i(port2_in), .port3_i(8'hff), .port4_i(8'hff), .is3_n_i(1'b1),
    .program_data_i(8'hff), .external_data_i(external_data_in),
    .program_address_o(), .program_read_o(),
    .external_address_o(external_address), .external_data_o(external_data_out),
    .external_write_o(external_write), .external_bus_valid_o(external_valid),
    .external_opcode_fetch_o(external_fetch), .port1_o(port1_out),
    .port1_oe_o(port1_oe), .port2_o(port2_out), .port2_oe_o(port2_oe),
    .port3_o(), .port3_oe_o(), .port4_o(), .port4_oe_o(), .os3_n_o(),
    .sci_tx_o(sci_tx), .sci_clock_o(sci_clock), .timer_irq_o(timer_irq),
    .sci_irq_o(sci_irq), .opcode_fetch_o(opcode_fetch), .retire_o(retire),
    .illegal_o(illegal), .undefined_o(undefined_value), .waiting_o(waiting_state),
    .sleeping_o(sleeping_state),
    .interrupt_ack_o(interrupt_ack), .debug_address_o(debug_address),
    .debug_pc_o(debug_pc), .debug_sp_o(debug_sp), .debug_a_o(debug_a),
    .debug_b_o(debug_b), .debug_x_o(debug_x), .debug_ccr_o(debug_ccr),
    .debug_timer_o(debug_timer), .debug_output_compare_o(debug_compare),
    .debug_input_capture_o(debug_capture), .debug_tcsr_o(debug_tcsr),
    .debug_trcsr_o(debug_trcsr), .debug_receive_data_o(debug_receive_data),
    .debug_opcode_o(debug_opcode)
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always @* begin
    if (external_fetch) begin
      assert (external_valid);
      assert (!external_write);
      assert (opcode_fetch);
    end
    if (external_valid) begin
      assert ((external_address > 16'h0014) ||
              ((external_address >= 16'h0004) && (external_address <= 16'h0007)) ||
              (external_address == 16'h000f));
    end
    assert (debug_address == external_address);
    if (debug_trcsr[1]) assert (port2_oe[4]);
    if (debug_trcsr[3]) assert (!port2_oe[3]);
  end

  always @(posedge clk) begin
    if (past_valid && $past(past_valid) && !$past(clock_enable)) begin
      assert ({port1_out, port1_oe, port2_out, port2_oe, debug_pc, debug_sp,
               debug_a, debug_b, debug_x, debug_ccr, debug_timer, debug_compare,
               debug_capture, debug_tcsr, debug_trcsr, debug_receive_data,
               debug_opcode, sleeping_state} ==
              $past({port1_out, port1_oe, port2_out, port2_oe, debug_pc, debug_sp,
                     debug_a, debug_b, debug_x, debug_ccr, debug_timer,
                     debug_compare, debug_capture, debug_tcsr, debug_trcsr,
                     debug_receive_data, debug_opcode, sleeping_state}));
    end
  end
endmodule
