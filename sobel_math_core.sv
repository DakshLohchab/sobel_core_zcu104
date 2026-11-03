`timescale 1ns / 1ps
module sobel_math_core#(
    parameter int threshold = 80
)(
    input logic clk,rst_n,win_valid,win_is_border,
    input logic [7:0] win_data [3][3],
    output logic [7:0] sobel_data,
    output logic sobel_valid);
    
    logic [10:0] gx_right,gx_left,gy_top,gy_bottom,gx,gy,abs_gx,abs_gy;
    logic valid_s1,valid_s2,border_s1,border_s2;
    logic [11:0] mag;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)begin
            gx_right <= 0;
            gx_left <= 0;
            gy_top <= 0;
            gy_bottom <= 0;
            valid_s1 <= 0;
            border_s1 <= 0;
        end
        else begin
            if(win_valid)begin
                gx_right <= win_data[0][2] + {win_data[1][2],1'b0} + win_data[2][2];
                gx_left <= win_data[0][0] + {win_data[1][0],1'b0} + win_data[2][0];
                gy_top <= win_data[2][0] + {win_data[2][1],1'b0} + win_data[2][2];
                gy_bottom <= win_data[0][0] + {win_data[0][1],1'b0} + win_data[0][2];
                valid_s1 <= 1;
                border_s1 <= win_is_border;
            end
            else begin
                gx_right <= 0;
                gx_left <= 0;
                gy_top <= 0;
                gy_bottom <= 0;
                valid_s1 <= 0;
                border_s1 <= 0;
            end
        end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)begin
            gx <= 0;
            gy <= 0;
            valid_s2 <= 0;
            border_s2 <= 0;
        end
        else begin
            if(valid_s1)begin
                gx <= gx_right - gx_left;
                gy <= gy_top - gy_bottom;
                border_s2 <= border_s1;
                valid_s2 <= 1;
            end
            else begin
                gx <= 0;
                gy <= 0;
                border_s2 <= 0;
                valid_s2 <= 0;
            end
        end
    end
    always_comb begin 
        abs_gx = (gx[10]) ? -gx : gx;
        abs_gy = (gy[10]) ? -gy : gy;
        mag = {1'b0, abs_gx} + {1'b0, abs_gy};
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)begin
            sobel_data <= 0;
            sobel_valid <= 0;
        end
        else begin
            sobel_valid <= valid_s2;
            if (valid_s2) begin
                 if (border_s2 || mag<threshold) begin
                    sobel_data <= 0;
                end
                 else if (mag>8'd255) begin
                    sobel_data <=8'd255;
                end
                 else begin
                    sobel_data <= mag;
                end
            end
            else begin
                sobel_data <= 0;
            end
        end 
    end

endmodule

                