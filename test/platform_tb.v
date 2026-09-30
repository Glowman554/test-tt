`timescale 1ns/1ps
module platform_tb;
    reg clk = 0;
    always #20 clk = !clk;
    reg reset = 1;
    reg valid = 0;
    reg [33:0] address = 0;
    reg write = 0;
    reg [1:0] kind = 0;
    wire ready, error;
    wire flash_cs_n, ram_a_cs_n, ram_b_cs_n;
    TinyPlatform dut (
        .clk(clk), .reset(reset), .valid(valid), .address(address),
        .write(write), .wdata(32'h12345678), .wstrb(4'hf),
        .kind(kind), .ready(ready), .rdata(), .error(error),
        .uart_rx(1'b1), .uart_tx(), .spi_sclk(), .spi_mosi(),
        .spi_miso(1'b0), .spi_cs_n(), .flash_cs_n(flash_cs_n),
        .ram_a_cs_n(ram_a_cs_n), .ram_b_cs_n(ram_b_cs_n),
        .mem_sclk(), .mem_mosi(), .mem_miso(1'b0),
        .irq_machine(), .irq_supervisor(), .irq_software(),
        .irq_timer(), .time_value()
    );
    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
        address = 0;
        write = 1;
        valid = 1;
        #1;
        if (!ready || !error || !flash_cs_n || !ram_a_cs_n || !ram_b_cs_n)
            $fatal(1, "SPI flash accepted a write");
        address = 34'h041000000;
        #1;
        if (!ready || !error) $fatal(1, "out-of-range PSRAM access accepted");
        address = 34'h040000000;
        write = 0;
        #1;
        if (ready || error) $fatal(1, "PSRAM read did not stall for controller");
        $display("platform_tb PASS: boot ROM is read-only and PSRAM is bounded");
        $finish;
    end
endmodule
