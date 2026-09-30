module Plic #(
    parameter NUM_SOURCES = 34,
    parameter [31:0] BASE_ADDRESS = 32'h0c000000
) (
    input clk,
    input reset,
    input [NUM_SOURCES:1] irq_sources,
    input [31:0] address,
    input [31:0] write_data,
    input [3:0] write_mask,
    input write_enable,
    input read_commit,
    output reg [31:0] read_data,
    output irq_machine,
    output irq_supervisor
);
    localparam ID_BITS = $clog2(NUM_SOURCES + 1);

    wire [31:0] offset = {address[31:2], 2'b00} - BASE_ADDRESS;
    wire in_range = address >= BASE_ADDRESS && offset < 32'h04000000;

    reg [2:0] priorities[1:NUM_SOURCES];
    reg [NUM_SOURCES:1] enables[0:1];
    reg [2:0] thresholds[0:1];
    reg [NUM_SOURCES:1] pending;
    reg [NUM_SOURCES:1] in_service;
    reg [NUM_SOURCES:1] owner;

    wire [ID_BITS-1:0] selected[0:1];
    localparam TREE_LEAVES = 1 << $clog2(NUM_SOURCES);
    wire [NUM_SOURCES:1] eligible[0:1];

    integer rc;
    integer rs;
    integer wc;
    integer ws;

    assign irq_machine = |eligible[0];
    assign irq_supervisor = |eligible[1];

    genvar context_id;
    genvar node;

    generate
        for (context_id = 0; context_id < 2; context_id = context_id + 1) begin : contexts
            wire [ID_BITS+2:0] winner[1:2*TREE_LEAVES-1];

            for (node = 0; node < TREE_LEAVES; node = node + 1) begin : leaves
                if (node < NUM_SOURCES) begin : source
                    localparam [ID_BITS-1:0] SOURCE_ID = node + 1;

                    assign eligible[context_id][node+1] = pending[node+1] &&
                        !in_service[node+1] && enables[context_id][node+1] &&
                        priorities[node+1] > thresholds[context_id];
                    assign winner[TREE_LEAVES+node] = eligible[context_id][node+1] ? {priorities[node+1], SOURCE_ID} : 0;
                end else begin : padding
                    assign winner[TREE_LEAVES+node] = 0;
                end
            end

            for (node = 1; node < TREE_LEAVES; node = node + 1) begin : branches
                assign winner[node] = winner[2*node][ID_BITS+2:ID_BITS] >= winner[2*node+1][ID_BITS+2:ID_BITS] ?
                    winner[2*node] : winner[2*node+1];
            end

            assign selected[context_id] = winner[1][ID_BITS-1:0];
        end
    endgenerate

    always @(*) begin
        read_data = 0;
        if (in_range) begin
            for (rs = 1; rs <= NUM_SOURCES; rs = rs + 1) begin
                if (offset == rs * 4) begin
                    read_data = {29'd0, priorities[rs]};
                end

                if (offset == 32'h1000 + (rs / 32) * 4) begin
                    read_data[rs % 32] = pending[rs];
                end
            end

            for (rc = 0; rc < 2; rc = rc + 1) begin
                for (rs = 1; rs <= NUM_SOURCES; rs = rs + 1) begin
                    if (offset == 32'h2000 + rc * 32'h80 + (rs / 32) * 4) begin
                        read_data[rs % 32] = enables[rc][rs];
                    end
                end

                if (offset == 32'h200000 + rc * 32'h1000) begin
                    read_data = {29'd0, thresholds[rc]};
                end

                if (offset == 32'h200004 + rc * 32'h1000) begin
                    read_data = selected[rc];
                end
            end
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pending <= 0;
            in_service <= 0;
            owner <= 0;
            for (wc = 0; wc < 2; wc = wc + 1) begin
                enables[wc] <= 0;
                thresholds[wc] <= 0;
            end

            for (ws = 1; ws <= NUM_SOURCES; ws = ws + 1) begin
                priorities[ws] <= 0;
            end
        end else begin
            pending <= pending | (irq_sources & ~in_service);

            if (in_range) begin
                for (wc = 0; wc < 2; wc = wc + 1) begin
                    if (read_commit && offset == 32'h200004 + wc * 32'h1000 && selected[wc] != 0) begin
                        pending[selected[wc]] <= 0;
                        in_service[selected[wc]] <= 1;
                        owner[selected[wc]] <= wc != 0;
                    end

                    if (write_enable) begin
                        if (offset == 32'h200000 + wc * 32'h1000 && write_mask[0]) begin
                            thresholds[wc] <= write_data[2:0];
                        end

                        for (ws = 1; ws <= NUM_SOURCES; ws = ws + 1) begin
                            if (offset == 32'h200004 + wc * 32'h1000 &&
                                write_mask[0] && write_data == ws &&
                                in_service[ws] && owner[ws] == (wc != 0) &&
                                enables[wc][ws]) begin
                                in_service[ws] <= 0;
                            end

                            if (offset == 32'h2000 + wc * 32'h80 + (ws / 32) * 4 && write_mask[(ws % 32) / 8]) begin
                                enables[wc][ws] <= write_data[ws % 32];
                            end
                        end
                    end
                end

                if (write_enable && write_mask[0]) begin
                    for (ws = 1; ws <= NUM_SOURCES; ws = ws + 1) begin
                        if (offset == ws * 4) begin
                            priorities[ws] <= write_data[2:0];
                        end
                    end
                end
            end
        end
    end
endmodule
