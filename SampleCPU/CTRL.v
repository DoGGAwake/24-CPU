`include "lib/defines.vh"
module CTRL(git clone
    input wire rst,
    // input wire stallreq_for_ex,
    // input wire stallreq_for_load,

    // output reg flush,
    // output reg [31:0] new_pc,
    output reg [`StallBus-1:0] stall
);  
    always @ (*) begin
        if (rst) begin
            stall = `StallBus'b0;
        end
        else begin
            stall = `StallBus'b0;
        end
    end

endmodule