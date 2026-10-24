#!/usr/bin/env python3
"""Run assembled gate code on Unicorn CFV4E; no stock firmware required.

Run build.py --assemble-only first; install unicorn to run this script.
The MMIO model checks command ordering and ownership, not jack voltage,
physical UART timing, DMA arbitration or the complete firmware scheduler.
"""
import os
from pathlib import Path
import shutil
import struct
import subprocess
import unittest

from unicorn import Uc, UC_ARCH_M68K, UC_MODE_BIG_ENDIAN, UC_HOOK_MEM_WRITE
from unicorn.m68k_const import (
    UC_CPU_M68K_CFV4E, UC_M68K_REG_A0, UC_M68K_REG_A7,
    UC_M68K_REG_D0, UC_M68K_REG_D1, UC_M68K_REG_D2,
    UC_M68K_REG_PC, UC_M68K_REG_SR,
)

ROOT = Path(__file__).resolve().parents[1]
CROSS = os.environ.get('CROSS') or next(
    c for c in ('m68k-elf-', 'm68k-linux-gnu-') if shutil.which(c + 'nm'))
SYMS = {}
for line in subprocess.check_output([CROSS + 'nm', ROOT/'build/_b.elf'], text=True).splitlines():
    p = line.split()
    if len(p) == 3:
        SYMS[p[2]] = int(p[0], 16)

UCR, USR = 0xec074008, 0xec074004
PLAYING = 0x40a7883c
STACK, STOP = 0x10f000, 0x100000


