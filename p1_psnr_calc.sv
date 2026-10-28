// p1_psnr_calc: main hardware logic.
module p1_psnr_calc (
    input  logic [31:0] mse_q4,
    input  logic        valid,
    output logic [9:0]  psnr_tenths
);
    logic [4:0]  n;
    logic [31:0] norm;
    logic [4:0]  f;
    logic [5:0]  lut;
    logic [10:0] log_q6;     
    logic [20:0] sub_full;
    logic [9:0]  sub_tenths;
    integer      i;

    // Combinational logic.

    always_comb begin
        n = 5'd0;
        for (i = 0; i < 32; i = i + 1)
            if (mse_q4[i]) n = i[4:0];

        norm = mse_q4 << (5'd31 - n);
        f    = norm[30:26];

        case (f)
            5'd0:  lut = 6'd1;   5'd1:  lut = 6'd4;   5'd2:  lut = 6'd7;   5'd3:  lut = 6'd10;
            5'd4:  lut = 6'd12;  5'd5:  lut = 6'd15;  5'd6:  lut = 6'd17;  5'd7:  lut = 6'd19;
            5'd8:  lut = 6'd22;  5'd9:  lut = 6'd24;  5'd10: lut = 6'd26;  5'd11: lut = 6'd28;
            5'd12: lut = 6'd30;  5'd13: lut = 6'd32;  5'd14: lut = 6'd35;  5'd15: lut = 6'd36;
            5'd16: lut = 6'd38;  5'd17: lut = 6'd40;  5'd18: lut = 6'd42;  5'd19: lut = 6'd44;
            5'd20: lut = 6'd46;  5'd21: lut = 6'd47;  5'd22: lut = 6'd49;  5'd23: lut = 6'd51;
            5'd24: lut = 6'd52;  5'd25: lut = 6'd54;  5'd26: lut = 6'd56;  5'd27: lut = 6'd57;
            5'd28: lut = 6'd59;  5'd29: lut = 6'd60;  5'd30: lut = 6'd62;  default: lut = 6'd63;
        endcase

        log_q6     = {n, 6'b0} + {5'b0, lut};
        sub_full   = log_q6 * 11'd482;
        sub_tenths = sub_full[19:10];

        if (!valid)
            psnr_tenths = 10'd0;
        else if (mse_q4 == 32'd0)
            psnr_tenths = 10'd1023;
        else if (sub_tenths >= 10'd602)
            psnr_tenths = 10'd1;
        else
            psnr_tenths = 10'd602 - sub_tenths;
    end
endmodule
