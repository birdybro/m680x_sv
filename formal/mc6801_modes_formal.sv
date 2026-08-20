// SPDX-License-Identifier: MIT
module mc6801_modes_formal;
  (* anyseq *) logic clk;
  logic past_valid = 1'b0;
  logic reset_n;
  logic mode0_program_read;
  logic mode0_external_valid;
  logic [15:0] mode0_address;
  logic [7:0] mode0_port3;
  logic [7:0] mode0_port3_oe;
  logic mode4_program_read;
  logic mode4_external_valid;
  logic [15:0] mode4_address;

  assign reset_n = past_valid;

  always @(posedge clk) past_valid <= 1'b1;

  /* verilator lint_off PINCONNECTEMPTY */
  mc6801_mcu #(.OPERATING_MODE(3'd0)) mode0 (
    .clk_i(clk), .reset_n_i(reset_n), .standby_reset_n_i(1'b1),
    .clock_enable_i(1'b1), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
    .standby_power_ok_i(1'b1), .port1_i(8'hff), .port2_i(5'h1f),
    .port3_i(8'hff), .port4_i(8'hff), .is3_n_i(1'b1),
    .program_data_i(8'hff), .external_data_i(8'hff), .program_address_o(),
    .program_read_o(mode0_program_read), .external_address_o(mode0_address),
    .external_data_o(), .external_write_o(),
    .external_bus_valid_o(mode0_external_valid), .external_opcode_fetch_o(),
    .port1_o(), .port1_oe_o(), .port2_o(), .port2_oe_o(),
    .port3_o(mode0_port3), .port3_oe_o(mode0_port3_oe), .port4_o(),
    .port4_oe_o(), .os3_n_o(), .sci_tx_o(),
    .sci_clock_o(), .timer_irq_o(), .sci_irq_o(), .opcode_fetch_o(),
    .retire_o(), .illegal_o(), .undefined_o(), .waiting_o(), .sleeping_o(),
    .interrupt_ack_o(), .debug_address_o(), .debug_pc_o(), .debug_sp_o(),
    .debug_a_o(), .debug_b_o(), .debug_x_o(), .debug_ccr_o(),
    .debug_timer_o(), .debug_output_compare_o(), .debug_input_capture_o(),
    .debug_tcsr_o(), .debug_trcsr_o(), .debug_receive_data_o(),
    .debug_opcode_o()
  );

  mc6801_mcu #(.OPERATING_MODE(3'd4)) mode4 (
    .clk_i(clk), .reset_n_i(reset_n), .standby_reset_n_i(1'b1),
    .clock_enable_i(1'b1), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
    .standby_power_ok_i(1'b1), .port1_i(8'hff), .port2_i(5'h1f),
    .port3_i(8'hff), .port4_i(8'hff), .is3_n_i(1'b1),
    .program_data_i(8'hff), .external_data_i(8'hff), .program_address_o(),
    .program_read_o(mode4_program_read), .external_address_o(mode4_address),
    .external_data_o(), .external_write_o(),
    .external_bus_valid_o(mode4_external_valid), .external_opcode_fetch_o(),
    .port1_o(), .port1_oe_o(), .port2_o(), .port2_oe_o(), .port3_o(),
    .port3_oe_o(), .port4_o(), .port4_oe_o(), .os3_n_o(), .sci_tx_o(),
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
    if (past_valid) begin
      assert (!(mode0_program_read && mode0_external_valid));
      assert (!(mode4_program_read && mode4_external_valid));

      if (mode0_program_read) begin
        assert (mode0_address >= 16'hf800);
        assert (mode0_port3_oe == 8'hff);
        assert (mode0_port3 == 8'hff);
      end
      if (mode0_external_valid && (mode0_address >= 16'hfffe))
        assert (!mode0_program_read);
      if (mode4_program_read) assert (mode4_address >= 16'hf800);
      if (mode4_external_valid) begin
        assert ((mode4_address >= 16'h0100) &&
                (mode4_address <= 16'h01ff));
      end
    end
  end
endmodule
