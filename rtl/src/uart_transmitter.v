

//============================================================
// UART TRANSMITTER
//============================================================
module uart_transmitter (
    input wire clk,
    input wire rst,
    input wire [7:0] tx_data,
    input wire tx_start,

    output reg data_out_ser,
    output wire tx_ready
);

    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam DATA  = 2'b10;
    localparam STOP  = 2'b11;

    reg [1:0] state;
    reg [7:0] data_reg;
    reg [2:0] bit_count;

    assign tx_ready = (state == IDLE);

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            state        <= IDLE;
            data_reg     <= 8'b0;
            bit_count    <= 3'b0;
            data_out_ser <= 1'b1;
        end
        else begin
            case (state)

                IDLE: begin
                    data_out_ser <= 1'b1;
                    bit_count    <= 3'b0;

                    if (tx_start) begin
                        data_reg <= tx_data;
                        state    <= START;
                    end
                end

                START: begin
                    data_out_ser <= 1'b0;
                    state        <= DATA;
                end

                DATA: begin
                    data_out_ser <= data_reg[0];
                    data_reg     <= {1'b0, data_reg[7:1]};

                    if (bit_count == 3'd7) begin
                        bit_count <= 3'b0;
                        state     <= STOP;
                    end
                    else begin
                        bit_count <= bit_count + 1'b1;
                    end
                end

                STOP: begin
                    data_out_ser <= 1'b1;
                    state        <= IDLE;
                end

                default: begin
                    state        <= IDLE;
                    data_out_ser <= 1'b1;
                end

            endcase
        end
    end

endmodule
