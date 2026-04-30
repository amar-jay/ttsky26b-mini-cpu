import cocotb
import os
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb.handle import Force, Release

def op(opcode, imm5):
    return (opcode << 5) | (imm5 & 0x1F)

# Helper to wait for the exact moment an instruction is executed
async def exec_inst(dut, opcode, imm5):
    # Force the instruction
    dut.user_project.instr.value = Force(op(opcode, imm5))
    
    # Wait until cpu_en goes high
    while int(dut.user_project.clk_div.value) != 15:
        await RisingEdge(dut.clk)
        
    # Wait one more cycle for the register latching
    await RisingEdge(dut.clk)
    
@cocotb.test(skip=os.environ.get("GATES", "no") == "yes")
async def test_isa_exhaustive(dut):
    dut._log.info("Start exhaustive ISA test")
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 20)
    dut.rst_n.value = 1

    # Test LDI
    await exec_inst(dut, 0b000, 12)
    assert int(dut.user_project.a.value) == 12, f"LDI failed: A={dut.user_project.a.value}"

    # Test ADDI
    await exec_inst(dut, 0b001, 5)
    assert int(dut.user_project.a.value) == 17, f"ADDI failed: A={dut.user_project.a.value}"

    # Test SUBI
    await exec_inst(dut, 0b010, 7)
    assert int(dut.user_project.a.value) == 10, "SUBI failed"

    # Test TAB (A -> B)
    await exec_inst(dut, 0b011, 0b0000)
    assert int(dut.user_project.b.value) == 10, "TAB failed"

    # Mutate A to something else
    await exec_inst(dut, 0b000, 20)
    
    # Test TBA (B -> A)
    await exec_inst(dut, 0b011, 0b0001)
    assert int(dut.user_project.a.value) == 10, "TBA failed"

    # Test IN
    dut.ui_in.value = 100
    await exec_inst(dut, 0b011, 0b0010)
    assert int(dut.user_project.a.value) == 100, "IN failed"

    # Test ANDB
    await exec_inst(dut, 0b000, 0b10101)  # LDI 21 (0x15)
    await exec_inst(dut, 0b011, 0b0000)   # TAB (B = 21)
    await exec_inst(dut, 0b000, 0b01111)  # LDI 15 (0x0F)
    await exec_inst(dut, 0b011, 0b0011)   # ANDB (A = 15 & 21 = 5)
    assert int(dut.user_project.a.value) == 5, "ANDB failed"

    # Test ORB
    await exec_inst(dut, 0b011, 0b0100)   # ORB (A = 5 | 21 = 21)
    assert int(dut.user_project.a.value) == 21, "ORB failed"

    # Test XORB
    await exec_inst(dut, 0b011, 0b0101)   # XORB (A = 21 ^ 21 = 0)
    assert int(dut.user_project.a.value) == 0, "XORB failed"

    # Test ADDB
    await exec_inst(dut, 0b000, 10)       # LDI 10
    await exec_inst(dut, 0b011, 0b0110)   # ADDB (A = 10 + 21 = 31)
    assert int(dut.user_project.a.value) == 31, "ADDB failed"

    # Test SUBB
    await exec_inst(dut, 0b011, 0b0111)   # SUBB (A = 31 - 21 = 10)
    assert int(dut.user_project.a.value) == 10, "SUBB failed"

    # Test SHL
    await exec_inst(dut, 0b011, 0b1000)   # SHL (A = 10 << 1 = 20)
    assert int(dut.user_project.a.value) == 20, "SHL failed"

    # Test SHR
    await exec_inst(dut, 0b011, 0b1001)   # SHR (A = 20 >> 1 = 10)
    assert int(dut.user_project.a.value) == 10, "SHR failed"

    # Test OUT
    await exec_inst(dut, 0b100, 0)        # OUT
    assert int(dut.uo_out.value) == 10, "OUT failed"

    # Test JMP
    await exec_inst(dut, 0b111, 14)       # JMP 14
    assert int(dut.user_project.pc.value) == 14, "JMP failed"

    # Test JZ/JNZ with non-zero
    await exec_inst(dut, 0b000, 1)        # LDI 1
    await exec_inst(dut, 0b110, 10)       # JZ 10 - should NOT jump
    assert int(dut.user_project.pc.value) != 10, "JZ branched when A!=0"
    
    await exec_inst(dut, 0b101, 10)       # JNZ 10 - should jump
    assert int(dut.user_project.pc.value) == 10, "JNZ failed to jump when A!=0"

    # Test JZ/JNZ with zero
    await exec_inst(dut, 0b000, 0)        # LDI 0
    await exec_inst(dut, 0b101, 5)        # JNZ 5 - should NOT jump
    assert int(dut.user_project.pc.value) != 5, "JNZ branched when A==0"

    await exec_inst(dut, 0b110, 5)        # JZ 5 - should jump
    assert int(dut.user_project.pc.value) == 5, "JZ failed to jump when A==0"

    dut._log.info("Exhaustive ISA test passed perfectly!")

