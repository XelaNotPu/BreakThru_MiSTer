//============================================================================
//  Break Thru — pause screen (custom overlay, independent of the MiSTer OSD)
//
//  When paused, replaces the game image with the XN logo (full-screen) and a
//  vertically-scrolling NFO read from pause.txt.  All assets live in the UNUSED
//  16 KB lead gap of the main program-ROM BRAM (dpram 0x0000-0x3FFF, which the
//  game never addresses — see brkthru_main.sv rom_rdaddr).  The main CPU is
//  frozen while paused, so this module borrows the ROM's read port (muxed in
//  brkthru_main) to fetch its assets — costing ZERO extra BRAM.
//
//  Gap layout (packed by sim/tools/pack_pause.py, embedded in the MRA):
//    0x0000  LOGO : 128x128, 4bpp, 2 px/byte (hi nibble = even x), row-major
//    0x2000  FONT : 128 chars x 8 rows/char, low nibble = 4 px (bit3 = leftmost)
//    0x2400  TEXT : 64 cols x 96 rows of ASCII (95 lines used)
//
//  Display: 256x240 active (hcnt 0..255, vcnt 8..247).  Logo scaled x2 and
//  vertically centred.  Text is a 4x7 cell font, 64 columns = 256 px, drawn in
//  bright ink with a 1 px drop-shadow for legibility over the logo.  Coverage
//  for each scan line is precomputed into a line buffer during the preceding
//  hblank (CPU frozen => ROM port free); the previous line's buffer feeds the
//  drop-shadow.  Scroll wraps for an infinite loop.
//============================================================================

