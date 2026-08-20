// SPDX-License-Identifier: MIT
module hd63701v0_modes_formal;
  (* anyseq *) logic clk;
  logic past_valid = 1'b0;
  logic reset_n;
  logic mode0_program;
  logic mode0_external;
  logic [15:0] mode0_address;
  logic mode5_program;
  logic mode5_external;
  logic [15:0] mode5_address;

  assign reset_n = past_valid;
  always @(posedge clk) past_valid <= 1'b1;

  /* verilator lint_off PINCONNECTEMPTY */
  hd63701v0_mcu #(.OPERATING_MODE(3'd0)) mode0 (
    .clk_i(clk), .reset_n_i(reset_n), .standby_n_i(1'b1),
    .clock_enable_i(1'b1), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
    .standby_power_ok_i(1'b1), .port1_i(8'hff), .port2_i(5'h1f),
    .port3_i(8'hff), .port4_i(8'hff), .is3_n_i(1'b1),
    .program_address_o(), .program_read_o(mode0_program),
    .program_data_i(8'hff), .external_address_o(mode0_address),
    .external_data_o(), .external_write_o(),
    .external_bus_valid_o(mode0_external), .external_opcode_fetch_o(),
    .external_data_i(8'hff), .port1_o(), .port1_oe_o(), .port2_o(),
    .port2_oe_o(), .port3_o(), .port3_oe_o(), .port4_o(), .port4_oe_o(),
    .os3_n_o(), .sci_tx_o(), .sci_clock_o(), .timer_irq_o(), .sci_irq_o(),
    .opcode_fetch_o(), .retire_o(), .illegal_o(), .undefined_o(), .waiting_o(),
    .sleeping_o(), .interrupt_ack_o(), .debug_address_o(), .debug_pc_o(),
    .debug_sp_o(), .debug_a_o(), .debug_b_o(), .debug_x_o(), .debug_ccr_o(),
    .debug_timer_o(), .debug_output_compare_o(), .debug_input_capture_o(),
    .debug_tcsr_o(), .debug_trcsr_o(), .debug_receive_data_o(), .debug_opcode_o()
  );

  hd63701v0_mcu #(.OPERATING_MODE(3'd5)) mode5 (
    .clk_i(clk), .reset_n_i(reset_n), .standby_n_i(1'b1),
    .clock_enable_i(1'b1), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
    .standby_power_ok_i(1'b1), .port1_i(8'hff), .port2_i(5'h1f),
    .port3_i(8'hff), .port4_i(8'hff), .is3_n_i(1'b1),
    .program_address_o(), .program_read_o(mode5_program),
    .program_data_i(8'hff), .external_address_o(mode5_address),
    .external_data_o(), .external_write_o(),
    .external_bus_valid_o(mode5_external), .external_opcode_fetch_o(),
    .external_data_i(8'hff), .port1_o(), .port1_oe_o(), .port2_o(),
    .port2_oe_o(), .port3_o(), .port3_oe_o(), .port4_o(), .port4_oe_o(),
    .os3_n_o(), .sci_tx_o(), .sci_clock_o(),
    .timer_irq_o(), .sci_irq_o(), .opcode_fetch_o(), .retire_o(), .illegal_o(),
    .undefined_o(), .waiting_o(), .sleeping_o(), .interrupt_ack_o(),
    .debug_address_o(), .debug_pc_o(), .debug_sp_o(), .debug_a_o(),
    .debug_b_o(), .debug_x_o(), .debug_ccr_o(), .debug_timer_o(),
    .debug_output_compare_o(), .debug_input_capture_o(), .debug_tcsr_o(),
    .debug_trcsr_o(), .debug_receive_data_o(), .debug_opcode_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always @* begin
    assert (!(mode0_program && mode0_external));
    assert (!(mode5_program && mode5_external));
    if (mode0_program) assert (mode0_address >= 16'hf000);
    if (mode0_external && (mode0_address >= 16'hf000))
      assert (mode0_address >= 16'hfffe);
    if (mode5_program) assert (mode5_address >= 16'hf000);
    if (mode5_external)
      assert ((mode5_address >= 16'h0100) && (mode5_address <= 16'h01ff));
  end
endmodule
