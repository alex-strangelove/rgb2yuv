`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/10/2025 05:47:46 PM
// Design Name: 
// Module Name: rtl_rgb2yuv_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module tb_rgb2yuv;
    // Parameters
    parameter BIT_DEPTH    = 8;
    parameter MULT_WIDTH   = 8;
    parameter REC_STANDARD = 0; // 1: Rec.709, 0: Rec.601

    // Constants for Rec.601/709 standards
    localparam real Kr_601 = 0.299;
    localparam real Kg_601 = 0.587;
    localparam real Kb_601 = 0.114;
    
    localparam real Kr_709 = 0.2126;
    localparam real Kg_709 = 0.7152;
    localparam real Kb_709 = 0.0722;

    // Chroma scaling factors
    localparam real KCb_FLOAT_601 = 1.0/(2.0*(1.0-Kb_601));
    localparam real KCr_FLOAT_601 = 1.0/(2.0*(1.0-Kr_601));
    
    localparam real KCb_FLOAT_709 = 1.0/(2.0*(1.0-Kb_709));
    localparam real KCr_FLOAT_709 = 1.0/(2.0*(1.0-Kr_709));

    localparam CLK_PERIOD                = 10;  // 10ns
    localparam PIPELINE_DEPTH            = 11; // 11 stages
    localparam PIPELINE_LATENCY          = PIPELINE_DEPTH * CLK_PERIOD;
    localparam RANDOM_PATTERN_TEST_COUNT = 100;

    // Clock & reset signals
    reg clk;
    reg reset;

    // RGB input & YUV output   
    reg  [BIT_DEPTH-1:0] R, G, B;
    wire [BIT_DEPTH-1:0] Y, U, V;

    // Instantiate the DUT
    rtl_rgb2yuv #(
        .BIT_DEPTH(BIT_DEPTH),
        .MULT_WIDTH(MULT_WIDTH),
        .REC_STANDARD(REC_STANDARD)
    ) dut (
        .clk(clk),
        .areset(reset),
        .R(R),
        .G(G),
        .B(B),
        .Y(Y),
        .U(U),
        .V(V)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Reset Generation: Assert reset low for a few cycles then deassert
    initial begin
        reset = 0;
        #12; // hold reset low for a little over one clock cycle
        reset = 1;
    end

  // Function to compute reference YUV values
  // The results are rounded and clamped to the [0,255] range.
    function automatic void compute_ref(
        input  [7:0] r,
        input  [7:0] g,
        input  [7:0] b,
        output int ref_y,
        output int ref_u,
        output int ref_v
    );
    real Yf, Uf, Vf;
    real Kr, Kg, Kb, KCb, KCr;
    begin
        // Select coefficients based on standard
        if (REC_STANDARD) begin  // Rec.709
            Kr = Kr_709;
            Kg = Kg_709;
            Kb = Kb_709;
            KCb = KCb_FLOAT_709;
            KCr = KCr_FLOAT_709;
        end else begin          // Rec.601
            Kr = Kr_601;
            Kg = Kg_601;
            Kb = Kb_601;
            KCb = KCb_FLOAT_601;
            KCr = KCr_FLOAT_601;
        end

        // Compute YUV
        Yf = Kr*r + Kg*g + Kb*b;
        Uf = 128 + (b - Yf) * KCb;
        Vf = 128 + (r - Yf) * KCr;

        // Round and clamp
        ref_y = $rtoi(Yf + 0.5);
        ref_u = $rtoi(Uf + 0.5);
        ref_v = $rtoi(Vf + 0.5);
        
        // Clamp to [0, 255]
        if (ref_y < 0)   ref_y = 0;
        if (ref_y > 255) ref_y = 255;
        if (ref_u < 0)   ref_u = 0;
        if (ref_u > 255) ref_u = 255;
        if (ref_v < 0)   ref_v = 0;
        if (ref_v > 255) ref_v = 255;
    end
    endfunction

    // Function to check if value is within tolerance
    function automatic bit within_tolerance(
        input logic [7:0] actual,
        input logic [7:0] expected,
        input logic [7:0] tolerance = 1
    );
        // Convert to int for correct arithmetic
        int a = actual;
        int e = expected;
        int t = tolerance;
        return (a >= (e - t)) && (a <= (e + t));
    endfunction

    initial begin
        // Wait for reset to be deasserted
        @(posedge reset);
        #10;

        #100; // Allow some time for the change to take effect
        run_all_tests();

        $finish;
    end

    // Add task to contain all the test patterns
    task automatic run_all_tests();
        int exp_y, exp_u, exp_v;
        string test_name;

        if (REC_STANDARD) 
            $display("Running tests for Rec.709 Standard...");
        else 
            $display("Running tests for Rec.601 Standard...");
        
        // Random pattern tests
        test_name = "Random";
        $display("Starting random pattern tests...");
        repeat (RANDOM_PATTERN_TEST_COUNT) begin
            R = $urandom_range(0, 255);
            G = $urandom_range(0, 255);
            B = $urandom_range(0, 255);
            #PIPELINE_LATENCY;
            compute_ref(R, G, B, exp_y, exp_u, exp_v);
            $display("================================");
            $display("Time: %t\nTest:     %s", $time, test_name);
            $display("Input:    RGB=(%3d,%3d,%3d)", R, G, B);
            $display("Output:   YUV=(%3d,%3d,%3d)", Y, U, V);
            $display("Expected: YUV=(%3d,%3d,%3d)", exp_y, exp_u, exp_v);
            if (!within_tolerance(Y, exp_y) || 
                !within_tolerance(U, exp_u) || 
                !within_tolerance(V, exp_v))
                $fatal(1, "Random test failed for RGB=(%d,%d,%d)", R, G, B);
            else
                $display("%s: Test Passed!", test_name);
            $display("================================\n");
        end
        $display("All random tests passed.\n");
        
        // Standard pattern tests
        $display("Starting standard pattern tests...");
        // Test pattern: Black (0,0,0)
        test_name = "Black";
        R = 8'd0; G = 8'd0; B = 8'd0;
        #PIPELINE_LATENCY;
        compute_ref(R, G, B, exp_y, exp_u, exp_v);
        $display("================================");
        $display("Time: %t\nTest:     %s", $time, test_name);
        $display("Input:    RGB=(%3d,%3d,%3d)", R, G, B);
        $display("Output:   YUV=(%3d,%3d,%3d)", Y, U, V);
        $display("Expected: YUV=(%3d,%3d,%3d)", exp_y, exp_u, exp_v);
        if (!within_tolerance(Y, exp_y) || 
            !within_tolerance(U, exp_u) || 
            !within_tolerance(V, exp_v))
            $fatal(1, "%s test failed", test_name);
        else
            $display("%s: Test Passed!", test_name);
        $display("================================\n");
            

        // Test pattern: White (255,255,255)
        test_name = "White";
        R = 8'd255; G = 8'd255; B = 8'd255;
        #PIPELINE_LATENCY;
        compute_ref(R, G, B, exp_y, exp_u, exp_v);
        $display("================================");
        $display("Time: %t\nTest:     %s", $time, test_name);
        $display("Input:    RGB=(%3d,%3d,%3d)", R, G, B);
        $display("Output:   YUV=(%3d,%3d,%3d)", Y, U, V);
        $display("Expected: YUV=(%3d,%3d,%3d)", exp_y, exp_u, exp_v);
        if (!within_tolerance(Y, exp_y) || 
            !within_tolerance(U, exp_u) || 
            !within_tolerance(V, exp_v))
            $fatal(1, "%s test failed", test_name);
        else
            $display("%s: Test Passed!", test_name);
        $display("================================\n");
            
        // Test pattern: Red (255,0,0)
        test_name = "Red";
        R = 8'd255; G = 8'd0; B = 8'd0;
        #PIPELINE_LATENCY;
        compute_ref(R, G, B, exp_y, exp_u, exp_v);
        $display("================================");
        $display("Time: %t\nTest:     %s", $time, test_name);
        $display("Input:    RGB=(%3d,%3d,%3d)", R, G, B);
        $display("Output:   YUV=(%3d,%3d,%3d)", Y, U, V);
        $display("Expected: YUV=(%3d,%3d,%3d)", exp_y, exp_u, exp_v);
        if (!within_tolerance(Y, exp_y) || 
            !within_tolerance(U, exp_u) || 
            !within_tolerance(V, exp_v))
            $fatal(1, "%s test failed", test_name);
        else
            $display("%s: Test Passed!", test_name);
        $display("================================\n");
            
        // Test pattern: Green (0,255,0)
        test_name = "Green";
        R = 8'd0; G = 8'd255; B = 8'd0;
        #PIPELINE_LATENCY;
        compute_ref(R, G, B, exp_y, exp_u, exp_v);
        $display("================================");
        $display("Time: %t\nTest:     %s", $time, test_name);
        $display("Input:    RGB=(%3d,%3d,%3d)", R, G, B);
        $display("Output:   YUV=(%3d,%3d,%3d)", Y, U, V);
        $display("Expected: YUV=(%3d,%3d,%3d)", exp_y, exp_u, exp_v);
        if (!within_tolerance(Y, exp_y) || 
            !within_tolerance(U, exp_u) || 
            !within_tolerance(V, exp_v))
            $fatal(1, "%s test failed", test_name);
        else
            $display("%s: Test Passed!", test_name);
        $display("================================\n");
            
        // Test pattern: Blue (0,0,255)
        test_name = "Blue";
        R = 8'd0; G = 8'd0; B = 8'd255;
        #PIPELINE_LATENCY;
        compute_ref(R, G, B, exp_y, exp_u, exp_v);
        $display("================================");
        $display("Time: %t\nTest:     %s", $time, test_name);
        $display("Input:    RGB=(%3d,%3d,%3d)", R, G, B);
        $display("Output:   YUV=(%3d,%3d,%3d)", Y, U, V);
        $display("Expected: YUV=(%3d,%3d,%3d)", exp_y, exp_u, exp_v);
        if (!within_tolerance(Y, exp_y) || 
            !within_tolerance(U, exp_u) || 
            !within_tolerance(V, exp_v))
            $fatal(1, "%s test failed", test_name);
        else
            $display("%s: Test Passed!", test_name);
        $display("================================\n");

        // Test pattern: Yellow (255,255,0)
        test_name = "Yellow";
        R = 8'd255; G = 8'd255; B = 8'd0;
        #PIPELINE_LATENCY;
        compute_ref(R, G, B, exp_y, exp_u, exp_v);
        $display("================================");
        $display("Time: %t\nTest:     %s", $time, test_name);
        $display("Input:    RGB=(%3d,%3d,%3d)", R, G, B);
        $display("Output:   YUV=(%3d,%3d,%3d)", Y, U, V);
        $display("Expected: YUV=(%3d,%3d,%3d)", exp_y, exp_u, exp_v);
        if (!within_tolerance(Y, exp_y) ||
            !within_tolerance(U, exp_u) ||
            !within_tolerance(V, exp_v))
            $fatal(1, "%s test failed", test_name);
        else
            $display("%s: Test Passed!", test_name);
        $display("================================\n");

        // Test pattern: Cyan (0,255,255)
        test_name = "Cyan";
        R = 8'd0; G = 8'd255; B = 8'd255;
        #PIPELINE_LATENCY;
        compute_ref(R, G, B, exp_y, exp_u, exp_v);
        $display("================================");
        $display("Time: %t\nTest:     %s", $time, test_name);
        $display("Input:    RGB=(%3d,%3d,%3d)", R, G, B);
        $display("Output:   YUV=(%3d,%3d,%3d)", Y, U, V);
        $display("Expected: YUV=(%3d,%3d,%3d)", exp_y, exp_u, exp_v);
        if (!within_tolerance(Y, exp_y) ||
            !within_tolerance(U, exp_u) ||
            !within_tolerance(V, exp_v))
            $fatal(1, "%s test failed", test_name);
        else
            $display("%s: Test Passed!", test_name);
        $display("================================\n");

        // Test pattern: Magenta (255,0,255)
        test_name = "Magenta";
        R = 8'd255; G = 8'd0; B = 8'd255;
        #PIPELINE_LATENCY;
        compute_ref(R, G, B, exp_y, exp_u, exp_v);
        $display("================================");
        $display("Time: %t\nTest:     %s", $time, test_name);
        $display("Input:    RGB=(%3d,%3d,%3d)", R, G, B);
        $display("Output:   YUV=(%3d,%3d,%3d)", Y, U, V);
        $display("Expected: YUV=(%3d,%3d,%3d)", exp_y, exp_u, exp_v);
        if (!within_tolerance(Y, exp_y) ||
            !within_tolerance(U, exp_u) ||
            !within_tolerance(V, exp_v))
            $fatal(1, "%s test failed", test_name);
        else
            $display("%s: Test Passed!", test_name);
        $display("================================\n");

        // Test pattern: Gray (128,128,128)
        test_name = "Gray";
        R = 8'd128; G = 8'd128; B = 8'd128;
        #PIPELINE_LATENCY;
        compute_ref(R, G, B, exp_y, exp_u, exp_v);
        $display("================================");
        $display("Time: %t\nTest:     %s", $time, test_name);
        $display("Input:    RGB=(%3d,%3d,%3d)", R, G, B);
        $display("Output:   YUV=(%3d,%3d,%3d)", Y, U, V);
        $display("Expected: YUV=(%3d,%3d,%3d)", exp_y, exp_u, exp_v);
        if (!within_tolerance(Y, exp_y) ||
            !within_tolerance(U, exp_u) ||
            !within_tolerance(V, exp_v))    
            $fatal(1, "%s test failed", test_name);
        else
            $display("%s: Test Passed!", test_name);
        $display("================================\n");
        $display("All standard pattern tests passed.");
        
        $display("All tests passed.");
    endtask

endmodule
