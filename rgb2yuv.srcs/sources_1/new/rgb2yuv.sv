`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/10/2025 05:17:37 PM
// Design Name: 
// Module Name: rgb2yuv
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

module rtl_rgb2yuv #(
    parameter BIT_DEPTH    = 8, // Typically 8, 10, or 12 bits for RGB/YUV
    parameter MULT_WIDTH   = 8, // Defines multiplication precision
    parameter REC_STANDARD = 0  // 0: Rec.601, 1: Rec.709
)(
    input                                  clk, areset_n,
    input  logic unsigned  [BIT_DEPTH-1:0] R, G, B, // RGB input
    output logic unsigned  [BIT_DEPTH-1:0] Y, U, V  // YUV output
);
    localparam Y_WIDTH = BIT_DEPTH + 2; // Need 2 bits: 1 for range > 255 (avoid overflow), 1 for negative numbers (sign bit)
    always_comb assert (MULT_WIDTH == 8) else $error(); // Only 8-bit multiplier supported for now

    // Constants
    localparam real Kr_601 = 0.299; // R 
    localparam real Kg_601 = 0.587; // G
    localparam real Kb_601 = 0.114; // B

    localparam real Kr_709 = 0.2126; // R 
    localparam real Kg_709 = 0.7152; // G
    localparam real Kb_709 = 0.0722; // B

    // Chroma scaling factors
    localparam real KCb_FLOAT_601 = 1.0/(2.0*(1.0-Kb_601));
    localparam real KCr_FLOAT_601 = 1.0/(2.0*(1.0-Kr_601));

    localparam real KCb_FLOAT_709 = 1.0/(2.0*(1.0-Kb_709));
    localparam real KCr_FLOAT_709 = 1.0/(2.0*(1.0-Kr_709));

    // Coefficients
    localparam signed [2*MULT_WIDTH-1:0] KCb = REC_STANDARD ? KCb_FLOAT_709 * (2**MULT_WIDTH) : 
                                                              KCb_FLOAT_601 * (2**MULT_WIDTH);

    localparam signed [2*MULT_WIDTH-1:0] KCr = REC_STANDARD ? KCr_FLOAT_709 * (2**MULT_WIDTH) : 
                                                              KCr_FLOAT_601 * (2**MULT_WIDTH);

    localparam int COEFF_601_Y [3] = '{
        int'(Kr_601  * (2**MULT_WIDTH)),  // R
        int'(Kg_601  * (2**MULT_WIDTH)),  // G
        int'(Kb_601  * (2**MULT_WIDTH))   // B
    };

    localparam int COEFF_709_Y [3] = '{
        int'(Kr_709 * (2**MULT_WIDTH)),  // R
        int'(Kg_709 * (2**MULT_WIDTH)),  // G
        int'(Kb_709 * (2**MULT_WIDTH))   // B
    };

    // Stage 1 pipeline registers
    logic unsigned [Y_WIDTH+MULT_WIDTH-1:0]   y_mult_s1, u_mult_s1, v_mult_s1;
    logic unsigned [Y_WIDTH+MULT_WIDTH-1:0]   y_mult_s2, u_mult_s2, v_mult_s2;
    logic unsigned [Y_WIDTH-1:0]              red_s1, blue_s1, red_s2, blue_s2;

    logic unsigned [Y_WIDTH+MULT_WIDTH-1:0]   sum_yuv;
    logic signed   [Y_WIDTH+MULT_WIDTH-1:0]   u_s3, v_s3, u_s4, v_s4;
    logic unsigned [Y_WIDTH-1:0]              y_s3, y_s4, y_s5, y_s6;

    logic signed   [Y_WIDTH+2*MULT_WIDTH-1:0] cb_s5, cr_s5;
    logic signed   [Y_WIDTH+2*MULT_WIDTH-1:0] cb_s6, cr_s6;

    // Coefficient selection based on standard
    wire [BIT_DEPTH+MULT_WIDTH-1:0] coeff_y_r = REC_STANDARD ? COEFF_709_Y[0] : COEFF_601_Y[0];
    wire [BIT_DEPTH+MULT_WIDTH-1:0] coeff_y_g = REC_STANDARD ? COEFF_709_Y[1] : COEFF_601_Y[1];
    wire [BIT_DEPTH+MULT_WIDTH-1:0] coeff_y_b = REC_STANDARD ? COEFF_709_Y[2] : COEFF_601_Y[2];

    // Pipeline stage 1: Multiply and Input Capture 
    always_ff @(posedge clk or negedge areset_n) begin 
        if (!areset_n) begin
            {y_mult_s1, u_mult_s1, v_mult_s1} <= '0;
            {red_s1, blue_s1}                 <= '0;
        end else begin
            y_mult_s1                         <= coeff_y_r * R;
            u_mult_s1                         <= coeff_y_g * G;
            v_mult_s1                         <= coeff_y_b * B;
            red_s1                            <= R;
            blue_s1                           <= B;
        end
    end

    // Pipeline stage 2: Latch Multiplication Results
    always_ff @(posedge clk or negedge areset_n) begin
        if (!areset_n) begin
            {y_mult_s2, u_mult_s2, v_mult_s2} <= '0;
        end else begin
            {y_mult_s2, u_mult_s2, v_mult_s2} <= {y_mult_s1, u_mult_s1, v_mult_s1};
            {red_s2, blue_s2}                 <= {red_s1, blue_s1};
        end
    end

    // Pipeline stage 3: Sum and Intermediate Calculation
    always_ff @(posedge clk or negedge areset_n) begin
        if (!areset_n) begin
            sum_yuv            <= '0;
            {y_s3, u_s3, v_s3} <= '0;
        end else begin
            sum_yuv            <= y_mult_s2 + u_mult_s2 + v_mult_s2;
            y_s3               <= (sum_yuv + (1<<(MULT_WIDTH - 1))) >> MULT_WIDTH;
            u_s3               <= (blue_s2 << MULT_WIDTH) - sum_yuv;
            v_s3               <= (red_s2 << MULT_WIDTH) - sum_yuv;
        end
    end

    // Pipeline stage 4: Latch Intermediate Values
    always_ff @(posedge clk or negedge areset_n) begin
        if (!areset_n) begin
            {y_s4, u_s4, v_s4} <= '0;
        end else begin
            {y_s4, u_s4, v_s4} <= {y_s3, u_s3, v_s3};
        end
    end

    // Pipeline stage 5: Final Chroma Scaling Calculation
    always_ff @(posedge clk or negedge areset_n) begin
        if (!areset_n) begin
            {cb_s5, cr_s5, y_s5} <= '0;
        end else begin
            cb_s5                <= (128 << (2*MULT_WIDTH)) + (KCb * u_s4);
            cr_s5                <= (128 << (2*MULT_WIDTH)) + (KCr * v_s4);
            y_s5                 <= y_s4;
        end
    end

    // Pipeline stage 6: Chroma Scaling Output
    always_ff @(posedge clk or negedge areset_n) begin
        if (!areset_n) begin
            {cb_s6, cr_s6, y_s6} <= '0;
        end else begin
            cb_s6                <= (cb_s5 + (1<<((2*MULT_WIDTH) - 1))) >> (2*MULT_WIDTH);
            cr_s6                <= (cr_s5 + (1<<((2*MULT_WIDTH) - 1))) >> (2*MULT_WIDTH);
            y_s6                 <= y_s5;
        end
    end

    // Pipeline stage 7: Output register
    always_ff @(posedge clk or negedge areset_n) begin
        if (!areset_n) begin
            {Y, U, V}      <= '0;
        end else begin
            Y              <= y_s6 > 255 ? 255 : y_s6;                   // Y
            U              <= cb_s6 < 0 ? 0 : cb_s6 > 255 ? 255 : cb_s6; // U
            V              <= cr_s6 < 0 ? 0 : cr_s6 > 255 ? 255 : cr_s6; // V
        end
    end

endmodule