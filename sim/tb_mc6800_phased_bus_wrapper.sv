// SPDX-License-Identifier: MIT
module tb_mc6800_phased_bus_wrapper;
  logic phase_clk;
  logic phase_reset_n;
  logic reset_n;
  logic clock_enable;
  logic irq_n;
  logic nmi_n;
  logic halt_n;
  logic tsc;
  logic dbe_gate;
  logic dbe;
  logic [7:0] data_in;
  logic phi1;
  logic phi2;
  logic [1:0] phase;
  logic [15:0] address;
  logic address_oe;
  logic [7:0] data_out;
  logic data_oe;
  logic read_not_write;
  logic read_not_write_oe;
  logic vma;
  logic ba;
  logic opcode_fetch;
  logic retire;
  logic illegal;
  logic undefined_value;
  logic waiting_state;
  logic interrupt_ack;
  logic [1:0] interrupt_vector;
  logic halted;
  logic [15:0] debug_pc;
  logic [15:0] debug_sp;
  logic [7:0] debug_a;
  logic [7:0] debug_b;
  logic [15:0] debug_x;
  logic [5:0] debug_ccr;
  logic [7:0] memory [0:65535];
  integer checks;
  integer index;
  integer cycles;
  integer write_windows;

  mc6800_phased_bus_wrapper dut (
    .phase_clk_i(phase_clk), .phase_reset_n_i(phase_reset_n),
    .reset_n_i(reset_n), .clock_enable_i(clock_enable), .irq_n_i(irq_n),
    .nmi_n_i(nmi_n), .halt_n_i(halt_n), .tsc_i(tsc), .dbe_i(dbe),
    .data_i(data_in), .phi1_o(phi1), .phi2_o(phi2),
    .bus_phase_o(phase), .address_o(address), .address_oe_o(address_oe),
    .data_o(data_out), .data_oe_o(data_oe),
    .read_not_write_o(read_not_write),
    .read_not_write_oe_o(read_not_write_oe), .vma_o(vma), .ba_o(ba),
    .opcode_fetch_o(opcode_fetch), .retire_o(retire), .illegal_o(illegal),
    .undefined_o(undefined_value), .waiting_o(waiting_state),
    .interrupt_ack_o(interrupt_ack), .interrupt_vector_o(interrupt_vector),
    .halted_o(halted), .debug_pc_o(debug_pc), .debug_sp_o(debug_sp),
    .debug_a_o(debug_a), .debug_b_o(debug_b), .debug_x_o(debug_x),
    .debug_ccr_o(debug_ccr)
  );

  assign dbe = dbe_gate && phi2;
  assign data_in = memory[address];
  always #5 phase_clk <= ~phase_clk;
  always @(posedge phase_clk) begin
    if (data_oe) memory[address] <= data_out;
  end

  task automatic check_value(input logic condition_value, input string label_value);
    begin
      checks = checks + 1;
      if (!condition_value) $fatal(1, "MC6800 phased bus: %s", label_value);
    end
  endtask

  task automatic advance_phase(input logic [1:0] expected_phase);
    begin
      @(posedge phase_clk);
      #1;
      check_value(phase == expected_phase, "subphase sequence");
      check_value(!(phi1 && phi2), "phi1/phi2 non-overlap");
    end
  endtask

  task automatic bus_cycle;
    logic [15:0] held_address;
    logic [15:0] held_pc;
    logic held_direction;
    begin
      check_value(phase == 2'd0 && phi1 && !phi2, "phi1 cycle start");
      held_address = address;
      held_pc = debug_pc;
      held_direction = read_not_write;

      advance_phase(2'd1);
      check_value(!phi1 && !phi2, "phi1-to-phi2 separation");
      check_value(address == held_address && debug_pc == held_pc &&
                  read_not_write == held_direction,
                  "bus and CPU stable after trailing phi1");

      advance_phase(2'd2);
      check_value(!phi1 && phi2, "phi2 data-transfer window");
      check_value(address == held_address && debug_pc == held_pc &&
                  read_not_write == held_direction,
                  "bus and CPU stable through phi2");
      if (vma && !read_not_write && dbe_gate) begin
        check_value(data_oe, "write data enabled during phi2");
        write_windows = write_windows + 1;
      end else begin
        check_value(!data_oe, "no unintended phi2 data drive");
      end

      advance_phase(2'd3);
      check_value(!phi1 && !phi2 && !data_oe, "post-phi2 separation");
      check_value(address == held_address && debug_pc == held_pc,
                  "normalized state waits until post-phi2 boundary");
      advance_phase(2'd0);
    end
  endtask

  task automatic run_instruction;
    begin
      cycles = 0;
      do begin
        bus_cycle();
        cycles = cycles + 1;
        if (cycles > 20) $fatal(1, "MC6800 phased instruction timeout");
      end while (!retire);
      check_value(!illegal && !undefined_value, "documented instruction retires");
    end
  endtask

  initial begin
    phase_clk = 1'b0;
    phase_reset_n = 1'b0;
    reset_n = 1'b0;
    clock_enable = 1'b1;
    irq_n = 1'b1;
    nmi_n = 1'b1;
    halt_n = 1'b1;
    tsc = 1'b0;
    dbe_gate = 1'b1;
    checks = 0;
    write_windows = 0;
    for (index = 0; index < 65536; index = index + 1) memory[index] = 8'h01;
    memory[16'hfffe] = 8'h10;
    memory[16'hffff] = 8'h00;
    memory[16'h1000] = 8'h8e;  // LDS #$01ff
    memory[16'h1001] = 8'h01;
    memory[16'h1002] = 8'hff;
    memory[16'h1003] = 8'h86;  // LDAA #$5a
    memory[16'h1004] = 8'h5a;
    memory[16'h1005] = 8'hb7;  // STAA $2000
    memory[16'h1006] = 8'h20;
    memory[16'h1007] = 8'h00;
    memory[16'h1008] = 8'hb7;  // STAA $2001, DBE suppressed
    memory[16'h1009] = 8'h20;
    memory[16'h100a] = 8'h01;
    memory[16'h100b] = 8'h01;  // NOP

    #1;
    check_value(phase == 2'd0 && !phi1 && !phi2,
                "integration reset suppresses projected clocks");
    phase_reset_n = 1'b1;
    #1;
    check_value(phi1 && !phi2, "phase projection starts with phi1");
    bus_cycle();
    check_value(!vma && address == 16'hfffe && read_not_write,
                "device reset bus state while phases continue");

    reset_n = 1'b1;
    cycles = 0;
    while (!(opcode_fetch && vma && address == 16'h1000)) begin
      bus_cycle();
      cycles = cycles + 1;
      if (cycles > 8) $fatal(1, "MC6800 phased reset-vector timeout");
    end
    check_value(debug_pc == 16'h1000, "reset vector reaches first opcode");

    run_instruction();
    run_instruction();
    run_instruction();
    check_value(memory[16'h2000] == 8'h5a && write_windows == 1,
                "write occurs once in projected phi2");

    dbe_gate = 1'b0;
    run_instruction();
    check_value(memory[16'h2001] == 8'h01 && write_windows == 1,
                "DBE suppresses complete second write window");
    dbe_gate = 1'b1;

    // TSC is documented to assert with phi1 high and phi2 low. Holding it at
    // that boundary freezes phases and the normalized CPU while releasing bus.
    check_value(phase == 2'd0 && phi1, "TSC setup at phi1");
    tsc = 1'b1;
    #1;
    for (cycles = 0; cycles < 3; cycles = cycles + 1) begin
      advance_phase(2'd0);
      check_value(phi1 && !phi2 && !address_oe && !read_not_write_oe &&
                  !vma && !ba && !data_oe,
                  "TSC holds phi1 and releases bus");
    end
    tsc = 1'b0;

    // Controls changing after trailing phi1 cannot affect the current cycle;
    // the next trailing-phi1 edge captures them for the following boundary.
    advance_phase(2'd1);
    halt_n = 1'b0;
    #1;
    check_value(dut.sampled_halt_n, "late HALT deferred past current phi1");
    advance_phase(2'd2);
    advance_phase(2'd3);
    advance_phase(2'd0);
    advance_phase(2'd1);
    check_value(!dut.sampled_halt_n, "HALT sampled on next trailing phi1");
    halt_n = 1'b1;

    check_value(debug_sp == 16'h01ff && debug_a == 8'h5a &&
                debug_b == 8'h00 && debug_x == 16'h0000 &&
                debug_ccr == 6'h10 && interrupt_vector == 2'b00 &&
                halted === 1'b0 && !waiting_state && !interrupt_ack,
                "deterministic architectural and control outputs");
    $display("MC6800 PHASED BUS PASS: %0d digital phase/control/data checks", checks);
    $finish;
  end
endmodule
