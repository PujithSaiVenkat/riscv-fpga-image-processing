// p1_image_metrics_fpga: main hardware logic.
module p1_image_metrics_fpga #(
    parameter integer IMG_W = 128,
    parameter integer IMG_H = 128,
    parameter logic [31:0] DST_BASE = 32'h0000_C000
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        proc_we,
    input  logic [31:0] proc_addr,
    input  logic [7:0]  proc_wdata,
    output logic [15:0] entropy_x100,
    output logic [15:0] avg_gradient_x100,
    output logic [15:0] rms_contrast_x100,
    output logic        metrics_valid
);
    localparam integer PIXELS = IMG_W * IMG_H;
    localparam integer RGB_BYTES = PIXELS * 3;
    localparam integer EDGE_COUNT = IMG_W*(IMG_H-1) + IMG_H*(IMG_W-1);
    localparam logic [31:0] LAST_BYTE_OFFSET = RGB_BYTES-1;

    typedef enum logic {COLLECT_FRAME, SCAN_HISTOGRAM} state_t;
    state_t state;
    logic [14:0] histogram [0:255];
    logic [7:0] red_byte, green_byte;
    logic [7:0] previous_gray;
    logic [7:0] previous_row [0:IMG_W-1];
    logic [31:0] pixel_sum;
    logic [31:0] pixel_square_sum;
    logic [31:0] gradient_sum;
    logic [31:0] histogram_term_sum;
    logic [7:0] histogram_index;
    logic [31:0] pixel_index;
    logic [31:0] byte_offset;
    logic [1:0] byte_lane;
    logic [7:0] gray_pixel;
    logic [15:0] gray_weighted_sum;
    logic [7:0] abs_dx, abs_dy;
    logic [8:0] gradient_term;
    logic [31:0] count_at_bin;
    logic [31:0] log_term;
    logic [31:0] hist_total_with_current;
    logic [31:0] mean_integer;
    logic [31:0] mean_square_integer;
    logic [31:0] variance_integer;
    logic [31:0] variance_x10000;
    logic [63:0] variance_numerator;
    logic [31:0] entropy_q4;
    integer i;

    function automatic [7:0] log2_count_q4(input logic [14:0] count);
        integer n;
        logic [14:0] normalized;
        logic [3:0] frac;
        logic [4:0] frac_q4;
        begin
            n = 0;
            for (integer k=0; k<15; k=k+1)
                if (count[k]) n = k;
            normalized = count << (14-n);
            frac = normalized[13:10];
            case (frac)
                0:frac_q4=0; 1:frac_q4=1; 2:frac_q4=3; 3:frac_q4=4;
                4:frac_q4=5; 5:frac_q4=6; 6:frac_q4=7; 7:frac_q4=8;
                8:frac_q4=9; 9:frac_q4=10; 10:frac_q4=10; 11:frac_q4=11;
                12:frac_q4=12; 13:frac_q4=13; 14:frac_q4=14; default:frac_q4=15;
            endcase
            log2_count_q4 = (n*16) + frac_q4;
        end
    endfunction

    function automatic [15:0] isqrt32(input logic [31:0] value);
        logic [31:0] low, high, mid;
        begin
            low=0; high=65535;
            for (integer k=0; k<16; k=k+1) begin
                mid = (low + high + 1) >> 1;
                if ((mid*mid) <= value) low=mid;
                else high=mid-1;
            end
            isqrt32=low[15:0];
        end
    endfunction

    // Combinational logic.

    always_comb begin
        byte_offset = proc_addr - DST_BASE;
        pixel_index = byte_offset / 3;
        byte_lane = byte_offset % 3;
        gray_weighted_sum = (red_byte * 16'd77) + (green_byte * 16'd150) + (proc_wdata * 16'd29);
        gray_pixel = gray_weighted_sum[15:8];
        abs_dx = (gray_pixel >= previous_gray) ? (gray_pixel-previous_gray) : (previous_gray-gray_pixel);
        abs_dy = (gray_pixel >= previous_row[pixel_index % IMG_W]) ?
                 (gray_pixel-previous_row[pixel_index % IMG_W]) :
                 (previous_row[pixel_index % IMG_W]-gray_pixel);
        gradient_term = 9'd0;
        if ((pixel_index % IMG_W) != 0) gradient_term = gradient_term + abs_dx;
        if ((pixel_index / IMG_W) != 0) gradient_term = gradient_term + abs_dy;
        count_at_bin = {17'd0, histogram[histogram_index]};
        log_term = (count_at_bin == 0) ? 32'd0 : count_at_bin * log2_count_q4(histogram[histogram_index]);
        hist_total_with_current = histogram_term_sum + log_term;
        mean_integer = pixel_sum / PIXELS;
        mean_square_integer = pixel_square_sum / PIXELS;
        variance_integer = (mean_square_integer >= mean_integer*mean_integer) ?
                           mean_square_integer - mean_integer*mean_integer : 32'd0;
        variance_x10000 = (variance_numerator * 64'd10000) / (PIXELS * PIXELS);
        variance_numerator = ({32'd0,pixel_square_sum} * 64'(PIXELS)) - ({32'd0,pixel_sum} * {32'd0,pixel_sum});
    end

    // Clocked logic.

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= COLLECT_FRAME;
            red_byte <= 0; green_byte <= 0; previous_gray <= 0;
            pixel_sum <= 0; pixel_square_sum <= 0; gradient_sum <= 0;
            histogram_term_sum <= 0; histogram_index <= 0;
            entropy_x100 <= 0; avg_gradient_x100 <= 0; rms_contrast_x100 <= 0;
            metrics_valid <= 1'b0;
            for (i=0; i<256; i=i+1) histogram[i] <= 0;
            for (i=0; i<IMG_W; i=i+1) previous_row[i] <= 0;
        end else begin
            if (state == COLLECT_FRAME) begin
                if (proc_we && (proc_addr >= DST_BASE) && (byte_offset < RGB_BYTES)) begin
                    if (byte_offset == 0) begin
                        pixel_sum <= 0;
                        pixel_square_sum <= 0;
                        gradient_sum <= 0;
                        metrics_valid <= 1'b0;
                    end
                    case (byte_lane)
                        0: red_byte <= proc_wdata;
                        1: green_byte <= proc_wdata;
                        2: begin
                            histogram[gray_pixel] <= histogram[gray_pixel] + 1'b1;
                            pixel_sum <= pixel_sum + gray_pixel;
                            pixel_square_sum <= pixel_square_sum + ({24'd0,gray_pixel} * {24'd0,gray_pixel});
                            gradient_sum <= gradient_sum + gradient_term;
                            previous_gray <= gray_pixel;
                            previous_row[pixel_index % IMG_W] <= gray_pixel;
                            if (byte_offset == LAST_BYTE_OFFSET) begin
                                state <= SCAN_HISTOGRAM;
                                histogram_index <= 0;
                                histogram_term_sum <= 0;
                            end
                        end
                        default: ;
                    endcase
                end
            end else begin
                histogram[histogram_index] <= 0;
                histogram_term_sum <= hist_total_with_current;
                if (histogram_index == 8'd255) begin
                    
                    if ((hist_total_with_current >> 14) <= 224)
                        entropy_x100 <= ((224 - (hist_total_with_current >> 14)) * 100) / 16;
                    else entropy_x100 <= 0;
                    avg_gradient_x100 <= (gradient_sum * 100) / EDGE_COUNT;
                    
                    rms_contrast_x100 <= isqrt32(variance_x10000);
                    metrics_valid <= 1'b1;
                    state <= COLLECT_FRAME;
                    histogram_index <= 0;
                end else histogram_index <= histogram_index + 1'b1;
            end
        end
    end
endmodule
