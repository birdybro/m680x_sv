// SPDX-License-Identifier: MIT
module hd6303r_bus_wrapper_formal;
  (* anyseq *) logic clk;
  (* anyseq *) logic clock_enable;
  (* anyseq *) logic standby_n;
  logic past_valid = 1'b0;
  logic reset_n;
  logic [1:0] phase1;
  logic [1:0] phase2;
  logic e1;
  logic e2;
  logic standby1;
  logic standby2;
  logic sleeping1;
  logic sleeping2;
  logic waiting1;
  logic waiting2;
  logic [7:0] p1_mode1;
  logic [7:0] p1oe_mode1;
  logic [7:0] p3_mode1;
  logic [7:0] p3oe_mode1;
  logic [7:0] p4_mode1;
  logic [7:0] p4oe_mode1;
  logic sc1oe_mode1;
  logic sc2_mode1;
  logic [15:0] address_mode1;
  logic [7:0] p3_mode2;
  logic [7:0] p3oe_mode2;
  logic [7:0] p4_mode2;
  logic [7:0] p4oe_mode2;
  logic sc1_mode2;
  logic sc1oe_mode2;
  logic sc2_mode2;
  logic [15:0] address_mode2;

  assign reset_n = past_valid;
  always @(posedge clk) past_valid <= 1'b1;

  /* verilator lint_off PINCONNECTEMPTY */
  hd6303r_bus_wrapper #(.OPERATING_MODE(3'd1)) mode1 (
    .phase_clk_i(clk), .phase_reset_n_i(reset_n), .reset_n_i(reset_n),
    .standby_n_i(standby_n), .clock_enable_i(clock_enable),
    .nmi_n_i(1'b1), .irq1_n_i(1'b1), .standby_power_ok_i(1'b1),
    .port1_i(8'hff), .port1_o(p1_mode1), .port1_oe_o(p1oe_mode1),
    .port2_i(5'h1f), .port2_o(), .port2_oe_o(), .port3_i(8'hff),
    .port3_o(p3_mode1), .port3_oe_o(p3oe_mode1),
    .port4_o(p4_mode1), .port4_oe_o(p4oe_mode1), .sc1_o(),
    .sc1_oe_o(sc1oe_mode1), .sc2_o(sc2_mode1), .e_o(e1),
    .bus_phase_o(phase1), .standby_active_o(standby1), .sci_tx_o(),
    .sci_clock_o(), .timer_irq_o(), .sci_irq_o(), .opcode_fetch_o(),
    .retire_o(), .illegal_o(), .undefined_o(), .waiting_o(waiting1),
    .sleeping_o(sleeping1),
    .interrupt_ack_o(), .debug_address_o(address_mode1), .debug_pc_o(),
    .debug_sp_o(), .debug_a_o(), .debug_b_o(), .debug_x_o(),
    .debug_ccr_o()
  );

  hd6303r_bus_wrapper #(.OPERATING_MODE(3'd2)) mode2 (
    .phase_clk_i(clk), .phase_reset_n_i(reset_n), .reset_n_i(reset_n),
    .standby_n_i(standby_n), .clock_enable_i(clock_enable),
    .nmi_n_i(1'b1), .irq1_n_i(1'b1), .standby_power_ok_i(1'b1),
    .port1_i(8'hff), .port1_o(), .port1_oe_o(), .port2_i(5'h1f),
    .port2_o(), .port2_oe_o(), .port3_i(8'hff), .port3_o(p3_mode2),
    .port3_oe_o(p3oe_mode2), .port4_o(p4_mode2),
    .port4_oe_o(p4oe_mode2), .sc1_o(sc1_mode2),
    .sc1_oe_o(sc1oe_mode2), .sc2_o(sc2_mode2), .e_o(e2),
    .bus_phase_o(phase2), .standby_active_o(standby2), .sci_tx_o(),
    .sci_clock_o(), .timer_irq_o(), .sci_irq_o(), .opcode_fetch_o(),
    .retire_o(), .illegal_o(), .undefined_o(), .waiting_o(waiting2),
    .sleeping_o(sleeping2),
    .interrupt_ack_o(), .debug_address_o(address_mode2), .debug_pc_o(),
    .debug_sp_o(), .debug_a_o(), .debug_b_o(), .debug_x_o(),
    .debug_ccr_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always @* begin
    assert (phase1 == phase2);
    assert (standby1 == standby2);
    assert (e1 == e2);
    assert (e1 == (reset_n && !standby1 && phase1[1]));
    if (!reset_n || standby1) begin
      assert (p1oe_mode1 == 8'h00);
      assert (p3oe_mode1 == 8'h00);
      assert (p4oe_mode1 == 8'h00);
      assert (p3oe_mode2 == 8'h00);
      assert (p4oe_mode2 == 8'h00);
      assert (sc2_mode1 && sc2_mode2);
    end else begin
      assert (!sc1oe_mode1);
      assert (p1oe_mode1 == 8'hff);
      assert (p4oe_mode1 == 8'hff);
      if (sleeping1 || waiting1) begin
        assert (sc2_mode1);
        assert (p1_mode1 == 8'hff);
        assert (p4_mode1 == 8'hff);
      end else begin
        assert (p1_mode1 == address_mode1[7:0]);
        assert (p4_mode1 == address_mode1[15:8]);
      end
      if (!e1) assert (p3oe_mode1 == 8'h00);
      if (p3oe_mode1 != 8'h00) assert (e1 && !sc2_mode1);

      assert (sc1oe_mode2);
      assert (sc1_mode2 == (phase2 == 2'd0));
      assert (p4oe_mode2 == 8'hff);
      if (sleeping2 || waiting2) begin
        assert (sc2_mode2);
        assert (p4_mode2 == 8'hff);
      end else begin
        assert (p4_mode2 == address_mode2[15:8]);
      end
      if (phase2 == 2'd0) begin
        assert (p3oe_mode2 == 8'hff);
        if (sleeping2 || waiting2) assert (p3_mode2 == 8'hff);
        else assert (p3_mode2 == address_mode2[7:0]);
      end
      if (phase2 == 2'd1) assert (p3oe_mode2 == 8'h00);
      if ((phase2 != 2'd0) && (p3oe_mode2 != 8'h00)) begin
        assert (e2 && !sc2_mode2);
      end
    end
  end

  always @(posedge clk) begin
    if (past_valid && $past(past_valid)) begin
      if ($past(clock_enable)) begin
        assert (phase1 == ($past(phase1) + 2'd1));
      end else begin
        assert (phase1 == $past(phase1));
      end
    end
  end
endmodule
