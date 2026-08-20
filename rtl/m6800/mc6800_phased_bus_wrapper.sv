// SPDX-License-Identifier: MIT
// Four-subphase FPGA integration wrapper for the MC6800 digital bus.
//
// Motorola M6800 Microcomputer System Design Data figures 1-3 and 12-16
// establish non-overlapping phi1/phi2 ordering, processor-control sampling at
// trailing phi1, and phi2 data transfer. The historical MPU receives phi1 and
// phi2 as clock inputs; phi1_o/phi2_o here are deterministic digital phase
// projections for FPGA integration, not an electrical clock-pad model.
module mc6800_phased_bus_wrapper (
  input  logic        phase_clk_i,
  input  logic        phase_reset_n_i,
  input  logic        reset_n_i,
  input  logic        clock_enable_i,
  input  logic        irq_n_i,
  input  logic        nmi_n_i,
  input  logic        halt_n_i,
  input  logic        tsc_i,
  input  logic        dbe_i,
  input  logic [7:0]  data_i,
  output logic        phi1_o,
  output logic        phi2_o,
  output logic [1:0]  bus_phase_o,
  output logic [15:0] address_o,
  output logic        address_oe_o,
  output logic [7:0]  data_o,
  output logic        data_oe_o,
  output logic        read_not_write_o,
  output logic        read_not_write_oe_o,
  output logic        vma_o,
  output logic        ba_o,
  output logic        opcode_fetch_o,
  output logic        retire_o,
  output logic        illegal_o,
  output logic        undefined_o,
  output logic        waiting_o,
  output logic        interrupt_ack_o,
  output logic [1:0]  interrupt_vector_o,
  output logic        halted_o,
  output logic [15:0] debug_pc_o,
  output logic [15:0] debug_sp_o,
  output logic [7:0]  debug_a_o,
  output logic [7:0]  debug_b_o,
  output logic [15:0] debug_x_o,
  output logic [5:0]  debug_ccr_o
);
  localparam logic [1:0] PHASE_PHI1 = 2'd0;
  localparam logic [1:0] PHASE_PHI2 = 2'd2;
  localparam logic [1:0] PHASE_GAP_21 = 2'd3;

  logic [1:0] bus_phase;
  logic sampled_irq_n;
  logic sampled_nmi_n;
  logic sampled_halt_n;
  logic normalized_cycle_enable;

  assign phi1_o = phase_reset_n_i && (bus_phase == PHASE_PHI1);
  assign phi2_o = phase_reset_n_i && (bus_phase == PHASE_PHI2);
  assign bus_phase_o = bus_phase;
  assign normalized_cycle_enable = clock_enable_i && !tsc_i &&
    (bus_phase == PHASE_GAP_21);

  always_ff @(posedge phase_clk_i or negedge phase_reset_n_i) begin
    if (!phase_reset_n_i) begin
      bus_phase <= PHASE_PHI1;
      sampled_irq_n <= 1'b1;
      sampled_nmi_n <= 1'b1;
      sampled_halt_n <= 1'b1;
    end else begin
      // Figures 12-15 specify processor-control setup relative to trailing
      // phi1. Hold the sampled values through phi2 and the cycle boundary.
      if (clock_enable_i && !tsc_i && (bus_phase == PHASE_PHI1)) begin
        sampled_irq_n <= irq_n_i;
        sampled_nmi_n <= nmi_n_i;
        sampled_halt_n <= halt_n_i;
      end
      // Figure 16 requires TSC use with phi1 high and phi2 low. A compliant
      // assertion therefore freezes this state without generating a clock.
      if (clock_enable_i && !tsc_i) bus_phase <= bus_phase + 2'd1;
    end
  end

  mc6800_bus_wrapper device (
    .clk_i(phase_clk_i),
    .reset_n_i(reset_n_i),
    .clock_enable_i(normalized_cycle_enable),
    .irq_n_i(sampled_irq_n),
    .nmi_n_i(sampled_nmi_n),
    .halt_n_i(sampled_halt_n),
    .tsc_i(tsc_i),
    .dbe_i(dbe_i),
    .data_i(data_i),
    .address_o(address_o),
    .address_oe_o(address_oe_o),
    .data_o(data_o),
    .data_oe_o(data_oe_o),
    .read_not_write_o(read_not_write_o),
    .read_not_write_oe_o(read_not_write_oe_o),
    .vma_o(vma_o),
    .ba_o(ba_o),
    .opcode_fetch_o(opcode_fetch_o),
    .retire_o(retire_o),
    .illegal_o(illegal_o),
    .undefined_o(undefined_o),
    .waiting_o(waiting_o),
    .interrupt_ack_o(interrupt_ack_o),
    .interrupt_vector_o(interrupt_vector_o),
    .halted_o(halted_o),
    .debug_pc_o(debug_pc_o),
    .debug_sp_o(debug_sp_o),
    .debug_a_o(debug_a_o),
    .debug_b_o(debug_b_o),
    .debug_x_o(debug_x_o),
    .debug_ccr_o(debug_ccr_o)
  );
endmodule
