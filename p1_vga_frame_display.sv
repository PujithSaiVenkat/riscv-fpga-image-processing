// p1_evpix_vga_dual_clock_ram: main hardware logic.
module p1_evpix_vga_dual_clock_ram #(
    parameter integer DATA_WIDTH = 8,
    parameter integer ADDR_WIDTH = 14,
    parameter integer DEPTH      = 16384
)(
    input  wire                  clk_wr,
    input  wire                  clk_rd,
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [DATA_WIDTH-1:0] wr_data,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output wire [DATA_WIDTH-1:0] rd_data
);

    altsyncram ram_inst (
        .clock0    (clk_wr),
        .clock1    (clk_rd),

        .wren_a    (wr_en),
        .address_a (wr_addr),
        .data_a    (wr_data),

        .address_b (rd_addr),
        .rden_b    (1'b1),
        .q_b       (rd_data)
    );

    defparam
        ram_inst.lpm_type = "altsyncram",
        ram_inst.operation_mode = "DUAL_PORT",
        ram_inst.intended_device_family = "Cyclone IV E",
        ram_inst.ram_block_type = "M9K",

        ram_inst.width_a = DATA_WIDTH,
        ram_inst.width_b = DATA_WIDTH,
        ram_inst.widthad_a = ADDR_WIDTH,
        ram_inst.widthad_b = ADDR_WIDTH,
        ram_inst.numwords_a = DEPTH,
        ram_inst.numwords_b = DEPTH,

        
        ram_inst.clock_enable_input_a = "BYPASS",

        
        ram_inst.address_reg_b = "CLOCK1",
        ram_inst.rdcontrol_reg_b = "CLOCK1",
        ram_inst.outdata_reg_b = "CLOCK1",

        ram_inst.clock_enable_input_b = "BYPASS",
        ram_inst.clock_enable_output_b = "BYPASS",

        ram_inst.address_aclr_b = "NONE",
        ram_inst.rdcontrol_aclr_b = "NONE",
        ram_inst.outdata_aclr_b = "NONE",

        ram_inst.read_during_write_mode_mixed_ports = "DONT_CARE",
        ram_inst.power_up_uninitialized = "FALSE",
        ram_inst.width_byteena_a = 1;

endmodule


module p1_vga_frame_display #(
    parameter int IMG_W    = 128,
    parameter int IMG_H    = 128,
    parameter int SRC_BASE = 0,
    parameter int DST_BASE = 32'h0000_C000,
    parameter int LEFT_X   = 96,
    parameter int TOP_Y    = 176,
    parameter int GAP      = 64
) (
    input  logic        clk_wr,
    input  logic        clk_pix,
    input  logic        reset,

    input  logic        right_bypass_src,
    input  logic [1:0]  overlay_mode,   
    input  logic [1:0]  bist_page,
    input  logic        bist_done,
    input  logic        bist_pass,
    input  logic [5:0]  bist_fail_count,
    input  logic [31:0] bist_reg_got [0:31],
    input  logic [7:0]  bist_mem_got [0:10],

    
    input  logic        ipu_mode,
    input  logic        ipu_valid,
    input  logic [2:0]  ipu_program_id,
    input  logic [31:0] fps_estimate,
    input  logic [31:0] last_process_cycles,
    input  logic [31:0] frame_count,
    input  logic [31:0] dropped_frame_count,
    input  logic [31:0] spi_error_count,
    input  logic [31:0] perf_cycle_count,
    input  logic [31:0] perf_ipu_busy_count,
    input  logic [31:0] perf_conv_count,
    input  logic [31:0] perf_pool_count,
    input  logic [31:0] perf_stall_count,
    input  logic [31:0] debug_ipu_result,
    input  logic [9:0]  psnr_tenths,   
    input  logic [31:0] mse_value,     
    input  logic [15:0] metric_entropy_x100,
    input  logic [15:0] metric_ag_x100,
    input  logic [15:0] metric_rms_x100,
    input  logic [31:0] metric_time_centi_ms,
    input  logic [31:0] metric_throughput_centi,
    input  logic [31:0] metric_fps_tenths,
    input  logic        metric_valid,

    input  logic [9:0]  x,
    input  logic [9:0]  y,
    input  logic        active,

    input  logic        host_we,
    input  logic [31:0] host_addr,
    input  logic [7:0]  host_wdata,
    input  logic        src_frame_done,  

    input  logic        proc_we,
    input  logic [31:0] proc_addr,
    input  logic [7:0]  proc_wdata,

    output logic [3:0]  vga_r,
    output logic [3:0]  vga_g,
    output logic [3:0]  vga_b
);

    localparam int PIXELS    = IMG_W * IMG_H;
    localparam int RGB_BYTES = PIXELS * 3;
    localparam int RIGHT_X   = LEFT_X + IMG_W + GAP;
    localparam int PIX_AW    = $clog2(PIXELS);

    wire [11:0] src_rgb444_a_q;
    wire [11:0] src_rgb444_b_q;
    wire [11:0] dst_rgb444_q;

    logic src_wr_sel;
    logic src_rd_sel;

    logic [7:0]  cap_r;
    logic [7:0]  cap_g;
    logic [1:0]  host_rgb_phase_wr;
    logic [PIX_AW-1:0] cap_pix_addr;
    logic        proc_in_range;
    logic        proc_new_frame_byte;
    logic [7:0]  proc_r;
    logic [7:0]  proc_g;
    logic [1:0]  proc_rgb_phase_wr;
    logic [PIX_AW-1:0] proc_pix_addr;
    logic        host_in_src_range;
    logic        host_new_frame_byte;

    assign host_in_src_range   = host_we && (host_addr >= SRC_BASE) && (host_addr < (SRC_BASE + RGB_BYTES));
    assign host_new_frame_byte = host_in_src_range && (host_addr == SRC_BASE);
    assign proc_in_range       = proc_we && (proc_addr >= DST_BASE) && ((proc_addr - DST_BASE) < RGB_BYTES);
    assign proc_new_frame_byte = proc_in_range && (proc_addr == DST_BASE);

    
    // Clocked logic.

    
    always_ff @(posedge clk_wr or posedge reset) begin
        if (reset) begin
            src_wr_sel        <= 1'b0;
            src_rd_sel        <= 1'b1;
            cap_r             <= 8'd0;
            cap_g             <= 8'd0;
            cap_pix_addr      <= '0;
            host_rgb_phase_wr <= 2'd0;
            proc_r            <= 8'd0;
            proc_g            <= 8'd0;
            proc_pix_addr     <= '0;
            proc_rgb_phase_wr <= 2'd0;
        end else begin

            if (host_new_frame_byte) begin
                
                cap_r             <= host_wdata;
                host_rgb_phase_wr <= 2'd1;
                cap_pix_addr      <= '0;
            end else if (host_in_src_range) begin
                unique case (host_rgb_phase_wr)
                    2'd0: begin
                        cap_r             <= host_wdata;
                        host_rgb_phase_wr <= 2'd1;
                    end
                    2'd1: begin
                        cap_g             <= host_wdata;
                        host_rgb_phase_wr <= 2'd2;
                    end
                    default: begin
                        host_rgb_phase_wr <= 2'd0;
                        if (cap_pix_addr != PIXELS-1)
                            cap_pix_addr <= cap_pix_addr + {{(PIX_AW-1){1'b0}}, 1'b1};
                    end
                endcase
            end

            if (src_frame_done) begin
                src_rd_sel <= src_wr_sel;
                src_wr_sel <= ~src_wr_sel;
            end

            if (proc_new_frame_byte) begin
                proc_r            <= proc_wdata;
                proc_rgb_phase_wr <= 2'd1;
                proc_pix_addr     <= '0;
            end else if (proc_in_range) begin
                unique case (proc_rgb_phase_wr)
                    2'd0: begin
                        proc_r            <= proc_wdata;
                        proc_rgb_phase_wr <= 2'd1;
                    end
                    2'd1: begin
                        proc_g            <= proc_wdata;
                        proc_rgb_phase_wr <= 2'd2;
                    end
                    default: begin
                        proc_rgb_phase_wr <= 2'd0;
                        if (proc_pix_addr != PIXELS-1)
                            proc_pix_addr <= proc_pix_addr + {{(PIX_AW-1){1'b0}}, 1'b1};
                    end
                endcase
            end
        end
    end

    p1_evpix_vga_dual_clock_ram #(
        .DATA_WIDTH(12),
        .ADDR_WIDTH(14),
        .DEPTH(PIXELS)
    ) u_src_ram_a (
        .clk_wr  (clk_wr),
        .clk_rd  (clk_pix),
        .wr_en   (host_in_src_range && !host_new_frame_byte &&
                  (host_rgb_phase_wr == 2'd2) && (cap_pix_addr < PIXELS) && !src_wr_sel),
        .wr_addr (cap_pix_addr),
        .wr_data ({cap_r[7:4], cap_g[7:4], host_wdata[7:4]}),
        .rd_addr (pix_index[PIX_AW-1:0]),
        .rd_data (src_rgb444_a_q)
    );

    p1_evpix_vga_dual_clock_ram #(
        .DATA_WIDTH(12),
        .ADDR_WIDTH(14),
        .DEPTH(PIXELS)
    ) u_src_ram_b (
        .clk_wr  (clk_wr),
        .clk_rd  (clk_pix),
        .wr_en   (host_in_src_range && !host_new_frame_byte &&
                  (host_rgb_phase_wr == 2'd2) && (cap_pix_addr < PIXELS) && src_wr_sel),
        .wr_addr (cap_pix_addr),
        .wr_data ({cap_r[7:4], cap_g[7:4], host_wdata[7:4]}),
        .rd_addr (pix_index[PIX_AW-1:0]),
        .rd_data (src_rgb444_b_q)
    );

    p1_evpix_vga_dual_clock_ram #(
        .DATA_WIDTH(12),
        .ADDR_WIDTH(14),
        .DEPTH(PIXELS)
    ) u_dst_ram (
        .clk_wr  (clk_wr),
        .clk_rd  (clk_pix),
        .wr_en   (proc_in_range && !proc_new_frame_byte &&
                  (proc_rgb_phase_wr == 2'd2) && (proc_pix_addr < PIXELS)),
        .wr_addr (proc_pix_addr),
        .wr_data ({proc_r[7:4], proc_g[7:4], proc_wdata[7:4]}),
        .rd_addr (pix_index[PIX_AW-1:0]),
        .rd_data (dst_rgb444_q)
    );

    logic in_left, in_right;
    logic pane_active;
    logic [9:0] img_x, img_y;
    logic [31:0] pix_index;
    logic [11:0] src_a_q, src_b_q, src_q;
    logic [11:0] dst_q;
    logic        in_left_q, in_right_q, active_q, right_bypass_src_q;
    logic        src_rd_sel_pix_q;
    logic [1:0]  overlay_mode_q;
    logic [9:0]  x_q, y_q;

    // Combinational logic.

    always_comb begin
        in_left  = active && (x >= LEFT_X) && (x < LEFT_X + IMG_W) && (y >= TOP_Y) && (y < TOP_Y + IMG_H);
        in_right = active && (x >= RIGHT_X) && (x < RIGHT_X + IMG_W) && (y >= TOP_Y) && (y < TOP_Y + IMG_H);
        pane_active = in_left || in_right;
        if (in_left) begin
            img_x = x - LEFT_X; img_y = y - TOP_Y;
        end else if (in_right) begin
            img_x = x - RIGHT_X; img_y = y - TOP_Y;
        end else begin
            img_x = 10'd0; img_y = 10'd0;
        end
        pix_index = (img_y * IMG_W) + img_x;
    end

    // Combinational logic.

    always_comb begin
        if (pane_active && (pix_index < PIXELS)) begin
            src_a_q = src_rgb444_a_q;
            src_b_q = src_rgb444_b_q;
            dst_q   = dst_rgb444_q;
        end else begin
            src_a_q = 12'b0;
            src_b_q = 12'b0;
            dst_q   = 12'b0;
        end
    end

    // Clocked logic.

    always_ff @(posedge clk_pix) begin
        src_rd_sel_pix_q <= src_rd_sel;
        in_left_q <= in_left; in_right_q <= in_right; active_q <= active;
        right_bypass_src_q <= right_bypass_src; overlay_mode_q <= overlay_mode;
        x_q <= x; y_q <= y;
    end

    assign src_q = (!src_rd_sel_pix_q) ? src_a_q : src_b_q;

    function automatic logic [3:0] hex_nibble(input logic [31:0] value, input int pos);
        begin
            hex_nibble = value[4*(7-pos) +: 4];
        end
    endfunction

    function automatic logic [7:0] hex_char(input logic [3:0] n);
        begin
            hex_char = (n < 10) ? (8'd48 + n) : (8'd55 + n);
        end
    endfunction

    function automatic logic [7:0] dec2_char(input int value, input int pos);
        int tens; int ones;
        begin
            tens = (value / 10) % 10; ones = value % 10;
            if (pos == 0) dec2_char = (value < 10) ? 8'd32 : (8'd48 + tens);
            else dec2_char = 8'd48 + ones;
        end
    endfunction

    function automatic logic [7:0] dec3_char(input int value, input int pos);
        int h; int t; int o;
        begin
            h = (value / 100) % 10; t = (value / 10) % 10; o = value % 10;
            if (pos == 0) dec3_char = (value < 100) ? 8'd32 : (8'd48 + h);
            else if (pos == 1) dec3_char = (value < 10) ? 8'd32 : (8'd48 + t);
            else dec3_char = 8'd48 + o;
        end
    endfunction

    function automatic logic [7:0] decimal_digit(input logic [31:0] value, input int pos);
        logic [31:0] digit_value;
        begin
            case (pos)
                0: digit_value = value % 10;
                1: digit_value = (value / 10) % 10;
                2: digit_value = (value / 100) % 10;
                3: digit_value = (value / 1000) % 10;
                4: digit_value = (value / 10000) % 10;
                5: digit_value = (value / 100000) % 10;
                default: digit_value = (value / 1000000) % 10;
            endcase
            decimal_digit = 8'd48 + digit_value[7:0];
        end
    endfunction

    function automatic logic [31:0] expected_reg(input int idx);
        begin
            unique case (idx)
                1: expected_reg=32'h0000000A; 2: expected_reg=32'hFFFFFFFD; 3: expected_reg=32'h00000005; 4: expected_reg=32'h0000000F;
                5: expected_reg=32'h00000007; 6: expected_reg=32'h00000001; 7: expected_reg=32'h00000001; 8: expected_reg=32'h0000000C;
                9: expected_reg=32'h0000001F; 10: expected_reg=32'h00000000; 11: expected_reg=32'h00000014; 12: expected_reg=32'h00000007;
                13: expected_reg=32'hFFFFFFFE; 14: expected_reg=32'h0000000F; 15: expected_reg=32'h00000005; 16: expected_reg=32'h00000007;
                17: expected_reg=32'h0000000F; 18: expected_reg=32'h00000008; 19: expected_reg=32'h00000280; 20: expected_reg=32'h00000000;
                21: expected_reg=32'hFFFFFFFF; 22: expected_reg=32'h00000001; 23: expected_reg=32'h00000000; 24: expected_reg=32'h12345000;
                25: expected_reg=32'h00000060; 26: expected_reg=32'h00000100; 27: expected_reg=32'h0000000A; 28: expected_reg=32'h000000C0;
                29: expected_reg=32'h000000EC; 30: expected_reg=32'h000000D0; 31: expected_reg=32'h0000FFFD;
                default: expected_reg=32'h00000000;
            endcase
        end
    endfunction

    function automatic logic [7:0] expected_mem(input int k);
        begin
            unique case(k)
                0: expected_mem=8'h0A; 1: expected_mem=8'h00; 2: expected_mem=8'h00; 3: expected_mem=8'h00;
                4: expected_mem=8'h05; 5: expected_mem=8'h00; 6: expected_mem=8'h07; 7: expected_mem=8'hFD;
                8: expected_mem=8'hFF; 9: expected_mem=8'hFF; 10: expected_mem=8'hFF;
                default: expected_mem=8'h00;
            endcase
        end
    endfunction

    function automatic int mem_addr_for_test(input int k);
        begin
            unique case(k)
                0: mem_addr_for_test=256; 1: mem_addr_for_test=257; 2: mem_addr_for_test=258; 3: mem_addr_for_test=259;
                4: mem_addr_for_test=260; 5: mem_addr_for_test=261; 6: mem_addr_for_test=262; 7: mem_addr_for_test=264;
                8: mem_addr_for_test=265; 9: mem_addr_for_test=266; 10: mem_addr_for_test=267; default: mem_addr_for_test=0;
            endcase
        end
    endfunction


    function automatic logic [7:0] short_hex_char(input logic [31:0] value, input int nib);
        begin
            short_hex_char = hex_char(value[4*(7-nib) +: 4]);
        end
    endfunction

    function automatic logic [7:0] instr_name_char(input int item, input int pos);
        begin
            instr_name_char = 8'd32;
            unique case (item)
                
                0,1,2,3,4,25: begin 
                    unique case (pos) 0:instr_name_char=8'd65;1:instr_name_char=8'd68;2:instr_name_char=8'd68;3:instr_name_char=8'd73; default: ; endcase
                end
                5: begin unique case(pos) 0:instr_name_char=8'd83;1:instr_name_char=8'd76;2:instr_name_char=8'd84;3:instr_name_char=8'd73; default: ; endcase end 
                6: begin unique case(pos) 0:instr_name_char=8'd83;1:instr_name_char=8'd76;2:instr_name_char=8'd84;3:instr_name_char=8'd85;4:instr_name_char=8'd73; default: ; endcase end 
                7: begin unique case(pos) 0:instr_name_char=8'd65;1:instr_name_char=8'd78;2:instr_name_char=8'd68;3:instr_name_char=8'd73; default: ; endcase end 
                8: begin unique case(pos) 0:instr_name_char=8'd79;1:instr_name_char=8'd82;2:instr_name_char=8'd73; default: ; endcase end 
                9: begin unique case(pos) 0:instr_name_char=8'd88;1:instr_name_char=8'd79;2:instr_name_char=8'd82;3:instr_name_char=8'd73; default: ; endcase end 
                10: begin unique case(pos) 0:instr_name_char=8'd83;1:instr_name_char=8'd76;2:instr_name_char=8'd76;3:instr_name_char=8'd73; default: ; endcase end 
                11: begin unique case(pos) 0:instr_name_char=8'd83;1:instr_name_char=8'd82;2:instr_name_char=8'd76;3:instr_name_char=8'd73; default: ; endcase end 
                12: begin unique case(pos) 0:instr_name_char=8'd83;1:instr_name_char=8'd82;2:instr_name_char=8'd65;3:instr_name_char=8'd73; default: ; endcase end 
                13: begin unique case(pos) 0:instr_name_char=8'd65;1:instr_name_char=8'd68;2:instr_name_char=8'd68; default: ; endcase end 
                14: begin unique case(pos) 0:instr_name_char=8'd83;1:instr_name_char=8'd85;2:instr_name_char=8'd66; default: ; endcase end 
                15: begin unique case(pos) 0:instr_name_char=8'd65;1:instr_name_char=8'd78;2:instr_name_char=8'd68; default: ; endcase end 
                16: begin unique case(pos) 0:instr_name_char=8'd79;1:instr_name_char=8'd82; default: ; endcase end 
                17: begin unique case(pos) 0:instr_name_char=8'd88;1:instr_name_char=8'd79;2:instr_name_char=8'd82; default: ; endcase end 
                18: begin unique case(pos) 0:instr_name_char=8'd83;1:instr_name_char=8'd76;2:instr_name_char=8'd76; default: ; endcase end 
                19: begin unique case(pos) 0:instr_name_char=8'd83;1:instr_name_char=8'd82;2:instr_name_char=8'd76; default: ; endcase end 
                20: begin unique case(pos) 0:instr_name_char=8'd83;1:instr_name_char=8'd82;2:instr_name_char=8'd65; default: ; endcase end 
                21: begin unique case(pos) 0:instr_name_char=8'd83;1:instr_name_char=8'd76;2:instr_name_char=8'd84; default: ; endcase end 
                22: begin unique case(pos) 0:instr_name_char=8'd83;1:instr_name_char=8'd76;2:instr_name_char=8'd84;3:instr_name_char=8'd85; default: ; endcase end 
                23: begin unique case(pos) 0:instr_name_char=8'd76;1:instr_name_char=8'd85;2:instr_name_char=8'd73; default: ; endcase end 
                24: begin unique case(pos) 0:instr_name_char=8'd65;1:instr_name_char=8'd85;2:instr_name_char=8'd73;3:instr_name_char=8'd80;4:instr_name_char=8'd67; default: ; endcase end 
                26: begin unique case(pos) 0:instr_name_char=8'd76;1:instr_name_char=8'd87; default: ; endcase end 
                27: begin unique case(pos) 0:instr_name_char=8'd74;1:instr_name_char=8'd65;2:instr_name_char=8'd76; default: ; endcase end 
                28: begin unique case(pos) 0:instr_name_char=8'd74;1:instr_name_char=8'd65;2:instr_name_char=8'd76;3:instr_name_char=8'd82; default: ; endcase end 
                29: begin unique case(pos) 0:instr_name_char=8'd74;1:instr_name_char=8'd65;2:instr_name_char=8'd76;3:instr_name_char=8'd82; default: ; endcase end 
                30: begin unique case(pos) 0:instr_name_char=8'd76;1:instr_name_char=8'd72;2:instr_name_char=8'd85; default: ; endcase end 
                
                31,32,33,34,38,39,40,41: begin unique case(pos) 0:instr_name_char=8'd83;1:instr_name_char=8'd87; default: ; endcase end 
                35,36: begin unique case(pos) 0:instr_name_char=8'd83;1:instr_name_char=8'd72; default: ; endcase end 
                37: begin unique case(pos) 0:instr_name_char=8'd83;1:instr_name_char=8'd66; default: ; endcase end 
                default: ;
            endcase
        end
    endfunction

    function automatic logic [7:0] program_name_char(input logic [2:0] pid, input int pos);
        begin
            program_name_char = 8'd32;
            unique case (pid)
                3'd0: begin unique case(pos) 0:program_name_char=8'd83;1:program_name_char=8'd79;2:program_name_char=8'd66;3:program_name_char=8'd69;4:program_name_char=8'd76; default: ; endcase end 
                3'd1: begin unique case(pos) 0:program_name_char=8'd71;1:program_name_char=8'd82;2:program_name_char=8'd65;3:program_name_char=8'd89; default: ; endcase end 
                3'd2: begin unique case(pos) 0:program_name_char=8'd84;1:program_name_char=8'd72;2:program_name_char=8'd82;3:program_name_char=8'd69;4:program_name_char=8'd83;5:program_name_char=8'd72; default: ; endcase end 
                3'd3: begin unique case(pos) 0:program_name_char=8'd67;1:program_name_char=8'd79;2:program_name_char=8'd78;3:program_name_char=8'd86; default: ; endcase end 
                default: ;
            endcase
        end
    endfunction

    function automatic logic [7:0] image_overlay_char(input int tr, input int tc);
        begin
            image_overlay_char = 8'd32;

            
            if (tr == 0) begin
                unique case (tc)
                    0:image_overlay_char=8'd73;1:image_overlay_char=8'd80;2:image_overlay_char=8'd85;4:image_overlay_char=8'd77;5:image_overlay_char=8'd79;6:image_overlay_char=8'd68;7:image_overlay_char=8'd69;9:image_overlay_char=8'd45;11:image_overlay_char=8'd69;12:image_overlay_char=8'd86;13:image_overlay_char=8'd80;14:image_overlay_char=8'd73;15:image_overlay_char=8'd88;16:image_overlay_char=8'd45;17:image_overlay_char=8'd82;18:image_overlay_char=8'd86;19:image_overlay_char=8'd51;20:image_overlay_char=8'd50;
                    default: ;
                endcase
            end
            
            else if (tr == 1) begin
                unique case (tc)
                    0:image_overlay_char=8'd73;1:image_overlay_char=8'd78;2:image_overlay_char=8'd83;3:image_overlay_char=8'd84;4:image_overlay_char=8'd82;5:image_overlay_char=8'd58;
                    7,8,9,10,11,12: image_overlay_char = ipu_valid ? program_name_char(ipu_program_id, tc-7) : ((tc==7)?8'd78:((tc==8)?8'd79:((tc==9)?8'd78:((tc==10)?8'd69:8'd32)))); 
                    20:image_overlay_char=8'd70;21:image_overlay_char=8'd80;22:image_overlay_char=8'd83;23:image_overlay_char=8'd58;
                    25:image_overlay_char=dec3_char(fps_estimate,0);26:image_overlay_char=dec3_char(fps_estimate,1);27:image_overlay_char=dec3_char(fps_estimate,2);
                    default: ;
                endcase
            end
            
            else if (tr == 2) begin
                unique case (tc)
                    0:image_overlay_char=8'd70;1:image_overlay_char=8'd82;2:image_overlay_char=8'd65;3:image_overlay_char=8'd77;4:image_overlay_char=8'd69;5:image_overlay_char=8'd58;
                    7,8,9,10,11,12,13,14: image_overlay_char=short_hex_char(frame_count,tc-7);
                    17:image_overlay_char=8'd68;18:image_overlay_char=8'd82;19:image_overlay_char=8'd79;20:image_overlay_char=8'd80;21:image_overlay_char=8'd58;
                    23,24,25,26,27,28,29,30: image_overlay_char=short_hex_char(dropped_frame_count,tc-23);
                    33:image_overlay_char=8'd69;34:image_overlay_char=8'd82;35:image_overlay_char=8'd82;36:image_overlay_char=8'd58;
                    38,39,40,41,42,43,44,45: image_overlay_char=short_hex_char(spi_error_count,tc-38);
                    default: ;
                endcase
            end
            
            else if (tr == 3) begin
                unique case (tc)
                    0:image_overlay_char=8'd80;1:image_overlay_char=8'd82;2:image_overlay_char=8'd79;3:image_overlay_char=8'd67;4:image_overlay_char=8'd95;5:image_overlay_char=8'd67;6:image_overlay_char=8'd89;7:image_overlay_char=8'd67;8:image_overlay_char=8'd58;
                    10,11,12,13,14,15,16,17: image_overlay_char=short_hex_char(last_process_cycles,tc-10);
                    20:image_overlay_char=8'd82;21:image_overlay_char=8'd69;22:image_overlay_char=8'd83;23:image_overlay_char=8'd58;
                    25,26,27,28,29,30,31,32: image_overlay_char=short_hex_char(debug_ipu_result,tc-25);
                    default: ;
                endcase
            end
            
            else if (tr == 4) begin
                unique case (tc)
                    0:image_overlay_char=8'd66;1:image_overlay_char=8'd85;2:image_overlay_char=8'd83;3:image_overlay_char=8'd89;4:image_overlay_char=8'd58;
                    6,7,8,9,10,11,12,13: image_overlay_char=short_hex_char(perf_ipu_busy_count,tc-6);
                    16:image_overlay_char=8'd67;17:image_overlay_char=8'd79;18:image_overlay_char=8'd78;19:image_overlay_char=8'd86;20:image_overlay_char=8'd58;
                    22,23,24,25,26,27,28,29: image_overlay_char=short_hex_char(perf_conv_count,tc-22);
                    32:image_overlay_char=8'd83;33:image_overlay_char=8'd84;34:image_overlay_char=8'd65;35:image_overlay_char=8'd76;36:image_overlay_char=8'd76;37:image_overlay_char=8'd58;
                    39,40,41,42,43,44,45,46: image_overlay_char=short_hex_char(perf_stall_count,tc-39);
                    default: ;
                endcase
            end
        end
    endfunction

    function automatic logic [7:0] cpu_welcome_char(input int tr, input int tc);
        logic [319:0] line;
        begin
            
            
            line = "                                        ";
            unique case (tr)
                2:  line = "EVPIX-RV32 VISION SOC                 ";
                4:  line = "RV32I 5-STAGE CPU + IMAGE IPU         ";
                6:  line = "CORE CLK:100MHZ   VGA:640X480@60HZ    ";
                8:  line = "CAMERA:OV7670  DIRECT FPGA  128X128   ";
                10: line = "INPUT:RGB565   MEMORY:RGB888 SOURCE   ";
                12: line = "SW0 IPU MODE   SW1-4 SELECT PROGRAM   ";
                14: line = "SW1 SOBEL  SW2 GRAY  SW3 THRESHOLD    ";
                16: line = "SW4 CONV   SW6 RV32I BASELINE BIST     ";
                18: line = "PERF: FPS  FRAME  PROC_CYC  BUSY STALL";
                20: line = "IPU: GRAY THRESH SOBEL CONV POOL       ";
                22: line = "DISPLAY: DOUBLE BUFFERED CLEAN VGA     ";
                25: line = "READY. SELECT A SWITCH MODE TO START.  ";
                default: line = "                                        ";
            endcase

            if (tr == 24) begin
                
                unique case (tc)
                    0:  cpu_welcome_char = 8'd70;  
                    1:  cpu_welcome_char = 8'd80;  
                    2:  cpu_welcome_char = 8'd83;  
                    3:  cpu_welcome_char = 8'd58;  
                    5:  cpu_welcome_char = dec3_char(fps_estimate,0);
                    6:  cpu_welcome_char = dec3_char(fps_estimate,1);
                    7:  cpu_welcome_char = dec3_char(fps_estimate,2);
                    10: cpu_welcome_char = 8'd70;  
                    11: cpu_welcome_char = 8'd82;  
                    12: cpu_welcome_char = 8'd65;  
                    13: cpu_welcome_char = 8'd77;  
                    14: cpu_welcome_char = 8'd69;  
                    15: cpu_welcome_char = 8'd58;  
                    17,18,19,20,21,22,23,24: cpu_welcome_char = short_hex_char(frame_count, tc-17);
                    27: cpu_welcome_char = 8'd67;  
                    28: cpu_welcome_char = 8'd76;  
                    29: cpu_welcome_char = 8'd75;  
                    30: cpu_welcome_char = 8'd58;  
                    31: cpu_welcome_char = 8'd49;  
                    32: cpu_welcome_char = 8'd48;  
                    33: cpu_welcome_char = 8'd48;  
                    34: cpu_welcome_char = 8'd77;  
                    35: cpu_welcome_char = 8'd72;  
                    36: cpu_welcome_char = 8'd90;  
                    default: cpu_welcome_char = 8'd32;
                endcase
            end else if ((tc >= 0) && (tc < 40)) begin
                cpu_welcome_char = line[8*(39-tc) +: 8];
            end else begin
                cpu_welcome_char = 8'd32;
            end
        end
    endfunction

    function automatic logic [7:0] bist_line_char(input int item, input int tc);
        int r; int m; logic [31:0] exp32; logic [31:0] got32; logic [7:0] exp8; logic [7:0] got8; logic is_pass;
        begin
            bist_line_char = 8'd32;
            if (item < 31) begin
                r = item + 1; exp32 = expected_reg(r); got32 = bist_reg_got[r]; is_pass = (got32 == exp32);
                if (tc>=0 && tc<5) bist_line_char=instr_name_char(item,tc);
                else if (tc==5) bist_line_char=8'd88; else if (tc==6) bist_line_char=dec2_char(r,0); else if (tc==7) bist_line_char=dec2_char(r,1);
                else if (tc==9) bist_line_char=8'd69; else if (tc==10) bist_line_char=8'd88; else if (tc==11) bist_line_char=8'd80;
                else if (tc>=13 && tc<21) bist_line_char=hex_char(hex_nibble(exp32,tc-13));
                else if (tc==23) bist_line_char=8'd71; else if (tc==24) bist_line_char=8'd79; else if (tc==25) bist_line_char=8'd84;
                else if (tc>=27 && tc<35) bist_line_char=hex_char(hex_nibble(got32,tc-27));
                else if (tc==37) bist_line_char=is_pass?8'd80:8'd70;
                else if (tc==38) bist_line_char=is_pass?8'd65:8'd65;
                else if (tc==39) bist_line_char=is_pass?8'd83:8'd73;
                else if (tc==40) bist_line_char=is_pass?8'd83:8'd76;
            end else if (item < 42) begin
                m = item - 31; exp8 = expected_mem(m); got8 = bist_mem_got[m]; is_pass = (got8 == exp8);
                if (tc>=0 && tc<3) bist_line_char=instr_name_char(item,tc);
                else if (tc>=4 && tc<7) bist_line_char=dec3_char(mem_addr_for_test(m), tc-4);
                else if (tc==9) bist_line_char=8'd69; else if (tc==10) bist_line_char=8'd88; else if (tc==11) bist_line_char=8'd80;
                else if (tc==17) bist_line_char=hex_char(exp8[7:4]); else if (tc==18) bist_line_char=hex_char(exp8[3:0]);
                else if (tc==23) bist_line_char=8'd71; else if (tc==24) bist_line_char=8'd79; else if (tc==25) bist_line_char=8'd84;
                else if (tc==31) bist_line_char=hex_char(got8[7:4]); else if (tc==32) bist_line_char=hex_char(got8[3:0]);
                else if (tc==37) bist_line_char=is_pass?8'd80:8'd70;
                else if (tc==38) bist_line_char=is_pass?8'd65:8'd65;
                else if (tc==39) bist_line_char=is_pass?8'd83:8'd73;
                else if (tc==40) bist_line_char=is_pass?8'd83:8'd76;
            end
        end
    endfunction

    function automatic logic [7:0] bist_char(input int tr, input int tc);
        int item; int local_row;
        begin
            bist_char = 8'd32;
            if (tr == 2) begin
                unique case (tc)
                    0:bist_char=8'd67;1:bist_char=8'd80;2:bist_char=8'd85;4:bist_char=8'd66;5:bist_char=8'd73;6:bist_char=8'd83;7:bist_char=8'd84;9:bist_char=8'd77;10:bist_char=8'd79;11:bist_char=8'd68;12:bist_char=8'd69;14:bist_char=8'd45;16:bist_char=8'd82;17:bist_char=8'd86;18:bist_char=8'd51;19:bist_char=8'd50;20:bist_char=8'd73;22:bist_char=8'd66;23:bist_char=8'd65;24:bist_char=8'd83;25:bist_char=8'd69;26:bist_char=8'd76;27:bist_char=8'd73;28:bist_char=8'd78;29:bist_char=8'd69;
                    default: ;
                endcase
            end else if (tr == 4) begin
                if (!bist_done) begin
                    unique case (tc)
                        0:bist_char=8'd82;1:bist_char=8'd85;2:bist_char=8'd78;3:bist_char=8'd78;4:bist_char=8'd73;5:bist_char=8'd78;6:bist_char=8'd71;8:bist_char=8'd46;9:bist_char=8'd46;10:bist_char=8'd46;
                        default: ;
                    endcase
                end else if (bist_pass) begin
                    unique case (tc)
                        0:bist_char=8'd65;1:bist_char=8'd76;2:bist_char=8'd76;4:bist_char=8'd66;5:bist_char=8'd65;6:bist_char=8'd83;7:bist_char=8'd69;8:bist_char=8'd76;9:bist_char=8'd73;10:bist_char=8'd78;11:bist_char=8'd69;13:bist_char=8'd67;14:bist_char=8'd72;15:bist_char=8'd69;16:bist_char=8'd67;17:bist_char=8'd75;18:bist_char=8'd83;20:bist_char=8'd80;21:bist_char=8'd65;22:bist_char=8'd83;23:bist_char=8'd83;24:bist_char=8'd69;25:bist_char=8'd68;
                        default: ;
                    endcase
                end else begin
                    unique case (tc)
                        0:bist_char=8'd70;1:bist_char=8'd65;2:bist_char=8'd73;3:bist_char=8'd76;5:bist_char=8'd67;6:bist_char=8'd79;7:bist_char=8'd85;8:bist_char=8'd78;9:bist_char=8'd84;11:bist_char=8'd61;13:bist_char=dec2_char(bist_fail_count,0);14:bist_char=dec2_char(bist_fail_count,1);
                        default: ;
                    endcase
                end
            end else if (tr == 6) begin
                unique case (tc)
                    0:bist_char=8'd84;1:bist_char=8'd69;2:bist_char=8'd83;3:bist_char=8'd84;9:bist_char=8'd69;10:bist_char=8'd88;11:bist_char=8'd80;21:bist_char=8'd71;22:bist_char=8'd79;23:bist_char=8'd84;34:bist_char=8'd82;35:bist_char=8'd69;36:bist_char=8'd83;37:bist_char=8'd85;38:bist_char=8'd76;39:bist_char=8'd84;
                    default: ;
                endcase
            end else if (tr >= 8 && tr < 22) begin
                local_row = tr - 8; item = (bist_page * 14) + local_row;
                bist_char = bist_line_char(item, tc);
            end else if (tr == 24) begin
                unique case (tc)
                    0:bist_char=8'd80;1:bist_char=8'd65;2:bist_char=8'd71;3:bist_char=8'd69;5:bist_char=8'd83;6:bist_char=8'd87;7:bist_char=8'd49;8:bist_char=8'd53;9:bist_char=8'd58;10:bist_char=8'd49;11:bist_char=8'd52;13:bist_char=8'd84;14:bist_char=8'd79;16:bist_char=8'd83;17:bist_char=8'd87;18:bist_char=8'd49;19:bist_char=8'd53;20:bist_char=8'd58;21:bist_char=8'd49;22:bist_char=8'd52;24:bist_char=8'd80;25:bist_char=8'd65;26:bist_char=8'd71;27:bist_char=8'd69;
                    default: ;
                endcase
            end
        end
    endfunction

    function automatic logic [4:0] font5x7(input logic [7:0] ch, input logic [2:0] row);
        begin
            font5x7 = 5'b00000;
            unique case (ch)
            8'd32: begin
                unique case (row)
                    3'd0: font5x7 = 5'b00000;
                    3'd1: font5x7 = 5'b00000;
                    3'd2: font5x7 = 5'b00000;
                    3'd3: font5x7 = 5'b00000;
                    3'd4: font5x7 = 5'b00000;
                    3'd5: font5x7 = 5'b00000;
                    3'd6: font5x7 = 5'b00000;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd33: begin
                unique case (row)
                    3'd0: font5x7 = 5'b00100;
                    3'd1: font5x7 = 5'b00100;
                    3'd2: font5x7 = 5'b00100;
                    3'd3: font5x7 = 5'b00100;
                    3'd4: font5x7 = 5'b00100;
                    3'd5: font5x7 = 5'b00000;
                    3'd6: font5x7 = 5'b00100;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd58: begin
                unique case (row)
                    3'd0: font5x7 = 5'b00000;
                    3'd1: font5x7 = 5'b00100;
                    3'd2: font5x7 = 5'b00100;
                    3'd3: font5x7 = 5'b00000;
                    3'd4: font5x7 = 5'b00100;
                    3'd5: font5x7 = 5'b00100;
                    3'd6: font5x7 = 5'b00000;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd45: begin
                unique case (row)
                    3'd0: font5x7 = 5'b00000;
                    3'd1: font5x7 = 5'b00000;
                    3'd2: font5x7 = 5'b00000;
                    3'd3: font5x7 = 5'b11111;
                    3'd4: font5x7 = 5'b00000;
                    3'd5: font5x7 = 5'b00000;
                    3'd6: font5x7 = 5'b00000;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd46: begin
                unique case (row)
                    3'd0: font5x7 = 5'b00000;
                    3'd1: font5x7 = 5'b00000;
                    3'd2: font5x7 = 5'b00000;
                    3'd3: font5x7 = 5'b00000;
                    3'd4: font5x7 = 5'b00000;
                    3'd5: font5x7 = 5'b00110;
                    3'd6: font5x7 = 5'b00110;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd44: begin
                unique case (row)
                    3'd0: font5x7 = 5'b00000;
                    3'd1: font5x7 = 5'b00000;
                    3'd2: font5x7 = 5'b00000;
                    3'd3: font5x7 = 5'b00000;
                    3'd4: font5x7 = 5'b00110;
                    3'd5: font5x7 = 5'b00100;
                    3'd6: font5x7 = 5'b01000;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd47: begin
                unique case (row)
                    3'd0: font5x7 = 5'b00001;
                    3'd1: font5x7 = 5'b00010;
                    3'd2: font5x7 = 5'b00100;
                    3'd3: font5x7 = 5'b01000;
                    3'd4: font5x7 = 5'b10000;
                    3'd5: font5x7 = 5'b00000;
                    3'd6: font5x7 = 5'b00000;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd61: begin
                unique case (row)
                    3'd0: font5x7 = 5'b00000;
                    3'd1: font5x7 = 5'b11111;
                    3'd2: font5x7 = 5'b00000;
                    3'd3: font5x7 = 5'b11111;
                    3'd4: font5x7 = 5'b00000;
                    3'd5: font5x7 = 5'b00000;
                    3'd6: font5x7 = 5'b00000;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd48: begin
                unique case (row)
                    3'd0: font5x7 = 5'b01110;
                    3'd1: font5x7 = 5'b10001;
                    3'd2: font5x7 = 5'b10011;
                    3'd3: font5x7 = 5'b10101;
                    3'd4: font5x7 = 5'b11001;
                    3'd5: font5x7 = 5'b10001;
                    3'd6: font5x7 = 5'b01110;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd49: begin
                unique case (row)
                    3'd0: font5x7 = 5'b00100;
                    3'd1: font5x7 = 5'b01100;
                    3'd2: font5x7 = 5'b00100;
                    3'd3: font5x7 = 5'b00100;
                    3'd4: font5x7 = 5'b00100;
                    3'd5: font5x7 = 5'b00100;
                    3'd6: font5x7 = 5'b01110;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd50: begin
                unique case (row)
                    3'd0: font5x7 = 5'b01110;
                    3'd1: font5x7 = 5'b10001;
                    3'd2: font5x7 = 5'b00001;
                    3'd3: font5x7 = 5'b00010;
                    3'd4: font5x7 = 5'b00100;
                    3'd5: font5x7 = 5'b01000;
                    3'd6: font5x7 = 5'b11111;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd51: begin
                unique case (row)
                    3'd0: font5x7 = 5'b11110;
                    3'd1: font5x7 = 5'b00001;
                    3'd2: font5x7 = 5'b00001;
                    3'd3: font5x7 = 5'b01110;
                    3'd4: font5x7 = 5'b00001;
                    3'd5: font5x7 = 5'b00001;
                    3'd6: font5x7 = 5'b11110;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd52: begin
                unique case (row)
                    3'd0: font5x7 = 5'b00010;
                    3'd1: font5x7 = 5'b00110;
                    3'd2: font5x7 = 5'b01010;
                    3'd3: font5x7 = 5'b10010;
                    3'd4: font5x7 = 5'b11111;
                    3'd5: font5x7 = 5'b00010;
                    3'd6: font5x7 = 5'b00010;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd53: begin
                unique case (row)
                    3'd0: font5x7 = 5'b11111;
                    3'd1: font5x7 = 5'b10000;
                    3'd2: font5x7 = 5'b10000;
                    3'd3: font5x7 = 5'b11110;
                    3'd4: font5x7 = 5'b00001;
                    3'd5: font5x7 = 5'b00001;
                    3'd6: font5x7 = 5'b11110;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd54: begin
                unique case (row)
                    3'd0: font5x7 = 5'b00110;
                    3'd1: font5x7 = 5'b01000;
                    3'd2: font5x7 = 5'b10000;
                    3'd3: font5x7 = 5'b11110;
                    3'd4: font5x7 = 5'b10001;
                    3'd5: font5x7 = 5'b10001;
                    3'd6: font5x7 = 5'b01110;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd55: begin
                unique case (row)
                    3'd0: font5x7 = 5'b11111;
                    3'd1: font5x7 = 5'b00001;
                    3'd2: font5x7 = 5'b00010;
                    3'd3: font5x7 = 5'b00100;
                    3'd4: font5x7 = 5'b01000;
                    3'd5: font5x7 = 5'b01000;
                    3'd6: font5x7 = 5'b01000;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd56: begin
                unique case (row)
                    3'd0: font5x7 = 5'b01110;
                    3'd1: font5x7 = 5'b10001;
                    3'd2: font5x7 = 5'b10001;
                    3'd3: font5x7 = 5'b01110;
                    3'd4: font5x7 = 5'b10001;
                    3'd5: font5x7 = 5'b10001;
                    3'd6: font5x7 = 5'b01110;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd57: begin
                unique case (row)
                    3'd0: font5x7 = 5'b01110;
                    3'd1: font5x7 = 5'b10001;
                    3'd2: font5x7 = 5'b10001;
                    3'd3: font5x7 = 5'b01111;
                    3'd4: font5x7 = 5'b00001;
                    3'd5: font5x7 = 5'b00010;
                    3'd6: font5x7 = 5'b01100;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd65: begin
                unique case (row)
                    3'd0: font5x7 = 5'b01110;
                    3'd1: font5x7 = 5'b10001;
                    3'd2: font5x7 = 5'b10001;
                    3'd3: font5x7 = 5'b11111;
                    3'd4: font5x7 = 5'b10001;
                    3'd5: font5x7 = 5'b10001;
                    3'd6: font5x7 = 5'b10001;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd66: begin
                unique case (row)
                    3'd0: font5x7 = 5'b11110;
                    3'd1: font5x7 = 5'b10001;
                    3'd2: font5x7 = 5'b10001;
                    3'd3: font5x7 = 5'b11110;
                    3'd4: font5x7 = 5'b10001;
                    3'd5: font5x7 = 5'b10001;
                    3'd6: font5x7 = 5'b11110;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd67: begin
                unique case (row)
                    3'd0: font5x7 = 5'b01110;
                    3'd1: font5x7 = 5'b10001;
                    3'd2: font5x7 = 5'b10000;
                    3'd3: font5x7 = 5'b10000;
                    3'd4: font5x7 = 5'b10000;
                    3'd5: font5x7 = 5'b10001;
                    3'd6: font5x7 = 5'b01110;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd68: begin
                unique case (row)
                    3'd0: font5x7 = 5'b11110;
                    3'd1: font5x7 = 5'b10001;
                    3'd2: font5x7 = 5'b10001;
                    3'd3: font5x7 = 5'b10001;
                    3'd4: font5x7 = 5'b10001;
                    3'd5: font5x7 = 5'b10001;
                    3'd6: font5x7 = 5'b11110;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd69: begin
                unique case (row)
                    3'd0: font5x7 = 5'b11111;
                    3'd1: font5x7 = 5'b10000;
                    3'd2: font5x7 = 5'b10000;
                    3'd3: font5x7 = 5'b11110;
                    3'd4: font5x7 = 5'b10000;
                    3'd5: font5x7 = 5'b10000;
                    3'd6: font5x7 = 5'b11111;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd70: begin
                unique case (row)
                    3'd0: font5x7 = 5'b11111;
                    3'd1: font5x7 = 5'b10000;
                    3'd2: font5x7 = 5'b10000;
                    3'd3: font5x7 = 5'b11110;
                    3'd4: font5x7 = 5'b10000;
                    3'd5: font5x7 = 5'b10000;
                    3'd6: font5x7 = 5'b10000;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd71: begin
                unique case (row)
                    3'd0: font5x7 = 5'b01110;
                    3'd1: font5x7 = 5'b10001;
                    3'd2: font5x7 = 5'b10000;
                    3'd3: font5x7 = 5'b10111;
                    3'd4: font5x7 = 5'b10001;
                    3'd5: font5x7 = 5'b10001;
                    3'd6: font5x7 = 5'b01111;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd72: begin
                unique case (row)
                    3'd0: font5x7 = 5'b10001;
                    3'd1: font5x7 = 5'b10001;
                    3'd2: font5x7 = 5'b10001;
                    3'd3: font5x7 = 5'b11111;
                    3'd4: font5x7 = 5'b10001;
                    3'd5: font5x7 = 5'b10001;
                    3'd6: font5x7 = 5'b10001;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd73: begin
                unique case (row)
                    3'd0: font5x7 = 5'b01110;
                    3'd1: font5x7 = 5'b00100;
                    3'd2: font5x7 = 5'b00100;
                    3'd3: font5x7 = 5'b00100;
                    3'd4: font5x7 = 5'b00100;
                    3'd5: font5x7 = 5'b00100;
                    3'd6: font5x7 = 5'b01110;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd74: begin
                unique case (row)
                    3'd0: font5x7 = 5'b00111;
                    3'd1: font5x7 = 5'b00010;
                    3'd2: font5x7 = 5'b00010;
                    3'd3: font5x7 = 5'b00010;
                    3'd4: font5x7 = 5'b10010;
                    3'd5: font5x7 = 5'b10010;
                    3'd6: font5x7 = 5'b01100;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd75: begin
                unique case (row)
                    3'd0: font5x7 = 5'b10001;
                    3'd1: font5x7 = 5'b10010;
                    3'd2: font5x7 = 5'b10100;
                    3'd3: font5x7 = 5'b11000;
                    3'd4: font5x7 = 5'b10100;
                    3'd5: font5x7 = 5'b10010;
                    3'd6: font5x7 = 5'b10001;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd76: begin
                unique case (row)
                    3'd0: font5x7 = 5'b10000;
                    3'd1: font5x7 = 5'b10000;
                    3'd2: font5x7 = 5'b10000;
                    3'd3: font5x7 = 5'b10000;
                    3'd4: font5x7 = 5'b10000;
                    3'd5: font5x7 = 5'b10000;
                    3'd6: font5x7 = 5'b11111;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd77: begin
                unique case (row)
                    3'd0: font5x7 = 5'b10001;
                    3'd1: font5x7 = 5'b11011;
                    3'd2: font5x7 = 5'b10101;
                    3'd3: font5x7 = 5'b10101;
                    3'd4: font5x7 = 5'b10001;
                    3'd5: font5x7 = 5'b10001;
                    3'd6: font5x7 = 5'b10001;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd78: begin
                unique case (row)
                    3'd0: font5x7 = 5'b10001;
                    3'd1: font5x7 = 5'b11001;
                    3'd2: font5x7 = 5'b10101;
                    3'd3: font5x7 = 5'b10011;
                    3'd4: font5x7 = 5'b10001;
                    3'd5: font5x7 = 5'b10001;
                    3'd6: font5x7 = 5'b10001;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd79: begin
                unique case (row)
                    3'd0: font5x7 = 5'b01110;
                    3'd1: font5x7 = 5'b10001;
                    3'd2: font5x7 = 5'b10001;
                    3'd3: font5x7 = 5'b10001;
                    3'd4: font5x7 = 5'b10001;
                    3'd5: font5x7 = 5'b10001;
                    3'd6: font5x7 = 5'b01110;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd80: begin
                unique case (row)
                    3'd0: font5x7 = 5'b11110;
                    3'd1: font5x7 = 5'b10001;
                    3'd2: font5x7 = 5'b10001;
                    3'd3: font5x7 = 5'b11110;
                    3'd4: font5x7 = 5'b10000;
                    3'd5: font5x7 = 5'b10000;
                    3'd6: font5x7 = 5'b10000;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd81: begin
                unique case (row)
                    3'd0: font5x7 = 5'b01110;
                    3'd1: font5x7 = 5'b10001;
                    3'd2: font5x7 = 5'b10001;
                    3'd3: font5x7 = 5'b10001;
                    3'd4: font5x7 = 5'b10101;
                    3'd5: font5x7 = 5'b10010;
                    3'd6: font5x7 = 5'b01101;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd82: begin
                unique case (row)
                    3'd0: font5x7 = 5'b11110;
                    3'd1: font5x7 = 5'b10001;
                    3'd2: font5x7 = 5'b10001;
                    3'd3: font5x7 = 5'b11110;
                    3'd4: font5x7 = 5'b10100;
                    3'd5: font5x7 = 5'b10010;
                    3'd6: font5x7 = 5'b10001;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd83: begin
                unique case (row)
                    3'd0: font5x7 = 5'b01111;
                    3'd1: font5x7 = 5'b10000;
                    3'd2: font5x7 = 5'b10000;
                    3'd3: font5x7 = 5'b01110;
                    3'd4: font5x7 = 5'b00001;
                    3'd5: font5x7 = 5'b00001;
                    3'd6: font5x7 = 5'b11110;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd84: begin
                unique case (row)
                    3'd0: font5x7 = 5'b11111;
                    3'd1: font5x7 = 5'b00100;
                    3'd2: font5x7 = 5'b00100;
                    3'd3: font5x7 = 5'b00100;
                    3'd4: font5x7 = 5'b00100;
                    3'd5: font5x7 = 5'b00100;
                    3'd6: font5x7 = 5'b00100;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd85: begin
                unique case (row)
                    3'd0: font5x7 = 5'b10001;
                    3'd1: font5x7 = 5'b10001;
                    3'd2: font5x7 = 5'b10001;
                    3'd3: font5x7 = 5'b10001;
                    3'd4: font5x7 = 5'b10001;
                    3'd5: font5x7 = 5'b10001;
                    3'd6: font5x7 = 5'b01110;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd86: begin
                unique case (row)
                    3'd0: font5x7 = 5'b10001;
                    3'd1: font5x7 = 5'b10001;
                    3'd2: font5x7 = 5'b10001;
                    3'd3: font5x7 = 5'b10001;
                    3'd4: font5x7 = 5'b10001;
                    3'd5: font5x7 = 5'b01010;
                    3'd6: font5x7 = 5'b00100;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd87: begin
                unique case (row)
                    3'd0: font5x7 = 5'b10001;
                    3'd1: font5x7 = 5'b10001;
                    3'd2: font5x7 = 5'b10001;
                    3'd3: font5x7 = 5'b10101;
                    3'd4: font5x7 = 5'b10101;
                    3'd5: font5x7 = 5'b10101;
                    3'd6: font5x7 = 5'b01010;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd88: begin
                unique case (row)
                    3'd0: font5x7 = 5'b10001;
                    3'd1: font5x7 = 5'b10001;
                    3'd2: font5x7 = 5'b01010;
                    3'd3: font5x7 = 5'b00100;
                    3'd4: font5x7 = 5'b01010;
                    3'd5: font5x7 = 5'b10001;
                    3'd6: font5x7 = 5'b10001;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd89: begin
                unique case (row)
                    3'd0: font5x7 = 5'b10001;
                    3'd1: font5x7 = 5'b10001;
                    3'd2: font5x7 = 5'b01010;
                    3'd3: font5x7 = 5'b00100;
                    3'd4: font5x7 = 5'b00100;
                    3'd5: font5x7 = 5'b00100;
                    3'd6: font5x7 = 5'b00100;
                    default: font5x7 = 5'b00000;
                endcase
            end
            8'd90: begin
                unique case (row)
                    3'd0: font5x7 = 5'b11111;
                    3'd1: font5x7 = 5'b00001;
                    3'd2: font5x7 = 5'b00010;
                    3'd3: font5x7 = 5'b00100;
                    3'd4: font5x7 = 5'b01000;
                    3'd5: font5x7 = 5'b10000;
                    3'd6: font5x7 = 5'b11111;
                    default: font5x7 = 5'b00000;
                endcase
            end
                default: font5x7 = 5'b00000;
            endcase
        end
    endfunction

    logic [6:0] text_col;
    logic [5:0] text_row;
    logic [2:0] font_x;
    logic [2:0] font_y;
    logic [7:0] text_ch;
    logic [4:0] font_bits;
    logic       font_on;
    logic       text_pixel;

    // Combinational logic.

    always_comb begin
        
        text_col = x_q[9:3];
        text_row = y_q[8:3];
        font_x   = x_q[2:0];
        font_y   = y_q[2:0];
        text_ch  = 8'd32;

        if (text_row == 6'd0) begin
            unique case (text_col)
                7'd0: text_ch=8'd70; 7'd1: text_ch=8'd82; 7'd2: text_ch=8'd65;
                7'd3: text_ch=8'd77; 7'd4: text_ch=8'd69; 7'd5: text_ch=8'd58;
                7'd6,7'd7,7'd8,7'd9,7'd10,7'd11,7'd12,7'd13: text_ch=short_hex_char(frame_count,text_col-7'd6);
                default: text_ch=8'd32;
            endcase
        end else if (text_row == 6'd1) begin
            unique case (text_col)
                0:text_ch=8'd80; 1:text_ch=8'd83; 2:text_ch=8'd78; 3:text_ch=8'd82; 4:text_ch=8'd58;
                6:text_ch=(psnr_tenths==0)?8'd45:((psnr_tenths==1023)?8'd57:dec3_char(psnr_tenths,0));
                7:text_ch=(psnr_tenths==0)?8'd45:((psnr_tenths==1023)?8'd57:dec3_char(psnr_tenths,1));
                8:text_ch=8'd46;
                9:text_ch=(psnr_tenths==0)?8'd45:((psnr_tenths==1023)?8'd57:dec3_char(psnr_tenths,2));
                11:text_ch=8'd68; 12:text_ch=8'd66;
                default:text_ch=8'd32;
            endcase
        end else if (text_row == 6'd2) begin
            unique case (text_col)
                0:text_ch=8'd77; 1:text_ch=8'd83; 2:text_ch=8'd69; 3:text_ch=8'd58;
                6,7,8,9,10,11,12,13:text_ch=short_hex_char(mse_value,text_col-7'd6);
                default:text_ch=8'd32;
            endcase
        end else if (text_row == 6'd3) begin
            
            unique case (text_col)
                0:text_ch=8'd73; 1:text_ch=8'd69; 2:text_ch=8'd58;
                4:text_ch=metric_valid ? decimal_digit({16'd0,metric_entropy_x100},2) : 8'd45;
                5:text_ch=8'd46;
                6:text_ch=metric_valid ? decimal_digit({16'd0,metric_entropy_x100},1) : 8'd45;
                7:text_ch=metric_valid ? decimal_digit({16'd0,metric_entropy_x100},0) : 8'd45;
                9:text_ch=8'd66; 10:text_ch=8'd73; 11:text_ch=8'd84; 12:text_ch=8'd83;
                default:text_ch=8'd32;
            endcase
        end else if (text_row == 6'd4 || text_row == 6'd5) begin
            
            unique case (text_col)
                0:text_ch=(text_row==4)?8'd65:8'd82;
                1:text_ch=(text_row==4)?8'd71:8'd77;
                2:text_ch=(text_row==4)?8'd58:8'd83;
                4:text_ch=metric_valid ? decimal_digit((text_row==4)?{16'd0,metric_ag_x100}:{16'd0,metric_rms_x100},4) : 8'd45;
                5:text_ch=metric_valid ? decimal_digit((text_row==4)?{16'd0,metric_ag_x100}:{16'd0,metric_rms_x100},3) : 8'd45;
                6:text_ch=metric_valid ? decimal_digit((text_row==4)?{16'd0,metric_ag_x100}:{16'd0,metric_rms_x100},2) : 8'd45;
                7:text_ch=8'd46;
                8:text_ch=metric_valid ? decimal_digit((text_row==4)?{16'd0,metric_ag_x100}:{16'd0,metric_rms_x100},1) : 8'd45;
                9:text_ch=metric_valid ? decimal_digit((text_row==4)?{16'd0,metric_ag_x100}:{16'd0,metric_rms_x100},0) : 8'd45;
                default:text_ch=8'd32;
            endcase
        end else if (text_row == 6'd6 || text_row == 6'd7) begin
            
            unique case (text_col)
                0:text_ch=(text_row==6)?8'd84:8'd77;
                1:text_ch=(text_row==6)?8'd73:8'd80;
                2:text_ch=(text_row==6)?8'd77:8'd47;
                3:text_ch=(text_row==6)?8'd69:8'd83;
                4:text_ch=8'd58;
                6:text_ch=decimal_digit((text_row==6)?metric_time_centi_ms:metric_throughput_centi,4);
                7:text_ch=decimal_digit((text_row==6)?metric_time_centi_ms:metric_throughput_centi,3);
                8:text_ch=decimal_digit((text_row==6)?metric_time_centi_ms:metric_throughput_centi,2);
                9:text_ch=8'd46;
                10:text_ch=decimal_digit((text_row==6)?metric_time_centi_ms:metric_throughput_centi,1);
                11:text_ch=decimal_digit((text_row==6)?metric_time_centi_ms:metric_throughput_centi,0);
                13:text_ch=(text_row==6)?8'd77:8'd77;
                14:text_ch=(text_row==6)?8'd83:8'd80;
                15:text_ch=(text_row==6)?8'd32:8'd47;
                16:text_ch=(text_row==6)?8'd32:8'd83;
                default:text_ch=8'd32;
            endcase
        end else if (text_row == 6'd8) begin
            
            unique case (text_col)
                0:text_ch=8'd70; 1:text_ch=8'd80; 2:text_ch=8'd83; 3:text_ch=8'd58;
                5:text_ch=decimal_digit(metric_fps_tenths,3);
                6:text_ch=decimal_digit(metric_fps_tenths,2);
                7:text_ch=decimal_digit(metric_fps_tenths,1);
                8:text_ch=8'd46;
                9:text_ch=decimal_digit(metric_fps_tenths,0);
                11:text_ch=8'd70; 12:text_ch=8'd80; 13:text_ch=8'd83;
                default:text_ch=8'd32;
            endcase
        end

        font_bits = font5x7(text_ch, font_y);

        unique case (font_x)
            3'd0: font_on = font_bits[4];
            3'd1: font_on = font_bits[3];
            3'd2: font_on = font_bits[2];
            3'd3: font_on = font_bits[1];
            3'd4: font_on = font_bits[0];
            default: font_on = 1'b0;
        endcase

        text_pixel = active_q && font_on && (text_row <= 6'd8);
    end

    logic [3:0] vga_r_next, vga_g_next, vga_b_next;

    // Combinational logic.

    always_comb begin
        vga_r_next = 4'h0;
        vga_g_next = 4'h0;
        vga_b_next = 4'h0;

        if (overlay_mode_q != 2'd0) begin
            
            
            if (active_q) begin
                vga_r_next = 4'h0;
                vga_g_next = 4'h0;
                vga_b_next = (overlay_mode_q == 2'd1) ? 4'h0 : 4'h2;
            end

            if (text_pixel) begin
                if (overlay_mode_q == 2'd2 && bist_done && !bist_pass) begin
                    vga_r_next = 4'hF; vga_g_next = 4'h3; vga_b_next = 4'h3;
                end else if (overlay_mode_q == 2'd2 && bist_done && bist_pass) begin
                    vga_r_next = 4'h3; vga_g_next = 4'hF; vga_b_next = 4'h3;
                end else begin
                    vga_r_next = 4'hF; vga_g_next = 4'hF; vga_b_next = 4'hF;
                end
            end
        end else begin
            
            if (active_q &&
                (x_q >= LEFT_X + IMG_W + (GAP/2) - 1) &&
                (x_q <= LEFT_X + IMG_W + (GAP/2) + 1) &&
                (y_q >= TOP_Y) && (y_q < TOP_Y + IMG_H)) begin
                vga_r_next = 4'hF; vga_g_next = 4'hF; vga_b_next = 4'hF;
            end

            if (in_left_q) begin
                vga_r_next = src_q[11:8];
                vga_g_next = src_q[7:4];
                vga_b_next = src_q[3:0];
            end else if (in_right_q) begin
                if (right_bypass_src_q) begin
                    vga_r_next = src_q[11:8];
                    vga_g_next = src_q[7:4];
                    vga_b_next = src_q[3:0];
                end else begin
                    vga_r_next = dst_q[11:8];
                    vga_g_next = dst_q[7:4];
                    vga_b_next = dst_q[3:0];
                end
            end

            
            if (text_pixel) begin
                vga_r_next = 4'h0;
                vga_g_next = 4'hF;
                vga_b_next = 4'h0;
            end
        end
    end

    // Clocked logic.

    always_ff @(posedge clk_pix or posedge reset) begin
        if (reset) begin
            vga_r <= 4'h0;
            vga_g <= 4'h0;
            vga_b <= 4'h0;
        end else begin
            vga_r <= vga_r_next;
            vga_g <= vga_g_next;
            vga_b <= vga_b_next;
        end
    end

endmodule
