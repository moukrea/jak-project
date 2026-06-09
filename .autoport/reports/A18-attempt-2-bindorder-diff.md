# Slot-22 dispatch-before-bind cluster — primary evidence

## Diff tool output (boot_link_tracer.py)

== boot-link bind-order diff ==
oracle: /tmp/x86-klink.log
  finishes=435 last="logo-loop"@435  milestone "link finish: logo" NOT reached
target: /tmp/arm64-klink.log
  finishes=216 DIED after "time-of-day"@seq216  (A18 trap fn=0x1c97a4)

FIRST divergence that explains the dispatch failure:
  type=process-taskable slot=22
    x86 oracle bound this method at finish seq 284;
    ARM64 reached it still EMPTY at finish seq 202 (never bound — only A18-trap-patched),
    and ARM64 boot died after "time-of-day" @ seq 216.
    => this is an engine type whose method was dispatched before its defmethod bound it on ARM64 ("type loaded after the A18 hook").

NOTE: the broad list below also includes methods the oracle binds at a seq the target never reached (it died at seq 216); those are not necessarily live dispatches. The slot-22 cluster whose arm64_empty seq is nearest the death seq are the live dispatch-before-bind suspects.
all dispatch-before-bind divergences (20 total, showing up to 30):
  type=process-taskable slot=22  oracle_bound@seq284  arm64_empty@seq202  [trapped]
  type=water-vol slot=22  oracle_bound@seq280  arm64_empty@seq200  [trapped]
  type=buzzer slot=22  oracle_bound@seq282  arm64_empty@seq200  [trapped]
  type=eco slot=22  oracle_bound@seq282  arm64_empty@seq200  [trapped]
  type=fuel-cell slot=22  oracle_bound@seq282  arm64_empty@seq200  [trapped]
  type=money slot=22  oracle_bound@seq282  arm64_empty@seq200  [trapped]
  type=barrel slot=22  oracle_bound@seq287  arm64_empty@seq200  [trapped]
  type=bucket slot=22  oracle_bound@seq287  arm64_empty@seq200  [trapped]
  type=crate slot=22  oracle_bound@seq287  arm64_empty@seq200  [trapped]
  type=pickup-spawner slot=22  oracle_bound@seq287  arm64_empty@seq200  [trapped]
  type=babak slot=22  oracle_bound@seq346  arm64_empty@seq200  [trapped]
  type=orb-cache-top slot=22  oracle_bound@seq348  arm64_empty@seq200  [trapped]
  type=entity slot=22  oracle_bound@seq274  arm64_empty@seq137  [trapped]
  type=entity-actor slot=22  oracle_bound@seq274  arm64_empty@seq137  [trapped]
  type=entity-ambient slot=22  oracle_bound@seq274  arm64_empty@seq137  [trapped]
  type=entity-camera slot=22  oracle_bound@seq274  arm64_empty@seq137  [trapped]
  type=projectile slot=22  oracle_bound@seq296  arm64_empty@seq125  [trapped]
  type=projectile-blue slot=22  oracle_bound@seq296  arm64_empty@seq125  [trapped]
  type=projectile-yellow slot=22  oracle_bound@seq296  arm64_empty@seq125  [trapped]
  type=pov-camera slot=22  oracle_bound@seq285  arm64_empty@seq110  [trapped]

## process-taskable slot 22 timeline on x86 (oracle)
KLINKTRACE method type=process-taskable slot=22 state=empty fn=0x0
KLINKTRACE method type=process-taskable slot=22 state=bound fn=0x1ec07d4

## process-taskable slot 22 timeline on arm64 (target)
KLINKTRACE method type=process-taskable slot=22 state=empty fn=0x0
KLINKTRACE method type=process-taskable slot=22 state=bound fn=0x1c97a4

