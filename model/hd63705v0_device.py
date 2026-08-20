"""Independent cycle model for the HD63705V0 digital MCU boundary.

The model is organized around documented peripheral register transactions and
one normalized E cycle at a time.  It is intentionally separate from the RTL
state machine.  Internal EPROM contents are supplied by ``program_memory``;
analog EPROM programming physics are outside the digital model.
"""

from __future__ import annotations

from dataclasses import dataclass

from model.common import Memory


VECTOR_SCI_TIMER2 = 0x1FF4
VECTOR_WAIT_TIMER = 0x1FF6
VECTOR_TIMER_INT2 = 0x1FF8
VECTOR_INT = 0x1FFA
VECTOR_SWI = 0x1FFC
VECTOR_RESET = 0x1FFE
EPROM_BASE = 0x1000
EPROM_BYTES = 0x1000
EPROM_DEFINED_STATES = frozenset(
    {"read", "output_disable", "program", "verify", "program_verify_disable"}
)


@dataclass(frozen=True)
class HD63705V0EPROMInputs:
    """Digital EPROM-mode pins and integration-owned storage byte."""

    eprom_mode: bool
    read_voltage: bool
    program_voltage: bool
    ce_n: bool
    oe_n: bool
    address: int
    input_data: int
    stored_data: int


@dataclass(frozen=True)
class HD63705V0EPROMCycle:
    """One combinational projection of Hitachi table 2-9."""

    state: str
    storage_address: int
    storage_read: bool
    output_data: int
    data_oe: bool
    program_data: int
    program_request: bool
    mcu_stopped: bool


def eprom_cycle(inputs: HD63705V0EPROMInputs) -> HD63705V0EPROMCycle:
    """Project the five documented EPROM states without analog assumptions."""

    if not 0 <= inputs.address < EPROM_BYTES:
        raise ValueError("EPROM address must be twelve-bit")
    if not 0 <= inputs.input_data <= 0xFF or not 0 <= inputs.stored_data <= 0xFF:
        raise ValueError("EPROM data must be eight-bit")

    if not inputs.eprom_mode:
        state = "mcu"
    elif inputs.program_voltage and not inputs.oe_n:
        # Table 2-9 marks CE as don't-care during verification.
        state = "verify"
    elif inputs.program_voltage and not inputs.ce_n and inputs.oe_n:
        state = "program"
    elif inputs.program_voltage and inputs.ce_n and inputs.oe_n:
        state = "program_verify_disable"
    elif inputs.read_voltage and not inputs.ce_n and not inputs.oe_n:
        state = "read"
    elif inputs.read_voltage and not inputs.ce_n and inputs.oe_n:
        state = "output_disable"
    else:
        state = "undefined_by_documentation"

    storage_read = state in {"read", "verify"}
    return HD63705V0EPROMCycle(
        state=state,
        storage_address=EPROM_BASE | inputs.address,
        storage_read=storage_read,
        output_data=inputs.stored_data,
        data_oe=storage_read,
        program_data=inputs.input_data,
        program_request=state == "program",
        mcu_stopped=inputs.eprom_mode,
    )


@dataclass(frozen=True)
class HD63705V0CycleInputs:
    """Inputs and optional CPU transaction for one normalized E cycle."""

    address: int = 0
    valid: bool = False
    write: bool = False
    data: int = 0
    port_a: int = 0xFF
    port_b: int = 0xFF
    port_c: int = 0xFF
    port_d: int = 0x7F
    timer: bool = False
    int_n: bool = True
    int2_n: bool = True
    interrupt_mask: bool = True
    waiting: bool = False
    stopped: bool = False


@dataclass(frozen=True)
class HD63705V0CycleResult:
    """Pre-edge bus value and post-edge observable peripheral state."""

    read_data: int
    program_bus: bool
    timer_irq: bool
    sci_irq: bool
    int_irq: bool
    int2_irq: bool
    irq_request: bool
    irq_vector: int
    state: dict[str, int | bool]


