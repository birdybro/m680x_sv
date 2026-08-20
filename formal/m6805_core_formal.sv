// SPDX-License-Identifier: MIT
module m6805_core_formal #(
  parameter logic HITACHI_PROFILE = 1'b0
);
  (* anyseq *) logic clk;
  logic reset_n;
  logic past_valid = 1'b0;
  logic [3:0] accepted_reset_cycles;
  (* anyseq *) logic clock_enable;
  (* anyseq *) logic bus_ready;
  (* anyseq *) logic irq_n;
  (* anyseq *) logic [7:0] data_in;
  logic [15:0] address;
  logic [7:0] data_out;
  logic write_enable;
  logic bus_valid;
  logic opcode_fetch;
  logic retire;
  logic illegal;
  logic undefined_value;
  logic waiting_state;
  logic stopped_state;
  logic interrupt_ack;
  logic [7:0] debug_a;
  logic [7:0] debug_x;
  logic [15:0] debug_sp;
  logic [15:0] debug_pc;
  logic [4:0] debug_ccr;
  logic [7:0] debug_opcode;
  logic [3:0] debug_cycles;

  assign reset_n = past_valid;
  always @(posedge clk) past_valid <= 1'b1;

  always @(posedge clk) begin
    if (!reset_n) accepted_reset_cycles <= 4'd0;
    else if (clock_enable && bus_ready &&
             (accepted_reset_cycles < (HITACHI_PROFILE ? 4'd2 : 4'd8))) begin
      accepted_reset_cycles <= accepted_reset_cycles + 4'd1;
    end
  end

  m6805_core #(.HITACHI_PROFILE(HITACHI_PROFILE)) dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(clock_enable),
    .bus_ready_i(bus_ready), .irq_n_i(irq_n), .interrupt_pin_n_i(irq_n),
    .irq_vector_i(16'hfffa), .data_i(data_in),
    .address_o(address), .data_o(data_out), .write_o(write_enable),
    .bus_valid_o(bus_valid), .opcode_fetch_o(opcode_fetch), .retire_o(retire),
    .illegal_o(illegal), .undefined_o(undefined_value), .waiting_o(waiting_state),
    .stopped_o(stopped_state), .interrupt_ack_o(interrupt_ack),
    .debug_a_o(debug_a), .debug_x_o(debug_x), .debug_sp_o(debug_sp),
    .debug_pc_o(debug_pc), .debug_ccr_o(debug_ccr), .debug_opcode_o(debug_opcode),
    .debug_instruction_cycles_o(debug_cycles)
  );

  always @* begin
    assert (!write_enable || bus_valid);
    assert (!opcode_fetch || (bus_valid && !write_enable));
    assert (!(waiting_state && stopped_state));
    if (past_valid) assert ((debug_sp & 16'hffe0) == 16'h0060);
    if (past_valid &&
        (accepted_reset_cycles < (HITACHI_PROFILE ? 4'd2 : 4'd8))) begin
      assert (bus_valid && !write_enable && !opcode_fetch);
      if (HITACHI_PROFILE && (accepted_reset_cycles == 4'd0)) begin
        assert (address == 16'hfffe);
      end else if (HITACHI_PROFILE) begin
        assert (address == 16'hffff);
      end else if (accepted_reset_cycles < 4'd6) begin
        assert (address == 16'hfffe);
      end else if (accepted_reset_cycles == 4'd6) begin
        assert (address == 16'hffff);
      end else begin
        assert (address == 16'h0000);
      end
    end
  end

  always @(posedge clk) begin
    if (past_valid && $past(past_valid) &&
        (!$past(clock_enable) || ($past(bus_valid) && !$past(bus_ready)))) begin
      assert ({debug_a, debug_x, debug_sp, debug_pc, debug_ccr,
               debug_opcode, debug_cycles} ==
              $past({debug_a, debug_x, debug_sp, debug_pc, debug_ccr,
                     debug_opcode, debug_cycles}));
      assert ({address, data_out, write_enable, bus_valid, opcode_fetch, retire,
               illegal, undefined_value, waiting_state, stopped_state,
               interrupt_ack} ==
              $past({address, data_out, write_enable, bus_valid, opcode_fetch, retire,
                     illegal, undefined_value, waiting_state, stopped_state,
                     interrupt_ack}));
    end
  end
endmodule
