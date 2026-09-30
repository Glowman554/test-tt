module BareMemory (
    input clk,
    input reset,
    input req_valid,
    input [31:0] req_address,
    input req_write,
    input [31:0] req_wdata,
    input [3:0] req_wstrb,
    input [1:0] req_kind,
    input req_atomic,
    input req_sc,
    input sc_reserved_valid,
    input [33:0] sc_reserved_address,
    output req_ready,
    output reg [31:0] req_rdata,
    output reg req_error,
    output req_page_fault,
    output reg sc_success,
    output [33:0] translated_address,
    output valid,
    output [33:0] address,
    output write,
    output [31:0] wdata,
    output [3:0] wstrb,
    output [1:0] kind,
    input ready,
    input [31:0] rdata,
    input error
);
    wire [33:0] physical_address = {2'b00, req_address};
    wire ram_address = req_address >= 32'h40000000 &&
                       req_address < 32'h41000000;
    wire sc_failed = req_sc &&
        (!sc_reserved_valid || sc_reserved_address != {physical_address[33:2], 2'b00});
    localparam IDLE = 2'd0;
    localparam ACCESS = 2'd1;
    localparam RESPONSE = 2'd2;
    reg [1:0] state;
    wire denied = req_atomic && !ram_address;
    assign translated_address = physical_address;
    assign valid = !reset && state == ACCESS && req_valid && !denied && !sc_failed;
    assign address = {physical_address[33:2], 2'b00};
    assign write = req_write;
    assign wdata = req_wdata;
    assign wstrb = req_write ? req_wstrb : 4'd0;
    assign kind = req_kind;
    assign req_ready = !reset && state == RESPONSE && req_valid;
    assign req_page_fault = 1'b0;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            req_rdata <= 0;
            req_error <= 0;
            sc_success <= 0;
        end else begin
            case (state)
                IDLE: if (req_valid) begin
                    req_rdata <= 0;
                    req_error <= 0;
                    sc_success <= 0;
                    state <= ACCESS;
                end
                ACCESS: begin
                    if (denied) begin
                        req_error <= 1;
                        state <= RESPONSE;
                    end else if (sc_failed) begin
                        state <= RESPONSE;
                    end else if (ready) begin
                        req_rdata <= rdata;
                        req_error <= error;
                        sc_success <= req_sc && !error;
                        state <= RESPONSE;
                    end
                end
                RESPONSE: if (req_valid) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
