// SPDX-License-Identifier: MIT
module tb_mc6801_mcu #(
  parameter logic [2:0] TEST_MODE = 3'd2
);
  logic clk;
  logic reset_n;
  logic clock_enable;
  logic nmi_n;
  logic irq1_n;
  logic standby_power_ok;
  logic [7:0] port1_in;
  logic [4:0] port2_in;
  logic [7:0] port1_out;
  logic [7:0] port1_oe;
  logic [4:0] port2_out;
  logic [4:0] port2_oe;
  logic [15:0] external_address;
  logic [7:0] external_data_in;
  logic [7:0] external_data_out;
  logic external_write;
  logic external_valid;
  logic external_fetch;
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
  logic [7:0] debug_receive_data;
  logic [7:0] debug_opcode;
  logic [7:0] memory [0:65535];
  integer index;
  integer cycles;
  integer checks;

  mc6801_mcu #(.OPERATING_MODE(TEST_MODE)) dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(clock_enable),
    .nmi_n_i(nmi_n), .irq1_n_i(irq1_n),
    .standby_power_ok_i(standby_power_ok), .port1_i(port1_in),
    .port2_i(port2_in), .external_data_i(external_data_in),
    .external_address_o(external_address), .external_data_o(external_data_out),
    .external_write_o(external_write), .external_bus_valid_o(external_valid),
    .external_opcode_fetch_o(external_fetch), .port1_o(port1_out),
    .port1_oe_o(port1_oe), .port2_o(port2_out), .port2_oe_o(port2_oe),
    .sci_tx_o(sci_tx), .sci_clock_o(sci_clock), .timer_irq_o(timer_irq),
    .sci_irq_o(sci_irq), .opcode_fetch_o(opcode_fetch), .retire_o(retire),
    .illegal_o(illegal), .undefined_o(undefined_value), .waiting_o(waiting_state),
    .sleeping_o(sleeping_state),
    .interrupt_ack_o(interrupt_ack), .debug_address_o(debug_address),
    .debug_pc_o(debug_pc), .debug_sp_o(debug_sp), .debug_a_o(debug_a),
    .debug_b_o(debug_b), .debug_x_o(debug_x), .debug_ccr_o(debug_ccr),
    .debug_timer_o(debug_timer), .debug_output_compare_o(debug_compare),
    .debug_input_capture_o(debug_capture), .debug_tcsr_o(debug_tcsr),
    .debug_trcsr_o(debug_trcsr), .debug_receive_data_o(debug_receive_data),
    .debug_opcode_o(debug_opcode)
  );

  assign external_data_in = memory[external_address];
  always #5 clk <= ~clk;
  always_ff @(posedge clk) begin
    if (clock_enable && external_valid && external_write) begin
      memory[external_address] <= external_data_out;
    end
  end

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic ticks(input integer count);
    integer tick_index;
    begin
      for (tick_index = 0; tick_index < count; tick_index = tick_index + 1) tick();
    end
  endtask

  task automatic reset_to(input logic [15:0] address_value);
    begin
      memory[16'hfffe] = address_value[15:8];
      memory[16'hffff] = address_value[7:0];
      #1;
      reset_n = 1'b0;
      #1;
      if (!external_valid || external_address != 16'hfffe || external_write) begin
        $fatal(1, "MC6801 mode %0d reset vector high", TEST_MODE);
      end
      tick();
      reset_n = 1'b1;
      tick();
      if (!external_valid || external_address != 16'hffff || external_write) begin
        $fatal(1, "MC6801 mode %0d reset vector low", TEST_MODE);
      end
      tick();
      if (debug_pc != address_value || !debug_ccr[4]) begin
        $fatal(1, "MC6801 reset state pc=%04x ccr=%02x", debug_pc, debug_ccr);
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
        if (cycles > 24) $fatal(1, "MC6801 opcode %02x did not retire", expected_opcode);
      end while (!retire);
      if (debug_opcode != expected_opcode || illegal || undefined_value) begin
        $fatal(1, "MC6801 opcode %02x result/decode actual=%02x", expected_opcode,
               debug_opcode);
      end
    end
  endtask

  task automatic wait_for_interrupt(input logic [15:0] expected_pc);
    begin
      cycles = 0;
      do begin
        tick();
        cycles = cycles + 1;
        if (cycles > 80) $fatal(1, "MC6801 interrupt did not acknowledge");
      end while (!interrupt_ack);
      if (debug_pc != expected_pc) begin
        $fatal(1, "MC6801 interrupt vector pc=%04x expected=%04x", debug_pc, expected_pc);
      end
      checks = checks + 1;
    end
  endtask

  task automatic send_nrz_byte(input logic [7:0] value);
    integer bit_index;
    begin
      @(negedge clk);
      port2_in[3] = 1'b0;
      ticks(16);
      for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
        port2_in[3] = value[bit_index];
        ticks(16);
      end
      port2_in[3] = 1'b1;
      ticks(16);
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    clock_enable = 1'b1;
    nmi_n = 1'b1;
    irq1_n = 1'b1;
    standby_power_ok = 1'b1;
    port1_in = 8'h3c;
    port2_in = 5'h15;
    checks = 0;
    for (index = 0; index < 65536; index = index + 1) memory[index] = 8'h01;

    // Expanded-mode register exclusions, physical-pin reads, DDRs, and RAM.
    memory[16'h0200] = 8'h86; memory[16'h0201] = 8'ha5; // LDAA #A5
    memory[16'h0202] = 8'h97; memory[16'h0203] = 8'h02; // STAA PORT1
    memory[16'h0204] = 8'h86; memory[16'h0205] = 8'hf0;
    memory[16'h0206] = 8'h97; memory[16'h0207] = 8'h00; // STAA P1DDR
    memory[16'h0208] = 8'h96; memory[16'h0209] = 8'h02; // physical pins
    memory[16'h020a] = 8'h97; memory[16'h020b] = 8'h80; // RAM or external
    memory[16'h020c] = 8'h96; memory[16'h020d] = 8'h00; // DDR reads FF
    memory[16'h020e] = 8'h96; memory[16'h020f] = 8'h80;
    memory[16'h0210] = 8'h86; memory[16'h0211] = 8'h77;
    memory[16'h0212] = 8'h97; memory[16'h0213] = 8'h04; // external exclusion
    memory[16'h0214] = 8'h96; memory[16'h0215] = 8'h03; // mode plus Port 2 pins
    reset_to(16'h0200);
    if (port1_oe != 8'h00 || port2_oe != 5'h00 || debug_timer != 16'h0002 ||
        debug_compare != 16'hffff || debug_tcsr != 8'h00 || debug_trcsr != 8'h20) begin
      $fatal(1, "MC6801 peripheral reset state");
    end
    checks = checks + 1;
    run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h86); run_instruction(8'h97);
    if (port1_out != 8'ha5 || port1_oe != 8'hf0) $fatal(1, "MC6801 GPIO write");
    checks = checks + 1;
    run_instruction(8'h96);
    if (debug_a != 8'h3c) $fatal(1, "MC6801 physical pin read %02x", debug_a);
    run_instruction(8'h97);
    run_instruction(8'h96);
    if (debug_a != 8'hff) $fatal(1, "MC6801 DDR read %02x", debug_a);
    run_instruction(8'h96);
    if (debug_a != 8'h3c) $fatal(1, "MC6801 RAM/external read %02x", debug_a);
    if ((TEST_MODE == 3'd2 && memory[16'h0080] == 8'h3c) ||
        (TEST_MODE == 3'd3 && memory[16'h0080] != 8'h3c)) begin
      $fatal(1, "MC6801 mode %0d RAM decode", TEST_MODE);
    end
    checks = checks + 4;
    run_instruction(8'h86); run_instruction(8'h97);
    if (memory[16'h0004] != 8'h77) $fatal(1, "MC6801 Port 3 register exclusion");
    run_instruction(8'h96);
    if (debug_a != {TEST_MODE, 5'h15}) $fatal(1, "MC6801 mode pin read %02x", debug_a);
    checks = checks + 2;

    if (TEST_MODE == 3'd3) begin
      $display("MC6801/MC6803 MCU MODE 3 PASS: %0d register, GPIO, and external decode checks", checks);
      $finish;
    end

    // Falling-edge input capture uses the synchronized second E boundary.
    port2_in[0] = 1'b1;
    memory[16'h0300] = 8'h20; memory[16'h0301] = 8'hfe;
    memory[16'h0302] = 8'h96; memory[16'h0303] = 8'h08;
    memory[16'h0304] = 8'h96; memory[16'h0305] = 8'h0d;
    reset_to(16'h0300);
    @(negedge clk);
    port2_in[0] = 1'b0;
    ticks(3);
    if (!debug_tcsr[7] || debug_capture == 16'h0000) begin
      $fatal(1, "MC6801 synchronized input capture tcsr=%02x capture=%04x", debug_tcsr,
             debug_capture);
    end
    checks = checks + 1;
    memory[16'h0301] = 8'h00;
    run_instruction(8'h20);
    run_instruction(8'h96); run_instruction(8'h96);
    if (debug_tcsr[7]) $fatal(1, "MC6801 ICF ordered clear");
    checks = checks + 1;

    // Preset the free counter, allow the reset-value FFFF compare to become
    // pending, and prove IRQ1 remains above output compare in device priority.
    memory[16'h0400] = 8'h86; memory[16'h0401] = 8'h08;
    memory[16'h0402] = 8'h97; memory[16'h0403] = 8'h08; // EOCI
    memory[16'h0404] = 8'h86; memory[16'h0405] = 8'h00;
    memory[16'h0406] = 8'h97; memory[16'h0407] = 8'h09; // FRC=FFF8
    memory[16'h0408] = 8'h01; memory[16'h0409] = 8'h01;
    memory[16'h040a] = 8'h01; memory[16'h040b] = 8'h01;
    memory[16'h040c] = 8'h0e; // CLI
    memory[16'h040d] = 8'h01; // documented post-CLI instruction
    memory[16'h040e] = 8'h20; memory[16'h040f] = 8'hfe;
    memory[16'h0310] = 8'h3b; // IRQ1 handler RTI
    memory[16'h0320] = 8'h01; // output compare handler
    memory[16'hfff8] = 8'h03; memory[16'hfff9] = 8'h10;
    memory[16'hfff4] = 8'h03; memory[16'hfff5] = 8'h20;
    reset_to(16'h0400);
    run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h01); run_instruction(8'h01);
    run_instruction(8'h01); run_instruction(8'h01);
    if (!timer_irq || !debug_tcsr[6]) $fatal(1, "MC6801 output compare request");
    run_instruction(8'h0e);
    run_instruction(8'h01);
    tick(); // timer IRQ2 entry is now in progress
    irq1_n = 1'b0;
    tick(); // sampled IRQ1 must replace IRQ2 at the late priority encoder
    irq1_n = 1'b1;
    wait_for_interrupt(16'h0310);
    run_instruction(8'h3b);
    wait_for_interrupt(16'h0320);
    checks = checks + 2;

    // Latch IRQ2 during a TCSR-clearing instruction. The request survives,
    // but its unlatched timer identity is gone at late vector selection, so
    // the documented priority encoder must take the default SCI vector.
    port2_in[0] = 1'b1;
    memory[16'h0700] = 8'h86; memory[16'h0701] = 8'h10; // EICI
    memory[16'h0702] = 8'h97; memory[16'h0703] = 8'h08;
    memory[16'h0704] = 8'h0e; memory[16'h0705] = 8'h01;
    memory[16'h0706] = 8'h7f; memory[16'h0707] = 8'h00;
    memory[16'h0708] = 8'h08; // CLR $0008 removes IRQ2 identity
    memory[16'h0330] = 8'h01;
    memory[16'hfff0] = 8'h03; memory[16'hfff1] = 8'h30;
    reset_to(16'h0700);
    run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h0e); run_instruction(8'h01);
    tick(); // fetch CLR before presenting the capture edge
    @(negedge clk);
    port2_in[0] = 1'b0;
    run_instruction(8'h7f);
    if (!debug_tcsr[7] || debug_tcsr[4] || timer_irq) begin
      $fatal(1, "MC6801 IRQ2 identity removal tcsr=%02x irq=%b", debug_tcsr,
             timer_irq);
    end
    wait_for_interrupt(16'h0330);
    checks = checks + 1;

    // Internally clocked NRZ transmitter: nine-mark enable preamble, then a
    // 10-bit LSB-first frame. TDRE identifies the exact transfer boundary.
    memory[16'h0500] = 8'h86; memory[16'h0501] = 8'h04;
    memory[16'h0502] = 8'h97; memory[16'h0503] = 8'h10; // internal NRZ /16
    memory[16'h0504] = 8'h86; memory[16'h0505] = 8'h02;
    memory[16'h0506] = 8'h97; memory[16'h0507] = 8'h11; // TE
    memory[16'h0508] = 8'h96; memory[16'h0509] = 8'h11; // arm TDRE clear
    memory[16'h050a] = 8'h86; memory[16'h050b] = 8'ha5;
    memory[16'h050c] = 8'h97; memory[16'h050d] = 8'h13;
    memory[16'h050e] = 8'h20; memory[16'h050f] = 8'hfe;
    reset_to(16'h0500);
    run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h86); run_instruction(8'h97);
    if (port2_oe[4] != 1'b1) $fatal(1, "MC6801 SCI transmit mux");
    run_instruction(8'h96); run_instruction(8'h86); run_instruction(8'h97);
    if (debug_trcsr[5]) $fatal(1, "MC6801 TDRE clear sequence");
    cycles = 0;
    while (!debug_trcsr[5]) begin
      tick();
      cycles = cycles + 1;
      if (cycles > 220) begin
        $fatal(1, "MC6801 SCI preamble/transfer timeout timer=%04x trcsr=%02x tx=%b",
               debug_timer, debug_trcsr, sci_tx);
      end
    end
    if (sci_tx != 1'b0) $fatal(1, "MC6801 SCI start bit");
    ticks(16); if (sci_tx != 1'b1) $fatal(1, "MC6801 SCI data bit 0");
    ticks(16); if (sci_tx != 1'b0) $fatal(1, "MC6801 SCI data bit 1");
    ticks(16); if (sci_tx != 1'b1) $fatal(1, "MC6801 SCI data bit 2");
    ticks(16); if (sci_tx != 1'b0) $fatal(1, "MC6801 SCI data bit 3");
    ticks(16); if (sci_tx != 1'b0) $fatal(1, "MC6801 SCI data bit 4");
    ticks(16); if (sci_tx != 1'b1) $fatal(1, "MC6801 SCI data bit 5");
    ticks(16); if (sci_tx != 1'b0) $fatal(1, "MC6801 SCI data bit 6");
    ticks(16); if (sci_tx != 1'b1) $fatal(1, "MC6801 SCI data bit 7");
    ticks(16); if (sci_tx != 1'b1) $fatal(1, "MC6801 SCI stop bit");
    checks = checks + 11;
    memory[16'h050f] = 8'h00;
    memory[16'h0510] = 8'h86; memory[16'h0511] = 8'h00;
    memory[16'h0512] = 8'h97; memory[16'h0513] = 8'h01;
    memory[16'h0514] = 8'h97; memory[16'h0515] = 8'h11;
    do run_instruction(8'h20); while (debug_pc != 16'h0510);
    run_instruction(8'h86);
    run_instruction(8'h97); run_instruction(8'h97);
    if (!port2_oe[4]) $fatal(1, "MC6801 TE sticky DDR/ignored write");
    checks = checks + 1;

    // Receiver center sampling and status-before-data flag clearing.
    memory[16'h0600] = 8'h86; memory[16'h0601] = 8'h04;
    memory[16'h0602] = 8'h97; memory[16'h0603] = 8'h10;
    memory[16'h0604] = 8'h86; memory[16'h0605] = 8'h08;
    memory[16'h0606] = 8'h97; memory[16'h0607] = 8'h11; // RE
    memory[16'h0608] = 8'h20; memory[16'h0609] = 8'hfe;
    port2_in[3] = 1'b1;
    reset_to(16'h0600);
    run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h86); run_instruction(8'h97);
    send_nrz_byte(8'h5a);
    if (!debug_trcsr[7] || debug_trcsr[6] || debug_receive_data != 8'h5a) begin
      $fatal(1, "MC6801 SCI receive status=%02x data=%02x", debug_trcsr,
             debug_receive_data);
    end
    checks = checks + 2;
    send_nrz_byte(8'ha5);
    if (debug_trcsr[7:6] != 2'b11 || debug_receive_data != 8'h5a) begin
      $fatal(1, "MC6801 SCI overrun retention status=%02x data=%02x", debug_trcsr,
             debug_receive_data);
    end
    checks = checks + 2;
    memory[16'h0609] = 8'h00; // let the current BRA fall through
    memory[16'h060a] = 8'h96; memory[16'h060b] = 8'h11;
    memory[16'h060c] = 8'h96; memory[16'h060d] = 8'h12;
    do run_instruction(8'h20); while (debug_pc != 16'h060a);
    run_instruction(8'h96); run_instruction(8'h96);
    if (debug_a != 8'h5a || debug_trcsr[7:6] != 2'b00) begin
      $fatal(1, "MC6801 SCI receive clear status=%02x a=%02x", debug_trcsr, debug_a);
    end
    checks = checks + 1;
    memory[16'h060e] = 8'h86; memory[16'h060f] = 8'hff;
    memory[16'h0610] = 8'h97; memory[16'h0611] = 8'h01;
    memory[16'h0612] = 8'h86; memory[16'h0613] = 8'h00;
    memory[16'h0614] = 8'h97; memory[16'h0615] = 8'h11;
    run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h86); run_instruction(8'h97);
    if (port2_oe[3]) $fatal(1, "MC6801 RE sticky DDR/ignored write");
    checks = checks + 1;

    if (waiting_state || sleeping_state || illegal || undefined_value ||
        (^debug_ccr === 1'bx) ||
        ((external_fetch !== 1'b0) && (external_fetch !== 1'b1)) ||
        ((opcode_fetch !== 1'b0) && (opcode_fetch !== 1'b1)) ||
        debug_address != external_address || debug_sp === 16'hxxxx ||
        debug_x === 16'hxxxx || debug_b === 8'hxx ||
        (^port2_out === 1'bx) || ((sci_irq !== 1'b0) && (sci_irq !== 1'b1)) ||
        ((sci_clock !== 1'b0) && (sci_clock !== 1'b1))) begin
      $fatal(1, "MC6801 deterministic outputs");
    end
    $display("MC6801/MC6803 MCU MODE 2 PASS: %0d memory, GPIO, timer, priority, and SCI checks",
             checks);
    $finish;
  end
endmodule
