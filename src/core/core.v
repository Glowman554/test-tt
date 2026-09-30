module RiscV #(
    parameter [31:0] RESET_PC = 0,
    parameter TLB_ENTRIES = 32,
    parameter ENABLE_MMU = 1,
    parameter ENABLE_PMP = 1
) (
    input clk,
    input reset,
    output valid,
    output [33:0] address,
    output write,
    output [31:0] wdata,
    output [3:0] wstrb,
    output [1:0] kind,
    input ready,
    input [31:0] rdata,
    input error,
    input irq_software,
    input irq_timer,
    input irq_machine,
    input irq_supervisor,
    input [63:0] time_value,
    output [1:0] privilege,
    output [1:0] data_privilege,
    output [31:0] satp_value,
    output [31:0] status_value,
    output retire_valid,
    output [31:0] retire_pc,
    output [31:0] retire_instruction,
    output [4:0] retire_rd,
    output [31:0] retire_data,
    output [31:0] pc,
    output trap_valid,
    output trap_interrupt,
    output [4:0] trap_cause,
    output [31:0] trap_pc,
    output [31:0] trap_value
);
    wire clear_reservation;
    wire interrupt_pending;
    wire csr_valid;
    wire csr_commit;
    wire csr_source_zero;
    wire csr_illegal;
    wire system_valid;
    wire system_commit;
    wire system_illegal;
    wire trap_ready;
    wire [4:0] interrupt_cause;
    wire [11:0] csr_address;
    wire [2:0] csr_operation;
    wire [2:0] system_operation;
    wire [31:0] csr_source;
    wire [31:0] csr_rdata;
    wire [31:0] return_pc;
    wire [31:0] trap_vector;
    wire [63:0] pmp_configuration;
    wire [255:0] pmp_addresses;
    wire engine_valid;
    wire engine_ready;
    wire engine_error;
    wire engine_page_fault;
    wire access_rmw;
    wire access_atomic;
    wire access_sc;
    wire [31:0] access_address;
    wire [1:0] access_size;
    wire [33:0] engine_address;
    wire [33:0] translated_address;
    wire [33:0] sc_reserved_address;
    wire [31:0] engine_rdata;
    wire [31:0] engine_wdata;
    wire [3:0] engine_wstrb;
    wire [1:0] engine_kind;
    wire engine_write;
    wire sc_reserved_valid;
    wire sc_success;

    wire csr_writes = csr_operation[1:0] == 1 || !csr_source_zero;

    wire translation_flush = (system_commit && system_operation == 4) ||
        (csr_commit && csr_writes &&
            (csr_address == 12'h180 || csr_address == 12'h3a0 || csr_address == 12'h3a1 ||
             (csr_address >= 12'h3b0 && csr_address <= 12'h3b7)));

    generate if (ENABLE_MMU) begin : translated_memory
    Mmu #(
        .TLB_ENTRIES(TLB_ENTRIES),
        .MEM_WORDS(0),
        .ENABLE_PMP(ENABLE_PMP)
    ) memory (
        .clk(clk),
        .reset(reset),
        .tlb_flush(translation_flush),
        .req_valid(engine_valid),
        .req_address(access_address),
        .req_size(access_size),
        .req_write(engine_write),
        .req_wdata(engine_wdata),
        .req_wstrb(engine_wstrb),
        .req_kind(engine_kind),
        .req_rmw(access_rmw),
        .req_atomic(access_atomic),
        .req_sc(access_sc),
        .sc_reserved_valid(sc_reserved_valid),
        .sc_reserved_address(sc_reserved_address),
        .req_privilege(engine_kind == 1 ? privilege : data_privilege),
        .satp(satp_value),
        .sum(status_value[18]),
        .mxr(status_value[19]),
        .pmp_configuration(pmp_configuration),
        .pmp_addresses(pmp_addresses),
        .req_ready(engine_ready),
        .req_rdata(engine_rdata),
        .req_error(engine_error),
        .req_page_fault(engine_page_fault),
        .sc_success(sc_success),
        .translated_address(translated_address),
        .valid(valid),
        .address(address),
        .write(write),
        .wdata(wdata),
        .wstrb(wstrb),
        .kind(kind),
        .ready(ready),
        .rdata(rdata),
        .error(error)
    );
    end else begin : direct_memory
    BareMemory memory (
        .clk(clk), .reset(reset), .req_valid(engine_valid),
        .req_address(access_address),
        .req_write(engine_write), .req_wdata(engine_wdata),
        .req_wstrb(engine_wstrb), .req_kind(engine_kind),
        .req_atomic(access_atomic),
        .req_sc(access_sc), .sc_reserved_valid(sc_reserved_valid),
        .sc_reserved_address(sc_reserved_address),
        .req_ready(engine_ready), .req_rdata(engine_rdata),
        .req_error(engine_error), .req_page_fault(engine_page_fault),
        .sc_success(sc_success), .translated_address(translated_address),
        .valid(valid), .address(address), .write(write),
        .wdata(wdata), .wstrb(wstrb), .kind(kind),
        .ready(ready), .rdata(rdata), .error(error)
    );
    end endgenerate

    ExecutionUnit #(
        .RESET_PC(RESET_PC)
    ) engine (
        .valid(engine_valid),
        .address(engine_address),
        .write(engine_write),
        .wdata(engine_wdata),
        .wstrb(engine_wstrb),
        .kind(engine_kind),
        .ready(engine_ready),
        .rdata(engine_rdata),
        .error(engine_error),
        .page_fault(engine_page_fault),
        .clk(clk),
        .reset(reset),
        .access_address(access_address),
        .access_size(access_size),
        .access_rmw(access_rmw),
        .access_atomic(access_atomic),
        .access_sc(access_sc),
        .sc_reserved_valid(sc_reserved_valid),
        .sc_reserved_address(sc_reserved_address),
        .translated_address(translated_address),
        .sc_success(sc_success),
        .privilege(privilege),
        .clear_reservation(clear_reservation),
        .interrupt_pending(interrupt_pending),
        .interrupt_cause(interrupt_cause),
        .csr_valid(csr_valid),
        .csr_commit(csr_commit),
        .csr_address(csr_address),
        .csr_operation(csr_operation),
        .csr_source(csr_source),
        .csr_source_zero(csr_source_zero),
        .csr_rdata(csr_rdata),
        .csr_illegal(csr_illegal),
        .system_valid(system_valid),
        .system_commit(system_commit),
        .system_operation(system_operation),
        .system_illegal(system_illegal),
        .return_pc(return_pc),
        .trap_valid(trap_valid),
        .trap_cause(trap_cause),
        .trap_interrupt(trap_interrupt),
        .trap_pc(trap_pc),
        .trap_value(trap_value),
        .trap_ready(trap_ready),
        .trap_vector(trap_vector),
        .retire_valid(retire_valid),
        .retire_pc(retire_pc),
        .retire_instruction(retire_instruction),
        .retire_rd(retire_rd),
        .retire_data(retire_data),
        .pc(pc)
    );

    CsrFile #(.ENABLE_MMU(ENABLE_MMU), .ENABLE_PMP(ENABLE_PMP)) control (
        .clk(clk),
        .reset(reset),
        .csr_valid(csr_valid),
        .csr_commit(csr_commit),
        .csr_address(csr_address),
        .csr_operation(csr_operation),
        .csr_source(csr_source),
        .csr_source_zero(csr_source_zero),
        .csr_rdata(csr_rdata),
        .csr_illegal(csr_illegal),
        .system_valid(system_valid),
        .system_commit(system_commit),
        .system_operation(system_operation),
        .system_illegal(system_illegal),
        .return_pc(return_pc),
        .context_flush(clear_reservation),
        .trap_valid(trap_valid),
        .trap_interrupt(trap_interrupt),
        .trap_cause(trap_cause),
        .trap_pc(trap_pc),
        .trap_value(trap_value),
        .trap_ready(trap_ready),
        .trap_vector(trap_vector),
        .irq_software(irq_software),
        .irq_timer(irq_timer),
        .irq_machine(irq_machine),
        .irq_supervisor(irq_supervisor),
        .time_value(time_value),
        .retired(retire_valid),
        .privilege(privilege),
        .interrupt_pending(interrupt_pending),
        .interrupt_cause(interrupt_cause),
        .satp_value(satp_value),
        .status_value(status_value),
        .data_privilege(data_privilege),
        .pmp_configuration(pmp_configuration),
        .pmp_addresses(pmp_addresses)
    );
endmodule
