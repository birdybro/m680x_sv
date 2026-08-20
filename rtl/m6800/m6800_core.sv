// SPDX-License-Identifier: MIT
module m6800_core #(
  parameter logic [1:0] ARCHITECTURE = 2'd0
) (
  input  logic        clk_i,
  input  logic        reset_n_i,
  input  logic        clock_enable_i,
  input  logic        bus_ready_i,
  input  logic        irq_n_i,
  input  logic [15:0] irq_vector_i,
  input  logic        nmi_n_i,
  input  logic        instruction_address_error_i,
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
  output logic        sleeping_o,
  output logic        interrupt_ack_o,
  output logic [1:0]  interrupt_vector_o,
  output logic [7:0]  debug_a_o,
  output logic [7:0]  debug_b_o,
  output logic [15:0] debug_x_o,
  output logic [15:0] debug_sp_o,
  output logic [15:0] debug_pc_o,
  output logic [5:0]  debug_ccr_o,
  output logic [7:0]  debug_opcode_o,
  output logic [3:0]  debug_instruction_cycles_o
);
  import m680x_alu_pkg::*;
  import m680x_decode_pkg::*;

  localparam int CCR_H = 5;
  localparam int CCR_I = 4;
  localparam int CCR_N = 3;
  localparam int CCR_Z = 2;
  localparam int CCR_V = 1;
  localparam int CCR_C = 0;

  typedef enum logic [5:0] {
    ST_RESET_HIGH,
    ST_RESET_LOW,
    ST_FETCH,
    ST_EXECUTE,
    ST_RELATIVE,
    ST_IMMEDIATE_8,
    ST_IMMEDIATE_16_HIGH,
    ST_IMMEDIATE_16_LOW,
    ST_DIRECT,
    ST_INDEXED,
    ST_EXTENDED_HIGH,
    ST_EXTENDED_LOW,
    ST_MEMORY_READ,
    ST_MEMORY_READ_16_HIGH,
    ST_MEMORY_READ_16_LOW,
    ST_MEMORY_WRITE,
    ST_MEMORY_WRITE_16_HIGH,
    ST_MEMORY_WRITE_16_LOW,
    ST_PUSH_RETURN_LOW,
    ST_PUSH_RETURN_HIGH,
    ST_PULL_PC_HIGH,
    ST_PULL_PC_LOW,
    ST_PUSH_BYTE,
    ST_PULL_BYTE,
    ST_PUSH_X_LOW,
    ST_PUSH_X_HIGH,
    ST_PULL_X_HIGH,
    ST_PULL_X_LOW,
    ST_MASK_IMMEDIATE,
    ST_MASK_DIRECT,
    ST_MASK_INDEXED,
    ST_INTERRUPT_DELAY,
    ST_INTERRUPT_PUSH,
    ST_WAIT_RESPONSE,
    ST_INTERRUPT_POST,
    ST_INTERRUPT_VECTOR_HIGH,
    ST_INTERRUPT_VECTOR_LOW,
    ST_RTI_PULL,
    ST_PADDING,
    ST_WAITING,
    ST_SLEEPING,
    ST_ILLEGAL
  } state_t;

  state_t state;
  state_t terminal_state;
  opcode_decode_t decoded;
  logic [7:0] accumulator_a;
  logic [7:0] accumulator_b;
  logic [15:0] index_register;
  logic [15:0] stack_pointer;
  logic [15:0] program_counter;
  logic [5:0] condition_codes;
  logic [7:0] instruction_register;
  logic [3:0] cycles_left;
  logic [15:0] effective_address;
  logic [15:0] control_target;
  logic [15:0] word_value;
  logic [7:0] temporary_high;
  logic [7:0] write_data;
  logic [2:0] phase;
  logic interrupt_is_wait;
  logic external_interrupt;
  logic nmi_previous;
  logic nmi_pending;
  logic [15:0] vector_address;
  logic [7:0] immediate_mask;
  logic [1:0] interrupt_enable_delay;
  logic trap_interrupt;
  logic wait_wake_slow;

  opcode_decode_t fetched_decode;
  logic decoded_sane;

  function automatic logic [7:0] selected_byte(input operation_target_t target);
    case (target)
      TARGET_B: selected_byte = accumulator_b;
      default: selected_byte = accumulator_a;
    endcase
  endfunction

  function automatic logic branch_condition(input operation_t operation);
    logic n;
    logic z;
    logic v;
    logic c;
    begin
      n = condition_codes[CCR_N];
      z = condition_codes[CCR_Z];
      v = condition_codes[CCR_V];
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
        OP_BVC: branch_condition = !v;
        OP_BVS: branch_condition = v;
        OP_BPL: branch_condition = !n;
        OP_BMI: branch_condition = n;
        OP_BGE: branch_condition = (n == v);
        OP_BLT: branch_condition = (n != v);
        OP_BGT: branch_condition = !z && (n == v);
        OP_BLE: branch_condition = z || (n != v);
        default: branch_condition = 1'b0;
      endcase
    end
  endfunction

  function automatic logic nmi_requested();
    nmi_requested = nmi_pending || (nmi_previous && !nmi_n_i);
  endfunction

  function automatic logic [1:0] mask_clear_delay();
    case (ARCHITECTURE)
      2'd1: mask_clear_delay = 2'd1;
      2'd2: mask_clear_delay = 2'd2;
      default: mask_clear_delay = 2'd0;
    endcase
  endfunction

  function automatic logic is_word_read(input operation_t operation);
    case (operation)
      OP_CPX, OP_LDS, OP_LDX, OP_LDD, OP_ADDD, OP_SUBD: is_word_read = 1'b1;
      default: is_word_read = 1'b0;
    endcase
  endfunction

  function automatic logic is_word_store(input operation_t operation);
    case (operation)
      OP_STS, OP_STX, OP_STD: is_word_store = 1'b1;
      default: is_word_store = 1'b0;
    endcase
  endfunction

  function automatic logic is_read_modify_write(input operation_t operation);
    case (operation)
      OP_NEG, OP_COM, OP_LSR, OP_ROR, OP_ASR, OP_ASL, OP_ROL,
      OP_DEC, OP_INC, OP_TST, OP_CLR: is_read_modify_write = 1'b1;
      default: is_read_modify_write = 1'b0;
    endcase
  endfunction

  function automatic logic is_mask_operation(input operation_t operation);
    case (operation)
      OP_AIM, OP_OIM, OP_EIM, OP_TIM: is_mask_operation = 1'b1;
      default: is_mask_operation = 1'b0;
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

  task automatic set_selected_byte(
    input operation_target_t target,
    input logic [7:0] value
  );
    begin
      if (target == TARGET_B) begin
        accumulator_b <= value;
      end else begin
        accumulator_a <= value;
      end
    end
  endtask

  task automatic set_nzv8(input logic [7:0] value);
    begin
      condition_codes[CCR_N] <= value[7];
      condition_codes[CCR_Z] <= (value == 8'h00);
      condition_codes[CCR_V] <= 1'b0;
    end
  endtask

  task automatic apply_hnzvc8(
    input logic h,
    input logic n,
    input logic z,
    input logic v,
    input logic c
  );
    begin
      condition_codes[CCR_H] <= h;
      condition_codes[CCR_N] <= n;
      condition_codes[CCR_Z] <= z;
      condition_codes[CCR_V] <= v;
      condition_codes[CCR_C] <= c;
    end
  endtask

  task automatic apply_nzvc8(
    input logic n,
    input logic z,
    input logic v,
    input logic c
  );
    begin
      condition_codes[CCR_N] <= n;
      condition_codes[CCR_Z] <= z;
      condition_codes[CCR_V] <= v;
      condition_codes[CCR_C] <= c;
    end
  endtask

  task automatic apply_nzv8_result(input logic n, input logic z, input logic v);
    begin
      condition_codes[CCR_N] <= n;
      condition_codes[CCR_Z] <= z;
      condition_codes[CCR_V] <= v;
    end
  endtask

  task automatic route_effective_address(input logic [15:0] address_value);
    logic [15:0] store_value;
    begin
      effective_address <= address_value;
      if (decoded.operation == OP_JMP) begin
        program_counter <= address_value;
        finish_to(ST_FETCH);
      end else if (decoded.operation == OP_JSR) begin
        control_target <= address_value;
        state <= ST_PUSH_RETURN_LOW;
      end else if (decoded.operation == OP_STA) begin
        write_data <= selected_byte(decoded.target);
        set_nzv8(selected_byte(decoded.target));
        state <= ST_MEMORY_WRITE;
      end else if (is_word_store(decoded.operation)) begin
        case (decoded.operation)
          OP_STX: store_value = index_register;
          OP_STS: store_value = stack_pointer;
          default: store_value = {accumulator_a, accumulator_b};
        endcase
        word_value <= store_value;
        condition_codes[CCR_N] <= store_value[15];
        condition_codes[CCR_Z] <= (store_value == 16'h0000);
        condition_codes[CCR_V] <= 1'b0;
        state <= ST_MEMORY_WRITE_16_HIGH;
      end else if (decoded.operation == OP_CLR) begin
        write_data <= 8'h00;
        condition_codes[CCR_N] <= 1'b0;
        condition_codes[CCR_Z] <= 1'b1;
        condition_codes[CCR_V] <= 1'b0;
        condition_codes[CCR_C] <= 1'b0;
        state <= ST_MEMORY_WRITE;
      end else if (is_word_read(decoded.operation)) begin
        state <= ST_MEMORY_READ_16_HIGH;
      end else begin
        state <= ST_MEMORY_READ;
      end
    end
  endtask

  task automatic execute_byte(
    input logic [7:0] operand,
    input logic       memory_destination
  );
    logic [7:0] left;
    alu8_result_t result_value;
    begin
      left = selected_byte(decoded.target);
      result_value = '0;
      case (decoded.operation)
        OP_AIM, OP_OIM, OP_EIM, OP_TIM: begin
          case (decoded.operation)
            OP_AIM, OP_TIM: result_value = logic8(operand, immediate_mask, 2'd0);
            OP_OIM: result_value = logic8(operand, immediate_mask, 2'd1);
            default: result_value = logic8(operand, immediate_mask, 2'd2);
          endcase
          set_nzv8(result_value.value);
          if (decoded.operation == OP_TIM) begin
            finish_to(ST_FETCH);
          end else begin
            write_data <= result_value.value;
            state <= ST_MEMORY_WRITE;
          end
        end
        OP_ADD, OP_ADC: begin
          result_value = add8(left, operand,
            (decoded.operation == OP_ADC) ? condition_codes[CCR_C] : 1'b0);
          set_selected_byte(decoded.target, result_value.value);
          apply_hnzvc8(result_value.h, result_value.n, result_value.z,
            result_value.v, result_value.c);
          finish_to(ST_FETCH);
        end
        OP_SUB, OP_SBC, OP_CMP: begin
          result_value = sub8(left, operand,
            (decoded.operation == OP_SBC) ? condition_codes[CCR_C] : 1'b0);
          if (decoded.operation != OP_CMP) begin
            set_selected_byte(decoded.target, result_value.value);
          end
          apply_nzvc8(result_value.n, result_value.z, result_value.v, result_value.c);
          finish_to(ST_FETCH);
        end
        OP_AND, OP_BIT: begin
          result_value = logic8(left, operand, 2'd0);
          if (decoded.operation == OP_AND) begin
            set_selected_byte(decoded.target, result_value.value);
          end
          set_nzv8(result_value.value);
          finish_to(ST_FETCH);
        end
        OP_EOR: begin
          result_value = logic8(left, operand, 2'd2);
          set_selected_byte(decoded.target, result_value.value);
          set_nzv8(result_value.value);
          finish_to(ST_FETCH);
        end
        OP_ORA: begin
          result_value = logic8(left, operand, 2'd1);
          set_selected_byte(decoded.target, result_value.value);
          set_nzv8(result_value.value);
          finish_to(ST_FETCH);
        end
        OP_LDA: begin
          set_selected_byte(decoded.target, operand);
          set_nzv8(operand);
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
      if (is_read_modify_write(decoded.operation)) begin
        if ((decoded.operation == OP_INC) || (decoded.operation == OP_DEC)) begin
          apply_nzv8_result(result_value.n, result_value.z, result_value.v);
        end else begin
          apply_nzvc8(result_value.n, result_value.z, result_value.v, result_value.c);
        end
        if (decoded.operation == OP_TST) begin
          finish_to(ST_FETCH);
        end else if (memory_destination) begin
          write_data <= result_value.value;
          state <= ST_MEMORY_WRITE;
        end else begin
          set_selected_byte(decoded.target, result_value.value);
          finish_to(ST_FETCH);
        end
      end
    end
  endtask

  task automatic execute_word(input logic [15:0] operand);
    logic [15:0] result_value;
    alu16_result_t word_result;
    begin
      result_value = 16'h0000;
      word_result = '0;
      case (decoded.operation)
        OP_CPX: begin
          result_value = index_register - operand;
          condition_codes[CCR_N] <= result_value[15];
          condition_codes[CCR_Z] <= (result_value == 16'h0000);
          condition_codes[CCR_V] <=
            (index_register[15] ^ operand[15]) & (index_register[15] ^ result_value[15]);
          if (ARCHITECTURE != 2'd0) condition_codes[CCR_C] <= (index_register < operand);
        end
        OP_LDX: begin
          index_register <= operand;
          condition_codes[CCR_N] <= operand[15];
          condition_codes[CCR_Z] <= (operand == 16'h0000);
          condition_codes[CCR_V] <= 1'b0;
        end
        OP_LDS: begin
          stack_pointer <= operand;
          condition_codes[CCR_N] <= operand[15];
          condition_codes[CCR_Z] <= (operand == 16'h0000);
          condition_codes[CCR_V] <= 1'b0;
        end
        OP_LDD: begin
          accumulator_a <= operand[15:8];
          accumulator_b <= operand[7:0];
          condition_codes[CCR_N] <= operand[15];
          condition_codes[CCR_Z] <= (operand == 16'h0000);
          condition_codes[CCR_V] <= 1'b0;
        end
        OP_ADDD, OP_SUBD: begin
          if (decoded.operation == OP_ADDD) begin
            word_result = add16({accumulator_a, accumulator_b}, operand);
          end else begin
            word_result = sub16({accumulator_a, accumulator_b}, operand);
          end
          accumulator_a <= word_result.value[15:8];
          accumulator_b <= word_result.value[7:0];
          condition_codes[CCR_N] <= word_result.n;
          condition_codes[CCR_Z] <= word_result.z;
          condition_codes[CCR_V] <= word_result.v;
          condition_codes[CCR_C] <= word_result.c;
        end
        default: begin
          illegal_o <= 1'b1;
          state <= ST_ILLEGAL;
        end
      endcase
      finish_to(ST_FETCH);
    end
  endtask

  task automatic execute_inherent();
    alu8_result_t result_value;
    // The shared DAA result exposes adjustment for exhaustive verification;
    // architectural execution consumes only the adjusted value and flags.
    /* verilator lint_off UNUSEDSIGNAL */
    daa_result_t decimal_value;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [15:0] inherent_word;
    begin
      result_value = '0;
      decimal_value = '0;
      inherent_word = 16'h0000;
      case (decoded.operation)
        OP_NOP: finish_to(ST_FETCH);
        OP_TAP: begin
          condition_codes <= accumulator_a[5:0];
          interrupt_enable_delay <= accumulator_a[CCR_I] ? 2'd0 : mask_clear_delay();
          finish_to(ST_FETCH);
        end
        OP_TPA: begin
          accumulator_a <= {2'b11, condition_codes};
          finish_to(ST_FETCH);
        end
        OP_INX, OP_DEX: begin
          index_register <= index_register + ((decoded.operation == OP_INX) ? 16'h0001 : 16'hffff);
          condition_codes[CCR_Z] <=
            (index_register + ((decoded.operation == OP_INX) ? 16'h0001 : 16'hffff)) == 16'h0000;
          finish_to(ST_FETCH);
        end
        OP_CLV, OP_SEV: begin
          condition_codes[CCR_V] <= (decoded.operation == OP_SEV);
          finish_to(ST_FETCH);
        end
        OP_CLC, OP_SEC: begin
          condition_codes[CCR_C] <= (decoded.operation == OP_SEC);
          finish_to(ST_FETCH);
        end
        OP_CLI, OP_SEI: begin
          condition_codes[CCR_I] <= (decoded.operation == OP_SEI);
          interrupt_enable_delay <=
            (decoded.operation == OP_SEI) ? 2'd0 : mask_clear_delay();
          finish_to(ST_FETCH);
        end
        OP_SBA, OP_CBA: begin
          result_value = sub8(accumulator_a, accumulator_b, 1'b0);
          if (decoded.operation == OP_SBA) accumulator_a <= result_value.value;
          apply_nzvc8(result_value.n, result_value.z, result_value.v, result_value.c);
          finish_to(ST_FETCH);
        end
        OP_TAB, OP_TBA: begin
          if (decoded.operation == OP_TAB) begin
            accumulator_b <= accumulator_a;
            set_nzv8(accumulator_a);
          end else begin
            accumulator_a <= accumulator_b;
            set_nzv8(accumulator_b);
          end
          finish_to(ST_FETCH);
        end
        OP_DAA: begin
          decimal_value = daa8(accumulator_a, condition_codes[CCR_H], condition_codes[CCR_C]);
          if (decimal_value.defined_state) begin
            accumulator_a <= decimal_value.value;
            condition_codes[CCR_N] <= decimal_value.n;
            condition_codes[CCR_Z] <= decimal_value.z;
            condition_codes[CCR_C] <= decimal_value.c;
          end else begin
            undefined_o <= 1'b1;
          end
          finish_to(ST_FETCH);
        end
        OP_ABA: begin
          result_value = add8(accumulator_a, accumulator_b, 1'b0);
          accumulator_a <= result_value.value;
          apply_hnzvc8(result_value.h, result_value.n, result_value.z,
            result_value.v, result_value.c);
          finish_to(ST_FETCH);
        end
        OP_LSRD, OP_ASLD: begin
          if (decoded.operation == OP_LSRD) begin
            inherent_word = {accumulator_a, accumulator_b} >> 1;
            condition_codes[CCR_N] <= 1'b0;
            condition_codes[CCR_C] <= accumulator_b[0];
            condition_codes[CCR_V] <= accumulator_b[0];
          end else begin
            inherent_word = {accumulator_a, accumulator_b} << 1;
            condition_codes[CCR_N] <= accumulator_a[6];
            condition_codes[CCR_C] <= accumulator_a[7];
            condition_codes[CCR_V] <= accumulator_a[6] ^ accumulator_a[7];
          end
          accumulator_a <= inherent_word[15:8];
          accumulator_b <= inherent_word[7:0];
          condition_codes[CCR_Z] <= (inherent_word == 16'h0000);
          finish_to(ST_FETCH);
        end
        OP_ABX: begin
          index_register <= index_register + {8'h00, accumulator_b};
          finish_to(ST_FETCH);
        end
        OP_MUL: begin
          inherent_word = mul8(accumulator_a, accumulator_b);
          accumulator_a <= inherent_word[15:8];
          accumulator_b <= inherent_word[7:0];
          condition_codes[CCR_C] <= inherent_word[7];
          finish_to(ST_FETCH);
        end
        OP_XGDX: begin
          inherent_word = {accumulator_a, accumulator_b};
          accumulator_a <= index_register[15:8];
          accumulator_b <= index_register[7:0];
          index_register <= inherent_word;
          finish_to(ST_FETCH);
        end
        OP_SLP: finish_to(ST_SLEEPING);
        OP_TSX: begin
          index_register <= stack_pointer + 16'h0001;
          finish_to(ST_FETCH);
        end
        OP_INS, OP_DES: begin
          stack_pointer <= stack_pointer + ((decoded.operation == OP_INS) ? 16'h0001 : 16'hffff);
          finish_to(ST_FETCH);
        end
        OP_TXS: begin
          stack_pointer <= index_register - 16'h0001;
          finish_to(ST_FETCH);
        end
        OP_PSHA, OP_PSHB: begin
          write_data <= (decoded.operation == OP_PSHA) ? accumulator_a : accumulator_b;
          state <= ST_PUSH_BYTE;
        end
        OP_PULA, OP_PULB: begin
          state <= ST_PULL_BYTE;
        end
        OP_PSHX: state <= ST_PUSH_X_LOW;
        OP_PULX: state <= ST_PULL_X_HIGH;
        OP_RTS: state <= ST_PULL_PC_HIGH;
        OP_RTI: begin
          phase <= 3'd0;
          state <= ST_RTI_PULL;
        end
        OP_WAI, OP_SWI: begin
          phase <= 3'd0;
          interrupt_is_wait <= (decoded.operation == OP_WAI);
          external_interrupt <= 1'b0;
          vector_address <= 16'hfffa;
          state <= ST_INTERRUPT_PUSH;
        end
        default: begin
          if (is_read_modify_write(decoded.operation)) begin
            execute_byte(selected_byte(decoded.target), 1'b0);
          end else begin
            illegal_o <= 1'b1;
            state <= ST_ILLEGAL;
          end
        end
      endcase
    end
  endtask

  task automatic execute_single_cycle(
    input operation_t single_operation,
    input operation_target_t single_target
  );
    alu8_result_t byte_result;
    logic [7:0] selected;
    logic [15:0] double_value;
    begin
      byte_result = '0;
      selected = selected_byte(single_target);
      double_value = {accumulator_a, accumulator_b};
      case (single_operation)
        OP_NOP: ;
        OP_TAP: begin
          condition_codes <= accumulator_a[5:0];
          interrupt_enable_delay <= accumulator_a[CCR_I] ? 2'd0 : mask_clear_delay();
        end
        OP_TPA: accumulator_a <= {2'b11, condition_codes};
        OP_INX, OP_DEX: begin
          index_register <= index_register +
            ((single_operation == OP_INX) ? 16'h0001 : 16'hffff);
          condition_codes[CCR_Z] <=
            (index_register + ((single_operation == OP_INX) ? 16'h0001 : 16'hffff)) == 16'h0000;
        end
        OP_CLV, OP_SEV: condition_codes[CCR_V] <= (single_operation == OP_SEV);
        OP_CLC, OP_SEC: condition_codes[CCR_C] <= (single_operation == OP_SEC);
        OP_CLI, OP_SEI: begin
          condition_codes[CCR_I] <= (single_operation == OP_SEI);
          interrupt_enable_delay <=
            (single_operation == OP_SEI) ? 2'd0 : mask_clear_delay();
        end
        OP_SBA, OP_CBA: begin
          byte_result = sub8(accumulator_a, accumulator_b, 1'b0);
          if (single_operation == OP_SBA) accumulator_a <= byte_result.value;
          apply_nzvc8(byte_result.n, byte_result.z, byte_result.v, byte_result.c);
        end
        OP_TAB, OP_TBA: begin
          if (single_operation == OP_TAB) accumulator_b <= accumulator_a;
          else accumulator_a <= accumulator_b;
          set_nzv8((single_operation == OP_TAB) ? accumulator_a : accumulator_b);
        end
        OP_ABA: begin
          byte_result = add8(accumulator_a, accumulator_b, 1'b0);
          accumulator_a <= byte_result.value;
          apply_hnzvc8(byte_result.h, byte_result.n, byte_result.z,
            byte_result.v, byte_result.c);
        end
        OP_TSX: index_register <= stack_pointer + 16'h0001;
        OP_INS, OP_DES: stack_pointer <= stack_pointer +
          ((single_operation == OP_INS) ? 16'h0001 : 16'hffff);
        OP_TXS: stack_pointer <= index_register - 16'h0001;
        OP_ABX: index_register <= index_register + {8'h00, accumulator_b};
        OP_LSRD: begin
          double_value = {accumulator_a, accumulator_b} >> 1;
          accumulator_a <= double_value[15:8];
          accumulator_b <= double_value[7:0];
          condition_codes[CCR_N] <= 1'b0;
          condition_codes[CCR_Z] <= (double_value == 16'h0000);
          condition_codes[CCR_V] <= accumulator_b[0];
          condition_codes[CCR_C] <= accumulator_b[0];
        end
        OP_ASLD: begin
          double_value = {accumulator_a, accumulator_b} << 1;
          accumulator_a <= double_value[15:8];
          accumulator_b <= double_value[7:0];
          condition_codes[CCR_N] <= double_value[15];
          condition_codes[CCR_Z] <= (double_value == 16'h0000);
          condition_codes[CCR_V] <= double_value[15] ^ accumulator_a[7];
          condition_codes[CCR_C] <= accumulator_a[7];
        end
        OP_NEG: byte_result = neg8(selected);
        OP_COM: byte_result = com8(selected);
        OP_LSR: byte_result = lsr8(selected);
        OP_ROR: byte_result = ror8(selected, condition_codes[CCR_C]);
        OP_ASR: byte_result = asr8(selected);
        OP_ASL: byte_result = asl8(selected);
        OP_ROL: byte_result = rol8(selected, condition_codes[CCR_C]);
        OP_DEC: byte_result = dec8(selected);
        OP_INC: byte_result = inc8(selected);
        OP_TST: byte_result = tst8(selected);
        OP_CLR: byte_result = clr8();
        default: begin
          illegal_o <= 1'b1;
          state <= ST_ILLEGAL;
        end
      endcase
      if (is_read_modify_write(single_operation)) begin
        if ((single_operation == OP_INC) || (single_operation == OP_DEC)) begin
          apply_nzv8_result(byte_result.n, byte_result.z, byte_result.v);
        end else begin
          apply_nzvc8(byte_result.n, byte_result.z, byte_result.v, byte_result.c);
        end
        if (single_operation != OP_TST) begin
          set_selected_byte(single_target, byte_result.value);
        end
      end
      if (single_operation != OP_INVALID) begin
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
      ST_RESET_HIGH: begin
        address_o = 16'hfffe;
        bus_valid_o = 1'b1;
      end
      ST_RESET_LOW: begin
        address_o = 16'hffff;
        bus_valid_o = 1'b1;
      end
      ST_FETCH: begin
        address_o = program_counter;
        bus_valid_o = 1'b1;
        opcode_fetch_o = 1'b1;
      end
      ST_RELATIVE, ST_IMMEDIATE_8, ST_IMMEDIATE_16_HIGH,
      ST_IMMEDIATE_16_LOW, ST_DIRECT, ST_INDEXED,
      ST_EXTENDED_HIGH, ST_EXTENDED_LOW, ST_MASK_IMMEDIATE,
      ST_MASK_DIRECT, ST_MASK_INDEXED: begin
        address_o = program_counter;
        bus_valid_o = 1'b1;
      end
      ST_MEMORY_READ, ST_MEMORY_READ_16_HIGH: begin
        address_o = effective_address;
        bus_valid_o = 1'b1;
      end
      ST_MEMORY_READ_16_LOW: begin
        address_o = effective_address + 16'h0001;
        bus_valid_o = 1'b1;
      end
      ST_MEMORY_WRITE: begin
        address_o = effective_address;
        data_o = write_data;
        write_o = 1'b1;
        bus_valid_o = 1'b1;
      end
      ST_MEMORY_WRITE_16_HIGH: begin
        address_o = effective_address;
        data_o = word_value[15:8];
        write_o = 1'b1;
        bus_valid_o = 1'b1;
      end
      ST_MEMORY_WRITE_16_LOW: begin
        address_o = effective_address + 16'h0001;
        data_o = word_value[7:0];
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
      ST_PULL_PC_HIGH, ST_PULL_PC_LOW, ST_PULL_BYTE, ST_RTI_PULL: begin
        address_o = stack_pointer + 16'h0001;
        bus_valid_o = 1'b1;
      end
      ST_PUSH_BYTE: begin
        address_o = stack_pointer;
        data_o = write_data;
        write_o = 1'b1;
        bus_valid_o = 1'b1;
      end
      ST_PUSH_X_LOW: begin
        address_o = stack_pointer;
        data_o = index_register[7:0];
        write_o = 1'b1;
        bus_valid_o = 1'b1;
      end
      ST_PUSH_X_HIGH: begin
        address_o = stack_pointer;
        data_o = index_register[15:8];
        write_o = 1'b1;
        bus_valid_o = 1'b1;
      end
      ST_PULL_X_HIGH, ST_PULL_X_LOW: begin
        address_o = stack_pointer + 16'h0001;
        bus_valid_o = 1'b1;
      end
      ST_INTERRUPT_PUSH: begin
        address_o = stack_pointer;
        write_o = 1'b1;
        bus_valid_o = 1'b1;
        case (phase)
          3'd0: data_o = program_counter[7:0];
          3'd1: data_o = program_counter[15:8];
          3'd2: data_o = index_register[7:0];
          3'd3: data_o = index_register[15:8];
          3'd4: data_o = accumulator_a;
          3'd5: data_o = accumulator_b;
          default: data_o = {2'b11, condition_codes};
        endcase
      end
      ST_INTERRUPT_DELAY: begin
        if (ARCHITECTURE == 2'd2) begin
          address_o = (phase == 3'd0) ? program_counter + 16'h0001 : 16'hffff;
          bus_valid_o = 1'b1;
        end
      end
      ST_WAIT_RESPONSE, ST_INTERRUPT_POST: begin
        // MC6801RM(AD2) figure 5-15 keeps the post-stack SP read visible
        // throughout the WAI interrupt-response cycles preceding the vector.
        if ((ARCHITECTURE == 2'd1) && interrupt_is_wait) begin
          address_o = stack_pointer;
          bus_valid_o = 1'b1;
        end
      end
      ST_INTERRUPT_VECTOR_HIGH: begin
        address_o = vector_address;
        bus_valid_o = 1'b1;
      end
      ST_INTERRUPT_VECTOR_LOW: begin
        address_o = vector_address + 16'h0001;
        bus_valid_o = 1'b1;
      end
      ST_WAITING: begin
        // Motorola MC6801RM(AD2) section 5.4.2 documents repeated reads at
        // the post-stack SP. Hitachi #U07 Q&A III.4.5 instead documents FFFF
        // with read/write strobes inactive. The MC6800 releases its bus and
        // therefore retains the default invalid state here.
        if (ARCHITECTURE == 2'd1) begin
          address_o = stack_pointer;
          bus_valid_o = 1'b1;
        end else if (ARCHITECTURE == 2'd2) begin
          address_o = 16'hffff;
        end
      end
      default: ;
    endcase
  end

  // A plain edge-triggered process is used because the state-update helpers above
  // are tasks. Some strict tools treat task assignments as separate writers under
  // always_ff even though every call originates from this one clocked process.
  always @(posedge clk_i or negedge reset_n_i) begin
    if (!reset_n_i) begin
      state <= ST_RESET_HIGH;
      terminal_state <= ST_FETCH;
      decoded <= '0;
      accumulator_a <= 8'h00;
      accumulator_b <= 8'h00;
      index_register <= 16'h0000;
      stack_pointer <= 16'h0000;
      program_counter <= 16'h0000;
      condition_codes <= 6'b010000;
      instruction_register <= 8'h00;
      cycles_left <= 4'd0;
      effective_address <= 16'h0000;
      control_target <= 16'h0000;
      word_value <= 16'h0000;
      temporary_high <= 8'h00;
      write_data <= 8'h00;
      phase <= 3'd0;
      interrupt_is_wait <= 1'b0;
      external_interrupt <= 1'b0;
      nmi_previous <= 1'b1;
      nmi_pending <= 1'b0;
      vector_address <= 16'hfffa;
      immediate_mask <= 8'h00;
      interrupt_enable_delay <= 2'd0;
      trap_interrupt <= 1'b0;
      wait_wake_slow <= 1'b0;
      retire_o <= 1'b0;
      illegal_o <= 1'b0;
      undefined_o <= 1'b0;
      interrupt_ack_o <= 1'b0;
      interrupt_vector_o <= 2'b00;
    end else if (clock_enable_i && (!bus_valid_o || bus_ready_i)) begin
      retire_o <= 1'b0;
      undefined_o <= 1'b0;
      interrupt_ack_o <= 1'b0;
      nmi_previous <= nmi_n_i;
      if (nmi_previous && !nmi_n_i) nmi_pending <= 1'b1;
      if (interrupt_enable_delay != 2'd0) begin
        interrupt_enable_delay <= interrupt_enable_delay - 2'd1;
      end
      if (state != ST_FETCH && state != ST_RESET_HIGH && state != ST_RESET_LOW &&
          state != ST_WAITING && state != ST_SLEEPING && state != ST_ILLEGAL) begin
        cycles_left <= cycles_left - 4'd1;
      end
      case (state)
        ST_RESET_HIGH: begin
          temporary_high <= data_i;
          state <= ST_RESET_LOW;
        end
        ST_RESET_LOW: begin
          program_counter <= {temporary_high, data_i};
          state <= ST_FETCH;
        end
        ST_FETCH: begin
          if ((ARCHITECTURE == 2'd2) && instruction_address_error_i) begin
            instruction_register <= data_i;
            decoded <= fetched_decode;
            vector_address <= 16'hffee;
            interrupt_vector_o <= 2'b11;
            phase <= 3'd0;
            interrupt_is_wait <= 1'b0;
            external_interrupt <= 1'b1;
            trap_interrupt <= 1'b1;
            state <= ST_INTERRUPT_DELAY;
          end else if (nmi_requested() ||
              (!irq_n_i && !condition_codes[CCR_I] && (interrupt_enable_delay == 2'd0))) begin
            phase <= 3'd0;
            interrupt_is_wait <= 1'b0;
            external_interrupt <= 1'b1;
            trap_interrupt <= 1'b0;
            if (nmi_requested()) begin
              vector_address <= 16'hfffc;
              interrupt_vector_o <= 2'b10;
              nmi_pending <= 1'b0;
            end else begin
              vector_address <= irq_vector_i;
              interrupt_vector_o <= 2'b01;
            end
            state <= ST_INTERRUPT_DELAY;
          end else begin
            instruction_register <= data_i;
            decoded <= fetched_decode;
            if (!fetched_decode.valid) begin
              if (ARCHITECTURE == 2'd2) begin
                vector_address <= 16'hffee;
                interrupt_vector_o <= 2'b11;
                phase <= 3'd0;
                interrupt_is_wait <= 1'b0;
                external_interrupt <= 1'b1;
                trap_interrupt <= 1'b1;
                state <= ST_INTERRUPT_DELAY;
              end else begin
                program_counter <= program_counter + 16'h0001;
                illegal_o <= 1'b1;
                state <= ST_ILLEGAL;
              end
            end else begin
              program_counter <= program_counter + 16'h0001;
              cycles_left <= fetched_decode.cycles - 4'd1;
              if ((ARCHITECTURE == 2'd2) && (fetched_decode.cycles == 4'd1)) begin
                execute_single_cycle(fetched_decode.operation, fetched_decode.target);
              end else if (is_mask_operation(fetched_decode.operation)) begin
                state <= ST_MASK_IMMEDIATE;
              end else begin
                case (fetched_decode.mode)
                  AM_INHERENT, AM_ACCUMULATOR_A, AM_ACCUMULATOR_B: state <= ST_EXECUTE;
                  AM_RELATIVE: state <= ST_RELATIVE;
                  AM_IMMEDIATE_8: state <= ST_IMMEDIATE_8;
                  AM_IMMEDIATE_16: state <= ST_IMMEDIATE_16_HIGH;
                  AM_DIRECT: state <= ST_DIRECT;
                  AM_INDEXED_8: state <= ST_INDEXED;
                  AM_EXTENDED: state <= ST_EXTENDED_HIGH;
                  default: begin
                    illegal_o <= 1'b1;
                    state <= ST_ILLEGAL;
                  end
                endcase
              end
            end
          end
        end
        ST_EXECUTE: execute_inherent();
        ST_RELATIVE: begin
          program_counter <= program_counter + 16'h0001;
          if (decoded.operation == OP_BSR) begin
            control_target <= program_counter + 16'h0001 + {{8{data_i[7]}}, data_i};
            state <= ST_PUSH_RETURN_LOW;
          end else begin
            if (branch_condition(decoded.operation)) begin
              program_counter <= program_counter + 16'h0001 + {{8{data_i[7]}}, data_i};
            end
            finish_to(ST_FETCH);
          end
        end
        ST_IMMEDIATE_8: begin
          program_counter <= program_counter + 16'h0001;
          execute_byte(data_i, 1'b0);
        end
        ST_IMMEDIATE_16_HIGH: begin
          temporary_high <= data_i;
          program_counter <= program_counter + 16'h0001;
          state <= ST_IMMEDIATE_16_LOW;
        end
        ST_IMMEDIATE_16_LOW: begin
          program_counter <= program_counter + 16'h0001;
          execute_word({temporary_high, data_i});
        end
        ST_DIRECT: begin
          program_counter <= program_counter + 16'h0001;
          route_effective_address({8'h00, data_i});
        end
        ST_INDEXED: begin
          program_counter <= program_counter + 16'h0001;
          route_effective_address(index_register + {8'h00, data_i});
        end
        ST_EXTENDED_HIGH: begin
          temporary_high <= data_i;
          program_counter <= program_counter + 16'h0001;
          state <= ST_EXTENDED_LOW;
        end
        ST_EXTENDED_LOW: begin
          program_counter <= program_counter + 16'h0001;
          route_effective_address({temporary_high, data_i});
        end
        ST_MASK_IMMEDIATE: begin
          immediate_mask <= data_i;
          program_counter <= program_counter + 16'h0001;
          if (decoded.mode == AM_DIRECT) begin
            state <= ST_MASK_DIRECT;
          end else begin
            state <= ST_MASK_INDEXED;
          end
        end
        ST_MASK_DIRECT: begin
          program_counter <= program_counter + 16'h0001;
          effective_address <= {8'h00, data_i};
          state <= ST_MEMORY_READ;
        end
        ST_MASK_INDEXED: begin
          program_counter <= program_counter + 16'h0001;
          effective_address <= index_register + {8'h00, data_i};
          state <= ST_MEMORY_READ;
        end
        ST_MEMORY_READ: execute_byte(data_i, 1'b1);
        ST_MEMORY_READ_16_HIGH: begin
          temporary_high <= data_i;
          state <= ST_MEMORY_READ_16_LOW;
        end
        ST_MEMORY_READ_16_LOW: execute_word({temporary_high, data_i});
        ST_MEMORY_WRITE: finish_to(ST_FETCH);
        ST_MEMORY_WRITE_16_HIGH: state <= ST_MEMORY_WRITE_16_LOW;
        ST_MEMORY_WRITE_16_LOW: finish_to(ST_FETCH);
        ST_PUSH_RETURN_LOW: begin
          stack_pointer <= stack_pointer - 16'h0001;
          state <= ST_PUSH_RETURN_HIGH;
        end
        ST_PUSH_RETURN_HIGH: begin
          stack_pointer <= stack_pointer - 16'h0001;
          program_counter <= control_target;
          finish_to(ST_FETCH);
        end
        ST_PULL_PC_HIGH: begin
          stack_pointer <= stack_pointer + 16'h0001;
          temporary_high <= data_i;
          state <= ST_PULL_PC_LOW;
        end
        ST_PULL_PC_LOW: begin
          stack_pointer <= stack_pointer + 16'h0001;
          program_counter <= {temporary_high, data_i};
          finish_to(ST_FETCH);
        end
        ST_PUSH_BYTE: begin
          stack_pointer <= stack_pointer - 16'h0001;
          finish_to(ST_FETCH);
        end
        ST_PULL_BYTE: begin
          stack_pointer <= stack_pointer + 16'h0001;
          if (decoded.operation == OP_PULA) accumulator_a <= data_i;
          else accumulator_b <= data_i;
          finish_to(ST_FETCH);
        end
        ST_PUSH_X_LOW: begin
          stack_pointer <= stack_pointer - 16'h0001;
          state <= ST_PUSH_X_HIGH;
        end
        ST_PUSH_X_HIGH: begin
          stack_pointer <= stack_pointer - 16'h0001;
          finish_to(ST_FETCH);
        end
        ST_PULL_X_HIGH: begin
          stack_pointer <= stack_pointer + 16'h0001;
          temporary_high <= data_i;
          state <= ST_PULL_X_LOW;
        end
        ST_PULL_X_LOW: begin
          stack_pointer <= stack_pointer + 16'h0001;
          index_register <= {temporary_high, data_i};
          finish_to(ST_FETCH);
        end
        ST_INTERRUPT_DELAY: begin
          if (phase == (trap_interrupt ? 3'd2 : 3'd1)) begin
            phase <= 3'd0;
            state <= ST_INTERRUPT_PUSH;
          end else begin
            phase <= phase + 3'd1;
          end
        end
        ST_INTERRUPT_PUSH: begin
          stack_pointer <= stack_pointer - 16'h0001;
          if (phase == 3'd6) begin
            if (interrupt_is_wait) begin
              finish_to(ST_WAITING);
            end else begin
              condition_codes[CCR_I] <= 1'b1;
              if (external_interrupt) begin
                if (trap_interrupt) begin
                  state <= ST_INTERRUPT_VECTOR_HIGH;
                end else begin
                  state <= ST_INTERRUPT_POST;
                end
              end else begin
                state <= ST_INTERRUPT_VECTOR_HIGH;
              end
            end
          end else begin
            phase <= phase + 3'd1;
          end
        end
        ST_WAIT_RESPONSE: begin
          // NMI and IRQ2 need one response cycle before late priority
          // selection; synchronized IRQ1 needs two. Together with the
          // recognition, priority, and vector cycles this produces the
          // documented five/six-E-cycle WAI response.
          if (phase == (wait_wake_slow ? 3'd1 : 3'd0)) begin
            phase <= 3'd0;
            state <= ST_INTERRUPT_POST;
          end else begin
            phase <= phase + 3'd1;
          end
        end
        ST_INTERRUPT_POST: begin
          // MC6801-family devices select the highest-priority maskable vector
          // after stacking, not when entry is first recognized. Resampling here
          // also preserves the documented default-SCI case if IRQ2 identity is
          // removed after its request flip-flop has been set.
          if (interrupt_vector_o == 2'b01) vector_address <= irq_vector_i;
          state <= ST_INTERRUPT_VECTOR_HIGH;
        end
        ST_INTERRUPT_VECTOR_HIGH: begin
          temporary_high <= data_i;
          state <= ST_INTERRUPT_VECTOR_LOW;
        end
        ST_INTERRUPT_VECTOR_LOW: begin
          program_counter <= {temporary_high, data_i};
          if (external_interrupt) begin
            external_interrupt <= 1'b0;
            trap_interrupt <= 1'b0;
            interrupt_is_wait <= 1'b0;
            wait_wake_slow <= 1'b0;
            state <= ST_FETCH;
            interrupt_ack_o <= 1'b1;
          end else begin
            finish_to(ST_FETCH);
          end
        end
        ST_RTI_PULL: begin
          stack_pointer <= stack_pointer + 16'h0001;
          case (phase)
            3'd0: condition_codes <= data_i[5:0];
            3'd1: accumulator_b <= data_i;
            3'd2: accumulator_a <= data_i;
            3'd3: index_register[15:8] <= data_i;
            3'd4: index_register[7:0] <= data_i;
            3'd5: temporary_high <= data_i;
            default: program_counter <= {temporary_high, data_i};
          endcase
          if (phase == 3'd6) finish_to(ST_FETCH);
          else phase <= phase + 3'd1;
        end
        ST_PADDING: begin
          if (cycles_left <= 4'd1) begin
            state <= terminal_state;
            retire_o <= 1'b1;
          end
        end
        ST_WAITING: begin
          if (nmi_requested() || (!irq_n_i && !condition_codes[CCR_I])) begin
            phase <= 3'd0;
            external_interrupt <= 1'b1;
            trap_interrupt <= 1'b0;
            condition_codes[CCR_I] <= 1'b1;
            wait_wake_slow <= (ARCHITECTURE == 2'd1) && !nmi_requested() &&
              (irq_vector_i == 16'hfff8);
            if (nmi_requested()) begin
              vector_address <= 16'hfffc;
              interrupt_vector_o <= 2'b10;
              nmi_pending <= 1'b0;
            end else begin
              vector_address <= irq_vector_i;
              interrupt_vector_o <= 2'b01;
            end
            if (ARCHITECTURE == 2'd1) state <= ST_WAIT_RESPONSE;
            else state <= ST_INTERRUPT_POST;
          end
        end
        ST_SLEEPING: begin
          if (!nmi_requested() && !irq_n_i && condition_codes[CCR_I]) begin
            // HD6301V1 section 2.12: a masked request releases SLP and
            // execution resumes without interrupt entry.
            state <= ST_FETCH;
          end else if (nmi_requested() || !irq_n_i) begin
            phase <= 3'd0;
            interrupt_is_wait <= 1'b0;
            external_interrupt <= 1'b1;
            trap_interrupt <= 1'b0;
            if (nmi_requested()) begin
              vector_address <= 16'hfffc;
              interrupt_vector_o <= 2'b10;
              nmi_pending <= 1'b0;
            end else begin
              vector_address <= irq_vector_i;
              interrupt_vector_o <= 2'b01;
            end
            state <= ST_INTERRUPT_DELAY;
          end
        end
        default: ;
      endcase
    end
  end

  assign fetched_decode = (ARCHITECTURE == 2'd0) ? decode_m6800(data_i) :
    ((ARCHITECTURE == 2'd1) ? decode_m6801(data_i) : decode_hd6301(data_i));
  assign decoded_sane = decoded.valid && (decoded.mode != AM_NONE) &&
    (decoded.length != 2'd0) && (decoded.bit_index == 3'd0);
  assign waiting_o = (state == ST_WAITING);
  assign sleeping_o = (state == ST_SLEEPING);
  assign debug_a_o = accumulator_a;
  assign debug_b_o = accumulator_b;
  assign debug_x_o = index_register;
  assign debug_sp_o = stack_pointer;
  assign debug_pc_o = program_counter;
  assign debug_ccr_o = condition_codes;
  assign debug_opcode_o = instruction_register;
  assign debug_instruction_cycles_o = decoded_sane ? decoded.cycles : 4'd0;
endmodule
