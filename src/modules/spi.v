module Spi #(
    parameter BASE_ADDRESS = 32'h80000040
) (
    input clk,
    input reset,

    input [31:0] address,
    input [31:0] write_data,
    input [3:0] write_mask,
    input write_enable,

    output reg sclk,
    output mosi,
    input miso,
    output cs_n,

    output reg [31:0] read_data
);
    wire [31:0] word_address = {address[31:2], 2'b00};

    reg [15:0] divider;
    reg cpol;
    reg cpha;
    reg cs;

    reg busy;
    reg [15:0] count;
    reg [3:0] edge_index;
    reg [7:0] tx_shift;
    reg [7:0] rx_shift;

    assign mosi = tx_shift[7];
    assign cs_n = !cs;

    wire ctrl_write = write_enable && word_address == BASE_ADDRESS;
    wire cs_write = write_enable && word_address == BASE_ADDRESS + 4;
    wire start = write_enable && word_address == BASE_ADDRESS + 8 && write_mask[0] && !busy;

    wire leading_edge = !edge_index[0];
    wire sample_edge = leading_edge ^ cpha;
    wire shift_edge = !sample_edge && edge_index != 0;

    always @* begin
        case (word_address)
            BASE_ADDRESS: read_data = {14'd0, cpha, cpol, divider};
            BASE_ADDRESS + 4: read_data = {31'd0, cs};
            BASE_ADDRESS + 8: read_data = {24'd0, rx_shift};
            BASE_ADDRESS + 12: read_data = {31'd0, busy};
            default: read_data = 0;
        endcase
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            divider <= 16'd67;
            cpol <= 0;
            cpha <= 0;
            cs <= 0;
            sclk <= 0;
            busy <= 0;
            count <= 0;
            edge_index <= 0;
            tx_shift <= 8'hff;
            rx_shift <= 0;
        end else begin
            if (ctrl_write) begin
                if (write_mask[0]) begin
                    divider[7:0] <= write_data[7:0];
                end

                if (write_mask[1]) begin
                    divider[15:8] <= write_data[15:8];
                end

                if (write_mask[2]) begin
                    cpol <= write_data[16];
                    cpha <= write_data[17];
                    if (!busy) begin
                        sclk <= write_data[16];
                    end
                end
            end

            if (cs_write && write_mask[0]) begin
                cs <= write_data[0];
            end

            if (start) begin
                tx_shift <= write_data[7:0];
                count <= divider;
                edge_index <= 0;
                busy <= 1;
            end else if (busy) begin
                if (count != 0) begin
                    count <= count - 1'b1;
                end else begin
                    count <= divider;
                    sclk <= !sclk;
                    edge_index <= edge_index + 1'b1;

                    if (sample_edge) begin
                        rx_shift <= {rx_shift[6:0], miso};
                    end

                    if (shift_edge) begin
                        tx_shift <= {tx_shift[6:0], 1'b1};
                    end

                    if (edge_index == 15) begin
                        busy <= 0;
                    end
                end
            end
        end
    end
endmodule
