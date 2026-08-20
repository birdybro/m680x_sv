// SPDX-License-Identifier: MIT
module hd6303r_modes_formal;
  (* anyseq *) logic clk;
  logic past_valid = 1'b0;
  logic reset_n;
  logic mode1_program_read;
  logic mode1_external_valid;
  logic [15:0] mode1_address;
  logic [7:0] mode1_port1;
  logic [7:0] mode1_port1_oe;
  logic mode4_program_read;
  logic mode4_external_valid;
  logic [15:0] mode4_address;
  logic [7:0] mode4_port4;
  logic [7:0] mode4_port4_oe;

  assign reset_n = past_valid;
  always @(posedge clk) past_valid <= 1'b1;

  /* verilator lint_off PINCONNECTEMPTY */
  mc6801_mcu #(
    .OPERATING_MODE(3'd1), .HITACHI_CPU(1'b1), .HITACHI_NEW_MODES(1'b1),
    .SCI_BIPHASE_SUPPORTED(1'b0)
  ) mode1 (
    .clk_i(clk), .reset_n_i(reset_n), .standby_reset_n_i(1'b1),
    .clock_enable_i(1'b1), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
    .standby_power_ok_i(1'b1), .port1_i(8'hff), .port2_i(5'h1f),
    .port3_i(8'hff), .port4_i(8'hff), .is3_n_i(1'b1),
    .program_data_i(8'hff), .external_data_i(8'hff), .program_address_o(),
    .program_read_o(mode1_program_read), .external_address_o(mode1_address),
    .external_data_o(), .external_write_o(),
    .external_bus_valid_o(mode1_external_valid), .external_opcode_fetch_o(),
    .port1_o(mode1_port1), .port1_oe_o(mode1_port1_oe), .port2_o(),
    .port2_oe_o(), .port3_o(), .port3_oe_o(), .port4_o(), .port4_oe_o(),
    .os3_n_o(), .sci_tx_o(), .sci_clock_o(), .timer_irq_o(), .sci_irq_o(),
    .opcode_fetch_o(), .retire_o(), .illegal_o(), .undefined_o(), .waiting_o(),
    .sleeping_o(), .interrupt_ack_o(), .debug_address_o(), .debug_pc_o(),
    .debug_sp_o(), .debug_a_o(), .debug_b_o(), .debug_x_o(), .debug_ccr_o(),
    .debug_timer_o(), .debug_output_compare_o(), .debug_input_capture_o(),
    .debug_tcsr_o(), .debug_trcsr_o(), .debug_receive_data_o(),
    .debug_opcode_o()
  );

  mc6801_mcu #(
    .OPERATING_MODE(3'd4), .HITACHI_CPU(1'b1), .HITACHI_NEW_MODES(1'b1),
    .SCI_BIPHASE_SUPPORTED(1'b0)
  ) mode4 (
    .clk_i(clk), .reset_n_i(reset_n), .standby_reset_n_i(1'b1),
    .clock_enable_i(1'b1), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
    .standby_power_ok_i(1'b1), .port1_i(8'hff), .port2_i(5'h1f),
    .port3_i(8'hff), .port4_i(8'hff), .is3_n_i(1'b1),
    .program_data_i(8'hff), .external_data_i(8'hff), .program_address_o(),
    .program_read_o(mode4_program_read), .external_address_o(mode4_address),
    .external_data_o(), .external_write_o(),
    .external_bus_valid_o(mode4_external_valid), .external_opcode_fetch_o(),
    .port1_o(), .port1_oe_o(), .port2_o(), .port2_oe_o(), .port3_o(),
    .port3_oe_o(), .port4_o(mode4_port4), .port4_oe_o(mode4_port4_oe),
    .os3_n_o(), .sci_tx_o(),
    .sci_clock_o(), .timer_irq_o(), .sci_irq_o(), .opcode_fetch_o(),
    .retire_o(), .illegal_o(), .undefined_o(), .waiting_o(), .sleeping_o(),
    .interrupt_ack_o(), .debug_address_o(), .debug_pc_o(), .debug_sp_o(),
    .debug_a_o(), .debug_b_o(), .debug_x_o(), .debug_ccr_o(),
    .debug_timer_o(), .debug_output_compare_o(), .debug_input_capture_o(),
    .debug_tcsr_o(), .debug_trcsr_o(), .debug_receive_data_o(),
    .debug_opcode_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always @* begin
    assert (!mode1_program_read);
    assert (!mode4_program_read);
    if (past_valid) begin
      assert (mode1_port1 == mode1_address[7:0]);
      assert (mode1_port1_oe == 8'hff);
      assert (mode4_port4 == mode4_address[15:8]);
      assert (mode4_port4_oe == 8'hff);
      if (mode1_external_valid) begin
        assert ((mode1_address == 16'h0000) ||
                (mode1_address == 16'h0002) ||
                ((mode1_address >= 16'h0004) &&
                 (mode1_address <= 16'h0007)) ||
                (mode1_address == 16'h000f) ||
                !((mode1_address >= 16'h0000) &&
                  (mode1_address <= 16'h0014)));
      end
      if (mode4_external_valid) begin
        assert (((mode4_address >= 16'h0004) &&
                 (mode4_address <= 16'h0007)) ||
                (mode4_address == 16'h000f) ||
                !((mode4_address >= 16'h0000) &&
                  (mode4_address <= 16'h0014)));
      end
    end
  end
endmodule
