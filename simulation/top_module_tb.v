`timescale 1ns / 1ps

module top_module_tb;

    // =========================================================================
    // 1. Parameters & Signals
    // =========================================================================
    parameter CLK_FREQ = 12000000;
    parameter BAUD_RATE = 921600;
    parameter BIT_PERIOD = 1000000000 / BAUD_RATE; // ~1085ns per bit

    reg clk;
    reg rst_pin;
    reg uart_rxd;       // Input TO the FPGA (Simulated TX from PC)
    wire uart_txd;      // Output FROM the FPGA (Simulated RX on PC)
    wire [1:0] led;

    // Variables for the Testbench Receiver
    reg [7:0] rx_byte;
    
    // =========================================================================
    // 2. Instantiate the Top Module (DUT)
    // =========================================================================
    top_module #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk(clk),
        .rst_pin(rst_pin),
        .uart_rxd(uart_rxd),
        .uart_txd(uart_txd),
        .led(led)
    );

    // =========================================================================
    // 3. Clock Generation (12 MHz)
    // =========================================================================
    initial begin
        clk = 0;
        forever #41.67 clk = ~clk; // Period approx 83.33ns
    end

    // =========================================================================
    // 4. Tasks for UART Simulation
    // =========================================================================
    
    // TASK: Send a Byte to the FPGA (Bit-Banging)
    task pc_send_byte(input [7:0] data);
        integer i;
        begin
            // Start Bit (Low)
            uart_rxd = 0;
            #(BIT_PERIOD);
            
            // Data Bits (LSB First)
            for (i = 0; i < 8; i = i + 1) begin
                uart_rxd = data[i];
                #(BIT_PERIOD);
            end
            
            // Stop Bit (High)
            uart_rxd = 1;
            #(BIT_PERIOD);
            
            // Small gap between bytes
            #(BIT_PERIOD * 5); 
        end
    endtask

    // TASK: Receive a Byte from the FPGA
    // This task blocks until a full byte is received from uart_txd
    task pc_receive_byte(output [7:0] data);
        integer i;
        begin
            // Wait for Start Bit (Falling Edge)
            wait(uart_txd == 0);
            
            // Wait 1.5 Bit Periods to sample middle of Bit 0
            #(BIT_PERIOD + (BIT_PERIOD / 2));
            
            // Sample 8 Bits
            for (i = 0; i < 8; i = i + 1) begin
                data[i] = uart_txd;
                #(BIT_PERIOD);
            end
            
            // Wait for Stop Bit (Just to align timing)
            // (We don't strictly check logic level here for simplicity)
            #(BIT_PERIOD);
        end
    endtask

    // =========================================================================
    // 5. Main Test Stimulus (The "Sender")
    // =========================================================================
    initial begin
        $display("============================================================");
        $display("Starting Top Module Simulation");
        $display("============================================================");

        // Initialize
        rst_pin = 1;
        uart_rxd = 1; // Idle line is High
        #500;
        
        // Release Reset
        rst_pin = 0;
        #500;

        // ---------------------------------------------------------------------
        // TEST CASE 1: Initialization / First Pixel (Block 0)
        // ---------------------------------------------------------------------
        // Expectation: BRAM is empty (0x00). Input 0x64 (100). 
        // Diff = 100 > 30. Result = MOTION DETECTED (0xFF).
        // Side Effect: BRAM Block 0 Cluster 0 updates to 0x64.
        $display("[PC] Sending Byte 1: 0x64 (Decimal 100)...");
        pc_send_byte(8'h64);

        // ---------------------------------------------------------------------
        // TEST CASE 2: Second Pixel (Block 1)
        // ---------------------------------------------------------------------
        // Expectation: BRAM Block 1 is empty (0x00). Input 0x10 (16).
        // Diff = 16 < 30. Result = NO MOTION (0x00).
        // Note: Even though BRAM is 0, 16 is close enough to 0 to be background.
        $display("[PC] Sending Byte 2: 0x10 (Decimal 16)...");
        pc_send_byte(8'h10);

        // Wait for receiver to finish printing
        #50000; 
        $display("============================================================");
        $display("Simulation Complete");
        $display("============================================================");
        $finish;
    end

    // =========================================================================
    // 6. Parallel Monitor (The "Receiver")
    // =========================================================================
    initial begin
        // Monitor Loop
        forever begin
            pc_receive_byte(rx_byte);
            
            $display("[FPGA RESPONSE] Received: 0x%h", rx_byte);
            
            if (rx_byte == 8'hFF)
                $display("                -> STATUS: MOTION DETECTED");
            else if (rx_byte == 8'h00)
                $display("                -> STATUS: BACKGROUND");
            else
                $display("                -> STATUS: UNKNOWN/ERROR");
        end
    end

endmodule