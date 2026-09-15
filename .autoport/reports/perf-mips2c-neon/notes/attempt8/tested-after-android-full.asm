$ aarch64-linux-gnu-objdump -drwC /home/emeric/code/jak-project/.autoport/reports/perf-mips2c-neon/notes/attempt8/tested-after-android.o

/home/emeric/code/jak-project/.autoport/reports/perf-mips2c-neon/notes/attempt8/tested-after-android.o:     file format elf64-littleaarch64


Disassembly of section .text._ZN6Mips2C4jak119sp_process_block_3d7executeEPv:

0000000000000000 <Mips2C::jak1::sp_process_block_3d::execute(void*)>:
   0:	d10443ff 	sub	sp, sp, #0x110
   4:	fd0043ec 	str	d12, [sp, #128]
   8:	6d092beb 	stp	d11, d10, [sp, #144]
   c:	6d0a23e9 	stp	d9, d8, [sp, #160]
  10:	a90b7bfd 	stp	x29, x30, [sp, #176]
  14:	a90c6ffc 	stp	x28, x27, [sp, #192]
  18:	a90d67fa 	stp	x26, x25, [sp, #208]
  1c:	a90e5ff8 	stp	x24, x23, [sp, #224]
  20:	a90f57f6 	stp	x22, x21, [sp, #240]
  24:	a9104ff4 	stp	x20, x19, [sp, #256]
  28:	9102c3fd 	add	x29, sp, #0xb0
  2c:	d53bd048 	mrs	x8, tpidr_el0
  30:	aa0003f4 	mov	x20, x0
  34:	f9000fe8 	str	x8, [sp, #24]
  38:	f9401508 	ldr	x8, [x8, #40]
  3c:	f81c03a8 	stur	x8, [x29, #-64]
  40:	94000000 	bl	0 <std::__ndk1::chrono::steady_clock::now()>	40: R_AARCH64_CALL26	std::__ndk1::chrono::steady_clock::now()
  44:	f9000be0 	str	x0, [sp, #16]
  48:	90000019 	adrp	x25, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	48: R_AARCH64_ADR_GOT_PAGE	g_spart_prof
  4c:	52800020 	mov	w0, #0x1                   	// #1
  50:	f9400339 	ldr	x25, [x25]	50: R_AARCH64_LD64_GOT_LO12_NC	g_spart_prof
  54:	91008321 	add	x1, x25, #0x20
  58:	94000000 	bl	0 <__aarch64_ldadd8_relax>	58: R_AARCH64_CALL26	__aarch64_ldadd8_relax
  5c:	9000001a 	adrp	x26, 0 <g_ee_main_mem>	5c: R_AARCH64_ADR_GOT_PAGE	g_ee_main_mem
  60:	f940ea88 	ldr	x8, [x20, #464]
  64:	aa1403fb 	mov	x27, x20
  68:	f940035a 	ldr	x26, [x26]	68: R_AARCH64_LD64_GOT_LO12_NC	g_ee_main_mem
  6c:	f940fa8a 	ldr	x10, [x20, #496]
  70:	9000001c 	adrp	x28, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	70: R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_3d::cache
  74:	d1028108 	sub	x8, x8, #0xa0
  78:	f9400349 	ldr	x9, [x26]
  7c:	f900ea88 	str	x8, [x20, #464]
  80:	f828492a 	str	x10, [x9, w8, uxtw]
  84:	f9400348 	ldr	x8, [x26]
  88:	b941d289 	ldr	w9, [x20, #464]
  8c:	f940f28a 	ldr	x10, [x20, #480]
  90:	8b090108 	add	x8, x8, x9
  94:	f900050a 	str	x10, [x8, #8]
  98:	b941d288 	ldr	w8, [x20, #464]
  9c:	f940ca89 	ldr	x9, [x20, #400]
  a0:	f940034a 	ldr	x10, [x26]
  a4:	3dc04280 	ldr	q0, [x20, #256]
  a8:	1100c108 	add	w8, w8, #0x30
  ac:	f900f289 	str	x9, [x20, #480]
  b0:	927c6d08 	and	x8, x8, #0xfffffff0
  b4:	3ca86940 	str	q0, [x10, x8]
  b8:	b941d288 	ldr	w8, [x20, #464]
  bc:	f9400349 	ldr	x9, [x26]
  c0:	3dc04680 	ldr	q0, [x20, #272]
  c4:	11010108 	add	w8, w8, #0x40
  c8:	927c6d08 	and	x8, x8, #0xfffffff0
  cc:	3ca86920 	str	q0, [x9, x8]
  d0:	b941d288 	ldr	w8, [x20, #464]
  d4:	f9400349 	ldr	x9, [x26]
  d8:	3dc04a80 	ldr	q0, [x20, #288]
  dc:	11014108 	add	w8, w8, #0x50
  e0:	927c6d08 	and	x8, x8, #0xfffffff0
  e4:	3ca86920 	str	q0, [x9, x8]
  e8:	b941d288 	ldr	w8, [x20, #464]
  ec:	f9400349 	ldr	x9, [x26]
  f0:	3dc04e80 	ldr	q0, [x20, #304]
  f4:	11018108 	add	w8, w8, #0x60
  f8:	927c6d08 	and	x8, x8, #0xfffffff0
  fc:	3ca86920 	str	q0, [x9, x8]
 100:	b941d288 	ldr	w8, [x20, #464]
 104:	f9400349 	ldr	x9, [x26]
 108:	3dc05280 	ldr	q0, [x20, #320]
 10c:	1101c108 	add	w8, w8, #0x70
 110:	927c6d08 	and	x8, x8, #0xfffffff0
 114:	3ca86920 	str	q0, [x9, x8]
 118:	b941d288 	ldr	w8, [x20, #464]
 11c:	f9400349 	ldr	x9, [x26]
 120:	3dc05680 	ldr	q0, [x20, #336]
 124:	11020108 	add	w8, w8, #0x80
 128:	927c6d08 	and	x8, x8, #0xfffffff0
 12c:	3ca86920 	str	q0, [x9, x8]
 130:	b941d288 	ldr	w8, [x20, #464]
 134:	f9400349 	ldr	x9, [x26]
 138:	3dc07280 	ldr	q0, [x20, #448]
 13c:	11024108 	add	w8, w8, #0x90
 140:	927c6d08 	and	x8, x8, #0xfffffff0
 144:	3ca86920 	str	q0, [x9, x8]
 148:	f8440f68 	ldr	x8, [x27, #64]!
 14c:	f9400b69 	ldr	x9, [x27, #16]
 150:	f940136a 	ldr	x10, [x27, #32]
 154:	a9037fff 	stp	xzr, xzr, [sp, #48]
 158:	f900e288 	str	x8, [x20, #448]
 15c:	f9401b68 	ldr	x8, [x27, #48]
 160:	3dc00fe0 	ldr	q0, [sp, #48]
 164:	f900aa89 	str	x9, [x20, #336]
 168:	f9402369 	ldr	x9, [x27, #64]
 16c:	f9008288 	str	x8, [x20, #256]
 170:	f940ea88 	ldr	x8, [x20, #464]
 174:	f900a28a 	str	x10, [x20, #320]
 178:	f9402b6a 	ldr	x10, [x27, #80]
 17c:	91004108 	add	x8, x8, #0x10
 180:	f9009a89 	str	x9, [x20, #304]
 184:	f9400349 	ldr	x9, [x26]
 188:	f900928a 	str	x10, [x20, #288]
 18c:	f9008a88 	str	x8, [x20, #272]
 190:	927c6d08 	and	x8, x8, #0xfffffff0
 194:	f940039c 	ldr	x28, [x28]	194: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_3d::cache
 198:	3ca86920 	str	q0, [x9, x8]
 19c:	f9400388 	ldr	x8, [x28]
 1a0:	b9800108 	ldrsw	x8, [x8]
 1a4:	72000d1f 	tst	w8, #0xf
 1a8:	f81f0368 	stur	x8, [x27, #-16]
 1ac:	54006741 	b.ne	e94 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe94>  // b.any
 1b0:	f9400349 	ldr	x9, [x26]
 1b4:	927c6d08 	and	x8, x8, #0xfffffff0
 1b8:	9000000a 	adrp	x10, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	1b8: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x40a
 1bc:	9100014a 	add	x10, x10, #0x0	1bc: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x40a
 1c0:	2f00e408 	movi	d8, #0x0
 1c4:	2f00e409 	movi	d9, #0x0
 1c8:	3ce86920 	ldr	q0, [x9, x8]
 1cc:	b941d288 	ldr	w8, [x20, #464]
 1d0:	f90007ea 	str	x10, [sp, #8]
 1d4:	1e2e100a 	fmov	s10, #1.000000000000000000e+00
 1d8:	910bf375 	add	x21, x27, #0x2fc
 1dc:	910c4296 	add	x22, x20, #0x310
 1e0:	3d80e280 	str	q0, [x20, #896]
 1e4:	11008108 	add	w8, w8, #0x20
 1e8:	92800013 	mov	x19, #0xffffffffffffffff    	// #-1
 1ec:	f941c68a 	ldr	x10, [x20, #904]
 1f0:	394e028b 	ldrb	w11, [x20, #896]
 1f4:	927c6d08 	and	x8, x8, #0xfffffff0
 1f8:	8b080128 	add	x8, x9, x8
 1fc:	3d800be0 	str	q0, [sp, #32]
 200:	a9032a8b 	stp	x11, x10, [x20, #48]
 204:	a900290b 	stp	x11, x10, [x8]
 208:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	208: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x405
 20c:	91000108 	add	x8, x8, #0x0	20c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x405
 210:	f940aa98 	ldr	x24, [x20, #336]
 214:	f90003e8 	str	x8, [sp]
 218:	1400000e 	b	250 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x250>
 21c:	f9409a88 	ldr	x8, [x20, #304]
 220:	f940aa89 	ldr	x9, [x20, #336]
 224:	f940a28a 	ldr	x10, [x20, #320]
 228:	f940828b 	ldr	x11, [x20, #256]
 22c:	f1000508 	subs	x8, x8, #0x1
 230:	91024138 	add	x24, x9, #0x90
 234:	f9009a88 	str	x8, [x20, #304]
 238:	9100c148 	add	x8, x10, #0x30
 23c:	91000577 	add	x23, x11, #0x1
 240:	f900aa98 	str	x24, [x20, #336]
 244:	f900a288 	str	x8, [x20, #320]
 248:	f9008297 	str	x23, [x20, #256]
 24c:	54005260 	b.eq	c98 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc98>  // b.none
 250:	91010321 	add	x1, x25, #0x40
 254:	52800020 	mov	w0, #0x1                   	// #1
 258:	94000000 	bl	0 <__aarch64_ldadd8_relax>	258: R_AARCH64_CALL26	__aarch64_ldadd8_relax
 25c:	f9400345 	ldr	x5, [x26]
 260:	92407f09 	and	x9, x24, #0xffffffff
 264:	b941728b 	ldr	w11, [x20, #368]
 268:	8b0900a8 	add	x8, x5, x9
 26c:	b980810a 	ldrsw	x10, [x8, #128]
 270:	6b0b015f 	cmp	w10, w11
 274:	f9001a8a 	str	x10, [x20, #48]
 278:	54fffd20 	b.eq	21c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x21c>  // b.none
 27c:	b941228c 	ldr	w12, [x20, #288]
 280:	b980690a 	ldrsw	x10, [x8, #104]
 284:	6b0b019f 	cmp	w12, w11
 288:	f9001a8a 	str	x10, [x20, #48]
 28c:	54000300 	b.eq	2ec <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2ec>  // b.none
 290:	9273014b 	and	x11, x10, #0x2000
 294:	f9001a8b 	str	x11, [x20, #48]
 298:	376802aa 	tbnz	w10, #13, 2ec <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2ec>
 29c:	b9806509 	ldrsw	x9, [x8, #100]
 2a0:	f9002293 	str	x19, [x20, #64]
 2a4:	f9001a89 	str	x9, [x20, #48]
 2a8:	34004bc9 	cbz	w9, c20 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc20>
 2ac:	b9806909 	ldrsw	x9, [x8, #104]
 2b0:	927a012a 	and	x10, x9, #0x40
 2b4:	9279f92b 	and	x11, x9, #0xffffffffffffffbf
 2b8:	f9001a8a 	str	x10, [x20, #48]
 2bc:	f900228b 	str	x11, [x20, #64]
 2c0:	b900690b 	str	w11, [x8, #104]
 2c4:	3637fac9 	tbz	w9, #6, 21c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x21c>
 2c8:	f9400348 	ldr	x8, [x26]
 2cc:	b9415289 	ldr	w9, [x20, #336]
 2d0:	b941428a 	ldr	w10, [x20, #320]
 2d4:	8b090109 	add	x9, x8, x9
 2d8:	8b0a0108 	add	x8, x8, x10
 2dc:	b9807d29 	ldrsw	x9, [x9, #124]
 2e0:	f9001a89 	str	x9, [x20, #48]
 2e4:	b9002d09 	str	w9, [x8, #44]
 2e8:	17ffffcd 	b	21c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x21c>
 2ec:	b941d28b 	ldr	w11, [x20, #464]
 2f0:	b980650a 	ldrsw	x10, [x8, #100]
 2f4:	f9002293 	str	x19, [x20, #64]
 2f8:	1100816b 	add	w11, w11, #0x20
 2fc:	f9001a8a 	str	x10, [x20, #48]
 300:	3100055f 	cmn	w10, #0x1
 304:	927c6d6b 	and	x11, x11, #0xfffffff0
 308:	3ceb68a0 	ldr	q0, [x5, x11]
 30c:	3d800360 	str	q0, [x27]
 310:	54000260 	b.eq	35c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x35c>  // b.none
 314:	f9402289 	ldr	x9, [x20, #64]
 318:	6f00e401 	movi	v1.2d, #0x0
 31c:	cb090149 	sub	x9, x10, x9
 320:	1e270120 	fmov	s0, w9
 324:	d360fd2b 	lsr	x11, x9, #32
 328:	f9002289 	str	x9, [x20, #64]
 32c:	4e0c1d60 	mov	v0.s[1], w11
 330:	9101228b 	add	x11, x20, #0x48
 334:	4d408160 	ld1	{v0.s}[2], [x11]
 338:	9101328b 	add	x11, x20, #0x4c
 33c:	4d409160 	ld1	{v0.s}[3], [x11]
 340:	4ea16400 	smax	v0.4s, v0.4s, v1.4s
 344:	3d800e80 	str	q0, [x20, #48]
 348:	340046ca 	cbz	w10, c20 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc20>
 34c:	f9401a89 	ldr	x9, [x20, #48]
 350:	b9006509 	str	w9, [x8, #100]
 354:	f9400345 	ldr	x5, [x26]
 358:	b9415289 	ldr	w9, [x20, #336]
 35c:	8b0900a8 	add	x8, x5, x9
 360:	b9806909 	ldrsw	x9, [x8, #104]
 364:	927a012a 	and	x10, x9, #0x40
 368:	9279f92b 	and	x11, x9, #0xffffffffffffffbf
 36c:	f9001a8a 	str	x10, [x20, #48]
 370:	f900228b 	str	x11, [x20, #64]
 374:	b900690b 	str	w11, [x8, #104]
 378:	36300129 	tbz	w9, #6, 39c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x39c>
 37c:	f9400348 	ldr	x8, [x26]
 380:	b9415289 	ldr	w9, [x20, #336]
 384:	b941428a 	ldr	w10, [x20, #320]
 388:	8b090109 	add	x9, x8, x9
 38c:	8b0a0108 	add	x8, x8, x10
 390:	b9807d29 	ldrsw	x9, [x9, #124]
 394:	f9001a89 	str	x9, [x20, #48]
 398:	b9002d09 	str	w9, [x8, #44]
 39c:	f9400348 	ldr	x8, [x26]
 3a0:	b941528a 	ldr	w10, [x20, #336]
 3a4:	8b0a0109 	add	x9, x8, x10
 3a8:	b980712b 	ldrsw	x11, [x9, #112]
 3ac:	f940ea89 	ldr	x9, [x20, #464]
 3b0:	f900ca8b 	str	x11, [x20, #400]
 3b4:	34000b8b 	cbz	w11, 524 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x524>
 3b8:	d1018129 	sub	x9, x9, #0x60
 3bc:	3dc07280 	ldr	q0, [x20, #448]
 3c0:	f900ea89 	str	x9, [x20, #464]
 3c4:	927c6d29 	and	x9, x9, #0xfffffff0
 3c8:	3ca96900 	str	q0, [x8, x9]
 3cc:	b941d288 	ldr	w8, [x20, #464]
 3d0:	f9400349 	ldr	x9, [x26]
 3d4:	3dc05680 	ldr	q0, [x20, #336]
 3d8:	11004108 	add	w8, w8, #0x10
 3dc:	927c6d08 	and	x8, x8, #0xfffffff0
 3e0:	3ca86920 	str	q0, [x9, x8]
 3e4:	b941d288 	ldr	w8, [x20, #464]
 3e8:	f9400349 	ldr	x9, [x26]
 3ec:	3dc05280 	ldr	q0, [x20, #320]
 3f0:	11008108 	add	w8, w8, #0x20
 3f4:	927c6d08 	and	x8, x8, #0xfffffff0
 3f8:	3ca86920 	str	q0, [x9, x8]
 3fc:	b941d288 	ldr	w8, [x20, #464]
 400:	f9400349 	ldr	x9, [x26]
 404:	3dc04280 	ldr	q0, [x20, #256]
 408:	1100c108 	add	w8, w8, #0x30
 40c:	927c6d08 	and	x8, x8, #0xfffffff0
 410:	3ca86920 	str	q0, [x9, x8]
 414:	b941d288 	ldr	w8, [x20, #464]
 418:	f9400349 	ldr	x9, [x26]
 41c:	3dc04e80 	ldr	q0, [x20, #304]
 420:	11010108 	add	w8, w8, #0x40
 424:	927c6d08 	and	x8, x8, #0xfffffff0
 428:	3ca86920 	str	q0, [x9, x8]
 42c:	f940e288 	ldr	x8, [x20, #448]
 430:	b941d28a 	ldr	w10, [x20, #464]
 434:	f940aa89 	ldr	x9, [x20, #336]
 438:	f940a28b 	ldr	x11, [x20, #320]
 43c:	f940034c 	ldr	x12, [x26]
 440:	3dc04a80 	ldr	q0, [x20, #288]
 444:	f9002288 	str	x8, [x20, #64]
 448:	11014148 	add	w8, w10, #0x50
 44c:	f9002a89 	str	x9, [x20, #80]
 450:	927c6d09 	and	x9, x8, #0xfffffff0
 454:	b9419288 	ldr	w8, [x20, #400]
 458:	f900328b 	str	x11, [x20, #96]
 45c:	3ca96980 	str	q0, [x12, x9]
 460:	f9402289 	ldr	x9, [x20, #64]
 464:	f9402a8a 	ldr	x10, [x20, #80]
 468:	f940328b 	ldr	x11, [x20, #96]
 46c:	a9032be9 	stp	x9, x10, [sp, #48]
 470:	f9403a89 	ldr	x9, [x20, #112]
 474:	f940428a 	ldr	x10, [x20, #128]
 478:	a90427eb 	stp	x11, x9, [sp, #64]
 47c:	f9404a8b 	ldr	x11, [x20, #144]
 480:	f9405289 	ldr	x9, [x20, #160]
 484:	a9052fea 	stp	x10, x11, [sp, #80]
 488:	f9405a8a 	ldr	x10, [x20, #176]
 48c:	a9062be9 	stp	x9, x10, [sp, #96]
 490:	340047e8 	cbz	w8, d8c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd8c>
 494:	f9400345 	ldr	x5, [x26]
 498:	f940b283 	ldr	x3, [x20, #352]
 49c:	f940ba84 	ldr	x4, [x20, #368]
 4a0:	8b0800a0 	add	x0, x5, x8
 4a4:	9100c3e1 	add	x1, sp, #0x30
 4a8:	aa1f03e2 	mov	x2, xzr
 4ac:	94000000 	bl	0 <_call_goal8_asm_systemv>	4ac: R_AARCH64_CALL26	_call_goal8_asm_systemv
 4b0:	f940ea89 	ldr	x9, [x20, #464]
 4b4:	f9400348 	ldr	x8, [x26]
 4b8:	f9001280 	str	x0, [x20, #32]
 4bc:	927c6d2a 	and	x10, x9, #0xfffffff0
 4c0:	3cea6900 	ldr	q0, [x8, x10]
 4c4:	1100412a 	add	w10, w9, #0x10
 4c8:	927c6d4a 	and	x10, x10, #0xfffffff0
 4cc:	3d807280 	str	q0, [x20, #448]
 4d0:	3cea6900 	ldr	q0, [x8, x10]
 4d4:	1100812a 	add	w10, w9, #0x20
 4d8:	927c6d4a 	and	x10, x10, #0xfffffff0
 4dc:	3d805680 	str	q0, [x20, #336]
 4e0:	3cea6900 	ldr	q0, [x8, x10]
 4e4:	1100c12a 	add	w10, w9, #0x30
 4e8:	927c6d4a 	and	x10, x10, #0xfffffff0
 4ec:	3d805280 	str	q0, [x20, #320]
 4f0:	3cea6900 	ldr	q0, [x8, x10]
 4f4:	1101012a 	add	w10, w9, #0x40
 4f8:	927c6d4a 	and	x10, x10, #0xfffffff0
 4fc:	3d804280 	str	q0, [x20, #256]
 500:	3cea6900 	ldr	q0, [x8, x10]
 504:	1101412a 	add	w10, w9, #0x50
 508:	91018129 	add	x9, x9, #0x60
 50c:	927c6d4a 	and	x10, x10, #0xfffffff0
 510:	3d804e80 	str	q0, [x20, #304]
 514:	3cea6900 	ldr	q0, [x8, x10]
 518:	b941528a 	ldr	w10, [x20, #336]
 51c:	f900ea89 	str	x9, [x20, #464]
 520:	3d804a80 	str	q0, [x20, #288]
 524:	8b0a010a 	add	x10, x8, x10
 528:	11008129 	add	w9, w9, #0x20
 52c:	b980794c 	ldrsw	x12, [x10, #120]
 530:	927c6d29 	and	x9, x9, #0xfffffff0
 534:	f9002a8c 	str	x12, [x20, #80]
 538:	b980754b 	ldrsw	x11, [x10, #116]
 53c:	f9001a8b 	str	x11, [x20, #48]
 540:	3ce96900 	ldr	q0, [x8, x9]
 544:	3d800360 	str	q0, [x27]
 548:	34000c8c 	cbz	w12, 6d8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x6d8>
 54c:	f9402288 	ldr	x8, [x20, #64]
 550:	eb080168 	subs	x8, x11, x8
 554:	f9001a88 	str	x8, [x20, #48]
 558:	b9007548 	str	w8, [x10, #116]
 55c:	54000be5 	b.pl	6d8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x6d8>  // b.nfrst
 560:	f940ea88 	ldr	x8, [x20, #464]
 564:	f9400349 	ldr	x9, [x26]
 568:	3dc07280 	ldr	q0, [x20, #448]
 56c:	d1018108 	sub	x8, x8, #0x60
 570:	f900ea88 	str	x8, [x20, #464]
 574:	927c6d08 	and	x8, x8, #0xfffffff0
 578:	3ca86920 	str	q0, [x9, x8]
 57c:	b941d288 	ldr	w8, [x20, #464]
 580:	f9400349 	ldr	x9, [x26]
 584:	3dc05680 	ldr	q0, [x20, #336]
 588:	11004108 	add	w8, w8, #0x10
 58c:	927c6d08 	and	x8, x8, #0xfffffff0
 590:	3ca86920 	str	q0, [x9, x8]
 594:	b941d288 	ldr	w8, [x20, #464]
 598:	f9400349 	ldr	x9, [x26]
 59c:	3dc05280 	ldr	q0, [x20, #320]
 5a0:	11008108 	add	w8, w8, #0x20
 5a4:	927c6d08 	and	x8, x8, #0xfffffff0
 5a8:	3ca86920 	str	q0, [x9, x8]
 5ac:	b941d288 	ldr	w8, [x20, #464]
 5b0:	f9400349 	ldr	x9, [x26]
 5b4:	3dc04280 	ldr	q0, [x20, #256]
 5b8:	1100c108 	add	w8, w8, #0x30
 5bc:	927c6d08 	and	x8, x8, #0xfffffff0
 5c0:	3ca86920 	str	q0, [x9, x8]
 5c4:	b941d288 	ldr	w8, [x20, #464]
 5c8:	f9400349 	ldr	x9, [x26]
 5cc:	3dc04e80 	ldr	q0, [x20, #304]
 5d0:	11010108 	add	w8, w8, #0x40
 5d4:	927c6d08 	and	x8, x8, #0xfffffff0
 5d8:	3ca86920 	str	q0, [x9, x8]
 5dc:	b941d288 	ldr	w8, [x20, #464]
 5e0:	f9400349 	ldr	x9, [x26]
 5e4:	3dc04a80 	ldr	q0, [x20, #288]
 5e8:	11014108 	add	w8, w8, #0x50
 5ec:	927c6d08 	and	x8, x8, #0xfffffff0
 5f0:	3ca86920 	str	q0, [x9, x8]
 5f4:	f940e289 	ldr	x9, [x20, #448]
 5f8:	f940a28a 	ldr	x10, [x20, #320]
 5fc:	f940aa8b 	ldr	x11, [x20, #336]
 600:	f9400f88 	ldr	x8, [x28, #24]
 604:	b981f28c 	ldrsw	x12, [x20, #496]
 608:	f9002289 	str	x9, [x20, #64]
 60c:	f9003a8a 	str	x10, [x20, #112]
 610:	f900328b 	str	x11, [x20, #96]
 614:	b9800108 	ldrsw	x8, [x8]
 618:	f900128c 	str	x12, [x20, #32]
 61c:	f9402a8c 	ldr	x12, [x20, #80]
 620:	a9042beb 	stp	x11, x10, [sp, #64]
 624:	f9404a8b 	ldr	x11, [x20, #144]
 628:	f9405a8a 	ldr	x10, [x20, #176]
 62c:	a90333e9 	stp	x9, x12, [sp, #48]
 630:	f9404289 	ldr	x9, [x20, #128]
 634:	f900ca88 	str	x8, [x20, #400]
 638:	a9052fe9 	stp	x9, x11, [sp, #80]
 63c:	f9405289 	ldr	x9, [x20, #160]
 640:	a9062be9 	stp	x9, x10, [sp, #96]
 644:	34003a48 	cbz	w8, d8c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd8c>
 648:	f9400345 	ldr	x5, [x26]
 64c:	f940b283 	ldr	x3, [x20, #352]
 650:	92407d08 	and	x8, x8, #0xffffffff
 654:	f940ba84 	ldr	x4, [x20, #368]
 658:	8b0800a0 	add	x0, x5, x8
 65c:	9100c3e1 	add	x1, sp, #0x30
 660:	aa1f03e2 	mov	x2, xzr
 664:	94000000 	bl	0 <_call_goal8_asm_systemv>	664: R_AARCH64_CALL26	_call_goal8_asm_systemv
 668:	f940ea88 	ldr	x8, [x20, #464]
 66c:	f9400349 	ldr	x9, [x26]
 670:	f9001280 	str	x0, [x20, #32]
 674:	927c6d0a 	and	x10, x8, #0xfffffff0
 678:	3cea6920 	ldr	q0, [x9, x10]
 67c:	1100410a 	add	w10, w8, #0x10
 680:	927c6d4a 	and	x10, x10, #0xfffffff0
 684:	3d807280 	str	q0, [x20, #448]
 688:	3cea6920 	ldr	q0, [x9, x10]
 68c:	1100810a 	add	w10, w8, #0x20
 690:	927c6d4a 	and	x10, x10, #0xfffffff0
 694:	3d805680 	str	q0, [x20, #336]
 698:	3cea6920 	ldr	q0, [x9, x10]
 69c:	1100c10a 	add	w10, w8, #0x30
 6a0:	927c6d4a 	and	x10, x10, #0xfffffff0
 6a4:	3d805280 	str	q0, [x20, #320]
 6a8:	3cea6920 	ldr	q0, [x9, x10]
 6ac:	1101010a 	add	w10, w8, #0x40
 6b0:	927c6d4a 	and	x10, x10, #0xfffffff0
 6b4:	3d804280 	str	q0, [x20, #256]
 6b8:	3cea6920 	ldr	q0, [x9, x10]
 6bc:	1101410a 	add	w10, w8, #0x50
 6c0:	91018108 	add	x8, x8, #0x60
 6c4:	927c6d4a 	and	x10, x10, #0xfffffff0
 6c8:	3d804e80 	str	q0, [x20, #304]
 6cc:	3cea6920 	ldr	q0, [x9, x10]
 6d0:	f900ea88 	str	x8, [x20, #464]
 6d4:	3d804a80 	str	q0, [x20, #288]
 6d8:	f940a289 	ldr	x9, [x20, #320]
 6dc:	f2400d3f 	tst	x9, #0xf
 6e0:	540039e1 	b.ne	e1c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe1c>  // b.any
 6e4:	f9400348 	ldr	x8, [x26]
 6e8:	927c6d29 	and	x9, x9, #0xfffffff0
 6ec:	8b09010a 	add	x10, x8, x9
 6f0:	f9400949 	ldr	x9, [x10, #16]
 6f4:	3dc00140 	ldr	q0, [x10]
 6f8:	f9001be9 	str	x9, [sp, #48]
 6fc:	f940aa89 	ldr	x9, [x20, #336]
 700:	b940194b 	ldr	w11, [x10, #24]
 704:	f2400d3f 	tst	x9, #0xf
 708:	b9003beb 	str	w11, [sp, #56]
 70c:	54003a61 	b.ne	e58 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe58>  // b.any
 710:	927c6d29 	and	x9, x9, #0xfffffff0
 714:	bd438a81 	ldr	s1, [x20, #904]
 718:	bd401d46 	ldr	s6, [x10, #28]
 71c:	8b090108 	add	x8, x8, x9
 720:	3dc00951 	ldr	q17, [x10, #32]
 724:	ad418905 	ldp	q5, q2, [x8, #48]
 728:	bd401904 	ldr	s4, [x8, #24]
 72c:	b9806109 	ldrsw	x9, [x8, #96]
 730:	bd402d07 	ldr	s7, [x8, #44]
 734:	4f819042 	fmul	v2.4s, v2.4s, v1.s[0]
 738:	fd400901 	ldr	d1, [x8, #16]
 73c:	5e140443 	mov	s3, v2.s[2]
 740:	0e22d421 	fadd	v1.2s, v1.2s, v2.2s
 744:	1e232890 	fadd	s16, s4, s3
 748:	3cc1c103 	ldur	q3, [x8, #28]
 74c:	bd438684 	ldr	s4, [x20, #900]
 750:	b9020289 	str	w9, [x20, #512]
 754:	f9001a89 	str	x9, [x20, #48]
 758:	340002e9 	cbz	w9, 7b4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x7b4>
 75c:	1e270132 	fmov	s18, w9
 760:	bd438e94 	ldr	s20, [x20, #908]
 764:	bd403a95 	ldr	s21, [x20, #56]
 768:	131f7d2a 	asr	w10, w9, #31
 76c:	bd033e83 	str	s3, [x20, #828]
 770:	1e350a95 	fmul	s21, s20, s21
 774:	1e323953 	fsub	s19, s10, s18
 778:	1e320a8b 	fmul	s11, s20, s18
 77c:	1e270152 	fmov	s18, w10
 780:	1e320a8c 	fmul	s12, s20, s18
 784:	bd037a95 	str	s21, [x20, #888]
 788:	1e330a93 	fmul	s19, s20, s19
 78c:	bd03728b 	str	s11, [x20, #880]
 790:	bd03768c 	str	s12, [x20, #884]
 794:	1e333953 	fsub	s19, s10, s19
 798:	0f939021 	fmul	v1.2s, v1.2s, v19.s[0]
 79c:	1e330a10 	fmul	s16, s16, s19
 7a0:	6e0c0675 	mov	v21.s[1], v19.s[0]
 7a4:	bd037e93 	str	s19, [x20, #892]
 7a8:	3d800bf5 	str	q21, [sp, #32]
 7ac:	fd019a81 	str	d1, [x20, #816]
 7b0:	bd033a90 	str	s16, [x20, #824]
 7b4:	0e0c0433 	dup	v19.2s, v1.s[1]
 7b8:	4f8490b2 	fmul	v18.4s, v5.4s, v4.s[0]
 7bc:	1e210894 	fmul	s20, s4, s1
 7c0:	bd033a90 	str	s16, [x20, #824]
 7c4:	f9401bea 	ldr	x10, [sp, #48]
 7c8:	bd034e87 	str	s7, [x20, #844]
 7cc:	f90002ca 	str	x10, [x22]
 7d0:	b9403bea 	ldr	w10, [sp, #56]
 7d4:	6e0c0613 	mov	v19.s[1], v16.s[0]
 7d8:	4e32d635 	fadd	v21.4s, v17.4s, v18.4s
 7dc:	1e270891 	fmul	s17, s4, s7
 7e0:	fd019a81 	str	d1, [x20, #816]
 7e4:	3d8002a3 	str	q3, [x21]
 7e8:	b9000aca 	str	w10, [x22, #8]
 7ec:	6e180473 	mov	v19.d[1], v3.d[0]
 7f0:	4ea0eab0 	fcmlt	v16.4s, v21.4s, #0.0
 7f4:	1e3128c6 	fadd	s6, s6, s17
 7f8:	ad1a8a85 	stp	q5, q2, [x20, #848]
 7fc:	4f849273 	fmul	v19.4s, v19.4s, v4.s[0]
 800:	4e701ea7 	bic	v7.16b, v21.16b, v16.16b
 804:	bd031e86 	str	s6, [x20, #796]
 808:	3d80ca87 	str	q7, [x20, #800]
 80c:	6e136016 	ext	v22.16b, v0.16b, v19.16b, #12
 810:	6e040696 	mov	v22.s[0], v20.s[0]
 814:	4e36d400 	fadd	v0.4s, v0.4s, v22.4s
 818:	3d80c280 	str	q0, [x20, #768]
 81c:	340000a9 	cbz	w9, 830 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x830>
 820:	3dc00be0 	ldr	q0, [sp, #32]
 824:	bd03728b 	str	s11, [x20, #880]
 828:	bd03768c 	str	s12, [x20, #884]
 82c:	fd01be80 	str	d0, [x20, #888]
 830:	0e0c3c29 	mov	w9, v1.s[1]
 834:	1e26002a 	fmov	w10, s1
 838:	f9419e8b 	ldr	x11, [x20, #824]
 83c:	5f839880 	fmul	s0, s4, v3.s[2]
 840:	5fa39882 	fmul	s2, s4, v3.s[3]
 844:	bd039294 	str	s20, [x20, #912]
 848:	3c8582b3 	stur	q19, [x21, #88]
 84c:	bd03ae91 	str	s17, [x20, #940]
 850:	aa098149 	orr	x9, x10, x9, lsl #32
 854:	3d80ee92 	str	q18, [x20, #944]
 858:	bd03a680 	str	s0, [x20, #932]
 85c:	bd03aa82 	str	s2, [x20, #936]
 860:	a9012d09 	stp	x9, x11, [x8, #16]
 864:	f940a288 	ldr	x8, [x20, #320]
 868:	f2400d1f 	tst	x8, #0xf
 86c:	540029e1 	b.ne	da8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xda8>  // b.any
 870:	f9400349 	ldr	x9, [x26]
 874:	f941828a 	ldr	x10, [x20, #768]
 878:	927c6d08 	and	x8, x8, #0xfffffff0
 87c:	f941868b 	ldr	x11, [x20, #776]
 880:	8b080128 	add	x8, x9, x8
 884:	a9002d0a 	stp	x10, x11, [x8]
 888:	f940a288 	ldr	x8, [x20, #320]
 88c:	f2400d1f 	tst	x8, #0xf
 890:	540028c1 	b.ne	da8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xda8>  // b.any
 894:	f9400349 	ldr	x9, [x26]
 898:	f9418a8a 	ldr	x10, [x20, #784]
 89c:	927c6d08 	and	x8, x8, #0xfffffff0
 8a0:	f9418e8b 	ldr	x11, [x20, #792]
 8a4:	8b080128 	add	x8, x9, x8
 8a8:	a9012d0a 	stp	x10, x11, [x8, #16]
 8ac:	f940a288 	ldr	x8, [x20, #320]
 8b0:	f2400d1f 	tst	x8, #0xf
 8b4:	540027a1 	b.ne	da8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xda8>  // b.any
 8b8:	f9400349 	ldr	x9, [x26]
 8bc:	f941928a 	ldr	x10, [x20, #800]
 8c0:	927c6d08 	and	x8, x8, #0xfffffff0
 8c4:	f941968b 	ldr	x11, [x20, #808]
 8c8:	8b080128 	add	x8, x9, x8
 8cc:	a9022d0a 	stp	x10, x11, [x8, #32]
 8d0:	f940a289 	ldr	x9, [x20, #320]
 8d4:	f940034a 	ldr	x10, [x26]
 8d8:	f9408a88 	ldr	x8, [x20, #272]
 8dc:	8b29414b 	add	x11, x10, w9, uxtw
 8e0:	f9001a88 	str	x8, [x20, #48]
 8e4:	f9002289 	str	x9, [x20, #64]
 8e8:	b9401169 	ldr	w9, [x11, #16]
 8ec:	b9020289 	str	w9, [x20, #512]
 8f0:	b940156c 	ldr	w12, [x11, #20]
 8f4:	b902068c 	str	w12, [x20, #516]
 8f8:	b940196b 	ldr	w11, [x11, #24]
 8fc:	b9020e8b 	str	w11, [x20, #524]
 900:	b8284949 	str	w9, [x10, w8, uxtw]
 904:	f9400348 	ldr	x8, [x26]
 908:	b9403289 	ldr	w9, [x20, #48]
 90c:	b942068a 	ldr	w10, [x20, #516]
 910:	8b090108 	add	x8, x8, x9
 914:	b900050a 	str	w10, [x8, #4]
 918:	f9400348 	ldr	x8, [x26]
 91c:	b9403289 	ldr	w9, [x20, #48]
 920:	b9420e8a 	ldr	w10, [x20, #524]
 924:	8b090108 	add	x8, x8, x9
 928:	b900090a 	str	w10, [x8, #8]
 92c:	bd420e80 	ldr	s0, [x20, #524]
 930:	bd420681 	ldr	s1, [x20, #516]
 934:	bd420283 	ldr	s3, [x20, #512]
 938:	f9400348 	ldr	x8, [x26]
 93c:	b9403289 	ldr	w9, [x20, #48]
 940:	1e200800 	fmul	s0, s0, s0
 944:	1e210821 	fmul	s1, s1, s1
 948:	1e230863 	fmul	s3, s3, s3
 94c:	8b090108 	add	x8, x8, x9
 950:	1e203942 	fsub	s2, s10, s0
 954:	bd020e80 	str	s0, [x20, #524]
 958:	1e213841 	fsub	s1, s2, s1
 95c:	bd020a82 	str	s2, [x20, #520]
 960:	7ea3d423 	fabd	s3, s1, s3
 964:	bd020681 	str	s1, [x20, #516]
 968:	1e21c063 	fsqrt	s3, s3
 96c:	bd020283 	str	s3, [x20, #512]
 970:	bd000d03 	str	s3, [x8, #12]
 974:	b9820288 	ldrsw	x8, [x20, #512]
 978:	f9400389 	ldr	x9, [x28]
 97c:	f9400345 	ldr	x5, [x26]
 980:	f9002288 	str	x8, [x20, #64]
 984:	b9400128 	ldr	w8, [x9]
 988:	93407d09 	sxtw	x9, w8
 98c:	f9001a89 	str	x9, [x20, #48]
 990:	b86868a8 	ldr	w8, [x5, x8]
 994:	92401d09 	and	x9, x8, #0xff
 998:	b9020288 	str	w8, [x20, #512]
 99c:	d1002928 	sub	x8, x9, #0xa
 9a0:	7100293f 	cmp	w9, #0xa
 9a4:	f9001a88 	str	x8, [x20, #48]
 9a8:	540003c3 	b.cc	a20 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa20>  // b.lo, b.ul, b.last
 9ac:	f9400788 	ldr	x8, [x28, #8]
 9b0:	f9408a89 	ldr	x9, [x20, #272]
 9b4:	f940aa8a 	ldr	x10, [x20, #336]
 9b8:	b981f28b 	ldrsw	x11, [x20, #496]
 9bc:	b9800108 	ldrsw	x8, [x8]
 9c0:	f9002289 	str	x9, [x20, #64]
 9c4:	9101414a 	add	x10, x10, #0x50
 9c8:	f9002a89 	str	x9, [x20, #80]
 9cc:	a90327e9 	stp	x9, x9, [sp, #48]
 9d0:	f9403a89 	ldr	x9, [x20, #112]
 9d4:	f900128b 	str	x11, [x20, #32]
 9d8:	f940428b 	ldr	x11, [x20, #128]
 9dc:	a90427ea 	stp	x10, x9, [sp, #64]
 9e0:	f9404a89 	ldr	x9, [x20, #144]
 9e4:	f900328a 	str	x10, [x20, #96]
 9e8:	f940528a 	ldr	x10, [x20, #160]
 9ec:	a90527eb 	stp	x11, x9, [sp, #80]
 9f0:	f9405a89 	ldr	x9, [x20, #176]
 9f4:	f900ca88 	str	x8, [x20, #400]
 9f8:	a90627ea 	stp	x10, x9, [sp, #96]
 9fc:	34001c88 	cbz	w8, d8c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd8c>
 a00:	f940b283 	ldr	x3, [x20, #352]
 a04:	f940ba84 	ldr	x4, [x20, #368]
 a08:	92407d08 	and	x8, x8, #0xffffffff
 a0c:	8b0800a0 	add	x0, x5, x8
 a10:	9100c3e1 	add	x1, sp, #0x30
 a14:	aa1f03e2 	mov	x2, xzr
 a18:	94000000 	bl	0 <_call_goal8_asm_systemv>	a18: R_AARCH64_CALL26	_call_goal8_asm_systemv
 a1c:	f9001280 	str	x0, [x20, #32]
 a20:	f9400788 	ldr	x8, [x28, #8]
 a24:	f9408a89 	ldr	x9, [x20, #272]
 a28:	f940aa8a 	ldr	x10, [x20, #336]
 a2c:	b981f28b 	ldrsw	x11, [x20, #496]
 a30:	b9800108 	ldrsw	x8, [x8]
 a34:	f9002289 	str	x9, [x20, #64]
 a38:	9101414a 	add	x10, x10, #0x50
 a3c:	f9002a89 	str	x9, [x20, #80]
 a40:	a90327e9 	stp	x9, x9, [sp, #48]
 a44:	f9403a89 	ldr	x9, [x20, #112]
 a48:	f900128b 	str	x11, [x20, #32]
 a4c:	f940428b 	ldr	x11, [x20, #128]
 a50:	a90427ea 	stp	x10, x9, [sp, #64]
 a54:	f9404a89 	ldr	x9, [x20, #144]
 a58:	f900328a 	str	x10, [x20, #96]
 a5c:	f940528a 	ldr	x10, [x20, #160]
 a60:	a90527eb 	stp	x11, x9, [sp, #80]
 a64:	f9405a89 	ldr	x9, [x20, #176]
 a68:	f900ca88 	str	x8, [x20, #400]
 a6c:	a90627ea 	stp	x10, x9, [sp, #96]
 a70:	340018e8 	cbz	w8, d8c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd8c>
 a74:	f9400345 	ldr	x5, [x26]
 a78:	f940b283 	ldr	x3, [x20, #352]
 a7c:	92407d08 	and	x8, x8, #0xffffffff
 a80:	f940ba84 	ldr	x4, [x20, #368]
 a84:	8b0800a0 	add	x0, x5, x8
 a88:	9100c3e1 	add	x1, sp, #0x30
 a8c:	aa1f03e2 	mov	x2, xzr
 a90:	94000000 	bl	0 <_call_goal8_asm_systemv>	a90: R_AARCH64_CALL26	_call_goal8_asm_systemv
 a94:	f9408a89 	ldr	x9, [x20, #272]
 a98:	f940034b 	ldr	x11, [x26]
 a9c:	f940a28a 	ldr	x10, [x20, #320]
 aa0:	f9001280 	str	x0, [x20, #32]
 aa4:	8b294168 	add	x8, x11, w9, uxtw
 aa8:	f900228a 	str	x10, [x20, #64]
 aac:	f9001a89 	str	x9, [x20, #48]
 ab0:	b9400d0c 	ldr	w12, [x8, #12]
 ab4:	b902069f 	str	wzr, [x20, #516]
 ab8:	1e270180 	fmov	s0, w12
 abc:	b902028c 	str	w12, [x20, #512]
 ac0:	92400d4c 	and	x12, x10, #0xf
 ac4:	1e202008 	fcmp	s0, #0.0
 ac8:	540001e4 	b.mi	b04 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb04>  // b.first
 acc:	b500186c 	cbnz	x12, dd8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdd8>
 ad0:	927c6d4a 	and	x10, x10, #0xfffffff0
 ad4:	f2400d3f 	tst	x9, #0xf
 ad8:	8b0a016a 	add	x10, x11, x10
 adc:	3dc00540 	ldr	q0, [x10, #16]
 ae0:	3d80a680 	str	q0, [x20, #656]
 ae4:	540017a1 	b.ne	dd8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdd8>  // b.any
 ae8:	3dc00100 	ldr	q0, [x8]
 aec:	3d80aa80 	str	q0, [x20, #672]
 af0:	fd415280 	ldr	d0, [x20, #672]
 af4:	bd42aa82 	ldr	s2, [x20, #680]
 af8:	0e28d401 	fadd	v1.2s, v0.2s, v8.2s
 afc:	1e292840 	fadd	s0, s2, s9
 b00:	1400000e 	b	b38 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb38>
 b04:	b50016ac 	cbnz	x12, dd8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdd8>
 b08:	927c6d4a 	and	x10, x10, #0xfffffff0
 b0c:	f2400d3f 	tst	x9, #0xf
 b10:	8b0a016a 	add	x10, x11, x10
 b14:	3dc00540 	ldr	q0, [x10, #16]
 b18:	3d80a680 	str	q0, [x20, #656]
 b1c:	540015e1 	b.ne	dd8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdd8>  // b.any
 b20:	3dc00100 	ldr	q0, [x8]
 b24:	3d80aa80 	str	q0, [x20, #672]
 b28:	fd415280 	ldr	d0, [x20, #672]
 b2c:	bd42aa82 	ldr	s2, [x20, #680]
 b30:	0ea0d501 	fsub	v1.2s, v8.2s, v0.2s
 b34:	1e223920 	fsub	s0, s9, s2
 b38:	0e0c3c29 	mov	w9, v1.s[1]
 b3c:	91004148 	add	x8, x10, #0x10
 b40:	1e26000a 	fmov	w10, s0
 b44:	1e26002b 	fmov	w11, s1
 b48:	b9429e8c 	ldr	w12, [x20, #668]
 b4c:	fd014a81 	str	d1, [x20, #656]
 b50:	bd029a80 	str	s0, [x20, #664]
 b54:	aa0c814a 	orr	x10, x10, x12, lsl #32
 b58:	aa098169 	orr	x9, x11, x9, lsl #32
 b5c:	a9002909 	stp	x9, x10, [x8]
 b60:	f9414e88 	ldr	x8, [x20, #664]
 b64:	f9414a89 	ldr	x9, [x20, #656]
 b68:	f9400345 	ldr	x5, [x26]
 b6c:	f940aa98 	ldr	x24, [x20, #336]
 b70:	3dc0ca80 	ldr	q0, [x20, #800]
 b74:	a9042289 	stp	x9, x8, [x20, #64]
 b78:	8b3840a8 	add	x8, x5, w24, uxtw
 b7c:	3d800e80 	str	q0, [x20, #48]
 b80:	b9806908 	ldrsw	x8, [x8, #104]
 b84:	927e0109 	and	x9, x8, #0x4
 b88:	f9002288 	str	x8, [x20, #64]
 b8c:	f9002a89 	str	x9, [x20, #80]
 b90:	36080108 	tbz	w8, #1, bb0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbb0>
 b94:	a9432a8b 	ldp	x11, x10, [x20, #48]
 b98:	290c2a9f 	stp	wzr, w10, [x20, #96]
 b9c:	d360fd4a 	lsr	x10, x10, #32
 ba0:	290d2a9f 	stp	wzr, w10, [x20, #104]
 ba4:	b500006b 	cbnz	x11, bb0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbb0>
 ba8:	f940328a 	ldr	x10, [x20, #96]
 bac:	b40003aa 	cbz	x10, c20 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc20>
 bb0:	92400108 	and	x8, x8, #0x1
 bb4:	f9000368 	str	x8, [x27]
 bb8:	b4000109 	cbz	x9, bd8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbd8>
 bbc:	f9401e89 	ldr	x9, [x20, #56]
 bc0:	d360fd2a 	lsr	x10, x9, #32
 bc4:	29077e89 	stp	w9, wzr, [x20, #56]
 bc8:	29062a9f 	stp	wzr, w10, [x20, #48]
 bcc:	f9401a8a 	ldr	x10, [x20, #48]
 bd0:	f100055f 	cmp	x10, #0x1
 bd4:	5400026b 	b.lt	c20 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc20>  // b.tstop
 bd8:	b4ffb228 	cbz	x8, 21c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x21c>
 bdc:	f9418288 	ldr	x8, [x20, #768]
 be0:	f9418689 	ldr	x9, [x20, #776]
 be4:	f9418a8a 	ldr	x10, [x20, #784]
 be8:	a9032688 	stp	x8, x9, [x20, #48]
 bec:	d360fd28 	lsr	x8, x9, #32
 bf0:	29077e89 	stp	w9, wzr, [x20, #56]
 bf4:	2906229f 	stp	wzr, w8, [x20, #48]
 bf8:	f9418e88 	ldr	x8, [x20, #792]
 bfc:	f9401a89 	ldr	x9, [x20, #48]
 c00:	a903228a 	stp	x10, x8, [x20, #48]
 c04:	b7f800e9 	tbnz	x9, #63, c20 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc20>
 c08:	f9401e88 	ldr	x8, [x20, #56]
 c0c:	d360fd09 	lsr	x9, x8, #32
 c10:	29077e88 	stp	w8, wzr, [x20, #56]
 c14:	2906269f 	stp	wzr, w9, [x20, #48]
 c18:	f9401a89 	ldr	x9, [x20, #48]
 c1c:	b6ffb009 	tbz	x9, #63, 21c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x21c>
 c20:	f9400b88 	ldr	x8, [x28, #16]
 c24:	f940e289 	ldr	x9, [x20, #448]
 c28:	f940828a 	ldr	x10, [x20, #256]
 c2c:	f940a28b 	ldr	x11, [x20, #320]
 c30:	b981f28c 	ldrsw	x12, [x20, #496]
 c34:	b9800108 	ldrsw	x8, [x8]
 c38:	f9002289 	str	x9, [x20, #64]
 c3c:	f9002a8a 	str	x10, [x20, #80]
 c40:	a9032be9 	stp	x9, x10, [sp, #48]
 c44:	f9404289 	ldr	x9, [x20, #128]
 c48:	f9404a8a 	ldr	x10, [x20, #144]
 c4c:	f9003a8b 	str	x11, [x20, #112]
 c50:	a9042ff8 	stp	x24, x11, [sp, #64]
 c54:	f940528b 	ldr	x11, [x20, #160]
 c58:	a9052be9 	stp	x9, x10, [sp, #80]
 c5c:	f9405a89 	ldr	x9, [x20, #176]
 c60:	f9003298 	str	x24, [x20, #96]
 c64:	f900ca88 	str	x8, [x20, #400]
 c68:	f900128c 	str	x12, [x20, #32]
 c6c:	a90627eb 	stp	x11, x9, [sp, #96]
 c70:	340008e8 	cbz	w8, d8c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd8c>
 c74:	f940b283 	ldr	x3, [x20, #352]
 c78:	f940ba84 	ldr	x4, [x20, #368]
 c7c:	92407d08 	and	x8, x8, #0xffffffff
 c80:	8b0800a0 	add	x0, x5, x8
 c84:	9100c3e1 	add	x1, sp, #0x30
 c88:	aa1f03e2 	mov	x2, xzr
 c8c:	94000000 	bl	0 <_call_goal8_asm_systemv>	c8c: R_AARCH64_CALL26	_call_goal8_asm_systemv
 c90:	f9001280 	str	x0, [x20, #32]
 c94:	17fffd62 	b	21c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x21c>
 c98:	f9400348 	ldr	x8, [x26]
 c9c:	f940ea89 	ldr	x9, [x20, #464]
 ca0:	f9001297 	str	x23, [x20, #32]
 ca4:	8b29410a 	add	x10, x8, w9, uxtw
 ca8:	f940014b 	ldr	x11, [x10]
 cac:	f900fa8b 	str	x11, [x20, #496]
 cb0:	1102412b 	add	w11, w9, #0x90
 cb4:	f940054a 	ldr	x10, [x10, #8]
 cb8:	927c6d6b 	and	x11, x11, #0xfffffff0
 cbc:	f900f28a 	str	x10, [x20, #480]
 cc0:	1102012a 	add	w10, w9, #0x80
 cc4:	3ceb6900 	ldr	q0, [x8, x11]
 cc8:	927c6d4a 	and	x10, x10, #0xfffffff0
 ccc:	3d807280 	str	q0, [x20, #448]
 cd0:	3cea6900 	ldr	q0, [x8, x10]
 cd4:	1101c12a 	add	w10, w9, #0x70
 cd8:	927c6d4a 	and	x10, x10, #0xfffffff0
 cdc:	3d805680 	str	q0, [x20, #336]
 ce0:	3cea6900 	ldr	q0, [x8, x10]
 ce4:	1101812a 	add	w10, w9, #0x60
 ce8:	927c6d4a 	and	x10, x10, #0xfffffff0
 cec:	3d805280 	str	q0, [x20, #320]
 cf0:	3cea6900 	ldr	q0, [x8, x10]
 cf4:	1101412a 	add	w10, w9, #0x50
 cf8:	927c6d4a 	and	x10, x10, #0xfffffff0
 cfc:	3d804e80 	str	q0, [x20, #304]
 d00:	3cea6900 	ldr	q0, [x8, x10]
 d04:	1101012a 	add	w10, w9, #0x40
 d08:	927c6d4a 	and	x10, x10, #0xfffffff0
 d0c:	3d804a80 	str	q0, [x20, #288]
 d10:	3cea6900 	ldr	q0, [x8, x10]
 d14:	1100c12a 	add	w10, w9, #0x30
 d18:	927c6d4a 	and	x10, x10, #0xfffffff0
 d1c:	3d804680 	str	q0, [x20, #272]
 d20:	3cea6900 	ldr	q0, [x8, x10]
 d24:	91028128 	add	x8, x9, #0xa0
 d28:	f900ea88 	str	x8, [x20, #464]
 d2c:	3d804280 	str	q0, [x20, #256]
 d30:	94000000 	bl	0 <std::__ndk1::chrono::steady_clock::now()>	d30: R_AARCH64_CALL26	std::__ndk1::chrono::steady_clock::now()
 d34:	f9400be8 	ldr	x8, [sp, #16]
 d38:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	d38: R_AARCH64_ADR_GOT_PAGE	g_spart_prof
 d3c:	f9400021 	ldr	x1, [x1]	d3c: R_AARCH64_LD64_GOT_LO12_NC	g_spart_prof
 d40:	cb080000 	sub	x0, x0, x8
 d44:	94000000 	bl	0 <__aarch64_ldadd8_relax>	d44: R_AARCH64_CALL26	__aarch64_ldadd8_relax
 d48:	f9400fe8 	ldr	x8, [sp, #24]
 d4c:	f9401508 	ldr	x8, [x8, #40]
 d50:	f85c03a9 	ldur	x9, [x29, #-64]
 d54:	eb09011f 	cmp	x8, x9
 d58:	54000d81 	b.ne	f08 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xf08>  // b.any
 d5c:	aa1703e0 	mov	x0, x23
 d60:	a9504ff4 	ldp	x20, x19, [sp, #256]
 d64:	fd4043ec 	ldr	d12, [sp, #128]
 d68:	a94f57f6 	ldp	x22, x21, [sp, #240]
 d6c:	a94e5ff8 	ldp	x24, x23, [sp, #224]
 d70:	a94d67fa 	ldp	x26, x25, [sp, #208]
 d74:	a94c6ffc 	ldp	x28, x27, [sp, #192]
 d78:	a94b7bfd 	ldp	x29, x30, [sp, #176]
 d7c:	6d4a23e9 	ldp	d9, d8, [sp, #160]
 d80:	6d492beb 	ldp	d11, d10, [sp, #144]
 d84:	910443ff 	add	sp, sp, #0x110
 d88:	d65f03c0 	ret
 d8c:	52803202 	mov	w2, #0x190                 	// #400
 d90:	f9400fe8 	ldr	x8, [sp, #24]
 d94:	f9401508 	ldr	x8, [x8, #40]
 d98:	f85c03a9 	ldur	x9, [x29, #-64]
 d9c:	eb09011f 	cmp	x8, x9
 da0:	54000320 	b.eq	e04 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe04>  // b.none
 da4:	14000059 	b	f08 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xf08>
 da8:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	da8: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x433
 dac:	91000109 	add	x9, x8, #0x0	dac: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x433
 db0:	52803802 	mov	w2, #0x1c0                 	// #448
 db4:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	db4: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x45a
 db8:	91000108 	add	x8, x8, #0x0	db8: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x45a
 dbc:	a90023e9 	stp	x9, x8, [sp]
 dc0:	f9400fe8 	ldr	x8, [sp, #24]
 dc4:	f9401508 	ldr	x8, [x8, #40]
 dc8:	f85c03a9 	ldur	x9, [x29, #-64]
 dcc:	eb09011f 	cmp	x8, x9
 dd0:	540001a0 	b.eq	e04 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe04>  // b.none
 dd4:	1400004d 	b	f08 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xf08>
 dd8:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	dd8: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x36a
 ddc:	91000109 	add	x9, x8, #0x0	ddc: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x36a
 de0:	52802b02 	mov	w2, #0x158                 	// #344
 de4:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	de4: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x3d2
 de8:	91000108 	add	x8, x8, #0x0	de8: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x3d2
 dec:	a90023e9 	stp	x9, x8, [sp]
 df0:	f9400fe8 	ldr	x8, [sp, #24]
 df4:	f9401508 	ldr	x8, [x8, #40]
 df8:	f85c03a9 	ldur	x9, [x29, #-64]
 dfc:	eb09011f 	cmp	x8, x9
 e00:	54000841 	b.ne	f08 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xf08>  // b.any
 e04:	a9400fe0 	ldp	x0, x3, [sp]
 e08:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	e08: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x397
 e0c:	91000021 	add	x1, x1, #0x0	e0c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x397
 e10:	90000004 	adrp	x4, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	e10: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0xc9
 e14:	91000084 	add	x4, x4, #0x0	e14: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0xc9
 e18:	94000000 	bl	0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>	e18: R_AARCH64_CALL26	private_assert_failed(char const*, char const*, int, char const*, char const*)
 e1c:	f9400fe8 	ldr	x8, [sp, #24]
 e20:	f9401508 	ldr	x8, [x8, #40]
 e24:	f85c03a9 	ldur	x9, [x29, #-64]
 e28:	eb09011f 	cmp	x8, x9
 e2c:	540006e1 	b.ne	f08 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xf08>  // b.any
 e30:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	e30: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1
 e34:	91000000 	add	x0, x0, #0x0	e34: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1
 e38:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	e38: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x2a
 e3c:	91000021 	add	x1, x1, #0x0	e3c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x2a
 e40:	90000003 	adrp	x3, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	e40: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x92
 e44:	91000063 	add	x3, x3, #0x0	e44: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x92
 e48:	90000004 	adrp	x4, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	e48: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0xc9
 e4c:	91000084 	add	x4, x4, #0x0	e4c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0xc9
 e50:	52801f42 	mov	w2, #0xfa                  	// #250
 e54:	94000000 	bl	0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>	e54: R_AARCH64_CALL26	private_assert_failed(char const*, char const*, int, char const*, char const*)
 e58:	f9400fe8 	ldr	x8, [sp, #24]
 e5c:	f9401508 	ldr	x8, [x8, #40]
 e60:	f85c03a9 	ldur	x9, [x29, #-64]
 e64:	eb09011f 	cmp	x8, x9
 e68:	54000501 	b.ne	f08 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xf08>  // b.any
 e6c:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	e6c: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0xca
 e70:	91000000 	add	x0, x0, #0x0	e70: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0xca
 e74:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	e74: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x2a
 e78:	91000021 	add	x1, x1, #0x0	e78: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x2a
 e7c:	90000003 	adrp	x3, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	e7c: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x92
 e80:	91000063 	add	x3, x3, #0x0	e80: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x92
 e84:	90000004 	adrp	x4, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	e84: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0xc9
 e88:	91000084 	add	x4, x4, #0x0	e88: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0xc9
 e8c:	52802002 	mov	w2, #0x100                 	// #256
 e90:	94000000 	bl	0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>	e90: R_AARCH64_CALL26	private_assert_failed(char const*, char const*, int, char const*, char const*)
 e94:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	e94: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x3d2
 e98:	91000109 	add	x9, x8, #0x0	e98: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x3d2
 e9c:	52802b02 	mov	w2, #0x158                 	// #344
 ea0:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	ea0: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x36a
 ea4:	91000108 	add	x8, x8, #0x0	ea4: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x36a
 ea8:	a90027e8 	stp	x8, x9, [sp]
 eac:	f9400fe8 	ldr	x8, [sp, #24]
 eb0:	f9401508 	ldr	x8, [x8, #40]
 eb4:	f85c03a9 	ldur	x9, [x29, #-64]
 eb8:	eb09011f 	cmp	x8, x9
 ebc:	54fffa40 	b.eq	e04 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe04>  // b.none
 ec0:	14000012 	b	f08 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xf08>
 ec4:	14000003 	b	ed0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xed0>
 ec8:	14000002 	b	ed0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xed0>
 ecc:	14000001 	b	ed0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xed0>
 ed0:	aa0003f4 	mov	x20, x0
 ed4:	94000000 	bl	0 <std::__ndk1::chrono::steady_clock::now()>	ed4: R_AARCH64_CALL26	std::__ndk1::chrono::steady_clock::now()
 ed8:	f9400be8 	ldr	x8, [sp, #16]
 edc:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	edc: R_AARCH64_ADR_GOT_PAGE	g_spart_prof
 ee0:	f9400021 	ldr	x1, [x1]	ee0: R_AARCH64_LD64_GOT_LO12_NC	g_spart_prof
 ee4:	cb080000 	sub	x0, x0, x8
 ee8:	94000000 	bl	0 <__aarch64_ldadd8_relax>	ee8: R_AARCH64_CALL26	__aarch64_ldadd8_relax
 eec:	f9400fe8 	ldr	x8, [sp, #24]
 ef0:	f9401508 	ldr	x8, [x8, #40]
 ef4:	f85c03a9 	ldur	x9, [x29, #-64]
 ef8:	eb09011f 	cmp	x8, x9
 efc:	54000061 	b.ne	f08 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xf08>  // b.any
 f00:	aa1403e0 	mov	x0, x20
 f04:	94000000 	bl	0 <_Unwind_Resume>	f04: R_AARCH64_CALL26	_Unwind_Resume
 f08:	94000000 	bl	0 <__stack_chk_fail>	f08: R_AARCH64_CALL26	__stack_chk_fail

Disassembly of section .text._ZN6Mips2C4jak119sp_process_block_3d4linkEv:

0000000000000000 <Mips2C::jak1::sp_process_block_3d::link()>:
   0:	d10143ff 	sub	sp, sp, #0x50
   4:	a9027bfd 	stp	x29, x30, [sp, #32]
   8:	f9001bf5 	str	x21, [sp, #48]
   c:	a9044ff4 	stp	x20, x19, [sp, #64]
  10:	910083fd 	add	x29, sp, #0x20
  14:	d53bd054 	mrs	x20, tpidr_el0
  18:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_3d::link()>	18: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0xf5
  1c:	91000000 	add	x0, x0, #0x0	1c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0xf5
  20:	f9401688 	ldr	x8, [x20, #40]
  24:	f81f83a8 	stur	x8, [x29, #-8]
  28:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	28: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  2c:	90000013 	adrp	x19, 0 <g_ee_main_mem>	2c: R_AARCH64_ADR_GOT_PAGE	g_ee_main_mem
  30:	90000015 	adrp	x21, 0 <Mips2C::jak1::sp_process_block_3d::link()>	30: R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_3d::cache
  34:	7100001f 	cmp	w0, #0x0
  38:	f9400273 	ldr	x19, [x19]	38: R_AARCH64_LD64_GOT_LO12_NC	g_ee_main_mem
  3c:	f9400268 	ldr	x8, [x19]
  40:	f94002b5 	ldr	x21, [x21]	40: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_3d::cache
  44:	8b204108 	add	x8, x8, w0, uxtw
  48:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_3d::link()>	48: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x105
  4c:	91000000 	add	x0, x0, #0x0	4c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x105
  50:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  54:	f90002a8 	str	x8, [x21]
  58:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	58: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  5c:	f9400268 	ldr	x8, [x19]
  60:	7100001f 	cmp	w0, #0x0
  64:	8b204108 	add	x8, x8, w0, uxtw
  68:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_3d::link()>	68: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x112
  6c:	91000000 	add	x0, x0, #0x0	6c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x112
  70:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  74:	f90006a8 	str	x8, [x21, #8]
  78:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	78: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  7c:	f9400268 	ldr	x8, [x19]
  80:	7100001f 	cmp	w0, #0x0
  84:	8b204108 	add	x8, x8, w0, uxtw
  88:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_3d::link()>	88: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x123
  8c:	91000000 	add	x0, x0, #0x0	8c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x123
  90:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  94:	f9000aa8 	str	x8, [x21, #16]
  98:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	98: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  9c:	f9400268 	ldr	x8, [x19]
  a0:	9000000b 	adrp	x11, 0 <Mips2C::jak1::sp_process_block_3d::link()>	a0: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x13b
  a4:	9100016b 	add	x11, x11, #0x0	a4: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x13b
  a8:	5285ad6a 	mov	w10, #0x2d6b                	// #11627
  ac:	3dc00160 	ldr	q0, [x11]
  b0:	7100001f 	cmp	w0, #0x0
  b4:	8b204108 	add	x8, x8, w0, uxtw
  b8:	528004c9 	mov	w9, #0x26                  	// #38
  bc:	72ac866a 	movk	w10, #0x6433, lsl #16
  c0:	390003e9 	strb	w9, [sp]
  c4:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  c8:	b90013ea 	str	w10, [sp, #16]
  cc:	3c8013e0 	stur	q0, [sp, #1]
  d0:	f9000ea8 	str	x8, [x21, #24]
  d4:	390053ff 	strb	wzr, [sp, #20]
  d8:	90000000 	adrp	x0, 0 <Mips2C::gLinkedFunctionTable>	d8: R_AARCH64_ADR_GOT_PAGE	Mips2C::gLinkedFunctionTable
  dc:	90000002 	adrp	x2, 0 <Mips2C::jak1::sp_process_block_3d::link()>	dc: R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_3d::execute(void*)
  e0:	910003e1 	mov	x1, sp
  e4:	f9400000 	ldr	x0, [x0]	e4: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::gLinkedFunctionTable
  e8:	f9400042 	ldr	x2, [x2]	e8: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_3d::execute(void*)
  ec:	52802003 	mov	w3, #0x100                 	// #256
  f0:	94000000 	bl	0 <Mips2C::LinkedFunctionTable::reg(std::__ndk1::basic_string<char, std::__ndk1::char_traits<char>, std::__ndk1::allocator<char> > const&, unsigned long (*)(void*), unsigned int)>	f0: R_AARCH64_CALL26	Mips2C::LinkedFunctionTable::reg(std::__ndk1::basic_string<char, std::__ndk1::char_traits<char>, std::__ndk1::allocator<char> > const&, unsigned long (*)(void*), unsigned int)
  f4:	394003e8 	ldrb	w8, [sp]
  f8:	36000068 	tbz	w8, #0, 104 <Mips2C::jak1::sp_process_block_3d::link()+0x104>
  fc:	f9400be0 	ldr	x0, [sp, #16]
 100:	94000000 	bl	0 <operator delete(void*)>	100: R_AARCH64_CALL26	operator delete(void*)
 104:	f9401688 	ldr	x8, [x20, #40]
 108:	f85f83a9 	ldur	x9, [x29, #-8]
 10c:	eb09011f 	cmp	x8, x9
 110:	54000221 	b.ne	154 <Mips2C::jak1::sp_process_block_3d::link()+0x154>  // b.any
 114:	a9444ff4 	ldp	x20, x19, [sp, #64]
 118:	f9401bf5 	ldr	x21, [sp, #48]
 11c:	a9427bfd 	ldp	x29, x30, [sp, #32]
 120:	910143ff 	add	sp, sp, #0x50
 124:	d65f03c0 	ret
 128:	394003e8 	ldrb	w8, [sp]
 12c:	aa0003f3 	mov	x19, x0
 130:	36000068 	tbz	w8, #0, 13c <Mips2C::jak1::sp_process_block_3d::link()+0x13c>
 134:	f9400be0 	ldr	x0, [sp, #16]
 138:	94000000 	bl	0 <operator delete(void*)>	138: R_AARCH64_CALL26	operator delete(void*)
 13c:	f9401688 	ldr	x8, [x20, #40]
 140:	f85f83a9 	ldur	x9, [x29, #-8]
 144:	eb09011f 	cmp	x8, x9
 148:	54000061 	b.ne	154 <Mips2C::jak1::sp_process_block_3d::link()+0x154>  // b.any
 14c:	aa1303e0 	mov	x0, x19
 150:	94000000 	bl	0 <_Unwind_Resume>	150: R_AARCH64_CALL26	_Unwind_Resume
 154:	94000000 	bl	0 <__stack_chk_fail>	154: R_AARCH64_CALL26	__stack_chk_fail

Disassembly of section .text._ZN6Mips2C4jak119sp_process_block_2d7executeEPv:

0000000000000000 <Mips2C::jak1::sp_process_block_2d::execute(void*)>:
       0:	d10543ff 	sub	sp, sp, #0x150
       4:	fd006bea 	str	d10, [sp, #208]
       8:	6d0e23e9 	stp	d9, d8, [sp, #224]
       c:	a90f7bfd 	stp	x29, x30, [sp, #240]
      10:	a9106ffc 	stp	x28, x27, [sp, #256]
      14:	a91167fa 	stp	x26, x25, [sp, #272]
      18:	a9125ff8 	stp	x24, x23, [sp, #288]
      1c:	a91357f6 	stp	x22, x21, [sp, #304]
      20:	a9144ff4 	stp	x20, x19, [sp, #320]
      24:	9103c3fd 	add	x29, sp, #0xf0
      28:	d53bd048 	mrs	x8, tpidr_el0
      2c:	aa0003f4 	mov	x20, x0
      30:	f9003fe8 	str	x8, [sp, #120]
      34:	f9401508 	ldr	x8, [x8, #40]
      38:	f81d03a8 	stur	x8, [x29, #-48]
      3c:	94000000 	bl	0 <std::__ndk1::chrono::steady_clock::now()>	3c: R_AARCH64_CALL26	std::__ndk1::chrono::steady_clock::now()
      40:	f9003be0 	str	x0, [sp, #112]
      44:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	44: R_AARCH64_ADR_GOT_PAGE	g_spart_prof
      48:	52800020 	mov	w0, #0x1                   	// #1
      4c:	f9400108 	ldr	x8, [x8]	4c: R_AARCH64_LD64_GOT_LO12_NC	g_spart_prof
      50:	9100a101 	add	x1, x8, #0x28
      54:	94000000 	bl	0 <__aarch64_ldadd8_relax>	54: R_AARCH64_CALL26	__aarch64_ldadd8_relax
      58:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	58: R_AARCH64_ADR_GOT_PAGE	g_perf_2dvec_off
      5c:	9000001b 	adrp	x27, 0 <g_ee_main_mem>	5c: R_AARCH64_ADR_GOT_PAGE	g_ee_main_mem
      60:	aa1403f6 	mov	x22, x20
      64:	f9400108 	ldr	x8, [x8]	64: R_AARCH64_LD64_GOT_LO12_NC	g_perf_2dvec_off
      68:	f940037b 	ldr	x27, [x27]	68: R_AARCH64_LD64_GOT_LO12_NC	g_ee_main_mem
      6c:	39400113 	ldrb	w19, [x8]
      70:	f940ea88 	ldr	x8, [x20, #464]
      74:	f9400369 	ldr	x9, [x27]
      78:	f940fa8a 	ldr	x10, [x20, #496]
      7c:	d1020108 	sub	x8, x8, #0x80
      80:	f900ea88 	str	x8, [x20, #464]
      84:	f828492a 	str	x10, [x9, w8, uxtw]
      88:	9000000a 	adrp	x10, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	88: R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_2d::cache
      8c:	b941d288 	ldr	w8, [x20, #464]
      90:	f9400369 	ldr	x9, [x27]
      94:	3dc04280 	ldr	q0, [x20, #256]
      98:	11004108 	add	w8, w8, #0x10
      9c:	927c6d08 	and	x8, x8, #0xfffffff0
      a0:	3ca86920 	str	q0, [x9, x8]
      a4:	b941d288 	ldr	w8, [x20, #464]
      a8:	f9400369 	ldr	x9, [x27]
      ac:	3dc04680 	ldr	q0, [x20, #272]
      b0:	11008108 	add	w8, w8, #0x20
      b4:	927c6d08 	and	x8, x8, #0xfffffff0
      b8:	3ca86920 	str	q0, [x9, x8]
      bc:	b941d288 	ldr	w8, [x20, #464]
      c0:	f9400369 	ldr	x9, [x27]
      c4:	3dc04a80 	ldr	q0, [x20, #288]
      c8:	1100c108 	add	w8, w8, #0x30
      cc:	927c6d08 	and	x8, x8, #0xfffffff0
      d0:	3ca86920 	str	q0, [x9, x8]
      d4:	b941d288 	ldr	w8, [x20, #464]
      d8:	f9400369 	ldr	x9, [x27]
      dc:	3dc04e80 	ldr	q0, [x20, #304]
      e0:	11010108 	add	w8, w8, #0x40
      e4:	927c6d08 	and	x8, x8, #0xfffffff0
      e8:	3ca86920 	str	q0, [x9, x8]
      ec:	b941d288 	ldr	w8, [x20, #464]
      f0:	f9400369 	ldr	x9, [x27]
      f4:	3dc05280 	ldr	q0, [x20, #320]
      f8:	11014108 	add	w8, w8, #0x50
      fc:	927c6d08 	and	x8, x8, #0xfffffff0
     100:	3ca86920 	str	q0, [x9, x8]
     104:	b941d288 	ldr	w8, [x20, #464]
     108:	f9400369 	ldr	x9, [x27]
     10c:	3dc05680 	ldr	q0, [x20, #336]
     110:	11018108 	add	w8, w8, #0x60
     114:	927c6d08 	and	x8, x8, #0xfffffff0
     118:	3ca86920 	str	q0, [x9, x8]
     11c:	b941d288 	ldr	w8, [x20, #464]
     120:	f9400369 	ldr	x9, [x27]
     124:	3dc07280 	ldr	q0, [x20, #448]
     128:	1101c108 	add	w8, w8, #0x70
     12c:	927c6d08 	and	x8, x8, #0xfffffff0
     130:	3ca86920 	str	q0, [x9, x8]
     134:	f9402288 	ldr	x8, [x20, #64]
     138:	f940014a 	ldr	x10, [x10]	138: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_2d::cache
     13c:	f9402a89 	ldr	x9, [x20, #80]
     140:	f900e288 	str	x8, [x20, #448]
     144:	f9403288 	ldr	x8, [x20, #96]
     148:	f900aa89 	str	x9, [x20, #336]
     14c:	f9403a89 	ldr	x9, [x20, #112]
     150:	f900a288 	str	x8, [x20, #320]
     154:	f9404288 	ldr	x8, [x20, #128]
     158:	f9008a89 	str	x9, [x20, #272]
     15c:	f9404a89 	ldr	x9, [x20, #144]
     160:	f9009a88 	str	x8, [x20, #304]
     164:	f9400148 	ldr	x8, [x10]
     168:	f9009289 	str	x9, [x20, #288]
     16c:	b9800108 	ldrsw	x8, [x8]
     170:	72000d1f 	tst	w8, #0xf
     174:	f8030ec8 	str	x8, [x22, #48]!
     178:	54008941 	b.ne	12a0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x12a0>  // b.any
     17c:	f9400369 	ldr	x9, [x27]
     180:	927c6d08 	and	x8, x8, #0xfffffff0
     184:	2f00e409 	movi	d9, #0x0
     188:	1e2e1008 	fmov	s8, #1.000000000000000000e+00
     18c:	1e3e100a 	fmov	s10, #-1.000000000000000000e+00
     190:	f940aa9a 	ldr	x26, [x20, #336]
     194:	3ce86920 	ldr	q0, [x9, x8]
     198:	910992d9 	add	x25, x22, #0x264
     19c:	91048298 	add	x24, x20, #0x120
     1a0:	9105029c 	add	x28, x20, #0x140
     1a4:	91054297 	add	x23, x20, #0x150
     1a8:	3d80c680 	str	q0, [x20, #784]
     1ac:	b9431288 	ldr	w8, [x20, #784]
     1b0:	b9431689 	ldr	w9, [x20, #788]
     1b4:	f9418e8a 	ldr	x10, [x20, #792]
     1b8:	92401d0b 	and	x11, x8, #0xff
     1bc:	aa098108 	orr	x8, x8, x9, lsl #32
     1c0:	f900828b 	str	x11, [x20, #256]
     1c4:	a9032a88 	stp	x8, x10, [x20, #48]
     1c8:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1c8: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x40a
     1cc:	91000109 	add	x9, x8, #0x0	1cc: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x40a
     1d0:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1d0: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x405
     1d4:	91000108 	add	x8, x8, #0x0	1d4: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x405
     1d8:	a90623e9 	stp	x9, x8, [sp, #96]
     1dc:	1400000e 	b	214 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x214>
     1e0:	f9409a88 	ldr	x8, [x20, #304]
     1e4:	f94002e9 	ldr	x9, [x23]
     1e8:	f940038a 	ldr	x10, [x28]
     1ec:	f9408a8b 	ldr	x11, [x20, #272]
     1f0:	f1000508 	subs	x8, x8, #0x1
     1f4:	9102413a 	add	x26, x9, #0x90
     1f8:	f9009a88 	str	x8, [x20, #304]
     1fc:	9100c148 	add	x8, x10, #0x30
     200:	91000575 	add	x21, x11, #0x1
     204:	f90002fa 	str	x26, [x23]
     208:	f9000388 	str	x8, [x28]
     20c:	f9008a95 	str	x21, [x20, #272]
     210:	540078c0 	b.eq	1128 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1128>  // b.none
     214:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	214: R_AARCH64_ADR_GOT_PAGE	g_spart_prof
     218:	52800020 	mov	w0, #0x1                   	// #1
     21c:	f9400108 	ldr	x8, [x8]	21c: R_AARCH64_LD64_GOT_LO12_NC	g_spart_prof
     220:	91012101 	add	x1, x8, #0x48
     224:	94000000 	bl	0 <__aarch64_ldadd8_relax>	224: R_AARCH64_CALL26	__aarch64_ldadd8_relax
     228:	f9400365 	ldr	x5, [x27]
     22c:	92407f49 	and	x9, x26, #0xffffffff
     230:	b941728b 	ldr	w11, [x20, #368]
     234:	8b0900a8 	add	x8, x5, x9
     238:	b980810a 	ldrsw	x10, [x8, #128]
     23c:	6b0b015f 	cmp	w10, w11
     240:	f9001a8a 	str	x10, [x20, #48]
     244:	54fffce0 	b.eq	1e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1e0>  // b.none
     248:	b940030c 	ldr	w12, [x24]
     24c:	b980690a 	ldrsw	x10, [x8, #104]
     250:	6b0b019f 	cmp	w12, w11
     254:	f90002ca 	str	x10, [x22]
     258:	54000320 	b.eq	2bc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x2bc>  // b.none
     25c:	9273014b 	and	x11, x10, #0x2000
     260:	f90002cb 	str	x11, [x22]
     264:	376802ca 	tbnz	w10, #13, 2bc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x2bc>
     268:	b9806509 	ldrsw	x9, [x8, #100]
     26c:	9280000a 	mov	x10, #0xffffffffffffffff    	// #-1
     270:	f900228a 	str	x10, [x20, #64]
     274:	f9001a89 	str	x9, [x20, #48]
     278:	34007189 	cbz	w9, 10a8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x10a8>
     27c:	b9806909 	ldrsw	x9, [x8, #104]
     280:	927a012a 	and	x10, x9, #0x40
     284:	9279f92b 	and	x11, x9, #0xffffffffffffffbf
     288:	f9001a8a 	str	x10, [x20, #48]
     28c:	f900228b 	str	x11, [x20, #64]
     290:	b900690b 	str	w11, [x8, #104]
     294:	3637fa69 	tbz	w9, #6, 1e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1e0>
     298:	f9400368 	ldr	x8, [x27]
     29c:	b94002e9 	ldr	w9, [x23]
     2a0:	b940038a 	ldr	w10, [x28]
     2a4:	8b090109 	add	x9, x8, x9
     2a8:	8b0a0108 	add	x8, x8, x10
     2ac:	b9807d29 	ldrsw	x9, [x9, #124]
     2b0:	f90002c9 	str	x9, [x22]
     2b4:	b9002d09 	str	w9, [x8, #44]
     2b8:	17ffffca 	b	1e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1e0>
     2bc:	b980650a 	ldrsw	x10, [x8, #100]
     2c0:	f940828b 	ldr	x11, [x20, #256]
     2c4:	cb0b014b 	sub	x11, x10, x11
     2c8:	3100055f 	cmn	w10, #0x1
     2cc:	f9001a8a 	str	x10, [x20, #48]
     2d0:	f900228b 	str	x11, [x20, #64]
     2d4:	54000200 	b.eq	314 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x314>  // b.none
     2d8:	1e270160 	fmov	s0, w11
     2dc:	d360fd69 	lsr	x9, x11, #32
     2e0:	6f00e401 	movi	v1.2d, #0x0
     2e4:	4e0c1d20 	mov	v0.s[1], w9
     2e8:	91012289 	add	x9, x20, #0x48
     2ec:	4d408120 	ld1	{v0.s}[2], [x9]
     2f0:	91013289 	add	x9, x20, #0x4c
     2f4:	4d409120 	ld1	{v0.s}[3], [x9]
     2f8:	4ea16400 	smax	v0.4s, v0.4s, v1.4s
     2fc:	3d800e80 	str	q0, [x20, #48]
     300:	34006d4a 	cbz	w10, 10a8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x10a8>
     304:	f94002c9 	ldr	x9, [x22]
     308:	b9006509 	str	w9, [x8, #100]
     30c:	f9400365 	ldr	x5, [x27]
     310:	b94002e9 	ldr	w9, [x23]
     314:	8b0900a8 	add	x8, x5, x9
     318:	b9806909 	ldrsw	x9, [x8, #104]
     31c:	927a012a 	and	x10, x9, #0x40
     320:	9279f92b 	and	x11, x9, #0xffffffffffffffbf
     324:	f9001a8a 	str	x10, [x20, #48]
     328:	f900228b 	str	x11, [x20, #64]
     32c:	b900690b 	str	w11, [x8, #104]
     330:	36300129 	tbz	w9, #6, 354 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x354>
     334:	f9400368 	ldr	x8, [x27]
     338:	b94002e9 	ldr	w9, [x23]
     33c:	b940038a 	ldr	w10, [x28]
     340:	8b090109 	add	x9, x8, x9
     344:	8b0a0108 	add	x8, x8, x10
     348:	b9807d29 	ldrsw	x9, [x9, #124]
     34c:	f90002c9 	str	x9, [x22]
     350:	b9002d09 	str	w9, [x8, #44]
     354:	f9400368 	ldr	x8, [x27]
     358:	b9415281 	ldr	w1, [x20, #336]
     35c:	8b010109 	add	x9, x8, x1
     360:	b9807129 	ldrsw	x9, [x9, #112]
     364:	f900ca89 	str	x9, [x20, #400]
     368:	34000d69 	cbz	w9, 514 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x514>
     36c:	f940ea89 	ldr	x9, [x20, #464]
     370:	3dc07280 	ldr	q0, [x20, #448]
     374:	d1014129 	sub	x9, x9, #0x50
     378:	f900ea89 	str	x9, [x20, #464]
     37c:	927c6d29 	and	x9, x9, #0xfffffff0
     380:	3ca96900 	str	q0, [x8, x9]
     384:	b941d288 	ldr	w8, [x20, #464]
     388:	f9400369 	ldr	x9, [x27]
     38c:	3dc05680 	ldr	q0, [x20, #336]
     390:	11004108 	add	w8, w8, #0x10
     394:	927c6d08 	and	x8, x8, #0xfffffff0
     398:	3ca86920 	str	q0, [x9, x8]
     39c:	b941d288 	ldr	w8, [x20, #464]
     3a0:	f9400369 	ldr	x9, [x27]
     3a4:	3dc05280 	ldr	q0, [x20, #320]
     3a8:	11008108 	add	w8, w8, #0x20
     3ac:	927c6d08 	and	x8, x8, #0xfffffff0
     3b0:	3ca86920 	str	q0, [x9, x8]
     3b4:	b941d288 	ldr	w8, [x20, #464]
     3b8:	f9400369 	ldr	x9, [x27]
     3bc:	3dc04680 	ldr	q0, [x20, #272]
     3c0:	1100c108 	add	w8, w8, #0x30
     3c4:	927c6d08 	and	x8, x8, #0xfffffff0
     3c8:	3ca86920 	str	q0, [x9, x8]
     3cc:	f940e288 	ldr	x8, [x20, #448]
     3d0:	b941d28a 	ldr	w10, [x20, #464]
     3d4:	f940aa89 	ldr	x9, [x20, #336]
     3d8:	f940a28b 	ldr	x11, [x20, #320]
     3dc:	f940036c 	ldr	x12, [x27]
     3e0:	3dc04e80 	ldr	q0, [x20, #304]
     3e4:	f9002288 	str	x8, [x20, #64]
     3e8:	11010148 	add	w8, w10, #0x40
     3ec:	f9002a89 	str	x9, [x20, #80]
     3f0:	927c6d09 	and	x9, x8, #0xfffffff0
     3f4:	b9419288 	ldr	w8, [x20, #400]
     3f8:	f900328b 	str	x11, [x20, #96]
     3fc:	3ca96980 	str	q0, [x12, x9]
     400:	f9402289 	ldr	x9, [x20, #64]
     404:	f9402a8a 	ldr	x10, [x20, #80]
     408:	f940328b 	ldr	x11, [x20, #96]
     40c:	a9392ba9 	stp	x9, x10, [x29, #-112]
     410:	f9403a89 	ldr	x9, [x20, #112]
     414:	f940428a 	ldr	x10, [x20, #128]
     418:	a93a27ab 	stp	x11, x9, [x29, #-96]
     41c:	f9404a8b 	ldr	x11, [x20, #144]
     420:	f9405289 	ldr	x9, [x20, #160]
     424:	a93b2faa 	stp	x10, x11, [x29, #-80]
     428:	f9405a8a 	ldr	x10, [x20, #176]
     42c:	a93c2ba9 	stp	x9, x10, [x29, #-64]
     430:	34006f08 	cbz	w8, 1210 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1210>
     434:	f9400365 	ldr	x5, [x27]
     438:	f940b283 	ldr	x3, [x20, #352]
     43c:	f940ba84 	ldr	x4, [x20, #368]
     440:	8b0800a0 	add	x0, x5, x8
     444:	d101c3a1 	sub	x1, x29, #0x70
     448:	aa1f03e2 	mov	x2, xzr
     44c:	94000000 	bl	0 <_call_goal8_asm_systemv>	44c: R_AARCH64_CALL26	_call_goal8_asm_systemv
     450:	f940ea88 	ldr	x8, [x20, #464]
     454:	f9400369 	ldr	x9, [x27]
     458:	f9001280 	str	x0, [x20, #32]
     45c:	927c6d0a 	and	x10, x8, #0xfffffff0
     460:	3cea6920 	ldr	q0, [x9, x10]
     464:	1100410a 	add	w10, w8, #0x10
     468:	927c6d4a 	and	x10, x10, #0xfffffff0
     46c:	3d807280 	str	q0, [x20, #448]
     470:	3cea6920 	ldr	q0, [x9, x10]
     474:	1100810a 	add	w10, w8, #0x20
     478:	927c6d4a 	and	x10, x10, #0xfffffff0
     47c:	3d8002e0 	str	q0, [x23]
     480:	3cea6920 	ldr	q0, [x9, x10]
     484:	1100c10a 	add	w10, w8, #0x30
     488:	927c6d4a 	and	x10, x10, #0xfffffff0
     48c:	3d800380 	str	q0, [x28]
     490:	3cea6920 	ldr	q0, [x9, x10]
     494:	1101010a 	add	w10, w8, #0x40
     498:	91014108 	add	x8, x8, #0x50
     49c:	927c6d4a 	and	x10, x10, #0xfffffff0
     4a0:	3d804680 	str	q0, [x20, #272]
     4a4:	3cea6920 	ldr	q0, [x9, x10]
     4a8:	f900ea88 	str	x8, [x20, #464]
     4ac:	3d804e80 	str	q0, [x20, #304]
     4b0:	94000000 	bl	0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	4b0: R_AARCH64_CALL26	.text._ZN6Mips2C4jak1L21geco_spart_dump_armedEv
     4b4:	9000000b 	adrp	x11, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	4b4: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals
     4b8:	5283e808 	mov	w8, #0x1f40                	// #8000
     4bc:	b94002e1 	ldr	w1, [x23]
     4c0:	b9400169 	ldr	w9, [x11]	4c0: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals
     4c4:	6b08013f 	cmp	w9, w8
     4c8:	1a9fa7e8 	cset	w8, lt	// lt = tstop
     4cc:	0a08000a 	and	w10, w0, w8
     4d0:	f9400368 	ldr	x8, [x27]
     4d4:	7100055f 	cmp	w10, #0x1
     4d8:	540001e1 	b.ne	514 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x514>  // b.any
     4dc:	11000529 	add	w9, w9, #0x1
     4e0:	8b010108 	add	x8, x8, x1
     4e4:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	4e4: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x14f
     4e8:	91000000 	add	x0, x0, #0x0	4e8: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x14f
     4ec:	b9000169 	str	w9, [x11]	4ec: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals
     4f0:	294e0d02 	ldp	w2, w3, [x8, #112]
     4f4:	b9407904 	ldr	w4, [x8, #120]
     4f8:	94000000 	bl	0 <printf>	4f8: R_AARCH64_CALL26	printf
     4fc:	90000008 	adrp	x8, 0 <stdout>	4fc: R_AARCH64_ADR_GOT_PAGE	stdout
     500:	f9400108 	ldr	x8, [x8]	500: R_AARCH64_LD64_GOT_LO12_NC	stdout
     504:	f9400100 	ldr	x0, [x8]
     508:	94000000 	bl	0 <fflush>	508: R_AARCH64_CALL26	fflush
     50c:	f9400368 	ldr	x8, [x27]
     510:	b94002e1 	ldr	w1, [x23]
     514:	8b010108 	add	x8, x8, x1
     518:	f940828b 	ldr	x11, [x20, #256]
     51c:	b980790a 	ldrsw	x10, [x8, #120]
     520:	f9002a8a 	str	x10, [x20, #80]
     524:	b9807509 	ldrsw	x9, [x8, #116]
     528:	f9001a89 	str	x9, [x20, #48]
     52c:	cb0b0129 	sub	x9, x9, x11
     530:	f9002289 	str	x9, [x20, #64]
     534:	3400154a 	cbz	w10, 7dc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x7dc>
     538:	f100052a 	subs	x10, x9, #0x1
     53c:	f90002ca 	str	x10, [x22]
     540:	b9007509 	str	w9, [x8, #116]
     544:	540014c5 	b.pl	7dc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x7dc>  // b.nfrst
     548:	f940ea88 	ldr	x8, [x20, #464]
     54c:	f9400369 	ldr	x9, [x27]
     550:	3dc07280 	ldr	q0, [x20, #448]
     554:	d1018108 	sub	x8, x8, #0x60
     558:	f900ea88 	str	x8, [x20, #464]
     55c:	927c6d08 	and	x8, x8, #0xfffffff0
     560:	3ca86920 	str	q0, [x9, x8]
     564:	b941d288 	ldr	w8, [x20, #464]
     568:	f9400369 	ldr	x9, [x27]
     56c:	3dc05680 	ldr	q0, [x20, #336]
     570:	11004108 	add	w8, w8, #0x10
     574:	927c6d08 	and	x8, x8, #0xfffffff0
     578:	3ca86920 	str	q0, [x9, x8]
     57c:	b941d288 	ldr	w8, [x20, #464]
     580:	f9400369 	ldr	x9, [x27]
     584:	3dc05280 	ldr	q0, [x20, #320]
     588:	11008108 	add	w8, w8, #0x20
     58c:	927c6d08 	and	x8, x8, #0xfffffff0
     590:	3ca86920 	str	q0, [x9, x8]
     594:	b941d288 	ldr	w8, [x20, #464]
     598:	f9400369 	ldr	x9, [x27]
     59c:	3dc04680 	ldr	q0, [x20, #272]
     5a0:	1100c108 	add	w8, w8, #0x30
     5a4:	927c6d08 	and	x8, x8, #0xfffffff0
     5a8:	3ca86920 	str	q0, [x9, x8]
     5ac:	b941d288 	ldr	w8, [x20, #464]
     5b0:	f9400369 	ldr	x9, [x27]
     5b4:	3dc04e80 	ldr	q0, [x20, #304]
     5b8:	11010108 	add	w8, w8, #0x40
     5bc:	927c6d08 	and	x8, x8, #0xfffffff0
     5c0:	3ca86920 	str	q0, [x9, x8]
     5c4:	b941d288 	ldr	w8, [x20, #464]
     5c8:	f9400369 	ldr	x9, [x27]
     5cc:	3dc04a80 	ldr	q0, [x20, #288]
     5d0:	11014108 	add	w8, w8, #0x50
     5d4:	927c6d08 	and	x8, x8, #0xfffffff0
     5d8:	3ca86920 	str	q0, [x9, x8]
     5dc:	f940e288 	ldr	x8, [x20, #448]
     5e0:	f940a289 	ldr	x9, [x20, #320]
     5e4:	f9002288 	str	x8, [x20, #64]
     5e8:	f940aa88 	ldr	x8, [x20, #336]
     5ec:	f9003a89 	str	x9, [x20, #112]
     5f0:	f9003288 	str	x8, [x20, #96]
     5f4:	94000000 	bl	0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	5f4: R_AARCH64_CALL26	.text._ZN6Mips2C4jak1L21geco_spart_dump_armedEv
     5f8:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	5f8: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals+0x4
     5fc:	5283e809 	mov	w9, #0x1f40                	// #8000
     600:	b9400108 	ldr	w8, [x8]	600: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals+0x4
     604:	6b09011f 	cmp	w8, w9
     608:	1a9fa7e9 	cset	w9, lt	// lt = tstop
     60c:	0a090015 	and	w21, w0, w9
     610:	710006bf 	cmp	w21, #0x1
     614:	540003a1 	b.ne	688 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x688>  // b.any
     618:	f9400369 	ldr	x9, [x27]
     61c:	b940038a 	ldr	w10, [x28]
     620:	11000508 	add	w8, w8, #0x1
     624:	9000000b 	adrp	x11, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	624: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals+0x4
     628:	f94002e1 	ldr	x1, [x23]
     62c:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	62c: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x174
     630:	91000000 	add	x0, x0, #0x0	630: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x174
     634:	b9000168 	str	w8, [x11]	634: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals+0x4
     638:	8b0a0128 	add	x8, x9, x10
     63c:	2d400500 	ldp	s0, s1, [x8]
     640:	bd400902 	ldr	s2, [x8, #8]
     644:	2d441103 	ldp	s3, s4, [x8, #32]
     648:	8b214129 	add	x9, x9, w1, uxtw
     64c:	2d451905 	ldp	s5, s6, [x8, #40]
     650:	1e22c042 	fcvt	d2, s2
     654:	1e22c000 	fcvt	d0, s0
     658:	1e22c021 	fcvt	d1, s1
     65c:	b9407122 	ldr	w2, [x9, #112]
     660:	1e22c063 	fcvt	d3, s3
     664:	1e22c084 	fcvt	d4, s4
     668:	b9407923 	ldr	w3, [x9, #120]
     66c:	1e22c0a5 	fcvt	d5, s5
     670:	1e22c0c6 	fcvt	d6, s6
     674:	94000000 	bl	0 <printf>	674: R_AARCH64_CALL26	printf
     678:	90000008 	adrp	x8, 0 <stdout>	678: R_AARCH64_ADR_GOT_PAGE	stdout
     67c:	f9400108 	ldr	x8, [x8]	67c: R_AARCH64_LD64_GOT_LO12_NC	stdout
     680:	f9400100 	ldr	x0, [x8]
     684:	94000000 	bl	0 <fflush>	684: R_AARCH64_CALL26	fflush
     688:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	688: R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_2d::cache
     68c:	f9400108 	ldr	x8, [x8]	68c: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_2d::cache
     690:	b981f289 	ldrsw	x9, [x20, #496]
     694:	f940228a 	ldr	x10, [x20, #64]
     698:	f9402a8b 	ldr	x11, [x20, #80]
     69c:	f9400d08 	ldr	x8, [x8, #24]
     6a0:	b9800108 	ldrsw	x8, [x8]
     6a4:	f9001289 	str	x9, [x20, #32]
     6a8:	f9403289 	ldr	x9, [x20, #96]
     6ac:	a9392faa 	stp	x10, x11, [x29, #-112]
     6b0:	f9403a8a 	ldr	x10, [x20, #112]
     6b4:	f940428b 	ldr	x11, [x20, #128]
     6b8:	f900ca88 	str	x8, [x20, #400]
     6bc:	a93a2ba9 	stp	x9, x10, [x29, #-96]
     6c0:	f9404a89 	ldr	x9, [x20, #144]
     6c4:	f940528a 	ldr	x10, [x20, #160]
     6c8:	a93b27ab 	stp	x11, x9, [x29, #-80]
     6cc:	f9405a89 	ldr	x9, [x20, #176]
     6d0:	a93c27aa 	stp	x10, x9, [x29, #-64]
     6d4:	340059e8 	cbz	w8, 1210 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1210>
     6d8:	f9400365 	ldr	x5, [x27]
     6dc:	f940b283 	ldr	x3, [x20, #352]
     6e0:	92407d08 	and	x8, x8, #0xffffffff
     6e4:	f940ba84 	ldr	x4, [x20, #368]
     6e8:	8b0800a0 	add	x0, x5, x8
     6ec:	d101c3a1 	sub	x1, x29, #0x70
     6f0:	aa1f03e2 	mov	x2, xzr
     6f4:	94000000 	bl	0 <_call_goal8_asm_systemv>	6f4: R_AARCH64_CALL26	_call_goal8_asm_systemv
     6f8:	f940ea89 	ldr	x9, [x20, #464]
     6fc:	f9400368 	ldr	x8, [x27]
     700:	f9001280 	str	x0, [x20, #32]
     704:	927c6d2a 	and	x10, x9, #0xfffffff0
     708:	3cea6900 	ldr	q0, [x8, x10]
     70c:	1100412a 	add	w10, w9, #0x10
     710:	927c6d4a 	and	x10, x10, #0xfffffff0
     714:	3d807280 	str	q0, [x20, #448]
     718:	3cea6900 	ldr	q0, [x8, x10]
     71c:	1100812a 	add	w10, w9, #0x20
     720:	927c6d4a 	and	x10, x10, #0xfffffff0
     724:	3d8002e0 	str	q0, [x23]
     728:	3cea6900 	ldr	q0, [x8, x10]
     72c:	1100c12a 	add	w10, w9, #0x30
     730:	927c6d4a 	and	x10, x10, #0xfffffff0
     734:	3d800380 	str	q0, [x28]
     738:	3cea6900 	ldr	q0, [x8, x10]
     73c:	1101012a 	add	w10, w9, #0x40
     740:	927c6d4a 	and	x10, x10, #0xfffffff0
     744:	3d804680 	str	q0, [x20, #272]
     748:	3cea6900 	ldr	q0, [x8, x10]
     74c:	1101412a 	add	w10, w9, #0x50
     750:	91018129 	add	x9, x9, #0x60
     754:	927c6d4a 	and	x10, x10, #0xfffffff0
     758:	3d804e80 	str	q0, [x20, #304]
     75c:	3cea6900 	ldr	q0, [x8, x10]
     760:	f900ea89 	str	x9, [x20, #464]
     764:	3d800300 	str	q0, [x24]
     768:	340003b5 	cbz	w21, 7dc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x7dc>
     76c:	b9400389 	ldr	w9, [x28]
     770:	f94002e1 	ldr	x1, [x23]
     774:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	774: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x1c2
     778:	91000000 	add	x0, x0, #0x0	778: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x1c2
     77c:	8b090109 	add	x9, x8, x9
     780:	8b214108 	add	x8, x8, w1, uxtw
     784:	2d400520 	ldp	s0, s1, [x9]
     788:	bd400922 	ldr	s2, [x9, #8]
     78c:	2d441123 	ldp	s3, s4, [x9, #32]
     790:	bd401911 	ldr	s17, [x8, #24]
     794:	2d451925 	ldp	s5, s6, [x9, #40]
     798:	1e22c042 	fcvt	d2, s2
     79c:	2d424107 	ldp	s7, s16, [x8, #16]
     7a0:	1e22c000 	fcvt	d0, s0
     7a4:	1e22c021 	fcvt	d1, s1
     7a8:	1e22c063 	fcvt	d3, s3
     7ac:	1e22c084 	fcvt	d4, s4
     7b0:	1e22c0a5 	fcvt	d5, s5
     7b4:	1e22c0c6 	fcvt	d6, s6
     7b8:	1e22c231 	fcvt	d17, s17
     7bc:	1e22c0e7 	fcvt	d7, s7
     7c0:	1e22c210 	fcvt	d16, s16
     7c4:	6d0047f0 	stp	d16, d17, [sp]
     7c8:	94000000 	bl	0 <printf>	7c8: R_AARCH64_CALL26	printf
     7cc:	90000008 	adrp	x8, 0 <stdout>	7cc: R_AARCH64_ADR_GOT_PAGE	stdout
     7d0:	f9400108 	ldr	x8, [x8]	7d0: R_AARCH64_LD64_GOT_LO12_NC	stdout
     7d4:	f9400100 	ldr	x0, [x8]
     7d8:	94000000 	bl	0 <fflush>	7d8: R_AARCH64_CALL26	fflush
     7dc:	b9400388 	ldr	w8, [x28]
     7e0:	37000833 	tbnz	w19, #0, 8e4 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x8e4>
     7e4:	f9400369 	ldr	x9, [x27]
     7e8:	b941528b 	ldr	w11, [x20, #336]
     7ec:	bd431a81 	ldr	s1, [x20, #792]
     7f0:	8b08012a 	add	x10, x9, x8
     7f4:	8b0b0129 	add	x9, x9, x11
     7f8:	f940094c 	ldr	x12, [x10, #16]
     7fc:	3dc00142 	ldr	q2, [x10]
     800:	f81903ac 	stur	x12, [x29, #-112]
     804:	bd404120 	ldr	s0, [x9, #64]
     808:	fc444123 	ldur	d3, [x9, #68]
     80c:	fc414124 	ldur	d4, [x9, #20]
     810:	b940612b 	ldr	w11, [x9, #96]
     814:	1e200820 	fmul	s0, s1, s0
     818:	0f819061 	fmul	v1.2s, v3.2s, v1.s[0]
     81c:	bd401123 	ldr	s3, [x9, #16]
     820:	1e232800 	fadd	s0, s0, s3
     824:	0e24d421 	fadd	v1.2s, v1.2s, v4.2s
     828:	3400010b 	cbz	w11, 848 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x848>
     82c:	1e270163 	fmov	s3, w11
     830:	bd431e84 	ldr	s4, [x20, #796]
     834:	1e233903 	fsub	s3, s8, s3
     838:	1e230883 	fmul	s3, s4, s3
     83c:	1e233903 	fsub	s3, s8, s3
     840:	1e230800 	fmul	s0, s0, s3
     844:	0f839021 	fmul	v1.2s, v1.2s, v3.s[0]
     848:	6e002003 	ext	v3.16b, v0.16b, v0.16b, #4
     84c:	bd401d24 	ldr	s4, [x9, #28]
     850:	bd431685 	ldr	s5, [x20, #788]
     854:	3dc00d26 	ldr	q6, [x9, #48]
     858:	fd401531 	ldr	d17, [x9, #40]
     85c:	fd400d47 	ldr	d7, [x10, #24]
     860:	4e0404b0 	dup	v16.4s, v5.s[0]
     864:	6e016063 	ext	v3.16b, v3.16b, v1.16b, #12
     868:	2e31de10 	fmul	v16.2s, v16.2s, v17.2s
     86c:	6e1c0483 	mov	v3.s[3], v4.s[0]
     870:	4f859063 	fmul	v3.4s, v3.4s, v5.s[0]
     874:	4f8590c5 	fmul	v5.4s, v6.4s, v5.s[0]
     878:	3dc00946 	ldr	q6, [x10, #32]
     87c:	bd001120 	str	s0, [x9, #16]
     880:	fc014121 	stur	d1, [x9, #20]
     884:	bd001d24 	str	s4, [x9, #28]
     888:	4e23d442 	fadd	v2.4s, v2.4s, v3.4s
     88c:	4e25d4c3 	fadd	v3.4s, v6.4s, v5.4s
     890:	f9400369 	ldr	x9, [x27]
     894:	0e30d4e5 	fadd	v5.2s, v7.2s, v16.2s
     898:	3ca86922 	str	q2, [x9, x8]
     89c:	f9400369 	ldr	x9, [x27]
     8a0:	4ea0e866 	fcmlt	v6.4s, v3.4s, #0.0
     8a4:	f85903aa 	ldur	x10, [x29, #-112]
     8a8:	8b080129 	add	x9, x9, x8
     8ac:	f900092a 	str	x10, [x9, #16]
     8b0:	fd000d25 	str	d5, [x9, #24]
     8b4:	4e661c63 	bic	v3.16b, v3.16b, v6.16b
     8b8:	f9400369 	ldr	x9, [x27]
     8bc:	8b080128 	add	x8, x9, x8
     8c0:	3d800903 	str	q3, [x8, #32]
     8c4:	3d80a682 	str	q2, [x20, #656]
     8c8:	f901528a 	str	x10, [x20, #672]
     8cc:	fd015685 	str	d5, [x20, #680]
     8d0:	3d80ae83 	str	q3, [x20, #688]
     8d4:	bd02c280 	str	s0, [x20, #704]
     8d8:	fd001b21 	str	d1, [x25, #48]
     8dc:	bd02ce84 	str	s4, [x20, #716]
     8e0:	14000092 	b	b28 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xb28>
     8e4:	f2400d1f 	tst	x8, #0xf
     8e8:	54004ba1 	b.ne	125c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x125c>  // b.any
     8ec:	f9400369 	ldr	x9, [x27]
     8f0:	927c6d08 	and	x8, x8, #0xfffffff0
     8f4:	8b08012a 	add	x10, x9, x8
     8f8:	f94002e8 	ldr	x8, [x23]
     8fc:	3dc00140 	ldr	q0, [x10]
     900:	f2400d1f 	tst	x8, #0xf
     904:	3d80a680 	str	q0, [x20, #656]
     908:	3dc00540 	ldr	q0, [x10, #16]
     90c:	3d80aa80 	str	q0, [x20, #672]
     910:	3dc00940 	ldr	q0, [x10, #32]
     914:	3d80ae80 	str	q0, [x20, #688]
     918:	54004a21 	b.ne	125c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x125c>  // b.any
     91c:	927c6d08 	and	x8, x8, #0xfffffff0
     920:	8b080128 	add	x8, x9, x8
     924:	3dc00500 	ldr	q0, [x8, #16]
     928:	3d80b280 	str	q0, [x20, #704]
     92c:	3dc00900 	ldr	q0, [x8, #32]
     930:	bd42c284 	ldr	s4, [x20, #704]
     934:	3d80b680 	str	q0, [x20, #720]
     938:	3dc00d00 	ldr	q0, [x8, #48]
     93c:	3d80ba80 	str	q0, [x20, #736]
     940:	3dc01100 	ldr	q0, [x8, #64]
     944:	3d80be80 	str	q0, [x20, #752]
     948:	bd431a80 	ldr	s0, [x20, #792]
     94c:	bd42f281 	ldr	s1, [x20, #752]
     950:	fd403322 	ldr	d2, [x25, #96]
     954:	bd42fe83 	ldr	s3, [x20, #764]
     958:	b9806109 	ldrsw	x9, [x8, #96]
     95c:	1e200821 	fmul	s1, s1, s0
     960:	0f809042 	fmul	v2.2s, v2.2s, v0.s[0]
     964:	1e200863 	fmul	s3, s3, s0
     968:	fd401b20 	ldr	d0, [x25, #48]
     96c:	b9020289 	str	w9, [x20, #512]
     970:	f9001a89 	str	x9, [x20, #48]
     974:	bd02f281 	str	s1, [x20, #752]
     978:	1e242821 	fadd	s1, s1, s4
     97c:	0e20d440 	fadd	v0.2s, v2.2s, v0.2s
     980:	fd003322 	str	d2, [x25, #96]
     984:	bd431e82 	ldr	s2, [x20, #796]
     988:	bd02fe83 	str	s3, [x20, #764]
     98c:	bd02c281 	str	s1, [x20, #704]
     990:	fd001b20 	str	d0, [x25, #48]
     994:	34000249 	cbz	w9, 9dc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9dc>
     998:	1e270123 	fmov	s3, w9
     99c:	f9401e8a 	ldr	x10, [x20, #56]
     9a0:	9e670124 	fmov	d4, x9
     9a4:	f901868a 	str	x10, [x20, #776]
     9a8:	1e233903 	fsub	s3, s8, s3
     9ac:	bd430a85 	ldr	s5, [x20, #776]
     9b0:	0f829084 	fmul	v4.2s, v4.2s, v2.s[0]
     9b4:	1e230843 	fmul	s3, s2, s3
     9b8:	1e250842 	fmul	s2, s2, s5
     9bc:	fd018284 	str	d4, [x20, #768]
     9c0:	1e233903 	fsub	s3, s8, s3
     9c4:	bd030a82 	str	s2, [x20, #776]
     9c8:	1e230821 	fmul	s1, s1, s3
     9cc:	0f839000 	fmul	v0.2s, v0.2s, v3.s[0]
     9d0:	bd030e83 	str	s3, [x20, #780]
     9d4:	bd02c281 	str	s1, [x20, #704]
     9d8:	fd001b20 	str	d0, [x25, #48]
     9dc:	bd431682 	ldr	s2, [x20, #788]
     9e0:	910bb289 	add	x9, x20, #0x2ec
     9e4:	fd417284 	ldr	d4, [x20, #736]
     9e8:	bd42d285 	ldr	s5, [x20, #720]
     9ec:	bd42d686 	ldr	s6, [x20, #724]
     9f0:	1e26000a 	fmov	w10, s0
     9f4:	4ea21c43 	mov	v3.16b, v2.16b
     9f8:	bd42da90 	ldr	s16, [x20, #728]
     9fc:	0f829012 	fmul	v18.2s, v0.2s, v2.s[0]
     a00:	1e250845 	fmul	s5, s2, s5
     a04:	1e260846 	fmul	s6, s2, s6
     a08:	bd42ce87 	ldr	s7, [x20, #716]
     a0c:	1e220831 	fmul	s17, s1, s2
     a10:	1e300850 	fmul	s16, s2, s16
     a14:	f941668b 	ldr	x11, [x20, #712]
     a18:	0d409123 	ld1	{v3.s}[1], [x9]
     a1c:	910ba289 	add	x9, x20, #0x2e8
     a20:	1e2208e7 	fmul	s7, s7, s2
     a24:	4d408124 	ld1	{v4.s}[2], [x9]
     a28:	fd004b32 	str	d18, [x25, #144]
     a2c:	1e260029 	fmov	w9, s1
     a30:	bd033285 	str	s5, [x20, #816]
     a34:	3dc0ae85 	ldr	q5, [x20, #688]
     a38:	4e833863 	zip1	v3.4s, v3.4s, v3.4s
     a3c:	bd033686 	str	s6, [x20, #820]
     a40:	fd400326 	ldr	d6, [x25]
     a44:	6e1c0444 	mov	v4.s[3], v2.s[0]
     a48:	bd032291 	str	s17, [x20, #800]
     a4c:	aa0a8129 	orr	x9, x9, x10, lsl #32
     a50:	0e26d646 	fadd	v6.2s, v18.2s, v6.2s
     a54:	bd42aa92 	ldr	s18, [x20, #680]
     a58:	bd033a90 	str	s16, [x20, #824]
     a5c:	bd032e87 	str	s7, [x20, #812]
     a60:	6e140443 	mov	v3.s[2], v2.s[0]
     a64:	1e322a10 	fadd	s16, s16, s18
     a68:	fd000326 	str	d6, [x25]
     a6c:	6e23dc83 	fmul	v3.4s, v4.4s, v3.4s
     a70:	bd42de84 	ldr	s4, [x20, #732]
     a74:	bd02aa90 	str	s16, [x20, #680]
     a78:	1e240842 	fmul	s2, s2, s4
     a7c:	bd429284 	ldr	s4, [x20, #656]
     a80:	4e25d465 	fadd	v5.4s, v3.4s, v5.4s
     a84:	1e242a24 	fadd	s4, s17, s4
     a88:	bd429e91 	ldr	s17, [x20, #668]
     a8c:	3d80d283 	str	q3, [x20, #832]
     a90:	1e3128e7 	fadd	s7, s7, s17
     a94:	bd42ae91 	ldr	s17, [x20, #684]
     a98:	bd033e82 	str	s2, [x20, #828]
     a9c:	4ea0e8b2 	fcmlt	v18.4s, v5.4s, #0.0
     aa0:	1e312842 	fadd	s2, s2, s17
     aa4:	bd029284 	str	s4, [x20, #656]
     aa8:	bd029e87 	str	s7, [x20, #668]
     aac:	4e721ca1 	bic	v1.16b, v5.16b, v18.16b
     ab0:	bd02ae82 	str	s2, [x20, #684]
     ab4:	3d80ae81 	str	q1, [x20, #688]
     ab8:	a9012d09 	stp	x9, x11, [x8, #16]
     abc:	f940a288 	ldr	x8, [x20, #320]
     ac0:	f2400d1f 	tst	x8, #0xf
     ac4:	54003b41 	b.ne	122c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x122c>  // b.any
     ac8:	f9400369 	ldr	x9, [x27]
     acc:	f9414a8a 	ldr	x10, [x20, #656]
     ad0:	927c6d08 	and	x8, x8, #0xfffffff0
     ad4:	f9414e8b 	ldr	x11, [x20, #664]
     ad8:	8b080128 	add	x8, x9, x8
     adc:	a9002d0a 	stp	x10, x11, [x8]
     ae0:	f940a288 	ldr	x8, [x20, #320]
     ae4:	f2400d1f 	tst	x8, #0xf
     ae8:	54003a21 	b.ne	122c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x122c>  // b.any
     aec:	f9400369 	ldr	x9, [x27]
     af0:	f941528a 	ldr	x10, [x20, #672]
     af4:	927c6d08 	and	x8, x8, #0xfffffff0
     af8:	f941568b 	ldr	x11, [x20, #680]
     afc:	8b080128 	add	x8, x9, x8
     b00:	a9012d0a 	stp	x10, x11, [x8, #16]
     b04:	f940a288 	ldr	x8, [x20, #320]
     b08:	f2400d1f 	tst	x8, #0xf
     b0c:	54003901 	b.ne	122c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x122c>  // b.any
     b10:	f9400369 	ldr	x9, [x27]
     b14:	f9415a8a 	ldr	x10, [x20, #688]
     b18:	927c6d08 	and	x8, x8, #0xfffffff0
     b1c:	f9415e8b 	ldr	x11, [x20, #696]
     b20:	8b080128 	add	x8, x9, x8
     b24:	a9022d0a 	stp	x10, x11, [x8, #32]
     b28:	94000000 	bl	0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	b28: R_AARCH64_CALL26	.text._ZN6Mips2C4jak1L21geco_spart_dump_armedEv
     b2c:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	b2c: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals+0x8
     b30:	b9400109 	ldr	w9, [x8]	b30: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals+0x8
     b34:	5283e808 	mov	w8, #0x1f40                	// #8000
     b38:	6b08013f 	cmp	w9, w8
     b3c:	1a9fa7e8 	cset	w8, lt	// lt = tstop
     b40:	0a080008 	and	w8, w0, w8
     b44:	7100051f 	cmp	w8, #0x1
     b48:	540007c1 	b.ne	c40 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc40>  // b.any
     b4c:	f940036a 	ldr	x10, [x27]
     b50:	b9400388 	ldr	w8, [x28]
     b54:	52a8690b 	mov	w11, #0x43480000            	// #1128792064
     b58:	f94002e1 	ldr	x1, [x23]
     b5c:	1e270162 	fmov	s2, w11
     b60:	8b080148 	add	x8, x10, x8
     b64:	2d440500 	ldp	s0, s1, [x8, #32]
     b68:	8b21414a 	add	x10, x10, w1, uxtw
     b6c:	2d461544 	ldp	s4, s5, [x10, #48]
     b70:	1e222000 	fcmp	s0, s2
     b74:	2d450d02 	ldp	s2, s3, [x8, #40]
     b78:	2d471d46 	ldp	s6, s7, [x10, #56]
     b7c:	540004cd 	b.le	c14 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc14>
     b80:	52a8690a 	mov	w10, #0x43480000            	// #1128792064
     b84:	1e270150 	fmov	s16, w10
     b88:	1e302020 	fcmp	s1, s16
     b8c:	5400044d 	b.le	c14 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc14>
     b90:	1e202048 	fcmp	s2, #0.0
     b94:	54000401 	b.ne	c14 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc14>  // b.any
     b98:	11000529 	add	w9, w9, #0x1
     b9c:	9000000a 	adrp	x10, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	b9c: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals+0x8
     ba0:	1e22c000 	fcvt	d0, s0
     ba4:	b9000149 	str	w9, [x10]	ba4: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals+0x8
     ba8:	1e22c021 	fcvt	d1, s1
     bac:	1e22c042 	fcvt	d2, s2
     bb0:	2d404510 	ldp	s16, s17, [x8]
     bb4:	bd400912 	ldr	s18, [x8, #8]
     bb8:	bd401113 	ldr	s19, [x8, #16]
     bbc:	bd401d14 	ldr	s20, [x8, #28]
     bc0:	1e22c063 	fcvt	d3, s3
     bc4:	1e22c084 	fcvt	d4, s4
     bc8:	1e22c0a5 	fcvt	d5, s5
     bcc:	1e22c0c6 	fcvt	d6, s6
     bd0:	1e22c0e7 	fcvt	d7, s7
     bd4:	1e22c210 	fcvt	d16, s16
     bd8:	1e22c231 	fcvt	d17, s17
     bdc:	1e22c252 	fcvt	d18, s18
     be0:	1e22c273 	fcvt	d19, s19
     be4:	1e22c294 	fcvt	d20, s20
     be8:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	be8: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x210
     bec:	91000000 	add	x0, x0, #0x0	bec: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x210
     bf0:	fd0003f0 	str	d16, [sp]
     bf4:	6d01d3f3 	stp	d19, d20, [sp, #24]
     bf8:	6d00cbf1 	stp	d17, d18, [sp, #8]
     bfc:	94000000 	bl	0 <printf>	bfc: R_AARCH64_CALL26	printf
     c00:	90000008 	adrp	x8, 0 <stdout>	c00: R_AARCH64_ADR_GOT_PAGE	stdout
     c04:	f9400108 	ldr	x8, [x8]	c04: R_AARCH64_LD64_GOT_LO12_NC	stdout
     c08:	f9400100 	ldr	x0, [x8]
     c0c:	94000000 	bl	0 <fflush>	c0c: R_AARCH64_CALL26	fflush
     c10:	1400000c 	b	c40 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc40>
     c14:	52a8590a 	mov	w10, #0x42c80000            	// #1120403456
     c18:	1e270150 	fmov	s16, w10
     c1c:	52a8604a 	mov	w10, #0x43020000            	// #1124204544
     c20:	1e302020 	fcmp	s1, s16
     c24:	1e270150 	fmov	s16, w10
     c28:	1e29a440 	fccmp	s2, s9, #0x0, ge	// ge = tcont
     c2c:	1e300402 	fccmp	s0, s16, #0x2, eq	// eq = none
     c30:	1a9f87ea 	cset	w10, ls	// ls = plast
     c34:	3707fb2a 	tbnz	w10, #0, b98 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xb98>
     c38:	1e2a2080 	fcmp	s4, s10
     c3c:	54fffae4 	b.mi	b98 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xb98>  // b.first
     c40:	37000153 	tbnz	w19, #0, c68 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc68>
     c44:	b9400388 	ldr	w8, [x28]
     c48:	f9400369 	ldr	x9, [x27]
     c4c:	11006108 	add	w8, w8, #0x18
     c50:	bc686920 	ldr	s0, [x9, x8]
     c54:	1e38000a 	fcvtzs	w10, s0
     c58:	13003d4a 	sxth	w10, w10
     c5c:	1e220140 	scvtf	s0, w10
     c60:	bc286920 	str	s0, [x9, x8]
     c64:	1400000b 	b	c90 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc90>
     c68:	f9400368 	ldr	x8, [x27]
     c6c:	b9414289 	ldr	w9, [x20, #320]
     c70:	8b090108 	add	x8, x8, x9
     c74:	bd401900 	ldr	s0, [x8, #24]
     c78:	1e380009 	fcvtzs	w9, s0
     c7c:	93403d29 	sxth	x9, w9
     c80:	1e220120 	scvtf	s0, w9
     c84:	f9001a89 	str	x9, [x20, #48]
     c88:	bd020280 	str	s0, [x20, #512]
     c8c:	bd001900 	str	s0, [x8, #24]
     c90:	f9400365 	ldr	x5, [x27]
     c94:	b9415288 	ldr	w8, [x20, #336]
     c98:	90000009 	adrp	x9, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	c98: R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_2d::cache
     c9c:	8b0800a8 	add	x8, x5, x8
     ca0:	b9406908 	ldr	w8, [x8, #104]
     ca4:	f9400129 	ldr	x9, [x9]	ca4: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_2d::cache
     ca8:	92790108 	and	x8, x8, #0x80
     cac:	f9400929 	ldr	x9, [x9, #16]
     cb0:	f9001a88 	str	x8, [x20, #48]
     cb4:	b9800129 	ldrsw	x9, [x9]
     cb8:	f900ca89 	str	x9, [x20, #400]
     cbc:	34001988 	cbz	w8, fec <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xfec>
     cc0:	94000000 	bl	0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	cc0: R_AARCH64_CALL26	.text._ZN6Mips2C4jak1L21geco_spart_dump_armedEv
     cc4:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	cc4: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals+0xc
     cc8:	b9400109 	ldr	w9, [x8]	cc8: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals+0xc
     ccc:	5290d408 	mov	w8, #0x86a0                	// #34464
     cd0:	72a00028 	movk	w8, #0x1, lsl #16
     cd4:	6b08013f 	cmp	w9, w8
     cd8:	1a9fa7e8 	cset	w8, lt	// lt = tstop
     cdc:	0a080015 	and	w21, w0, w8
     ce0:	710006bf 	cmp	w21, #0x1
     ce4:	54000941 	b.ne	e0c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xe0c>  // b.any
     ce8:	f9400368 	ldr	x8, [x27]
     cec:	f94002e1 	ldr	x1, [x23]
     cf0:	1100052a 	add	w10, w9, #0x1
     cf4:	9000000b 	adrp	x11, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	cf4: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals+0xc
     cf8:	2f00e405 	movi	d5, #0x0
     cfc:	2f00e410 	movi	d16, #0x0
     d00:	8b214109 	add	x9, x8, w1, uxtw
     d04:	b900016a 	str	w10, [x11]	d04: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals+0xc
     d08:	2f00e411 	movi	d17, #0x0
     d0c:	2f00e412 	movi	d18, #0x0
     d10:	529ffc6b 	mov	w11, #0xffe3                	// #65507
     d14:	b9406d22 	ldr	w2, [x9, #108]
     d18:	72a0ffeb 	movk	w11, #0x7ff, lsl #16
     d1c:	5100444a 	sub	w10, w2, #0x11
     d20:	6b0b015f 	cmp	w10, w11
     d24:	54000082 	b.cs	d34 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xd34>  // b.hs, b.nlast
     d28:	8b02010a 	add	x10, x8, x2
     d2c:	2d404552 	ldp	s18, s17, [x10]
     d30:	bd400950 	ldr	s16, [x10, #8]
     d34:	9000000a 	adrp	x10, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	d34: R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_2d::cache
     d38:	1100116b 	add	w11, w11, #0x4
     d3c:	f940014a 	ldr	x10, [x10]	d3c: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_2d::cache
     d40:	2d410121 	ldp	s1, s0, [x9, #8]
     d44:	2d420d22 	ldp	s2, s3, [x9, #16]
     d48:	bd401924 	ldr	s4, [x9, #24]
     d4c:	f940014a 	ldr	x10, [x10]
     d50:	2d4a1d26 	ldp	s6, s7, [x9, #80]
     d54:	2d4b6d3a 	ldp	s26, s27, [x9, #88]
     d58:	b940014a 	ldr	w10, [x10]
     d5c:	5100454c 	sub	w12, w10, #0x11
     d60:	6b0b019f 	cmp	w12, w11
     d64:	b940038b 	ldr	w11, [x28]
     d68:	8b0b010b 	add	x11, x8, x11
     d6c:	2d405173 	ldp	s19, s20, [x11]
     d70:	bd400975 	ldr	s21, [x11, #8]
     d74:	2d445d76 	ldp	s22, s23, [x11, #32]
     d78:	2d456578 	ldp	s24, s25, [x11, #40]
     d7c:	54000062 	b.cs	d88 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xd88>  // b.hs, b.nlast
     d80:	8b0a0108 	add	x8, x8, x10
     d84:	bd400505 	ldr	s5, [x8, #4]
     d88:	1e22c000 	fcvt	d0, s0
     d8c:	1e22c021 	fcvt	d1, s1
     d90:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	d90: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x274
     d94:	91000000 	add	x0, x0, #0x0	d94: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x274
     d98:	1e22c042 	fcvt	d2, s2
     d9c:	1e22c063 	fcvt	d3, s3
     da0:	1e22c084 	fcvt	d4, s4
     da4:	1e22c0a5 	fcvt	d5, s5
     da8:	1e22c0c6 	fcvt	d6, s6
     dac:	1e22c0e7 	fcvt	d7, s7
     db0:	1e22c35a 	fcvt	d26, s26
     db4:	1e22c37b 	fcvt	d27, s27
     db8:	1e22c252 	fcvt	d18, s18
     dbc:	1e22c231 	fcvt	d17, s17
     dc0:	1e22c210 	fcvt	d16, s16
     dc4:	1e22c273 	fcvt	d19, s19
     dc8:	1e22c294 	fcvt	d20, s20
     dcc:	1e22c2b5 	fcvt	d21, s21
     dd0:	1e22c2d6 	fcvt	d22, s22
     dd4:	1e22c2f7 	fcvt	d23, s23
     dd8:	1e22c318 	fcvt	d24, s24
     ddc:	6d006ffa 	stp	d26, d27, [sp]
     de0:	1e22c339 	fcvt	d25, s25
     de4:	6d0147f2 	stp	d18, d17, [sp, #16]
     de8:	6d0357f4 	stp	d20, d21, [sp, #48]
     dec:	6d045ff6 	stp	d22, d23, [sp, #64]
     df0:	6d0567f8 	stp	d24, d25, [sp, #80]
     df4:	6d024ff0 	stp	d16, d19, [sp, #32]
     df8:	94000000 	bl	0 <printf>	df8: R_AARCH64_CALL26	printf
     dfc:	90000008 	adrp	x8, 0 <stdout>	dfc: R_AARCH64_ADR_GOT_PAGE	stdout
     e00:	f9400108 	ldr	x8, [x8]	e00: R_AARCH64_LD64_GOT_LO12_NC	stdout
     e04:	f9400100 	ldr	x0, [x8]
     e08:	94000000 	bl	0 <fflush>	e08: R_AARCH64_CALL26	fflush
     e0c:	f940ea88 	ldr	x8, [x20, #464]
     e10:	f9400369 	ldr	x9, [x27]
     e14:	3dc07280 	ldr	q0, [x20, #448]
     e18:	d1018108 	sub	x8, x8, #0x60
     e1c:	f900ea88 	str	x8, [x20, #464]
     e20:	927c6d08 	and	x8, x8, #0xfffffff0
     e24:	3ca86920 	str	q0, [x9, x8]
     e28:	b941d288 	ldr	w8, [x20, #464]
     e2c:	f9400369 	ldr	x9, [x27]
     e30:	3dc05680 	ldr	q0, [x20, #336]
     e34:	11004108 	add	w8, w8, #0x10
     e38:	927c6d08 	and	x8, x8, #0xfffffff0
     e3c:	3ca86920 	str	q0, [x9, x8]
     e40:	b941d288 	ldr	w8, [x20, #464]
     e44:	f9400369 	ldr	x9, [x27]
     e48:	3dc05280 	ldr	q0, [x20, #320]
     e4c:	11008108 	add	w8, w8, #0x20
     e50:	927c6d08 	and	x8, x8, #0xfffffff0
     e54:	3ca86920 	str	q0, [x9, x8]
     e58:	b941d288 	ldr	w8, [x20, #464]
     e5c:	f9400369 	ldr	x9, [x27]
     e60:	3dc04680 	ldr	q0, [x20, #272]
     e64:	1100c108 	add	w8, w8, #0x30
     e68:	927c6d08 	and	x8, x8, #0xfffffff0
     e6c:	3ca86920 	str	q0, [x9, x8]
     e70:	b941d288 	ldr	w8, [x20, #464]
     e74:	f9400369 	ldr	x9, [x27]
     e78:	3dc04e80 	ldr	q0, [x20, #304]
     e7c:	11010108 	add	w8, w8, #0x40
     e80:	927c6d08 	and	x8, x8, #0xfffffff0
     e84:	3ca86920 	str	q0, [x9, x8]
     e88:	f940e288 	ldr	x8, [x20, #448]
     e8c:	b941d28a 	ldr	w10, [x20, #464]
     e90:	f940aa89 	ldr	x9, [x20, #336]
     e94:	f940a28b 	ldr	x11, [x20, #320]
     e98:	f940036c 	ldr	x12, [x27]
     e9c:	3dc04a80 	ldr	q0, [x20, #288]
     ea0:	f9002288 	str	x8, [x20, #64]
     ea4:	11014148 	add	w8, w10, #0x50
     ea8:	f9002a89 	str	x9, [x20, #80]
     eac:	927c6d09 	and	x9, x8, #0xfffffff0
     eb0:	b9419288 	ldr	w8, [x20, #400]
     eb4:	f900328b 	str	x11, [x20, #96]
     eb8:	3ca96980 	str	q0, [x12, x9]
     ebc:	f9402289 	ldr	x9, [x20, #64]
     ec0:	f9402a8a 	ldr	x10, [x20, #80]
     ec4:	f940328b 	ldr	x11, [x20, #96]
     ec8:	a9392ba9 	stp	x9, x10, [x29, #-112]
     ecc:	f9403a89 	ldr	x9, [x20, #112]
     ed0:	f940428a 	ldr	x10, [x20, #128]
     ed4:	a93a27ab 	stp	x11, x9, [x29, #-96]
     ed8:	f9404a8b 	ldr	x11, [x20, #144]
     edc:	f9405289 	ldr	x9, [x20, #160]
     ee0:	a93b2faa 	stp	x10, x11, [x29, #-80]
     ee4:	f9405a8a 	ldr	x10, [x20, #176]
     ee8:	a93c2ba9 	stp	x9, x10, [x29, #-64]
     eec:	34001928 	cbz	w8, 1210 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1210>
     ef0:	f9400365 	ldr	x5, [x27]
     ef4:	f940b283 	ldr	x3, [x20, #352]
     ef8:	f940ba84 	ldr	x4, [x20, #368]
     efc:	8b0800a0 	add	x0, x5, x8
     f00:	d101c3a1 	sub	x1, x29, #0x70
     f04:	aa1f03e2 	mov	x2, xzr
     f08:	94000000 	bl	0 <_call_goal8_asm_systemv>	f08: R_AARCH64_CALL26	_call_goal8_asm_systemv
     f0c:	f940ea88 	ldr	x8, [x20, #464]
     f10:	f9400365 	ldr	x5, [x27]
     f14:	f9001280 	str	x0, [x20, #32]
     f18:	927c6d09 	and	x9, x8, #0xfffffff0
     f1c:	3ce968a0 	ldr	q0, [x5, x9]
     f20:	11004109 	add	w9, w8, #0x10
     f24:	927c6d29 	and	x9, x9, #0xfffffff0
     f28:	3d807280 	str	q0, [x20, #448]
     f2c:	3ce968a0 	ldr	q0, [x5, x9]
     f30:	11008109 	add	w9, w8, #0x20
     f34:	927c6d29 	and	x9, x9, #0xfffffff0
     f38:	3d8002e0 	str	q0, [x23]
     f3c:	3ce968a0 	ldr	q0, [x5, x9]
     f40:	1100c109 	add	w9, w8, #0x30
     f44:	927c6d29 	and	x9, x9, #0xfffffff0
     f48:	3d800380 	str	q0, [x28]
     f4c:	3ce968a0 	ldr	q0, [x5, x9]
     f50:	11010109 	add	w9, w8, #0x40
     f54:	927c6d29 	and	x9, x9, #0xfffffff0
     f58:	3d804680 	str	q0, [x20, #272]
     f5c:	3ce968a0 	ldr	q0, [x5, x9]
     f60:	11014109 	add	w9, w8, #0x50
     f64:	91018108 	add	x8, x8, #0x60
     f68:	927c6d29 	and	x9, x9, #0xfffffff0
     f6c:	3d804e80 	str	q0, [x20, #304]
     f70:	3ce968a0 	ldr	q0, [x5, x9]
     f74:	f900ea88 	str	x8, [x20, #464]
     f78:	3d800300 	str	q0, [x24]
     f7c:	34000395 	cbz	w21, fec <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xfec>
     f80:	f94002e1 	ldr	x1, [x23]
     f84:	b9400388 	ldr	w8, [x28]
     f88:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	f88: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x2f3
     f8c:	91000000 	add	x0, x0, #0x0	f8c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x2f3
     f90:	8b2140a9 	add	x9, x5, w1, uxtw
     f94:	8b0800a8 	add	x8, x5, x8
     f98:	2d401d06 	ldp	s6, s7, [x8]
     f9c:	bd400910 	ldr	s16, [x8, #8]
     fa0:	2d410121 	ldp	s1, s0, [x9, #8]
     fa4:	2d4a0d22 	ldp	s2, s3, [x9, #80]
     fa8:	1e22c210 	fcvt	d16, s16
     fac:	2d4b1524 	ldp	s4, s5, [x9, #88]
     fb0:	1e22c0c6 	fcvt	d6, s6
     fb4:	1e22c000 	fcvt	d0, s0
     fb8:	1e22c021 	fcvt	d1, s1
     fbc:	1e22c0e7 	fcvt	d7, s7
     fc0:	1e22c042 	fcvt	d2, s2
     fc4:	1e22c063 	fcvt	d3, s3
     fc8:	1e22c084 	fcvt	d4, s4
     fcc:	1e22c0a5 	fcvt	d5, s5
     fd0:	fd0003f0 	str	d16, [sp]
     fd4:	94000000 	bl	0 <printf>	fd4: R_AARCH64_CALL26	printf
     fd8:	90000008 	adrp	x8, 0 <stdout>	fd8: R_AARCH64_ADR_GOT_PAGE	stdout
     fdc:	f9400108 	ldr	x8, [x8]	fdc: R_AARCH64_LD64_GOT_LO12_NC	stdout
     fe0:	f9400100 	ldr	x0, [x8]
     fe4:	94000000 	bl	0 <fflush>	fe4: R_AARCH64_CALL26	fflush
     fe8:	f9400365 	ldr	x5, [x27]
     fec:	b9414288 	ldr	w8, [x20, #320]
     ff0:	f940aa9a 	ldr	x26, [x20, #336]
     ff4:	11008108 	add	w8, w8, #0x20
     ff8:	927c6d08 	and	x8, x8, #0xfffffff0
     ffc:	3ce868a0 	ldr	q0, [x5, x8]
    1000:	8b3a40a8 	add	x8, x5, w26, uxtw
    1004:	3d8002c0 	str	q0, [x22]
    1008:	b9806908 	ldrsw	x8, [x8, #104]
    100c:	927e0109 	and	x9, x8, #0x4
    1010:	f9002288 	str	x8, [x20, #64]
    1014:	f9002a89 	str	x9, [x20, #80]
    1018:	36080108 	tbz	w8, #1, 1038 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1038>
    101c:	a9432a8b 	ldp	x11, x10, [x20, #48]
    1020:	29182a9f 	stp	wzr, w10, [x20, #192]
    1024:	d360fd4a 	lsr	x10, x10, #32
    1028:	29192a9f 	stp	wzr, w10, [x20, #200]
    102c:	b500006b 	cbnz	x11, 1038 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1038>
    1030:	f940628a 	ldr	x10, [x20, #192]
    1034:	b40003aa 	cbz	x10, 10a8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x10a8>
    1038:	92400108 	and	x8, x8, #0x1
    103c:	f9002288 	str	x8, [x20, #64]
    1040:	b4000109 	cbz	x9, 1060 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1060>
    1044:	f9401e89 	ldr	x9, [x20, #56]
    1048:	d360fd2a 	lsr	x10, x9, #32
    104c:	29197e89 	stp	w9, wzr, [x20, #200]
    1050:	29182a9f 	stp	wzr, w10, [x20, #192]
    1054:	f940628a 	ldr	x10, [x20, #192]
    1058:	f100055f 	cmp	x10, #0x1
    105c:	5400026b 	b.lt	10a8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x10a8>  // b.tstop
    1060:	b4ff8c08 	cbz	x8, 1e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1e0>
    1064:	f9414a88 	ldr	x8, [x20, #656]
    1068:	f9414e89 	ldr	x9, [x20, #664]
    106c:	f941528a 	ldr	x10, [x20, #672]
    1070:	a9032688 	stp	x8, x9, [x20, #48]
    1074:	d360fd28 	lsr	x8, x9, #32
    1078:	29077e89 	stp	w9, wzr, [x20, #56]
    107c:	2906229f 	stp	wzr, w8, [x20, #48]
    1080:	f9415688 	ldr	x8, [x20, #680]
    1084:	f9401a89 	ldr	x9, [x20, #48]
    1088:	a903228a 	stp	x10, x8, [x20, #48]
    108c:	b7f800e9 	tbnz	x9, #63, 10a8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x10a8>
    1090:	f9401e88 	ldr	x8, [x20, #56]
    1094:	d360fd09 	lsr	x9, x8, #32
    1098:	29077e88 	stp	w8, wzr, [x20, #56]
    109c:	2906269f 	stp	wzr, w9, [x20, #48]
    10a0:	f9401a89 	ldr	x9, [x20, #48]
    10a4:	b6ff89e9 	tbz	x9, #63, 1e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1e0>
    10a8:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	10a8: R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_2d::cache
    10ac:	f9400108 	ldr	x8, [x8]	10ac: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_2d::cache
    10b0:	f940e289 	ldr	x9, [x20, #448]
    10b4:	f9408a8a 	ldr	x10, [x20, #272]
    10b8:	f940a28b 	ldr	x11, [x20, #320]
    10bc:	b981f28c 	ldrsw	x12, [x20, #496]
    10c0:	f9400508 	ldr	x8, [x8, #8]
    10c4:	b9800108 	ldrsw	x8, [x8]
    10c8:	f9002289 	str	x9, [x20, #64]
    10cc:	f9002a8a 	str	x10, [x20, #80]
    10d0:	a9392ba9 	stp	x9, x10, [x29, #-112]
    10d4:	f9404289 	ldr	x9, [x20, #128]
    10d8:	f9404a8a 	ldr	x10, [x20, #144]
    10dc:	f9003a8b 	str	x11, [x20, #112]
    10e0:	a93a2fba 	stp	x26, x11, [x29, #-96]
    10e4:	f940528b 	ldr	x11, [x20, #160]
    10e8:	a93b2ba9 	stp	x9, x10, [x29, #-80]
    10ec:	f9405a89 	ldr	x9, [x20, #176]
    10f0:	f900329a 	str	x26, [x20, #96]
    10f4:	f900ca88 	str	x8, [x20, #400]
    10f8:	f900128c 	str	x12, [x20, #32]
    10fc:	a93c27ab 	stp	x11, x9, [x29, #-64]
    1100:	34000888 	cbz	w8, 1210 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1210>
    1104:	f940b283 	ldr	x3, [x20, #352]
    1108:	f940ba84 	ldr	x4, [x20, #368]
    110c:	92407d08 	and	x8, x8, #0xffffffff
    1110:	8b0800a0 	add	x0, x5, x8
    1114:	d101c3a1 	sub	x1, x29, #0x70
    1118:	aa1f03e2 	mov	x2, xzr
    111c:	94000000 	bl	0 <_call_goal8_asm_systemv>	111c: R_AARCH64_CALL26	_call_goal8_asm_systemv
    1120:	f9001280 	str	x0, [x20, #32]
    1124:	17fffc2f 	b	1e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1e0>
    1128:	f9400368 	ldr	x8, [x27]
    112c:	f940ea89 	ldr	x9, [x20, #464]
    1130:	f9001295 	str	x21, [x20, #32]
    1134:	f869490a 	ldr	x10, [x8, w9, uxtw]
    1138:	1101c12b 	add	w11, w9, #0x70
    113c:	f900fa8a 	str	x10, [x20, #496]
    1140:	927c6d6a 	and	x10, x11, #0xfffffff0
    1144:	3cea6900 	ldr	q0, [x8, x10]
    1148:	1101812a 	add	w10, w9, #0x60
    114c:	927c6d4a 	and	x10, x10, #0xfffffff0
    1150:	3d807280 	str	q0, [x20, #448]
    1154:	3cea6900 	ldr	q0, [x8, x10]
    1158:	1101412a 	add	w10, w9, #0x50
    115c:	927c6d4a 	and	x10, x10, #0xfffffff0
    1160:	3d8002e0 	str	q0, [x23]
    1164:	3cea6900 	ldr	q0, [x8, x10]
    1168:	1101012a 	add	w10, w9, #0x40
    116c:	927c6d4a 	and	x10, x10, #0xfffffff0
    1170:	3d800380 	str	q0, [x28]
    1174:	3cea6900 	ldr	q0, [x8, x10]
    1178:	1100c12a 	add	w10, w9, #0x30
    117c:	927c6d4a 	and	x10, x10, #0xfffffff0
    1180:	3d804e80 	str	q0, [x20, #304]
    1184:	3cea6900 	ldr	q0, [x8, x10]
    1188:	1100812a 	add	w10, w9, #0x20
    118c:	927c6d4a 	and	x10, x10, #0xfffffff0
    1190:	3d800300 	str	q0, [x24]
    1194:	3cea6900 	ldr	q0, [x8, x10]
    1198:	1100412a 	add	w10, w9, #0x10
    119c:	927c6d4a 	and	x10, x10, #0xfffffff0
    11a0:	3d804680 	str	q0, [x20, #272]
    11a4:	3cea6900 	ldr	q0, [x8, x10]
    11a8:	91020128 	add	x8, x9, #0x80
    11ac:	f900ea88 	str	x8, [x20, #464]
    11b0:	3d804280 	str	q0, [x20, #256]
    11b4:	94000000 	bl	0 <std::__ndk1::chrono::steady_clock::now()>	11b4: R_AARCH64_CALL26	std::__ndk1::chrono::steady_clock::now()
    11b8:	f9403be8 	ldr	x8, [sp, #112]
    11bc:	cb080000 	sub	x0, x0, x8
    11c0:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	11c0: R_AARCH64_ADR_GOT_PAGE	g_spart_prof
    11c4:	f9400108 	ldr	x8, [x8]	11c4: R_AARCH64_LD64_GOT_LO12_NC	g_spart_prof
    11c8:	91002101 	add	x1, x8, #0x8
    11cc:	94000000 	bl	0 <__aarch64_ldadd8_relax>	11cc: R_AARCH64_CALL26	__aarch64_ldadd8_relax
    11d0:	f9403fe8 	ldr	x8, [sp, #120]
    11d4:	f9401508 	ldr	x8, [x8, #40]
    11d8:	f85d03a9 	ldur	x9, [x29, #-48]
    11dc:	eb09011f 	cmp	x8, x9
    11e0:	54000981 	b.ne	1310 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1310>  // b.any
    11e4:	aa1503e0 	mov	x0, x21
    11e8:	a9544ff4 	ldp	x20, x19, [sp, #320]
    11ec:	fd406bea 	ldr	d10, [sp, #208]
    11f0:	a95357f6 	ldp	x22, x21, [sp, #304]
    11f4:	a9525ff8 	ldp	x24, x23, [sp, #288]
    11f8:	a95167fa 	ldp	x26, x25, [sp, #272]
    11fc:	a9506ffc 	ldp	x28, x27, [sp, #256]
    1200:	a94f7bfd 	ldp	x29, x30, [sp, #240]
    1204:	6d4e23e9 	ldp	d9, d8, [sp, #224]
    1208:	910543ff 	add	sp, sp, #0x150
    120c:	d65f03c0 	ret
    1210:	52803202 	mov	w2, #0x190                 	// #400
    1214:	f9403fe8 	ldr	x8, [sp, #120]
    1218:	f9401508 	ldr	x8, [x8, #40]
    121c:	f85d03a9 	ldur	x9, [x29, #-48]
    1220:	eb09011f 	cmp	x8, x9
    1224:	54000320 	b.eq	1288 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1288>  // b.none
    1228:	1400003a 	b	1310 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1310>
    122c:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	122c: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x433
    1230:	91000109 	add	x9, x8, #0x0	1230: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x433
    1234:	52803802 	mov	w2, #0x1c0                 	// #448
    1238:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1238: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x45a
    123c:	91000108 	add	x8, x8, #0x0	123c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x45a
    1240:	a90627e8 	stp	x8, x9, [sp, #96]
    1244:	f9403fe8 	ldr	x8, [sp, #120]
    1248:	f9401508 	ldr	x8, [x8, #40]
    124c:	f85d03a9 	ldur	x9, [x29, #-48]
    1250:	eb09011f 	cmp	x8, x9
    1254:	540001a0 	b.eq	1288 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1288>  // b.none
    1258:	1400002e 	b	1310 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1310>
    125c:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	125c: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x36a
    1260:	91000109 	add	x9, x8, #0x0	1260: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x36a
    1264:	52802b02 	mov	w2, #0x158                 	// #344
    1268:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1268: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x3d2
    126c:	91000108 	add	x8, x8, #0x0	126c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x3d2
    1270:	a90627e8 	stp	x8, x9, [sp, #96]
    1274:	f9403fe8 	ldr	x8, [sp, #120]
    1278:	f9401508 	ldr	x8, [x8, #40]
    127c:	f85d03a9 	ldur	x9, [x29, #-48]
    1280:	eb09011f 	cmp	x8, x9
    1284:	54000461 	b.ne	1310 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1310>  // b.any
    1288:	a94603e3 	ldp	x3, x0, [sp, #96]
    128c:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	128c: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x397
    1290:	91000021 	add	x1, x1, #0x0	1290: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x397
    1294:	90000004 	adrp	x4, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1294: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0xc9
    1298:	91000084 	add	x4, x4, #0x0	1298: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0xc9
    129c:	94000000 	bl	0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>	129c: R_AARCH64_CALL26	private_assert_failed(char const*, char const*, int, char const*, char const*)
    12a0:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	12a0: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x3d2
    12a4:	91000109 	add	x9, x8, #0x0	12a4: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x3d2
    12a8:	52802b02 	mov	w2, #0x158                 	// #344
    12ac:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	12ac: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x36a
    12b0:	91000108 	add	x8, x8, #0x0	12b0: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x36a
    12b4:	a90623e9 	stp	x9, x8, [sp, #96]
    12b8:	f9403fe8 	ldr	x8, [sp, #120]
    12bc:	f9401508 	ldr	x8, [x8, #40]
    12c0:	f85d03a9 	ldur	x9, [x29, #-48]
    12c4:	eb09011f 	cmp	x8, x9
    12c8:	54fffe00 	b.eq	1288 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1288>  // b.none
    12cc:	14000011 	b	1310 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1310>
    12d0:	14000001 	b	12d4 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x12d4>
    12d4:	aa0003f4 	mov	x20, x0
    12d8:	94000000 	bl	0 <std::__ndk1::chrono::steady_clock::now()>	12d8: R_AARCH64_CALL26	std::__ndk1::chrono::steady_clock::now()
    12dc:	f9403be8 	ldr	x8, [sp, #112]
    12e0:	cb080000 	sub	x0, x0, x8
    12e4:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	12e4: R_AARCH64_ADR_GOT_PAGE	g_spart_prof
    12e8:	f9400108 	ldr	x8, [x8]	12e8: R_AARCH64_LD64_GOT_LO12_NC	g_spart_prof
    12ec:	91002101 	add	x1, x8, #0x8
    12f0:	94000000 	bl	0 <__aarch64_ldadd8_relax>	12f0: R_AARCH64_CALL26	__aarch64_ldadd8_relax
    12f4:	f9403fe8 	ldr	x8, [sp, #120]
    12f8:	f9401508 	ldr	x8, [x8, #40]
    12fc:	f85d03a9 	ldur	x9, [x29, #-48]
    1300:	eb09011f 	cmp	x8, x9
    1304:	54000061 	b.ne	1310 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1310>  // b.any
    1308:	aa1403e0 	mov	x0, x20
    130c:	94000000 	bl	0 <_Unwind_Resume>	130c: R_AARCH64_CALL26	_Unwind_Resume
    1310:	94000000 	bl	0 <__stack_chk_fail>	1310: R_AARCH64_CALL26	__stack_chk_fail

Disassembly of section .text._ZN6Mips2C4jak1L21geco_spart_dump_armedEv:

0000000000000000 <Mips2C::jak1::geco_spart_dump_armed()>:
   0:	d10283ff 	sub	sp, sp, #0xa0
   4:	a9077bfd 	stp	x29, x30, [sp, #112]
   8:	f90043f5 	str	x21, [sp, #128]
   c:	a9094ff4 	stp	x20, x19, [sp, #144]
  10:	9101c3fd 	add	x29, sp, #0x70
  14:	d53bd053 	mrs	x19, tpidr_el0
  18:	90000014 	adrp	x20, 0 <Mips2C::jak1::geco_spart_dump_armed()>	18: R_AARCH64_ADR_PREL_PG_HI21	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
  1c:	f9401668 	ldr	x8, [x19, #40]
  20:	f81f83a8 	stur	x8, [x29, #-8]
  24:	f9400288 	ldr	x8, [x20]	24: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
  28:	b100091f 	cmn	x8, #0x2
  2c:	540004c1 	b.ne	c4 <Mips2C::jak1::geco_spart_dump_armed()+0xc4>  // b.any
  30:	92800008 	mov	x8, #0xffffffffffffffff    	// #-1
  34:	90000000 	adrp	x0, 0 <Mips2C::jak1::geco_spart_dump_armed()>	34: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x48d
  38:	91000000 	add	x0, x0, #0x0	38: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x48d
  3c:	f9000288 	str	x8, [x20]	3c: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
  40:	94000000 	bl	0 <getenv>	40: R_AARCH64_CALL26	getenv
  44:	6f00e400 	movi	v0.2d, #0x0
  48:	3c84c3e0 	stur	q0, [sp, #76]
  4c:	ad0083e0 	stp	q0, q0, [sp, #16]
  50:	ad0183e0 	stp	q0, q0, [sp, #48]
  54:	3d8003e0 	str	q0, [sp]
  58:	b4000080 	cbz	x0, 68 <Mips2C::jak1::geco_spart_dump_armed()+0x68>
  5c:	39400008 	ldrb	w8, [x0]
  60:	35000188 	cbnz	w8, 90 <Mips2C::jak1::geco_spart_dump_armed()+0x90>
  64:	14000017 	b	c0 <Mips2C::jak1::geco_spart_dump_armed()+0xc0>
  68:	90000000 	adrp	x0, 0 <Mips2C::jak1::geco_spart_dump_armed()>	68: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x49b
  6c:	91000000 	add	x0, x0, #0x0	6c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x49b
  70:	910003e1 	mov	x1, sp
  74:	94000000 	bl	0 <__system_property_get>	74: R_AARCH64_CALL26	__system_property_get
  78:	2a0003e8 	mov	w8, w0
  7c:	910003e0 	mov	x0, sp
  80:	7100051f 	cmp	w8, #0x1
  84:	540001eb 	b.lt	c0 <Mips2C::jak1::geco_spart_dump_armed()+0xc0>  // b.tstop
  88:	394003e8 	ldrb	w8, [sp]
  8c:	340001a8 	cbz	w8, c0 <Mips2C::jak1::geco_spart_dump_armed()+0xc0>
  90:	94000000 	bl	0 <atol>	90: R_AARCH64_CALL26	atol
  94:	f100041f 	cmp	x0, #0x1
  98:	54000061 	b.ne	a4 <Mips2C::jak1::geco_spart_dump_armed()+0xa4>  // b.any
  9c:	aa1f03e8 	mov	x8, xzr
  a0:	14000007 	b	bc <Mips2C::jak1::geco_spart_dump_armed()+0xbc>
  a4:	f100081f 	cmp	x0, #0x2
  a8:	540000cb 	b.lt	c0 <Mips2C::jak1::geco_spart_dump_armed()+0xc0>  // b.tstop
  ac:	aa0003f5 	mov	x21, x0
  b0:	aa1f03e0 	mov	x0, xzr
  b4:	94000000 	bl	0 <time>	b4: R_AARCH64_CALL26	time
  b8:	8b150008 	add	x8, x0, x21
  bc:	f9000288 	str	x8, [x20]	bc: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
  c0:	f9400288 	ldr	x8, [x20]	c0: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
  c4:	f100051f 	cmp	x8, #0x1
  c8:	5400010b 	b.lt	e8 <Mips2C::jak1::geco_spart_dump_armed()+0xe8>  // b.tstop
  cc:	aa1f03e0 	mov	x0, xzr
  d0:	94000000 	bl	0 <time>	d0: R_AARCH64_CALL26	time
  d4:	f9400288 	ldr	x8, [x20]	d4: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
  d8:	eb08001f 	cmp	x0, x8
  dc:	5400006b 	b.lt	e8 <Mips2C::jak1::geco_spart_dump_armed()+0xe8>  // b.tstop
  e0:	aa1f03e8 	mov	x8, xzr
  e4:	f900029f 	str	xzr, [x20]	e4: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
  e8:	f9401669 	ldr	x9, [x19, #40]
  ec:	f85f83aa 	ldur	x10, [x29, #-8]
  f0:	f100011f 	cmp	x8, #0x0
  f4:	1a9f17e0 	cset	w0, eq	// eq = none
  f8:	eb0a013f 	cmp	x9, x10
  fc:	540000c1 	b.ne	114 <Mips2C::jak1::geco_spart_dump_armed()+0x114>  // b.any
 100:	a9494ff4 	ldp	x20, x19, [sp, #144]
 104:	f94043f5 	ldr	x21, [sp, #128]
 108:	a9477bfd 	ldp	x29, x30, [sp, #112]
 10c:	910283ff 	add	sp, sp, #0xa0
 110:	d65f03c0 	ret
 114:	94000000 	bl	0 <__stack_chk_fail>	114: R_AARCH64_CALL26	__stack_chk_fail

Disassembly of section .text._ZN6Mips2C4jak119sp_process_block_2d4linkEv:

0000000000000000 <Mips2C::jak1::sp_process_block_2d::link()>:
   0:	d10143ff 	sub	sp, sp, #0x50
   4:	a9027bfd 	stp	x29, x30, [sp, #32]
   8:	f9001bf5 	str	x21, [sp, #48]
   c:	a9044ff4 	stp	x20, x19, [sp, #64]
  10:	910083fd 	add	x29, sp, #0x20
  14:	d53bd054 	mrs	x20, tpidr_el0
  18:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::link()>	18: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0xf5
  1c:	91000000 	add	x0, x0, #0x0	1c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0xf5
  20:	f9401688 	ldr	x8, [x20, #40]
  24:	f81f83a8 	stur	x8, [x29, #-8]
  28:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	28: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  2c:	90000013 	adrp	x19, 0 <g_ee_main_mem>	2c: R_AARCH64_ADR_GOT_PAGE	g_ee_main_mem
  30:	90000015 	adrp	x21, 0 <Mips2C::jak1::sp_process_block_2d::link()>	30: R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_2d::cache
  34:	7100001f 	cmp	w0, #0x0
  38:	f9400273 	ldr	x19, [x19]	38: R_AARCH64_LD64_GOT_LO12_NC	g_ee_main_mem
  3c:	f9400268 	ldr	x8, [x19]
  40:	f94002b5 	ldr	x21, [x21]	40: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_2d::cache
  44:	8b204108 	add	x8, x8, w0, uxtw
  48:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::link()>	48: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x112
  4c:	91000000 	add	x0, x0, #0x0	4c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x112
  50:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  54:	f90002a8 	str	x8, [x21]
  58:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	58: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  5c:	f9400268 	ldr	x8, [x19]
  60:	7100001f 	cmp	w0, #0x0
  64:	8b204108 	add	x8, x8, w0, uxtw
  68:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::link()>	68: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x333
  6c:	91000000 	add	x0, x0, #0x0	6c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x333
  70:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  74:	f90006a8 	str	x8, [x21, #8]
  78:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	78: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  7c:	f9400268 	ldr	x8, [x19]
  80:	7100001f 	cmp	w0, #0x0
  84:	8b204108 	add	x8, x8, w0, uxtw
  88:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::link()>	88: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x33e
  8c:	91000000 	add	x0, x0, #0x0	8c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x33e
  90:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  94:	f9000aa8 	str	x8, [x21, #16]
  98:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	98: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  9c:	f9400268 	ldr	x8, [x19]
  a0:	9000000b 	adrp	x11, 0 <Mips2C::jak1::sp_process_block_2d::link()>	a0: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x356
  a4:	9100016b 	add	x11, x11, #0x0	a4: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x356
  a8:	5285ad6a 	mov	w10, #0x2d6b                	// #11627
  ac:	3dc00160 	ldr	q0, [x11]
  b0:	7100001f 	cmp	w0, #0x0
  b4:	8b204108 	add	x8, x8, w0, uxtw
  b8:	528004c9 	mov	w9, #0x26                  	// #38
  bc:	72ac864a 	movk	w10, #0x6432, lsl #16
  c0:	390003e9 	strb	w9, [sp]
  c4:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  c8:	b90013ea 	str	w10, [sp, #16]
  cc:	3c8013e0 	stur	q0, [sp, #1]
  d0:	f9000ea8 	str	x8, [x21, #24]
  d4:	390053ff 	strb	wzr, [sp, #20]
  d8:	90000000 	adrp	x0, 0 <Mips2C::gLinkedFunctionTable>	d8: R_AARCH64_ADR_GOT_PAGE	Mips2C::gLinkedFunctionTable
  dc:	90000002 	adrp	x2, 0 <Mips2C::jak1::sp_process_block_2d::link()>	dc: R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_2d::execute(void*)
  e0:	910003e1 	mov	x1, sp
  e4:	f9400000 	ldr	x0, [x0]	e4: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::gLinkedFunctionTable
  e8:	f9400042 	ldr	x2, [x2]	e8: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_2d::execute(void*)
  ec:	52802003 	mov	w3, #0x100                 	// #256
  f0:	94000000 	bl	0 <Mips2C::LinkedFunctionTable::reg(std::__ndk1::basic_string<char, std::__ndk1::char_traits<char>, std::__ndk1::allocator<char> > const&, unsigned long (*)(void*), unsigned int)>	f0: R_AARCH64_CALL26	Mips2C::LinkedFunctionTable::reg(std::__ndk1::basic_string<char, std::__ndk1::char_traits<char>, std::__ndk1::allocator<char> > const&, unsigned long (*)(void*), unsigned int)
  f4:	394003e8 	ldrb	w8, [sp]
  f8:	36000068 	tbz	w8, #0, 104 <Mips2C::jak1::sp_process_block_2d::link()+0x104>
  fc:	f9400be0 	ldr	x0, [sp, #16]
 100:	94000000 	bl	0 <operator delete(void*)>	100: R_AARCH64_CALL26	operator delete(void*)
 104:	f9401688 	ldr	x8, [x20, #40]
 108:	f85f83a9 	ldur	x9, [x29, #-8]
 10c:	eb09011f 	cmp	x8, x9
 110:	54000221 	b.ne	154 <Mips2C::jak1::sp_process_block_2d::link()+0x154>  // b.any
 114:	a9444ff4 	ldp	x20, x19, [sp, #64]
 118:	f9401bf5 	ldr	x21, [sp, #48]
 11c:	a9427bfd 	ldp	x29, x30, [sp, #32]
 120:	910143ff 	add	sp, sp, #0x50
 124:	d65f03c0 	ret
 128:	394003e8 	ldrb	w8, [sp]
 12c:	aa0003f3 	mov	x19, x0
 130:	36000068 	tbz	w8, #0, 13c <Mips2C::jak1::sp_process_block_2d::link()+0x13c>
 134:	f9400be0 	ldr	x0, [sp, #16]
 138:	94000000 	bl	0 <operator delete(void*)>	138: R_AARCH64_CALL26	operator delete(void*)
 13c:	f9401688 	ldr	x8, [x20, #40]
 140:	f85f83a9 	ldur	x9, [x29, #-8]
 144:	eb09011f 	cmp	x8, x9
 148:	54000061 	b.ne	154 <Mips2C::jak1::sp_process_block_2d::link()+0x154>  // b.any
 14c:	aa1303e0 	mov	x0, x19
 150:	94000000 	bl	0 <_Unwind_Resume>	150: R_AARCH64_CALL26	_Unwind_Resume
 154:	94000000 	bl	0 <__stack_chk_fail>	154: R_AARCH64_CALL26	__stack_chk_fail

EXIT 0
