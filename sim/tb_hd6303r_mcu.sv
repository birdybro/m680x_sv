// SPDX-License-Identifier: MIT
module tb_hd6303r_mcu;
  logic clk;
  logic reset_n;
  logic standby_n;
  logic nmi_n;
  logic irq1_n;
  logic [4:0] port2_in;
  logic [15:0] external_address;
  logic [7:0] external_data_in;
  logic [7:0] external_data_out;
  logic external_write;
  logic external_valid;
  logic external_fetch;
  logic [7:0] port1_out;
  logic [7:0] port1_oe;
  logic [4:0] port2_out;
  logic [4:0] port2_oe;
  logic sci_tx;
  logic sci_clock;
  logic timer_irq;
  logic sci_irq;
  logic opcode_fetch;
  logic retire;
  logic illegal;
  logic undefined_value;
  logic waiting_state;
  logic sleeping_state;
  logic interrupt_ack;
  logic [15:0] debug_address;
  logic [15:0] debug_pc;
  logic [15:0] debug_sp;
  logic [7:0] debug_a;
  logic [7:0] debug_b;
  logic [15:0] debug_x;
  logic [5:0] debug_ccr;
  logic [15:0] debug_timer;
  logic [15:0] debug_compare;
  logic [15:0] debug_capture;
  logic [7:0] debug_tcsr;
  logic [7:0] debug_trcsr;
  logic [7:0] debug_receive;
  logic [7:0] debug_opcode;
  logic [7:0] memory [0:65535];
  integer index;
  integer cycles;
  integer checks;
  logic [15:0] sleeping_timer;

  hd6303r_mcu dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(1'b1),
    .standby_n_i(standby_n),
    .nmi_n_i(nmi_n), .irq1_n_i(irq1_n), .standby_power_ok_i(1'b1),
    .port1_i(8'h3c), .port2_i(port2_in), .external_data_i(external_data_in),
    .external_address_o(external_address), .external_data_o(external_data_out),
    .external_write_o(external_write), .external_bus_valid_o(external_valid),
    .external_opcode_fetch_o(external_fetch), .port1_o(port1_out),
    .port1_oe_o(port1_oe), .port2_o(port2_out), .port2_oe_o(port2_oe),
    .sci_tx_o(sci_tx), .sci_clock_o(sci_clock), .timer_irq_o(timer_irq),
    .sci_irq_o(sci_irq), .opcode_fetch_o(opcode_fetch), .retire_o(retire),
    .illegal_o(illegal), .undefined_o(undefined_value), .waiting_o(waiting_state),
    .sleeping_o(sleeping_state), .interrupt_ack_o(interrupt_ack),
    .debug_address_o(debug_address), .debug_pc_o(debug_pc),
    .debug_sp_o(debug_sp), .debug_a_o(debug_a), .debug_b_o(debug_b),
    .debug_x_o(debug_x), .debug_ccr_o(debug_ccr), .debug_timer_o(debug_timer),
    .debug_output_compare_o(debug_compare), .debug_input_capture_o(debug_capture),
    .debug_tcsr_o(debug_tcsr), .debug_trcsr_o(debug_trcsr),
    .debug_receive_data_o(debug_receive), .debug_opcode_o(debug_opcode)
  );

  assign external_data_in = memory[external_address];
  always #5 clk <= ~clk;
  always_ff @(posedge clk) begin
    if (external_valid && external_write) memory[external_address] <= external_data_out;
  end

  task automatic tick;
    begin @(posedge clk); #1; end
  endtask

  task automatic ticks(input integer count);
    integer tick_index;
    begin
      for (tick_index = 0; tick_index < count; tick_index = tick_index + 1) tick();
    end
  endtask

  task automatic send_misframed_byte(input logic [7:0] value);
    integer bit_index;
    begin
      @(negedge clk);
      port2_in[3] = 1'b0;
      ticks(16);
      for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
        port2_in[3] = value[bit_index];
        ticks(16);
      end
      port2_in[3] = 1'b0;
      ticks(16);
    end
  endtask

  task automatic run_instruction(input logic [7:0] expected_opcode);
    begin
      cycles = 0;
      do begin
        tick();
        cycles = cycles + 1;
        if (cycles > 20) $fatal(1, "HD6303R opcode %02x did not retire", expected_opcode);
      end while (!retire);
      if (debug_opcode != expected_opcode || illegal || undefined_value) begin
        $fatal(1, "HD6303R opcode mismatch expected=%02x actual=%02x",
               expected_opcode, debug_opcode);
      end
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    standby_n = 1'b1;
    nmi_n = 1'b1;
    irq1_n = 1'b1;
    port2_in = 5'h1d;
    checks = 0;
    for (index = 0; index < 65536; index = index + 1) memory[index] = 8'h01;

    memory[16'hfffe] = 8'h02; memory[16'hffff] = 8'h00;
    memory[16'hffee] = 8'h03; memory[16'hffef] = 8'h00;
    memory[16'h0200] = 8'h8e; memory[16'h0201] = 8'h01; memory[16'h0202] = 8'hff;
    memory[16'h0203] = 8'h86; memory[16'h0204] = 8'h0f;
    memory[16'h0205] = 8'h97; memory[16'h0206] = 8'h80;
    memory[16'h0207] = 8'h71; memory[16'h0208] = 8'hf0; memory[16'h0209] = 8'h80;
    memory[16'h020a] = 8'h96; memory[16'h020b] = 8'h80;
    memory[16'h020c] = 8'hce; memory[16'h020d] = 8'h12; memory[16'h020e] = 8'h34;
    memory[16'h020f] = 8'hcc; memory[16'h0210] = 8'hab; memory[16'h0211] = 8'hcd;
    memory[16'h0212] = 8'h18;
    memory[16'h0213] = 8'h1a;
    memory[16'h0214] = 8'h86; memory[16'h0215] = 8'h5a;
    memory[16'h0216] = 8'h00;
    memory[16'h0300] = 8'h01;

    #1; reset_n = 1'b0; #1; reset_n = 1'b1;
    tick(); tick();
    if (debug_pc != 16'h0200 || !debug_ccr[4] || external_address != 16'h0200) begin
      $fatal(1, "HD6303R reset/external vector state");
    end
    checks = checks + 1;

    run_instruction(8'h8e);
    run_instruction(8'h86);
    run_instruction(8'h97);
    run_instruction(8'h71);
    run_instruction(8'h96);
    if (debug_a != 8'h00 || memory[16'h0080] != 8'h01) begin
      $fatal(1, "HD6303R internal RAM/AIM result a=%02x external=%02x",
             debug_a, memory[16'h0080]);
    end
    checks = checks + 2;

    run_instruction(8'hce);
    run_instruction(8'hcc);
    run_instruction(8'h18);
    if ({debug_a, debug_b} != 16'h1234 || debug_x != 16'habcd) begin
      $fatal(1, "HD6303R XGDX result d=%04x x=%04x", {debug_a, debug_b}, debug_x);
    end
    checks = checks + 1;

    run_instruction(8'h1a);
    if (!sleeping_state) $fatal(1, "HD6303R SLP did not enter sleep");
    sleeping_timer = debug_timer;
    ticks(4);
    if (!sleeping_state || debug_timer != sleeping_timer + 16'd4) begin
      $fatal(1, "HD6303R sleep peripheral clocking");
    end
    irq1_n = 1'b0;
    tick();
    irq1_n = 1'b1;
    if (sleeping_state || interrupt_ack || debug_sp != 16'h01ff) begin
      $fatal(1, "HD6303R masked IRQ sleep release");
    end
    run_instruction(8'h86);
    if (debug_a != 8'h5a) $fatal(1, "HD6303R masked wake resume");
    checks = checks + 3;

    cycles = 0;
    do begin
      tick();
      cycles = cycles + 1;
      if (cycles > 16) $fatal(1, "HD6303R opcode TRAP did not acknowledge");
    end while (!interrupt_ack);
    if (debug_pc != 16'h0300 || debug_sp != 16'h01f8 || illegal || retire) begin
      $fatal(1, "HD6303R opcode TRAP state pc=%04x sp=%04x", debug_pc, debug_sp);
    end
    checks = checks + 1;

    // A simultaneous NMI must retain priority over a masked IRQ wake request.
    memory[16'hfffe] = 8'h02; memory[16'hffff] = 8'h40;
    memory[16'hfffc] = 8'h03; memory[16'hfffd] = 8'h40;
    memory[16'h0240] = 8'h8e; memory[16'h0241] = 8'h01; memory[16'h0242] = 8'hff;
    memory[16'h0243] = 8'h1a;
    #1; reset_n = 1'b0; #1; reset_n = 1'b1;
    tick(); tick();
    run_instruction(8'h8e);
    run_instruction(8'h1a);
    nmi_n = 1'b0;
    irq1_n = 1'b0;
    cycles = 0;
    do begin
      tick();
      cycles = cycles + 1;
      if (cycles > 16) $fatal(1, "HD6303R simultaneous NMI did not acknowledge");
    end while (!interrupt_ack);
    nmi_n = 1'b1;
    irq1_n = 1'b1;
    if (debug_pc != 16'h0340 || debug_sp != 16'h01f8) begin
      $fatal(1, "HD6303R simultaneous NMI priority pc=%04x", debug_pc);
    end
    checks = checks + 1;

    // HD6303R shares the HD6301V1 rule: ORFE is set on a missing stop bit,
    // but the misframed shift-register byte is not transferred into RDR.
    memory[16'hfffe] = 8'h04; memory[16'hffff] = 8'h00;
    memory[16'h0400] = 8'h86; memory[16'h0401] = 8'h04;
    memory[16'h0402] = 8'h97; memory[16'h0403] = 8'h10;
    memory[16'h0404] = 8'h86; memory[16'h0405] = 8'h08;
    memory[16'h0406] = 8'h97; memory[16'h0407] = 8'h11;
    memory[16'h0408] = 8'h20; memory[16'h0409] = 8'hfe;
    port2_in[3] = 1'b1;
    #1; reset_n = 1'b0; #1; reset_n = 1'b1;
    tick(); tick();
    run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h86); run_instruction(8'h97);
    send_misframed_byte(8'ha5);
    if (!debug_trcsr[6] || debug_trcsr[7] || debug_receive != 8'h00) begin
      $fatal(1, "HD6303R framing-error RDR inhibition trcsr=%02x rdr=%02x",
             debug_trcsr, debug_receive);
    end
    checks = checks + 1;

    // Hitachi permits a double-byte store to replace the full FRC and sets
    // TOF only when the counter subsequently rolls from FFFF to 0000.
    memory[16'hfffe] = 8'h05; memory[16'hffff] = 8'h00;
    memory[16'h0500] = 8'hcc; memory[16'h0501] = 8'ha5;
    memory[16'h0502] = 8'h5a;
    memory[16'h0503] = 8'hdd; memory[16'h0504] = 8'h09;
    memory[16'h0505] = 8'hcc; memory[16'h0506] = 8'hff;
    memory[16'h0507] = 8'hfe;
    memory[16'h0508] = 8'hdd; memory[16'h0509] = 8'h09;
    memory[16'h050a] = 8'h20; memory[16'h050b] = 8'hfe;
    #1; reset_n = 1'b0; #1; reset_n = 1'b1;
    tick(); tick();
    run_instruction(8'hcc); run_instruction(8'hdd);
    if (debug_timer != 16'ha55a) $fatal(1, "HD6303R FRC double write");
    run_instruction(8'hcc); run_instruction(8'hdd);
    if (debug_timer != 16'hfffe) $fatal(1, "HD6303R FRC rollover preset");
    tick();
    if (debug_timer != 16'hffff || debug_tcsr[5]) begin
      $fatal(1, "HD6303R early TOF timer=%04x tcsr=%02x", debug_timer, debug_tcsr);
    end
    tick();
    if (debug_timer != 16'h0000 || !debug_tcsr[5]) begin
      $fatal(1, "HD6303R rollover TOF timer=%04x tcsr=%02x", debug_timer, debug_tcsr);
    end
    checks = checks + 2;

    // HD6303R shares the V1 E-synchronous STBY boundary. External bus
    // qualification and GPIO drive stop while retained RAM remains intact.
    memory[16'hfffe] = 8'h06; memory[16'hffff] = 8'h00;
    memory[16'h0600] = 8'h8e; memory[16'h0601] = 8'h01;
    memory[16'h0602] = 8'hff;
    memory[16'h0603] = 8'h86; memory[16'h0604] = 8'ha5;
    memory[16'h0605] = 8'h97; memory[16'h0606] = 8'h80;
    memory[16'h0607] = 8'h86; memory[16'h0608] = 8'hc0;
    memory[16'h0609] = 8'h97; memory[16'h060a] = 8'h14;
    memory[16'h060b] = 8'h86; memory[16'h060c] = 8'hff;
    memory[16'h060d] = 8'h97; memory[16'h060e] = 8'h00;
    memory[16'h060f] = 8'h20; memory[16'h0610] = 8'hfe;
    memory[16'h0620] = 8'h96; memory[16'h0621] = 8'h14;
    memory[16'h0622] = 8'h96; memory[16'h0623] = 8'h80;
    memory[16'h0624] = 8'h20; memory[16'h0625] = 8'hfe;
    #1; reset_n = 1'b0; #1; reset_n = 1'b1;
    tick(); tick();
    run_instruction(8'h8e);
    run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h86); run_instruction(8'h97);
    if (port1_oe != 8'hff) $fatal(1, "HD6303R standby setup DDR");
    memory[16'hfffe] = 8'h06; memory[16'hffff] = 8'h20;
    standby_n = 1'b0;
    #1;
    if (port1_oe != 8'hff) $fatal(1, "HD6303R STBY was not E-synchronous");
    tick();
    if (port1_oe != 8'h00 || port2_oe != 5'h00 || external_valid ||
        debug_timer != 16'h0000) begin
      $fatal(1, "HD6303R standby reset/high impedance");
    end
    ticks(2);
    standby_n = 1'b1;
    cycles = 0;
    do begin
      tick();
      cycles = cycles + 1;
      if (cycles > 5) $fatal(1, "HD6303R standby release did not reset-vector");
    end while (debug_pc != 16'h0620 || !opcode_fetch);
    run_instruction(8'h96);
    if (debug_a != 8'hc0) $fatal(1, "HD6303R retained STBY_PWR %02x", debug_a);
    run_instruction(8'h96);
    if (debug_a != 8'ha5) $fatal(1, "HD6303R standby RAM retention %02x", debug_a);
    checks = checks + 6;

    if (waiting_state || undefined_value || port1_oe != 8'h00 ||
        port2_oe != 5'h00 || debug_address != external_address ||
        ((external_fetch !== 1'b0) && (external_fetch !== 1'b1)) ||
        ((opcode_fetch !== 1'b0) && (opcode_fetch !== 1'b1)) ||
        ((sci_tx !== 1'b0) && (sci_tx !== 1'b1)) ||
        ((sci_clock !== 1'b0) && (sci_clock !== 1'b1)) ||
        timer_irq || sci_irq || (^port1_out === 1'bx) || (^port2_out === 1'bx) ||
        (^debug_ccr === 1'bx) ||
        debug_compare !== 16'hffff || debug_capture === 16'hxxxx ||
        debug_tcsr === 8'hxx || debug_trcsr === 8'hxx || debug_receive === 8'hxx) begin
      $fatal(1, "HD6303R deterministic device outputs");
    end
    $display("HD6303R MODE 2 PASS: %0d ISA, RAM, low-power, timer, SCI, and TRAP checks", checks);
    $finish;
  end
endmodule
