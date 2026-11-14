//============================================================================
//
//  Blue Print sound PCB model
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

module BluePrint_SND
(
	input                reset,
	input				 pause,
	input                clk_40m,

	input          [7:0] sound_cmd,
	input                sound_cmd_wr,

	input         [15:0] dip_sw,          // [7:0] = bank 1, [15:8] = bank 2

	output         [7:0] dipsw_readback,

	output signed [15:0] sound,

	input                vblank,

	output chip_pool_pkg::z80_i_t  z80_1_i,
	input  chip_pool_pkg::z80_o_t  z80_1_o,
	output chip_pool_pkg::ay_i_t   ay_0_i,
	input  chip_pool_pkg::ayio_o_t ay_0_o,
	output chip_pool_pkg::ay_i_t   ay_1_i,
	input  chip_pool_pkg::ayio_o_t ay_1_o,

	output        [11:0] rom_snd_a,
	input          [7:0] rom1_D, rom2_D,

	output ram_pool_pkg::pram_i_t pr_i,
	input  ram_pool_pkg::pram_o_t pr_o
);

wire cen_1m25, cen_0m625;
jtframe_frac_cen #(2) sound_cen
(
	.clk(clk_40m),
	.n(10'd1),
	.m(10'd32),
	.cen({cen_0m625, cen_1m25})
);

reg [8:0] div = 9'd0;
always_ff @(posedge clk_40m) begin
	div <= div + 9'd1;
end
wire cen_dcrm = !div;

wire [15:0] sound_A;
wire [7:0] sound_Dout;
wire n_m1, n_mreq, n_iorq, n_rd, n_wr, n_rfsh;
assign sound_A    = z80_1_o.a;
assign sound_Dout = z80_1_o.dout;
assign n_m1       = z80_1_o.m1_n;
assign n_mreq     = z80_1_o.mreq_n;
assign n_iorq     = z80_1_o.iorq_n;
assign n_rd       = z80_1_o.rd_n;
assign n_wr       = z80_1_o.wr_n;
assign n_rfsh     = z80_1_o.rfsh_n;

wire cs_rom1 = ~n_mreq & n_rfsh & ~sound_A[15] & ~sound_A[14] & ~sound_A[13];
wire cs_rom2 = ~n_mreq & n_rfsh & ~sound_A[15] & ~sound_A[14] &  sound_A[13];
wire cs_ram  = ~n_mreq & n_rfsh & ~sound_A[15] &  sound_A[14] & ~sound_A[13];
wire cs_ay1_w = ~n_mreq & n_rfsh & ~sound_A[15] & sound_A[14] & sound_A[13] & ~n_wr;
wire cs_ay1_r = ~n_mreq & n_rfsh & ~sound_A[15] & sound_A[14] & sound_A[13] & ~n_rd;
wire cs_ay2_w = ~n_mreq & n_rfsh &  sound_A[15] & ~sound_A[14] & ~sound_A[13] & ~n_wr;
wire cs_ay2_r = ~n_mreq & n_rfsh &  sound_A[15] & ~sound_A[14] & ~sound_A[13] & ~n_rd;

wire ay1_bdir = cs_ay1_w & (sound_A[1:0] != 2'b10);
wire ay1_bc1  = (cs_ay1_w & ~sound_A[0] & ~sound_A[1]) |
                (cs_ay1_r & sound_A[1]);

wire ay2_bdir = cs_ay2_w & (sound_A[1:0] != 2'b10);
wire ay2_bc1  = (cs_ay2_w & ~sound_A[0] & ~sound_A[1]) |
                (cs_ay2_r & sound_A[1]);

wire ay1_reading = ~ay1_bdir & ay1_bc1;
wire ay2_reading = ~ay2_bdir & ay2_bc1;

wire [7:0] sound_Din = cs_rom1           ? rom1_D :
                       cs_rom2           ? rom2_D :
                       (cs_ram & n_wr)   ? sndram_D :
                       ay1_reading       ? ay1_D :
                       ay2_reading       ? ay2_D :
                       8'hFF;

assign rom_snd_a = sound_A[11:0];

wire [7:0] sndram_D;
assign pr_i.a_addr = 16'(sound_A[9:0]);
assign pr_i.a_d    = sound_Dout;
assign pr_i.a_we   = cs_ram & ~n_wr;
assign pr_i.b_addr = 16'd0;
assign pr_i.b_d    = 8'd0;
assign pr_i.b_we   = 1'b0;
assign sndram_D    = pr_o.a_q;

reg [12:0] irq_cnt = 13'd0;
reg irq_pulse = 1'b0;
always_ff @(posedge clk_40m) begin
	if (cen_1m25) begin
		if (irq_cnt == 13'd5207) begin
			irq_cnt <= 13'd0;
			irq_pulse <= 1'b1;
		end else begin
			irq_cnt <= irq_cnt + 13'd1;
			irq_pulse <= 1'b0;
		end
	end else
		irq_pulse <= 1'b0;
end

wire irq_clr = (~reset | ~(n_iorq | n_m1));
reg n_irq = 1'b1;
always_ff @(posedge clk_40m or posedge irq_clr) begin
	if (irq_clr)
		n_irq <= 1'b1;
	else if (irq_pulse)
		n_irq <= 1'b0;
end

reg n_nmi = 1'b1;
reg sound_cmd_wr_last = 1'b0;
always_ff @(posedge clk_40m) begin
	sound_cmd_wr_last <= sound_cmd_wr;
	if (!sound_cmd_wr_last && sound_cmd_wr)
		n_nmi <= 1'b0;
	else if (cen_1m25)
		n_nmi <= 1'b1;
end

wire [7:0] ay1_D;
wire [7:0] ay1A_raw, ay1B_raw, ay1C_raw;
assign ay_0_i.ce     = cen_1m25 & ~pause;
assign ay_0_i.bdir   = ay1_bdir;
assign ay_0_i.bc1    = ay1_bc1;
assign ay_0_i.din    = sound_Dout;
assign ay_0_i.ioa_in = 8'd0;
assign ay_0_i.iob_in = sound_cmd;
assign ay1_D      = ay_0_o.dout;
assign ay1A_raw   = ay_0_o.a;
assign ay1B_raw   = ay_0_o.b;
assign ay1C_raw   = ay_0_o.c;
assign dipsw_readback = ay_0_o.ioa_out;

wire [7:0] ay2_D;
wire [7:0] ay2A_raw, ay2B_raw, ay2C_raw;
assign ay_1_i.ce     = cen_0m625 & ~pause;
assign ay_1_i.bdir   = ay2_bdir;
assign ay_1_i.bc1    = ay2_bc1;
assign ay_1_i.din    = sound_Dout;
assign ay_1_i.ioa_in = dip_sw[7:0];
assign ay_1_i.iob_in = dip_sw[15:8];
assign ay2_D      = ay_1_o.dout;
assign ay2A_raw   = ay_1_o.a;
assign ay2B_raw   = ay_1_o.b;
assign ay2C_raw   = ay_1_o.c;

wire signed [15:0] ay1A_dcrm, ay1B_dcrm, ay1C_dcrm, ay2A_dcrm, ay2B_dcrm, ay2C_dcrm;
jt49_dcrm2 #(16) dcrm_ay1A
(
	.clk(clk_40m),
	.cen(cen_dcrm),
	.rst(~reset),
	.din({3'd0, ay1A_raw, 5'd0}),
	.dout(ay1A_dcrm)
);
jt49_dcrm2 #(16) dcrm_ay1B
(
	.clk(clk_40m),
	.cen(cen_dcrm),
	.rst(~reset),
	.din({3'd0, ay1B_raw, 5'd0}),
	.dout(ay1B_dcrm)
);
jt49_dcrm2 #(16) dcrm_ay1C
(
	.clk(clk_40m),
	.cen(cen_dcrm),
	.rst(~reset),
	.din({3'd0, ay1C_raw, 5'd0}),
	.dout(ay1C_dcrm)
);
jt49_dcrm2 #(16) dcrm_ay2A
(
	.clk(clk_40m),
	.cen(cen_dcrm),
	.rst(~reset),
	.din({3'd0, ay2A_raw, 5'd0}),
	.dout(ay2A_dcrm)
);
jt49_dcrm2 #(16) dcrm_ay2B
(
	.clk(clk_40m),
	.cen(cen_dcrm),
	.rst(~reset),
	.din({3'd0, ay2B_raw, 5'd0}),
	.dout(ay2B_dcrm)
);
jt49_dcrm2 #(16) dcrm_ay2C
(
	.clk(clk_40m),
	.cen(cen_dcrm),
	.rst(~reset),
	.din({3'd0, ay2C_raw, 5'd0}),
	.dout(ay2C_dcrm)
);

assign sound = 16'hFFFF - (ay1A_dcrm + ay1B_dcrm + ay1C_dcrm + ay2A_dcrm + ay2B_dcrm + ay2C_dcrm);

assign z80_1_i.ce    = cen_1m25 & ~pause;
assign z80_1_i.int_n = n_irq;
assign z80_1_i.nmi_n = n_nmi;
assign z80_1_i.di    = sound_Din;

endmodule
