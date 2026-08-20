// SPDX-License-Identifier: MIT
// MC6801-lineage common digital MCU integration.
//
// Register, timer, SCI, and interrupt behavior is derived from Motorola
// MC6801 Reference Manual MC6801RM(AD2), chapters 2, 3, 5, 6, and 7. One
// clk_i/clock_enable_i step represents one complete E-cycle. Physical Port 3
// address/data multiplexing and the E/AS waveform belong in a pin wrapper.
// HD6301_MODE7 enables the separately documented Hitachi single-chip decode,
// Port 3/4 registers, handshake, and internal program-memory interface. The
// RAM and address-error parameters distinguish the V1 and 63701V0 maps.
// HITACHI_NEW_MODES selects the V1/R meanings of Mode 1 and Mode 4, which are
// not interchangeable with the same-numbered Motorola MC6801 configurations.
module mc6801_mcu #(
  parameter logic [2:0] OPERATING_MODE = 3'd2,
  parameter logic       HITACHI_CPU = 1'b0,
  parameter logic       HD6301_MODE7 = 1'b0,
  parameter logic       HITACHI_NEW_MODES = 1'b0,
  parameter logic       SCI_TRANSFER_FRAMING_ERROR = 1'b1,
  parameter logic       SCI_BIPHASE_SUPPORTED = 1'b1,
  parameter logic       TIMER_COUNTER_DOUBLE_WRITE = 1'b0,
  parameter logic       TIMER_OVERFLOW_AT_ZERO = 1'b0,
  parameter logic       PORT_DDR_ASYNC_RESET = 1'b1,
  parameter logic [15:0] INTERNAL_RAM_START = 16'h0080,
  parameter logic [15:0] INTERNAL_RAM_BYTES = 16'd128,
  parameter logic [15:0] INTERNAL_PROGRAM_START = 16'hf800,
  parameter logic [15:0] INTERNAL_PROGRAM_BYTES = 16'd2048,
  parameter logic [15:0] MODE7_ADDRESS_TRAP_LOW_END = 16'h007f
) (
  input  logic        clk_i,
  input  logic        reset_n_i,
  input  logic        standby_reset_n_i,
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
  localparam logic HITACHI_MODE7 = HITACHI_CPU && HD6301_MODE7 &&
    (OPERATING_MODE == 3'd7);
  localparam logic [15:0] VECTOR_IRQ1 = 16'hfff8;
  localparam logic [15:0] VECTOR_INPUT_CAPTURE = 16'hfff6;
  localparam logic [15:0] VECTOR_OUTPUT_COMPARE = 16'hfff4;
  localparam logic [15:0] VECTOR_TIMER_OVERFLOW = 16'hfff2;
  localparam logic [15:0] VECTOR_SCI = 16'hfff0;
  localparam logic [15:0] INTERNAL_RAM_END =
    INTERNAL_RAM_START + INTERNAL_RAM_BYTES - 1;

  // The shared shell reserves the largest supported page. Decode limits the
  // physical window to 128 bytes on MC6801/HD6301V1 or 192 on HD63701V0.
  logic [7:0] ram [0:255];
  logic [7:0] port1_latch;
  logic [4:0] port2_latch;
  logic [7:0] port3_latch;
  logic [7:0] port4_latch;
  logic [7:0] port1_ddr;
  logic [4:0] port2_ddr;
  logic [7:0] port3_ddr;
  logic [7:0] port4_ddr;
  logic [7:0] port1_ddr_next;
  logic [4:0] port2_ddr_next;
  logic [7:0] port3_ddr_next;
  logic [7:0] port4_ddr_next;
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
  logic tx_biphase_level;
  logic rx_previous;
  logic rx_busy;
  logic [12:0] rx_countdown;
  logic [3:0] rx_bit_index;
  logic [7:0] rx_shift;
  logic biphase_transition_seen;
  logic [12:0] biphase_interval;
  logic biphase_short_pending;
  logic [1:0] biphase_idle_intervals;
  logic [3:0] wake_mark_count;
  logic sci_clock_previous;
  logic [2:0] sci_external_subcycles;

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
  logic [7:0] internal_ram_index;
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
  logic sci_half_tick;
  logic [12:0] sci_divisor;
  logic sci_nrz_format;
  logic sci_biphase_format;
  logic sci_external_nrz;
  logic sci_external_clock_rise;
  logic sci_receive_count_event;
  logic [12:0] sci_receive_half_interval;
  logic [12:0] sci_receive_bit_interval;
  logic sci_receive_transition;
  logic [12:0] sci_biphase_elapsed;
  logic [12:0] sci_biphase_threshold;
  logic sci_biphase_short_interval;
  logic sci_biphase_decoded_valid;
  logic sci_biphase_decoded_bit;
  logic sci_tx_current_bit;
  logic sci_clock_level;
  logic timer_counter_write;
  logic capture_high_read;
  logic [7:0] timer_counter_write_high;
  logic timer_counter_write_armed;
  logic is3_falling_edge;
  logic port3_access;
  logic instruction_address_error;
  logic port3_irq;
  logic device_reset_n;
  logic [2:0] active_mode;
  logic hitachi_mode1_nonmultiplexed;
  logic hitachi_mode4_expanded;
  logic single_chip_ports;
  logic port4_registers;
  logic mode0_reset_vector_pending;
  logic mode0_reset_vector_select;
  logic program_address_select;
  logic mode5_external_select;

  assign device_reset_n = reset_n_i && standby_reset_n_i;
  assign hitachi_mode1_nonmultiplexed = HITACHI_NEW_MODES &&
    (active_mode == 3'd1);
  assign hitachi_mode4_expanded = HITACHI_NEW_MODES &&
    (active_mode == 3'd4);
  assign single_chip_ports =
    ((active_mode == 3'd4) && !hitachi_mode4_expanded) ||
    (active_mode == 3'd7);
  assign port4_registers = active_mode[2] && !hitachi_mode4_expanded;

  // The mode is hardware-latched at reset. Mode 4 has the documented single
  // write-only escape to Mode 5; no other software mode transition exists.
  always_ff @(posedge clk_i or negedge device_reset_n) begin
    if (!device_reset_n) begin
      active_mode <= OPERATING_MODE;
    end else if (clock_enable_i && internal_write &&
                 (core_address == 16'h0003) && (active_mode == 3'd4) &&
                 !hitachi_mode4_expanded &&
                 core_data_out[5]) begin
      active_mode <= 3'd5;
    end
  end

  // Mode 0 exposes only the two reset-vector reads externally. Later reads of
  // the same addresses select mask ROM, including software inspection of the
  // internal interrupt vectors.
  always_ff @(posedge clk_i or negedge device_reset_n) begin
    if (!device_reset_n) begin
      mode0_reset_vector_pending <= 1'b1;
    end else if (clock_enable_i && (active_mode == 3'd0) && core_bus_valid &&
                 !core_write && (core_address == 16'hffff)) begin
      mode0_reset_vector_pending <= 1'b0;
    end
  end

  function automatic logic register_is_internal(input logic [15:0] address_value);
    begin
      if (hitachi_mode1_nonmultiplexed &&
          ((address_value == 16'h0000) || (address_value == 16'h0002))) begin
        register_is_internal = 1'b0;
      end else begin
        case (address_value)
          16'h0000, 16'h0001, 16'h0002, 16'h0003,
          16'h0008, 16'h0009, 16'h000a, 16'h000b,
          16'h000c, 16'h000d, 16'h000e,
          16'h0010, 16'h0011, 16'h0012, 16'h0013,
          16'h0014: register_is_internal = 1'b1;
          16'h0004, 16'h0006, 16'h000f:
            register_is_internal = single_chip_ports;
          16'h0005, 16'h0007: register_is_internal = port4_registers;
          default: register_is_internal = 1'b0;
        endcase
      end
    end
  endfunction

  function automatic logic program_address_in_range(input logic [15:0] address_value);
    logic [16:0] program_offset;
    begin
      program_offset = {1'b0, address_value} - {1'b0, INTERNAL_PROGRAM_START};
      program_address_in_range =
        program_offset < {1'b0, INTERNAL_PROGRAM_BYTES};
    end
  endfunction

  always_comb begin
    port1_ddr_next = port1_ddr;
    port2_ddr_next = port2_ddr;
    port3_ddr_next = port3_ddr;
    port4_ddr_next = port4_ddr;
    if (internal_write) begin
      case (core_address)
        16'h0000: port1_ddr_next = core_data_out;
        16'h0001: begin
          port2_ddr_next[1:0] = core_data_out[1:0];
          if (!rmcr[3]) port2_ddr_next[2] = core_data_out[2];
          if (!trcsr_control[3]) port2_ddr_next[3] = core_data_out[3];
          if (!trcsr_control[1]) port2_ddr_next[4] = core_data_out[4];
        end
        16'h0004: if (single_chip_ports) port3_ddr_next = core_data_out;
        16'h0005: if (port4_registers) port4_ddr_next = core_data_out;
        16'h0010: if (core_data_out[3]) begin
          port2_ddr_next[2] = !core_data_out[2];
        end
        16'h0011: begin
          if (core_data_out[3]) port2_ddr_next[3] = 1'b0;
          if (core_data_out[1]) port2_ddr_next[4] = 1'b1;
        end
        default: ;
      endcase
    end
  end

  // HD6301-family manuals deliberately mix E-synchronous DDR clearing with
  // asynchronous reset of other device state. This local warning exception
  // covers that manufacturer-defined reset topology only.
  /* verilator lint_off SYNCASYNCNET */
  generate
    if (PORT_DDR_ASYNC_RESET) begin : generate_async_ddr_reset
      always_ff @(posedge clk_i or negedge device_reset_n) begin
        if (!device_reset_n) begin
          port1_ddr <= 8'h00;
          port2_ddr <= 5'h00;
          port3_ddr <= 8'h00;
          port4_ddr <= 8'h00;
        end else if (clock_enable_i) begin
          port1_ddr <= port1_ddr_next;
          port2_ddr <= port2_ddr_next;
          port3_ddr <= port3_ddr_next;
          port4_ddr <= port4_ddr_next;
        end
      end
    end else begin : generate_synchronous_ddr_reset
      always_ff @(posedge clk_i) begin
        if (!device_reset_n) begin
          port1_ddr <= 8'h00;
          port2_ddr <= 5'h00;
          port3_ddr <= 8'h00;
          port4_ddr <= 8'h00;
        end else if (clock_enable_i) begin
          port1_ddr <= port1_ddr_next;
          port2_ddr <= port2_ddr_next;
          port3_ddr <= port3_ddr_next;
          port4_ddr <= port4_ddr_next;
        end
      end
    end
  endgenerate
  /* verilator lint_on SYNCASYNCNET */

  always_comb begin
    internal_register_select = core_bus_valid && register_is_internal(core_address);
    internal_ram_index = ((active_mode == 3'd4) && !hitachi_mode4_expanded) ?
      {1'b0, core_address[6:0]} :
      core_address[7:0] - INTERNAL_RAM_START[7:0];
    internal_ram_select = core_bus_valid && rame && (active_mode != 3'd3) &&
      (((active_mode == 3'd4) && !hitachi_mode4_expanded && core_address[7]) ||
       (((active_mode != 3'd4) || hitachi_mode4_expanded) &&
        (core_address >= INTERNAL_RAM_START) &&
        (core_address <= INTERNAL_RAM_END)));

    program_address_select = 1'b0;
    if (HITACHI_MODE7) begin
      program_address_select = program_address_in_range(core_address);
    end else begin
      case (active_mode)
        3'd0, 3'd5, 3'd7:
          program_address_select = program_address_in_range(core_address);
        3'd1: program_address_select = !hitachi_mode1_nonmultiplexed &&
          program_address_in_range(core_address) && (core_address < 16'hfff0);
        3'd6: program_address_select = program_address_in_range(core_address);
        default: program_address_select = 1'b0;
      endcase
    end
    mode0_reset_vector_select = (active_mode == 3'd0) &&
      mode0_reset_vector_pending && (core_address >= 16'hfffe);
    internal_program_select = core_bus_valid && program_address_select &&
      !mode0_reset_vector_select;
    unusable_select = core_bus_valid && single_chip_ports &&
      !internal_register_select && !internal_ram_select &&
      !internal_program_select;
    mode5_external_select = core_bus_valid && (active_mode == 3'd5) &&
      (core_address >= 16'h0100) && (core_address <= 16'h01ff);
    internal_read = clock_enable_i && internal_register_select && !core_write;
    internal_write = clock_enable_i && internal_register_select && core_write;
    timer_counter_write = internal_write &&
      ((core_address == 16'h0009) ||
       (TIMER_COUNTER_DOUBLE_WRITE && timer_counter_write_armed &&
        (core_address == 16'h000a)));
    capture_high_read = internal_read && (core_address == 16'h000d);
    port3_access = clock_enable_i && internal_register_select &&
      (core_address == 16'h0006);
    instruction_address_error = HITACHI_MODE7 && core_opcode_fetch &&
      ((core_address <= MODE7_ADDRESS_TRAP_LOW_END) ||
       ((core_address >= 16'h0100) && (core_address <= 16'hefff)));

    core_data_in = external_data_i;
    if (internal_program_select) begin
      core_data_in = program_data_i;
    end else if (unusable_select) begin
      core_data_in = 8'hff;
    end else if (internal_ram_select) begin
      core_data_in = ram[internal_ram_index];
    end else if (internal_register_select) begin
      case (core_address)
        16'h0000, 16'h0001: core_data_in = 8'hff;
        16'h0002: core_data_in = port1_i;
        16'h0003: core_data_in = {active_mode, port2_i};
        16'h0004: core_data_in = port3_latch_valid ? port3_input_latch : port3_i;
        16'h0005: core_data_in = 8'hff;
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
    timer_overflow_event = !timer_counter_write &&
      (TIMER_OVERFLOW_AT_ZERO ? (timer_next == 16'h0000) :
       (timer_next == 16'hffff));
    is3_falling_edge = is3_sync2 && !is3_sync1;

    case (rmcr[1:0])
      2'b00: begin
        sci_divisor = 13'd16;
        sci_bit_tick = (timer_next[3:0] == 4'h0);
        sci_half_tick = (timer_next[2:0] == 3'h0);
        sci_clock_level = timer_counter[3];
      end
      2'b01: begin
        sci_divisor = 13'd128;
        sci_bit_tick = (timer_next[6:0] == 7'h00);
        sci_half_tick = (timer_next[5:0] == 6'h00);
        sci_clock_level = timer_counter[6];
      end
      2'b10: begin
        sci_divisor = 13'd1024;
        sci_bit_tick = (timer_next[9:0] == 10'h000);
        sci_half_tick = (timer_next[8:0] == 9'h000);
        sci_clock_level = timer_counter[9];
      end
      default: begin
        sci_divisor = 13'd4096;
        sci_bit_tick = (timer_next[11:0] == 12'h000);
        sci_half_tick = (timer_next[10:0] == 11'h000);
        sci_clock_level = timer_counter[11];
      end
    endcase
    sci_nrz_format = rmcr[3:2] != 2'b00;
    sci_biphase_format = SCI_BIPHASE_SUPPORTED && (rmcr[3:2] == 2'b00);
    sci_external_nrz = rmcr[3:2] == 2'b11;
    sci_external_clock_rise = !sci_clock_previous && port2_i[2];
    if (sci_external_nrz) begin
      sci_bit_tick = sci_external_clock_rise &&
        (sci_external_subcycles == 3'd7);
      sci_receive_count_event = sci_external_clock_rise;
      sci_receive_half_interval = 13'd4;
      sci_receive_bit_interval = 13'd8;
    end else begin
      sci_receive_count_event = 1'b1;
      sci_receive_half_interval = sci_divisor >> 1;
      sci_receive_bit_interval = sci_divisor;
    end
    sci_receive_transition = rx_previous != port2_i[3];
    sci_biphase_elapsed = (biphase_interval == 13'h1fff) ?
      13'h1fff : biphase_interval + 13'd1;
    sci_biphase_threshold = sci_divisor - (sci_divisor >> 2);
    sci_biphase_short_interval = sci_biphase_elapsed < sci_biphase_threshold;
    sci_biphase_decoded_valid = biphase_transition_seen &&
      sci_receive_transition &&
      (!sci_biphase_short_interval || !biphase_short_pending);
    sci_biphase_decoded_bit = sci_biphase_short_interval;
    sci_tx_current_bit = (tx_bits_remaining != 4'd0) ? tx_shift[0] : 1'b1;
  end

  always_ff @(posedge clk_i or negedge device_reset_n) begin
    if (!device_reset_n) begin
      port1_latch <= 8'h00;
      port2_latch <= 5'h00;
      port3_latch <= 8'h00;
      port4_latch <= 8'h00;
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
    end else if (clock_enable_i) begin
      is3_sync1 <= is3_n_i;
      is3_sync2 <= is3_sync1;
      if (!standby_power_ok_i) begin
        rame <= 1'b0;
      end
      if (internal_write) begin
        case (core_address)
          16'h0002: port1_latch <= core_data_out;
          16'h0003: begin
            port2_latch[0] <= core_data_out[0];
            if (!rmcr[3]) port2_latch[2] <= core_data_out[2];
            if (!trcsr_control[3]) port2_latch[3] <= core_data_out[3];
            if (!trcsr_control[1]) port2_latch[4] <= core_data_out[4];
          end
          16'h0006: if (single_chip_ports) port3_latch <= core_data_out;
          16'h0007: if (single_chip_ports) port4_latch <= core_data_out;
          16'h000f: if (single_chip_ports) begin
            port3_is3_enable <= core_data_out[6];
            port3_output_strobe_select <= core_data_out[4];
            port3_latch_enable <= core_data_out[3];
          end
          16'h0014: begin
            rame <= core_data_out[6];
          end
          default: ;
        endcase
      end

      if (single_chip_ports && internal_read && (core_address == 16'h000f)) begin
        port3_clear_armed <= port3_is3_flag;
      end
      if (single_chip_ports && port3_access) begin
        if (!core_write) port3_latch_valid <= 1'b0;
        if (port3_clear_armed) begin
          port3_is3_flag <= 1'b0;
          port3_clear_armed <= 1'b0;
        end
      end
      // A new IS3 edge wins over a coincident software clear.
      if (single_chip_ports && is3_falling_edge) begin
        port3_is3_flag <= 1'b1;
        if (port3_latch_enable && !port3_latch_valid) begin
          port3_input_latch <= port3_i;
          port3_latch_valid <= 1'b1;
        end
      end
    end
  end

  // STBY_PWR belongs to the retained supply domain. The normalized FPGA
  // boundary initializes it deterministically on external reset, preserves it
  // through a standby reset while supply remains valid, and clears it when the
  // modeled retention supply is lost.
  always_ff @(posedge clk_i or negedge reset_n_i) begin
    if (!reset_n_i) begin
      standby_power <= 1'b0;
    end else if (clock_enable_i) begin
      if (!standby_power_ok_i) begin
        standby_power <= 1'b0;
      end else if (standby_reset_n_i && internal_write &&
                   (core_address == 16'h0014)) begin
        standby_power <= core_data_out[7];
      end
    end
  end

  // The reference manual does not define RAM contents after reset. Keeping
  // reset out of the write process preserves inference-friendly device RAM.
  always_ff @(posedge clk_i) begin
    if (clock_enable_i && core_bus_valid && core_write && internal_ram_select) begin
      ram[internal_ram_index] <= core_data_out;
    end
  end

  always_ff @(posedge clk_i or negedge device_reset_n) begin
    if (!device_reset_n) begin
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
      timer_counter_write_high <= 8'h00;
      timer_counter_write_armed <= 1'b0;
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
          16'h0009: begin
            timer_counter <= 16'hfff8;
            if (TIMER_COUNTER_DOUBLE_WRITE) begin
              timer_counter_write_high <= core_data_out;
              timer_counter_write_armed <= 1'b1;
            end
          end
          16'h000a: if (TIMER_COUNTER_DOUBLE_WRITE && timer_counter_write_armed) begin
            timer_counter <= {timer_counter_write_high, core_data_out};
            timer_counter_write_armed <= 1'b0;
          end
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

  always_ff @(posedge clk_i or negedge device_reset_n) begin
    if (!device_reset_n) begin
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
      tx_biphase_level <= 1'b1;
      rx_previous <= 1'b1;
      rx_busy <= 1'b0;
      rx_countdown <= 13'd0;
      rx_bit_index <= 4'd0;
      rx_shift <= 8'h00;
      biphase_transition_seen <= 1'b0;
      biphase_interval <= 13'd0;
      biphase_short_pending <= 1'b0;
      biphase_idle_intervals <= 2'd0;
      wake_mark_count <= 4'd0;
      sci_clock_previous <= 1'b1;
      sci_external_subcycles <= 3'd0;
    end else if (clock_enable_i) begin
      rx_previous <= port2_i[3];
      sci_clock_previous <= port2_i[2];
      if (sci_external_nrz && sci_external_clock_rise) begin
        sci_external_subcycles <= sci_external_subcycles + 3'd1;
      end else if (!sci_external_nrz) begin
        sci_external_subcycles <= 3'd0;
      end
      if (!trcsr_control[1]) begin
        tx_biphase_level <= 1'b1;
      end else if (sci_biphase_format && sci_half_tick &&
                   !(internal_write && (core_address == 16'h0010)) &&
                   !(internal_write && (core_address == 16'h0011) &&
                     (core_data_out[1] != trcsr_control[1])) &&
                   (sci_bit_tick || sci_tx_current_bit)) begin
        tx_biphase_level <= !tx_biphase_level;
      end

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
          16'h0010: begin
            rmcr <= core_data_out[3:0];
            sci_external_subcycles <= 3'd0;
            tx_biphase_level <= 1'b1;
            biphase_transition_seen <= 1'b0;
            biphase_interval <= 13'd0;
            biphase_short_pending <= 1'b0;
            biphase_idle_intervals <= 2'd0;
          end
          16'h0011: begin
            trcsr_control <= core_data_out[4:0];
            if (!trcsr_control[1] && core_data_out[1]) begin
              tx_preamble_remaining <= 4'd9;
              tx_active <= 1'b0;
              tx_biphase_level <= 1'b1;
            end
            if (!core_data_out[1]) begin
              tx_active <= 1'b0;
              tx_bits_remaining <= 4'd0;
              tx_biphase_level <= 1'b1;
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

      if (sci_bit_tick && sci_nrz_format && trcsr_control[0]) begin
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

      if (sci_bit_tick && (sci_nrz_format || sci_biphase_format) &&
          trcsr_control[1]) begin
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

      if (sci_biphase_format) begin
        if (!(internal_write && (core_address == 16'h0010)) &&
            !(internal_write && (core_address == 16'h0011) &&
              (((core_data_out[3:0] ^ trcsr_control[3:0]) & 4'h9) != 4'h0))) begin
          if (!trcsr_control[3] && !trcsr_control[0]) begin
            rx_busy <= 1'b0;
            biphase_transition_seen <= 1'b0;
            biphase_interval <= 13'd0;
            biphase_short_pending <= 1'b0;
            biphase_idle_intervals <= 2'd0;
          end else begin
            if (sci_receive_transition) begin
              biphase_interval <= 13'd0;
              if (!biphase_transition_seen) begin
                biphase_transition_seen <= 1'b1;
              end else if (sci_biphase_short_interval) begin
                if (biphase_idle_intervals != 2'd2)
                  biphase_idle_intervals <= biphase_idle_intervals + 2'd1;
                biphase_short_pending <= !biphase_short_pending;
              end else begin
                biphase_idle_intervals <= 2'd0;
                biphase_short_pending <= 1'b0;
              end
            end else begin
              biphase_interval <= sci_biphase_elapsed;
            end

            if (sci_biphase_decoded_valid) begin
              if (trcsr_control[0]) begin
                rx_busy <= 1'b0;
                if (sci_biphase_decoded_bit) begin
                  if (wake_mark_count == 4'd9) begin
                    trcsr_control[0] <= 1'b0;
                    wake_mark_count <= 4'd0;
                  end else begin
                    wake_mark_count <= wake_mark_count + 4'd1;
                  end
                end else begin
                  wake_mark_count <= 4'd0;
                end
              end else if (!trcsr_control[3]) begin
                rx_busy <= 1'b0;
              end else if (!rx_busy) begin
                if (!sci_biphase_decoded_bit &&
                    (biphase_idle_intervals == 2'd2)) begin
                  rx_busy <= 1'b1;
                  rx_bit_index <= 4'd1;
                  rx_shift <= 8'h00;
                end
              end else if (rx_bit_index <= 4'd8) begin
                rx_shift[rx_bit_index[2:0] - 3'd1] <= sci_biphase_decoded_bit;
                rx_bit_index <= rx_bit_index + 4'd1;
              end else begin
                rx_busy <= 1'b0;
                biphase_idle_intervals <= sci_biphase_decoded_bit ? 2'd1 : 2'd2;
                if (!sci_biphase_decoded_bit) begin
                  if (SCI_TRANSFER_FRAMING_ERROR && !rdrf && !orfe)
                    receive_data <= rx_shift;
                  orfe <= 1'b1;
                end else if (rdrf || orfe) begin
                  orfe <= 1'b1;
                end else begin
                  receive_data <= rx_shift;
                  rdrf <= 1'b1;
                end
              end
            end
          end
        end
      end else if (!sci_nrz_format || !trcsr_control[3] || trcsr_control[0]) begin
        rx_busy <= 1'b0;
      end else if (!rx_busy) begin
        if (rx_previous && !port2_i[3]) begin
          rx_busy <= 1'b1;
          rx_countdown <= sci_receive_half_interval;
          rx_bit_index <= 4'd0;
        end
      end else if (sci_receive_count_event && (rx_countdown > 13'd1)) begin
        rx_countdown <= rx_countdown - 13'd1;
      end else if (sci_receive_count_event && (rx_bit_index == 4'd0)) begin
        if (port2_i[3]) begin
          rx_busy <= 1'b0;
        end else begin
          rx_bit_index <= 4'd1;
          rx_countdown <= sci_receive_bit_interval;
        end
      end else if (sci_receive_count_event && (rx_bit_index <= 4'd8)) begin
        rx_shift[rx_bit_index[2:0] - 3'd1] <= port2_i[3];
        rx_bit_index <= rx_bit_index + 4'd1;
        rx_countdown <= sci_receive_bit_interval;
      end else if (sci_receive_count_event) begin
        rx_busy <= 1'b0;
        if (!port2_i[3]) begin
          if (SCI_TRANSFER_FRAMING_ERROR && !rdrf && !orfe) begin
            receive_data <= rx_shift;
          end
          orfe <= 1'b1;
          // A following zero is itself the next start bit (continuous BREAK).
          rx_busy <= 1'b1;
          rx_bit_index <= 4'd1;
          rx_countdown <= sci_receive_bit_interval;
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
  always_ff @(posedge clk_i or negedge device_reset_n) begin
    if (!device_reset_n) begin
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
    port3_irq = single_chip_ports && port3_is3_flag && port3_is3_enable;

    if (irq1_pending || !irq1_n_i || port3_irq) core_irq_vector = VECTOR_IRQ1;
    else if (tcsr[7] && tcsr[4]) core_irq_vector = VECTOR_INPUT_CAPTURE;
    else if (tcsr[6] && tcsr[3]) core_irq_vector = VECTOR_OUTPUT_COMPARE;
    else if (tcsr[5] && tcsr[2]) core_irq_vector = VECTOR_TIMER_OVERFLOW;
    else core_irq_vector = VECTOR_SCI;
    irq_n = !(irq1_pending || !irq1_n_i || port3_irq || irq2_pending ||
      timer_irq_o || sci_irq_o);

    if (!trcsr_control[1]) begin
      sci_tx_o = 1'b1;
    end else if (sci_biphase_format) begin
      sci_tx_o = tx_biphase_level;
    end else if (sci_nrz_format) begin
      sci_tx_o = tx_active ? tx_shift[0] : 1'b1;
    end else begin
      sci_tx_o = 1'b1;
    end
    sci_clock_o = sci_clock_level;
    port1_o = port1_latch;
    port1_oe_o = port1_ddr;
    if (hitachi_mode1_nonmultiplexed && device_reset_n) begin
      port1_o = core_address[7:0];
      port1_oe_o = 8'hff;
    end
    port2_o = port2_latch;
    port2_oe_o = port2_ddr;
    port3_o = port3_latch;
    port3_oe_o = 8'h00;
    if (single_chip_ports) begin
      port3_oe_o = port3_ddr;
    end else if (device_reset_n && core_bus_valid &&
                 (core_write || ((active_mode == 3'd0) &&
                  (internal_register_select || internal_ram_select ||
                   internal_program_select)))) begin
      port3_o = core_write ? core_data_out : core_data_in;
      port3_oe_o = 8'hff;
    end

    port4_o = port4_latch;
    port4_oe_o = 8'h00;
    if (single_chip_ports) begin
      port4_oe_o = port4_ddr;
    end else if (active_mode == 3'd5) begin
      port4_o = core_address[7:0];
      port4_oe_o = port4_ddr;
    end else if (active_mode == 3'd6) begin
      port4_o = core_address[15:8];
      port4_oe_o = port4_ddr;
    end else if ((!active_mode[2] || hitachi_mode4_expanded) && device_reset_n) begin
      port4_o = core_address[15:8];
      port4_oe_o = 8'hff;
    end
    os3_n_o = !(single_chip_ports && port3_access &&
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
    .reset_n_i(device_reset_n),
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
  assign external_bus_valid_o = (active_mode == 3'd5) ? mode5_external_select :
    (core_bus_valid && !single_chip_ports && !internal_register_select &&
     !internal_ram_select && !internal_program_select && !unusable_select);
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
