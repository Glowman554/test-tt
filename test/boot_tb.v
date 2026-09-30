`timescale 1ns/1ps
module boot_tb;
    reg clk = 0;
    always #20 clk = !clk;
    reg rst_n = 0;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;
    reg miso = 0;
    wire [7:0] uio_in = {5'b0, miso, 2'b0};
    integer retire_count = 0;
    integer i;
    reg [7:0] flash [0:255];
    reg [7:0] opcode = 0;
    reg [23:0] spi_address = 0;
    integer bit_index = 0;

    tt_um_toxicfox_inferno dut (
        .ui_in(8'b00000010), .uo_out(uo_out), .uio_in(uio_in),
        .uio_out(uio_out), .uio_oe(uio_oe), .ena(1'b1),
        .clk(clk), .rst_n(rst_n)
    );

    always @(negedge uio_out[0]) begin
        bit_index = 0;
        opcode = 0;
        spi_address = 0;
    end
    always @(posedge uio_out[3]) if (!uio_out[0]) begin
        if (bit_index < 8) opcode = {opcode[6:0], uio_out[1]};
        else if (bit_index < 32) spi_address = {spi_address[22:0], uio_out[1]};
        bit_index = bit_index + 1;
    end
    always @(negedge uio_out[3]) if (!uio_out[0] && opcode == 8'h03 && bit_index >= 32)
        miso = flash[(spi_address + ((bit_index-32)/8)) & 255] >> (7 - ((bit_index-32)%8));

    always @(posedge clk) if (uo_out[4]) begin
        retire_count = retire_count + 1;
        if (retire_count == 3) begin
            $display("boot_tb PASS: executed from SPI flash");
            $finish;
        end
    end

    initial begin
        for (i = 0; i < 256; i = i + 1) flash[i] = 0;
        // jal x0, 0: repeatedly fetch and retire an instruction at reset PC.
        flash[0] = 8'h6f;
        flash[1] = 0;
        flash[2] = 0;
        flash[3] = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        #1000000;
        $fatal(1, "CPU failed to boot from SPI flash");
    end
endmodule
