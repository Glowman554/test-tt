// Physical bus: 16 MiB boot flash, 16 MiB PSRAM, CLINT, one-source PLIC,
// one UART, and one software-controlled SPI port.
module TinyPlatform (
    input wire clk,
    input wire reset,
    input wire valid,
    input wire [33:0] address,
    input wire write,
    input wire [31:0] wdata,
    input wire [3:0] wstrb,
    input wire [1:0] kind,
    output wire ready,
    output reg [31:0] rdata,
    output wire error,
    input wire uart_rx,
    output wire uart_tx,
    output wire spi_sclk,
    output wire spi_mosi,
    input wire spi_miso,
    output wire spi_cs_n,
    output wire flash_cs_n,
    output wire ram_a_cs_n,
    output wire ram_b_cs_n,
    output wire mem_sclk,
    output wire mem_mosi,
    input wire mem_miso,
    output wire irq_machine,
    output wire irq_supervisor,
    output wire irq_software,
    output wire irq_timer,
    output wire [63:0] time_value
);
    wire [31:0] a = address[31:0];
    wire flash_sel = a < 32'h01000000;
    wire ram_sel = a >= 32'h40000000 && a < 32'h41000000;
    wire uart_sel = a >= 32'h80000008 && a < 32'h80000014;
    wire spi_sel = a >= 32'h80000040 && a < 32'h80000050;
    wire clint_sel = a >= 32'h02000000 && a < 32'h02010000;
    wire plic_sel = a >= 32'h0c000000 && a < 32'h10000000;
    wire mmio_sel = uart_sel || spi_sel || clint_sel || plic_sel;
    wire mem_sel = flash_sel || ram_sel;
    wire bad = address[33:32] != 0 || a[1:0] != 0 || kind == 3 ||
               !(mem_sel || mmio_sel) || (write && flash_sel) ||
               (kind != 0 && (mmio_sel || write));
    wire mem_valid = valid && !reset && !bad && mem_sel;
    wire mem_ready;
    wire [31:0] mem_data;
    wire [31:0] uart_data;
    wire [31:0] spi_data;
    wire [31:0] clint_data;
    wire [31:0] plic_data;
    wire uart_irq;
    wire commit = valid && ready && !error;
    wire wr_commit = commit && write;
    wire rd_commit = commit && !write;

    assign ready = valid && !reset && (bad || (mem_sel ? mem_ready : 1'b1));
    assign error = valid && !reset && bad;

    always @(*) begin
        rdata = 0;
        if (!bad) begin
            if (mem_sel) rdata = mem_data;
            else if (uart_sel) rdata = uart_data;
            else if (spi_sel) rdata = spi_data;
            else if (clint_sel) rdata = clint_data;
            else if (plic_sel) rdata = plic_data;
        end
    end

    SerialMemory memory (
        .clk(clk), .reset(reset), .valid(mem_valid), .address(a),
        .write(write), .wdata(wdata), .wstrb(wstrb),
        .ready(mem_ready), .rdata(mem_data),
        .flash_cs_n(flash_cs_n), .ram_a_cs_n(ram_a_cs_n),
        .ram_b_cs_n(ram_b_cs_n), .sclk(mem_sclk),
        .mosi(mem_mosi), .miso(mem_miso)
    );

    Uart uart (
        .clk(clk), .reset(reset), .address(a),
        .write_data(wdata), .write_mask(wstrb),
        .write_enable(wr_commit && uart_sel),
        .read_commit(rd_commit && uart_sel),
        .rx(uart_rx), .tx(uart_tx), .rx_valid(uart_irq),
        .read_data(uart_data)
    );

    Spi spi (
        .clk(clk), .reset(reset), .address(a),
        .write_data(wdata), .write_mask(wstrb),
        .write_enable(wr_commit && spi_sel),
        .sclk(spi_sclk), .mosi(spi_mosi), .miso(spi_miso),
        .cs_n(spi_cs_n), .read_data(spi_data)
    );

    Clint clint (
        .clk(clk), .reset(reset), .address(a),
        .write_data(wdata), .write_mask(wstrb),
        .write_enable(wr_commit && clint_sel),
        .read_data(clint_data), .irq_software(irq_software),
        .irq_timer(irq_timer), .time_value(time_value)
    );

    Plic #(.NUM_SOURCES(1)) plic (
        .clk(clk), .reset(reset), .irq_sources(uart_irq),
        .address(a), .write_data(wdata), .write_mask(wstrb),
        .write_enable(wr_commit && plic_sel),
        .read_commit(rd_commit && plic_sel),
        .read_data(plic_data), .irq_machine(irq_machine),
        .irq_supervisor(irq_supervisor)
    );
endmodule
