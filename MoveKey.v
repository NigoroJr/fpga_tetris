module MoveKey(key_push, out, clk, RST);
    input key_push;
    output reg out;
    input clk, RST;
    reg [31:0] counter;
    always @(posedge clk or negedge RST) begin
        if (RST == 1'b0) begin
            out <= 1'b0;
            counter <= 32'b0;
        end
        else begin
            if (key_push == 1'b1) begin
                // If it's less than 0.2 seconds from the last key press
                if (counter < 32'd10000000) begin
                    out <= 1'b0;
                    counter <= counter + 1'b1;
                end
                else begin
                    out <= 1'b1;
                    counter <= 1'b0;
                end
            end
            else begin
                out <= 1'b0;
                counter <= 1'b0;
            end
        end
    end
endmodule
