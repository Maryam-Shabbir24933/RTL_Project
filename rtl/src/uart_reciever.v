
`timescale 1ns/1ps

//============================================================
// UART RECEIVER
//============================================================
module uart_reciever(
    input wire clk,
    input wire rst,
    input wire data_in_ser,
    input wire rx_en,
    output reg [7:0] rx_data,
    output reg rx_status
);

    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam DATA  = 2'b10;
    localparam STOP  = 2'b11;

    reg [1:0] state;
    reg [1:0] next_state;

    reg [7:0] data_reg;
    reg [3:0] bit_count;

    always @(posedge clk or negedge rst) begin
        if (!rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;

        case (state)
            IDLE: begin
                if (rx_en && data_in_ser == 1'b0)
                    next_state = START;
            end

            START: begin
                next_state = DATA;
            end

            DATA: begin
                if (bit_count == 4'd7)
                    next_state = STOP;
            end

            STOP: begin
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            data_reg  <= 8'b0;
            bit_count <= 4'b0;
            rx_data   <= 8'b0;
            rx_status <= 1'b0;
        end
        else begin
            rx_status <= 1'b0;

            case (state)
                IDLE: begin
                    bit_count <= 4'b0;
                end

                START: begin
                    bit_count <= 4'b0;
                end

                DATA: begin
                    data_reg <= {data_in_ser, data_reg[7:1]};

                    if (bit_count == 4'd7)
                        bit_count <= 4'd0;
                    else
                        bit_count <= bit_count + 1'b1;
                end

                STOP: begin
                    if (data_in_ser == 1'b1) begin
                        rx_data   <= data_reg;
                        rx_status <= 1'b1;
                    end

                    bit_count <= 4'd0;
                end

                default: begin
                    bit_count <= 4'd0;
                end
            endcase
        end
    end

endmodule
