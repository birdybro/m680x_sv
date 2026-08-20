"""Independent HD6301V1 legal-mode digital device model.

The model extends the documented HD6801-compatible peripheral behavior with
the independently specified Hitachi mode maps, Port 3/4 registers, strobes,
IS3 latch/interrupt, and Mode-7 instruction-address error classification. It
models E-cycle transactions rather than the RTL state machine.
"""

from __future__ import annotations

from model.common import Memory
from model.mc6801_device import (
    INTERNAL_REGISTERS,
    MC6801CycleInputs,
    MC6801CycleResult,
    MC6801DeviceModel,
    VECTOR_IRQ1,
)


MODE7_REGISTERS = INTERNAL_REGISTERS | frozenset(range(0x0004, 0x0008)) | {0x000F}


class HD6301V1DeviceModel(MC6801DeviceModel):
    """Specification-derived model of every legal HD6301V1 mode."""

    def __init__(
        self,
        operating_mode: int = 7,
        *,
        external_memory: Memory | None = None,
        program_memory: Memory | None = None,
    ) -> None:
        if operating_mode not in {0, 1, 2, 4, 5, 6, 7}:
            raise ValueError("HD6301V1 operating mode must be 0, 1, 2, 4, 5, 6, or 7")
        super().__init__(
            operating_mode,
            external_memory=external_memory,
            program_memory=program_memory,
            transfer_framing_error=False,
            sci_biphase_supported=False,
            hitachi_new_modes=True,
            timer_counter_double_write=True,
            timer_overflow_at_zero=True,
        )
        self.instruction_address_trap_low_end = 0x007F

    def register_is_internal(self, address: int) -> bool:
        if self.active_mode == 7:
            return (address & 0xFFFF) in MODE7_REGISTERS
        return super().register_is_internal(address)

    def ram_is_internal(self, address: int) -> bool:
        address &= 0xFFFF
        return (
            self.state.rame
            and self.internal_ram_start
            <= address
            < self.internal_ram_start + len(self.ram)
        )

    def program_is_internal(self, address: int) -> bool:
        return self.active_mode in {0, 5, 6, 7} and (address & 0xFFFF) >= 0xF000

    def instruction_address_error(self, address: int) -> bool:
        address &= 0xFFFF
        return self.active_mode == 7 and (
            address <= self.instruction_address_trap_low_end
            or 0x0100 <= address <= 0xEFFF
        )

    def read_register(
        self,
        address: int,
        *,
        port1: int = 0xFF,
        port2: int = 0x1F,
        port3: int = 0xFF,
        port4: int = 0xFF,
    ) -> int:
        address &= 0xFFFF
        state = self.state
        if self.active_mode != 7:
            return super().read_register(
                address,
                port1=port1,
                port2=port2,
                port3=port3,
                port4=port4,
            )
        if address in {0x0004, 0x0005}:
            return 0xFF
        if address == 0x0006:
            return state.port3_input_latch if state.port3_latch_valid else port3 & 0xFF
        if address == 0x0007:
            return port4 & 0xFF
        if address == 0x000F:
            return int(state.snapshot()["P3CSR"])
        return super().read_register(address, port1=port1, port2=port2)

    @property
    def port3_irq(self) -> bool:
        return bool(
            self.active_mode == 7
            and self.state.port3_is3_flag
            and self.state.port3_is3_enable
        )

    def irq_vector(self, irq1_n: bool = True) -> int:
        if self.port3_irq:
            return VECTOR_IRQ1
        return super().irq_vector(irq1_n)

    def irq_request(self, irq1_n: bool = True) -> bool:
        return self.port3_irq or super().irq_request(irq1_n)

    def port34_outputs(self) -> tuple[int, int, int, int]:
        """Return Port 3 value/OE followed by Port 4 value/OE."""

        state = self.state
        return (
            state.port3_latch,
            state.port3_ddr,
            state.port4_latch,
            state.port4_ddr,
        )

    def cycle(self, inputs: MC6801CycleInputs = MC6801CycleInputs()) -> MC6801CycleResult:
        """Advance one E-cycle and classify the selected Hitachi mode."""

        if self.active_mode != 7:
            return super().cycle(inputs)

        if not 0 <= inputs.data <= 0xFF:
            raise ValueError("cycle write data must be eight-bit")
        address = inputs.address & 0xFFFF
        register_select = inputs.valid and self.register_is_internal(address)
        ram_select = inputs.valid and self.ram_is_internal(address)
        program_select = inputs.valid and self.program_is_internal(address)
        internal_read = register_select and not inputs.write
        internal_write = register_select and inputs.write
        port3_access = register_select and address == 0x0006
        os3_n = not (
            port3_access and (inputs.write == self.state.port3_output_strobe_select)
        )

        if program_select:
            read_data = self.program_memory[address]
        elif ram_select:
            read_data = self.ram[self.ram_index(address)]
        elif register_select:
            read_data = self.read_register(
                address,
                port1=inputs.port1,
                port2=inputs.port2,
                port3=inputs.port3,
                port4=inputs.port4,
            )
        else:
            read_data = 0xFF

        timer_irq_before = self.timer_irq
        sci_irq_before = self.sci_irq
        capture_pin = bool(
            (self.state.port2_latch if self.state.port2_ddr & 1 else inputs.port2) & 1
        )
        self._advance_memory_and_gpio(
            inputs, address, internal_write, ram_select, external_bus=False
        )
        self._advance_port34(inputs, address, internal_read, internal_write)
        self._advance_timer(inputs, address, internal_read, internal_write, capture_pin)
        self._advance_sci(inputs, address, internal_read, internal_write)
        self._advance_interrupt_latches(
            inputs, timer_irq_before=timer_irq_before, sci_irq_before=sci_irq_before
        )

        return MC6801CycleResult(
            read_data=read_data,
            external_bus=False,
            timer_irq=self.timer_irq,
            sci_irq=self.sci_irq,
            irq_request=self.irq_request(inputs.irq1_n),
            irq_vector=self.irq_vector(inputs.irq1_n),
            state=self.state.snapshot(),
            program_bus=bool(program_select and not inputs.write),
            address_error=bool(
                inputs.valid
                and inputs.opcode_fetch
                and self.instruction_address_error(address)
            ),
            os3_n=os3_n,
        )

    def _advance_port34(
        self,
        inputs: MC6801CycleInputs,
        address: int,
        internal_read: bool,
        internal_write: bool,
    ) -> None:
        if self.active_mode != 7:
            super()._advance_port34(inputs, address, internal_read, internal_write)
            return
        state = self.state
        falling_edge = state.is3_sync[1] and not state.is3_sync[0]
        state.is3_sync = [inputs.is3_n, state.is3_sync[0]]

        if internal_write:
            if address == 0x0004:
                state.port3_ddr = inputs.data
            elif address == 0x0005:
                state.port4_ddr = inputs.data
            elif address == 0x0006:
                state.port3_latch = inputs.data
            elif address == 0x0007:
                state.port4_latch = inputs.data
            elif address == 0x000F:
                state.port3_is3_enable = bool(inputs.data & 0x40)
                state.port3_output_strobe_select = bool(inputs.data & 0x10)
                state.port3_latch_enable = bool(inputs.data & 0x08)

        if internal_read and address == 0x000F:
            state.port3_clear_armed = state.port3_is3_flag
        if (internal_read or internal_write) and address == 0x0006:
            if internal_read:
                state.port3_latch_valid = False
            if state.port3_clear_armed:
                state.port3_is3_flag = False
                state.port3_clear_armed = False

        # A new edge wins over a simultaneous ordered flag clear.
        if falling_edge:
            state.port3_is3_flag = True
            if state.port3_latch_enable and not state.port3_latch_valid:
                state.port3_input_latch = inputs.port3 & 0xFF
                state.port3_latch_valid = True


class HD6301V1Mode7Model(HD6301V1DeviceModel):
    """Backward-compatible name for the single-chip Mode-7 profile."""

    def __init__(self, *, program_memory: Memory | None = None) -> None:
        super().__init__(7, program_memory=program_memory)
