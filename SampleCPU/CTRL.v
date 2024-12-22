`include "lib/defines.vh"
module CTRL(
    input wire rst,
    // input wire stallreq_for_ex,
    // input wire stallreq_for_load,

    input wire stallreq_from_id,
    input wire stallreq_from_ex,

    // output reg flush,
    // output reg [31:0] new_pc,
    output reg [`StallBus-1:0] stall
);  

    //stall[0]为1表示没有暂停
    //stall[1]为1 if段暂停
    //stall[2]为1 id段暂停
    //stall[3]为1 ex段暂停
    //stall[4]为1 mem段暂停
    //stall[5]为1 wb段暂停

    always @ (*) begin
        if (rst) begin
            stall = `StallBus'b0;
        end
        // //id段若请求暂停，则暂停ex,mem,wb
        // else if(stallreq_from_ex == 1'b1) begin
        //     stall <= 6'b001111;
        // end
        // //ex段若请求暂停，则暂停mem,wb
        // else if(stallreq_from_id == 1'b1) begin
        //     stall <= 6'b000111;  
        // end
        else begin
            //stall = `StallBus'b0;  
            stall <= 6'b000000;
        end
    end
//在五级流水线每级结构中都应该有暂停相关部分
endmodule