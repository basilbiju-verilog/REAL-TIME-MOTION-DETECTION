`timescale 1ns / 1ps

module bram_controller #(
    parameter ADDR_WIDTH = 11,           // 2^11 = 2048 (Enough for 1200 blocks)
    parameter MEM_DEPTH  = 1200,         // 40x30 blocks
    parameter CENT_WIDTH = 32,           // 4 clusters * 8 bits
    parameter FRAME_WIDTH = 64           // 4 clusters * 16 bits
)(
    input wire clk,
    
    // Address for Read/Write (Shared for simplicity in this flow)
    input wire [ADDR_WIDTH-1:0] addr,
    
    // Write Enable (High = Update/Replace, Low = Read)
    input wire we,
    
    // Data Input (What we want to write to BRAM)
    input wire [CENT_WIDTH-1:0]  wdata_cent,
    input wire [FRAME_WIDTH-1:0] wdata_frame,
    
    // Data Output (What we read from BRAM)
    output reg [CENT_WIDTH-1:0]  rdata_cent,
    output reg [FRAME_WIDTH-1:0] rdata_frame
);

    // -------------------------------------------------------------------------
    // Memory Arrays (Inferred Block RAM)
    // -------------------------------------------------------------------------
    (* ram_style = "block" *) reg [CENT_WIDTH-1:0]  mem_cent  [0:MEM_DEPTH-1];
    (* ram_style = "block" *) reg [FRAME_WIDTH-1:0] mem_frame [0:MEM_DEPTH-1];

    // -------------------------------------------------------------------------
    // Initial Block (Optional: Initialize RAM to 0 to avoid X in simulation)
    // -------------------------------------------------------------------------
    integer i;
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1) begin
            mem_cent[i] = 0;
            mem_frame[i] = 0;
        end
    end

    // -------------------------------------------------------------------------
    // Synchronous Read / Write Logic
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (we) begin
            // Write Operation
            mem_cent[addr]  <= wdata_cent;
            mem_frame[addr] <= wdata_frame;
        end
        
        // Read Operation (Always happens, acts as Read-During-Write)
        // Note: In BRAM, read data appears 1 clock cycle after address is set
        rdata_cent  <= mem_cent[addr];
        rdata_frame <= mem_frame[addr];
    end

endmodule