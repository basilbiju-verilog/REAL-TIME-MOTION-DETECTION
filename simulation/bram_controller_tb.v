`timescale 1ns / 1ps

module bram_controller_tb;

    // Parameters
    parameter ADDR_WIDTH = 11;
    parameter CENT_WIDTH = 32;
    parameter FRAME_WIDTH = 64;

    // Signals
    reg clk;
    reg [ADDR_WIDTH-1:0] addr;
    reg we;
    reg [CENT_WIDTH-1:0] wdata_cent;
    reg [FRAME_WIDTH-1:0] wdata_frame;
    wire [CENT_WIDTH-1:0] rdata_cent;
    wire [FRAME_WIDTH-1:0] rdata_frame;

    // Instantiate DUT
    bram_controller #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .CENT_WIDTH(CENT_WIDTH),
        .FRAME_WIDTH(FRAME_WIDTH)
    ) dut (
        .clk(clk),
        .addr(addr),
        .we(we),
        .wdata_cent(wdata_cent),
        .wdata_frame(wdata_frame),
        .rdata_cent(rdata_cent),
        .rdata_frame(rdata_frame)
    );

    // Clock Gen
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz effective for sim speed
    end

    // Test Sequence
    initial begin
        // Initialize
        addr = 0;
        we = 0;
        wdata_cent = 0;
        wdata_frame = 0;
        #20;

        // -------------------------------------------------------
        // TEST 1: Write to Address 10 (Simulating Block #10)
        // -------------------------------------------------------
        $display("Writing to Block 10...");
        addr = 11'd10;
        we = 1;
        // Centroids: Clust0=0xAA, Clust1=0xBB, Clust2=0xCC, Clust3=0xDD
        wdata_cent  = 32'hDDCCBBAA; 
        // FrameNums: Clust0=1, Clust1=2, Clust2=3, Clust3=4
        wdata_frame = 64'h0004000300020001; 
        
        #10; // Wait 1 clock cycle
        we = 0; // Turn off write enable

        // -------------------------------------------------------
        // TEST 2: Write to Address 500 (Simulating Block #500)
        // -------------------------------------------------------
        $display("Writing to Block 500...");
        addr = 11'd500;
        we = 1;
        wdata_cent  = 32'h12345678;
        wdata_frame = 64'h000A000B000C000D;
        
        #10;
        we = 0;

        // -------------------------------------------------------
        // TEST 3: Read Back Address 10
        // -------------------------------------------------------
        $display("Reading back Block 10...");
        addr = 11'd10;
        #10; // Wait for BRAM read latency (1 cycle)
        
        if (rdata_cent == 32'hDDCCBBAA)
            $display("[PASS] Block 10 Centroids correct: %h", rdata_cent);
        else
            $display("[FAIL] Block 10 Centroids mismatch: %h", rdata_cent);

        // -------------------------------------------------------
        // TEST 4: Read Back Address 500
        // -------------------------------------------------------
        $display("Reading back Block 500...");
        addr = 11'd500;
        #10;
        
        if (rdata_frame == 64'h000A000B000C000D)
            $display("[PASS] Block 500 Frames correct: %h", rdata_frame);
        else
            $display("[FAIL] Block 500 Frames mismatch: %h", rdata_frame);

        #50;
        $finish;
    end

endmodule