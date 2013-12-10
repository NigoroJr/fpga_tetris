module SecTimer(clk, rst, sec);
    // Increments the `sec` every 10*10^6 clocks (0.2 sec)
    // Use 50MHz clock!
    input clk, rst;
    output reg [31:0] sec;
    reg [31:0] count;

    always @(posedge clk or negedge rst) begin
        if (rst == 1'b0) begin
            sec <= 3'b0;
            count <= 32'b0;
        end
        else begin
            if (count == 32'd10000000) begin
                sec <= sec + 1;
                count <= 32'b0;
            end
            else begin
                count <= count + 1'b1;
            end
        end
    end
endmodule
