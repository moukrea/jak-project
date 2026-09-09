# Moins d'appels pilote par draw, memes pixels

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
background_common.cpp:348-368 : 4 glTexParameteri sur l'objet texture a chaque changement (revalidation pilote) au lieu d'objets sampler ; Direct/Generic/Sprite rejouent 32 appels d'etat par flush (:162-318) ; Merc2 respecifie 8 attributs de VAO par bucket de niveau et par flush (:4349), draw envmap = 2 draws + 3 glColorMask (:5075-5115). Le cache perf_state_cache ne couvre que la famille tfrag (:376). Les 88 glGetUniformLocation par arbre sont traites dans lighting-ao-indirect (ub_frame + cache).

## Livrable
Objets sampler, cache d'etat etendu a Direct/Generic/Sprite/Merc2, un VAO persistant par niveau pour merc (API setup_merc_vao conservee : la passe Z de lighting-shadows la reutilise). Le moteur compte les appels d'etat redondants (meme valeur que l'etat courant) et publie gl_redundant_state_calls_per_frame. refset_replay_maxdiff == 0 sur les trois references.

## Preuve exigee
`gl_redundant_state_calls_per_frame <= 50` dans `reports/perf-gl-state/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-gl-state device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : identique au pixel ; gl_cpu_ms baisse.

## Hors perimetre
Ne touche pas a first_tfrag_draw_setup (perimetre lumiere). Ne touche a aucune feature validee.
