//============================================================================
//  Break Thru — clock-enable generator
//
//  System clock = 48 MHz (4 x the 12 MHz master crystal), so every device rate
//  divides cleanly (hardware_notes §1):
//     pixel   6.0 MHz = 48/8    (ce_pix)
//     YM3526  3.0 MHz = 48/16   (ce_ym3526)   } consumed at the sound milestone
//     YM2203  1.5 MHz = 48/32   (ce_ym2203)   }
//     CPU-E   1.5 MHz = 48/32   (cen_cpu_e / cen_cpu_q)
//
//  The MC6809E core (mc6809i.v) is single-clock with two non-overlapping
//  clock-enable pulses per bus cycle: cen_E and cen_Q (Q trailing E by half a
//  bus cycle). We place cen_cpu_e at divider count 0 and cen_cpu_q at count 16
//  of the 32-clock (1.5 MHz) window — the quadrature the 6809E expects.
//
//  A single free-running /32 counter keeps all enables phase-coherent.
//============================================================================

module breakthru_clocks
(
    input  wire clk,        // 48 MHz
    input  wire reset,

    output wire ce_pix,     // 6.0 MHz
    output wire ce_ym3526,  // 3.0 MHz
    output wire ce_ym2203,  // 1.5 MHz
    output wire cen_cpu_e,  // 1.5 MHz, 6809E E-phase enable
    output wire cen_cpu_q   // 1.5 MHz, 6809E Q-phase enable (trails E by 16 clk)
);

    reg [4:0] div = 5'd0;   // 0..31 @ 48 MHz -> wraps at 1.5 MHz

    always @(posedge clk) begin
        if (reset) div <= 5'd0;
        else       div <= div + 5'd1;
    end

    assign ce_pix    = (div[2:0] == 3'd0);    // every 8  -> 6.0 MHz
    assign ce_ym3526 = (div[3:0] == 4'd0);    // every 16 -> 3.0 MHz
    assign ce_ym2203 = (div       == 5'd0);   // every 32 -> 1.5 MHz
    assign cen_cpu_e = (div       == 5'd0);   // 6809E E phase
    assign cen_cpu_q = (div       == 5'd16);  // 6809E Q phase (half a bus cycle later)

endmodule
