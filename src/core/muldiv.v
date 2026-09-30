module MulDiv (
    input clk,
    input reset,
    input start,
    input [2:0] operation,
    input [31:0] lhs,
    input [31:0] rhs,
    output reg busy,
    output reg done,
    output reg [31:0] result
);
    reg [2:0] op;
    reg [5:0] count;

    reg negate_product;
    reg negate_quotient;
    reg negate_remainder;

    reg [63:0] accumulator;
    reg [63:0] multiplicand;
    reg [31:0] multiplier;
    reg [31:0] dividend;
    reg [31:0] divisor;
    reg [31:0] quotient;
    reg [32:0] remainder;

    wire signed_lhs = operation == 1 || operation == 2 || operation == 4 || operation == 6;
    wire signed_rhs = operation == 1 || operation == 4 || operation == 6;

    wire [31:0] abs_lhs = signed_lhs && lhs[31] ? (~lhs + 32'd1) : lhs;
    wire [31:0] abs_rhs = signed_rhs && rhs[31] ? (~rhs + 32'd1) : rhs;
    wire [63:0] sum = accumulator + (multiplier[0] ? multiplicand : 64'd0);
    wire [63:0] product = negate_product ? (~sum + 64'd1) : sum;
    wire [32:0] shifted_remainder = {remainder[31:0], dividend[31]};

    wire subtract = shifted_remainder >= {1'b0, divisor};

    wire [32:0] next_remainder = subtract ? shifted_remainder - {1'b0, divisor} : shifted_remainder;
    wire [31:0] next_quotient = {quotient[30:0], subtract};
    wire [31:0] signed_quotient = negate_quotient ? (~next_quotient + 32'd1) : next_quotient;
    wire [31:0] signed_remainder = negate_remainder ? (~next_remainder[31:0] + 32'd1) : next_remainder[31:0];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            busy <= 0;
            done <= 0;
            result <= 0;
            op <= 0;
            count <= 0;
            negate_product <= 0;
            negate_quotient <= 0;
            negate_remainder <= 0;
            accumulator <= 0;
            multiplicand <= 0;
            multiplier <= 0;
            dividend <= 0;
            divisor <= 0;
            quotient <= 0;
            remainder <= 0;
        end else begin
            done <= 0;
            if (start && !busy) begin
                op <= operation;
                count <= 0;
                negate_product <= (signed_lhs && lhs[31]) ^ (signed_rhs && rhs[31]);
                negate_quotient <= signed_lhs && (lhs[31] ^ rhs[31]);
                negate_remainder <= signed_lhs && lhs[31];
                accumulator <= 0;
                multiplicand <= {32'd0, abs_lhs};
                multiplier <= abs_rhs;
                dividend <= abs_lhs;
                divisor <= abs_rhs;
                quotient <= 0;
                remainder <= 0;
                if (operation[2] && rhs == 0) begin
                    result <= operation[1] ? lhs : 32'hffffffff;
                    done <= 1;
                end else begin
                    busy <= 1;
                end
            end else if (busy) begin
                count <= count + 1;
                if (!op[2]) begin
                    accumulator <= sum;
                    multiplicand <= multiplicand << 1;
                    multiplier <= multiplier >> 1;
                    if (count == 31) begin
                        result <= op == 0 ? product[31:0] : product[63:32];
                    end
                end else begin
                    remainder <= next_remainder;
                    quotient <= next_quotient;
                    dividend <= dividend << 1;
                    if (count == 31) begin
                        result <= op[1] ? signed_remainder : signed_quotient;
                    end
                end
                if (count == 31) begin
                    busy <= 0;
                    done <= 1;
                end
            end
        end
    end
endmodule
