`timescale 1ns/1ps
module serial_memory_tb;
    reg clk = 0;
    always #20 clk = !clk;
    reg reset = 1;
    reg valid = 0;
    reg [31:0] address = 0;
    reg write = 0;
    reg [31:0] wdata = 0;
    reg [3:0] wstrb = 0;
    wire ready;
    wire [31:0] rdata;
    wire flash_cs_n, ram_a_cs_n, ram_b_cs_n, sclk, mosi;
    reg miso = 0;

    SerialMemory #(.STARTUP_CYCLES(4)) dut (
        .clk(clk), .reset(reset), .valid(valid), .address(address),
        .write(write), .wdata(wdata), .wstrb(wstrb), .ready(ready),
        .rdata(rdata), .flash_cs_n(flash_cs_n),
        .ram_a_cs_n(ram_a_cs_n), .ram_b_cs_n(ram_b_cs_n),
        .sclk(sclk), .mosi(mosi), .miso(miso)
    );

    reg [7:0] flash [0:255];
    reg [7:0] ram_a [0:255];
    reg [7:0] ram_b [0:255];
    integer i;
    integer bit_index = 0;
    reg [7:0] opcode = 0;
    reg [23:0] spi_address = 0;
    reg [7:0] byte_shift = 0;
    reg [1:0] device = 0;
    wire selected = !flash_cs_n || !ram_a_cs_n || !ram_b_cs_n;

    always @(negedge flash_cs_n or negedge ram_a_cs_n or negedge ram_b_cs_n) begin
        bit_index = 0;
        opcode = 0;
        spi_address = 0;
        byte_shift = 0;
        if (!flash_cs_n) device = 0;
        else if (!ram_a_cs_n) device = 1;
        else device = 2;
    end

    always @(posedge sclk) if (selected) begin
        if (bit_index < 8) opcode = {opcode[6:0], mosi};
        else if (bit_index < 32) spi_address = {spi_address[22:0], mosi};
        else if (opcode == 8'h02) begin
            byte_shift = {byte_shift[6:0], mosi};
            if (bit_index[2:0] == 7) begin
                if (device == 1) ram_a[spi_address[7:0]] = byte_shift;
                else if (device == 2) ram_b[spi_address[7:0]] = byte_shift;
                else $fatal(1, "flash write attempted");
                spi_address = spi_address + 1'b1;
            end
        end
        bit_index = bit_index + 1;
    end

    always @(negedge sclk) if (selected && opcode == 8'h03 && bit_index >= 32) begin
        case (device)
            0: miso = flash[(spi_address + ((bit_index-32)/8)) & 255] >> (7 - ((bit_index-32)%8));
            1: miso = ram_a[(spi_address + ((bit_index-32)/8)) & 255] >> (7 - ((bit_index-32)%8));
            2: miso = ram_b[(spi_address + ((bit_index-32)/8)) & 255] >> (7 - ((bit_index-32)%8));
        endcase
    end

    task transaction;
        input [31:0] addr;
        input wr;
        input [31:0] data;
        input [3:0] mask;
        input [31:0] expected;
        begin
            @(negedge clk);
            address = addr;
            write = wr;
            wdata = data;
            wstrb = mask;
            valid = 1;
            wait (ready);
            #1;
            if (!wr && rdata !== expected)
                $fatal(1, "read %08x: got %08x expected %08x", addr, rdata, expected);
            @(negedge clk);
            valid = 0;
            @(negedge clk);
        end
    endtask

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            flash[i] = 0;
            ram_a[i] = 0;
            ram_b[i] = 0;
        end
        flash[0] = 8'h13;
        flash[1] = 8'h05;
        flash[2] = 8'h00;
        flash[3] = 8'h00;
        repeat (3) @(negedge clk);
        reset = 0;
        transaction(32'h00000000, 0, 0, 0, 32'h00000513);
        transaction(32'h40000004, 1, 32'h12345678, 4'b1111, 0);
        transaction(32'h40000004, 0, 0, 0, 32'h12345678);
        transaction(32'h40000004, 1, 32'h00aabb00, 4'b0110, 0);
        transaction(32'h40000004, 0, 0, 0, 32'h12aabb78);
        transaction(32'h40800004, 1, 32'hdeadbeef, 4'b1111, 0);
        transaction(32'h40800004, 0, 0, 0, 32'hdeadbeef);
        transaction(32'h40000004, 0, 0, 0, 32'h12aabb78);
        $display("serial_memory_tb PASS");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "timeout");
    end
endmodule
