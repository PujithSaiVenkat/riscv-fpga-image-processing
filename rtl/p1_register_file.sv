// p1_register_file: main hardware logic.
module p1_register_file (
    input  logic        clk, reset, reg_write,
    input  logic [4:0]  rs1, rs2, rd,
    input  logic [31:0] write_data,
    output logic [31:0] rd1, rd2,
    output logic [31:0] debug_registers [0:31]
);

    logic [31:0] registers [0:31];

    initial begin : INIT_REGFILE
        for (int i = 0; i < 32; i = i + 1)
            registers[i] = 32'd0;
    end

    // Clocked logic.

    always_ff @(posedge clk) begin
        if (reg_write && rd != 5'd0)
            registers[rd] <= write_data;
    end

    assign rd1 = (rs1 == 5'd0) ? 32'b0 : registers[rs1];
    assign rd2 = (rs2 == 5'd0) ? 32'b0 : registers[rs2];

    genvar dbg_i;
    generate
        for (dbg_i = 0; dbg_i < 32; dbg_i = dbg_i + 1) begin : G_DEBUG_REGS
            assign debug_registers[dbg_i] = (dbg_i == 0) ? 32'd0 : registers[dbg_i];
        end
    endgenerate

endmodule
