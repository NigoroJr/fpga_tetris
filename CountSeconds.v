module CountSeconds(clk, rst, forceReset, seconds);
	input clk, rst, forceReset;
	inout reg [4:0] seconds;
	// Counter that counts 24 seconds
	always @(posedge clk or negedge rst) begin
		if (rst == 1'b0) begin
			seconds <= 5'b0;
		end
		else begin
			if (forceReset == 1'b1) begin
				seconds <= 5'b0;
			end
			else if (seconds == 5'd23) begin
				seconds <= 5'b0;
			end
			else begin
				seconds <= seconds + 1'b1;
			end
		end
	end
endmodule
