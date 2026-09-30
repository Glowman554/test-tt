// Single-bit SPI memory bus for the Tiny Tapeout flash/PSRAM Pmod.
// Flash: W25Q128JV, 0x00000000-0x00ffffff, read-only.
// PSRAM: two APS6404L chips, 0x40000000-0x40ffffff.
// The memory bus has one outstanding transaction and holds ready until valid drops.
module SerialMemory #(
    parameter STARTUP_CYCLES = 4096
) (
    input wire clk,
    input wire reset,
    input wire valid,
    input wire [31:0] address,
    input wire write,
    input wire [31:0] wdata,
    input wire [3:0] wstrb,
    output wire ready,
    output wire [31:0] rdata,
    output wire flash_cs_n,
    output wire ram_a_cs_n,
    output wire ram_b_cs_n,
    output wire sclk,
    output wire mosi,
    input wire miso
);
    localparam IDLE = 3'd0;
    localparam SETUP = 3'd1;
    localparam SAMPLE = 3'd2;
    localparam GAP = 3'd3;
    localparam DONE = 3'd4;

    reg [2:0] state;
    reg [12:0] startup_count;
    reg startup_done;
    reg is_flash;
    reg bank_b;
    reg req_write;
    reg [23:0] word_offset;
    reg [31:0] write_word;
    reg [3:0] remaining_mask;
    reg [1:0] lane;
    reg [39:0] tx_shift;
    reg [31:0] rx_shift;
    reg [6:0] bit_count;

    function [1:0] first_lane;
        input [3:0] mask;
        begin
            if (mask[0]) first_lane = 0;
            else if (mask[1]) first_lane = 1;
            else if (mask[2]) first_lane = 2;
            else first_lane = 3;
        end
    endfunction

    wire active = state == SETUP || state == SAMPLE;
    assign flash_cs_n = !(active && is_flash);
    assign ram_a_cs_n = !(active && !is_flash && !bank_b);
    assign ram_b_cs_n = !(active && !is_flash && bank_b);
    assign sclk = state == SAMPLE;
    assign mosi = tx_shift[39];
    assign ready = state == DONE;
    // SPI sends the byte at the lowest address first; the CPU is little-endian.
    assign rdata = {rx_shift[7:0], rx_shift[15:8], rx_shift[23:16], rx_shift[31:24]};

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            startup_count <= 0;
            startup_done <= 0;
            is_flash <= 0;
            bank_b <= 0;
            req_write <= 0;
            word_offset <= 0;
            write_word <= 0;
            remaining_mask <= 0;
            lane <= 0;
            tx_shift <= 0;
            rx_shift <= 0;
            bit_count <= 0;
        end else begin
            if (!startup_done) begin
                if (startup_count == STARTUP_CYCLES - 1) begin
                    startup_done <= 1;
                end else begin
                    startup_count <= startup_count + 1'b1;
                end
            end

            case (state)
                IDLE: if (startup_done && valid) begin
                    is_flash <= address[31:24] == 0;
                    bank_b <= address[23];
                    req_write <= write;
                    word_offset <= address[23:0];
                    write_word <= wdata;
                    rx_shift <= 0;
                    bit_count <= 0;
                    if (write) begin
                        if (wstrb == 0) begin
                            state <= DONE;
                        end else begin
                            lane <= first_lane(wstrb);
                            remaining_mask <= wstrb & ~(4'b0001 << first_lane(wstrb));
                            tx_shift <= {8'h02, 1'b0, address[22:2], first_lane(wstrb),
                                         wdata[first_lane(wstrb)*8 +: 8]};
                            state <= SETUP;
                        end
                    end else begin
                        tx_shift <= {8'h03,
                                     address[31:24] == 0 ? address[23:0] : {1'b0, address[22:0]},
                                     8'h00};
                        state <= SETUP;
                    end
                end
                SETUP: state <= SAMPLE;
                SAMPLE: begin
                    if (!req_write && bit_count >= 32)
                        rx_shift <= {rx_shift[30:0], miso};
                    tx_shift <= {tx_shift[38:0], 1'b0};
                    bit_count <= bit_count + 1'b1;
                    if ((req_write && bit_count == 39) || (!req_write && bit_count == 63))
                        state <= req_write && remaining_mask != 0 ? GAP : DONE;
                    else
                        state <= SETUP;
                end
                GAP: begin
                    lane <= first_lane(remaining_mask);
                    remaining_mask <= remaining_mask & ~(4'b0001 << first_lane(remaining_mask));
                    tx_shift <= {8'h02, 1'b0, word_offset[22:2], first_lane(remaining_mask),
                                 write_word[first_lane(remaining_mask)*8 +: 8]};
                    bit_count <= 0;
                    state <= SETUP;
                end
                DONE: if (!valid) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
