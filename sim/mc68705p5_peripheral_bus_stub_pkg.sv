// SPDX-License-Identifier: MIT
// Verification-only CPU transaction source for MC68705P5 peripheral testing.
package mc68705p5_peripheral_bus_stub_pkg;
  logic [15:0] stub_address;
  logic [7:0] stub_data;
  logic stub_write;
  logic stub_valid;
  logic stub_interrupt_mask;
endpackage
