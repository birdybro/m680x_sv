// SPDX-License-Identifier: MIT
module tb_mc6801_bus_wrapper;
  import mc6801_peripheral_bus_stub_pkg::*;

  logic phase_clk;
  logic phase_reset_n;
  logic reset_n;
  logic clock_enable;
  logic [7:0] port3_in;
  logic [1:0] phase [0:7];
  logic e [0:7];
  logic [7:0] port3 [0:7];
  logic [7:0] port3_oe [0:7];
  logic [7:0] port4 [0:7];
  logic [7:0] port4_oe [0:7];
  logic sc1 [0:7];
  logic sc1_oe [0:7];
  logic sc2 [0:7];
  logic [2:0] active_mode [0:7];
  integer checks;

  generate
    for (genvar mode_index = 0; mode_index < 8; mode_index = mode_index + 1) begin : devices
      /* verilator lint_off PINCONNECTEMPTY */
      mc6801_bus_wrapper #(.OPERATING_MODE(mode_index)) device (
        .phase_clk_i(phase_clk), .phase_reset_n_i(phase_reset_n),
        .reset_n_i(reset_n), .clock_enable_i(clock_enable),
        .nmi_n_i(1'b1), .irq1_n_i(1'b1), .program_data_i(8'ha6),
        .program_address_o(), .program_read_o(), .port1_i(8'h3c),
        .port1_o(), .port1_oe_o(), .port2_i(5'h15), .port2_o(),
        .port2_oe_o(), .port3_i(port3_in), .port3_o(port3[mode_index]),
        .port3_oe_o(port3_oe[mode_index]), .port4_i(8'h96),
        .port4_o(port4[mode_index]), .port4_oe_o(port4_oe[mode_index]),
        .sc1_i(1'b1), .sc1_o(sc1[mode_index]),
        .sc1_oe_o(sc1_oe[mode_index]), .sc2_o(sc2[mode_index]),
        .e_o(e[mode_index]), .bus_phase_o(phase[mode_index]),
        .opcode_fetch_o(), .retire_o(), .illegal_o(), .undefined_o(),
        .waiting_o(), .interrupt_ack_o(),
        .operating_mode_o(active_mode[mode_index]), .debug_address_o(),
        .debug_pc_o(), .debug_sp_o(), .debug_a_o(), .debug_b_o(),
        .debug_x_o(), .debug_ccr_o()
      );
      /* verilator lint_on PINCONNECTEMPTY */
    end
  endgenerate

  always #5 phase_clk <= ~phase_clk;

  task automatic check_value(input logic condition_value, input string label_value);
    begin
      if (!condition_value) $fatal(1, "%0s", label_value);
      checks = checks + 1;
    end
  endtask

  task automatic advance_phase(input logic [1:0] expected_phase);
    begin
      @(posedge phase_clk);
      #1;
      check_value(phase[2] == expected_phase, "phase sequence");
    end
  endtask

  task automatic set_transaction(
    input logic [15:0] address_value,
    input logic write_value,
    input logic [7:0] data_value
  );
    begin
      stub_address = address_value;
      stub_write = write_value;
      stub_data = data_value;
      stub_valid = 1'b1;
      #1;
    end
  endtask

  task automatic check_all_mode_roles(input logic [1:0] expected_phase);
    integer mode_index;
    begin
      for (mode_index = 0; mode_index < 8; mode_index = mode_index + 1) begin
        check_value(phase[mode_index] == expected_phase,
                    "all modes share the bus phase");
        check_value(e[mode_index] == expected_phase[1],
                    "all modes share the E waveform");
        check_value(sc1_oe[mode_index] ==
                    ((mode_index != 4) && (mode_index != 7)),
                    "SC1 output role follows operating mode");
        if ((mode_index <= 3) || (mode_index == 6)) begin
          check_value(sc1[mode_index] == (expected_phase == 2'd0),
                      "multiplexed modes share the AS waveform");
          if (expected_phase == 2'd0) begin
            check_value((port3[mode_index] == 8'h5a) &&
                        (port3_oe[mode_index] == 8'hff),
                        "multiplexed modes drive low address before AS closes");
          end else begin
            check_value(port3_oe[mode_index] == 8'h00,
                        "multiplexed modes release Port 3 for an external read");
          end
        end
      end
    end
  endtask

  task automatic finish_cycle;
    begin
      advance_phase(2'd1);
      advance_phase(2'd2);
      advance_phase(2'd3);
      advance_phase(2'd0);
    end
  endtask

  initial begin
    phase_clk = 1'b0;
    phase_reset_n = 1'b0;
    reset_n = 1'b0;
    clock_enable = 1'b1;
    port3_in = 8'h5c;
    stub_address = 16'ha55a;
    stub_data = 8'hc7;
    stub_write = 1'b0;
    stub_valid = 1'b1;
    stub_opcode_fetch = 1'b0;
    stub_interrupt_mask = 1'b1;
    stub_sleeping = 1'b0;
    stub_waiting = 1'b0;
    stub_sp = 16'h0000;
    checks = 0;

    #1;
    check_value(phase[2] == 2'd0 && !e[2], "phase reset starts at address phase");
    check_value(port3_oe[2] == 8'h00, "device reset releases multiplexed Port 3");
    check_value(sc1[2] && sc2[2], "device reset holds AS and R/W high");

    // Historical RESET does not stop E; only the integration phase reset does.
    phase_reset_n = 1'b1;
    advance_phase(2'd1);
    check_value(!e[2] && sc1[2] && sc2[2], "reset phase 1 controls");
    advance_phase(2'd2);
    check_value(e[2] && sc1[2] && sc2[2], "E runs high during device reset");
    advance_phase(2'd3);
    check_value(e[2] && port3_oe[2] == 8'h00, "reset E-high bus release");
    advance_phase(2'd0);
    reset_n = 1'b1;
    #1;

    // Expanded multiplexed address, latch-close, and read-data phases.
    set_transaction(16'ha55a, 1'b0, 8'h00);
    check_all_mode_roles(2'd0);
    check_value(!e[2] && sc1[2] && sc1_oe[2] && sc2[2], "mode2 address controls");
    check_value(port3[2] == 8'h5a && port3_oe[2] == 8'hff,
           "mode2 low address on Port 3");
    check_value(port4[2] == 8'ha5 && port4_oe[2] == 8'hff,
           "mode2 high address on Port 4");
    advance_phase(2'd1);
    check_all_mode_roles(2'd1);
    check_value(!e[2] && !sc1[2] && port3_oe[2] == 8'h00,
           "mode2 closes AS before E and releases Port 3");
    advance_phase(2'd2);
    check_all_mode_roles(2'd2);
    check_value(e[2] && port3_oe[2] == 8'h00, "mode2 read E-rise release");
    advance_phase(2'd3);
    check_all_mode_roles(2'd3);
    check_value(e[2] && port3_oe[2] == 8'h00, "mode2 read E-fall sampling phase");
    advance_phase(2'd0);

    // A write turns R/W low for the cycle and drives data only while E is high.
    set_transaction(16'h1234, 1'b1, 8'hc7);
    check_value(!sc2[2] && port3[2] == 8'h34 && port3_oe[2] == 8'hff,
           "mode2 write address phase");
    advance_phase(2'd1);
    check_value(port3_oe[2] == 8'h00, "mode2 write turnaround phase");
    advance_phase(2'd2);
    check_value(e[2] && port3[2] == 8'hc7 && port3_oe[2] == 8'hff,
           "mode2 E-high write data");
    advance_phase(2'd3);
    check_value(port3[2] == 8'hc7 && port3_oe[2] == 8'hff,
           "mode2 write data held through E high");
    advance_phase(2'd0);

    // Mode 0 alone monitors internal read data on the expanded data bus.
    set_transaction(16'h0002, 1'b0, 8'h00);
    advance_phase(2'd1);
    advance_phase(2'd2);
    check_value(port3[0] == 8'h3c && port3_oe[0] == 8'hff,
           "mode0 internal read monitoring");
    check_value(port3_oe[2] == 8'h00, "mode2 internal read remains released");
    advance_phase(2'd3);
    advance_phase(2'd0);

    // Non-multiplexed Mode 5 supplies IOS and gates write-data drive with E.
    set_transaction(16'h0100, 1'b1, 8'h6d);
    check_value(!sc1[5] && sc1_oe[5] && !e[5] && port3_oe[5] == 8'h00,
           "mode5 IOS low and pre-E data release");
    advance_phase(2'd1);
    check_value(!sc1[5] && port3_oe[5] == 8'h00, "mode5 IOS stays selected");
    advance_phase(2'd2);
    check_value(e[5] && port3[5] == 8'h6d && port3_oe[5] == 8'hff,
           "mode5 E-high write data");
    advance_phase(2'd3);
    advance_phase(2'd0);
    set_transaction(16'h01ff, 1'b0, 8'h00);
    check_value(!sc1[5], "mode5 IOS includes 01FF");
    finish_cycle();
    set_transaction(16'h0200, 1'b0, 8'h00);
    check_value(sc1[5], "mode5 IOS excludes 0200");
    finish_cycle();

    // Single-chip pins remain GPIO/OS3, with SC1 acting only as an input.
    check_value(!sc1_oe[7] && sc2[7], "mode7 SC1 input and inactive OS3");
    check_value(port3_oe[7] == 8'h00 && port4_oe[7] == 8'h00,
           "mode7 GPIO directions reset to input");

    // The Mode 4 escape write changes physical pin roles on the next E cycle.
    check_value(active_mode[4] == 3'd4 && !sc1_oe[4], "mode4 starts single chip");
    set_transaction(16'h0003, 1'b1, 8'h20);
    finish_cycle();
    check_value(active_mode[4] == 3'd5 && sc1_oe[4], "mode4 write enters mode5");
    set_transaction(16'h0100, 1'b0, 8'h00);
    check_value(!sc1[4], "transitioned mode4 emits mode5 IOS");

    // MC6801RM(AD2) 5.4.2 defines WAI as repeated reads at the post-stack SP.
    set_transaction(16'ha55a, 1'b1, 8'hc7);
    stub_sp = 16'h1ff8;
    stub_waiting = 1'b1;
    #1;
    check_value(sc2[2] && (port3[2] == 8'hf8) &&
                (port3_oe[2] == 8'hff) && (port4[2] == 8'h1f),
                "mode2 WAI repeats the post-stack SP read");
    check_value(sc2[5] && sc1[5] && (port4[5] == 8'hf8),
                "mode5 WAI exposes post-stack SP and inactive IOS");
    stub_sp = 16'h0180;
    #1;
    check_value(!sc1[5] && (port4[5] == 8'h80),
                "mode5 WAI IOS follows the post-stack SP");
    advance_phase(2'd1);
    advance_phase(2'd2);
    check_value((port3_oe[2] == 8'h00) && (port3_oe[5] == 8'h00),
                "WAI read data phases remain released");
    advance_phase(2'd3);
    advance_phase(2'd0);
    stub_waiting = 1'b0;

    // FPGA clock-enable freezes the four-subphase generator and MCU state.
    clock_enable = 1'b0;
    @(posedge phase_clk);
    #1;
    check_value(phase[2] == 2'd0 && !e[2], "clock enable holds bus phase");

    $display("MC6801 phased bus wrapper PASS checks=%0d", checks);
    $finish;
  end
endmodule