## x86 finish sequence around the slot-22 binding window (seq 274-296)
KLINKTRACE finish obj=main seq=270
KLINKTRACE finish obj=collide-cache seq=271
KLINKTRACE finish obj=relocate seq=272
KLINKTRACE finish obj=memory-usage seq=273
KLINKTRACE finish obj=entity seq=274
KLINKTRACE finish obj=path seq=275
KLINKTRACE finish obj=vol seq=276
KLINKTRACE finish obj=navigate seq=277
KLINKTRACE finish obj=aligner seq=278
KLINKTRACE finish obj=effect-control seq=279
KLINKTRACE finish obj=water seq=280
KLINKTRACE finish obj=collectables-part seq=281
KLINKTRACE finish obj=collectables seq=282
KLINKTRACE finish obj=task-control seq=283
KLINKTRACE finish obj=process-taskable seq=284
KLINKTRACE finish obj=pov-camera seq=285
KLINKTRACE finish obj=powerups seq=286
KLINKTRACE finish obj=crates seq=287
KLINKTRACE finish obj=hud seq=288
KLINKTRACE finish obj=hud-classes seq=289
KLINKTRACE finish obj=progress-static seq=290
KLINKTRACE finish obj=progress-part seq=291
KLINKTRACE finish obj=progress-draw seq=292
KLINKTRACE finish obj=progress seq=293
KLINKTRACE finish obj=progress-pc seq=294
KLINKTRACE finish obj=credits seq=295
KLINKTRACE finish obj=projectiles seq=296
KLINKTRACE finish obj=ocean seq=297
KLINKTRACE finish obj=ocean-vu0 seq=298
KLINKTRACE finish obj=ocean-texture seq=299
KLINKTRACE finish obj=ocean-mid seq=300

## arm64 finish sequence at boot death (seq 210-216, last before SIGILL)
KLINKTRACE finish obj=speedruns seq=210
KLINKTRACE finish obj=pckernel-common seq=211
KLINKTRACE finish obj=pckernel seq=212
KLINKTRACE finish obj=mood-tables seq=213
KLINKTRACE finish obj=mood seq=214
KLINKTRACE finish obj=weather-part seq=215
KLINKTRACE finish obj=time-of-day seq=216

## A18 trap pointer reported in arm64 log
A18-DIAG sym-bind-trace: bound __a18-method-zero-trap to a18_method_zero_trap (GOAL fn ptr 0x1c97a4), patched 83 empty method slots across loaded kernel types — type-method-zero BLR-to-ee_base now lands at the trap (which prints the named missing impl and returns 0)

## arm64 SIGILL crash signature (the dispatch that triggered)
GK-DIAG sig=4 fault=0x2123000000 pc=0x2123000000 lr=0x21231d3754
GK-DIAG A18-DIAG type-method-zero: hop=0 MOV X8 <- X9 @ lr-36
GK-DIAG A18-DIAG type-method-zero: ldr-pc=0x21231d372c base=X16 offset=0x68 size=W method-slot=22 obj-add@found obj-goal-reg=X9 obj-goal=0x2215c0 obj-host=0x21232215c0 loaded-value=0x22162c type-tag@obj_host-4=0x50a1e0 obj-reg-clobbered-since-add=1
GK-DIAG A18-DIAG type-method-zero: TYPETAG-LOAD chain ldur-pc=0x21231d3724 host-obj-reg=X16 host-obj@signal=0x2123000000 type-tag-via-host=0x0 innerobj-add@found innerobj-reg=X12 innerobj-goal=0x4070 innerobj-host=0x2123004070 innerobj-type-tag=0x0 (canonical virtual-dispatch shape — the failing method is slot 22 of the innerobj's type)
GK-DIAG A18-DIAG type-method-zero: walking type-tag host=0x212350a1e0 sym-field=0x1c1414 sym-slot=0x21231c1414 (this slot is the type's symbol; dump_sym_name_at_slot follows):

## Source location of process-taskable's :state-methods (slot 22 = lose)

Per deftype process-taskable in goal_src/jak1/engine/game/task/task-control-h.gc:
