/*
 * Copyright (c) 2024 Ciro Cattuto, Modified 2026
 * based on the VGA examples by Uri Shaked
 * and on tt07-conway-term (https://github.com/ccattuto/tt07-conway-term)
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_vga_example(
  input  wire [7:0] ui_in,    // Dedicated inputs
  output wire [7:0] uo_out,   // Dedicated outputs
  input  wire [7:0] uio_in,   // IOs: Input path
  output wire [7:0] uio_out,  // IOs: Output path
  output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
  input  wire       ena,      // always 1 when the design is powered, so you can ignore it
  input  wire       clk,      // clock
  input  wire       rst_n     // reset_n - low to reset
);

// VGA signals
wire hsync;
wire vsync;
wire video_active;
wire [9:0] pix_x;
wire [9:0] pix_y;

// stops/starts simulation
wire running;
assign running = ~ui_in[0];

// randomizes board state (used here to reset the game manually)
wire randomize;
assign randomize = ui_in[1];

// Color Output Registers
reg [1:0] R;
reg [1:0] G;
reg [1:0] B;

// TinyVGA PMOD
assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

// Unused outputs assigned to 0.
assign uio_out = 0;
assign uio_oe  = 0;

// Suppress unused signals warning
wire _unused_ok = &{ena, ui_in, uio_in};

hvsync_generator hvsync_gen(
  .clk(clk),
  .reset(~rst_n),
  .hsync(hsync),
  .vsync(vsync),
  .display_on(video_active),
  .hpos(pix_x),
  .vpos(pix_y)
);

// ----------------- RENDERER: TITLE, MONITOR & PLAY AREA --------------------

// Monitor Bezel and Active Play Area boundaries
wire border_active = (pix_x >= 56 && pix_x < 640-56 && pix_y >= 104 && pix_y < 480-104) ? 1 : 0;
wire frame_active  = (pix_x >= 64 && pix_x < 640-64 && pix_y >= 112 && pix_y < 480-112) ? 1 : 0;

// Text Renderer for "SNAKE APPLE" title (Scaled 4x and placed above the monitor)
// Centered perfectly: X=192, Width=256 (64*4), Y=40, Height=32 (8*4)
wire in_text_bounds = (pix_x >= 192 && pix_x < 192 + 256) && (pix_y >= 40 && pix_y < 40 + 32);

// Divide by 4 to map the VGA pixels back to the 64x8 font grid
wire [5:0] text_x = (pix_x - 192) >> 2; 
wire [2:0] text_y = (pix_y - 40) >> 2;

// 64-bit wide row definitions for perfectly clean synthesis
reg [63:0] title_rom [0:7];
initial begin
  // Structure: 00_S_N_A_K_E_000_A_P_P_L_E_00 (Exactly 64 bits wide)
  title_rom[0] = 64'b00_01110_0_10001_0_01110_0_10010_0_11111_000_01110_0_11110_0_11110_0_10000_0_11111_00;
  title_rom[1] = 64'b00_10000_0_11001_0_10001_0_10100_0_10000_000_10001_0_10001_0_10001_0_10000_0_10000_00;
  title_rom[2] = 64'b00_10000_0_10101_0_10001_0_11000_0_10000_000_10001_0_10001_0_10001_0_10000_0_10000_00;
  title_rom[3] = 64'b00_01110_0_10011_0_11111_0_10100_0_11110_000_11111_0_11110_0_11110_0_10000_0_11110_00;
  title_rom[4] = 64'b00_00001_0_10001_0_10001_0_10010_0_10000_000_10001_0_10000_0_10000_0_10000_0_10000_00;
  title_rom[5] = 64'b00_10001_0_10001_0_10001_0_10001_0_10000_000_10001_0_10000_0_10000_0_10000_0_10000_00;
  title_rom[6] = 64'b00_01110_0_10001_0_10001_0_10001_0_11111_000_10001_0_10000_0_10000_0_11111_0_11111_00;
  title_rom[7] = 64'b00_00000_0_00000_0_00000_0_00000_0_00000_000_00000_0_00000_0_00000_0_00000_0_00000_00;
end

// Safely extract the exact pixel by reading from MSB (left) to LSB (right)
wire [63:0] current_row = title_rom[text_y];
wire title_pixel = in_text_bounds ? current_row[6'd63 - text_x] : 1'b0;

// compute index into board state
wire [10:0] cell_index;
assign cell_index = (pix_y[7:3] << 6) | pix_x[8:3];

wire is_snake = board_state[cell_index];
wire is_apple = (cell_index == apple_pos);

// look up into the 8x8 icon bitmap for live cells
wire snake_pixel = snake_icon[pix_y[2:0]][pix_x[2:0]];
wire [1:0] apple_pixel_color = apple_icon[pix_y[2:0]][pix_x[2:0]*2 +: 2];

// Color Palette Logic
always @(*) begin
  if (video_active) begin
    if (in_text_bounds && title_pixel) begin
       // Draw Arcade Marquee Title
       R = 2'b11; G = 2'b11; B = 2'b11; // White Title Text
    end else if (frame_active) begin
      // Inside Game Play Area
      if (is_apple && (apple_pixel_color != 2'b00)) begin
         if (apple_pixel_color == 2'b10) begin 
            R = 2'b00; G = 2'b10; B = 2'b00; // Leaf/Stem
         end else begin 
            R = 2'b11; G = 2'b00; B = 2'b00; // Red Apple Body
         end
      end else if (is_snake && snake_pixel) begin
         R = 2'b01; G = 2'b11; B = 2'b00; // Vibrant Yellow-Green Snake
      end else begin
         R = 2'b00; G = 2'b00; B = 2'b01; // Dark Blue Background
      end
    end else if (border_active) begin
      // Monitor Bezel
      R = 2'b10; G = 2'b10; B = 2'b11; // Gray-Blue Bezel
    end else begin
      // Outside monitor (Black Void)
      R = 2'b00; G = 2'b00; B = 2'b00; 
    end
  end else begin
    R = 2'b00; G = 2'b00; B = 2'b00; // Blanking interval
  end
end
  
// clock
localparam CLOCK_FREQ = 24000000;
wire boot_reset = ~rst_n;


// ----------------- SIMULATION PARAMS & MEMORY -------------------------

localparam logWIDTH = 6, logHEIGHT = 5;         // 64x32 board
localparam UPDATE_INTERVAL = CLOCK_FREQ / 35;   // 35 Hz 

localparam WIDTH = 2 ** logWIDTH;
localparam HEIGHT = 2 ** logHEIGHT;
localparam BOARD_SIZE = WIDTH * HEIGHT;

reg board_state [0:BOARD_SIZE-1];         // current state of the grid
reg [10:0] snake_body [0:1023];           // expanded buffer (max length 1024)

reg [9:0] head_ptr;                       
reg [9:0] tail_ptr;                       
reg [10:0] head_pos;                      
reg [10:0] apple_pos;                     
reg [3:0]  grow_queue;                    // how many segments left to grow


// ----------------- SIMULATION CONTROL LOGIC --------------------

localparam ACTION_INIT = 0, ACTION_CLEAR = 1, ACTION_IDLE = 2, ACTION_UPDATE = 3, ACTION_CLEAR_TAIL = 4, ACTION_SPAWN = 5;
reg [2:0] action;
reg [31:0] timer;
reg [10:0] init_index;

always @(posedge clk) begin
  if (boot_reset || randomize) begin
    action <= ACTION_INIT;
    timer <= 0;
  end else begin
    case (action)
      
      ACTION_INIT: begin
        init_index <= 0;
        action <= ACTION_CLEAR;
      end

      ACTION_CLEAR: begin
        board_state[init_index] <= 0;
        if (init_index == BOARD_SIZE - 1) begin
          head_pos <= 11'd540;   
          apple_pos <= 11'd550;  
          head_ptr <= 0;
          tail_ptr <= 0;
          grow_queue <= 0;
          board_state[540] <= 1; 
          snake_body[0] <= 540;  
          action <= ACTION_IDLE;
        end else begin
          init_index <= init_index + 1;
        end
      end

      ACTION_IDLE: begin
        if (running) begin
          if (timer < UPDATE_INTERVAL) begin
            timer <= timer + 1;
          end else if (~vsync) begin
            timer <= 0;
            action <= ACTION_UPDATE;
          end
        end
      end

      ACTION_UPDATE: begin
        if (next_pos_reg == head_pos) begin
          action <= ACTION_INIT; // Crashed
        end else begin
          head_pos <= next_pos_reg;
          head_ptr <= head_ptr + 1;
          snake_body[head_ptr + 1] <= next_pos_reg;
          board_state[next_pos_reg] <= 1;

          if (next_pos_reg == apple_pos) begin
            // Eat apple: Grow by exactly 2 segments (1 natural head step + 1 added to queue)
            grow_queue <= grow_queue + 1; 
            action <= ACTION_SPAWN;
          end else begin
            // Normal movement
            if (grow_queue > 0) begin
              grow_queue <= grow_queue - 1;
              action <= ACTION_IDLE; // Skip clearing tail to grow
            end else begin
              action <= ACTION_CLEAR_TAIL; // Clear tail to maintain length
            end
          end
        end
      end

      ACTION_CLEAR_TAIL: begin
        board_state[snake_body[tail_ptr]] <= 0;
        tail_ptr <= tail_ptr + 1;
        action <= ACTION_IDLE;
      end

      ACTION_SPAWN: begin
        if (!board_state[lfsr_reg[10:0]]) begin
          apple_pos <= lfsr_reg[10:0];
          action <= ACTION_IDLE;
        end
      end

      default: action <= ACTION_IDLE;
    endcase
  end
end

// ----------------- AUTOMATIC AI (PATHFINDING) --------------------

wire [5:0] head_x = head_pos[5:0];
wire [4:0] head_y = head_pos[10:6];
wire [5:0] apple_x = apple_pos[5:0];
wire [4:0] apple_y = apple_pos[10:6];

wire [10:0] pos_R = {head_y, head_x + 6'd1};
wire [10:0] pos_L = {head_y, head_x - 6'd1};
wire [10:0] pos_D = {head_y + 5'd1, head_x};
wire [10:0] pos_U = {head_y - 5'd1, head_x};

// Collision detection bounds
wire can_R = (head_x != 63) && !board_state[pos_R];
wire can_L = (head_x != 0)  && !board_state[pos_L];
wire can_D = (head_y != 31) && !board_state[pos_D];
wire can_U = (head_y != 0)  && !board_state[pos_U];

// Manhattan desires
wire want_R = (head_x < apple_x);
wire want_L = (head_x > apple_x);
wire want_D = (head_y < apple_y);
wire want_U = (head_y > apple_y);

reg [10:0] next_pos_reg;

always @(*) begin
  // 1. Try moving directly towards the apple if the path is clear
  if (want_R && can_R) next_pos_reg = pos_R;
  else if (want_L && can_L) next_pos_reg = pos_L;
  else if (want_D && can_D) next_pos_reg = pos_D;
  else if (want_U && can_U) next_pos_reg = pos_U;
  
  // 2. Fallback: Path towards apple is blocked, pick ANY safe direction
  else if (can_R) next_pos_reg = pos_R;
  else if (can_D) next_pos_reg = pos_D;
  else if (can_L) next_pos_reg = pos_L;
  else if (can_U) next_pos_reg = pos_U;
  
  // 3. Trapped: Snake crashed into itself or corners
  else next_pos_reg = head_pos; 
end

// --------------- RNG (Linear Feedback Shift Register) --------------------

reg [15:0] lfsr_reg; 
wire feedback = lfsr_reg[15] ^ lfsr_reg[13] ^ lfsr_reg[12] ^ lfsr_reg[10];

always @(posedge clk) begin
  if (boot_reset) begin
    lfsr_reg <= 16'b1010_1101_0011_0001;
  end else begin
    lfsr_reg <= {lfsr_reg[14:0], feedback};
  end
end

// --------------- ICONS FOR SNAKE & APPLE --------------------

reg [7:0] snake_icon[0:7];
reg [15:0] apple_icon[0:7];

initial begin
  // Bent corner (Rounded box) for snake body
  snake_icon[0] = 8'b01111110;
  snake_icon[1] = 8'b11111111;
  snake_icon[2] = 8'b11111111;
  snake_icon[3] = 8'b11111111;
  snake_icon[4] = 8'b11111111;
  snake_icon[5] = 8'b11111111;
  snake_icon[6] = 8'b11111111;
  snake_icon[7] = 8'b01111110;

  // Multicolor apple mapping
  apple_icon[0] = 16'b00_00_00_10_10_00_00_00;
  apple_icon[1] = 16'b00_00_10_10_00_00_00_00;
  apple_icon[2] = 16'b00_01_01_01_01_01_01_00;
  apple_icon[3] = 16'b01_01_01_01_01_01_01_01;
  apple_icon[4] = 16'b01_01_01_01_01_01_01_01;
  apple_icon[5] = 16'b01_01_01_01_01_01_01_01;
  apple_icon[6] = 16'b00_01_01_01_01_01_01_00;
  apple_icon[7] = 16'b00_00_01_01_01_01_00_00;
end

endmodule