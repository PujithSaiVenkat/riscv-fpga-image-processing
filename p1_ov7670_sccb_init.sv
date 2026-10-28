// p1_ov7670_sccb_init: main hardware logic.
module p1_ov7670_sccb_init #(
    parameter int CLK_HZ  = 100_000_000,
    parameter int SCCB_HZ = 100_000
) (
    input  logic clk,
    input  logic reset,
    input  logic colorbar_enable,

    output logic ov_sioc,
    inout  wire  ov_siod,

    output logic init_done,
    output logic init_busy,
    output logic init_error
);

    localparam int QTR_CYCLES = (CLK_HZ / (SCCB_HZ * 4));
    localparam int QTR_W      = (QTR_CYCLES <= 2) ? 2 : $clog2(QTR_CYCLES + 1);
    localparam int PWR_DELAY_CYCLES = CLK_HZ / 20; 
    localparam int PWR_W = $clog2(PWR_DELAY_CYCLES + 1);

    function automatic logic [15:0] cfg_word(input int idx);
        begin
            unique case (idx)
                
                0:  cfg_word = 16'h1280; 
                1:  cfg_word = 16'h1101; 
                2:  cfg_word = 16'h3A04; 
                3:  cfg_word = 16'h1200; 

                
                4:  cfg_word = 16'h1713; 
                5:  cfg_word = 16'h1801; 
                6:  cfg_word = 16'h32B6; 
                7:  cfg_word = 16'h1902; 
                8:  cfg_word = 16'h1A7A; 
                9:  cfg_word = 16'h030A; 
                10: cfg_word = 16'h0C00; 
                11: cfg_word = 16'h3E00; 
                12: cfg_word = 16'h1500; 

                13: cfg_word = 16'h7A20;
                14: cfg_word = 16'h7B10;
                15: cfg_word = 16'h7C1E;
                16: cfg_word = 16'h7D35;
                17: cfg_word = 16'h7E5A;
                18: cfg_word = 16'h7F69;
                19: cfg_word = 16'h8076;
                20: cfg_word = 16'h8180;
                21: cfg_word = 16'h8288;
                22: cfg_word = 16'h838F;
                23: cfg_word = 16'h8496;
                24: cfg_word = 16'h85A3;
                25: cfg_word = 16'h86AF;
                26: cfg_word = 16'h87C4;
                27: cfg_word = 16'h88D7;
                28: cfg_word = 16'h89E8;

                29: cfg_word = 16'h13E0; 
                30: cfg_word = 16'h0000; 
                31: cfg_word = 16'h1000; 
                32: cfg_word = 16'h0D40; 
                33: cfg_word = 16'h1418; 
                34: cfg_word = 16'hA505;
                35: cfg_word = 16'hAB07;
                36: cfg_word = 16'h2495;
                37: cfg_word = 16'h2533;
                38: cfg_word = 16'h26E3;
                39: cfg_word = 16'h9F78;
                40: cfg_word = 16'hA068;
                41: cfg_word = 16'hA103;
                42: cfg_word = 16'hA6D8;
                43: cfg_word = 16'hA7D8;
                44: cfg_word = 16'hA8F0;
                45: cfg_word = 16'hA990;
                46: cfg_word = 16'hAA94;
                47: cfg_word = 16'h13E5; 

                
                48: cfg_word = 16'h0E61;
                49: cfg_word = 16'h0F4B;
                50: cfg_word = 16'h1602;
                51: cfg_word = 16'h1E07; 
                52: cfg_word = 16'h2102;
                53: cfg_word = 16'h2291;
                54: cfg_word = 16'h2907;
                55: cfg_word = 16'h330B;
                56: cfg_word = 16'h350B;
                57: cfg_word = 16'h371D;
                58: cfg_word = 16'h3871;
                59: cfg_word = 16'h392A;
                60: cfg_word = 16'h3C78;
                61: cfg_word = 16'h4D40;
                62: cfg_word = 16'h4E20;
                63: cfg_word = 16'h6900;
                64: cfg_word = 16'h6B4A;
                65: cfg_word = 16'h7410;
                66: cfg_word = 16'h8D4F;
                67: cfg_word = 16'h8E00;
                68: cfg_word = 16'h8F00;
                69: cfg_word = 16'h9000;
                70: cfg_word = 16'h9100;
                71: cfg_word = 16'h9600;
                72: cfg_word = 16'h9A00;
                73: cfg_word = 16'hB084;
                74: cfg_word = 16'hB10C;
                75: cfg_word = 16'hB20E;
                76: cfg_word = 16'hB382;
                77: cfg_word = 16'hB80A;

                
                78: cfg_word = 16'h430A;
                79: cfg_word = 16'h44F0;
                80: cfg_word = 16'h4534;
                81: cfg_word = 16'h4658;
                82: cfg_word = 16'h4728;
                83: cfg_word = 16'h483A;
                84: cfg_word = 16'h5988;
                85: cfg_word = 16'h5A88;
                86: cfg_word = 16'h5B44;
                87: cfg_word = 16'h5C67;
                88: cfg_word = 16'h5D49;
                89: cfg_word = 16'h5E0E;
                90: cfg_word = 16'h6C0A;
                91: cfg_word = 16'h6D55;
                92: cfg_word = 16'h6E11;
                93: cfg_word = 16'h6F9F;
                94: cfg_word = 16'h6A40;
                95: cfg_word = 16'h0140; 
                96: cfg_word = 16'h0260; 
                97: cfg_word = 16'h13E7; 

                
                98:  cfg_word = 16'h1204; 
                99:  cfg_word = 16'h8C00; 
                100: cfg_word = 16'h0400; 
                101: cfg_word = 16'h4010; 
                102: cfg_word = 16'h1438; 
                103: cfg_word = 16'h4FB3; 
                104: cfg_word = 16'h50B3; 
                105: cfg_word = 16'h5100;
                106: cfg_word = 16'h523D;
                107: cfg_word = 16'h53A7;
                108: cfg_word = 16'h54E4;
                109: cfg_word = 16'h589E; 
                110: cfg_word = 16'h3DC0; 
                111: cfg_word = 16'h4108; 
                112: cfg_word = 16'h3F00; 
                113: cfg_word = 16'h5640; 

                
                114: cfg_word = {8'h42, colorbar_enable ? 8'h08 : 8'h00};

                115: cfg_word = 16'hFFFF;
                default: cfg_word = 16'hFFFF;
            endcase
        end
    endfunction

    typedef enum logic [3:0] {
        ST_POWERUP,
        ST_LOAD,
        ST_START_1,
        ST_START_2,
        ST_BIT_LOW,
        ST_BIT_HIGH,
        ST_ACK_LOW,
        ST_ACK_HIGH,
        ST_STOP_1,
        ST_STOP_2,
        ST_STOP_3,
        ST_NEXT,
        ST_DONE
    } state_t;

    state_t state;
    logic [PWR_W-1:0] pwr_cnt;
    logic [QTR_W-1:0] qtr_cnt;
    logic             tick;

    logic [7:0] dev_addr, reg_addr, reg_data, tx_byte;
    logic [7:0] bit_idx;
    logic [1:0] byte_idx;
    int         cfg_idx;
    logic [15:0] word_now;
    logic        siod_drive_low;

    assign ov_siod = siod_drive_low ? 1'b0 : 1'bz;

    // Combinational logic.

    always_comb begin
        tick = (qtr_cnt == QTR_CYCLES[QTR_W-1:0] - 1'b1);
    end

    // Clocked logic.

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            qtr_cnt <= '0;
        end else if (state == ST_POWERUP || state == ST_DONE) begin
            qtr_cnt <= '0;
        end else begin
            if (tick)
                qtr_cnt <= '0;
            else
                qtr_cnt <= qtr_cnt + {{(QTR_W-1){1'b0}}, 1'b1};
        end
    end

    // Clocked logic.

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state          <= ST_POWERUP;
            pwr_cnt        <= '0;
            cfg_idx        <= 0;
            byte_idx       <= 2'd0;
            bit_idx        <= 8'd7;
            dev_addr       <= 8'h42;
            reg_addr       <= 8'd0;
            reg_data       <= 8'd0;
            tx_byte        <= 8'h42;
            ov_sioc        <= 1'b1;
            siod_drive_low <= 1'b0;
            init_done      <= 1'b0;
            init_busy      <= 1'b1;
            init_error     <= 1'b0;
        end else begin
            init_busy <= !init_done;

            unique case (state)
                ST_POWERUP: begin
                    ov_sioc        <= 1'b1;
                    siod_drive_low <= 1'b0;
                    if (pwr_cnt == PWR_DELAY_CYCLES[PWR_W-1:0] - 1'b1) begin
                        pwr_cnt <= '0;
                        state   <= ST_LOAD;
                    end else begin
                        pwr_cnt <= pwr_cnt + {{(PWR_W-1){1'b0}}, 1'b1};
                    end
                end

                ST_LOAD: begin
                    word_now = cfg_word(cfg_idx);
                    if (word_now == 16'hFFFF) begin
                        state <= ST_DONE;
                    end else begin
                        dev_addr <= 8'h42;
                        reg_addr <= word_now[15:8];
                        reg_data <= word_now[7:0];
                        tx_byte  <= 8'h42;
                        byte_idx <= 2'd0;
                        bit_idx  <= 8'd7;
                        state    <= ST_START_1;
                    end
                end

                ST_START_1: if (tick) begin
                    ov_sioc        <= 1'b1;
                    siod_drive_low <= 1'b0;
                    state          <= ST_START_2;
                end

                ST_START_2: if (tick) begin
                    ov_sioc        <= 1'b1;
                    siod_drive_low <= 1'b1; 
                    state          <= ST_BIT_LOW;
                end

                ST_BIT_LOW: if (tick) begin
                    ov_sioc        <= 1'b0;
                    siod_drive_low <= ~tx_byte[bit_idx[2:0]];
                    state          <= ST_BIT_HIGH;
                end

                ST_BIT_HIGH: if (tick) begin
                    ov_sioc <= 1'b1;
                    if (bit_idx == 0) begin
                        state <= ST_ACK_LOW;
                    end else begin
                        bit_idx <= bit_idx - 8'd1;
                        state   <= ST_BIT_LOW;
                    end
                end

                ST_ACK_LOW: if (tick) begin
                    ov_sioc        <= 1'b0;
                    siod_drive_low <= 1'b0; 
                    state          <= ST_ACK_HIGH;
                end

                ST_ACK_HIGH: if (tick) begin
                    ov_sioc <= 1'b1;

                    if (ov_siod)
                        init_error <= 1'b1;

                    if (byte_idx == 2'd0) begin
                        byte_idx <= 2'd1;
                        tx_byte  <= reg_addr;
                        bit_idx  <= 8'd7;
                        state    <= ST_BIT_LOW;
                    end else if (byte_idx == 2'd1) begin
                        byte_idx <= 2'd2;
                        tx_byte  <= reg_data;
                        bit_idx  <= 8'd7;
                        state    <= ST_BIT_LOW;
                    end else begin
                        state <= ST_STOP_1;
                    end
                end

                ST_STOP_1: if (tick) begin
                    ov_sioc        <= 1'b0;
                    siod_drive_low <= 1'b1;
                    state          <= ST_STOP_2;
                end

                ST_STOP_2: if (tick) begin
                    ov_sioc        <= 1'b1;
                    siod_drive_low <= 1'b1;
                    state          <= ST_STOP_3;
                end

                ST_STOP_3: if (tick) begin
                    ov_sioc        <= 1'b1;
                    siod_drive_low <= 1'b0; 
                    state          <= ST_NEXT;
                end

                ST_NEXT: if (tick) begin
                    cfg_idx <= cfg_idx + 1;
                    
                    if (cfg_idx == 0)
                        state <= ST_POWERUP;
                    else
                        state <= ST_LOAD;
                end

                ST_DONE: begin
                    ov_sioc        <= 1'b1;
                    siod_drive_low <= 1'b0;
                    init_done      <= 1'b1;
                    init_busy      <= 1'b0;
                end

                default: state <= ST_POWERUP;
            endcase
        end
    end

endmodule
