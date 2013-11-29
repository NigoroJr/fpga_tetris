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

wire SEC_CLK;
reg [2:0] sec;
reg forceReset;
SecTimer secondClock(CLOCK_50, RST, sec, forceReset);

// draw_? are decided at the very end of this file
reg [3:0] draw_r, draw_g, draw_b;
assign mVGA_R = {draw_r, 6'b0};
assign mVGA_G = {draw_g, 6'b0};
assign mVGA_B = {draw_b, 6'b0};

parameter   INIT = 4'd0,
            GENERATE = 4'd1,
            WRITE_TO_SRAM = 4'd2,
            DRAW = 4'd3,
            ERASE = 4'd4,
            MOVE_ONE_DOWN = 4'd5,
            CHECK_IF_MOVABLE = 4'd6,
            MOVE_LEFT = 4'd7,
            MOVE_RIGHT = 4'd8;
            /*
            SPIN_LEFT = 4'd9,
            CHECK_COMPLETE_ROW = 4'd10,
            DELETE_ROW = 4'd11,
            SHIFT_ALL_BLOCKS_ABOVE = 4'd12,
            GAME_OVER = 4'd13;
            */
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
reg [3:0] STATE;

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
assign SRAM_ADDR = we ? (isReadColor ? {read_x, read_y, 8'b0} : {grid_x, grid_y, 8'b0}) : {x, y, 8'b0};
assign SRAM_WE_N = we;
assign SRAM_LB_N = 0;
assign SRAM_OE_N = 0;
assign SRAM_UB_N = 0;

/*---- Control variables ----*/
wire gameStarted;
assign gameStarted = SW[0];
wire move_left_key, move_right_key, spin_left_key;
MoveKey toLeft(KEY[3], move_left_key, RST);

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
wire [4:0] grid_x, grid_y;
assign grid_x = (mCoord_X - 220) / 20;
assign grid_y = (mCoord_Y - 20) / 20;
// Coordinates used when writing to SRAM
reg [4:0] x, y, read_x, read_y;
reg [4:0] tetromino_x, tetromino_y;
reg [2:0] current_tetromino;
// Iterate through 0-3 to draw Tetrominoes
reg [2:0] draw_tetromino_count;
// Indicates whether the Tetromino was erased or not (i.e. just drawn)
reg erased;
// Type of check that was requested (TODO: change name)
reg [2:0] requestMovableCheck;
// 1 if movable, 0 if not
reg isMovable, check_done;
// Something similar to draw_tetromino_count but used for checking
reg [2:0] check_movable_count;
// Used to initialize the SRAM
reg [4:0] init_x, init_y;
// Calculate next state
always @(posedge VGA_CTRL_CLK or negedge RST) begin
    if (RST == 1'b0) begin
        // The following have to be initialized here because it will be used in INIT state
        init_x <= 5'd0;
        init_y <= 5'd0;
        isReadColor <= 1'b0;
        // TODO: check if these are really necessary. for now, better safe than sorry :)
        requestMovableCheck <= 3'd0;
        isMovable <= 1'b1;
        STATE <= INIT;
    end
    else begin
    case (STATE)
        INIT: begin
            if (gameStarted == 1'b1 && init_y == 23) begin
                we <= 1'b1;
                init_x <= 5'd0;
                init_y <= 5'd0;
                // Prepare for GENERATE state and change state
                draw_tetromino_count <= 0;
                STATE <= GENERATE;
            end
            else begin
                we <= 1'b0;
                // Initialize field with white
                color <= WHITE;
                x <= init_x;
                y <= init_y;
                STATE <= INIT;
                if (init_x == 10) begin
                    init_x <= 0;
                    init_y <= init_y + 1;
                end
                else begin
                    init_x <= init_x + 1;
                end
            end
        end
        GENERATE: begin
            we <= 1'b1;
            // TODO: get random number
            current_tetromino <= SW[17:15];
            // Use the same "pivot" instead of different ones for each Tetromino
            tetromino_x <= 5'd3;
            tetromino_y <= 5'd2;
            STATE <= DRAW;
        end
        DRAW: begin
            we <= 1'b1;
            // Tell MOVE_ONE_DOWN that we drew the Tetromino
            erased <= 1'b0;
            STATE <= WRITE_TO_SRAM;
            // Don't forget to initialize (another place in in ERASE)
            draw_tetromino_count <= 0;
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
                draw_tetromino_count <= 0;
                // Return to "calling" state
                case (requestMovableCheck)
                    LEFT:       STATE <= MOVE_LEFT;
                    RIGHT:      STATE <= MOVE_RIGHT;
                    default:    STATE <= MOVE_ONE_DOWN;
                endcase
            end
            else begin
                // Enable write
                we <= 1'b0;
                STATE <= WRITE_TO_SRAM;
                draw_tetromino_count <= draw_tetromino_count + 1;
                // Draw Tetromino based on pivot
                case (current_tetromino)
                    I: begin
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
                                x <= tetromino_x + 2;
                                y <= tetromino_y;
                            end
                            3'd3: begin
                                x <= tetromino_x + 3;
                                y <= tetromino_y;
                            end
                        endcase
                    end
                    O: begin
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
                    J: begin
                        case (draw_tetromino_count)
                            3'd0: begin
                                x <= tetromino_x + 2;
                                y <= tetromino_y;
                            end
                            3'd1: begin
                                x <= tetromino_x + 2;
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
                    S: begin
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
                                y <= tetromino_y;
                            end
                            3'd3: begin
                                x <= tetromino_x + 2;
                                y <= tetromino_y;
                            end
                        endcase
                    end
                    Z: begin
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
                                x <= tetromino_x + 2;
                                y <= tetromino_y + 1;
                            end
                        endcase
                    end
                    T: begin
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
                endcase
            end
        end // End of WRITE_TO_SRAM
        // Erase current Tetromino from the field. Used when moving.
        ERASE: begin
            we <= 1'b1;
            // Note: You could also make a variable `BACKGROUND_COLOR` and set color to that.
            color <= WHITE;
            // Yes, we erased it
            erased <= 1'b1;
            // Don't forget to initialize here, too (another place in in DRAW)
            draw_tetromino_count <= 0;
            // Another note: The state will change to MOVE_ONE_DOWN automatically after WRITE_TO_SRAM state.
            STATE <= WRITE_TO_SRAM;
        end
        MOVE_ONE_DOWN: begin
            we <= 1'b1;
            // This needs to be set to 0 in other MOVE states!
            isReadColor <= 1'b0;
            // Move when there was key input
            if (move_left_key == 1'b1) begin
                STATE <= MOVE_LEFT;
            end
            else if (move_right_key == 1'b1) begin
                STATE <= MOVE_RIGHT;
            end

            // Check if a check hasn't been requested yet
            else if (requestMovableCheck == 3'd0) begin
                // Request check for "moving down"
                requestMovableCheck <= DOWN;
                // Initialize before changing states
                check_movable_count <= 3'd0;
                isMovable <= 1'b1;
                check_done <= 1'b0;
                STATE <= CHECK_IF_MOVABLE;
            end
            // If it can't move anymore (in this state, meaning it hit the bottom)
            else if (check_done == 1'b1 && isMovable == 1'b0) begin
                // Reset requestMovableCheck
                requestMovableCheck <= NONE;
                // Leave the Tetromino alone and generate a new ones
                STATE <= GENERATE;
            end
            // Clear the Tetromino first and redraw
            else if (sec == 3'd1) begin
                if (erased == 1'b1) begin
                    // Reset requestMovableCheck
                    requestMovableCheck <= NONE;
                    tetromino_y <= tetromino_y + 1;
                    // Reset timer
                    forceReset <= 1'b1;
                    STATE <= DRAW;
                end
                else begin
                    STATE <= ERASE;
                    forceReset <= 1'b0;
                end
            end
            // Otherwise, take a break for a while
            else begin
                forceReset <= 1'b0;
            end
        end
        // Checks if the Tetromino can really move to the next grid
        CHECK_IF_MOVABLE: begin
            // Variables:
            //      Type of request => requestMovableCheck
            //      Result set to   => isMovable
            //      Indicates done  => check_done
            //      Counter         => check_movable_count
            //      SRAM content    => color_read
            //      Specify address => read_x, read_y

            we <= 1'b1;
            // Go back to previous state
            if (check_movable_count == 3'd3) begin
                check_movable_count <= 3'd0;
                isReadColor <= 1'b0;
                check_done <= 1'b1;
                // Go back to "calling" state
                case (requestMovableCheck)
                    DOWN:   STATE <= MOVE_ONE_DOWN;
                    LEFT:   STATE <= MOVE_LEFT;
                    RIGHT:  STATE <= MOVE_RIGHT;
                    // Can't happen
                    default:STATE <= INIT;
                endcase
            end
            else begin
                // Important in order to *read* from SRAM
                isReadColor <= 1'b1;
                check_movable_count <= check_movable_count + 1;
                // Make isMovable 0 if next grid is NOT white or within the field
                isMovable <= (color_read == WHITE)
                    & read_x >= 0 & read_x < 10
                    & read_y >= 0 & read_y < 22;
                case (current_tetromino)
                    I: begin
                        case (requestMovableCheck)
                            DOWN: begin
                                case (check_movable_count)
                                    3'd0: begin
                                        read_x <= tetromino_x;
                                        read_y <= tetromino_y + 1;
                                    end
                                    3'd1: begin
                                        read_x <= tetromino_x + 1;
                                        read_y <= tetromino_y + 1;
                                    end
                                    3'd2: begin
                                        read_x <= tetromino_x + 2;
                                        read_y <= tetromino_y + 1;
                                    end
                                    3'd3: begin
                                        read_x <= tetromino_x + 3;
                                        read_y <= tetromino_y + 1;
                                    end
                                endcase
                            end
                            LEFT: begin
                                case (check_movable_count)
                                    3'd0: begin
                                        read_x <= tetromino_x - 1;
                                        read_y <= tetromino_y;
                                    end
                                endcase
                            end
                            RIGHT: begin
                                case (check_movable_count)
                                    3'd0: begin
                                        read_x <= tetromino_x + 1;
                                        read_y <= tetromino_y;
                                    end
                                endcase
                            end
                            SPIN_L: begin
                                // TODO
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
                                // TODO
                            end
                        endcase
                    end // End of O
                    L: begin
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
                                // TODO
                            end
                        endcase
                    end // End of L
                    J: begin
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
                                        read_x <= tetromino_x + 1;
                                        read_y <= tetromino_y;
                                    end
                                    3'd1: begin
                                        read_x <= tetromino_x + 1;
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
                                // TODO
                            end
                        endcase
                    end // End of J
                    S: begin
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
                                        read_x <= tetromino_x + 2;
                                        read_y <= tetromino_y + 1;
                                    end
                                endcase
                            end
                            SPIN_L: begin
                                // TODO
                            end
                        endcase
                    end // End of S
                    Z: begin
                        case (requestMovableCheck)
                            DOWN: begin
                                case (check_movable_count)
                                    3'd0: begin
                                        read_x <= tetromino_x;
                                        read_y <= tetromino_y + 1;
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
                                        read_x <= tetromino_x;
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
                                // TODO
                            end
                        endcase
                    end // End of Z
                    T: begin
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
                                // TODO
                            end
                        endcase
                    end // End of T
                endcase
            end
        end // End of CHECK_IF_MOVABLE
        MOVE_LEFT: begin
            we <= 1'b1;
            if (check_done == 1'b1 && isMovable == 1'b1) begin
                if (erased == 1'b1) begin
                    // Reset requestMovableCheck
                    requestMovableCheck <= NONE;
                    tetromino_x <= tetromino_x + 1;
                    // Reset timer
                    forceReset <= 1'b1;
                    STATE <= DRAW;
                end
                else begin
                    STATE <= ERASE;
                    forceReset <= 1'b0;
                end
            end
            // TODO: should this be if requestMovableCheck == NONE ??
            else if (check_done == 1'b0) begin
                // Request check for "moving left"
                requestMovableCheck <= LEFT;
                // Initialize before changing states
                check_movable_count <= 3'd0;
                isMovable <= 1'b1;
                check_done <= 1'b0;
                STATE <= CHECK_IF_MOVABLE;
            end
            else begin
                STATE <= MOVE_ONE_DOWN;
            end
        end
        MOVE_RIGHT: begin
            we <= 1'b1;
            if (check_done == 1'b1 && isMovable == 1'b1) begin
                if (erased == 1'b1) begin
                    // Reset requestMovableCheck
                    requestMovableCheck <= NONE;
                    tetromino_x <= tetromino_x + 1;
                    // Reset timer
                    forceReset <= 1'b1;
                    STATE <= DRAW;
                end
                else begin
                    STATE <= ERASE;
                    forceReset <= 1'b0;
                end
            end
            else if (check_done == 1'b0) begin
                // Request check for "moving right"
                requestMovableCheck <= RIGHT;
                // Initialize before changing states
                check_movable_count <= 3'd0;
                isMovable <= 1'b1;
                check_done <= 1'b0;
                STATE <= CHECK_IF_MOVABLE;
            end
            else begin
                STATE <= MOVE_ONE_DOWN;
            end
        end
    endcase
    end
end

// Show content on SRAM
always @(*) begin
    LEDR = move_left_key;
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
