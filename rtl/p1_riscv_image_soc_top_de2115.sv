// p1_riscv_image_soc_top_de2115: main hardware logic.
module p1_riscv_image_soc_top_de2115 #(
    parameter int CPU_RESET_CYCLES       = 16,
    parameter int PROCESS_TIMEOUT_CYCLES = 5000000    
) (
    input  logic        CLOCK_50,
    input  logic [3:0]  KEY,          

    
    input  logic [17:0] SW,

    inout  wire  [35:0] GPIO,

    
    output logic [17:0] LEDR,

    
    output logic [7:0]  VGA_R,
    output logic [7:0]  VGA_G,
    output logic [7:0]  VGA_B,
    output logic        VGA_CLK,
    output logic        VGA_BLANK_N,
    output logic        VGA_HS,
    output logic        VGA_VS,
    output logic        VGA_SYNC_N
);

    
    logic reset_btn;
    assign reset_btn = ~KEY[0];

    logic [15:0] sw;
    logic [15:0] led;
    assign sw           = SW[15:0];
    assign LEDR[15:0]   = led;
    assign LEDR[17:16]  = 2'b00;

    logic       ov7670_pclk;
    logic       ov7670_href;
    logic       ov7670_vsync;
    logic [7:0] ov7670_d;
    logic       ov7670_xclk;
    logic       ov7670_sioc;
    logic       ov7670_pwdn;
    logic       ov7670_reset_n;

    assign ov7670_d      = GPIO[7:0];
    assign ov7670_pclk   = GPIO[8];
    assign ov7670_href   = GPIO[9];
    assign ov7670_vsync  = GPIO[10];
    assign GPIO[11]      = ov7670_xclk;
    assign GPIO[12]      = ov7670_sioc;
    
    assign GPIO[14]      = ov7670_pwdn;
    assign GPIO[15]      = ov7670_reset_n;
    assign GPIO[35:16]   = 20'bz;   

    logic [3:0] vga_r;
    logic [3:0] vga_g;
    logic [3:0] vga_b;
    logic       hsync;
    logic       vsync;

    assign VGA_R  = {vga_r, vga_r};
    assign VGA_G  = {vga_g, vga_g};
    assign VGA_B  = {vga_b, vga_b};
    assign VGA_HS = hsync;
    assign VGA_VS = vsync;
    assign VGA_SYNC_N   = 1'b0;
    assign VGA_BLANK_N  = vga_active;
    assign VGA_CLK      = clk_25mhz;

    localparam int IMG_W    = 128;
    localparam int IMG_H    = 128;
    localparam int SRC_BASE = 0;
    localparam int DST_BASE = 32'h0000_C000;

    
    logic clk_core;
    assign clk_core = CLOCK_50;

    
    logic clk_25mhz;

    // Clocked logic.

    always_ff @(posedge CLOCK_50 or posedge reset_btn) begin
        if (reset_btn)
            clk_25mhz <= 1'b0;
        else
            clk_25mhz <= ~clk_25mhz;
    end

    assign ov7670_xclk    = clk_25mhz;
    assign ov7670_pwdn    = 1'b0; 
    assign ov7670_reset_n = 1'b1; 

    logic ov_sccb_done;
    logic ov_sccb_busy;
    logic ov_sccb_error;

    p1_ov7670_sccb_init u_ov7670_sccb (
        .clk        (clk_core),
        .reset      (reset_btn),
        .colorbar_enable(sw[10]),
        .ov_sioc    (ov7670_sioc),
        .ov_siod    (GPIO[13]),
        .init_done  (ov_sccb_done),
        .init_busy  (ov_sccb_busy),
        .init_error (ov_sccb_error)
    );

    logic [15:0] sw_meta, sw_sync;

    // Clocked logic.

    always_ff @(posedge clk_core or posedge reset_btn) begin
        if (reset_btn) begin
            sw_meta <= 16'b0;
            sw_sync <= 16'b0;
        end else begin
            sw_meta <= sw;
            sw_sync <= sw_meta;
        end
    end

    logic       ipu_mode;
    logic       cpu_bist_mode;
    logic       cpu_welcome_mode;
    logic [5:0] instr_sw;
    logic       instr_onehot;
    logic       ipu_valid;
    logic       bypass_output;
    logic [2:0] selected_program_id;

    assign ipu_mode         = sw_sync[0];
    assign cpu_bist_mode    = 1'b0;   
    assign cpu_welcome_mode = (~sw_sync[0]);
    assign instr_sw         = sw_sync[6:1];
    assign instr_onehot  = (instr_sw != 6'b000000) && ((instr_sw & (instr_sw - 6'b000001)) == 6'b000000);
    assign ipu_valid     = ipu_mode && instr_onehot;
    assign bypass_output = ~ipu_valid;

    // Combinational logic.

    always_comb begin
        unique case (1'b1)
            sw_sync[1]: selected_program_id = 3'd0; 
            sw_sync[2]: selected_program_id = 3'd1; 
            sw_sync[3]: selected_program_id = 3'd2; 
            sw_sync[4]: selected_program_id = 3'd3; 
            sw_sync[5]: selected_program_id = 3'd4; 
            sw_sync[6]: selected_program_id = 3'd5; 
            default:    selected_program_id = 3'd0;
        endcase
    end

    logic [6:0] control_word_q;
    logic [6:0] control_word_now;
    logic       control_changed;

    assign control_word_now = {ipu_mode, cpu_bist_mode, ipu_valid, selected_program_id, instr_onehot};
    assign control_changed  = (control_word_now != control_word_q);

    // Clocked logic.

    always_ff @(posedge clk_core or posedge reset_btn) begin
        if (reset_btn)
            control_word_q <= 7'b0;
        else
            control_word_q <= control_word_now;
    end

    
    logic [9:0] vga_x;
    logic [9:0] vga_y;
    logic       vga_active;

    p1_vga_640x480 u_vga_timing (
        .clk_pix (clk_25mhz),
        .reset   (reset_btn),
        .x       (vga_x),
        .y       (vga_y),
        .active  (vga_active),
        .hsync   (hsync),
        .vsync   (vsync)
    );

    
    logic        host_we;       
    logic [31:0] host_addr;
    logic [7:0]  host_wdata;

    logic        cam_core_we;   
    logic [31:0] cam_core_addr;
    logic [7:0]  cam_core_wdata;
    logic        core_frame_done;
    logic        core_load_done;

    logic        frame_done;
    logic        frame_loading;
    logic        load_done;
    logic [31:0] load_count;
    logic [31:0] frame_count;
    logic [31:0] dropped_frame_count;
    logic [31:0] spi_error_count;

    logic        processing_active;
    logic        accept_enable;

    assign accept_enable = ipu_valid ? ~processing_active : 1'b0;

    p1_ov7670_capture_128_rgb565_to_rgb888 #(
        .IMG_W      (IMG_W),
        .IMG_H      (IMG_H),
        .BASE_ADDR  (SRC_BASE),
        .SWAP_RB    (1'b0),
        .SWAP_BYTES (1'b0)
    ) u_ov7670_capture (
        .clk                 (clk_core),
        .reset               (reset_btn | ~ov_sccb_done),
        .ov_pclk             (ov7670_pclk),
        .ov_href             (ov7670_href),
        .ov_vsync            (ov7670_vsync),
        .ov_d                (ov7670_d),
        .accept_enable       (accept_enable),
        .cfg_swap_bytes      (sw_sync[12]),
        .cfg_swap_rb         (sw_sync[13]),
        .cfg_sample_falling  (sw_sync[11]),
        .host_we             (host_we),
        .host_addr           (host_addr),
        .host_wdata          (host_wdata),
        .core_host_we        (cam_core_we),
        .core_host_addr      (cam_core_addr),
        .core_host_wdata     (cam_core_wdata),
        .core_frame_done     (core_frame_done),
        .core_load_done      (core_load_done),
        .frame_done          (frame_done),
        .frame_loading       (frame_loading),
        .load_done           (load_done),
        .byte_count          (load_count),
        .frame_count         (frame_count),
        .dropped_frame_count (dropped_frame_count),
        .error_count         (spi_error_count)
    );

    
    logic        proc_we;
    logic [31:0] proc_addr;
    logic [7:0]  proc_wdata;

    logic [31:0] debug_pc;
    logic [31:0] debug_instr;
    logic        debug_ipu_busy;
    logic        debug_ipu_done;
    logic [31:0] debug_ipu_result;
    logic [31:0] debug_cycle_counter;
    logic [31:0] perf_ipu_busy_count;
    logic [31:0] perf_conv_count;
    logic [31:0] perf_pool_count;
    logic [31:0] perf_stall_count;
    logic [9:0]  debug_psnr_tenths;
    logic [31:0] debug_hardware_mse;
    logic        bist_done;
    logic        bist_pass;
    logic [5:0]  bist_fail_count;
    logic [31:0] bist_reg_got [0:31];
    logic [7:0]  bist_mem_got [0:10];

    logic        core_host_we;
    logic [31:0] core_host_addr;
    logic [7:0]  core_host_wdata;

    assign core_host_we    = ipu_valid ? cam_core_we : 1'b0;
    assign core_host_addr  = cam_core_addr;
    assign core_host_wdata = cam_core_wdata;

    logic cpu_reset_hold;
    logic [$clog2(CPU_RESET_CYCLES+1)-1:0] cpu_reset_count;
    logic cpu_reset;
    logic [31:0] process_counter;
    logic process_timeout_seen;

    // Clocked logic.

    always_ff @(posedge clk_core or posedge reset_btn) begin
        if (reset_btn) begin
            cpu_reset_hold       <= 1'b1;
            cpu_reset_count      <= CPU_RESET_CYCLES;
            processing_active    <= 1'b0;
            process_counter      <= 32'd0;
            process_timeout_seen <= 1'b0;
        end else begin
            if (control_changed) begin
                
                
                cpu_reset_hold       <= 1'b1;
                cpu_reset_count      <= CPU_RESET_CYCLES;
                processing_active    <= 1'b0;
                process_counter      <= 32'd0;
                process_timeout_seen <= 1'b0;
            end else if (cpu_welcome_mode || !ipu_valid) begin
                
                
                cpu_reset_hold    <= 1'b1;
                cpu_reset_count   <= CPU_RESET_CYCLES;
                processing_active <= 1'b0;
                process_counter   <= 32'd0;
            end else begin
                
                if (core_frame_done) begin
                    cpu_reset_hold       <= 1'b1;
                    cpu_reset_count      <= CPU_RESET_CYCLES;
                    processing_active    <= 1'b1;
                    process_counter      <= 32'd0;
                    process_timeout_seen <= 1'b0;
                end else begin
                    if (cpu_reset_hold) begin
                        if (cpu_reset_count != 0)
                            cpu_reset_count <= cpu_reset_count - 1'b1;
                        else if (core_load_done)
                            cpu_reset_hold <= 1'b0;
                    end

                    if (processing_active && !cpu_reset_hold) begin
                        process_counter <= process_counter + 32'd1;

                        if (debug_ipu_done) begin
                            processing_active <= 1'b0;
                        end else if (process_counter >= PROCESS_TIMEOUT_CYCLES) begin
                            processing_active    <= 1'b0;
                            process_timeout_seen <= 1'b1;
                        end
                    end
                end
            end
        end
    end

    assign cpu_reset = reset_btn | cpu_reset_hold;

    localparam int CORE_HZ = 50000000;
    logic [31:0] fps_window_counter;
    logic [31:0] cam_frame_accum;
    logic [31:0] disp_frame_accum;
    logic [31:0] fps_estimate;
    logic [31:0] last_process_cycles;
    logic        vga_vsync_q;
    logic        display_60_mode;

    assign display_60_mode = sw_sync[9];

    // Clocked logic.

    always_ff @(posedge clk_core or posedge reset_btn) begin
        if (reset_btn) begin
            fps_window_counter <= 32'd0;
            cam_frame_accum    <= 32'd0;
            disp_frame_accum   <= 32'd0;
            fps_estimate       <= 32'd0;
            last_process_cycles<= 32'd0;
            vga_vsync_q        <= 1'b0;
        end else begin
            vga_vsync_q <= vsync;

            if (frame_done)
                cam_frame_accum <= cam_frame_accum + 32'd1;

            if (vsync && !vga_vsync_q)
                disp_frame_accum <= disp_frame_accum + 32'd1;

            if (fps_window_counter >= CORE_HZ-1) begin
                fps_window_counter <= 32'd0;
                fps_estimate       <= display_60_mode ? disp_frame_accum : cam_frame_accum;
                cam_frame_accum    <= 32'd0;
                disp_frame_accum   <= 32'd0;
            end else begin
                fps_window_counter <= fps_window_counter + 32'd1;
            end

            if (ipu_valid && processing_active && !cpu_reset_hold && (debug_ipu_done || (process_counter >= PROCESS_TIMEOUT_CYCLES))) begin
                last_process_cycles <= process_counter;
            end
        end
    end


    p1_rv32i_core_fpga #(
        .IMG_W (IMG_W),
        .IMG_H (IMG_H)
    ) cpu_core (
        .clk                 (clk_core),
        .reset               (cpu_reset),
        .program_id          (selected_program_id),
        .cpu_regression_mode (cpu_bist_mode),
        .host_we             (core_host_we),
        .host_addr           (core_host_addr),
        .host_wdata          (core_host_wdata),
        .proc_we             (proc_we),
        .proc_addr           (proc_addr),
        .proc_wdata          (proc_wdata),
        .debug_pc            (debug_pc),
        .debug_instr         (debug_instr),
        .debug_ipu_busy      (debug_ipu_busy),
        .debug_ipu_done      (debug_ipu_done),
        .debug_ipu_result    (debug_ipu_result),
        .debug_cycle_counter (debug_cycle_counter),
        .perf_ipu_busy_count (perf_ipu_busy_count),
        .perf_conv_count     (perf_conv_count),
        .perf_pool_count     (perf_pool_count),
        .perf_stall_count    (perf_stall_count),
        .debug_psnr_tenths   (debug_psnr_tenths),
        .debug_hardware_mse  (debug_hardware_mse),
        .bist_done           (bist_done),
        .bist_pass           (bist_pass),
        .bist_fail_count     (bist_fail_count),
        .bist_reg_got        (bist_reg_got),
        .bist_mem_got        (bist_mem_got)
    );

    logic [9:0]  psnr_hold;
    logic [31:0] mse_hold;

    // Clocked logic.

    always_ff @(posedge clk_core or posedge reset_btn) begin
        if (reset_btn) begin
            psnr_hold <= 10'd0;
            mse_hold  <= 32'd0;
        end else if (!ipu_valid || control_changed) begin
            psnr_hold <= 10'd0;
            mse_hold  <= 32'd0;
        end else if (debug_ipu_done) begin
            psnr_hold <= debug_psnr_tenths;
            mse_hold  <= debug_hardware_mse;
        end
    end

    logic cpu_pass;
    logic cpu_fail;
    assign cpu_pass = 1'b0;
    assign cpu_fail = 1'b0;

    
    logic [1:0] overlay_mode;
    assign overlay_mode = 2'd0;

    logic [15:0] metric_entropy_x100;
    logic [15:0] metric_ag_x100;
    logic [15:0] metric_rms_x100;
    logic metric_valid;
    logic [31:0] metric_time_centi_ms;
    logic [31:0] metric_throughput_centi;
    logic [31:0] metric_fps_tenths;
    logic [31:0] processed_frame_accum;
    logic [31:0] processed_fps_estimate;

    p1_image_metrics_fpga #(.IMG_W(IMG_W), .IMG_H(IMG_H), .DST_BASE(DST_BASE)) u_image_metrics (
        .clk               (clk_core),
        .reset             (reset_btn),
        .proc_we           (ipu_valid ? proc_we : 1'b0),
        .proc_addr         (proc_addr),
        .proc_wdata        (proc_wdata),
        .entropy_x100      (metric_entropy_x100),
        .avg_gradient_x100 (metric_ag_x100),
        .rms_contrast_x100 (metric_rms_x100),
        .metrics_valid     (metric_valid)
    );

    // Combinational logic.

    always_comb begin
        metric_time_centi_ms = (last_process_cycles == 0) ? 32'd0 : (last_process_cycles / 32'd500);
        metric_throughput_centi = (last_process_cycles == 0) ? 32'd0 : (32'd81920000 / last_process_cycles);
        metric_fps_tenths = processed_fps_estimate * 32'd10;
    end

    // Clocked logic.

    always_ff @(posedge clk_core or posedge reset_btn) begin
        if (reset_btn) begin
            processed_frame_accum <= 32'd0;
            processed_fps_estimate <= 32'd0;
        end else begin
            if (debug_ipu_done)
                processed_frame_accum <= processed_frame_accum + 32'd1;
            if (fps_window_counter >= CORE_HZ-1) begin
                processed_fps_estimate <= processed_frame_accum;
                processed_frame_accum <= 32'd0;
            end
        end
    end

    p1_vga_frame_display #(
        .IMG_W    (IMG_W),
        .IMG_H    (IMG_H),
        .SRC_BASE (SRC_BASE),
        .DST_BASE (DST_BASE),
        .LEFT_X   (96),
        .TOP_Y    (176),
        .GAP      (64)
    ) u_display (
        .clk_wr           (clk_core),
        .clk_pix          (clk_25mhz),
        .reset            (reset_btn),
        .right_bypass_src (bypass_output),
        .overlay_mode     (overlay_mode),
        .bist_page        (2'b00),
        .bist_done        (1'b0),
        .bist_pass        (1'b0),
        .bist_fail_count  (6'b0),
        .bist_reg_got     (bist_reg_got),
        .bist_mem_got     (bist_mem_got),
        .ipu_mode         (ipu_mode),
        .ipu_valid        (ipu_valid),
        .ipu_program_id   (selected_program_id),
        .fps_estimate     (fps_estimate),
        .last_process_cycles(last_process_cycles),
        .frame_count      (frame_count),
        .dropped_frame_count(dropped_frame_count),
        .spi_error_count  (spi_error_count),
        .perf_cycle_count (debug_cycle_counter),
        .perf_ipu_busy_count(perf_ipu_busy_count),
        .perf_conv_count  (perf_conv_count),
        .perf_pool_count  (perf_pool_count),
        .perf_stall_count (perf_stall_count),
        .debug_ipu_result (debug_ipu_result),
        .psnr_tenths      (psnr_hold),
        .mse_value        (mse_hold),
        .metric_entropy_x100 (metric_entropy_x100),
        .metric_ag_x100 (metric_ag_x100),
        .metric_rms_x100 (metric_rms_x100),
        .metric_time_centi_ms (metric_time_centi_ms),
        .metric_throughput_centi (metric_throughput_centi),
        .metric_fps_tenths (metric_fps_tenths),
        .metric_valid (metric_valid),
        .x                (vga_x),
        .y                (vga_y),
        .active           (vga_active),
        .host_we          (host_we),
        .host_addr        (host_addr),
        .host_wdata       (host_wdata),
        .src_frame_done   (frame_done),
        .proc_we          (ipu_valid ? proc_we : 1'b0),
        .proc_addr        (proc_addr),
        .proc_wdata       (proc_wdata),
        .vga_r            (vga_r),
        .vga_g            (vga_g),
        .vga_b            (vga_b)
    );

    assign led[0]    = ipu_mode;
    assign led[1]    = sw_sync[1];
    assign led[2]    = sw_sync[2];
    assign led[3]    = sw_sync[3];
    assign led[4]    = sw_sync[4];
    assign led[5]    = ipu_valid;
    assign led[6]    = sw_sync[5];
    assign led[7]    = sw_sync[6];
    assign led[8]    = 1'b0;
    assign led[9]    = |spi_error_count | ov_sccb_error;
    assign led[10]   = processing_active;
    assign led[11]   = process_timeout_seen;
    assign led[12]   = sw_sync[12];
    assign led[13]   = sw_sync[13];
    assign led[14]   = sw_sync[10];
    assign led[15]   = sw_sync[9];

endmodule
