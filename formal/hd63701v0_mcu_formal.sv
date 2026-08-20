// SPDX-License-Identifier: MIT
module hd63701v0_mcu_formal;
  (* anyseq *) logic clk;
  logic reset_n;
  logic past_valid = 1'b0;
  (* anyseq *) logic clock_enable;
  (* anyseq *) logic nmi_n;
  (* anyseq *) logic irq1_n;
  (* anyseq *) logic standby_n;
  (* anyseq *) logic standby_power_ok;
  (* anyseq *) logic [7:0] port1_in;
  (* anyseq *) logic [4:0] port2_in;
  (* anyseq *) logic [7:0] port3_in;
  (* anyseq *) logic [7:0] port4_in;
  (* anyseq *) logic is3_n;
  (* anyseq *) logic [7:0] program_data;
  logic [15:0] program_address;
  logic program_read;
  logic [7:0] port1_out;
  logic [7:0] port1_oe;
  logic [4:0] port2_out;
  logic [4:0] port2_oe;
  logic [7:0] port3_out;
  logic [7:0] port3_oe;
  logic [7:0] port4_out;
  logic [7:0] port4_oe;
  logic os3_n;
  logic opcode_fetch;
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
  logic [7:0] debug_receive;
  logic [7:0] debug_opcode;
  logic sleeping;

  assign reset_n = past_valid;
  always @(posedge clk) past_valid <= 1'b1;

  /* verilator lint_off PINCONNECTEMPTY */
  hd63701v0_mcu dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(clock_enable),
    .standby_n_i(standby_n),
    .nmi_n_i(nmi_n), .irq1_n_i(irq1_n),
    .standby_power_ok_i(standby_power_ok), .port1_i(port1_in),
    .port2_i(port2_in), .port3_i(port3_in), .port4_i(port4_in),
    .is3_n_i(is3_n), .program_address_o(program_address),
    .program_read_o(program_read), .program_data_i(program_data),
    .port1_o(port1_out), .port1_oe_o(port1_oe), .port2_o(port2_out),
    .port2_oe_o(port2_oe), .port3_o(port3_out), .port3_oe_o(port3_oe),
    .port4_o(port4_out), .port4_oe_o(port4_oe), .os3_n_o(os3_n),
    .sci_tx_o(), .sci_clock_o(), .timer_irq_o(), .sci_irq_o(),
    .opcode_fetch_o(opcode_fetch), .retire_o(), .illegal_o(), .undefined_o(),
    .waiting_o(), .sleeping_o(sleeping), .interrupt_ack_o(),
    .debug_address_o(debug_address), .debug_pc_o(debug_pc),
    .debug_sp_o(debug_sp), .debug_a_o(debug_a), .debug_b_o(debug_b),
    .debug_x_o(debug_x), .debug_ccr_o(debug_ccr),
    .debug_timer_o(debug_timer), .debug_output_compare_o(debug_compare),
    .debug_input_capture_o(debug_capture), .debug_tcsr_o(debug_tcsr),
    .debug_trcsr_o(debug_trcsr), .debug_receive_data_o(debug_receive),
    .debug_opcode_o(debug_opcode)
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always @* begin
    assert (program_address == debug_address);
    if (program_read) assert (program_address >= 16'hf000);
    if (opcode_fetch && ((debug_address <= 16'h003f) ||
        ((debug_address >= 16'h0100) && (debug_address <= 16'hefff)))) begin
      assert (!program_read);
    end
    if (!os3_n) assert (debug_address == 16'h0006);
    if (!standby_n) begin
      assert (!program_read);
      assert ({port1_oe, port2_oe, port3_oe, port4_oe} == '0);
    end
  end

  always @(posedge clk) begin
    if (past_valid && $past(past_valid) && !$past(clock_enable) &&
        $past(standby_n) && standby_n) begin
      assert ({port1_out, port1_oe, port2_out, port2_oe, port3_out, port3_oe,
               port4_out, port4_oe, debug_pc, debug_sp, debug_a, debug_b,
               debug_x, debug_ccr, debug_timer, debug_compare, debug_capture,
               debug_tcsr, debug_trcsr, debug_receive, debug_opcode, sleeping} ==
              $past({port1_out, port1_oe, port2_out, port2_oe, port3_out,
                     port3_oe, port4_out, port4_oe, debug_pc, debug_sp,
                     debug_a, debug_b, debug_x, debug_ccr, debug_timer,
                     debug_compare, debug_capture, debug_tcsr, debug_trcsr,
                     debug_receive, debug_opcode, sleeping}));
    end
  end
endmodule
