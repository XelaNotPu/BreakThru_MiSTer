//============================================================================
//  Break Thru — foreground / text tilemap renderer (M5)
//
//  32x32 map of 8x8, 3bpp chars (TILEMAP_SCAN_ROWS), palette pens 0x00-0x07,
//  transparent pen 0, drawn on top of all other layers (hardware_notes §5.1).
//
//  Char decode VERIFIED (docs/video_decode.md): the 8-pixel row of char `code`
//  at row `y` comes from 4 bytes B1..B4 at chars-region addr {group,code,y}:
//     B1 = {00,code,y}: plane1 hi-nibble, plane2 lo-nibble  (right pixels 4-7)
//     B2 = {01,code,y}: plane1 hi-nibble, plane2 lo-nibble  (left  pixels 0-3)
//     B3 = {10,code,y}: plane0 lo-nibble                    (right pixels 4-7)
//     B4 = {11,code,y}: plane0 lo-nibble                    (left  pixels 0-3)
//  pen = {plane0, plane1, plane2}  (MAME ordering: offset-32772 plane = MSB).
//
//  The char ROM is held as 4 parallel 2Kx8 lanes (one per group) so the whole
//  row is fetched in one read. Output pen is registered on ce_pix (a small,
//  layer-consistent pixel-pipeline latency compensated in the video mixer).
//============================================================================

module brkthru_char
(
    input  wire        clk,
    input  wire        ce_pix,
    input  wire [8:0]  hcnt,      // 0..383 (visible 0..255)
    input  wire [8:0]  vcnt,      // 0..271 (visible 8..247)

    // char ROM load (chars region byte address 0..0x1FFF)
    input  wire        cr_we,
    input  wire [12:0] cr_addr,
    input  wire [7:0]  cr_data,

    // foreground VRAM read port (to brkthru_main port B)
    output wire [9:0]  fgram_addr,
    input  wire [7:0]  fgram_q,

    // output pixel
    output reg  [2:0]  fg_pen,
    output reg         fg_transp   // 1 = transparent
);
    // visible pixel coordinates
    wire [8:0] sy = vcnt - 9'd8;           // 0..239 in visible region
    wire [4:0] tx = hcnt[7:3];
    wire [4:0] ty = sy[7:3];
    wire [2:0] col = hcnt[2:0];
    wire [2:0] row = sy[2:0];

    // tile index (SCAN_ROWS): ty*32 + tx
    assign fgram_addr = {ty, tx};
    wire [7:0] code = fgram_q;

    // char ROM: 4 lanes (2Kx8), read all four at {code,row}
    wire [10:0] rdaddr = {code, row};
    wire [1:0]  wlane  = cr_addr[12:11];
    wire [10:0] waddr  = cr_addr[10:0];
    wire [7:0]  B1, B2, B3, B4;

    dpram #(.AW(11), .DW(8)) u_l0 ( .clk(clk),
        .addr_a(waddr), .data_a(cr_data), .we_a(cr_we & (wlane==2'd0)), .q_a(),
        .addr_b(rdaddr),.data_b(8'h00),   .we_b(1'b0),                  .q_b(B1) );
    dpram #(.AW(11), .DW(8)) u_l1 ( .clk(clk),
        .addr_a(waddr), .data_a(cr_data), .we_a(cr_we & (wlane==2'd1)), .q_a(),
        .addr_b(rdaddr),.data_b(8'h00),   .we_b(1'b0),                  .q_b(B2) );
    dpram #(.AW(11), .DW(8)) u_l2 ( .clk(clk),
        .addr_a(waddr), .data_a(cr_data), .we_a(cr_we & (wlane==2'd2)), .q_a(),
        .addr_b(rdaddr),.data_b(8'h00),   .we_b(1'b0),                  .q_b(B3) );
    dpram #(.AW(11), .DW(8)) u_l3 ( .clk(clk),
        .addr_a(waddr), .data_a(cr_data), .we_a(cr_we & (wlane==2'd3)), .q_a(),
        .addr_b(rdaddr),.data_b(8'h00),   .we_b(1'b0),                  .q_b(B4) );

    // assemble the pen for the current column (see header table)
    //   cc = col[1:0] within the 4-pixel nibble group; col[2] selects left/right
    wire [1:0] cc      = col[1:0];
    wire [7:0] byte_hl = col[2] ? B1 : B2;   // planes 1,2 source
    wire [7:0] byte_p0 = col[2] ? B3 : B4;   // plane 0 source
    wire p1 = byte_hl[7 - cc];               // plane1 = high nibble (bit 7..4)
    wire p2 = byte_hl[3 - cc];               // plane2 = low  nibble (bit 3..0)
    wire p0 = byte_p0[3 - cc];               // plane0 = low  nibble
    wire [2:0] pen = {p0, p1, p2};

    always @(posedge clk) if (ce_pix) begin
        fg_pen    <= pen;
        fg_transp <= (pen == 3'd0);
    end
endmodule
