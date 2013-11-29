module MoveKey(key_push, out, RST);
    input key_push;
    output reg out;
    input RST;
    always @(posedge key_push or negedge RST) begin
        if (RST == 1'b0)
            out <= 1'b0;
        else
            out <= 1'b1;
    end
endmodule
