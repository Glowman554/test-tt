module ExecutionUnit #(
    parameter [31:0] RESET_PC = 0
) (
    input clk,
    input reset,
    output valid,
    output [33:0] address,
    output write,
    output [31:0] wdata,
    output [3:0] wstrb,
    output [1:0] kind,
    output [31:0] access_address,
    output [1:0] access_size,
    output access_rmw,
    output access_atomic,
    output access_sc,
    output reg sc_reserved_valid,
    output reg [33:0] sc_reserved_address,
    input [33:0] translated_address,
    input sc_success,
    input page_fault,
    input ready,
    input [31:0] rdata,
    input error,
    input [1:0] privilege,
    input clear_reservation,
    input interrupt_pending,
    input [4:0] interrupt_cause,
    output csr_valid,
    output csr_commit,
    output [11:0] csr_address,
    output [2:0] csr_operation,
    output [31:0] csr_source,
    output csr_source_zero,
    input [31:0] csr_rdata,
    input csr_illegal,
    output system_valid,
    output system_commit,
    output [2:0] system_operation,
    input system_illegal,
    input [31:0] return_pc,
    output trap_valid,
    output reg [4:0] trap_cause,
    output reg trap_interrupt,
    output reg [31:0] trap_pc,
    output reg [31:0] trap_value,
    input trap_ready,
    input [31:0] trap_vector,
    output reg retire_valid,
    output reg [31:0] retire_pc,
    output reg [31:0] retire_instruction,
    output reg [4:0] retire_rd,
    output reg [31:0] retire_data,
    output reg [31:0] pc
);
    localparam FETCH = 0;
    localparam EXECUTE = 1;
    localparam MEMORY = 2;
    localparam TRAP = 3;
    localparam MULDIV = 4;
    localparam ATOMIC_READ = 5;
    localparam ATOMIC_WRITE = 6;
    localparam BOUNDARY = 7;
    localparam FETCH_HIGH = 8;

    reg [3:0] state;
    reg [31:0] instruction;
    reg [31:0] raw_instruction;
    reg compressed;
    reg [15:0] fetch_low;

    reg [31:0] registers[0:31];

    wire [4:0] rs1 = instruction[19:15];
    wire [4:0] rs2 = instruction[24:20];

    wire [4:0] rd = instruction[11:7];

    wire [31:0] a = rs1 == 0 ? 0 : registers[rs1];
    wire [31:0] b = rs2 == 0 ? 0 : registers[rs2];

    wire [2:0] funct3 = instruction[14:12];
    wire [6:0] funct7 = instruction[31:25];

    wire [31:0] imm_i = {{20{instruction[31]}}, instruction[31:20]};
    wire [31:0] imm_s = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
    wire [31:0] imm_b = {{19{instruction[31]}}, instruction[31], instruction[7], instruction[30:25], instruction[11:8], 1'b0};
    wire [31:0] imm_u = {instruction[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instruction[31]}}, instruction[31], instruction[19:12], instruction[20], instruction[30:21], 1'b0};

    // These operations are mutually exclusive in EXECUTE, so one adder can
    // serve register arithmetic and effective-address generation.
    wire register_arithmetic = instruction[6:0] == 7'h33;
    wire subtract = register_arithmetic && funct3 == 0 && funct7 == 7'h20;
    wire [31:0] add_operand = register_arithmetic ? b :
                              instruction[6:0] == 7'h23 ? imm_s : imm_i;
    wire [31:0] data_sum = a + (add_operand ^ {32{subtract}}) + subtract;
    wire [31:0] pc_offset = instruction[6:0] == 7'h17 ? imm_u :
                            instruction[6:0] == 7'h6f ? imm_j : imm_b;
    wire [31:0] pc_sum = pc + pc_offset;

    function [31:0] reverse_bits(input [31:0] value);
        integer bit_index;
        begin
            for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1)
                reverse_bits[bit_index] = value[31-bit_index];
        end
    endfunction

    wire shift_left = funct3 == 1;
    wire shift_arithmetic = funct3 == 5 && funct7 == 7'h20;
    wire [4:0] shift_amount = register_arithmetic ? b[4:0] : instruction[24:20];
    wire [31:0] shift_input = shift_left ? reverse_bits(a) : a;
    wire signed [32:0] shift_signed_input = {shift_arithmetic && a[31], shift_input};
    wire [31:0] shift_output = shift_signed_input >>> shift_amount;
    wire [31:0] shift_result = shift_left ? reverse_bits(shift_output) : shift_output;

    reg illegal;
    reg reg_write;
    reg memory_op;
    reg store;
    reg jump;
    reg branch_taken;
    reg ecall;
    reg ebreak;
    reg muldiv_op;
    reg atomic;
    reg csr_op;

    reg [2:0] decoded_system;
    reg [31:0] result;
    reg [31:0] next_pc;

    reg [31:0] effective_address;
    reg [31:0] mem_address;
    reg [31:0] mem_wdata;
    reg [31:0] mem_next_pc;
    reg [3:0] mem_wstrb;
    reg [2:0] mem_funct3;
    reg [4:0] mem_rd;
    reg mem_write;

    reg reservation_valid;

    reg [1:0] previous_privilege;
    reg [33:0] reservation_address;
    reg [31:0] atomic_old;
    reg [4:0] atomic_operation;
    reg [31:0] atomic_updated;

    wire is_lr = instruction[31:27] == 5'b00010;
    wire is_sc = instruction[31:27] == 5'b00011;

    wire [31:0] shifted_read = rdata >> {mem_address[1:0], 3'b000};
    reg [31:0] load_result;

    integer i;

    wire muldiv_done;
    wire [31:0] muldiv_result;

    MulDiv muldiv (
        .clk(clk),
        .reset(reset),
        .start(state == EXECUTE && muldiv_op && !illegal && !reset),
        .operation(funct3),
        .lhs(a),
        .rhs(b),
        .busy(),
        .done(muldiv_done),
        .result(muldiv_result)
    );

    wire [31:0] seq_pc = pc + (compressed ? 32'd2 : 32'd4);
    wire [31:0] fetch_address = state == FETCH_HIGH ? {pc[31:2] + 30'd1, 2'b00} : {pc[31:2], 2'b00};
    wire [15:0] fetch_half = pc[1] ? rdata[31:16] : rdata[15:0];
    wire [31:0] expanded;

    Decompress decompress (
        .c(fetch_half),
        .instruction(expanded)
    );

    wire data_state = state == MEMORY || state == ATOMIC_READ || state == ATOMIC_WRITE;

    assign valid = !reset && ((state == FETCH && !pc[0]) || state == FETCH_HIGH || data_state);
    assign address = {2'b0, (data_state ? {mem_address[31:2], 2'b0} : fetch_address)};

    assign write = (state == MEMORY && mem_write) || state == ATOMIC_WRITE;
    assign wdata = mem_wdata;
    assign wstrb = write ? mem_wstrb : 4'b0;

    assign kind = state == FETCH || state == FETCH_HIGH ? 2'd1 : 2'd0;

    assign access_address = data_state ? mem_address : fetch_address;
    assign access_size = state == MEMORY ? mem_funct3[1:0] : 2'd2;
    assign access_rmw = (state == ATOMIC_READ || state == ATOMIC_WRITE) && atomic_operation != 2 && atomic_operation != 3;
    assign access_atomic = state == ATOMIC_READ || state == ATOMIC_WRITE;
    assign access_sc = state == ATOMIC_WRITE && atomic_operation == 3;

    assign trap_valid = !reset && state == TRAP;
    assign csr_valid = !reset && state == EXECUTE && csr_op;
    assign csr_commit = csr_valid && !csr_illegal;
    assign csr_address = instruction[31:20];
    assign csr_operation = funct3;
    assign csr_source = funct3[2] ? {27'd0, rs1} : a;
    assign csr_source_zero = rs1 == 0;
    assign system_valid = !reset && state == EXECUTE && decoded_system != 0;
    assign system_commit = system_valid && !system_illegal;
    assign system_operation = decoded_system;

    always @(*) begin
        illegal = 0;
        reg_write = 0;
        memory_op = 0;
        store = 0;
        jump = 0;
        branch_taken = 0;
        ecall = 0;
        ebreak = 0;
        muldiv_op = 0;
        atomic = 0;
        csr_op = 0;
        decoded_system = 0;
        result = 0;
        next_pc = seq_pc;
        effective_address = 0;

        case (instruction[6:0])
            7'h37: begin
                reg_write = 1;
                result = imm_u;
            end

            7'h17: begin
                reg_write = 1;
                result = pc_sum;
            end

            7'h6f: begin
                reg_write = 1;
                result = seq_pc;
                next_pc = pc_sum;
                jump = 1;
            end

            7'h67: begin
                if (funct3 != 0) begin
                    illegal = 1;
                end

                reg_write = 1;
                result = seq_pc;
                next_pc = data_sum & 32'hfffffffe;
                jump = 1;
            end

            7'h63: begin
                case (funct3)
                    0: branch_taken = a == b;
                    1: branch_taken = a != b;
                    4: branch_taken = $signed(a) < $signed(b);
                    5: branch_taken = $signed(a) >= $signed(b);
                    6: branch_taken = a < b;
                    7: branch_taken = a >= b;
                    default: illegal = 1;
                endcase

                if (branch_taken) begin
                    next_pc = pc_sum;
                    jump = 1;
                end
            end

            7'h03: begin
                memory_op = 1;
                effective_address = data_sum;
                if (funct3 != 0 && funct3 != 1 && funct3 != 2 && funct3 != 4 && funct3 != 5) begin
                    illegal = 1;
                end
            end

            7'h23: begin
                memory_op = 1;
                store = 1;
                effective_address = data_sum;
                if (funct3 > 2) begin
                    illegal = 1;
                end
            end

            7'h2f: begin
                atomic = 1;
                effective_address = a;
                if (funct3 != 2) begin
                    illegal = 1;
                end

                case (instruction[31:27])
                    0, 1, 3, 4, 8, 12, 16, 20, 24, 28: ;

                    2: begin
                        if (rs2 != 0) begin
                            illegal = 1;
                        end
                    end

                    default: illegal = 1;
                endcase
            end

            7'h13: begin
                reg_write = 1;
                case (funct3)
                    0: result = data_sum;
                    2: result = $signed(a) < $signed(imm_i);
                    3: result = a < imm_i;
                    4: result = a ^ imm_i;
                    6: result = a | imm_i;
                    7: result = a & imm_i;

                    1: begin
                        result = shift_result;
                        if (funct7 != 0) begin
                            illegal = 1;
                        end
                    end

                    5: begin
                        if (funct7 == 0) begin
                            result = shift_result;
                        end else if (funct7 == 7'h20) begin
                            result = shift_result;
                        end else begin
                            illegal = 1;
                        end
                    end
                endcase
            end

            7'h33: begin
                reg_write = 1;
                if (funct7 == 1) begin
                    muldiv_op = 1;
                end else begin
                    case (funct3)
                        0: begin
                            if (funct7 == 0) begin
                                result = data_sum;
                            end else if (funct7 == 7'h20) begin
                                result = data_sum;
                            end else begin
                                illegal = 1;
                            end
                        end

                        1: result = shift_result;
                        2: result = $signed(a) < $signed(b);
                        3: result = a < b;
                        4: result = a ^ b;

                        5: begin
                            if (funct7 == 0) begin
                                result = shift_result;
                            end else if (funct7 == 7'h20) begin
                                result = shift_result;
                            end else begin
                                illegal = 1;
                            end
                        end

                        6: result = a | b;
                        7: result = a & b;
                    endcase

                    if (funct3 != 0 && funct3 != 5 && funct7 != 0) begin
                        illegal = 1;
                    end
                end
            end

            7'h0f: begin
                if (funct3 != 0 && funct3 != 1) begin
                    illegal = 1;
                end
            end

            7'h73: begin
                if (instruction == 32'h00000073) begin
                    ecall = 1;
                end else if (instruction == 32'h00100073) begin
                    ebreak = 1;
                end else if (funct3 == 1 || funct3 == 2 || funct3 == 3 || funct3 == 5 || funct3 == 6 || funct3 == 7) begin
                    csr_op = 1;
                end else if (instruction == 32'h30200073) begin
                    decoded_system = 1;  // MRET
                end else if (instruction == 32'h10200073) begin
                    decoded_system = 2;  // SRET
                end else if (instruction == 32'h10500073) begin
                    decoded_system = 3;  // WFI
                end else if (instruction[31:25] == 7'h09 && funct3 == 0 && rd == 0) begin
                    decoded_system = 4;  // SFENCE.VMA
                end else begin
                    illegal = 1;
                end
            end

            default: illegal = 1;
        endcase
    end

    always @(*) begin
        case (atomic_operation)
            0: atomic_updated = rdata + mem_wdata;
            1: atomic_updated = mem_wdata;
            4: atomic_updated = rdata ^ mem_wdata;
            8: atomic_updated = rdata | mem_wdata;
            12: atomic_updated = rdata & mem_wdata;
            16: atomic_updated = $signed(rdata) < $signed(mem_wdata) ? rdata : mem_wdata;
            20: atomic_updated = $signed(rdata) > $signed(mem_wdata) ? rdata : mem_wdata;
            24: atomic_updated = rdata < mem_wdata ? rdata : mem_wdata;
            28: atomic_updated = rdata > mem_wdata ? rdata : mem_wdata;
            default: atomic_updated = mem_wdata;
        endcase
    end

    always @(*) begin
        case (mem_funct3)
            0: load_result = {{24{shifted_read[7]}}, shifted_read[7:0]};
            1: load_result = {{16{shifted_read[15]}}, shifted_read[15:0]};
            2: load_result = rdata;
            4: load_result = {24'b0, shifted_read[7:0]};
            5: load_result = {16'b0, shifted_read[15:0]};
            default: load_result = 0;
        endcase
    end

    task raise_trap(input [4:0] cause, input [31:0] value);
        begin
            state <= TRAP;
            trap_interrupt <= 0;
            trap_cause <= cause;
            trap_pc <= pc;
            trap_value <= value;
            reservation_valid <= 0;
        end
    endtask

    task retire(input [31:0] new_pc, input wr, input [4:0] dest, input [31:0] value);
        begin
            if (wr && dest != 0) begin
                registers[dest] <= value;
            end

            pc <= new_pc;
            state <= BOUNDARY;
            retire_valid <= 1;
            retire_pc <= pc;
            retire_instruction <= instruction;
            retire_rd <= wr ? dest : 0;
            retire_data <= wr && dest != 0 ? value : 0;
        end
    endtask

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= BOUNDARY;
            pc <= RESET_PC;
            instruction <= 32'h00000013;
            raw_instruction <= 32'h00000013;
            compressed <= 0;
            fetch_low <= 0;
            mem_address <= 0;
            mem_wdata <= 0;
            mem_wstrb <= 0;
            mem_next_pc <= 0;
            mem_rd <= 0;
            mem_funct3 <= 0;
            mem_write <= 0;
            reservation_valid <= 0;
            reservation_address <= 0;
            atomic_old <= 0;
            atomic_operation <= 0;
            previous_privilege <= 3;
            sc_reserved_valid <= 0;
            sc_reserved_address <= 0;
            trap_interrupt <= 0;
            trap_cause <= 0;
            trap_pc <= 0;
            trap_value <= 0;
            retire_valid <= 0;
            retire_pc <= 0;
            retire_instruction <= 0;
            retire_rd <= 0;
            retire_data <= 0;
            for (i = 0; i < 32; i = i + 1) begin
                registers[i] <= 0;
            end
        end else begin
            retire_valid <= 0;
            registers[0] <= 0;

            case (state)
                BOUNDARY: begin
                    if (interrupt_pending) begin
                        state <= TRAP;
                        trap_interrupt <= 1;
                        trap_cause <= interrupt_cause;
                        trap_pc <= pc;
                        trap_value <= 0;
                        reservation_valid <= 0;
                    end else begin
                        state <= FETCH;
                    end
                end

                FETCH: begin
                    if (pc[0]) begin
                        raise_trap(0, pc);
                    end else if (ready) begin
                        if (error) begin
                            raise_trap(page_fault ? 12 : 1, pc);
                        end else if (fetch_half[1:0] != 2'b11) begin
                            instruction <= expanded;
                            raw_instruction <= {16'd0, fetch_half};
                            compressed <= 1;
                            state <= EXECUTE;
                        end else if (pc[1]) begin
                            fetch_low <= fetch_half;
                            state <= FETCH_HIGH;
                        end else begin
                            instruction <= rdata;
                            raw_instruction <= rdata;
                            compressed <= 0;
                            state <= EXECUTE;
                        end
                    end
                end

                FETCH_HIGH: begin
                    if (ready) begin
                        if (error) begin
                            raise_trap(page_fault ? 12 : 1, {pc[31:2] + 30'd1, 2'b00});
                        end else begin
                            instruction <= {rdata[15:0], fetch_low};
                            raw_instruction <= {rdata[15:0], fetch_low};
                            compressed <= 0;
                            state <= EXECUTE;
                        end
                    end
                end

                EXECUTE: begin
                    if (illegal) begin
                        raise_trap(2, raw_instruction);
                    end else if (csr_op && csr_illegal) begin
                        raise_trap(2, raw_instruction);
                    end else if (decoded_system != 0 && system_illegal) begin
                        raise_trap(2, raw_instruction);
                    end else if (csr_op) begin
                        retire(next_pc, 1, rd, csr_rdata);
                    end else if (decoded_system != 0) begin
                        if (decoded_system == 1 || decoded_system == 2) begin
                            reservation_valid <= 0;
                            retire(return_pc, 0, 0, 0);
                        end else begin
                            if (decoded_system == 4) begin
                                reservation_valid <= 0;
                            end

                            retire(next_pc, 0, 0, 0);
                        end
                    end else if (ecall) begin
                        raise_trap(privilege == 0 ? 8 : privilege == 1 ? 9 : 11, 0);
                    end else if (ebreak) begin
                        raise_trap(3, pc);
                    end else if (muldiv_op) begin
                        state <= MULDIV;
                    end else if (atomic) begin
                        if (effective_address[1:0] != 0) begin
                            raise_trap(is_lr ? 4 : 6, effective_address);
                        end else begin
                            mem_address <= effective_address;
                            mem_wdata <= b;
                            mem_wstrb <= 15;
                            mem_rd <= rd;
                            mem_next_pc <= next_pc;
                            atomic_operation <= instruction[31:27];

                            if (is_sc) begin
                                sc_reserved_valid <= reservation_valid;
                                sc_reserved_address <= reservation_address;
                                reservation_valid <= 0;
                                state <= ATOMIC_WRITE;
                            end else begin
                                state <= ATOMIC_READ;
                            end
                        end
                    end else if (memory_op) begin
                        if (store) begin
                            reservation_valid <= 0;
                        end

                        if ((funct3[1:0] == 1 && effective_address[0]) || (funct3[1:0] == 2 && effective_address[1:0] != 0)) begin
                            raise_trap(store ? 6 : 4, effective_address);
                        end else begin
                            mem_address <= effective_address;
                            mem_wdata <= b << {effective_address[1:0], 3'b0};
                            mem_wstrb <= (funct3 == 0 ? 4'b0001 : funct3 == 1 ? 4'b0011 : 4'b1111) << effective_address[1:0];
                            mem_funct3 <= funct3;
                            mem_rd <= rd;
                            mem_write <= store;
                            mem_next_pc <= next_pc;
                            state <= MEMORY;
                        end
                    end else begin
                        retire(next_pc, reg_write, rd, result);
                    end
                end

                MEMORY: begin
                    if (ready) begin
                        if (error) begin
                            raise_trap(page_fault ? (mem_write ? 15 : 13) : (mem_write ? 7 : 5), mem_address);
                        end else begin
                            retire(mem_next_pc, !mem_write, mem_rd, load_result);
                        end
                    end
                end

                TRAP: begin
                    if (trap_ready) begin
                        pc <= trap_vector;
                        state <= BOUNDARY;
                    end
                end

                MULDIV: begin
                    if (muldiv_done) begin
                        retire(seq_pc, 1, rd, muldiv_result);
                    end
                end

                ATOMIC_READ: begin
                    if (ready) begin
                        if (error) begin
                            raise_trap(page_fault ? (atomic_operation == 2 ? 13 : 15) : (atomic_operation == 2 ? 5 : 7), mem_address);
                        end else if (atomic_operation == 2) begin
                            reservation_valid <= 1;
                            reservation_address <= {translated_address[33:2], 2'b0};
                            retire(mem_next_pc, 1, mem_rd, rdata);
                        end else begin
                            reservation_valid <= 0;
                            atomic_old <= rdata;
                            mem_wdata <= atomic_updated;
                            state <= ATOMIC_WRITE;
                        end
                    end
                end

                ATOMIC_WRITE: begin
                    if (ready) begin
                        if (error) begin
                            raise_trap(page_fault ? 15 : 7, mem_address);
                        end else begin
                            retire(mem_next_pc, 1, mem_rd, atomic_operation == 3 ? (sc_success ? 0 : 1) : atomic_old);
                        end
                    end
                end
            endcase

            previous_privilege <= privilege;
            if (clear_reservation || privilege != previous_privilege) begin
                reservation_valid <= 0;
            end
        end
    end
endmodule
