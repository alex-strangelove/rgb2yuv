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
    input                                  clk, areset,
    input  logic unsigned  [BIT_DEPTH-1:0] R, G, B, // RGB input
    output logic unsigned  [BIT_DEPTH-1:0] Y, U, V  // YUV output
);
    localparam Y_WIDTH = BIT_DEPTH + 2; // Need 2 bits: 1 for range > 255 (avoid overflow), 1 for negative numbers (sign bit)
    always_comb assert (MULT_WIDTH == 8) else $error();

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

    // Pipeline registers
    logic unsigned [Y_WIDTH+MULT_WIDTH-1:0]   y_mult_r, y_mult_g, y_mult_b;
    logic unsigned [Y_WIDTH+MULT_WIDTH-1:0]   y_mult, u_mult, v_mult;
    logic unsigned [Y_WIDTH-1:0]              red_r, blue_r;

    logic unsigned [Y_WIDTH+MULT_WIDTH-1:0]   sum_rgb;
    logic signed   [Y_WIDTH+MULT_WIDTH-1:0]   u0, v0, u1, v1;
    logic unsigned [Y_WIDTH-1:0]              y0, y1;

    logic signed   [Y_WIDTH+2*MULT_WIDTH-1:0] cb1, cr1;
    logic signed   [Y_WIDTH-1:0]              cb2, cr2;
    logic unsigned [Y_WIDTH-1:0]              y2;

    // Coefficient selection based on standard
    wire [BIT_DEPTH+MULT_WIDTH-1:0] coeff_y_r = REC_STANDARD ? COEFF_709_Y[0] : COEFF_601_Y[0];
    wire [BIT_DEPTH+MULT_WIDTH-1:0] coeff_y_g = REC_STANDARD ? COEFF_709_Y[1] : COEFF_601_Y[1];
    wire [BIT_DEPTH+MULT_WIDTH-1:0] coeff_y_b = REC_STANDARD ? COEFF_709_Y[2] : COEFF_601_Y[2];

    // Pipeline stage 1: Multiply and Input Capture 
    always_ff @(posedge clk or negedge areset) begin 
        if (!areset) begin
            {y_mult_r, y_mult_g, y_mult_b} <= '0;
            {red_r, blue_r}                <= '0;
        end else begin
            y_mult_r                       <= coeff_y_r * R;
            y_mult_g                       <= coeff_y_g * G;
            y_mult_b                       <= coeff_y_b * B;
            red_r                          <= R;
            blue_r                         <= B;
        end
    end

    // Pipeline stage 2: Latch Multiplication Results
    always_ff @(posedge clk or negedge areset) begin
        if (!areset) begin
            {y_mult, u_mult, v_mult} <= '0;
        end else begin
            {y_mult, u_mult, v_mult} <= {y_mult_r, y_mult_g, y_mult_b};
        end
    end

    // Pipeline stage 3: Sum and Intermediate Calculation
    always_ff @(posedge clk or negedge areset) begin
        if (!areset) begin
            sum_rgb         <= '0;
            {y0, u0, v0}    <= '0;
        end else begin
            sum_rgb         <= y_mult + u_mult + v_mult;
            y0              <= (sum_rgb + (1<<(MULT_WIDTH - 1))) >> MULT_WIDTH;
            u0              <= (blue_r << MULT_WIDTH) - sum_rgb;
            v0              <= (red_r << MULT_WIDTH) - sum_rgb;
        end
    end

    // Pipeline stage 4: Latch Intermediate Values
    always_ff @(posedge clk or negedge areset) begin
        if (!areset) begin
            {y1, u1, v1} <= '0;
        end else begin
            {y1, u1, v1} <= {y0, u0, v0};
        end
    end

    // Pipeline stage 5: Final Chroma Scaling Calculation
    always_ff @(posedge clk or negedge areset) begin
        if (!areset) begin
            {cb1, cr1, y2} <= '0;
        end else begin
            cb1            <= (128 << (2*MULT_WIDTH)) + (KCb * u1);
            cr1            <= (128 << (2*MULT_WIDTH)) + (KCr * v1);
            
            y2             <= y1;
            cb2            <= (cb1 + (1<<((2*MULT_WIDTH) - 1))) >> (2*MULT_WIDTH);
            cr2            <= (cr1 + (1<<((2*MULT_WIDTH) - 1))) >> (2*MULT_WIDTH);
        end
    end

    // Pipeline stage 6: Output register
    always_ff @(posedge clk or negedge areset) begin
        if (!areset) begin
            {Y, U, V} <= '0;
        end else begin
            Y <= y2 > 255 ? 255 : y2;                 // Y
            U <= cb2 < 0 ? 0 : cb2 > 255 ? 255 : cb2; // U
            V <= cr2 < 0 ? 0 : cr2 > 255 ? 255 : cr2; // V
        end
    end

endmodule