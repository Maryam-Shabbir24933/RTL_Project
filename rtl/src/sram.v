module sram_dual_port #(
    parameter DATA_WIDTH  = 8,
    parameter ADDR_WIDTH  = 4,
    parameter DEPTH       = 16,
    parameter BEATS_WIDTH = 3
)(
    input wire clk,
    input wire rst_n,

    // Per-beat request/valid
    input wire start,
    input wire rw_en,
    input wire [ADDR_WIDTH-1:0] address,
    input wire [BEATS_WIDTH-1:0] data_beats,

    // Write data
    input wire [DATA_WIDTH-1:0] wr_data,

    // Read data
    output reg [DATA_WIDTH-1:0] rd_data,
    output reg rd_valid,

    // Status
    output reg busy,
    output reg done
);

    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];

    reg [BEATS_WIDTH-1:0] beat_count;
    reg [BEATS_WIDTH-1:0] requested_beats;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            beat_count      <= 0;
            requested_beats <= 0;

            busy     <= 1'b0;
            done     <= 1'b0;
            rd_valid <= 1'b0;
            rd_data  <= 0;
        end
        else begin
            done     <= 1'b0;
            rd_valid <= 1'b0;

            // Each start corresponds to one beat.
            // The address comes directly from the controller.
            if (start) begin

                if (!busy) begin
                    // Start a new transaction and process
                    // its first beat immediately.
                    if (data_beats != 0) begin

                        requested_beats <= data_beats;

                        if (rw_en) begin
                            memory[address] <= wr_data;
                        end
                        else begin
                            rd_data  <= memory[address];
                            rd_valid <= 1'b1;
                        end

                        // First beat has been processed.
                        if (data_beats == 1) begin
                            beat_count <= 0;
                            busy       <= 1'b0;
                            done       <= 1'b1;
                        end
                        else begin
                            beat_count <= 1;
                            busy       <= 1'b1;
                        end
                    end
                end

                else begin
                    // Process the remaining beats using the
                    // current address supplied by the controller.
                    if (rw_en) begin
                        memory[address] <= wr_data;
                    end
                    else begin
                        rd_data  <= memory[address];
                        rd_valid <= 1'b1;
                    end

                    if (beat_count == requested_beats - 1'b1) begin
                        beat_count <= 0;
                        busy       <= 1'b0;
                        done       <= 1'b1;
                    end
                    else begin
                        beat_count <= beat_count + 1'b1;
                    end
                end
            end
        end
    end

endmodule
