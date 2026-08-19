from __future__ import annotations

import unittest

from model.hd6303r_device import HD6303RMode2Model
from model.mc6801_device import MC6801CycleInputs


class HD6303RMode2ModelTests(unittest.TestCase):
    @staticmethod
    def cycle(model: HD6303RMode2Model, **values: int | bool):
        return model.cycle(MC6801CycleInputs(**values))

    @classmethod
    def write(cls, model: HD6303RMode2Model, address: int, data: int) -> None:
        cls.cycle(model, address=address, valid=True, write=True, data=data)

    def test_framing_error_does_not_transfer_misframed_byte(self) -> None:
        model = HD6303RMode2Model()
        model.state.receive_data = 0x3C
        self.write(model, 0x0010, 0x04)
        self.write(model, 0x0011, 0x08)
        levels = [0, *(0xA5 >> bit & 1 for bit in range(8)), 0]
        for level in levels:
            for _ in range(16):
                self.cycle(model, port2=level << 3)
        self.assertTrue(model.state.orfe)
        self.assertFalse(model.state.rdrf)
        self.assertEqual(model.state.receive_data, 0x3C)


if __name__ == "__main__":
    unittest.main()