@dataclass
class HD63705V0PeripheralState:
    port_a_latch: int = 0
    port_b_latch: int = 0
    port_c_latch: int = 0
    port_d_latch: int = 0
    port_a_ddr: int = 0
    port_b_ddr: int = 0
    port_c_ddr: int = 0
    port_d_ddr: int = 0
    timer_data: int = 0xF0
    timer_request: bool = False
    timer_mask: bool = True
    timer_clock: int = 1
    timer_divide: int = 0
    timer_prescaler: int = 0x7F
    timer_previous: bool = False
    int_previous: bool = True
    int_latch: bool = False
    int2_previous: bool = True
    int2_request: bool = False
    int2_mask: bool = True
    int_level_sensitive: bool = False
    scr: int = 0
    sci_request: bool = False
    timer2_request: bool = False
    sci_mask: bool = True
    timer2_mask: bool = True
    sci_data: int = 0
    sci_divider: int = 0
    sci_clock: bool = False
    sci_external_previous: bool = False
    transmit_shift: int = 0
    transmit_bits: int = 0
    transmit_active: bool = False
    transmit_output: bool = False
    receive_shift: int = 0
    receive_bits: int = 0
    receive_armed: bool = False
    stop_initialized: bool = False

    @property
    def tcr(self) -> int:
        return (
            (int(self.timer_request) << 7)
            | (int(self.timer_mask) << 6)
            | ((self.timer_clock & 0x03) << 4)
            | (self.timer_divide & 0x07)
        )

    @property
    def mr(self) -> int:
        return (
            (int(self.int2_request) << 7)
            | (int(self.int2_mask) << 6)
            | (int(self.int_level_sensitive) << 5)
            | 0x1F
        )

    @property
    def ssr(self) -> int:
        # SSR3 is a write-only prescaler-initialize pulse and always reads zero.
        return (
            (int(self.sci_request) << 7)
            | (int(self.timer2_request) << 6)
            | (int(self.sci_mask) << 5)
            | (int(self.timer2_mask) << 4)
            | 0x07
        )

    def snapshot(self) -> dict[str, int | bool]:
        return {
            "PORTA": self.port_a_latch,
            "PORTB": self.port_b_latch,
            "PORTC": self.port_c_latch,
            "PORTD": self.port_d_latch,
            "DDRA": self.port_a_ddr,
            "DDRB": self.port_b_ddr,
            "DDRC": self.port_c_ddr,
            "DDRD": self.port_d_ddr,
            "TDR": self.timer_data,
            "TCR": self.tcr,
            "MR": self.mr,
            "SCR": self.scr,
            "SSR": self.ssr,
            "SDR": self.sci_data,
            "sci_clock": self.sci_clock,
            "sci_tx": self.transmit_output,
            "int_latch": self.int_latch,
            "stop_initialized": self.stop_initialized,
        }


