//============================================================================
//
//  Blue Print dispatcher: shared CPU / AY / ROM / RAM pools + the board (rtl/boards/blueprint/)
//  Copyright (C) 2021 Ace
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

module blueprint_dispatcher
(
	input                reset,
	input                clk_40m,

	input          [7:0] p1_controls,
	input          [7:0] p2_controls,

	input         [15:0] dip_sw,

	output               video_hsync, video_vsync, video_csync,
	output               video_hblank, video_vblank,
	output               ce_pix,
	output         [4:0] video_r, video_g, video_b,

	output signed [15:0] sound,

	input                crt_flip,

	input          [3:0] h_center, v_center,

	input         [24:0] ioctl_addr,
	input          [7:0] ioctl_data,
	input                ioctl_wr,
	input          [7:0] ioctl_index,

	input                pause,

	input         [15:0] hs_address,
	input          [7:0] hs_data_in,
	output         [7:0] hs_data_out,
	input                hs_write
);

wire [7:0] sound_cmd;
wire       sound_cmd_wr;
wire [7:0] dipsw_readback_from_snd;
wire [7:0] dipsw_readback = dipsw_readback_from_snd;

wire main1_cs_i, main2_cs_i, main3_cs_i, main4_cs_i, main5_cs_i, main6_cs_i;
wire tile0_cs_i, tile1_cs_i;
wire spr_r_cs_i, spr_b_cs_i, spr_g_cs_i;

