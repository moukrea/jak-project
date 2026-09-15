     6c4: f940a289     	ldr	x9, [x20, #0x140]
     6c8: f2400d3f     	tst	x9, #0xf
     6cc: 54003721     	b.ne	0xdb0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb0>
     6d0: f9400348     	ldr	x8, [x26]
     6d4: 927c6d29     	and	x9, x9, #0xfffffff0
     6d8: 8b09010a     	add	x10, x8, x9
     6dc: f940aa89     	ldr	x9, [x20, #0x150]
     6e0: 3dc00140     	ldr	q0, [x10]
     6e4: f2400d3f     	tst	x9, #0xf
     6e8: 3d80c280     	str	q0, [x20, #0x300]
     6ec: 3dc00540     	ldr	q0, [x10, #0x10]
     6f0: 3d80c680     	str	q0, [x20, #0x310]
     6f4: 3dc00940     	ldr	q0, [x10, #0x20]
     6f8: 3d80ca80     	str	q0, [x20, #0x320]
     6fc: 540035a1     	b.ne	0xdb0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb0>
     700: 927c6d29     	and	x9, x9, #0xfffffff0
     704: 8b090108     	add	x8, x8, x9
     708: 3dc00500     	ldr	q0, [x8, #0x10]
     70c: 3d80ce80     	str	q0, [x20, #0x330]
     710: 3dc00900     	ldr	q0, [x8, #0x20]
     714: bd433284     	ldr	s4, [x20, #0x330]
     718: 3d80d280     	str	q0, [x20, #0x340]
     71c: 3dc00d00     	ldr	q0, [x8, #0x30]
     720: 3d80d680     	str	q0, [x20, #0x350]
     724: 3dc01100     	ldr	q0, [x8, #0x40]
     728: 3d80da80     	str	q0, [x20, #0x360]
     72c: bd438a80     	ldr	s0, [x20, #0x388]
     730: bd436281     	ldr	s1, [x20, #0x360]
     734: fd4032a2     	ldr	d2, [x21, #0x60]
     738: bd436e83     	ldr	s3, [x20, #0x36c]
     73c: b9806109     	ldrsw	x9, [x8, #0x60]
     740: 1e200821     	fmul	s1, s1, s0
     744: 0f809042     	fmul	v2.2s, v2.2s, v0.s[0]
     748: 1e200863     	fmul	s3, s3, s0
     74c: fd401aa0     	ldr	d0, [x21, #0x30]
     750: b9020289     	str	w9, [x20, #0x200]
     754: f9001a89     	str	x9, [x20, #0x30]
     758: bd036281     	str	s1, [x20, #0x360]
     75c: 1e242821     	fadd	s1, s1, s4
     760: 0e20d440     	fadd	v0.2s, v2.2s, v0.2s
     764: fd0032a2     	str	d2, [x21, #0x60]
     768: bd438e82     	ldr	s2, [x20, #0x38c]
     76c: bd036e83     	str	s3, [x20, #0x36c]
     770: bd033281     	str	s1, [x20, #0x330]
     774: fd001aa0     	str	d0, [x21, #0x30]
     778: 34000249     	cbz	w9, 0x7c0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x7c0>
     77c: 1e270123     	fmov	s3, w9
     780: f9401e8a     	ldr	x10, [x20, #0x38]
     784: 9e670124     	fmov	d4, x9
     788: f901be8a     	str	x10, [x20, #0x378]
     78c: 1e233943     	fsub	s3, s10, s3
     790: bd437a85     	ldr	s5, [x20, #0x378]
     794: 0f829084     	fmul	v4.2s, v4.2s, v2.s[0]
     798: 1e230843     	fmul	s3, s2, s3
     79c: 1e250842     	fmul	s2, s2, s5
     7a0: fd01ba84     	str	d4, [x20, #0x370]
     7a4: 1e233943     	fsub	s3, s10, s3
     7a8: bd037a82     	str	s2, [x20, #0x378]
     7ac: 1e230821     	fmul	s1, s1, s3
     7b0: 0f839000     	fmul	v0.2s, v0.2s, v3.s[0]
     7b4: bd037e83     	str	s3, [x20, #0x37c]
     7b8: bd033281     	str	s1, [x20, #0x330]
     7bc: fd001aa0     	str	d0, [x21, #0x30]
     7c0: bd438682     	ldr	s2, [x20, #0x384]
     7c4: 910d7289     	add	x9, x20, #0x35c
     7c8: fd41aa84     	ldr	d4, [x20, #0x350]
     7cc: bd433e85     	ldr	s5, [x20, #0x33c]
     7d0: fd4022b0     	ldr	d16, [x21, #0x40]
     7d4: 1e26000a     	fmov	w10, s0
     7d8: 4ea21c43     	mov	v3.16b, v2.16b
     7dc: 4ea21c46     	mov	v6.16b, v2.16b
     7e0: bd434e92     	ldr	s18, [x20, #0x34c]
     7e4: 6e0c0445     	mov	v5.s[1], v2.s[0]
     7e8: 3dc0ca93     	ldr	q19, [x20, #0x320]
     7ec: 0f829011     	fmul	v17.2s, v0.2s, v2.s[0]
     7f0: f9419e8b     	ldr	x11, [x20, #0x338]
     7f4: 0d409123     	ld1	{ v3.s }[1], [x9]
     7f8: 910d6289     	add	x9, x20, #0x358
     7fc: 4d408124     	ld1	{ v4.s }[2], [x9]
     800: 910d0289     	add	x9, x20, #0x340
     804: 4e0c04a7     	dup	v7.4s, v5.s[1]
     808: 0d409126     	ld1	{ v6.s }[1], [x9]
     80c: 1e260029     	fmov	w9, s1
     810: 4e833863     	zip1	v3.4s, v3.4s, v3.4s
     814: fd004ab1     	str	d17, [x21, #0x90]
     818: 6e1c0444     	mov	v4.s[3], v2.s[0]
     81c: 4e8738a5     	zip1	v5.4s, v5.4s, v7.4s
     820: 6e180606     	mov	v6.d[1], v16.d[0]
     824: bd430287     	ldr	s7, [x20, #0x300]
     828: fd4002b0     	ldr	d16, [x21]
     82c: aa0a8129     	orr	x9, x9, x10, lsl #32
     830: 6e140443     	mov	v3.s[2], v2.s[0]
     834: 6e23dc83     	fmul	v3.4s, v4.4s, v3.4s
     838: 1e220824     	fmul	s4, s1, s2
     83c: 1e320842     	fmul	s2, s2, s18
     840: 4e33d472     	fadd	v18.4s, v3.4s, v19.4s
     844: 1e272887     	fadd	s7, s4, s7
     848: bd039284     	str	s4, [x20, #0x390]
     84c: 6e26dca4     	fmul	v4.4s, v5.4s, v6.4s
     850: 0e30d625     	fadd	v5.2s, v17.2s, v16.2s
     854: bd431e93     	ldr	s19, [x20, #0x31c]
     858: bd430e86     	ldr	s6, [x20, #0x30c]
     85c: bd03ae82     	str	s2, [x20, #0x3ac]
     860: 1e222a62     	fadd	s2, s19, s2
     864: 3d80ee83     	str	q3, [x20, #0x3b0]
     868: 4ea0ea50     	fcmlt	v16.4s, v18.4s, #0.0
     86c: bd030287     	str	s7, [x20, #0x300]
     870: fd0002a5     	str	d5, [x21]
     874: 1e262885     	fadd	s5, s4, s6
     878: 3c8982a4     	stur	q4, [x21, #0x98]
     87c: bd031e82     	str	s2, [x20, #0x31c]
     880: 4e701e41     	bic	v1.16b, v18.16b, v16.16b
     884: bd030e85     	str	s5, [x20, #0x30c]
     888: 3d80ca81     	str	q1, [x20, #0x320]
     88c: a9012d09     	stp	x9, x11, [x8, #0x10]
     890: f940a288     	ldr	x8, [x20, #0x140]
     894: f2400d1f     	tst	x8, #0xf
     898: 54002ae1     	b.ne	0xdf4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdf4>
     89c: f9400349     	ldr	x9, [x26]
     8a0: f941828a     	ldr	x10, [x20, #0x300]
     8a4: 927c6d08     	and	x8, x8, #0xfffffff0
     8a8: f941868b     	ldr	x11, [x20, #0x308]
     8ac: 8b080128     	add	x8, x9, x8
     8b0: a9002d0a     	stp	x10, x11, [x8]
     8b4: f940a288     	ldr	x8, [x20, #0x140]
     8b8: f2400d1f     	tst	x8, #0xf
     8bc: 540029c1     	b.ne	0xdf4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdf4>
     8c0: f9400349     	ldr	x9, [x26]
     8c4: f9418a8a     	ldr	x10, [x20, #0x310]
     8c8: 927c6d08     	and	x8, x8, #0xfffffff0
     8cc: f9418e8b     	ldr	x11, [x20, #0x318]
     8d0: 8b080128     	add	x8, x9, x8
     8d4: a9012d0a     	stp	x10, x11, [x8, #0x10]
     8d8: f940a288     	ldr	x8, [x20, #0x140]
     8dc: f2400d1f     	tst	x8, #0xf
     8e0: 540028a1     	b.ne	0xdf4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdf4>
     8e4: f9400349     	ldr	x9, [x26]
     8e8: f941928a     	ldr	x10, [x20, #0x320]
     8ec: 927c6d08     	and	x8, x8, #0xfffffff0
     8f0: f941968b     	ldr	x11, [x20, #0x328]
     8f4: 8b080128     	add	x8, x9, x8
     8f8: a9022d0a     	stp	x10, x11, [x8, #0x20]
