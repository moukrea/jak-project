## READ FIRST: .autoport/plans/build-system-pillar.md. P4 (final) of the owner's build-system pillar.
# Phase Grecharged-buildsys-cidocs — CI matrix green + user-centric docs
Owner (verbatim): "documentation user centric pour chaque target, simple, claire, concise et très noob
friendly, que tonton Jeanot de la compta puisse le faire... README réécrit intégralement, digérable par
quelqu'un qui n'est pas un dev, avec des sous-documents bien organisés pour chaque build target."
Deliverables: (1) CI: adapt the fork's existing workflows (windows-build-msvc/clang, macos-build-arm,
linux) to the new build CLI + flags + packaging outputs; windows-x86_64 artifact green in CI (no local
Windows — wine smoke best-effort); macos-arm64 green if the fork still passes upstream mac build;
(2) README full rewrite (non-dev: what this is, what it brings, how to get/build/play, per-OS quick
paths); (3) docs/build-<target>.md per target + user install guides; (4) jak-builds release layout
switched to the new artifacts. Proofs: CI runs linked green, docs reviewed against the "tonton Jeanot"
bar (each guide executable top-to-bottom without dev knowledge). Max: max_turns 2400, max_retries 5.
