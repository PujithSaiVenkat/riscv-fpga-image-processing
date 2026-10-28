// p1_adder: main hardware logic.
module p1_adder (
    input  logic [31:0] a, b,
    output logic [31:0] sum
);

    assign sum = a + b;

endmodule
