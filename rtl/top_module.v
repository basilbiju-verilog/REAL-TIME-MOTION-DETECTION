`timescale 1ns / 1ps

module top_module #(
    parameter CLK_FREQ = 12000000,
    parameter BAUD_RATE = 921600
)(
    input wire clk,          // 12MHz System Clock
    input wire rst_pin,      // Button on Cmod A7 (Optional reset)
    
    // UART Signals (Connect to Cmod A7 USB-UART pins)
    input wire uart_rxd,     // RX Input
    output wire uart_txd,    // TX Output
    
    // LEDs for debugging
    output wire [1:0] led    // LED[0] = Motion, LED[1] = Heartbeat
);

    // --------------------------------------------------------
    // 1. Internal Signals
    // --------------------------------------------------------
    wire rst = rst_pin; // Active high reset (assuming button is not inverted)
    
    // UART Receiver Signals
    wire [7:0] rx_data;
    wire rx_valid;
    
    // UART Transmitter Signals
    reg tx_start;
    reg [7:0] tx_data;
    wire tx_busy;
    
    // BRAM Signals
    reg [10:0] bram_addr; // 0 to 1199
    wire [31:0] bram_cent_read;
    wire [63:0] bram_frame_read;
    reg bram_we;
    wire [31:0] bram_cent_write;
    wire [63:0] bram_frame_write;
    
    // Motion Core Signals
    reg core_enable;
    wire motion_detected;
    wire [31:0] core_new_cent;
    wire [63:0] core_new_frame;
    
    // Global Counters
    reg [10:0] block_counter = 0; // Tracks which block (0-1199)
    reg [15:0] frame_counter = 1; // Tracks frame number

    // State Machine
    localparam S_IDLE       = 0;
    localparam S_READ_RAM   = 1;
    localparam S_PROCESS    = 2;
    localparam S_WRITE_RAM  = 3;
    localparam S_SEND_UART  = 4;
    
    reg [2:0] state = S_IDLE;

    // --------------------------------------------------------
    // 2. Instantiate Modules
    // --------------------------------------------------------
    
    uart_rx #( .CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE) ) u_rx (
        .clk(clk), .rst(rst),
        .rx_in(uart_rxd),
        .data_out(rx_data),
        .data_valid(rx_valid)
    );

    uart_tx #( .CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE) ) u_tx (
        .clk(clk), .rst(rst),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_out(uart_txd),
        .tx_busy(tx_busy)
    );
    
    bram_controller u_bram (
        .clk(clk),
        .addr(bram_addr),
        .we(bram_we),
        .wdata_cent(bram_cent_write),
        .wdata_frame(bram_frame_write),
        .rdata_cent(bram_cent_read),
        .rdata_frame(bram_frame_read)
    );
    
    motion_detect_core u_core (
        .clk(clk), .rst(rst),
        .enable(core_enable),
        .current_block_cent(rx_data), // Data directly from UART
        .current_frame_num(frame_counter),
        .old_centroids(bram_cent_read),
        .old_frame_nums(bram_frame_read),
        .motion_detected(motion_detected),
        .new_centroids(core_new_cent),
        .new_frame_nums(core_new_frame)
    );

    // --------------------------------------------------------
    // 3. Main Control Logic (FSM)
    // --------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            block_counter <= 0;
            frame_counter <= 1;
            bram_we <= 0;
            core_enable <= 0;
            tx_start <= 0;
            tx_data <= 0;
        end else begin
            case (state)
            
                // Wait for a byte from Python
                S_IDLE: begin
                    bram_we <= 0;
                    core_enable <= 0;
                    tx_start <= 0;
                    
                    if (rx_valid) begin
                        // 1. Set Address for BRAM
                        bram_addr <= block_counter;
                        // 2. Go to Read state
                        state <= S_READ_RAM;
                    end
                end
                
                // Wait 1 cycle for BRAM latency
                S_READ_RAM: begin
                    // BRAM Read happens automatically here. 
                    // Data will be ready at 'bram_cent_read' in next cycle.
                    state <= S_PROCESS;
                end
                
                // Trigger the Motion Core
                S_PROCESS: begin
                    core_enable <= 1; // Pulse enable for one cycle
                    state <= S_WRITE_RAM;
                end
                
                // Write results back to BRAM and Prepare TX
                S_WRITE_RAM: begin
                    core_enable <= 0;
                    
                    // Write Back
                    bram_we <= 1;
                    
                    // Note: We wire the core's output directly to BRAM input logic below
                    // bram_cent_write <= core_new_cent; (See assignments below)
                    
                    // (tx_data is loaded in S_SEND_UART: motion_detected is a
                    //  registered core output and is only valid one cycle after
                    //  the core captures its inputs)
                    state <= S_SEND_UART;
                end
                
                // Send result back to Python
                S_SEND_UART: begin
                    bram_we <= 0; // Turn off write

                    // Send 0xFF (255) for Motion, 0x00 for Background
                    // (motion_detected now holds the result for THIS block)
                    tx_data <= motion_detected ? 8'hFF : 8'h00;
                    
                    if (!tx_busy) begin
                        tx_start <= 1;
                        state <= S_IDLE;
                        
                        // Increment Counters
                        if (block_counter == 1199) begin
                            block_counter <= 0;
                            frame_counter <= frame_counter + 1;
                        end else begin
                            block_counter <= block_counter + 1;
                        end
                    end else begin
                        tx_start <= 0;
                    end
                end
            endcase
        end
    end

    // --------------------------------------------------------
    // 4. Assignments
    // --------------------------------------------------------
    
    // Wire Core output to BRAM input
    assign bram_cent_write = core_new_cent;
    assign bram_frame_write = core_new_frame;

    // Debug LEDs
    assign led[0] = motion_detected; // LED on when motion detected
    assign led[1] = frame_counter[4]; // Blink every 16 frames (Heartbeat)

endmodule