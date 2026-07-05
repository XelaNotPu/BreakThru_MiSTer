//============================================================================
//  Break Thru — video timing generator
//
//  Reproduces MAME's screen.set_raw(12_MHz_XTAL/2, 384, 0, 256, 272, 8, 248)
//  (brkthru.cpp line 802).  See docs/hardware_notes.md §2.
//
//  set_raw signature: (pixclock, htotal, hbend, hbstart, vtotal, vbend, vbstart)
//     pixclock = 6 MHz   htotal = 384  hbend = 0   hbstart = 256
//                        vtotal = 272  vbend = 8   vbstart = 248
//  => visible 256 x 240, HSync 15.625 kHz, VSync 57.44 Hz.
//
//  Runs on the system clock with a 1-cycle pixel enable (ce_pix @ 6 MHz).
//============================================================================

module breakthru_video_timing
(
    input  wire        clk,        // system clock
    input  wire        ce_pix,     // 6 MHz pixel enable (1 clk wide)
    input  wire        reset,

    output reg  [8:0]  hcnt,       // 0..HTOTAL-1
    output reg  [8:0]  vcnt,       // 0..VTOTAL-1

    output wire        hblank,
    output wire        vblank,
    output wire        hsync,
    output wire        vsync,
    output wire        hde,        // horizontal data enable (visible)
    output wire        vde,        // vertical   data enable (visible)

    output reg         vblank_rise // 1 clk pulse at the first line of vblank (drives main-CPU NMI)
);

    // ---- Timing constants (MAME set_raw) — see hardware_notes §2 -------------
    localparam [8:0] HTOTAL  = 9'd384;  // total pixels per line
    /* verilator lint_off UNUSEDPARAM */
    localparam [8:0] HBEND   = 9'd0;    // first visible pixel (hbend); 0 => hde low bound implicit
    /* verilator lint_on UNUSEDPARAM */
    localparam [8:0] HBSTART = 9'd256;  // first blanked pixel (hbstart) -> 256 visible
    localparam [8:0] VTOTAL  = 9'd272;  // total lines per frame
    localparam [8:0] VBEND   = 9'd8;    // first visible line (vbend)
    localparam [8:0] VBSTART = 9'd248;  // first blanked line (vbstart) -> 240 visible

    // ---- Sync pulse placement -------------------------------------------------
    // NOTE: MAME's set_raw does not specify sync position/width, only blanking.
    // These are placed inside the blanking interval per common MiSTer arcade
    // practice and are tunable against real hardware later. Active-high pulses
    // (the sys/ framework handles final polarity), matching the template.
    localparam [8:0] HSSTART = 9'd288;  // within hblank (256..383)
    localparam [8:0] HSEND   = 9'd320;  // 32-pixel hsync
    localparam [8:0] VSSTART = 9'd254;  // within vblank (248..271)
    localparam [8:0] VSEND   = 9'd258;  // 4-line vsync

    // ---- Counters -------------------------------------------------------------
    wire hmax = (hcnt == HTOTAL - 9'd1);
    wire vmax = (vcnt == VTOTAL - 9'd1);

    always @(posedge clk) begin
        vblank_rise <= 1'b0;
        if (reset) begin
            hcnt <= 9'd0;
            vcnt <= 9'd0;
        end
        else if (ce_pix) begin
            if (hmax) begin
                hcnt <= 9'd0;
                if (vmax) begin
                    vcnt <= 9'd0;
                end
                else begin
                    vcnt <= vcnt + 9'd1;
                    // pulse when we step onto the first blanked line
                    if (vcnt == VBSTART - 9'd1)
                        vblank_rise <= 1'b1;
                end
            end
            else begin
                hcnt <= hcnt + 9'd1;
            end
        end
    end

    // ---- Derived video strobes ------------------------------------------------
    // HBEND == 0, so the low bound is always satisfied (kept as a comment to
    // avoid an always-true unsigned comparison; see HBEND localparam above).
    assign hde    = (hcnt < HBSTART);
    assign vde    = (vcnt >= VBEND)   && (vcnt < VBSTART);
    assign hblank = ~hde;
    assign vblank = ~vde;
    assign hsync  = (hcnt >= HSSTART) && (hcnt < HSEND);
    assign vsync  = (vcnt >= VSSTART) && (vcnt < VSEND);

endmodule
