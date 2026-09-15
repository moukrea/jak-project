
.autoport/reports/perf-mips2c-neon/notes/attempt8/tested-block-parity-arm-clang:     file format elf64-littleaarch64


Disassembly of section .text:

0000000000010e40 <_start>:
   10e40:	d503201f 	nop
   10e44:	d280001d 	mov	x29, #0x0                   	// #0
   10e48:	d280001e 	mov	x30, #0x0                   	// #0
   10e4c:	aa0003e5 	mov	x5, x0
   10e50:	f94003e1 	ldr	x1, [sp]
   10e54:	910023e2 	add	x2, sp, #0x8
   10e58:	910003e6 	mov	x6, sp
   10e5c:	d503201f 	nop
   10e60:	10003080 	adr	x0, 11470 <main>
   10e64:	d2800003 	mov	x3, #0x0                   	// #0
   10e68:	d2800004 	mov	x4, #0x0                   	// #0
   10e6c:	94000475 	bl	12040 <__libc_start_main@plt>
   10e70:	94000470 	bl	12030 <abort@plt>

0000000000010e74 <call_weak_fn>:
   10e74:	d0000080 	adrp	x0, 22000 <fprintf@plt+0xff50>
   10e78:	f9415400 	ldr	x0, [x0, #680]
   10e7c:	b4000040 	cbz	x0, 10e84 <call_weak_fn+0x10>
   10e80:	14000474 	b	12050 <__gmon_start__@plt>
   10e84:	d65f03c0 	ret
	...

0000000000010e90 <deregister_tm_clones>:
   10e90:	d503201f 	nop
   10e94:	1010a260 	adr	x0, 322e0 <__TMC_END__>
   10e98:	d503201f 	nop
   10e9c:	1010a221 	adr	x1, 322e0 <__TMC_END__>
   10ea0:	eb00003f 	cmp	x1, x0
   10ea4:	540000c0 	b.eq	10ebc <deregister_tm_clones+0x2c>  // b.none
   10ea8:	d0000081 	adrp	x1, 22000 <fprintf@plt+0xff50>
   10eac:	f9415821 	ldr	x1, [x1, #688]
   10eb0:	b4000061 	cbz	x1, 10ebc <deregister_tm_clones+0x2c>
   10eb4:	aa0103f0 	mov	x16, x1
   10eb8:	d61f0200 	br	x16
   10ebc:	d65f03c0 	ret

0000000000010ec0 <register_tm_clones>:
   10ec0:	d503201f 	nop
   10ec4:	1010a0e0 	adr	x0, 322e0 <__TMC_END__>
   10ec8:	d503201f 	nop
   10ecc:	1010a0a1 	adr	x1, 322e0 <__TMC_END__>
   10ed0:	cb000021 	sub	x1, x1, x0
   10ed4:	d37ffc22 	lsr	x2, x1, #63
   10ed8:	8b810c41 	add	x1, x2, x1, asr #3
   10edc:	9341fc21 	asr	x1, x1, #1
   10ee0:	b40000c1 	cbz	x1, 10ef8 <register_tm_clones+0x38>
   10ee4:	d0000082 	adrp	x2, 22000 <fprintf@plt+0xff50>
   10ee8:	f9415c42 	ldr	x2, [x2, #696]
   10eec:	b4000062 	cbz	x2, 10ef8 <register_tm_clones+0x38>
   10ef0:	aa0203f0 	mov	x16, x2
   10ef4:	d61f0200 	br	x16
   10ef8:	d65f03c0 	ret
   10efc:	d503201f 	nop

0000000000010f00 <__do_global_dtors_aux>:
   10f00:	a9be7bfd 	stp	x29, x30, [sp, #-32]!
   10f04:	910003fd 	mov	x29, sp
   10f08:	f9000bf3 	str	x19, [sp, #16]
   10f0c:	d0000113 	adrp	x19, 32000 <_DYNAMIC+0xff30>
   10f10:	394d0260 	ldrb	w0, [x19, #832]
   10f14:	35000140 	cbnz	w0, 10f3c <__do_global_dtors_aux+0x3c>
   10f18:	d0000080 	adrp	x0, 22000 <fprintf@plt+0xff50>
   10f1c:	f9416000 	ldr	x0, [x0, #704]
   10f20:	b4000080 	cbz	x0, 10f30 <__do_global_dtors_aux+0x30>
   10f24:	d0000100 	adrp	x0, 32000 <_DYNAMIC+0xff30>
   10f28:	f9416c00 	ldr	x0, [x0, #728]
   10f2c:	9400044d 	bl	12060 <__cxa_finalize@plt>
   10f30:	97ffffd8 	bl	10e90 <deregister_tm_clones>
   10f34:	52800020 	mov	w0, #0x1                   	// #1
   10f38:	390d0260 	strb	w0, [x19, #832]
   10f3c:	f9400bf3 	ldr	x19, [sp, #16]
   10f40:	a8c27bfd 	ldp	x29, x30, [sp], #32
   10f44:	d65f03c0 	ret
   10f48:	d503201f 	nop
   10f4c:	d503201f 	nop

0000000000010f50 <frame_dummy>:
   10f50:	17ffffdc 	b	10ec0 <register_tm_clones>

0000000000010f54 <before(Mips2C::ExecutionContext*)>:
   10f54:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
   10f58:	910003fd 	mov	x29, sp
   10f5c:	f940a008 	ldr	x8, [x0, #320]
   10f60:	f2400d1f 	tst	x8, #0xf
   10f64:	540012e1 	b.ne	111c0 <before(Mips2C::ExecutionContext*)+0x26c>  // b.any
   10f68:	d0000109 	adrp	x9, 32000 <_DYNAMIC+0xff30>
   10f6c:	927c6d08 	and	x8, x8, #0xfffffff0
   10f70:	f941a529 	ldr	x9, [x9, #840]
   10f74:	8b08012a 	add	x10, x9, x8
   10f78:	f940a808 	ldr	x8, [x0, #336]
   10f7c:	3dc00140 	ldr	q0, [x10]
   10f80:	f2400d1f 	tst	x8, #0xf
   10f84:	3d80c000 	str	q0, [x0, #768]
   10f88:	3dc00540 	ldr	q0, [x10, #16]
   10f8c:	3d80c400 	str	q0, [x0, #784]
   10f90:	3dc00940 	ldr	q0, [x10, #32]
   10f94:	3d80c800 	str	q0, [x0, #800]
   10f98:	54001141 	b.ne	111c0 <before(Mips2C::ExecutionContext*)+0x26c>  // b.any
   10f9c:	927c6d08 	and	x8, x8, #0xfffffff0
   10fa0:	910d100b 	add	x11, x0, #0x344
   10fa4:	8b08012a 	add	x10, x9, x8
   10fa8:	3dc00540 	ldr	q0, [x10, #16]
   10fac:	3d80cc00 	str	q0, [x0, #816]
   10fb0:	3dc00940 	ldr	q0, [x10, #32]
   10fb4:	3d80d000 	str	q0, [x0, #832]
   10fb8:	3dc00d40 	ldr	q0, [x10, #48]
   10fbc:	3d80d400 	str	q0, [x0, #848]
   10fc0:	3dc01140 	ldr	q0, [x10, #64]
   10fc4:	3d80d800 	str	q0, [x0, #864]
   10fc8:	bd438800 	ldr	s0, [x0, #904]
   10fcc:	fd41b001 	ldr	d1, [x0, #864]
   10fd0:	fd41b402 	ldr	d2, [x0, #872]
   10fd4:	b9806148 	ldrsw	x8, [x10, #96]
   10fd8:	0f809023 	fmul	v3.2s, v1.2s, v0.s[0]
   10fdc:	0f809042 	fmul	v2.2s, v2.2s, v0.s[0]
   10fe0:	fd419800 	ldr	d0, [x0, #816]
   10fe4:	bd433801 	ldr	s1, [x0, #824]
   10fe8:	b9020008 	str	w8, [x0, #512]
   10fec:	f9001808 	str	x8, [x0, #48]
   10ff0:	0e20d460 	fadd	v0.2s, v3.2s, v0.2s
   10ff4:	1e212841 	fadd	s1, s2, s1
   10ff8:	fd01b402 	str	d2, [x0, #872]
   10ffc:	bd438c02 	ldr	s2, [x0, #908]
   11000:	fd01b003 	str	d3, [x0, #864]
   11004:	fd019800 	str	d0, [x0, #816]
   11008:	bd033801 	str	s1, [x0, #824]
   1100c:	34000288 	cbz	w8, 1105c <before(Mips2C::ExecutionContext*)+0x108>
   11010:	1e2e1003 	fmov	s3, #1.000000000000000000e+00
   11014:	1e270104 	fmov	s4, w8
   11018:	131f7d0c 	asr	w12, w8, #31
   1101c:	bd403806 	ldr	s6, [x0, #56]
   11020:	1e243865 	fsub	s5, s3, s4
   11024:	1e240844 	fmul	s4, s2, s4
   11028:	1e260846 	fmul	s6, s2, s6
   1102c:	1e250845 	fmul	s5, s2, s5
   11030:	bd037004 	str	s4, [x0, #880]
   11034:	bd037806 	str	s6, [x0, #888]
   11038:	1e253863 	fsub	s3, s3, s5
   1103c:	1e270185 	fmov	s5, w12
   11040:	1e250842 	fmul	s2, s2, s5
   11044:	0f839000 	fmul	v0.2s, v0.2s, v3.s[0]
   11048:	1e230821 	fmul	s1, s1, s3
   1104c:	bd037c03 	str	s3, [x0, #892]
   11050:	bd037402 	str	s2, [x0, #884]
   11054:	fd019800 	str	d0, [x0, #816]
   11058:	bd033801 	str	s1, [x0, #824]
   1105c:	bd438402 	ldr	s2, [x0, #900]
   11060:	910d700c 	add	x12, x0, #0x35c
   11064:	fd41a804 	ldr	d4, [x0, #848]
   11068:	bd433c05 	ldr	s5, [x0, #828]
   1106c:	fd400170 	ldr	d16, [x11]
   11070:	3dc0c811 	ldr	q17, [x0, #800]
   11074:	4ea21c43 	mov	v3.16b, v2.16b
   11078:	4ea21c46 	mov	v6.16b, v2.16b
   1107c:	1e220821 	fmul	s1, s1, s2
   11080:	6e0c0445 	mov	v5.s[1], v2.s[0]
   11084:	0f829000 	fmul	v0.2s, v0.2s, v2.s[0]
   11088:	0d409183 	ld1	{v3.s}[1], [x12]
   1108c:	910d600c 	add	x12, x0, #0x358
   11090:	4d408184 	ld1	{v4.s}[2], [x12]
   11094:	910d000c 	add	x12, x0, #0x340
   11098:	bd039801 	str	s1, [x0, #920]
   1109c:	4e0c04a7 	dup	v7.4s, v5.s[1]
   110a0:	0d409186 	ld1	{v6.s}[1], [x12]
   110a4:	fd01c800 	str	d0, [x0, #912]
   110a8:	4e833863 	zip1	v3.4s, v3.4s, v3.4s
   110ac:	f9419c0c 	ldr	x12, [x0, #824]
   110b0:	6e1c0444 	mov	v4.s[3], v2.s[0]
   110b4:	4e8738a5 	zip1	v5.4s, v5.4s, v7.4s
   110b8:	6e180606 	mov	v6.d[1], v16.d[0]
   110bc:	bd430807 	ldr	s7, [x0, #776]
   110c0:	6e140443 	mov	v3.s[2], v2.s[0]
   110c4:	1e272821 	fadd	s1, s1, s7
   110c8:	6e26dca5 	fmul	v5.4s, v5.4s, v6.4s
   110cc:	bd430c06 	ldr	s6, [x0, #780]
   110d0:	6e23dc83 	fmul	v3.4s, v4.4s, v3.4s
   110d4:	bd434c04 	ldr	s4, [x0, #844]
   110d8:	bd030801 	str	s1, [x0, #776]
   110dc:	1e240842 	fmul	s2, s2, s4
   110e0:	fd418004 	ldr	d4, [x0, #768]
   110e4:	1e2628a1 	fadd	s1, s5, s6
   110e8:	3c858165 	stur	q5, [x11, #88]
   110ec:	f941980b 	ldr	x11, [x0, #816]
   110f0:	4e31d470 	fadd	v16.4s, v3.4s, v17.4s
   110f4:	0e24d404 	fadd	v4.2s, v0.2s, v4.2s
   110f8:	bd431c11 	ldr	s17, [x0, #796]
   110fc:	3d80ec03 	str	q3, [x0, #944]
   11100:	bd03ac02 	str	s2, [x0, #940]
   11104:	1e222a22 	fadd	s2, s17, s2
   11108:	bd030c01 	str	s1, [x0, #780]
   1110c:	4ea0ea00 	fcmlt	v0.4s, v16.4s, #0.0
   11110:	fd018004 	str	d4, [x0, #768]
   11114:	bd031c02 	str	s2, [x0, #796]
   11118:	4e601e00 	bic	v0.16b, v16.16b, v0.16b
   1111c:	3d80c800 	str	q0, [x0, #800]
   11120:	a901314b 	stp	x11, x12, [x10, #16]
   11124:	f940a00a 	ldr	x10, [x0, #320]
   11128:	f2400d5f 	tst	x10, #0xf
   1112c:	54000361 	b.ne	11198 <before(Mips2C::ExecutionContext*)+0x244>  // b.any
   11130:	927c6d4a 	and	x10, x10, #0xfffffff0
   11134:	f941800b 	ldr	x11, [x0, #768]
   11138:	f941840c 	ldr	x12, [x0, #776]
   1113c:	8b0a012a 	add	x10, x9, x10
   11140:	a900314b 	stp	x11, x12, [x10]
   11144:	f940a00a 	ldr	x10, [x0, #320]
   11148:	f2400d5f 	tst	x10, #0xf
   1114c:	54000261 	b.ne	11198 <before(Mips2C::ExecutionContext*)+0x244>  // b.any
   11150:	927c6d4a 	and	x10, x10, #0xfffffff0
   11154:	f941880b 	ldr	x11, [x0, #784]
   11158:	f9418c0c 	ldr	x12, [x0, #792]
   1115c:	8b0a012a 	add	x10, x9, x10
   11160:	a901314b 	stp	x11, x12, [x10, #16]
   11164:	f940a00a 	ldr	x10, [x0, #320]
   11168:	f2400d5f 	tst	x10, #0xf
   1116c:	54000161 	b.ne	11198 <before(Mips2C::ExecutionContext*)+0x244>  // b.any
   11170:	7100011f 	cmp	w8, #0x0
   11174:	927c6d4a 	and	x10, x10, #0xfffffff0
   11178:	f941900b 	ldr	x11, [x0, #800]
   1117c:	f941940c 	ldr	x12, [x0, #808]
   11180:	1a9f17e8 	cset	w8, eq	// eq = none
   11184:	8b0a0129 	add	x9, x9, x10
   11188:	a902312b 	stp	x11, x12, [x9, #32]
   1118c:	2a0803e0 	mov	w0, w8
   11190:	a8c17bfd 	ldp	x29, x30, [sp], #16
   11194:	d65f03c0 	ret
   11198:	f0ffff60 	adrp	x0, 0 <__abi_tag-0x2c4>
   1119c:	91260c00 	add	x0, x0, #0x983
   111a0:	f0ffff61 	adrp	x1, 0 <__abi_tag-0x2c4>
   111a4:	91275c21 	add	x1, x1, #0x9d7
   111a8:	f0ffff63 	adrp	x3, 0 <__abi_tag-0x2c4>
   111ac:	91298863 	add	x3, x3, #0xa62
   111b0:	f0ffff64 	adrp	x4, 0 <__abi_tag-0x2c4>
   111b4:	9127d884 	add	x4, x4, #0x9f6
   111b8:	52803802 	mov	w2, #0x1c0                 	// #448
   111bc:	9400037b 	bl	11fa8 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
   111c0:	f0ffff60 	adrp	x0, 0 <__abi_tag-0x2c4>
   111c4:	9126a800 	add	x0, x0, #0x9aa
   111c8:	f0ffff61 	adrp	x1, 0 <__abi_tag-0x2c4>
   111cc:	91275c21 	add	x1, x1, #0x9d7
   111d0:	f0ffff63 	adrp	x3, 0 <__abi_tag-0x2c4>
   111d4:	91254063 	add	x3, x3, #0x950
   111d8:	f0ffff64 	adrp	x4, 0 <__abi_tag-0x2c4>
   111dc:	9127d884 	add	x4, x4, #0x9f6
   111e0:	52802b02 	mov	w2, #0x158                 	// #344
   111e4:	94000371 	bl	11fa8 <private_assert_failed(char const*, char const*, int, char const*, char const*)>

00000000000111e8 <after(Mips2C::ExecutionContext*)>:
   111e8:	d10083ff 	sub	sp, sp, #0x20
   111ec:	a9017bfd 	stp	x29, x30, [sp, #16]
   111f0:	910043fd 	add	x29, sp, #0x10
   111f4:	f940a008 	ldr	x8, [x0, #320]
   111f8:	f2400d1f 	tst	x8, #0xf
   111fc:	54001121 	b.ne	11420 <after(Mips2C::ExecutionContext*)+0x238>  // b.any
   11200:	b0000109 	adrp	x9, 32000 <_DYNAMIC+0xff30>
   11204:	927c6d08 	and	x8, x8, #0xfffffff0
   11208:	f941a529 	ldr	x9, [x9, #840]
   1120c:	8b08012b 	add	x11, x9, x8
   11210:	f940a808 	ldr	x8, [x0, #336]
   11214:	f940096a 	ldr	x10, [x11, #16]
   11218:	b940196c 	ldr	w12, [x11, #24]
   1121c:	3dc00160 	ldr	q0, [x11]
   11220:	f2400d1f 	tst	x8, #0xf
   11224:	f90003ea 	str	x10, [sp]
   11228:	b9000bec 	str	w12, [sp, #8]
   1122c:	540010e1 	b.ne	11448 <after(Mips2C::ExecutionContext*)+0x260>  // b.any
   11230:	927c6d08 	and	x8, x8, #0xfffffff0
   11234:	bd438801 	ldr	s1, [x0, #904]
   11238:	3dc00973 	ldr	q19, [x11, #32]
   1123c:	8b08012a 	add	x10, x9, x8
   11240:	ad419942 	ldp	q2, q6, [x10, #48]
   11244:	fd400943 	ldr	d3, [x10, #16]
   11248:	bd401945 	ldr	s5, [x10, #24]
   1124c:	b9806148 	ldrsw	x8, [x10, #96]
   11250:	bd402d47 	ldr	s7, [x10, #44]
   11254:	4f8190c1 	fmul	v1.4s, v6.4s, v1.s[0]
   11258:	bd401d66 	ldr	s6, [x11, #28]
   1125c:	910cf00b 	add	x11, x0, #0x33c
   11260:	5e140424 	mov	s4, v1.s[2]
   11264:	0e21d463 	fadd	v3.2s, v3.2s, v1.2s
   11268:	1e2428b0 	fadd	s16, s5, s4
   1126c:	3cc1c144 	ldur	q4, [x10, #28]
   11270:	bd438405 	ldr	s5, [x0, #900]
   11274:	b9020008 	str	w8, [x0, #512]
   11278:	f9001808 	str	x8, [x0, #48]
   1127c:	340002c8 	cbz	w8, 112d4 <after(Mips2C::ExecutionContext*)+0xec>
   11280:	1e2e1011 	fmov	s17, #1.000000000000000000e+00
   11284:	1e270112 	fmov	s18, w8
   11288:	bd438c15 	ldr	s21, [x0, #908]
   1128c:	bd403816 	ldr	s22, [x0, #56]
   11290:	131f7d0c 	asr	w12, w8, #31
   11294:	1e323a34 	fsub	s20, s17, s18
   11298:	1e360ab6 	fmul	s22, s21, s22
   1129c:	1e320ab2 	fmul	s18, s21, s18
   112a0:	1e340ab4 	fmul	s20, s21, s20
   112a4:	bd037816 	str	s22, [x0, #888]
   112a8:	bd037012 	str	s18, [x0, #880]
   112ac:	1e343a37 	fsub	s23, s17, s20
   112b0:	1e270191 	fmov	s17, w12
   112b4:	4eb61ed4 	mov	v20.16b, v22.16b
   112b8:	1e310ab1 	fmul	s17, s21, s17
   112bc:	6e0c06f4 	mov	v20.s[1], v23.s[0]
   112c0:	0f979063 	fmul	v3.2s, v3.2s, v23.s[0]
   112c4:	1e370a10 	fmul	s16, s16, s23
   112c8:	bd037c17 	str	s23, [x0, #892]
   112cc:	bd037411 	str	s17, [x0, #884]
   112d0:	14000001 	b	112d4 <after(Mips2C::ExecutionContext*)+0xec>
   112d4:	4e080496 	dup	v22.2d, v4.d[0]
   112d8:	4f859055 	fmul	v21.4s, v2.4s, v5.s[0]
   112dc:	1e2308b7 	fmul	s23, s5, s3
   112e0:	f94003ec 	ldr	x12, [sp]
   112e4:	b9400bed 	ldr	w13, [sp, #8]
   112e8:	bd033810 	str	s16, [x0, #824]
   112ec:	3d800164 	str	q4, [x11]
   112f0:	6e042476 	mov	v22.s[0], v3.s[1]
   112f4:	f901880c 	str	x12, [x0, #784]
   112f8:	0e0c3c6c 	mov	w12, v3.s[1]
   112fc:	4e35d678 	fadd	v24.4s, v19.4s, v21.4s
   11300:	1e2708b3 	fmul	s19, s5, s7
   11304:	bd034c07 	str	s7, [x0, #844]
   11308:	b903180d 	str	w13, [x0, #792]
   1130c:	1e26006d 	fmov	w13, s3
   11310:	fd019803 	str	d3, [x0, #816]
   11314:	6e0c0616 	mov	v22.s[1], v16.s[0]
   11318:	ad1a8402 	stp	q2, q1, [x0, #848]
   1131c:	4ea0eb1a 	fcmlt	v26.4s, v24.4s, #0.0
   11320:	1e3328c6 	fadd	s6, s6, s19
   11324:	4f8592d6 	fmul	v22.4s, v22.4s, v5.s[0]
   11328:	4e7a1f07 	bic	v7.16b, v24.16b, v26.16b
   1132c:	bd031c06 	str	s6, [x0, #796]
   11330:	6e166019 	ext	v25.16b, v0.16b, v22.16b, #12
   11334:	3d80c807 	str	q7, [x0, #800]
   11338:	6e0406f9 	mov	v25.s[0], v23.s[0]
   1133c:	4e39d410 	fadd	v16.4s, v0.4s, v25.4s
   11340:	5f8498a0 	fmul	s0, s5, v4.s[2]
   11344:	5fa498a4 	fmul	s4, s5, v4.s[3]
   11348:	3d80c010 	str	q16, [x0, #768]
   1134c:	34000088 	cbz	w8, 1135c <after(Mips2C::ExecutionContext*)+0x174>
   11350:	bd037012 	str	s18, [x0, #880]
   11354:	bd037411 	str	s17, [x0, #884]
   11358:	fd01bc14 	str	d20, [x0, #888]
   1135c:	3c858176 	stur	q22, [x11, #88]
   11360:	f9419c0b 	ldr	x11, [x0, #824]
   11364:	aa0c81ac 	orr	x12, x13, x12, lsl #32
   11368:	bd039017 	str	s23, [x0, #912]
   1136c:	bd03a400 	str	s0, [x0, #932]
   11370:	bd03a804 	str	s4, [x0, #936]
   11374:	bd03ac13 	str	s19, [x0, #940]
   11378:	3d80ec15 	str	q21, [x0, #944]
   1137c:	a9012d4c 	stp	x12, x11, [x10, #16]
   11380:	f940a00a 	ldr	x10, [x0, #320]
   11384:	f2400d5f 	tst	x10, #0xf
   11388:	54000381 	b.ne	113f8 <after(Mips2C::ExecutionContext*)+0x210>  // b.any
   1138c:	927c6d4a 	and	x10, x10, #0xfffffff0
   11390:	f941800b 	ldr	x11, [x0, #768]
   11394:	f941840c 	ldr	x12, [x0, #776]
   11398:	8b0a012a 	add	x10, x9, x10
   1139c:	a900314b 	stp	x11, x12, [x10]
   113a0:	f940a00a 	ldr	x10, [x0, #320]
   113a4:	f2400d5f 	tst	x10, #0xf
   113a8:	54000281 	b.ne	113f8 <after(Mips2C::ExecutionContext*)+0x210>  // b.any
   113ac:	927c6d4a 	and	x10, x10, #0xfffffff0
   113b0:	f941880b 	ldr	x11, [x0, #784]
   113b4:	f9418c0c 	ldr	x12, [x0, #792]
   113b8:	8b0a012a 	add	x10, x9, x10
   113bc:	a901314b 	stp	x11, x12, [x10, #16]
   113c0:	f940a00a 	ldr	x10, [x0, #320]
   113c4:	f2400d5f 	tst	x10, #0xf
   113c8:	54000181 	b.ne	113f8 <after(Mips2C::ExecutionContext*)+0x210>  // b.any
   113cc:	7100011f 	cmp	w8, #0x0
   113d0:	927c6d4a 	and	x10, x10, #0xfffffff0
   113d4:	f941900b 	ldr	x11, [x0, #800]
   113d8:	f941940c 	ldr	x12, [x0, #808]
   113dc:	1a9f17e8 	cset	w8, eq	// eq = none
   113e0:	8b0a0129 	add	x9, x9, x10
   113e4:	a902312b 	stp	x11, x12, [x9, #32]
   113e8:	2a0803e0 	mov	w0, w8
   113ec:	a9417bfd 	ldp	x29, x30, [sp, #16]
   113f0:	910083ff 	add	sp, sp, #0x20
   113f4:	d65f03c0 	ret
   113f8:	f0ffff60 	adrp	x0, 0 <__abi_tag-0x2c4>
   113fc:	91260c00 	add	x0, x0, #0x983
   11400:	f0ffff61 	adrp	x1, 0 <__abi_tag-0x2c4>
   11404:	91275c21 	add	x1, x1, #0x9d7
   11408:	f0ffff63 	adrp	x3, 0 <__abi_tag-0x2c4>
   1140c:	91298863 	add	x3, x3, #0xa62
   11410:	f0ffff64 	adrp	x4, 0 <__abi_tag-0x2c4>
   11414:	9127d884 	add	x4, x4, #0x9f6
   11418:	52803802 	mov	w2, #0x1c0                 	// #448
   1141c:	940002e3 	bl	11fa8 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
   11420:	d503201f 	nop
   11424:	30f7b380 	adr	x0, a95 <_IO_stdin_used+0x375>
   11428:	f0ffff61 	adrp	x1, 0 <__abi_tag-0x2c4>
   1142c:	9127f021 	add	x1, x1, #0x9fc
   11430:	f0ffff63 	adrp	x3, 0 <__abi_tag-0x2c4>
   11434:	912e2463 	add	x3, x3, #0xb89
   11438:	f0ffff64 	adrp	x4, 0 <__abi_tag-0x2c4>
   1143c:	9127d884 	add	x4, x4, #0x9f6
   11440:	528006a2 	mov	w2, #0x35                  	// #53
   11444:	940002d9 	bl	11fa8 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
   11448:	f0ffff60 	adrp	x0, 0 <__abi_tag-0x2c4>
   1144c:	912d7800 	add	x0, x0, #0xb5e
   11450:	f0ffff61 	adrp	x1, 0 <__abi_tag-0x2c4>
   11454:	9127f021 	add	x1, x1, #0x9fc
   11458:	f0ffff63 	adrp	x3, 0 <__abi_tag-0x2c4>
   1145c:	912e2463 	add	x3, x3, #0xb89
   11460:	f0ffff64 	adrp	x4, 0 <__abi_tag-0x2c4>
   11464:	9127d884 	add	x4, x4, #0x9f6
   11468:	52800762 	mov	w2, #0x3b                  	// #59
   1146c:	940002cf 	bl	11fa8 <private_assert_failed(char const*, char const*, int, char const*, char const*)>

0000000000011470 <main>:
   11470:	fc180fea 	str	d10, [sp, #-128]!
   11474:	6d0123e9 	stp	d9, d8, [sp, #16]
   11478:	a9027bfd 	stp	x29, x30, [sp, #32]
   1147c:	a9036ffc 	stp	x28, x27, [sp, #48]
   11480:	a90467fa 	stp	x26, x25, [sp, #64]
   11484:	a9055ff8 	stp	x24, x23, [sp, #80]
   11488:	a90657f6 	stp	x22, x21, [sp, #96]
   1148c:	a9074ff4 	stp	x20, x19, [sp, #112]
   11490:	910083fd 	add	x29, sp, #0x20
   11494:	d14007ff 	sub	sp, sp, #0x1, lsl #12
   11498:	d124c3ff 	sub	sp, sp, #0x930
   1149c:	914007f8 	add	x24, sp, #0x1, lsl #12
   114a0:	914007ea 	add	x10, sp, #0x1, lsl #12
   114a4:	912383e9 	add	x9, sp, #0x8e0
   114a8:	91098318 	add	x24, x24, #0x260
   114ac:	9111814a 	add	x10, x10, #0x460
   114b0:	529999b4 	mov	w20, #0xcccd                	// #52429
   114b4:	91018308 	add	x8, x24, #0x60
   114b8:	aa1f03f7 	mov	x23, xzr
   114bc:	2a1f03fa 	mov	w26, wzr
   114c0:	f9015be8 	str	x8, [sp, #688]
   114c4:	91010148 	add	x8, x10, #0x40
   114c8:	2a1f03e4 	mov	w4, wzr
   114cc:	f90157e8 	str	x8, [sp, #680]
   114d0:	91020148 	add	x8, x10, #0x80
   114d4:	5280029b 	mov	w27, #0x14                  	// #20
   114d8:	f90153e8 	str	x8, [sp, #672]
   114dc:	91030148 	add	x8, x10, #0xc0
   114e0:	f0ffff62 	adrp	x2, 0 <__abi_tag-0x2c4>
   114e4:	912f0042 	add	x2, x2, #0xbc0
   114e8:	f9014fe8 	str	x8, [sp, #664]
   114ec:	91040148 	add	x8, x10, #0x100
   114f0:	f9014be8 	str	x8, [sp, #656]
   114f4:	91050148 	add	x8, x10, #0x140
   114f8:	72b99994 	movk	w20, #0xcccc, lsl #16
   114fc:	f90147e8 	str	x8, [sp, #648]
   11500:	91060148 	add	x8, x10, #0x180
   11504:	f0ffff75 	adrp	x21, 0 <__abi_tag-0x2c4>
   11508:	912fc2b5 	add	x21, x21, #0xbf0
   1150c:	f90143e8 	str	x8, [sp, #640]
   11510:	91070148 	add	x8, x10, #0x1c0
   11514:	f9013fe8 	str	x8, [sp, #632]
   11518:	913683e8 	add	x8, sp, #0xda0
   1151c:	910a014a 	add	x10, x10, #0x280
   11520:	910a3108 	add	x8, x8, #0x28c
   11524:	f0ffff79 	adrp	x25, 0 <__abi_tag-0x2c4>
   11528:	9124c339 	add	x25, x25, #0x930
   1152c:	f9011be8 	str	x8, [sp, #560]
   11530:	910a3128 	add	x8, x9, #0x28c
   11534:	528f3729 	mov	w9, #0x79b9                	// #31161
   11538:	f90117e8 	str	x8, [sp, #552]
   1153c:	12807fe8 	mov	w8, #0xfffffc00            	// #-1024
   11540:	72b3c6e9 	movk	w9, #0x9e37, lsl #16
   11544:	b904c3e8 	str	w8, [sp, #1216]
   11548:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   1154c:	4e040d20 	dup	v0.4s, w9
   11550:	3dc21901 	ldr	q1, [x8, #2144]
   11554:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11558:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   1155c:	b904c7ff 	str	wzr, [sp, #1220]
   11560:	ad0f87e0 	stp	q0, q1, [sp, #496]
   11564:	3dc22100 	ldr	q0, [x8, #2176]
   11568:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   1156c:	b81ec3bf 	stur	wzr, [x29, #-20]
   11570:	3d807be0 	str	q0, [sp, #480]
   11574:	3dc1e120 	ldr	q0, [x9, #1920]
   11578:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   1157c:	b902bbff 	str	wzr, [sp, #696]
   11580:	3d8077e0 	str	q0, [sp, #464]
   11584:	3dc1d500 	ldr	q0, [x8, #1872]
   11588:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   1158c:	f9011fea 	str	x10, [sp, #568]
   11590:	3d8073e0 	str	q0, [sp, #448]
   11594:	3dc1e500 	ldr	q0, [x8, #1936]
   11598:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   1159c:	3d806fe0 	str	q0, [sp, #432]
   115a0:	3dc22920 	ldr	q0, [x9, #2208]
   115a4:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   115a8:	3d806be0 	str	q0, [sp, #416]
   115ac:	3dc1cd00 	ldr	q0, [x8, #1840]
   115b0:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   115b4:	3d8067e0 	str	q0, [sp, #400]
   115b8:	3dc24100 	ldr	q0, [x8, #2304]
   115bc:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   115c0:	3d8063e0 	str	q0, [sp, #384]
   115c4:	3dc1e920 	ldr	q0, [x9, #1952]
   115c8:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   115cc:	3d805fe0 	str	q0, [sp, #368]
   115d0:	3dc23500 	ldr	q0, [x8, #2256]
   115d4:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   115d8:	3d805be0 	str	q0, [sp, #352]
   115dc:	3dc23900 	ldr	q0, [x8, #2272]
   115e0:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   115e4:	3d8057e0 	str	q0, [sp, #336]
   115e8:	3dc1dd20 	ldr	q0, [x9, #1904]
   115ec:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   115f0:	3d8053e0 	str	q0, [sp, #320]
   115f4:	3dc1fd00 	ldr	q0, [x8, #2032]
   115f8:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   115fc:	3d804fe0 	str	q0, [sp, #304]
   11600:	3dc21d00 	ldr	q0, [x8, #2160]
   11604:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11608:	3d804be0 	str	q0, [sp, #288]
   1160c:	3dc1d920 	ldr	q0, [x9, #1888]
   11610:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   11614:	3d8047e0 	str	q0, [sp, #272]
   11618:	3dc23100 	ldr	q0, [x8, #2240]
   1161c:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11620:	3d8043e0 	str	q0, [sp, #256]
   11624:	3dc20500 	ldr	q0, [x8, #2064]
   11628:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   1162c:	3d803fe0 	str	q0, [sp, #240]
   11630:	3dc24920 	ldr	q0, [x9, #2336]
   11634:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   11638:	3d803be0 	str	q0, [sp, #224]
   1163c:	3dc22500 	ldr	q0, [x8, #2192]
   11640:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11644:	3d8037e0 	str	q0, [sp, #208]
   11648:	3dc1f500 	ldr	q0, [x8, #2000]
   1164c:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11650:	3d8033e0 	str	q0, [sp, #192]
   11654:	3dc1ed20 	ldr	q0, [x9, #1968]
   11658:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   1165c:	3d802fe0 	str	q0, [sp, #176]
   11660:	3dc20100 	ldr	q0, [x8, #2048]
   11664:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11668:	3d802be0 	str	q0, [sp, #160]
   1166c:	3dc20900 	ldr	q0, [x8, #2080]
   11670:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11674:	3d8027e0 	str	q0, [sp, #144]
   11678:	3dc1f920 	ldr	q0, [x9, #2016]
   1167c:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   11680:	3d8023e0 	str	q0, [sp, #128]
   11684:	3dc20d00 	ldr	q0, [x8, #2096]
   11688:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   1168c:	3d801fe0 	str	q0, [sp, #112]
   11690:	3dc23d00 	ldr	q0, [x8, #2288]
   11694:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11698:	3d801be0 	str	q0, [sp, #96]
   1169c:	3dc24520 	ldr	q0, [x9, #2320]
   116a0:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   116a4:	3d8017e0 	str	q0, [sp, #80]
   116a8:	3dc1f100 	ldr	q0, [x8, #1984]
   116ac:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   116b0:	3d8013e0 	str	q0, [sp, #64]
   116b4:	3dc21500 	ldr	q0, [x8, #2128]
   116b8:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   116bc:	3d800fe0 	str	q0, [sp, #48]
   116c0:	3dc1d120 	ldr	q0, [x9, #1856]
   116c4:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   116c8:	3d800be0 	str	q0, [sp, #32]
   116cc:	3dc21100 	ldr	q0, [x8, #2112]
   116d0:	3d8007e0 	str	q0, [sp, #16]
   116d4:	3dc22d20 	ldr	q0, [x9, #2224]
   116d8:	3d8003e0 	str	q0, [sp]
   116dc:	910006ec 	add	x12, x23, #0x1
   116e0:	ad4f87e2 	ldp	q2, q1, [sp, #496]
   116e4:	4e040d80 	dup	v0.4s, w12
   116e8:	911203f3 	add	x19, sp, #0x480
   116ec:	f10052ff 	cmp	x23, #0x14
   116f0:	528000e8 	mov	w8, #0x7                   	// #7
   116f4:	5280738a 	mov	w10, #0x39c                 	// #924
   116f8:	92407eee 	and	x14, x23, #0xffffffff
   116fc:	1a8833e8 	csel	w8, wzr, w8, cc	// cc = lo, ul, last
   11700:	1a8a33eb 	csel	w11, wzr, w10, cc	// cc = lo, ul, last
   11704:	528924aa 	mov	w10, #0x4925                	// #18725
   11708:	4ea29c00 	mul	v0.4s, v0.4s, v2.4s
   1170c:	53196109 	lsl	w9, w8, #7
   11710:	72a4924a 	movk	w10, #0x2492, lsl #16
   11714:	9baa7dcd 	umull	x13, w14, w10
   11718:	f9010fec 	str	x12, [sp, #536]
   1171c:	529999a1 	mov	w1, #0xcccd                	// #52429
   11720:	0b17012f 	add	w15, w9, w23
   11724:	52801049 	mov	w9, #0x82                  	// #130
   11728:	2a0803f0 	mov	w16, w8
   1172c:	12003dec 	and	w12, w15, #0xffff
   11730:	1b095d0a 	madd	w10, w8, w9, w23
   11734:	0b170169 	add	w9, w11, w23
   11738:	4ea18402 	add	v2.4s, v0.4s, v1.4s
   1173c:	ad4b9be1 	ldp	q1, q6, [sp, #368]
   11740:	1b017d8b 	mul	w11, w12, w1
   11744:	33190910 	bfi	w16, w8, #7, #3
   11748:	5280106c 	mov	w12, #0x83                  	// #131
   1174c:	1b0c5d0c 	madd	w12, w8, w12, w23
   11750:	d360fdb2 	lsr	x18, x13, #32
   11754:	12003d31 	and	w17, w9, #0xffff
   11758:	4ea18403 	add	v3.4s, v0.4s, v1.4s
   1175c:	3dc05be1 	ldr	q1, [sp, #352]
   11760:	4ea68410 	add	v16.4s, v0.4s, v6.4s
   11764:	0b170210 	add	w16, w16, w23
   11768:	53147d6b 	lsr	w11, w11, #20
   1176c:	1b017e2d 	mul	w13, w17, w1
   11770:	4ea18404 	add	v4.4s, v0.4s, v1.4s
   11774:	ad4a07e6 	ldp	q6, q1, [sp, #320]
   11778:	12003e11 	and	w17, w16, #0xffff
   1177c:	4b1202e0 	sub	w0, w23, w18
   11780:	1b1bbd6b 	msub	w11, w11, w27, w15
   11784:	1b017e31 	mul	w17, w17, w1
   11788:	0b400652 	add	w18, w18, w0, lsr #1
   1178c:	12003d40 	and	w0, w10, #0xffff
   11790:	4ea18405 	add	v5.4s, v0.4s, v1.4s
   11794:	4ea68411 	add	v17.4s, v0.4s, v6.4s
   11798:	12003d8f 	and	w15, w12, #0xffff
   1179c:	1b017c00 	mul	w0, w0, w1
   117a0:	53147dad 	lsr	w13, w13, #20
   117a4:	53027e52 	lsr	w18, w18, #2
   117a8:	1b017def 	mul	w15, w15, w1
   117ac:	5291c721 	mov	w1, #0x8e39                	// #36409
   117b0:	53147e31 	lsr	w17, w17, #20
   117b4:	72a71c61 	movk	w1, #0x38e3, lsl #16
   117b8:	531e7516 	lsl	w22, w8, #2
   117bc:	aa1f03e3 	mov	x3, xzr
   117c0:	4c002e62 	st1	{v2.2d-v5.2d}, [x19]
   117c4:	ad490be1 	ldp	q1, q2, [sp, #288]
   117c8:	911103f3 	add	x19, sp, #0x440
   117cc:	9ba17dce 	umull	x14, w14, w1
   117d0:	53147def 	lsr	w15, w15, #20
   117d4:	1b1bc230 	msub	w16, w17, w27, w16
   117d8:	53147c11 	lsr	w17, w0, #20
   117dc:	531f7900 	lsl	w0, w8, #1
   117e0:	4ea28412 	add	v18.4s, v0.4s, v2.4s
   117e4:	1b1bb1ec 	msub	w12, w15, w27, w12
   117e8:	4b120e4f 	sub	w15, w18, w18, lsl #3
   117ec:	4ea18413 	add	v19.4s, v0.4s, v1.4s
   117f0:	ad4c87e6 	ldp	q6, q1, [sp, #400]
   117f4:	d361fdce 	lsr	x14, x14, #33
   117f8:	1b1baa2a 	msub	w10, w17, w27, w10
   117fc:	0b170111 	add	w17, w8, w23
   11800:	1b1ba5a8 	msub	w8, w13, w27, w9
   11804:	120006e9 	and	w9, w23, #0x3
   11808:	0b0f02ed 	add	w13, w23, w15
   1180c:	4ea68402 	add	v2.4s, v0.4s, v6.4s
   11810:	0b0e0dce 	add	w14, w14, w14, lsl #3
   11814:	1e03f928 	ucvtf	s8, w9, #2
   11818:	4c002e70 	st1	{v16.2d-v19.2d}, [x19]
   1181c:	4ea18410 	add	v16.4s, v0.4s, v1.4s
   11820:	3dc047e1 	ldr	q1, [sp, #272]
   11824:	911003f3 	add	x19, sp, #0x400
   11828:	528f3729 	mov	w9, #0x79b9                	// #31161
   1182c:	4b0e02ee 	sub	w14, w23, w14
   11830:	4ea18403 	add	v3.4s, v0.4s, v1.4s
   11834:	3dc03be1 	ldr	q1, [sp, #224]
   11838:	72b3c6e9 	movk	w9, #0x9e37, lsl #16
   1183c:	4a0902e9 	eor	w9, w23, w9
   11840:	1e03f1a9 	ucvtf	s9, w13, #4
   11844:	1e03f5ca 	ucvtf	s10, w14, #3
   11848:	4ea18411 	add	v17.4s, v0.4s, v1.4s
   1184c:	3dc06fe1 	ldr	q1, [sp, #432]
   11850:	b902bfe9 	str	w9, [sp, #700]
   11854:	92403d69 	and	x9, x11, #0xffff
   11858:	92403d08 	and	x8, x8, #0xffff
   1185c:	b90277f1 	str	w17, [sp, #628]
   11860:	4ea18414 	add	v20.4s, v0.4s, v1.4s
   11864:	3dc043e1 	ldr	q1, [sp, #256]
   11868:	f90137e9 	str	x9, [sp, #616]
   1186c:	92403e09 	and	x9, x16, #0xffff
   11870:	f90127e8 	str	x8, [sp, #584]
   11874:	0b000228 	add	w8, w17, w0
   11878:	4ea18404 	add	v4.4s, v0.4s, v1.4s
   1187c:	3dc037e1 	ldr	q1, [sp, #208]
   11880:	f90133e9 	str	x9, [sp, #608]
   11884:	92403d49 	and	x9, x10, #0xffff
   11888:	b90247e8 	str	w8, [sp, #580]
   1188c:	0b0002e8 	add	w8, w23, w0
   11890:	4ea18412 	add	v18.4s, v0.4s, v1.4s
   11894:	3dc02fe1 	ldr	q1, [sp, #176]
   11898:	f9012fe9 	str	x9, [sp, #600]
   1189c:	92403d89 	and	x9, x12, #0xffff
   118a0:	b90243e8 	str	w8, [sp, #576]
   118a4:	aa0203e8 	mov	x8, x2
   118a8:	4ea18415 	add	v21.4s, v0.4s, v1.4s
   118ac:	3dc03fe1 	ldr	q1, [sp, #240]
   118b0:	f9012be9 	str	x9, [sp, #592]
   118b4:	4ea18405 	add	v5.4s, v0.4s, v1.4s
   118b8:	3dc033e1 	ldr	q1, [sp, #192]
   118bc:	4ea18413 	add	v19.4s, v0.4s, v1.4s
   118c0:	4c002e62 	st1	{v2.2d-v5.2d}, [x19]
   118c4:	ad448be1 	ldp	q1, q2, [sp, #144]
   118c8:	910f03f3 	add	x19, sp, #0x3c0
   118cc:	4ea28416 	add	v22.4s, v0.4s, v2.4s
   118d0:	4ea18417 	add	v23.4s, v0.4s, v1.4s
   118d4:	ad4e07e6 	ldp	q6, q1, [sp, #448]
   118d8:	4c002e70 	st1	{v16.2d-v19.2d}, [x19]
   118dc:	910e03f3 	add	x19, sp, #0x380
   118e0:	4ea18410 	add	v16.4s, v0.4s, v1.4s
   118e4:	3dc023e1 	ldr	q1, [sp, #128]
   118e8:	4ea68402 	add	v2.4s, v0.4s, v6.4s
   118ec:	4ea18403 	add	v3.4s, v0.4s, v1.4s
   118f0:	3dc017e1 	ldr	q1, [sp, #80]
   118f4:	4c002e74 	st1	{v20.2d-v23.2d}, [x19]
   118f8:	910d03f3 	add	x19, sp, #0x340
   118fc:	4ea18411 	add	v17.4s, v0.4s, v1.4s
   11900:	3dc07be1 	ldr	q1, [sp, #480]
   11904:	4ea18414 	add	v20.4s, v0.4s, v1.4s
   11908:	3dc01fe1 	ldr	q1, [sp, #112]
   1190c:	4ea18404 	add	v4.4s, v0.4s, v1.4s
   11910:	3dc013e1 	ldr	q1, [sp, #64]
   11914:	4ea18412 	add	v18.4s, v0.4s, v1.4s
   11918:	3dc00be1 	ldr	q1, [sp, #32]
   1191c:	4ea18415 	add	v21.4s, v0.4s, v1.4s
   11920:	3dc01be1 	ldr	q1, [sp, #96]
   11924:	4ea18405 	add	v5.4s, v0.4s, v1.4s
   11928:	3dc00fe1 	ldr	q1, [sp, #48]
   1192c:	4ea18413 	add	v19.4s, v0.4s, v1.4s
   11930:	4c002e62 	st1	{v2.2d-v5.2d}, [x19]
   11934:	ad400be1 	ldp	q1, q2, [sp]
   11938:	910c03f3 	add	x19, sp, #0x300
   1193c:	4ea28416 	add	v22.4s, v0.4s, v2.4s
   11940:	4ea18417 	add	v23.4s, v0.4s, v1.4s
   11944:	4c002e70 	st1	{v16.2d-v19.2d}, [x19]
   11948:	910b03f3 	add	x19, sp, #0x2c0
   1194c:	4c002e74 	st1	{v20.2d-v23.2d}, [x19]
   11950:	b8636849 	ldr	w9, [x2, x3]
   11954:	b9400508 	ldr	w8, [x8, #4]
   11958:	aa1f03ea 	mov	x10, xzr
   1195c:	f90113e3 	str	x3, [sp, #544]
   11960:	b904cbe9 	str	w9, [sp, #1224]
   11964:	b81e83a8 	stur	w8, [x29, #-24]
   11968:	d503201f 	nop
   1196c:	10f791e8 	adr	x8, ba8 <_IO_stdin_used+0x488>
   11970:	914007e0 	add	x0, sp, #0x1, lsl #12
   11974:	b86a691c 	ldr	w28, [x8, x10]
   11978:	91118000 	add	x0, x0, #0x460
   1197c:	2a1f03e1 	mov	w1, wzr
   11980:	52809802 	mov	w2, #0x4c0                 	// #1216
   11984:	b904dfe4 	str	w4, [sp, #1244]
   11988:	f9026bea 	str	x10, [sp, #1232]
   1198c:	940001b9 	bl	12070 <memset@plt>
   11990:	f100a2ff 	cmp	x23, #0x28
   11994:	54000622 	b.cs	11a58 <main+0x5e8>  // b.hs, b.nlast
   11998:	b94277ea 	ldr	w10, [sp, #628]
   1199c:	b94243eb 	ldr	w11, [sp, #576]
   119a0:	914007e0 	add	x0, sp, #0x1, lsl #12
   119a4:	b94247ec 	ldr	w12, [sp, #580]
   119a8:	b942bfed 	ldr	w13, [sp, #700]
   119ac:	aa1f03e8 	mov	x8, xzr
   119b0:	f9411fe1 	ldr	x1, [sp, #568]
   119b4:	2a1703e9 	mov	w9, w23
   119b8:	91118000 	add	x0, x0, #0x460
   119bc:	4a0d35ad 	eor	w13, w13, w13, lsl #13
   119c0:	9bb47d2e 	umull	x14, w9, w20
   119c4:	8b080032 	add	x18, x1, x8
   119c8:	9bb47d4f 	umull	x15, w10, w20
   119cc:	91004108 	add	x8, x8, #0x10
   119d0:	4a4d45ad 	eor	w13, w13, w13, lsr #17
   119d4:	9bb47d70 	umull	x16, w11, w20
   119d8:	f108011f 	cmp	x8, #0x200
   119dc:	9bb47d91 	umull	x17, w12, w20
   119e0:	d364fdce 	lsr	x14, x14, #36
   119e4:	4a0d15ad 	eor	w13, w13, w13, lsl #5
   119e8:	d364fdef 	lsr	x15, x15, #36
   119ec:	d364fe10 	lsr	x16, x16, #36
   119f0:	1b1ba5ce 	msub	w14, w14, w27, w9
   119f4:	0b160129 	add	w9, w9, w22
   119f8:	4a0d35ad 	eor	w13, w13, w13, lsl #13
   119fc:	d364fe31 	lsr	x17, x17, #36
   11a00:	1b1ba9ef 	msub	w15, w15, w27, w10
   11a04:	1b1bae10 	msub	w16, w16, w27, w11
   11a08:	0b16016b 	add	w11, w11, w22
   11a0c:	0b16014a 	add	w10, w10, w22
   11a10:	4a4d45ad 	eor	w13, w13, w13, lsr #17
   11a14:	1b1bb231 	msub	w17, w17, w27, w12
   11a18:	b86e5aae 	ldr	w14, [x21, w14, uxtw #2]
   11a1c:	b86f5aaf 	ldr	w15, [x21, w15, uxtw #2]
   11a20:	0b16018c 	add	w12, w12, w22
   11a24:	4a0d15ad 	eor	w13, w13, w13, lsl #5
   11a28:	b8705ab0 	ldr	w16, [x21, w16, uxtw #2]
   11a2c:	29003e4e 	stp	w14, w15, [x18]
   11a30:	b8715aae 	ldr	w14, [x21, w17, uxtw #2]
   11a34:	4a0d35ad 	eor	w13, w13, w13, lsl #13
   11a38:	29013a50 	stp	w16, w14, [x18, #8]
   11a3c:	4a4d45ad 	eor	w13, w13, w13, lsr #17
   11a40:	4a0d15ad 	eor	w13, w13, w13, lsl #5
   11a44:	4a0d35ad 	eor	w13, w13, w13, lsl #13
   11a48:	4a4d45ad 	eor	w13, w13, w13, lsr #17
   11a4c:	4a0d15ad 	eor	w13, w13, w13, lsl #5
   11a50:	54fffb61 	b.ne	119bc <main+0x54c>  // b.any
   11a54:	14000019 	b	11ab8 <main+0x648>
   11a58:	b942bfed 	ldr	w13, [sp, #700]
   11a5c:	914007e0 	add	x0, sp, #0x1, lsl #12
   11a60:	aa1f03e8 	mov	x8, xzr
   11a64:	91118000 	add	x0, x0, #0x460
   11a68:	4a0d35a9 	eor	w9, w13, w13, lsl #13
   11a6c:	8b08000e 	add	x14, x0, x8
   11a70:	91004108 	add	x8, x8, #0x10
   11a74:	f108011f 	cmp	x8, #0x200
   11a78:	4a494529 	eor	w9, w9, w9, lsr #17
   11a7c:	4a091529 	eor	w9, w9, w9, lsl #5
   11a80:	4a09352a 	eor	w10, w9, w9, lsl #13
   11a84:	b90281c9 	str	w9, [x14, #640]
   11a88:	4a4a454a 	eor	w10, w10, w10, lsr #17
   11a8c:	4a0a154a 	eor	w10, w10, w10, lsl #5
   11a90:	4a0a354b 	eor	w11, w10, w10, lsl #13
   11a94:	b90285ca 	str	w10, [x14, #644]
   11a98:	4a4b456b 	eor	w11, w11, w11, lsr #17
   11a9c:	4a0b156b 	eor	w11, w11, w11, lsl #5
   11aa0:	4a0b356c 	eor	w12, w11, w11, lsl #13
   11aa4:	b90289cb 	str	w11, [x14, #648]
   11aa8:	4a4c458c 	eor	w12, w12, w12, lsr #17
   11aac:	4a0c158d 	eor	w13, w12, w12, lsl #5
   11ab0:	b9028dcd 	str	w13, [x14, #652]
   11ab4:	54fffda1 	b.ne	11a68 <main+0x5f8>  // b.any
   11ab8:	f100a2ff 	cmp	x23, #0x28
   11abc:	54000202 	b.cs	11afc <main+0x68c>  // b.hs, b.nlast
   11ac0:	f94137e8 	ldr	x8, [sp, #616]
   11ac4:	f94133e9 	ldr	x9, [sp, #608]
   11ac8:	f9412fea 	ldr	x10, [sp, #600]
   11acc:	b8687aa8 	ldr	w8, [x21, x8, lsl #2]
   11ad0:	b8697aa9 	ldr	w9, [x21, x9, lsl #2]
   11ad4:	b86a7aaa 	ldr	w10, [x21, x10, lsl #2]
   11ad8:	b918e3e8 	str	w8, [sp, #6368]
   11adc:	f9412be8 	ldr	x8, [sp, #592]
   11ae0:	b918e7e9 	str	w9, [sp, #6372]
   11ae4:	f94127e9 	ldr	x9, [sp, #584]
   11ae8:	b8687aa8 	ldr	w8, [x21, x8, lsl #2]
   11aec:	b918ebea 	str	w10, [sp, #6376]
   11af0:	b8697aaa 	ldr	w10, [x21, x9, lsl #2]
   11af4:	b918efe8 	str	w8, [sp, #6380]
   11af8:	14000014 	b	11b48 <main+0x6d8>
   11afc:	4a0d35a8 	eor	w8, w13, w13, lsl #13
   11b00:	4a484508 	eor	w8, w8, w8, lsr #17
   11b04:	4a081508 	eor	w8, w8, w8, lsl #5
   11b08:	4a083509 	eor	w9, w8, w8, lsl #13
   11b0c:	b918e3e8 	str	w8, [sp, #6368]
   11b10:	4a494529 	eor	w9, w9, w9, lsr #17
   11b14:	4a091529 	eor	w9, w9, w9, lsl #5
   11b18:	4a09352a 	eor	w10, w9, w9, lsl #13
   11b1c:	b918e7e9 	str	w9, [sp, #6372]
   11b20:	4a4a454a 	eor	w10, w10, w10, lsr #17
   11b24:	4a0a154a 	eor	w10, w10, w10, lsl #5
   11b28:	4a0a354b 	eor	w11, w10, w10, lsl #13
   11b2c:	b918ebea 	str	w10, [sp, #6376]
   11b30:	4a4b456b 	eor	w11, w11, w11, lsr #17
   11b34:	4a0b156b 	eor	w11, w11, w11, lsl #5
   11b38:	4a0b356c 	eor	w12, w11, w11, lsl #13
   11b3c:	b918efeb 	str	w11, [sp, #6380]
   11b40:	4a4c4588 	eor	w8, w12, w12, lsr #17
   11b44:	4a08150a 	eor	w10, w8, w8, lsl #5
   11b48:	911203eb 	add	x11, sp, #0x480
   11b4c:	911103ec 	add	x12, sp, #0x440
   11b50:	b918f3ea 	str	w10, [sp, #6384]
   11b54:	4c402d60 	ld1	{v0.2d-v3.2d}, [x11]
   11b58:	f94157eb 	ldr	x11, [sp, #680]
   11b5c:	52a7f40a 	mov	w10, #0x3fa00000            	// #1067450368
   11b60:	b918f7ea 	str	w10, [sp, #6388]
   11b64:	b944cbea 	ldr	w10, [sp, #1224]
   11b68:	910b03ee 	add	x14, sp, #0x2c0
   11b6c:	529f002d 	mov	w13, #0xf801                	// #63489
   11b70:	aa1f03e8 	mov	x8, xzr
   11b74:	aa1f03e9 	mov	x9, xzr
   11b78:	72a007ed 	movk	w13, #0x3f, lsl #16
   11b7c:	4c000800 	st4	{v0.4s-v3.4s}, [x0]
   11b80:	4c402d80 	ld1	{v0.2d-v3.2d}, [x12]
   11b84:	911003ec 	add	x12, sp, #0x400
   11b88:	4c000960 	st4	{v0.4s-v3.4s}, [x11]
   11b8c:	4c402d80 	ld1	{v0.2d-v3.2d}, [x12]
   11b90:	f94153eb 	ldr	x11, [sp, #672]
   11b94:	910f03ec 	add	x12, sp, #0x3c0
   11b98:	4c000960 	st4	{v0.4s-v3.4s}, [x11]
   11b9c:	4c402d80 	ld1	{v0.2d-v3.2d}, [x12]
   11ba0:	f9414feb 	ldr	x11, [sp, #664]
   11ba4:	910e03ec 	add	x12, sp, #0x380
   11ba8:	4c000960 	st4	{v0.4s-v3.4s}, [x11]
   11bac:	4c402d80 	ld1	{v0.2d-v3.2d}, [x12]
   11bb0:	f9414beb 	ldr	x11, [sp, #656]
   11bb4:	910d03ec 	add	x12, sp, #0x340
   11bb8:	4c000960 	st4	{v0.4s-v3.4s}, [x11]
   11bbc:	4c402d80 	ld1	{v0.2d-v3.2d}, [x12]
   11bc0:	f94147eb 	ldr	x11, [sp, #648]
   11bc4:	910c03ec 	add	x12, sp, #0x300
   11bc8:	4c000960 	st4	{v0.4s-v3.4s}, [x11]
   11bcc:	4c402d80 	ld1	{v0.2d-v3.2d}, [x12]
   11bd0:	f94143eb 	ldr	x11, [sp, #640]
   11bd4:	f9413fec 	ldr	x12, [sp, #632]
   11bd8:	4c000960 	st4	{v0.4s-v3.4s}, [x11]
   11bdc:	6f00e400 	movi	v0.2d, #0x0
   11be0:	b944c3eb 	ldr	w11, [sp, #1216]
   11be4:	b915a3ea 	str	w10, [sp, #5536]
   11be8:	b85e83aa 	ldur	w10, [x29, #-24]
   11bec:	3d8517e0 	str	q0, [sp, #5200]
   11bf0:	3d8513e0 	str	q0, [sp, #5184]
   11bf4:	3d850fe0 	str	q0, [sp, #5168]
   11bf8:	3d850be0 	str	q0, [sp, #5152]
   11bfc:	3d8507e0 	str	q0, [sp, #5136]
   11c00:	3d8503e0 	str	q0, [sp, #5120]
   11c04:	3d84ffe0 	str	q0, [sp, #5104]
   11c08:	3d84fbe0 	str	q0, [sp, #5088]
   11c0c:	3d84f7e0 	str	q0, [sp, #5072]
   11c10:	3d84f3e0 	str	q0, [sp, #5056]
   11c14:	3d84efe0 	str	q0, [sp, #5040]
   11c18:	3d84ebe0 	str	q0, [sp, #5024]
   11c1c:	3d84e7e0 	str	q0, [sp, #5008]
   11c20:	3d84e3e0 	str	q0, [sp, #4992]
   11c24:	3d84dfe0 	str	q0, [sp, #4976]
   11c28:	3d84dbe0 	str	q0, [sp, #4960]
   11c2c:	3d84d7e0 	str	q0, [sp, #4944]
   11c30:	3d84d3e0 	str	q0, [sp, #4928]
   11c34:	3d84cfe0 	str	q0, [sp, #4912]
   11c38:	3d84cbe0 	str	q0, [sp, #4896]
   11c3c:	3d84c7e0 	str	q0, [sp, #4880]
   11c40:	3d84c3e0 	str	q0, [sp, #4864]
   11c44:	3d84bfe0 	str	q0, [sp, #4848]
   11c48:	3d84bbe0 	str	q0, [sp, #4832]
   11c4c:	3d84b7e0 	str	q0, [sp, #4816]
   11c50:	3d84b3e0 	str	q0, [sp, #4800]
   11c54:	3d84afe0 	str	q0, [sp, #4784]
   11c58:	3d84abe0 	str	q0, [sp, #4768]
   11c5c:	3d84a7e0 	str	q0, [sp, #4752]
   11c60:	3d84a3e0 	str	q0, [sp, #4736]
   11c64:	3d849fe0 	str	q0, [sp, #4720]
   11c68:	3d849be0 	str	q0, [sp, #4704]
   11c6c:	4c402dc0 	ld1	{v0.2d-v3.2d}, [x14]
   11c70:	b915b3ea 	str	w10, [sp, #5552]
   11c74:	b944c7ea 	ldr	w10, [sp, #1220]
   11c78:	4c000980 	st4	{v0.4s-v3.4s}, [x12]
   11c7c:	1400000d 	b	11cb0 <main+0x840>
   11c80:	9bad7d4c 	umull	x12, w10, w13
   11c84:	f107ed3f 	cmp	x9, #0x1fb
   11c88:	d361fd8c 	lsr	x12, x12, #33
   11c8c:	0b0c2d8c 	add	w12, w12, w12, lsl #11
   11c90:	4b0c016c 	sub	w12, w11, w12
   11c94:	1e02f580 	scvtf	s0, w12, #3
   11c98:	bc296b00 	str	s0, [x24, x9]
   11c9c:	540001e8 	b.hi	11cd8 <main+0x868>  // b.pmore
   11ca0:	91001129 	add	x9, x9, #0x4
   11ca4:	91000508 	add	x8, x8, #0x1
   11ca8:	1101116b 	add	w11, w11, #0x44
   11cac:	1101114a 	add	w10, w10, #0x44
   11cb0:	f101a2ff 	cmp	x23, #0x68
   11cb4:	54fffe62 	b.cs	11c80 <main+0x810>  // b.hs, b.nlast
   11cb8:	927ced2c 	and	x12, x9, #0xfffffffffffffff0
   11cbc:	f107f13f 	cmp	x9, #0x1fc
   11cc0:	8b0c000c 	add	x12, x0, x12
   11cc4:	b37e050c 	bfi	x12, x8, #2, #2
   11cc8:	b942818c 	ldr	w12, [x12, #640]
   11ccc:	b8296b0c 	str	w12, [x24, x9]
   11cd0:	54fffe83 	b.cc	11ca0 <main+0x830>  // b.lo, b.ul, b.last
   11cd4:	14000008 	b	11cf4 <main+0x884>
   11cd8:	b942bbe8 	ldr	w8, [sp, #696]
   11cdc:	b917e3ff 	str	wzr, [sp, #6112]
   11ce0:	bd17e7e8 	str	s8, [sp, #6116]
   11ce4:	11000508 	add	w8, w8, #0x1
   11ce8:	bd17ebe9 	str	s9, [sp, #6120]
   11cec:	b902bbe8 	str	w8, [sp, #696]
   11cf0:	bd17efea 	str	s10, [sp, #6124]
   11cf4:	f9415be8 	ldr	x8, [sp, #688]
   11cf8:	b85e83a9 	ldur	w9, [x29, #-24]
   11cfc:	914007e1 	add	x1, sp, #0x1, lsl #12
   11d00:	913683e0 	add	x0, sp, #0xda0
   11d04:	91118021 	add	x1, x1, #0x460
   11d08:	52809802 	mov	w2, #0x4c0                 	// #1216
   11d0c:	b829491c 	str	w28, [x8, w9, uxtw]
   11d10:	940000dc 	bl	12080 <memcpy@plt>
   11d14:	914007e1 	add	x1, sp, #0x1, lsl #12
   11d18:	912383e0 	add	x0, sp, #0x8e0
   11d1c:	52809802 	mov	w2, #0x4c0                 	// #1216
   11d20:	91118021 	add	x1, x1, #0x460
   11d24:	940000d7 	bl	12080 <memcpy@plt>
   11d28:	914007e1 	add	x1, sp, #0x1, lsl #12
   11d2c:	911b83e0 	add	x0, sp, #0x6e0
   11d30:	52804002 	mov	w2, #0x200                 	// #512
   11d34:	91098021 	add	x1, x1, #0x260
   11d38:	940000d2 	bl	12080 <memcpy@plt>
   11d3c:	914007e1 	add	x1, sp, #0x1, lsl #12
   11d40:	911383e0 	add	x0, sp, #0x4e0
   11d44:	52804002 	mov	w2, #0x200                 	// #512
   11d48:	91098021 	add	x1, x1, #0x260
   11d4c:	940000cd 	bl	12080 <memcpy@plt>
   11d50:	911b83e8 	add	x8, sp, #0x6e0
   11d54:	b0000113 	adrp	x19, 32000 <_DYNAMIC+0xff30>
   11d58:	913683e0 	add	x0, sp, #0xda0
   11d5c:	f901a668 	str	x8, [x19, #840]
   11d60:	97fffc7d 	bl	10f54 <before(Mips2C::ExecutionContext*)>
   11d64:	2a0003f8 	mov	w24, w0
   11d68:	911383e8 	add	x8, sp, #0x4e0
   11d6c:	912383e0 	add	x0, sp, #0x8e0
   11d70:	f901a668 	str	x8, [x19, #840]
   11d74:	97fffd1d 	bl	111e8 <after(Mips2C::ExecutionContext*)>
   11d78:	4a000308 	eor	w8, w24, w0
   11d7c:	37000168 	tbnz	w8, #0, 11da8 <main+0x938>
   11d80:	913683e0 	add	x0, sp, #0xda0
   11d84:	912383e1 	add	x1, sp, #0x8e0
   11d88:	52809802 	mov	w2, #0x4c0                 	// #1216
   11d8c:	940000c1 	bl	12090 <bcmp@plt>
   11d90:	350000c0 	cbnz	w0, 11da8 <main+0x938>
   11d94:	911b83e0 	add	x0, sp, #0x6e0
   11d98:	911383e1 	add	x1, sp, #0x4e0
   11d9c:	52804002 	mov	w2, #0x200                 	// #512
   11da0:	940000bc 	bl	12090 <bcmp@plt>
   11da4:	340008e0 	cbz	w0, 11ec0 <main+0xa50>
   11da8:	b85ec3a8 	ldur	w8, [x29, #-20]
   11dac:	b904cffa 	str	w26, [sp, #1228]
   11db0:	71002d1f 	cmp	w8, #0xb
   11db4:	540007e8 	b.hi	11eb0 <main+0xa40>  // b.pmore
   11db8:	b944cbe2 	ldr	w2, [sp, #1224]
   11dbc:	b85e83a3 	ldur	w3, [x29, #-24]
   11dc0:	f0ffff60 	adrp	x0, 0 <__abi_tag-0x2c4>
   11dc4:	912b8400 	add	x0, x0, #0xae1
   11dc8:	2a1703e1 	mov	w1, w23
   11dcc:	2a1c03e4 	mov	w4, w28
   11dd0:	940000b4 	bl	120a0 <printf@plt>
   11dd4:	f94117f3 	ldr	x19, [sp, #552]
   11dd8:	f9411bfa 	ldr	x26, [sp, #560]
   11ddc:	aa1f03fc 	mov	x28, xzr
   11de0:	14000006 	b	11df8 <main+0x988>
   11de4:	9100079c 	add	x28, x28, #0x1
   11de8:	9100435a 	add	x26, x26, #0x10
   11dec:	91004273 	add	x19, x19, #0x10
   11df0:	f100839f 	cmp	x28, #0x20
   11df4:	540005e0 	b.eq	11eb0 <main+0xa40>  // b.none
   11df8:	b85f4343 	ldur	w3, [x26, #-12]
   11dfc:	b85f4264 	ldur	w4, [x19, #-12]
   11e00:	6b04007f 	cmp	w3, w4
   11e04:	540001c1 	b.ne	11e3c <main+0x9cc>  // b.any
   11e08:	b85f8343 	ldur	w3, [x26, #-8]
   11e0c:	b85f8264 	ldur	w4, [x19, #-8]
   11e10:	6b04007f 	cmp	w3, w4
   11e14:	54000241 	b.ne	11e5c <main+0x9ec>  // b.any
   11e18:	b85fc343 	ldur	w3, [x26, #-4]
   11e1c:	b85fc264 	ldur	w4, [x19, #-4]
   11e20:	6b04007f 	cmp	w3, w4
   11e24:	540002c1 	b.ne	11e7c <main+0xa0c>  // b.any
   11e28:	b9400343 	ldr	w3, [x26]
   11e2c:	b9400264 	ldr	w4, [x19]
   11e30:	6b04007f 	cmp	w3, w4
   11e34:	54fffd80 	b.eq	11de4 <main+0x974>  // b.none
   11e38:	14000019 	b	11e9c <main+0xa2c>
   11e3c:	aa1903e0 	mov	x0, x25
   11e40:	2a1c03e1 	mov	w1, w28
   11e44:	2a1f03e2 	mov	w2, wzr
   11e48:	94000096 	bl	120a0 <printf@plt>
   11e4c:	b85f8343 	ldur	w3, [x26, #-8]
   11e50:	b85f8264 	ldur	w4, [x19, #-8]
   11e54:	6b04007f 	cmp	w3, w4
   11e58:	54fffe00 	b.eq	11e18 <main+0x9a8>  // b.none
   11e5c:	aa1903e0 	mov	x0, x25
   11e60:	2a1c03e1 	mov	w1, w28
   11e64:	52800022 	mov	w2, #0x1                   	// #1
   11e68:	9400008e 	bl	120a0 <printf@plt>
   11e6c:	b85fc343 	ldur	w3, [x26, #-4]
   11e70:	b85fc264 	ldur	w4, [x19, #-4]
   11e74:	6b04007f 	cmp	w3, w4
   11e78:	54fffd80 	b.eq	11e28 <main+0x9b8>  // b.none
   11e7c:	aa1903e0 	mov	x0, x25
   11e80:	2a1c03e1 	mov	w1, w28
   11e84:	52800042 	mov	w2, #0x2                   	// #2
   11e88:	94000086 	bl	120a0 <printf@plt>
   11e8c:	b9400343 	ldr	w3, [x26]
   11e90:	b9400264 	ldr	w4, [x19]
   11e94:	6b04007f 	cmp	w3, w4
   11e98:	54fffa60 	b.eq	11de4 <main+0x974>  // b.none
   11e9c:	aa1903e0 	mov	x0, x25
   11ea0:	2a1c03e1 	mov	w1, w28
   11ea4:	52800062 	mov	w2, #0x3                   	// #3
   11ea8:	9400007e 	bl	120a0 <printf@plt>
   11eac:	17ffffce 	b	11de4 <main+0x974>
   11eb0:	b85ec3a8 	ldur	w8, [x29, #-20]
   11eb4:	b944cffa 	ldr	w26, [sp, #1228]
   11eb8:	11000508 	add	w8, w8, #0x1
   11ebc:	b81ec3a8 	stur	w8, [x29, #-20]
   11ec0:	f9426bea 	ldr	x10, [sp, #1232]
   11ec4:	52800029 	mov	w9, #0x1                   	// #1
   11ec8:	b944dfe4 	ldr	w4, [sp, #1244]
   11ecc:	12000308 	and	w8, w24, #0x1
   11ed0:	0a380129 	bic	w9, w9, w24
   11ed4:	914007f8 	add	x24, sp, #0x1, lsl #12
   11ed8:	9100114a 	add	x10, x10, #0x4
   11edc:	0b080084 	add	w4, w4, w8
   11ee0:	0b09035a 	add	w26, w26, w9
   11ee4:	f100615f 	cmp	x10, #0x18
   11ee8:	91098318 	add	x24, x24, #0x260
   11eec:	54ffd3e1 	b.ne	11968 <main+0x4f8>  // b.any
   11ef0:	f94113e3 	ldr	x3, [sp, #544]
   11ef4:	f0ffff62 	adrp	x2, 0 <__abi_tag-0x2c4>
   11ef8:	912f0042 	add	x2, x2, #0xbc0
   11efc:	91002063 	add	x3, x3, #0x8
   11f00:	f100c07f 	cmp	x3, #0x30
   11f04:	8b030048 	add	x8, x2, x3
   11f08:	54ffd241 	b.ne	11950 <main+0x4e0>  // b.any
   11f0c:	b944c3e8 	ldr	w8, [sp, #1216]
   11f10:	f9410ff7 	ldr	x23, [sp, #536]
   11f14:	11007d08 	add	w8, w8, #0x1f
   11f18:	f102a2ff 	cmp	x23, #0xa8
   11f1c:	b904c3e8 	str	w8, [sp, #1216]
   11f20:	b944c7e8 	ldr	w8, [sp, #1220]
   11f24:	11007d08 	add	w8, w8, #0x1f
   11f28:	b904c7e8 	str	w8, [sp, #1220]
   11f2c:	54ffbd81 	b.ne	116dc <main+0x26c>  // b.any
   11f30:	b85ec3b3 	ldur	w19, [x29, #-20]
   11f34:	b942bbe2 	ldr	w2, [sp, #696]
   11f38:	f0ffff60 	adrp	x0, 0 <__abi_tag-0x2c4>
   11f3c:	912c1c00 	add	x0, x0, #0xb07
   11f40:	5282f401 	mov	w1, #0x17a0                	// #6048
   11f44:	2a1a03e3 	mov	w3, w26
   11f48:	2a1303e5 	mov	w5, w19
   11f4c:	94000055 	bl	120a0 <printf@plt>
   11f50:	7100027f 	cmp	w19, #0x0
   11f54:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11f58:	91297508 	add	x8, x8, #0xa5d
   11f5c:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   11f60:	9127dd29 	add	x9, x9, #0x9f7
   11f64:	f0ffff60 	adrp	x0, 0 <__abi_tag-0x2c4>
   11f68:	912afc00 	add	x0, x0, #0xabf
   11f6c:	9a881121 	csel	x1, x9, x8, ne	// ne = any
   11f70:	1a9f07f3 	cset	w19, ne	// ne = any
   11f74:	9400004b 	bl	120a0 <printf@plt>
   11f78:	2a1303e0 	mov	w0, w19
   11f7c:	914007ff 	add	sp, sp, #0x1, lsl #12
   11f80:	9124c3ff 	add	sp, sp, #0x930
   11f84:	a9474ff4 	ldp	x20, x19, [sp, #112]
   11f88:	a94657f6 	ldp	x22, x21, [sp, #96]
   11f8c:	a9455ff8 	ldp	x24, x23, [sp, #80]
   11f90:	a94467fa 	ldp	x26, x25, [sp, #64]
   11f94:	a9436ffc 	ldp	x28, x27, [sp, #48]
   11f98:	a9427bfd 	ldp	x29, x30, [sp, #32]
   11f9c:	6d4123e9 	ldp	d9, d8, [sp, #16]
   11fa0:	fc4807ea 	ldr	d10, [sp], #128
   11fa4:	d65f03c0 	ret

0000000000011fa8 <private_assert_failed(char const*, char const*, int, char const*, char const*)>:
   11fa8:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
   11fac:	910003fd 	mov	x29, sp
   11fb0:	b0000088 	adrp	x8, 22000 <fprintf@plt+0xff50>
   11fb4:	aa0403e6 	mov	x6, x4
   11fb8:	aa0303e5 	mov	x5, x3
   11fbc:	f9416508 	ldr	x8, [x8, #712]
   11fc0:	2a0203e4 	mov	w4, w2
   11fc4:	aa0103e3 	mov	x3, x1
   11fc8:	aa0003e2 	mov	x2, x0
   11fcc:	d503201f 	nop
   11fd0:	50f757c1 	adr	x1, aca <_IO_stdin_used+0x3aa>
   11fd4:	f9400108 	ldr	x8, [x8]
   11fd8:	aa0803e0 	mov	x0, x8
   11fdc:	94000035 	bl	120b0 <fprintf@plt>
   11fe0:	94000014 	bl	12030 <abort@plt>

Disassembly of section .init:

0000000000011fe4 <_init>:
   11fe4:	d503201f 	nop
   11fe8:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
   11fec:	910003fd 	mov	x29, sp
   11ff0:	97fffba1 	bl	10e74 <call_weak_fn>
   11ff4:	a8c17bfd 	ldp	x29, x30, [sp], #16
   11ff8:	d65f03c0 	ret

Disassembly of section .fini:

0000000000011ffc <_fini>:
   11ffc:	d503201f 	nop
   12000:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
   12004:	910003fd 	mov	x29, sp
   12008:	a8c17bfd 	ldp	x29, x30, [sp], #16
   1200c:	d65f03c0 	ret

Disassembly of section .plt:

0000000000012010 <abort@plt-0x20>:
   12010:	a9bf7bf0 	stp	x16, x30, [sp, #-16]!
   12014:	90000110 	adrp	x16, 32000 <_DYNAMIC+0xff30>
   12018:	f9417a11 	ldr	x17, [x16, #752]
   1201c:	910bc210 	add	x16, x16, #0x2f0
   12020:	d61f0220 	br	x17
   12024:	d503201f 	nop
   12028:	d503201f 	nop
   1202c:	d503201f 	nop

0000000000012030 <abort@plt>:
   12030:	90000110 	adrp	x16, 32000 <_DYNAMIC+0xff30>
   12034:	f9417e11 	ldr	x17, [x16, #760]
   12038:	910be210 	add	x16, x16, #0x2f8
   1203c:	d61f0220 	br	x17

0000000000012040 <__libc_start_main@plt>:
   12040:	90000110 	adrp	x16, 32000 <_DYNAMIC+0xff30>
   12044:	f9418211 	ldr	x17, [x16, #768]
   12048:	910c0210 	add	x16, x16, #0x300
   1204c:	d61f0220 	br	x17

0000000000012050 <__gmon_start__@plt>:
   12050:	90000110 	adrp	x16, 32000 <_DYNAMIC+0xff30>
   12054:	f9418611 	ldr	x17, [x16, #776]
   12058:	910c2210 	add	x16, x16, #0x308
   1205c:	d61f0220 	br	x17

0000000000012060 <__cxa_finalize@plt>:
   12060:	90000110 	adrp	x16, 32000 <_DYNAMIC+0xff30>
   12064:	f9418a11 	ldr	x17, [x16, #784]
   12068:	910c4210 	add	x16, x16, #0x310
   1206c:	d61f0220 	br	x17

0000000000012070 <memset@plt>:
   12070:	90000110 	adrp	x16, 32000 <_DYNAMIC+0xff30>
   12074:	f9418e11 	ldr	x17, [x16, #792]
   12078:	910c6210 	add	x16, x16, #0x318
   1207c:	d61f0220 	br	x17

0000000000012080 <memcpy@plt>:
   12080:	90000110 	adrp	x16, 32000 <_DYNAMIC+0xff30>
   12084:	f9419211 	ldr	x17, [x16, #800]
   12088:	910c8210 	add	x16, x16, #0x320
   1208c:	d61f0220 	br	x17

0000000000012090 <bcmp@plt>:
   12090:	90000110 	adrp	x16, 32000 <_DYNAMIC+0xff30>
   12094:	f9419611 	ldr	x17, [x16, #808]
   12098:	910ca210 	add	x16, x16, #0x328
   1209c:	d61f0220 	br	x17

00000000000120a0 <printf@plt>:
   120a0:	90000110 	adrp	x16, 32000 <_DYNAMIC+0xff30>
   120a4:	f9419a11 	ldr	x17, [x16, #816]
   120a8:	910cc210 	add	x16, x16, #0x330
   120ac:	d61f0220 	br	x17

00000000000120b0 <fprintf@plt>:
   120b0:	90000110 	adrp	x16, 32000 <_DYNAMIC+0xff30>
   120b4:	f9419e11 	ldr	x17, [x16, #824]
   120b8:	910ce210 	add	x16, x16, #0x338
   120bc:	d61f0220 	br	x17
