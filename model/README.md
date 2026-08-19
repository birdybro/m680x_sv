# Independent executable model

This directory contains the specification-derived Python model. It is written
for obvious architectural behavior and deterministic verification, not by
translation from RTL. The RTL and model will retain separate control
structures so that differential tests can expose mistakes in either one.

`alu.py` is the first completed layer. It reports only the flags an operation
defines, leaving each CPU lineage to preserve unaffected condition-code bits.
The DAA function transcribes the nine manufacturer table rows and explicitly
marks every other input state undefined instead of inventing silicon behavior.

`make test-alu` currently checks 1,839,105 finite ALU cases:

- 131,072 ADD/ADC operand and carry states;
- 131,072 SUB/SBC/CMP operand and borrow states;
- 196,608 AND/OR/XOR operand pairs;
- 65,536 unsigned multiply operand pairs;
- 3,073 unary, shift, rotate, test, and clear states;
- all 1,024 accumulator/H/C input states against the DAA table, additionally
  cross-checked from 20,000 valid packed-BCD additions; and
- 1,310,720 16-bit ADDD/SUBD/CPX cases formed by every left operand and ten
  architectural boundary operands.

The test oracles use signed-range properties, arithmetic identities, and a
separate declarative DAA table rather than calling model helpers to predict
their own results.

`m6800.py` is the instruction-level path for M6800, MC6801/MC6803, and
HD6301/HD6303/HD63701. It has its own register/stack organization and executes
all 647 documented encodings in those three architecture maps. Each step emits
an ordered memory-access trace, the documented total cycle count, effective
address, pre/post architectural state, and any manufacturer-undefined flags.
Directed regressions cover wraparound addressing, call and interrupt stack byte
order, SWI/RTI, WAI interrupt entry without double stacking, masking, reset
vectors, and the Hitachi immediate-memory and exchange extensions.
