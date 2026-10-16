
`timescale 1ns/1ps

module tb_uart_sram_top;

    reg clk;
    reg rst_n;
    reg rx_en;
    reg data_in_ser;

    wire data_out_ser;

    //========================================================
    // EXPECTED CONTROLLER TRANSACTIONS
    //========================================================
    reg [3:0] expected_addr [0:63];
    reg       expected_rw   [0:63];
    reg [7:0] expected_data [0:63];

    reg [7:0] payload [0:6];

    integer expected_total;
    integer monitor_seen;
    integer monitor_enable;

    integer errors;
    integer monitor_errors;
    integer tx_frame_errors;

    integer i;
    integer j;
    integer cycles;
    integer tx_base;

    //========================================================
    // UART TX CAPTURE
    //========================================================
    reg [7:0] tx_captured [0:63];
    reg [7:0] captured_byte;

    integer tx_capture_count;
    integer cap_bit;

    //========================================================
    // DUT
    //========================================================
    uart_sram_top dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .rx_en        (rx_en),
        .data_in_ser  (data_in_ser),
        .data_out_ser (data_out_ser)
    );

    //========================================================
    // CLOCK: 10 ns PERIOD
    //========================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    //========================================================
    // WAVEFORM DUMP
    //========================================================
    initial begin
        $dumpfile("uart_sram_multibeat.vcd");
        $dumpvars(0, tb_uart_sram_top);
    end

    //========================================================
    // CONTROLLER MONITOR
    //
    // Checks every controller beat:
    // 1. Correct address
    // 2. Correct read/write mode
    // 3. Correct write data
    //
    // Address is expected to increment modulo 16.
    //========================================================
    integer monitor_index;

    always @(negedge clk) begin
        if ((rst_n === 1'b1) &&
            (monitor_enable == 1) &&
            (dut.data_valid === 1'b1)) begin

            monitor_index = monitor_seen;

            if (monitor_index >= expected_total) begin
                $display(
                    "FAIL: Unexpected controller beat, address=%0d, mode=%b",
                    dut.addr, dut.rw_en
                );

                monitor_errors = monitor_errors + 1;
            end
            else begin

                // Check address
                if (dut.addr !== expected_addr[monitor_index]) begin
                    $display(
                        "FAIL: Beat %0d address=%0d expected=%0d",
                        monitor_index + 1,
                        dut.addr,
                        expected_addr[monitor_index]
                    );

                    monitor_errors = monitor_errors + 1;
                end
                else begin
                    $display(
                        "PASS: Beat %0d address=%0d",
                        monitor_index + 1,
                        dut.addr
                    );
                end

                // Check transaction direction
                if (dut.rw_en !== expected_rw[monitor_index]) begin
                    $display(
                        "FAIL: Beat %0d read/write mode=%b expected=%b",
                        monitor_index + 1,
                        dut.rw_en,
                        expected_rw[monitor_index]
                    );

                    monitor_errors = monitor_errors + 1;
                end

                // Check write data
                if (expected_rw[monitor_index] == 1'b1) begin
                    if (dut.wdata !== expected_data[monitor_index]) begin
                        $display(
                            "FAIL: Beat %0d write data=%h expected=%h",
                            monitor_index + 1,
                            dut.wdata,
                            expected_data[monitor_index]
                        );

                        monitor_errors = monitor_errors + 1;
                    end
                    else begin
                        $display(
                            "PASS: Beat %0d write data=%h",
                            monitor_index + 1,
                            dut.wdata
                        );
                    end
                end
            end

            monitor_seen = monitor_seen + 1;
        end
    end

    //========================================================
    // UART TRANSMITTER MONITOR
    //
    // Automatically captures complete UART frames.
    // Data is LSB first.
    //
    // Starting on the falling edge of the start bit:
    // wait one half-cycle, then sample each bit at subsequent
    // falling clock edges.
    //========================================================
    initial begin
        forever begin

            // Wait for a frame start while idle between frames.
            @(negedge data_out_ser);

            // First falling clock edge: start-bit interval.
            @(negedge clk);

            // Sample the eight data bits.
            for (cap_bit = 0; cap_bit < 8; cap_bit = cap_bit + 1) begin
                @(negedge clk);
                #1;
                captured_byte[cap_bit] = data_out_ser;
            end

            // Check UART stop bit.
            @(negedge clk);
            #1;

            if (data_out_ser !== 1'b1) begin
                $display(
                    "FAIL: UART TX invalid stop bit for byte %h",
                    captured_byte
                );

                tx_frame_errors = tx_frame_errors + 1;
            end

            // Save received byte.
            if (tx_capture_count < 64) begin
                tx_captured[tx_capture_count] = captured_byte;

                $display(
                    "UART TX CAPTURE: byte[%0d] = %h",
                    tx_capture_count,
                    captured_byte
                );

                tx_capture_count = tx_capture_count + 1;
            end
            else begin
                $display("FAIL: TX capture array overflow");
                tx_frame_errors = tx_frame_errors + 1;
            end

        end
    end

    //========================================================
    // SEND ONE UART BYTE TO DUT
    //
    // Drives only:
    // data_in_ser
    // rx_en
    //
    // The RX FSM uses one clock per serial bit.
    //========================================================
    task uart_send_byte;
        input [7:0] value;

        integer bit_idx;

        begin
            // Start bit
            @(negedge clk);
            rx_en       = 1'b1;
            data_in_ser = 1'b0;

            // Keep start low while RX enters START state.
            @(negedge clk);
            rx_en       = 1'b0;
            data_in_ser = 1'b0;

            // Eight data bits, LSB first.
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                @(negedge clk);
                data_in_ser = value[bit_idx];
            end

            // Valid stop bit
            @(negedge clk);
            data_in_ser = 1'b1;

            // Allow RX to sample stop and FIFO to store byte.
            repeat (2) @(posedge clk);

            @(negedge clk);
            rx_en       = 1'b0;
            data_in_ser = 1'b1;
        end
    endtask

    //========================================================
    // SEND UART BYTE WITH INVALID STOP BIT
    //========================================================
    task uart_send_bad_stop_byte;
        input [7:0] value;

        integer bit_idx;

        begin
            // Start bit
            @(negedge clk);
            rx_en       = 1'b1;
            data_in_ser = 1'b0;

            @(negedge clk);
            rx_en       = 1'b0;
            data_in_ser = 1'b0;

            // Data bits
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                @(negedge clk);
                data_in_ser = value[bit_idx];
            end

            // Invalid stop bit
            @(negedge clk);
            data_in_ser = 1'b0;

            // RX samples the invalid stop bit.
            @(posedge clk);

            // Return serial input to idle.
            @(negedge clk);
            data_in_ser = 1'b1;
            rx_en       = 1'b0;

            repeat (2) @(posedge clk);
            @(negedge clk);
        end
    endtask

    //========================================================
    // SEND WRITE TRANSACTION
    //
    // Header = {number_of_beats, starting_address, 1'b1}
    // Followed by the payload bytes.
    //========================================================
    task send_write_transaction;
        input [2:0] beats;
        input [3:0] start_address;

        integer k;

        begin
            uart_send_byte({beats, start_address, 1'b1});

            for (k = 0; k < beats; k = k + 1) begin
                uart_send_byte(payload[k]);
            end
        end
    endtask

    //========================================================
    // SEND READ TRANSACTION
    //
    // Header = {number_of_beats, starting_address, 1'b0}
    // Read data is returned by the DUT over UART TX.
    //========================================================
    task send_read_transaction;
        input [2:0] beats;
        input [3:0] start_address;

        begin
            uart_send_byte({beats, start_address, 1'b0});
        end
    endtask

    //========================================================
    // CLEAR EXPECTED TRANSACTIONS
    //========================================================
    task clear_expectations;
        begin
            monitor_enable = 0;
            expected_total = 0;
            monitor_seen  = 0;
        end
    endtask

    //========================================================
    // APPEND EXPECTED TRANSACTION
    //
    // Allows multiple transactions to be monitored in a
    // single sequence without clearing the monitor.
    //========================================================
    task append_expected_transaction;
        input [2:0] beats;
        input [3:0] start_address;
        input       rw_mode;

        integer k;
        integer base_index;

        begin
            base_index = expected_total;

            for (k = 0; k < beats; k = k + 1) begin

                // Four-bit arithmetic wraps from 15 to 0.
                expected_addr[base_index + k] = start_address + k;

                expected_rw[base_index + k] = rw_mode;

                expected_data[base_index + k] = payload[k];

            end

            expected_total = base_index + beats;
        end
    endtask

    //========================================================
    // WAIT FOR CONTROLLER BEATS
    //========================================================
    task wait_for_controller_beats;
        input integer wanted;
        input integer max_cycles;

        integer wait_count;

        begin
            wait_count = 0;

            while ((monitor_seen < wanted) &&
                   (wait_count < max_cycles)) begin

                @(negedge clk);
                wait_count = wait_count + 1;

            end

            if (monitor_seen < wanted) begin
                $display(
                    "FAIL: Controller timeout. Seen=%0d expected=%0d",
                    monitor_seen,
                    wanted
                );

                errors = errors + 1;
            end

            if (monitor_seen > wanted) begin
                $display(
                    "FAIL: Controller produced extra beats. Seen=%0d expected=%0d",
                    monitor_seen,
                    wanted
                );

                errors = errors + 1;
            end
        end
    endtask

    //========================================================
    // WAIT FOR UART TX BYTES
    //========================================================
    task wait_for_tx_count;
        input integer target_count;
        input integer max_cycles;

        integer wait_count;

        begin
            wait_count = 0;

            while ((tx_capture_count < target_count) &&
                   (wait_count < max_cycles)) begin

                @(negedge clk);
                wait_count = wait_count + 1;

            end

            if (tx_capture_count < target_count) begin
                $display(
                    "FAIL: UART TX timeout. Captured=%0d expected=%0d",
                    tx_capture_count,
                    target_count
                );

                errors = errors + 1;
            end
        end
    endtask

    //========================================================
    // VERIFY SRAM CONTENTS
    //========================================================
    task check_sram_values;
        input [3:0] start_address;
        input [2:0] beats;

        integer k;
        reg [3:0] test_address;

        begin
            for (k = 0; k < beats; k = k + 1) begin

                test_address = start_address + k;

                if (dut.u_sram.memory[test_address] !== payload[k]) begin

                    $display(
                        "FAIL: SRAM[%0d]=%h expected=%h",
                        test_address,
                        dut.u_sram.memory[test_address],
                        payload[k]
                    );

                    errors = errors + 1;
                end
                else begin
                    $display(
                        "PASS: SRAM[%0d]=%h",
                        test_address,
                        payload[k]
                    );
                end

            end
        end
    endtask

    //========================================================
    // VERIFY CAPTURED UART READ DATA
    //========================================================
    task check_uart_values;
        input integer base_index;
        input [2:0] beats;

        integer k;

        begin
            for (k = 0; k < beats; k = k + 1) begin

                if (tx_captured[base_index + k] !== payload[k]) begin

                    $display(
                        "FAIL: UART read byte %0d=%h expected=%h",
                        k + 1,
                        tx_captured[base_index + k],
                        payload[k]
                    );

                    errors = errors + 1;
                end
                else begin
                    $display(
                        "PASS: UART read byte %0d=%h",
                        k + 1,
                        tx_captured[base_index + k]
                    );
                end

            end
        end
    endtask

    //========================================================
    // CHECK THAT RX FIFO IS EMPTY
    //========================================================
    task check_rx_fifo_empty;
        begin
            if (dut.rx_fifo_empty !== 1'b1) begin
                $display("FAIL: RX FIFO should be empty");
                errors = errors + 1;
            end
            else begin
                $display("PASS: RX FIFO empty");
            end
        end
    endtask

    //========================================================
    // WAIT FOR TX FIFO TO DRAIN AND TX TO BECOME IDLE
    //========================================================
    task wait_for_tx_idle;
        integer wait_count;

        begin
            wait_count = 0;

            while (((dut.tx_fifo_empty !== 1'b1) ||
                    (dut.tx_ready !== 1'b1)) &&
                   (wait_count < 200)) begin

                @(negedge clk);
                wait_count = wait_count + 1;

            end

            if ((dut.tx_fifo_empty !== 1'b1) ||
                (dut.tx_ready !== 1'b1)) begin

                $display("FAIL: TX FIFO or transmitter did not return to idle");
                errors = errors + 1;
            end
            else begin
                $display("PASS: TX FIFO drained and transmitter ready");
            end

            if (data_out_ser !== 1'b1) begin
                $display("FAIL: UART TX line is not idle high");
                errors = errors + 1;
            end
        end
    endtask

    //========================================================
    // MAIN TEST SEQUENCE
    //========================================================
    initial begin

        rst_n       = 1'b0;
        rx_en       = 1'b0;
        data_in_ser = 1'b1;

        expected_total = 0;
        monitor_seen   = 0;
        monitor_enable = 0;

        errors          = 0;
        monitor_errors  = 0;
        tx_frame_errors = 0;
        tx_capture_count = 0;

        //====================================================
        // RESET
        //====================================================
        $display("");
        $display("==============================================");
        $display(" UART-SRAM COMPREHENSIVE SELF-CHECKING TEST ");
        $display("==============================================");

        repeat (5) @(posedge clk);

        @(negedge clk);
        rst_n = 1'b1;

        repeat (3) @(negedge clk);

        //====================================================
        // TEST 1: SINGLE-BEAT WRITE AND READ
        //====================================================
        $display("");
        $display("========== TEST 1: SINGLE-BEAT WRITE/READ ==========");

        payload[0] = 8'h00;

        clear_expectations();
        append_expected_transaction(3'd1, 4'd2, 1'b1);
        monitor_enable = 1;

        send_write_transaction(3'd1, 4'd2);

        wait_for_controller_beats(1, 300);

        repeat (3) @(posedge clk);
        check_sram_values(4'd2, 3'd1);
        check_rx_fifo_empty();

        monitor_enable = 0;

        tx_base = tx_capture_count;

        clear_expectations();
        append_expected_transaction(3'd1, 4'd2, 1'b0);
        monitor_enable = 1;

        send_read_transaction(3'd1, 4'd2);

        wait_for_controller_beats(1, 300);
        wait_for_tx_count(tx_base + 1, 300);

        check_uart_values(tx_base, 3'd1);
        wait_for_tx_idle();

        monitor_enable = 0;

        //====================================================
        // TEST 2: TWO-BEAT WRITE AND READ
        //====================================================
        $display("");
        $display("========== TEST 2: TWO-BEAT WRITE/READ ==========");

        payload[0] = 8'hFF;
        payload[1] = 8'h80;

        clear_expectations();
        append_expected_transaction(3'd2, 4'd7, 1'b1);
        monitor_enable = 1;

        send_write_transaction(3'd2, 4'd7);

        wait_for_controller_beats(2, 400);

        repeat (3) @(posedge clk);
        check_sram_values(4'd7, 3'd2);
        check_rx_fifo_empty();

        monitor_enable = 0;

        tx_base = tx_capture_count;

        clear_expectations();
        append_expected_transaction(3'd2, 4'd7, 1'b0);
        monitor_enable = 1;

        send_read_transaction(3'd2, 4'd7);

        wait_for_controller_beats(2, 300);
        wait_for_tx_count(tx_base + 2, 300);

        check_uart_values(tx_base, 3'd2);
        wait_for_tx_idle();

        monitor_enable = 0;

        //====================================================
        // TEST 3: THREE-BEAT WRITE AND READ
        //====================================================
        $display("");
        $display("========== TEST 3: THREE-BEAT WRITE/READ ==========");

        payload[0] = 8'hA5;
        payload[1] = 8'h3C;
        payload[2] = 8'hD7;

        clear_expectations();
        append_expected_transaction(3'd3, 4'd4, 1'b1);
        monitor_enable = 1;

        send_write_transaction(3'd3, 4'd4);

        wait_for_controller_beats(3, 500);

        repeat (3) @(posedge clk);
        check_sram_values(4'd4, 3'd3);

        monitor_enable = 0;

        tx_base = tx_capture_count;

        clear_expectations();
        append_expected_transaction(3'd3, 4'd4, 1'b0);
        monitor_enable = 1;

        send_read_transaction(3'd3, 4'd4);

        wait_for_controller_beats(3, 300);
        wait_for_tx_count(tx_base + 3, 400);

        check_uart_values(tx_base, 3'd3);
        wait_for_tx_idle();

        monitor_enable = 0;

        //====================================================
        // TEST 4: SEVEN-BEAT WRITE/READ WITH ADDRESS WRAP
        //
        // Addresses:
        // 13, 14, 15, 0, 1, 2, 3
        //====================================================
        $display("");
        $display("========== TEST 4: SEVEN-BEAT ADDRESS WRAP ==========");

        payload[0] = 8'h00;
        payload[1] = 8'hFF;
        payload[2] = 8'h55;
        payload[3] = 8'hAA;
        payload[4] = 8'h81;
        payload[5] = 8'h18;
        payload[6] = 8'h7E;

        clear_expectations();
        append_expected_transaction(3'd7, 4'd13, 1'b1);
        monitor_enable = 1;

        send_write_transaction(3'd7, 4'd13);

        wait_for_controller_beats(7, 800);

        repeat (3) @(posedge clk);
        check_sram_values(4'd13, 3'd7);
        check_rx_fifo_empty();

        monitor_enable = 0;

        tx_base = tx_capture_count;

        clear_expectations();
        append_expected_transaction(3'd7, 4'd13, 1'b0);
        monitor_enable = 1;

        send_read_transaction(3'd7, 4'd13);

        wait_for_controller_beats(7, 300);
        wait_for_tx_count(tx_base + 7, 500);

        check_uart_values(tx_base, 3'd7);
        wait_for_tx_idle();

        monitor_enable = 0;

        //====================================================
        // TEST 5: BACK-TO-BACK SINGLE-BEAT WRITES
        //
        // First:  SRAM[1] = 12
        // Second: SRAM[9] = 34
        //====================================================
        $display("");
        $display("========== TEST 5: BACK-TO-BACK TRANSACTIONS ==========");

        clear_expectations();

        payload[0] = 8'h12;
        append_expected_transaction(3'd1, 4'd1, 1'b1);

        monitor_enable = 1;

        send_write_transaction(3'd1, 4'd1);

        // Append the second expected transaction without
        // resetting the monitor.
        payload[0] = 8'h34;
        append_expected_transaction(3'd1, 4'd9, 1'b1);

        send_write_transaction(3'd1, 4'd9);

        wait_for_controller_beats(2, 600);

        repeat (3) @(posedge clk);

        if (dut.u_sram.memory[1] !== 8'h12) begin
            $display("FAIL: Back-to-back write SRAM[1]");
            errors = errors + 1;
        end
        else begin
            $display("PASS: Back-to-back write SRAM[1]=12");
        end

        if (dut.u_sram.memory[9] !== 8'h34) begin
            $display("FAIL: Back-to-back write SRAM[9]");
            errors = errors + 1;
        end
        else begin
            $display("PASS: Back-to-back write SRAM[9]=34");
        end

        check_rx_fifo_empty();

        monitor_enable = 0;

        //====================================================
        // TEST 6: ZERO-BEAT HEADER
        //
        // No data beats should be issued.
        //====================================================
        $display("");
        $display("========== TEST 6: ZERO-BEAT HEADER ==========");

        clear_expectations();
        monitor_enable = 1;

        uart_send_byte({3'd0, 4'd5, 1'b1});

        repeat (30) @(negedge clk);

        if (monitor_seen != 0) begin
            $display("FAIL: Zero-beat header generated a data beat");
            errors = errors + 1;
        end
        else begin
            $display("PASS: Zero-beat header generated no data beats");
        end

        check_rx_fifo_empty();

        monitor_enable = 0;

        //====================================================
        // TEST 7: INVALID STOP BIT ON HEADER
        //
        // Header should not enter RX FIFO.
        //====================================================
        $display("");
        $display("========== TEST 7: INVALID UART HEADER STOP ==========");

        clear_expectations();
        monitor_enable = 1;

        uart_send_bad_stop_byte({3'd1, 4'd6, 1'b1});

        repeat (30) @(negedge clk);

        if (monitor_seen != 0) begin
            $display("FAIL: Invalid-stop header generated a beat");
            errors = errors + 1;
        end
        else begin
            $display("PASS: Invalid-stop header was rejected");
        end

        check_rx_fifo_empty();

        monitor_enable = 0;

        //====================================================
        // TEST 8: INVALID PAYLOAD STOP BIT AND RECOVERY
        //
        // Header requests one beat at address 8.
        // Bad payload 55 must be rejected.
        // Valid payload C3 must complete the transaction.
        //====================================================
        $display("");
        $display("========== TEST 8: INVALID PAYLOAD AND RECOVERY ==========");

        payload[0] = 8'hC3;

        clear_expectations();
        append_expected_transaction(3'd1, 4'd8, 1'b1);
        monitor_enable = 1;

        uart_send_byte({3'd1, 4'd8, 1'b1});

        uart_send_bad_stop_byte(8'h55);

        repeat (20) @(negedge clk);

        if (monitor_seen != 0) begin
            $display("FAIL: Invalid payload incorrectly generated a beat");
            errors = errors + 1;
        end
        else begin
            $display("PASS: Invalid payload was rejected");
        end

        // A subsequent valid payload must complete the write.
        uart_send_byte(8'hC3);

        wait_for_controller_beats(1, 400);

        repeat (3) @(posedge clk);

        if (dut.u_sram.memory[8] !== 8'hC3) begin
            $display(
                "FAIL: Recovery write SRAM[8]=%h expected=C3",
                dut.u_sram.memory[8]
            );
            errors = errors + 1;
        end
        else begin
            $display("PASS: Valid payload recovered transaction SRAM[8]=C3");
        end

        check_rx_fifo_empty();

        monitor_enable = 0;

        //====================================================
        // TEST 9: RESET DURING A MULTIBEAT TRANSACTION
        //
        // Start a three-beat write at address 10.
        // Only the first payload is sent.
        // Reset should abandon the unfinished transaction.
        // Then verify a new transaction works.
        //====================================================
        $display("");
        $display("========== TEST 9: RESET DURING MULTIBEAT ==========");

        payload[0] = 8'h11;
        payload[1] = 8'h22;
        payload[2] = 8'h33;

        clear_expectations();
        append_expected_transaction(3'd3, 4'd10, 1'b1);
        monitor_enable = 1;

        uart_send_byte({3'd3, 4'd10, 1'b1});
        uart_send_byte(8'h11);

        wait_for_controller_beats(1, 400);

        if (monitor_seen == 1) begin
            $display("PASS: First beat issued before reset");
        end

        // Stop checking the old transaction.
        monitor_enable = 0;

        // Assert active-low reset.
        @(negedge clk);
        rst_n       = 1'b0;
        rx_en       = 1'b0;
        data_in_ser = 1'b1;

        repeat (4) @(posedge clk);

        @(negedge clk);
        rst_n = 1'b1;

        repeat (4) @(negedge clk);

        // Verify that a new single-beat write works after reset.
        payload[0] = 8'hBE;

        clear_expectations();
        append_expected_transaction(3'd1, 4'd11, 1'b1);
        monitor_enable = 1;

        send_write_transaction(3'd1, 4'd11);

        wait_for_controller_beats(1, 400);

        repeat (3) @(posedge clk);

        if (dut.u_sram.memory[11] !== 8'hBE) begin
            $display(
                "FAIL: Post-reset write SRAM[11]=%h expected=BE",
                dut.u_sram.memory[11]
            );
            errors = errors + 1;
        end
        else begin
            $display("PASS: Controller and SRAM recovered after reset");
        end

        monitor_enable = 0;

        //====================================================
        // TEST 10: FINAL IDLE AND FIFO CHECKS
        //====================================================
        $display("");
        $display("========== TEST 10: FINAL IDLE CHECKS ==========");

        repeat (5) @(negedge clk);

        check_rx_fifo_empty();
        wait_for_tx_idle();

        //====================================================
        // FINAL SUMMARY
        //====================================================
        $display("");
        $display("==============================================");
        $display("               TEST SUMMARY");
        $display("==============================================");

        $display("Testbench check errors : %0d", errors);
        $display("Controller monitor errors : %0d", monitor_errors);
        $display("UART TX frame errors : %0d", tx_frame_errors);

        if ((errors == 0) &&
            (monitor_errors == 0) &&
            (tx_frame_errors == 0)) begin

            $display("");
            $display("========== ALL TESTS PASSED ==========");
        end
        else begin
            $display("");
            $display("========== TEST FAILED ==========");
        end

        $display("==============================================");

        $finish;
    end

    //========================================================
    // GLOBAL TIMEOUT
    //========================================================
    initial begin
        #200000;

        $display("");
        $display("FAIL: GLOBAL TESTBENCH TIMEOUT");
        $display(
            "Controller beats observed=%0d, expected=%0d",
            monitor_seen,
            expected_total
        );

        $finish;
    end

endmodule
