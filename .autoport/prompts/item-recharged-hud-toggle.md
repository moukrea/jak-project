> LIS D'ABORD `prompts/item-recharged-hud-toggle-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Un interrupteur dans les réglages Recharged allume ou éteint le HUD rechargé ; éteint, on retrouve le HUD d'origine

## Defaut cite
- 2026-09-19 : « Hello ? »

## Cause connue
Cree le 18/09 07:30 par le superviseur, sur demande de l'owner (JAK-177) : « on doit avoir un toggle dans les reglages recharges pour activer ou desactiver le HUD recharge ! Par defaut a on, herite du master toggle recharge… a off c'est le HUD d'origine ! ». ETAT MESURE AU MOMENT DE LA CREATION : le reglage `recharged-hud?` EXISTE dans pc-settings et les quatre chantiers du HUD le lisent deja a l'execution ; ce qui MANQUE est la LIGNE DE MENU — progress-pc.gc:1597 la pose sous `#when FLAG_RECHARGED_HUD`, drapeau de compilation a #f dans l'arbre suivi, donc ABSENTE du binaire livre (meme piege que le coeur, la jauge et les ramassables, tous sortis du drapeau les 17 et 18/09). Le libelle et l'aide existent deja (*recharged-hud-label*, pc-text-hint-rhud). PORTE : elle se lit sur le binaire LIVRE — la ligne est presente, sa valeur par defaut est ON, le passage a OFF ramene a zero les dessins […suite dans le contrat]

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
`recharged_hud_toggle_defects == 0` dans `reports/recharged-hud-toggle/proof.txt`.
Le proof se produit par `lib/proof_run.sh recharged-hud-toggle x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Reglages Recharged, interrupteur HUD sur OFF (puis aussi maitre Recharged sur OFF) : maintenir L2/R2 pour afficher le HUD. UNE question : la pile d'energie et la mecamouche RECHARGEES apparaissent-elles encore par-dessus celles d'origine ? (l'interrupteur lui-meme, sa valeur par defaut et le retour au HUD d'origine au repos sont valides par l'owner : ne pas les redemander)..

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
