//============================================================================
//  Break Thru — sprite engine (M7)
//
//  64 sprites (4 bytes each), 16x16 3bpp, optional double-height (16x32).
//  Per-line line-buffer renderer: each line evaluates all 64 sprites and draws
//  those covering the NEXT line into a double-buffered 256-px line buffer; the
//  display side reads the other bank.
//
//  SPRITE PRIORITY (verified against MAME + hardware capture, 2026-07-04):
//  MAME's draw_sprites() iterates offs 252->0 with prio_transpen, which sets the
//  priority bitmap to 31 on EVERY non-transparent pixel and blocks any later
//  draw there (PIXEL_OP_REBASE_TRANSPEN_PRIORITY in drawgfxt.ipp: `PRIORITY=31`
//  + `pmask |= 1<<31`). Net effect: FIRST-drawn sprite wins each pixel, i.e. the
//  HIGHER-offset sprite is ON TOP. We reproduce this with a plain last-write-wins
//  line buffer by processing sprites LOW->HIGH offset (sidx 0->63): the highest
//  offset is written last and therefore ends on top. This is what keeps the
//  player car (offs 184/188) drawn over its dithered shadow (offs 176/180) so
//  the shadow is hidden when grounded and only shows on the ground when jumping.
//  Decode VERIFIED (docs/video_decode.md).
//
//  Addresses to sprite RAM and sprite ROM are COMBINATIONAL (clean 1-clock
//  registered-read latency: set addr in state N, data valid in state N+1).
//
//  Sprite ROM: 3 lanes P2@0x00000, P1@0x08000, P0@0x10000 (32 KB each).
//    word_base = code*32 + subrow; cols 8-15 at +0, cols 0-7 at +16 (MSB-first).
//    pen = {P0,P1,P2}; palette index = {1'b1, color, pen}; pen0 = transparent.
//  NOTE: flip_screen not yet applied (upright only) — see status open-questions.
//============================================================================

