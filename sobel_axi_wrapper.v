`timescale 1ns / 1ps

module sobel_axi_wrapper #(
    parameter integer threshold    = 80,
    parameter integer IMAGE_WIDTH  = 128,
    parameter integer IMAGE_HEIGHT = 128
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axis:m_axis, ASSOCIATED_RESET aresetn" *)
    input  wire       aclk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire       aresetn,

    input  wire       s_axis_tvalid,
    input  wire       s_axis_tlast,
    input  wire       m_axis_tready,
    input  wire [7:0] s_axis_tdata,
    output wire       s_axis_tready,
    output wire       m_axis_tvalid,
    output wire       m_axis_tlast,
    output wire [7:0] m_axis_tdata
);

    localparam integer NUM_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT; // 16384
    localparam integer FLUSH_LEN  = IMAGE_WIDTH + 1;            // 129

    // Sized localparams to prevent 32-bit WIDTHEXPAND warnings in Verilator
    localparam [14:0] LAST_PIXEL = NUM_PIXELS - 1;              // 15'd16383
    localparam [7:0]  LAST_FLUSH = FLUSH_LEN - 1;               // 8'd128

    localparam [1:0] S_STREAM = 2'd0,
                     S_FLUSH  = 2'd1,
                     S_DRAIN  = 2'd2,
                     S_RESET  = 2'd3;

    reg [1:0]  state;
    reg [14:0] int_cnt, out_cnt;
    reg [7:0]  flush_cnt;
    reg [2:0]  reset_cnt;
    reg        core_reset_n;

    wire       core_in_valid, core_out_valid;
    wire [7:0] core_out_data, core_in_data;

    // 1. Combinational AXI-Stream & Core Muxing
    assign s_axis_tready = (state == S_STREAM) && core_reset_n;

    assign core_in_valid = (state == S_STREAM) ? (s_axis_tvalid && s_axis_tready) :
                           (state == S_FLUSH)  ? 1'b1 : 1'b0;

    assign core_in_data  = (state == S_STREAM) ? s_axis_tdata : 8'd0;

    assign m_axis_tdata  = core_out_data;
    assign m_axis_tvalid = core_out_valid;
    assign m_axis_tlast  = core_out_valid && (out_cnt == LAST_PIXEL);

    // 2. Sequential 4-State FSM & Counters
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state        <= S_RESET;
            int_cnt      <= 15'd0;
            out_cnt      <= 15'd0;
            flush_cnt    <= 8'd0;
            reset_cnt    <= 3'd0;
            core_reset_n <= 1'b0;
        end else begin
            // Count valid output pixels exiting top.sv
            if (core_out_valid) begin
                if (out_cnt == LAST_PIXEL)
                    out_cnt <= 15'd0;
                else
                    out_cnt <= out_cnt + 15'd1;
            end

            case (state)
                // State 0: Stream 16,384 real pixels from DMA into top.sv
                S_STREAM: begin
                    core_reset_n <= 1'b1;
                    if (s_axis_tvalid && s_axis_tready) begin
                        if (int_cnt == LAST_PIXEL) begin
                            int_cnt   <= 15'd0;
                            flush_cnt <= 8'd0;
                            state     <= S_FLUSH;
                        end else begin
                            int_cnt   <= int_cnt + 15'd1;
                        end
                    end
                end

                // State 1: Inject 129 dummy zero pixels to push final row out of lb1
                S_FLUSH: begin
                    if (flush_cnt == LAST_FLUSH) begin
                        flush_cnt <= 8'd0;
                        state     <= S_DRAIN;
                    end else begin
                        flush_cnt <= flush_cnt + 8'd1;
                    end
                end

                // State 2: Wait for the 16,384th output pixel to leave sobel_math_core
                S_DRAIN: begin
                    if (core_out_valid && (out_cnt == LAST_PIXEL)) begin
                        reset_cnt <= 3'd0;
                        state     <= S_RESET;
                    end
                end

                // State 3: Pulse core_reset_n low for 4 clocks, then 1 recovery clock
                S_RESET: begin
                    int_cnt   <= 15'd0;
                    out_cnt   <= 15'd0;
                    flush_cnt <= 8'd0;
                    if (reset_cnt < 3'd4) begin
                        core_reset_n <= 1'b0;
                        reset_cnt    <= reset_cnt + 3'd1;
                    end else begin
                        core_reset_n <= 1'b1;
                        reset_cnt    <= 3'd0;
                        state        <= S_STREAM;
                    end
                end

                default: state <= S_RESET;
            endcase
        end
    end

    // 3. Instantiate Verified SystemVerilog Core
    top #(
        .IMG_WIDTH  (IMAGE_WIDTH),
        .IMG_HEIGHT (IMAGE_HEIGHT),
        .threshold  (threshold)
    ) u_top (
        .clk           (aclk),
        .rst_n         (core_reset_n),
        .data_in_valid (core_in_valid),
        .data_in       (core_in_data),
        .sobel_data    (core_out_data),
        .sobel_valid   (core_out_valid)
    );

endmodule