//============================================================================
//
//  Blue Print main CPU board model
//  Copyright (C) 2026 Rodimus
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.
//
//============================================================================

module BluePrint_CPU
(
	input         reset,
	input         clk_40m,

	output  [4:0] red, green, blue,
	output        video_hsync, video_vsync, video_csync,
	output        video_hblank, video_vblank,
	output        ce_pix,

	input   [7:0] p1_controls,    // {coin, start2, start1, btn1, left, down, right, up}
	input   [7:0] p2_controls,    // {3'b111, btn1, left, down, right, up}

	input   [7:0] dipsw_readback,

	output  [7:0] sound_cmd,
	output        sound_cmd_wr,

	input         crt_flip,

	input   [3:0] h_center, v_center,

	output chip_pool_pkg::z80_i_t z80_0_i,
	input  chip_pool_pkg::z80_o_t z80_0_o,

	output [11:0] rom_cpu_a,
	input   [7:0] rom1_D, rom2_D, rom3_D, rom4_D, rom5_D, rom6_D,
	output [11:0] rom_tile_a,
	input   [7:0] tile0_D, tile1_D,
	output [11:0] rom_spr_a,
	input   [7:0] spr_r_D, spr_b_D, spr_g_D,

	output ram_pool_pkg::pram_i_t [4:0] pr_i,
	input  ram_pool_pkg::pram_o_t [4:0] pr_o,

	input         pause,

	input  [15:0] hs_address,
	input   [7:0] hs_data_in,
	output  [7:0] hs_data_out,
	input         hs_write
);

