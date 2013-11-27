module SecTimer(clk, rst, sec);
	// Outputs a 1 every 25*10^6 clocks (0.5 sec)
    // Use 50MHz clock!
	input clk, rst;
	output reg sec;
	reg [31:0] count;

	always @(posedge clk or negedge rst) begin
		if (rst == 1'b0) begin
			sec <= 1'b0;
			count <= 32'b0;
		end
		else begin
			if (count == 32'd25000000) begin
				sec <= 1'b1;
				count <= 32'b0;
			end
			else begin
				sec <= 1'b0;
				count <= count + 1'b1;
			end
		end
	end
endmodule
