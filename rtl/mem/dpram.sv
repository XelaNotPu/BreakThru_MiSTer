//============================================================================
//  Simple true dual-port RAM (single clock) — infers Cyclone V M10K BRAM.
//
//  Used for: work RAM, shared video RAM (CPU port A / video port B), and
//  ROM regions loaded via the ioctl download path (write port A, read port B).
//  Read-during-write on the same port returns OLD data (read-first); the two
//  ports never write the same address in this design.
//============================================================================

module dpram #(
    parameter AW = 10,
    parameter DW = 8
)
(
    input  wire            clk,

    input  wire [AW-1:0]   addr_a,
    input  wire [DW-1:0]   data_a,
    input  wire            we_a,
    output reg  [DW-1:0]   q_a,

    input  wire [AW-1:0]   addr_b,
    input  wire [DW-1:0]   data_b,
    input  wire            we_b,
    output reg  [DW-1:0]   q_b
);
    reg [DW-1:0] mem [0:(2**AW)-1];

    always @(posedge clk) begin
        if (we_a) mem[addr_a] <= data_a;
        q_a <= mem[addr_a];
    end

    always @(posedge clk) begin
        if (we_b) mem[addr_b] <= data_b;
        q_b <= mem[addr_b];
    end
endmodule
