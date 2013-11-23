module Timer(clk, rst, count, keep, max);
	// Outputs a 1 every 50*10^6 clocks (= second)
	input clk, rst;
	inout reg [31:0] keep;
	output reg [31:0] count;
	input [31:0] max;

	always @(posedge clk or negedge rst) begin
		if (rst == 1'b0) begin
			count <= 32'b0;
			keep <= 32'b0;
		end
		else begin
			if (keep == max) begin
				count = count + 1'b1;
				keep <= 32'b0;
			end
			else begin
				keep <= keep + 1'b1;
			end
		end
	end
endmodule
