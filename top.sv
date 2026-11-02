module top#(
    parameter int IMG_WIDTH = 128,
    parameter int IMG_HEIGHT = 128,
    parameter int threshold = 80
)(
    input logic clk,rst_n,data_in_valid,
    input logic [7:0] data_in,
    output logic [7:0] sobel_data,
    output logic sobel_valid);
    
    logic [7:0] win_data [3][3];
    logic win_valid,win_is_border;

    sobel_window_gen #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    )u_sobel_window_gen(
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .data_in_valid(data_in_valid),
        .win_data(win_data),
        .win_valid(win_valid),
        .win_is_border(win_is_border)
    );

    sobel_math_core #(
        .threshold(threshold)
    )u_sobel_math_core(
        .clk(clk),
        .rst_n(rst_n),
        .win_valid(win_valid),
        .win_is_border(win_is_border),
        .win_data(win_data),
        .sobel_data(sobel_data),
        .sobel_valid(sobel_valid)
    );      

endmodule