reg [2:0] pix_div = 3'd0;
always @(posedge clk_40m) pix_div <= pix_div + 3'd1;
wire cen_5m = (pix_div == 3'd0);

wire [1:0] cpu_cen_o;
jtframe_frac_cen #(2) cpu_cen
(
	.clk(clk_40m),
	.n(10'd7),
	.m(10'd80),
	.cen(cpu_cen_o),
	.cenb()
);
wire cen_3m5 = cpu_cen_o[0];

assign ce_pix = cen_5m;

reg [8:0] base_h_cnt = 9'd0;
reg [8:0] v_cnt = 9'd0;
always_ff @(posedge clk_40m) begin
	if (cen_5m) begin
		if (base_h_cnt == 9'd319) begin
			base_h_cnt <= 9'd0;
			v_cnt <= (v_cnt == 9'd263) ? 9'd0 : v_cnt + 9'd1;
		end else
			base_h_cnt <= base_h_cnt + 9'd1;
	end
end

wire [8:0] h_cnt = (base_h_cnt <= 9'd248) ? base_h_cnt : 9'd248;

wire hblk = (base_h_cnt >= 9'd256);
wire vblk = (v_cnt < 9'd16) | (v_cnt >= 9'd240);
assign video_hblank = hblk;
assign video_vblank = vblk;

wire [8:0] hs_start = 9'd280 + {5'd0, h_center};
wire [8:0] hs_end   = hs_start + 9'd32;
wire [8:0] vs_start = 9'd248 + {5'd0, v_center};
wire [8:0] vs_end   = vs_start + 9'd4;
assign video_hsync = (base_h_cnt >= hs_start && base_h_cnt < hs_end);
assign video_vsync = (v_cnt >= vs_start && v_cnt < vs_end);
assign video_csync = ~(video_hsync ^ video_vsync);

wire [15:0] z80_A;
wire [7:0] z80_Dout;
wire n_mreq, n_iorq, n_rd, n_wr, n_rfsh, n_m1;
assign z80_A    = z80_0_o.a;
assign z80_Dout = z80_0_o.dout;
assign n_m1     = z80_0_o.m1_n;
assign n_mreq   = z80_0_o.mreq_n;
assign n_iorq   = z80_0_o.iorq_n;
assign n_rd     = z80_0_o.rd_n;
assign n_wr     = z80_0_o.wr_n;
assign n_rfsh   = z80_0_o.rfsh_n;

reg n_irq = 1'b1;
reg vblk_last = 1'b0;
wire irq_ack = ~n_iorq & ~n_m1;
always_ff @(posedge clk_40m) begin
	if (!reset) begin
		n_irq <= 1'b1;
		vblk_last <= 1'b0;
	end else begin
		if (irq_ack)
			n_irq <= 1'b1;
		else if (vblk && !vblk_last)
			n_irq <= 1'b0;
		vblk_last <= vblk;
	end
end

wire mem_valid = ~n_mreq & n_rfsh;
wire cs_rom    = mem_valid & ~z80_A[15] & (z80_A[14:13] != 2'b11);
wire cs_wram   = mem_valid & (z80_A[15:11] == 5'b10000);
wire cs_vram   = mem_valid & (z80_A[15:12] == 4'h9);
wire cs_scroll = mem_valid & (z80_A[15:8]  == 8'hA0);
wire cs_sprite = mem_valid & (z80_A[15:8]  == 8'hB0);
wire cs_io_c   = mem_valid & (z80_A[15:12] == 4'hC);
wire cs_sndcmd = mem_valid & (z80_A[15:12] == 4'hD) & ~n_wr;
wire cs_e000   = mem_valid & (z80_A[15:12] == 4'hE);
wire cs_cram   = mem_valid & (z80_A[15:12] == 4'hF);

assign rom_cpu_a = z80_A[11:0];

wire [7:0] rom_D = (z80_A[14:12] == 3'd0) ? rom1_D :
                   (z80_A[14:12] == 3'd1) ? rom2_D :
                   (z80_A[14:12] == 3'd2) ? rom3_D :
                   (z80_A[14:12] == 3'd3) ? rom4_D :
                   (z80_A[14:12] == 3'd4) ? rom5_D :
                   (z80_A[14:12] == 3'd5) ? rom6_D :
                   8'hFF;

reg  [11:0] tile_render_addr;
assign rom_tile_a = tile_render_addr;

reg  [11:0] spr_render_addr;
assign rom_spr_a = spr_render_addr;

ram_pool_pkg::pram_i_t wram_i, vram_i, cram_i, scroll_i, sprite_i;
ram_pool_pkg::pram_o_t wram_o, vram_o, cram_o, scroll_o, sprite_o;
assign pr_i = {sprite_i, scroll_i, cram_i, vram_i, wram_i};
assign {sprite_o, scroll_o, cram_o, vram_o, wram_o} = pr_o;

wire [7:0] wram_D;
assign wram_i.a_addr = 16'(z80_A[10:0]);
assign wram_i.a_d    = z80_Dout;
assign wram_i.a_we   = cs_wram & ~n_wr;
assign wram_i.b_addr = 16'(hs_address[10:0]);
assign wram_i.b_d    = hs_data_in;
assign wram_i.b_we   = hs_write;
assign wram_D = wram_o.a_q;
assign hs_data_out = wram_o.b_q;

wire [7:0] vram_cpu_D, vram_render_D;
reg  [9:0] vram_render_addr;
assign vram_i.a_addr = 16'(z80_A[9:0]);
assign vram_i.a_d    = z80_Dout;
assign vram_i.a_we   = cs_vram & ~n_wr;
assign vram_i.b_addr = 16'(vram_render_addr);
assign vram_i.b_d    = 8'd0;
assign vram_i.b_we   = 1'b0;
assign vram_cpu_D = vram_o.a_q;
assign vram_render_D = vram_o.b_q;

wire [7:0] cram_cpu_D, cram_render_D;
reg  [9:0] cram_render_addr;
assign cram_i.a_addr = 16'(z80_A[9:0]);
assign cram_i.a_d    = z80_Dout;
assign cram_i.a_we   = cs_cram & ~n_wr;
assign cram_i.b_addr = 16'(cram_render_addr);
assign cram_i.b_d    = 8'd0;
assign cram_i.b_we   = 1'b0;
assign cram_cpu_D = cram_o.a_q;
assign cram_render_D = cram_o.b_q;

wire [7:0] scroll_cpu_D, scroll_render_D;
reg  [7:0] scroll_render_addr;
assign scroll_i.a_addr = 16'(z80_A[7:0]);
assign scroll_i.a_d    = z80_Dout;
assign scroll_i.a_we   = cs_scroll & ~n_wr;
assign scroll_i.b_addr = 16'(scroll_render_addr);
assign scroll_i.b_d    = 8'd0;
assign scroll_i.b_we   = 1'b0;
assign scroll_cpu_D = scroll_o.a_q;
assign scroll_render_D = scroll_o.b_q;

wire [7:0] sprite_cpu_D, sprite_scan_D;
reg  [7:0] sprite_scan_addr;
assign sprite_i.a_addr = 16'(z80_A[7:0]);
assign sprite_i.a_d    = z80_Dout;
assign sprite_i.a_we   = cs_sprite & ~n_wr;
assign sprite_i.b_addr = 16'(sprite_scan_addr);
assign sprite_i.b_d    = 8'd0;
assign sprite_i.b_we   = 1'b0;
assign sprite_cpu_D = sprite_o.a_q;
assign sprite_scan_D = sprite_o.b_q;

reg flip = 1'b0;
reg gfx_bank = 1'b0;
always_ff @(posedge clk_40m) begin
	if (!reset) begin
		flip <= 1'b0;
		gfx_bank <= 1'b0;
	end else if (cen_3m5 && cs_e000 && ~n_wr) begin
		flip <= ~z80_Dout[1];
		gfx_bank <= z80_Dout[2];
	end
end

wire master_flip = flip ^ crt_flip;

reg [7:0] snd_cmd_reg = 8'd0;
reg snd_cmd_wr_reg = 1'b0;
always_ff @(posedge clk_40m) begin
	snd_cmd_wr_reg <= 1'b0;
	if (cen_3m5 && cs_sndcmd) begin
		snd_cmd_reg <= z80_Dout;
		snd_cmd_wr_reg <= 1'b1;
	end
end
assign sound_cmd = snd_cmd_reg;
assign sound_cmd_wr = snd_cmd_wr_reg;

wire [7:0] z80_Din = cs_rom                                ? rom_D :
                     (cs_wram & n_wr)                       ? wram_D :
                     (cs_vram & n_wr)                       ? vram_cpu_D :
                     (cs_cram & n_wr)                       ? cram_cpu_D :
                     (cs_scroll & n_wr)                     ? scroll_cpu_D :
                     (cs_sprite & n_wr)                     ? sprite_cpu_D :
                     (cs_io_c & ~n_rd & (z80_A[1:0] == 2'b00)) ? p1_controls :
                     (cs_io_c & ~n_rd & (z80_A[1:0] == 2'b01)) ? p2_controls :
                     (cs_io_c & ~n_rd & (z80_A[1:0] == 2'b11)) ? dipsw_readback :
                     8'hFF;

assign z80_0_i.ce    = cen_3m5 & ~pause;
assign z80_0_i.int_n = n_irq;
assign z80_0_i.nmi_n = 1'b1;
assign z80_0_i.di    = z80_Din;

reg [7:0] tile_shift0, tile_shift1;
reg [6:0] tile_color_latch;
reg       tile_priority_latch;
reg       prev_bank_bit;
reg [4:0] latched_col;
reg [7:0] pipe_tile0, pipe_tile1;
reg [6:0] pipe_color;
reg       pipe_priority;
reg [2:0] pipe_fine_y;

// tile pixels shift out MSB-first, so a flipped column loads reversed
wire [7:0] pipe_tile0_rev = {pipe_tile0[0], pipe_tile0[1], pipe_tile0[2], pipe_tile0[3],
                             pipe_tile0[4], pipe_tile0[5], pipe_tile0[6], pipe_tile0[7]};
wire [7:0] pipe_tile1_rev = {pipe_tile1[0], pipe_tile1[1], pipe_tile1[2], pipe_tile1[3],
                             pipe_tile1[4], pipe_tile1[5], pipe_tile1[6], pipe_tile1[7]};

wire [4:0] screen_col  = h_cnt[7:3];
wire [2:0] fine_x      = h_cnt[2:0];
wire [7:0] screen_y    = v_cnt[7:0];

localparam [4:0] FLIP_COL_ADJ = 5'd3;
localparam [7:0] FLIP_SPR_ADJ = 8'd12;
wire [4:0] eff_col = master_flip ? ((~screen_col) - FLIP_COL_ADJ) : screen_col;
wire [7:0] eff_y   = master_flip ? ~screen_y   : screen_y;
wire visible_line = (v_cnt >= 9'd16) && (v_cnt < 9'd240);

always_ff @(posedge clk_40m) begin
	if (!reset) begin
		tile_shift0         <= 8'd0;
		tile_shift1         <= 8'd0;
		tile_color_latch    <= 7'd0;
		tile_priority_latch <= 1'b0;
		prev_bank_bit       <= 1'b0;
		latched_col         <= 5'd0;
		pipe_tile0          <= 8'd0;
		pipe_tile1          <= 8'd0;
		pipe_color          <= 7'd0;
		pipe_priority       <= 1'b0;
		pipe_fine_y         <= 3'd0;
	end else if (cen_5m) begin
		if (!visible_line) begin
			tile_shift0 <= 8'd0;
			tile_shift1 <= 8'd0;
			if (v_cnt == 9'd15 && h_cnt == 9'd0)
				prev_bank_bit <= 1'b0;
		end else begin
			case (fine_x)

				3'd0: begin
					tile_shift0         <= master_flip ? pipe_tile0_rev : pipe_tile0;
					tile_shift1         <= master_flip ? pipe_tile1_rev : pipe_tile1;
					tile_color_latch    <= pipe_color;
					tile_priority_latch <= pipe_priority;
					latched_col         <= eff_col;
					scroll_render_addr  <= 8'd30 - {3'd0, eff_col};
				end

				3'd1: begin
					begin
						reg [7:0] scrolled_y;
						scrolled_y       = eff_y + scroll_render_D;
						pipe_fine_y      <= scrolled_y[2:0];
						vram_render_addr <= {(5'd30 - latched_col), scrolled_y[7:3]};
						cram_render_addr <= {(5'd30 - latched_col), scrolled_y[7:3]};
					end
					tile_shift0 <= {tile_shift0[6:0], 1'b0};
					tile_shift1 <= {tile_shift1[6:0], 1'b0};
				end

				3'd2: begin
					tile_shift0 <= {tile_shift0[6:0], 1'b0};
					tile_shift1 <= {tile_shift1[6:0], 1'b0};
				end

				3'd3: begin
					pipe_color       <= cram_render_D[6:0];
					pipe_priority    <= cram_render_D[7];
					tile_render_addr <= {prev_bank_bit & gfx_bank, vram_render_D, pipe_fine_y};
					prev_bank_bit    <= cram_render_D[6];
					tile_shift0      <= {tile_shift0[6:0], 1'b0};
					tile_shift1      <= {tile_shift1[6:0], 1'b0};
				end

				3'd4: begin
					pipe_tile0  <= tile0_D;
					pipe_tile1  <= tile1_D;
					tile_shift0 <= {tile_shift0[6:0], 1'b0};
					tile_shift1 <= {tile_shift1[6:0], 1'b0};
				end

				default: begin
					tile_shift0 <= {tile_shift0[6:0], 1'b0};
					tile_shift1 <= {tile_shift1[6:0], 1'b0};
				end

			endcase
		end
	end
end

wire [1:0] tile_pixel     = {tile_shift1[7], tile_shift0[7]};
wire       tile_transparent = (tile_pixel == 2'b00);
wire       tile_intensity   = tile_color_latch[6];
wire [2:0] color_lo         = tile_color_latch[2:0];
wire [2:0] color_hi         = tile_color_latch[5:3];

wire [2:0] pen_rbg = (tile_pixel == 2'b01) ? color_lo :
                     (tile_pixel == 2'b10) ? color_hi :
                     (tile_pixel == 2'b11) ? (color_lo | color_hi) :
                     3'b000;

wire [4:0] r_tile = pen_rbg[0] ? (tile_intensity ? 5'd24 : 5'd31) : 5'd0;
wire [4:0] g_tile = pen_rbg[2] ? (tile_intensity ? 5'd24 : 5'd31) : 5'd0;
wire [4:0] b_tile = pen_rbg[1] ? (tile_intensity ? 5'd24 : 5'd31) : 5'd0;

reg [2:0] linebuf0 [0:255];
reg [2:0] linebuf1 [0:255];
reg       linebuf_sel = 1'b0;

always_ff @(posedge clk_40m) begin
	if (!reset)
		linebuf_sel <= 1'b0;
	else if (cen_5m && h_cnt == 9'd0)
		linebuf_sel <= ~linebuf_sel;
end

reg [3:0] spr_state;
reg [5:0] spr_idx;
reg [7:0] spr_byte0;
reg [7:0] spr_byte1;
reg [7:0] spr_byte2;
reg [7:0] spr_byte3;
reg       spr_flipy;
reg       prev_sprite_flipy;
reg [7:0] spr_rom_r_lat, spr_rom_b_lat, spr_rom_g_lat;
reg [2:0] spr_pix_cnt;
reg [7:0] next_scanline;

localparam SPR_IDLE     = 4'd0;
localparam SPR_INIT_RD  = 4'd2;
localparam SPR_INIT_LAT = 4'd3;
localparam SPR_RD_B0    = 4'd4;
localparam SPR_RD_B1    = 4'd5;
localparam SPR_RD_B2    = 4'd6;
localparam SPR_RD_B3    = 4'd7;
localparam SPR_ROMADDR  = 4'd8;
localparam SPR_ROMWAIT  = 4'd9;
localparam SPR_ROMWAIT2 = 4'd12;
localparam SPR_PIXELS   = 4'd10;
localparam SPR_NEXT     = 4'd11;

always_ff @(posedge clk_40m) begin
	if (!reset) begin
		spr_state         <= SPR_IDLE;
		spr_idx           <= 6'd0;
		prev_sprite_flipy <= 1'b0;
	end else begin
		case (spr_state)

			SPR_IDLE: begin
				if (cen_5m && base_h_cnt == 9'd256) begin
					next_scanline  <= v_cnt[7:0] + 8'd1;
					sprite_scan_addr <= 8'hFE;
					spr_state        <= SPR_INIT_RD;
				end
			end

			SPR_INIT_RD: begin
				spr_state <= SPR_INIT_LAT;
			end

			SPR_INIT_LAT: begin
				prev_sprite_flipy <= sprite_scan_D[7];
				spr_idx           <= 6'd0;
				sprite_scan_addr  <= 8'd0;
				spr_state         <= SPR_RD_B0;
			end

			SPR_RD_B0: begin
				sprite_scan_addr <= {spr_idx, 2'd1};
				spr_state        <= SPR_RD_B1;
			end

			SPR_RD_B1: begin
				spr_byte0        <= sprite_scan_D;
				sprite_scan_addr <= {spr_idx, 2'd2};
				spr_state        <= SPR_RD_B2;
			end

			SPR_RD_B2: begin
				spr_byte1        <= sprite_scan_D;
				sprite_scan_addr <= {spr_idx, 2'd3};
				spr_state        <= SPR_RD_B3;
			end

			SPR_RD_B3: begin
				spr_byte2 <= sprite_scan_D;
				spr_flipy <= prev_sprite_flipy;
				spr_state <= SPR_ROMADDR;
			end

			SPR_ROMADDR: begin
				spr_byte3         <= sprite_scan_D;
				prev_sprite_flipy <= spr_byte2[7];
				begin
					reg [8:0] raw_line;
					raw_line = master_flip ? ({1'b0, next_scanline} - {1'b0, spr_byte0} + 9'd1)
					                       : ({1'b0, next_scanline} - 9'd239 + {1'b0, spr_byte0});
					if (raw_line[8] || raw_line[7:4] != 4'd0) begin
						spr_state <= SPR_NEXT;
					end else begin
						reg [3:0] line_in_sprite;
						line_in_sprite  = (spr_flipy ^ master_flip) ? (4'd15 - raw_line[3:0]) : raw_line[3:0];
						spr_render_addr <= {spr_byte1, line_in_sprite};
						spr_state       <= SPR_ROMWAIT;
					end
				end
			end

			SPR_ROMWAIT: begin
				spr_state <= SPR_ROMWAIT2;
			end

			SPR_ROMWAIT2: begin
				spr_rom_r_lat <= spr_r_D;
				spr_rom_b_lat <= spr_b_D;
				spr_rom_g_lat <= spr_g_D;
				spr_pix_cnt <= 3'd0;
				spr_state <= SPR_PIXELS;
			end

			SPR_PIXELS: begin
				begin
					reg [2:0] bit_pos;
					reg [2:0] pixel_val;
					reg [7:0] x_pos;
					reg [7:0] x_base;
					bit_pos   = (spr_byte2[6] ^ master_flip) ? spr_pix_cnt : (3'd7 - spr_pix_cnt);
					pixel_val = {spr_rom_g_lat[bit_pos], spr_rom_b_lat[bit_pos], spr_rom_r_lat[bit_pos]};
					x_base    = master_flip ? (8'd248 - spr_byte3 - FLIP_SPR_ADJ) : spr_byte3;
					x_pos     = x_base + {5'd0, spr_pix_cnt} + 8'd0;
					if (pixel_val != 3'd0) begin
						if (~linebuf_sel)
							linebuf1[x_pos] <= pixel_val;
						else
							linebuf0[x_pos] <= pixel_val;
					end
					if (spr_pix_cnt == 3'd7)
						spr_state <= SPR_NEXT;
					else
						spr_pix_cnt <= spr_pix_cnt + 3'd1;
				end
			end

			SPR_NEXT: begin
				if (spr_idx == 6'd63)
					spr_state <= SPR_IDLE;
				else begin
					spr_idx          <= spr_idx + 6'd1;
					sprite_scan_addr <= {spr_idx + 6'd1, 2'd0};
					spr_state        <= SPR_RD_B0;
				end
			end

			default: spr_state <= SPR_IDLE;
		endcase
	end
end

wire [2:0] sprite_pixel       = linebuf_sel ? linebuf1[h_cnt[7:0] - 8'd3] : linebuf0[h_cnt[7:0] - 8'd3];

always_ff @(posedge clk_40m) begin
    if (cen_5m && visible_line) begin
        if (linebuf_sel)
            linebuf1[h_cnt[7:0] - 8'd3] <= 3'd0;
        else
            linebuf0[h_cnt[7:0] - 8'd3] <= 3'd0;
    end
end

wire       sprite_transparent = (sprite_pixel == 3'b000);

wire [4:0] r_sprite = sprite_pixel[0] ? 5'd31 : 5'd0;
wire [4:0] g_sprite = sprite_pixel[2] ? 5'd31 : 5'd0;
wire [4:0] b_sprite = sprite_pixel[1] ? 5'd31 : 5'd0;

wire [4:0] r_final = (tile_priority_latch && !tile_transparent) ? r_tile :
                     (!sprite_transparent)                       ? r_sprite :
                     r_tile;
wire [4:0] g_final = (tile_priority_latch && !tile_transparent) ? g_tile :
                     (!sprite_transparent)                       ? g_sprite :
                     g_tile;
wire [4:0] b_final = (tile_priority_latch && !tile_transparent) ? b_tile :
                     (!sprite_transparent)                       ? b_sprite :
                     b_tile;

assign red   = (hblk | vblk) ? 5'd0 : r_final;
assign green = (hblk | vblk) ? 5'd0 : g_final;
assign blue  = (hblk | vblk) ? 5'd0 : b_final;

endmodule
