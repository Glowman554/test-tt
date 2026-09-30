module Mmu #(
    parameter TLB_ENTRIES = 32
) (
    input clk,
    input reset,
    input tlb_flush,
    input req_valid,
    input [31:0] req_address,
    input [1:0] req_size,
    input req_write,
    input [31:0] req_wdata,
    input [3:0] req_wstrb,
    input [1:0] req_kind,
    input req_rmw,
    input req_atomic,
    input req_sc,
    input sc_reserved_valid,
    input [33:0] sc_reserved_address,
    input [1:0] req_privilege,
    input [31:0] satp,
    input sum,
    input mxr,
    input [63:0] pmp_configuration,
    input [255:0] pmp_addresses,
    output req_ready,
    output reg [31:0] req_rdata,
    output reg req_error,
    output reg req_page_fault,
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
    localparam IDLE = 0;
    localparam WALK_CHECK = 1;
    localparam WALK = 2;
    localparam ACCESS_CHECK = 3;
    localparam ACCESS = 4;
    localparam RESPONSE = 5;
    localparam TLB_LOOKUP = 6;

    reg [2:0] state;
    reg [31:0] va;
    reg [31:0] data;
    reg [33:0] pa;
    reg [33:0] pte_address;
    reg [33:0] reserved_address;
    reg [1:0] size;
    reg [1:0] mode;
    reg [1:0] access_kind;
    reg [3:0] strobes;

    reg store;
    reg rmw;
    reg atomic;
    reg sc;
    reg reserved_valid;
    reg permit_sum;
    reg permit_mxr;
    reg level;

    wire fetch = access_kind == 1;
    wire needs_write = store || rmw || sc;
    wire leaf = rdata[1] || rdata[3];
    wire pte_invalid = !rdata[0] || (!rdata[1] && rdata[2]);

    function page_denied(input [7:0] flags, input [1:0] privilege_mode, input instruction_access, input write_needed, input read_needed,
                         input allow_user_data, input allow_execute_read);
        begin
            page_denied = (privilege_mode == 0 && !flags[4]) ||
                (privilege_mode == 1 && flags[4] && (instruction_access || !allow_user_data)) ||
                (instruction_access ? !flags[3] :
                    ((write_needed && !flags[2]) ||
                     (read_needed && !(flags[1] || (allow_execute_read && flags[3]))))) ||
                !flags[6] || (write_needed && !flags[7]);
        end
    endfunction

    wire leaf_fault = page_denied(rdata[7:0], mode, fetch, needs_write, !store || rmw, permit_sum, permit_mxr) ||
        (level && rdata[19:10] != 0);

    localparam TLB_STORAGE = TLB_ENTRIES > 0 ? TLB_ENTRIES : 1;
    localparam TLB_INDEX_BITS = TLB_ENTRIES > 1 ? $clog2(TLB_ENTRIES) : 1;
    localparam [31:0] TLB_LAST_INDEX = TLB_STORAGE - 1;

    (* ram_style = "block", syn_ramstyle = "block_ram" *) reg [63:0] tlb_mem[0:TLB_STORAGE-1];
    reg [63:0] tlb_record;
    reg [13:0] tlb_generation;
    reg tlb_clearing;
    reg [TLB_INDEX_BITS-1:0] tlb_clear_index;

    reg [31:0] cached_satp;
    reg [31:0] walk_satp;
    reg discard_fill;
    wire invalidate = tlb_flush || cached_satp != satp;

    function [TLB_INDEX_BITS-1:0] cache_index(input [19:0] vpn);
        reg [31:0] index_value;
        begin
            index_value = {12'd0, vpn} % TLB_STORAGE;
            cache_index = index_value[TLB_INDEX_BITS-1:0];
        end
    endfunction

    wire [TLB_INDEX_BITS-1:0] lookup_index = cache_index(req_address[31:12]);
    wire [TLB_INDEX_BITS-1:0] fill_index = cache_index(va[31:12]);
    wire [21:0] leaf_ppn = level ? {rdata[31:20], va[21:12]} : rdata[31:10];
    wire fill = TLB_ENTRIES > 0 && state == WALK && ready && !error &&
        !pte_invalid && leaf && !leaf_fault && !invalidate &&
        !discard_fill && !tlb_clearing && walk_satp == satp;

    always @(posedge clk) begin
        if (!reset && !tlb_clearing && state == IDLE && req_valid && TLB_ENTRIES > 0) begin
            tlb_record <= tlb_mem[lookup_index];
        end
        if (!reset && tlb_clearing) begin
            tlb_mem[tlb_clear_index] <= 64'd0;
        end else if (!reset && fill) begin
            tlb_mem[fill_index] <= {tlb_generation, va[31:12], leaf_ppn, rdata[7:0]};
        end
    end

    wire tlb_hit = TLB_ENTRIES > 0 && !tlb_clearing && !invalidate &&
        !discard_fill && walk_satp == satp &&
        tlb_record[63:50] == tlb_generation && tlb_record[49:30] == va[31:12];
    wire [33:0] hit_address = {tlb_record[29:8], va[11:0]};
    wire hit_denied = page_denied(tlb_record[7:0], mode, fetch, needs_write,
                                 !store || rmw, permit_sum, permit_mxr);

    wire pmp_allowed;

    function is_ram(input [33:0] a);
        is_ram = a[33:32] == 0 && a >= 34'h040000000 && a < 34'h041000000;
    endfunction

    wire walk_denied = !pmp_allowed || !is_ram(pte_address);
    wire access_denied = !pmp_allowed || (atomic && !is_ram(pa));
    wire sc_failed = sc && (!reserved_valid || reserved_address != {pa[33:2], 2'b0});

    PmpCheck protection (
        .configuration(pmp_configuration),
        .addresses(pmp_addresses),
        .address(state == WALK_CHECK ? pte_address : pa),
        .size(state == WALK_CHECK ? 2'd2 : size),
        .privilege(state == WALK_CHECK ? 2'd1 : mode),
        .execute(state != WALK_CHECK && fetch),
        .read_access(state == WALK_CHECK || (!fetch && (!store || rmw))),
        .write_access(state != WALK_CHECK && needs_write),
        .allowed(pmp_allowed)
    );

    assign req_ready = !reset && state == RESPONSE && req_valid;
    assign translated_address = pa;
    assign valid = !reset && (state == WALK || state == ACCESS);
    assign address = state == WALK ? pte_address : {pa[33:2], 2'b0};
    assign write = state == ACCESS && store;
    assign wdata = data;
    assign wstrb = write ? strobes : 4'd0;
    assign kind = state == WALK ? 2'd2 : access_kind;

    task fault(input page);
        begin
            req_error <= 1;
            req_page_fault <= page;
            sc_success <= 0;
            state <= RESPONSE;
        end
    endtask

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            va <= 0;
            pa <= 0;
            data <= 0;
            size <= 0;
            mode <= 3;
            pte_address <= 0;
            reserved_address <= 0;
            reserved_valid <= 0;
            access_kind <= 0;
            strobes <= 0;
            store <= 0;
            rmw <= 0;
            atomic <= 0;
            sc <= 0;
            permit_sum <= 0;
            permit_mxr <= 0;
            level <= 1;
            req_rdata <= 0;
            req_error <= 0;
            req_page_fault <= 0;
            sc_success <= 0;
            tlb_generation <= 14'd1;
            tlb_clearing <= TLB_ENTRIES > 0;
            tlb_clear_index <= 0;
            cached_satp <= 0;
            walk_satp <= 0;
            discard_fill <= 0;
        end else begin
            cached_satp <= satp;

            if (tlb_clearing) begin
                if (tlb_clear_index == TLB_LAST_INDEX[TLB_INDEX_BITS-1:0]) begin
                    tlb_clearing <= 0;
                    tlb_clear_index <= 0;
                end else begin
                    tlb_clear_index <= tlb_clear_index + 1'b1;
                end
            end

            if (invalidate) begin
                if (TLB_ENTRIES > 0 && !tlb_clearing) begin
                    if (&tlb_generation) begin
                        tlb_generation <= 14'd1;
                        tlb_clearing <= 1;
                        tlb_clear_index <= 0;
                    end else begin
                        tlb_generation <= tlb_generation + 1'b1;
                    end
                end
                if (state != IDLE) begin
                    discard_fill <= 1;
                end
            end

            case (state)
                IDLE: begin
                    if (req_valid && !tlb_clearing) begin
                        va <= req_address;
                        size <= req_size;
                        store <= req_write;
                        data <= req_wdata;
                        strobes <= req_wstrb;
                        access_kind <= req_kind;
                        rmw <= req_rmw;
                        atomic <= req_atomic;
                        sc <= req_sc;
                        reserved_valid <= sc_reserved_valid;
                        reserved_address <= sc_reserved_address;
                        walk_satp <= satp;
                        discard_fill <= 0;
                        mode <= req_privilege;
                        permit_sum <= sum;
                        permit_mxr <= mxr;
                        req_rdata <= 0;
                        req_error <= 0;
                        req_page_fault <= 0;
                        sc_success <= 0;

                        if (req_privilege == 3 || !satp[31]) begin
                            pa <= {2'd0, req_address};
                            state <= ACCESS_CHECK;
                        end else if (TLB_ENTRIES > 0) begin
                            state <= TLB_LOOKUP;
                        end else begin
                            pte_address <= {satp[21:0], 12'd0} + {22'd0, req_address[31:22], 2'd0};
                            level <= 1;
                            state <= WALK_CHECK;
                        end
                    end
                end

                TLB_LOOKUP: begin
                    if (tlb_hit) begin
                        pa <= hit_address;
                        if (hit_denied) begin
                            fault(1);
                        end else begin
                            state <= ACCESS_CHECK;
                        end
                    end else begin
                        pte_address <= {walk_satp[21:0], 12'd0} + {22'd0, va[31:22], 2'd0};
                        level <= 1;
                        state <= WALK_CHECK;
                    end
                end

                WALK_CHECK: begin
                    if (walk_denied) begin
                        fault(0);
                    end else begin
                        state <= WALK;
                    end
                end

                WALK: begin
                    if (ready) begin
                        if (error) begin
                            fault(0);
                        end else if (pte_invalid) begin
                            fault(1);
                        end else if (leaf) begin
                            if (leaf_fault) begin
                                fault(1);
                            end else begin
                                pa <= level ? {rdata[31:20], va[21:0]} : {rdata[31:10], va[11:0]};
                                state <= ACCESS_CHECK;
                            end
                        end else if (!level || rdata[7:6] != 0 || rdata[4]) begin
                            fault(1);
                        end else begin
                            pte_address <= {rdata[31:10], 12'd0} + {22'd0, va[21:12], 2'd0};
                            level <= 0;
                            state <= WALK_CHECK;
                        end
                    end
                end

                ACCESS_CHECK: begin
                    if (access_denied) begin
                        fault(0);
                    end else if (sc_failed) begin
                        sc_success <= 0;
                        state <= RESPONSE;
                    end else begin
                        state <= ACCESS;
                    end
                end

                ACCESS: begin
                    if (ready) begin
                        if (error) begin
                            fault(0);
                        end else begin
                            req_rdata <= rdata;
                            sc_success <= sc;
                            state <= RESPONSE;
                        end
                    end
                end

                RESPONSE: begin
                    if (req_valid) begin
                        state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
