> LIS D'ABORD `prompts/item-harness-judge-binary-race-with-builder-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Le juge compare la preuve au binaire du disque au moment du verdict : un build entre la fin de la course et le verdict rejette une preuve juste

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Cree le 20/09 14:50 par le superviseur. FAIT MESURE : essai 4 de grass-blade-variants refuse par validators/generic.sh:134 — « sha=f1f2c5ece3ac69e4 n'est pas celui de build-android/lib/arm64-v8a/libgk.so sur le disque » — alors que proof.txt de la MEME course publie proof_binary_decision=identique, proof_binary_local_md5 = proof_binary_device_md5 = fa9b98975b29df41… : au moment de la COURSE, disque, APK et appareil portaient le meme binaire. Entre la fin de la course et le verdict, auto_build_apk.sh a produit QUATRE builds (14:16, 14:19, 14:21, 14:26 : un par commit, dont ceux du worker et du superviseur), et libgk.so du disque a change. La garde du constructeur ne retient que pendant la COURSE (« une course de preuve tourne — RETENTEE », auto_build_apk.sh:397/470), pas jusqu'au VERDICT. Consequence : un essai debite pour de la plomberie (releve du 16/09 : 4 echecs sur 5), et les termes […suite dans le contrat]

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
`judge_binary_race_defects == 0` dans `reports/harness-judge-binary-race-with-builder/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-judge-binary-race-with-builder x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a regarder en jeu : preuve machine..

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
