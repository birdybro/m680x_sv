// SPDX-License-Identifier: MIT
module tb_hd63701v0_mcu;
  logic clk;
  logic reset_n;
  logic standby_n;
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
  integer trap_program_reads;

  hd63701v0_mcu dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(1'b1),
    .standby_n_i(standby_n),
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
      #1;
    end
  endtask

  task automatic ticks(input integer count);
    integer tick_index;
    begin
      for (tick_index = 0; tick_index < count; tick_index = tick_index + 1) tick();
    end
  endtask

  task automatic reset_to(input logic [15:0] target);
    begin
      firmware[12'hffe] = target[15:8];
      firmware[12'hfff] = target[7:0];
      #1; reset_n = 1'b0; #1;
      if (!program_read || program_address != 16'hfffe) begin
        $fatal(1, "HD63701V0 reset vector high is not internal EPROM");
      end
      reset_n = 1'b1;
      tick();
      if (!program_read || program_address != 16'hffff) begin
        $fatal(1, "HD63701V0 reset vector low is not internal EPROM");
      end
      tick();
      if (debug_pc != target || !debug_ccr[4] || program_address != target) begin
        $fatal(1, "HD63701V0 Mode 7 reset state pc=%04x", debug_pc);
      end
      if (port2_out[1] != 1'b0) $fatal(1, "HD63701V0 OLVL reset is not zero");
      checks = checks + 2;
    end
  endtask

  task automatic run_instruction(input logic [7:0] expected_opcode);
    begin
      cycles = 0;
      do begin
        tick();
        cycles = cycles + 1;
        if (cycles > 20) begin
          $fatal(1, "HD63701V0 opcode %02x did not retire", expected_opcode);
        end
      end while (!retire);
      if (debug_opcode != expected_opcode || illegal || undefined_value) begin
        $fatal(1, "HD63701V0 opcode mismatch expected=%02x actual=%02x",
               expected_opcode, debug_opcode);
      end
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

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    standby_n = 1'b1;
    nmi_n = 1'b1;
    irq1_n = 1'b1;
    is3_n = 1'b1;
    port2_in = 5'h1d;
    port3_in = 8'h3c;
    port4_in = 8'hc3;
    checks = 0;
    for (index = 0; index < 4096; index = index + 1) firmware[index] = 8'h01;

    // Execute at both ends of the documented 0040-00FF RAM window. Allowing
    // fetches from 0040-007F is the explicit normalized policy for the
    // manual's conflicting Mode-7 address-error table and physical RAM map.
    firmware[12'h000] = 8'h8e; firmware[12'h001] = 8'h00;
    firmware[12'h002] = 8'hfe;
    firmware[12'h003] = 8'h86; firmware[12'h004] = 8'h01;
    firmware[12'h005] = 8'h97; firmware[12'h006] = 8'h40;
    firmware[12'h007] = 8'h7e; firmware[12'h008] = 8'h00;
    firmware[12'h009] = 8'h40;
    reset_to(16'hf000);
    run_instruction(8'h8e); run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h7e); run_instruction(8'h01);
    if (debug_pc != 16'h0041 || program_read || interrupt_ack) begin
      $fatal(1, "HD63701V0 executable RAM lower boundary");
    end
    checks = checks + 1;

    firmware[12'h020] = 8'h86; firmware[12'h021] = 8'h01;
    firmware[12'h022] = 8'h97; firmware[12'h023] = 8'hff;
    firmware[12'h024] = 8'h7e; firmware[12'h025] = 8'h00;
    firmware[12'h026] = 8'hff;
    reset_to(16'hf020);
    run_instruction(8'h86); run_instruction(8'h97); run_instruction(8'h7e);
    run_instruction(8'h01);
    if (debug_pc != 16'h0100) $fatal(1, "HD63701V0 RAM upper boundary");
    checks = checks + 1;

    // The unambiguous 0100-EFFF non-memory range traps on instruction fetch.
    firmware[12'h040] = 8'h8e; firmware[12'h041] = 8'h00;
    firmware[12'h042] = 8'hfe;
    firmware[12'h043] = 8'h7e; firmware[12'h044] = 8'h01;
    firmware[12'h045] = 8'h00;
    firmware[12'h140] = 8'h01;
    firmware[12'hfee] = 8'hf1; firmware[12'hfef] = 8'h40;
    reset_to(16'hf040);
    run_instruction(8'h8e); run_instruction(8'h7e);
    cycles = 0;
    trap_program_reads = 0;
    do begin
      if (cycles == 0 && (program_read || debug_address != 16'h0100 || !opcode_fetch)) begin
        $fatal(1, "HD63701V0 non-memory fetch decode");
      end
      if (program_read) trap_program_reads = trap_program_reads + 1;
      tick();
      cycles = cycles + 1;
      if (cycles > 13) $fatal(1, "HD63701V0 address TRAP did not acknowledge");
    end while (!interrupt_ack);
    if (cycles != 13 || debug_pc != 16'hf140 || debug_sp != 16'h00f7 ||
        trap_program_reads != 4 || illegal || retire) begin
      $fatal(1, "HD63701V0 address TRAP cycles=%0d reads=%0d pc=%04x sp=%04x",
             cycles, trap_program_reads, debug_pc, debug_sp);
    end
    checks = checks + 2;

    // V0 transfers a misframed shift-register byte into RDR while setting
    // ORFE and leaving RDRF clear, unlike HD6301V1 and HD6303R.
    firmware[12'h200] = 8'h86; firmware[12'h201] = 8'h04;
    firmware[12'h202] = 8'h97; firmware[12'h203] = 8'h10;
    firmware[12'h204] = 8'h86; firmware[12'h205] = 8'h08;
    firmware[12'h206] = 8'h97; firmware[12'h207] = 8'h11;
    reset_to(16'hf200);
    run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h86); run_instruction(8'h97);
    send_misframed_byte(8'ha5);
    if (!debug_trcsr[6] || debug_trcsr[7] || debug_receive != 8'ha5) begin
      $fatal(1, "HD63701V0 framing transfer trcsr=%02x rdr=%02x",
             debug_trcsr, debug_receive);
    end
    checks = checks + 1;

    // V0 retains the Hitachi two-byte FRC write and TOF-at-zero rule.
    firmware[12'h240] = 8'hcc; firmware[12'h241] = 8'ha5;
    firmware[12'h242] = 8'h5a;
    firmware[12'h243] = 8'hdd; firmware[12'h244] = 8'h09;
    firmware[12'h245] = 8'h20; firmware[12'h246] = 8'hfe;
    reset_to(16'hf240);
    run_instruction(8'hcc); run_instruction(8'hdd);
    if (debug_timer != 16'ha55a) $fatal(1, "HD63701V0 FRC double write");
    checks = checks + 1;

    // Single-chip Port 3 and Port 4 remain full GPIO with their own DDRs.
    firmware[12'h280] = 8'h86; firmware[12'h281] = 8'hf0;
    firmware[12'h282] = 8'h97; firmware[12'h283] = 8'h04;
    firmware[12'h284] = 8'h86; firmware[12'h285] = 8'ha5;
    firmware[12'h286] = 8'h97; firmware[12'h287] = 8'h06;
    firmware[12'h288] = 8'h86; firmware[12'h289] = 8'h0f;
    firmware[12'h28a] = 8'h97; firmware[12'h28b] = 8'h05;
    firmware[12'h28c] = 8'h86; firmware[12'h28d] = 8'h5a;
    firmware[12'h28e] = 8'h97; firmware[12'h28f] = 8'h07;
    reset_to(16'hf280);
    run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h86); run_instruction(8'h97);
    if (port3_oe != 8'hf0 || port3_out != 8'ha5 ||
        port4_oe != 8'h0f || port4_out != 8'h5a) begin
      $fatal(1, "HD63701V0 Mode-7 GPIO");
    end
    #1; reset_n = 1'b0; #1;
    if (port3_oe != 8'h00 || port4_oe != 8'h00) begin
      $fatal(1, "HD63701V0 DDRs did not reset asynchronously");
    end
    reset_n = 1'b1;
    checks = checks + 3;

    // V0 STBY is asynchronous: active device state and pin drive disappear
    // immediately, while RAM and the retained STBY_PWR bit remain supplied.
    firmware[12'h300] = 8'h8e; firmware[12'h301] = 8'h00;
    firmware[12'h302] = 8'hfe;
    firmware[12'h303] = 8'h86; firmware[12'h304] = 8'ha5;
    firmware[12'h305] = 8'h97; firmware[12'h306] = 8'h40;
    firmware[12'h307] = 8'h86; firmware[12'h308] = 8'hc0;
    firmware[12'h309] = 8'h97; firmware[12'h30a] = 8'h14;
    firmware[12'h30b] = 8'h86; firmware[12'h30c] = 8'hff;
    firmware[12'h30d] = 8'h97; firmware[12'h30e] = 8'h00;
    firmware[12'h30f] = 8'h20; firmware[12'h310] = 8'hfe;
    firmware[12'h320] = 8'h96; firmware[12'h321] = 8'h14;
    firmware[12'h322] = 8'h96; firmware[12'h323] = 8'h40;
    firmware[12'h324] = 8'h20; firmware[12'h325] = 8'hfe;
    reset_to(16'hf300);
    run_instruction(8'h8e);
    run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h86); run_instruction(8'h97);
    run_instruction(8'h86); run_instruction(8'h97);
    if (port1_oe != 8'hff) $fatal(1, "HD63701V0 standby setup DDR");
    firmware[12'hffe] = 8'hf3; firmware[12'hfff] = 8'h20;
    standby_n = 1'b0;
    #1;
    if (port1_oe != 8'h00 || port2_oe != 5'h00 ||
        port3_oe != 8'h00 || port4_oe != 8'h00 || program_read ||
        debug_timer != 16'h0000) begin
      $fatal(1, "HD63701V0 asynchronous standby reset/high impedance");
    end
    ticks(2);
    standby_n = 1'b1;
    cycles = 0;
    do begin
      tick();
      cycles = cycles + 1;
      if (cycles > 4) $fatal(1, "HD63701V0 standby release did not reset-vector");
    end while (debug_pc != 16'hf320 || !opcode_fetch);
    run_instruction(8'h96);
    if (debug_a != 8'hc0) $fatal(1, "HD63701V0 retained STBY_PWR %02x", debug_a);
    run_instruction(8'h96);
    if (debug_a != 8'ha5) $fatal(1, "HD63701V0 standby RAM retention %02x", debug_a);
    checks = checks + 6;

    if (waiting_state || sleeping_state || undefined_value || timer_irq || sci_irq ||
        ((sci_tx !== 1'b0) && (sci_tx !== 1'b1)) ||
        ((sci_clock !== 1'b0) && (sci_clock !== 1'b1)) ||
        ((os3_n !== 1'b0) && (os3_n !== 1'b1)) ||
        (^port1_out === 1'bx) || (^port1_oe === 1'bx) ||
        (^port2_out === 1'bx) || (^port2_oe === 1'bx) ||
        (^debug_a === 1'bx) ||
        (^debug_ccr === 1'bx) || (^debug_timer === 1'bx) ||
        debug_compare !== 16'hffff || debug_capture === 16'hxxxx ||
        debug_tcsr === 8'hxx || debug_trcsr === 8'hxx ||
        debug_b === 8'hxx || debug_x === 16'hxxxx) begin
      $fatal(1, "HD63701V0 deterministic device outputs");
    end
    $display("HD63701V0 MODE 7 PASS: %0d EPROM, RAM, GPIO, low-power, SCI, and TRAP checks",
             checks);
    $finish;
  end
endmodule
