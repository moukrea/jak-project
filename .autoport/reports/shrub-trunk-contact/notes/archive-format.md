# Archive GPU shrub/trunk — format 1
DIRECTIVES vab39193976

Producer: `shrub_contact_probe.{h,cpp}`, codec independent of GL: `shrub_contact_archive.h`.
No snapshots or callback are needed to archive. The optional callback receives the same checked
samples, synchronously; its frame is now the anchored `pad_replay::current_frame()`.

## Sampling and identity

Only logical frames120,180,240,300,360,420,480,540,600 are sampled (nine planned frames).
The prepared replay has120 neutral ticks,130 walking ticks, then neutral ticks; this window
covers before/contact/after and excludes the long stationary remainder. `capture_frame(render_frame)` selects the
first rendered frame seen for that logical frame across shrub, tie and grass. All draws in that
render frame are retained; repeated renders of the same logical frame are excluded. Manager
must call `archive_tick()` every frame, including no-draw frames. The following logical frame
closes a sampled frame. Frame601 (or the first observed frame>600) closes sample600. An
interrupted/unclosed final frame is deliberately not committed. `shrub_archive_complete` is0
until the window has passed AND all nine planned frame bits are set. A bit is set only when
the frame is closed with records and its requested disk write succeeds. Bit0 is frame120,
bit8 is frame600; full mask511. Duplicate/unplanned closure is rejected.
`shrub_archive_expected_frames=9`, `shrub_archive_observed_frame_mask` and
`shrub_archive_observed_frames` accompany progressive status. `shrub_archive_missing_planned_frames`
is published ONLY after logical frame600, so a not-yet-reached sample is never called missing.
An unfinished replay cannot claim a complete comparison window.

File name `<logical-frame>.shrub`. Binary scalar metadata is unsigned 64-bit little endian.
Header: magic 0x3141524847534f, logical frame, record count. Each record consists of:
length-prefixed identity, mapping number, length-prefixed input bytes, pre bytes, post bytes.
Trailer: FNV1a64 checksum of all preceding bytes. A length prefix is an unsigned64 byte count.
Identity is itself: domain string, level string, geo unsigned64 (two's complement signed int),
tree unsigned64, semantic name string, ordinal unsigned64. Ordinal is local to that exact
(domain,level,geo,tree,name) in the logical frame. geo<0 means shrub, otherwise tie.
Grass supplies its own geo/tree chunk/pass identity. CPU and float payloads retain original
bits; supported campaign hosts x86_64 and Android arm64 are little endian.

Capture inputs contain primitive mode/type/restart state, actual EBO bytes in submitted order,
then the referenced complete-primitive vertex IDs (sorted unique). Pre/post contain the actual
TF xyz float bits in that same vertex order. TF does not measure rasterization. Every enabled
VBO attribute is observed at those IDs: enabled flag, component count/type/normalization/integer
flag and raw per-vertex bytes; unused padding, object handles and stride are not compared.
Uniforms are read from the actual current program, with type/count and actual scalar bits,
including each active array element. Unsupported types fail explicitly. Bound uniform blocks
are copied from their actual bound byte range as observations.

## Mappings, derived independently from semantic names

- `capture`, `native-row0`: Common (0), strict inputs and pre both arms; post strict OFF.
- `contact-anchor`: Contact (1), strict OFF only.
- `contact-attachment`: NewAttachment (2), allowed absent reference, every byte must be zero OFF.
- attributes0/7/8 and shrub attribute9: Common. TIE attribute10: Contact.
- `uniform-u_tie_sway_*`, `uniform-u_shrub_native_on`, `uniform-u_jak_*`,
  `uniform-u_trample*`: Common. `u_shrub_contact_on` / `u_tie_contact_on`: Contact.
- Other attributes/uniforms/UBOs: Observation (3), archived but not deformation comparisons.
  Fragment TOD/color/PBR and camera projection do not feed measured pre/post world positions.
- Grass capture inputs and pre/post are strict in BOTH arms. Grass `attribute-0` holds sampled
  GrassInstance bytes; `attribute-light` holds the sampled RGBA bytes; ALL grass `uniform-*`
  records hold GL-observed uniform bits and are Common. They are registered before capture.

Unknown semantic record names/domains or mapping tags inconsistent with those rules are
rejected at reference consumption. Missing nonmapped identities, differing input bytes,
differing pre/post bits, empty populations, missing/corrupt frame files all count as failures.
Paired shrub/tie/grass populations are published separately; callers must require all relevant
populations nonzero. No global defect total or proof.txt is emitted here.

`archive_blob` caches load-time values even before replay anchor; each matching geo/tree/level
capture archives the latest cached values. Callers split rows into named records above and
update the native row after each actual wind update. No reference blob is ever fed to GL,
Loader, a LUT or geometry. `archive_capture` accepts synchronously copied opaque packed inputs
and pre/post bytes for instanced grass; instance/vertex IDs must be included by that caller.

## Commit and bounds

Output: OG_SHRUB_ARCHIVE / debug.opengoal.shrub.archive.
Read-only old-binary reference: OG_SHRUB_REFERENCE / debug.opengoal.shrub.reference.
Read-only corrected OFF archive: OG_SHRUB_OFF_REFERENCE / debug.opengoal.shrub.off_reference.
On Android a nonempty property takes precedence over its environment equivalent.

Each closed frame is fsync'd to exclusive `.partial`, atomically linked to its final name
without overwriting an earlier run, then its directory is fsync'd. Readers require exact file
length, frame identity, checksum, unique keys and bounded lengths. `.partial` is never read.
Limits: 32MiB per record/VBO map, 128MiB per cached-blob pool, 128MiB per encoded frame,
1GiB per run on disk. Exceeding a bound fails; it never silently decimates or succeeds.
The codec and GL capture paths both retain finite checks and missing-identity errors.

ON reads each complete old reference frame, compares current inputs/pre and grass post.
When OFF_REFERENCE is configured it ALSO reads corrected OFF for that frame and compares
OFF against the old reference (strict pre/post, Common/Contact, zero new attachments).
These are machine-produced byte comparisons, not imported summary verdicts.

Counters: shrub_archive_closed_frames, population_errors, input_differences, pre_differences,
post_differences, reference_enabled, shrub_pairs, tie_pairs, grass_pairs (same prefix);
off_pairs, off_missing, off_input_differences, off_pre_differences, off_post_differences,
off_reference_enabled (same prefix). GL/archive operational errors: shrub_contact_gpu_errors.
No comparison-enabled flag or positive population can be inferred from zero differences alone.

## Offline bench

`g++ -std=c++17 -Wall -Wextra -Werror -I. .autoport/reports/shrub-trunk-contact/notes/archive_codec_test.cpp -o .autoport/reports/shrub-trunk-contact/notes/archive_codec_test`
Run that executable. It exercises equality, byte changes, wrong frame, truncation/corruption,
missing records/files/populations, OFF-only mappings, zero attachment OFF, mapping tag rejection
and atomic no-overwrite. Additional assertions cover planned-window bounds, nine-bit completion,
missing planned samples, duplicate closure and exact grass blob schema. Measured result: all assertions passed. No engine build or device run
was performed by this subtask; GPU compatibility, timing and real-run volumes remain unproved.
