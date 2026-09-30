`timescale 1ns/1ps
module boot_loader_tb;
    reg clk = 0;
    always #20 clk = !clk;
    reg rst_n = 0;
    wire [7:0] uo_out, uio_out, uio_oe;
    reg miso = 0;
    wire [7:0] uio_in = {5'b0, miso, 2'b0};
    reg [7:0] flash [0:65575];
    reg [7:0] ram [0:511];
    reg [7:0] opcode = 0;
    reg [23:0] spi_address = 0;
    reg [7:0] write_shift = 0;
    integer bit_index = 0;
    integer i;
    wire flash_selected = !uio_out[0];
    wire ram_selected = !uio_out[6];

    tt_um_toxicfox_inferno dut (
        .ui_in(8'b00000010), .uo_out(uo_out), .uio_in(uio_in),
        .uio_out(uio_out), .uio_oe(uio_oe), .ena(1'b1),
        .clk(clk), .rst_n(rst_n)
    );

    always @(negedge uio_out[0] or negedge uio_out[6]) begin
        bit_index = 0;
        opcode = 0;
        spi_address = 0;
        write_shift = 0;
    end
    always @(posedge uio_out[3]) if (flash_selected || ram_selected) begin
        if (bit_index < 8) opcode = {opcode[6:0], uio_out[1]};
        else if (bit_index < 32) spi_address = {spi_address[22:0], uio_out[1]};
        else if (opcode == 8'h02 && ram_selected) begin
            write_shift = {write_shift[6:0], uio_out[1]};
            if (bit_index[2:0] == 7) begin
                ram[spi_address[8:0]] = write_shift;
                spi_address = spi_address + 1'b1;
            end
        end
        bit_index = bit_index + 1;
    end
    always @(negedge uio_out[3]) if ((flash_selected || ram_selected) &&
                                     opcode == 8'h03 && bit_index >= 32) begin
        if (flash_selected)
            miso = flash[spi_address + ((bit_index-32)/8)] >> (7 - ((bit_index-32)%8));
        else
            miso = ram[(spi_address + ((bit_index-32)/8)) & 511] >> (7 - ((bit_index-32)%8));
    end

    initial begin
        for (i = 0; i < 65576; i = i + 1) flash[i] = 8'hff;
        for (i = 0; i < 512; i = i + 1) ram[i] = 0;
        $readmemh("test/build/flash.hex", flash);
        repeat (4) @(negedge clk);
        rst_n = 1;
        wait ({ram[259], ram[258], ram[257], ram[256]} == 32'h12345678);
        $display("boot_loader_tb PASS: copied and executed PSRAM payload");
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1, "boot loader did not run payload");
    end
endmodule
