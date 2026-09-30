`default_nettype none

module tt_um_toxicfox_inferno (
    input wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input wire ena,
    input wire clk,
    input wire rst_n
);
    wire reset = !rst_n;
    wire valid;
    wire [33:0] address;
    wire write;
    wire [31:0] wdata;
    wire [3:0] wstrb;
    wire [1:0] kind;
    wire ready;
    wire [31:0] rdata;
    wire error;
    wire irq_machine;
    wire irq_supervisor;
    wire irq_software;
    wire irq_timer;
    wire [63:0] time_value;
    wire uart_tx;
    wire spi_sclk;
    wire spi_mosi;
    wire spi_cs_n;
    wire flash_cs_n;
    wire ram_a_cs_n;
    wire ram_b_cs_n;
    wire mem_sclk;
    wire mem_mosi;
    wire retire_valid;
    wire trap_valid;

    RiscV #(
        .RESET_PC(32'h00000000), .TLB_ENTRIES(32),
        .ENABLE_MMU(0), .ENABLE_PMP(0)
    ) cpu (
        .clk(clk), .reset(reset), .valid(valid), .address(address),
        .write(write), .wdata(wdata), .wstrb(wstrb), .kind(kind),
        .ready(ready), .rdata(rdata), .error(error),
        .irq_machine(irq_machine), .irq_supervisor(irq_supervisor),
        .irq_software(irq_software), .irq_timer(irq_timer),
        .time_value(time_value), .retire_valid(retire_valid),
        .trap_valid(trap_valid)
    );

    TinyPlatform platform (
        .clk(clk), .reset(reset), .valid(valid), .address(address),
        .write(write), .wdata(wdata), .wstrb(wstrb), .kind(kind),
        .ready(ready), .rdata(rdata), .error(error),
        .uart_rx(ui_in[1]), .uart_tx(uart_tx),
        .spi_sclk(spi_sclk), .spi_mosi(spi_mosi),
        .spi_miso(ui_in[0]), .spi_cs_n(spi_cs_n),
        .flash_cs_n(flash_cs_n), .ram_a_cs_n(ram_a_cs_n),
        .ram_b_cs_n(ram_b_cs_n), .mem_sclk(mem_sclk),
        .mem_mosi(mem_mosi), .mem_miso(uio_in[2]),
        .irq_machine(irq_machine), .irq_supervisor(irq_supervisor),
        .irq_software(irq_software), .irq_timer(irq_timer),
        .time_value(time_value)
    );

    // QSPI Pmod in single-bit SPI mode. IO2/IO3 stay high for flash WP#/HOLD#.
    assign uio_out = {ram_b_cs_n, ram_a_cs_n, 2'b11, mem_sclk,
                      1'b0, mem_mosi, flash_cs_n};
    assign uio_oe = 8'b11111011;
    assign uo_out = {2'b00, trap_valid, retire_valid, spi_cs_n,
                     spi_mosi, spi_sclk, uart_tx};
    wire _unused = &{ena, ui_in[7:2], uio_in[7:3], uio_in[1:0], 1'b0};
endmodule

`default_nettype wire
