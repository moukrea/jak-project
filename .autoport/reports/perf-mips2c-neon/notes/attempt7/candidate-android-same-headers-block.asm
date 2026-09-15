     6d4: f940a289     	ldr	x9, [x20, #0x140]
     6d8: f2400d3f     	tst	x9, #0xf
     6dc: 540038c1     	b.ne	0xdf4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdf4>
     6e0: f9400348     	ldr	x8, [x26]
     6e4: 927c6d29     	and	x9, x9, #0xfffffff0
     6e8: 8b09010a     	add	x10, x8, x9
     6ec: f9400949     	ldr	x9, [x10, #0x10]
     6f0: 3dc00140     	ldr	q0, [x10]
     6f4: f9001be9     	str	x9, [sp, #0x30]
     6f8: f940aa89     	ldr	x9, [x20, #0x150]
     6fc: b940194b     	ldr	w11, [x10, #0x18]
     700: f2400d3f     	tst	x9, #0xf
     704: b9003beb     	str	w11, [sp, #0x38]
     708: 54003941     	b.ne	0xe30 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe30>
     70c: 927c6d29     	and	x9, x9, #0xfffffff0
     710: bd438a81     	ldr	s1, [x20, #0x388]
     714: bd401d46     	ldr	s6, [x10, #0x1c]
     718: 8b090108     	add	x8, x8, x9
     71c: 3dc00951     	ldr	q17, [x10, #0x20]
     720: ad418905     	ldp	q5, q2, [x8, #0x30]
     724: bd401904     	ldr	s4, [x8, #0x18]
     728: b9806109     	ldrsw	x9, [x8, #0x60]
     72c: bd402d07     	ldr	s7, [x8, #0x2c]
     730: 4f819042     	fmul	v2.4s, v2.4s, v1.s[0]
     734: fd400901     	ldr	d1, [x8, #0x10]
     738: 5e140443     	mov	s3, v2.s[2]
     73c: 0e22d421     	fadd	v1.2s, v1.2s, v2.2s
     740: 1e232890     	fadd	s16, s4, s3
     744: 3cc1c103     	ldur	q3, [x8, #0x1c]
     748: bd438684     	ldr	s4, [x20, #0x384]
     74c: b9020289     	str	w9, [x20, #0x200]
     750: f9001a89     	str	x9, [x20, #0x30]
     754: 34000209     	cbz	w9, 0x794 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x794>
     758: 1e270132     	fmov	s18, w9
     75c: bd438e93     	ldr	s19, [x20, #0x38c]
     760: 1e270134     	fmov	s20, w9
     764: 131f7d2a     	asr	w10, w9, #31
     768: bd403a95     	ldr	s21, [x20, #0x38]
     76c: 1e323952     	fsub	s18, s10, s18
     770: 4e0c1d54     	mov	v20.s[1], w10
     774: 1e350a75     	fmul	s21, s19, s21
     778: 1e320a72     	fmul	s18, s19, s18
     77c: 0f93928b     	fmul	v11.2s, v20.2s, v19.s[0]
     780: 1e323952     	fsub	s18, s10, s18
     784: 6e0c0655     	mov	v21.s[1], v18.s[0]
     788: 0f929021     	fmul	v1.2s, v1.2s, v18.s[0]
     78c: 1e300a50     	fmul	s16, s18, s16
     790: 3d800bf5     	str	q21, [sp, #0x20]
     794: 0e0c0433     	dup	v19.2s, v1.s[1]
     798: 4f8490b2     	fmul	v18.4s, v5.4s, v4.s[0]
     79c: 1e210894     	fmul	s20, s4, s1
     7a0: bd033a90     	str	s16, [x20, #0x338]
     7a4: f9401bea     	ldr	x10, [sp, #0x30]
     7a8: bd034e87     	str	s7, [x20, #0x34c]
     7ac: f90002ca     	str	x10, [x22]
     7b0: b9403bea     	ldr	w10, [sp, #0x38]
     7b4: 6e0c0613     	mov	v19.s[1], v16.s[0]
     7b8: 4e32d635     	fadd	v21.4s, v17.4s, v18.4s
     7bc: 1e270891     	fmul	s17, s4, s7
     7c0: fd019a81     	str	d1, [x20, #0x330]
     7c4: 3d8002a3     	str	q3, [x21]
     7c8: b9000aca     	str	w10, [x22, #0x8]
     7cc: 6e180473     	mov	v19.d[1], v3.d[0]
     7d0: 4ea0eab0     	fcmlt	v16.4s, v21.4s, #0.0
     7d4: 1e3128c6     	fadd	s6, s6, s17
     7d8: ad1a8a85     	stp	q5, q2, [x20, #0x350]
     7dc: 4f849273     	fmul	v19.4s, v19.4s, v4.s[0]
     7e0: 4e701ea7     	bic	v7.16b, v21.16b, v16.16b
     7e4: bd031e86     	str	s6, [x20, #0x31c]
     7e8: 3d80ca87     	str	q7, [x20, #0x320]
     7ec: 6e136016     	ext	v22.16b, v0.16b, v19.16b, #0xc
     7f0: 6e040696     	mov	v22.s[0], v20.s[0]
     7f4: 4e36d400     	fadd	v0.4s, v0.4s, v22.4s
     7f8: 3d80c280     	str	q0, [x20, #0x300]
     7fc: 34000089     	cbz	w9, 0x80c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x80c>
     800: 3dc00be0     	ldr	q0, [sp, #0x20]
     804: fd01ba8b     	str	d11, [x20, #0x370]
     808: fd01be80     	str	d0, [x20, #0x378]
     80c: 0e0c3c29     	mov	w9, v1.s[1]
     810: 1e26002a     	fmov	w10, s1
     814: f9419e8b     	ldr	x11, [x20, #0x338]
     818: 5f839880     	fmul	s0, s4, v3.s[2]
     81c: 5fa39882     	fmul	s2, s4, v3.s[3]
     820: bd039294     	str	s20, [x20, #0x390]
     824: 3c8582b3     	stur	q19, [x21, #0x58]
     828: bd03ae91     	str	s17, [x20, #0x3ac]
     82c: aa098149     	orr	x9, x10, x9, lsl #32
     830: 3d80ee92     	str	q18, [x20, #0x3b0]
     834: bd03a680     	str	s0, [x20, #0x3a4]
     838: bd03aa82     	str	s2, [x20, #0x3a8]
     83c: a9012d09     	stp	x9, x11, [x8, #0x10]
     840: f940a288     	ldr	x8, [x20, #0x140]
     844: f2400d1f     	tst	x8, #0xf
     848: 540029c1     	b.ne	0xd80 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd80>
     84c: f9400349     	ldr	x9, [x26]
     850: f941828a     	ldr	x10, [x20, #0x300]
     854: 927c6d08     	and	x8, x8, #0xfffffff0
     858: f941868b     	ldr	x11, [x20, #0x308]
     85c: 8b080128     	add	x8, x9, x8
     860: a9002d0a     	stp	x10, x11, [x8]
     864: f940a288     	ldr	x8, [x20, #0x140]
     868: f2400d1f     	tst	x8, #0xf
     86c: 540028a1     	b.ne	0xd80 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd80>
     870: f9400349     	ldr	x9, [x26]
     874: f9418a8a     	ldr	x10, [x20, #0x310]
     878: 927c6d08     	and	x8, x8, #0xfffffff0
     87c: f9418e8b     	ldr	x11, [x20, #0x318]
     880: 8b080128     	add	x8, x9, x8
     884: a9012d0a     	stp	x10, x11, [x8, #0x10]
     888: f940a288     	ldr	x8, [x20, #0x140]
     88c: f2400d1f     	tst	x8, #0xf
     890: 54002781     	b.ne	0xd80 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd80>
     894: f9400349     	ldr	x9, [x26]
     898: f941928a     	ldr	x10, [x20, #0x320]
     89c: 927c6d08     	and	x8, x8, #0xfffffff0
     8a0: f941968b     	ldr	x11, [x20, #0x328]
     8a4: 8b080128     	add	x8, x9, x8
     8a8: a9022d0a     	stp	x10, x11, [x8, #0x20]
