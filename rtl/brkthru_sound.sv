//============================================================================
//  Break Thru — sound subsystem (M10)   (hardware_notes §10)
//
//  MC6809 (audio) @ 1.5 MHz bus. Map:
//    0000-1FFF RAM(8K) | 2000-2001 YM3526(jtopl) W | 4000 soundlatch R |
//    6000-6001 YM2203(jt03) R/W | 8000-FFFF ROM(32K)
//  NMI = soundlatch data-pending (main write to 0x1802).  IRQ = YM3526 irq_n.
//  Mono mix: YM2203 FM x0.10 + SSG x0.50 + YM3526 x1.0  (MAME route weights).
//============================================================================

module brkthru_sound
(
    input  wire         clk,
    input  wire         reset,
    input  wire         cen_e,        // 1.5 MHz 6809E E
    input  wire         cen_q,        // 1.5 MHz 6809E Q
    input  wire         ce_ym2203,    // 1.5 MHz
    input  wire         ce_ym3526,    // 3.0 MHz

    input  wire         rom_we,       // sound ROM load (32K)
    input  wire [14:0]  rom_wr_addr,
    input  wire [7:0]   rom_wr_data,

    input  wire [7:0]   soundlatch,
    input  wire         soundlatch_wr,

    output wire signed [15:0] snd,

    // ---- debug taps (sim only; unconnected in synthesis, pruned) ----
    output wire [15:0] dbg_pc,
    output wire        dbg_opn_wr,   // write to YM2203 (0x6000)
    output wire        dbg_opl_wr,   // write to YM3526 (0x2000)
    output wire        dbg_opn_rd,   // status read of YM2203
    // per-chip audio (diagnostic stereo split): OPL (YM3526) vs OPN (YM2203)
    output wire signed [15:0] snd_opl,
    output wire signed [15:0] snd_opn
);
    // ---- CPU ----
    wire [15:0] A;
    wire [7:0]  cpu_dout;
    reg  [7:0]  cpu_din;
    wire        RnW;
    wire        nNMI, nIRQ;
    wire [111:0] regdata;

    mc6809i u_scpu (
        .D(cpu_din), .DOut(cpu_dout), .ADDR(A), .RnW(RnW),
        .clk(clk), .cen_E(cen_e), .cen_Q(cen_q),
        .BS(), .BA(), .nIRQ(nIRQ), .nFIRQ(1'b1), .nNMI(nNMI),
        .AVMA(), .BUSY(), .LIC(), .nHALT(1'b1), .nRESET(~reset), .nDMABREQ(1'b1),
        .OP(), .RegData(regdata)
    );

    wire wr = ~RnW & cen_q;

    assign dbg_pc     = regdata[111:96];
    assign dbg_opn_wr = opn_cs & ~RnW & cen_q;
    assign dbg_opl_wr = opl_cs & ~RnW & cen_q;
    assign dbg_opn_rd = opn_cs &  RnW & cen_q;

    // ---- decode ----
    wire ram_cs   = (A[15:13] == 3'b000);        // 0000-1FFF
    wire opl_cs   = (A[15:1]  == 15'h1000);      // 2000-2001
    wire latch_cs = (A == 16'h4000);             // 4000
    wire opn_cs   = (A[15:1]  == 15'h3000);      // 6000-6001
    wire rom_cs   = A[15];                        // 8000-FFFF

    // ---- RAM 8K ----
    wire [7:0] ram_q;
    dpram #(.AW(13), .DW(8)) u_sram (.clk(clk),
        .addr_a(A[12:0]), .data_a(cpu_dout), .we_a(wr & ram_cs), .q_a(ram_q),
        .addr_b(13'd0), .data_b(8'd0), .we_b(1'b0), .q_b());

    // ---- ROM 32K (port A load, port B read) ----
    wire [7:0] rom_q;
    dpram #(.AW(15), .DW(8)) u_srom (.clk(clk),
        .addr_a(rom_wr_addr), .data_a(rom_wr_data), .we_a(rom_we), .q_a(),
        .addr_b(A[14:0]), .data_b(8'd0), .we_b(1'b0), .q_b(rom_q));

    // ---- YM2203 (jt03) ----
    wire [7:0] opn_dout;
    wire signed [15:0] opn_fm;
    wire [9:0] opn_psg;
    jt03 u_opn (
        .rst(reset), .clk(clk), .cen(ce_ym2203),
        .din(cpu_dout), .addr(A[0]), .cs_n(~opn_cs), .wr_n(RnW),
        .dout(opn_dout), .irq_n(),
        .IOA_in(8'd0), .IOB_in(8'd0),
        .psg_A(), .psg_B(), .psg_C(),
        .fm_snd(opn_fm), .psg_snd(opn_psg), .snd(), .snd_sample(),
        .debug_view()
    );

    // ---- YM3526 (jtopl) ----
    wire signed [15:0] opl_snd;
    jtopl u_opl (
        .rst(reset), .clk(clk), .cen(ce_ym3526),
        .din(cpu_dout), .addr(A[0]), .cs_n(~opl_cs), .wr_n(RnW),
        .dout(), .irq_n(nIRQ), .snd(opl_snd), .sample()
    );

    // ---- data-in mux ----
    always @(*) begin
        if      (rom_cs)   cpu_din = rom_q;
        else if (ram_cs)   cpu_din = ram_q;
        else if (latch_cs) cpu_din = soundlatch;
        else if (opn_cs)   cpu_din = opn_dout;
        else               cpu_din = 8'hFF;
    end

    // ---- Sound NMI from soundlatch write (serialized clean pulse) ----
    // Each main-CPU latch write produces exactly ONE low->high edge on nNMI.
    // A request bit queues writes that arrive during a pulse so rapid commands
    // (e.g. continuous gunfire) are serialized rather than merged/dropped, and
    // nNMI always auto-returns high (never sticks low). One low + one high cen_E
    // period per command; commands from the main CPU are far slower than that.
    reg       nmi_n_r;
    reg       nmi_req;
    reg [1:0] nmi_st;                  // 0 idle, 1 low, 2 high-gap
    always @(posedge clk) begin
        if (reset) begin nmi_n_r<=1'b1; nmi_req<=1'b0; nmi_st<=2'd0; end
        else begin
            if (soundlatch_wr) nmi_req <= 1'b1;
            if (cen_e) case (nmi_st)
                2'd0: if (nmi_req) begin nmi_n_r<=1'b0; nmi_req<=1'b0; nmi_st<=2'd1; end
                2'd1: begin nmi_n_r<=1'b1; nmi_st<=2'd2; end
                2'd2: nmi_st<=2'd0;
                default: nmi_st<=2'd0;
            endcase
        end
    end
    assign nNMI = nmi_n_r;

    // ---- mono mix ----
    // In this game YM3526 (OPL) = music, YM2203 (FM+SSG) = SFX (confirmed by a
    // stereo-split hardware test). MAME routes FM x0.50 / SSG x0.10 / OPL x1.0,
    // but the jt cores' raw output scales differ from MAME's normalized streams,
    // and the game's gunfire/explosions sit mostly on the YM2203 FM channels.
    // The stereo diagnostic that the user confirmed audible used FM at FULL scale
    // (x1.0) + SSG<<5, so we match that here: FM x1.0, SSG ±16384, OPL x0.5.
    // Music is sustained and SFX transient, so the clamp on simultaneous peaks
    // is rarely hit; when it is, the transient SFX correctly dominates.
    wire signed [10:0] psg_c = $signed({1'b0, opn_psg}) - 11'sd512;   // center SSG (~±512)
    wire signed [15:0] opl_g = opl_snd >>> 1;                         // YM3526 (music) x0.5
    wire signed [15:0] fm_g  = opn_fm;                                // YM2203 FM (SFX)  x1.0 (was x0.5)
    wire signed [15:0] ssg_g = $signed(psg_c) <<< 5;                  // YM2203 SSG (SFX) ±16384 (boosted)
    wire signed [17:0] acc   = {{2{opl_g[15]}}, opl_g}
                             + {{2{fm_g[15]}}, fm_g}
                             + {{2{ssg_g[15]}}, ssg_g};
    assign snd = (acc >  18'sd32767) ? 16'sd32767 :
                 (acc < -18'sd32768) ? -16'sd32768 : acc[15:0];

    // ---- diagnostic per-chip audio (stereo split) ----
    // OPL (YM3526) alone, and OPN (YM2203 FM+SSG) alone, each at a clearly
    // audible level and clamped. Lets a hardware listen isolate which chip the
    // SFX are on (or reveal they're drowned in the mono mix).
    assign snd_opl = opl_snd;                                    // YM3526 raw
    wire signed [17:0] opn_acc = {{2{opn_fm[15]}}, opn_fm}       // OPN FM full
                               + {{3{psg_c[10]}}, psg_c, 5'd0};  // + SSG x32 (louder)
    assign snd_opn = (opn_acc >  18'sd32767) ? 16'sd32767 :
                     (opn_acc < -18'sd32768) ? -16'sd32768 : opn_acc[15:0];
endmodule
