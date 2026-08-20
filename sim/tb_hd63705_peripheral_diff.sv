// SPDX-License-Identifier: MIT
module tb_hd63705_peripheral_diff;
  import hd63705_peripheral_vectors_pkg::*;
  import hd63705_peripheral_bus_stub_pkg::*;

  logic clk;
  // The DUT applies the same reset to asynchronous peripheral state and the
  // verification-only core boundary; this warning is testbench topology only.
  /* verilator lint_off SYNCASYNCNET */
  logic reset_n;
  /* verilator lint_on SYNCASYNCNET */
  logic standby_n;
  logic int_n;
  logic int2_n;
  logic timer_pin;
  logic [7:0] port_a_in;
  logic [7:0] port_b_in;
  logic [7:0] port_c_in;
  logic [6:0] port_d_in;
  logic [7:0] program_data;
  logic [13:0] program_address;
  logic program_read;
  logic [7:0] port_a_out;
  logic [7:0] port_b_out;
  logic [7:0] port_c_out;
  logic [6:0] port_d_out;
  logic [7:0] port_a_oe;
  logic [7:0] port_b_oe;
  logic [7:0] port_c_oe;
  logic [6:0] port_d_oe;
  logic sci_tx;
  logic sci_clock;
  logic timer_irq;
  logic sci_irq;
  logic int_irq;
  logic int2_irq;
  logic [15:0] irq_vector;
  logic [15:0] debug_address;
  logic [4:0] debug_ccr;
  logic [7:0] debug_timer;
  logic [7:0] debug_tcr;
  logic [7:0] debug_mr;
  logic [7:0] debug_scr;
  logic [7:0] debug_ssr;
  logic [7:0] debug_sdr;
  hd63705_peripheral_vector_t expected;
  integer cycle_index;
  integer map_address;
  integer map_checks;
  integer ram_checks;
  integer timer_value;
  integer timer_divide;
  integer timer_source;
  integer timer_event_index;
  integer timer_tcr_checks;
  integer timer_counter_checks;
  integer timer_source_checks;
  integer timer_access_checks;
  integer gpio_port;
  integer gpio_bit;
  integer gpio_latch;
  integer gpio_direction;
  integer gpio_pin;
  integer gpio_checks;
  integer sci_value;
  integer sci_initial;
  integer sci_ddr_checks;
  logic expected_program_read;
  logic [7:0] expected_timer;
  logic [7:0] expected_tcr;
  logic [7:0] expected_ddr;

  /* verilator lint_off PINCONNECTEMPTY */
  hd63705v0_mcu dut (
    .clk_i(clk), .reset_n_i(reset_n), .clock_enable_i(1'b1),
    .standby_n_i(standby_n), .int_n_i(int_n), .int2_n_i(int2_n),
    .timer_i(timer_pin), .port_a_i(port_a_in), .port_b_i(port_b_in),
    .port_c_i(port_c_in), .port_d_i(port_d_in), .port_a_o(port_a_out),
    .port_b_o(port_b_out), .port_c_o(port_c_out), .port_d_o(port_d_out),
    .port_a_oe_o(port_a_oe), .port_b_oe_o(port_b_oe),
    .port_c_oe_o(port_c_oe), .port_d_oe_o(port_d_oe),
    .program_address_o(program_address), .program_read_o(program_read),
    .program_data_i(program_data), .eprom_mode_i(1'b0),
    .eprom_address_i(12'h000), .eprom_data_i(8'h00),
    .eprom_chip_enable_n_i(1'b1), .eprom_output_enable_n_i(1'b1),
    .eprom_read_voltage_i(1'b0), .eprom_program_voltage_i(1'b0),
    .eprom_data_o(), .eprom_data_oe_o(),
    .eprom_program_data_o(), .eprom_program_o(), .sci_tx_o(sci_tx),
    .sci_clock_o(sci_clock), .timer_irq_o(timer_irq), .sci_irq_o(sci_irq),
    .int_irq_o(int_irq), .int2_irq_o(int2_irq), .irq_vector_o(irq_vector),
    .opcode_fetch_o(), .retire_o(), .illegal_o(), .undefined_o(),
    .waiting_o(), .stopped_o(), .interrupt_ack_o(),
    .debug_address_o(debug_address), .debug_pc_o(), .debug_sp_o(),
    .debug_a_o(), .debug_x_o(), .debug_ccr_o(debug_ccr), .debug_opcode_o(),
    .debug_instruction_cycles_o(), .debug_timer_o(debug_timer),
    .debug_tcr_o(debug_tcr), .debug_mr_o(debug_mr), .debug_scr_o(debug_scr),
    .debug_ssr_o(debug_ssr), .debug_sdr_o(debug_sdr)
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always #5 clk <= ~clk;

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic bus_write(input logic [13:0] address,
                           input logic [7:0] data);
    begin
      stub_address = {2'b00, address};
      stub_data = data;
      stub_valid = 1'b1;
      stub_write = 1'b1;
      tick();
    end
  endtask

  task automatic timer_source_event(input integer source);
    logic [7:0] timer_before;
    begin
      stub_valid = 1'b0;
      stub_write = 1'b0;
      case (source)
        0: begin
          timer_pin = 1'b0;
          tick();
        end
        1: begin
          timer_pin = 1'b1;
          tick();
        end
        3: begin
          timer_before = debug_timer;
          timer_pin = 1'b0;
          tick();
          if (debug_timer !== timer_before) begin
            $fatal(1, "HD63705 external timer counted on falling edge data=%02x/%02x",
                   debug_timer, timer_before);
          end
          timer_pin = 1'b1;
          tick();
        end
        default: $fatal(1, "HD63705 invalid timer source event %0d", source);
      endcase
    end
  endtask

  initial begin
    clk = 1'b0;
    reset_n = 1'b1;
    standby_n = 1'b1;
    int_n = 1'b1;
    int2_n = 1'b1;
    timer_pin = 1'b0;
    port_a_in = 8'hff;
    port_b_in = 8'hff;
    port_c_in = 8'hff;
    port_d_in = 7'h7f;
    program_data = 8'hff;
    stub_address = 16'h0000;
    stub_data = 8'h00;
    stub_write = 1'b0;
    stub_valid = 1'b0;
    stub_interrupt_mask = 1'b1;
    stub_waiting = 1'b0;
    stub_stopped = 1'b0;
    map_checks = 0;
    ram_checks = 0;
    timer_tcr_checks = 0;
    timer_counter_checks = 0;
    timer_source_checks = 0;
    timer_access_checks = 0;
    gpio_checks = 0;
    sci_ddr_checks = 0;
    #1;
    reset_n = 1'b0;
    #1;
    reset_n = 1'b1;

    for (cycle_index = 0; cycle_index < HD63705_PERIPHERAL_VECTOR_COUNT;
         cycle_index = cycle_index + 1) begin
      expected = hd63705_peripheral_vector(cycle_index[9:0]);
      stub_address = expected.address;
      stub_data = expected.data;
      stub_write = expected.write;
      stub_valid = expected.valid;
      stub_interrupt_mask = expected.interrupt_mask;
      stub_waiting = expected.waiting;
      stub_stopped = expected.stopped;
      int_n = expected.int_n;
      int2_n = expected.int2_n;
      timer_pin = expected.timer_pin;
      port_a_in = expected.port_a;
      port_b_in = expected.port_b;
      port_c_in = expected.port_c;
      port_d_in = expected.port_d;
      program_data = expected.program_data;
      #1;
      if ((expected.valid && !expected.write &&
           dut.core_data_in !== expected.read_data) ||
          program_address !== expected.address[13:0] ||
          program_read !== expected.program_bus ||
          debug_address !== {2'b00, expected.address[13:0]} ||
          debug_ccr !== {1'b0, expected.interrupt_mask, 3'b000}) begin
        $fatal(1, "HD63705 peripheral bus mismatch cycle=%0d address=%04x read=%02x/%02x program=%b/%b",
               cycle_index, expected.address, dut.core_data_in, expected.read_data,
               program_read, expected.program_bus);
      end
      tick();
      if (port_a_out !== expected.port_a_output || port_a_oe !== expected.port_a_oe ||
          port_b_out !== expected.port_b_output || port_b_oe !== expected.port_b_oe ||
          port_c_out !== expected.port_c_output || port_c_oe !== expected.port_c_oe ||
          port_d_out !== expected.port_d_output || port_d_oe !== expected.port_d_oe ||
          debug_timer !== expected.timer_data || debug_tcr !== expected.tcr ||
          debug_mr !== expected.mr || debug_scr !== expected.scr ||
          debug_ssr !== expected.ssr || debug_sdr !== expected.sdr ||
          timer_irq !== expected.timer_irq || sci_irq !== expected.sci_irq ||
          int_irq !== expected.int_irq || int2_irq !== expected.int2_irq ||
          dut.irq_request !== expected.irq_request || irq_vector !== expected.irq_vector ||
          sci_tx !== expected.sci_tx || sci_clock !== expected.sci_clock) begin
        $display("  ports A=%02x/%02x oe=%02x/%02x B=%02x/%02x oe=%02x/%02x C=%02x/%02x oe=%02x/%02x D=%02x/%02x oe=%02x/%02x",
                 port_a_out, expected.port_a_output, port_a_oe, expected.port_a_oe,
                 port_b_out, expected.port_b_output, port_b_oe, expected.port_b_oe,
                 port_c_out, expected.port_c_output, port_c_oe, expected.port_c_oe,
                 port_d_out, expected.port_d_output, port_d_oe, expected.port_d_oe);
        $display("  irq timer=%b/%b sci=%b/%b int=%b/%b int2=%b/%b any=%b/%b tx=%b/%b ck=%b/%b",
                 timer_irq, expected.timer_irq, sci_irq, expected.sci_irq,
                 int_irq, expected.int_irq, int2_irq, expected.int2_irq,
                 dut.irq_request, expected.irq_request, sci_tx, expected.sci_tx,
                 sci_clock, expected.sci_clock);
        $fatal(1, "HD63705 peripheral state mismatch cycle=%0d TDR=%02x/%02x TCR=%02x/%02x MR=%02x/%02x SCR=%02x/%02x SSR=%02x/%02x vector=%04x/%04x",
               cycle_index, debug_timer, expected.timer_data, debug_tcr, expected.tcr,
               debug_mr, expected.mr, debug_scr, expected.scr, debug_ssr,
               expected.ssr, irq_vector, expected.irq_vector);
      end
    end

    // Figure 2-1 accounts for all 14 physical address bits. QA635-338A
    // separately prohibits $0013-$001f as IC-test space; the deterministic
    // $ff read below is therefore checked only as the normalized FPGA policy.
    reset_n = 1'b0;
    #1;
    reset_n = 1'b1;
    standby_n = 1'b1;
    stub_waiting = 1'b0;
    stub_stopped = 1'b0;
    int_n = 1'b1;
    int2_n = 1'b1;
    timer_pin = 1'b0;
    port_a_in = 8'hff;
    port_b_in = 8'hff;
    port_c_in = 8'hff;
    port_d_in = 7'h7f;
    stub_valid = 1'b1;
    stub_write = 1'b0;
    for (map_address = 0; map_address < 16384;
         map_address = map_address + 1) begin
      stub_address = map_address[15:0];
      program_data = map_address[7:0] ^ 8'ha6;
      expected_program_read =
        (map_address >= 'h1000) && (map_address <= 'h1fff);
      #1;
      if (program_address !== map_address[13:0] ||
          program_read !== expected_program_read) begin
        $fatal(1, "HD63705 memory select address=%04x program_address=%04x read=%b/%b",
               map_address[13:0], program_address, program_read,
               expected_program_read);
      end
      if (expected_program_read && dut.core_data_in !== program_data) begin
        $fatal(1, "HD63705 EPROM read address=%04x data=%02x/%02x",
               map_address[13:0], dut.core_data_in, program_data);
      end else if (!(map_address <= 'h0012) &&
                   !((map_address >= 'h0040) && (map_address <= 'h00ff)) &&
                   !expected_program_read && dut.core_data_in !== 8'hff) begin
        $fatal(1, "HD63705 normalized unused/test read address=%04x data=%02x",
               map_address[13:0], dut.core_data_in);
      end
      map_checks = map_checks + 1;
    end

    // Fill and read all 192 bytes, then prove retention through both RES and
    // STBY. The latter is entered with nonzero DDRs so high impedance is also
    // observed independently of the register reset values.
    for (map_address = 'h0040; map_address <= 'h00ff;
         map_address = map_address + 1) begin
      stub_address = map_address[15:0];
      stub_data = map_address[7:0] ^ 8'h5a;
      stub_write = 1'b1;
      tick();
    end
    stub_write = 1'b0;
    for (map_address = 'h0040; map_address <= 'h00ff;
         map_address = map_address + 1) begin
      stub_address = map_address[15:0];
      #1;
      if (dut.core_data_in !== (map_address[7:0] ^ 8'h5a)) begin
        $fatal(1, "HD63705 RAM read address=%04x data=%02x",
               map_address[13:0], dut.core_data_in);
      end
      ram_checks = ram_checks + 1;
    end
    stub_valid = 1'b0;
    reset_n = 1'b0;
    #1;
    reset_n = 1'b1;
    stub_valid = 1'b1;
    for (map_address = 'h0040; map_address <= 'h00ff;
         map_address = map_address + 1) begin
      stub_address = map_address[15:0];
      #1;
      if (dut.core_data_in !== (map_address[7:0] ^ 8'h5a)) begin
        $fatal(1, "HD63705 RAM reset retention address=%04x data=%02x",
               map_address[13:0], dut.core_data_in);
      end
      ram_checks = ram_checks + 1;
    end

    // Tables 2-1 through 2-3 define every TCR bit, all eight divider ratios,
    // and all four input sources. QA635-314A covers TDR access during count;
    // QA635-315A fixes the external event polarity as rising-edge.
    timer_pin = 1'b0;
    for (timer_value = 0; timer_value < 256; timer_value = timer_value + 1) begin
      bus_write(14'h0009, 8'h20);
      bus_write(14'h0008, 8'h55);
      bus_write(14'h0009, timer_value[7:0]);
      expected_tcr = timer_value[7:0] & 8'h77;
      if (debug_tcr !== expected_tcr) begin
        $fatal(1, "HD63705 TCR write value=%02x read=%02x/%02x",
               timer_value[7:0], debug_tcr, expected_tcr);
      end
      if (timer_value[3] && dut.timer_prescaler !== 7'h7f) begin
        $fatal(1, "HD63705 TCR prescaler initialize value=%02x state=%02x",
               timer_value[7:0], dut.timer_prescaler);
      end
      timer_tcr_checks = timer_tcr_checks + 1;
    end

    for (timer_divide = 0; timer_divide < 8;
         timer_divide = timer_divide + 1) begin
      for (timer_value = 0; timer_value < 256;
           timer_value = timer_value + 1) begin
        bus_write(14'h0009, 8'h28 | timer_divide[7:0]);
        bus_write(14'h0008, timer_value[7:0]);
        bus_write(14'h0009, 8'h08 | timer_divide[7:0]);
        stub_valid = 1'b0;
        stub_write = 1'b0;
        timer_pin = 1'b0;
        tick();
        expected_timer = timer_value[7:0] - 8'h01;
        expected_tcr = timer_divide[7:0];
        if (timer_value == 1) expected_tcr = expected_tcr | 8'h80;
        if (debug_timer !== expected_timer || debug_tcr !== expected_tcr ||
            timer_irq !== (timer_value == 1)) begin
          $fatal(1, "HD63705 timer counter value=%02x divide=%0d TDR=%02x/%02x TCR=%02x/%02x irq=%b/%b",
                 timer_value[7:0], timer_divide, debug_timer, expected_timer,
                 debug_tcr, expected_tcr, timer_irq, timer_value == 1);
        end
        timer_counter_checks = timer_counter_checks + 1;
      end
    end

    for (timer_source = 0; timer_source < 4;
         timer_source = timer_source + 1) begin
      for (timer_divide = 0; timer_divide < 8;
           timer_divide = timer_divide + 1) begin
        timer_pin = 1'b0;
        bus_write(14'h0009, 8'h28 | timer_divide[7:0]);
        bus_write(14'h0008, 8'h02);
        bus_write(14'h0009, (timer_source[7:0] << 4) |
                            8'h08 | timer_divide[7:0]);
        stub_valid = 1'b0;
        stub_write = 1'b0;
        if (timer_source == 2) begin
          for (timer_event_index = 0;
               timer_event_index < (1 << timer_divide) + 2;
               timer_event_index = timer_event_index + 1) begin
            timer_pin = timer_event_index[0];
            tick();
            if (debug_timer !== 8'h02) begin
              $fatal(1, "HD63705 stopped timer divide=%0d event=%0d data=%02x",
                     timer_divide, timer_event_index, debug_timer);
            end
          end
        end else begin
          if (timer_source == 1) begin
            timer_pin = 1'b0;
            repeat (3) begin
              tick();
              if (debug_timer !== 8'h02) begin
                $fatal(1, "HD63705 gated-low timer divide=%0d data=%02x",
                       timer_divide, debug_timer);
              end
            end
          end
          timer_source_event(timer_source);
          if (debug_timer !== 8'h01) begin
            $fatal(1, "HD63705 timer first source event source=%0d divide=%0d data=%02x",
                   timer_source, timer_divide, debug_timer);
          end
          for (timer_event_index = 1;
               timer_event_index < (1 << timer_divide);
               timer_event_index = timer_event_index + 1) begin
            timer_source_event(timer_source);
            if (debug_timer !== 8'h01) begin
              $fatal(1, "HD63705 timer early divide source=%0d divide=%0d event=%0d data=%02x",
                     timer_source, timer_divide, timer_event_index, debug_timer);
            end
          end
          timer_source_event(timer_source);
          if (debug_timer !== 8'h00 || !timer_irq) begin
            $fatal(1, "HD63705 timer terminal source=%0d divide=%0d data=%02x irq=%b",
                   timer_source, timer_divide, debug_timer, timer_irq);
          end
        end
        timer_source_checks = timer_source_checks + 1;
      end
    end

    bus_write(14'h0009, 8'h28);
    bus_write(14'h0008, 8'h01);
    bus_write(14'h0009, 8'h08);
    stub_valid = 1'b0;
    tick();
    if (debug_timer !== 8'h00 || !timer_irq) begin
      $fatal(1, "HD63705 timer request assertion data=%02x irq=%b",
             debug_timer, timer_irq);
    end
    bus_write(14'h0009, 8'he0);
    if (debug_tcr !== 8'he0 || timer_irq) begin
      $fatal(1, "HD63705 timer mask/preserve TCR=%02x irq=%b", debug_tcr, timer_irq);
    end
    bus_write(14'h0009, 8'ha0);
    if (debug_tcr !== 8'ha0 || !timer_irq) begin
      $fatal(1, "HD63705 timer unmask/preserve TCR=%02x irq=%b", debug_tcr, timer_irq);
    end
    bus_write(14'h0009, 8'h20);
    if (debug_tcr !== 8'h20 || timer_irq) begin
      $fatal(1, "HD63705 timer request clear TCR=%02x irq=%b", debug_tcr, timer_irq);
    end
    bus_write(14'h0008, 8'h03);
    bus_write(14'h0009, 8'h08);
    stub_address = 16'h0008;
    stub_valid = 1'b1;
    stub_write = 1'b0;
    #1;
    if (dut.core_data_in !== 8'h03) begin
      $fatal(1, "HD63705 TDR active read data=%02x", dut.core_data_in);
    end
    tick();
    if (debug_timer !== 8'h02) begin
      $fatal(1, "HD63705 TDR read disturbed count data=%02x", debug_timer);
    end
    bus_write(14'h0008, 8'h55);
    if (debug_timer !== 8'h55) begin
      $fatal(1, "HD63705 TDR active write did not restart count data=%02x",
             debug_timer);
    end
    timer_access_checks = 8;

    // Figure 2-16(a) defines the complete 31-pin common-port truth table.
    // Exercise each bit independently for both latch, direction, and pin
    // values; Port D bit seven is the fixed-one non-pin readback bit.
    bus_write(14'h0010, 8'h00);
    for (gpio_port = 0; gpio_port < 4; gpio_port = gpio_port + 1) begin
      for (gpio_bit = 0; gpio_bit < ((gpio_port == 3) ? 7 : 8);
           gpio_bit = gpio_bit + 1) begin
        for (gpio_latch = 0; gpio_latch < 2; gpio_latch = gpio_latch + 1) begin
          for (gpio_direction = 0; gpio_direction < 2;
               gpio_direction = gpio_direction + 1) begin
            for (gpio_pin = 0; gpio_pin < 2; gpio_pin = gpio_pin + 1) begin
              port_a_in = 8'h00;
              port_b_in = 8'h00;
              port_c_in = 8'h00;
              port_d_in = 7'h00;
              case (gpio_port)
                0: port_a_in[gpio_bit] = gpio_pin[0];
                1: port_b_in[gpio_bit] = gpio_pin[0];
                2: port_c_in[gpio_bit] = gpio_pin[0];
                default: port_d_in[gpio_bit] = gpio_pin[0];
              endcase
              bus_write(gpio_port[13:0],
                        gpio_latch[0] ? (8'h01 << gpio_bit) : 8'h00);
              bus_write(gpio_port[13:0] + 14'd4,
                        gpio_direction[0] ? (8'h01 << gpio_bit) : 8'h00);
              stub_address = gpio_port[15:0];
              stub_valid = 1'b1;
              stub_write = 1'b0;
              #1;
              if (dut.core_data_in[gpio_bit] !==
                  (gpio_direction[0] ? gpio_latch[0] : gpio_pin[0])) begin
                $fatal(1, "HD63705 GPIO read port=%0d bit=%0d latch=%0d dir=%0d pin=%0d data=%02x",
                       gpio_port, gpio_bit, gpio_latch, gpio_direction,
                       gpio_pin, dut.core_data_in);
              end
              case (gpio_port)
                0: if (port_a_out[gpio_bit] !== gpio_latch[0] ||
                          port_a_oe[gpio_bit] !== gpio_direction[0])
                     $fatal(1, "HD63705 GPIO A output bit=%0d", gpio_bit);
                1: if (port_b_out[gpio_bit] !== gpio_latch[0] ||
                          port_b_oe[gpio_bit] !== gpio_direction[0])
                     $fatal(1, "HD63705 GPIO B output bit=%0d", gpio_bit);
                2: if (port_c_out[gpio_bit] !== gpio_latch[0] ||
                          port_c_oe[gpio_bit] !== gpio_direction[0])
                     $fatal(1, "HD63705 GPIO C output bit=%0d", gpio_bit);
                default: if (port_d_out[gpio_bit] !== gpio_latch[0] ||
                                port_d_oe[gpio_bit] !== gpio_direction[0])
                           $fatal(1, "HD63705 GPIO D output bit=%0d", gpio_bit);
              endcase
              gpio_checks = gpio_checks + 1;
            end
          end
        end
      end
    end
    stub_address = 16'h0003;
    stub_valid = 1'b1;
    stub_write = 1'b0;
    #1;
    if (dut.core_data_in[7] !== 1'b1) begin
      $fatal(1, "HD63705 Port D fixed-one readback data=%02x", dut.core_data_in);
    end
    gpio_checks = gpio_checks + 1;

    // QA635-302A says SCI selection writes D3/D4/D5's stored DDR value and
    // later deselection retains it; QA635-303A leaves D0-D2/D6 untouched.
    for (sci_value = 0; sci_value < 256; sci_value = sci_value + 1) begin
      for (sci_initial = 0; sci_initial < 2; sci_initial = sci_initial + 1) begin
        expected_ddr = sci_initial[0] ? 8'h7f : 8'h00;
        bus_write(14'h0007, expected_ddr);
        bus_write(14'h0010, sci_value[7:0]);
        if (sci_value[7]) expected_ddr[3] = 1'b1;
        if (sci_value[6]) expected_ddr[4] = 1'b0;
        if (sci_value[5]) expected_ddr[5] = !sci_value[4];
        if (dut.port_d_ddr !== expected_ddr[6:0] ||
            (port_d_oe & 7'h47) !== (expected_ddr[6:0] & 7'h47)) begin
          $fatal(1, "HD63705 SCI DDR write SCR=%02x initial=%02x DDR=%02x/%02x OE=%02x",
                 sci_value[7:0], sci_initial[0] ? 8'h7f : 8'h00,
                 dut.port_d_ddr, expected_ddr, port_d_oe);
        end
        bus_write(14'h0010, 8'h00);
        if (dut.port_d_ddr !== expected_ddr[6:0]) begin
          $fatal(1, "HD63705 SCI DDR retention SCR=%02x DDR=%02x/%02x",
                 sci_value[7:0], dut.port_d_ddr, expected_ddr);
        end
        sci_ddr_checks = sci_ddr_checks + 1;
      end
    end
    bus_write(14'h0010, 8'he0);
    bus_write(14'h0007, 8'h50);
    if ((port_d_oe & 7'h38) !== 7'h28 ||
        (port_d_oe & 7'h47) !== 7'h40) begin
      $fatal(1, "HD63705 SCI internal direction override OE=%02x", port_d_oe);
    end
    bus_write(14'h0010, 8'hf0);
    bus_write(14'h0007, 8'h70);
    if ((port_d_oe & 7'h38) !== 7'h08 ||
        (port_d_oe & 7'h47) !== 7'h40) begin
      $fatal(1, "HD63705 SCI external direction override OE=%02x", port_d_oe);
    end
    bus_write(14'h0010, 8'h00);
    if (port_d_oe !== 7'h70) begin
      $fatal(1, "HD63705 SCI disable direction retention OE=%02x", port_d_oe);
    end
    sci_ddr_checks = sci_ddr_checks + 3;

    bus_write(14'h0000, 8'ha5);
    bus_write(14'h0001, 8'h5a);
    bus_write(14'h0002, 8'hc3);
    bus_write(14'h0003, 8'h69);
    bus_write(14'h0004, 8'hf0);
    bus_write(14'h0005, 8'h0f);
    bus_write(14'h0006, 8'haa);
    bus_write(14'h0007, 8'h55);
    stub_valid = 1'b0;
    stub_write = 1'b0;
    stub_waiting = 1'b1;
    tick();
    if (port_a_out !== 8'ha5 || port_b_out !== 8'h5a ||
        port_c_out !== 8'hc3 || port_d_out !== 7'h69 ||
        port_a_oe !== 8'hf0 || port_b_oe !== 8'h0f ||
        port_c_oe !== 8'haa || port_d_oe !== 7'h55) begin
      $fatal(1, "HD63705 WAIT GPIO retention");
    end
    gpio_checks = gpio_checks + 8;
    stub_waiting = 1'b0;
    stub_stopped = 1'b1;
    tick();
    if (port_a_out !== 8'ha5 || port_b_out !== 8'h5a ||
        port_c_out !== 8'hc3 || port_d_out !== 7'h69 ||
        port_a_oe !== 8'hf0 || port_b_oe !== 8'h0f ||
        port_c_oe !== 8'haa || port_d_oe !== 7'h55) begin
      $fatal(1, "HD63705 STOP GPIO retention");
    end
    gpio_checks = gpio_checks + 8;
    stub_stopped = 1'b0;
    tick();

    for (map_address = 'h0004; map_address <= 'h0007;
         map_address = map_address + 1) begin
      bus_write(map_address[13:0], 8'hff);
    end
    if (port_a_oe !== 8'hff || port_b_oe !== 8'hff ||
        port_c_oe !== 8'hff || port_d_oe !== 7'h7f) begin
      $fatal(1, "HD63705 pre-standby GPIO direction");
    end
    stub_valid = 1'b0;
    stub_write = 1'b0;
    standby_n = 1'b0;
    #1;
    if (port_a_oe !== 8'h00 || port_b_oe !== 8'h00 ||
        port_c_oe !== 8'h00 || port_d_oe !== 7'h00 ||
        debug_tcr !== 8'h50 || debug_mr !== 8'h5f ||
        debug_scr !== 8'h00 || debug_ssr !== 8'h37) begin
      $fatal(1, "HD63705 standby reset/high impedance TCR=%02x MR=%02x SCR=%02x SSR=%02x",
             debug_tcr, debug_mr, debug_scr, debug_ssr);
    end
    reset_n = 1'b0;
    standby_n = 1'b1;
    #1;
    reset_n = 1'b1;
    stub_valid = 1'b1;
    for (map_address = 'h0040; map_address <= 'h00ff;
         map_address = map_address + 1) begin
      stub_address = map_address[15:0];
      #1;
      if (dut.core_data_in !== (map_address[7:0] ^ 8'h5a)) begin
        $fatal(1, "HD63705 RAM standby retention address=%04x data=%02x",
               map_address[13:0], dut.core_data_in);
      end
      ram_checks = ram_checks + 1;
    end

    $display("HD63705V0 PERIPHERAL DIFFERENTIAL PASS: seed=%08x cycles=%0d map checks=%0d RAM checks=%0d TCR checks=%0d timer counter checks=%0d source/divider checks=%0d timer access checks=%0d GPIO checks=%0d SCI DDR checks=%0d",
             32'h63705000, HD63705_PERIPHERAL_VECTOR_COUNT,
             map_checks, ram_checks, timer_tcr_checks, timer_counter_checks,
             timer_source_checks, timer_access_checks, gpio_checks,
             sci_ddr_checks);
    $finish;
  end
endmodule
