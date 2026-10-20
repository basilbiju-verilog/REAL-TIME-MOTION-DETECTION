`timescale 1ns / 1ps

module uart_tx #(
    parameter CLK_FREQ = 12000000,  // Standard Cmod A7 clock
    parameter BAUD_RATE = 921600    // High speed for video
)(
    input wire clk,
    input wire rst,
    input wire tx_start,          // Pulse to start transmission
    input wire [7:0] tx_data,     // Byte to send
    output reg tx_out,            // Serial Output (to PC)
    output reg tx_busy            // High while sending
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam DATA  = 2'b10;
    localparam STOP  = 2'b11;

    reg [1:0] state = IDLE;
    reg [15:0] clk_count = 0;
    reg [2:0] bit_index = 0;
    reg [7:0] data_temp = 0;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            tx_out <= 1'b1; // Idle state is High
            tx_busy <= 0;
            clk_count <= 0;
            bit_index <= 0;
            data_temp <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tx_out <= 1'b1;
                    clk_count <= 0;
                    bit_index <= 0;
                    
                    if (tx_start) begin
                        data_temp <= tx_data; // Latch data
                        tx_busy <= 1'b1;
                        state <= START;
                    end else begin
                        tx_busy <= 1'b0;
                    end
                end

                // 1. Send Start Bit (Low)
                START: begin
                    tx_out <= 1'b0;
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        state <= DATA;
                    end
                end

                // 2. Send Data Bits (LSB First)
                DATA: begin
                    tx_out <= data_temp[bit_index];
                    
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            bit_index <= 0;
                            state <= STOP;
                        end
                    end
                end

                // 3. Send Stop Bit (High)
                STOP: begin
                    tx_out <= 1'b1;
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        state <= IDLE; // Done, go back to IDLE
                        tx_busy <= 0;  // Ready for next byte
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule