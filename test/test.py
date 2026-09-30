import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_pinout_and_boot_access(dut):
    cocotb.start_soon(Clock(dut.clk, 40, unit="ns").start())
    dut.ena.value = 1
    dut.ui_in.value = 2  # UART RX idles high
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 4)
    assert int(dut.uio_oe.value) == 0xFB
    assert int(dut.uio_out.value) & 0xF1 == 0xF1
    dut.rst_n.value = 1
    saw_flash_select = False
    saw_clock_high = False
    for _ in range(4300):
        await ClockCycles(dut.clk, 1)
        pins = int(dut.uio_out.value)
        if not (pins & 1):
            saw_flash_select = True
            saw_clock_high |= bool(pins & 8)
    assert saw_flash_select
    assert saw_clock_high
