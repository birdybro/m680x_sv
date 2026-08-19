// SPDX-License-Identifier: MIT
// HD63705V0 single-chip digital MCU integration.
//
// The normalized clock boundary advances one E cycle per enabled rising edge.
// Internal EPROM storage remains an FPGA integration responsibility.  The
// optional programming signals expose only the documented digital address,
// data, verify, and program controls; programming voltage physics are excluded.
module hd63705v0_mcu (
  input  logic        clk_i,
  input  logic        reset_n_i,
  input  logic        clock_enable_i,
  input  logic        standby_n_i,
  input  logic        int_n_i,
  input  logic        int2_n_i,
  input  logic        timer_i,
  input  logic [7:0]  port_a_i,
  input  logic [7:0]  port_b_i,
  input  logic [7:0]  port_c_i,
  input  logic [6:0]  port_d_i,
  output logic [7:0]  port_a_o,
  output logic [7:0]  port_b_o,
  output logic [7:0]  port_c_o,
  output logic [6:0]  port_d_o,
  output logic [7:0]  port_a_oe_o,
  output logic [7:0]  port_b_oe_o,
  output logic [7:0]  port_c_oe_o,
  output logic [6:0]  port_d_oe_o,
  output logic [13:0] program_address_o,
  output logic        program_read_o,
  input  logic [7:0]  program_data_i,
  input  logic        eprom_mode_i,
  input  logic [11:0] eprom_address_i,
  input  logic [7:0]  eprom_data_i,
  input  logic        eprom_chip_enable_n_i,
  input  logic        eprom_output_enable_n_i,
  input  logic        eprom_program_voltage_i,
  output logic [7:0]  eprom_data_o,
  output logic        eprom_data_oe_o,
  output logic [7:0]  eprom_program_data_o,
  output logic        eprom_program_o,
  output logic        sci_tx_o,
  output logic        sci_clock_o,
  output logic        timer_irq_o,
  output logic        sci_irq_o,
  output logic        int_irq_o,
  output logic        int2_irq_o,
  output logic [15:0] irq_vector_o,
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
  output logic [7:0]  debug_tcr_o,
  output logic [7:0]  debug_mr_o,
  output logic [7:0]  debug_scr_o,
  output logic [7:0]  debug_ssr_o,
  output logic [7:0]  debug_sdr_o
);
  localparam logic [15:0] SCI_TIMER2_VECTOR = 16'h1ff4;
  localparam logic [15:0] WAIT_TIMER_VECTOR = 16'h1ff6;
  localparam logic [15:0] TIMER_INT2_VECTOR = 16'h1ff8;
  localparam logic [15:0] INT_VECTOR = 16'h1ffa;
  localparam logic [15:0] SWI_VECTOR = 16'h1ffc;
  localparam logic [15:0] RESET_VECTOR = 16'h1ffe;

  logic [7:0] ram [0:191];
  logic [7:0] port_a_latch;
  logic [7:0] port_b_latch;
  logic [7:0] port_c_latch;
  logic [6:0] port_d_latch;
  logic [7:0] port_a_ddr;
  logic [7:0] port_b_ddr;
  logic [7:0] port_c_ddr;
  logic [6:0] port_d_ddr;
  logic [7:0] timer_data;
  logic [7:4] timer_control_high;
  logic [2:0] timer_prescale_select;
  logic [6:0] timer_prescaler;
  logic timer_previous;
  logic int_previous;
  logic int_latch;
  logic int2_previous;
  logic [7:5] miscellaneous;
  logic [7:0] sci_control;
  logic [7:4] sci_status;
  logic [7:0] sci_data;
  logic [14:0] sci_divider;
  logic sci_clock;
  logic sci_external_previous;
  logic [7:0] transmit_shift;
  logic [3:0] transmit_bits;
  logic transmit_active;
  logic transmit_output;
  logic [6:0] receive_shift;
  logic [3:0] receive_bits;
  logic receive_armed;
  logic stopped_previous;

  logic timer_input_event;
  logic timer_counter_event;
  logic timer_rising;
  logic [6:0] timer_prescale_mask;
  logic [14:0] sci_interval_mask;
  logic sci_toggle;
  logic sci_internal_rising;
  logic sci_internal_falling;
  logic sci_external_rising;
  logic sci_external_falling;
  logic sci_serial_rising;
  logic sci_serial_falling;
  logic sci_serial_selected;
  logic int_request;
  logic int2_request;
  logic timer_request;
  logic sci_request;
  logic irq_request;
  logic [15:0] core_irq_vector;
  logic [7:0] core_data_in;
  logic [7:0] core_data_out;
  // The generic execution core computes sixteen-bit effective addresses;
  // HD63705V0 exposes only A13:A0, so the upper two bits are intentionally
  // discarded at this device boundary.
  /* verilator lint_off UNUSEDSIGNAL */
  logic [15:0] core_address;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [15:0] core_debug_pc;
  logic core_write;
  logic core_bus_valid;
  logic device_reset_n;
  logic program_select;

  function automatic logic [6:0] prescale_mask(input logic [2:0] selection);
    case (selection)
      3'd0: prescale_mask = 7'h00;
      3'd1: prescale_mask = 7'h01;
      3'd2: prescale_mask = 7'h03;
      3'd3: prescale_mask = 7'h07;
      3'd4: prescale_mask = 7'h0f;
      3'd5: prescale_mask = 7'h1f;
      3'd6: prescale_mask = 7'h3f;
      default: prescale_mask = 7'h7f;
    endcase
  endfunction

  function automatic logic [14:0] serial_interval_mask(input logic [3:0] selection);
    case (selection)
      4'd0: serial_interval_mask = 15'h0000;
      4'd1: serial_interval_mask = 15'h0001;
      4'd2: serial_interval_mask = 15'h0003;
      4'd3: serial_interval_mask = 15'h0007;
      4'd4: serial_interval_mask = 15'h000f;
      4'd5: serial_interval_mask = 15'h001f;
      4'd6: serial_interval_mask = 15'h003f;
      4'd7: serial_interval_mask = 15'h007f;
      4'd8: serial_interval_mask = 15'h00ff;
      4'd9: serial_interval_mask = 15'h01ff;
      4'd10: serial_interval_mask = 15'h03ff;
      4'd11: serial_interval_mask = 15'h07ff;
      4'd12: serial_interval_mask = 15'h0fff;
      4'd13: serial_interval_mask = 15'h1fff;
      4'd14: serial_interval_mask = 15'h3fff;
      default: serial_interval_mask = 15'h7fff;
    endcase
  endfunction

  assign device_reset_n = reset_n_i && standby_n_i && !eprom_mode_i;
  assign program_select = (core_address[13:0] >= 14'h1000) &&
                          (core_address[13:0] <= 14'h1fff);

  always_comb begin
    timer_rising = !timer_previous && timer_i;
    case (timer_control_high[5:4])
      2'b00: timer_input_event = 1'b1;
      2'b01: timer_input_event = timer_i;
      2'b10: timer_input_event = 1'b0;
      default: timer_input_event = timer_rising;
    endcase
    timer_prescale_mask = prescale_mask(timer_prescale_select);
    timer_counter_event = timer_input_event &&
                          ((timer_prescaler & timer_prescale_mask) ==
                           timer_prescale_mask);

    sci_interval_mask = serial_interval_mask(sci_control[3:0]);
    sci_toggle = (sci_divider == sci_interval_mask);
    sci_internal_rising = sci_toggle && !sci_clock;
    sci_internal_falling = sci_toggle && sci_clock;
    sci_external_rising = !sci_external_previous && port_d_i[5];
    sci_external_falling = sci_external_previous && !port_d_i[5];
    sci_serial_selected = sci_control[5];
    if (sci_control[4]) begin
      sci_serial_rising = sci_external_rising;
      sci_serial_falling = sci_external_falling;
    end else begin
      sci_serial_rising = sci_internal_rising;
      sci_serial_falling = sci_internal_falling;
    end

    int_request = int_latch || (miscellaneous[5] && !int_n_i);
    int2_request = miscellaneous[7] && !miscellaneous[6];
    timer_request = timer_control_high[7] && !timer_control_high[6];
    sci_request = (sci_status[7] && !sci_status[5]) ||
                  (sci_status[6] && !sci_status[4]);
    if (stopped_o) irq_request = int_request || int2_request;
    else irq_request = int_request || int2_request || timer_request || sci_request;

    if (int_request) core_irq_vector = INT_VECTOR;
    else if (int2_request) core_irq_vector = TIMER_INT2_VECTOR;
    else if (timer_request && waiting_o) core_irq_vector = WAIT_TIMER_VECTOR;
    else if (timer_request) core_irq_vector = TIMER_INT2_VECTOR;
    else core_irq_vector = SCI_TIMER2_VECTOR;
  end

  always_comb begin
    core_data_in = 8'hff;
    case (core_address[13:0])
      14'h0000: core_data_in = (port_a_latch & port_a_ddr) |
                                     (port_a_i & ~port_a_ddr);
      14'h0001: core_data_in = (port_b_latch & port_b_ddr) |
                                     (port_b_i & ~port_b_ddr);
      14'h0002: core_data_in = (port_c_latch & port_c_ddr) |
                                     (port_c_i & ~port_c_ddr);
      14'h0003: core_data_in = {1'b1, (port_d_latch & port_d_ddr) |
                                      (port_d_i & ~port_d_ddr)};
      14'h0004: core_data_in = port_a_ddr;
      14'h0005: core_data_in = port_b_ddr;
      14'h0006: core_data_in = port_c_ddr;
      14'h0007: core_data_in = {1'b1, port_d_ddr};
      14'h0008: core_data_in = timer_data;
      14'h0009: core_data_in = {timer_control_high, 1'b0, timer_prescale_select};
      14'h000a: core_data_in = {miscellaneous, 5'h1f};
      14'h0010: core_data_in = sci_control;
      14'h0011: core_data_in = {sci_status, 1'b0, 3'b111};
      14'h0012: core_data_in = sci_data;
      default: begin
        if ((core_address[13:0] >= 14'h0040) &&
            (core_address[13:0] <= 14'h00ff)) begin
          core_data_in = ram[core_address[7:0] - 8'h40];
        end else if (program_select) begin
          core_data_in = program_data_i;
        end
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge device_reset_n) begin
    if (!device_reset_n) begin
      port_a_latch <= 8'h00;
      port_b_latch <= 8'h00;
      port_c_latch <= 8'h00;
      port_d_latch <= 7'h00;
      port_a_ddr <= 8'h00;
      port_b_ddr <= 8'h00;
      port_c_ddr <= 8'h00;
      port_d_ddr <= 7'h00;
      timer_data <= 8'hf0;
      timer_control_high <= 4'h5;
      timer_prescale_select <= 3'h0;
      timer_prescaler <= 7'h7f;
      timer_previous <= 1'b0;
      int_previous <= 1'b1;
      int_latch <= 1'b0;
      int2_previous <= 1'b1;
      miscellaneous <= 3'b010;
      sci_control <= 8'h00;
      sci_status <= 4'b0011;
      sci_data <= 8'h00;
      sci_divider <= 15'h0000;
      sci_clock <= 1'b0;
      sci_external_previous <= 1'b0;
      transmit_shift <= 8'h00;
      transmit_bits <= 4'd0;
      transmit_active <= 1'b0;
      transmit_output <= 1'b0;
      receive_shift <= 7'h00;
      receive_bits <= 4'd0;
      receive_armed <= 1'b0;
      stopped_previous <= 1'b0;
    end else if (clock_enable_i) begin
      timer_previous <= timer_i;
      int_previous <= int_n_i;
      int2_previous <= int2_n_i;
      sci_external_previous <= port_d_i[5];
      stopped_previous <= stopped_o;

      if (int_previous && !int_n_i) int_latch <= 1'b1;
      if (int2_previous && !int2_n_i) miscellaneous[7] <= 1'b1;
      if (core_bus_valid && !core_write && (core_address[13:0] == 14'h1ffa)) begin
        int_latch <= 1'b0;
      end

      if (stopped_o && !stopped_previous) begin
        timer_data <= 8'hf0;
        timer_control_high[7] <= 1'b0;
        timer_control_high[6] <= 1'b1;
        sci_status[7:6] <= 2'b00;
        sci_status[5:4] <= 2'b11;
      end else if (!stopped_o) begin
        if (timer_input_event) begin
          timer_prescaler <= timer_prescaler + 7'h01;
          if (timer_counter_event) begin
            timer_data <= timer_data - 8'h01;
            if (timer_data == 8'h01) timer_control_high[7] <= 1'b1;
          end
        end

        if (sci_serial_selected && sci_toggle) begin
          sci_divider <= 15'h0000;
          sci_clock <= !sci_clock;
        end else if (sci_serial_selected) begin
          sci_divider <= sci_divider + 15'h0001;
        end
        if (sci_serial_selected && sci_internal_falling) sci_status[6] <= 1'b1;

        if (sci_serial_selected && sci_serial_falling && transmit_active &&
            sci_control[7]) begin
          transmit_output <= transmit_shift[0];
          transmit_shift <= {1'b0, transmit_shift[7:1]};
          transmit_bits <= transmit_bits + 4'd1;
          if (transmit_bits == 4'd7) transmit_active <= 1'b0;
        end
        if (sci_serial_selected && sci_serial_rising) begin
          if (!transmit_active && (transmit_bits == 4'd8)) begin
            sci_status[7] <= 1'b1;
            transmit_bits <= 4'd0;
          end
          if (receive_armed && sci_control[6]) begin
            receive_bits <= receive_bits + 4'd1;
            if (receive_bits == 4'd7) begin
              sci_data <= {port_d_i[4], receive_shift[6:0]};
              sci_status[7] <= 1'b1;
              receive_shift <= 7'h00;
              receive_bits <= 4'd0;
            end else begin
              receive_shift[receive_bits[2:0]] <= port_d_i[4];
            end
          end
        end
      end

      if (core_bus_valid && core_write) begin
        case (core_address[13:0])
          14'h0000: port_a_latch <= core_data_out;
          14'h0001: port_b_latch <= core_data_out;
          14'h0002: port_c_latch <= core_data_out;
          14'h0003: port_d_latch <= core_data_out[6:0];
          14'h0004: port_a_ddr <= core_data_out;
          14'h0005: port_b_ddr <= core_data_out;
          14'h0006: port_c_ddr <= core_data_out;
          14'h0007: port_d_ddr <= core_data_out[6:0];
          14'h0008: timer_data <= core_data_out;
          14'h0009: begin
            if (!core_data_out[7]) timer_control_high[7] <= 1'b0;
            timer_control_high[6:4] <= core_data_out[6:4];
            timer_prescale_select <= core_data_out[2:0];
            if (core_data_out[3]) timer_prescaler <= 7'h7f;
          end
          14'h000a: begin
            if (!core_data_out[7]) miscellaneous[7] <= 1'b0;
            miscellaneous[6:5] <= core_data_out[6:5];
          end
          14'h0010: sci_control <= core_data_out;
          14'h0011: begin
            if (!core_data_out[7]) sci_status[7] <= 1'b0;
            if (!core_data_out[6]) sci_status[6] <= 1'b0;
            sci_status[5:4] <= core_data_out[5:4];
            if (core_data_out[3]) sci_divider <= 15'h0000;
          end
          14'h0012: begin
            sci_data <= core_data_out;
            if (sci_control[5]) begin
              sci_status[7] <= 1'b0;
              receive_armed <= 1'b1;
              transmit_shift <= core_data_out;
              transmit_bits <= 4'd0;
              transmit_active <= 1'b1;
              if (!sci_control[4]) sci_divider <= 15'h0000;
            end
          end
          default: ;
        endcase
      end else if (core_bus_valid && !core_write &&
                   (core_address[13:0] == 14'h0012) && sci_control[5]) begin
        sci_status[7] <= 1'b0;
        receive_armed <= 1'b1;
        if (!sci_control[4]) sci_divider <= 15'h0000;
      end
    end
  end

  // RAM contents are retained through RES and STBY, as documented.  This
  // reset-free write process also preserves FPGA RAM inference.
  // device_reset_n is intentionally both the asynchronous register reset and
  // a synchronous RAM-write gate so STBY preserves the RAM array.
  /* verilator lint_off SYNCASYNCNET */
  always_ff @(posedge clk_i) begin
    if (device_reset_n && clock_enable_i && core_bus_valid && core_write &&
        (core_address[13:0] >= 14'h0040) && (core_address[13:0] <= 14'h00ff)) begin
      ram[core_address[7:0] - 8'h40] <= core_data_out;
    end
  end
  /* verilator lint_on SYNCASYNCNET */

  m6805_core #(
    .HITACHI_PROFILE(1'b1),
    .PC_MASK(16'h3fff),
    .STACK_BASE(16'h00c0),
    .STACK_MASK(16'h003f),
    .STACK_TOP(16'h00ff),
    .SWI_VECTOR(SWI_VECTOR),
    .RESET_VECTOR(RESET_VECTOR)
  ) cpu (
    .clk_i(clk_i), .reset_n_i(device_reset_n),
    .clock_enable_i(clock_enable_i), .bus_ready_i(1'b1),
    .irq_n_i(!irq_request), .interrupt_pin_n_i(int_n_i),
    .irq_vector_i(core_irq_vector), .data_i(core_data_in),
    .address_o(core_address), .data_o(core_data_out), .write_o(core_write),
    .bus_valid_o(core_bus_valid), .opcode_fetch_o(opcode_fetch_o),
    .retire_o(retire_o), .illegal_o(illegal_o), .undefined_o(undefined_o),
    .waiting_o(waiting_o), .stopped_o(stopped_o),
    .interrupt_ack_o(interrupt_ack_o), .debug_a_o(debug_a_o),
    .debug_x_o(debug_x_o), .debug_sp_o(debug_sp_o),
    .debug_pc_o(core_debug_pc), .debug_ccr_o(debug_ccr_o),
    .debug_opcode_o(debug_opcode_o),
    .debug_instruction_cycles_o(debug_instruction_cycles_o)
  );

  always_comb begin
    port_a_o = port_a_latch;
    port_b_o = port_b_latch;
    port_c_o = port_c_latch;
    port_d_o = port_d_latch;
    port_a_oe_o = device_reset_n ? port_a_ddr : 8'h00;
    port_b_oe_o = device_reset_n ? port_b_ddr : 8'h00;
    port_c_oe_o = device_reset_n ? port_c_ddr : 8'h00;
    port_d_oe_o = device_reset_n ? port_d_ddr : 7'h00;
    if (sci_control[7]) begin
      port_d_o[3] = transmit_output;
      if (device_reset_n) port_d_oe_o[3] = 1'b1;
    end
    if (sci_control[6]) port_d_oe_o[4] = 1'b0;
    if (sci_control[5]) begin
      if (sci_control[4]) begin
        port_d_oe_o[5] = 1'b0;
      end else begin
        port_d_o[5] = sci_clock;
        if (device_reset_n) port_d_oe_o[5] = 1'b1;
      end
    end

    if (eprom_mode_i) begin
      program_address_o = {2'b01, eprom_address_i};
      program_read_o = eprom_program_voltage_i && !eprom_output_enable_n_i;
    end else begin
      program_address_o = core_address[13:0];
      program_read_o = core_bus_valid && !core_write && program_select;
    end
  end

  assign eprom_data_o = program_data_i;
  assign eprom_data_oe_o = eprom_mode_i && eprom_program_voltage_i &&
                           !eprom_output_enable_n_i;
  assign eprom_program_data_o = eprom_data_i;
  assign eprom_program_o = eprom_mode_i && eprom_program_voltage_i &&
                           !eprom_chip_enable_n_i && eprom_output_enable_n_i;
  assign sci_tx_o = transmit_output;
  assign sci_clock_o = sci_clock;
  assign timer_irq_o = timer_request;
  assign sci_irq_o = sci_request;
  assign int_irq_o = int_request;
  assign int2_irq_o = int2_request;
  assign irq_vector_o = core_irq_vector;
  assign debug_address_o = {2'b00, core_address[13:0]};
  assign debug_pc_o = core_debug_pc;
  assign debug_timer_o = timer_data;
  assign debug_tcr_o = {timer_control_high, 1'b0, timer_prescale_select};
  assign debug_mr_o = {miscellaneous, 5'h1f};
  assign debug_scr_o = sci_control;
  assign debug_ssr_o = {sci_status, 1'b0, 3'b111};
  assign debug_sdr_o = sci_data;

endmodule
