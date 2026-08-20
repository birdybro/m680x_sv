// SPDX-License-Identifier: MIT
module tb_mc68705p5_mask_timer;
  import mc68705p5_peripheral_bus_stub_pkg::*;

  localparam integer TIMER_CONFIGURATION_COUNT = 32;

  logic clk;
  logic reset_n;
  logic timer_pin;
  logic [7:0] debug_timer [0:TIMER_CONFIGURATION_COUNT-1];
  logic [7:0] debug_tcr [0:TIMER_CONFIGURATION_COUNT-1];
  logic timer_irq [0:TIMER_CONFIGURATION_COUNT-1];
  integer option_index;
  integer divide_select;
  logic [7:0] expected_counter;
  integer checks;
  integer pulse_index;

  genvar generate_index;
  generate
    for (generate_index = 0;
         generate_index < TIMER_CONFIGURATION_COUNT;
         generate_index = generate_index + 1) begin : timer_dut
      localparam logic [2:0] DIVIDE_OPTION = 3'(generate_index);
      localparam logic CLOCK_SOURCE_OPTION = (generate_index % 16) >= 8;
      localparam logic TIE_OPTION = generate_index >= 16;
      localparam logic [7:0] DEVICE_MASK_OPTION = {
        1'b0, 1'b1, CLOCK_SOURCE_OPTION, TIE_OPTION, 1'b0, DIVIDE_OPTION
      };

      /* verilator lint_off PINCONNECTEMPTY */
      mc68705p5_mcu #(.MASK_OPTION(DEVICE_MASK_OPTION)) dut (
        .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(1'b1),
        .int_n_i(1'b1), .timer_i(timer_pin), .port_a_i(8'hff),
        .port_b_i(8'hff), .port_c_i(4'hf), .port_a_o(), .port_b_o(),
        .port_c_o(), .port_a_oe_o(), .port_b_oe_o(), .port_c_oe_o(),
        .program_address_o(), .program_read_o(), .program_data_i(8'hff),
        .vpp_present_i(1'b0), .bootstrap_voltage_i(1'b0),
        .bootstrap_mode_o(), .eprom_latch_enable_o(),
        .eprom_program_enable_o(), .eprom_program_address_o(),
        .eprom_program_data_o(), .timer_irq_o(timer_irq[generate_index]),
        .external_irq_o(), .opcode_fetch_o(), .retire_o(), .illegal_o(),
        .undefined_o(), .waiting_o(), .stopped_o(), .interrupt_ack_o(),
        .debug_address_o(), .debug_pc_o(), .debug_sp_o(), .debug_a_o(),
        .debug_x_o(), .debug_ccr_o(), .debug_opcode_o(),
        .debug_instruction_cycles_o(),
        .debug_timer_o(debug_timer[generate_index]),
        .debug_timer_control_o(debug_tcr[generate_index]),
        .debug_program_control_o()
      );
      /* verilator lint_on PINCONNECTEMPTY */
    end
  endgenerate

  always #5 clk <= ~clk;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic write_register(input logic [10:0] address_value,
                                input logic [7:0] data_value);
    begin
      stub_address = {5'h00, address_value};
      stub_data = data_value;
      stub_write = 1'b1;
      stub_valid = 1'b1;
      tick();
      stub_valid = 1'b0;
      stub_write = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    timer_pin = 1'b0;
    stub_address = 16'h0000;
    stub_data = 8'h00;
    stub_write = 1'b0;
    stub_valid = 1'b0;
    stub_interrupt_mask = 1'b1;
    checks = 0;
    #1;
    reset_n = 1'b0;
    #1;
    reset_n = 1'b1;
    tick();

    // TOPT fixes CLS and PS2:PS0 from MOR, forces TIE/PSC read high, and
    // leaves only TIR/TIM writable. Instantiate both values of ignored MOR
    // TIE across every source/divider combination.
    for (option_index = 0; option_index < TIMER_CONFIGURATION_COUNT;
         option_index = option_index + 1) begin
      if (debug_tcr[option_index] !== 8'h7f ||
          debug_timer[option_index] !== 8'hff) begin
        $fatal(1, "P5 MOR reset option=%0d TCR=%02x TDR=%02x",
               option_index, debug_tcr[option_index],
               debug_timer[option_index]);
      end
      checks = checks + 1;
    end

    write_register(11'h009, 8'h00);
    for (option_index = 0; option_index < TIMER_CONFIGURATION_COUNT;
         option_index = option_index + 1) begin
      if (debug_tcr[option_index] !== 8'h3f) begin
        $fatal(1, "P5 MOR ignored-lower write option=%0d TCR=%02x",
               option_index, debug_tcr[option_index]);
      end
      checks = checks + 1;
    end

    write_register(11'h009, 8'hc0);
    for (option_index = 0; option_index < TIMER_CONFIGURATION_COUNT;
         option_index = option_index + 1) begin
      if (debug_tcr[option_index] !== 8'hff || timer_irq[option_index]) begin
        $fatal(1, "P5 MOR TIR/TIM write option=%0d TCR=%02x IRQ=%b",
               option_index, debug_tcr[option_index], timer_irq[option_index]);
      end
      checks = checks + 1;
    end

    write_register(11'h009, 8'h00);
    write_register(11'h008, 8'h02);
    timer_pin = 1'b1;
    tick();
    for (option_index = 0; option_index < TIMER_CONFIGURATION_COUNT;
         option_index = option_index + 1) begin
      if (debug_timer[option_index] !== 8'h01 || timer_irq[option_index]) begin
        $fatal(1, "P5 MOR initial event option=%0d TDR=%02x IRQ=%b",
               option_index, debug_timer[option_index], timer_irq[option_index]);
      end
      checks = checks + 1;
    end

    // A held-high TIMER pin clocks the gated-internal configurations every
    // cycle but supplies only the already-consumed initial rising transition
    // to external-clock configurations.
    for (pulse_index = 0; pulse_index < 128;
         pulse_index = pulse_index + 1) begin
      tick();
    end
    for (option_index = 0; option_index < TIMER_CONFIGURATION_COUNT;
         option_index = option_index + 1) begin
      divide_select = option_index % 8;
      if ((option_index % 16) < 8) begin
        expected_counter = 8'(1 - (128 >> divide_select));
        if (debug_timer[option_index] !== expected_counter ||
            !timer_irq[option_index] || debug_tcr[option_index] !== 8'hbf) begin
          $fatal(1, "P5 MOR gated count option=%0d TDR=%02x/%02x TCR=%02x",
                 option_index, debug_timer[option_index],
                 expected_counter, debug_tcr[option_index]);
        end
      end else if (debug_timer[option_index] !== 8'h01 ||
                   timer_irq[option_index] ||
                   debug_tcr[option_index] !== 8'h3f) begin
        $fatal(1, "P5 MOR held external option=%0d TDR=%02x TCR=%02x IRQ=%b",
               option_index, debug_timer[option_index],
               debug_tcr[option_index], timer_irq[option_index]);
      end
      checks = checks + 1;
    end

    // Re-armed positive transitions clock both groups. This gives 256 total
    // post-initial events to gated configurations and 128 to external ones.
    for (pulse_index = 0; pulse_index < 128;
         pulse_index = pulse_index + 1) begin
      timer_pin = 1'b0;
      tick();
      timer_pin = 1'b1;
      tick();
    end
    for (option_index = 0; option_index < TIMER_CONFIGURATION_COUNT;
         option_index = option_index + 1) begin
      divide_select = option_index % 8;
      if ((option_index % 16) < 8) begin
        expected_counter = 8'(1 - (256 >> divide_select));
      end else begin
        expected_counter = 8'(1 - (128 >> divide_select));
      end
      if (debug_timer[option_index] !== expected_counter ||
          !timer_irq[option_index] || debug_tcr[option_index] !== 8'hbf) begin
        $fatal(1, "P5 MOR edge count option=%0d TDR=%02x/%02x TCR=%02x IRQ=%b",
               option_index, debug_timer[option_index], expected_counter,
               debug_tcr[option_index], timer_irq[option_index]);
      end
      checks = checks + 1;
    end

    write_register(11'h009, 8'h40);
    for (option_index = 0; option_index < TIMER_CONFIGURATION_COUNT;
         option_index = option_index + 1) begin
      if (debug_tcr[option_index] !== 8'h7f || timer_irq[option_index]) begin
        $fatal(1, "P5 MOR clear/mask option=%0d TCR=%02x IRQ=%b",
               option_index, debug_tcr[option_index], timer_irq[option_index]);
      end
      checks = checks + 1;
    end

    $display("MC68705P5 MOR TIMER PASS: %0d fixed-option checks", checks);
    $finish;
  end
endmodule
