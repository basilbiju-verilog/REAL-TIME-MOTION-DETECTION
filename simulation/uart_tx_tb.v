`timescale 1ns / 1ps

module uart_tx_tb;

    parameter CLK_FREQ = 12000000;
    parameter BAUD_RATE = 921600;
    parameter BIT_PERIOD = 1000000000 / BAUD_RATE; // ~1085ns

    reg clk;
    reg rst;
    reg tx_start;
    reg [7:0] tx_data;
    wire tx_out;
    wire tx_busy;

    // Instantiate DUT
    uart_tx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk(clk),
        .rst(rst),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_out(tx_out),
        .tx_busy(tx_busy)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #41.67 clk = ~clk; // 12 MHz
    end

    // Test Sequence
    initial begin
        // Initialize
        rst = 1;
        tx_start = 0;
        tx_data = 0;
        #200;
        rst = 0;
        #200;

        // Test 1: Send 0x55 (Binary 01010101)
        // This creates a square wave pattern on tx_out (0-1-0-1...)
        $display("Starting Test 1: Sending 0x55...");
        tx_data = 8'h55;
        tx_start = 1;
        #84; // Hold start pulse for one clock cycle
        tx_start = 0;

        // Wait for transmission to finish
        wait(tx_busy == 1); // Wait for it to become busy
        wait(tx_busy == 0); // Wait for it to finish
        
        $display("Test 1 Complete. Check waveform for Start(0) -> 10101010 -> Stop(1)");

        #2000; // Small delay

        // Test 2: Send 0xFF (Binary 11111111)
        // This keeps the line High (except for start bit)
        $display("Starting Test 2: Sending 0xFF...");
        tx_data = 8'hFF;
        tx_start = 1;
        #84;
        tx_start = 0;
        
        wait(tx_busy == 1);
        wait(tx_busy == 0);
        $display("Test 2 Complete.");

        #2000;
        $finish;
    end

endmodule