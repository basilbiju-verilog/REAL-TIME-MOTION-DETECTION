`timescale 1ns / 1ps

module motion_detect_core #(
    parameter THRESHOLD = 120    // Sensitivity (Difference > 30 = Motion)
)(
    input wire clk,
    input wire rst,
    input wire enable,          // High when we have valid data from BRAM
    
    // Inputs (Current State)
    input wire [7:0] current_block_cent, // From UART
    input wire [15:0] current_frame_num, // From Global Counter
    
    // Inputs (From BRAM - Old State)
    input wire [31:0] old_centroids,     // 4 clusters (8 bits each)
    input wire [63:0] old_frame_nums,    // 4 clusters (16 bits each)
    
    // Outputs (Result)
    output reg motion_detected,
    
    // Outputs (To Write Back to BRAM - New State)
    output reg [31:0] new_centroids,
    output reg [63:0] new_frame_nums
);

    // ---------------------------------------------------------
    // 1. Unpack BRAM Data for easier processing
    // ---------------------------------------------------------
    wire [7:0]  clust_c [0:3]; // Centroids
    wire [15:0] clust_f [0:3]; // Frame Numbers
    
    assign clust_c[0] = old_centroids[7:0];
    assign clust_c[1] = old_centroids[15:8];
    assign clust_c[2] = old_centroids[23:16];
    assign clust_c[3] = old_centroids[31:24];
    
    assign clust_f[0] = old_frame_nums[15:0];
    assign clust_f[1] = old_frame_nums[31:16];
    assign clust_f[2] = old_frame_nums[47:32];
    assign clust_f[3] = old_frame_nums[63:48];

    // ---------------------------------------------------------
    // 2. Calculate Manhattan Distances (Absolute Diff)
    // ---------------------------------------------------------
    reg [7:0] diff [0:3];
    integer i;
    
    always @(*) begin
        for (i = 0; i < 4; i = i + 1) begin
            if (current_block_cent > clust_c[i])
                diff[i] = current_block_cent - clust_c[i];
            else
                diff[i] = clust_c[i] - current_block_cent;
        end
    end

    // ---------------------------------------------------------
    // 3. Logic: Find Match and Oldest Cluster
    // ---------------------------------------------------------
    reg match_found;
    reg [1:0] match_index;
    reg [1:0] oldest_index;
    reg [15:0] min_frame_val;

    always @(*) begin
        // A. Find Match (Is any diff < THRESHOLD?)
        match_found = 0;
        match_index = 0;
        
        // Priority encoder style: Check 0, then 1, etc.
        // (You could optimize to find the *best* match, but first match is faster)
        if (diff[0] < THRESHOLD) begin match_found = 1; match_index = 0; end
        else if (diff[1] < THRESHOLD) begin match_found = 1; match_index = 1; end
        else if (diff[2] < THRESHOLD) begin match_found = 1; match_index = 2; end
        else if (diff[3] < THRESHOLD) begin match_found = 1; match_index = 3; end

        // B. Find Oldest Cluster (Minimum Frame Number)
        // This is the cluster we will replace if no match is found
        min_frame_val = clust_f[0];
        oldest_index = 0;

        if (clust_f[1] < min_frame_val) begin min_frame_val = clust_f[1]; oldest_index = 1; end
        if (clust_f[2] < min_frame_val) begin min_frame_val = clust_f[2]; oldest_index = 2; end
        if (clust_f[3] < min_frame_val) begin min_frame_val = clust_f[3]; oldest_index = 3; end
    end

    // ---------------------------------------------------------
    // 4. Update Logic (Synchronous)
    // ---------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            motion_detected <= 0;
            new_centroids <= 0;
            new_frame_nums <= 0;
        end else if (enable) begin
            // Default: Keep old values
            new_centroids <= old_centroids;
            new_frame_nums <= old_frame_nums;
            
            if (match_found) begin
                // SITUATION: BACKGROUND DETECTED
                motion_detected <= 0;
                
                // Update Matched Cluster: New = (Old + Current) / 2
                // We perform the average calculation: (A + B) >> 1
                case (match_index)
                    2'd0: begin
                        new_centroids[7:0]   <= (clust_c[0] + current_block_cent) >> 1;
                        new_frame_nums[15:0] <= current_frame_num;
                    end
                    2'd1: begin
                        new_centroids[15:8]   <= (clust_c[1] + current_block_cent) >> 1;
                        new_frame_nums[31:16] <= current_frame_num;
                    end
                    2'd2: begin
                        new_centroids[23:16]  <= (clust_c[2] + current_block_cent) >> 1;
                        new_frame_nums[47:32] <= current_frame_num;
                    end
                    2'd3: begin
                        new_centroids[31:24]  <= (clust_c[3] + current_block_cent) >> 1;
                        new_frame_nums[63:48] <= current_frame_num;
                    end
                endcase
            end else begin
                // SITUATION: MOTION DETECTED
                motion_detected <= 1;
                
                // Replace Oldest Cluster with Current Data
                case (oldest_index)
                    2'd0: begin
                        new_centroids[7:0]   <= current_block_cent;
                        new_frame_nums[15:0] <= current_frame_num;
                    end
                    2'd1: begin
                        new_centroids[15:8]   <= current_block_cent;
                        new_frame_nums[31:16] <= current_frame_num;
                    end
                    2'd2: begin
                        new_centroids[23:16]  <= current_block_cent;
                        new_frame_nums[47:32] <= current_frame_num;
                    end
                    2'd3: begin
                        new_centroids[31:24]  <= current_block_cent;
                        new_frame_nums[63:48] <= current_frame_num;
                    end
                endcase
            end
        end
    end

endmodule