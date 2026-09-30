module Uart #(
    parameter BASE_ADDRESS = 32'h80000008
) (
    input clk,
    input reset,

    input [31:0] address,
    input [31:0] write_data,
    input [3:0] write_mask,
    input write_enable,
    input read_commit,

    input rx,
    output tx,
    output rx_valid,
    output reg [31:0] read_data
);
    wire [31:0] word_address = {address[31:2], 2'b00};
    reg [31:0] scaler;
    wire tx_busy;
    wire tx_start;
    wire rx_clear;
    wire [7:0] rx_data;

    assign tx_start = write_enable && word_address == BASE_ADDRESS + 4 && write_mask[0];
    assign rx_clear = read_commit && word_address == BASE_ADDRESS + 8;

    always @* begin
        case (word_address)
            BASE_ADDRESS: read_data = scaler;
            BASE_ADDRESS + 4: read_data = {31'd0, tx_busy};
            BASE_ADDRESS + 8: read_data = {16'd0, rx_data, 7'd0, rx_valid};
            default: read_data = 0;
        endcase
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            scaler <= 0;
        end else if (write_enable && word_address == BASE_ADDRESS) begin
            if (write_mask[0]) begin
                scaler[7:0] <= write_data[7:0];
            end

            if (write_mask[1]) begin
                scaler[15:8] <= write_data[15:8];
            end

            if (write_mask[2]) begin
                scaler[23:16] <= write_data[23:16];
            end

            if (write_mask[3]) begin
                scaler[31:24] <= write_data[31:24];
            end
        end
    end

    UartTx tx_unit (
        .clk(clk),
        .reset(reset),
        .scaler(scaler),
        .start(tx_start),
        .data(write_data[7:0]),
        .tx(tx),
        .busy(tx_busy)
    );

    UartRx rx_unit (
        .clk(clk),
        .reset(reset),
        .scaler(scaler),
        .rx(rx),
        .clear(rx_clear),
        .data(rx_data),
        .valid(rx_valid)
    );
endmodule

module UartTx (
    input clk,
    input reset,
    input [31:0] scaler,
    input start,
    input [7:0] data,
    output reg tx,
    output reg busy
);
    localparam IDLE = 2'd0;
    localparam START = 2'd1;
    localparam DATA = 2'd2;
    localparam STOP = 2'd3;

    reg [1:0] state;
    reg [31:0] count;
    reg [31:0] frame_scaler;
    reg [7:0] payload;
    reg [2:0] bitpos;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            tx <= 1'b1;
            busy <= 1'b0;
            count <= 0;
            frame_scaler <= 0;
            payload <= 0;
            bitpos <= 0;
        end else if (state == IDLE) begin
            busy <= 1'b0;
            if (start) begin
                payload <= data;
                frame_scaler <= scaler;
                count <= scaler;
                bitpos <= 0;
                tx <= 1'b0;
                busy <= 1'b1;
                state <= START;
            end
        end else if (count != 0) begin
            count <= count - 1'b1;
        end else begin
            count <= frame_scaler;
            case (state)
                START: begin
                    tx <= payload[0];
                    state <= DATA;
                end

                DATA: if (bitpos == 7) begin
                    tx <= 1'b1;
                    state <= STOP;
                end else begin
                    bitpos <= bitpos + 1'b1;
                    tx <= payload[bitpos + 1'b1];
                end

                STOP: state <= IDLE;

                default: begin
                    state <= IDLE;
                    tx <= 1'b1;
                end
            endcase
        end
    end
endmodule

module UartRx (
    input clk,
    input reset,
    input [31:0] scaler,
    input rx,
    input clear,
    output reg [7:0] data,
    output reg valid
);
    localparam IDLE = 2'd0;
    localparam START = 2'd1;
    localparam DATA = 2'd2;
    localparam STOP = 2'd3;

    reg [1:0] state;
    reg [31:0] count;
    reg [2:0] bitpos;
    reg [7:0] shift;
    (* async_reg = "true" *) reg rx_meta;
    (* async_reg = "true" *) reg rx_sync;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            count <= 0;
            bitpos <= 0;
            shift <= 0;
            data <= 0;
            valid <= 0;
            rx_meta <= 1;
            rx_sync <= 1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;

            if (clear) begin
                valid <= 1'b0;
            end

            case (state)
                IDLE: if (!rx_sync && !valid) begin
                    count <= (scaler + 1'b1) >> 1;
                    bitpos <= 0;
                    state <= START;
                end

                START: if (count != 0) begin
                    count <= count - 1'b1;
                end else if (!rx_sync) begin
                    count <= scaler;
                    state <= DATA;
                end else begin
                    state <= IDLE;
                end

                DATA: if (count != 0) begin
                    count <= count - 1'b1;
                end else begin
                    count <= scaler;
                    shift[bitpos] <= rx_sync;
                    if (bitpos == 7) state <= STOP;
                    else bitpos <= bitpos + 1'b1;
                end

                STOP: if (count != 0) begin
                    count <= count - 1'b1;
                end else begin
                    if (rx_sync) begin
                        data <= shift;
                        valid <= 1'b1;
                    end
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
