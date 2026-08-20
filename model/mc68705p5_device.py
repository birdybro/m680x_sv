"""Independent cycle model for the MC68705P5 digital MCU boundary.

The model follows Motorola ADI-964-R1 register and memory facts.  It models
one processor cycle at a time and leaves oscillator, high-voltage, and EPROM
charge-storage physics outside the digital boundary.
"""

from __future__ import annotations

from dataclasses import dataclass

from model.common import Memory


VECTOR_BOOTSTRAP = 0x7F6
VECTOR_TIMER = 0x7F8
VECTOR_EXTERNAL = 0x7FA
VECTOR_SWI = 0x7FC
VECTOR_RESET = 0x7FE
EPROM_CONTROL_DEFINED_STATES = frozenset(
    {
        "program",
        "controls_disconnected",
        "latch_address_data",
        "invalid",
        "high_voltage_on_vpp",
        "operating",
    }
)


@dataclass(frozen=True)
class MC68705P5EPROMControlInputs:
    """The three factual columns of Motorola's PCR programming table."""

    vpp_present: bool
    pge: bool
    ple: bool


@dataclass(frozen=True)
class MC68705P5EPROMControl:
    """Digital effects of one PCR/VPP state; ``None`` denotes an invalid row."""

    state: str
    read_enabled: bool | None
    latch_enabled: bool | None
    program_enabled: bool | None


def eprom_control(
    inputs: MC68705P5EPROMControlInputs,
) -> MC68705P5EPROMControl:
    """Project the complete printed-page-17 PCR table without analog physics."""

    if inputs.ple and not inputs.pge:
        return MC68705P5EPROMControl("invalid", None, None, None)
    if not inputs.vpp_present:
        state = "operating" if inputs.ple else "controls_disconnected"
        return MC68705P5EPROMControl(state, True, False, False)
    if inputs.ple:
        return MC68705P5EPROMControl("high_voltage_on_vpp", True, False, False)
    if inputs.pge:
        return MC68705P5EPROMControl("latch_address_data", False, True, False)
    return MC68705P5EPROMControl("program", False, True, True)


@dataclass(frozen=True)
class MC68705P5CycleInputs:
    """Pins and optional CPU transaction for one normalized processor cycle."""

    address: int = 0
    valid: bool = False
    write: bool = False
    data: int = 0
    port_a: int = 0xFF
    port_b: int = 0xFF
    port_c: int = 0x0F
    timer: bool = False
    int_n: bool = True
    interrupt_mask: bool = True
    vpp_present: bool = False
    bootstrap_voltage: bool = False


@dataclass(frozen=True)
class MC68705P5CycleResult:
    """Pre-edge read selection and post-edge peripheral state."""

    read_data: int
    program_address: int
    program_read: bool
    timer_irq: bool
    external_irq: bool
    irq_request: bool
    irq_vector: int
    bootstrap_mode: bool
    eprom_latch_enable: bool
    eprom_program_enable: bool
    state: dict[str, int | bool]


@dataclass
class MC68705P5PeripheralState:
    port_a_latch: int = 0
    port_b_latch: int = 0
    port_c_latch: int = 0
    port_a_ddr: int = 0
    port_b_ddr: int = 0
    port_c_ddr: int = 0
    timer_data: int = 0xFF
    timer_request: bool = False
    timer_mask: bool = True
    timer_external: bool = False
    timer_external_enable: bool = False
    timer_divide: int = 0
    timer_prescaler: int = 0x7F
    timer_previous: bool = False
    int_previous: bool = True
    external_request: bool = False
    pcr_latch_enable: bool = True
    pcr_program_enable: bool = True
    eprom_address_latch: int = 0
    eprom_data_latch: int = 0
    bootstrap_active: bool = False
    reset_vector_phase: int = 0

    def tcr(self, mask_option: int) -> int:
        if mask_option & 0x40:
            return (
                (int(self.timer_request) << 7)
                | (int(self.timer_mask) << 6)
                | 0x3F
            )
        return (
            (int(self.timer_request) << 7)
            | (int(self.timer_mask) << 6)
            | (int(self.timer_external) << 5)
            | (int(self.timer_external_enable) << 4)
            | (self.timer_divide & 0x07)
        )

    def pcr(self, vpp_present: bool) -> int:
        return (
            0xF8
            | (int(not vpp_present) << 2)
            | (int(self.pcr_program_enable) << 1)
            | int(self.pcr_latch_enable)
        )

    def snapshot(self, mask_option: int) -> dict[str, int | bool]:
        return {
            "PORTA": self.port_a_latch,
            "PORTB": self.port_b_latch,
            "PORTC": self.port_c_latch,
            "DDRA": self.port_a_ddr,
            "DDRB": self.port_b_ddr,
            "DDRC": self.port_c_ddr,
            "TDR": self.timer_data,
            "TCR": self.tcr(mask_option),
            "PCR_PLE": self.pcr_latch_enable,
            "PCR_PGE": self.pcr_program_enable,
            "EPROM_ADDRESS": self.eprom_address_latch,
            "EPROM_DATA": self.eprom_data_latch,
            "BOOTSTRAP": self.bootstrap_active,
            "RESET_PHASE": self.reset_vector_phase,
        }


