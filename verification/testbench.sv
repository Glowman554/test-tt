`timescale 1ns / 1ps
module sim;
    localparam [31:0] RAM_BASE = 32'h40000000;
    localparam RAM_WORDS = 4 * 1024 * 1024;
    localparam [31:0] SIG_ADDRESS = 32'h80000004;

    reg clk = 0;
    reg reset = 1;

    always #5 clk = !clk;

    wire valid;
    wire write;
    wire ready;
    wire error;
    wire [33:0] address;
    wire [31:0] wdata;
    wire [31:0] rdata;
    wire [3:0] wstrb;
    wire [1:0] kind;
    wire irq_machine;
    wire irq_supervisor;
    wire irq_software;
    wire irq_timer;
    wire [63:0] time_value;
    wire retire_valid;
    wire [31:0] retire_pc;
    wire [31:0] retire_instruction;
    wire [4:0] retire_rd;
    wire [31:0] retire_data;
    wire [1:0] privilege;
    wire trap_valid;
    wire trap_interrupt;
    wire [4:0] trap_cause;
    wire [31:0] trap_pc;
    wire [31:0] trap_value;

    reg [31:0] sig_pending;

    RiscV #(
        .RESET_PC(RAM_BASE)
    ) cpu (
        .clk(clk),
        .reset(reset),
        .valid(valid),
        .address(address),
        .write(write),
        .wdata(wdata),
        .wstrb(wstrb),
        .kind(kind),
        .ready(ready),
        .rdata(rdata),
        .error(error),
        .irq_machine(irq_machine || sig_pending[11]),
        .irq_supervisor(irq_supervisor || sig_pending[9]),
        .irq_software(irq_software),
        .irq_timer(irq_timer),
        .time_value(time_value),
        .privilege(privilege),
        .data_privilege(),
        .satp_value(),
        .status_value(),
        .retire_valid(retire_valid),
        .retire_pc(retire_pc),
        .retire_instruction(retire_instruction),
        .retire_rd(retire_rd),
        .retire_data(retire_data),
        .pc(),
        .trap_valid(trap_valid),
        .trap_interrupt(trap_interrupt),
        .trap_cause(trap_cause),
        .trap_pc(trap_pc),
        .trap_value(trap_value)
    );

    reg [31:0] ram[0:RAM_WORDS-1];
    reg bus_pending;
    wire [31:0] bus_address = address[31:0];
    wire ram_hit = address[33:32] == 0 &&
        bus_address >= RAM_BASE && bus_address < RAM_BASE + RAM_WORDS * 4;
    wire clint_hit = address[33:32] == 0 &&
        bus_address >= 32'h02000000 && bus_address < 32'h02010000;
    wire plic_hit = address[33:32] == 0 &&
        bus_address >= 32'h0c000000 && bus_address < 32'h10000000;
    wire sig_hit = address == {2'b00, SIG_ADDRESS};
    wire [21:0] ram_index = bus_address[23:2];
    wire [31:0] clint_rdata, plic_rdata;
    wire bus_commit = valid && ready && !error;
    wire ram_commit = bus_commit && ram_hit && write;
    integer lane;

    assign ready = valid && bus_pending;
    assign error = valid && !(ram_hit || clint_hit || plic_hit || sig_hit);
    assign rdata = ram_hit ? ram[ram_index] :
                   clint_hit ? clint_rdata :
                   plic_hit ? plic_rdata : 32'd0;

    Clint clint (
        .clk(clk), .reset(reset), .address(bus_address),
        .write_data(wdata), .write_mask(wstrb),
        .write_enable(bus_commit && write && clint_hit),
        .read_data(clint_rdata), .irq_software(irq_software),
        .irq_timer(irq_timer), .time_value(time_value)
    );

    Plic #(.NUM_SOURCES(1)) plic (
        .clk(clk), .reset(reset), .irq_sources(1'b0),
        .address(bus_address), .write_data(wdata), .write_mask(wstrb),
        .write_enable(bus_commit && write && plic_hit),
        .read_commit(bus_commit && !write && plic_hit),
        .read_data(plic_rdata), .irq_machine(irq_machine),
        .irq_supervisor(irq_supervisor)
    );

    always @(posedge clk) begin
        if (reset || ready) begin
            bus_pending <= 0;
        end else if (valid) begin
            bus_pending <= 1;
        end

        if (ram_commit) begin
            for (lane = 0; lane < 4; lane = lane + 1) begin
                if (wstrb[lane])
                    ram[ram_index][lane*8 +: 8] <= wdata[lane*8 +: 8];
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            sig_pending <= 0;
        end else if (bus_commit && write && sig_hit) begin
            if (wdata[31]) begin
                sig_pending <= sig_pending | (wdata & 32'h00000a00);
            end else begin
                sig_pending <= sig_pending & ~(wdata & 32'h00000a00);
            end
        end
    end

    reg [4095:0] image;
    reg [31:0] tohost;
    reg [31:0] tohost_value;
    reg [63:0] cycles;
    reg [63:0] timeout;
    reg [63:0] retired;

    initial begin
        if (!$value$plusargs("image=%s", image)) begin
            $display("ARCH_TB: missing +image=<hex>");
            $finish;
        end

        if (!$value$plusargs("tohost=%h", tohost)) begin
            $display("ARCH_TB: missing +tohost=<hex address>");
            $finish;
        end

        if (!$value$plusargs("timeout=%d", timeout)) begin
            timeout = 20000000;
        end

        $readmemh(image, ram);
        tohost_value = 0;
        cycles = 0;
        retired = 0;
        repeat (8) @(posedge clk);
        reset = 0;
    end

    always @(posedge clk) begin
        if (!reset) begin
            cycles <= cycles + 1;
            if (cycles >= timeout) begin
                $display("\nARCH_TB: TIMEOUT after %0d cycles, %0d instructions, pc=%08x", cycles, retired, cpu.pc);
                $finish;
            end

            if (retire_valid) begin
                retired <= retired + 1;
            end

            if (ram_commit && bus_address == tohost) begin
                tohost_value <= wdata;
            end

            if (ram_commit && bus_address == tohost + 4) begin
                if (wdata == 32'h01010000) begin
                    $write("%c", tohost_value[7:0]);
                end else if (wdata == 0) begin
                    if (tohost_value == 1) begin
                        $display("\nARCH_TB: PASS after %0d cycles, %0d instructions", cycles, retired);
                    end else begin
                        $display("\nARCH_TB: FAIL code=%0d after %0d cycles, %0d instructions", tohost_value,
                                 cycles, retired);
                    end

                    $finish;
                end
            end
        end
    end
endmodule
