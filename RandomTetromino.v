module RandomTetromino(clk, rst, out);
    input clk, rst;
    reg [31:0] rand;
    output reg[2:0] out;
    
    always @(posedge clk or negedge rst) begin
        if (rst == 1'b0) begin
            out <= 3'b0;
            rand <= 32'h55555555;
        end
        else begin
            rand <= {
                rand[31:28],                // 4
                rand[27:25] ^ rand[5:3],    // 3
                rand[23],                   // 1
                rand[20] ^ rand[5],         // 1
                rand[24:18] ^ rand[12:6],   // 7
                rand[17:16] ^ rand[2:1],    // 2
                rand[8:4],                  // 5
                rand[3:0] ^ rand[15:12],    // 4
                rand[14:8] ^ rand[8:2]      // 6
            };
            out <= rand[26:24];
        end
    end
endmodule
