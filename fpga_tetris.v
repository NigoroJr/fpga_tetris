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

// draw_? are decided at the very end of this file
reg [3:0] draw_r, draw_g, draw_b;
assign mVGA_R = {draw_r, 6'b0};
assign mVGA_G = {draw_g, 6'b0};
assign mVGA_B = {draw_b, 6'b0};

parameter   INIT = 4'd0,
            GENERATE = 4'd1,
            MOVE_ONE_DOWN = 4'd2;
            /*
            MOVE_LEFT = 4'd3,
            MOVE_RIGHT = 4'd4,
            SPIN_LEFT = 4'd5,
            HIT_BOTTOM = 4'd6,
            CHECK_COMPLETE_ROW = 4'd7,
            DELETE_ROW = 4'd8,
            SHIFT_ALL_BLOCKS_ABOVE = 4'd9,
            GAME_OVER = 4'd10;
            */
parameter I = 3'd0,
          O = 3'd1,
          L = 3'd2,
          J = 3'd3,
          S = 3'd4,
          Z = 3'd5,
          T = 3'd6;
// Colors (TODO: change name because it's confusing)
parameter black = 4'h0,
          white = 4'hf;
reg [3:0] r, g, b;
reg [3:0] STATE;

/*---- SRAM stuff ----*/
// 1 when disabled, 0 when enabled
wire we;
// 1 when overwriting (such as generating new Tetromino)
reg overwrite;
// For dev purpose
assign we = 1'b0;
assign SRAM_LB_N = 0;
assign SRAM_OE_N = 0;
assign SRAM_UB_N = 0;
assign SRAM_DQ = we ? 16'hzzzz : {r, g, b, 4'b0};
assign SRAM_ADDR = overwrite ? {x, y, 8'b0} : {read_x, read_y, 8'b0};
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
wire [4:0] read_x, read_y;
assign read_x = (mCoord_X - 220) / 20;
assign read_y = (mCoord_Y - 20) / 20;
reg [4:0] x, y, tetromino_x, tetromino_y;
reg [2:0] current_tetromino;
// Iterate through 0-3 to draw Tetrominos
reg [1:0] draw_tetromino_count;
// Calculate next state
always @(posedge VGA_CTRL_CLK or negedge RST) begin
    if (RST == 1'b0) begin
        STATE <= INIT;
    end
    else begin
    case (STATE)
        INIT: begin
            if (gameStarted == 1'b1) begin
                // Prepare for GENERATE state and change state
                // TODO: get random number
                current_tetromino = I;
                draw_tetromino_count <= 2'd0;
                STATE <= GENERATE;
            end
            else begin
                STATE <= INIT;
            end
        end
        GENERATE: begin
            overwrite = 1'b1;
            // Go to next state when finished drawing
            if (draw_tetromino_count == 2'd3) begin
                draw_tetromino_count <= 2'd0;
                STATE <= MOVE_ONE_DOWN;
            end
            // Draw Tetromino
            case (current_tetromino)
                I: begin
                    // Cyan
                    r = black;
                    g = white;
                    b = white;
                    tetromino_x = 5'd4;
                    tetromino_y = 5'd0;
                    case (draw_tetromino_count)
                        2'd0: begin
                            x = tetromino_x;
                            y = tetromino_y;
                        end
                        2'd1: begin
                            x = tetromino_x;
                            y = tetromino_y + 1;
                        end
                        2'd2: begin
                            x = tetromino_x;
                            y = tetromino_y + 2;
                        end
                        2'd3: begin
                            x = tetromino_x;
                            y = tetromino_y + 3;
                        end
                    endcase
                end
                O: begin
                    // Yellow
                    r = white;
                    g = white;
                    b = black;
                end
                L: begin
                    // Orange
                    r = white;
                    g = 4'd165;
                    b = black;
                end
                J: begin
                    // Blue
                    r = black;
                    g = black;
                    b = white;
                end
                S: begin
                    // Green
                    r = black;
                    g = white;
                    b = black;
                end
                Z:begin
                    // Red
                    r = white;
                    g = black;
                    b = black;
                end
                T: begin
                    // Purple
                    r = white;
                    g = black;
                    b = white;
                end
            endcase
        end
    endcase
    end
end

// Show content on SRAM
always @(*) begin
    // Paint in black if it's outside the field
    if ((mCoord_X < 220 || (mCoord_X >= 420 && mCoord_X < 640))
        // 60 not 20 because the first 2 "grids" are not shown
        || (mCoord_Y < 60 || (mCoord_Y >= 460 && mCoord_Y < 480))) begin
        draw_r = black;
        draw_g = black;
        draw_b = black;
    end
    // Otherwise, show content of SRAM at that address
    else begin
        draw_r = SRAM_DQ[15:12];
        draw_g = SRAM_DQ[11:8];
        draw_b = SRAM_DQ[7:4];
    end
end

endmodule
