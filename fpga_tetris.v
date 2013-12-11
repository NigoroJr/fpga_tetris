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
  output reg [17:0] LEDR,  // LED Red[17:0]
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
assign GPIO_0 = 36'hzzzzzzzzz;
assign GPIO_1 = 36'hzzzzzzzzz;

wire RST;
assign RST = KEY[0];

// reset delay gives some time for peripherals to initialize
wire DLY_RST;
Reset_Delay r0( .iCLK(CLOCK_50),.oRESET(DLY_RST) );

// Send switches to red leds 
//assign LEDR = SW;

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
wire [9:0]  mVGA_R;
wire [9:0]  mVGA_G;
wire [9:0]  mVGA_B;
wire [9:0]  mCoord_X;
wire [9:0]  mCoord_Y;

assign TD_RESET = 1'b1; // Enable 27 MHz

VGA_Audio_PLL   p1 (
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
/*  Notes
    ---------------------------------------------------
    Idea:
    Add a variable called PREVIOUS_STATE and check which state "called" the current state.
    This variable can be used to determine whether it's the first iteration in this state or not.
    e.g. If the previous state was something else, initialize variables with 0 and set prev state
    to this state, else, do counting or whatever you want to do.
*/
wire SEC_CLK;
reg [31:0] sec;
reg forceReset;
SecTimer secondClock(CLOCK_50, RST, sec, forceReset);

// draw_? are decided at the very end of this file
reg [3:0] draw_r, draw_g, draw_b;
assign mVGA_R = {draw_r, 6'b0};
assign mVGA_G = {draw_g, 6'b0};
assign mVGA_B = {draw_b, 6'b0};

parameter   INIT = 5'd0,
            GENERATE = 5'd1,
            SET_COLOR = 5'd2,
            WRITE_TO_SRAM = 5'd3,
            WAIT = 5'd4,
            REMOVE_COLOR = 5'd5,
            CHECK_IF_MOVABLE = 5'd6,
            MOVE_ONE_DOWN = 5'd7,
            MOVE_LEFT = 5'd8,
            MOVE_RIGHT = 5'd9,
            SPIN_LEFT = 5'd10,
            CHECK_COMPLETE_ROW = 5'd11,
            DELETE_ROW = 5'd12,
            SHIFT_ALL_BLOCKS_ABOVE = 5'd13,
            SHIFT_BLOCKS_READ_ABOVE = 5'd14,
            SHIFT_BLOCKS_WRITE_TO_CURRENT = 5'd15,
            GAME_OVER = 5'd16,
            DECREMENT_SHIFT_COUNT_Y = 5'd17,
            INCREMENT_SHIFT_COUNT_X = 5'd18,
            INCREMENT_DRAW_COUNT = 5'd19,
            COLOR_READ_BUFFER = 5'd20,
            CHECK_BUFFER = 5'd21;
// Each Tetromino has a name
parameter I = 3'd0,
          O = 3'd1,
          L = 3'd2,
          J = 3'd3,
          S = 3'd4,
          Z = 3'd5,
          T = 3'd6;
// Colors
parameter BLACK     = 16'h0000,
          WHITE     = 16'h0fff,
          CYAN      = 16'h00ff,
          YELLOW    = 16'h0ff0,
          ORANGE    = 16'h0fa0,
          BLUE      = 16'h000f,
          GREEN     = 16'h00f0,
          RED       = 16'h0f00,
          PURPLE    = 16'h0f0f;
// Type of movability check
parameter NONE      = 3'd0,
          DOWN      = 3'd1,
          LEFT      = 3'd2,
          RIGHT     = 3'd3,
          SPIN_L    = 3'd4;
// Represents the state for FSM
reg [4:0] STATE;
// Represents the state of rotation
reg [1:0] spin_state;
parameter   ORIG = 2'd0,
            L_1	= 2'd1,
            L_2	= 2'd2,
            L_3	= 2'd3;

/*---- SRAM stuff ----*/
// 1 when disabled, 0 when enabled (all the other boolean variables will follow the "common-sense")
reg we;
// 1 when enabled, 0 when disabled
reg isReadColor;
reg [15:0] color;
// Color that was read from the SRAM at address read_x, read_y
wire [15:0] color_read;
assign color_read = isReadColor ? SRAM_DQ : 16'h0000;
assign SRAM_DQ = we ? 16'hzzzz : color;
assign SRAM_ADDR = we ? (isReadColor ? {read_x, read_y, 6'b0} : {grid_x, grid_y, 6'b0}) : {x, y, 6'b0};
assign SRAM_WE_N = we;
assign SRAM_LB_N = 0;
assign SRAM_OE_N = 0;
assign SRAM_UB_N = 0;

/*---- Control variables ----*/
wire gameStarted;
assign gameStarted = SW[0];
wire move_left_key, move_right_key, spin_left_key;
MoveKey toLeft(~KEY[3], move_left_key, CLOCK_50, RST);
MoveKey toRight(~KEY[1], move_right_key, CLOCK_50, RST);
MoveKey toSpinLeft(~KEY[2], spin_left_key, CLOCK_50, RST);
// Generate random tetromino every clock
RandomTetromino rand(CLOCK_50, RST, random_tetromino);
/*
    Use the coordinates and see the field as grids of 20px by 20px
    |<-220->|
    +------------------+
    |       +--+       |
    |       |  |       |
    |       +--+       |
    +------------------+
*/
// These are something like 2-dimensional arrays. Used when reading from SRAM.
// read_? are used when you want to read something at a certain address
wire [5:0] grid_x, grid_y;
assign grid_x = (mCoord_X - 220) / 20;
assign grid_y = (mCoord_Y - 20) / 20;
// Coordinates used when writing to SRAM
reg [5:0] x, y, read_x, read_y, shift_count_x, shift_count_y, deleted_row;
reg [5:0] tetromino_x, tetromino_y;
reg [2:0] current_tetromino;
wire [2:0] random_tetromino;
// Iterate through 0-3 to draw Tetrominoes
reg [2:0] draw_tetromino_count;
// Indicates whether the Tetromino was erased or not (i.e. just drawn)
reg erased, request_erase;
// Type of check that was requested
reg [2:0] requestMovableCheck;
// 1 if movable, 0 if not
reg isMovable;
// Something similar to draw_tetromino_count but used for checking
reg [2:0] check_movable_count;
// Used to initialize the SRAM
reg [5:0] init_x, init_y;
// Calculate next state
always @(posedge VGA_CTRL_CLK or negedge RST) begin
    if (RST == 1'b0) begin
        // The following have to be initialized here because it will be used in INIT state
        init_x <= 6'd0;
        init_y <= 6'd0;
        isReadColor <= 1'b0;
        requestMovableCheck <= 3'd0;
        isMovable <= 1'b1;
        forceReset <= 1'b0;
        STATE <= INIT;
    end
    else begin
    case (STATE)
        INIT: begin
            if (gameStarted == 1'b1 && init_y == 6'd22) begin
                we <= 1'b1;
                init_x <= 6'd0;
                init_y <= 6'd0;
                // Prepare for GENERATE state and change state
                draw_tetromino_count <= 3'd0;
                STATE <= GENERATE;
            end
            else begin
                we <= 1'b0;
                // Initialize field with white
                color <= WHITE;
                x <= init_x;
                y <= init_y;
                STATE <= INIT;
                if (init_x == 6'd10) begin
                    init_x <= 6'd0;
                    init_y <= init_y + 1;
                end
                else begin
                    init_x <= init_x + 1;
                end
            end
        end
        GENERATE: begin
            spin_state <= ORIG;
            we <= 1'b1;
            //current_tetromino <= SW[17:15];
            current_tetromino <= random_tetromino % 7;
            // Set appearing position
            tetromino_x <= 6'd3;
            tetromino_y <= 6'd1;
            STATE <= SET_COLOR;
        end
        SET_COLOR: begin
            we <= 1'b1;
            // Tell WRITE_TO_SRAM that we drew the Tetromino
            erased <= 1'b0;
            STATE <= WRITE_TO_SRAM;
            // Don't forget to initialize (another place is in REMOVE_COLOR)
            //draw_tetromino_count <= 3'd0;
            case (current_tetromino)
                I: color <= CYAN;
                O: color <= YELLOW;
                L: color <= ORANGE;
                J: color <= BLUE;
                S: color <= GREEN;
                Z: color <= RED;
                T: color <= PURPLE;
            endcase
        end
        WRITE_TO_SRAM: begin
            /*  +----------------------------------------------------------------------------------+
                | Important!!                                                                      |
                | This state requires the `color` to be set in the previous state.                 |
                | It was designed like this so that this state can be used both to draw and erase. |
                +----------------------------------------------------------------------------------+ */
            // Go to next state when finished drawing
            if (draw_tetromino_count == 3'd4) begin
                // Disable write
                we <= 1'b1;
                draw_tetromino_count <= 3'd0;
                // If the state was "called" by the REMOVE_COLOR state
                if (request_erase == 1'b1) begin
                    STATE <= REMOVE_COLOR;
                    erased <= 1'b1;
                    // Note: request_erase is reset in REMOVE_COLOR state
                end
                // When it came from the SET_COLOR state
                else begin
                    STATE <= WAIT;
                end
            end
            else begin
                // Enable write
                we <= 1'b0;
                //STATE <= WRITE_TO_SRAM;
                //draw_tetromino_count <= draw_tetromino_count + 1;
                STATE <= INCREMENT_DRAW_COUNT;
                // Draw Tetromino based on pivot
                case (current_tetromino)
                    I: begin
                        case (spin_state % 2)
                            ORIG: begin
                                case (draw_tetromino_count)
                                    3'd0: begin
                                        x <= tetromino_x;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd1: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd2: begin
                                        x <= tetromino_x + 2;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd3: begin
                                        x <= tetromino_x + 3;
                                        y <= tetromino_y + 1;
                                    end
                                endcase
                            end
                            L_1: begin
                                case (draw_tetromino_count)
                                    3'd0: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y;
                                    end
                                    3'd1: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd2: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 2;
                                    end
                                    3'd3: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 3;
                                    end
                                endcase
                            end
                        endcase
                    end
                    O: begin
                        // Doesn't change according to the spin state
                        case (draw_tetromino_count)
                            3'd0: begin
                                x <= tetromino_x + 1;
                                y <= tetromino_y;
                            end
                            3'd1: begin
                                x <= tetromino_x + 1;
                                y <= tetromino_y + 1;
                            end
                            3'd2: begin
                                x <= tetromino_x + 2;
                                y <= tetromino_y;
                            end
                            3'd3: begin
                                x <= tetromino_x + 2;
                                y <= tetromino_y + 1;
                            end
                        endcase
                   end
                    L: begin
                        case (spin_state)
                            ORIG: begin
                                case (draw_tetromino_count)
                                    3'd0: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y;
                                    end
                                    3'd1: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd2: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 2;
                                    end
                                    3'd3: begin
                                        x <= tetromino_x + 2;
                                        y <= tetromino_y + 2;
                                    end
                                endcase
                            end
                            L_1: begin
                                case (draw_tetromino_count)
                                    3'd0: begin
                                        x <= tetromino_x;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd1: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd2: begin
                                        x <= tetromino_x + 2;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd3: begin
                                        x <= tetromino_x + 2;
                                        y <= tetromino_y;
                                    end
                                endcase
                            end
                            L_2: begin
                                case (draw_tetromino_count)
                                    3'd0: begin
                                        x <= tetromino_x;
                                        y <= tetromino_y;
                                    end
                                    3'd1: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y;
                                    end
                                    3'd2: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd3: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 2;
                                    end
                                endcase
                            end
                            L_3: begin
                                case (draw_tetromino_count)
                                    3'd0: begin
                                        x <= tetromino_x;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd1: begin
                                        x <= tetromino_x;
                                        y <= tetromino_y + 2;
                                    end
                                    3'd2: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd3: begin
                                        x <= tetromino_x + 2;
                                        y <= tetromino_y + 1;
                                    end
                                endcase
                            end
                        endcase
                    end
                    J: begin
                        case (spin_state)
                            ORIG: begin
                                case (draw_tetromino_count)
                                    3'd0: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y;
                                    end
                                    3'd1: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd2: begin
                                        x <= tetromino_x;
                                        y <= tetromino_y + 2;
                                    end
                                    3'd3: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 2;
                                    end
                                endcase
                            end
                            L_1: begin
                                case (draw_tetromino_count)
                                    3'd0: begin
                                        x <= tetromino_x;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd1: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd2: begin
                                        x <= tetromino_x + 2;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd3: begin
                                        x <= tetromino_x + 2;
                                        y <= tetromino_y + 2;
                                    end
                                endcase
                            end
                            L_2: begin
                                case (draw_tetromino_count)
                                    3'd0: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y;
                                    end
                                    3'd1: begin
                                        x <= tetromino_x + 2;
                                        y <= tetromino_y;
                                    end
                                    3'd2: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd3: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 2;
                                    end
                                endcase
                            end
                            L_3: begin
                                case (draw_tetromino_count)
                                    3'd0: begin
                                        x <= tetromino_x;
                                        y <= tetromino_y;
                                    end
                                    3'd1: begin
                                        x <= tetromino_x;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd2: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd3: begin
                                        x <= tetromino_x + 2;
                                        y <= tetromino_y + 1;
                                    end
                                endcase
                            end
                        endcase
                    end
                    S: begin
                        case (spin_state % 2)
                            ORIG: begin
                                case (draw_tetromino_count)
                                    3'd0: begin
                                        x <= tetromino_x;
                                        y <= tetromino_y + 2;
                                    end
                                    3'd1: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 2;
                                    end
                                    3'd2: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd3: begin
                                        x <= tetromino_x + 2;
                                        y <= tetromino_y + 1;
                                    end
                                endcase
                            end
                            L_1: begin
                                case (draw_tetromino_count)
                                    3'd0: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y;
                                    end
                                    3'd1: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd2: begin
                                        x <= tetromino_x + 2;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd3: begin
                                        x <= tetromino_x + 2;
                                        y <= tetromino_y + 2;
                                    end
                                endcase
                            end
                        endcase
                    end
                    Z: begin
                        case (spin_state % 2)
                            ORIG: begin
                                case (draw_tetromino_count)
                                    3'd0: begin
                                        x <= tetromino_x;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd1: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd2: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 2;
                                    end
                                    3'd3: begin
                                        x <= tetromino_x + 2;
                                        y <= tetromino_y + 2;
                                    end
                                endcase
                            end
                            L_1: begin
                                case (draw_tetromino_count)
                                    3'd0: begin
                                        x <= tetromino_x;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd1: begin
                                        x <= tetromino_x;
                                        y <= tetromino_y + 2;
                                    end
                                    3'd2: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd3: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y;
                                    end
                                endcase
                            end
                        endcase
                    end
                    T: begin
                        case (spin_state)
                            ORIG: begin
                                case (draw_tetromino_count)
                                    3'd0: begin
                                        x <= tetromino_x;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd1: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y;
                                    end
                                    3'd2: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd3: begin
                                        x <= tetromino_x + 2;
                                        y <= tetromino_y + 1;
                                    end
                                endcase
                            end
                            L_1: begin
                                case (draw_tetromino_count)
                                    3'd0: begin
                                        x <= tetromino_x;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd1: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y;
                                    end
                                    3'd2: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd3: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 2;
                                    end
                                endcase
                            end
                            L_2: begin
                                case (draw_tetromino_count)
                                    3'd0: begin
                                        x <= tetromino_x;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd1: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd2: begin
                                        x <= tetromino_x + 2;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd3: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 2;
                                    end
                                endcase
                            end
                            L_3: begin
                                case (draw_tetromino_count)
                                    3'd0: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y;
                                    end
                                    3'd1: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 1;
                                    end
                                    3'd2: begin
                                        x <= tetromino_x + 1;
                                        y <= tetromino_y + 2;
                                    end
                                    3'd3: begin
                                        x <= tetromino_x + 2;
                                        y <= tetromino_y + 1;
                                    end
                                endcase
                            end
                        endcase
                    end
                endcase
            end
        end // End of WRITE_TO_SRAM
        INCREMENT_DRAW_COUNT: begin
            we <= 1'b1;
            isReadColor <= 1'b0;
            draw_tetromino_count <= draw_tetromino_count + 1;
            STATE <= WRITE_TO_SRAM;
        end
        WAIT: begin
            we <= 1'b1;

            if (sec < 3'd1) begin
                // Move when there was key input
                if (move_left_key == 1'b1) begin
                    requestMovableCheck <= LEFT;
                    check_movable_count <= 3'd0;
                    isMovable <= 1'b1;
                    STATE <= CHECK_IF_MOVABLE;
                end
                else if (move_right_key == 1'b1) begin
                    requestMovableCheck <= RIGHT;
                    check_movable_count <= 3'd0;
                    isMovable <= 1'b1;
                    STATE <= CHECK_IF_MOVABLE;
                end
                else if (spin_left_key == 1'b1) begin
                    requestMovableCheck <= SPIN_L;
                    check_movable_count <= 3'd0;
                    isMovable <= 1'b1;
                    STATE <= CHECK_IF_MOVABLE;
                end
                else begin
                    STATE <= WAIT;
                end
            end
            // When it waited for a certain amount of time
            else begin
                requestMovableCheck <= DOWN;
                isMovable <= 1'b1;
                forceReset <= 1'b1;
                STATE <= CHECK_IF_MOVABLE;
            end
        end
        /*  Checks if the Tetromino can really move to the next grid
            TODO: Add explanation of how this works
        */
        CHECK_IF_MOVABLE: begin
            /*  Variables:
                    Type of request => requestMovableCheck
                    Result set to   => isMovable
                    Counter         => check_movable_count
                    SRAM content    => color_read
                    Specify address => read_x, read_y

                Important
                    Make sure to consider the overlap when spinning!
            */

            forceReset <= 1'b0;
            we <= 1'b1;
            if (isMovable == 1'b0) begin
                // Reset isMovable to 1 (movable)
                isMovable <= 1'b1;
                // If it couldn't move downward anymore
                if (requestMovableCheck == DOWN) begin
                    STATE <= CHECK_COMPLETE_ROW;
                    read_x <= 6'd0;
                    read_y <= 6'd22;
                end
                // If LEFT, RIGHT, or SPIN_L was requested and wasn't approved, go back and wait
                else begin
                    STATE <= WAIT;
                end
            end
            else if (check_movable_count == 3'd4) begin
                // Reset counter
                //check_movable_count <= 3'd0;
                isReadColor <= 1'b0;
                // Request was approved
                STATE <= REMOVE_COLOR;
            end
            else begin
                we <= 1'b1;
                // Important in order to *read* from SRAM
                isReadColor <= 1'b1;
                STATE <= CHECK_BUFFER;
                case (current_tetromino)
                    I: begin
                        case (spin_state % 2)
                            ORIG: begin
                                case (requestMovableCheck)
                                    DOWN: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd3: begin
                                                read_x <= tetromino_x + 3;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    LEFT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x - 1;
                                                read_y <= tetromino_y + 1;
                                            end
                                        endcase
                                    end
                                    RIGHT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 4;
                                                read_y <= tetromino_y + 1;
                                            end
                                        endcase
                                    end
                                    SPIN_L: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 3;
                                            end
                                        endcase
                                    end
                                endcase
                            end
                            L_1: begin
                                case (requestMovableCheck)
                                    DOWN: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 4;
                                            end
                                        endcase
                                    end
                                    LEFT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd3: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 3;
                                            end
                                        endcase
                                    end
                                    RIGHT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd3: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 3;
                                            end
                                        endcase
                                    end
                                    SPIN_L: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 3;
                                                read_y <= tetromino_y + 1;
                                            end
                                        endcase
                                    end
                                endcase
                            end
                        endcase
                    end // End of I
                    O: begin
                        case (requestMovableCheck)
                            DOWN: begin
                                case (check_movable_count)
                                    3'd0: begin
                                        read_x <= tetromino_x + 1;
                                        read_y <= tetromino_y + 2;
                                    end
                                    3'd1: begin
                                        read_x <= tetromino_x + 2;
                                        read_y <= tetromino_y + 2;
                                    end
                                endcase
                            end
                            LEFT: begin
                                case (check_movable_count)
                                    3'd0: begin
                                        read_x <= tetromino_x;
                                        read_y <= tetromino_y;
                                    end
                                    3'd1: begin
                                        read_x <= tetromino_x;
                                        read_y <= tetromino_y + 1;
                                    end
                                endcase
                            end
                            RIGHT: begin
                                case (check_movable_count)
                                    3'd0: begin
                                        read_x <= tetromino_x + 3;
                                        read_y <= tetromino_y;
                                    end
                                    3'd1: begin
                                        read_x <= tetromino_x + 3;
                                        read_y <= tetromino_y + 1;
                                    end
                                endcase
                            end
                            SPIN_L: begin
                                // No spin movement because it doesn't change anything
                            end
                        endcase
                    end // End of O
                    L: begin
                        case (spin_state)
                            ORIG: begin
                                case (requestMovableCheck)
                                    DOWN: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 3;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 3;
                                            end
                                        endcase
                                    end
                                    LEFT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    RIGHT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 3;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    SPIN_L: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y;
                                            end
                                        endcase
                                    end
                                endcase
                            end
                            L_1: begin
                                case (requestMovableCheck)
                                    DOWN: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    LEFT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x - 1;
                                                read_y <= tetromino_y + 1;
                                            end
                                        endcase
                                    end
                                    RIGHT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 3;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 3;
                                                read_y <= tetromino_y + 1;
                                            end
                                        endcase
                                    end
                                    SPIN_L: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                endcase
                            end
                            L_2: begin
                                case (requestMovableCheck)
                                    DOWN: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 3;
                                            end
                                        endcase
                                    end
                                    LEFT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x - 1;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    RIGHT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    SPIN_L: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 1;
                                            end
                                        endcase
                                    end
                                endcase
                            end
                            L_3: begin
                                case (requestMovableCheck)
                                    DOWN: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 3;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    LEFT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x - 1;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x - 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    RIGHT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 3;
                                                read_y <= tetromino_y + 1;
                                            end
                                        endcase
                                    end
                                    SPIN_L: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                endcase
                            end
                        endcase
                    end // End of L
                    J: begin
                        case (spin_state)
                            ORIG: begin
                                case (requestMovableCheck)
                                    DOWN: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 3;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 3;
                                            end
                                        endcase
                                    end
                                    LEFT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x - 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    RIGHT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    SPIN_L: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                endcase
                            end
                            L_1: begin
                                case (requestMovableCheck)
                                    DOWN: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 3;
                                            end
                                        endcase
                                    end
                                    LEFT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x - 1;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    RIGHT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 3;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 3;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    SPIN_L: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                endcase
                            end
                            L_2: begin
                                case (requestMovableCheck)
                                    DOWN: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 3;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 1;
                                            end
                                        endcase
                                    end
                                    LEFT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    RIGHT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 3;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    SPIN_L: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 1;
                                            end
                                        endcase
                                    end
                                endcase
                            end
                            L_3: begin
                                case (requestMovableCheck)
                                    DOWN: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    LEFT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x - 1;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x - 1;
                                                read_y <= tetromino_y + 1;
                                            end
                                        endcase
                                    end
                                    RIGHT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 3;
                                                read_y <= tetromino_y + 1;
                                            end
                                        endcase
                                    end
                                    SPIN_L: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                endcase
                            end
                        endcase
                    end // End of J
                    S: begin
                        case (spin_state % 2)
                            ORIG: begin
                                case (requestMovableCheck)
                                    DOWN: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 3;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 3;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    LEFT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x - 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    RIGHT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 3;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    SPIN_L: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                endcase
                            end
                            L_1: begin
                                case (requestMovableCheck)
                                    DOWN: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 3;
                                            end
                                        endcase
                                    end
                                    LEFT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    RIGHT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 3;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 3;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    SPIN_L: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                endcase
                            end
                        endcase
                    end // End of S
                    Z: begin
                        case (spin_state % 2)
                            ORIG: begin
                                case (requestMovableCheck)
                                    DOWN: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 3;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 3;
                                            end
                                        endcase
                                    end
                                    LEFT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x - 1;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    RIGHT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 3;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    SPIN_L: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                endcase
                            end
                            L_1: begin
                                case (requestMovableCheck)
                                    DOWN: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 3;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    LEFT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x - 1;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x - 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    RIGHT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    SPIN_L: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                endcase
                            end
                        endcase
                    end // End of Z
                    T: begin
                        case (spin_state)
                            ORIG: begin
                                case (requestMovableCheck)
                                    DOWN: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    LEFT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x - 1;
                                                read_y <= tetromino_y + 1;
                                            end
                                        endcase
                                    end
                                    RIGHT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 3;
                                                read_y <= tetromino_y + 1;
                                            end
                                        endcase
                                    end
                                    SPIN_L: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                endcase
                            end
                            L_1: begin
                                case (requestMovableCheck)
                                    DOWN: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 3;
                                            end
                                        endcase
                                    end
                                    LEFT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x - 1;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    RIGHT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    SPIN_L: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 1;
                                            end
                                        endcase
                                    end
                                endcase
                            end
                            L_2: begin
                                case (requestMovableCheck)
                                    DOWN: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 3;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    LEFT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x - 1;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    RIGHT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 3;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    SPIN_L: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y;
                                            end
                                        endcase
                                    end
                                endcase
                            end
                            L_3: begin
                                case (requestMovableCheck)
                                    DOWN: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 1;
                                                read_y <= tetromino_y + 3;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    LEFT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 2;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 3;
                                            end
                                        endcase
                                    end
                                    RIGHT: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y;
                                            end
                                            3'd1: begin
                                                read_x <= tetromino_x + 3;
                                                read_y <= tetromino_y + 1;
                                            end
                                            3'd2: begin
                                                read_x <= tetromino_x + 2;
                                                read_y <= tetromino_y + 2;
                                            end
                                        endcase
                                    end
                                    SPIN_L: begin
                                        case (check_movable_count)
                                            3'd0: begin
                                                read_x <= tetromino_x;
                                                read_y <= tetromino_y + 1;
                                            end
                                        endcase
                                    end
                                endcase
                            end
                        endcase
                    end // End of T
                endcase
            end
        end // End of CHECK_IF_MOVABLE
        CHECK_BUFFER: begin
            we <= 1'b1;
            isReadColor <= 1'b0;
            check_movable_count <= check_movable_count + 1;
            STATE <= CHECK_IF_MOVABLE;
            // Make isMovable 0 if next grid is NOT white or within the field
            isMovable <= (color_read == WHITE
                && read_x >= 6'd0 && read_x < 6'd10
                && read_y >= 6'd0 && read_y < 6'd22) ? 1'b1 : 1'b0;
        end
        // Erase current Tetromino from the field. Used when moving.
        REMOVE_COLOR: begin
            we <= 1'b1;
            // Note: You could also make a variable `BACKGROUND_COLOR` and set color to that.
            color <= WHITE;
            // Don't forget to initialize here, too (another place is in SET_COLOR)
            //draw_tetromino_count <= 3'd0;
            // Erase grids if it hadn't been erased yet
            if (erased == 1'b0) begin
                request_erase <= 1'b1;
                STATE <= WRITE_TO_SRAM;
            end
            else begin
                request_erase <= 1'b0;
                erased <= 1'b0;
                // Go to whatever state the movement was approved
                case (requestMovableCheck)
                    DOWN:   STATE <= MOVE_ONE_DOWN;
                    LEFT:   STATE <= MOVE_LEFT;
                    RIGHT:  STATE <= MOVE_RIGHT;
                    SPIN_L: STATE <= SPIN_LEFT;
                    // Can't happen
                    default:STATE <= INIT;
                endcase
            end
        end
        MOVE_ONE_DOWN: begin
            we <= 1'b1;
            // Reset requestMovableCheck
            requestMovableCheck <= NONE;
            tetromino_y <= tetromino_y + 1;
            STATE <= SET_COLOR;
        end
        MOVE_LEFT: begin
            we <= 1'b1;
            // Reset requestMovableCheck
            requestMovableCheck <= NONE;
            tetromino_x <= tetromino_x - 1;
            STATE <= SET_COLOR;
        end
        MOVE_RIGHT: begin
            we <= 1'b1;
            // Reset requestMovableCheck
            requestMovableCheck <= NONE;
            tetromino_x <= tetromino_x + 1;
            STATE <= SET_COLOR;
        end
        SPIN_LEFT: begin
            we <= 1'b1;
            requestMovableCheck <= NONE;
            spin_state <= spin_state + 1;
            STATE <= SET_COLOR;
        end
        CHECK_COMPLETE_ROW: begin
            // Disable write
            we <= 1'b1;
            // Go to GENERATE when check reached the top row
            if (read_y == 6'd0) begin
                isReadColor <= 1'b0;
                STATE <= GENERATE;
            end
            else begin
                isReadColor <= 1'b1;
                // When it reached the end of the row
                if (read_x == 6'd9) begin
                    read_x <= 6'd0;
                    if (color_read == WHITE) begin
                        read_y <= read_y - 6'd1;
                    end
                    // If it's a complete row
                    else begin
                        // Prepare to delete
                        x <= -6'd1;
                        STATE <= DELETE_ROW;
                    end
                end
                else begin
                    // That row is not complete
                    if (color_read == WHITE) begin
                        read_x <= 6'd0;
                        read_y <= read_y - 6'd1;
                    end
                    else begin
                        read_x <= read_x + 6'd1;
                    end
                end
            end
        end
        DELETE_ROW: begin
            isReadColor <= 1'b0;
            if (x == 6'd10) begin
                we <= 1'b1;
                // +1 because read_y gets decremented before the first evaluation
                shift_count_y <= read_y + 1;
                // Save the position of the deleted row because read_y will be changed
                deleted_row <= read_y;
                STATE <= SHIFT_ALL_BLOCKS_ABOVE;
            end
            else begin
                // Enable write
                we <= 1'b0;
                x <= x + 1;
                y <= read_y;
                color <= WHITE;
                STATE <= DELETE_ROW;
            end
        end
        // This state is the master of the 2 states: SHIFT_BLOCKS_READ_ABOVE and SHIFT_BLOCKS_WRITE_TO_CURRENT
        SHIFT_ALL_BLOCKS_ABOVE: begin
            // Disable write
            we <= 1'b1;
            isReadColor <= 1'b0;
            // Note: Shifting starts from the line that was erased
            // Ends at the second-from-top line
            // (top line is -6'd1 and when it exit state when entering the top row)
            if (shift_count_y == 6'd0) begin
                // Restore read_y
                read_y <= deleted_row + 1;
                STATE <= CHECK_COMPLETE_ROW;
            end
            else begin
                STATE <= DECREMENT_SHIFT_COUNT_Y;
            end
        end
        DECREMENT_SHIFT_COUNT_Y: begin
            // It first gets incremented
            shift_count_x <= -6'd1;
            shift_count_y <= shift_count_y - 6'd1;
            STATE <= INCREMENT_SHIFT_COUNT_X;
        end
        INCREMENT_SHIFT_COUNT_X: begin
            we <= 1'b1;
            isReadColor <= 1'b0;
            if (shift_count_x == 6'd10) begin
                shift_count_x <= 6'd0;
                STATE <= SHIFT_ALL_BLOCKS_ABOVE;
            end
            else begin
                shift_count_x <= shift_count_x + 1;
                STATE <= SHIFT_BLOCKS_READ_ABOVE;
            end
        end
        SHIFT_BLOCKS_READ_ABOVE: begin
            // Disable write
            we <= 1'b1;
            // Yes, we're reading color
            isReadColor <= 1'b1;
            read_x <= shift_count_x;
            read_y <= shift_count_y - 1;
            //STATE <= SHIFT_BLOCKS_WRITE_TO_CURRENT;
            STATE <= COLOR_READ_BUFFER;
        end
        COLOR_READ_BUFFER: begin
            we <= 1'b1;
            color <= color_read;
            // Off to shifting we go
            STATE <= SHIFT_BLOCKS_WRITE_TO_CURRENT;
        end
        SHIFT_BLOCKS_WRITE_TO_CURRENT: begin
            we <= 1'b0;
            isReadColor <= 1'b0;
            x <= shift_count_x;
            y <= shift_count_y;
            // Color was defined in the previous state
            STATE <= INCREMENT_SHIFT_COUNT_X;
        end
        GAME_OVER: begin
        end
    endcase
    end
end

// Show content on SRAM
always @(*) begin
    LEDR = STATE;
    // Paint in black if it's outside the field
    if ((mCoord_X < 220 || (mCoord_X >= 420 && mCoord_X < 640))
        // 60 not 20 because the first 2 "grids" are not shown
        || (mCoord_Y < 60 || (mCoord_Y >= 460 && mCoord_Y < 480))) begin
        {draw_r, draw_g, draw_b} = BLACK;
    end
    // Otherwise, show content of SRAM on the field
    else begin
        draw_r = SRAM_DQ[11:8];
        draw_g = SRAM_DQ[7:4];
        draw_b = SRAM_DQ[3:0];
    end
end

endmodule
