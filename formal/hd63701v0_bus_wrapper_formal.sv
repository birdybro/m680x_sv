// SPDX-License-Identifier: MIT
module hd63701v0_bus_wrapper_formal;
  (* anyseq *) logic clk;
  (* anyseq *) logic clock_enable;
  (* anyseq *) logic standby_n;
  (* anyseq *) logic device_reset_n;
  (* anyseq *) logic [7:0] port3_in;
  logic past_valid = 1'b0;
  logic expected_reset_active = 1'b1;
  logic expected_reset_state_n;
  logic phase_reset_n;
  logic reset_n;
  logic [1:0] phase;
  logic e;
  logic standby;
  logic sleeping;
  logic waiting;
  logic [7:0] port1_oe;
  logic [4:0] port2_oe;
  logic [7:0] port3;
  logic [7:0] port3_oe;
  logic [7:0] port4;
  logic [7:0] port4_oe;
  logic sc1;
  logic sc1_oe;
  logic sc2;
  logic [15:0] address;
  logic [1:0] phase7;
  logic standby7;
  logic sc1_oe7;
  logic sc2_7;

  assign phase_reset_n = past_valid;
  assign reset_n = past_valid && device_reset_n;
  assign expected_reset_state_n = phase_reset_n && reset_n && standby_n;

  always @(posedge clk) past_valid <= 1'b1;

  always @(posedge clk or negedge expected_reset_state_n) begin
    if (!expected_reset_state_n) begin
      expected_reset_active <= 1'b1;
    end else if (clock_enable && (phase == 2'd3)) begin
      expected_reset_active <= 1'b0;
    end
  end

  /* verilator lint_off PINCONNECTEMPTY */
  hd63701v0_bus_wrapper #(.OPERATING_MODE(3'd6)) dut (
    .phase_clk_i(clk), .phase_reset_n_i(phase_reset_n), .reset_n_i(reset_n),
    .standby_n_i(standby_n), .clock_enable_i(clock_enable), .nmi_n_i(1'b1),
    .irq1_n_i(1'b1), .standby_power_ok_i(1'b1), .program_data_i(8'hff),
    .program_address_o(), .program_read_o(), .port1_i(8'hff), .port1_o(),
    .port1_oe_o(port1_oe), .port2_i(5'h1f), .port2_o(),
    .port2_oe_o(port2_oe), .port3_i(port3_in), .port3_o(port3),
    .port3_oe_o(port3_oe), .port4_i(8'hff), .port4_o(port4),
    .port4_oe_o(port4_oe), .sc1_i(1'b1), .sc1_o(sc1),
    .sc1_oe_o(sc1_oe), .sc2_o(sc2), .e_o(e), .bus_phase_o(phase),
    .standby_active_o(standby), .sci_tx_o(), .sci_clock_o(),
    .timer_irq_o(), .sci_irq_o(), .opcode_fetch_o(), .retire_o(),
    .illegal_o(), .undefined_o(), .waiting_o(waiting),
    .sleeping_o(sleeping), .interrupt_ack_o(), .debug_address_o(address),
    .debug_pc_o(), .debug_sp_o(), .debug_a_o(), .debug_b_o(), .debug_x_o(),
    .debug_ccr_o()
  );

  hd63701v0_bus_wrapper #(.OPERATING_MODE(3'd7)) mode7 (
    .phase_clk_i(clk), .phase_reset_n_i(phase_reset_n), .reset_n_i(reset_n),
    .standby_n_i(standby_n), .clock_enable_i(clock_enable), .nmi_n_i(1'b1),
    .irq1_n_i(1'b1), .standby_power_ok_i(1'b1), .program_data_i(8'hff),
    .program_address_o(), .program_read_o(), .port1_i(8'hff), .port1_o(),
    .port1_oe_o(), .port2_i(5'h1f), .port2_o(), .port2_oe_o(),
    .port3_i(port3_in), .port3_o(), .port3_oe_o(), .port4_i(8'hff),
    .port4_o(), .port4_oe_o(), .sc1_i(1'b1), .sc1_o(),
    .sc1_oe_o(sc1_oe7), .sc2_o(sc2_7), .e_o(), .bus_phase_o(phase7),
    .standby_active_o(standby7), .sci_tx_o(), .sci_clock_o(),
    .timer_irq_o(), .sci_irq_o(), .opcode_fetch_o(), .retire_o(),
    .illegal_o(), .undefined_o(), .waiting_o(), .sleeping_o(),
    .interrupt_ack_o(), .debug_address_o(), .debug_pc_o(), .debug_sp_o(),
    .debug_a_o(), .debug_b_o(), .debug_x_o(), .debug_ccr_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always @* begin
    assert (phase7 == phase);
    assert (standby7 == standby);
    assert (e == (phase_reset_n && standby_n && phase[1]));
    assert (standby == !standby_n);
    if (!phase_reset_n || !reset_n || !standby_n || expected_reset_active) begin
      assert (port1_oe == 8'h00);
      assert (port2_oe == 5'h00);
      assert (port3_oe == 8'h00);
      assert (port4_oe == 8'h00);
      assert (sc1);
      assert (sc2);
      assert (sc2_7);
      if (!phase_reset_n) assert (!sc1_oe);
      else assert (sc1_oe == !phase[1]);
    end else begin
      assert (sc1_oe);
      assert (!sc1_oe7);
      assert (sc1 == (phase == 2'd0));
      if (sleeping || waiting) begin
        assert (sc2);
        assert (port4 == 8'hff);
      end else begin
        assert (port4 == address[15:8]);
      end
      if (phase == 2'd0) begin
        assert (port3_oe == 8'hff);
        if (sleeping || waiting) assert (port3 == 8'hff);
        else assert (port3 == address[7:0]);
      end
      if (phase == 2'd1) assert (port3_oe == 8'h00);
      if ((phase != 2'd0) && (port3_oe != 8'h00)) begin
        assert (e && !sc2 && !sleeping && !waiting);
      end
    end
  end

  always @(posedge clk) begin
    if (past_valid && $past(past_valid)) begin
      if (!$past(phase_reset_n) || !$past(standby_n)) begin
        assert (phase == 2'd0);
      end else if ($past(clock_enable)) begin
        assert (phase == ($past(phase) + 2'd1));
      end else begin
        assert (phase == $past(phase));
      end
      // HD63701V0 figure 3-11-5 permits OS3 changes only at positive E edges.
      if ($past(phase_reset_n) && phase_reset_n &&
          $past(reset_n) && reset_n && !$past(standby7) && !standby7 &&
          (!$past(clock_enable) || ($past(phase7) != 2'd1))) begin
        assert (sc2_7 == $past(sc2_7));
      end
    end
  end
endmodule
