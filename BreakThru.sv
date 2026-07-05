//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 1;               // signed
assign AUDIO_L = paused ? 16'sd0 : sound_out;  // mute while paused (CPUs frozen)
assign AUDIO_R = paused ? 16'sd0 : sound_out;
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"Break Thru;;",
	"-;",
	"DIP;",                       // DIP Switches page (from the MRA <switches>)
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"J1,Fire,Accelerate;",              // action buttons (bits 4,5); Coin/Start/Pause
	"jn,A,B;",                          // (bits 10/11/12) come from the MRA <buttons>

	"V,v",`BUILD_DATE
};

// DIP switches delivered by the MRA <switches base="16"> into status[]:
//   status[23:16] = DSW1 (8 bits), status[28:24] = DSW2 low 5 bits
wire [7:0] dsw1_bus = status[23:16];
wire [4:0] dsw2_bus = status[28:24];

wire forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;
wire  [15:0] joystick_0, joystick_1;

// ROM download (ioctl) — MRA concatenates all regions into index 0, byte stream
wire        ioctl_download;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire  [7:0] ioctl_index;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask(0),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),

	.ps2_key(ps2_key)
);

// ---- ROM download demux (download stream layout, see docs/rom_map.md) ----
// index 0 concatenates: maincpu(0x00000) chars(0x20000) tiles(0x22000)
//   sprites(0x42000) proms(0x5A000) audiocpu(0x5A200)
wire dl = ioctl_download && (ioctl_index == 8'd0);
wire main_rom_we = ioctl_wr && dl && (ioctl_addr <  27'h20000);
wire char_we     = ioctl_wr && dl && (ioctl_addr >= 27'h20000) && (ioctl_addr < 27'h22000);
wire tiles_we    = ioctl_wr && dl && (ioctl_addr >= 27'h22000) && (ioctl_addr < 27'h42000);
wire sprite_we   = ioctl_wr && dl && (ioctl_addr >= 27'h42000) && (ioctl_addr < 27'h5A000);
wire prom_we     = ioctl_wr && dl && (ioctl_addr >= 27'h5A000) && (ioctl_addr < 27'h5A200);
wire audio_we    = ioctl_wr && dl && (ioctl_addr >= 27'h5A200) && (ioctl_addr < 27'h62200);
wire [14:0] audio_wr_addr = ioctl_addr - 27'h5A200;        // audiocpu 0x5A200 -> 0..0x7FFF
// chars/proms bases are aligned (low bits = offset); tiles/sprites bases are not
wire [12:0] char_wr_addr   = ioctl_addr[12:0];             // chars   0x20000 -> 0..0x1FFF
wire [16:0] tiles_wr_addr  = ioctl_addr - 27'h22000;       // tiles   0x22000 -> 0..0x1FFFF
wire [16:0] sprite_wr_addr = ioctl_addr - 27'h42000;       // sprites 0x42000 -> 0..0x17FFF
wire  [8:0] prom_wr_addr   = ioctl_addr[8:0];              // proms   0x5A000 -> 0..0x1FF

///////////////////////   CLOCKS   ///////////////////////////////

// clk_sys = 48 MHz (4x the 12 MHz Break Thru master crystal). See rtl/pll/pll_0002.v
// (output_clock_frequency0 = 48 MHz) and rtl/breakthru_clocks.sv.
wire clk_sys;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys)
);

wire reset = RESET | status[0] | buttons[1];

// --- pause control (Pause button = joystick bit 12 via MRA <buttons>) --------
// Toggling pause freezes the game (CPU clock enables gated below) and shows the
// custom pause screen (brkthru_pause).  The NFO scrolls ~14 px/s (advance 1 px
// every 4 frames); scroll resets to the top each time pause is entered.
// Scroll is tracked as (text row, font row) instead of a pixel count so the
// pause renderer never has to divide by the 7-px cell height (a divide-by-7 on
// the 48 MHz path blew setup timing).  One font row = one pixel of scroll.
wire pause_btn = joystick_0[12] | joystick_1[12];
reg  paused, pause_btn_d;
reg  [6:0]  scroll_row;    // 0..94 (95 NFO lines), wraps for infinite loop
reg  [2:0]  scroll_frow;   // 0..6  (font-cell row)
reg  [1:0]  scroll_div;
always @(posedge clk_sys) begin
	pause_btn_d <= pause_btn;
	if (reset) begin
		paused <= 1'b0; scroll_row <= 7'd0; scroll_frow <= 3'd0; scroll_div <= 2'd0;
	end
	else begin
		if (pause_btn & ~pause_btn_d) begin
			paused <= ~paused;
			if (~paused) begin scroll_row <= 7'd0; scroll_frow <= 3'd0; scroll_div <= 2'd0; end
		end
		if (paused & vblank_rise) begin
			scroll_div <= scroll_div + 2'd1;
			if (scroll_div == 2'd3) begin       // ~14 px/s
				if (scroll_frow == 3'd7) begin  // font cell FH=8 tall
					scroll_frow <= 3'd0;
					scroll_row  <= (scroll_row == 7'd71) ? 7'd0 : (scroll_row + 7'd1); // 72 NFO rows
				end
				else scroll_frow <= scroll_frow + 3'd1;
			end
		end
	end
end

// --- clock enables: 6 MHz pixel, 3 MHz YM3526, 1.5 MHz YM2203, 6809E E/Q ---
wire ce_pix, ce_ym3526, ce_ym2203, cen_cpu_e, cen_cpu_q;
// gated enables: freeze both 6809s while paused (video/pixel clock keeps running)
wire cen_cpu_e_g = cen_cpu_e & ~paused;
wire cen_cpu_q_g = cen_cpu_q & ~paused;
breakthru_clocks clocks
(
	.clk(clk_sys),
	.reset(reset),
	.ce_pix(ce_pix),
	.ce_ym3526(ce_ym3526),
	.ce_ym2203(ce_ym2203),
	.cen_cpu_e(cen_cpu_e),
	.cen_cpu_q(cen_cpu_q)
);

// --- video timing: MAME set_raw(6MHz,384,0,256,272,8,248) => 256x240 @ 57.44 Hz ---
wire [8:0] hcnt, vcnt;
wire HBlank, VBlank, HSync, VSync, hde, vde, vblank_rise;
breakthru_video_timing video_timing
(
	.clk(clk_sys),
	.ce_pix(ce_pix),
	.reset(reset),
	.hcnt(hcnt),
	.vcnt(vcnt),
	.hblank(HBlank),
	.vblank(VBlank),
	.hsync(HSync),
	.vsync(VSync),
	.hde(hde),
	.vde(vde),
	.vblank_rise(vblank_rise)
);

// --- inter-module wires ---
wire        cpu_reset = reset | ioctl_download;   // hold CPU in reset during ROM load
wire [8:0]  bgscroll;
wire [2:0]  bg_pal_hi;
wire        flip_screen;
wire [7:0]  soundlatch;
wire        soundlatch_wr;
wire [7:0]  m_fgram_q, m_sprram_q;
wire [15:0] m_bgram_q;
wire [15:0] cpu_addr, cpu_pc;
wire        cpu_rnw;
wire [7:0]  cpu_dout_o;
wire [9:0]  fg_fgram_addr;
wire [2:0]  fg_pen;
wire        fg_transp;
wire [8:0]  bg_bgram_addr;
wire [2:0]  bg_pen;
wire [3:0]  bg_color;
wire        bg_transp;
wire [7:0]  spr_sprram_addr;
wire [2:0]  spr_pen, spr_color;
wire        spr_prio, spr_transp;

// --- inputs & DIPs (M9) ---
wire [7:0] in_p1, in_p2, in_dsw1, in_dsw2_coin;
wire       in_coin_trigger;
brkthru_inputs u_inputs
(
	.clk(clk_sys),
	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.vblank(VBlank),
	.dsw1_in(dsw1_bus),                  // from MRA <switches> via status[23:16]
	.dsw2_in({1'b1, dsw2_bus[3:0]}),     // bit4 (Service Mode) forced OFF so the game
	                                     // boots to play; lives/bonus still from OSD.
	                                     // (TODO: MRA <switches> default not applying to
	                                     //  status — investigate; forcing service is the
	                                     //  safe interim so self-test doesn't trap boot.)
	.p1(in_p1),
	.p2(in_p2),
	.dsw1(in_dsw1),
	.dsw2_coin(in_dsw2_coin),
	.coin_trigger(in_coin_trigger)
);

// --- main CPU subsystem (M4) ---
brkthru_main u_main
(
	.clk(clk_sys),
	.reset(cpu_reset),
	.cen_cpu_e(cen_cpu_e_g),
	.cen_cpu_q(cen_cpu_q_g),

	.rom_we(main_rom_we),
	.rom_wr_addr(ioctl_addr[16:0]),
	.rom_wr_data(ioctl_dout),

	.p1(in_p1), .p2(in_p2), .dsw1(in_dsw1), .dsw2_coin(in_dsw2_coin), .flip_dip(1'b0),
	.vblank_rise(vblank_rise),
	.coin_trigger(in_coin_trigger),

	.pause_active(paused),
	.pause_rom_addr(pause_rom_addr),
	.pause_rom_q(pause_rom_q),

	.bgscroll(bgscroll),
	.bg_pal_hi(bg_pal_hi),
	.flip_screen(flip_screen),
	.soundlatch(soundlatch),
	.soundlatch_wr(soundlatch_wr),

	.fgram_rdaddr(fg_fgram_addr),  .fgram_q(m_fgram_q),
	.bgram_rdaddr(bg_bgram_addr),  .bgram_q(m_bgram_q),
	.sprram_rdaddr(spr_sprram_addr), .sprram_q(m_sprram_q),

	.cpu_addr(cpu_addr),
	.cpu_rnw(cpu_rnw),
	.cpu_dout_o(cpu_dout_o),
	.cpu_pc(cpu_pc)
);

// --- foreground text renderer (M5) ---
brkthru_char u_char
(
	.clk(clk_sys),
	.ce_pix(ce_pix),
	.hcnt(hcnt),
	.vcnt(vcnt),
	.cr_we(char_we),
	.cr_addr(char_wr_addr),
	.cr_data(ioctl_dout),
	.fgram_addr(fg_fgram_addr),
	.fgram_q(m_fgram_q),
	.fg_pen(fg_pen),
	.fg_transp(fg_transp)
);

// --- background renderer (M6) ---
brkthru_bg u_bg
(
	.clk(clk_sys),
	.ce_pix(ce_pix),
	.hcnt(hcnt),
	.vcnt(vcnt),
	.bgscroll(bgscroll),
	.bg_pal_hi(bg_pal_hi),
	.tr_we(tiles_we),
	.tr_addr(tiles_wr_addr),
	.tr_data(ioctl_dout),
	.bgram_addr(bg_bgram_addr),
	.bgram_q(m_bgram_q),
	.bg_pen(bg_pen),
	.bg_color(bg_color),
	.bg_transp(bg_transp)
);

// --- sprite engine (M7) ---
brkthru_sprite u_spr
(
	.clk(clk_sys),
	.ce_pix(ce_pix),
	.reset(cpu_reset),
	.hcnt(hcnt),
	.vcnt(vcnt),
	.sr_we(sprite_we),
	.sr_addr(sprite_wr_addr),
	.sr_data(ioctl_dout),
	.sprram_addr(spr_sprram_addr),
	.sprram_q(m_sprram_q),
	.spr_pen(spr_pen),
	.spr_color(spr_color),
	.spr_prio(spr_prio),
	.spr_transp(spr_transp)
);

// --- palette (M8) + layer priority mix (hardware_notes §5.4) ---
//  BG opaque base; low-pri sprites over transparent-BG only; hi-pri sprites over
//  all BG; FG text on top.
wire [7:0] bg_index  = {1'b1, bg_color, bg_pen};    // 0x80 | (color<<3) | pen
wire [7:0] spr_index = {2'b01, spr_color, spr_pen}; // 0x40 | (color<<3) | pen
wire       spr_show  = ~spr_transp & (spr_prio | bg_transp);
wire [7:0] mix_index = fg_transp ? (spr_show ? spr_index : bg_index)
                                 : {5'b00000, fg_pen};
wire [7:0] pal_index = mix_index;
wire [7:0] pal_r, pal_g, pal_b;
brkthru_palette u_pal
(
	.clk(clk_sys),
	.prom_we(prom_we),
	.prom_addr(prom_wr_addr),
	.prom_data(ioctl_dout),
	.pal_index(pal_index),
	.r(pal_r), .g(pal_g), .b(pal_b)
);

// --- pause screen overlay: XN logo + scrolling NFO, reads its assets from the
//     unused 16 KB gap of the main program ROM (borrows u_main's port B while
//     the CPU is frozen).  Costs zero extra BRAM. ---
wire [13:0] pause_rom_addr;
wire [7:0]  pause_rom_q;
wire [7:0]  pause_r, pause_g, pause_b;
brkthru_pause u_pause
(
	.clk(clk_sys),
	.ce_pix(ce_pix),
	.reset(reset),
	.hcnt(hcnt),
	.vcnt(vcnt),
	.pause_active(paused),
	.scroll_row(scroll_row),
	.scroll_frow(scroll_frow),
	.rom_addr(pause_rom_addr),
	.rom_data(pause_rom_q),
	.r(pause_r), .g(pause_g), .b(pause_b)
);

// --- video output: align syncs to the pixel-pipeline latency (fg 1px + palette 1clk) ---
reg hs_d, vs_d, hb_d, vb_d;
always @(posedge clk_sys) if (ce_pix) begin
	hs_d <= HSync;  vs_d <= VSync;
	hb_d <= HBlank; vb_d <= VBlank;
end

// --- sound subsystem (M10) ---
wire signed [15:0] sound_out;
brkthru_sound u_sound
(
	.clk(clk_sys),
	.reset(cpu_reset),
	.cen_e(cen_cpu_e_g),
	.cen_q(cen_cpu_q_g),
	.ce_ym2203(ce_ym2203),
	.ce_ym3526(ce_ym3526),
	.rom_we(audio_we),
	.rom_wr_addr(audio_wr_addr),
	.rom_wr_data(ioctl_dout),
	.soundlatch(soundlatch),
	.soundlatch_wr(soundlatch_wr),
	.snd(sound_out),
	.dbg_pc(), .dbg_opn_wr(), .dbg_opl_wr(), .dbg_opn_rd(),
	.snd_opl(snd_opl_w), .snd_opn(snd_opn_w)
);
wire signed [15:0] snd_opl_w, snd_opn_w;

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = ce_pix;
assign VGA_DE = ~(hb_d | vb_d);
assign VGA_HS = hs_d;
assign VGA_VS = vs_d;
// pause screen replaces the game image while paused
assign VGA_R  = paused ? pause_r : pal_r;
assign VGA_G  = paused ? pause_g : pal_g;
assign VGA_B  = paused ? pause_b : pal_b;

reg  [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1; 
assign LED_USER    = act_cnt[26]  ? act_cnt[25:18]  > act_cnt[7:0]  : act_cnt[25:18]  <= act_cnt[7:0];

endmodule
