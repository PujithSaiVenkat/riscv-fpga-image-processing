// p1_ipu_fpga: main hardware logic.
module p1_ipu_fpga #(
    parameter int IMG_W = 128,
    parameter int IMG_H = 128,
    parameter logic [7:0] THRESHOLD_VALUE = 8'd128,
    
    
    parameter bit         BORDER_PASSTHRU = 1'b0
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic [2:0]  op,
    input  logic [3:0]  kernel,
    input  logic [31:0] src_base,
    input  logic [31:0] dst_base,
    output logic        busy,
    output logic        done,
    output logic [31:0] result,
    output logic [31:0] conv_cycle_count,
    output logic [31:0] pool_cycle_count,
    output logic [31:0] hardware_mse,      
    output logic [9:0]  psnr_tenths,       

    output logic        mem_re,
    output logic        mem_we,
    output logic [31:0] mem_addr,
    output logic [7:0]  mem_wdata,
    input  logic [7:0]  mem_rdata
);

    localparam int PIXELS      = IMG_W * IMG_H;
    localparam int POOL_W      = IMG_W / 2;
    localparam int POOL_H      = IMG_H / 2;
    localparam int POOL_PIXELS = POOL_W * POOL_H;

    localparam logic [2:0] OP_GRAY     = 3'd0;
    localparam logic [2:0] OP_THRESH   = 3'd1;
    localparam logic [2:0] OP_MAXPIX   = 3'd2;
    localparam logic [2:0] OP_SOBEL    = 3'd3;
    localparam logic [2:0] OP_CONV     = 3'd4;
    localparam logic [2:0] OP_MAXPOOL  = 3'd5;
    localparam logic [2:0] OP_AVGPOOL  = 3'd6;
    localparam logic [2:0] OP_GAUSS    = 3'd7;

    typedef enum logic [4:0] {
        ST_IDLE          = 5'd0,
        ST_RGB_REQ_R     = 5'd1,
        ST_RGB_CAP_R     = 5'd2,
        ST_RGB_REQ_G     = 5'd3,
        ST_RGB_CAP_G     = 5'd4,
        ST_RGB_REQ_B     = 5'd5,
        ST_RGB_CAP_B     = 5'd6,
        ST_SIMPLE_WRITE  = 5'd7,
        ST_WIN_START     = 5'd8,
        ST_WIN_REQ       = 5'd9,
        ST_WIN_CAP       = 5'd10,
        ST_CONV_WRITE    = 5'd11,
        ST_POOL_REQ      = 5'd12,
        ST_POOL_CAP      = 5'd13,
        ST_POOL_WRITE    = 5'd14,
        ST_FINISH        = 5'd15
    } state_t;

    state_t state;
    logic [2:0]  op_r;
    logic [3:0]  kernel_r;
    logic [31:0] src_base_r, dst_base_r;
    logic [31:0] pix_idx;
    logic [1:0]  dst_chan;   

    logic [7:0] r_reg, g_reg, b_reg;
    logic [7:0] max_pix;
    logic [7:0] gray_now;

    logic [3:0] win_idx;
    logic [1:0] chan_idx;
    logic [7:0] tmp_r, tmp_g;

    
    logic [7:0] winR0, winR1, winR2, winR3, winR4, winR5, winR6, winR7, winR8;
    logic [7:0] winG0, winG1, winG2, winG3, winG4, winG5, winG6, winG7, winG8;
    logic [7:0] winB0, winB1, winB2, winB3, winB4, winB5, winB6, winB7, winB8;

    logic [1:0] pool_idx;
    logic [7:0] pool_a, pool_b, pool_c, pool_d;

    integer cx, cy;
    integer nx, ny;
    integer n_pix;

    
    integer gx_r, gy_r, mag_r;
    integer gx_g, gy_g, mag_g;
    integer gx_b, gy_b, mag_b;
    logic [7:0] sobel_r, sobel_g, sobel_b;
    integer conv_sum_r, conv_sum_g, conv_sum_b;
    integer conv_norm_r, conv_norm_g, conv_norm_b;
    logic [7:0] conv_r, conv_g, conv_b;
    integer gauss_sum_r, gauss_sum_g, gauss_sum_b;
    logic [7:0] gauss_r, gauss_g, gauss_b;
    logic [7:0] conv_out_r, conv_out_g, conv_out_b;

    
    integer sharp_sum_r, sharp_sum_g, sharp_sum_b;
    logic [7:0] sharp_r, sharp_g, sharp_b;

    
    logic        is_border;
    logic        border_fetch;      
    logic [7:0]  conv_wr_byte;      
    logic [7:0]  mse_src;           
    logic signed [9:0] mse_diff;
    logic [7:0]  mse_abs;
    logic [15:0] mse_sq;
    logic [31:0] mse_acc;           
    logic [44:0] mse_prod;
    logic [31:0] mse_q4_w;          
    logic [31:0] mse_q4_r;
    logic        mse_valid;
    logic [9:0]  psnr_w;

    logic [7:0] thresh_gray;
    logic [9:0] pool_sum;
    logic [7:0] pool_pix;

    
    integer pool_sx, pool_sy, pool_dx, pool_dy, pool_px, pool_py;
    integer pool_pixaddr;

    function automatic [7:0] rgb_to_gray(
        input logic [7:0] r,
        input logic [7:0] g,
        input logic [7:0] b
    );
        logic [15:0] sum;
        begin
            sum = (r * 8'd77) + (g * 8'd150) + (b * 8'd29);
            rgb_to_gray = sum[15:8];
        end
    endfunction

    function automatic signed [7:0] kernel_coeff(
        input logic [3:0] kid,
        input integer idx
    );
        begin
            case (kid)
                4'd0: begin 
                    case (idx)
                        4: kernel_coeff = 8'sd1;
                        default: kernel_coeff = 8'sd0;
                    endcase
                end
                4'd1: begin 
                    case (idx)
                        0: kernel_coeff = -8'sd1;
                        1: kernel_coeff =  8'sd0;
                        2: kernel_coeff =  8'sd1;
                        3: kernel_coeff = -8'sd2;
                        4: kernel_coeff =  8'sd0;
                        5: kernel_coeff =  8'sd2;
                        6: kernel_coeff = -8'sd1;
                        7: kernel_coeff =  8'sd0;
                        8: kernel_coeff =  8'sd1;
                        default: kernel_coeff = 8'sd0;
                    endcase
                end
                4'd2: begin 
                    case (idx)
                        0: kernel_coeff =  8'sd1;
                        1: kernel_coeff =  8'sd2;
                        2: kernel_coeff =  8'sd1;
                        3: kernel_coeff =  8'sd0;
                        4: kernel_coeff =  8'sd0;
                        5: kernel_coeff =  8'sd0;
                        6: kernel_coeff = -8'sd1;
                        7: kernel_coeff = -8'sd2;
                        8: kernel_coeff = -8'sd1;
                        default: kernel_coeff = 8'sd0;
                    endcase
                end
                4'd3: begin 
                    case (idx)
                        0,2,6,8: kernel_coeff = 8'sd1;
                        1,3,5,7: kernel_coeff = 8'sd2;
                        4: kernel_coeff = 8'sd4;
                        default: kernel_coeff = 8'sd0;
                    endcase
                end
                4'd4: begin 
                    case (idx)
                        0,2,6,8: kernel_coeff = 8'sd0;
                        1,3,5,7: kernel_coeff = -8'sd1;
                        4: kernel_coeff = 8'sd5;
                        default: kernel_coeff = 8'sd0;
                    endcase
                end
                4'd5: begin 
                    case (idx)
                        4: kernel_coeff = 8'sd8;
                        default: kernel_coeff = -8'sd1;
                    endcase
                end
                default: kernel_coeff = 8'sd0;
            endcase
        end
    endfunction

    // Combinational logic.

    always_comb begin
        gray_now = rgb_to_gray(r_reg, g_reg, b_reg);
        thresh_gray = (gray_now >= THRESHOLD_VALUE) ? 8'hFF : 8'h00;
    end

    // Combinational logic.

    always_comb begin
        
        cx = pix_idx % IMG_W;
        cy = pix_idx / IMG_W;

        
        nx = cx + (win_idx % 3) - 1;
        ny = cy + (win_idx / 3) - 1;
        n_pix = (ny * IMG_W) + nx;

        
        gx_r = -$signed({1'b0, winR0})
               -($signed({1'b0, winR3}) <<< 1)
               -$signed({1'b0, winR6})
               +$signed({1'b0, winR2})
               +($signed({1'b0, winR5}) <<< 1)
               +$signed({1'b0, winR8});
        gy_r =  $signed({1'b0, winR0})
               +($signed({1'b0, winR1}) <<< 1)
               +$signed({1'b0, winR2})
               -$signed({1'b0, winR6})
               -($signed({1'b0, winR7}) <<< 1)
               -$signed({1'b0, winR8});
        if (gx_r < 0) gx_r = -gx_r;
        if (gy_r < 0) gy_r = -gy_r;
        mag_r = gx_r + gy_r;
        sobel_r = (mag_r > 255) ? 8'hFF : mag_r[7:0];

        gx_g = -$signed({1'b0, winG0})
               -($signed({1'b0, winG3}) <<< 1)
               -$signed({1'b0, winG6})
               +$signed({1'b0, winG2})
               +($signed({1'b0, winG5}) <<< 1)
               +$signed({1'b0, winG8});
        gy_g =  $signed({1'b0, winG0})
               +($signed({1'b0, winG1}) <<< 1)
               +$signed({1'b0, winG2})
               -$signed({1'b0, winG6})
               -($signed({1'b0, winG7}) <<< 1)
               -$signed({1'b0, winG8});
        if (gx_g < 0) gx_g = -gx_g;
        if (gy_g < 0) gy_g = -gy_g;
        mag_g = gx_g + gy_g;
        sobel_g = (mag_g > 255) ? 8'hFF : mag_g[7:0];

        gx_b = -$signed({1'b0, winB0})
               -($signed({1'b0, winB3}) <<< 1)
               -$signed({1'b0, winB6})
               +$signed({1'b0, winB2})
               +($signed({1'b0, winB5}) <<< 1)
               +$signed({1'b0, winB8});
        gy_b =  $signed({1'b0, winB0})
               +($signed({1'b0, winB1}) <<< 1)
               +$signed({1'b0, winB2})
               -$signed({1'b0, winB6})
               -($signed({1'b0, winB7}) <<< 1)
               -$signed({1'b0, winB8});
        if (gx_b < 0) gx_b = -gx_b;
        if (gy_b < 0) gy_b = -gy_b;
        mag_b = gx_b + gy_b;
        sobel_b = (mag_b > 255) ? 8'hFF : mag_b[7:0];

        
        conv_sum_r = 0;
        conv_sum_r += $signed(kernel_coeff(kernel_r,0)) * $signed({1'b0, winR0});
        conv_sum_r += $signed(kernel_coeff(kernel_r,1)) * $signed({1'b0, winR1});
        conv_sum_r += $signed(kernel_coeff(kernel_r,2)) * $signed({1'b0, winR2});
        conv_sum_r += $signed(kernel_coeff(kernel_r,3)) * $signed({1'b0, winR3});
        conv_sum_r += $signed(kernel_coeff(kernel_r,4)) * $signed({1'b0, winR4});
        conv_sum_r += $signed(kernel_coeff(kernel_r,5)) * $signed({1'b0, winR5});
        conv_sum_r += $signed(kernel_coeff(kernel_r,6)) * $signed({1'b0, winR6});
        conv_sum_r += $signed(kernel_coeff(kernel_r,7)) * $signed({1'b0, winR7});
        conv_sum_r += $signed(kernel_coeff(kernel_r,8)) * $signed({1'b0, winR8});
        conv_norm_r = (kernel_r == 4'd3) ? (conv_sum_r >>> 4) : conv_sum_r;
        if (conv_norm_r < 0)        conv_r = 8'd0;
        else if (conv_norm_r > 255) conv_r = 8'hFF;
        else                        conv_r = conv_norm_r[7:0];

        conv_sum_g = 0;
        conv_sum_g += $signed(kernel_coeff(kernel_r,0)) * $signed({1'b0, winG0});
        conv_sum_g += $signed(kernel_coeff(kernel_r,1)) * $signed({1'b0, winG1});
        conv_sum_g += $signed(kernel_coeff(kernel_r,2)) * $signed({1'b0, winG2});
        conv_sum_g += $signed(kernel_coeff(kernel_r,3)) * $signed({1'b0, winG3});
        conv_sum_g += $signed(kernel_coeff(kernel_r,4)) * $signed({1'b0, winG4});
        conv_sum_g += $signed(kernel_coeff(kernel_r,5)) * $signed({1'b0, winG5});
        conv_sum_g += $signed(kernel_coeff(kernel_r,6)) * $signed({1'b0, winG6});
        conv_sum_g += $signed(kernel_coeff(kernel_r,7)) * $signed({1'b0, winG7});
        conv_sum_g += $signed(kernel_coeff(kernel_r,8)) * $signed({1'b0, winG8});
        conv_norm_g = (kernel_r == 4'd3) ? (conv_sum_g >>> 4) : conv_sum_g;
        if (conv_norm_g < 0)        conv_g = 8'd0;
        else if (conv_norm_g > 255) conv_g = 8'hFF;
        else                        conv_g = conv_norm_g[7:0];

        conv_sum_b = 0;
        conv_sum_b += $signed(kernel_coeff(kernel_r,0)) * $signed({1'b0, winB0});
        conv_sum_b += $signed(kernel_coeff(kernel_r,1)) * $signed({1'b0, winB1});
        conv_sum_b += $signed(kernel_coeff(kernel_r,2)) * $signed({1'b0, winB2});
        conv_sum_b += $signed(kernel_coeff(kernel_r,3)) * $signed({1'b0, winB3});
        conv_sum_b += $signed(kernel_coeff(kernel_r,4)) * $signed({1'b0, winB4});
        conv_sum_b += $signed(kernel_coeff(kernel_r,5)) * $signed({1'b0, winB5});
        conv_sum_b += $signed(kernel_coeff(kernel_r,6)) * $signed({1'b0, winB6});
        conv_sum_b += $signed(kernel_coeff(kernel_r,7)) * $signed({1'b0, winB7});
        conv_sum_b += $signed(kernel_coeff(kernel_r,8)) * $signed({1'b0, winB8});
        conv_norm_b = (kernel_r == 4'd3) ? (conv_sum_b >>> 4) : conv_sum_b;
        if (conv_norm_b < 0)        conv_b = 8'd0;
        else if (conv_norm_b > 255) conv_b = 8'hFF;
        else                        conv_b = conv_norm_b[7:0];

        
        gauss_sum_r = $signed({1'b0, winR0})
                    + ($signed({1'b0, winR1}) <<< 1)
                    + $signed({1'b0, winR2})
                    + ($signed({1'b0, winR3}) <<< 1)
                    + ($signed({1'b0, winR4}) <<< 2)
                    + ($signed({1'b0, winR5}) <<< 1)
                    + $signed({1'b0, winR6})
                    + ($signed({1'b0, winR7}) <<< 1)
                    + $signed({1'b0, winR8});
        gauss_r = gauss_sum_r[11:4];
        gauss_sum_g = $signed({1'b0, winG0})
                    + ($signed({1'b0, winG1}) <<< 1)
                    + $signed({1'b0, winG2})
                    + ($signed({1'b0, winG3}) <<< 1)
                    + ($signed({1'b0, winG4}) <<< 2)
                    + ($signed({1'b0, winG5}) <<< 1)
                    + $signed({1'b0, winG6})
                    + ($signed({1'b0, winG7}) <<< 1)
                    + $signed({1'b0, winG8});
        gauss_g = gauss_sum_g[11:4];
        gauss_sum_b = $signed({1'b0, winB0})
                    + ($signed({1'b0, winB1}) <<< 1)
                    + $signed({1'b0, winB2})
                    + ($signed({1'b0, winB3}) <<< 1)
                    + ($signed({1'b0, winB4}) <<< 2)
                    + ($signed({1'b0, winB5}) <<< 1)
                    + $signed({1'b0, winB6})
                    + ($signed({1'b0, winB7}) <<< 1)
                    + $signed({1'b0, winB8});
        gauss_b = gauss_sum_b[11:4];

        
        sharp_sum_r = ($signed({1'b0, winR4}) <<< 2) + $signed({1'b0, winR4})
                    - $signed({1'b0, winR1}) - $signed({1'b0, winR3})
                    - $signed({1'b0, winR5}) - $signed({1'b0, winR7});
        if (sharp_sum_r < 0)        sharp_r = 8'd0;
        else if (sharp_sum_r > 255) sharp_r = 8'hFF;
        else                        sharp_r = sharp_sum_r[7:0];

        sharp_sum_g = ($signed({1'b0, winG4}) <<< 2) + $signed({1'b0, winG4})
                    - $signed({1'b0, winG1}) - $signed({1'b0, winG3})
                    - $signed({1'b0, winG5}) - $signed({1'b0, winG7});
        if (sharp_sum_g < 0)        sharp_g = 8'd0;
        else if (sharp_sum_g > 255) sharp_g = 8'hFF;
        else                        sharp_g = sharp_sum_g[7:0];

        sharp_sum_b = ($signed({1'b0, winB4}) <<< 2) + $signed({1'b0, winB4})
                    - $signed({1'b0, winB1}) - $signed({1'b0, winB3})
                    - $signed({1'b0, winB5}) - $signed({1'b0, winB7});
        if (sharp_sum_b < 0)        sharp_b = 8'd0;
        else if (sharp_sum_b > 255) sharp_b = 8'hFF;
        else                        sharp_b = sharp_sum_b[7:0];

        if (op_r == OP_SOBEL) begin
            conv_out_r = sobel_r; conv_out_g = sobel_g; conv_out_b = sobel_b;
        end else if (op_r == OP_GAUSS) begin
            conv_out_r = gauss_r; conv_out_g = gauss_g; conv_out_b = gauss_b;
        end else if ((op_r == OP_CONV) && (kernel_r == 4'd4)) begin
            conv_out_r = sharp_r; conv_out_g = sharp_g; conv_out_b = sharp_b;
        end else begin
            conv_out_r = conv_r; conv_out_g = conv_g; conv_out_b = conv_b;
        end

        
        is_border = (cx == 0) || (cx == IMG_W-1) || (cy == 0) || (cy == IMG_H-1);

        case (dst_chan)
            2'd0:    mse_src = winR4;
            2'd1:    mse_src = winG4;
            default: mse_src = winB4;
        endcase

        if (is_border)
            conv_wr_byte = BORDER_PASSTHRU ? mse_src : 8'd0;
        else if (dst_chan == 2'd0)
            conv_wr_byte = conv_out_r;
        else if (dst_chan == 2'd1)
            conv_wr_byte = conv_out_g;
        else
            conv_wr_byte = conv_out_b;

        mse_diff = $signed({2'b00, conv_wr_byte}) - $signed({2'b00, mse_src});
        mse_abs  = (mse_diff < 0) ? 8'(-mse_diff) : 8'(mse_diff);
        mse_sq   = mse_abs * mse_abs;                    

        mse_prod = mse_acc[31:10] * 23'd5592406;
        mse_q4_w = {11'b0, mse_prod[44:24]};

        
        pool_sx = (pix_idx % POOL_W) * 2;
        pool_sy = (pix_idx / POOL_W) * 2;
        pool_dx = pool_idx % 2;
        pool_dy = pool_idx / 2;
        pool_px = pool_sx + pool_dx;
        pool_py = pool_sy + pool_dy;
        pool_pixaddr = (pool_py * IMG_W) + pool_px;

        pool_sum = {2'b00, pool_a} + {2'b00, pool_b} + {2'b00, pool_c} + {2'b00, pool_d};
        if (op_r == OP_MAXPOOL) begin
            pool_pix = pool_a;
            if (pool_b > pool_pix) pool_pix = pool_b;
            if (pool_c > pool_pix) pool_pix = pool_c;
            if (pool_d > pool_pix) pool_pix = pool_d;
        end else begin
            pool_pix = pool_sum[9:2];
        end
    end

    // Combinational logic.

    always_comb begin
        mem_re    = 1'b0;
        mem_we    = 1'b0;
        mem_addr  = 32'b0;
        mem_wdata = 8'b0;

        case (state)
            ST_RGB_REQ_R: begin
                mem_re   = 1'b1;
                mem_addr = src_base_r + (pix_idx * 32'd3);
            end
            ST_RGB_REQ_G: begin
                mem_re   = 1'b1;
                mem_addr = src_base_r + (pix_idx * 32'd3) + 32'd1;
            end
            ST_RGB_REQ_B: begin
                mem_re   = 1'b1;
                mem_addr = src_base_r + (pix_idx * 32'd3) + 32'd2;
            end
            ST_SIMPLE_WRITE: begin
                if (op_r != OP_MAXPIX) begin
                    mem_we    = 1'b1;
                    mem_addr  = dst_base_r + (pix_idx * 32'd3) + {30'b0, dst_chan};
                    mem_wdata = (op_r == OP_THRESH) ? thresh_gray : gray_now;
                end
            end
            ST_WIN_REQ: begin
                mem_re   = 1'b1;
                mem_addr = src_base_r + (n_pix * 32'd3) + {30'b0, chan_idx};
            end
            ST_CONV_WRITE: begin
                mem_we   = 1'b1;
                mem_addr = dst_base_r + (pix_idx * 32'd3) + {30'b0, dst_chan};
                mem_wdata = conv_wr_byte;
            end
            ST_POOL_REQ: begin
                mem_re   = 1'b1;
                mem_addr = src_base_r + (pool_pixaddr * 32'd3) + {30'b0, chan_idx};
            end
            ST_POOL_WRITE: begin
                mem_we    = 1'b1;
                mem_addr  = dst_base_r + (pix_idx * 32'd3) + {30'b0, dst_chan};
                mem_wdata = pool_pix;
            end
            default: begin
            end
        endcase
    end

    // Clocked logic.

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            busy             <= 1'b0;
            done             <= 1'b0;
            result           <= 32'b0;
            conv_cycle_count <= 32'b0;
            pool_cycle_count <= 32'b0;
            hardware_mse     <= 32'b0;
            mse_acc          <= 32'b0;
            mse_q4_r         <= 32'b0;
            mse_valid        <= 1'b0;
            border_fetch     <= 1'b0;
            state            <= ST_IDLE;
            op_r             <= 3'b0;
            kernel_r         <= 4'b0;
            src_base_r       <= 32'b0;
            dst_base_r       <= 32'b0;
            pix_idx          <= 32'b0;
            dst_chan         <= 2'b0;
            r_reg            <= 8'b0;
            g_reg            <= 8'b0;
            b_reg            <= 8'b0;
            max_pix          <= 8'b0;
            win_idx          <= 4'b0;
            chan_idx         <= 2'b0;
            tmp_r            <= 8'b0;
            tmp_g            <= 8'b0;
            winR0 <= 8'b0; winR1 <= 8'b0; winR2 <= 8'b0;
            winR3 <= 8'b0; winR4 <= 8'b0; winR5 <= 8'b0;
            winR6 <= 8'b0; winR7 <= 8'b0; winR8 <= 8'b0;
            winG0 <= 8'b0; winG1 <= 8'b0; winG2 <= 8'b0;
            winG3 <= 8'b0; winG4 <= 8'b0; winG5 <= 8'b0;
            winG6 <= 8'b0; winG7 <= 8'b0; winG8 <= 8'b0;
            winB0 <= 8'b0; winB1 <= 8'b0; winB2 <= 8'b0;
            winB3 <= 8'b0; winB4 <= 8'b0; winB5 <= 8'b0;
            winB6 <= 8'b0; winB7 <= 8'b0; winB8 <= 8'b0;
            pool_idx         <= 2'b0;
            pool_a           <= 8'b0;
            pool_b           <= 8'b0;
            pool_c           <= 8'b0;
            pool_d           <= 8'b0;
        end else begin
            if (busy) begin
                if ((op_r == OP_SOBEL) || (op_r == OP_CONV) || (op_r == OP_GAUSS))
                    conv_cycle_count <= conv_cycle_count + 32'd1;
                else if ((op_r == OP_MAXPOOL) || (op_r == OP_AVGPOOL))
                    pool_cycle_count <= pool_cycle_count + 32'd1;
            end

            if (start && !busy) begin
                busy       <= 1'b1;
                done       <= 1'b0;
                result     <= 32'b0;
                hardware_mse <= 32'b0;
                mse_acc    <= 32'b0;
                mse_q4_r   <= 32'b0;
                mse_valid  <= 1'b0;
                border_fetch <= 1'b0;
                op_r       <= op;
                kernel_r   <= kernel;
                src_base_r <= src_base;
                dst_base_r <= dst_base;
                pix_idx    <= 32'b0;
                dst_chan   <= 2'b0;
                max_pix    <= 8'b0;
                win_idx    <= 4'd0;
                chan_idx   <= 2'd0;
                pool_idx   <= 2'd0;

                case (op)
                    OP_GRAY, OP_THRESH, OP_MAXPIX: state <= ST_RGB_REQ_R;
                    OP_SOBEL, OP_CONV, OP_GAUSS:   state <= ST_WIN_START;
                    OP_MAXPOOL, OP_AVGPOOL:        state <= ST_POOL_REQ;
                    default: begin
                        busy   <= 1'b0;
                        done   <= 1'b1;
                        result <= 32'b0;
                        state  <= ST_IDLE;
                    end
                endcase
            end else begin
                case (state)
                    ST_IDLE: begin
                    end

                    ST_RGB_REQ_R: state <= ST_RGB_CAP_R;
                    ST_RGB_CAP_R: begin
                        r_reg <= mem_rdata;
                        state <= ST_RGB_REQ_G;
                    end
                    ST_RGB_REQ_G: state <= ST_RGB_CAP_G;
                    ST_RGB_CAP_G: begin
                        g_reg <= mem_rdata;
                        state <= ST_RGB_REQ_B;
                    end
                    ST_RGB_REQ_B: state <= ST_RGB_CAP_B;
                    ST_RGB_CAP_B: begin
                        b_reg <= mem_rdata;
                        state <= ST_SIMPLE_WRITE;
                    end

                    ST_SIMPLE_WRITE: begin
                        if (op_r == OP_MAXPIX) begin
                            if (gray_now > max_pix)
                                max_pix <= gray_now;
                            if (pix_idx == PIXELS-1) begin
                                result <= {24'b0, (gray_now > max_pix ? gray_now : max_pix)};
                                state  <= ST_FINISH;
                            end else begin
                                pix_idx <= pix_idx + 32'd1;
                                state   <= ST_RGB_REQ_R;
                            end
                        end else begin
                            
                            if (dst_chan == 2'd2) begin
                                dst_chan <= 2'b0;
                                if (pix_idx == PIXELS-1) begin
                                    result <= 32'd1;
                                    state  <= ST_FINISH;
                                end else begin
                                    pix_idx <= pix_idx + 32'd1;
                                    state   <= ST_RGB_REQ_R;
                                end
                            end else begin
                                dst_chan <= dst_chan + 2'd1;
                                state    <= ST_SIMPLE_WRITE;
                            end
                        end
                    end

                    ST_WIN_START: begin
                        if (is_border) begin
                            
                            
                            border_fetch <= 1'b1;
                            win_idx      <= 4'd4;
                            chan_idx     <= 2'd0;
                            state        <= ST_WIN_REQ;
                        end else begin
                            border_fetch <= 1'b0;
                            win_idx      <= 4'd0;
                            chan_idx     <= 2'd0;
                            state        <= ST_WIN_REQ;
                        end
                    end

                    ST_WIN_REQ: state <= ST_WIN_CAP;
                    ST_WIN_CAP: begin
                        if (chan_idx == 2'd0) begin
                            tmp_r    <= mem_rdata;
                            chan_idx <= 2'd1;
                            state    <= ST_WIN_REQ;
                        end else if (chan_idx == 2'd1) begin
                            tmp_g    <= mem_rdata;
                            chan_idx <= 2'd2;
                            state    <= ST_WIN_REQ;
                        end else begin
                            case (win_idx)
                                4'd0: begin winR0 <= tmp_r; winG0 <= tmp_g; winB0 <= mem_rdata; end
                                4'd1: begin winR1 <= tmp_r; winG1 <= tmp_g; winB1 <= mem_rdata; end
                                4'd2: begin winR2 <= tmp_r; winG2 <= tmp_g; winB2 <= mem_rdata; end
                                4'd3: begin winR3 <= tmp_r; winG3 <= tmp_g; winB3 <= mem_rdata; end
                                4'd4: begin winR4 <= tmp_r; winG4 <= tmp_g; winB4 <= mem_rdata; end
                                4'd5: begin winR5 <= tmp_r; winG5 <= tmp_g; winB5 <= mem_rdata; end
                                4'd6: begin winR6 <= tmp_r; winG6 <= tmp_g; winB6 <= mem_rdata; end
                                4'd7: begin winR7 <= tmp_r; winG7 <= tmp_g; winB7 <= mem_rdata; end
                                4'd8: begin winR8 <= tmp_r; winG8 <= tmp_g; winB8 <= mem_rdata; end
                                default: ;
                            endcase
                            chan_idx <= 2'd0;
                            if ((win_idx == 4'd8) || (border_fetch && (win_idx == 4'd4))) begin
                                dst_chan <= 2'b0;
                                state <= ST_CONV_WRITE;
                            end else begin
                                win_idx <= win_idx + 4'd1;
                                state   <= ST_WIN_REQ;
                            end
                        end
                    end

                    ST_CONV_WRITE: begin
                        
                        mse_acc <= mse_acc + {16'b0, mse_sq};
                        
                        if (dst_chan == 2'd2) begin
                            dst_chan <= 2'b0;
                            if (pix_idx == PIXELS-1) begin
                                result <= 32'd1;
                                state  <= ST_FINISH;
                            end else begin
                                pix_idx <= pix_idx + 32'd1;
                                state   <= ST_WIN_START;
                            end
                        end else begin
                            dst_chan <= dst_chan + 2'd1;
                            state    <= ST_CONV_WRITE;
                        end
                    end

                    ST_POOL_REQ: state <= ST_POOL_CAP;
                    ST_POOL_CAP: begin
                        if (chan_idx == 2'd0) begin
                            tmp_r    <= mem_rdata;
                            chan_idx <= 2'd1;
                            state    <= ST_POOL_REQ;
                        end else if (chan_idx == 2'd1) begin
                            tmp_g    <= mem_rdata;
                            chan_idx <= 2'd2;
                            state    <= ST_POOL_REQ;
                        end else begin
                            case (pool_idx)
                                2'd0: pool_a <= rgb_to_gray(tmp_r, tmp_g, mem_rdata);
                                2'd1: pool_b <= rgb_to_gray(tmp_r, tmp_g, mem_rdata);
                                2'd2: pool_c <= rgb_to_gray(tmp_r, tmp_g, mem_rdata);
                                2'd3: pool_d <= rgb_to_gray(tmp_r, tmp_g, mem_rdata);
                                default: ;
                            endcase
                            chan_idx <= 2'd0;
                            if (pool_idx == 2'd3) begin
                                pool_idx <= 2'd0;
                                dst_chan <= 2'b0;
                                state    <= ST_POOL_WRITE;
                            end else begin
                                pool_idx <= pool_idx + 2'd1;
                                state    <= ST_POOL_REQ;
                            end
                        end
                    end

                    ST_POOL_WRITE: begin
                        if (dst_chan == 2'd2) begin
                            dst_chan <= 2'b0;
                            if (pix_idx == POOL_PIXELS-1) begin
                                result <= 32'd1;
                                state  <= ST_FINISH;
                            end else begin
                                pix_idx <= pix_idx + 32'd1;
                                state   <= ST_POOL_REQ;
                            end
                        end else begin
                            dst_chan <= dst_chan + 2'd1;
                            state    <= ST_POOL_WRITE;
                        end
                    end

                    ST_FINISH: begin
                        if ((op_r == OP_SOBEL) || (op_r == OP_CONV) || (op_r == OP_GAUSS)) begin
                            hardware_mse <= {4'b0, mse_q4_w[31:4]};   
                            mse_q4_r     <= mse_q4_w;
                            mse_valid    <= 1'b1;
                        end
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= ST_IDLE;
                    end

                    default: begin
                        state <= ST_IDLE;
                    end
                endcase
            end
        end
    end

    
    p1_psnr_calc u_psnr (
        .mse_q4      (mse_q4_r),
        .valid       (mse_valid),
        .psnr_tenths (psnr_w)
    );

    // Clocked logic.

    always_ff @(posedge clk or posedge reset) begin
        if (reset) psnr_tenths <= 10'd0;
        else       psnr_tenths <= psnr_w;
    end

endmodule
