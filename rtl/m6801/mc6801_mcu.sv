// SPDX-License-Identifier: MIT
// MC6801-lineage common digital MCU integration.
//
// Register, timer, SCI, and interrupt behavior is derived from Motorola
// MC6801 Reference Manual MC6801RM(AD2), chapters 2, 3, 5, 6, and 7. One
// clk_i/clock_enable_i step represents one complete E-cycle. Physical Port 3
// address/data multiplexing and the E/AS waveform belong in a pin wrapper.
// HD6301_MODE7 enables the separately documented HD6301V1 single-chip decode,
// Port 3/4 registers, handshake, and internal program-memory interface.
module mc6801_mcu #(
  parameter logic [2:0] OPERATING_MODE = 3'd2,
  parameter logic       HITACHI_CPU = 1'b0,
  parameter logic       HD6301_MODE7 = 1'b0
) (
  input  logic        clk_i,
  input  logic        reset_n_i,
  input  logic        clock_enable_i,
  input  logic        nmi_n_i,
  input  logic        irq1_n_i,
  input  logic        standby_power_ok_i,
  input  logic [7:0]  port1_i,
  input  logic [4:0]  port2_i,
  input  logic [7:0]  port3_i,
  input  logic [7:0]  port4_i,
  input  logic        is3_n_i,
  input  logic [7:0]  program_data_i,
  input  logic [7:0]  external_data_i,
  output logic [15:0] program_address_o,
  output logic        program_read_o,
  output logic [15:0] external_address_o,
  output logic [7:0]  external_data_o,
  output logic        external_write_o,
  output logic        external_bus_valid_o,
  output logic        external_opcode_fetch_o,
  output logic [7:0]  port1_o,
  output logic [7:0]  port1_oe_o,
  output logic [4:0]  port2_o,
  output logic [4:0]  port2_oe_o,
  output logic [7:0]  port3_o,
  output logic [7:0]  port3_oe_o,
  output logic [7:0]  port4_o,
  output logic [7:0]  port4_oe_o,
  output logic        os3_n_o,
  output logic        sci_tx_o,
  output logic        sci_clock_o,
  output logic        timer_irq_o,
  output logic        sci_irq_o,
  output logic        opcode_fetch_o,
  output logic        retire_o,
  output logic        illegal_o,
  output logic        undefined_o,
  output logic        waiting_o,
  output logic        sleeping_o,
  output logic        interrupt_ack_o,
  output logic [15:0] debug_address_o,
  output logic [15:0] debug_pc_o,
  output logic [15:0] debug_sp_o,
  output logic [7:0]  debug_a_o,
  output logic [7:0]  debug_b_o,
  output logic [15:0] debug_x_o,
  output logic [5:0]  debug_ccr_o,
  output logic [15:0] debug_timer_o,
  output logic [15:0] debug_output_compare_o,
  output logic [15:0] debug_input_capture_o,
  output logic [7:0]  debug_tcsr_o,
  output logic [7:0]  debug_trcsr_o,
  output logic [7:0]  debug_receive_data_o,
  output logic [7:0]  debug_opcode_o
);
  localparam logic MODE7 = HITACHI_CPU && HD6301_MODE7 &&
    (OPERATING_MODE == 3'd7);
  localparam logic [15:0] VECTOR_IRQ1 = 16'hfff8;
  localparam logic [15:0] VECTOR_INPUT_CAPTURE = 16'hfff6;
  localparam logic [15:0] VECTOR_OUTPUT_COMPARE = 16'hfff4;
  localparam logic [15:0] VECTOR_TIMER_OVERFLOW = 16'hfff2;
  localparam logic [15:0] VECTOR_SCI = 16'hfff0;

  logic [7:0] ram [0:127];
  logic [7:0] port1_latch;
  logic [4:0] port2_latch;
  logic [7:0] port3_latch;
  logic [7:0] port4_latch;
  logic [7:0] port1_ddr;
  logic [4:0] port2_ddr;
  logic [7:0] port3_ddr;
  logic [7:0] port4_ddr;
  logic [7:0] port3_input_latch;
  logic port3_latch_valid;
  logic port3_latch_enable;
  logic port3_output_strobe_select;
  logic port3_is3_enable;
  logic port3_is3_flag;
  logic is3_sync1;
  logic is3_sync2;
  logic port3_clear_armed;
  logic rame;
  logic standby_power;

  logic [15:0] timer_counter;
  logic [15:0] output_compare;
  logic [15:0] input_capture;
  logic [7:0] counter_low_latch;
  logic [7:0] tcsr;
  logic output_level;
  logic compare_inhibit;
  logic capture_inhibit;
  logic capture_sync1;
  logic capture_sync2;
  logic icf_clear_armed;
  logic ocf_clear_armed;
  logic tof_clear_armed;

  logic [3:0] rmcr;
  logic [4:0] trcsr_control;
  logic rdrf;
  logic orfe;
  logic tdre;
  logic [7:0] receive_data;
  logic [7:0] transmit_data;
  logic tdre_clear_armed;
  logic receive_clear_armed;
  logic [9:0] tx_shift;
  logic [3:0] tx_bits_remaining;
  logic [3:0] tx_preamble_remaining;
  logic tx_active;
  logic rx_previous;
  logic rx_busy;
  logic [12:0] rx_countdown;
  logic [3:0] rx_bit_index;
  logic [7:0] rx_shift;
  logic [3:0] wake_mark_count;

  logic [15:0] core_address;
  logic [7:0] core_data_in;
  logic [7:0] core_data_out;
  logic core_write;
  logic core_bus_valid;
  logic core_opcode_fetch;
  logic [15:0] core_irq_vector;
  logic irq_n;
  logic irq1_pending;
  logic irq2_pending;
  logic internal_register_select;
  logic internal_ram_select;
  logic internal_program_select;
  logic unusable_select;
  logic internal_read;
  logic internal_write;
  logic [15:0] timer_next;
  logic capture_pin;
  logic capture_edge;
  logic timer_compare_event;
  logic timer_overflow_event;
  logic sci_bit_tick;
  logic [12:0] sci_divisor;
  logic sci_nrz_internal;
  logic sci_clock_level;
  logic timer_counter_write;
  logic capture_high_read;
  logic is3_falling_edge;
  logic port3_access;
  logic instruction_address_error;
  logic port3_irq;

  function automatic logic register_is_internal(input logic [15:0] address_value);
    begin
      case (address_value)
        16'h0000, 16'h0001, 16'h0002, 16'h0003,
        16'h0008, 16'h0009, 16'h000a, 16'h000b,
        16'h000c, 16'h000d, 16'h000e,
        16'h0010, 16'h0011, 16'h0012, 16'h0013,
        16'h0014: register_is_internal = 1'b1;
        16'h0004, 16'h0005, 16'h0006, 16'h0007,
        16'h000f: register_is_internal = MODE7;
        default: register_is_internal = 1'b0;
      endcase
    end
  endfunction

  always_comb begin
    internal_register_select = core_bus_valid && register_is_internal(core_address);
    internal_ram_select = core_bus_valid && rame && (OPERATING_MODE != 3'd3) &&
      (core_address >= 16'h0080) && (core_address <= 16'h00ff);
    internal_program_select = core_bus_valid && MODE7 &&
      (core_address >= 16'hf000);
    unusable_select = core_bus_valid && MODE7 && !internal_register_select &&
      !internal_ram_select && !internal_program_select;
    internal_read = clock_enable_i && internal_register_select && !core_write;
    internal_write = clock_enable_i && internal_register_select && core_write;
    timer_counter_write = internal_write && (core_address == 16'h0009);
    capture_high_read = internal_read && (core_address == 16'h000d);
    port3_access = clock_enable_i && internal_register_select &&
      (core_address == 16'h0006);
    instruction_address_error = MODE7 && core_opcode_fetch &&
      ((core_address <= 16'h007f) ||
       ((core_address >= 16'h0100) && (core_address <= 16'hefff)));

    core_data_in = external_data_i;
    if (internal_program_select) begin
      core_data_in = program_data_i;
    end else if (unusable_select) begin
      core_data_in = 8'hff;
    end else if (internal_ram_select) begin
      core_data_in = ram[core_address[6:0]];
    end else if (internal_register_select) begin
      case (core_address)
        16'h0000, 16'h0001: core_data_in = 8'hff;
        16'h0002: core_data_in = port1_i;
        16'h0003: core_data_in = {OPERATING_MODE, port2_i};
        16'h0004, 16'h0005: core_data_in = 8'hff;
        16'h0006: core_data_in = port3_latch_valid ? port3_input_latch : port3_i;
        16'h0007: core_data_in = port4_i;
        16'h0008: core_data_in = tcsr;
        16'h0009: core_data_in = timer_counter[15:8];
        16'h000a: core_data_in = counter_low_latch;
        16'h000b: core_data_in = output_compare[15:8];
        16'h000c: core_data_in = output_compare[7:0];
        16'h000d: core_data_in = input_capture[15:8];
        16'h000e: core_data_in = input_capture[7:0];
        16'h000f: core_data_in = {port3_is3_flag, port3_is3_enable, 1'b1,
          port3_output_strobe_select, port3_latch_enable, 3'b111};
        16'h0011: core_data_in = {rdrf, orfe, tdre, trcsr_control};
        16'h0012: core_data_in = receive_data;
        16'h0014: core_data_in = {standby_power, rame, 6'h00};
        default: core_data_in = 8'hff;
      endcase
    end
  end

  always_comb begin
    timer_next = timer_counter + 16'h0001;
    capture_pin = port2_ddr[0] ? port2_latch[0] : port2_i[0];
    capture_edge = tcsr[1] ? (capture_sync1 && !capture_sync2) :
      (!capture_sync1 && capture_sync2);
    timer_compare_event = !timer_counter_write && !compare_inhibit &&
      (timer_next == output_compare);
    timer_overflow_event = !timer_counter_write && (timer_next == 16'hffff);
    is3_falling_edge = is3_sync2 && !is3_sync1;

    case (rmcr[1:0])
      2'b00: begin
        sci_divisor = 13'd16;
        sci_bit_tick = (timer_next[3:0] == 4'h0);
        sci_clock_level = timer_counter[3];
      end
      2'b01: begin
        sci_divisor = 13'd128;
        sci_bit_tick = (timer_next[6:0] == 7'h00);
        sci_clock_level = timer_counter[6];
      end
      2'b10: begin
        sci_divisor = 13'd1024;
        sci_bit_tick = (timer_next[9:0] == 10'h000);
        sci_clock_level = timer_counter[9];
      end
      default: begin
        sci_divisor = 13'd4096;
        sci_bit_tick = (timer_next[11:0] == 12'h000);
        sci_clock_level = timer_counter[11];
      end
    endcase
    sci_nrz_internal = (rmcr[3:2] == 2'b01) || (rmcr[3:2] == 2'b10);
  end

  always_ff @(posedge clk_i or negedge reset_n_i) begin
    if (!reset_n_i) begin
      port1_latch <= 8'h00;
      port2_latch <= 5'h00;
      port3_latch <= 8'h00;
      port4_latch <= 8'h00;
      port1_ddr <= 8'h00;
      port2_ddr <= 5'h00;
      port3_ddr <= 8'h00;
      port4_ddr <= 8'h00;
      port3_input_latch <= 8'h00;
      port3_latch_valid <= 1'b0;
      port3_latch_enable <= 1'b0;
      port3_output_strobe_select <= 1'b0;
      port3_is3_enable <= 1'b0;
      port3_is3_flag <= 1'b0;
      is3_sync1 <= 1'b1;
      is3_sync2 <= 1'b1;
      port3_clear_armed <= 1'b0;
      rame <= 1'b1;
      // Silicon reset preserves this bit. A deterministic zero is selected at
      // the FPGA boundary; analog retention remains outside the digital claim.
      standby_power <= 1'b0;
    end else if (clock_enable_i) begin
      is3_sync1 <= is3_n_i;
      is3_sync2 <= is3_sync1;
      if (!standby_power_ok_i) begin
        standby_power <= 1'b0;
        rame <= 1'b0;
      end
      if (internal_write) begin
        case (core_address)
          16'h0000: port1_ddr <= core_data_out;
          16'h0001: begin
            port2_ddr[1:0] <= core_data_out[1:0];
            if (!rmcr[3]) port2_ddr[2] <= core_data_out[2];
            if (!trcsr_control[3]) port2_ddr[3] <= core_data_out[3];
            if (!trcsr_control[1]) port2_ddr[4] <= core_data_out[4];
          end
          16'h0002: port1_latch <= core_data_out;
          16'h0003: begin
            port2_latch[0] <= core_data_out[0];
            if (!rmcr[3]) port2_latch[2] <= core_data_out[2];
            if (!trcsr_control[3]) port2_latch[3] <= core_data_out[3];
            if (!trcsr_control[1]) port2_latch[4] <= core_data_out[4];
          end
          16'h0004: if (MODE7) port3_ddr <= core_data_out;
          16'h0005: if (MODE7) port4_ddr <= core_data_out;
          16'h0006: if (MODE7) port3_latch <= core_data_out;
          16'h0007: if (MODE7) port4_latch <= core_data_out;
          16'h000f: if (MODE7) begin
            port3_is3_enable <= core_data_out[6];
            port3_output_strobe_select <= core_data_out[4];
            port3_latch_enable <= core_data_out[3];
          end
          16'h0010: begin
            if (core_data_out[3]) port2_ddr[2] <= !core_data_out[2];
          end
          16'h0011: begin
            if (core_data_out[3]) port2_ddr[3] <= 1'b0;
            if (core_data_out[1]) port2_ddr[4] <= 1'b1;
          end
          16'h0014: begin
            standby_power <= core_data_out[7] && standby_power_ok_i;
            rame <= core_data_out[6];
          end
          default: ;
        endcase
      end

      if (MODE7 && internal_read && (core_address == 16'h000f)) begin
        port3_clear_armed <= port3_is3_flag;
      end
      if (MODE7 && port3_access) begin
        if (!core_write) port3_latch_valid <= 1'b0;
        if (port3_clear_armed) begin
          port3_is3_flag <= 1'b0;
          port3_clear_armed <= 1'b0;
        end
      end
      // A new IS3 edge wins over a coincident software clear.
      if (MODE7 && is3_falling_edge) begin
        port3_is3_flag <= 1'b1;
        if (port3_latch_enable && !port3_latch_valid) begin
          port3_input_latch <= port3_i;
          port3_latch_valid <= 1'b1;
        end
      end
    end
  end

  // The reference manual does not define RAM contents after reset. Keeping
  // reset out of the write process preserves an inference-friendly 128x8 RAM.
  always_ff @(posedge clk_i) begin
    if (clock_enable_i && core_bus_valid && core_write && internal_ram_select) begin
      ram[core_address[6:0]] <= core_data_out;
    end
  end

  always_ff @(posedge clk_i or negedge reset_n_i) begin
    if (!reset_n_i) begin
      timer_counter <= 16'h0000;
      output_compare <= 16'hffff;
      input_capture <= 16'h0000;
      counter_low_latch <= 8'h00;
      tcsr <= 8'h00;
      output_level <= 1'b0;
      compare_inhibit <= 1'b0;
      capture_inhibit <= 1'b0;
      capture_sync1 <= 1'b0;
      capture_sync2 <= 1'b0;
      icf_clear_armed <= 1'b0;
      ocf_clear_armed <= 1'b0;
      tof_clear_armed <= 1'b0;
    end else if (clock_enable_i) begin
      capture_sync1 <= capture_pin;
      capture_sync2 <= capture_sync1;
      compare_inhibit <= 1'b0;
      capture_inhibit <= 1'b0;
      timer_counter <= timer_next;

      if (internal_read && (core_address == 16'h0008)) begin
        icf_clear_armed <= tcsr[7];
        ocf_clear_armed <= tcsr[6];
        tof_clear_armed <= tcsr[5];
      end
      if (internal_read && (core_address == 16'h0009)) begin
        counter_low_latch <= timer_counter[7:0];
        if (tof_clear_armed) begin
          tcsr[5] <= 1'b0;
          tof_clear_armed <= 1'b0;
        end
      end
      if (capture_high_read) begin
        capture_inhibit <= 1'b1;
        if (icf_clear_armed) begin
          tcsr[7] <= 1'b0;
          icf_clear_armed <= 1'b0;
        end
      end

      if (internal_write) begin
        case (core_address)
          16'h0008: tcsr[4:0] <= core_data_out[4:0];
          16'h0009: timer_counter <= 16'hfff8;
          16'h000b: begin
            output_compare[15:8] <= core_data_out;
            compare_inhibit <= 1'b1;
            if (ocf_clear_armed) begin
              tcsr[6] <= 1'b0;
              ocf_clear_armed <= 1'b0;
            end
          end
          16'h000c: begin
            output_compare[7:0] <= core_data_out;
            if (ocf_clear_armed) begin
              tcsr[6] <= 1'b0;
              ocf_clear_armed <= 1'b0;
            end
          end
          default: ;
        endcase
      end

      // New hardware events win over a coincident software clear.
      if (timer_overflow_event) tcsr[5] <= 1'b1;
      if (timer_compare_event) begin
        tcsr[6] <= 1'b1;
        output_level <= tcsr[0];
      end
      if (capture_edge && !capture_inhibit && !capture_high_read) begin
        input_capture <= timer_next;
        tcsr[7] <= 1'b1;
      end
    end
  end

  always_ff @(posedge clk_i or negedge reset_n_i) begin
    if (!reset_n_i) begin
      rmcr <= 4'h0;
      trcsr_control <= 5'h00;
      rdrf <= 1'b0;
      orfe <= 1'b0;
      tdre <= 1'b1;
      receive_data <= 8'h00;
      transmit_data <= 8'h00;
      tdre_clear_armed <= 1'b0;
      receive_clear_armed <= 1'b0;
      tx_shift <= 10'h3ff;
      tx_bits_remaining <= 4'd0;
      tx_preamble_remaining <= 4'd0;
      tx_active <= 1'b0;
      rx_previous <= 1'b1;
      rx_busy <= 1'b0;
      rx_countdown <= 13'd0;
      rx_bit_index <= 4'd0;
      rx_shift <= 8'h00;
      wake_mark_count <= 4'd0;
    end else if (clock_enable_i) begin
      rx_previous <= port2_i[3];

      if (internal_read && (core_address == 16'h0011)) begin
        tdre_clear_armed <= tdre;
        receive_clear_armed <= rdrf || orfe;
      end
      if (internal_read && (core_address == 16'h0012) && receive_clear_armed) begin
        rdrf <= 1'b0;
        orfe <= 1'b0;
        receive_clear_armed <= 1'b0;
      end

      if (internal_write) begin
        case (core_address)
          16'h0010: rmcr <= core_data_out[3:0];
          16'h0011: begin
            trcsr_control <= core_data_out[4:0];
            if (!trcsr_control[1] && core_data_out[1]) begin
              tx_preamble_remaining <= 4'd9;
              tx_active <= 1'b0;
            end
            if (!core_data_out[1]) begin
              tx_active <= 1'b0;
              tx_bits_remaining <= 4'd0;
            end
          end
          16'h0013: begin
            transmit_data <= core_data_out;
            if (tdre_clear_armed) begin
              tdre <= 1'b0;
              tdre_clear_armed <= 1'b0;
            end
          end
          default: ;
        endcase
      end

      if (sci_bit_tick && trcsr_control[0]) begin
        if (port2_i[3]) begin
          if (wake_mark_count == 4'd9) begin
            trcsr_control[0] <= 1'b0;
            wake_mark_count <= 4'd0;
          end else begin
            wake_mark_count <= wake_mark_count + 4'd1;
          end
        end else begin
          wake_mark_count <= 4'd0;
        end
      end

      if (sci_bit_tick && sci_nrz_internal && trcsr_control[1]) begin
        if (tx_preamble_remaining != 4'd0) begin
          tx_preamble_remaining <= tx_preamble_remaining - 4'd1;
        end else if (tx_active) begin
          if (tx_bits_remaining == 4'd1) begin
            if (!tdre) begin
              tx_shift <= {1'b1, transmit_data, 1'b0};
              tx_bits_remaining <= 4'd10;
              tdre <= 1'b1;
            end else begin
              tx_active <= 1'b0;
              tx_bits_remaining <= 4'd0;
            end
          end else begin
            tx_shift <= {1'b1, tx_shift[9:1]};
            tx_bits_remaining <= tx_bits_remaining - 4'd1;
          end
        end else if (!tdre) begin
          tx_shift <= {1'b1, transmit_data, 1'b0};
          tx_bits_remaining <= 4'd10;
          tx_active <= 1'b1;
          tdre <= 1'b1;
        end
      end

      if (!trcsr_control[3] || !sci_nrz_internal || trcsr_control[0]) begin
        rx_busy <= 1'b0;
      end else if (!rx_busy) begin
        if (rx_previous && !port2_i[3]) begin
          rx_busy <= 1'b1;
          rx_countdown <= sci_divisor >> 1;
          rx_bit_index <= 4'd0;
        end
      end else if (rx_countdown > 13'd1) begin
        rx_countdown <= rx_countdown - 13'd1;
      end else if (rx_bit_index == 4'd0) begin
        if (port2_i[3]) begin
          rx_busy <= 1'b0;
        end else begin
          rx_bit_index <= 4'd1;
          rx_countdown <= sci_divisor;
        end
      end else if (rx_bit_index <= 4'd8) begin
        rx_shift[rx_bit_index[2:0] - 3'd1] <= port2_i[3];
        rx_bit_index <= rx_bit_index + 4'd1;
        rx_countdown <= sci_divisor;
      end else begin
        rx_busy <= 1'b0;
        if (!port2_i[3]) begin
          if (!rdrf && !orfe) receive_data <= rx_shift;
          orfe <= 1'b1;
          // A following zero is itself the next start bit (continuous BREAK).
          rx_busy <= 1'b1;
          rx_bit_index <= 4'd1;
          rx_countdown <= sci_divisor;
        end else if (rdrf || orfe) begin
          orfe <= 1'b1;
        end else begin
          receive_data <= rx_shift;
          rdrf <= 1'b1;
        end
      end
    end
  end

  // The IRQ1 request flip-flop is held reset while I is set and retains a
  // sampled low pulse while interrupts are enabled. This is separate from the
  // level-sensitive Port 3, timer, and SCI flag sources.
  always_ff @(posedge clk_i or negedge reset_n_i) begin
    if (!reset_n_i) begin
      irq1_pending <= 1'b0;
      irq2_pending <= 1'b0;
    end else if (clock_enable_i) begin
      if (debug_ccr_o[4]) begin
        irq1_pending <= 1'b0;
        irq2_pending <= 1'b0;
      end else begin
        if (!irq1_n_i) irq1_pending <= 1'b1;
        if (timer_irq_o || sci_irq_o) irq2_pending <= 1'b1;
      end
    end
  end

  always_comb begin
    sci_irq_o = (trcsr_control[4] && (rdrf || orfe)) ||
      (trcsr_control[2] && tdre);
    timer_irq_o = (tcsr[7] && tcsr[4]) || (tcsr[6] && tcsr[3]) ||
      (tcsr[5] && tcsr[2]);
    port3_irq = MODE7 && port3_is3_flag && port3_is3_enable;

    if (irq1_pending || !irq1_n_i || port3_irq) core_irq_vector = VECTOR_IRQ1;
    else if (tcsr[7] && tcsr[4]) core_irq_vector = VECTOR_INPUT_CAPTURE;
    else if (tcsr[6] && tcsr[3]) core_irq_vector = VECTOR_OUTPUT_COMPARE;
    else if (tcsr[5] && tcsr[2]) core_irq_vector = VECTOR_TIMER_OVERFLOW;
    else core_irq_vector = VECTOR_SCI;
    irq_n = !(irq1_pending || !irq1_n_i || port3_irq || irq2_pending ||
      timer_irq_o || sci_irq_o);

    sci_tx_o = (trcsr_control[1] && tx_active) ? tx_shift[0] : 1'b1;
    sci_clock_o = sci_clock_level;
    port1_o = port1_latch;
    port1_oe_o = port1_ddr;
    port2_o = port2_latch;
    port2_oe_o = port2_ddr;
    port3_o = port3_latch;
    port3_oe_o = MODE7 ? port3_ddr : 8'h00;
    port4_o = port4_latch;
    port4_oe_o = MODE7 ? port4_ddr : 8'h00;
    os3_n_o = !(MODE7 && port3_access &&
      (core_write == port3_output_strobe_select));
    port2_o[1] = output_level;
    if (rmcr[3]) begin
      port2_oe_o[2] = !rmcr[2];
      port2_o[2] = sci_clock_level;
    end
    if (trcsr_control[3]) port2_oe_o[3] = 1'b0;
    if (trcsr_control[1]) begin
      port2_oe_o[4] = 1'b1;
      port2_o[4] = sci_tx_o;
    end
  end

  /* verilator lint_off PINCONNECTEMPTY */
  m6800_core #(.ARCHITECTURE(HITACHI_CPU ? 2'd2 : 2'd1)) cpu (
    .clk_i(clk_i),
    .reset_n_i(reset_n_i),
    .clock_enable_i(clock_enable_i),
    .bus_ready_i(1'b1),
    .irq_n_i(irq_n),
    .irq_vector_i(core_irq_vector),
    .nmi_n_i(nmi_n_i),
    .instruction_address_error_i(instruction_address_error),
    .data_i(core_data_in),
    .address_o(core_address),
    .data_o(core_data_out),
    .write_o(core_write),
    .bus_valid_o(core_bus_valid),
    .opcode_fetch_o(core_opcode_fetch),
    .retire_o(retire_o),
    .illegal_o(illegal_o),
    .undefined_o(undefined_o),
    .waiting_o(waiting_o),
    .sleeping_o(sleeping_o),
    .interrupt_ack_o(interrupt_ack_o),
    .interrupt_vector_o(),
    .debug_a_o(debug_a_o),
    .debug_b_o(debug_b_o),
    .debug_x_o(debug_x_o),
    .debug_sp_o(debug_sp_o),
    .debug_pc_o(debug_pc_o),
    .debug_ccr_o(debug_ccr_o),
    .debug_opcode_o(debug_opcode_o),
    .debug_instruction_cycles_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  assign external_address_o = core_address;
  assign program_address_o = core_address;
  assign program_read_o = internal_program_select && !core_write;
  assign external_data_o = core_data_out;
  assign external_write_o = core_write;
  assign external_bus_valid_o = core_bus_valid && !internal_register_select &&
    !internal_ram_select && !internal_program_select && !unusable_select;
  assign external_opcode_fetch_o = core_opcode_fetch && external_bus_valid_o;
  assign opcode_fetch_o = core_opcode_fetch;
  assign debug_address_o = core_address;
  assign debug_timer_o = timer_counter;
  assign debug_output_compare_o = output_compare;
  assign debug_input_capture_o = input_capture;
  assign debug_tcsr_o = tcsr;
  assign debug_trcsr_o = {rdrf, orfe, tdre, trcsr_control};
  assign debug_receive_data_o = receive_data;
endmodule
