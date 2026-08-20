// SPDX-License-Identifier: MIT
module mc6801_bus_wrapper_formal;
  (* anyseq *) logic clk;
  (* anyseq *) logic clock_enable;
  logic past_valid = 1'b0;
  logic reset_n;
  logic [1:0] phase2;
  logic e2;
  logic [7:0] p3_mode2;
  logic [7:0] p3oe_mode2;
  logic [7:0] p4_mode2;
  logic [7:0] p4oe_mode2;
  logic sc1_mode2;
  logic sc1oe_mode2;
  logic sc2_mode2;
  logic [15:0] address_mode2;
  logic [15:0] sp_mode2;
  logic waiting_mode2;
  logic [1:0] phase5;
  logic e5;
  logic [7:0] p3oe_mode5;
  logic sc1_mode5;
  logic sc1oe_mode5;
  logic sc2_mode5;
  logic [15:0] address_mode5;
  logic [15:0] sp_mode5;
  logic waiting_mode5;

  assign reset_n = past_valid;
  always @(posedge clk) past_valid <= 1'b1;

  /* verilator lint_off PINCONNECTEMPTY */
  mc6801_bus_wrapper #(.OPERATING_MODE(3'd2)) mode2 (
    .phase_clk_i(clk), .phase_reset_n_i(reset_n), .reset_n_i(reset_n),
    .clock_enable_i(clock_enable), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
    .program_data_i(8'hff), .program_address_o(), .program_read_o(),
    .port1_i(8'hff), .port1_o(), .port1_oe_o(), .port2_i(5'h1f),
    .port2_o(), .port2_oe_o(), .port3_i(8'hff), .port3_o(p3_mode2),
    .port3_oe_o(p3oe_mode2), .port4_i(8'hff), .port4_o(p4_mode2),
    .port4_oe_o(p4oe_mode2), .sc1_i(1'b1), .sc1_o(sc1_mode2),
    .sc1_oe_o(sc1oe_mode2), .sc2_o(sc2_mode2), .e_o(e2),
    .bus_phase_o(phase2), .opcode_fetch_o(), .retire_o(), .illegal_o(),
    .undefined_o(), .waiting_o(waiting_mode2), .interrupt_ack_o(),
    .operating_mode_o(), .debug_address_o(address_mode2), .debug_pc_o(),
    .debug_sp_o(sp_mode2),
    .debug_a_o(), .debug_b_o(), .debug_x_o(), .debug_ccr_o()
  );

  mc6801_bus_wrapper #(.OPERATING_MODE(3'd5)) mode5 (
    .phase_clk_i(clk), .phase_reset_n_i(reset_n), .reset_n_i(reset_n),
    .clock_enable_i(clock_enable), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
    .program_data_i(8'hff), .program_address_o(), .program_read_o(),
    .port1_i(8'hff), .port1_o(), .port1_oe_o(), .port2_i(5'h1f),
    .port2_o(), .port2_oe_o(), .port3_i(8'hff), .port3_o(),
    .port3_oe_o(p3oe_mode5), .port4_i(8'hff), .port4_o(),
    .port4_oe_o(), .sc1_i(1'b1), .sc1_o(sc1_mode5),
    .sc1_oe_o(sc1oe_mode5), .sc2_o(sc2_mode5), .e_o(e5),
    .bus_phase_o(phase5), .opcode_fetch_o(), .retire_o(), .illegal_o(),
    .undefined_o(), .waiting_o(waiting_mode5), .interrupt_ack_o(),
    .operating_mode_o(), .debug_address_o(address_mode5), .debug_pc_o(),
    .debug_sp_o(sp_mode5),
    .debug_a_o(), .debug_b_o(), .debug_x_o(), .debug_ccr_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always @* begin
    assert (phase2 == phase5);
    assert (e2 == (reset_n && phase2[1]));
    assert (e5 == (reset_n && phase5[1]));
    if (!reset_n) begin
      assert (p3oe_mode2 == 8'h00);
      assert (p3oe_mode5 == 8'h00);
      assert (sc1_mode2 && sc2_mode2);
      assert (sc1_mode5 && sc2_mode5);
    end else begin
      assert (sc1oe_mode2);
      assert (sc1oe_mode5);
      assert (sc1_mode2 == (phase2 == 2'd0));
      if (phase2 == 2'd0) begin
        if (waiting_mode2) assert (p3_mode2 == sp_mode2[7:0]);
        else assert (p3_mode2 == address_mode2[7:0]);
        assert (p3oe_mode2 == 8'hff);
        if (waiting_mode2) assert (p4_mode2 == sp_mode2[15:8]);
        else assert (p4_mode2 == address_mode2[15:8]);
        assert (p4oe_mode2 == 8'hff);
      end
      if (phase2 == 2'd1) assert (p3oe_mode2 == 8'h00);
      if (waiting_mode2 && (phase2 != 2'd0)) assert (p3oe_mode2 == 8'h00);
      if ((phase2 != 2'd0) && (p3oe_mode2 != 8'h00)) assert (e2);

      if (waiting_mode5) begin
        assert (sc1_mode5 == !((sp_mode5 >= 16'h0100) &&
                               (sp_mode5 <= 16'h01ff)));
        assert (p3oe_mode5 == 8'h00);
      end else begin
        assert (sc1_mode5 == !((address_mode5 >= 16'h0100) &&
                               (address_mode5 <= 16'h01ff)));
      end
      if (!e5) assert (p3oe_mode5 == 8'h00);
      if (p3oe_mode5 != 8'h00) assert (e5 && !sc2_mode5);
    end
  end

  always @(posedge clk) begin
    if (past_valid && $past(past_valid)) begin
      if ($past(clock_enable)) begin
        assert (phase2 == ($past(phase2) + 2'd1));
      end else begin
        assert (phase2 == $past(phase2));
      end
    end
  end
endmodule
