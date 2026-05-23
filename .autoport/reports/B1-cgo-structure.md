# Phase B1 — arm64 CGO regen (structural check)

> arm64 CGOs regenerated: KERNEL.CGO=158,816B, ENGINE.CGO=7,955,040B, GAME.CGO=11,569,536B. arm64-ret density: K=1.50/KB E=0.73/KB G=0.54/KB. x86-ret bytes: K=0.003% E=0.019% G=0.052% (<1% each, anti-x86-contamination). x86 oracle CGOs hash-match A2 baseline. Kernel probe: 4736.

## Per-CGO structural metrics

| CGO | bytes | objects | fns | arm64 ret | x86 ret | density (ret/KB) | x86 ret % | min/mean/max fn size |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| KERNEL.CGO | 158,816 | 8 | 197 | 233 | 5 | 1.50 | 0.003 | 20/391/6341 |
| ENGINE.CGO | 7,955,040 | 306 | 3845 | 5699 | 1504 | 0.73 | 0.019 | 16/922/46232 |
| GAME.CGO | 11,569,536 | 346 | 4199 | 6108 | 6031 | 0.54 | 0.052 | 16/911/46232 |

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
