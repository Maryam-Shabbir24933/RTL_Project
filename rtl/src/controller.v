
//============================================================
// CONTROLLER
//
// Header format:
// [7:5] = number of data beats
// [4:1] = starting address
// [0]   = read/write control
//
// rw_en = 1: SRAM write
// rw_en = 0: SRAM read
//
// The controller generates the address sequence:
// start_address, start_address+1, start_address+2, ...
//============================================================
module controller #(
    parameter DATA_BEATS_W = 3,
    parameter ADDR_W       = 4,
    parameter INS_W        = 8
)(
    input wire clk_i,
    input wire rst_i,

    input wire [INS_W-1:0] dout,
    input wire fifo_empty,

    output wire controller_ready,
    output wire rw_en_o,
    output wire [DATA_BEATS_W-1:0] wr_rd_beats_o,
    output wire [ADDR_W-1:0] address_o,
    output wire [INS_W-1:0] data_o,
    output reg data_valid
);

    localparam IDLE = 2'b00;
    localparam DATA = 2'b01;

    reg [1:0] state;
    reg [1:0] next_state;

    reg [DATA_BEATS_W-1:0] wr_rd_beat_reg;
    reg [DATA_BEATS_W-1:0] count;

    reg [INS_W-1:0] data_reg;
    reg [ADDR_W-1:0] address_reg;
    reg rw_en_reg;

    assign data_o        = data_reg;
    assign address_o     = address_reg;
    assign rw_en_o       = rw_en_reg;
    assign wr_rd_beats_o = wr_rd_beat_reg;


    assign controller_ready =
        !fifo_empty &&
        ((state == IDLE) ||
         ((state == DATA) && rw_en_reg));

    //========================================================
    // NEXT-STATE LOGIC
    //========================================================
    always @(*) begin
        next_state = state;

        case (state)

            IDLE: begin
                if (!fifo_empty && (dout[7:5] != 3'b000))
                    next_state = DATA;
            end

            DATA: begin
                if (rw_en_reg) begin

                    if (!fifo_empty &&
                        (count == wr_rd_beat_reg - 1'b1))
                        next_state = IDLE;
                end
                else begin
.
                    if (count == wr_rd_beat_reg - 1'b1)
                        next_state = IDLE;
                end
            end

            default: begin
                next_state = IDLE;
            end

        endcase
    end

    //========================================================
    // STATE REGISTER
    //========================================================
    always @(posedge clk_i or negedge rst_i) begin
        if (!rst_i)
            state <= IDLE;
        else
            state <= next_state;
    end

    //========================================================
    // HEADER, DATA AND ADDRESS CONTROL
    //========================================================
    always @(posedge clk_i or negedge rst_i) begin
        if (!rst_i) begin
            count          <= 0;
            wr_rd_beat_reg <= 0;
            address_reg    <= 0;
            rw_en_reg      <= 0;
            data_reg       <= 0;
            data_valid     <= 0;
        end
        else begin

            data_valid <= 1'b0;

            case (state)

                IDLE: begin
                    if (!fifo_empty) begin
                        wr_rd_beat_reg <= dout[7:5];
                        address_reg    <= dout[4:1];
                        rw_en_reg      <= dout[0];

                        count <= 0;
                    end
                end

                DATA: begin
                    if (rw_en_reg) begin
                        //====================================
                        // WRITE TRANSACTION
                        //====================================
                        if (!fifo_empty) begin
                            data_reg   <= dout;
                            data_valid <= 1'b1;

                           
                            if (count != 0)
                                address_reg <= address_reg + 1'b1;

                            count <= count + 1'b1;
                        end
                    end
                    else begin
                        //====================================
                        // READ TRANSACTION
                        //====================================
                        data_valid <= 1'b1;

                        if (count != 0)
                            address_reg <= address_reg + 1'b1;

                        count <= count + 1'b1;
                    end
                end

                default: begin
                    count <= 0;
                end

            endcase
        end
    end

endmodule
