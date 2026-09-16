# Handoff — perf-codegen-arm64-calls (essai 7, 2026-09-16 18:38)

_Écrit par l'orchestrateur : cet essai n'a laissé aucune note. Ce qui suit est
tout ce que la machine peut prouver, pas un compte rendu._

## Dernier échec du validateur
```
[perf-codegen-arm64-calls FAIL] source moteur editee APRES la preuve (game/graphics/opengl_renderer/DirectRenderer2.cpp) : la preuve ne decrit pas ce binaire
[perf-codegen-arm64-calls FAIL] verdict_sources_sha=490580e6eb04af40 recopie dans la preuve, de49779e0162a701 recalcule sur le disque (27 fichier(s) epingle(s), liste=.autoport/acquis/_lib.sh,.autoport/acquis/crate-collision.sh,.autoport/acquis/cutscene-framing.sh,.autoport/acquis/daxter-eyes.sh,.autoport/acquis/font-urbanist.sh,.autoport/acquis/grass.sh,.autoport/acquis/loading-screen.sh,.autoport/acquis/perf-dma-chain-copies.sh,.autoport/acquis/perf-fbo-passes.sh,.autoport/acquis/subtitles.sh,.autoport/lib/backlog.py,.autoport/lib/device_binary_gate.sh,.autoport/lib/device_teardown.sh,.autoport/lib/gate_verdict.py,.autoport/lib/hdr_batches.py,.autoport/lib/impossible.py,.autoport/lib/pick_device.sh,.autoport/lib/proof_impossible.sh,.autoport/lib/proof_run.sh,.autoport/lib/run_commits.sh,.autoport/lib/stale_precheck.sh,.autoport/lib/verdict_sources.sh,.autoport/lib/zf_context.sh,.autoport/validators/generic.sh) : une source du VERDICT a change depuis la course. Commits survenus DEPUIS LE DEPART de cette course : 76, dont 4 touchant une source de verdict [2251f1472b:.autoport/acquis/shrub-trunk-contact.sh+.autoport/tests/harness/shrub_contact_local.py,ca4929da13:.autoport/tests/harness/shrub_contact_local.py,ecf837bb21:.autoport/lib/proof_run.sh,0f1b87faa5:.autoport/lib/census/perf-codegen-arm64-calls.sh]
[perf-codegen-arm64-calls FAIL] verdict_sources_count=24 dans la preuve, 27 sur le disque : la liste des sources du verdict a change depuis la course
[perf-codegen-arm64-calls FAIL] source du VERDICT editee APRES la preuve (.autoport/acquis/shrub-trunk-contact.sh,.autoport/lib/census/perf-codegen-arm64-calls.sh,.autoport/lib/proof_run.sh,.autoport/tests/harness/shrub_contact_local.py) : la preuve est plus vieille que son propre juge
[perf-codegen-arm64-calls FAIL] proof_attempt_id=perf-codegen-arm64-calls@6#1789438574 dans la preuve, essai courant 'perf-codegen-arm64-calls@7#1789575648' : cette preuve a ete produite par une AUTRE course (course=20260915T023442Z-1630758-da5d43c9, pid=1630758, started_at=2026-09-15T02:34:43Z). Le verdict porterait sur la mauvaise course.
[perf-codegen-arm64-calls FAIL] acquis : 10 script(s)/20fd0b057d5577cb dans la preuve, 11/af926c1ac648bc77 sur le disque — une garde d'acquis VALIDE PAR L'OWNER a change ou disparu depuis la course
[perf-codegen-arm64-calls FAIL] sha=0650799f8e3323e8 n'est pas celui de build-android/lib/arm64-v8a/libgk.so sur le disque
[perf-codegen-arm64-calls FAIL] codegen_lot_defects=1 viole le critere codegen_lot_defects == 0
[perf-codegen-arm64-calls FAIL] 8 constat(s) ci-dessus, aucun n'a ete masque par un autre.
```

## Fichiers touchés par cet essai
- .autoport/.release_notes_hash
- .autoport/reports/perf-codegen-arm64-calls/FINDINGS.txt
- android/app/src/jak1/assets-slim/bundle/jak1_cgo.manifest.properties

## Ce qui reste
- inconnu : à rétablir en lisant le diff ci-dessus.
