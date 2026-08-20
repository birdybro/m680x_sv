// SPDX-License-Identifier: MIT
module tb_hd6303r_bus_wrapper;
  import mc6801_peripheral_bus_stub_pkg::*;

  logic phase_clk;
  logic phase_reset_n;
  logic reset_n;
  logic standby_n;
  logic clock_enable;
  logic [7:0] port3_in;
  logic [1:0] phase [0:2];
  logic e [0:2];
  logic [7:0] port1 [0:2];
  logic [7:0] port1_oe [0:2];
  logic [7:0] port3 [0:2];
  logic [7:0] port3_oe [0:2];
  logic [7:0] port4 [0:2];
  logic [7:0] port4_oe [0:2];
  logic sc1 [0:2];
  logic sc1_oe [0:2];
  logic sc2 [0:2];
  logic standby_active [0:2];
  integer checks;

  generate
    for (genvar mode_index = 0; mode_index < 3; mode_index = mode_index + 1) begin : devices
      localparam logic [2:0] DEVICE_MODE =
        mode_index == 0 ? 3'd1 : (mode_index == 1 ? 3'd2 : 3'd4);
      /* verilator lint_off PINCONNECTEMPTY */
      hd6303r_bus_wrapper #(.OPERATING_MODE(DEVICE_MODE)) device (
        .phase_clk_i(phase_clk), .phase_reset_n_i(phase_reset_n),
        .reset_n_i(reset_n), .standby_n_i(standby_n),
        .clock_enable_i(clock_enable), .nmi_n_i(1'b1), .irq1_n_i(1'b1),
        .standby_power_ok_i(1'b1), .port1_i(8'h96),
        .port1_o(port1[mode_index]), .port1_oe_o(port1_oe[mode_index]),
        .port2_i(5'h15), .port2_o(), .port2_oe_o(), .port3_i(port3_in),
        .port3_o(port3[mode_index]), .port3_oe_o(port3_oe[mode_index]),
        .port4_o(port4[mode_index]), .port4_oe_o(port4_oe[mode_index]),
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
      if (!condition_value) $fatal(1, "%0s", label_value);
      checks = checks + 1;
    end
  endtask

  task automatic advance_phase(input logic [1:0] expected_phase);
    begin
      @(posedge phase_clk);
      #1;
      for (integer device_index = 0; device_index < 3;
           device_index = device_index + 1) begin
        check_value(phase[device_index] == expected_phase,
                    "all devices share phase sequence");
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
    check_value(phase[0] == 2'd0 && !e[0], "integration phase reset");
    for (integer reset_index = 0; reset_index < 3;
         reset_index = reset_index + 1) begin
      check_value((port1_oe[reset_index] == 8'h00) &&
                  (port3_oe[reset_index] == 8'h00) &&
                  (port4_oe[reset_index] == 8'h00),
                  "device reset releases address and data buses");
      check_value(sc2[reset_index], "device reset holds R/W high");
    end

    // Historical reset leaves E running; only the FPGA phase reset stops it.
    phase_reset_n = 1'b1;
    advance_phase(2'd1);
    advance_phase(2'd2);
    check_value(e[0] && e[1] && e[2], "E continues during device reset");
    advance_phase(2'd3);
    advance_phase(2'd0);
    reset_n = 1'b1;
    #1;

    // Mode 1 uses dedicated lower/upper address and data buses.
    set_transaction(16'ha55a, 1'b0, 8'h00);
    check_value((port1[0] == 8'h5a) && (port1_oe[0] == 8'hff),
                "mode1 lower address bus");
    check_value((port4[0] == 8'ha5) && (port4_oe[0] == 8'hff),
                "mode1 upper address bus");
    check_value((port3_oe[0] == 8'h00) && !sc1_oe[0] && sc2[0],
                "mode1 dedicated read-data controls");

    // Modes 2/4 share the documented multiplexed Port-3 waveform.
    for (integer mux_index = 1; mux_index < 3; mux_index = mux_index + 1) begin
      check_value((port3[mux_index] == 8'h5a) &&
                  (port3_oe[mux_index] == 8'hff),
                  "multiplexed low address phase");
      check_value(sc1[mux_index] && sc1_oe[mux_index] && sc2[mux_index],
                  "multiplexed address controls");
      check_value((port4[mux_index] == 8'ha5) &&
                  (port4_oe[mux_index] == 8'hff),
                  "multiplexed upper address bus");
    end
    advance_phase(2'd1);
    check_value(!sc1[1] && !sc1[2] && (port3_oe[1] == 8'h00) &&
                (port3_oe[2] == 8'h00), "AS close and Port-3 turnaround");
    advance_phase(2'd2);
    check_value(e[0] && e[1] && e[2], "E-high read phase");
    check_value((port3_oe[0] == 8'h00) && (port3_oe[1] == 8'h00) &&
                (port3_oe[2] == 8'h00), "all read data buses released");
    advance_phase(2'd3);
    advance_phase(2'd0);

    // All physical modes drive writes only while E is high.
    set_transaction(16'h1234, 1'b1, 8'hc7);
    check_value(!sc2[0] && !sc2[1] && !sc2[2], "R/W low for writes");
    check_value((port3_oe[0] == 8'h00) && (port3[1] == 8'h34) &&
                (port3_oe[1] == 8'hff) && (port3_oe[2] == 8'hff),
                "write address phase roles");
    advance_phase(2'd1);
    check_value((port3_oe[0] == 8'h00) && (port3_oe[1] == 8'h00) &&
                (port3_oe[2] == 8'h00), "write turnaround phase");
    advance_phase(2'd2);
    for (integer write_index = 0; write_index < 3;
         write_index = write_index + 1) begin
      check_value((port3[write_index] == 8'hc7) &&
                  (port3_oe[write_index] == 8'hff),
                  "E-high write data in every legal mode");
    end
    advance_phase(2'd3);
    advance_phase(2'd0);

    // SLP leaves E running but forces an idle read of FFFF on every bus form.
    stub_sleeping = 1'b1;
    #1;
    check_value(sc2[0] && sc2[1] && sc2[2], "sleep forces read direction");
    check_value((port1[0] == 8'hff) && (port4[0] == 8'hff),
                "mode1 sleep address is FFFF");
    check_value((port3[1] == 8'hff) && (port3[2] == 8'hff) &&
                (port4[1] == 8'hff) && (port4[2] == 8'hff),
                "multiplexed sleep address is FFFF");
    advance_phase(2'd1);
    advance_phase(2'd2);
    check_value(e[0] && e[1] && e[2], "sleep leaves E running");
    check_value((port3_oe[0] == 8'h00) && (port3_oe[1] == 8'h00) &&
                (port3_oe[2] == 8'h00), "sleep data phase is a released read");
    advance_phase(2'd3);
    advance_phase(2'd0);
    stub_sleeping = 1'b0;

    // Hitachi #U07 Q&A III.4.5 specifies FFFF, high-Z data, and inactive
    // RD/WR strobes during WAI; the wrapper represents that as read direction.
    stub_waiting = 1'b1;
    set_transaction(16'h1234, 1'b1, 8'hc7);
    check_value(sc2[0] && sc2[1] && sc2[2], "WAI forces read direction");
    check_value((port1[0] == 8'hff) && (port4[0] == 8'hff),
                "mode1 WAI address is FFFF");
    check_value((port3[1] == 8'hff) && (port3[2] == 8'hff) &&
                (port4[1] == 8'hff) && (port4[2] == 8'hff),
                "multiplexed WAI address is FFFF");
    advance_phase(2'd1);
    advance_phase(2'd2);
    check_value(e[0] && e[1] && e[2], "WAI leaves E running");
    check_value((port3_oe[0] == 8'h00) && (port3_oe[1] == 8'h00) &&
                (port3_oe[2] == 8'h00), "WAI data phase is released");
    advance_phase(2'd3);
    advance_phase(2'd0);
    stub_waiting = 1'b0;

    // Internal writes are still visible physically, as stated by the manual.
    set_transaction(16'h0080, 1'b1, 8'h6d);
    advance_phase(2'd1);
    advance_phase(2'd2);
    for (integer mirror_index = 0; mirror_index < 3;
         mirror_index = mirror_index + 1) begin
      check_value((port3[mirror_index] == 8'h6d) &&
                  (port3_oe[mirror_index] == 8'hff),
                  "internal write is mirrored on physical data bus");
    end
    advance_phase(2'd3);
    advance_phase(2'd0);

    // STBY is accepted at an E boundary, releases buses, and stops E.
    standby_n = 1'b0;
    finish_cycle();
    check_value(standby_active[0] && standby_active[1] && standby_active[2],
                "standby accepted in every mode");
    check_value(!e[0] && !e[1] && !e[2], "standby stops E");
    for (integer standby_index = 0; standby_index < 3;
         standby_index = standby_index + 1) begin
      check_value((port1_oe[standby_index] == 8'h00) &&
                  (port3_oe[standby_index] == 8'h00) &&
                  (port4_oe[standby_index] == 8'h00),
                  "standby releases address and data buses");
    end

    standby_n = 1'b1;
    finish_cycle();
    check_value(!standby_active[0] && !standby_active[1] &&
                !standby_active[2], "standby release is E-synchronous");

    clock_enable = 1'b0;
    @(posedge phase_clk);
    #1;
    check_value(phase[0] == 2'd0 && !e[0], "clock enable holds phase and E");

    $display("HD6303R phased bus wrapper PASS checks=%0d", checks);
    $finish;
  end
endmodule
