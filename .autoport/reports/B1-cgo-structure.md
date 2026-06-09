# Phase B1 — arm64 CGO regen (structural check)

> arm64 CGOs regenerated: KERNEL.CGO=172,080B, ENGINE.CGO=8,536,592B, GAME.CGO=12,194,832B. arm64-ret density: K=1.39/KB E=0.68/KB G=0.51/KB. x86-ret bytes: K=0.004% E=0.019% G=0.050% (<1% each, anti-x86-contamination). x86 oracle CGOs hash-match A2 baseline. Kernel probe: 4736.

## Per-CGO structural metrics

| CGO | bytes | objects | fns | arm64 ret | x86 ret | density (ret/KB) | x86 ret % | min/mean/max fn size |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| KERNEL.CGO | 172,080 | 8 | 197 | 233 | 6 | 1.39 | 0.004 | 20/427/6661 |
| ENGINE.CGO | 8,536,592 | 306 | 3845 | 5699 | 1602 | 0.68 | 0.019 | 16/997/48368 |
| GAME.CGO | 12,194,832 | 346 | 4199 | 6108 | 6131 | 0.51 | 0.050 | 16/987/48368 |

## decode_sample (first function in each CGO)

### KERNEL.CGO

Top mnemonics: `mov`=3, `ldp`=1, `ret`=1, `stp`=1

```text
0:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
4:	910003fd 	mov	x29, sp
8:	aa0703e7 	mov	x7, x7
c:	aa0703e0 	mov	x0, x7
10:	a8c17bfd 	ldp	x29, x30, [sp], #16
14:	d65f03c0 	ret
```

### ENGINE.CGO

Top mnemonics: `mov`=5, `fcvtzs`=1, `ldp`=1, `ret`=1, `scvtf`=1, `stp`=1, `sxtw`=1

```text
0:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
4:	910003fd 	mov	x29, sp
8:	aa0703e7 	mov	x7, x7
c:	aa0703f7 	mov	x23, x7
10:	1e3802e9 	fcvtzs	w9, s23
14:	93407d29 	sxtw	x9, w9
18:	1e220137 	scvtf	s23, w9
1c:	aa1703e0 	mov	x0, x23
20:	aa0003e0 	mov	x0, x0
24:	a8c17bfd 	ldp	x29, x30, [sp], #16
28:	d65f03c0 	ret
```

### GAME.CGO

Top mnemonics: `mov`=5, `fcvtzs`=1, `ldp`=1, `ret`=1, `scvtf`=1, `stp`=1, `sxtw`=1

```text
0:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
4:	910003fd 	mov	x29, sp
8:	aa0703e7 	mov	x7, x7
c:	aa0703f7 	mov	x23, x7
10:	1e3802e9 	fcvtzs	w9, s23
14:	93407d29 	sxtw	x9, w9
18:	1e220137 	scvtf	s23, w9
1c:	aa1703e0 	mov	x0, x23
20:	aa0003e0 	mov	x0, x0
24:	a8c17bfd 	ldp	x29, x30, [sp], #16
28:	d65f03c0 	ret
```

## Kernel symbol probe

```
4736
```
