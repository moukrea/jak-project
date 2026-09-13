# Une preuve sur appareil deploie le binaire local, ou refuse tout de suite — jamais 400 s trop tard

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signalement du worker de hdr-shadow-range (essai 3, 13/09, FINDINGS.txt). `proof_run.sh <id> device` NE DEPLOIE PAS : il lance l'application deja installee, et le seul temoin d'un binaire perime est `device_lib_md5 != local_lib_md5` au fond du proof, 400 s trop tard. Chaque item appareil reinvente la meme garde (l'essai 2 de hdr-shadow-range s'est fabrique `notes/deploy.sh`, sortie 4 sur ecart de md5). C'est aussi la memoire du superviseur « deploy landing guard » : le symptome est `proof_feature_state=absent`, la cause un md5 qui differe.

## Livrable
`stale_binary_runs` = 0, somme de termes publies SEPAREMENT.
1. LE COUT D'AVANT EST CHIFFRE : compte de courses appareil archivees dont `device_lib_md5 != local_lib_md5`, publie par item ; non nul.
2. LA VERIFICATION PRECEDE LA MESURE : avant de lancer, la course compare les md5 ; ecart = soit deploiement du build local (quand l'appareil et le verrou du constructeur le permettent), soit refus IMMEDIAT avec un rc nomme et distinct — jamais une mesure sur un binaire perime. Publier la decision et les deux md5.
3. PLUS DE GARDE PRIVEE : compte de scripts `notes/deploy*.sh` ou equivalents ecrits par des items apres la livraison = zero.
4. LE TEMOIN A DEUX BRAS : bac a sable, md5 egaux = la course mesure ; md5 differents sans deploiement possible = refus avant l'appareil, `proof.txt` intact (item precedent). Les deux verdicts cote a cote.
PREUVE : `FEATURE harness-proof-run-device-deploys-or-refuses-first armed=1 hits=<courses appareil ayant verifie le binaire AVANT de mesurer>` + la ligne `stale_binary_runs=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Preuve exigee
`stale_binary_runs == 0` dans `reports/harness-proof-run-device-deploys-or-refuses-first/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-proof-run-device-deploys-or-refuses-first x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir dans le jeu : c'est du harnais. L'effet se lit sur les essais qui ne meurent plus pour cette cause..

## Hors perimetre
Ne touche pas au constructeur ni au publieur ; ne fait aucun `adb install` hors du verrou du constructeur. Tout ce qui n'est pas cet item.
