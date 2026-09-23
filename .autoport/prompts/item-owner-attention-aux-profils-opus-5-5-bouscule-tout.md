> LIS D'ABORD `prompts/item-owner-attention-aux-profils-opus-5-5-bouscule-tout-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Plus rien ne tourne sous Opus 5 ni Fable 5.1 ; le choix de modele et d'effort par role est reglable en un seul endroit et mesure en continu

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Ticket cree par l'owner dans Linear le 2026-09-23. Son texte : ![image.png](https://uploads.linear.app/a0a96fbe-70d3-4d8d-9350-9c6c972f09b2/8c3ff3e0-321a-4999-8f69-66781cd85cf0/87a7a1da-7140-4e0e-973e-e765357b87ff)

![image.png](https://uploads.linear.app/a0a96fbe-70d3-4d8d-9350-9c6c972f09b2/da45f037-9f07-4b31-b314-47204c7470b8/6eaae378-5924-4d40-a5c3-a7b009f02597)

![image.png](https://uploads.linear.app/a0a96fbe-70d3-4d8d-9350-9c6c972f09b2/c7f214dd-fe92-4e92-a96a-fe1d14cea2ee/c5173c58-d024-4492-b2a6-795e61f007a7)

Alors Claude Opus 5 est à bannir, Fable 5.1 aussi, Opus 5.5 vient de sortir et il éclate tous les modèles de Claude pour un cout inférieur et un ration performance X perf encore […suite dans le contrat]

## Livrable
1. INTERDICTION STRUCTURELLE : une liste de modeles bannis (claude-opus-5, claude-fable-5-1, claude-fable-5) dans UN fichier de config ; une porte (lint + lancement) refuse tout chemin vivant qui peut lancer un modele banni : defauts de supervisor.sh, profil actif, repli code en dur, frontmatter .claude/agents/*.md, toute ligne de commande `claude --model`. `banned_model_paths` = nombre de ces chemins ; doit valoir 0. Le superviseur et ses sous-agents lisent leur modele dans model-profiles.json, plus dans une constante du script.
2. REGLABLE EN UN SEUL ENDROIT : changer le modele ou l'effort d'un role = une commande (`autoport profile ...`) ou une ligne de model-profiles.json, applique a la […suite dans le contrat]

## Preuve exigee
`banned_model_paths == 0` dans `reports/owner-attention-aux-profils-opus-5-5-bouscule-tout/proof.txt`.
Le proof se produit par `lib/proof_run.sh owner-attention-aux-profils-opus-5-5-bouscule-tout x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
