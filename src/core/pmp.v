module PmpRegisters (
    input clk,
    input reset,
    input [11:0] address,
    input write_enable,
    input [31:0] write_data,
    output reg known,
    output reg [31:0] read_data,
    output [63:0] configuration,
    output [255:0] addresses
);
    reg [7:0] cfg[0:7];
    reg [31:0] addr[0:7];
    integer i;
    integer j;
    genvar n;

    generate
        for (n = 0; n < 8; n = n + 1) begin : packed_entries
            assign configuration[n*8 +: 8] = cfg[n];
            assign addresses[n*32 +: 32] = addr[n];
        end
    endgenerate

    function [7:0] normalize(input [7:0] v);
        begin
            normalize = v & 8'h9f;
            if (v[1:0] == 2'b10) begin
                normalize[1] = 0;  // W without R is reserved
            end
        end
    endfunction

    always @(*) begin
        known = 0;
        read_data = 0;
        if (address == 12'h3a0 || address == 12'h3a1) begin
            known = 1;
            for (j = 0; j < 4; j = j + 1) begin
                read_data[j*8 +: 8] = cfg[(address == 12'h3a1 ? 4 : 0)+j];
            end
        end

        if (address == 12'h3a2 || address == 12'h3a3 || (address >= 12'h3b8 && address <= 12'h3bf)) begin
            known = 1;
        end

        for (j = 0; j < 8; j = j + 1) begin
            if (address == 12'h3b0 + j) begin
                known = 1;
                read_data = addr[j];
            end
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 8; i = i + 1) begin
                cfg[i] <= 0;
                addr[i] <= 0;
            end
        end else if (write_enable) begin
            for (i = 0; i < 8; i = i + 1) begin
                if (!cfg[i][7]) begin
                    if (address == 12'h3a0 + i / 4) begin
                        cfg[i] <= normalize(write_data[(i%4)*8 +: 8]);
                    end

                    if (address == 12'h3b0 + i) begin
                        if (i == 7) begin
                            addr[i] <= write_data;
                        end else if (!(cfg[i+1][7] && cfg[i+1][4:3] == 1)) begin
                            addr[i] <= write_data;
                        end
                    end
                end
            end
        end
    end
endmodule

module PmpCheck (
    input [63:0] configuration,
    input [255:0] addresses,
    input [33:0] address,
    input [1:0] size,
    input [1:0] privilege,
    input execute,
    input read_access,
    input write_access,
    output reg allowed
);
    integer entry;
    reg found;

    wire [35:0] napot_mask[0:7];
    genvar region;
    genvar mask_bit;

    generate
        for (region = 0; region < 8; region = region + 1) begin : napot_masks
            assign napot_mask[region][2:0] = 3'b111;
            assign napot_mask[region][35] = 1'b0;
            for (mask_bit = 3; mask_bit < 35; mask_bit = mask_bit + 1) begin : prefix
                assign napot_mask[region][mask_bit] = &addresses[region*32 +: mask_bit-2];
            end
        end
    endgenerate

    reg [7:0] cfg;
    reg [31:0] encoded;
    reg [35:0] lower;
    reg [35:0] upper;
    reg [35:0] first_byte;
    reg [35:0] end_byte;

    always @(*) begin
        allowed = privilege == 3;
        found = 0;
        cfg = 0;
        encoded = 0;
        lower = 0;
        upper = 0;
        first_byte = {2'd0, address};
        end_byte = first_byte + (36'd1 << size);

        for (entry = 0; entry < 8; entry = entry + 1) begin
            cfg = configuration[entry*8 +: 8];
            encoded = addresses[entry*32 +: 32];
            lower = 0;
            upper = 0;

            case (cfg[4:3])
                1: begin
                    if (entry != 0) begin
                        lower = {2'd0, addresses[(entry-1)*32 +: 32], 2'd0};
                    end

                    upper = {2'd0, encoded, 2'd0};
                end

                2: begin
                    lower = {2'd0, encoded, 2'd0};
                    upper = lower + 4;
                end

                3: begin
                    lower = {2'd0, encoded, 2'd0} & ~napot_mask[entry];
                    upper = ({2'd0, encoded, 2'd0} | napot_mask[entry]) + 36'd1;
                end

                default: ;
            endcase

            if (!found && cfg[4:3] != 0 && lower < upper && first_byte < upper && end_byte > lower) begin
                found = 1;
                allowed = first_byte >= lower && end_byte <= upper &&
                    ((privilege == 3 && !cfg[7]) ||
                     ((!execute || cfg[2]) && (!read_access || cfg[0]) && (!write_access || cfg[1])));
            end
        end

        if (size == 3 || privilege == 2) begin
            allowed = 0;
        end
    end
endmodule
