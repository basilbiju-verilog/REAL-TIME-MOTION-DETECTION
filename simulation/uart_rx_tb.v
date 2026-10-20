`timescale 1ns / 1ps

module uart_rx_tb;

    // Parameters
    parameter CLK_FREQ = 12000000;
    parameter BAUD_RATE = 921600;
    parameter BIT_PERIOD = 1000000000 / BAUD_RATE; // ~1085ns

    // Signals
    reg clk;
    reg rst;
    reg rx_in;
    wire [7:0] data_out;
    wire data_valid;

    // DUT Instantiation
    uart_rx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk(clk),
        .rst(rst),
        .rx_in(rx_in),
        .data_out(data_out),
        .data_valid(data_valid)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #41.67 clk = ~clk;
    end

    // Task to Send Byte
    task send_byte(input [7:0] data);
        integer i;
        begin
            // Start Bit
            rx_in = 0;
            #(BIT_PERIOD);
            // Data Bits
            for (i = 0; i < 8; i = i + 1) begin
                rx_in = data[i];
                #(BIT_PERIOD);
            end
            // Stop Bit
            rx_in = 1;
            #(BIT_PERIOD);
        end
    endtask

    // --------------------------------------------------------
    // PROCESS 1: STIMULUS (Sending Data)
    // --------------------------------------------------------
    initial begin
        rst = 1;
        rx_in = 1;
        #200;
        rst = 0;
        #200;

        // Send First Byte
        send_byte(8'h55);
        
        // Delay between bytes
        #2000; 

        // Send Second Byte
        send_byte(8'hA3);

        // Wait a bit and finish
        #2000;
        $finish;
    end

    // --------------------------------------------------------
    // PROCESS 2: MONITOR (Checking Data)
    // --------------------------------------------------------
    initial begin
        // Monitor Logic: Runs in parallel to sending
        
        // Check 1st Byte
        @(posedge data_valid); // Wait for the receiver to say "Ready"
        if (data_out == 8'h55) 
            $display("[PASS] Test 1: Received 0x55 correctly.");
        else 
            $display("[FAIL] Test 1: Expected 0x55, got 0x%h", data_out);

        // Check 2nd Byte
        @(posedge data_valid); // Wait for the receiver to say "Ready" again
        if (data_out == 8'hA3) 
            $display("[PASS] Test 2: Received 0xA3 correctly.");
        else 
            $display("[FAIL] Test 2: Expected 0xA3, got 0x%h", data_out);
    end

endmodule