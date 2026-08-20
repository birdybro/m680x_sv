// SPDX-License-Identifier: MIT
module tb_mc68705p5_mcu;
  logic clk;
  logic reset_n;
  logic clock_enable;
  logic int_n;
  logic timer_pin;
  logic [7:0] port_a_in;
  logic [7:0] port_b_in;
  logic [3:0] port_c_in;
  logic [7:0] port_a_out;
  logic [7:0] port_b_out;
  logic [3:0] port_c_out;
  logic [7:0] port_a_oe;
  logic [7:0] port_b_oe;
  logic [3:0] port_c_oe;
  logic [10:0] program_address;
  logic program_read;
  logic [7:0] program_data;
  logic vpp_present;
  logic bootstrap_voltage;
  logic bootstrap_mode;
  logic eprom_latch_enable;
  logic eprom_program_enable;
  logic [10:0] eprom_program_address;
  logic [7:0] eprom_program_data;
  logic timer_irq;
  logic external_irq;
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
  logic [7:0] debug_timer_control;
  logic [7:0] debug_program_control;
  logic [7:0] firmware [0:2047];
  integer index;
  integer cycles;
  integer checks;

  mc68705p5_mcu dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(clock_enable),
    .int_n_i(int_n), .timer_i(timer_pin), .port_a_i(port_a_in),
    .port_b_i(port_b_in), .port_c_i(port_c_in), .port_a_o(port_a_out),
    .port_b_o(port_b_out), .port_c_o(port_c_out), .port_a_oe_o(port_a_oe),
    .port_b_oe_o(port_b_oe), .port_c_oe_o(port_c_oe),
    .program_address_o(program_address), .program_read_o(program_read),
    .program_data_i(program_data), .vpp_present_i(vpp_present),
    .bootstrap_voltage_i(bootstrap_voltage), .bootstrap_mode_o(bootstrap_mode),
    .eprom_latch_enable_o(eprom_latch_enable),
    .eprom_program_enable_o(eprom_program_enable),
    .eprom_program_address_o(eprom_program_address),
    .eprom_program_data_o(eprom_program_data), .timer_irq_o(timer_irq),
    .external_irq_o(external_irq), .opcode_fetch_o(opcode_fetch),
    .retire_o(retire), .illegal_o(illegal), .undefined_o(undefined_value),
    .waiting_o(waiting_state), .stopped_o(stopped_state),
    .interrupt_ack_o(interrupt_ack), .debug_address_o(debug_address),
    .debug_pc_o(debug_pc), .debug_sp_o(debug_sp), .debug_a_o(debug_a),
    .debug_x_o(debug_x), .debug_ccr_o(debug_ccr),
    .debug_opcode_o(debug_opcode), .debug_instruction_cycles_o(debug_cycles),
    .debug_timer_o(debug_timer), .debug_timer_control_o(debug_timer_control),
    .debug_program_control_o(debug_program_control)
  );

  assign program_data = firmware[program_address];
  always #5 clk <= ~clk;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic reset_to(input logic [10:0] address_value);
    logic [10:0] vector_address;
    begin
      vector_address = bootstrap_voltage ? 11'h7f6 : 11'h7fe;
      firmware[vector_address] = {5'h00, address_value[10:8]};
      firmware[vector_address + 11'h001] = address_value[7:0];
      #1;
      reset_n = 1'b0;
      #1;
      if (!program_read || program_address != vector_address) begin
        $fatal(1, "P5 reset vector high address=%03x expected=%03x",
               program_address, vector_address);
      end
      tick();
      reset_n = 1'b1;
      tick();
      if (!program_read || program_address != vector_address + 11'h001) begin
        $fatal(1, "P5 reset vector low address=%03x expected=%03x",
               program_address, vector_address + 11'h001);
      end
      tick();
      if (debug_pc[10:0] != address_value || debug_sp != 16'h007f || !debug_ccr[3]) begin
        $fatal(1, "P5 reset architectural state pc=%04x sp=%04x ccr=%02x", debug_pc,
               debug_sp, debug_ccr);
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
        if (cycles > 16) $fatal(1, "P5 opcode %02x did not retire", expected_opcode);
      end while (!retire);
      if (debug_opcode != expected_opcode || debug_cycles != cycles[3:0] ||
          illegal || undefined_value) begin
        $fatal(1, "P5 opcode %02x result/timing mismatch", expected_opcode);
      end
    end
  endtask

  task automatic wait_for_interrupt(
    input logic [10:0] expected_pc,
    input logic [10:0] expected_vector,
    input logic [10:0] expected_return_pc
  );
    logic [10:0] expected_bus_address;
    logic [7:0] expected_bus_data;
    begin
      cycles = 0;
      do begin
        if ((cycles <= 1) && (!dut.core_bus_valid || dut.core_write ||
            dut.core_address[10:0] != expected_return_pc ||
            dut.core_data_in != 8'h9d || opcode_fetch != (cycles == 0))) begin
          $fatal(1, "P5 interrupt opcode-read cycle=%0d address=%03x/%03x data=%02x valid=%b write=%b fetch=%b",
                 cycles, dut.core_address[10:0], expected_return_pc,
                 dut.core_data_in, dut.core_bus_valid, dut.core_write,
                 opcode_fetch);
        end
        if ((cycles >= 2) && (cycles <= 6)) begin
          case (cycles)
            2: begin
              expected_bus_address = 11'h07f;
              expected_bus_data = expected_return_pc[7:0];
            end
            3: begin
              expected_bus_address = 11'h07e;
              expected_bus_data = {5'h1f, expected_return_pc[10:8]};
            end
            4: begin
              expected_bus_address = 11'h07d;
              expected_bus_data = debug_x;
            end
            5: begin
              expected_bus_address = 11'h07c;
              expected_bus_data = debug_a;
            end
            default: begin
              expected_bus_address = 11'h07b;
              expected_bus_data = {3'b111, debug_ccr};
            end
          endcase
          if (!dut.core_bus_valid || !dut.core_write ||
              dut.core_address[10:0] != expected_bus_address ||
              dut.core_data_out != expected_bus_data) begin
            $fatal(1, "P5 interrupt stack cycle %0d address=%03x/%03x data=%02x/%02x valid=%b write=%b",
                   cycles, dut.core_address[10:0], expected_bus_address,
                   dut.core_data_out, expected_bus_data,
                   dut.core_bus_valid, dut.core_write);
          end
        end
        if (cycles == 7) begin
          if (!dut.core_bus_valid || dut.core_write ||
              dut.core_address[10:0] != 11'h07a) begin
            $fatal(1, "P5 interrupt unused-stack read address=%03x valid=%b write=%b",
                   dut.core_address[10:0], dut.core_bus_valid, dut.core_write);
          end
        end
        if ((cycles >= 8) && (cycles <= 10)) begin
          case (cycles)
            8: expected_bus_address = expected_vector;
            9: expected_bus_address = expected_vector + 11'h001;
            default: expected_bus_address = expected_vector + 11'h002;
          endcase
          if (!dut.core_bus_valid || dut.core_write ||
              dut.core_address[10:0] != expected_bus_address) begin
            $fatal(1, "P5 interrupt vector cycle %0d address=%03x/%03x valid=%b write=%b",
                   cycles, dut.core_address[10:0], expected_bus_address,
                   dut.core_bus_valid, dut.core_write);
          end
        end
        tick();
        cycles = cycles + 1;
        if (cycles > 14) $fatal(1, "P5 interrupt did not acknowledge");
      end while (!interrupt_ack);
      if (cycles != 11 || debug_pc[10:0] != expected_pc) begin
        $fatal(1, "P5 interrupt response cycles=%0d/11 vector=%03x/%03x",
               cycles, debug_pc[10:0], expected_pc);
      end
      checks = checks + 1;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    clock_enable = 1'b1;
    int_n = 1'b1;
    timer_pin = 1'b0;
    port_a_in = 8'h3c;
    port_b_in = 8'h5a;
    port_c_in = 4'h9;
    vpp_present = 1'b0;
    bootstrap_voltage = 1'b0;
    checks = 0;
    for (index = 0; index < 2048; index = index + 1) firmware[index] = 8'h9d;

    // GPIO data/DDR behavior and internal RAM decode.
    firmware[11'h100] = 8'ha6; firmware[11'h101] = 8'ha5; // LDA #$a5
    firmware[11'h102] = 8'hb7; firmware[11'h103] = 8'h00; // STA PORTA
    firmware[11'h104] = 8'ha6; firmware[11'h105] = 8'hf0; // LDA #$f0
    firmware[11'h106] = 8'hb7; firmware[11'h107] = 8'h04; // STA DDRA
    firmware[11'h108] = 8'hb6; firmware[11'h109] = 8'h00; // LDA PORTA
    firmware[11'h10a] = 8'hb7; firmware[11'h10b] = 8'h10; // STA first RAM byte
    firmware[11'h10c] = 8'hb6; firmware[11'h10d] = 8'h04; // LDA DDRA
    firmware[11'h10e] = 8'hb6; firmware[11'h10f] = 8'h10; // LDA first RAM byte
    #1;
    reset_to(11'h100);
    if (port_a_oe != 8'h00 || port_b_oe != 8'h00 || port_c_oe != 4'h0 ||
        debug_timer_control != 8'h40 || debug_program_control != 8'hff) begin
      $fatal(1, "P5 peripheral reset state pa=%02x pb=%02x pc=%x t=%02x tc=%02x",
             port_a_oe, port_b_oe, port_c_oe, debug_timer, debug_timer_control);
    end
    checks = checks + 1;
    run_instruction(8'ha6);
    run_instruction(8'hb7);
    run_instruction(8'ha6);
    run_instruction(8'hb7);
    if (port_a_out != 8'ha5 || port_a_oe != 8'hf0) $fatal(1, "P5 GPIO output/DDR");
    checks = checks + 1;
    run_instruction(8'hb6);
    if (debug_a != 8'hac) $fatal(1, "P5 mixed input/output port read %02x", debug_a);
    run_instruction(8'hb7);
    run_instruction(8'hb6);
    if (debug_a != 8'hff) $fatal(1, "P5 DDR read value");
    run_instruction(8'hb6);
    if (debug_a != 8'hac) $fatal(1, "P5 internal RAM read/write");
    checks = checks + 3;

    // Configure a disabled timer while I is set, make both requests pending,
    // then prove external INT priority and the distinct timer vector.
    firmware[11'h200] = 8'ha6; firmware[11'h201] = 8'h60; // mask, no clock
    firmware[11'h202] = 8'hb7; firmware[11'h203] = 8'h09;
    firmware[11'h204] = 8'ha6; firmware[11'h205] = 8'h01;
    firmware[11'h206] = 8'hb7; firmware[11'h207] = 8'h08;
    firmware[11'h208] = 8'ha6; firmware[11'h209] = 8'h20; // unmask, no clock
    firmware[11'h20a] = 8'hb7; firmware[11'h20b] = 8'h09;
    firmware[11'h20c] = 8'ha6; firmware[11'h20d] = 8'h00; // internal, bypass
    firmware[11'h20e] = 8'hb7; firmware[11'h20f] = 8'h09;
    firmware[11'h210] = 8'h9a; // CLI
    firmware[11'h211] = 8'h9d; // NOP (not fetched before IRQ)
    firmware[11'h300] = 8'h1f; firmware[11'h301] = 8'h09; // BCLR7 TCR
    firmware[11'h302] = 8'h80; // RTI
    firmware[11'h310] = 8'h80; // external handler: RTI
    firmware[11'h7f8] = 8'h03; firmware[11'h7f9] = 8'h00;
    firmware[11'h7fa] = 8'h03; firmware[11'h7fb] = 8'h10;
    reset_to(11'h200);
    run_instruction(8'ha6); run_instruction(8'hb7);
    run_instruction(8'ha6); run_instruction(8'hb7);
    run_instruction(8'ha6); run_instruction(8'hb7);
    run_instruction(8'ha6); run_instruction(8'hb7);
    int_n = 1'b0;
    run_instruction(8'h9a);
    if (!timer_irq || !external_irq) $fatal(1, "P5 simultaneous requests not pending");
    wait_for_interrupt(11'h310, 11'h7fa, 11'h211);
    if (external_irq) $fatal(1, "P5 external request latch not cleared");
    if (debug_sp != 16'h007a || dut.ram[111] != 8'h11 ||
        dut.ram[110] != 8'hfa || dut.ram[109] != 8'h00 ||
        dut.ram[108] != 8'h00 || dut.ram[107] != 8'he2) begin
      $fatal(1, "P5 interrupt frame sp=%04x frame=%02x %02x %02x %02x %02x",
             debug_sp, dut.ram[111], dut.ram[110], dut.ram[109],
             dut.ram[108], dut.ram[107]);
    end
    checks = checks + 1;
    int_n = 1'b1;
    run_instruction(8'h80);
    wait_for_interrupt(11'h300, 11'h7f8, 11'h211);
    run_instruction(8'h1f);
    if (timer_irq || debug_timer_control[7]) $fatal(1, "P5 timer request clear");
    run_instruction(8'h80);
    checks = checks + 2;

    // Eleven-bit subroutine returns store the five unused PCH bits as ones.
    firmware[11'h320] = 8'had; firmware[11'h321] = 8'h01;
    firmware[11'h323] = 8'h81;
    reset_to(11'h320);
    run_instruction(8'had);
    if (debug_sp != 16'h007d || dut.ram[111] != 8'h22 ||
        dut.ram[110] != 8'hfb) begin
      $fatal(1, "P5 BSR frame sp=%04x PCL=%02x PCH=%02x",
             debug_sp, dut.ram[111], dut.ram[110]);
    end
    run_instruction(8'h81);
    if (debug_sp != 16'h007f || debug_pc[10:0] != 11'h322) begin
      $fatal(1, "P5 RTS restore sp=%04x pc=%04x", debug_sp, debug_pc);
    end
    checks = checks + 1;

    // TIMER high-voltage bootstrap selection uses the separate 7F6 vector.
    // Code in the caller-supplied bootstrap ROM exercises the documented PCR
    // latch/program sequence without modeling high-voltage pulse physics.
    firmware[11'h790] = 8'ha6; firmware[11'h791] = 8'h02; // PLE low, PGE high
    firmware[11'h792] = 8'hb7; firmware[11'h793] = 8'h0b;
    firmware[11'h794] = 8'ha6; firmware[11'h795] = 8'h5a;
    firmware[11'h796] = 8'hb7; firmware[11'h797] = 8'h80; // latch EPROM byte
    firmware[11'h798] = 8'ha6; firmware[11'h799] = 8'h00; // enable programming
    firmware[11'h79a] = 8'hb7; firmware[11'h79b] = 8'h0b;
    firmware[11'h79c] = 8'h9d;
    bootstrap_voltage = 1'b1;
    vpp_present = 1'b1;
    reset_to(11'h790);
    if (!bootstrap_mode) $fatal(1, "P5 bootstrap selection not retained");
    run_instruction(8'ha6); run_instruction(8'hb7);
    if (!eprom_latch_enable || eprom_program_enable ||
        debug_program_control != 8'hfa) begin
      $fatal(1, "P5 EPROM latch state latch=%b program=%b",
             eprom_latch_enable, eprom_program_enable);
    end
    run_instruction(8'ha6); run_instruction(8'hb7);
    if (eprom_program_address != 11'h080 || eprom_program_data != 8'h5a) begin
      $fatal(1, "P5 EPROM address/data latch address=%03x data=%02x",
             eprom_program_address, eprom_program_data);
    end
    run_instruction(8'ha6); run_instruction(8'hb7);
    if (!eprom_program_enable || eprom_program_address != 11'h080 ||
        eprom_program_data != 8'h5a || debug_program_control != 8'hf8) begin
      $fatal(1, "P5 EPROM program request enable=%b address=%03x data=%02x",
             eprom_program_enable, eprom_program_address, eprom_program_data);
    end
    checks = checks + 4;
    bootstrap_voltage = 1'b0;
    vpp_present = 1'b0;
    #1;

    if (eprom_latch_enable || eprom_program_enable || waiting_state || stopped_state ||
        port_b_out != 8'h00 || port_c_out != 4'h0 || debug_address >= 16'h0800 ||
        debug_pc[15:11] != 5'h00 || debug_x != 8'h00 ||
        ((opcode_fetch !== 1'b0) && (opcode_fetch !== 1'b1)) ||
        (^debug_ccr === 1'bx)) begin
      $fatal(1, "P5 deterministic outputs el=%b ep=%b wait=%b stop=%b pb=%02x pc=%x addr=%04x dpc=%04x x=%02x fetch=%b ccr=%02x",
             eprom_latch_enable, eprom_program_enable, waiting_state, stopped_state,
             port_b_out, port_c_out, debug_address, debug_pc, debug_x, opcode_fetch,
             debug_ccr);
    end
    $display("MC68705P5 MCU PASS: %0d memory, GPIO, timer, priority, bootstrap, and programming checks", checks);
    $finish;
  end
endmodule
