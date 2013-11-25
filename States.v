module States(x, y, r, g, b, S, NS);
input [9:0] x, y;
output [9:0] r, g, b;
input [3:0] S;
output [3:0] NS;
parameter   INIT = 4'd0,
            DRAW_BOARD = 4'd1,
            GENERATE = 4'd2,
            MOVE_ONE_DOWN = 4'd3;
            /*
            MOVE_LEFT = 4'd4,
            MOVE_RIGHT = 4'd5,
            SPIN_LEFT = 4'd6,
            HIT_BOTTOM = 4'd7,
            CHECK_COMPLETE_ROW = 4'd8,
            DELETE_ROW = 4'd9,
            SHIFT_ALL_BLOCKS_ABOVE = 4'd10,
            GAME_OVER = 4'd11;
            */
// End states

endmodule
