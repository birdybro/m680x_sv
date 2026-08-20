// SPDX-License-Identifier: MIT
module tb_hd63705v0_mcu;
  logic clk;
  logic reset_n;
  logic clock_enable;
  logic standby_n;
  logic int_n;
  logic int2_n;
  logic timer_pin;
  logic [7:0] port_a_in;
  logic [7:0] port_b_in;
  logic [7:0] port_c_in;
  logic [6:0] port_d_in;
  logic [7:0] port_a_out;
  logic [7:0] port_b_out;
  logic [7:0] port_c_out;
  logic [6:0] port_d_out;
  logic [7:0] port_a_oe;
  logic [7:0] port_b_oe;
  logic [7:0] port_c_oe;
  logic [6:0] port_d_oe;
  logic [13:0] program_address;
  logic program_read;
  logic [7:0] program_data;
  logic eprom_mode;
  logic [11:0] eprom_address;
  logic [7:0] eprom_data_in;
  logic eprom_ce_n;
  logic eprom_oe_n;
  logic eprom_read_voltage;
  logic eprom_vpp;
  logic [7:0] eprom_data_out;
  logic eprom_data_oe;
  logic [7:0] eprom_program_data;
  logic eprom_program;
  logic sci_tx;
  logic sci_clock;
  logic timer_irq;
  logic sci_irq;
  logic int_irq;
  logic int2_irq;
  logic [15:0] irq_vector;
  logic opcode_fetch;
  logic retire;
  logic illegal;
  logic undefined_value;
  logic waiting_state;
  logic stopped_state;
  logic interrupt_ack;
  logic [15:0] debug_address;
  logic [15:0] debug_pc;
  logic [15:0] debug_sp;
  logic [7:0] debug_a;
  logic [7:0] debug_x;
  logic [4:0] debug_ccr;
  logic [7:0] debug_opcode;
  logic [3:0] debug_cycles;
  logic [7:0] debug_timer;
  logic [7:0] debug_tcr;
  logic [7:0] debug_mr;
  logic [7:0] debug_scr;
  logic [7:0] debug_ssr;
  logic [7:0] debug_sdr;
  logic [7:0] firmware [0:16383];
  logic [7:0] transmitted;
  logic [7:0] receive_pattern;
  integer index;
  integer cycles;
  integer checks;

  hd63705v0_mcu dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(clock_enable),
    .standby_n_i(standby_n), .int_n_i(int_n), .int2_n_i(int2_n),
    .timer_i(timer_pin), .port_a_i(port_a_in), .port_b_i(port_b_in),
    .port_c_i(port_c_in), .port_d_i(port_d_in), .port_a_o(port_a_out),
    .port_b_o(port_b_out), .port_c_o(port_c_out), .port_d_o(port_d_out),
    .port_a_oe_o(port_a_oe), .port_b_oe_o(port_b_oe),
    .port_c_oe_o(port_c_oe), .port_d_oe_o(port_d_oe),
    .program_address_o(program_address), .program_read_o(program_read),
    .program_data_i(program_data), .eprom_mode_i(eprom_mode),
    .eprom_address_i(eprom_address), .eprom_data_i(eprom_data_in),
    .eprom_chip_enable_n_i(eprom_ce_n),
    .eprom_output_enable_n_i(eprom_oe_n),
    .eprom_read_voltage_i(eprom_read_voltage),
    .eprom_program_voltage_i(eprom_vpp), .eprom_data_o(eprom_data_out),
    .eprom_data_oe_o(eprom_data_oe),
    .eprom_program_data_o(eprom_program_data), .eprom_program_o(eprom_program),
    .sci_tx_o(sci_tx), .sci_clock_o(sci_clock), .timer_irq_o(timer_irq),
    .sci_irq_o(sci_irq), .int_irq_o(int_irq), .int2_irq_o(int2_irq),
    .irq_vector_o(irq_vector), .opcode_fetch_o(opcode_fetch),
    .retire_o(retire), .illegal_o(illegal), .undefined_o(undefined_value),
    .waiting_o(waiting_state), .stopped_o(stopped_state),
    .interrupt_ack_o(interrupt_ack), .debug_address_o(debug_address),
    .debug_pc_o(debug_pc), .debug_sp_o(debug_sp), .debug_a_o(debug_a),
    .debug_x_o(debug_x), .debug_ccr_o(debug_ccr),
    .debug_opcode_o(debug_opcode), .debug_instruction_cycles_o(debug_cycles),
    .debug_timer_o(debug_timer), .debug_tcr_o(debug_tcr),
    .debug_mr_o(debug_mr), .debug_scr_o(debug_scr),
    .debug_ssr_o(debug_ssr), .debug_sdr_o(debug_sdr)
  );

  assign program_data = firmware[program_address];
  always #5 clk <= ~clk;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic reset_to(input logic [13:0] address_value);
    begin
      firmware[14'h1ffe] = {2'b00, address_value[13:8]};
      firmware[14'h1fff] = address_value[7:0];
      #1;
      reset_n = 1'b0;
      #1;
      if (!program_read || program_address != 14'h1ffe) begin
        $fatal(1, "HD63705V0 reset vector high address");
      end
      tick();
      reset_n = 1'b1;
      tick();
      if (!program_read || program_address != 14'h1fff) begin
        $fatal(1, "HD63705V0 reset vector low address");
      end
      tick();
      if (debug_pc[13:0] != address_value || debug_sp != 16'h00ff ||
          !debug_ccr[3]) begin
        $fatal(1, "HD63705V0 reset state pc=%04x sp=%04x ccr=%02x",
               debug_pc, debug_sp, debug_ccr);
      end
      checks = checks + 1;
    end
  endtask

  task automatic run_instruction(input logic [7:0] expected_opcode);
    begin
      cycles = 0;
      do begin
        tick();
        cycles = cycles + 1;
        if (cycles > 20) begin
          $fatal(1, "HD63705V0 opcode %02x did not retire pc=%04x",
                 expected_opcode, debug_pc);
        end
      end while (!retire);
      if (debug_opcode != expected_opcode || debug_cycles != cycles[3:0] ||
          illegal || undefined_value) begin
        $fatal(1, "HD63705V0 opcode %02x result/timing opcode=%02x cycles=%0d/%0d",
               expected_opcode, debug_opcode, cycles, debug_cycles);
      end
    end
  endtask

  task automatic wait_for_interrupt(input logic [13:0] expected_pc);
    begin
      cycles = 0;
      do begin
        tick();
        cycles = cycles + 1;
        if (cycles > 20) $fatal(1, "HD63705V0 interrupt did not acknowledge");
      end while (!interrupt_ack);
      if (debug_pc[13:0] != expected_pc) begin
        $fatal(1, "HD63705V0 interrupt vector pc=%04x expected=%04x",
               debug_pc, expected_pc);
      end
      checks = checks + 1;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    clock_enable = 1'b1;
    standby_n = 1'b1;
    int_n = 1'b1;
    int2_n = 1'b1;
    timer_pin = 1'b0;
    port_a_in = 8'h3c;
    port_b_in = 8'h5a;
    port_c_in = 8'hc3;
    port_d_in = 7'h7f;
    eprom_mode = 1'b0;
    eprom_address = 12'h000;
    eprom_data_in = 8'h00;
    eprom_ce_n = 1'b1;
    eprom_oe_n = 1'b1;
    eprom_read_voltage = 1'b0;
    eprom_vpp = 1'b0;
    checks = 0;
    receive_pattern = 8'h3c;
    for (index = 0; index < 16384; index = index + 1) firmware[index] = 8'h9d;

    // Physical RAM boundaries, GPIO mixed pin/latch reads, and readable DDRs.
    firmware[14'h1100] = 8'ha6; firmware[14'h1101] = 8'ha5;
    firmware[14'h1102] = 8'hb7; firmware[14'h1103] = 8'h00;
    firmware[14'h1104] = 8'ha6; firmware[14'h1105] = 8'hf0;
    firmware[14'h1106] = 8'hb7; firmware[14'h1107] = 8'h04;
    firmware[14'h1108] = 8'hb6; firmware[14'h1109] = 8'h00;
    firmware[14'h110a] = 8'hb7; firmware[14'h110b] = 8'h40;
    firmware[14'h110c] = 8'hb6; firmware[14'h110d] = 8'h40;
    firmware[14'h110e] = 8'ha6; firmware[14'h110f] = 8'h3c;
    firmware[14'h1110] = 8'hb7; firmware[14'h1111] = 8'hff;
    firmware[14'h1112] = 8'hb6; firmware[14'h1113] = 8'hff;
    firmware[14'h1114] = 8'hb6; firmware[14'h1115] = 8'h04;
    reset_to(14'h1100);
    if (port_a_oe != 8'h00 || port_b_oe != 8'h00 || port_c_oe != 8'h00 ||
        port_d_oe != 7'h00 || debug_timer != 8'hf0 || debug_tcr != 8'h50 ||
        debug_mr != 8'h5f || debug_scr != 8'h00 || debug_ssr != 8'h37) begin
      $fatal(1, "HD63705V0 peripheral reset pa=%02x pb=%02x pc=%02x pd=%02x tdr=%02x tcr=%02x mr=%02x scr=%02x ssr=%02x",
             port_a_oe, port_b_oe, port_c_oe, port_d_oe, debug_timer,
             debug_tcr, debug_mr, debug_scr, debug_ssr);
    end
    checks = checks + 1;
    run_instruction(8'ha6); run_instruction(8'hb7);
    run_instruction(8'ha6); run_instruction(8'hb7);
    if (port_a_out != 8'ha5 || port_a_oe != 8'hf0) begin
      $fatal(1, "HD63705V0 GPIO latch/direction");
    end
    checks = checks + 1;
    run_instruction(8'hb6);
    if (debug_a != 8'hac) $fatal(1, "HD63705V0 mixed GPIO read %02x", debug_a);
    run_instruction(8'hb7); run_instruction(8'hb6);
    if (debug_a != 8'hac) $fatal(1, "HD63705V0 low RAM boundary");
    run_instruction(8'ha6); run_instruction(8'hb7); run_instruction(8'hb6);
    if (debug_a != 8'h3c) $fatal(1, "HD63705V0 high RAM boundary");
    run_instruction(8'hb6);
    if (debug_a != 8'hf0) $fatal(1, "HD63705V0 DDR readback");
    checks = checks + 4;

    // A timer event entered from WAIT uses the separate 1FF6 vector.
    firmware[14'h1200] = 8'ha6; firmware[14'h1201] = 8'h01;
    firmware[14'h1202] = 8'hb7; firmware[14'h1203] = 8'h08;
    firmware[14'h1204] = 8'ha6; firmware[14'h1205] = 8'h10;
    firmware[14'h1206] = 8'hb7; firmware[14'h1207] = 8'h09;
    firmware[14'h1208] = 8'h8f;
    firmware[14'h1300] = 8'h1f; firmware[14'h1301] = 8'h09;
    firmware[14'h1302] = 8'h80;
    firmware[14'h1ff6] = 8'h13; firmware[14'h1ff7] = 8'h00;
    timer_pin = 1'b0;
    reset_to(14'h1200);
    run_instruction(8'ha6); run_instruction(8'hb7);
    run_instruction(8'ha6); run_instruction(8'hb7); run_instruction(8'h8f);
    if (!waiting_state || debug_timer != 8'h01) begin
      $fatal(1, "HD63705V0 WAIT timer setup wait=%b timer=%02x",
             waiting_state, debug_timer);
    end
    timer_pin = 1'b1;
    wait_for_interrupt(14'h1300);
    if (!timer_irq || irq_vector != 16'h1ff8) begin
      $fatal(1, "HD63705V0 wait timer request/vector post-entry irq=%b vec=%04x",
             timer_irq, irq_vector);
    end
    run_instruction(8'h1f);
    if (timer_irq || debug_tcr[7]) $fatal(1, "HD63705V0 timer request clear");
    checks = checks + 2;
    timer_pin = 1'b0;

    // Simultaneous external requests prove INT priority and retained INT2.
    firmware[14'h1400] = 8'ha6; firmware[14'h1401] = 8'h00;
    firmware[14'h1402] = 8'hb7; firmware[14'h1403] = 8'h0a;
    firmware[14'h1404] = 8'h9a;
    firmware[14'h1405] = 8'h9d;
    firmware[14'h1500] = 8'h80;
    firmware[14'h1510] = 8'h1f; firmware[14'h1511] = 8'h0a;
    firmware[14'h1512] = 8'h80;
    firmware[14'h1ffa] = 8'h15; firmware[14'h1ffb] = 8'h00;
    firmware[14'h1ff8] = 8'h15; firmware[14'h1ff9] = 8'h10;
    reset_to(14'h1400);
    run_instruction(8'ha6); run_instruction(8'hb7);
    int_n = 1'b0;
    int2_n = 1'b0;
    run_instruction(8'h9a);
    run_instruction(8'h9d);
    if (!int_irq || !int2_irq || irq_vector != 16'h1ffa) begin
      $fatal(1, "HD63705V0 external priority int=%b int2=%b vector=%04x",
             int_irq, int2_irq, irq_vector);
    end
    wait_for_interrupt(14'h1500);
    int_n = 1'b1;
    int2_n = 1'b1;
    run_instruction(8'h80);
    wait_for_interrupt(14'h1510);
    run_instruction(8'h1f);
    if (int2_irq || debug_mr[7]) $fatal(1, "HD63705V0 INT2 software clear");
    checks = checks + 2;

    // QA635-329A: a pending unmasked source completes the four-cycle WAIT
    // or STOP instruction but prevents entry into the low-power state. A
    // timer already pending before WAIT therefore uses the normal $1ff8
    // vector, not the special vector reserved for a timer arising in WAIT.
    firmware[14'h1520] = 8'ha6; firmware[14'h1521] = 8'h01;
    firmware[14'h1522] = 8'hb7; firmware[14'h1523] = 8'h08;
    firmware[14'h1524] = 8'ha6; firmware[14'h1525] = 8'h00;
    firmware[14'h1526] = 8'hb7; firmware[14'h1527] = 8'h09;
    firmware[14'h1528] = 8'h8f;
    firmware[14'h1530] = 8'h1f; firmware[14'h1531] = 8'h09;
    firmware[14'h1532] = 8'h80;
    firmware[14'h1540] = 8'h80;
    firmware[14'h1ff6] = 8'h15; firmware[14'h1ff7] = 8'h40;
    firmware[14'h1ff8] = 8'h15; firmware[14'h1ff9] = 8'h30;
    timer_pin = 1'b0;
    reset_to(14'h1520);
    run_instruction(8'ha6); run_instruction(8'hb7);
    run_instruction(8'ha6); run_instruction(8'hb7);
    if (!timer_irq) $fatal(1, "HD63705V0 pending timer setup");
    run_instruction(8'h8f);
    if (waiting_state || stopped_state || irq_vector != 16'h1ff8) begin
      $fatal(1, "HD63705V0 pending timer entered WAIT wait=%b stop=%b vector=%04x",
             waiting_state, stopped_state, irq_vector);
    end
    wait_for_interrupt(14'h1530);
    if (debug_sp != 16'h00fa || dut.ram[191] != 8'h29 ||
        dut.ram[190] != 8'hd5 || dut.ram[189] != 8'h00 ||
        dut.ram[188] != 8'h00 || dut.ram[187][3] != 1'b0) begin
      $fatal(1, "HD63705V0 WAIT pending frame sp=%04x %02x %02x %02x %02x %02x",
             debug_sp, dut.ram[191], dut.ram[190], dut.ram[189],
             dut.ram[188], dut.ram[187]);
    end
    checks = checks + 2;

    // A falling INT while I is still set likewise prevents STOP and retains
    // the complete next-PC/X/A/CCR frame. The vector fetch clears edge INT.
    firmware[14'h1580] = 8'h8e;
    firmware[14'h1590] = 8'h80;
    firmware[14'h1ffa] = 8'h15; firmware[14'h1ffb] = 8'h90;
    int_n = 1'b1;
    reset_to(14'h1580);
    int_n = 1'b0;
    run_instruction(8'h8e);
    if (waiting_state || stopped_state || irq_vector != 16'h1ffa) begin
      $fatal(1, "HD63705V0 pending INT entered STOP wait=%b stop=%b vector=%04x",
             waiting_state, stopped_state, irq_vector);
    end
    wait_for_interrupt(14'h1590);
    if (debug_sp != 16'h00fa || dut.ram[191] != 8'h81 ||
        dut.ram[190] != 8'hd5 || dut.ram[189] != 8'h00 ||
        dut.ram[188] != 8'h00 || dut.ram[187][3] != 1'b0 || int_irq) begin
      $fatal(1, "HD63705V0 STOP pending frame/clear sp=%04x int=%b",
             debug_sp, int_irq);
    end
    int_n = 1'b1;
    checks = checks + 2;

    // The 14-bit PC stores both unused PCH bits as ones for subroutine calls.
    firmware[14'h15a0] = 8'had; firmware[14'h15a1] = 8'h01;
    firmware[14'h15a3] = 8'h81;
    reset_to(14'h15a0);
    run_instruction(8'had);
    if (debug_sp != 16'h00fd || dut.ram[191] != 8'ha2 ||
        dut.ram[190] != 8'hd5) begin
      $fatal(1, "HD63705V0 BSR frame sp=%04x PCL=%02x PCH=%02x",
             debug_sp, dut.ram[191], dut.ram[190]);
    end
    run_instruction(8'h81);
    if (debug_sp != 16'h00ff || debug_pc[13:0] != 14'h15a2) begin
      $fatal(1, "HD63705V0 RTS restore sp=%04x pc=%04x", debug_sp, debug_pc);
    end
    checks = checks + 1;

    // Masked INT2 and timer requests do not prevent STOP. Their request bits
    // are still captured; figure 2-18 then normalizes the timer request.
    firmware[14'h15c0] = 8'ha6; firmware[14'h15c1] = 8'h01;
    firmware[14'h15c2] = 8'hb7; firmware[14'h15c3] = 8'h08;
    firmware[14'h15c4] = 8'ha6; firmware[14'h15c5] = 8'h40;
    firmware[14'h15c6] = 8'hb7; firmware[14'h15c7] = 8'h09;
    firmware[14'h15c8] = 8'h8e;
    int2_n = 1'b1;
    reset_to(14'h15c0);
    run_instruction(8'ha6); run_instruction(8'hb7);
    run_instruction(8'ha6); run_instruction(8'hb7);
    int2_n = 1'b0;
    run_instruction(8'h8e);
    tick();
    if (!stopped_state || !debug_mr[7] || debug_tcr[7] ||
        debug_tcr[6] != 1'b1) begin
      $fatal(1, "HD63705V0 masked requests blocked STOP stop=%b MR=%02x TCR=%02x",
             stopped_state, debug_mr, debug_tcr);
    end
    int2_n = 1'b1;
    checks = checks + 2;

    // External-clock synchronous transmit and receive exercise all eight bits.
    firmware[14'h1600] = 8'ha6; firmware[14'h1601] = 8'hf0;
    firmware[14'h1602] = 8'hb7; firmware[14'h1603] = 8'h10;
    firmware[14'h1604] = 8'ha6; firmware[14'h1605] = 8'h30;
    firmware[14'h1606] = 8'hb7; firmware[14'h1607] = 8'h11;
    firmware[14'h1608] = 8'ha6; firmware[14'h1609] = 8'ha5;
    firmware[14'h160a] = 8'hb7; firmware[14'h160b] = 8'h12;
    port_d_in = 7'h7f;
    reset_to(14'h1600);
    run_instruction(8'ha6); run_instruction(8'hb7);
    run_instruction(8'ha6); run_instruction(8'hb7);
    run_instruction(8'ha6); run_instruction(8'hb7);
    if ((port_d_oe & 7'h38) != 7'h08) begin
      $fatal(1, "HD63705V0 SCI direction overrides %02x", port_d_oe);
    end
    transmitted = 8'h00;
    for (index = 0; index < 8; index = index + 1) begin
      port_d_in = 7'h0f;
      port_d_in[4] = receive_pattern[index];
      tick();
      transmitted[index] = sci_tx;
      port_d_in[5] = 1'b1;
      tick();
    end
    if (transmitted != 8'ha5 || debug_sdr != 8'h3c || !debug_ssr[7]) begin
      $fatal(1, "HD63705V0 SCI transfer tx=%02x rx=%02x ssr=%02x",
             transmitted, debug_sdr, debug_ssr);
    end
    checks = checks + 2;

    // The normalized wrapper follows figure 2-18 for timer/SCI STOP fields;
    // section 2.9 prose/table 2-5 conflicts and is tracked in the device spec.
    firmware[14'h1800] = 8'ha6; firmware[14'h1801] = 8'h00;
    firmware[14'h1802] = 8'hb7; firmware[14'h1803] = 8'h09;
    firmware[14'h1804] = 8'ha6; firmware[14'h1805] = 8'h00;
    firmware[14'h1806] = 8'hb7; firmware[14'h1807] = 8'h11;
    firmware[14'h1808] = 8'ha6; firmware[14'h1809] = 8'h12;
    firmware[14'h180a] = 8'hb7; firmware[14'h180b] = 8'h08;
    firmware[14'h180c] = 8'h8e;
    firmware[14'h1900] = 8'h80;
    firmware[14'h1ffa] = 8'h19; firmware[14'h1ffb] = 8'h00;
    reset_to(14'h1800);
    run_instruction(8'ha6); run_instruction(8'hb7);
    run_instruction(8'ha6); run_instruction(8'hb7);
    run_instruction(8'ha6); run_instruction(8'hb7); run_instruction(8'h8e);
    tick();
    if (!stopped_state || debug_timer != 8'hf0 ||
        (debug_tcr & 8'hc0) != 8'h40 || (debug_ssr & 8'hf0) != 8'h30) begin
      $fatal(1, "HD63705V0 STOP state stop=%b tdr=%02x tcr=%02x ssr=%02x",
             stopped_state, debug_timer, debug_tcr, debug_ssr);
    end
    checks = checks + 1;
    int_n = 1'b0;
    wait_for_interrupt(14'h1900);
    int_n = 1'b1;

    // STBY asynchronously resets registers and makes pins high impedance while
    // preserving the physical RAM written in the first program.
    standby_n = 1'b0;
    #1;
    if (port_a_oe != 8'h00 || port_b_oe != 8'h00 || port_c_oe != 8'h00 ||
        port_d_oe != 7'h00 || debug_tcr != 8'h50 || debug_mr != 8'h5f) begin
      $fatal(1, "HD63705V0 standby reset/high impedance");
    end
    checks = checks + 1;
    reset_n = 1'b0;
    standby_n = 1'b1;
    firmware[14'h1a00] = 8'hb6; firmware[14'h1a01] = 8'h40;
    reset_to(14'h1a00);
    run_instruction(8'hb6);
    if (debug_a != 8'hac) $fatal(1, "HD63705V0 standby RAM retention %02x", debug_a);
    checks = checks + 1;

    // Normalized EPROM mode maps the twelve physical address pins onto the
    // internal 1000-1FFF image and implements every Table 2-9 digital state.
    firmware[14'h1123] = 8'h5a;
    eprom_address = 12'h123;
    eprom_mode = 1'b1;
    eprom_read_voltage = 1'b0;
    eprom_vpp = 1'b1;
    eprom_ce_n = 1'b1;
    eprom_oe_n = 1'b0;
    #1;
    if (program_address != 14'h1123 || !program_read || !eprom_data_oe ||
        eprom_data_out != 8'h5a || port_a_oe != 8'h00) begin
      $fatal(1, "HD63705V0 EPROM verify address=%04x read=%b oe=%b data=%02x",
             program_address, program_read, eprom_data_oe, eprom_data_out);
    end
    checks = checks + 1;

    // Verification explicitly treats CE as don't-care.
    eprom_ce_n = 1'b0;
    #1;
    if (!program_read || !eprom_data_oe || eprom_program) begin
      $fatal(1, "HD63705V0 EPROM verify CE-don't-care");
    end
    checks = checks + 1;

    // Programming: VPP, CE low, and OE high.
    eprom_oe_n = 1'b1;
    eprom_ce_n = 1'b0;
    eprom_data_in = 8'hc3;
    #1;
    if (!eprom_program || eprom_program_data != 8'hc3 || program_read ||
        eprom_data_oe) begin
      $fatal(1, "HD63705V0 EPROM program control");
    end
    checks = checks + 1;

    // Program/verify disable: VPP with both controls high.
    eprom_ce_n = 1'b1;
    #1;
    if (eprom_program || program_read || eprom_data_oe) begin
      $fatal(1, "HD63705V0 EPROM program/verify disable");
    end
    checks = checks + 1;

    // Ordinary read: +5 V, CE low, and OE low.
    eprom_vpp = 1'b0;
    eprom_read_voltage = 1'b1;
    eprom_ce_n = 1'b0;
    eprom_oe_n = 1'b0;
    #1;
    if (!program_read || !eprom_data_oe || eprom_program ||
        eprom_data_out != 8'h5a) begin
      $fatal(1, "HD63705V0 EPROM ordinary read");
    end
    checks = checks + 1;

    // Output disable: +5 V, CE low, and OE high.
    eprom_oe_n = 1'b1;
    #1;
    if (eprom_program || program_read || eprom_data_oe) begin
      $fatal(1, "HD63705V0 EPROM output disable");
    end
    checks = checks + 1;

    // No qualified TIMER/VPP level is a safe inactive normalization.
    eprom_read_voltage = 1'b0;
    eprom_ce_n = 1'b0;
    eprom_oe_n = 1'b0;
    #1;
    if (eprom_program || program_read || eprom_data_oe) begin
      $fatal(1, "HD63705V0 EPROM unqualified voltage");
    end
    checks = checks + 1;

    eprom_address = 12'h000;
    #1;
    if (program_address != 14'h1000) begin
      $fatal(1, "HD63705V0 EPROM low address boundary");
    end
    eprom_address = 12'hfff;
    #1;
    if (program_address != 14'h1fff) begin
      $fatal(1, "HD63705V0 EPROM high address boundary");
    end
    checks = checks + 2;
    eprom_mode = 1'b0;

    if (debug_address[15:14] != 2'b00 || debug_pc[15:14] != 2'b00 ||
        ((opcode_fetch !== 1'b0) && (opcode_fetch !== 1'b1)) ||
        ((sci_clock !== 1'b0) && (sci_clock !== 1'b1)) ||
        ((sci_irq !== 1'b0) && (sci_irq !== 1'b1)) ||
        (^debug_ccr === 1'bx) || port_b_out != 8'h00 ||
        port_c_out != 8'h00 || (^port_d_out === 1'bx) || debug_x != 8'h00) begin
      $fatal(1, "HD63705V0 deterministic outputs addr=%04x pc=%04x fetch=%b ccr=%02x pb=%02x pc=%02x x=%02x",
             debug_address, debug_pc, opcode_fetch, debug_ccr, port_b_out,
             port_c_out, debug_x);
    end
    $display("HD63705V0 MCU PASS: %0d memory, GPIO, timer, interrupt, SCI, low-power, and EPROM checks", checks);
    $finish;
  end
endmodule