module brkthru_sprite
(
    input  wire        clk,
    input  wire        ce_pix,
    input  wire        reset,
    input  wire [8:0]  hcnt,
    input  wire [8:0]  vcnt,

    input  wire        sr_we,
    input  wire [16:0] sr_addr,
    input  wire [7:0]  sr_data,

    output wire [7:0]  sprram_addr,
    input  wire [7:0]  sprram_q,

    output wire [2:0]  spr_pen,
    output wire [2:0]  spr_color,
    output wire        spr_prio,
    output wire        spr_transp
);
    // ---- state ----
    localparam S_IDLE=0, S_CLR=1, S_RD0=2, S_RD1=3, S_RD2=4, S_RD3=5, S_EVAL=6,
               S_FR=7, S_FR2=8, S_FL2=9, S_DRAW=10, S_NEXT=11;
    reg [3:0]  st;
    reg [7:0]  clr_x;
    reg [5:0]  sidx;
    reg [1:0]  rd_sel;
    reg        fetch_left;
    reg [7:0]  b0,b1,b2;
    reg [8:0]  target;
    reg [9:0]  code; reg [2:0] scolor; reg sprio; reg en;
    reg [8:0]  sx; reg [4:0] srow;
    reg [3:0]  drawcol;
    reg [7:0]  hRp0,hRp1,hRp2, hLp0,hLp1,hLp2;

    // combinational sprite-RAM address
    assign sprram_addr = {sidx, rd_sel};

    // sprite-position decode (valid when b0/b1/b2 latched and sprram_q = b3)
    reg dbl; reg [8:0] syv, sxv, topv, delta, hgt;
    always @(*) begin
        syv  = 9'd240 - {1'b0, b2};
        sxv  = 9'd240 - {1'b0, sprram_q};
        if (sprram_q >= 8'd248) sxv = sxv + 9'd256;   // sx < -7 -> +256
        dbl  = b0[4];
        topv = dbl ? (syv - 9'd16) : syv;
        hgt  = dbl ? 9'd32 : 9'd16;
        delta = (target - topv) & 9'h0FF;             // 8-bit vertical wrap
    end

    // sprite ROM: combinational read address
    wire [9:0]  tile  = dbl ? (srow[4] ? (code | 10'd1) : (code & ~10'd1)) : code;
    wire [14:0] wbase = {tile, 5'd0} + {11'd0, srow[3:0]};   // code*32 + subrow
    wire [14:0] raddr = wbase + (fetch_left ? 15'd16 : 15'd0);
    wire [1:0]  wlane = sr_addr[16:15];
    wire [14:0] waddr = sr_addr[14:0];
    wire [7:0]  pl2, pl1, pl0;
    dpram #(.AW(15), .DW(8)) u_p2 (.clk(clk),
        .addr_a(waddr), .data_a(sr_data), .we_a(sr_we & (wlane==2'd0)), .q_a(),
        .addr_b(raddr), .data_b(8'h00),   .we_b(1'b0),                  .q_b(pl2));
    dpram #(.AW(15), .DW(8)) u_p1 (.clk(clk),
        .addr_a(waddr), .data_a(sr_data), .we_a(sr_we & (wlane==2'd1)), .q_a(),
        .addr_b(raddr), .data_b(8'h00),   .we_b(1'b0),                  .q_b(pl1));
    dpram #(.AW(15), .DW(8)) u_p0 (.clk(clk),
        .addr_a(waddr), .data_a(sr_data), .we_a(sr_we & (wlane==2'd2)), .q_a(),
        .addr_b(raddr), .data_b(8'h00),   .we_b(1'b0),                  .q_b(pl0));

    // ---- line buffer 512x7 (2 banks x 256): {prio, color[2:0], pen[2:0]} ----
    wire       disp_bank   = vcnt[0];
    wire       render_bank = ~vcnt[0];
    reg  [8:0] lb_waddr;
    reg  [6:0] lb_wdata;
    reg        lb_we;
    wire [8:0] lb_raddr = {disp_bank, hcnt[7:0]};
    wire [6:0] lb_q;
    dpram #(.AW(9), .DW(7)) u_lbuf (.clk(clk),
        .addr_a(lb_waddr), .data_a(lb_wdata), .we_a(lb_we), .q_a(),
        .addr_b(lb_raddr), .data_b(7'd0),     .we_b(1'b0),  .q_b(lb_q));

    // Register the line-buffer output on ce_pix so the sprite layer has the SAME
    // 1-pixel pipeline latency as the fg/bg tilemaps (which register on ce_pix).
    // Without this the sprite layer is ~1 px ahead of the background at the mixer,
    // making sprites (e.g. the player car) sit slightly off vs the playfield.
    reg [6:0] lb_qr;
    always @(posedge clk) if (ce_pix) lb_qr <= lb_q;
    assign spr_pen    = lb_qr[2:0];
    assign spr_color  = lb_qr[5:3];
    assign spr_prio   = lb_qr[6];
    assign spr_transp = (lb_qr[2:0] == 3'd0);

    always @(posedge clk) begin
        lb_we <= 1'b0;
        if (reset) st <= S_IDLE;
        else case (st)
            S_IDLE: if (ce_pix && hcnt == 9'd0) begin
                        target <= vcnt + 9'd1; clr_x <= 8'd0; st <= S_CLR;
                    end
            S_CLR:  begin
                        lb_waddr <= {render_bank, clr_x}; lb_wdata <= 7'd0; lb_we <= 1'b1;
                        clr_x <= clr_x + 8'd1;
                        // process LOW->HIGH offset so higher-offset sprites are
                        // written last (on top) — see priority note in header.
                        if (clr_x == 8'd255) begin sidx <= 6'd0; rd_sel <= 2'd0; st <= S_RD0; end
                    end
            // combinational addr {sidx,rd_sel}; data valid one state later
            S_RD0:  begin rd_sel <= 2'd1; st <= S_RD1; end                  // addr {sidx,0}
            S_RD1:  begin b0 <= sprram_q; rd_sel <= 2'd2; st <= S_RD2; end  // b0 = [sidx,0]
            S_RD2:  begin b1 <= sprram_q; rd_sel <= 2'd3; st <= S_RD3; end  // b1 = [sidx,1]
            S_RD3:  begin b2 <= sprram_q; st <= S_EVAL; end                 // b2 = [sidx,2]
            S_EVAL: begin
                        // sprram_q = b3 = [sidx,3]; comb block gives sxv/topv/delta/hgt
                        en     <= b0[0];
                        sprio  <= b0[3];
                        scolor <= b0[7:5];
                        code   <= {b0[2:1], b1};
                        sx     <= sxv;
                        srow   <= delta[4:0];
                        fetch_left <= 1'b0;                     // raddr = wbase (right half)
                        if (b0[0] && (delta < hgt)) st <= S_FR;
                        else                        st <= S_NEXT;
                    end
            S_FR:   begin fetch_left <= 1'b1; st <= S_FR2; end  // raddr becomes wbase+16
            S_FR2:  begin hRp2<=pl2; hRp1<=pl1; hRp0<=pl0; st <= S_FL2; end  // right bytes (cols 8-15)
            S_FL2:  begin hLp2<=pl2; hLp1<=pl1; hLp0<=pl0; drawcol<=4'd0; st <= S_DRAW; end // left (0-7)
            S_DRAW: begin : draw
                        reg [7:0] bp2, bp1, bp0; reg [2:0] bidx; reg [2:0] pen; reg [8:0] px;
                        if (drawcol < 4'd8) begin bp2=hLp2; bp1=hLp1; bp0=hLp0; end  // cols 0-7
                        else                begin bp2=hRp2; bp1=hRp1; bp0=hRp0; end  // cols 8-15
                        bidx = 3'd7 - drawcol[2:0];
                        pen  = {bp0[bidx], bp1[bidx], bp2[bidx]};   // {P0,P1,P2}
                        px   = sx + {5'd0, drawcol};
                        if (pen != 3'd0 && !px[8]) begin
                            lb_waddr <= {render_bank, px[7:0]};
                            lb_wdata <= {sprio, scolor, pen};
                            lb_we    <= 1'b1;
                        end
                        if (drawcol == 4'd15) st <= S_NEXT; else drawcol <= drawcol + 4'd1;
                    end
            S_NEXT: if (sidx == 6'd63) st <= S_IDLE;
                    else begin sidx <= sidx + 6'd1; rd_sel <= 2'd0; st <= S_RD0; end
            default: st <= S_IDLE;
        endcase
    end
endmodule
