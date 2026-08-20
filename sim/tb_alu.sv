// SPDX-License-Identifier: MIT
module tb_alu;
  import m680x_alu_pkg::*;

  alu8_result_t result8;
  alu16_result_t result16;
  daa_result_t daa_result;
  integer left;
  integer right;
  integer carry;
  integer value;
  integer total;
  integer signed_left;
  integer signed_right;
  integer signed_result;
  integer boundary_index;
  integer boundary;
  integer half_carry;
  integer high_nibble;
  integer low_nibble;
  integer expected_adjustment;
  logic expected_carry;
  logic expected_defined;
  integer cases;

  function automatic integer boundary_value(input integer index);
    case (index)
      0: boundary_value = 0;
      1: boundary_value = 1;
      2: boundary_value = 127;
      3: boundary_value = 128;
      4: boundary_value = 255;
      5: boundary_value = 256;
      6: boundary_value = 32767;
      7: boundary_value = 32768;
      8: boundary_value = 65534;
      default: boundary_value = 65535;
    endcase
  endfunction

  function automatic integer signed8(input integer operand);
    signed8 = (operand >= 128) ? operand - 256 : operand;
  endfunction

  function automatic integer signed16(input integer operand);
    signed16 = (operand >= 32768) ? operand - 65536 : operand;
  endfunction

  task automatic fail8(input string operation);
    $fatal(1, "%s mismatch left=%02x right=%02x carry=%0d", operation, left, right, carry);
  endtask

  initial begin
    cases = 0;
    for (carry = 0; carry < 2; carry = carry + 1) begin
      for (left = 0; left < 256; left = left + 1) begin
        for (right = 0; right < 256; right = right + 1) begin
          result8 = add8(left[7:0], right[7:0], carry[0]);
          total = left + right + carry;
          value = total & 255;
          signed_result = signed8(left) + signed8(right) + carry;
          if (result8.value != value[7:0] || result8.h != (((left & 15) + (right & 15) + carry) >= 16) ||
              result8.n != (value >= 128) || result8.z != (value == 0) ||
              result8.v != ((signed_result < -128) || (signed_result > 127)) || result8.c != (total >= 256)) begin
            fail8("ADD/ADC");
          end
          result8 = sub8(left[7:0], right[7:0], carry[0]);
          total = left - right - carry;
          value = total & 255;
          signed_result = signed8(left) - signed8(right) - carry;
          if (result8.value != value[7:0] || result8.n != (value >= 128) || result8.z != (value == 0) ||
              result8.v != ((signed_result < -128) || (signed_result > 127)) || result8.c != (total < 0)) begin
            fail8("SUB/SBC");
          end
          result8 = logic8(left[7:0], right[7:0], 2'd0);
          value = left & right;
          if (result8.value != value[7:0] || result8.n != (value >= 128) ||
              result8.z != (value == 0) || result8.v != 1'b0) begin
            fail8("AND");
          end
          result8 = logic8(left[7:0], right[7:0], 2'd1);
          value = left | right;
          if (result8.value != value[7:0] || result8.n != (value >= 128) ||
              result8.z != (value == 0) || result8.v != 1'b0) begin
            fail8("OR");
          end
          result8 = logic8(left[7:0], right[7:0], 2'd2);
          value = left ^ right;
          if (result8.value != value[7:0] || result8.n != (value >= 128) ||
              result8.z != (value == 0) || result8.v != 1'b0) begin
            fail8("XOR");
          end
          total = left * right;
          if (mul8(left[7:0], right[7:0]) != total[15:0]) begin
            fail8("MUL");
          end
          cases = cases + 5;
        end
      end
    end

    for (left = 0; left < 256; left = left + 1) begin
      result8 = neg8(left[7:0]);
      value = (-left) & 255;
      if (result8.value != value[7:0] || result8.n != (value >= 128) || result8.z != (value == 0) ||
          result8.v != (left == 128) || result8.c != (left != 0)) fail8("NEG");
      result8 = com8(left[7:0]);
      value = left ^ 255;
      if (result8.value != value[7:0] || result8.n != (value >= 128) || result8.z != (value == 0) ||
          result8.v != 1'b0 || result8.c != 1'b1) fail8("COM");
      result8 = inc8(left[7:0]);
      value = (left + 1) & 255;
      if (result8.value != value[7:0] || result8.n != (value >= 128) || result8.z != (value == 0) ||
          result8.v != (left == 127)) fail8("INC");
      result8 = dec8(left[7:0]);
      value = (left - 1) & 255;
      if (result8.value != value[7:0] || result8.n != (value >= 128) || result8.z != (value == 0) ||
          result8.v != (left == 128)) fail8("DEC");
      result8 = tst8(left[7:0]);
      if (result8.value != left[7:0] || result8.n != (left >= 128) || result8.z != (left == 0)) fail8("TST");
      result8 = lsr8(left[7:0]);
      value = left >> 1;
      if (result8.value != value[7:0] || result8.n != 1'b0 || result8.z != (value == 0) ||
          result8.v != left[0] || result8.c != left[0]) fail8("LSR");
      result8 = asr8(left[7:0]);
      value = (left >> 1) | (left & 128);
      if (result8.value != value[7:0] || result8.n != (value >= 128) || result8.z != (value == 0) ||
          result8.v != ((value >= 128) ^ left[0]) || result8.c != left[0]) fail8("ASR");
      result8 = asl8(left[7:0]);
      value = (left << 1) & 255;
      if (result8.value != value[7:0] || result8.n != (value >= 128) || result8.z != (value == 0) ||
          result8.v != ((value >= 128) ^ (left >= 128)) || result8.c != (left >= 128)) fail8("ASL");
      for (carry = 0; carry < 2; carry = carry + 1) begin
        result8 = ror8(left[7:0], carry[0]);
        value = (left >> 1) | (carry << 7);
        if (result8.value != value[7:0] || result8.n != (value >= 128) || result8.z != (value == 0) ||
            result8.v != ((value >= 128) ^ left[0]) || result8.c != left[0]) fail8("ROR");
        result8 = rol8(left[7:0], carry[0]);
        value = ((left << 1) | carry) & 255;
        if (result8.value != value[7:0] || result8.n != (value >= 128) || result8.z != (value == 0) ||
            result8.v != ((value >= 128) ^ (left >= 128)) || result8.c != (left >= 128)) fail8("ROL");
        cases = cases + 2;
      end
      cases = cases + 8;
    end

    result8 = clr8();
    if (result8.value != 8'h00 || result8.n != 1'b0 || result8.z != 1'b1 ||
        result8.v != 1'b0 || result8.c != 1'b0) $fatal(1, "CLR mismatch");
    cases = cases + 1;

    for (left = 0; left < 65536; left = left + 1) begin
      for (boundary_index = 0; boundary_index < 10; boundary_index = boundary_index + 1) begin
        boundary = boundary_value(boundary_index);
        result16 = add16(left[15:0], boundary[15:0]);
        total = left + boundary;
        value = total & 65535;
        signed_left = signed16(left);
        signed_right = signed16(boundary);
        signed_result = signed_left + signed_right;
        if (result16.value != value[15:0] || result16.n != (value >= 32768) || result16.z != (value == 0) ||
            result16.v != ((signed_result < -32768) || (signed_result > 32767)) || result16.c != (total >= 65536)) begin
          $fatal(1, "ADD16 mismatch left=%04x right=%04x", left, boundary);
        end
        result16 = sub16(left[15:0], boundary[15:0]);
        total = left - boundary;
        value = total & 65535;
        signed_result = signed_left - signed_right;
        if (result16.value != value[15:0] || result16.n != (value >= 32768) || result16.z != (value == 0) ||
            result16.v != ((signed_result < -32768) || (signed_result > 32767)) || result16.c != (total < 0)) begin
          $fatal(1, "SUB16 mismatch left=%04x right=%04x", left, boundary);
        end
        cases = cases + 2;
      end
    end

    // Independently encode all nine rows of the manufacturer DAA table and
    // classify the complete finite A/H/C input space, including undefined rows.
    for (carry = 0; carry < 2; carry = carry + 1) begin
      for (half_carry = 0; half_carry < 2; half_carry = half_carry + 1) begin
        for (left = 0; left < 256; left = left + 1) begin
          high_nibble = left >> 4;
          low_nibble = left & 15;
          expected_defined = 1'b1;
          expected_adjustment = 0;
          expected_carry = carry[0];
          if ((carry == 0) && (half_carry == 0) &&
              (high_nibble <= 9) && (low_nibble <= 9)) begin
            expected_adjustment = 0;
            expected_carry = 1'b0;
          end else if ((carry == 0) && (half_carry == 0) &&
                       (high_nibble <= 8) && (low_nibble >= 10)) begin
            expected_adjustment = 6;
            expected_carry = 1'b0;
          end else if ((carry == 0) && (half_carry == 1) &&
                       (high_nibble <= 9) && (low_nibble <= 3)) begin
            expected_adjustment = 6;
            expected_carry = 1'b0;
          end else if ((carry == 0) && (half_carry == 0) &&
                       (high_nibble >= 10) && (low_nibble <= 9)) begin
            expected_adjustment = 96;
            expected_carry = 1'b1;
          end else if ((carry == 0) && (half_carry == 0) &&
                       (high_nibble >= 9) && (low_nibble >= 10)) begin
            expected_adjustment = 102;
            expected_carry = 1'b1;
          end else if ((carry == 0) && (half_carry == 1) &&
                       (high_nibble >= 10) && (low_nibble <= 3)) begin
            expected_adjustment = 102;
            expected_carry = 1'b1;
          end else if ((carry == 1) && (half_carry == 0) &&
                       (high_nibble <= 2) && (low_nibble <= 9)) begin
            expected_adjustment = 96;
            expected_carry = 1'b1;
          end else if ((carry == 1) && (half_carry == 0) &&
                       (high_nibble <= 2) && (low_nibble >= 10)) begin
            expected_adjustment = 102;
            expected_carry = 1'b1;
          end else if ((carry == 1) && (half_carry == 1) &&
                       (high_nibble <= 3) && (low_nibble <= 3)) begin
            expected_adjustment = 102;
            expected_carry = 1'b1;
          end else begin
            expected_defined = 1'b0;
          end

          daa_result = daa8(left[7:0], half_carry[0], carry[0]);
          value = (left + expected_adjustment) & 255;
          if (daa_result.defined_state != expected_defined ||
              (expected_defined &&
               (daa_result.value != value[7:0] ||
                daa_result.adjustment != expected_adjustment[7:0] ||
                daa_result.n != (value >= 128) || daa_result.z != (value == 0) ||
                daa_result.c != expected_carry))) begin
            $fatal(1, "DAA mismatch A=%02x H=%0d C=%0d actual=%02x/%02x/%0d/%0d/%0d/%0d expected=%02x/%02x/%0d/%0d/%0d/%0d",
                   left, half_carry, carry, daa_result.value, daa_result.adjustment,
                   daa_result.defined_state, daa_result.n, daa_result.z, daa_result.c,
                   value, expected_adjustment, expected_defined, value >= 128,
                   value == 0, expected_carry);
          end
          cases = cases + 1;
        end
      end
    end

    $display("RTL ALU PASS: %0d finite cases", cases);
    $finish;
  end
endmodule