module brkthru_pause
(
    input  wire        clk,
    input  wire        ce_pix,
    input  wire        reset,

    input  wire [8:0]  hcnt,        // 0..383
    input  wire [8:0]  vcnt,        // 0..271
    input  wire        pause_active,

    input  wire [6:0]  scroll_row,   // top-of-screen text row (0..94)
    input  wire [2:0]  scroll_frow,  // top-of-screen font-cell row (0..6)

    // borrowed main-ROM read port (valid only while pause_active; 1-clk latency)
    output reg  [13:0] rom_addr,    // into the 0x0000-0x3FFF gap
    input  wire [7:0]  rom_data,

    output reg  [7:0]  r,
    output reg  [7:0]  g,
    output reg  [7:0]  b
);
    // ---- asset base offsets within the gap ----
    localparam [13:0] LOGO_OFF = 14'h0000;
    localparam [13:0] FONT_OFF = 14'h2000;
    localparam [13:0] TEXT_OFF = 14'h2400;

    localparam [8:0]  H_ACTIVE  = 9'd256;   // hbstart
    localparam [8:0]  V_TOP     = 9'd8;      // vbend (first visible line)
    // Font/layout dims — MUST match sim/tools/pack_pause.py (FW=5, FH=8, ROWS=72).
    localparam        FW        = 5;         // font cell width  (5 px)
    localparam        FH        = 8;         // font cell height (8 px)
    localparam [6:0]  NCOLS     = 7'd51;     // rendered columns (51*5 = 255 px)
    localparam [6:0]  LAST_COL  = NCOLS - 7'd1;
    localparam [6:0]  LAST_ROW  = 7'd71;     // 72 NFO rows (0..71); loops at end

    localparam [23:0] INK_COL    = 24'hFFF4B4;  // bright text
    localparam [23:0] SHADOW_COL = 24'h080610;  // near-black drop shadow

    // ---- 16-colour logo palette (from pack_pause.py; quantised XN logo) ----
    function [23:0] logo_rgb(input [3:0] i);
        case (i)
            4'd0 : logo_rgb = 24'h000000; 4'd1 : logo_rgb = 24'h000000;
            4'd2 : logo_rgb = 24'h344CDB; 4'd3 : logo_rgb = 24'h000000;
            4'd4 : logo_rgb = 24'h1D0F3F; 4'd5 : logo_rgb = 24'h6A4740;
            4'd6 : logo_rgb = 24'h030203; 4'd7 : logo_rgb = 24'h351305;
            4'd8 : logo_rgb = 24'h000001; 4'd9 : logo_rgb = 24'h000A58;
            4'd10: logo_rgb = 24'h8B68D3; 4'd11: logo_rgb = 24'hAFB7EC;
            4'd12: logo_rgb = 24'hCA783C; 4'd13: logo_rgb = 24'hF5BC30;
            4'd14: logo_rgb = 24'h1A15AD; 4'd15: logo_rgb = 24'h640DC6;
            default: logo_rgb = 24'h000000;
        endcase
    endfunction

    // ---- per-line text coverage buffers (1 bit / screen pixel) ----
    reg [255:0] cov_cur;    // line being displayed
    reg [255:0] cov_prev;   // line above (feeds drop-shadow)
    reg [255:0] cov_next;   // line being precomputed (next scan line)

    // =========================================================================
    //  Coverage compute FSM — during hblank builds cov_next for the next line.
    //  Reads 64 chars + 64 font bytes; hblank (128 px * 8 clk = 1024 clk) is
    //  ample for ~5*64 = 320 clks of work.
    // =========================================================================
    // Per-column read pipeline.  ROM latency is 2 clks from issuing an address
    // (rom_addr_fsm is registered, then the dpram read is registered), so each
    // fetch needs a wait state before its data is valid:
    //   CS_CH  issue TEXT addr -> CS_CHW wait -> CS_FN read char + issue FONT addr
    //   -> CS_FNW wait -> CS_WR read font byte + expand 4 px.
    localparam CS_IDLE=0, CS_CHW=1, CS_CH=2, CS_FN=3, CS_FNW=4, CS_WR=5;
    reg [2:0]  cs;
    reg [6:0]  ccol;              // 0..NCOLS-1 (rendered columns)
    reg [6:0]  crow;              // text row of the line being computed (0..71)
    reg [2:0]  cfrow;             // font-cell row of that line (0..7)
    reg        line_done;
    reg [13:0] rom_addr_fsm;

    // next display line, and its (row,frow) derived incrementally — NO divide:
    // the first visible line loads the scroll origin; each line below advances
    // one font row, rolling to the next text row every 7 lines.
    wire [8:0] disp_next = (vcnt == 9'd271) ? 9'd0 : (vcnt + 9'd1);
    reg  [6:0] nrow;
    reg  [2:0] nfrow;
    always @(*) begin
        if (disp_next == V_TOP) begin           // top visible line -> scroll origin
            nrow = scroll_row; nfrow = scroll_frow;
        end
        else if (cfrow == 3'd7) begin            // roll to next text row (cell is FH=8 tall)
            nfrow = 3'd0; nrow = (crow == LAST_ROW) ? 7'd0 : (crow + 7'd1);
        end
        else begin
            nfrow = cfrow + 3'd1; nrow = crow;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            cs <= CS_IDLE; line_done <= 1'b0; rom_addr_fsm <= 14'd0;
        end
        else begin
            case (cs)
                CS_IDLE: begin
                    if (hcnt == H_ACTIVE && !line_done) begin
                        crow <= nrow; cfrow <= nfrow;   // advance/load (no divide)
                        ccol <= 7'd0;
                        cs   <= CS_CH;
                    end
                    else if (hcnt != H_ACTIVE) begin
                        line_done <= 1'b0;
                    end
                end
                CS_CH: begin                                    // issue TEXT + row*64 + col
                    rom_addr_fsm <= TEXT_OFF + {crow, 6'd0} + {7'd0, ccol};
                    cs <= CS_CHW;
                end
                CS_CHW: cs <= CS_FN;                            // wait for char data (2-clk latency)
                CS_FN: begin                                    // read char, issue FONT + char*8 + fontrow
                    rom_addr_fsm <= FONT_OFF + {rom_data, 3'd0} + {11'd0, cfrow};
                    cs <= CS_FNW;
                end
                CS_FNW: cs <= CS_WR;                            // wait font read
                CS_WR: begin : expand                           // expand FW=5 px (bit4=leftmost)
                    reg [8:0] pb;
                    pb = ccol * FW;                             // pixel base = col*5
                    cov_next[pb + 9'd0] <= rom_data[4];
                    cov_next[pb + 9'd1] <= rom_data[3];
                    cov_next[pb + 9'd2] <= rom_data[2];
                    cov_next[pb + 9'd3] <= rom_data[1];
                    cov_next[pb + 9'd4] <= rom_data[0];
                    if (ccol == LAST_COL) begin
                        cs <= CS_IDLE; line_done <= 1'b1;
                    end
                    else begin
                        ccol <= ccol + 7'd1; cs <= CS_CH;
                    end
                end
                default: cs <= CS_IDLE;
            endcase
        end
    end

    // rotate coverage buffers at the start of each displayed line
    always @(posedge clk) begin
        if (reset) begin cov_cur <= 256'd0; cov_prev <= 256'd0; end
        else if (ce_pix && hcnt == 9'd0) begin
            cov_prev <= cov_cur;
            cov_cur  <= cov_next;
        end
    end

    // =========================================================================
    //  Active-pixel logo fetch + composite
    // =========================================================================
    wire        active = (hcnt < H_ACTIVE) && (vcnt >= V_TOP) && (vcnt < 9'd248);
    wire [6:0]  logox  = hcnt[7:1];                 // 0..127
    wire [6:0]  logoy  = vcnt[7:1];                 // 4..123 (centred crop)
    wire [13:0] logo_a = LOGO_OFF + {logoy, 6'd0} + {8'd0, logox[6:1]}; // row*64 + x/2

    // single ROM-address driver: logo during active, FSM during hblank
    always @(*) rom_addr = (hcnt < H_ACTIVE) ? logo_a : rom_addr_fsm;

    reg [7:0] logo_byte;
    always @(posedge clk) if (hcnt < H_ACTIVE) logo_byte <= rom_data;
    wire [3:0] logo_idx = logox[0] ? logo_byte[3:0] : logo_byte[7:4];

    wire [7:0] xm1 = (hcnt[7:0] == 8'd0) ? 8'd0 : (hcnt[7:0] - 8'd1);

    always @(posedge clk) begin
        if (ce_pix) begin
            if (active) begin
                if      (cov_cur[hcnt[7:0]]) {r,g,b} <= INK_COL;      // text
                else if (cov_prev[xm1])      {r,g,b} <= SHADOW_COL;   // drop shadow
                else                         {r,g,b} <= logo_rgb(logo_idx);
            end
            else begin
                {r,g,b} <= 24'h000000;                                // border/blank
            end
        end
    end

endmodule
