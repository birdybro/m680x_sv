// SPDX-License-Identifier: MIT
module tb_hd63701v0_prom;
  import mc6801_peripheral_bus_stub_pkg::*;

  logic clk;
  logic reset_n;
  logic prom_mode;
  logic prom_vpp;
  logic irq_a9;
  logic [7:0] port1_in;
  logic [7:0] port3_in;
  logic [7:0] port4_in;
  logic [15:0] program_address;
  logic program_read;
  logic [14:0] prom_address;
  logic [7:0] prom_data;
  logic prom_data_oe;
  logic [7:0] prom_program_data;
  logic prom_program;
  logic external_valid;
  logic external_fetch;
  logic os3_n;
  logic timer_irq;
  logic sci_irq;
  logic [7:0] port1_oe;
  logic [4:0] port2_oe;
  logic [7:0] port3_out;
  logic [7:0] port3_oe;
  logic [7:0] port4_oe;
  logic sci_tx;
  logic sci_clock;
  logic opcode_fetch;
  logic retire;
  logic illegal;
  logic undefined_instruction;
  logic waiting;
  logic sleeping;
  logic interrupt_ack;
  integer checks;

  /* verilator lint_off PINCONNECTEMPTY */
  hd63701v0_mcu #(.OPERATING_MODE(3'd2)) dut (
    .clk_i(clk), .reset_n_i(reset_n), .standby_n_i(1'b1),
    .clock_enable_i(1'b1), .nmi_n_i(1'b1), .irq1_n_i(irq_a9),
    .standby_power_ok_i(1'b1), .port1_i(port1_in), .port2_i(5'h1f),
    .port3_i(port3_in), .port4_i(port4_in), .is3_n_i(1'b1),
    .program_address_o(program_address), .program_read_o(program_read),
    .program_data_i(8'ha6), .prom_mode_i(prom_mode),
    .prom_program_voltage_i(prom_vpp), .prom_address_o(prom_address),
    .prom_data_o(prom_data), .prom_data_oe_o(prom_data_oe),
    .prom_program_data_o(prom_program_data), .prom_program_o(prom_program),
    .external_address_o(), .external_data_o(), .external_write_o(),
    .external_bus_valid_o(external_valid),
    .external_opcode_fetch_o(external_fetch), .external_data_i(8'h5a),
    .port1_o(), .port1_oe_o(port1_oe), .port2_o(),
    .port2_oe_o(port2_oe), .port3_o(port3_out), .port3_oe_o(port3_oe),
    .port4_o(), .port4_oe_o(port4_oe), .os3_n_o(os3_n), .sci_tx_o(sci_tx),
    .sci_clock_o(sci_clock), .timer_irq_o(timer_irq), .sci_irq_o(sci_irq),
    .opcode_fetch_o(opcode_fetch), .retire_o(retire), .illegal_o(illegal),
    .undefined_o(undefined_instruction), .waiting_o(waiting),
    .sleeping_o(sleeping),
    .interrupt_ack_o(interrupt_ack), .debug_address_o(), .debug_pc_o(),
    .debug_sp_o(), .debug_a_o(), .debug_b_o(), .debug_x_o(), .debug_ccr_o(),
    .debug_timer_o(), .debug_output_compare_o(), .debug_input_capture_o(),
    .debug_tcsr_o(), .debug_trcsr_o(), .debug_receive_data_o(),
    .debug_opcode_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always #5 clk <= ~clk;

  task automatic check_value(input logic condition_value, input string label_value);
    begin
      checks = checks + 1;
      if (!condition_value) $fatal(1, "HD63701V0 PROM: %0s", label_value);
    end
  endtask

  task automatic set_address(input logic [14:0] address_value);
    begin
      port1_in = address_value[7:0];
      port4_in[0] = address_value[8];
      irq_a9 = address_value[9];
      port4_in[5:2] = address_value[13:10];
      port4_in[1] = address_value[14];
      #1;
    end
  endtask

  task automatic set_controls(
    input logic vpp_value,
    input logic ce_n_value,
    input logic oe_n_value
  );
    begin
      prom_vpp = vpp_value;
      port4_in[7] = ce_n_value;
      port4_in[6] = oe_n_value;
      #1;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b0;
    prom_mode = 1'b0;
    prom_vpp = 1'b0;
    irq_a9 = 1'b1;
    port1_in = 8'h5a;
    port3_in = 8'hc7;
    port4_in = 8'hc0;
    stub_address = 16'h3456;
    stub_data = 8'h69;
    stub_write = 1'b0;
    stub_valid = 1'b1;
    stub_opcode_fetch = 1'b1;
    stub_interrupt_mask = 1'b1;
    stub_sleeping = 1'b0;
    stub_waiting = 1'b0;
    stub_sp = 16'h0000;
    checks = 0;

    reset_n = 1'b1;
    #1;
    check_value(external_valid && external_fetch,
                "normal Mode 2 keeps the normalized external boundary");
    check_value(!prom_data_oe && !prom_program,
                "PROM controls are inactive outside PROM mode");

    // Section 3.1: PROM mode stops every MCU function and repurposes the
    // physical Port-1/3/4 and IRQ pins as a 27256-compatible interface.
    stub_sleeping = 1'b1;
    stub_waiting = 1'b1;
    prom_mode = 1'b1;
    #1;
    check_value(!external_valid && !external_fetch && !opcode_fetch,
                "PROM mode suppresses CPU and external-memory activity");
    check_value(!retire && !waiting && !sleeping && !interrupt_ack,
                "PROM mode stops execution and low-power state reporting");
    check_value(!illegal && !undefined_instruction && !timer_irq && !sci_irq &&
                os3_n,
                "PROM mode suppresses instruction, interrupt, and strobe status");
    check_value((port1_oe == 8'h00) && (port2_oe == 5'h00) &&
                (port4_oe == 8'h00),
                "PROM address and control pins are inputs");
    check_value(sci_tx && !sci_clock,
                "PROM mode holds normalized serial outputs at reset idle");

    set_address(15'h4b5a);
    check_value(prom_address == 15'h4b5a,
                "P41/P45:P42/IRQ/P40/Port1 map exactly to A14:A0");

    // Table 3-1 Read: VPP=VCC, CE low, OE low.
    set_address(15'h0abc);
    set_controls(1'b0, 1'b0, 1'b0);
    check_value(prom_data_oe && (port3_oe == 8'hff),
                "read drives all eight PROM data pins");
    check_value((prom_data == 8'ha6) && (port3_out == 8'ha6),
                "read returns the integration-owned EPROM byte");
    check_value(program_read && (program_address == 16'hfabc),
                "read selects the corresponding F000-FFFF storage byte");
    check_value(!prom_program, "read cannot issue a program request");

    // Output disable: VPP=VCC, CE low, OE high.
    set_controls(1'b0, 1'b0, 1'b1);
    check_value(!prom_data_oe && (port3_oe == 8'h00) && !program_read,
                "output-disable releases data and storage read");
    check_value(!prom_program, "output-disable cannot program");

    // High-performance program: VPP present, CE low, OE high.
    set_controls(1'b1, 1'b0, 1'b1);
    check_value(prom_program && !prom_data_oe && !program_read,
                "program asserts only the integration storage request");
    check_value(prom_program_data == 8'hc7,
                "program forwards the byte sampled on Port 3");
    check_value(program_address == 16'hfabc,
                "program and verify share the selected storage address");

    // Verify: VPP present, CE high, OE low.
    set_controls(1'b1, 1'b1, 1'b0);
    check_value(prom_data_oe && !prom_program && program_read,
                "verify drives data and reads storage without programming");
    check_value((port3_out == 8'ha6) && (port3_oe == 8'hff),
                "verify returns the stored byte on Port 3");

    // Program inhibit: VPP present, CE high, OE high.
    set_controls(1'b1, 1'b1, 1'b1);
    check_value(!prom_data_oe && !prom_program && !program_read,
                "program inhibit is high impedance and inactive");

    // Figure 3-3: the physical array ends at 0FFF; higher 27256 addresses
    // read erased FF and cannot select or modify the 4-KiB FPGA image.
    set_address(15'h1000);
    set_controls(1'b0, 1'b0, 1'b0);
    check_value(prom_data_oe && (prom_data == 8'hff) &&
                (port3_out == 8'hff),
                "addresses above 0FFF drive the documented erased value");
    check_value(!program_read, "erased extension does not read array storage");
    set_controls(1'b1, 1'b0, 1'b1);
    check_value(!prom_program,
                "addresses above 0FFF cannot issue a program request");
    set_address(15'h7fff);
    check_value(prom_address == 15'h7fff,
                "all fifteen external address bits remain observable");

    // The three combinations absent from table 3-1 are safely inactive and
    // remain explicitly UNDEFINED_BY_DOCUMENTATION in the structured spec.
    set_controls(1'b0, 1'b1, 1'b0);
    check_value(!prom_data_oe && !prom_program && !program_read,
                "unlisted VCC/CE-high/OE-low combination is safe inactive");
    set_controls(1'b0, 1'b1, 1'b1);
    check_value(!prom_data_oe && !prom_program && !program_read,
                "unlisted VCC/CE-high/OE-high combination is safe inactive");
    set_controls(1'b1, 1'b0, 1'b0);
    check_value(!prom_data_oe && !prom_program && !program_read,
                "unlisted VPP/CE-low/OE-low combination is safe inactive");

    stub_sleeping = 1'b0;
    stub_waiting = 1'b0;
    prom_mode = 1'b0;
    #1;
    check_value(external_valid && external_fetch,
                "leaving PROM mode restores the selected MCU boundary");

    $display("HD63701V0 PROM PASS checks=%0d", checks);
    $finish;
  end
endmodule
