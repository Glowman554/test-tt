module PmpCheckReference (
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
