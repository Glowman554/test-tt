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

// One PMP entry is evaluated per clock by the MMU.  This shares the NAPOT
// mask and range comparators across all eight entries.
module PmpEntryCheck (
    input [7:0] configuration,
    input [31:0] encoded,
    input [31:0] previous_encoded,
    input [33:0] address,
    input [1:0] size,
    input [1:0] privilege,
    input execute,
    input read_access,
    input write_access,
    output region_match,
    output permitted
);
    wire [35:0] first_byte = {2'b00, address};
    wire [35:0] end_byte = first_byte + (36'd1 << size);
    wire [35:0] last_byte = end_byte - 1'b1;
    wire [35:0] top = {2'b00, encoded, 2'b00};
    wire [35:0] bottom = {2'b00, previous_encoded, 2'b00};
    wire [35:0] napot_mask;
    genvar mask_bit;

    assign napot_mask[2:0] = 3'b111;
    assign napot_mask[35] = 1'b0;
    generate
        for (mask_bit = 3; mask_bit < 35; mask_bit = mask_bit + 1) begin : prefix
            assign napot_mask[mask_bit] = &encoded[mask_bit-3:0];
        end
    endgenerate

    wire [35:0] napot_base = top & ~napot_mask;
    wire napot_first = (first_byte & ~napot_mask) == napot_base;
    wire napot_last = (last_byte & ~napot_mask) == napot_base;
    wire na4_first = first_byte[35:2] == {2'b00, encoded};
    wire na4_last = last_byte[35:2] == {2'b00, encoded};
    wire tor_valid = bottom < top;
    wire tor_overlap = tor_valid && first_byte < top && end_byte > bottom;
    wire tor_inside = first_byte >= bottom && end_byte <= top;
    wire region_inside = configuration[4:3] == 2'b01 ? tor_inside :
                         configuration[4:3] == 2'b10 ? (na4_first && na4_last) :
                         (napot_first && napot_last);

    assign region_match = configuration[4:3] == 2'b01 ? tor_overlap :
                          configuration[4:3] == 2'b10 ? (na4_first || na4_last) :
                          configuration[4:3] == 2'b11 ? (napot_first || napot_last) : 1'b0;
    assign permitted = region_inside && size != 3 && privilege != 2 &&
        ((privilege == 3 && !configuration[7]) ||
         ((!execute || configuration[2]) && (!read_access || configuration[0]) &&
          (!write_access || configuration[1])));
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
    wire [35:0] first_byte = {2'b00, address};
    wire [35:0] end_byte = first_byte + (36'd1 << size);
    wire [35:0] last_byte = end_byte - 1'b1;
    wire [7:0] region_match;
    wire [7:0] permitted;
    genvar region;
    genvar mask_bit;

    generate
        for (region = 0; region < 8; region = region + 1) begin : regions
            wire [7:0] cfg = configuration[region*8 +: 8];
            wire [31:0] encoded = addresses[region*32 +: 32];
            wire [35:0] top = {2'b00, encoded, 2'b00};
            wire [35:0] bottom;
            if (region == 0) begin : first
                assign bottom = 0;
            end else begin : later
                assign bottom = {2'b00, addresses[(region-1)*32 +: 32], 2'b00};
            end

            wire [35:0] napot_mask;
            assign napot_mask[2:0] = 3'b111;
            assign napot_mask[35] = 1'b0;
            for (mask_bit = 3; mask_bit < 35; mask_bit = mask_bit + 1) begin : prefix
                assign napot_mask[mask_bit] = &encoded[mask_bit-3:0];
            end
            wire [35:0] napot_base = top & ~napot_mask;
            wire napot_first = (first_byte & ~napot_mask) == napot_base;
            wire napot_last = (last_byte & ~napot_mask) == napot_base;
            wire na4_first = first_byte[35:2] == {2'b00, encoded};
            wire na4_last = last_byte[35:2] == {2'b00, encoded};
            wire tor_valid = bottom < top;
            wire tor_overlap = tor_valid && first_byte < top && end_byte > bottom;
            wire tor_inside = first_byte >= bottom && end_byte <= top;

            assign region_match[region] = cfg[4:3] == 2'b01 ? tor_overlap :
                                     cfg[4:3] == 2'b10 ? (na4_first || na4_last) :
                                     cfg[4:3] == 2'b11 ? (napot_first || napot_last) : 1'b0;
            wire region_inside = cfg[4:3] == 2'b01 ? tor_inside :
                          cfg[4:3] == 2'b10 ? (na4_first && na4_last) :
                          (napot_first && napot_last);
            assign permitted[region] = region_inside &&
                ((privilege == 3 && !cfg[7]) ||
                 ((!execute || cfg[2]) && (!read_access || cfg[0]) &&
                  (!write_access || cfg[1])));
        end
    endgenerate

    always @(*) begin
        allowed = privilege == 3;
        found = 0;
        for (entry = 0; entry < 8; entry = entry + 1) begin
            if (!found && region_match[entry]) begin
                found = 1;
                allowed = permitted[entry];
            end
        end

        if (size == 3 || privilege == 2) begin
            allowed = 0;
        end
    end
endmodule
