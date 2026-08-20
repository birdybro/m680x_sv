// SPDX-License-Identifier: MIT
// MC68705P5 digital MCU integration.
//
// Register and memory locations follow Motorola ADI-964-R1, figures 4, 7,
// 13, 15, and 16 and the Timer Control Register description.  User EPROM,
// bootstrap ROM, and vectors are supplied by a separate FPGA firmware memory
// through program_data_i; this module owns their documented address decode.
module mc68705p5_mcu #(
  parameter logic [7:0] MASK_OPTION = 8'h00
) (
  input  logic        clk_i,
  input  logic        reset_n_i,
  input  logic        clock_enable_i,
  input  logic        int_n_i,
  input  logic        timer_i,
  input  logic [7:0]  port_a_i,
  input  logic [7:0]  port_b_i,
  input  logic [3:0]  port_c_i,
  output logic [7:0]  port_a_o,
  output logic [7:0]  port_b_o,
  output logic [3:0]  port_c_o,
  output logic [7:0]  port_a_oe_o,
  output logic [7:0]  port_b_oe_o,
  output logic [3:0]  port_c_oe_o,
  output logic [10:0] program_address_o,
  output logic        program_read_o,
  input  logic [7:0]  program_data_i,
  input  logic        vpp_present_i,
  input  logic        bootstrap_voltage_i,
  output logic        bootstrap_mode_o,
  output logic        eprom_latch_enable_o,
  output logic        eprom_program_enable_o,
  output logic [10:0] eprom_program_address_o,
  output logic [7:0]  eprom_program_data_o,
  output logic        timer_irq_o,
  output logic        external_irq_o,
  output logic        opcode_fetch_o,
  output logic        retire_o,
  output logic        illegal_o,
  output logic        undefined_o,
  output logic        waiting_o,
  output logic        stopped_o,
  output logic        interrupt_ack_o,
  output logic [15:0] debug_address_o,
  output logic [15:0] debug_pc_o,
  output logic [15:0] debug_sp_o,
  output logic [7:0]  debug_a_o,
  output logic [7:0]  debug_x_o,
  output logic [4:0]  debug_ccr_o,
  output logic [7:0]  debug_opcode_o,
  output logic [3:0]  debug_instruction_cycles_o,
  output logic [7:0]  debug_timer_o,
  output logic [7:0]  debug_timer_control_o,
  output logic [7:0]  debug_program_control_o
);
  localparam logic [15:0] TIMER_VECTOR = 16'h07f8;
  localparam logic [15:0] EXTERNAL_VECTOR = 16'h07fa;
  localparam logic [15:0] SWI_VECTOR = 16'h07fc;
  localparam logic [15:0] RESET_VECTOR = 16'h07fe;

  logic [7:0] ram [0:111];
  logic [7:0] port_a_latch;
  logic [7:0] port_b_latch;
  logic [3:0] port_c_latch;
  logic [7:0] port_a_ddr;
  logic [7:0] port_b_ddr;
  logic [3:0] port_c_ddr;
  logic [7:0] timer_data;
  logic [7:0] timer_control;
  logic [6:0] timer_prescaler;
  logic timer_pin_previous;
  logic int_pin_previous;
  logic external_request;
  logic pcr_latch_enable;
  logic pcr_program_enable;
  logic [10:0] eprom_address_latch;
  logic [7:0] eprom_data_latch;
  logic timer_input_event;
  logic timer_counter_event;
  logic timer_tin;
  logic timer_tie;
  logic [2:0] timer_prescale_select;
  logic [6:0] timer_prescale_mask;
  logic [7:0] core_data_in;
  logic [7:0] core_data_out;
  // The generic core computes sixteen-bit effective addresses; the physical
  // MC68705P5 device boundary exposes and decodes only A10:A0.
  /* verilator lint_off UNUSEDSIGNAL */
  logic [15:0] core_address;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [15:0] core_irq_vector;
  logic [15:0] core_debug_pc;
  logic core_write;
  logic core_bus_valid;
  logic irq_n;
  logic bootstrap_select;
  logic bootstrap_active;
  logic bootstrap_effective;
  logic [1:0] reset_vector_phase;
  logic [10:0] selected_program_address;

  function automatic logic program_storage_address(input logic [10:0] address_value);
    program_storage_address =
      ((address_value >= 11'h080) && (address_value <= 11'h783)) ||
      (address_value >= 11'h785);
  endfunction

  function automatic logic bootstrap_rom_address(input logic [10:0] address_value);
    bootstrap_rom_address = (address_value >= 11'h785) &&
                            (address_value <= 11'h7f7);
  endfunction

  function automatic logic eprom_address(input logic [10:0] address_value);
    eprom_address = ((address_value >= 11'h080) && (address_value <= 11'h784)) ||
                    (address_value >= 11'h7f8);
  endfunction

  assign bootstrap_select = bootstrap_voltage_i && !MASK_OPTION[3];
  assign bootstrap_effective = (reset_vector_phase == 2'd0) ?
                               bootstrap_select : bootstrap_active;

  always_comb begin
    selected_program_address = core_address[10:0];
    if (bootstrap_effective && (reset_vector_phase == 2'd0) &&
        (core_address[10:0] == RESET_VECTOR[10:0])) begin
      selected_program_address = 11'h7f6;
    end else if (bootstrap_effective && (reset_vector_phase == 2'd1) &&
                 (core_address[10:0] == (RESET_VECTOR[10:0] + 11'h001))) begin
      selected_program_address = 11'h7f7;
    end
  end

  always_comb begin
    if (MASK_OPTION[6]) begin
      timer_tin = MASK_OPTION[5];
      timer_tie = 1'b1;
      timer_prescale_select = MASK_OPTION[2:0];
    end else begin
      timer_tin = timer_control[5];
      timer_tie = timer_control[4];
      timer_prescale_select = timer_control[2:0];
    end

    case ({timer_tin, timer_tie})
      2'b00: timer_input_event = 1'b1;
      2'b01: timer_input_event = timer_i;
      2'b10: timer_input_event = 1'b0;
      default: timer_input_event = timer_i && !timer_pin_previous;
    endcase

    case (timer_prescale_select)
      3'd0: timer_prescale_mask = 7'h00;
      3'd1: timer_prescale_mask = 7'h01;
      3'd2: timer_prescale_mask = 7'h03;
      3'd3: timer_prescale_mask = 7'h07;
      3'd4: timer_prescale_mask = 7'h0f;
      3'd5: timer_prescale_mask = 7'h1f;
      3'd6: timer_prescale_mask = 7'h3f;
      default: timer_prescale_mask = 7'h7f;
    endcase
    timer_counter_event = timer_input_event &&
                          ((timer_prescaler & timer_prescale_mask) == timer_prescale_mask);
  end

  always_comb begin
    core_data_in = 8'hff;
    case (core_address[10:0])
      11'h000: core_data_in = (port_a_latch & port_a_ddr) | (port_a_i & ~port_a_ddr);
      11'h001: core_data_in = (port_b_latch & port_b_ddr) | (port_b_i & ~port_b_ddr);
      11'h002: core_data_in = {4'hf, (port_c_latch & port_c_ddr) | (port_c_i & ~port_c_ddr)};
      11'h004, 11'h005, 11'h006: core_data_in = 8'hff;
      11'h008: core_data_in = timer_data;
      11'h009: begin
        if (MASK_OPTION[6]) core_data_in = {timer_control[7:6], 6'h3f};
        else core_data_in = timer_control;
      end
      11'h00b: core_data_in = {5'h1f, !vpp_present_i, pcr_program_enable,
                              pcr_latch_enable};
      11'h784: core_data_in = MASK_OPTION;
      default: begin
        if ((core_address[10:0] >= 11'h010) && (core_address[10:0] <= 11'h07f)) begin
          core_data_in = ram[core_address[6:0] - 7'h10];
        end else if (program_storage_address(selected_program_address)) begin
          if (bootstrap_rom_address(selected_program_address) ||
              !vpp_present_i || pcr_latch_enable) begin
            core_data_in = program_data_i;
          end
        end
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge reset_n_i) begin
    if (!reset_n_i) begin
      port_a_latch <= 8'h00;
      port_b_latch <= 8'h00;
      port_c_latch <= 4'h0;
      port_a_ddr <= 8'h00;
      port_b_ddr <= 8'h00;
      port_c_ddr <= 4'h0;
      timer_data <= 8'hff;
      timer_control <= {1'b0, 1'b1, MASK_OPTION[5], MASK_OPTION[4],
                        1'b0, MASK_OPTION[2:0]};
      timer_prescaler <= 7'h7f;
      timer_pin_previous <= 1'b0;
      int_pin_previous <= 1'b1;
      external_request <= 1'b0;
      pcr_latch_enable <= 1'b1;
      pcr_program_enable <= 1'b1;
      eprom_address_latch <= 11'h000;
      eprom_data_latch <= 8'h00;
      bootstrap_active <= 1'b0;
      reset_vector_phase <= 2'd0;
    end else if (clock_enable_i) begin
      timer_pin_previous <= timer_i;
      int_pin_previous <= int_n_i;

      if ((reset_vector_phase == 2'd0) && core_bus_valid && !core_write &&
          (core_address[10:0] == RESET_VECTOR[10:0])) begin
        bootstrap_active <= bootstrap_select;
        reset_vector_phase <= 2'd1;
      end else if ((reset_vector_phase == 2'd1) && core_bus_valid && !core_write &&
                   (core_address[10:0] == (RESET_VECTOR[10:0] + 11'h001))) begin
        reset_vector_phase <= 2'd2;
      end

      if (int_pin_previous && !int_n_i) external_request <= 1'b1;
      if (core_bus_valid && !core_write && (core_address[10:0] == 11'h7fa)) begin
        external_request <= 1'b0;
      end

      if (timer_input_event) begin
        timer_prescaler <= timer_prescaler + 7'h01;
        if (timer_counter_event) begin
          timer_data <= timer_data - 8'h01;
          if (timer_data == 8'h01) timer_control[7] <= 1'b1;
        end
      end

      if (core_bus_valid && core_write) begin
        case (core_address[10:0])
          11'h000: port_a_latch <= core_data_out;
          11'h001: port_b_latch <= core_data_out;
          11'h002: port_c_latch <= core_data_out[3:0];
          11'h004: port_a_ddr <= core_data_out;
          11'h005: port_b_ddr <= core_data_out;
          11'h006: port_c_ddr <= core_data_out[3:0];
          11'h008: timer_data <= core_data_out;
          11'h009: begin
            if (MASK_OPTION[6]) begin
              timer_control[7:6] <= core_data_out[7:6];
            end else begin
              timer_control[7:4] <= core_data_out[7:4];
              timer_control[3] <= 1'b0;
              timer_control[2:0] <= core_data_out[2:0];
              if (core_data_out[3]) timer_prescaler <= 7'h7f;
            end
          end
          11'h00b: begin
            pcr_latch_enable <= core_data_out[0];
            if (core_data_out[0]) pcr_program_enable <= 1'b1;
            else pcr_program_enable <= core_data_out[1];
          end
          default: ;
        endcase
        if (eprom_address(core_address[10:0]) && vpp_present_i &&
            !pcr_latch_enable && pcr_program_enable) begin
          eprom_address_latch <= core_address[10:0];
          eprom_data_latch <= core_data_out;
        end
      end
    end
  end

  // A separate, reset-free write process preserves FPGA RAM inference.  The
  // manufacturer does not define RAM contents after reset.
  always_ff @(posedge clk_i) begin
    if (clock_enable_i && core_bus_valid && core_write &&
        (core_address[10:0] >= 11'h010) && (core_address[10:0] <= 11'h07f)) begin
      ram[core_address[6:0] - 7'h10] <= core_data_out;
    end
  end

  assign core_irq_vector = external_request ? EXTERNAL_VECTOR : TIMER_VECTOR;
  assign irq_n = ~(external_request || (timer_control[7] && !timer_control[6]));

  m6805_core #(
    .PC_MASK(16'h07ff),
    .STACK_BASE(16'h0060),
    .STACK_MASK(16'h001f),
    .STACK_TOP(16'h007f),
    .SWI_VECTOR(SWI_VECTOR),
    .RESET_VECTOR(RESET_VECTOR)
  ) cpu (
    .clk_i(clk_i),
    .reset_n_i(reset_n_i),
    .clock_enable_i(clock_enable_i),
    .bus_ready_i(1'b1),
    .irq_n_i(irq_n),
    .interrupt_pin_n_i(int_n_i),
    .irq_vector_i(core_irq_vector),
    .data_i(core_data_in),
    .address_o(core_address),
    .data_o(core_data_out),
    .write_o(core_write),
    .bus_valid_o(core_bus_valid),
    .opcode_fetch_o(opcode_fetch_o),
    .retire_o(retire_o),
    .illegal_o(illegal_o),
    .undefined_o(undefined_o),
    .waiting_o(waiting_o),
    .stopped_o(stopped_o),
    .interrupt_ack_o(interrupt_ack_o),
    .debug_a_o(debug_a_o),
    .debug_x_o(debug_x_o),
    .debug_sp_o(debug_sp_o),
    .debug_pc_o(core_debug_pc),
    .debug_ccr_o(debug_ccr_o),
    .debug_opcode_o(debug_opcode_o),
    .debug_instruction_cycles_o(debug_instruction_cycles_o)
  );

  assign port_a_o = port_a_latch;
  assign port_b_o = port_b_latch;
  assign port_c_o = port_c_latch;
  assign port_a_oe_o = port_a_ddr;
  assign port_b_oe_o = port_b_ddr;
  assign port_c_oe_o = port_c_ddr;
  assign program_address_o = selected_program_address;
  assign program_read_o = core_bus_valid && !core_write &&
                          program_storage_address(selected_program_address) &&
                          (bootstrap_rom_address(selected_program_address) ||
                           !vpp_present_i || pcr_latch_enable);
  assign bootstrap_mode_o = bootstrap_effective;
  assign eprom_latch_enable_o = !pcr_latch_enable && vpp_present_i;
  assign eprom_program_enable_o = !pcr_program_enable && !pcr_latch_enable &&
                                  vpp_present_i;
  assign eprom_program_address_o = eprom_address_latch;
  assign eprom_program_data_o = eprom_data_latch;
  assign timer_irq_o = timer_control[7] && !timer_control[6];
  assign external_irq_o = external_request;
  assign debug_address_o = {5'h00, core_address[10:0]};
  assign debug_pc_o = core_debug_pc;
  assign debug_timer_o = timer_data;
  assign debug_timer_control_o = MASK_OPTION[6] ? {timer_control[7:6], 6'h3f} :
                                                  timer_control;
  assign debug_program_control_o = {5'h1f, !vpp_present_i,
                                    pcr_program_enable, pcr_latch_enable};
endmodule
