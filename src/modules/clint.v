module Clint #(
    parameter [31:0] BASE_ADDRESS = 32'h02000000
) (
    input clk,
    input reset,
    input [31:0] address,
    input [31:0] write_data,
    input [3:0] write_mask,
    input write_enable,
    output reg [31:0] read_data,
    output irq_software,
    output irq_timer,
    output [63:0] time_value
);
    wire [31:0] word_address = {address[31:2], 2'b00};
    reg msip;
    reg [63:0] mtime;
    reg [63:0] mtimecmp;
    integer lane;

    assign irq_software = msip;
    assign irq_timer = mtime >= mtimecmp;
    assign time_value = mtime;

    always @(*) begin
        case (word_address)
            BASE_ADDRESS: read_data = {31'd0, msip};
            BASE_ADDRESS + 32'h4000: read_data = mtimecmp[31:0];
            BASE_ADDRESS + 32'h4004: read_data = mtimecmp[63:32];
            BASE_ADDRESS + 32'hbff8: read_data = mtime[31:0];
            BASE_ADDRESS + 32'hbffc: read_data = mtime[63:32];
            default: read_data = 0;
        endcase
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            msip <= 0;
            mtime <= 0;
            mtimecmp <= 64'hffff_ffff_ffff_ffff;
        end else begin
            mtime <= mtime + 64'd1;
            if (write_enable) begin
                if (word_address == BASE_ADDRESS && write_mask[0]) begin
                    msip <= write_data[0];
                end

                for (lane = 0; lane < 4; lane = lane + 1) begin
                    if (write_mask[lane]) begin
                        case (word_address)
                            BASE_ADDRESS + 32'h4000: mtimecmp[lane*8 +: 8] <= write_data[lane*8 +: 8];
                            BASE_ADDRESS + 32'h4004: mtimecmp[32+lane*8 +: 8] <= write_data[lane*8 +: 8];
                            BASE_ADDRESS + 32'hbff8: mtime[lane*8 +: 8] <= write_data[lane*8 +: 8];
                            BASE_ADDRESS + 32'hbffc: mtime[32+lane*8 +: 8] <= write_data[lane*8 +: 8];
                            default: ;
                        endcase
                    end
                end
            end
        end
    end
endmodule