class HD63705V0DeviceModel:
    """Specification-derived HD63705V0 memory and peripheral model."""

    def __init__(self, *, program_memory: Memory | None = None) -> None:
        self.program_memory = program_memory if program_memory is not None else Memory()
        self.ram = bytearray(192)
        self.state = HD63705V0PeripheralState()

    def reset(self) -> None:
        """Reset documented registers while preserving undefined RAM contents."""

        self.state = HD63705V0PeripheralState()

    @staticmethod
    def register_is_internal(address: int) -> bool:
        return 0 <= (address & 0x3FFF) <= 0x12

    @staticmethod
    def ram_is_internal(address: int) -> bool:
        return 0x0040 <= (address & 0x3FFF) <= 0x00FF

    @staticmethod
    def program_is_internal(address: int) -> bool:
        return 0x1000 <= (address & 0x3FFF) <= 0x1FFF

    @staticmethod
    def _port_read(latch: int, ddr: int, pins: int, mask: int = 0xFF) -> int:
        return ((latch & ddr) | (pins & ~ddr) | ~mask) & 0xFF

    def read_register(self, address: int, inputs: HD63705V0CycleInputs) -> int:
        s = self.state
        address &= 0x3FFF
        values = {
            0x00: self._port_read(s.port_a_latch, s.port_a_ddr, inputs.port_a),
            0x01: self._port_read(s.port_b_latch, s.port_b_ddr, inputs.port_b),
            0x02: self._port_read(s.port_c_latch, s.port_c_ddr, inputs.port_c),
            0x03: self._port_read(s.port_d_latch, s.port_d_ddr, inputs.port_d, 0x7F),
            0x04: s.port_a_ddr,
            0x05: s.port_b_ddr,
            0x06: s.port_c_ddr,
            0x07: 0x80 | s.port_d_ddr,
            0x08: s.timer_data,
            0x09: s.tcr,
            0x0A: s.mr,
            0x10: s.scr,
            0x11: s.ssr,
            0x12: s.sci_data,
        }
        return values.get(address, 0xFF) & 0xFF

    @property
    def timer_irq(self) -> bool:
        return self.state.timer_request and not self.state.timer_mask

    @property
    def sci_irq(self) -> bool:
        s = self.state
        return (s.sci_request and not s.sci_mask) or (
            s.timer2_request and not s.timer2_mask
        )

    def int_irq(self, int_n: bool) -> bool:
        s = self.state
        return s.int_latch or (s.int_level_sensitive and not int_n)

    def int2_irq(self) -> bool:
        return self.state.int2_request and not self.state.int2_mask

    def irq_vector(self, inputs: HD63705V0CycleInputs) -> int:
        if self.int_irq(inputs.int_n):
            return VECTOR_INT
        if self.int2_irq():
            return VECTOR_TIMER_INT2
        if self.timer_irq:
            return VECTOR_WAIT_TIMER if inputs.waiting else VECTOR_TIMER_INT2
        return VECTOR_SCI_TIMER2

    def irq_request(self, inputs: HD63705V0CycleInputs) -> bool:
        if inputs.stopped:
            return self.int_irq(inputs.int_n) or self.int2_irq()
        return self.int_irq(inputs.int_n) or self.int2_irq() or self.timer_irq or self.sci_irq

    def port_outputs(self) -> tuple[int, int, int, int, int, int, int, int]:
        """Return value/OE pairs for Ports A through D."""

        s = self.state
        d_value = s.port_d_latch & 0x7F
        d_oe = s.port_d_ddr & 0x7F
        if s.scr & 0x80:
            d_value = (d_value & ~0x08) | (int(s.transmit_output) << 3)
            d_oe |= 0x08
        if s.scr & 0x40:
            d_oe &= ~0x10
        if s.scr & 0x20:
            if s.scr & 0x10:
                d_oe &= ~0x20
            else:
                d_value = (d_value & ~0x20) | (int(s.sci_clock) << 5)
                d_oe |= 0x20
        return (
            s.port_a_latch,
            s.port_a_ddr,
            s.port_b_latch,
            s.port_b_ddr,
            s.port_c_latch,
            s.port_c_ddr,
            d_value,
            d_oe,
        )

    def cycle(self, inputs: HD63705V0CycleInputs = HD63705V0CycleInputs()) -> HD63705V0CycleResult:
        """Advance one normalized E cycle."""

        if not 0 <= inputs.data <= 0xFF:
            raise ValueError("cycle write data must be eight-bit")
        address = inputs.address & 0x3FFF
        register_select = inputs.valid and self.register_is_internal(address)
        ram_select = inputs.valid and self.ram_is_internal(address)
        program_select = inputs.valid and self.program_is_internal(address)
        if register_select:
            read_data = self.read_register(address, inputs)
        elif ram_select:
            read_data = self.ram[address - 0x40]
        elif program_select:
            read_data = self.program_memory[address]
        else:
            read_data = 0xFF

        if inputs.stopped and not self.state.stop_initialized:
            self._enter_stop()
        elif not inputs.stopped:
            self.state.stop_initialized = False

        if not inputs.stopped:
            self._advance_timer(inputs)
            self._advance_sci(inputs)
        else:
            # The stopped peripherals do not count or shift, but recovery
            # starts from the levels then present rather than synthesizing an
            # edge from a pin transition that occurred while clocks were off.
            self.state.timer_previous = inputs.timer
            self.state.sci_external_previous = bool(inputs.port_d & 0x20)
        self._advance_external_interrupts(inputs)

        if ram_select and inputs.write:
            self.ram[address - 0x40] = inputs.data
        if register_select and inputs.write:
            self._write_register(address, inputs.data)
        if register_select and not inputs.write and address == 0x12 and self.state.scr & 0x20:
            self._access_sdr()
        if program_select and inputs.write:
            # MCU-mode EPROM writes have no digital effect.
            pass
        if inputs.valid and not inputs.write and address == VECTOR_INT:
            self.state.int_latch = False

        return HD63705V0CycleResult(
            read_data=read_data,
            program_bus=bool(program_select and not inputs.write),
            timer_irq=self.timer_irq,
            sci_irq=self.sci_irq,
            int_irq=self.int_irq(inputs.int_n),
            int2_irq=self.int2_irq(),
            irq_request=self.irq_request(inputs),
            irq_vector=self.irq_vector(inputs),
            state=self.state.snapshot(),
        )

    def _enter_stop(self) -> None:
        s = self.state
        s.timer_data = 0xF0
        s.timer_request = False
        s.timer_mask = True
        s.sci_request = False
        s.timer2_request = False
        s.sci_mask = True
        s.timer2_mask = True
        s.stop_initialized = True

    def _advance_external_interrupts(self, inputs: HD63705V0CycleInputs) -> None:
        s = self.state
        if s.int_previous and not inputs.int_n:
            s.int_latch = True
        if s.int2_previous and not inputs.int2_n:
            s.int2_request = True
        s.int_previous = inputs.int_n
        s.int2_previous = inputs.int2_n

    def _advance_timer(self, inputs: HD63705V0CycleInputs) -> None:
        s = self.state
        timer_rising = not s.timer_previous and inputs.timer
        s.timer_previous = inputs.timer
        source_event = {
            0: True,
            1: inputs.timer,
            2: False,
            3: timer_rising,
        }[s.timer_clock]
        mask = (1 << s.timer_divide) - 1
        if source_event:
            counter_event = (s.timer_prescaler & mask) == mask
            s.timer_prescaler = (s.timer_prescaler + 1) & 0x7F
            if counter_event:
                if s.timer_data == 1:
                    s.timer_request = True
                s.timer_data = (s.timer_data - 1) & 0xFF

    @staticmethod
    def _sci_interval_mask(rate: int) -> int:
        return (1 << rate) - 1 if rate else 0

    def _advance_sci(self, inputs: HD63705V0CycleInputs) -> None:
        s = self.state
        external_clock = bool(inputs.port_d & 0x20)
        external_rising = not s.sci_external_previous and external_clock
        external_falling = s.sci_external_previous and not external_clock
        s.sci_external_previous = external_clock
        if not s.scr & 0x20:
            return

        interval_mask = self._sci_interval_mask(s.scr & 0x0F)
        toggle = s.sci_divider == interval_mask
        internal_rising = toggle and not s.sci_clock
        internal_falling = toggle and s.sci_clock
        if toggle:
            s.sci_divider = 0
            s.sci_clock = not s.sci_clock
        else:
            s.sci_divider = (s.sci_divider + 1) & 0x7FFF

        if internal_falling:
            s.timer2_request = True
        if s.scr & 0x10:
            rising, falling = external_rising, external_falling
        else:
            rising, falling = internal_rising, internal_falling

        if falling and s.transmit_active and s.scr & 0x80:
            s.transmit_output = bool(s.transmit_shift & 1)
            s.transmit_shift >>= 1
            s.transmit_bits += 1
            if s.transmit_bits == 8:
                s.transmit_active = False
        if rising:
            if s.transmit_bits == 8 and not s.transmit_active:
                s.sci_request = True
                s.transmit_bits = 0
            if s.receive_armed and s.scr & 0x40:
                bit = 1 if inputs.port_d & 0x10 else 0
                s.receive_shift |= bit << s.receive_bits
                s.receive_bits += 1
                if s.receive_bits == 8:
                    s.sci_data = s.receive_shift
                    s.sci_request = True
                    s.receive_shift = 0
                    s.receive_bits = 0

    def _access_sdr(self) -> None:
        s = self.state
        s.sci_request = False
        s.receive_armed = True
        if (s.scr & 0x30) == 0x20:
            s.sci_divider = 0

    def _write_register(self, address: int, data: int) -> None:
        s = self.state
        if address == 0x00:
            s.port_a_latch = data
        elif address == 0x01:
            s.port_b_latch = data
        elif address == 0x02:
            s.port_c_latch = data
        elif address == 0x03:
            s.port_d_latch = data & 0x7F
        elif address == 0x04:
            s.port_a_ddr = data
        elif address == 0x05:
            s.port_b_ddr = data
        elif address == 0x06:
            s.port_c_ddr = data
        elif address == 0x07:
            s.port_d_ddr = data & 0x7F
        elif address == 0x08:
            s.timer_data = data
        elif address == 0x09:
            if not data & 0x80:
                s.timer_request = False
            s.timer_mask = bool(data & 0x40)
            s.timer_clock = (data >> 4) & 0x03
            s.timer_divide = data & 0x07
            if data & 0x08:
                s.timer_prescaler = 0x7F
        elif address == 0x0A:
            if not data & 0x80:
                s.int2_request = False
            s.int2_mask = bool(data & 0x40)
            s.int_level_sensitive = bool(data & 0x20)
        elif address == 0x10:
            s.scr = data
        elif address == 0x11:
            if not data & 0x80:
                s.sci_request = False
            if not data & 0x40:
                s.timer2_request = False
            s.sci_mask = bool(data & 0x20)
            s.timer2_mask = bool(data & 0x10)
            if data & 0x08:
                s.sci_divider = 0
        elif address == 0x12:
            s.sci_data = data
            if s.scr & 0x20:
                self._access_sdr()
                s.transmit_shift = data
                s.transmit_bits = 0
                s.transmit_active = True