class MC68705P5DeviceModel:
    """Specification-derived MC68705P5 memory and peripheral model."""

    def __init__(
        self,
        *,
        mask_option: int = 0,
        program_memory: Memory | None = None,
    ) -> None:
        if not 0 <= mask_option <= 0xFF:
            raise ValueError("mask option must be eight-bit")
        self.mask_option = mask_option
        self.program_memory = program_memory if program_memory is not None else Memory()
        self.ram = bytearray(112)
        self.state = self._reset_state()

    def _reset_state(self) -> MC68705P5PeripheralState:
        return MC68705P5PeripheralState(
            timer_external=bool(self.mask_option & 0x20),
            timer_external_enable=bool(self.mask_option & 0x10),
            timer_divide=self.mask_option & 0x07,
        )

    def reset(self) -> None:
        """Reset documented registers without changing unspecified RAM."""

        self.state = self._reset_state()

    @staticmethod
    def ram_is_internal(address: int) -> bool:
        return 0x010 <= (address & 0x7FF) <= 0x07F

    @staticmethod
    def eprom_is_programmable(address: int) -> bool:
        address &= 0x7FF
        return (
            0x080 <= address <= 0x784
            or 0x7F8 <= address <= 0x7FF
        )

    @staticmethod
    def bootstrap_rom(address: int) -> bool:
        return 0x785 <= (address & 0x7FF) <= 0x7F7

    @classmethod
    def program_is_internal(cls, address: int) -> bool:
        return cls.eprom_is_programmable(address) or cls.bootstrap_rom(address)

    @classmethod
    def program_storage_address(cls, address: int) -> bool:
        address &= 0x7FF
        return (
            0x080 <= address <= 0x783
            or cls.bootstrap_rom(address)
            or 0x7F8 <= address <= 0x7FF
        )

    def bootstrap_selected(self, inputs: MC68705P5CycleInputs) -> bool:
        if self.state.reset_vector_phase == 0:
            return inputs.bootstrap_voltage and not bool(self.mask_option & 0x08)
        return self.state.bootstrap_active

    def selected_program_address(self, inputs: MC68705P5CycleInputs) -> int:
        address = inputs.address & 0x7FF
        if (
            self.bootstrap_selected(inputs)
            and self.state.reset_vector_phase == 0
            and address == VECTOR_RESET
        ):
            return VECTOR_BOOTSTRAP
        if (
            self.bootstrap_selected(inputs)
            and self.state.reset_vector_phase == 1
            and address == VECTOR_RESET + 1
        ):
            return VECTOR_BOOTSTRAP + 1
        return address

    @staticmethod
    def _port_read(latch: int, ddr: int, pins: int, mask: int = 0xFF) -> int:
        return ((latch & ddr) | (pins & ~ddr) | ~mask) & 0xFF

    def read(self, inputs: MC68705P5CycleInputs) -> int:
        s = self.state
        address = inputs.address & 0x7FF
        selected_address = self.selected_program_address(inputs)
        if address == 0x000:
            return self._port_read(s.port_a_latch, s.port_a_ddr, inputs.port_a)
        if address == 0x001:
            return self._port_read(s.port_b_latch, s.port_b_ddr, inputs.port_b)
        if address == 0x002:
            return self._port_read(s.port_c_latch, s.port_c_ddr, inputs.port_c, 0x0F)
        if address in (0x004, 0x005, 0x006):
            return 0xFF
        if address == 0x008:
            return s.timer_data
        if address == 0x009:
            return s.tcr(self.mask_option)
        if address == 0x00B:
            return s.pcr(inputs.vpp_present)
        if address == 0x784:
            return self.mask_option
        if self.ram_is_internal(address):
            return self.ram[address - 0x10]
        if self.bootstrap_rom(selected_address):
            return self.program_memory[selected_address]
        if self.eprom_is_programmable(selected_address):
            # VPP absent disconnects PCR control from the EPROM read path.
            if not inputs.vpp_present or s.pcr_latch_enable:
                return self.program_memory[selected_address]
        return 0xFF

    def timer_options(self) -> tuple[bool, bool, int]:
        if self.mask_option & 0x40:
            return True, bool(self.mask_option & 0x20), self.mask_option & 0x07
        s = self.state
        return s.timer_external_enable, s.timer_external, s.timer_divide

    @property
    def timer_irq(self) -> bool:
        return self.state.timer_request and not self.state.timer_mask

    @property
    def external_irq(self) -> bool:
        return self.state.external_request

    @property
    def irq_vector(self) -> int:
        return VECTOR_EXTERNAL if self.external_irq else VECTOR_TIMER

    @property
    def irq_request(self) -> bool:
        return self.external_irq or self.timer_irq

    def port_outputs(self) -> tuple[int, int, int, int, int, int]:
        s = self.state
        return (
            s.port_a_latch,
            s.port_a_ddr,
            s.port_b_latch,
            s.port_b_ddr,
            s.port_c_latch,
            s.port_c_ddr,
        )

    def cycle(
        self,
        inputs: MC68705P5CycleInputs = MC68705P5CycleInputs(),
    ) -> MC68705P5CycleResult:
        """Advance one normalized processor cycle."""

        if not 0 <= inputs.data <= 0xFF:
            raise ValueError("cycle write data must be eight-bit")
        address = inputs.address & 0x7FF
        selected_address = self.selected_program_address(inputs)
        read_data = self.read(inputs)
        program_read = (
            inputs.valid
            and not inputs.write
            and self.program_storage_address(selected_address)
            and (
                self.bootstrap_rom(selected_address)
                or not inputs.vpp_present
                or self.state.pcr_latch_enable
            )
        )

        s = self.state
        timer_enable, timer_external, timer_divide = self.timer_options()
        timer_rising = inputs.timer and not s.timer_previous
        if timer_external and timer_enable:
            timer_event = timer_rising
        elif timer_external:
            timer_event = False
        elif timer_enable:
            timer_event = inputs.timer
        else:
            timer_event = True
        prescale_mask = (1 << timer_divide) - 1
        counter_event = timer_event and (s.timer_prescaler & prescale_mask) == prescale_mask

        s.timer_previous = inputs.timer
        s.int_previous, old_int = inputs.int_n, s.int_previous
        if (
            s.reset_vector_phase == 0
            and inputs.valid
            and not inputs.write
            and address == VECTOR_RESET
        ):
            s.bootstrap_active = inputs.bootstrap_voltage and not bool(
                self.mask_option & 0x08
            )
            s.reset_vector_phase = 1
        elif (
            s.reset_vector_phase == 1
            and inputs.valid
            and not inputs.write
            and address == VECTOR_RESET + 1
        ):
            s.reset_vector_phase = 2
        if old_int and not inputs.int_n:
            s.external_request = True
        if inputs.valid and not inputs.write and address == VECTOR_EXTERNAL:
            s.external_request = False

        if timer_event:
            s.timer_prescaler = (s.timer_prescaler + 1) & 0x7F
            if counter_event:
                if s.timer_data == 0x01:
                    s.timer_request = True
                s.timer_data = (s.timer_data - 1) & 0xFF

        if inputs.valid and inputs.write:
            data = inputs.data
            if address == 0x000:
                s.port_a_latch = data
            elif address == 0x001:
                s.port_b_latch = data
            elif address == 0x002:
                s.port_c_latch = data & 0x0F
            elif address == 0x004:
                s.port_a_ddr = data
            elif address == 0x005:
                s.port_b_ddr = data
            elif address == 0x006:
                s.port_c_ddr = data & 0x0F
            elif address == 0x008:
                s.timer_data = data
            elif address == 0x009:
                s.timer_request = bool(data & 0x80)
                s.timer_mask = bool(data & 0x40)
                if not self.mask_option & 0x40:
                    s.timer_external = bool(data & 0x20)
                    s.timer_external_enable = bool(data & 0x10)
                    s.timer_divide = data & 0x07
                    if data & 0x08:
                        s.timer_prescaler = 0x7F
            elif address == 0x00B:
                s.pcr_latch_enable = bool(data & 0x01)
                s.pcr_program_enable = bool(data & 0x02) if not data & 0x01 else True
            elif self.ram_is_internal(address):
                self.ram[address - 0x10] = data
            elif (
                self.eprom_is_programmable(address)
                and inputs.vpp_present
                and not s.pcr_latch_enable
                and s.pcr_program_enable
            ):
                s.eprom_address_latch = address
                s.eprom_data_latch = data

        eprom_latch_enable = inputs.vpp_present and not s.pcr_latch_enable
        eprom_program_enable = (
            eprom_latch_enable and not s.pcr_program_enable
        )
        return MC68705P5CycleResult(
            read_data=read_data,
            program_address=selected_address,
            program_read=program_read,
            timer_irq=self.timer_irq,
            external_irq=self.external_irq,
            irq_request=self.irq_request,
            irq_vector=self.irq_vector,
            bootstrap_mode=self.bootstrap_selected(inputs),
            eprom_latch_enable=eprom_latch_enable,
            eprom_program_enable=eprom_program_enable,
            state=s.snapshot(self.mask_option),
        )
