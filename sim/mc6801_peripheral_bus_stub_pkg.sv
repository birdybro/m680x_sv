// SPDX-License-Identifier: MIT
// Shared controls for the verification-only MC6801 peripheral bus source.
package mc6801_peripheral_bus_stub_pkg;
  logic [15:0] stub_address;
  logic [7:0] stub_data;
  logic stub_write;
  logic stub_valid;
  logic stub_opcode_fetch = 1'b0;
  logic stub_interrupt_mask;
  logic stub_sleeping = 1'b0;
  logic stub_waiting = 1'b0;
  logic [15:0] stub_sp = 16'h0000;
endpackage
