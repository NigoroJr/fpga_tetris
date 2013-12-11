module SecTimer(clk, rst, sec, forceReset);
    // Increments the `sec` every 10*10^6 clocks (0.2 sec)
    // Use 50MHz clock!
    input clk, rst;
    input forceReset;
    output reg [31:0] sec;
    reg [31:0] count;

    always @(posedge clk or negedge rst) begin
        if (rst == 1'b0) begin
            sec <= 32'b0;
            count <= 32'b0;
        end
        else begin
            if (forceReset == 1'b1) begin
                sec <= 32'd0;
                count <= 32'b0;
            end
            else if (count == 32'd1000000) begin
                sec <= sec + 1;
                count <= 32'b0;
            end
            else begin
                count <= count + 1'b1;
            end
        end
    end
endmodule
