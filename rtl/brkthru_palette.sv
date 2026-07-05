//============================================================================
//  Break Thru — palette (M8)
//
//  256 colors from two PROMs (hardware_notes §8):
//    13.bin (R/G): low nibble = RED, high nibble = GREEN
//    14.bin (B):   low nibble = BLUE
//  4-bit channel -> 8-bit via resistor weights {bit0:0x0E, bit1:0x1F, bit2:0x43, bit3:0x8F}.
//
//  PROMs loaded via ioctl into the "proms" region (0x200): addr[8]=0 -> 13.bin (R/G),
//  addr[8]=1 -> 14.bin (B).  Lookup: pal_index (0..255) -> r,g,b (1-clk BRAM latency).
//============================================================================

module brkthru_palette
(
    input  wire        clk,

    // ioctl PROM load (proms region, 0..0x1FF)
    input  wire        prom_we,
    input  wire [8:0]  prom_addr,
    input  wire [7:0]  prom_data,

    // lookup
    input  wire [7:0]  pal_index,
    output wire [7:0]  r,
    output wire [7:0]  g,
    output wire [7:0]  b
);
    // 4-bit -> 8-bit resistor-ladder weight (sum of 0x0E,0x1F,0x43,0x8F)
    function [7:0] w4to8(input [3:0] v);
        w4to8 = (v[0] ? 8'h0E : 8'h00)
              + (v[1] ? 8'h1F : 8'h00)
              + (v[2] ? 8'h43 : 8'h00)
              + (v[3] ? 8'h8F : 8'h00);
    endfunction

    wire [7:0] rg_q, b_q;

    // R/G PROM (13.bin) — written when prom_addr[8]==0
    dpram #(.AW(8), .DW(8)) u_rg (
        .clk(clk),
        .addr_a(prom_addr[7:0]), .data_a(prom_data), .we_a(prom_we & ~prom_addr[8]), .q_a(),
        .addr_b(pal_index),      .data_b(8'h00),     .we_b(1'b0),                    .q_b(rg_q)
    );

    // B PROM (14.bin) — written when prom_addr[8]==1
    dpram #(.AW(8), .DW(8)) u_b (
        .clk(clk),
        .addr_a(prom_addr[7:0]), .data_a(prom_data), .we_a(prom_we & prom_addr[8]), .q_a(),
        .addr_b(pal_index),      .data_b(8'h00),     .we_b(1'b0),                   .q_b(b_q)
    );

    assign r = w4to8(rg_q[3:0]);
    assign g = w4to8(rg_q[7:4]);
    assign b = w4to8(b_q[3:0]);
endmodule
