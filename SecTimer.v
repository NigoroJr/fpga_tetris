module SecTimer(clk, rst, sec, forceReset);
    // Outputs a 1 every 25*10^6 clocks (0.5 sec)
    // Use 50MHz clock!
    input clk, rst;
    input forceReset;
    output reg [2:0] sec;
    reg [31:0] count;

    always @(posedge clk or negedge rst) begin
        if (rst == 1'b0) begin
            sec <= 3'b0;
            count <= 32'b0;
        end
        else begin
            if (forceReset == 1'b1) begin
                sec <= 3'b0;
            end
            else if (count == 32'd25000000) begin
                sec <= sec + 1;
                count <= 32'b0;
            end
            else begin
                count <= count + 1'b1;
            end
        end
    end
endmodule
