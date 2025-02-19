# RTL n-bit RGB to YUV Converter

A pipelined RGB to YUV color space converter implemented in SystemVerilog, supporting both Rec.601 and Rec.709 standards.

## Features

- Support for both Rec.601 and Rec.709 color space standards
- Configurable bit depth (default 8-bit)
- 6-stage pipeline architecture for high throughput
- Automatic clamping of output values to valid range
- Comprehensive testbench with standard color patterns and random tests

## Design Parameters

- `BIT_DEPTH`: Input/output precision (default: 8 bits)
- `MULT_WIDTH`: Fixed-point multiplication precision (default: 8 bits)
- `REC_STANDARD`: Color space standard selection (0: Rec.601, 1: Rec.709)

## Interface

```systemverilog
module rtl_rgb2yuv (
    input                          clk, areset,
    input  logic [BIT_DEPTH-1:0]   R, G, B,    // RGB input
    output logic [BIT_DEPTH-1:0]   Y, U, V     // YUV output
);
```

## Color Space Coefficients

### Rec.601
- Y = 0.299R + 0.587G + 0.114B
- U = (B - Y) × 0.564 + 128
- V = (R - Y) × 0.713 + 128

### Rec.709
- Y = 0.2126R + 0.7152G + 0.0722B
- U = (B - Y) × 0.539 + 128
- V = (R - Y) × 0.635 + 128

## Implementation Details (Zynq Ultrascale+)

- 6-stage pipelined architecture for optimal performance
- Fixed-point arithmetic for efficient hardware implementation
- Built-in value clamping to ensure valid output range
- Fmax: 500 MHz (2.0 ns period)

## Verification

The testbench (`rtl_rgb2yuv_tb.sv`) includes:
- Standard color pattern tests (black, white, primary colors)
- Random pattern tests
- Automatic result verification against software model
- Configurable tolerance for comparison

## Usage

1. Set desired parameters in the instantiation:
```systemverilog
rtl_rgb2yuv #(
    .BIT_DEPTH(8),
    .MULT_WIDTH(8),
    .REC_STANDARD(0)  // 0 for Rec.601, 1 for Rec.709
) rgb2yuv_inst (
    .clk(clk),
    .areset_n(reset),
    .R(r_in),
    .G(g_in),
    .B(b_in),
    .Y(y_out),
    .U(u_out),
    .V(v_out)
);
```

2. Provide active-high clock and active-low asynchronous reset
3. Input RGB values on rising clock edge
4. Sample YUV outputs 6 clock cycles later

## Timing Constraints

- Target clock frequency: 500 MHz
- Clock port: E12 (LVCMOS33)
