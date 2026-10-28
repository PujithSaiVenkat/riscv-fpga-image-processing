// p1_evpix_byte_ram_dp: main hardware logic.
module p1_evpix_byte_ram_dp #(
    parameter integer ADDR_WIDTH = 14,
    parameter integer DEPTH      = 16384
)(
    input  wire                  clk,

    
    
    
    

    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [7:0]            wr_data,

    
    
    
    

    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output wire [7:0]            rd_data
);


    
    
    
    
    
    
    
    
    
    
    
    
    
    

    altsyncram ram_inst (

        
        
        

        .clock0    (clk),

        
        
        

        .wren_a    (wr_en),
        .address_a (wr_addr),
        .data_a    (wr_data),

        
        
        

        .address_b (rd_addr),
        .q_b       (rd_data),

        
        
        
        
        
        

        .wren_b        (1'b0),
        .data_b        (8'b0),

        .rden_a        (1'b0),
        .rden_b        (1'b1),

        .clocken0      (1'b1),
        .clocken1      (1'b1),
        .clocken2      (1'b1),
        .clocken3      (1'b1),

        .aclr0         (1'b0),
        .aclr1         (1'b0)

    );


    
    
    

    defparam

        
        
        

        ram_inst.lpm_type =
            "altsyncram",

        ram_inst.operation_mode =
            "DUAL_PORT",

        ram_inst.intended_device_family =
            "Cyclone IV E",

        ram_inst.ram_block_type =
            "M9K",


        
        
        

        ram_inst.width_a =
            8,

        ram_inst.widthad_a =
            ADDR_WIDTH,

        ram_inst.numwords_a =
            DEPTH,


        
        
        

        ram_inst.width_b =
            8,

        ram_inst.widthad_b =
            ADDR_WIDTH,

        ram_inst.numwords_b =
            DEPTH,


        
        
        
        
        
        

        ram_inst.address_reg_b =
            "CLOCK0",


        
        
        

        ram_inst.rdcontrol_reg_b =
            "CLOCK0",


        
        
        

        ram_inst.outdata_reg_b =
            "UNREGISTERED",


        
        
        
        
        

        ram_inst.outdata_aclr_b =
            "NONE",


        
        
        

        ram_inst.clock_enable_input_a =
            "BYPASS",

        ram_inst.clock_enable_input_b =
            "BYPASS",

        ram_inst.clock_enable_output_a =
            "BYPASS",

        ram_inst.clock_enable_output_b =
            "BYPASS",


        
        
        

        ram_inst.power_up_uninitialized =
            "FALSE",


        
        
        
        
        
        

        ram_inst.read_during_write_mode_mixed_ports =
            "DONT_CARE",


        
        
        

        ram_inst.width_byteena_a =
            1;

endmodule







module p1_data_memory_fpga #(
    parameter int MEM_BYTES = 65536
) (

    input  logic        clk,
    input  logic        reset,

    
    
    

    input  logic        mem_write,
    input  logic        mem_read,

    input  logic [2:0]  funct3,

    input  logic [31:0] addr,
    input  logic [31:0] write_data,

    output logic [31:0] read_data,


    
    
    

    input  logic        ipu_mem_re,
    input  logic        ipu_mem_we,

    input  logic [31:0] ipu_addr,
    input  logic [7:0]  ipu_write_data,

    output logic [7:0]  ipu_read_data,


    
    
    

    input  logic        host_we,
    input  logic [31:0] host_addr,
    input  logic [7:0]  host_wdata,


    
    
    

    output logic [31:0] mmio_status,
    output logic        mmio_valid

);


    
    
    

    localparam int WORDS =
        MEM_BYTES / 4;

    localparam logic [31:0] MMIO_STATUS_ADDR =
        32'h0000_FF00;

    localparam int CPU_FAST_BYTES =
        288;


    
    
    

    function automatic logic in_byte_range(
        input logic [31:0] a
    );

        in_byte_range =
            (a < MEM_BYTES);

    endfunction


    function automatic logic in_word_range(
        input logic [31:0] wa
    );

        in_word_range =
            (wa < WORDS);

    endfunction


    function automatic logic in_cpu_fast_range(
        input logic [31:0] a
    );

        in_cpu_fast_range =
            (a < CPU_FAST_BYTES);

    endfunction


    
    
    
    
    

    logic [7:0] cpu_fast_mem
        [0:CPU_FAST_BYTES-1];


    integer init_i;

    initial begin

        for (
            init_i = 0;
            init_i < CPU_FAST_BYTES;
            init_i = init_i + 1
        ) begin

            cpu_fast_mem[init_i] = 8'd0;

        end

    end


    
    
    

    logic        bram_wr_en;

    logic [31:0] bram_wr_word_addr;

    logic [3:0]  bram_wr_be;

    logic [7:0]  bram_wr_b0;
    logic [7:0]  bram_wr_b1;
    logic [7:0]  bram_wr_b2;
    logic [7:0]  bram_wr_b3;


    
    
    
    
    
    
    
    
    
    
    

    // Combinational logic.


    
    
    
    
    
    
    
    
    
    
    

    always_comb begin

        bram_wr_en =
            1'b0;

        bram_wr_word_addr =
            32'd0;

        bram_wr_be =
            4'b0000;

        bram_wr_b0 =
            8'd0;

        bram_wr_b1 =
            8'd0;

        bram_wr_b2 =
            8'd0;

        bram_wr_b3 =
            8'd0;


        
        
        

        if (
            host_we &&
            in_byte_range(host_addr)
        ) begin

            bram_wr_en =
                1'b1;

            bram_wr_word_addr =
                host_addr[31:2];


            case (host_addr[1:0])

                2'd0: begin

                    bram_wr_be =
                        4'b0001;

                    bram_wr_b0 =
                        host_wdata;

                end


                2'd1: begin

                    bram_wr_be =
                        4'b0010;

                    bram_wr_b1 =
                        host_wdata;

                end


                2'd2: begin

                    bram_wr_be =
                        4'b0100;

                    bram_wr_b2 =
                        host_wdata;

                end


                2'd3: begin

                    bram_wr_be =
                        4'b1000;

                    bram_wr_b3 =
                        host_wdata;

                end


                default: begin

                    bram_wr_be =
                        4'b0000;

                end

            endcase

        end


        
        
        

        else if (
            ipu_mem_we &&
            in_byte_range(ipu_addr)
        ) begin

            bram_wr_en =
                1'b1;

            bram_wr_word_addr =
                ipu_addr[31:2];


            case (ipu_addr[1:0])

                2'd0: begin

                    bram_wr_be =
                        4'b0001;

                    bram_wr_b0 =
                        ipu_write_data;

                end


                2'd1: begin

                    bram_wr_be =
                        4'b0010;

                    bram_wr_b1 =
                        ipu_write_data;

                end


                2'd2: begin

                    bram_wr_be =
                        4'b0100;

                    bram_wr_b2 =
                        ipu_write_data;

                end


                2'd3: begin

                    bram_wr_be =
                        4'b1000;

                    bram_wr_b3 =
                        ipu_write_data;

                end


                default: begin

                    bram_wr_be =
                        4'b0000;

                end

            endcase

        end


        
        
        

        else if (
            mem_write &&
            (addr != MMIO_STATUS_ADDR) &&
            in_byte_range(addr)
        ) begin

            bram_wr_en =
                1'b1;

            bram_wr_word_addr =
                addr[31:2];


            case (funct3)

                
                
                

                3'b000: begin

                    case (addr[1:0])

                        2'd0: begin

                            bram_wr_be =
                                4'b0001;

                            bram_wr_b0 =
                                write_data[7:0];

                        end


                        2'd1: begin

                            bram_wr_be =
                                4'b0010;

                            bram_wr_b1 =
                                write_data[7:0];

                        end


                        2'd2: begin

                            bram_wr_be =
                                4'b0100;

                            bram_wr_b2 =
                                write_data[7:0];

                        end


                        2'd3: begin

                            bram_wr_be =
                                4'b1000;

                            bram_wr_b3 =
                                write_data[7:0];

                        end


                        default: begin

                            bram_wr_en =
                                1'b0;

                        end

                    endcase

                end


                
                
                

                3'b001: begin

                    if (addr[1:0] == 2'd0) begin

                        bram_wr_be =
                            4'b0011;

                        bram_wr_b0 =
                            write_data[7:0];

                        bram_wr_b1 =
                            write_data[15:8];

                    end

                    else if (addr[1:0] == 2'd2) begin

                        bram_wr_be =
                            4'b1100;

                        bram_wr_b2 =
                            write_data[7:0];

                        bram_wr_b3 =
                            write_data[15:8];

                    end

                    else begin

                        bram_wr_en =
                            1'b0;

                    end

                end


                
                
                

                3'b010: begin

                    if (addr[1:0] == 2'd0) begin

                        bram_wr_be =
                            4'b1111;

                        bram_wr_b0 =
                            write_data[7:0];

                        bram_wr_b1 =
                            write_data[15:8];

                        bram_wr_b2 =
                            write_data[23:16];

                        bram_wr_b3 =
                            write_data[31:24];

                    end

                    else begin

                        bram_wr_en =
                            1'b0;

                    end

                end


                default: begin

                    bram_wr_en =
                        1'b0;

                end

            endcase

        end

    end


    
    
    

    wire [7:0] ram0_q;
    wire [7:0] ram1_q;
    wire [7:0] ram2_q;
    wire [7:0] ram3_q;


    
    
    

    p1_evpix_byte_ram_dp #(
        .ADDR_WIDTH(14),
        .DEPTH(16384)
    ) ram_lane0 (

        .clk(clk),

        .wr_en(
            bram_wr_en &&
            bram_wr_be[0]
        ),

        .wr_addr(
            bram_wr_word_addr[13:0]
        ),

        .wr_data(
            bram_wr_b0
        ),

        .rd_addr(
            ipu_addr[15:2]
        ),

        .rd_data(
            ram0_q
        )

    );


    
    
    

    p1_evpix_byte_ram_dp #(
        .ADDR_WIDTH(14),
        .DEPTH(16384)
    ) ram_lane1 (

        .clk(clk),

        .wr_en(
            bram_wr_en &&
            bram_wr_be[1]
        ),

        .wr_addr(
            bram_wr_word_addr[13:0]
        ),

        .wr_data(
            bram_wr_b1
        ),

        .rd_addr(
            ipu_addr[15:2]
        ),

        .rd_data(
            ram1_q
        )

    );


    
    
    

    p1_evpix_byte_ram_dp #(
        .ADDR_WIDTH(14),
        .DEPTH(16384)
    ) ram_lane2 (

        .clk(clk),

        .wr_en(
            bram_wr_en &&
            bram_wr_be[2]
        ),

        .wr_addr(
            bram_wr_word_addr[13:0]
        ),

        .wr_data(
            bram_wr_b2
        ),

        .rd_addr(
            ipu_addr[15:2]
        ),

        .rd_data(
            ram2_q
        )

    );


    
    
    

    p1_evpix_byte_ram_dp #(
        .ADDR_WIDTH(14),
        .DEPTH(16384)
    ) ram_lane3 (

        .clk(clk),

        .wr_en(
            bram_wr_en &&
            bram_wr_be[3]
        ),

        .wr_addr(
            bram_wr_word_addr[13:0]
        ),

        .wr_data(
            bram_wr_b3
        ),

        .rd_addr(
            ipu_addr[15:2]
        ),

        .rd_data(
            ram3_q
        )

    );


    
    
    
    
    

    logic [1:0] ipu_lane_q;


    // Clocked logic.


    always_ff @(posedge clk) begin

        ipu_lane_q <=
            ipu_addr[1:0];

    end


    // Combinational logic.


    always_comb begin

        case (ipu_lane_q)

            2'd0:
                ipu_read_data =
                    ram0_q;

            2'd1:
                ipu_read_data =
                    ram1_q;

            2'd2:
                ipu_read_data =
                    ram2_q;

            2'd3:
                ipu_read_data =
                    ram3_q;

            default:
                ipu_read_data =
                    8'd0;

        endcase

    end


    
    
    

    // Clocked logic.


    
    
    

    always_ff @(posedge clk) begin

        if (
            mem_write &&
            (addr != MMIO_STATUS_ADDR) &&
            in_cpu_fast_range(addr)
        ) begin

            case (funct3)

                
                
                

                3'b000: begin

                    cpu_fast_mem[
                        addr[8:0]
                    ] <=
                        write_data[7:0];

                end


                
                
                

                3'b001: begin

                    if (
                        ((addr[1:0] == 2'd0) ||
                         (addr[1:0] == 2'd2)) &&
                        in_cpu_fast_range(
                            addr + 32'd1
                        )
                    ) begin

                        cpu_fast_mem[
                            addr[8:0]
                        ] <=
                            write_data[7:0];

                        cpu_fast_mem[
                            addr[8:0] + 9'd1
                        ] <=
                            write_data[15:8];

                    end

                end


                
                
                

                3'b010: begin

                    if (
                        (addr[1:0] == 2'd0) &&
                        in_cpu_fast_range(
                            addr + 32'd3
                        )
                    ) begin

                        cpu_fast_mem[
                            addr[8:0]
                        ] <=
                            write_data[7:0];

                        cpu_fast_mem[
                            addr[8:0] + 9'd1
                        ] <=
                            write_data[15:8];

                        cpu_fast_mem[
                            addr[8:0] + 9'd2
                        ] <=
                            write_data[23:16];

                        cpu_fast_mem[
                            addr[8:0] + 9'd3
                        ] <=
                            write_data[31:24];

                    end

                end


                default: begin

                end

            endcase

        end

    end


    
    
    

    logic [31:0] cpu_fast_word;

    logic [8:0] cpu_base_addr;

    logic cpu_fast_word_ok;


    assign cpu_base_addr =
        {
            addr[8:2],
            2'b00
        };


    assign cpu_fast_word_ok =
        (addr < CPU_FAST_BYTES) &&
        (
            ({addr[31:2], 2'b00} + 32'd3)
            < CPU_FAST_BYTES
        );


    // Combinational logic.


    always_comb begin

        if (cpu_fast_word_ok) begin

            cpu_fast_word = {

                cpu_fast_mem[
                    cpu_base_addr + 9'd3
                ],

                cpu_fast_mem[
                    cpu_base_addr + 9'd2
                ],

                cpu_fast_mem[
                    cpu_base_addr + 9'd1
                ],

                cpu_fast_mem[
                    cpu_base_addr
                ]

            };

        end

        else begin

            cpu_fast_word =
                32'd0;

        end

    end


    
    
    

    // Combinational logic.


    
    
    

    always_comb begin

        read_data =
            32'd0;


        if (
            mem_read &&
            cpu_fast_word_ok
        ) begin

            case (funct3)

                
                
                

                3'b000: begin

                    case (addr[1:0])

                        2'd0:

                            read_data = {
                                {24{
                                    cpu_fast_word[7]
                                }},
                                cpu_fast_word[7:0]
                            };


                        2'd1:

                            read_data = {
                                {24{
                                    cpu_fast_word[15]
                                }},
                                cpu_fast_word[15:8]
                            };


                        2'd2:

                            read_data = {
                                {24{
                                    cpu_fast_word[23]
                                }},
                                cpu_fast_word[23:16]
                            };


                        2'd3:

                            read_data = {
                                {24{
                                    cpu_fast_word[31]
                                }},
                                cpu_fast_word[31:24]
                            };


                        default:

                            read_data =
                                32'd0;

                    endcase

                end


                
                
                

                3'b001: begin

                    if (addr[1] == 1'b0) begin

                        read_data = {
                            {16{
                                cpu_fast_word[15]
                            }},
                            cpu_fast_word[15:0]
                        };

                    end

                    else begin

                        read_data = {
                            {16{
                                cpu_fast_word[31]
                            }},
                            cpu_fast_word[31:16]
                        };

                    end

                end


                
                
                

                3'b010:

                    read_data =
                        cpu_fast_word;


                
                
                

                3'b100: begin

                    case (addr[1:0])

                        2'd0:

                            read_data = {
                                24'd0,
                                cpu_fast_word[7:0]
                            };


                        2'd1:

                            read_data = {
                                24'd0,
                                cpu_fast_word[15:8]
                            };


                        2'd2:

                            read_data = {
                                24'd0,
                                cpu_fast_word[23:16]
                            };


                        2'd3:

                            read_data = {
                                24'd0,
                                cpu_fast_word[31:24]
                            };


                        default:

                            read_data =
                                32'd0;

                    endcase

                end


                
                
                

                3'b101: begin

                    if (addr[1] == 1'b0) begin

                        read_data = {
                            16'd0,
                            cpu_fast_word[15:0]
                        };

                    end

                    else begin

                        read_data = {
                            16'd0,
                            cpu_fast_word[31:16]
                        };

                    end

                end


                default:

                    read_data =
                        32'd0;

            endcase

        end

    end


    
    
    

    // Clocked logic.


    
    
    

    always_ff @(posedge clk or posedge reset) begin

        if (reset) begin

            mmio_status <=
                32'd0;

            mmio_valid <=
                1'b0;

        end

        else begin

            mmio_valid <=
                1'b0;


            if (
                mem_write &&
                (addr == MMIO_STATUS_ADDR)
            ) begin

                mmio_status <=
                    write_data;

                mmio_valid <=
                    1'b1;

            end

        end

    end


endmodule
