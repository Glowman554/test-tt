module Decompress (
    input [15:0] c,
    output reg [31:0] instruction
);
    localparam [6:0] OP_IMM = 7'h13;
    localparam [6:0] OP = 7'h33;
    localparam [6:0] LUI = 7'h37;
    localparam [6:0] LOAD = 7'h03;
    localparam [6:0] STORE = 7'h23;
    localparam [6:0] LOAD_FP = 7'h07;
    localparam [6:0] STORE_FP = 7'h27;
    localparam [6:0] BRANCH = 7'h63;
    localparam [6:0] JALR = 7'h67;
    localparam [6:0] JAL = 7'h6f;

    wire [4:0] rd = c[11:7];
    wire [4:0] rs2 = c[6:2];
    wire [4:0] rd_short = {2'b01, c[4:2]};
    wire [4:0] rs1_short = {2'b01, c[9:7]};

    wire [11:0] imm6 = {{7{c[12]}}, c[6:2]};
    wire [11:0] addi4spn_imm = {2'b0, c[10:7], c[12:11], c[5], c[6], 2'b00};
    wire [11:0] word_offset = {5'b0, c[5], c[12:10], c[6], 2'b00};
    wire [11:0] double_offset = {4'b0, c[6:5], c[12:10], 3'b000};
    wire [11:0] lwsp_offset = {4'b0, c[3:2], c[12], c[6:4], 2'b00};
    wire [11:0] ldsp_offset = {3'b0, c[4:2], c[12], c[6:5], 3'b000};
    wire [11:0] swsp_offset = {4'b0, c[8:7], c[12:9], 2'b00};
    wire [11:0] sdsp_offset = {3'b0, c[9:7], c[12:10], 3'b000};
    wire [11:0] addi16sp_imm = {{3{c[12]}}, c[4:3], c[5], c[2], c[6], 4'b0};
    wire [20:0] jump_offset = {{10{c[12]}}, c[8], c[10:9], c[6], c[7], c[2], c[11], c[5:3], 1'b0};
    wire [12:0] branch_offset = {{5{c[12]}}, c[6:5], c[2], c[11:10], c[4:3], 1'b0};

    function [31:0] i_type(input [11:0] imm, input [4:0] rs1, input [2:0] funct3, input [4:0] dest, input [6:0] opcode);
        i_type = {imm, rs1, funct3, dest, opcode};
    endfunction

    function [31:0] s_type(input [11:0] imm, input [4:0] src, input [4:0] rs1, input [2:0] funct3, input [6:0] opcode);
        s_type = {imm[11:5], src, rs1, funct3, imm[4:0], opcode};
    endfunction

    function [31:0] r_type(input [6:0] funct7, input [4:0] src, input [4:0] rs1, input [2:0] funct3, input [4:0] dest);
        r_type = {funct7, src, rs1, funct3, dest, OP};
    endfunction

    function [31:0] b_type(input [12:0] imm, input [4:0] rs1, input [2:0] funct3);
        b_type = {imm[12], imm[10:5], 5'd0, rs1, funct3, imm[4:1], imm[11], BRANCH};
    endfunction

    function [31:0] j_type(input [20:0] imm, input [4:0] dest);
        j_type = {imm[20], imm[10:1], imm[11], imm[19:12], dest, JAL};
    endfunction

    always @(*) begin
        instruction = 32'd0;

        case ({c[1:0], c[15:13]})
            // Quadrant 0
            5'b00_000: if (addi4spn_imm != 0) begin
                instruction = i_type(addi4spn_imm, 5'd2, 3'd0, rd_short, OP_IMM);
            end
            5'b00_001: instruction = i_type(double_offset, rs1_short, 3'd3, rd_short, LOAD_FP);
            5'b00_010: instruction = i_type(word_offset, rs1_short, 3'd2, rd_short, LOAD);
            5'b00_011: instruction = i_type(word_offset, rs1_short, 3'd2, rd_short, LOAD_FP);
            5'b00_101: instruction = s_type(double_offset, rd_short, rs1_short, 3'd3, STORE_FP);
            5'b00_110: instruction = s_type(word_offset, rd_short, rs1_short, 3'd2, STORE);
            5'b00_111: instruction = s_type(word_offset, rd_short, rs1_short, 3'd2, STORE_FP);

            // Quadrant 1
            5'b01_000: instruction = i_type(imm6, rd, 3'd0, rd, OP_IMM);
            5'b01_001: instruction = j_type(jump_offset, 5'd1);
            5'b01_010: instruction = i_type(imm6, 5'd0, 3'd0, rd, OP_IMM);
            5'b01_011: begin
                if (rd == 2) begin
                    if (addi16sp_imm != 0) begin
                        instruction = i_type(addi16sp_imm, 5'd2, 3'd0, 5'd2, OP_IMM);
                    end
                end else if (imm6 != 0) begin
                    instruction = {{15{c[12]}}, c[6:2], rd, LUI};
                end
            end
            5'b01_100: begin
                case (c[11:10])
                    2'b00: if (!c[12]) begin
                        instruction = i_type({7'h00, c[6:2]}, rs1_short, 3'd5, rs1_short, OP_IMM);
                    end
                    2'b01: if (!c[12]) begin
                        instruction = i_type({7'h20, c[6:2]}, rs1_short, 3'd5, rs1_short, OP_IMM);
                    end
                    2'b10: instruction = i_type(imm6, rs1_short, 3'd7, rs1_short, OP_IMM);
                    2'b11: begin
                        if (!c[12]) begin
                            case (c[6:5])
                                2'b00: instruction = r_type(7'h20, rd_short, rs1_short, 3'd0, rs1_short);
                                2'b01: instruction = r_type(7'h00, rd_short, rs1_short, 3'd4, rs1_short);
                                2'b10: instruction = r_type(7'h00, rd_short, rs1_short, 3'd6, rs1_short);
                                2'b11: instruction = r_type(7'h00, rd_short, rs1_short, 3'd7, rs1_short);
                            endcase
                        end
                    end
                endcase
            end
            5'b01_101: instruction = j_type(jump_offset, 5'd0);
            5'b01_110: instruction = b_type(branch_offset, rs1_short, 3'd0);
            5'b01_111: instruction = b_type(branch_offset, rs1_short, 3'd1);

            // Quadrant 2
            5'b10_000: if (!c[12]) begin
                instruction = i_type({7'h00, c[6:2]}, rd, 3'd1, rd, OP_IMM);
            end
            5'b10_001: instruction = i_type(ldsp_offset, 5'd2, 3'd3, rd, LOAD_FP);
            5'b10_010: if (rd != 0) begin
                instruction = i_type(lwsp_offset, 5'd2, 3'd2, rd, LOAD);
            end
            5'b10_011: instruction = i_type(lwsp_offset, 5'd2, 3'd2, rd, LOAD_FP);
            5'b10_100: begin
                if (!c[12]) begin
                    if (rs2 == 0) begin
                        if (rd != 0) begin
                            instruction = i_type(12'd0, rd, 3'd0, 5'd0, JALR);
                        end
                    end else begin
                        instruction = r_type(7'h00, rs2, 5'd0, 3'd0, rd);
                    end
                end else begin
                    if (rs2 == 0) begin
                        if (rd == 0) begin
                            instruction = 32'h00100073;
                        end else begin
                            instruction = i_type(12'd0, rd, 3'd0, 5'd1, JALR);
                        end
                    end else begin
                        instruction = r_type(7'h00, rs2, rd, 3'd0, rd);
                    end
                end
            end
            5'b10_101: instruction = s_type(sdsp_offset, rs2, 5'd2, 3'd3, STORE_FP);
            5'b10_110: instruction = s_type(swsp_offset, rs2, 5'd2, 3'd2, STORE);
            5'b10_111: instruction = s_type(swsp_offset, rs2, 5'd2, 3'd2, STORE_FP);

            default: ;
        endcase
    end
endmodule
