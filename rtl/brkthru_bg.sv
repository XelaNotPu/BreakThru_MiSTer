//============================================================================
//  Break Thru — background tilemap renderer (M6)
//
//  32x16 map of 16x16, 3bpp tiles (TILEMAP_SCAN_COLS), 512x256, 9-bit hscroll,
//  transparent pen 0.  Decode VERIFIED (docs/video_decode.md):
//    code   = bgram_q & 0x3FF ; attr = bgram_q[10] (byte1 bit2)
//    region byte offset O = code[9:8]*0x8000 + (code[7] ? 0x1000 : 0)
//    TB = O + tile*32 ; layout2 iff code[7]
//    row y: packed byte Bpk = TB+y+gadd (plane1 hi-nibble, plane2 lo-nibble)
//           plane0 byte  Bp0 = Bpk + (layout1 ? 0x4000 : 0x3000), plane0 in
//           low nibble (layout1) or high nibble (layout2)
//    x-groups: A(0-3)+0, B(4-7)+0x2000, C(8-11)+16, D(12-15)+0x2010
//  pen = {plane0, plane1, plane2}; palette index = {1'b1, cs, attr, pen}.
//
//  Tiles ROM (128 KB) is one dual-port BRAM: port A = ioctl write / packed-byte
//  read, port B = plane0-byte read, giving both bytes in a single cycle.
//============================================================================

module brkthru_bg
(
    input  wire        clk,
    input  wire        ce_pix,
    input  wire [8:0]  hcnt,        // 0..383 (visible 0..255)
    input  wire [8:0]  vcnt,        // 0..271 (visible 8..247)
    input  wire [8:0]  bgscroll,    // 9-bit horizontal scroll
    input  wire [2:0]  bg_pal_hi,   // control[5:3] = colour-set high (cs)

    // tiles ROM load (tiles region byte address 0..0x1FFFF)
    input  wire        tr_we,
    input  wire [16:0] tr_addr,
    input  wire [7:0]  tr_data,

    // background VRAM read (16-bit tile word) — to brkthru_main port B
    output wire [8:0]  bgram_addr,
    input  wire [15:0] bgram_q,

    // output pixel
    output reg  [2:0]  bg_pen,
    output reg  [3:0]  bg_color,    // {cs[2:0], attr}
    output reg         bg_transp
);
    // ---- screen -> tilemap coordinates ----
    wire [8:0] sy   = vcnt - 9'd8;
    wire [8:0] bg_x = hcnt + bgscroll;      // wraps mod 512 (9-bit)
    wire [4:0] tx   = bg_x[8:4];
    wire [3:0] colp = bg_x[3:0];
    wire [3:0] ty   = sy[7:4];
    wire [3:0] rowp = sy[3:0];

    // tile index (SCAN_COLS): tx*16 + ty
    assign bgram_addr = {tx, ty};

    // ---- decode the fetched tile word ----
    wire [9:0] code = bgram_q[9:0];
    wire       attr = bgram_q[10];          // byte1 bit2
    wire       layout2 = code[7];
    wire [6:0] tile = code[6:0];
    // region byte offset O = code[9:8]*0x8000 + (code[7]?0x1000:0)
    wire [16:0] O  = {code[9:8], 15'd0} + (code[7] ? 17'h1000 : 17'h0);
    wire [16:0] TB = O + {5'd0, tile, 5'd0}; // tile*32

    // x-group add: A=0, B=0x2000, C=16, D=0x2010  (group = colp[3:2])
    wire [16:0] gadd = (colp[2] ? 17'h2000 : 17'h0) | (colp[3] ? 17'h10 : 17'h0);
    wire [1:0]  k    = colp[1:0];            // pixel within nibble group

    wire [16:0] Bpk = TB + {13'd0, rowp} + gadd;
    wire [16:0] Bp0 = Bpk + (layout2 ? 17'h3000 : 17'h4000);

    // tiles ROM: port A = write-or-packed-read, port B = plane0-read
    wire [7:0] pk_byte, p0_byte;
    dpram #(.AW(17), .DW(8)) u_tiles (
        .clk(clk),
        .addr_a(tr_we ? tr_addr : Bpk), .data_a(tr_data), .we_a(tr_we), .q_a(pk_byte),
        .addr_b(Bp0),                   .data_b(8'h00),    .we_b(1'b0), .q_b(p0_byte)
    );

    // assemble pen for pixel k in group (MSB-first: bit 3-k within the nibble)
    wire [2:0] nb = 3'd3 - {1'b0, k};             // nibble bit index (0..3)
    wire p1 = pk_byte[3'd4 + nb];                 // plane1 = high nibble
    wire p2 = pk_byte[nb];                        // plane2 = low nibble
    wire p0 = layout2 ? p0_byte[3'd4 + nb]        // layout2: plane0 high nibble
                      : p0_byte[nb];              // layout1: plane0 low nibble
    wire [2:0] pen = {p0, p1, p2};

    always @(posedge clk) if (ce_pix) begin
        bg_pen    <= pen;
        bg_color  <= {bg_pal_hi, attr};
        bg_transp <= (pen == 3'd0);
    end
endmodule
