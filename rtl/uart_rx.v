`timescale 1ns / 1ps

module uart_rx #(
    parameter CLK_FREQ = 12000000,  // Standard Cmod A7 clock is 12 MHz
    parameter BAUD_RATE = 921600    // High speed for video data
)(
    input wire clk,
    input wire rst,
    input wire rx_in,             // Serial Input
    output reg [7:0] data_out,    // Parallel Byte Output
    output reg data_valid         // Single cycle pulse when data is ready
);

    // Calculate clocks per bit automatically
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    // FSM States
    localparam IDLE  = 3'b000;
    localparam START = 3'b001;
    localparam DATA  = 3'b010;
    localparam STOP  = 3'b011;
    localparam DONE  = 3'b100;

    reg [2:0] state = IDLE;
    reg [15:0] clk_count = 0;
    reg [2:0] bit_index = 0; // Tracks which bit (0-7) we are receiving
    reg [7:0] rx_byte_temp = 0;
    
    // Double-flop synchronizer to prevent metastability on external input
    reg rx_sync_1, rx_sync;
    always @(posedge clk) begin
        rx_sync_1 <= rx_in;
        rx_sync   <= rx_sync_1;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            clk_count <= 0;
            bit_index <= 0;
            data_out <= 0;
            data_valid <= 0;
            rx_byte_temp <= 0;
        end else begin
            case (state)
                // 1. Wait for Start Bit (Falling Edge)
                IDLE: begin
                    data_valid <= 0;
                    clk_count <= 0;
                    bit_index <= 0;
                    if (rx_sync == 1'b0) begin // Start bit detected
                        state <= START;
                    end
                end

                // 2. Check Middle of Start Bit
                START: begin
                    // Wait half a bit period to sample in the middle
                    if (clk_count == (CLKS_PER_BIT - 1) / 2) begin
                        if (rx_sync == 1'b0) begin
                            clk_count <= 0; // Reset counter for first data bit
                            state <= DATA;
                        end else begin
                            state <= IDLE; // False start glitch
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                // 3. Sample 8 Data Bits
                DATA: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        rx_byte_temp[bit_index] <= rx_sync; // Sample data LSB first
                        
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            bit_index <= 0;
                            state <= STOP;
                        end
                    end
                end

                // 4. Handle Stop Bit
                STOP: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        state <= DONE; // Stop bit period finished
                        clk_count <= 0;
                    end
                end

                // 5. Output Valid Data
                DONE: begin
                    data_out <= rx_byte_temp;
                    data_valid <= 1'b1;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule