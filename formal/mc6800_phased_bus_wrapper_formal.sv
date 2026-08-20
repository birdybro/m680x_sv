// SPDX-License-Identifier: MIT
module mc6800_phased_bus_wrapper_formal;
  (* anyseq *) logic clk;
  (* anyseq *) logic clock_enable;
  (* anyseq *) logic irq_n;
  (* anyseq *) logic nmi_n;
  (* anyseq *) logic halt_n;
  (* anyseq *) logic tsc;
  (* anyseq *) logic dbe;
  (* anyseq *) logic [7:0] data_in;
  logic past_valid = 1'b0;
  logic reset_n;
  logic phi1;
  logic phi2;
  logic [1:0] phase;
  logic address_oe;
  logic data_oe;
  logic read_not_write;
  logic read_not_write_oe;
  logic vma;
  logic ba;

  assign reset_n = past_valid;
  always @(posedge clk) past_valid <= 1'b1;

  /* verilator lint_off PINCONNECTEMPTY */
  mc6800_phased_bus_wrapper dut (
    .phase_clk_i(clk), .phase_reset_n_i(reset_n), .reset_n_i(reset_n),
    .clock_enable_i(clock_enable), .irq_n_i(irq_n), .nmi_n_i(nmi_n),
    .halt_n_i(halt_n), .tsc_i(tsc), .dbe_i(dbe), .data_i(data_in),
    .phi1_o(phi1), .phi2_o(phi2), .bus_phase_o(phase), .address_o(),
    .address_oe_o(address_oe), .data_o(), .data_oe_o(data_oe),
    .read_not_write_o(read_not_write),
    .read_not_write_oe_o(read_not_write_oe), .vma_o(vma), .ba_o(ba),
    .opcode_fetch_o(), .retire_o(), .illegal_o(), .undefined_o(),
    .waiting_o(), .interrupt_ack_o(), .interrupt_vector_o(), .halted_o(),
    .debug_pc_o(), .debug_sp_o(), .debug_a_o(), .debug_b_o(), .debug_x_o(),
    .debug_ccr_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always @* begin
    assert (!(phi1 && phi2));
    if (!reset_n) begin
      assert (!phi1 && !phi2);
    end else begin
      assert (phi1 == (phase == 2'd0));
      assert (phi2 == (phase == 2'd2));
    end
    if (tsc) begin
      assert (!address_oe && !read_not_write_oe && !vma && !ba && !data_oe);
    end
    if (ba) begin
      assert (!address_oe && !read_not_write_oe && !vma && !data_oe);
    end
    if (data_oe) assert (dbe && vma && !read_not_write);
  end

  always @(posedge clk) begin
    if (past_valid && $past(past_valid)) begin
      if ($past(clock_enable) && !$past(tsc)) begin
        assert (phase == ($past(phase) + 2'd1));
      end else begin
        assert (phase == $past(phase));
      end
    end
  end
endmodule
