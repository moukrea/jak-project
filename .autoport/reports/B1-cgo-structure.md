# Phase B1 — arm64 CGO regen (structural check)

> arm64 CGOs regenerated: KERNEL.CGO=120,288B, ENGINE.CGO=6,110,016B, GAME.CGO=9,595,568B. arm64-ret density: K=1.98/KB E=0.96/KB G=0.65/KB. x86-ret bytes: K=0.008% E=0.021% G=0.060% (<1% each, anti-x86-contamination). x86 oracle CGOs hash-match A2 baseline. Kernel probe: 4736.

## Per-CGO structural metrics

| CGO | bytes | objects | fns | arm64 ret | x86 ret | density (ret/KB) | x86 ret % | min/mean/max fn size |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| KERNEL.CGO | 120,288 | 8 | 197 | 233 | 10 | 1.98 | 0.008 | 20/289/5285 |
| ENGINE.CGO | 6,110,016 | 306 | 3845 | 5699 | 1252 | 0.96 | 0.021 | 16/674/38860 |
| GAME.CGO | 9,595,568 | 346 | 4199 | 6108 | 5774 | 0.65 | 0.060 | 16/663/38860 |

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
