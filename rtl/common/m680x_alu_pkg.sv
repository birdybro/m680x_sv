// SPDX-License-Identifier: MIT
// Specification-derived arithmetic shared by the clean-room RTL cores.
package m680x_alu_pkg;
  typedef struct packed {
    logic [7:0] value;
    logic       h;
    logic       n;
    logic       z;
    logic       v;
    logic       c;
  } alu8_result_t;

  typedef struct packed {
    logic [15:0] value;
    logic        n;
    logic        z;
    logic        v;
    logic        c;
  } alu16_result_t;

  typedef struct packed {
    logic [7:0] value;
    logic [7:0] adjustment;
    logic       defined_state;
    logic       n;
    logic       z;
    logic       c;
  } daa_result_t;

  function automatic alu8_result_t add8(
    input logic [7:0] left,
    input logic [7:0] right,
    input logic       carry_in
  );
    logic [8:0] total;
    begin
      total = {1'b0, left} + {1'b0, right} + carry_in;
      add8 = {
        total[7:0],
        ({1'b0, left[3:0]} + {1'b0, right[3:0]} + carry_in) > 5'h0f,
        total[7],
        total[7:0] == 8'h00,
        (~(left[7] ^ right[7])) & (left[7] ^ total[7]),
        total[8]
      };
    end
  endfunction

  function automatic alu8_result_t sub8(
    input logic [7:0] left,
    input logic [7:0] right,
    input logic       borrow_in
  );
    logic [8:0] subtrahend;
    logic [7:0] value;
    begin
      subtrahend = {1'b0, right} + borrow_in;
      value = left - subtrahend[7:0];
      sub8 = {
        value, 1'b0, value[7], value == 8'h00,
        (left[7] ^ right[7]) & (left[7] ^ value[7]),
        {1'b0, left} < subtrahend
      };
    end
  endfunction

  function automatic alu16_result_t add16(
    input logic [15:0] left,
    input logic [15:0] right
  );
    logic [16:0] total;
    begin
      total = {1'b0, left} + {1'b0, right};
      add16 = {
        total[15:0], total[15], total[15:0] == 16'h0000,
        (~(left[15] ^ right[15])) & (left[15] ^ total[15]), total[16]
      };
    end
  endfunction

  function automatic alu16_result_t sub16(
    input logic [15:0] left,
    input logic [15:0] right
  );
    logic [15:0] value;
    begin
      value = left - right;
      sub16 = {
        value, value[15], value == 16'h0000,
        (left[15] ^ right[15]) & (left[15] ^ value[15]), left < right
      };
    end
  endfunction

  function automatic alu8_result_t logic8(
    input logic [7:0] left,
    input logic [7:0] right,
    input logic [1:0] operation
  );
    logic [7:0] value;
    begin
      case (operation)
        2'd0: value = left & right;
        2'd1: value = left | right;
        default: value = left ^ right;
      endcase
      logic8 = {value, 1'b0, value[7], value == 8'h00, 2'b00};
    end
  endfunction

  function automatic alu8_result_t neg8(input logic [7:0] operand);
    logic [7:0] value;
    begin
      value = 8'h00 - operand;
      neg8 = {
        value, 1'b0, value[7], value == 8'h00,
        operand == 8'h80, operand != 8'h00
      };
    end
  endfunction

  function automatic alu8_result_t com8(input logic [7:0] operand);
    logic [7:0] value;
    begin
      value = ~operand;
      com8 = {value, 1'b0, value[7], value == 8'h00, 1'b0, 1'b1};
    end
  endfunction

  function automatic alu8_result_t lsr8(input logic [7:0] operand);
    logic [7:0] value;
    begin
      value = {1'b0, operand[7:1]};
      lsr8 = {value, 2'b00, value == 8'h00, operand[0], operand[0]};
    end
  endfunction

  function automatic alu8_result_t asr8(input logic [7:0] operand);
    logic [7:0] value;
    begin
      value = {operand[7], operand[7:1]};
      asr8 = {
        value, 1'b0, value[7], value == 8'h00,
        value[7] ^ operand[0], operand[0]
      };
    end
  endfunction

  function automatic alu8_result_t asl8(input logic [7:0] operand);
    logic [7:0] value;
    begin
      value = {operand[6:0], 1'b0};
      asl8 = {
        value, 1'b0, value[7], value == 8'h00,
        value[7] ^ operand[7], operand[7]
      };
    end
  endfunction

  function automatic alu8_result_t ror8(
    input logic [7:0] operand,
    input logic       carry_in
  );
    logic [7:0] value;
    begin
      value = {carry_in, operand[7:1]};
      ror8 = {
        value, 1'b0, value[7], value == 8'h00,
        value[7] ^ operand[0], operand[0]
      };
    end
  endfunction

  function automatic alu8_result_t rol8(
    input logic [7:0] operand,
    input logic       carry_in
  );
    logic [7:0] value;
    begin
      value = {operand[6:0], carry_in};
      rol8 = {
        value, 1'b0, value[7], value == 8'h00,
        value[7] ^ operand[7], operand[7]
      };
    end
  endfunction

  function automatic alu8_result_t inc8(input logic [7:0] operand);
    logic [7:0] value;
    begin
      value = operand + 8'h01;
      inc8 = {
        value, 1'b0, value[7], value == 8'h00,
        operand == 8'h7f, 1'b0
      };
    end
  endfunction

  function automatic alu8_result_t dec8(input logic [7:0] operand);
    logic [7:0] value;
    begin
      value = operand - 8'h01;
      dec8 = {
        value, 1'b0, value[7], value == 8'h00,
        operand == 8'h80, 1'b0
      };
    end
  endfunction

  function automatic alu8_result_t tst8(input logic [7:0] operand);
    begin
      tst8 = {operand, 1'b0, operand[7], operand == 8'h00, 2'b00};
    end
  endfunction

  function automatic alu8_result_t clr8();
    begin
      clr8 = {8'h00, 3'b001, 2'b00};
    end
  endfunction

  function automatic logic [15:0] mul8(
    input logic [7:0] left,
    input logic [7:0] right
  );
    begin
      mul8 = left * right;
    end
  endfunction

  function automatic daa_result_t daa8(
    input logic [7:0] accumulator,
    input logic       half_carry,
    input logic       carry
  );
    logic [3:0] high;
    logic [3:0] low;
    logic [7:0] adjustment;
    logic carry_out;
    logic defined_state;
    logic [7:0] value;
    begin
      high = accumulator[7:4];
      low = accumulator[3:0];
      adjustment = 8'h00;
      carry_out = carry;
      defined_state = 1'b1;
      if (!carry && !half_carry && high <= 4'h9 && low <= 4'h9) begin
        adjustment = 8'h00;
        carry_out = 1'b0;
      end else if (!carry && !half_carry && high <= 4'h8 && low >= 4'ha) begin
        adjustment = 8'h06;
        carry_out = 1'b0;
      end else if (!carry && half_carry && high <= 4'h9 && low <= 4'h3) begin
        adjustment = 8'h06;
        carry_out = 1'b0;
      end else if (!carry && !half_carry && high >= 4'ha && low <= 4'h9) begin
        adjustment = 8'h60;
        carry_out = 1'b1;
      end else if (!carry && !half_carry && high >= 4'h9 && low >= 4'ha) begin
        adjustment = 8'h66;
        carry_out = 1'b1;
      end else if (!carry && half_carry && high >= 4'ha && low <= 4'h3) begin
        adjustment = 8'h66;
        carry_out = 1'b1;
      end else if (carry && !half_carry && high <= 4'h2 && low <= 4'h9) begin
        adjustment = 8'h60;
        carry_out = 1'b1;
      end else if (carry && !half_carry && high <= 4'h2 && low >= 4'ha) begin
        adjustment = 8'h66;
        carry_out = 1'b1;
      end else if (carry && half_carry && high <= 4'h3 && low <= 4'h3) begin
        adjustment = 8'h66;
        carry_out = 1'b1;
      end else begin
        defined_state = 1'b0;
      end
      value = accumulator + adjustment;
      daa8 = {
        defined_state ? value : accumulator,
        adjustment,
        defined_state,
        defined_state && value[7],
        defined_state && (value == 8'h00),
        defined_state && carry_out
      };
    end
  endfunction
endpackage
