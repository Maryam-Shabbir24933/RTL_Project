module uart_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 16,
    parameter ADDR_WIDTH = 4
)(
    input wire clk,
    input wire rst,

    input wire [DATA_WIDTH-1:0] data_in,
    input wire rx_status,
    input wire controller_ready,

    output wire [DATA_WIDTH-1:0] data_out,
    output wire full,
    output wire empty
);

    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];

    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [ADDR_WIDTH:0] count;

    wire write_fifo;
    wire read_fifo;

    assign full  = (count == DEPTH);
    assign empty = (count == 0);

    assign data_out = empty ? {DATA_WIDTH{1'b0}} : memory[rd_ptr];

    assign write_fifo = rx_status && !full;
    assign read_fifo  = controller_ready && !empty;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
        end
        else begin
            if (write_fifo) begin
                memory[wr_ptr] <= data_in;

                if (wr_ptr == DEPTH-1)
                    wr_ptr <= 0;
                else
                    wr_ptr <= wr_ptr + 1'b1;
            end

            if (read_fifo) begin
                if (rd_ptr == DEPTH-1)
                    rd_ptr <= 0;
                else
                    rd_ptr <= rd_ptr + 1'b1;
            end

            case ({write_fifo, read_fifo})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule