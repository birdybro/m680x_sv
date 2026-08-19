// SPDX-License-Identifier: MIT
// MC6800 device-oriented bus-control wrapper.
//
// Signal behavior follows Motorola M6800 Microcomputer System Design Data,
// "Microprocessor Interface Lines" and "Processor Controls" (printed pages
// 4 and 16-20). clk_i advances one complete normalized processor cycle; pin-
// level phi1/phi2 generation and electrical timing remain integration concerns.
module mc6800_bus_wrapper (
  input  logic        clk_i,
  input  logic        reset_n_i,
  input  logic        clock_enable_i,
  input  logic        irq_n_i,
  input  logic        nmi_n_i,
  input  logic        halt_n_i,
  input  logic        tsc_i,
  input  logic        dbe_i,
  input  logic [7:0]  data_i,
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
  logic [15:0] core_address;
  logic [7:0] core_data_out;
  logic core_write;
  logic core_bus_valid;
  logic core_waiting;
  logic core_retire;
  logic core_clock_enable;
  logic core_irq_n;
  logic core_nmi_n;
  logic halted;
  logic halt_release;
  logic halt_release_started;
  logic irq_held;
  logic nmi_held;
  logic nmi_previous;
  logic halt_entry;

  assign halt_entry = !halted && !halt_n_i && core_retire &&
    !(halt_release && !halt_release_started);
  assign core_clock_enable = clock_enable_i && !halted && !tsc_i && !halt_entry;
  assign core_irq_n = irq_held ? 1'b0 : irq_n_i;
  assign core_nmi_n = nmi_held ? 1'b0 : nmi_n_i;

  always_ff @(posedge clk_i or negedge reset_n_i) begin
    if (!reset_n_i) begin
      halted <= 1'b0;
      halt_release <= 1'b0;
      halt_release_started <= 1'b0;
      irq_held <= 1'b0;
      nmi_held <= 1'b0;
      nmi_previous <= 1'b1;
    end else begin
      nmi_previous <= nmi_n_i;

      if (halt_entry) begin
        halted <= 1'b1;
        halt_release <= 1'b0;
        halt_release_started <= 1'b0;
      end else if (halted && halt_n_i) begin
        halted <= 1'b0;
        halt_release <= 1'b1;
        halt_release_started <= 1'b0;
      end

      if (halt_release && !halt_release_started && core_clock_enable) begin
        halt_release_started <= 1'b1;
      end else if (halt_release && halt_release_started && core_retire && halt_n_i) begin
        halt_release <= 1'b0;
        halt_release_started <= 1'b0;
      end

      // Keep a halted request asserted until the core acknowledges that exact
      // interrupt class. In particular, a pulsed IRQ must survive release while
      // the I mask is still set and remain pending until software clears it.
      if (interrupt_ack_o && (interrupt_vector_o == 2'b01)) irq_held <= 1'b0;
      if (interrupt_ack_o && (interrupt_vector_o == 2'b10)) nmi_held <= 1'b0;

      // A new request on the acknowledgement boundary wins over the clear.
      if ((halted || halt_entry) && !irq_n_i) irq_held <= 1'b1;
      if (!core_clock_enable && nmi_previous && !nmi_n_i) nmi_held <= 1'b1;
    end
  end

  always_comb begin
    ba_o = reset_n_i && !tsc_i && (halted || core_waiting);
    address_o = core_address;
    data_o = core_data_out;
    read_not_write_o = !core_write;
    address_oe_o = !tsc_i && !ba_o;
    read_not_write_oe_o = !tsc_i && !ba_o;
    vma_o = reset_n_i && !tsc_i && !ba_o && core_bus_valid;
    data_oe_o = dbe_i && vma_o && core_write;
  end

  // Base M6800 has no sleep state, and the wrapper does not expose decode-only
  // debug fields. Empty connections are intentional at this boundary.
  /* verilator lint_off PINCONNECTEMPTY */
  m6800_core #(.ARCHITECTURE(2'd0)) cpu (
    .clk_i(clk_i),
    .reset_n_i(reset_n_i),
    .clock_enable_i(core_clock_enable),
    .bus_ready_i(1'b1),
    .irq_n_i(core_irq_n),
    .nmi_n_i(core_nmi_n),
    .instruction_address_error_i(1'b0),
    .data_i(data_i),
    .address_o(core_address),
    .data_o(core_data_out),
    .write_o(core_write),
    .bus_valid_o(core_bus_valid),
    .opcode_fetch_o(opcode_fetch_o),
    .retire_o(core_retire),
    .illegal_o(illegal_o),
    .undefined_o(undefined_o),
    .waiting_o(core_waiting),
    .sleeping_o(),
    .interrupt_ack_o(interrupt_ack_o),
    .interrupt_vector_o(interrupt_vector_o),
    .debug_a_o(debug_a_o),
    .debug_b_o(debug_b_o),
    .debug_x_o(debug_x_o),
    .debug_sp_o(debug_sp_o),
    .debug_pc_o(debug_pc_o),
    .debug_ccr_o(debug_ccr_o),
    .debug_opcode_o(),
    .debug_instruction_cycles_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  assign retire_o = core_retire;
  assign waiting_o = core_waiting;
  assign halted_o = halted;
endmodule
