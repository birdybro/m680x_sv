// SPDX-License-Identifier: MIT
module m6805_core #(
  parameter logic        HITACHI_PROFILE = 1'b0,
  parameter logic [15:0] PC_MASK = 16'hffff,
  parameter logic [15:0] STACK_BASE = 16'h0060,
  parameter logic [15:0] STACK_MASK = 16'h001f,
  parameter logic [15:0] STACK_TOP = 16'h007f,
  parameter logic [15:0] SWI_VECTOR = 16'hfffc,
  parameter logic [15:0] RESET_VECTOR = 16'hfffe
) (
  input  logic        clk_i,
  input  logic        reset_n_i,
  input  logic        clock_enable_i,
  input  logic        bus_ready_i,
  input  logic        irq_n_i,
  input  logic        interrupt_pin_n_i,
  input  logic [15:0] irq_vector_i,
  input  logic [7:0]  data_i,
  output logic [15:0] address_o,
  output logic [7:0]  data_o,
  output logic        write_o,
  output logic        bus_valid_o,
  output logic        opcode_fetch_o,
  output logic        retire_o,
  output logic        illegal_o,
  output logic        undefined_o,
  output logic        waiting_o,
  output logic        stopped_o,
  output logic        interrupt_ack_o,
  output logic [7:0]  debug_a_o,
  output logic [7:0]  debug_x_o,
  output logic [15:0] debug_sp_o,
  output logic [15:0] debug_pc_o,
  output logic [4:0]  debug_ccr_o,
  output logic [7:0]  debug_opcode_o,
  output logic [3:0]  debug_instruction_cycles_o
);
  import m680x_alu_pkg::*;
  import m680x_decode_pkg::*;

  localparam int CCR_H = 4;
  localparam int CCR_I = 3;
  localparam int CCR_N = 2;
  localparam int CCR_Z = 1;
  localparam int CCR_C = 0;

  typedef enum logic [5:0] {
    ST_RESET_HIGH,
    ST_RESET_LOW,
    ST_FETCH,
    ST_EXECUTE,
    ST_RELATIVE,
    ST_IMMEDIATE,
    ST_DIRECT,
    ST_EXTENDED_HIGH,
    ST_EXTENDED_LOW,
    ST_INDEXED_NONE,
    ST_INDEXED_8,
    ST_INDEXED_16_HIGH,
    ST_INDEXED_16_LOW,
    ST_MEMORY_READ,
    ST_MEMORY_WRITE,
    ST_BIT_ADDRESS,
    ST_BIT_DISPLACEMENT,
    ST_BIT_READ,
    ST_BIT_WRITE,
    ST_PUSH_RETURN_LOW,
    ST_PUSH_RETURN_HIGH,
    ST_PULL_PC_HIGH,
    ST_PULL_PC_LOW,
    ST_INTERRUPT_PUSH,
    ST_INTERRUPT_VECTOR_HIGH,
    ST_INTERRUPT_VECTOR_LOW,
    ST_RTI_PULL,
    ST_PADDING,
    ST_WAITING,
    ST_STOPPED,
    ST_ILLEGAL
  } state_t;

  state_t state;
  state_t terminal_state;
  opcode_decode_t decoded;
  opcode_decode_t fetched_decode;
  logic [7:0] accumulator;
  logic [7:0] index_register;
  logic [15:0] stack_pointer;
  logic [15:0] program_counter;
  logic [4:0] condition_codes;
  logic [7:0] instruction_register;
  logic [3:0] cycles_left;
  logic [15:0] effective_address;
  logic [15:0] control_target;
  logic [15:0] vector_address;
  logic [7:0] temporary_high;
  logic [7:0] write_data;
  logic [7:0] branch_displacement;
  logic [2:0] phase;
  logic external_interrupt;
  logic decoded_sane;
  logic interrupt_enable_delay;

  function automatic logic [15:0] pc_value(input logic [15:0] value);
    pc_value = value & PC_MASK;
  endfunction

  function automatic logic [15:0] stack_advance(
    input logic [15:0] value,
    input logic decrement
  );
    logic [15:0] low_value;
    begin
      low_value = decrement ? (value - 16'h0001) : (value + 16'h0001);
      stack_advance = STACK_BASE | (low_value & STACK_MASK);
    end
  endfunction

  function automatic logic [7:0] selected_register(input operation_target_t target);
    selected_register = (target == TARGET_X) ? index_register : accumulator;
  endfunction

  function automatic logic branch_condition(input operation_t operation);
    logic h;
    logic i;
    logic n;
    logic z;
    logic c;
    begin
      h = condition_codes[CCR_H];
      i = condition_codes[CCR_I];
      n = condition_codes[CCR_N];
      z = condition_codes[CCR_Z];
      c = condition_codes[CCR_C];
      case (operation)
        OP_BRA: branch_condition = 1'b1;
        OP_BRN: branch_condition = 1'b0;
        OP_BHI: branch_condition = !c && !z;
        OP_BLS: branch_condition = c || z;
        OP_BCC: branch_condition = !c;
        OP_BCS: branch_condition = c;
        OP_BNE: branch_condition = !z;
        OP_BEQ: branch_condition = z;
        OP_BHCC: branch_condition = !h;
        OP_BHCS: branch_condition = h;
        OP_BPL: branch_condition = !n;
        OP_BMI: branch_condition = n;
        OP_BMC: branch_condition = !i;
        OP_BMS: branch_condition = i;
        OP_BIL: branch_condition = !interrupt_pin_n_i;
        OP_BIH: branch_condition = interrupt_pin_n_i;
        default: branch_condition = 1'b0;
      endcase
    end
  endfunction

  function automatic logic is_rmw(input operation_t operation);
    case (operation)
      OP_NEG, OP_COM, OP_LSR, OP_ROR, OP_ASR, OP_ASL, OP_ROL,
      OP_DEC, OP_INC, OP_TST, OP_CLR: is_rmw = 1'b1;
      default: is_rmw = 1'b0;
    endcase
  endfunction

  task automatic finish_to(input state_t destination);
    begin
      terminal_state <= destination;
      if (cycles_left <= 4'd1) begin
        state <= destination;
        retire_o <= 1'b1;
      end else begin
        state <= ST_PADDING;
      end
    end
  endtask

  task automatic set_selected_register(
    input operation_target_t target,
    input logic [7:0] value
  );
    begin
      if (target == TARGET_X) index_register <= value;
      else accumulator <= value;
    end
  endtask

  task automatic set_nz(input logic [7:0] value);
    begin
      condition_codes[CCR_N] <= value[7];
      condition_codes[CCR_Z] <= (value == 8'h00);
    end
  endtask

  task automatic route_address(input logic [15:0] address_value);
    logic [7:0] stored_value;
    begin
      effective_address <= address_value;
      if (decoded.operation == OP_JMP) begin
        program_counter <= pc_value(address_value);
        finish_to(ST_FETCH);
      end else if (decoded.operation == OP_JSR) begin
        control_target <= pc_value(address_value);
        state <= ST_PUSH_RETURN_LOW;
      end else if ((decoded.operation == OP_STA) || (decoded.operation == OP_STX)) begin
        stored_value = (decoded.operation == OP_STX) ? index_register : accumulator;
        write_data <= stored_value;
        set_nz(stored_value);
        state <= ST_MEMORY_WRITE;
      end else if (decoded.operation == OP_CLR) begin
        write_data <= 8'h00;
        condition_codes[CCR_N] <= 1'b0;
        condition_codes[CCR_Z] <= 1'b1;
        state <= ST_MEMORY_WRITE;
      end else begin
        state <= ST_MEMORY_READ;
      end
    end
  endtask

  task automatic apply_rmw_flags(
    input operation_t operation,
    input logic n,
    input logic z,
    input logic c
  );
    begin
      condition_codes[CCR_N] <= n;
      condition_codes[CCR_Z] <= z;
      case (operation)
        OP_NEG, OP_COM, OP_LSR, OP_ROR, OP_ASR, OP_ASL, OP_ROL:
          condition_codes[CCR_C] <= c;
        default: ;
      endcase
    end
  endtask

  task automatic execute_byte(
    input logic [7:0] operand,
    input logic memory_destination
  );
    logic [7:0] left;
    // The shared ALU reports V for M6800-family users; M6805 has no V bit.
    /* verilator lint_off UNUSEDSIGNAL */
    alu8_result_t result_value;
    /* verilator lint_on UNUSEDSIGNAL */
    begin
      left = (decoded.operation == OP_CPX) ? index_register : accumulator;
      result_value = '0;
      case (decoded.operation)
        OP_ADD, OP_ADC: begin
          result_value = add8(left, operand,
            (decoded.operation == OP_ADC) ? condition_codes[CCR_C] : 1'b0);
          accumulator <= result_value.value;
          condition_codes[CCR_H] <= result_value.h;
          condition_codes[CCR_N] <= result_value.n;
          condition_codes[CCR_Z] <= result_value.z;
          condition_codes[CCR_C] <= result_value.c;
          finish_to(ST_FETCH);
        end
        OP_SUB, OP_SBC, OP_CMP, OP_CPX: begin
          result_value = sub8(left, operand,
            (decoded.operation == OP_SBC) ? condition_codes[CCR_C] : 1'b0);
          if ((decoded.operation == OP_SUB) || (decoded.operation == OP_SBC)) begin
            accumulator <= result_value.value;
          end
          condition_codes[CCR_N] <= result_value.n;
          condition_codes[CCR_Z] <= result_value.z;
          condition_codes[CCR_C] <= result_value.c;
          finish_to(ST_FETCH);
        end
        OP_AND, OP_BIT: begin
          result_value = logic8(left, operand, 2'd0);
          if (decoded.operation == OP_AND) accumulator <= result_value.value;
          set_nz(result_value.value);
          finish_to(ST_FETCH);
        end
        OP_EOR: begin
          result_value = logic8(left, operand, 2'd2);
          accumulator <= result_value.value;
          set_nz(result_value.value);
          finish_to(ST_FETCH);
        end
        OP_ORA: begin
          result_value = logic8(left, operand, 2'd1);
          accumulator <= result_value.value;
          set_nz(result_value.value);
          finish_to(ST_FETCH);
        end
        OP_LDA, OP_LDX: begin
          if (decoded.operation == OP_LDX) index_register <= operand;
          else accumulator <= operand;
          set_nz(operand);
          finish_to(ST_FETCH);
        end
        OP_NEG: result_value = neg8(operand);
        OP_COM: result_value = com8(operand);
        OP_LSR: result_value = lsr8(operand);
        OP_ROR: result_value = ror8(operand, condition_codes[CCR_C]);
        OP_ASR: result_value = asr8(operand);
        OP_ASL: result_value = asl8(operand);
        OP_ROL: result_value = rol8(operand, condition_codes[CCR_C]);
        OP_DEC: result_value = dec8(operand);
        OP_INC: result_value = inc8(operand);
        OP_TST: result_value = tst8(operand);
        OP_CLR: result_value = clr8();
        default: begin
          illegal_o <= 1'b1;
          state <= ST_ILLEGAL;
        end
      endcase
      if (is_rmw(decoded.operation)) begin
        apply_rmw_flags(decoded.operation, result_value.n, result_value.z, result_value.c);
        if (decoded.operation == OP_TST) begin
          finish_to(ST_FETCH);
        end else if (memory_destination) begin
          write_data <= result_value.value;
          state <= ST_MEMORY_WRITE;
        end else begin
          set_selected_register(decoded.target, result_value.value);
          finish_to(ST_FETCH);
        end
      end
    end
  endtask

  task automatic execute_inherent();
    // The shared DAA result exposes adjustment for exhaustive verification;
    // architectural execution consumes only the adjusted value and flags.
    /* verilator lint_off UNUSEDSIGNAL */
    daa_result_t decimal_value;
    /* verilator lint_on UNUSEDSIGNAL */
    begin
      decimal_value = '0;
      case (decoded.operation)
        OP_NOP: finish_to(ST_FETCH);
        OP_TAX: begin
          index_register <= accumulator;
          finish_to(ST_FETCH);
        end
        OP_TXA: begin
          accumulator <= index_register;
          finish_to(ST_FETCH);
        end
        OP_RSP: begin
          stack_pointer <= STACK_TOP;
          finish_to(ST_FETCH);
        end
        OP_CLC, OP_SEC: begin
          condition_codes[CCR_C] <= (decoded.operation == OP_SEC);
          finish_to(ST_FETCH);
        end
        OP_CLI, OP_SEI: begin
          condition_codes[CCR_I] <= (decoded.operation == OP_SEI);
          interrupt_enable_delay <=
            (decoded.operation == OP_CLI) && HITACHI_PROFILE;
          finish_to(ST_FETCH);
        end
        OP_DAA: begin
          decimal_value = daa8(accumulator, condition_codes[CCR_H], condition_codes[CCR_C]);
          if (decimal_value.defined_state) begin
            accumulator <= decimal_value.value;
            condition_codes[CCR_N] <= decimal_value.n;
            condition_codes[CCR_Z] <= decimal_value.z;
            condition_codes[CCR_C] <= decimal_value.c;
          end else begin
            undefined_o <= 1'b1;
          end
          finish_to(ST_FETCH);
        end
        OP_STOP, OP_WAIT: begin
          condition_codes[CCR_I] <= 1'b0;
          interrupt_enable_delay <= 1'b0;
          if (decoded.operation == OP_STOP) begin
            finish_to(ST_STOPPED);
          end else begin
            finish_to(ST_WAITING);
          end
        end
        OP_RTS: state <= ST_PULL_PC_HIGH;
        OP_RTI: begin
          phase <= 3'd0;
          state <= ST_RTI_PULL;
        end
        OP_SWI: begin
          vector_address <= SWI_VECTOR;
          external_interrupt <= 1'b0;
          phase <= 3'd0;
          state <= ST_INTERRUPT_PUSH;
        end
        default: begin
          if (is_rmw(decoded.operation)) execute_byte(selected_register(decoded.target), 1'b0);
          else begin
            illegal_o <= 1'b1;
            state <= ST_ILLEGAL;
          end
        end
      endcase
    end
  endtask

  task automatic execute_single_cycle(input operation_t operation);
    begin
      case (operation)
        OP_NOP: ;
        OP_CLC: condition_codes[CCR_C] <= 1'b0;
        OP_SEC: condition_codes[CCR_C] <= 1'b1;
        default: begin
          illegal_o <= 1'b1;
          state <= ST_ILLEGAL;
        end
      endcase
      if ((operation == OP_NOP) || (operation == OP_CLC) || (operation == OP_SEC)) begin
        cycles_left <= 4'd0;
        terminal_state <= ST_FETCH;
        state <= ST_FETCH;
        retire_o <= 1'b1;
      end
    end
  endtask

  always_comb begin
    address_o = 16'h0000;
    data_o = 8'h00;
    write_o = 1'b0;
    bus_valid_o = 1'b0;
    opcode_fetch_o = 1'b0;
    case (state)
      ST_RESET_HIGH: begin address_o = RESET_VECTOR; bus_valid_o = 1'b1; end
      ST_RESET_LOW: begin address_o = RESET_VECTOR + 16'h0001; bus_valid_o = 1'b1; end
      ST_FETCH: begin
        address_o = program_counter;
        bus_valid_o = 1'b1;
        opcode_fetch_o = 1'b1;
      end
      ST_RELATIVE, ST_IMMEDIATE, ST_DIRECT, ST_EXTENDED_HIGH, ST_EXTENDED_LOW,
      ST_INDEXED_8, ST_INDEXED_16_HIGH, ST_INDEXED_16_LOW,
      ST_BIT_ADDRESS, ST_BIT_DISPLACEMENT: begin
        address_o = program_counter;
        bus_valid_o = 1'b1;
      end
      ST_MEMORY_READ, ST_BIT_READ: begin
        address_o = effective_address;
        bus_valid_o = 1'b1;
      end
      ST_MEMORY_WRITE, ST_BIT_WRITE: begin
        address_o = effective_address;
        data_o = write_data;
        write_o = 1'b1;
        bus_valid_o = 1'b1;
      end
      ST_PUSH_RETURN_LOW: begin
        address_o = stack_pointer;
        data_o = program_counter[7:0];
        write_o = 1'b1;
        bus_valid_o = 1'b1;
      end
      ST_PUSH_RETURN_HIGH: begin
        address_o = stack_pointer;
        data_o = program_counter[15:8];
        write_o = 1'b1;
        bus_valid_o = 1'b1;
      end
      ST_PULL_PC_HIGH, ST_PULL_PC_LOW, ST_RTI_PULL: begin
        address_o = stack_advance(stack_pointer, 1'b0);
        bus_valid_o = 1'b1;
      end
      ST_INTERRUPT_PUSH: begin
        address_o = stack_pointer;
        write_o = 1'b1;
        bus_valid_o = 1'b1;
        case (phase)
          3'd0: data_o = program_counter[7:0];
          3'd1: data_o = program_counter[15:8];
          3'd2: data_o = index_register;
          3'd3: data_o = accumulator;
          default: data_o = {3'b111, condition_codes};
        endcase
      end
      ST_INTERRUPT_VECTOR_HIGH: begin address_o = vector_address; bus_valid_o = 1'b1; end
      ST_INTERRUPT_VECTOR_LOW: begin address_o = vector_address + 16'h0001; bus_valid_o = 1'b1; end
      default: ;
    endcase
  end

  // State-mutating tasks are called only from this single clocked process.
  always @(posedge clk_i or negedge reset_n_i) begin
    if (!reset_n_i) begin
      state <= ST_RESET_HIGH;
      terminal_state <= ST_FETCH;
      decoded <= '0;
      accumulator <= 8'h00;
      index_register <= 8'h00;
      stack_pointer <= STACK_TOP;
      program_counter <= 16'h0000;
      condition_codes <= 5'b01000;
      instruction_register <= 8'h00;
      cycles_left <= 4'd0;
      effective_address <= 16'h0000;
      control_target <= 16'h0000;
      vector_address <= SWI_VECTOR;
      temporary_high <= 8'h00;
      write_data <= 8'h00;
      branch_displacement <= 8'h00;
      phase <= 3'd0;
      external_interrupt <= 1'b0;
      interrupt_enable_delay <= 1'b0;
      retire_o <= 1'b0;
      illegal_o <= 1'b0;
      undefined_o <= 1'b0;
      interrupt_ack_o <= 1'b0;
    end else if (clock_enable_i && (!bus_valid_o || bus_ready_i)) begin
      retire_o <= 1'b0;
      undefined_o <= 1'b0;
      interrupt_ack_o <= 1'b0;
      if (interrupt_enable_delay) interrupt_enable_delay <= 1'b0;
      if (state != ST_FETCH && state != ST_RESET_HIGH && state != ST_RESET_LOW &&
          state != ST_WAITING && state != ST_STOPPED && state != ST_ILLEGAL) begin
        cycles_left <= cycles_left - 4'd1;
      end
      case (state)
        ST_RESET_HIGH: begin
          temporary_high <= data_i;
          state <= ST_RESET_LOW;
        end
        ST_RESET_LOW: begin
          program_counter <= pc_value({temporary_high, data_i});
          state <= ST_FETCH;
        end
        ST_FETCH: begin
          if (!irq_n_i && !condition_codes[CCR_I] && !interrupt_enable_delay) begin
            vector_address <= irq_vector_i;
            external_interrupt <= 1'b1;
            phase <= 3'd0;
            state <= ST_INTERRUPT_PUSH;
          end else begin
            instruction_register <= data_i;
            decoded <= fetched_decode;
            program_counter <= pc_value(program_counter + 16'h0001);
            if (!fetched_decode.valid) begin
              illegal_o <= 1'b1;
              state <= ST_ILLEGAL;
            end else begin
              cycles_left <= fetched_decode.cycles - 4'd1;
              if (HITACHI_PROFILE && (fetched_decode.cycles == 4'd1)) begin
                execute_single_cycle(fetched_decode.operation);
              end else begin
                case (fetched_decode.mode)
                  AM_INHERENT, AM_ACCUMULATOR_A, AM_INDEX_REGISTER_X: state <= ST_EXECUTE;
                  AM_RELATIVE: state <= ST_RELATIVE;
                  AM_IMMEDIATE_8: state <= ST_IMMEDIATE;
                  AM_DIRECT: state <= ST_DIRECT;
                  AM_EXTENDED: state <= ST_EXTENDED_HIGH;
                  AM_INDEXED_NONE: state <= ST_INDEXED_NONE;
                  AM_INDEXED_8: state <= ST_INDEXED_8;
                  AM_INDEXED_16: state <= ST_INDEXED_16_HIGH;
                  AM_BIT_TEST_BRANCH: state <= ST_BIT_ADDRESS;
                  AM_BIT_SET_CLEAR: state <= ST_BIT_ADDRESS;
                  default: begin illegal_o <= 1'b1; state <= ST_ILLEGAL; end
                endcase
              end
            end
          end
        end
        ST_EXECUTE: execute_inherent();
        ST_RELATIVE: begin
          program_counter <= pc_value(program_counter + 16'h0001);
          if (decoded.operation == OP_BSR) begin
            control_target <= pc_value(program_counter + 16'h0001 + {{8{data_i[7]}}, data_i});
            state <= ST_PUSH_RETURN_LOW;
          end else begin
            if (branch_condition(decoded.operation)) begin
              program_counter <= pc_value(program_counter + 16'h0001 + {{8{data_i[7]}}, data_i});
            end
            finish_to(ST_FETCH);
          end
        end
        ST_IMMEDIATE: begin
          program_counter <= pc_value(program_counter + 16'h0001);
          execute_byte(data_i, 1'b0);
        end
        ST_DIRECT: begin
          program_counter <= pc_value(program_counter + 16'h0001);
          route_address({8'h00, data_i});
        end
        ST_EXTENDED_HIGH: begin
          temporary_high <= data_i;
          program_counter <= pc_value(program_counter + 16'h0001);
          state <= ST_EXTENDED_LOW;
        end
        ST_EXTENDED_LOW: begin
          program_counter <= pc_value(program_counter + 16'h0001);
          route_address({temporary_high, data_i});
        end
        ST_INDEXED_NONE: route_address({8'h00, index_register});
        ST_INDEXED_8: begin
          program_counter <= pc_value(program_counter + 16'h0001);
          route_address({8'h00, index_register} + {8'h00, data_i});
        end
        ST_INDEXED_16_HIGH: begin
          temporary_high <= data_i;
          program_counter <= pc_value(program_counter + 16'h0001);
          state <= ST_INDEXED_16_LOW;
        end
        ST_INDEXED_16_LOW: begin
          program_counter <= pc_value(program_counter + 16'h0001);
          route_address({8'h00, index_register} + {temporary_high, data_i});
        end
        ST_MEMORY_READ: execute_byte(data_i, 1'b1);
        ST_MEMORY_WRITE: finish_to(ST_FETCH);
        ST_BIT_ADDRESS: begin
          effective_address <= {8'h00, data_i};
          program_counter <= pc_value(program_counter + 16'h0001);
          if (decoded.mode == AM_BIT_TEST_BRANCH) begin
            state <= ST_BIT_DISPLACEMENT;
          end else begin
            state <= ST_BIT_READ;
          end
        end
        ST_BIT_DISPLACEMENT: begin
          branch_displacement <= data_i;
          program_counter <= pc_value(program_counter + 16'h0001);
          state <= ST_BIT_READ;
        end
        ST_BIT_READ: begin
          if ((decoded.operation == OP_BRSET) || (decoded.operation == OP_BRCLR)) begin
            condition_codes[CCR_C] <= data_i[decoded.bit_index];
            if (data_i[decoded.bit_index] == (decoded.operation == OP_BRSET)) begin
              program_counter <= pc_value(program_counter +
                {{8{branch_displacement[7]}}, branch_displacement});
            end
            finish_to(ST_FETCH);
          end else begin
            if (decoded.operation == OP_BSET) write_data <= data_i | (8'h01 << decoded.bit_index);
            else write_data <= data_i & ~(8'h01 << decoded.bit_index);
            state <= ST_BIT_WRITE;
          end
        end
        ST_BIT_WRITE: finish_to(ST_FETCH);
        ST_PUSH_RETURN_LOW: begin
          stack_pointer <= stack_advance(stack_pointer, 1'b1);
          state <= ST_PUSH_RETURN_HIGH;
        end
        ST_PUSH_RETURN_HIGH: begin
          stack_pointer <= stack_advance(stack_pointer, 1'b1);
          program_counter <= control_target;
          finish_to(ST_FETCH);
        end
        ST_PULL_PC_HIGH: begin
          stack_pointer <= stack_advance(stack_pointer, 1'b0);
          temporary_high <= data_i;
          state <= ST_PULL_PC_LOW;
        end
        ST_PULL_PC_LOW: begin
          stack_pointer <= stack_advance(stack_pointer, 1'b0);
          program_counter <= pc_value({temporary_high, data_i});
          finish_to(ST_FETCH);
        end
        ST_INTERRUPT_PUSH: begin
          stack_pointer <= stack_advance(stack_pointer, 1'b1);
          if (phase == 3'd4) begin
            condition_codes[CCR_I] <= 1'b1;
            state <= ST_INTERRUPT_VECTOR_HIGH;
          end else begin
            phase <= phase + 3'd1;
          end
        end
        ST_INTERRUPT_VECTOR_HIGH: begin
          temporary_high <= data_i;
          state <= ST_INTERRUPT_VECTOR_LOW;
        end
        ST_INTERRUPT_VECTOR_LOW: begin
          program_counter <= pc_value({temporary_high, data_i});
          if (external_interrupt) begin
            external_interrupt <= 1'b0;
            interrupt_ack_o <= 1'b1;
            state <= ST_FETCH;
          end else begin
            finish_to(ST_FETCH);
          end
        end
        ST_RTI_PULL: begin
          stack_pointer <= stack_advance(stack_pointer, 1'b0);
          case (phase)
            3'd0: condition_codes <= data_i[4:0];
            3'd1: accumulator <= data_i;
            3'd2: index_register <= data_i;
            3'd3: temporary_high <= data_i;
            default: program_counter <= pc_value({temporary_high, data_i});
          endcase
          if (phase == 3'd4) finish_to(ST_FETCH);
          else phase <= phase + 3'd1;
        end
        ST_PADDING: begin
          if (cycles_left <= 4'd1) begin
            state <= terminal_state;
            retire_o <= 1'b1;
          end
        end
        ST_WAITING, ST_STOPPED: begin
          if (!irq_n_i) begin
            vector_address <= irq_vector_i;
            external_interrupt <= 1'b1;
            phase <= 3'd0;
            state <= ST_INTERRUPT_PUSH;
          end
        end
        default: ;
      endcase
    end
  end

  assign fetched_decode = HITACHI_PROFILE ? decode_hd6305(data_i) : decode_m6805(data_i);
  assign decoded_sane = decoded.valid && (decoded.mode != AM_NONE) && (decoded.length != 2'd0);
  assign waiting_o = (state == ST_WAITING);
  assign stopped_o = (state == ST_STOPPED);
  assign debug_a_o = accumulator;
  assign debug_x_o = index_register;
  assign debug_sp_o = stack_pointer;
  assign debug_pc_o = program_counter;
  assign debug_ccr_o = condition_codes;
  assign debug_opcode_o = instruction_register;
  assign debug_instruction_cycles_o = decoded_sane ? decoded.cycles : 4'd0;
endmodule
