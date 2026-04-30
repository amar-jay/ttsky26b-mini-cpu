/*
 * Copyright (c) 2026 amarjay 
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// =========================================================================
// Instruction Set Architecture (ISA) Documentation
// =========================================================================
// Format: [Opcode: 3 bits][Operand: 5 bits]
// 
// Opcodes:
// 000 : LDI imm5    -> A = imm5
// 001 : ADDI imm5   -> A = A + imm5
// 010 : SUBI imm5   -> A = A - imm5
// 011 : ALU/Reg ops -> (See operand sub-opcodes below)
// 100 : OUT         -> out_reg = A (update output pins)
// 101 : JNZ imm5    -> if (A != 0) PC = imm5
// 110 : JZ  imm5    -> if (A == 0) PC = imm5
// 111 : JMP imm5    -> PC = imm5
//
// ALU/Reg Sub-opcodes (when Opcode == 011):
// 0000: TAB         -> B = A
// 0001: TBA         -> A = B
// 0010: IN          -> A = ui_in
// 0011: ANDB        -> A = A & B
// 0100: ORB         -> A = A | B
// 0101: XORB        -> A = A ^ B
// 0110: ADDB        -> A = A + B
// 0111: SUBB        -> A = A - B
// 1000: SHL         -> A = A << 1
// 1001: SHR         -> A = A >> 1
// =========================================================================

module tt_um_amarjay (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // Disable bidirectional I/O pins
    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;
    
    // CPU Registers
    reg [4:0] pc;
    reg [7:0] a;
    reg [7:0] b;
    reg [7:0] out_reg;

    assign uo_out = out_reg;

    // ROM Implementation (32 x 8-bit combinational lookup)
    reg [7:0] instr;

    always @(*) begin
        instr = 8'b111_00000; // Safe default assignment to prevent latches (JMP 0 / NOP)
        case (pc)
            // Knight Rider Scanner Program (Smooth Bounce)
            5'd00: instr = 8'b000_00001; // LDI 1      (A = 1)
            5'd01: instr = 8'b100_00000; // OUT        (uo_out = A)
            5'd02: instr = 8'b011_01000; // SHL        (A = A << 1)
            5'd03: instr = 8'b101_00001; // JNZ 1      (if A != 0, goto 1)
            5'd04: instr = 8'b000_10000; // LDI 16     (A = 16. Setting up for 64 since LDI max is 31)
            5'd05: instr = 8'b011_01000; // SHL        (A = 32)
            5'd06: instr = 8'b011_01000; // SHL        (A = 64)
            5'd07: instr = 8'b100_00000; // OUT        (uo_out = A)
            5'd08: instr = 8'b011_01001; // SHR        (A = A >> 1)
            5'd09: instr = 8'b101_00111; // JNZ 7      (if A != 0, goto 7)
            5'd10: instr = 8'b111_00000; // JMP 0      (PC = 0)
            default: instr = 8'b111_00000; // JMP 0 (PC = 0)
        endcase
    end

    // Instruction Decode
    wire [2:0] opcode = instr[7:5];
    wire [4:0] imm5   = instr[4:0];

    // ALU Logic (Combinational)
    // Determines the next value of register 'a' (next_a) to avoid latches.
    reg [7:0] next_a;
    always @(*) begin
        // Safe default assignment to prevent inferred latches
        next_a = a; 
        
        case (opcode)
            3'b000: next_a = {3'b000, imm5};                      // LDI imm5: Load Immediate (Implicit zero-extension)
            3'b001: next_a = a + {3'b000, imm5};                  // ADDI imm5: Add Immediate (Implicit zero-extension)
            3'b010: next_a = a - {3'b000, imm5};                  // SUBI imm5: Subtract Immediate
            3'b011: begin // ALU & Special Register Operations
                case (imm5[3:0])
                    4'b0000: next_a = a;                // TAB (Transfer A to B, A remains unchanged)
                    4'b0001: next_a = b;                // TBA (Transfer B to A)
                    4'b0010: next_a = ui_in;            // IN (Read dedicated input pins)
                    4'b0011: next_a = a & b;            // ANDB (Bitwise AND)
                    4'b0100: next_a = a | b;            // ORB (Bitwise OR)
                    4'b0101: next_a = a ^ b;            // XORB (Bitwise XOR)
                    4'b0110: next_a = a + b;            // ADDB (Addition)
                    4'b0111: next_a = a - b;            // SUBB (Subtraction)
                    4'b1000: next_a = {a[6:0], 1'b0};   // SHL (Logical Shift Left)
                    4'b1001: next_a = {1'b0, a[7:1]};   // SHR (Logical Shift Right)
                    default: next_a = a;                // Safe default for unmapped ALU ops
                endcase
            end
            default: next_a = a;                        // Safe default for unmapped opcodes (OUT, JMP, JNZ, JZ do not modify A)
        endcase
    end

    // Clock Divider (Small 4-bit Counter)
    // We use a clock enable (cpu_en) to run the CPU slower safely. 
    reg [3:0] clk_div;
    wire cpu_en = (&clk_div); // Reduction AND replaces (clk_div == 4'b1111) for cheaper area

    always @(posedge clk) begin
        if (!rst_n) begin
            clk_div <= 4'b0;
        end else begin
            clk_div <= clk_div + 1;
        end
    end

    // =========================================================================
    // Execution Semantics:
    // ALL branching (JNZ, JZ), IO updates (OUT), and internal register 
    // updates (TAB) explicitly use the CURRENT state of 'a'. 
    // The ALU concurrently evaluates 'next_a', which commits on the clock edge.
    // This defines a single clear "current-state evaluates, next-state updates" model.
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            pc      <= 5'b0;
            a       <= 8'b0;
            b       <= 8'b0;
            out_reg <= 8'b0;
        end else if (cpu_en) begin
            // Update A to the evaluated next_a state (from the ALU)
            a <= next_a;

            // Execute B load (TAB)
            if (opcode == 3'b011 && imm5[3:0] == 4'b0000) begin
                b <= a; // Latches the current value of 'a'.
            end

            // Execute OUT write (uo_out)
            if (opcode == 3'b100) begin
                out_reg <= a; // Latches the current value of 'a'.
            end

            // PC Control (Branching) based on current state of 'a'
            if (opcode == 3'b101 && a != 8'd0) begin
                pc <= imm5; // JNZ: Jump if Not Zero
            end
            else if (opcode == 3'b110 && a == 8'd0) begin
                pc <= imm5; // JZ: Jump if Zero
            end
            else if (opcode == 3'b111) begin
                pc <= imm5; // JMP: Unconditional Jump
            end
            else begin
                pc <= pc + 1; // Default: Proceed to next instruction
            end
        end
    end

    // Wire unneeded inputs to prevent warnings
    wire _unused = &{ena, uio_in, 1'b0};

endmodule
