//============================================================================
//  Break Thru — inputs & DIPs (M9)   (hardware_notes §11)
//
//  MiSTer joystick bit order (arcade convention): [0]R [1]L [2]D [3]U
//  [4]B1 [5]B2 ... [10]Coin [11]Start [12]Pause  (Coin/Start per MRA <buttons>).
//  All game input ports are ACTIVE-LOW.
//    P1 (0x1800) bits: 0=B1 1=B2 2=Down 3=Up 4=Left 5=Right 6=Start1 7=Start2
//    P2 (0x1801): P2 (cocktail) dirs/buttons; bit6 unused; bit7 = VBlank (raw).
//    DSW2_COIN (0x1803): bits0-4 = DIP2; 5=Coin1 6=Coin2 7=Service (active-low).
//  A coin/service press edge pulses coin_trigger (drives the main-CPU IRQ).
//============================================================================

module brkthru_inputs
(
    input  wire        clk,
    input  wire [15:0] joystick_0,
    input  wire [15:0] joystick_1,
    input  wire        vblank,        // raw VBlank for P2 bit7
    input  wire [7:0]  dsw1_in,       // DIP bank 1 (from MRA)
    input  wire [4:0]  dsw2_in,       // DIP bank 2 low 5 bits (from MRA)

    output wire [7:0]  p1,
    output wire [7:0]  p2,
    output wire [7:0]  dsw1,
    output wire [7:0]  dsw2_coin,
    output reg         coin_trigger
);
    wire p1_b1=joystick_0[4], p1_b2=joystick_0[5];
    wire p1_r=joystick_0[0], p1_l=joystick_0[1], p1_d=joystick_0[2], p1_u=joystick_0[3];
    wire p1_start=joystick_0[11], p2_start=joystick_1[11];
    wire coin1=joystick_0[10], coin2=joystick_1[10];

    wire p2_b1=joystick_1[4], p2_b2=joystick_1[5];
    wire p2_r=joystick_1[0], p2_l=joystick_1[1], p2_d=joystick_1[2], p2_u=joystick_1[3];

    // active-low assembly (bit6 of P2 unused -> reads 1; bit7 = raw VBlank)
    assign p1 = ~{ p2_start, p1_start, p1_r, p1_l, p1_u, p1_d, p1_b2, p1_b1 };
    assign p2 = { vblank, 1'b1, ~p2_r, ~p2_l, ~p2_u, ~p2_d, ~p2_b2, ~p2_b1 };

    assign dsw1 = dsw1_in;
    assign dsw2_coin = { 1'b1 /*service inactive*/, ~coin2, ~coin1, dsw2_in };

    // coin edge -> 1-clk pulse
    reg coin_any_d;
    wire coin_any = coin1 | coin2;
    always @(posedge clk) begin
        coin_any_d   <= coin_any;
        coin_trigger <= coin_any & ~coin_any_d;   // rising edge
    end
endmodule
