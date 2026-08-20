// SPDX-License-Identifier: MIT
module tb_hd6301v1_bus_wrapper;
  import mc6801_peripheral_bus_stub_pkg::*;

  logic phase_clk;
  logic phase_reset_n;
  logic reset_n;
  logic standby_n;
  logic clock_enable;
  logic [7:0] port3_in;
  logic [1:0] phase [0:6];
  logic e [0:6];
  logic [7:0] port1 [0:6];
  logic [7:0] port1_oe [0:6];
  logic [7:0] port3 [0:6];
  logic [7:0] port3_oe [0:6];
  logic [7:0] port4 [0:6];
  logic [7:0] port4_oe [0:6];
  logic sc1 [0:6];
  logic sc1_oe [0:6];
  logic sc2 [0:6];
  logic standby_active [0:6];
  integer checks;

  generate
    for (genvar mode_index = 0; mode_index < 7; mode_index = mode_index + 1) begin : devices
      localparam logic [2:0] DEVICE_MODE =
        mode_index < 3 ? mode_index : (mode_index + 1);
      /* verilator lint_off PINCONNECTEMPTY */
      hd6301v1_bus_wrapper #(.OPERATING_MODE(DEVICE_MODE)) device (
        .phase_clk_i(phase_clk), .phase_reset_n_i(phase_reset_n),
        .reset_n_i(reset_n), .standby_n_i(standby_n),
        .clock_enable_i(clock_enable), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
        .standby_power_ok_i(1'b1), .program_data_i(8'h01),
        .program_address_o(), .program_read_o(), .port1_i(8'h5a),
        .port1_o(port1[mode_index]), .port1_oe_o(port1_oe[mode_index]),
        .port2_i(5'h15), .port2_o(), .port2_oe_o(), .port3_i(port3_in),
        .port3_o(port3[mode_index]), .port3_oe_o(port3_oe[mode_index]),
        .port4_i(8'ha6), .port4_o(port4[mode_index]),
        .port4_oe_o(port4_oe[mode_index]), .sc1_i(1'b1),
        .sc1_o(sc1[mode_index]), .sc1_oe_o(sc1_oe[mode_index]),
        .sc2_o(sc2[mode_index]), .e_o(e[mode_index]),
        .bus_phase_o(phase[mode_index]),
        .standby_active_o(standby_active[mode_index]), .sci_tx_o(),
        .sci_clock_o(), .timer_irq_o(), .sci_irq_o(), .opcode_fetch_o(),
        .retire_o(), .illegal_o(), .undefined_o(), .waiting_o(),
        .sleeping_o(), .interrupt_ack_o(), .debug_address_o(), .debug_pc_o(),
        .debug_sp_o(), .debug_a_o(), .debug_b_o(), .debug_x_o(),
        .debug_ccr_o()
      );
      /* verilator lint_on PINCONNECTEMPTY */
    end
  endgenerate

  always #5 phase_clk <= ~phase_clk;

  task automatic check_value(input logic condition_value, input string label_value);
    begin
      checks = checks + 1;
      if (!condition_value) $fatal(1, "HD6301V1 phased bus: %0s", label_value);
    end
  endtask

  task automatic advance_phase(input logic [1:0] expected_phase);
    begin
      @(posedge phase_clk);
      #1;
      for (integer device_index = 0; device_index < 7;
           device_index = device_index + 1) begin
        check_value(phase[device_index] == expected_phase,
                    "all legal modes share the subphase sequence");
      end
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

  task automatic finish_cycle;
    begin
      advance_phase(2'd1);
      advance_phase(2'd2);
      advance_phase(2'd3);
      advance_phase(2'd0);
    end
  endtask

  task automatic write_register(input logic [15:0] address_value,
                                input logic [7:0] data_value);
    begin
      set_transaction(address_value, 1'b1, data_value);
      finish_cycle();
    end
  endtask

  initial begin
    phase_clk = 1'b0;
    phase_reset_n = 1'b0;
    reset_n = 1'b0;
    standby_n = 1'b1;
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
    for (integer mode_index = 0; mode_index < 7; mode_index = mode_index + 1) begin
      check_value((phase[mode_index] == 2'd0) && !e[mode_index],
                  "integration reset initializes E-low address phase");
      check_value((port1_oe[mode_index] == 8'h00) &&
                  (port3_oe[mode_index] == 8'h00) &&
                  (port4_oe[mode_index] == 8'h00),
                  "integration reset safely releases all port buses");
    end

    // Section 2.8 keeps configured address pins active until the third
    // completed E cycle with RES low, then releases every address bus.
    phase_reset_n = 1'b1;
    #1;
    for (integer reset_cycle = 0; reset_cycle < 3; reset_cycle = reset_cycle + 1) begin
      check_value((port3_oe[0] == 8'hff) && (port4_oe[0] == 8'hff),
                  "Mode 0 reset drives multiplexed address");
      check_value((port1_oe[1] == 8'hff) && (port4_oe[1] == 8'hff),
                  "Mode 1 reset drives dedicated address");
      check_value((port3_oe[2] == 8'hff) && (port4_oe[2] == 8'hff) &&
                  (port3_oe[3] == 8'hff) && (port4_oe[3] == 8'hff),
                  "Modes 2 and 4 reset drive multiplexed address");
      check_value((port3_oe[5] == 8'hff) && (port4_oe[5] == 8'h00),
                  "Mode 6 reset drives only configured multiplexed address");
      advance_phase(2'd1);
      advance_phase(2'd2);
      for (integer mode_index = 0; mode_index < 7;
           mode_index = mode_index + 1) begin
        check_value(e[mode_index], "E continues throughout device reset");
      end
      advance_phase(2'd3);
      advance_phase(2'd0);
    end
    for (integer mode_index = 0; mode_index < 7; mode_index = mode_index + 1) begin
      check_value((port1_oe[mode_index] == 8'h00) &&
                  (port3_oe[mode_index] == 8'h00) &&
                  (port4_oe[mode_index] == 8'h00),
                  "third reset cycle releases every address/data bus");
      check_value(sc2[mode_index], "established reset holds SC2 high");
    end
    reset_n = 1'b1;
    #1;

    // Configure GPIO/partial-address directions and latches. Expanded modes
    // that do not implement a register simply ignore the shared transaction.
    write_register(16'h0000, 8'hf0);
    write_register(16'h0002, 8'h96);
    write_register(16'h0004, 8'h3c);
    write_register(16'h0006, 8'hc3);
    write_register(16'h0005, 8'h0f);
    write_register(16'h0007, 8'h69);

    set_transaction(16'ha55a, 1'b0, 8'h00);
    check_value((port1[1] == 8'h5a) && (port1_oe[1] == 8'hff) &&
                (port4[1] == 8'ha5) && (port4_oe[1] == 8'hff),
                "Mode 1 dedicated full address bus");
    for (integer gpio_index = 0; gpio_index < 7; gpio_index = gpio_index + 1) begin
      if (gpio_index != 1) begin
        check_value((port1[gpio_index] == 8'h96) &&
                    (port1_oe[gpio_index] == 8'hf0),
                    "non-Mode-1 Port 1 retains GPIO role");
      end
    end
    for (integer mux_index = 0; mux_index < 7; mux_index = mux_index + 1) begin
      if ((mux_index == 0) || (mux_index == 2) || (mux_index == 3) ||
          (mux_index == 5)) begin
        check_value((port3[mux_index] == 8'h5a) &&
                    (port3_oe[mux_index] == 8'hff) && sc1[mux_index] &&
                    sc1_oe[mux_index], "multiplexed low-address/AS phase");
      end
    end
    check_value((port4[0] == 8'ha5) && (port4_oe[0] == 8'hff) &&
                (port4[2] == 8'ha5) && (port4_oe[2] == 8'hff) &&
                (port4[3] == 8'ha5) && (port4_oe[3] == 8'hff),
                "full upper-address roles in Modes 0/2/4");
    check_value((port4[4] == 8'h5a) && (port4_oe[4] == 8'h0f) &&
                (port4[5] == 8'ha5) && (port4_oe[5] == 8'h0f),
                "Mode 5/6 partial address follows Port-4 DDR");
    check_value((port3[6] == 8'hc3) && (port3_oe[6] == 8'h3c) &&
                (port4[6] == 8'h69) && (port4_oe[6] == 8'h0f) &&
                !sc1_oe[6], "Mode 7 retains GPIO and IS3 input roles");

    advance_phase(2'd1);
    check_value(!sc1[0] && !sc1[2] && !sc1[3] && !sc1[5],
                "AS closes before E rises");
    check_value((port3_oe[0] == 8'h00) && (port3_oe[2] == 8'h00) &&
                (port3_oe[3] == 8'h00) && (port3_oe[5] == 8'h00),
                "multiplexed Port 3 turns around after AS");
    advance_phase(2'd2);
    for (integer expanded_index = 0; expanded_index < 6;
         expanded_index = expanded_index + 1) begin
      check_value(e[expanded_index] && (port3_oe[expanded_index] == 8'h00),
                  "expanded read releases data bus during E");
    end
    check_value(e[6] && (port3_oe[6] == 8'h3c),
                "single-chip GPIO direction is independent of E");
    advance_phase(2'd3);
    advance_phase(2'd0);

    set_transaction(16'h1234, 1'b1, 8'hc7);
    for (integer expanded_index = 0; expanded_index < 6;
         expanded_index = expanded_index + 1) begin
      check_value(!sc2[expanded_index], "expanded write drives R/W low");
    end
    advance_phase(2'd1);
    advance_phase(2'd2);
    for (integer expanded_index = 0; expanded_index < 6;
         expanded_index = expanded_index + 1) begin
      check_value((port3[expanded_index] == 8'hc7) &&
                  (port3_oe[expanded_index] == 8'hff),
                  "every expanded mode drives write data only during E");
    end
    check_value((port3[6] == 8'hc3) && (port3_oe[6] == 8'h3c),
                "Mode 7 write transaction cannot leak an expanded bus role");
    advance_phase(2'd3);
    advance_phase(2'd0);

    set_transaction(16'h015a, 1'b0, 8'h00);
    check_value(!sc1[4] && sc1_oe[4], "Mode 5 IOS selects 0100-01FF");
    set_transaction(16'h0200, 1'b0, 8'h00);
    check_value(sc1[4], "Mode 5 IOS rejects the next page");

    set_transaction(16'h0006, 1'b0, 8'h00);
    check_value(sc2[6], "Mode 7 OS3 remains inactive while E is low");
    advance_phase(2'd1);
    advance_phase(2'd2);
    check_value(!sc2[6], "Mode 7 SC2 carries selected Port-3 OS3 E strobe");
    advance_phase(2'd3);
    advance_phase(2'd0);
    set_transaction(16'h0080, 1'b1, 8'h6d);
    advance_phase(2'd1);
    advance_phase(2'd2);
    for (integer expanded_index = 0; expanded_index < 6;
         expanded_index = expanded_index + 1) begin
      check_value((port3[expanded_index] == 8'h6d) &&
                  (port3_oe[expanded_index] == 8'hff),
                  "internal write is visible on each expanded data bus");
    end
    advance_phase(2'd3);
    advance_phase(2'd0);

    // SLP and WAI retain FFFF on expanded address forms with released data;
    // Mode 7 continues to expose the retained GPIO state.
    for (integer low_power_kind = 0; low_power_kind < 2;
         low_power_kind = low_power_kind + 1) begin
      stub_sleeping = low_power_kind == 0;
      stub_waiting = low_power_kind == 1;
      set_transaction(16'h1234, 1'b1, 8'hc7);
      check_value((port3[0] == 8'hff) && (port4[0] == 8'hff) &&
                  (port1[1] == 8'hff) && (port4[1] == 8'hff) &&
                  (port3[2] == 8'hff) && (port4[2] == 8'hff) &&
                  (port3[3] == 8'hff) && (port4[3] == 8'hff) &&
                  (port4[4] == 8'hff) && (port3[5] == 8'hff) &&
                  (port4[5] == 8'hff),
                  "low-power expanded address is FFFF in every bus form");
      check_value((port1[6] == 8'h96) && (port3[6] == 8'hc3) &&
                  (port4[6] == 8'h69), "Mode 7 low power retains GPIO values");
      advance_phase(2'd1);
      advance_phase(2'd2);
      for (integer expanded_index = 0; expanded_index < 6;
           expanded_index = expanded_index + 1) begin
        check_value(sc2[expanded_index] &&
                    (port3_oe[expanded_index] == 8'h00),
                    "low-power expanded data phase is a released read");
      end
      advance_phase(2'd3);
      advance_phase(2'd0);
      stub_sleeping = 1'b0;
      stub_waiting = 1'b0;
    end

    standby_n = 1'b0;
    finish_cycle();
    for (integer mode_index = 0; mode_index < 7; mode_index = mode_index + 1) begin
      check_value(standby_active[mode_index] && !e[mode_index],
                  "E-synchronous standby suppresses E");
      check_value((port1_oe[mode_index] == 8'h00) &&
                  (port3_oe[mode_index] == 8'h00) &&
                  (port4_oe[mode_index] == 8'h00),
                  "standby releases every port bus");
    end
    standby_n = 1'b1;
    finish_cycle();
    for (integer mode_index = 0; mode_index < 7; mode_index = mode_index + 1) begin
      check_value(!standby_active[mode_index],
                  "standby release is sampled at the E boundary");
    end

    clock_enable = 1'b0;
    @(posedge phase_clk);
    #1;
    for (integer mode_index = 0; mode_index < 7; mode_index = mode_index + 1) begin
      check_value((phase[mode_index] == 2'd0) && !e[mode_index],
                  "clock enable holds the complete digital phase state");
    end

    $display("HD6301V1 phased bus wrapper PASS checks=%0d", checks);
    $finish;
  end
endmodule
