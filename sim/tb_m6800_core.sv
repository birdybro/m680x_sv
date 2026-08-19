// SPDX-License-Identifier: MIT
module tb_m6800_core;
  logic clk;
  logic reset_n;
  logic clock_enable;
  logic bus_ready;
  logic irq_n;
  logic nmi_n;
  logic [7:0] data_in;
  logic [15:0] address;
  logic [7:0] data_out;
  logic write_enable;
  logic bus_valid;
  logic opcode_fetch;
  logic retire;
  logic illegal;
  logic undefined_value;
  logic waiting_state;
  logic sleeping_state;
  logic interrupt_ack;
  logic [1:0] interrupt_vector;
  logic [7:0] debug_a;
  logic [7:0] debug_b;
  logic [15:0] debug_x;
  logic [15:0] debug_sp;
  logic [15:0] debug_pc;
  logic [5:0] debug_ccr;
  logic [7:0] debug_opcode;
  logic [3:0] debug_cycles;
  logic [7:0] memory [0:65535];
  logic [15:0] trace_address [0:15];
  logic [7:0] trace_data [0:15];
  logic trace_write [0:15];
  logic trace_valid [0:15];
  logic trace_fetch [0:15];
  integer instruction_cycles;
  integer index;
  integer cases;

  m6800_core dut (
    .clk_i(clk),
    .reset_n_i(reset_n),
    .clock_enable_i(clock_enable),
    .bus_ready_i(bus_ready),
    .irq_n_i(irq_n),
    .nmi_n_i(nmi_n),
    .data_i(data_in),
    .address_o(address),
    .data_o(data_out),
    .write_o(write_enable),
    .bus_valid_o(bus_valid),
    .opcode_fetch_o(opcode_fetch),
    .retire_o(retire),
    .illegal_o(illegal),
    .undefined_o(undefined_value),
    .waiting_o(waiting_state),
    .sleeping_o(sleeping_state),
    .interrupt_ack_o(interrupt_ack),
    .interrupt_vector_o(interrupt_vector),
    .debug_a_o(debug_a),
    .debug_b_o(debug_b),
    .debug_x_o(debug_x),
    .debug_sp_o(debug_sp),
    .debug_pc_o(debug_pc),
    .debug_ccr_o(debug_ccr),
    .debug_opcode_o(debug_opcode),
    .debug_instruction_cycles_o(debug_cycles)
  );

  assign data_in = memory[address];

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (clock_enable && bus_ready && bus_valid && write_enable) begin
      memory[address] <= data_out;
    end
  end

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic run_interrupt(input integer expected_cycles, input logic [1:0] expected_vector);
    begin
      instruction_cycles = 0;
      do begin
        if (instruction_cycles >= 16) $fatal(1, "interrupt did not acknowledge");
        trace_address[instruction_cycles] = address;
        trace_data[instruction_cycles] = write_enable ? data_out : data_in;
        trace_write[instruction_cycles] = write_enable;
        trace_valid[instruction_cycles] = bus_valid;
        trace_fetch[instruction_cycles] = opcode_fetch;
        tick();
        instruction_cycles = instruction_cycles + 1;
      end while (!interrupt_ack);
      if (instruction_cycles != expected_cycles || interrupt_vector != expected_vector) begin
        $fatal(1, "interrupt timing/vector expected=%0d/%0d actual=%0d/%0d",
          expected_cycles, expected_vector, instruction_cycles, interrupt_vector);
      end
      cases = cases + 1;
    end
  endtask

  task automatic run_instruction(input integer expected_cycles, input logic [7:0] expected_opcode);
    begin
      instruction_cycles = 0;
      do begin
        if (instruction_cycles >= 16) begin
          $fatal(1, "instruction %02x did not retire pc=%04x current=%02x ccr=%02x irq=%0d nmi=%0d",
            expected_opcode, debug_pc, debug_opcode, debug_ccr, irq_n, nmi_n);
        end
        trace_address[instruction_cycles] = address;
        trace_data[instruction_cycles] = write_enable ? data_out : data_in;
        trace_write[instruction_cycles] = write_enable;
        trace_valid[instruction_cycles] = bus_valid;
        trace_fetch[instruction_cycles] = opcode_fetch;
        tick();
        instruction_cycles = instruction_cycles + 1;
      end while (!retire);
      if (debug_opcode != expected_opcode || instruction_cycles != expected_cycles ||
          debug_cycles != expected_cycles[3:0]) begin
        $fatal(1, "opcode/timing mismatch opcode=%02x expected=%0d actual=%0d decoded=%0d",
          debug_opcode, expected_cycles, instruction_cycles, debug_cycles);
      end
      if (!trace_valid[0] || !trace_fetch[0] || trace_write[0]) begin
        $fatal(1, "opcode %02x did not start with a read fetch", expected_opcode);
      end
      cases = cases + 1;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    clock_enable = 1'b1;
    bus_ready = 1'b1;
    irq_n = 1'b1;
    nmi_n = 1'b1;
    cases = 0;
    for (index = 0; index < 65536; index = index + 1) memory[index] = 8'h00;

    memory[16'hfffe] = 8'h10;
    memory[16'hffff] = 8'h00;
    memory[16'hfffa] = 8'h12;
    memory[16'hfffb] = 8'h00;
    memory[16'hfff8] = 8'h13;
    memory[16'hfff9] = 8'h00;
    memory[16'hfffc] = 8'h14;
    memory[16'hfffd] = 8'h00;

    // Main program: stack setup, arithmetic, store, index wrap, subroutine,
    // both branch outcomes, software interrupt, and return.
    memory[16'h1000] = 8'h8e;  // LDS #$01ff
    memory[16'h1001] = 8'h01;
    memory[16'h1002] = 8'hff;
    memory[16'h1003] = 8'h86;  // LDAA #$7f
    memory[16'h1004] = 8'h7f;
    memory[16'h1005] = 8'h8b;  // ADDA #$01
    memory[16'h1006] = 8'h01;
    memory[16'h1007] = 8'hb7;  // STAA $2000
    memory[16'h1008] = 8'h20;
    memory[16'h1009] = 8'h00;
    memory[16'h100a] = 8'hce;  // LDX #$ffff
    memory[16'h100b] = 8'hff;
    memory[16'h100c] = 8'hff;
    memory[16'h100d] = 8'h08;  // INX
    memory[16'h100e] = 8'hbd;  // JSR $1100
    memory[16'h100f] = 8'h11;
    memory[16'h1010] = 8'h00;
    memory[16'h1011] = 8'h27;  // BEQ +2, not taken
    memory[16'h1012] = 8'h02;
    memory[16'h1013] = 8'h26;  // BNE +2, taken
    memory[16'h1014] = 8'h02;
    memory[16'h1015] = 8'h01;
    memory[16'h1016] = 8'h01;
    memory[16'h1017] = 8'h3f;  // SWI
    memory[16'h1018] = 8'h01;  // NOP after RTI
    memory[16'h1019] = 8'h0e;  // CLI
    memory[16'h101a] = 8'h0f;  // SEI
    memory[16'h101b] = 8'h0e;  // CLI
    memory[16'h101c] = 8'h3e;  // WAI
    memory[16'h101d] = 8'h01;  // NOP after WAI interrupt
    memory[16'h1100] = 8'h0d;  // SEC
    memory[16'h1101] = 8'h4c;  // INCA (must preserve C)
    memory[16'h1102] = 8'h39;  // RTS
    memory[16'h1200] = 8'h3b;  // RTI
    memory[16'h1300] = 8'h3b;  // IRQ handler: RTI
    memory[16'h1400] = 8'h3b;  // NMI handler: RTI

    // Reset has two documented vector reads before the first opcode fetch.
    #1;
    reset_n = 1'b0;
    #1;
    if (!bus_valid || write_enable || address != 16'hfffe) $fatal(1, "reset high-vector cycle");
    reset_n = 1'b1;
    tick();
    if (!bus_valid || write_enable || address != 16'hffff) $fatal(1, "reset low-vector cycle");
    tick();
    if (!opcode_fetch || address != 16'h1000 || debug_pc != 16'h1000) $fatal(1, "reset vector result");
    cases = cases + 1;

    // Clock-enable and ready stalls must leave all externally visible state stable.
    clock_enable = 1'b0;
    tick();
    if (address != 16'h1000 || debug_pc != 16'h1000 || retire) $fatal(1, "clock-enable stall");
    clock_enable = 1'b1;
    bus_ready = 1'b0;
    tick();
    if (address != 16'h1000 || debug_pc != 16'h1000 || retire) $fatal(1, "bus-ready stall");
    bus_ready = 1'b1;
    cases = cases + 2;

    run_instruction(3, 8'h8e);
    if (debug_sp != 16'h01ff || !debug_ccr[4]) $fatal(1, "LDS result/mask");
    run_instruction(2, 8'h86);
    if (debug_a != 8'h7f || !debug_ccr[4]) $fatal(1, "LDAA result/mask");
    run_instruction(2, 8'h8b);
    if (debug_a != 8'h80 || debug_ccr[5:4] != 2'b11 || debug_ccr[3:0] != 4'b1010) begin
      $fatal(1, "ADDA result/flags A=%02x CCR=%02x", debug_a, debug_ccr);
    end
    run_instruction(5, 8'hb7);
    if (memory[16'h2000] != 8'h80 || !trace_write[3] ||
        trace_address[3] != 16'h2000 || trace_data[3] != 8'h80 || trace_valid[4]) begin
      $fatal(1, "STAA external trace");
    end
    run_instruction(3, 8'hce);
    run_instruction(4, 8'h08);
    if (debug_x != 16'h0000 || !debug_ccr[4] || !debug_ccr[2]) $fatal(1, "INX wrap/zero/mask");

    run_instruction(9, 8'hbd);
    if (debug_pc != 16'h1100 || debug_sp != 16'h01fd ||
        memory[16'h01ff] != 8'h11 || memory[16'h01fe] != 8'h10) begin
      $fatal(1, "JSR target or return stack order");
    end
    run_instruction(2, 8'h0d);
    run_instruction(2, 8'h4c);
    if (debug_a != 8'h81 || !debug_ccr[4] || !debug_ccr[0]) $fatal(1, "INC carry/mask preservation");
    run_instruction(5, 8'h39);
    if (debug_pc != 16'h1011 || debug_sp != 16'h01ff) $fatal(1, "RTS result");

    run_instruction(4, 8'h27);
    if (debug_pc != 16'h1013 || !debug_ccr[4]) $fatal(1, "not-taken branch/mask");
    run_instruction(4, 8'h26);
    if (debug_pc != 16'h1017) $fatal(1, "taken branch");

    run_instruction(12, 8'h3f);
    if (debug_pc != 16'h1200 || debug_sp != 16'h01f8 ||
        memory[16'h01ff] != 8'h18 || memory[16'h01fe] != 8'h10 ||
        memory[16'h01fd] != 8'h00 || memory[16'h01fc] != 8'h00 ||
        memory[16'h01fb] != 8'h81 || memory[16'h01fa] != 8'h00 ||
        !debug_ccr[4]) begin
      $fatal(1, "SWI vector or interrupt frame");
    end
    run_instruction(10, 8'h3b);
    if (debug_pc != 16'h1018 || debug_sp != 16'h01ff || debug_a != 8'h81 ||
        debug_x != 16'h0000 || debug_ccr[0] != 1'b1) begin
      $fatal(1, "RTI frame restore");
    end
    run_instruction(2, 8'h01);
    if (debug_pc != 16'h1019 || debug_b != 8'h00 || !debug_ccr[4] ||
        illegal || undefined_value || waiting_state || sleeping_state) begin
      $fatal(1, "post-interrupt NOP result ccr=%02x stacked=%02x", debug_ccr, memory[16'h01f9]);
    end

    // IRQ is level-sensitive, masked until CLI retires, and begins with the
    // documented discarded opcode fetch followed by two internal cycles.
    irq_n = 1'b0;
    run_instruction(2, 8'h0e);
    if (debug_pc != 16'h101a || debug_ccr[4]) $fatal(1, "masked IRQ or CLI result");
    run_interrupt(13, 2'b01);
    if (debug_pc != 16'h1300 || debug_sp != 16'h01f8 || !debug_ccr[4] ||
        !trace_fetch[0] || !trace_valid[0] || trace_address[0] != 16'h101a ||
        trace_valid[1] || trace_valid[2] || !trace_write[3] ||
        trace_address[3] != 16'h01ff || trace_data[3] != 8'h1a ||
        trace_valid[10] || trace_address[11] != 16'hfff8 ||
        trace_address[12] != 16'hfff9) begin
      $fatal(1, "IRQ entry bus sequence or frame");
    end
    irq_n = 1'b1;
    run_instruction(10, 8'h3b);
    if (debug_pc != 16'h101a || debug_sp != 16'h01ff || debug_ccr[4]) begin
      $fatal(1, "IRQ RTI restore");
    end

    // NMI is edge-latched and has priority regardless of the I mask.
    run_instruction(2, 8'h0f);
    if (!debug_ccr[4]) $fatal(1, "SEI result");
    nmi_n = 1'b0;
    run_interrupt(13, 2'b10);
    if (debug_pc != 16'h1400 || trace_address[11] != 16'hfffc ||
        trace_address[12] != 16'hfffd || trace_data[3] != 8'h1b) begin
      $fatal(1, "NMI entry bus sequence or frame");
    end
    nmi_n = 1'b1;
    run_instruction(10, 8'h3b);
    if (debug_pc != 16'h101b || !debug_ccr[4]) $fatal(1, "NMI RTI restore");

    // WAI stacks once. A subsequent IRQ performs only internal/vector cycles.
    run_instruction(2, 8'h0e);
    run_instruction(9, 8'h3e);
    if (!waiting_state || debug_sp != 16'h01f8) $fatal(1, "WAI entry");
    irq_n = 1'b0;
    run_interrupt(4, 2'b01);
    if (debug_pc != 16'h1300 || debug_sp != 16'h01f8 || trace_valid[0] ||
        trace_valid[1] || trace_address[2] != 16'hfff8 ||
        trace_address[3] != 16'hfff9) begin
      $fatal(1, "WAI wakeup restacked or used wrong vector timing");
    end
    irq_n = 1'b1;
    run_instruction(10, 8'h3b);
    if (debug_pc != 16'h101d || debug_sp != 16'h01ff || debug_ccr[4]) begin
      $fatal(1, "WAI RTI restore");
    end

    $display("M6800 CORE PASS: %0d directed checks", cases);
    $finish;
  end
endmodule