wire ioctl_wr_cpu = ioctl_wr && (ioctl_index == 8'd0);
wire ioctl_wr_snd = ioctl_wr && (ioctl_index == 8'd1);

wire snd_rom1_cs_i = (ioctl_addr < 25'h1000);
wire snd_rom2_cs_i = (ioctl_addr >= 25'h1000) && (ioctl_addr < 25'h2000);

selector DLSEL
(
	.ioctl_addr(ioctl_addr),
	.main1_cs(main1_cs_i),
	.main2_cs(main2_cs_i),
	.main3_cs(main3_cs_i),
	.main4_cs(main4_cs_i),
	.main5_cs(main5_cs_i),
	.main6_cs(main6_cs_i),
	.tile0_cs(tile0_cs_i),
	.tile1_cs(tile1_cs_i),
	.spr_r_cs(spr_r_cs_i),
	.spr_b_cs(spr_b_cs_i),
	.spr_g_cs(spr_g_cs_i)
);

/////////////////////////////  Shared ROM blocks  /////////////////////////////

wire [11:0] rom_cpu_a, rom_tile_a, rom_spr_a, rom_snd_a;
wire  [7:0] rom1_D, rom2_D, rom3_D, rom4_D, rom5_D, rom6_D, tile0_D, tile1_D, spr_r_D, spr_b_D, spr_g_D, snd1_D, snd2_D;
eprom_4k main_rom1(.CLK(clk_40m), .ADDR(rom_cpu_a), .CLK_DL(clk_40m), .ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(main1_cs_i), .WR(ioctl_wr_cpu), .DATA(rom1_D));
eprom_4k main_rom2(.CLK(clk_40m), .ADDR(rom_cpu_a), .CLK_DL(clk_40m), .ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(main2_cs_i), .WR(ioctl_wr_cpu), .DATA(rom2_D));
eprom_4k main_rom3(.CLK(clk_40m), .ADDR(rom_cpu_a), .CLK_DL(clk_40m), .ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(main3_cs_i), .WR(ioctl_wr_cpu), .DATA(rom3_D));
eprom_4k main_rom4(.CLK(clk_40m), .ADDR(rom_cpu_a), .CLK_DL(clk_40m), .ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(main4_cs_i), .WR(ioctl_wr_cpu), .DATA(rom4_D));
eprom_4k main_rom5(.CLK(clk_40m), .ADDR(rom_cpu_a), .CLK_DL(clk_40m), .ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(main5_cs_i), .WR(ioctl_wr_cpu), .DATA(rom5_D));
eprom_4k main_rom6(.CLK(clk_40m), .ADDR(rom_cpu_a), .CLK_DL(clk_40m), .ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(main6_cs_i), .WR(ioctl_wr_cpu), .DATA(rom6_D));
eprom_4k tile_rom0(.CLK(clk_40m), .ADDR(rom_tile_a), .CLK_DL(clk_40m), .ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(tile0_cs_i), .WR(ioctl_wr_cpu), .DATA(tile0_D));
eprom_4k tile_rom1(.CLK(clk_40m), .ADDR(rom_tile_a), .CLK_DL(clk_40m), .ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(tile1_cs_i), .WR(ioctl_wr_cpu), .DATA(tile1_D));
eprom_4k spr_rom_r(.CLK(clk_40m), .ADDR(rom_spr_a),  .CLK_DL(clk_40m), .ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(spr_r_cs_i), .WR(ioctl_wr_cpu), .DATA(spr_r_D));
eprom_4k spr_rom_b(.CLK(clk_40m), .ADDR(rom_spr_a),  .CLK_DL(clk_40m), .ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(spr_b_cs_i), .WR(ioctl_wr_cpu), .DATA(spr_b_D));
eprom_4k spr_rom_g(.CLK(clk_40m), .ADDR(rom_spr_a),  .CLK_DL(clk_40m), .ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(spr_g_cs_i), .WR(ioctl_wr_cpu), .DATA(spr_g_D));
eprom_4k snd_rom1 (.CLK(clk_40m), .ADDR(rom_snd_a),  .CLK_DL(clk_40m), .ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(snd_rom1_cs_i), .WR(ioctl_wr_snd), .DATA(snd1_D));
eprom_4k snd_rom2 (.CLK(clk_40m), .ADDR(rom_snd_a),  .CLK_DL(clk_40m), .ADDR_DL(ioctl_addr), .DATA_IN(ioctl_data), .CS_DL(snd_rom2_cs_i), .WR(ioctl_wr_snd), .DATA(snd2_D));

/////////////////////////////  Chip pool  /////////////////////////////

chip_pool_pkg::z80_i_t  z80_0_i, z80_1_i;
chip_pool_pkg::z80_o_t  z80_0_o, z80_1_o;
chip_pool_pkg::ay_i_t   ay_0_i, ay_1_i;
chip_pool_pkg::ayio_o_t ay_0_o, ay_1_o;

t80sv_T80s z80_0
(
	.RESET_n(reset), .CLK(clk_40m), .CEN(z80_0_i.ce), .WAIT_n(1'b1), .INT_n(z80_0_i.int_n), .NMI_n(z80_0_i.nmi_n),
	.BUSRQ_n(1'b1), .M1_n(z80_0_o.m1_n), .MREQ_n(z80_0_o.mreq_n), .IORQ_n(z80_0_o.iorq_n), .RD_n(z80_0_o.rd_n),
	.WR_n(z80_0_o.wr_n), .RFSH_n(z80_0_o.rfsh_n), .A(z80_0_o.a), .DI(z80_0_i.di), .DO(z80_0_o.dout)
);

t80sv_T80s z80_1
(
	.RESET_n(reset), .CLK(clk_40m), .CEN(z80_1_i.ce), .WAIT_n(1'b1), .INT_n(z80_1_i.int_n), .NMI_n(z80_1_i.nmi_n),
	.BUSRQ_n(1'b1), .M1_n(z80_1_o.m1_n), .MREQ_n(z80_1_o.mreq_n), .IORQ_n(z80_1_o.iorq_n), .RD_n(z80_1_o.rd_n),
	.WR_n(z80_1_o.wr_n), .RFSH_n(z80_1_o.rfsh_n), .A(z80_1_o.a), .DI(z80_1_i.di), .DO(z80_1_o.dout)
);

jt49_bus #(.COMP(3'b100)) ay_0
(
	.rst_n(reset), .clk(clk_40m), .clk_en(ay_0_i.ce), .bdir(ay_0_i.bdir), .bc1(ay_0_i.bc1), .din(ay_0_i.din), .sel(1'b1),
	.dout(ay_0_o.dout), .sound(ay_0_o.sound), .A(ay_0_o.a), .B(ay_0_o.b), .C(ay_0_o.c), .sample(),
	.IOA_in(ay_0_i.ioa_in), .IOA_out(ay_0_o.ioa_out), .IOB_in(ay_0_i.iob_in), .IOB_out(ay_0_o.iob_out)
);

jt49_bus #(.COMP(3'b100)) ay_1
(
	.rst_n(reset), .clk(clk_40m), .clk_en(ay_1_i.ce), .bdir(ay_1_i.bdir), .bc1(ay_1_i.bc1), .din(ay_1_i.din), .sel(1'b1),
	.dout(ay_1_o.dout), .sound(ay_1_o.sound), .A(ay_1_o.a), .B(ay_1_o.b), .C(ay_1_o.c), .sample(),
	.IOA_in(ay_1_i.ioa_in), .IOA_out(ay_1_o.ioa_out), .IOB_in(ay_1_i.iob_in), .IOB_out(ay_1_o.iob_out)
);

/////////////////////////////  Board RAM pool  /////////////////////////////

ram_pool_pkg::pram_i_t [5:0] pool_i;
ram_pool_pkg::pram_o_t [5:0] pool_o;

dpram_dc #(.widthad_a(11)) ram_0
(
	.clock_a(clk_40m), .wren_a(pool_i[0].a_we), .address_a(pool_i[0].a_addr[10:0]), .data_a(pool_i[0].a_d), .q_a(pool_o[0].a_q),
	.clock_b(clk_40m), .wren_b(pool_i[0].b_we), .address_b(pool_i[0].b_addr[10:0]), .data_b(pool_i[0].b_d), .q_b(pool_o[0].b_q)
);

dpram_dc #(.widthad_a(10)) ram_1
(
	.clock_a(clk_40m), .wren_a(pool_i[1].a_we), .address_a(pool_i[1].a_addr[9:0]), .data_a(pool_i[1].a_d), .q_a(pool_o[1].a_q),
	.clock_b(clk_40m), .wren_b(pool_i[1].b_we), .address_b(pool_i[1].b_addr[9:0]), .data_b(pool_i[1].b_d), .q_b(pool_o[1].b_q)
);

dpram_dc #(.widthad_a(10)) ram_2
(
	.clock_a(clk_40m), .wren_a(pool_i[2].a_we), .address_a(pool_i[2].a_addr[9:0]), .data_a(pool_i[2].a_d), .q_a(pool_o[2].a_q),
	.clock_b(clk_40m), .wren_b(pool_i[2].b_we), .address_b(pool_i[2].b_addr[9:0]), .data_b(pool_i[2].b_d), .q_b(pool_o[2].b_q)
);

dpram_dc #(.widthad_a(8)) ram_3
(
	.clock_a(clk_40m), .wren_a(pool_i[3].a_we), .address_a(pool_i[3].a_addr[7:0]), .data_a(pool_i[3].a_d), .q_a(pool_o[3].a_q),
	.clock_b(clk_40m), .wren_b(pool_i[3].b_we), .address_b(pool_i[3].b_addr[7:0]), .data_b(pool_i[3].b_d), .q_b(pool_o[3].b_q)
);

dpram_dc #(.widthad_a(8)) ram_4
(
	.clock_a(clk_40m), .wren_a(pool_i[4].a_we), .address_a(pool_i[4].a_addr[7:0]), .data_a(pool_i[4].a_d), .q_a(pool_o[4].a_q),
	.clock_b(clk_40m), .wren_b(pool_i[4].b_we), .address_b(pool_i[4].b_addr[7:0]), .data_b(pool_i[4].b_d), .q_b(pool_o[4].b_q)
);

dpram_dc #(.widthad_a(10)) ram_5
(
	.clock_a(clk_40m), .wren_a(pool_i[5].a_we), .address_a(pool_i[5].a_addr[9:0]), .data_a(pool_i[5].a_d), .q_a(pool_o[5].a_q),
	.clock_b(clk_40m), .wren_b(pool_i[5].b_we), .address_b(pool_i[5].b_addr[9:0]), .data_b(pool_i[5].b_d), .q_b(pool_o[5].b_q)
);

/////////////////////////////  Board  /////////////////////////////

BluePrint_CPU main_pcb
(
	.reset(reset),
	.clk_40m(clk_40m),

	.red(video_r),
	.green(video_g),
	.blue(video_b),
	.video_hsync(video_hsync),
	.video_vsync(video_vsync),
	.video_csync(video_csync),
	.video_hblank(video_hblank),
	.video_vblank(video_vblank),
	.ce_pix(ce_pix),

	.p1_controls(p1_controls),
	.p2_controls(p2_controls),
	.dipsw_readback(dipsw_readback),

	.sound_cmd(sound_cmd),
	.sound_cmd_wr(sound_cmd_wr),

	.crt_flip(crt_flip),
	.h_center(h_center),
	.v_center(v_center),

	.z80_0_i(z80_0_i), .z80_0_o(z80_0_o),
	.rom_cpu_a(rom_cpu_a),
	.rom1_D(rom1_D), .rom2_D(rom2_D), .rom3_D(rom3_D), .rom4_D(rom4_D), .rom5_D(rom5_D), .rom6_D(rom6_D),
	.rom_tile_a(rom_tile_a), .tile0_D(tile0_D), .tile1_D(tile1_D),
	.rom_spr_a(rom_spr_a), .spr_r_D(spr_r_D), .spr_b_D(spr_b_D), .spr_g_D(spr_g_D),
	.pr_i(pool_i[4:0]), .pr_o(pool_o[4:0]),

	.pause(pause),

	.hs_address(hs_address),
	.hs_data_out(hs_data_out),
	.hs_data_in(hs_data_in),
	.hs_write(hs_write)
);

BluePrint_SND sound_pcb
(
	.reset(reset),
	.pause(pause),
	.clk_40m(clk_40m),
	.sound_cmd(sound_cmd),
	.sound_cmd_wr(sound_cmd_wr),
	.dip_sw(dip_sw),
	.dipsw_readback(dipsw_readback_from_snd),
	.sound(sound),
	.vblank(video_vblank),
	.z80_1_i(z80_1_i), .z80_1_o(z80_1_o),
	.ay_0_i(ay_0_i), .ay_0_o(ay_0_o), .ay_1_i(ay_1_i), .ay_1_o(ay_1_o),
	.rom_snd_a(rom_snd_a), .rom1_D(snd1_D), .rom2_D(snd2_D),
	.pr_i(pool_i[5]), .pr_o(pool_o[5])
);

endmodule
