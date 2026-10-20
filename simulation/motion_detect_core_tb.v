`timescale 1ns / 1ps

module motion_detect_core_tb;

    reg clk;
    reg rst;
    reg enable;
    reg [7:0] current_block_cent;
    reg [15:0] current_frame_num;
    reg [31:0] old_centroids;
    reg [63:0] old_frame_nums;
    wire motion_detected;
    wire [31:0] new_centroids;
    wire [63:0] new_frame_nums;

    motion_detect_core #(
        .THRESHOLD(30)
    ) dut (
        .clk(clk), .rst(rst), .enable(enable),
        .current_block_cent(current_block_cent),
        .current_frame_num(current_frame_num),
        .old_centroids(old_centroids),
        .old_frame_nums(old_frame_nums),
        .motion_detected(motion_detected),
        .new_centroids(new_centroids),
        .new_frame_nums(new_frame_nums)
    );

    initial begin
        clk = 0; forever #5 clk = ~clk;
    end

    initial begin
        rst = 1; enable = 0;
        #20; rst = 0;

        // TEST 1: MATCH SCENARIO (Background)
        // Stored Clusters: 100, 200, 50, 0
        // Incoming: 110 (Close to 100, diff is 10)
        $display("TEST 1: Background Match...");
        old_centroids = 32'h0032C864; // 0, 50, 200, 100 (in hex)
        old_frame_nums = 64'd0;       // All old
        current_block_cent = 8'd110;
        current_frame_num = 16'd5;
        enable = 1;
        
        #10; // Wait for clock
        if (motion_detected == 0) $display("[PASS] Motion Flag Low (Correct)");
        else $display("[FAIL] Motion Flag High");
        
        // Check if Cluster 0 (100) updated to (100+110)/2 = 105 (0x69)
        if (new_centroids[7:0] == 8'd105) $display("[PASS] Cluster Updated to 105");
        else $display("[FAIL] Cluster Update Wrong: %d", new_centroids[7:0]);


        // TEST 2: NO MATCH SCENARIO (Motion)
        // Stored Clusters: 100, 200, 50, 0
        // Incoming: 250 (Diffs: 150, 50, 200, 250) -> All > 30
        // Oldest Cluster: Cluster 3 (Frame 1)
        #20;
        $display("TEST 2: Motion Detect...");
        old_centroids = 32'h0032C864; 
        old_frame_nums = 64'h0005000500050001; // Cluster 3 is oldest (frame 1)
        current_block_cent = 8'd250;
        current_frame_num = 16'd10;
        
        #10;
        if (motion_detected == 1) $display("[PASS] Motion Flag High (Correct)");
        else $display("[FAIL] Motion Flag Low");

        // Check if Cluster 3 (Oldest) was replaced with 250 (0xFA)
        if (new_centroids[31:24] == 8'd250) $display("[PASS] Oldest Cluster Replaced");
        else $display("[FAIL] Replacement Wrong: %d", new_centroids[31:24]);

        #50; $finish;
    end
endmodule