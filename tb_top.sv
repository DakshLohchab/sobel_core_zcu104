`timescale 1ns / 1ps

module tb_top;

    // 1. Parameters
    parameter int IMG_WIDTH  = 128;
    parameter int IMG_HEIGHT = 128;
    parameter int threshold  = 80;
    parameter int NUM_PIXELS = IMG_WIDTH * IMG_HEIGHT; // 16,384 pixels

    // 2. DUT Signals
    logic       clk = 0;
    logic       rst_n;
    logic       data_in_valid;
    logic [7:0] data_in;
    logic [7:0] sobel_data;
    logic       sobel_valid;

    // 3. Memory Arrays for Input Image and Golden Reference
    logic [7:0] img_data          [0:NUM_PIXELS-1];
    logic [7:0] sobel_data_golden [0:NUM_PIXELS-1];

    // 4. Scoreboard Counters & File Handle
    int out_cnt = 0;
    int err_cnt = 0;
    int fd_out;

    // 5. Instantiate Top-Level DUT
    top #(
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT),
        .threshold  (threshold)
    ) u_top (
        .clk           (clk),
        .rst_n         (rst_n),
        .data_in_valid (data_in_valid),
        .data_in       (data_in),
        .sobel_data    (sobel_data),
        .sobel_valid   (sobel_valid)
    );

    // 6. 100 MHz Clock Generation (10 ns period)
    always #5 clk = ~clk;

    // 7. Stimulus Block: Load files, Reset, Stream 16,384 pixels, Flush 129 clocks
    initial begin
        // Load hex memory files (Add both .mem files to Vivado Simulation Sources)
        $readmemh("input_gray.mem", img_data);
        $readmemh("golden_sobel.mem", sobel_data_golden);

        // Open an output file to save hardware results if you want to plot the image later
        fd_out = $fopen("fpga_output.mem", "w");

        // Initialize inputs and assert active-low reset
        rst_n         = 1'b0;
        data_in_valid = 1'b0;
        data_in       = 8'd0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        $display("------------------------------------------------------------");
        $display("Starting Sobel Edge Detection Simulation (%0dx%0d)...", IMG_WIDTH, IMG_HEIGHT);
        $display("------------------------------------------------------------");

        // Phase A: Stream all 16,384 pixels (1 pixel per clock cycle)
        for (int i = 0; i < NUM_PIXELS; i++) begin
            @(posedge clk);
            data_in_valid <= 1'b1;
            data_in       <= img_data[i];
        end

        // Phase B: Flush the final 129 pixels out of Line Buffer 1
        for (int i = 0; i < IMG_WIDTH + 1; i++) begin
            @(posedge clk);
            data_in_valid <= 1'b1;
            data_in       <= 8'd0;
        end

        // Phase C: Stop input stream and wait for the 3-stage math pipeline to drain
        @(posedge clk);
        data_in_valid <= 1'b0;
        data_in       <= 8'd0;

        repeat (10) @(posedge clk);

        $fclose(fd_out);

        // Print Final Verification Report
        $display("------------------------------------------------------------");
        $display("Simulation Complete!");
        $display("Total Valid Pixels Received : %0d / %0d", out_cnt, NUM_PIXELS);
        $display("Total Mismatches vs Golden  : %0d", err_cnt);
        if (out_cnt == NUM_PIXELS && err_cnt == 0) begin
            $display("STATUS: PASS! Hardware matches golden_sobel.mem 100%%!");
        end else begin
            $display("STATUS: FAIL! Check waveform for mismatches.");
        end
        $display("------------------------------------------------------------");

        $finish;
    end

    // 8. Self-Checking Monitor Block: Compares every valid output pixel against golden_sobel.mem
    always @(posedge clk) begin
        if (rst_n && sobel_valid) begin
            // Write hardware output byte to fpga_output.mem
            $fwrite(fd_out, "%02X\n", sobel_data);

            // Compare against golden reference
            if (sobel_data !== sobel_data_golden[out_cnt]) begin
                if (err_cnt < 20) begin // Print first 20 errors to avoid flooding console
                    $display("[ERROR] Pixel %0d (Row %0d, Col %0d): Expected %02h, Got %02h",
                             out_cnt, out_cnt / IMG_WIDTH, out_cnt % IMG_WIDTH,
                             sobel_data_golden[out_cnt], sobel_data);
                end
                err_cnt <= err_cnt + 1;
            end

            out_cnt <= out_cnt + 1;
        end
    end

endmodule