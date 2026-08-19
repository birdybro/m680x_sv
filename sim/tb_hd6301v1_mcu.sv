// SPDX-License-Identifier: MIT
module tb_hd6301v1_mcu;
  logic clk;
  logic reset_n;
  logic nmi_n;
  logic irq1_n;
  logic is3_n;
  logic [4:0] port2_in;
  logic [7:0] port3_in;
  logic [7:0] port4_in;
  logic [15:0] program_address;
  logic program_read;
  logic [7:0] program_data;
  logic [7:0] port1_out;
  logic [7:0] port1_oe;
  logic [4:0] port2_out;
  logic [4:0] port2_oe;
  logic [7:0] port3_out;
  logic [7:0] port3_oe;
  logic [7:0] port4_out;
  logic [7:0] port4_oe;
  logic os3_n;
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
  logic [7:0] firmware [0:4095];
  integer index;
  integer cycles;
  integer checks;
  integer os3_pulses;
  integer trap_program_reads;

  hd6301v1_mcu dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(1'b1),
    .nmi_n_i(nmi_n), .irq1_n_i(irq1_n), .standby_power_ok_i(1'b1),
    .port1_i(8'h3c), .port2_i(port2_in), .port3_i(port3_in),
    .port4_i(port4_in), .is3_n_i(is3_n),
    .program_address_o(program_address), .program_read_o(program_read),
    .program_data_i(program_data), .port1_o(port1_out), .port1_oe_o(port1_oe),
    .port2_o(port2_out), .port2_oe_o(port2_oe), .port3_o(port3_out),
    .port3_oe_o(port3_oe), .port4_o(port4_out), .port4_oe_o(port4_oe),
    .os3_n_o(os3_n), .sci_tx_o(sci_tx), .sci_clock_o(sci_clock),
    .timer_irq_o(timer_irq), .sci_irq_o(sci_irq), .opcode_fetch_o(opcode_fetch),
    .retire_o(retire), .illegal_o(illegal), .undefined_o(undefined_value),
    .waiting_o(waiting_state), .sleeping_o(sleeping_state),
    .interrupt_ack_o(interrupt_ack), .debug_address_o(debug_address),
    .debug_pc_o(debug_pc), .debug_sp_o(debug_sp), .debug_a_o(debug_a),
    .debug_b_o(debug_b), .debug_x_o(debug_x), .debug_ccr_o(debug_ccr),
    .debug_timer_o(debug_timer), .debug_output_compare_o(debug_compare),
    .debug_input_capture_o(debug_capture), .debug_tcsr_o(debug_tcsr),
    .debug_trcsr_o(debug_trcsr), .debug_receive_data_o(debug_receive),
    .debug_opcode_o(debug_opcode)
  );

  assign program_data = firmware[program_address[11:0]];
  always #5 clk <= ~clk;

  task automatic tick;
    begin
      @(posedge clk);
      if (!os3_n) os3_pulses = os3_pulses + 1;
      #1;
    end
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

  task automatic reset_to(input logic [15:0] target);
    begin
      firmware[12'hffe] = target[15:8];
      firmware[12'hfff] = target[7:0];
      #1; reset_n = 1'b0; #1;
      if (!program_read || program_address != 16'hfffe) begin
        $fatal(1, "HD6301V1 reset vector high is not internal program memory");
      end
      reset_n = 1'b1;
      tick();
      if (!program_read || program_address != 16'hffff) begin
        $fatal(1, "HD6301V1 reset vector low is not internal program memory");
      end
      tick();
      if (debug_pc != target || !debug_ccr[4] || program_address != target) begin
        $fatal(1, "HD6301V1 Mode 7 reset state pc=%04x", debug_pc);
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
          $fatal(1, "HD6301V1 opcode %02x did not retire", expected_opcode);
        end
      end while (!retire);
      if (debug_opcode != expected_opcode || illegal || undefined_value) begin
        $fatal(1, "HD6301V1 opcode mismatch expected=%02x actual=%02x",
               expected_opcode, debug_opcode);
      end
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    nmi_n = 1'b1;
    irq1_n = 1'b1;
    is3_n = 1'b1;
    port2_in = 5'h1d;
    port3_in = 8'h3c;
    port4_in = 8'hc3;
    checks = 0;
    os3_pulses = 0;
    for (index = 0; index < 4096; index = index + 1) firmware[index] = 8'h01;

    // GPIO, Port 3 input latch, ordered flag clear, and both OS3 selectors.
    firmware[12'h000] = 8'h8e; firmware[12'h001] = 8'h00;
    firmware[12'h002] = 8'hff;
    firmware[12'h003] = 8'h86; firmware[12'h004] = 8'hf0;
    firmware[12'h005] = 8'h97; firmware[12'h006] = 8'h04;
    firmware[12'h007] = 8'h86; firmware[12'h008] = 8'ha5;
    firmware[12'h009] = 8'h97; firmware[12'h00a] = 8'h06;
    firmware[12'h00b] = 8'h86; firmware[12'h00c] = 8'h0f;
    firmware[12'h00d] = 8'h97; firmware[12'h00e] = 8'h05;
    firmware[12'h00f] = 8'h86; firmware[12'h010] = 8'h5a;
    firmware[12'h011] = 8'h97; firmware[12'h012] = 8'h07;
    firmware[12'h013] = 8'h96; firmware[12'h014] = 8'h06;
    firmware[12'h015] = 8'h96; firmware[12'h016] = 8'h07;
    firmware[12'h017] = 8'h86; firmware[12'h018] = 8'h48;
    firmware[12'h019] = 8'h97; firmware[12'h01a] = 8'h0f;
    firmware[12'h01b] = 8'h1a;
    firmware[12'h01c] = 8'h96; firmware[12'h01d] = 8'h0f;
    firmware[12'h01e] = 8'h96; firmware[12'h01f] = 8'h06;
    firmware[12'h020] = 8'h96; firmware[12'h021] = 8'h0f;
    firmware[12'h022] = 8'h86; firmware[12'h023] = 8'h58;
    firmware[12'h024] = 8'h97; firmware[12'h025] = 8'h0f;
    firmware[12'h026] = 8'h86; firmware[12'h027] = 8'h3c;
    firmware[12'h028] = 8'h97; firmware[12'h029] = 8'h06;

    reset_to(16'hf000);
    run_instruction(8'h8e);
    run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h86); run_instruction(8'h97);
    if (port3_oe != 8'hf0 || port3_out != 8'ha5 || os3_pulses != 0) begin
      $fatal(1, "HD6301V1 Port 3 output/DDR or unselected OS3");
    end
    run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h86); run_instruction(8'h97);
    if (port4_oe != 8'h0f || port4_out != 8'h5a) begin
      $fatal(1, "HD6301V1 Port 4 output/DDR");
    end
    run_instruction(8'h96);
    if (debug_a != 8'h3c || os3_pulses != 1) $fatal(1, "HD6301V1 Port 3 pin read");
    run_instruction(8'h96);
    if (debug_a != 8'hc3) $fatal(1, "HD6301V1 Port 4 pin read");
    run_instruction(8'h86); run_instruction(8'h97); run_instruction(8'h1a);
    if (!sleeping_state) $fatal(1, "HD6301V1 SLP did not enter sleep");

    port3_in = 8'h96;
    is3_n = 1'b0;
    tick(); tick(); tick();
    is3_n = 1'b1;
    if (sleeping_state || interrupt_ack) $fatal(1, "masked IS3 did not resume SLP");
    run_instruction(8'h96);
    if (debug_a != 8'hef) $fatal(1, "HD6301V1 P3CSR flag/control read %02x", debug_a);
    run_instruction(8'h96);
    if (debug_a != 8'h96 || os3_pulses != 2) begin
      $fatal(1, "HD6301V1 Port 3 input latch/read strobe");
    end
    run_instruction(8'h96);
    if (debug_a != 8'h6f) $fatal(1, "HD6301V1 ordered IS3 flag clear %02x", debug_a);
    run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h86); run_instruction(8'h97);
    if (port3_out != 8'h3c || os3_pulses != 3) begin
      $fatal(1, "HD6301V1 write-selected OS3");
    end
    #1; reset_n = 1'b0; #1;
    if (port3_oe != 8'hf0) $fatal(1, "HD6301V1 DDR reset changed before E edge");
    tick();
    if (port3_oe != 8'h00) $fatal(1, "HD6301V1 DDR reset missed E edge");
    reset_n = 1'b1;
    checks = checks + 10;

    // The 128-byte RAM is executable; ordinary accesses to Mode-7 holes do
    // not become external bus cycles, while an instruction fetch does TRAP.
    firmware[12'h100] = 8'h8e; firmware[12'h101] = 8'h00;
    firmware[12'h102] = 8'hff;
    firmware[12'h103] = 8'h86; firmware[12'h104] = 8'h01;
    firmware[12'h105] = 8'h97; firmware[12'h106] = 8'h80;
    firmware[12'h107] = 8'h7e; firmware[12'h108] = 8'h00;
    firmware[12'h109] = 8'h80;
    reset_to(16'hf100);
    run_instruction(8'h8e); run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h7e); run_instruction(8'h01);
    if (debug_pc != 16'h0081 || interrupt_ack || program_read) begin
      $fatal(1, "HD6301V1 executable internal RAM");
    end
    checks = checks + 1;

    firmware[12'h120] = 8'h8e; firmware[12'h121] = 8'h00;
    firmware[12'h122] = 8'hff;
    firmware[12'h123] = 8'h7e; firmware[12'h124] = 8'h01;
    firmware[12'h125] = 8'h00;
    firmware[12'h140] = 8'h01;
    firmware[12'hfee] = 8'hf1; firmware[12'hfef] = 8'h40;
    reset_to(16'hf120);
    run_instruction(8'h8e); run_instruction(8'h7e);
    cycles = 0;
    trap_program_reads = 0;
    do begin
      if (cycles == 0 && (program_read || debug_address != 16'h0100 || !opcode_fetch)) begin
        $fatal(1, "HD6301V1 non-memory fetch decode");
      end
      if (program_read) trap_program_reads = trap_program_reads + 1;
      tick();
      cycles = cycles + 1;
      if (cycles > 13) $fatal(1, "HD6301V1 address TRAP did not acknowledge");
    end while (!interrupt_ack);
    if (cycles != 13 || debug_pc != 16'hf140 || debug_sp != 16'h00f8 ||
        trap_program_reads != 4 || illegal || retire) begin
      $fatal(1, "HD6301V1 Mode-7 address TRAP cycles=%0d reads=%0d pc=%04x",
             cycles, trap_program_reads, debug_pc);
    end
    checks = checks + 2;

    // HD6301V1 differs from MC6801 and HD63701V0: a framing error sets
    // ORFE without transferring the misframed shift-register byte into RDR.
    firmware[12'h300] = 8'h86; firmware[12'h301] = 8'h04;
    firmware[12'h302] = 8'h97; firmware[12'h303] = 8'h10;
    firmware[12'h304] = 8'h86; firmware[12'h305] = 8'h08;
    firmware[12'h306] = 8'h97; firmware[12'h307] = 8'h11;
    reset_to(16'hf300);
    run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h86); run_instruction(8'h97);
    send_misframed_byte(8'ha5);
    if (!debug_trcsr[6] || debug_trcsr[7] || debug_receive != 8'h00) begin
      $fatal(1, "HD6301V1 framing-error RDR inhibition trcsr=%02x rdr=%02x",
             debug_trcsr, debug_receive);
    end
    checks = checks + 1;

    // Hitachi permits a double-byte store to replace the full FRC. Its TOF
    // flag is asserted on FFFF-to-0000 rollover, one cycle later than MC6801.
    firmware[12'h340] = 8'hcc; firmware[12'h341] = 8'ha5;
    firmware[12'h342] = 8'h5a;
    firmware[12'h343] = 8'hdd; firmware[12'h344] = 8'h09;
    firmware[12'h345] = 8'hcc; firmware[12'h346] = 8'hff;
    firmware[12'h347] = 8'hfe;
    firmware[12'h348] = 8'hdd; firmware[12'h349] = 8'h09;
    firmware[12'h34a] = 8'h20; firmware[12'h34b] = 8'hfe;
    reset_to(16'hf340);
    run_instruction(8'hcc); run_instruction(8'hdd);
    if (debug_timer != 16'ha55a) $fatal(1, "HD6301V1 FRC double write");
    run_instruction(8'hcc); run_instruction(8'hdd);
    if (debug_timer != 16'hfffe) $fatal(1, "HD6301V1 FRC rollover preset");
    tick();
    if (debug_timer != 16'hffff || debug_tcsr[5]) begin
      $fatal(1, "HD6301V1 early TOF timer=%04x tcsr=%02x", debug_timer, debug_tcsr);
    end
    tick();
    if (debug_timer != 16'h0000 || !debug_tcsr[5]) begin
      $fatal(1, "HD6301V1 rollover TOF timer=%04x tcsr=%02x", debug_timer, debug_tcsr);
    end
    checks = checks + 2;

    // With I clear, the same IS3 flag is the documented IRQ1-priority source.
    firmware[12'h200] = 8'h8e; firmware[12'h201] = 8'h00;
    firmware[12'h202] = 8'hff;
    firmware[12'h203] = 8'h86; firmware[12'h204] = 8'h40;
    firmware[12'h205] = 8'h97; firmware[12'h206] = 8'h0f;
    firmware[12'h207] = 8'h0e;
    firmware[12'h208] = 8'h1a;
    firmware[12'h240] = 8'h01;
    firmware[12'hff8] = 8'hf2; firmware[12'hff9] = 8'h40;
    is3_n = 1'b1;
    reset_to(16'hf200);
    run_instruction(8'h8e); run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h0e); run_instruction(8'h1a);
    if (!sleeping_state || debug_ccr[4]) $fatal(1, "HD6301V1 CLI/SLP setup");
    is3_n = 1'b0;
    cycles = 0;
    do begin
      tick();
      cycles = cycles + 1;
      if (cycles > 20) $fatal(1, "HD6301V1 IS3 interrupt did not acknowledge");
    end while (!interrupt_ack);
    is3_n = 1'b1;
    if (debug_pc != 16'hf240 || debug_sp != 16'h00f8 || sleeping_state) begin
      $fatal(1, "HD6301V1 IS3 vector pc=%04x sp=%04x", debug_pc, debug_sp);
    end
    checks = checks + 2;

    if (waiting_state || undefined_value || port1_oe != 8'h00 ||
        port2_oe != 5'h00 || timer_irq || sci_irq ||
        ((sci_tx !== 1'b0) && (sci_tx !== 1'b1)) ||
        ((sci_clock !== 1'b0) && (sci_clock !== 1'b1)) ||
        (^port1_out === 1'bx) || (^port2_out === 1'bx) ||
        (^debug_ccr === 1'bx) || (^debug_timer === 1'bx) ||
        debug_compare !== 16'hffff ||
        debug_capture === 16'hxxxx || debug_tcsr === 8'hxx ||
        debug_trcsr === 8'hxx || debug_receive === 8'hxx ||
        debug_b === 8'hxx || debug_x === 16'hxxxx) begin
      $fatal(1, "HD6301V1 deterministic device outputs");
    end
    $display("HD6301V1 MODE 7 PASS: %0d memory, GPIO, SCI, strobe, TRAP, and IRQ checks",
             checks);
    $finish;
  end
endmodule
