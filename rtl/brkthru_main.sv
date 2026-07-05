//============================================================================
//  Break Thru — main CPU subsystem (MC6809E @ 1.5 MHz)
//
//  Implements brkthru_main_map (brkthru.cpp lines 508-525) — see
//  docs/hardware_notes.md §3/§4/§6.  Instantiates the vendored mc6809i core
//  directly, driven by cen_cpu_e / cen_cpu_q from breakthru_clocks.
//
//  Shared video RAMs (fg / bg / sprite) live here: CPU writes on port A,
//  the video engine reads on port B (addr in, q out).
//  Program ROM (0x20000 region) is a BRAM loaded via the ioctl write port.
//============================================================================

module brkthru_main
(
    input  wire        clk,          // 48 MHz
    input  wire        reset,        // active high
    input  wire        cen_cpu_e,    // 6809E E enable (1.5 MHz)
    input  wire        cen_cpu_q,    // 6809E Q enable (1.5 MHz)

    // ---- program ROM load (ioctl / sim), maincpu region 0x00000-0x1FFFF ----
    input  wire        rom_we,
    input  wire [16:0] rom_wr_addr,
    input  wire [7:0]  rom_wr_data,

    // ---- inputs / DIPs (read at 0x1800-0x1803), active-low as MAME ----
    input  wire [7:0]  p1,
    input  wire [7:0]  p2,
    input  wire [7:0]  dsw1,
    input  wire [7:0]  dsw2_coin,
    input  wire        flip_dip,     // hardware flip switch (SW2:6)

    // ---- interrupt sources ----
    input  wire        vblank_rise,  // 1-clk pulse at start of vblank -> NMI
    input  wire        coin_trigger, // 1-clk pulse on coin/service edge -> IRQ

    // ---- pause-screen asset read port (borrows ROM port B while CPU frozen) ----
    input  wire        pause_active,     // 1 = pause screen owns the ROM read port
    input  wire [13:0] pause_rom_addr,   // read into the unused 0x0000-0x3FFF gap
    output wire [7:0]  pause_rom_q,      // gap byte (1-clk latency)

    // ---- register outputs to video / sound ----
    output reg  [8:0]  bgscroll,     // 9-bit horizontal background scroll
    output reg  [2:0]  bg_pal_hi,    // control_w bits 5:3 (BG color code high)
    output wire        flip_screen,  // control bit6 XOR flip_dip
    output reg  [7:0]  soundlatch,
    output reg         soundlatch_wr,// 1-clk pulse when 0x1802 written

    // ---- shared video RAM read ports (video engine side) ----
    input  wire [9:0]  fgram_rdaddr, output wire [7:0]  fgram_q,   // 0x400 chars (byte)
    input  wire [8:0]  bgram_rdaddr, output wire [15:0] bgram_q,   // 512 tile words (2 bytes)
    input  wire [7:0]  sprram_rdaddr,output wire [7:0]  sprram_q,  // 0x100 sprites (byte)

    // ---- debug / observation ----
    output wire [15:0] cpu_addr,
    output wire        cpu_rnw,
    output wire [7:0]  cpu_dout_o,
    output wire [15:0] cpu_pc
);
    // ------------------------------------------------------------------
    //  CPU core
    // ------------------------------------------------------------------
    wire [15:0] A;
    wire [7:0]  cpu_dout;
    reg  [7:0]  cpu_din;
    wire        RnW;
    wire [111:0] RegData;

    wire nNMI, nIRQ;

    mc6809i u_cpu (
        .D        (cpu_din),
        .DOut     (cpu_dout),
        .ADDR     (A),
        .RnW      (RnW),
        .clk      (clk),
        .cen_E    (cen_cpu_e),
        .cen_Q    (cen_cpu_q),
        .BS       (),
        .BA       (),
        .nIRQ     (nIRQ),
        .nFIRQ    (1'b1),
        .nNMI     (nNMI),
        .AVMA     (),
        .BUSY     (),
        .LIC      (),
        .nHALT    (1'b1),
        .nRESET   (~reset),
        .nDMABREQ (1'b1),
        .OP       (),
        .RegData  (RegData)
    );

    assign cpu_addr   = A;
    assign cpu_rnw    = RnW;
    assign cpu_dout_o = cpu_dout;
    assign cpu_pc     = RegData[111:96];

    // one write strobe per bus cycle (address + data stable at cen_Q)
    wire wr = ~RnW & cen_cpu_q;

    // ------------------------------------------------------------------
    //  Address decode  (hardware_notes §3)
    // ------------------------------------------------------------------
    wire fg_cs   = (A[15:10] == 6'b000000);            // 0x0000-0x03FF
    wire bg_cs   = (A[15:10] == 6'b000011);            // 0x0C00-0x0FFF
    wire spr_cs  = (A[15:8]  == 8'h10);                // 0x1000-0x10FF
    // work RAM: 0x0400-0x0BFF and 0x1100-0x17FF
    wire wram_cs = ((A >= 16'h0400) && (A <= 16'h0BFF)) ||
                   ((A >= 16'h1100) && (A <= 16'h17FF));
    wire io_cs   = (A[15:2]  == 14'h0600);             // 0x1800-0x1803
    wire bank_cs = (A[15:13] == 3'b001);               // 0x2000-0x3FFF
    wire fix_cs  = (A[15:14] != 2'b00);                // 0x4000-0xFFFF
    wire rom_cs  = bank_cs | fix_cs;

    // ------------------------------------------------------------------
    //  Program ROM (0x20000) — port A = ioctl load, port B = CPU read
    // ------------------------------------------------------------------
    reg  [2:0] bank;   // ROM bank select (control_w bits 2:0)
    wire [16:0] rom_rdaddr = bank_cs ? {1'b1, bank, A[12:0]}   // 0x10000 + bank*0x2000
                                     : {1'b0, A};              // 0x4000-0xFFFF direct
    wire [7:0]  rom_q;

    // Port B is the CPU's ROM read port during play.  While the pause screen is
    // active the CPU is frozen (cen gated off in the top level), so we lend the
    // port to the pause overlay, which reads its assets from the unused
    // 0x0000-0x3FFF lead gap.  The game never addresses that gap (rom_rdaddr is
    // always >= 0x04000), so there is no aliasing and no extra BRAM.
    wire [16:0] portb_addr = pause_active ? {3'b000, pause_rom_addr} : rom_rdaddr;
    dpram #(.AW(17), .DW(8)) u_prog (
        .clk(clk),
        .addr_a(rom_wr_addr), .data_a(rom_wr_data), .we_a(rom_we), .q_a(),
        .addr_b(portb_addr),  .data_b(8'h00),       .we_b(1'b0),  .q_b(rom_q)
    );
    assign pause_rom_q = rom_q;

    // ------------------------------------------------------------------
    //  Work RAM (0x0000-0x1FFF window; only the two RAM ranges are written)
    // ------------------------------------------------------------------
    wire [7:0] wram_q;
    dpram #(.AW(13), .DW(8)) u_wram (
        .clk(clk),
        .addr_a(A[12:0]), .data_a(cpu_dout), .we_a(wr & wram_cs), .q_a(wram_q),
        .addr_b(13'd0),   .data_b(8'h00),    .we_b(1'b0),         .q_b()
    );

    // ------------------------------------------------------------------
    //  Shared video RAMs: CPU port A (write), video port B (read)
    // ------------------------------------------------------------------
    dpram #(.AW(10), .DW(8)) u_fgram (
        .clk(clk),
        .addr_a(A[9:0]),      .data_a(cpu_dout), .we_a(wr & fg_cs), .q_a(fg_q_cpu),
        .addr_b(fgram_rdaddr),.data_b(8'h00),    .we_b(1'b0),       .q_b(fgram_q)
    );
    wire [7:0] fg_q_cpu;

    // BG VRAM as two byte lanes (even/odd) so the video side reads a full 16-bit
    // tile word in one access; CPU writes/reads a byte selected by A[0].
    wire [7:0] bg_lo_qa, bg_hi_qa, bg_lo_qb, bg_hi_qb;
    wire [7:0] bg_q_cpu = A[0] ? bg_hi_qa : bg_lo_qa;
    dpram #(.AW(9), .DW(8)) u_bg_lo ( .clk(clk),
        .addr_a(A[9:1]),      .data_a(cpu_dout), .we_a(wr & bg_cs & ~A[0]), .q_a(bg_lo_qa),
        .addr_b(bgram_rdaddr),.data_b(8'h00),    .we_b(1'b0),               .q_b(bg_lo_qb) );
    dpram #(.AW(9), .DW(8)) u_bg_hi ( .clk(clk),
        .addr_a(A[9:1]),      .data_a(cpu_dout), .we_a(wr & bg_cs &  A[0]), .q_a(bg_hi_qa),
        .addr_b(bgram_rdaddr),.data_b(8'h00),    .we_b(1'b0),               .q_b(bg_hi_qb) );
    assign bgram_q = {bg_hi_qb, bg_lo_qb};

    dpram #(.AW(8), .DW(8)) u_sprram (
        .clk(clk),
        .addr_a(A[7:0]),       .data_a(cpu_dout), .we_a(wr & spr_cs), .q_a(spr_q_cpu),
        .addr_b(sprram_rdaddr),.data_b(8'h00),    .we_b(1'b0),        .q_b(sprram_q)
    );
    wire [7:0] spr_q_cpu;

    // ------------------------------------------------------------------
    //  Input port read mux (0x1800-0x1803)  (hardware_notes §11)
    // ------------------------------------------------------------------
    reg [7:0] io_q;
    always @(*) begin
        case (A[1:0])
            2'd0: io_q = p1;
            2'd1: io_q = p2;
            2'd2: io_q = dsw1;
            2'd3: io_q = dsw2_coin;
        endcase
    end

    // ------------------------------------------------------------------
    //  CPU read data mux (combinational over 1-clk-latency BRAM outputs)
    // ------------------------------------------------------------------
    always @(*) begin
        if      (rom_cs)  cpu_din = rom_q;
        else if (fg_cs)   cpu_din = fg_q_cpu;
        else if (bg_cs)   cpu_din = bg_q_cpu;
        else if (spr_cs)  cpu_din = spr_q_cpu;
        else if (wram_cs) cpu_din = wram_q;
        else if (io_cs)   cpu_din = io_q;
        else              cpu_din = 8'hFF;
    end

    // ------------------------------------------------------------------
    //  Control registers (writes to 0x1800-0x1803)  (hardware_notes §4)
    // ------------------------------------------------------------------
    reg [1:0] int_enable;   // bit0 = IRQ disable, bit1 = NMI enable
    reg       ctrl_flip;    // control_w bit6 (software flip)

    assign flip_screen = ctrl_flip ^ flip_dip;

    always @(posedge clk) begin
        soundlatch_wr <= 1'b0;
        if (reset) begin
            bgscroll   <= 9'd0;
            bg_pal_hi  <= 3'd0;
            ctrl_flip  <= 1'b0;
            bank       <= 3'd0;
            int_enable <= 2'b00;
            soundlatch <= 8'd0;
        end
        else if (wr & io_cs) begin
            case (A[1:0])
                2'd0: bgscroll <= {bgscroll[8], cpu_dout};          // bgscroll_w (low 8)
                2'd1: begin                                         // control_w
                          bank      <= cpu_dout[2:0];
                          bg_pal_hi <= cpu_dout[5:3];
                          ctrl_flip <= cpu_dout[6];
                          bgscroll  <= {cpu_dout[7], bgscroll[7:0]};// scroll bit 8
                      end
                2'd2: begin soundlatch <= cpu_dout; soundlatch_wr <= 1'b1; end
                2'd3: int_enable <= cpu_dout[1:0];                  // int_enable_w
            endcase
        end
    end

    // ------------------------------------------------------------------
    //  Interrupts  (hardware_notes §6)
    //    NMI = VBlank (edge) when int_enable[1]; pulse nNMI low one bus cycle.
    //    IRQ = coin edge (level) when int_enable[0]==0; cleared by writing
    //          int_enable bit0 = 1.
    // ------------------------------------------------------------------
    reg nmi_req, nmi_hold, nmi_n_r;
    always @(posedge clk) begin
        if (reset) begin
            nmi_req <= 1'b0; nmi_hold <= 1'b0; nmi_n_r <= 1'b1;
        end
        else begin
            if (vblank_rise & int_enable[1]) nmi_req <= 1'b1;
            if (cen_cpu_e) begin
                if (nmi_req)       begin nmi_n_r <= 1'b0; nmi_req <= 1'b0; nmi_hold <= 1'b1; end
                else if (nmi_hold) begin nmi_n_r <= 1'b1; nmi_hold <= 1'b0; end
            end
        end
    end
    assign nNMI = nmi_n_r;

    reg irq_pend;
    always @(posedge clk) begin
        if (reset) irq_pend <= 1'b0;
        else begin
            if (coin_trigger & ~int_enable[0]) irq_pend <= 1'b1;
            if (wr & io_cs & (A[1:0]==2'd3) & cpu_dout[0]) irq_pend <= 1'b0;
        end
    end
    assign nIRQ = ~irq_pend;

endmodule
