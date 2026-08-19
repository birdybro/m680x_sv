// SPDX-License-Identifier: MIT
module tb_mc6800_bus_wrapper;
  logic clk;
  logic reset_n;
  logic clock_enable;
  logic irq_n;
  logic nmi_n;
  logic halt_n;
  logic tsc;
  logic dbe;
  logic [7:0] data_in;
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
  integer index;
  integer cycles;
  integer checks;
  logic [15:0] held_pc;

  mc6800_bus_wrapper dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(clock_enable),
    .irq_n_i(irq_n), .nmi_n_i(nmi_n), .halt_n_i(halt_n), .tsc_i(tsc),
    .dbe_i(dbe), .data_i(data_in), .address_o(address),
    .address_oe_o(address_oe), .data_o(data_out), .data_oe_o(data_oe),
    .read_not_write_o(read_not_write),
    .read_not_write_oe_o(read_not_write_oe), .vma_o(vma), .ba_o(ba),
    .opcode_fetch_o(opcode_fetch), .retire_o(retire), .illegal_o(illegal),
    .undefined_o(undefined_value), .waiting_o(waiting_state),
    .interrupt_ack_o(interrupt_ack), .interrupt_vector_o(interrupt_vector),
    .halted_o(halted), .debug_pc_o(debug_pc), .debug_sp_o(debug_sp),
    .debug_a_o(debug_a), .debug_b_o(debug_b), .debug_x_o(debug_x),
    .debug_ccr_o(debug_ccr)
  );

  assign data_in = memory[address];
  always #5 clk <= ~clk;
  always @(posedge clk) begin
    if (data_oe) memory[address] <= data_out;
  end

  task automatic tick;
    begin @(posedge clk); #1; end
  endtask

  task automatic run_instruction(input logic [7:0] expected_opcode);
    begin
      cycles = 0;
      do begin
        tick();
        cycles = cycles + 1;
        if (cycles > 16) $fatal(1, "MC6800 wrapper opcode %02x did not retire", expected_opcode);
      end while (!retire);
      if (illegal || undefined_value) begin
        $fatal(1, "MC6800 wrapper opcode %02x failed", expected_opcode);
      end
    end
  endtask

  task automatic run_store(input logic suppress_data_bus);
    logic saw_write;
    begin
      cycles = 0;
      saw_write = 1'b0;
      do begin
        if (vma && !read_not_write) begin
          saw_write = 1'b1;
          dbe = !suppress_data_bus;
          #1;
          if (data_oe != !suppress_data_bus) $fatal(1, "MC6800 DBE write gating");
        end
        tick();
        dbe = 1'b1;
        cycles = cycles + 1;
        if (cycles > 12) $fatal(1, "MC6800 wrapper store did not retire");
      end while (!retire);
      if (!saw_write) $fatal(1, "MC6800 wrapper store had no write cycle");
    end
  endtask

  task automatic wait_for_interrupt(input logic [15:0] expected_pc,
                                    input logic [1:0] expected_vector);
    begin
      cycles = 0;
      do begin
        tick();
        cycles = cycles + 1;
        if (cycles > 20) begin
          $fatal(1, "MC6800 wrapper interrupt did not acknowledge pc=%04x sp=%04x halted=%b ba=%b vma=%b address=%04x retire=%b waiting=%b",
                 debug_pc, debug_sp, halted, ba, vma, address, retire,
                 waiting_state);
        end
      end while (!interrupt_ack);
      if (debug_pc != expected_pc || interrupt_vector != expected_vector) begin
        $fatal(1, "MC6800 wrapper interrupt vector pc=%04x id=%x", debug_pc,
               interrupt_vector);
      end
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    clock_enable = 1'b1;
    irq_n = 1'b1;
    nmi_n = 1'b1;
    halt_n = 1'b1;
    tsc = 1'b0;
    dbe = 1'b1;
    checks = 0;
    for (index = 0; index < 65536; index = index + 1) memory[index] = 8'h01;

    memory[16'hfffe] = 8'h10; memory[16'hffff] = 8'h00;
    memory[16'hfffc] = 8'h12; memory[16'hfffd] = 8'h00;
    memory[16'hfff8] = 8'h13; memory[16'hfff9] = 8'h00;
    memory[16'h1000] = 8'h8e; memory[16'h1001] = 8'h01; // LDS #$01ff
    memory[16'h1002] = 8'hff;
    memory[16'h1003] = 8'h01;                         // NOP
    memory[16'h1004] = 8'h86; memory[16'h1005] = 8'h5a; // LDAA #$5a
    memory[16'h1006] = 8'hb7; memory[16'h1007] = 8'h20; // STAA $2000
    memory[16'h1008] = 8'h00;
    memory[16'h1009] = 8'hb7; memory[16'h100a] = 8'h20; // STAA $2001
    memory[16'h100b] = 8'h01;
    memory[16'h100c] = 8'h0e;                         // CLI
    memory[16'h100d] = 8'h3e;                         // WAI
    memory[16'h1200] = 8'h3b;                         // NMI handler: RTI
    memory[16'h1300] = 8'h3b;                         // IRQ handler: RTI

    #1;
    reset_n = 1'b0;
    #1;
    if (address != 16'hfffe || !address_oe || !read_not_write_oe ||
        !read_not_write || vma || ba || data_oe) begin
      $fatal(1, "MC6800 reset bus controls");
    end
    tick();
    reset_n = 1'b1;
    tick();
    tick();
    if (debug_pc != 16'h1000 || !opcode_fetch || !vma) $fatal(1, "MC6800 reset vector");
    checks = checks + 2;

    run_instruction(8'h8e);
    tsc = 1'b1;
    held_pc = debug_pc;
    tick();
    if (address_oe || read_not_write_oe || vma || ba || data_oe ||
        debug_pc != held_pc) begin
      $fatal(1, "MC6800 TSC bus release/stall");
    end
    tsc = 1'b0;
    run_instruction(8'h01);
    checks = checks + 2;

    // Enter the LDAA operand cycle before requesting HALT so the current
    // instruction must finish, rather than halting at the preceding boundary.
    tick();
    if (retire || debug_pc != 16'h1005) $fatal(1, "MC6800 HALT setup fetch");
    halt_n = 1'b0;
    run_instruction(8'h86);
    // Exercise the boundary where HALT takes ownership and an NMI edge arrives
    // on the same clock. The core is already gated, so the wrapper must retain it.
    nmi_n = 1'b0;
    tick();
    nmi_n = 1'b1;
    held_pc = debug_pc;
    if (!halted || !ba || address_oe || read_not_write_oe || vma || data_oe) begin
      $fatal(1, "MC6800 HALT bus release");
    end
    tick();
    if (debug_pc != held_pc) $fatal(1, "MC6800 HALT state changed");

    tick();
    halt_n = 1'b1;
    tick();
    halt_n = 1'b0;
    wait_for_interrupt(16'h1200, 2'b10);
    run_instruction(8'h3b);
    tick();
    if (!halted || debug_pc != 16'h1006) begin
      $fatal(1, "MC6800 single-step halt/RTI halted=%b pc=%04x retire=%b ba=%b",
             halted, debug_pc, retire, ba);
    end
    checks = checks + 4;

    // A maskable request latched during HALT remains pending while reset's I
    // mask is set, across ordinary instructions, and until CLI permits entry.
    irq_n = 1'b0;
    tick();
    irq_n = 1'b1;
    tick();
    halt_n = 1'b1;
    tick();
    run_store(1'b1);
    if (memory[16'h2000] != 8'h01) $fatal(1, "MC6800 DBE failed to suppress write");
    run_store(1'b0);
    if (memory[16'h2001] != 8'h5a) $fatal(1, "MC6800 enabled write missing");
    checks = checks + 2;

    run_instruction(8'h0e);
    wait_for_interrupt(16'h1300, 2'b01);
    run_instruction(8'h3b);
    if (debug_pc != 16'h100d || debug_sp != 16'h01ff || debug_ccr[4]) begin
      $fatal(1, "MC6800 held IRQ did not survive mask/release");
    end
    checks = checks + 2;

    run_instruction(8'h3e);
    if (!waiting_state || !ba || address_oe || read_not_write_oe || vma) begin
      $fatal(1, "MC6800 WAI bus release");
    end
    irq_n = 1'b0;
    wait_for_interrupt(16'h1300, 2'b01);
    irq_n = 1'b1;
    checks = checks + 2;

    if (debug_sp != 16'h01f8 || debug_a != 8'h5a || debug_b != 8'h00 ||
        debug_x != 16'h0000 || debug_ccr != 6'b010000 ||
        ((data_oe !== 1'b0) && (data_oe !== 1'b1))) begin
      $fatal(1, "MC6800 wrapper deterministic state");
    end
    $display("MC6800 BUS WRAPPER PASS: %0d reset, control, halt, interrupt, and DBE checks",
             checks);
    $finish;
  end
endmodule
