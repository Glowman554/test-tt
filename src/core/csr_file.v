module CsrFile #(
    parameter ENABLE_MMU = 1,
    parameter ENABLE_PMP = 1
) (
    input clk,
    input reset,
    input csr_valid,
    input csr_commit,
    input [11:0] csr_address,
    input [2:0] csr_operation,
    input [31:0] csr_source,
    input csr_source_zero,
    output reg [31:0] csr_rdata,
    output csr_illegal,
    input system_valid,
    input system_commit,
    input [2:0] system_operation,
    output system_illegal,
    output [31:0] return_pc,
    output context_flush,
    input trap_valid,
    input trap_interrupt,
    input [4:0] trap_cause,
    input [31:0] trap_pc,
    input [31:0] trap_value,
    output trap_ready,
    output [31:0] trap_vector,
    input irq_software,
    input irq_timer,
    input irq_machine,
    input irq_supervisor,
    input [63:0] time_value,
    input retired,
    output reg [1:0] privilege,
    output reg interrupt_pending,
    output reg [4:0] interrupt_cause,
    output [31:0] satp_value,
    output [31:0] status_value,
    output [1:0] data_privilege,
    output [63:0] pmp_configuration,
    output [255:0] pmp_addresses
);
    localparam [31:0] STATUS_MASK = 32'h007e19aa;
    localparam [31:0] SSTATUS_MASK = 32'h000c0122;
    localparam [31:0] IRQ_MASK = 32'h00000aaa;
    localparam [31:0] DELEG_IRQ_MASK = 32'h00000222;
    localparam [31:0] DELEG_EXCEPTION_MASK = 32'h0000b3ff;

    reg [31:0] mstatus;
    reg [31:0] mie;
    reg [31:0] mideleg;
    reg [31:0] medeleg;
    reg [31:0] mtvec;
    reg [31:0] stvec;
    reg [31:0] mepc;
    reg [31:0] sepc;
    reg [31:0] mcause;
    reg [31:0] scause;
    reg [31:0] mtval;
    reg [31:0] stval;
    reg [31:0] mscratch;
    reg [31:0] sscratch;
    reg [31:0] satp;
    reg [31:0] mcounteren;
    reg [31:0] scounteren;
    reg [31:0] mcountinhibit;
    reg [31:0] software_pending;
    reg [63:0] mcycle;
    reg [63:0] minstret;
    reg menvcfg_fiom;
    reg senvcfg_fiom;
    wire [31:0] mip = software_pending |
        (irq_software ? 32'h8 : 0) | (irq_timer ? 32'h80 : 0) |
        (irq_machine ? 32'h800 : 0) | (irq_supervisor ? 32'h200 : 0);

    wire csr_write = csr_operation[1:0] == 1 || !csr_source_zero;
    reg csr_known;

    reg counter_denied;
    reg [31:0] rmw_base;
    reg [31:0] csr_wdata;

    wire write_fire = csr_valid && csr_commit && !csr_illegal && csr_write && !reset;
    wire system_fire = system_valid && system_commit && !system_illegal && !reset;

    wire pmp_known;
    wire [31:0] pmp_read;

    generate if (ENABLE_PMP) begin : with_pmp
    PmpRegisters pmp (
        .clk(clk),
        .reset(reset),
        .address(csr_address),
        .write_enable(write_fire),
        .write_data(csr_wdata),
        .known(pmp_known),
        .read_data(pmp_read),
        .configuration(pmp_configuration),
        .addresses(pmp_addresses)
    );
    end else begin : without_pmp
        assign pmp_known = 1'b0;
        assign pmp_read = 32'd0;
        assign pmp_configuration = 64'd0;
        assign pmp_addresses = 256'd0;
    end endgenerate

    wire delegate_trap = privilege != 3 && (trap_interrupt ? mideleg[trap_cause] : medeleg[trap_cause]);
    wire [31:0] target_vector = delegate_trap ? stvec : mtvec;

    assign trap_ready = !reset;
    assign trap_vector = {target_vector[31:2], 2'b0} + ((trap_interrupt && target_vector[1:0] == 1) ? {25'd0, trap_cause, 2'b0} : 32'd0);
    assign return_pc = system_operation == 1 ? mepc : sepc;

    assign satp_value = ENABLE_MMU ? satp : 32'd0;
    assign status_value = mstatus;
    assign data_privilege = privilege == 3 && mstatus[17] ? mstatus[12:11] : privilege;

    assign context_flush = (write_fire && csr_address == 12'h180) ||
        (system_fire && (system_operation == 1 || system_operation == 2 || system_operation == 4));

    assign csr_illegal = csr_valid && (!csr_known || counter_denied ||
        csr_address[9:8] > privilege ||
        (csr_address[11:10] == 3 && csr_write) ||
        (csr_address == 12'h180 && privilege == 1 && mstatus[20]) ||
        (csr_operation[1:0] == 0));
    assign system_illegal = system_valid &&
        ((system_operation == 1 && privilege != 3) ||
         (system_operation == 2 && (privilege == 0 || (privilege == 1 && mstatus[22]))) ||
         (system_operation == 3 && (privilege == 0 || (privilege != 3 && mstatus[21]))) ||
         (system_operation == 4 && (privilege == 0 || (privilege == 1 && mstatus[20]))) ||
         system_operation == 0 || system_operation > 4);

    always @(*) begin
        csr_rdata = 0;
        csr_known = 1;
        counter_denied = 0;
        case (csr_address)
            12'h100: csr_rdata = mstatus & SSTATUS_MASK;
            12'h104: csr_rdata = mie & mideleg;
            12'h105: csr_rdata = stvec;
            12'h106: csr_rdata = scounteren;
            12'h10a: csr_rdata = {31'd0, senvcfg_fiom};
            12'h140: csr_rdata = sscratch;
            12'h141: csr_rdata = sepc;
            12'h142: csr_rdata = scause;
            12'h143: csr_rdata = stval;
            12'h144: csr_rdata = mip & mideleg;
            12'h180: csr_rdata = ENABLE_MMU ? satp : 32'd0;
            12'h300: csr_rdata = mstatus;
            12'h301: csr_rdata = 32'h40141105;  // fixed RV32 IMAC, S, U
            12'h302: csr_rdata = medeleg;
            12'h303: csr_rdata = mideleg;
            12'h304: csr_rdata = mie;
            12'h305: csr_rdata = mtvec;
            12'h306: csr_rdata = mcounteren;
            12'h30a: csr_rdata = {31'd0, menvcfg_fiom};
            12'h310: csr_rdata = 0;  // mstatush: little-endian, no virtualization
            12'h31a: csr_rdata = 0;  // menvcfgh
            12'h320: csr_rdata = mcountinhibit;
            12'h340: csr_rdata = mscratch;
            12'h341: csr_rdata = mepc;
            12'h342: csr_rdata = mcause;
            12'h343: csr_rdata = mtval;
            12'h344: csr_rdata = mip;
            12'hb00, 12'hc00: csr_rdata = mcycle[31:0];
            12'hb80, 12'hc80: csr_rdata = mcycle[63:32];
            12'hb02, 12'hc02: csr_rdata = minstret[31:0];
            12'hb82, 12'hc82: csr_rdata = minstret[63:32];
            12'hc01: csr_rdata = time_value[31:0];
            12'hc81: csr_rdata = time_value[63:32];
            12'hf11, 12'hf12, 12'hf13, 12'hf14, 12'hf15: csr_rdata = 0;

            default: begin
                csr_known = pmp_known;
                csr_rdata = pmp_read;
            end
        endcase

        if ((csr_address >= 12'hc00 && csr_address <= 12'hc02) || (csr_address >= 12'hc80 && csr_address <= 12'hc82)) begin
            if (privilege != 3 && !mcounteren[csr_address[1:0]]) begin
                counter_denied = 1;
            end

            if (privilege == 0 && !scounteren[csr_address[1:0]]) begin
                counter_denied = 1;
            end
        end


        rmw_base = csr_rdata;
        if (csr_address == 12'h344) begin
            rmw_base = software_pending;
        end

        if (csr_address == 12'h144) begin
            rmw_base = software_pending & mideleg;
        end

        case (csr_operation[1:0])
            1: csr_wdata = csr_source;
            2: csr_wdata = rmw_base | csr_source;
            3: csr_wdata = rmw_base & ~csr_source;
            default: csr_wdata = rmw_base;
        endcase
    end

    wire [31:0] machine_eligible = (privilege != 3 || mstatus[3]) ? (mie & mip & ~mideleg) : 32'd0;
    wire [31:0] supervisor_eligible = (privilege == 0 || (privilege == 1 && mstatus[1])) ? (mie & mip & mideleg) : 32'd0;
    wire [31:0] eligible = machine_eligible != 0 ? machine_eligible : supervisor_eligible;

    always @(*) begin
        interrupt_pending = 1;
        interrupt_cause = 0;
        if (eligible[11]) begin
            interrupt_cause = 11;
        end else if (eligible[3]) begin
            interrupt_cause = 3;
        end else if (eligible[7]) begin
            interrupt_cause = 7;
        end else if (eligible[9]) begin
            interrupt_cause = 9;
        end else if (eligible[1]) begin
            interrupt_cause = 1;
        end else if (eligible[5]) begin
            interrupt_cause = 5;
        end else begin
            interrupt_pending = 0;
        end
    end

    function [31:0] normalize_status(input [31:0] value);
        begin
            normalize_status = value & STATUS_MASK;
            if (value[12:11] == 2) begin
                normalize_status[12:11] = 0;
            end
        end
    endfunction

    function [31:0] normalize_vector(input [31:0] value);
        normalize_vector = {value[31:2], value[1:0] == 1 ? 2'b01 : 2'b00};
    endfunction

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            privilege <= 3;
            mstatus <= 0;
            mie <= 0;
            mideleg <= 0;
            medeleg <= 0;
            mtvec <= 0;
            stvec <= 0;
            mepc <= 0;
            sepc <= 0;
            mcause <= 0;
            scause <= 0;
            mtval <= 0;
            stval <= 0;
            mscratch <= 0;
            sscratch <= 0;
            satp <= 0;
            mcounteren <= 0;
            scounteren <= 0;
            mcountinhibit <= 0;
            software_pending <= 0;
            mcycle <= 0;
            minstret <= 0;
            menvcfg_fiom <= 0;
            senvcfg_fiom <= 0;
        end else begin
            if (!mcountinhibit[0]) begin
                mcycle <= mcycle + 64'd1;
            end

            if (retired && !mcountinhibit[2]) begin
                minstret <= minstret + 64'd1;
            end

            if (write_fire) begin
                case (csr_address)
                    12'h100: mstatus <= normalize_status((mstatus & ~SSTATUS_MASK) | (csr_wdata & SSTATUS_MASK));
                    12'h104: mie <= (mie & ~mideleg) | (csr_wdata & mideleg);
                    12'h105: stvec <= normalize_vector(csr_wdata);
                    12'h106: scounteren <= csr_wdata & 7;
                    12'h10a: senvcfg_fiom <= csr_wdata[0];
                    12'h140: sscratch <= csr_wdata;
                    12'h141: sepc <= {csr_wdata[31:1], 1'b0};
                    12'h142: scause <= csr_wdata;
                    12'h143: stval <= csr_wdata;
                    12'h144: software_pending <= (software_pending & ~(mideleg & 2)) | (csr_wdata & mideleg & 2);
                    12'h180: if (ENABLE_MMU) satp <= csr_wdata & 32'h803fffff;  // ASIDLEN=0
                    12'h300: mstatus <= normalize_status(csr_wdata);
                    12'h302: medeleg <= csr_wdata & DELEG_EXCEPTION_MASK;
                    12'h303: mideleg <= csr_wdata & DELEG_IRQ_MASK;
                    12'h304: mie <= csr_wdata & IRQ_MASK;
                    12'h305: mtvec <= normalize_vector(csr_wdata);
                    12'h306: mcounteren <= csr_wdata & 7;
                    12'h30a: menvcfg_fiom <= csr_wdata[0];
                    12'h320: mcountinhibit <= csr_wdata & 5;
                    12'h340: mscratch <= csr_wdata;
                    12'h341: mepc <= {csr_wdata[31:1], 1'b0};
                    12'h342: mcause <= csr_wdata;
                    12'h343: mtval <= csr_wdata;
                    12'h344: software_pending <= csr_wdata & DELEG_IRQ_MASK;
                    12'hb00: mcycle[31:0] <= csr_wdata;
                    12'hb80: mcycle[63:32] <= csr_wdata;
                    12'hb02: minstret[31:0] <= csr_wdata;
                    12'hb82: minstret[63:32] <= csr_wdata;
                    default: ;
                endcase
            end

            if (trap_valid && trap_ready) begin
                if (delegate_trap) begin
                    sepc <= {trap_pc[31:1], 1'b0};
                    scause <= {trap_interrupt, 26'd0, trap_cause};
                    stval <= trap_value;
                    mstatus[5] <= mstatus[1];
                    mstatus[1] <= 0;
                    mstatus[8] <= privilege == 1;
                    privilege <= 1;
                end else begin
                    mepc <= {trap_pc[31:1], 1'b0};
                    mcause <= {trap_interrupt, 26'd0, trap_cause};
                    mtval <= trap_value;
                    mstatus[7] <= mstatus[3];
                    mstatus[3] <= 0;
                    mstatus[12:11] <= privilege;
                    privilege <= 3;
                end
            end else if (system_fire) begin
                if (system_operation == 1) begin
                    privilege <= mstatus[12:11];
                    mstatus[3] <= mstatus[7];
                    mstatus[7] <= 1;
                    mstatus[12:11] <= 0;
                    if (mstatus[12:11] != 3) begin
                        mstatus[17] <= 0;
                    end
                end else if (system_operation == 2) begin
                    privilege <= mstatus[8] ? 1 : 0;
                    mstatus[1] <= mstatus[5];
                    mstatus[5] <= 1;
                    mstatus[8] <= 0;
                    mstatus[17] <= 0;
                end
            end
        end
    end
endmodule
