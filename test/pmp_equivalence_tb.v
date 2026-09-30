`timescale 1ns/1ps
module pmp_equivalence_tb;
    reg [63:0] configuration;
    reg [255:0] addresses;
    reg [33:0] address;
    reg [1:0] size;
    reg [1:0] privilege;
    reg execute, read_access, write_access;
    wire new_allowed, reference_allowed;
    reg [2:0] scan_index;
    wire scan_match, scan_permitted;
    reg scan_allowed, scan_found;
    integer entry;
    integer mode, lock_bit, permission, offset, access_size, priv, i, region;
    integer checks = 0;

    PmpCheck dut (
        .configuration(configuration), .addresses(addresses),
        .address(address), .size(size), .privilege(privilege),
        .execute(execute), .read_access(read_access),
        .write_access(write_access), .allowed(new_allowed)
    );
    PmpCheckReference reference (
        .configuration(configuration), .addresses(addresses),
        .address(address), .size(size), .privilege(privilege),
        .execute(execute), .read_access(read_access),
        .write_access(write_access), .allowed(reference_allowed)
    );
    PmpEntryCheck scanned (
        .configuration(configuration[scan_index*8 +: 8]),
        .encoded(addresses[scan_index*32 +: 32]),
        .previous_encoded(scan_index == 0 ? 32'd0 : addresses[(scan_index-1'b1)*32 +: 32]),
        .address(address), .size(size), .privilege(privilege),
        .execute(execute), .read_access(read_access),
        .write_access(write_access), .region_match(scan_match),
        .permitted(scan_permitted)
    );

    task check;
        begin
            #1;
            checks = checks + 1;
            if (new_allowed !== reference_allowed)
                $fatal(1, "PMP mismatch addr=%h size=%d privilege=%d cfg=%h pmpaddr=%h new=%b ref=%b",
                       address, size, privilege, configuration, addresses,
                       new_allowed, reference_allowed);
            scan_allowed = privilege == 3 && size != 3;
            scan_found = 0;
            for (entry = 0; entry < 8; entry = entry + 1) begin
                scan_index = entry;
                #1;
                if (!scan_found && scan_match) begin
                    scan_found = 1;
                    scan_allowed = scan_permitted;
                end
            end
            if (scan_allowed !== reference_allowed)
                $fatal(1, "serial PMP mismatch addr=%h size=%d privilege=%d cfg=%h pmpaddr=%h scan=%b ref=%b",
                       address, size, privilege, configuration, addresses,
                       scan_allowed, reference_allowed);
        end
    endtask

    initial begin
        configuration = 0;
        addresses = 0;
        address = 0;
        size = 0;
        privilege = 0;
        execute = 0;
        read_access = 0;
        write_access = 0;
        for (mode = 0; mode < 4; mode = mode + 1)
            for (lock_bit = 0; lock_bit < 2; lock_bit = lock_bit + 1)
                for (permission = 0; permission < 8; permission = permission + 1) begin
                    configuration = 0;
                    addresses = 0;
                    addresses[0 +: 32] = 32'h000003fc;
                    addresses[32 +: 32] = mode == 3 ? 32'h00000403 : 32'h00000401;
                    configuration[8 +: 8] = (lock_bit << 7) | (mode << 3) | permission;
                    for (offset = -16; offset < 24; offset = offset + 1)
                        for (access_size = 0; access_size < 4; access_size = access_size + 1)
                            for (priv = 0; priv < 4; priv = priv + 1) begin
                                address = 34'h1000 + offset;
                                size = access_size;
                                privilege = priv;
                                execute = permission[0];
                                read_access = permission[1];
                                write_access = permission[2];
                                check();
                            end
                end

        for (i = 0; i < 2000; i = i + 1) begin
            configuration = {$random, $random};
            addresses = {$random, $random, $random, $random,
                         $random, $random, $random, $random};
            region = i % 8;
            address = {2'b0, addresses[region*32 +: 32]} << 2;
            address = address + (i % 19) - 9;
            size = i % 4;
            privilege = (i / 4) % 4;
            execute = i[0];
            read_access = i[1];
            write_access = i[2];
            check();
        end
        $display("pmp_equivalence_tb PASS: %0d comparisons", checks);
        $finish;
    end
endmodule
