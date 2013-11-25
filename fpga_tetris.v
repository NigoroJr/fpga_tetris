module fpga_tetris(
// Clock Input
  input CLOCK_50,    // 50 MHz
  input CLOCK_27,     // 27 MHz
// Push Button
  input [3:0] KEY,      // Pushbutton[3:0]
// DPDT Switch
  input [17:0] SW,        // Toggle Switch[17:0]
// 7-SEG Display
  output [6:0] HEX0,HEX1,HEX2,HEX3,HEX4,HEX5,HEX6,HEX7,  // Seven Segment Digits
// LED
  output [8:0] LEDG,  // LED Green[8:0]
  output [17:0] LEDR,  // LED Red[17:0]
// GPIO
 inout [35:0] GPIO_0,GPIO_1,    // GPIO Connections
// TV Decoder
//TD_DATA,        //    TV Decoder Data bus 8 bits
//TD_HS,        //    TV Decoder H_SYNC
//TD_VS,        //    TV Decoder V_SYNC
  output TD_RESET,    //    TV Decoder Reset
// VGA
  output VGA_CLK,                         // VGA Clock
  output VGA_HS,                          // VGA H_SYNC
  output VGA_VS,                          // VGA V_SYNC
  output VGA_BLANK,                       // VGA BLANK
  output VGA_SYNC,                        // VGA SYNC
  output [9:0] VGA_R,                     // VGA Red[9:0]
  output [9:0] VGA_G,                     // VGA Green[9:0]
  output [9:0] VGA_B,                     // VGA Blue[9:0]
  
  inout [15:0] SRAM_DQ,
  output [17:0] SRAM_ADDR,
  output SRAM_UB_N,
  output SRAM_LB_N,
  output SRAM_WE_N,
  output SRAM_CE_N,
  output SRAM_OE_N
);

// All inout port turn to tri-state
assign    GPIO_0        =    36'hzzzzzzzzz;
assign    GPIO_1        =    36'hzzzzzzzzz;

wire RST;
assign RST = KEY[0];

// reset delay gives some time for peripherals to initialize
wire DLY_RST;
Reset_Delay r0(    .iCLK(CLOCK_50),.oRESET(DLY_RST) );

// Send switches to red leds 
assign LEDR = SW;

// Turn off green leds
assign LEDG = 8'h00;

wire [6:0] blank = 7'b111_1111;

// blank unused 7-segment digits
assign HEX0 = blank;
assign HEX1 = blank;
assign HEX2 = blank;
assign HEX3 = blank;
assign HEX4 = blank;
assign HEX5 = blank;
assign HEX6 = blank;
assign HEX7 = blank;

wire        VGA_CTRL_CLK;
wire        AUD_CTRL_CLK;
wire [9:0]    mVGA_R;
wire [9:0]    mVGA_G;
wire [9:0]    mVGA_B;
wire [9:0]    mCoord_X;
wire [9:0]    mCoord_Y;

assign    TD_RESET = 1'b1; // Enable 27 MHz

VGA_Audio_PLL     p1 (    
    .areset(~DLY_RST),
    .inclk0(CLOCK_27),
    .c0(VGA_CTRL_CLK),
    .c1(AUD_CTRL_CLK),
    .c2(VGA_CLK)
);


vga_sync u1(
   .iCLK(VGA_CTRL_CLK),
   .iRST_N(DLY_RST&KEY[0]),    
   .iRed(mVGA_R),
   .iGreen(mVGA_G),
   .iBlue(mVGA_B),
   // pixel coordinates
   .px(mCoord_X),
   .py(mCoord_Y),
   // VGA Side
   .VGA_R(VGA_R),
   .VGA_G(VGA_G),
   .VGA_B(VGA_B),
   .VGA_H_SYNC(VGA_HS),
   .VGA_V_SYNC(VGA_VS),
   .VGA_SYNC(VGA_SYNC),
   .VGA_BLANK(VGA_BLANK)
);

assign mVGA_R = {r, 6'b0};
assign mVGA_G = {g, 6'b0};
assign mVGA_B = {b, 6'b0};

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
// Colors (TODO: change name because it's confusing)
parameter black = 4'h0,
          white = 4'hf;
reg [3:0] r, g, b;
reg [3:0] S, NS;

/*---- SRAM stuff ----*/
// 0 when enabled, 1 when disabled
reg we;
// For dev purpose
assign we = 1'b1;
assign SRAM_LB_N = 0;
assign SRAM_OE_N = 0;
assign SRAM_UB_N = 0;
assign SRAM_DQ = we ? 16'hzzzz : {r, g, b, 4'b0};
assign SRAM_ADDR = {x, y, 8'b0};
assign SRAM_WE_N = we;

/*---- Control variables ----*/
wire gameStarted;
assign gameStarted = SW[0];

// Use the coordinates and see the field as grids of 10px by 10px
/*
    |<-220->|
    +------------------+
    |       +--+       |
    |       |  |       |
    |       +--+       |
    +------------------+
*/
// These are something like 2-dimensional arrays
wire [4:0] x, y;
assign x = (mCoord_X - 220) / 10;
assign y = (mCoord_Y - 20) / 10;
// Calculate next state
always @(*) begin
    case (S)
        INIT: begin
            if (gameStarted == 1'b1) begin
                NS = DRAW_BOARD;
            end
            else begin
                NS = INIT;
            end
        end
        DRAW_BOARD: begin
            
        end
    endcase
end

// What to show on screen for each state (technically, write to SRAM)
always @(*) begin
    // Paint in black if it's outside the field
    if ((mCoord_X < 220 || (mCoord_X >= 420 && mCoord_X < 640)) || (mCoord_Y < 20 || (mCoord_Y >= 460 && mCoord_Y < 480))) begin
        r = black;
        g = black;
        b = black;
    end
    else begin
        case (S)
            INIT: begin
                r = black;
                g = black;
                b = black;
            end
        endcase
    end
end

// Change states
always @(posedge VGA_CTRL_CLK or negedge RST) begin
    if (RST == 1'b0) begin
        S <= INIT;
    end
    else begin
        S <= NS;
    end
end

endmodule
