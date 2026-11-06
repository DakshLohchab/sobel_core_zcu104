`timescale 1ns / 1ps

module tb_wrapper;

    parameter int IMAGE_WIDTH  = 128;
    parameter int IMAGE_HEIGHT = 128;
    parameter int threshold    = 80;
    parameter int NUM_PIXELS   = IMAGE_WIDTH * IMAGE_HEIGHT;

    logic       aclk = 0;
    logic       aresetn;
    logic       s_axis_tvalid;
    logic       s_axis_tlast;
    logic       m_axis_tready;
    logic [7:0] s_axis_tdata;
    logic       s_axis_tready;
    logic       m_axis_tvalid;
    logic       m_axis_tlast;
    logic [7:0] m_axis_tdata;

    logic [7:0] img_data          [0:NUM_PIXELS-1];
    logic [7:0] sobel_data_golden [0:NUM_PIXELS-1];

    int out_pix_cnt  = 0;
    int total_errors = 0;
    int tlast_seen   = 0;
    bit check_enable = 0;

    // Instantiate Wrapper DUT
    sobel_axi_wrapper #(
        .threshold    (threshold),
        .IMAGE_WIDTH  (IMAGE_WIDTH),
        .IMAGE_HEIGHT (IMAGE_HEIGHT)
    ) dut (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tlast  (s_axis_tlast),
        .m_axis_tready (m_axis_tready),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tready (s_axis_tready),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tlast  (m_axis_tlast),
        .m_axis_tdata  (m_axis_tdata)
    );

    // 100 MHz Clock
    always #5 aclk = ~aclk;

    // AXI4-Stream Master Driver Task (Supports Continuous or Random-Gap Streaming)
    task automatic send_frame(input bit random_gaps);
        int sent = 0;
        while (sent < NUM_PIXELS) begin
            if (random_gaps && ($urandom_range(0, 3) == 0)) begin
                s_axis_tvalid <= 1'b0;
                s_axis_tlast  <= 1'b0;
                @(posedge aclk);
            end else begin
                s_axis_tvalid <= 1'b1;
                s_axis_tdata  <= img_data[sent];
                s_axis_tlast  <= (sent == NUM_PIXELS - 1);
                @(posedge aclk);
                // Hold tvalid and tdata steady until s_axis_tready is high
                while (!s_axis_tready) begin
                    @(posedge aclk);
                end
                sent++;
            end
        end
        s_axis_tvalid <= 1'b0;
        s_axis_tlast  <= 1'b0;
    endtask

    initial begin
        $readmemh("input_gray.mem", img_data);
        $readmemh("golden_sobel.mem", sobel_data_golden);

        aresetn       = 1'b0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        s_axis_tdata  = 8'd0;
        m_axis_tready = 1'b1;

        repeat (10) @(posedge aclk);
        aresetn = 1'b1;
        repeat (10) @(posedge aclk);

        $display("============================================================");
        $display("GATE 1: Testing 3 Full Frames + Mid-Frame Reset Recovery");
        $display("============================================================");

        // 1. Frame 1: Continuous Burst
        check_enable = 1;
        out_pix_cnt  = 0;
        send_frame(0);
        wait (tlast_seen == 1);
        @(posedge aclk);
        $display("[Frame 1 - Continuous] Complete! Pixels: %0d, Errors: %0d", out_pix_cnt, total_errors);

        // 2. Mid-Frame Abort Test: Stream 5,000 pixels then pull aresetn low
        $display("[Abort Test] Streaming 5000 pixels then asserting mid-frame aresetn...");
        check_enable = 0;
        for (int i = 0; i < 5000; i++) begin
            s_axis_tvalid <= 1'b1;
            s_axis_tdata  <= img_data[i];
            @(posedge aclk);
            while (!s_axis_tready) @(posedge aclk);
        end
        s_axis_tvalid <= 1'b0;
        aresetn       <= 1'b0; // Abort mid-frame
        repeat (5) @(posedge aclk);
        aresetn       <= 1'b1;
        repeat (10) @(posedge aclk);

        // 3. Frame 2 (Post-Abort) & Frame 3 (Back-to-Back with Random Gaps)
        check_enable = 1;
        out_pix_cnt  = 0;
        send_frame(1); // Frame 2 with random input gaps
        wait (tlast_seen == 2);
        @(posedge aclk);
        $display("[Frame 2 - Post-Abort] Complete! Pixels: %0d, Errors: %0d", out_pix_cnt, total_errors);

        out_pix_cnt  = 0;
        send_frame(1); // Frame 3 immediately back-to-back
        wait (tlast_seen == 3);
        @(posedge aclk);
        $display("[Frame 3 - Back-to-Back] Complete! Pixels: %0d, Errors: %0d", out_pix_cnt, total_errors);

        repeat (10) @(posedge aclk);
        $display("============================================================");
        if (total_errors == 0 && tlast_seen == 3)
            $display("GATE 1 STATUS: PASS! All 3 frames (49,152 pixels) verified with 0 errors!");
        else
            $display("GATE 1 STATUS: FAIL! Total Errors: %0d", total_errors);
        $display("============================================================");
        $finish;
    end

    // Self-Checking Output Monitor
    always @(posedge aclk) begin
        if (aresetn && check_enable && m_axis_tvalid && m_axis_tready) begin
            if (m_axis_tdata !== sobel_data_golden[out_pix_cnt]) begin
                if (total_errors < 20)
                    $display("[ERROR] Frame %0d, Pixel %0d: Expected %02h, Got %02h",
                             tlast_seen + 1, out_pix_cnt, sobel_data_golden[out_pix_cnt], m_axis_tdata);
                total_errors <= total_errors + 1;
            end

            // Verify m_axis_tlast pulses ONLY on the 16,384th pixel of each frame
            if (out_pix_cnt == NUM_PIXELS - 1) begin
                if (!m_axis_tlast) begin
                    $display("[ERROR] Missing m_axis_tlast on pixel 16383!");
                    total_errors <= total_errors + 1;
                end
                tlast_seen <= tlast_seen + 1;
            end else if (m_axis_tlast) begin
                $display("[ERROR] Premature m_axis_tlast at pixel %0d!", out_pix_cnt);
                total_errors <= total_errors + 1;
            end

            out_pix_cnt <= out_pix_cnt + 1;
        end
    end

endmodule