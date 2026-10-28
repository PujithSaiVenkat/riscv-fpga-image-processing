// p1_fetch_stage: main hardware logic.
module p1_fetch_stage (
    input  logic        clk,
    input  logic        reset,
    input  logic        stall,
    input  logic        pc_src_e,
    input  logic [31:0] pc_target_e,
    output logic [31:0] pc_f,
    output logic [31:0] pc_plus4_f
);

    logic [31:0] next_pc;

    p1_program_counter pc_reg (
        .clk    (clk),
        .reset  (reset),
        .en     (~stall),
        .pc_in  (next_pc),
        .pc_out (pc_f)
    );

    p1_adder pc_adder (
        .a   (pc_f),
        .b   (32'd4),
        .sum (pc_plus4_f)
    );

    assign next_pc = pc_src_e ? pc_target_e : pc_plus4_f;

endmodule
