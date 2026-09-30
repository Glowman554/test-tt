`timescale 1ns/1ps
module mmu_tlb_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1;
    reg req_valid = 0;
    reg tlb_flush = 0;
    wire req_ready;
    wire [31:0] req_rdata;
    wire req_error, req_page_fault;
    wire valid;
    wire [33:0] address;
    wire [1:0] kind;
    integer walks = 0;
    integer accesses = 0;

    Mmu #(.TLB_ENTRIES(32)) dut (
        .clk(clk), .reset(reset), .tlb_flush(tlb_flush),
        .req_valid(req_valid), .req_address(32'h10001000), .req_size(2'd2),
        .req_write(1'b0), .req_wdata(32'd0), .req_wstrb(4'd0),
        .req_kind(2'd0), .req_rmw(1'b0), .req_atomic(1'b0),
        .req_sc(1'b0), .sc_reserved_valid(1'b0), .sc_reserved_address(34'd0),
        .req_privilege(2'd1), .satp(32'h80040001), .sum(1'b0), .mxr(1'b0),
        .pmp_configuration(64'h1f),
        .pmp_addresses({224'd0, 32'hffffffff}),
        .req_ready(req_ready), .req_rdata(req_rdata),
        .req_error(req_error), .req_page_fault(req_page_fault),
        .sc_success(), .translated_address(),
        .valid(valid), .address(address), .write(), .wdata(),
        .wstrb(), .kind(kind), .ready(valid),
        .rdata(kind == 2 ? 32'h100000cf : 32'hdeadbeef), .error(1'b0)
    );

    always @(posedge clk) begin
        if (!reset && valid) begin
            if (kind == 2) begin
                walks = walks + 1;
                if (address != 34'h040001100)
                    $fatal(1, "unexpected page table address %h", address);
            end else begin
                accesses = accesses + 1;
                if (address != 34'h040001000)
                    $fatal(1, "unexpected translated address %h", address);
            end
        end
    end

    task request;
        integer cycles;
        begin
            @(negedge clk);
            req_valid = 1;
            cycles = 0;
            while (!req_ready && cycles < 100) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (!req_ready || req_error || req_page_fault || req_rdata != 32'hdeadbeef)
                $fatal(1, "MMU request failed after %0d cycles: ready=%b error=%b page=%b data=%h",
                       cycles, req_ready, req_error, req_page_fault, req_rdata);
            req_valid = 0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
        repeat (35) @(negedge clk); // initial TLB clear
        request();
        if (walks != 1 || accesses != 1)
            $fatal(1, "first request did not walk: walks=%0d accesses=%0d", walks, accesses);
        request();
        if (walks != 1 || accesses != 2)
            $fatal(1, "TLB hit was lost: walks=%0d accesses=%0d", walks, accesses);
        @(negedge clk);
        tlb_flush = 1;
        @(negedge clk);
        tlb_flush = 0;
        request();
        if (walks != 2 || accesses != 3)
            $fatal(1, "TLB flush failed: walks=%0d accesses=%0d", walks, accesses);
        $display("mmu_tlb_tb PASS: walk, hit, flush");
        $finish;
    end
endmodule