class GateTest(unittest.TestCase):
    def setUp(self):
        self.u = Uc(UC_ARCH_M68K, UC_MODE_BIG_ENDIAN)
        self.u.ctl_set_cpu_model(UC_CPU_M68K_CFV4E)
        for addr, size in ((0x40000000, 0x200000), (0x40490000, 0x10000),
                           (0x40a70000, 0x10000), (0x100000, 0x10000),
                           (0xec074000, 0x1000), (0xfc044000, 0x2000),
                           (0xfc04c000, 0x1000)):
            self.u.mem_map(addr, size)
        self.u.mem_write(0x401ab750, (ROOT/'build/_b.bin').read_bytes())
        self.writes = []
        for lo, hi in ((0xec074000, 0xec074fff), (0xfc044000, 0xfc045fff),
                       (0xfc04c000, 0xfc04cfff)):
            self.u.hook_add(UC_HOOK_MEM_WRITE, self.mmio, begin=lo, end=hi)
        self.u.mem_write(USR, b'\x0c')
        self.put(PLAYING, 1)

    def mmio(self, uc, access, addr, size, value, data):
        value &= (1 << (8 * size)) - 1
        self.writes.append((addr, size, value))
        # Pessimistically report TXEMP clear while BREAK is asserted.
        if addr == UCR:
            self.assertEqual(size, 1)
            self.assertIn(value, (4, 0x60, 0x70))
            uc.mem_write(USR, b'\x04' if value == 0x60 else b'\x0c')

    def put(self, name, value):
        self.u.mem_write(SYMS[name] if isinstance(name, str) else name,
                         struct.pack('>I', value & 0xffffffff))

    def get(self, name):
        return int.from_bytes(self.u.mem_read(SYMS[name], 4), 'big')

    def run_code(self, name, *, end=STOP, d0=0, d1=0, a0=0, sr=0x2000):
        self.u.reg_write(UC_M68K_REG_SR, sr)
        self.u.reg_write(UC_M68K_REG_A7, STACK)
        self.put(STACK, STOP)
        self.u.reg_write(UC_M68K_REG_D0, d0)
        self.u.reg_write(UC_M68K_REG_D1, d1)
        self.u.reg_write(UC_M68K_REG_D2, 0x12345678)
        self.u.reg_write(UC_M68K_REG_A0, a0)
        self.u.emu_start(SYMS[name], end, count=1000)
        self.assertEqual(self.u.reg_read(UC_M68K_REG_PC), end)
        self.assertEqual(self.u.reg_read(UC_M68K_REG_D2), 0x12345678)

    def service(self):
        self.run_code('gate_service')
        self.assertEqual(self.u.reg_read(UC_M68K_REG_SR) & 0x2700, 0x2000)
        self.assertEqual(self.u.reg_read(UC_M68K_REG_A7), STACK + 4)

    def activate(self, mode):
        self.put('gate_mode', mode)
        self.service()
        self.assertEqual(self.get('gate_active'), mode)

    def byte(self, value):
        self.run_code('gate_tx_byte', end=0x400012c4, d1=value, sr=0x2700)

    def test_disabled_has_no_mmio_writes(self):
        self.service()
        self.assertEqual(self.writes, [])

    def test_waits_for_every_transmit_busy_condition(self):
        self.put('gate_mode', 3)
        for addr in (0x4049dca0, 0x4049dcbc, 0x4049dccc):
            self.put(addr, 1)
            self.service()
            self.assertEqual(self.get('gate_active'), 0)
            self.put(addr, 0)
        self.u.mem_write(0xfc0454be, b'\x00\x40')
        self.service()
        self.assertEqual(self.get('gate_active'), 0)
        self.u.mem_write(0xfc0454be, b'\x00\x00')
        self.u.mem_write(USR, b'\x04')
        self.service()
        self.assertEqual(self.get('gate_active'), 0)
        self.assertEqual(self.writes, [])
        self.u.mem_write(USR, b'\x0c')
        self.service()
        self.assertEqual(self.writes, [(0xfc044019, 1, 37),
                                      (0xfc04401c, 1, 37),
                                      (0xfc04c01c, 1, 53), (UCR, 1, 4),
                                      (UCR, 1, 0x60)])

    def test_clock_divisions_and_pulse_expiry(self):
        for mode, divisor in enumerate((24, 12, 6, 1), 1):
            self.activate(mode)
            self.byte(0xfa)
            self.assertEqual(self.get('gate_level'), 0)
            for _ in range(8):
                self.service()
            self.assertEqual(self.get('gate_level'), 1)
            for tick in range(1, 50):
                before = len(self.writes)
                self.byte(0xf8)
                self.assertEqual((UCR, 1, 0x70) in self.writes[before:], tick % divisor == 0)
                if tick % divisor == 0:
                    for _ in range(7):
                        self.service()
                        self.assertEqual(self.get('gate_level'), 0)
                    self.service()
                    self.assertEqual(self.get('gate_level'), 1)

    def test_stopped_transport_and_realtime_filter(self):
        self.activate(3)
        for byte in (0x90, 60, 100, 0xfe, 0xf9, 0xfb):
            self.byte(byte)
        self.assertEqual(self.get('gate_count'), 0)
        self.byte(0xf8)
        self.assertEqual(self.get('gate_level'), 0)
        self.byte(0xfc)
        self.assertEqual(self.get('gate_level'), 1)
        self.byte(0xf8)
        self.put(PLAYING, 0)
        self.service()
        self.assertEqual(self.get('gate_level'), 1)
        self.byte(0xf8)
        self.assertEqual(self.get('gate_level'), 1)
        self.put(PLAYING, 1)
        self.byte(0xfa)
        self.assertEqual(self.get('gate_level'), 0)
        for _ in range(8):
            self.service()
        self.byte(0xf8)
        self.assertEqual(self.get('gate_level'), 1)  # no extra first-clock pulse

    def test_start_alignment_at_slow_and_fast_tempos(self):
        # Tick period is 60/(BPM*24), with 1500 audio blocks per second.
        # Simulate sixteenth-note clock at 30/120 BPM. First edge is on FA;
        # subsequent edges stay six F8 apart without a tempo-sized start gap.
        for blocks_per_tick in (125, 31):
            self.activate(0)
            self.activate(3)
            self.byte(0xfa)
            self.assertEqual(self.get('gate_level'), 0)
            for tick in range(1, 19):
                for _ in range(blocks_per_tick):
                    self.service()
                before = len(self.writes)
                self.byte(0xf8)
                self.assertEqual((UCR, 1, 0x70) in self.writes[before:], tick % 6 == 0)

    def test_pending_and_active_modes_drop_midi(self):
        for requested, active in ((3, 0), (3, 3), (0, 3), (5, 3)):
            self.put('gate_mode', requested)
            self.put('gate_active', active)
            self.run_code('gate_tx_buffer', end=0x40001226, d0=3, a0=0x101000, sr=0x2700)
            self.byte(0x90)
        self.assertEqual(self.writes, [])

    def test_stock_producer_replay_when_off(self):
        # Consume flags with a branch: Unicorn exposes lazy flags through
        # branches more reliably than a host read of SR. Return 0 if Z, 1 otherwise.
        branch = bytes.fromhex('670470014e7570004e75')
        self.u.mem_write(0x4000115e, branch)
        self.u.mem_write(0x40001254, branch)
        self.run_code('gate_tx_buffer', d0=3, a0=0x101000, sr=0x2700)
        self.assertEqual(self.u.reg_read(UC_M68K_REG_D1), 0x101003)
        self.assertEqual(self.u.reg_read(UC_M68K_REG_D0), 0)
        self.put(0x4049dca0, 1)
        self.run_code('gate_tx_byte', d1=0xf8, sr=0x2700)
        self.assertEqual(self.u.reg_read(UC_M68K_REG_D0), 1)
        self.assertEqual(self.u.reg_read(UC_M68K_REG_D1), 0xf8)
        self.assertEqual(self.writes, [])

    def test_fixed_levels_flush_and_restore(self):
        self.activate(6)
        self.assertEqual(self.get('gate_level'), 1)
        before = list(self.writes)
        for _ in range(10):
            self.service()
            self.byte(0xf8)
        self.assertEqual(self.writes, before)
        self.run_code('gate_flush_status', end=0x40001326)
        self.assertTrue(self.u.reg_read(UC_M68K_REG_D0) & 8)
        self.activate(5)
        self.assertEqual(self.get('gate_level'), 0)
        self.activate(6)
        self.activate(0)
        self.assertEqual(self.writes[-1], (UCR, 1, 0x70))
        self.assertEqual(self.get('gate_timer'), 0)
        self.run_code('gate_tx_byte', end=0x40001254, d1=0x90, sr=0x2700)
        self.u.mem_write(USR, b'\x04')
        self.run_code('gate_flush_status', end=0x40001326)
        self.assertFalse(self.u.reg_read(UC_M68K_REG_D0) & 8)


if __name__ == '__main__':
    unittest.main()
