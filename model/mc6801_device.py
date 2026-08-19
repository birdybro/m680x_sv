"""Independent cycle model for documented MC6801/MC6803 Mode 2/3 devices.

This model is organized around externally presented E-cycle transactions and
peripheral state, independently of the RTL CPU wrapper.  It implements the
common digital register, RAM, GPIO, timer, SCI, and interrupt behavior defined
for MC6801 and for the functionally identical MC6803 expanded modes.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from model.common import Memory


INTERNAL_REGISTERS = frozenset(
    (*range(0x0000, 0x0004), *range(0x0008, 0x000F), *range(0x0010, 0x0015))
)
VECTOR_IRQ1 = 0xFFF8
VECTOR_INPUT_CAPTURE = 0xFFF6
VECTOR_OUTPUT_COMPARE = 0xFFF4
VECTOR_TIMER_OVERFLOW = 0xFFF2
VECTOR_SCI = 0xFFF0
SCI_DIVISORS = (16, 128, 1024, 4096)


@dataclass(frozen=True)
class MC6801CycleInputs:
    """Digital inputs and optional memory transaction for one E-cycle."""

    address: int = 0
    valid: bool = False
    write: bool = False
    data: int = 0
    port1: int = 0xFF
    port2: int = 0x1F
    port3: int = 0xFF
    port4: int = 0xFF
    is3_n: bool = True
    opcode_fetch: bool = False
    irq1_n: bool = True
    interrupt_mask: bool = True
    standby_power_ok: bool = True


@dataclass(frozen=True)
class MC6801CycleResult:
    """Combinational bus result and post-cycle device snapshot."""

    read_data: int
    external_bus: bool
    timer_irq: bool
    sci_irq: bool
    irq_request: bool
    irq_vector: int
    state: dict[str, int | bool]
    program_bus: bool = False
    address_error: bool = False
    os3_n: bool = True


@dataclass
class MC6801PeripheralState:
    port1_latch: int = 0
    port2_latch: int = 0
    port1_ddr: int = 0
    port2_ddr: int = 0
    port3_latch: int = 0
    port4_latch: int = 0
    port3_ddr: int = 0
    port4_ddr: int = 0
    port3_input_latch: int = 0
    port3_latch_valid: bool = False
    port3_latch_enable: bool = False
    port3_output_strobe_select: bool = False
    port3_is3_enable: bool = False
    port3_is3_flag: bool = False
    port3_clear_armed: bool = False
    is3_sync: list[bool] = field(default_factory=lambda: [True, True])
    rame: bool = True
    standby_power: bool = False
    timer: int = 0
    output_compare: int = 0xFFFF
    input_capture: int = 0
    counter_low_latch: int = 0
    tcsr: int = 0
    output_level: bool = False
    compare_inhibit: bool = False
    capture_inhibit: bool = False
    capture_sync: list[bool] = field(default_factory=lambda: [False, False])
    clear_armed: int = 0
    rmcr: int = 0
    trcsr_control: int = 0
    rdrf: bool = False
    orfe: bool = False
    tdre: bool = True
    receive_data: int = 0
    transmit_data: int = 0
    status_armed: int = 0
    tx_frame: int = 0x3FF
    tx_bits: int = 0
    tx_marks: int = 0
    rx_previous: bool = True
    rx_busy: bool = False
    rx_countdown: int = 0
    rx_bit: int = 0
    rx_shift: int = 0
    wake_marks: int = 0
    irq1_pending: bool = False
    irq2_pending: bool = False

    def snapshot(self) -> dict[str, int | bool]:
        return {
            "port1_latch": self.port1_latch,
            "port2_latch": self.port2_latch,
            "port1_ddr": self.port1_ddr,
            "port2_ddr": self.port2_ddr,
            "port3_latch": self.port3_latch,
            "port4_latch": self.port4_latch,
            "port3_ddr": self.port3_ddr,
            "port4_ddr": self.port4_ddr,
            "P3CSR": (
                (int(self.port3_is3_flag) << 7)
                | (int(self.port3_is3_enable) << 6)
                | 0x20
                | (int(self.port3_output_strobe_select) << 4)
                | (int(self.port3_latch_enable) << 3)
                | 0x07
            ),
            "RAME": self.rame,
            "STBY_PWR": self.standby_power,
            "timer": self.timer,
            "output_compare": self.output_compare,
            "input_capture": self.input_capture,
            "TCSR": self.tcsr,
            "RMCR": self.rmcr,
            "TRCSR": self.trcsr,
            "RDR": self.receive_data,
            "sci_tx": self.sci_tx,
            "irq1_pending": self.irq1_pending,
            "irq2_pending": self.irq2_pending,
        }

    @property
    def trcsr(self) -> int:
        return (
            (int(self.rdrf) << 7)
            | (int(self.orfe) << 6)
            | (int(self.tdre) << 5)
            | self.trcsr_control
        )

    @property
    def sci_tx(self) -> int:
        return (self.tx_frame & 1) if (self.trcsr_control & 0x02 and self.tx_bits) else 1


class MC6801DeviceModel:
    """Specification-derived digital peripheral model for Modes 2 and 3."""

    def __init__(
        self,
        operating_mode: int = 2,
        *,
        external_memory: Memory | None = None,
        transfer_framing_error: bool = True,
    ) -> None:
        if operating_mode not in {2, 3}:
            raise ValueError("MC6801/MC6803 device model supports only Modes 2 and 3")
        self.operating_mode = operating_mode
        self.external_memory = external_memory if external_memory is not None else Memory()
        self.ram = bytearray(128)
        self.state = MC6801PeripheralState()
        self.transfer_framing_error = transfer_framing_error

    def reset(self) -> None:
        """Reset documented digital state without inventing RAM contents."""

        self.state = MC6801PeripheralState()

    def register_is_internal(self, address: int) -> bool:
        return (address & 0xFFFF) in INTERNAL_REGISTERS

    def ram_is_internal(self, address: int) -> bool:
        address &= 0xFFFF
        return self.operating_mode == 2 and self.state.rame and 0x0080 <= address <= 0x00FF

    def read_register(self, address: int, *, port1: int = 0xFF, port2: int = 0x1F) -> int:
        """Return the value driven by an internal register before an E edge."""

        s = self.state
        address &= 0xFFFF
        values = {
            0x0000: 0xFF,
            0x0001: 0xFF,
            0x0002: port1,
            0x0003: (self.operating_mode << 5) | (port2 & 0x1F),
            0x0008: s.tcsr,
            0x0009: s.timer >> 8,
            0x000A: s.counter_low_latch,
            0x000B: s.output_compare >> 8,
            0x000C: s.output_compare & 0xFF,
            0x000D: s.input_capture >> 8,
            0x000E: s.input_capture & 0xFF,
            0x0010: 0xFF,
            0x0011: s.trcsr,
            0x0012: s.receive_data,
            0x0013: 0xFF,
            0x0014: (int(s.standby_power) << 7) | (int(s.rame) << 6),
        }
        return values.get(address, 0xFF) & 0xFF

    @property
    def timer_irq(self) -> bool:
        return bool(
            (self.state.tcsr & 0x90) == 0x90
            or (self.state.tcsr & 0x48) == 0x48
            or (self.state.tcsr & 0x24) == 0x24
        )

    @property
    def sci_irq(self) -> bool:
        s = self.state
        return bool(
            (s.trcsr_control & 0x10 and (s.rdrf or s.orfe))
            or (s.trcsr_control & 0x04 and s.tdre)
        )

    def irq_vector(self, irq1_n: bool = True) -> int:
        s = self.state
        if s.irq1_pending or not irq1_n:
            return VECTOR_IRQ1
        if (s.tcsr & 0x90) == 0x90:
            return VECTOR_INPUT_CAPTURE
        if (s.tcsr & 0x48) == 0x48:
            return VECTOR_OUTPUT_COMPARE
        if (s.tcsr & 0x24) == 0x24:
            return VECTOR_TIMER_OVERFLOW
        return VECTOR_SCI

    def irq_request(self, irq1_n: bool = True) -> bool:
        s = self.state
        return bool(
            s.irq1_pending
            or not irq1_n
            or s.irq2_pending
            or self.timer_irq
            or self.sci_irq
        )

    def port_outputs(self) -> tuple[int, int, int, int]:
        """Return Port 1 value/OE followed by Port 2 value/OE."""

        s = self.state
        port2_value = (s.port2_latch & 0x1D) | (int(s.output_level) << 1)
        port2_oe = s.port2_ddr
        if s.rmcr & 0x08:
            divisor = SCI_DIVISORS[s.rmcr & 0x03]
            port2_oe = (port2_oe & ~0x04) | (0 if s.rmcr & 0x04 else 0x04)
            port2_value = (port2_value & ~0x04) | (
                (1 if s.timer & (divisor >> 1) else 0) << 2
            )
        if s.trcsr_control & 0x08:
            port2_oe &= ~0x08
        if s.trcsr_control & 0x02:
            port2_oe |= 0x10
            port2_value = (port2_value & ~0x10) | (s.sci_tx << 4)
        return s.port1_latch, s.port1_ddr, port2_value & 0x1F, port2_oe & 0x1F

    def cycle(self, inputs: MC6801CycleInputs = MC6801CycleInputs()) -> MC6801CycleResult:
        """Advance one documented E-cycle and return pre-edge read/post-edge state."""

        if not 0 <= inputs.data <= 0xFF:
            raise ValueError("cycle write data must be eight-bit")
        address = inputs.address & 0xFFFF
        register_select = inputs.valid and self.register_is_internal(address)
        ram_select = inputs.valid and self.ram_is_internal(address)
        internal_read = register_select and not inputs.write
        internal_write = register_select and inputs.write
        external_bus = bool(inputs.valid and not register_select and not ram_select)
        if ram_select:
            read_data = self.ram[address & 0x7F]
        elif register_select:
            read_data = self.read_register(address, port1=inputs.port1, port2=inputs.port2)
        else:
            read_data = self.external_memory[address]

        timer_irq_before = self.timer_irq
        sci_irq_before = self.sci_irq
        capture_pin = bool(
            (self.state.port2_latch if self.state.port2_ddr & 1 else inputs.port2) & 1
        )
        self._advance_memory_and_gpio(inputs, address, internal_write, ram_select, external_bus)
        self._advance_timer(inputs, address, internal_read, internal_write, capture_pin)
        self._advance_sci(inputs, address, internal_read, internal_write)
        self._advance_interrupt_latches(
            inputs, timer_irq_before=timer_irq_before, sci_irq_before=sci_irq_before
        )

        return MC6801CycleResult(
            read_data=read_data,
            external_bus=external_bus,
            timer_irq=self.timer_irq,
            sci_irq=self.sci_irq,
            irq_request=self.irq_request(inputs.irq1_n),
            irq_vector=self.irq_vector(inputs.irq1_n),
            state=self.state.snapshot(),
        )

    def _advance_memory_and_gpio(
        self,
        inputs: MC6801CycleInputs,
        address: int,
        internal_write: bool,
        ram_select: bool,
        external_bus: bool,
    ) -> None:
        s = self.state
        data = inputs.data
        if not inputs.standby_power_ok:
            s.standby_power = False
            s.rame = False
        if ram_select and inputs.write:
            self.ram[address & 0x7F] = data
        elif external_bus and inputs.write:
            self.external_memory[address] = data
        if not internal_write:
            return
        if address == 0x0000:
            s.port1_ddr = data
        elif address == 0x0001:
            s.port2_ddr = (s.port2_ddr & 0x1C) | (data & 0x03)
            if not s.rmcr & 0x08:
                s.port2_ddr = (s.port2_ddr & ~0x04) | (data & 0x04)
            if not s.trcsr_control & 0x08:
                s.port2_ddr = (s.port2_ddr & ~0x08) | (data & 0x08)
            if not s.trcsr_control & 0x02:
                s.port2_ddr = (s.port2_ddr & ~0x10) | (data & 0x10)
        elif address == 0x0002:
            s.port1_latch = data
        elif address == 0x0003:
            s.port2_latch = (s.port2_latch & ~0x01) | (data & 0x01)
            if not s.rmcr & 0x08:
                s.port2_latch = (s.port2_latch & ~0x04) | (data & 0x04)
            if not s.trcsr_control & 0x08:
                s.port2_latch = (s.port2_latch & ~0x08) | (data & 0x08)
            if not s.trcsr_control & 0x02:
                s.port2_latch = (s.port2_latch & ~0x10) | (data & 0x10)
        elif address == 0x0010 and data & 0x08:
            s.port2_ddr = (s.port2_ddr & ~0x04) | (0 if data & 0x04 else 0x04)
        elif address == 0x0011:
            if data & 0x08:
                s.port2_ddr &= ~0x08
            if data & 0x02:
                s.port2_ddr |= 0x10
        elif address == 0x0014:
            s.standby_power = bool(data & 0x80 and inputs.standby_power_ok)
            s.rame = bool(data & 0x40)

    def _advance_timer(
        self,
        inputs: MC6801CycleInputs,
        address: int,
        internal_read: bool,
        internal_write: bool,
        capture_pin: bool,
    ) -> None:
        s = self.state
        old_tcsr = s.tcsr
        old_timer = s.timer
        was_capture_inhibited = s.capture_inhibit
        next_timer = (old_timer + 1) & 0xFFFF
        counter_write = internal_write and address == 0x0009
        capture_high_read = internal_read and address == 0x000D
        selected_edge = (
            s.capture_sync == [True, False]
            if old_tcsr & 0x02
            else s.capture_sync == [False, True]
        )
        compare_event = (
            not counter_write and not s.compare_inhibit and next_timer == s.output_compare
        )
        overflow_event = not counter_write and next_timer == 0xFFFF

        s.capture_sync = [capture_pin, s.capture_sync[0]]
        s.compare_inhibit = False
        s.capture_inhibit = False
        s.timer = 0xFFF8 if counter_write else next_timer

        if internal_read and address == 0x0008:
            s.clear_armed = old_tcsr & 0xE0
        if internal_read and address == 0x0009:
            s.counter_low_latch = old_timer & 0xFF
            if s.clear_armed & 0x20:
                s.tcsr &= ~0x20
                s.clear_armed &= ~0x20
        if capture_high_read:
            s.capture_inhibit = True
            if s.clear_armed & 0x80:
                s.tcsr &= ~0x80
                s.clear_armed &= ~0x80
        if internal_write:
            if address == 0x0008:
                s.tcsr = (s.tcsr & 0xE0) | (inputs.data & 0x1F)
            elif address == 0x000B:
                s.output_compare = ((inputs.data & 0xFF) << 8) | (s.output_compare & 0xFF)
                s.compare_inhibit = True
                if s.clear_armed & 0x40:
                    s.tcsr &= ~0x40
                    s.clear_armed &= ~0x40
            elif address == 0x000C:
                s.output_compare = (s.output_compare & 0xFF00) | inputs.data
                if s.clear_armed & 0x40:
                    s.tcsr &= ~0x40
                    s.clear_armed &= ~0x40

        if overflow_event:
            s.tcsr |= 0x20
        if compare_event:
            s.tcsr |= 0x40
            s.output_level = bool(old_tcsr & 1)
        if selected_edge and not capture_high_read and not was_capture_inhibited:
            s.input_capture = next_timer
            s.tcsr |= 0x80

    def _advance_sci(
        self,
        inputs: MC6801CycleInputs,
        address: int,
        internal_read: bool,
        internal_write: bool,
    ) -> None:
        s = self.state
        old_control = s.trcsr_control
        divisor = SCI_DIVISORS[s.rmcr & 0x03]
        bit_tick = ((s.timer & (divisor - 1)) == 0)
        internal_nrz = (s.rmcr >> 2) in {1, 2}
        receive_pin = bool(inputs.port2 & 0x08)

        s.rx_previous, previous_pin = receive_pin, s.rx_previous
        if internal_read and address == 0x0011:
            s.status_armed = (int(s.rdrf or s.orfe) << 1) | int(s.tdre)
        if internal_read and address == 0x0012 and s.status_armed & 0x02:
            s.rdrf = False
            s.orfe = False
            s.status_armed &= ~0x02

        if internal_write:
            if address == 0x0010:
                s.rmcr = inputs.data & 0x0F
            elif address == 0x0011:
                s.trcsr_control = inputs.data & 0x1F
                if not old_control & 0x02 and inputs.data & 0x02:
                    s.tx_marks = 9
                    s.tx_bits = 0
                if not inputs.data & 0x02:
                    s.tx_bits = 0
            elif address == 0x0013:
                s.transmit_data = inputs.data
                if s.status_armed & 0x01:
                    s.tdre = False
                    s.status_armed &= ~0x01

        if bit_tick and old_control & 0x01:
            if receive_pin:
                if s.wake_marks == 9:
                    s.trcsr_control &= ~0x01
                    s.wake_marks = 0
                else:
                    s.wake_marks += 1
            else:
                s.wake_marks = 0

        if bit_tick and internal_nrz and old_control & 0x02:
            if s.tx_marks:
                s.tx_marks -= 1
            elif s.tx_bits:
                if s.tx_bits == 1:
                    if not s.tdre:
                        s.tx_frame = 0x200 | (s.transmit_data << 1)
                        s.tx_bits = 10
                        s.tdre = True
                    else:
                        s.tx_bits = 0
                else:
                    s.tx_frame = 0x200 | (s.tx_frame >> 1)
                    s.tx_bits -= 1
            elif not s.tdre:
                s.tx_frame = 0x200 | (s.transmit_data << 1)
                s.tx_bits = 10
                s.tdre = True

        if not old_control & 0x08 or not internal_nrz or old_control & 0x01:
            s.rx_busy = False
        elif not s.rx_busy:
            if previous_pin and not receive_pin:
                s.rx_busy = True
                s.rx_countdown = divisor // 2
                s.rx_bit = 0
        elif s.rx_countdown > 1:
            s.rx_countdown -= 1
        elif s.rx_bit == 0:
            if receive_pin:
                s.rx_busy = False
            else:
                s.rx_bit = 1
                s.rx_countdown = divisor
        elif s.rx_bit <= 8:
            mask = 1 << (s.rx_bit - 1)
            s.rx_shift = (s.rx_shift | mask) if receive_pin else (s.rx_shift & ~mask)
            s.rx_bit += 1
            s.rx_countdown = divisor
        else:
            s.rx_busy = False
            if not receive_pin:
                if self.transfer_framing_error and not s.rdrf and not s.orfe:
                    s.receive_data = s.rx_shift
                s.orfe = True
                s.rx_busy = True
                s.rx_bit = 1
                s.rx_countdown = divisor
            elif s.rdrf or s.orfe:
                s.orfe = True
            else:
                s.receive_data = s.rx_shift
                s.rdrf = True

    def _advance_interrupt_latches(
        self,
        inputs: MC6801CycleInputs,
        *,
        timer_irq_before: bool,
        sci_irq_before: bool,
    ) -> None:
        s = self.state
        if inputs.interrupt_mask:
            s.irq1_pending = False
            s.irq2_pending = False
        else:
            s.irq1_pending |= not inputs.irq1_n
            s.irq2_pending |= timer_irq_before or sci_irq_before
