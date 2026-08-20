// SPDX-License-Identifier: MIT
module hd63701v0_prom_formal;
  (* anyseq *) logic clk;
  (* anyseq *) logic prom_mode;
  (* anyseq *) logic prom_vpp;
  (* anyseq *) logic irq_a9;
  (* anyseq *) logic [7:0] port1;
  (* anyseq *) logic [7:0] port3;
  (* anyseq *) logic [7:0] port4;
  (* anyseq *) logic [7:0] program_data;
  logic [14:0] prom_address;
  logic [15:0] program_address;
  logic program_read;
  logic [7:0] prom_data;
  logic prom_data_oe;
  logic [7:0] prom_program_data;
  logic prom_program;
  logic external_valid;
  logic external_fetch;
  logic os3_n;
  logic timer_irq;
  logic sci_irq;
  logic [7:0] port1_oe;
  logic [4:0] port2_oe;
  logic [7:0] port3_out;
  logic [7:0] port3_oe;
  logic [7:0] port4_oe;
  logic sci_tx;
  logic sci_clock;
  logic opcode_fetch;
  logic retire;
  logic illegal;
  logic undefined_instruction;
  logic waiting;
  logic sleeping;
  logic interrupt_ack;
  logic internal_address;
  logic read_select;
  logic verify_select;

  assign internal_address = prom_address <= 15'h0fff;
  assign read_select = prom_mode && !prom_vpp && !port4[7] && !port4[6];
  assign verify_select = prom_mode && prom_vpp && port4[7] && !port4[6];

  /* verilator lint_off PINCONNECTEMPTY */
  hd63701v0_mcu #(.OPERATING_MODE(3'd2)) dut (
    .clk_i(clk), .reset_n_i(1'b1), .standby_n_i(1'b1),
    .clock_enable_i(1'b1), .nmi_n_i(1'b1), .irq1_n_i(irq_a9),
    .standby_power_ok_i(1'b1), .port1_i(port1), .port2_i(5'h1f),
    .port3_i(port3), .port4_i(port4), .is3_n_i(1'b1),
    .program_address_o(program_address), .program_read_o(program_read),
    .program_data_i(program_data), .prom_mode_i(prom_mode),
    .prom_program_voltage_i(prom_vpp), .prom_address_o(prom_address),
    .prom_data_o(prom_data), .prom_data_oe_o(prom_data_oe),
    .prom_program_data_o(prom_program_data), .prom_program_o(prom_program),
    .external_address_o(), .external_data_o(), .external_write_o(),
    .external_bus_valid_o(external_valid),
    .external_opcode_fetch_o(external_fetch), .external_data_i(8'hff),
    .port1_o(), .port1_oe_o(port1_oe), .port2_o(),
    .port2_oe_o(port2_oe), .port3_o(port3_out), .port3_oe_o(port3_oe),
    .port4_o(), .port4_oe_o(port4_oe), .os3_n_o(os3_n), .sci_tx_o(sci_tx),
    .sci_clock_o(sci_clock), .timer_irq_o(timer_irq), .sci_irq_o(sci_irq),
    .opcode_fetch_o(opcode_fetch), .retire_o(retire), .illegal_o(illegal),
    .undefined_o(undefined_instruction), .waiting_o(waiting),
    .sleeping_o(sleeping),
    .interrupt_ack_o(interrupt_ack), .debug_address_o(), .debug_pc_o(),
    .debug_sp_o(), .debug_a_o(), .debug_b_o(), .debug_x_o(), .debug_ccr_o(),
    .debug_timer_o(), .debug_output_compare_o(), .debug_input_capture_o(),
    .debug_tcsr_o(), .debug_trcsr_o(), .debug_receive_data_o(),
    .debug_opcode_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always @* begin
    assert (prom_address == {port4[1], port4[5:2], irq_a9,
                             port4[0], port1});
    assert (prom_program_data == port3);
    assert (prom_data_oe == (read_select || verify_select));
    assert (prom_program == (prom_mode && prom_vpp && !port4[7] &&
                             port4[6] && internal_address));
    if (prom_mode) begin
      assert (program_address == {4'hf, prom_address[11:0]});
      assert (program_read == ((read_select || verify_select) &&
                               internal_address));
      assert (port1_oe == 8'h00);
      assert (port2_oe == 5'h00);
      assert (port4_oe == 8'h00);
      assert (port3_out == prom_data);
      assert (port3_oe == {8{prom_data_oe}});
      assert (!external_valid && !external_fetch);
      assert (!opcode_fetch && !retire && !waiting && !sleeping &&
              !interrupt_ack);
      assert (!illegal && !undefined_instruction && !timer_irq && !sci_irq);
      assert (os3_n);
      assert (sci_tx && !sci_clock);
      if (internal_address) assert (prom_data == program_data);
      else assert (prom_data == 8'hff);
    end
  end
endmodule
