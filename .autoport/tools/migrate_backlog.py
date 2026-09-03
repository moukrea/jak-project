#!/usr/bin/env python3
"""Migration des 278 phases de `milestones.yaml` vers `backlog.yaml`.

Rejouable : lit uniquement des sources en lecture seule (milestones.yaml, state.json,
owner-ok/, prompts/, reports/*/owner-defects.txt, git log) et reecrit backlog.yaml.
N'ecrit RIEN d'autre. Aucune source n'est modifiee.

    python3 .autoport/tools/migrate_backlog.py [--out backlog.yaml] [--dry-run]

Regroupement : l'unite du backlog est la FEATURE que l'owner valide, pas l'id de phase.
Les familles ci-dessous sont declarees avec leur PREUVE (mots de l'owner, prompt partage,
validateur partage, ou une phase qui en nomme explicitement une autre). Toute phase qui
n'est pas dans une famille devient un item a elle seule : on ne fusionne jamais sur une
simple ressemblance de nom.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from collections import OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
AP = os.path.dirname(HERE)                       # .autoport/
REPO = os.path.dirname(AP)                       # jak-project/

MILESTONES = os.path.join(AP, "milestones.yaml")
STATE = os.path.join(AP, "state.json")
OWNER_OK = os.path.join(AP, "owner-ok")
PROMPTS = os.path.join(AP, "prompts")
REPORTS = os.path.join(AP, "reports")
DEFAULT_OUT = os.path.join(AP, "backlog.yaml")

RECENT_CUTOFF = "2026-08-28"   # "retour recent de l'owner" au sens de la priorisation

# Ce que l'owner a repete le plus souvent passe devant, quelle que soit la date. Ordre tenu
# a la main : c'est le seul endroit ou un humain classe.
HEAD_ORDER = ["cutscene-npc-flicker", "hd-skin-origin-stretch", "foliage-wind",
              "anim-interp-low-fps"]


# --------------------------------------------------------------------------------------
# 1. Familles : une feature = un item. Chaque entree porte sa preuve.
# --------------------------------------------------------------------------------------

# (id d'item, [ids de phases, du plus ancien au plus recent], preuve de la fusion)
FAMILIES = [
    ("cutscene-npc-flicker",
     ["Gcutscene-npc-flicker", "Gcutscene-npc-flicker-2"],
     "meme prompt (prompts/phase-Gcutscene-npc-flicker.md) et meme validateur ; "
     "le clone -2 est le retour 2 de l'owner sur le meme defaut"),

    ("cutscene-skip",
     ["Gcutscene-skip-all", "Gcutscene-skip-polish", "Gcutscene-skip-polish-2"],
     "les trois partagent prompts/phase-Gcutscene-skip-all.md ; -polish et -polish-2 sont "
     "les retours 1 et 2 de l'owner sur la meme cartouche de saut"),

    ("subtitle-style",
     ["Gsubtitle-style", "Gsubtitle-style-2"],
     "meme prompt ; -2 est intitule « SOUS-TITRES, RETOUR 2 » et l'owner valide « les "
     "sous-titres » d'un seul mot"),

    ("crate-collision",
     ["Gjak1-crate-collision", "Gjak1-crate-collision-2"],
     "meme prompt ; -2 est « CAISSES, RETOUR 2 » ; l'owner ferme « les caisses » en un mot"),

    ("anim-interp-low-fps",
     ["Gfixed-tick-anim-interp", "Gfixed-tick-anim-interp-2"],
     "-2 est « ANIMATIONS SACCADEES ..., retour 2 » sur le meme defaut d'interpolation"),

    ("grass-overhang",
     ["Grecharged-grass-overhang", "Grecharged-grass-overhang2", "Grecharged-grass-overhang3",
      "Grecharged-grass-overhang4", "Grecharged-grass-overhang5", "Grecharged-grass-overhang6",
      "Grecharged-grass-overhang7"],
     "sept rounds du meme livrable ; chaque round nomme le precedent comme rejete par "
     "l'owner ; il a fini par ordonner « Parke ... et passe a l'occlusion ambiante »"),

    ("foliage-wind",
     ["Grecharged-foliage-wind", "Grecharged-foliage-wind2", "Grecharged-foliage-wind3"],
     "rounds 1/2/3 de la meme brise dans les arbres ; -wind2 et -wind3 citent le round "
     "precedent comme non valide par l'owner"),

    ("hd-models",
     ["Grecharged-hd-models", "Grecharged-hd-models2", "Grecharged-hd-models3",
      "Grecharged-hd-models4", "Grecharged-hd-models5"],
     "cinq rounds du meme remplacement de modeles ; chaque round cite le verdict de "
     "l'owner sur le precedent (« un carnage », « CURSED », roadmap M2/M3)"),

    ("cutscene-vertical-frame",
     ["Gcutscene-reframe", "Gandroid-window-size", "Gcine-vertical-frame"],
     "l'owner : « les barres noires laterales ? c'est regle avec les cinematiques » "
     "(jeton Gandroid-window-size) ; le jeton Gcutscene-reframe dit que Gcine-vertical-frame "
     "porte le verdict"),

    ("pbr-per-material",
     ["Gpbr-per-texture-materials", "Gpbr-material-props", "Gpbr-props-reach-draw"],
     "l'owner : « pourquoi deux chantiers ? c'est debile » ; Gpbr-material-props dit « la "
     "phase precedente en avait livre 7 » et le refus de Gpbr-props-reach-draw porte sur "
     "ces memes 7 textures"),

    ("loading-screen",
     ["Gloading-screen", "Gloading-screen-window"],
     "-window est « ECRAN DE CHARGEMENT, RETOUR 4 » ; le jeton Gloading-screen dit que ses "
     "sept defauts sont traites par -window"),

    ("font-urbanist",
     ["Gfont-urbanist", "Gfont-regression"],
     "Gfont-regression est intitule « REGRESSION SUR UN ACQUIS VALIDE — LA POLICE URBANIST "
     "EST CASSEE » : c'est la meme police, rouverte"),

    ("keira-hd-parts",
     ["Gkeira-hd-detached-parts", "Gkeira-visor-deliver"],
     "validateur partage (validators/phase-Gkeira-hd-detached-parts.sh) ; -deliver dit que "
     "Gkeira-hd-detached-parts a ete declaree passee sans que le modele change"),

    ("title-sun-halo",
     ["Ghalo", "Ghalo-sun", "Gsun-halo"],
     "Gsun-halo : « RE-DO (owner ground truth, prior Ghalo/Ghalo-sun false-green) » — il "
     "nomme les deux precedentes"),

    ("menu-placement",
     ["Gmenu-ui-placement", "Gmenu-placement", "Gmenu-textures"],
     "Gmenu-placement : « prior Gmenu-ui-placement scale-proxy false-green » ; Gmenu-textures : "
     "« prior Gmenu-placement PART-proxy false-green »"),

    ("newgame-cinematic-crash",
     ["Gnewgame-crash", "Gcine-crash2", "Gcine-crash3", "Gfix-cinematic-crash", "Gcine-crash-mid"],
     "chaine explicite : crash2 cite le correctif de Gnewgame-crash, crash3 cite crash2, "
     "Gfix-cinematic-crash est un RE-DO du meme chemin owner, crash-mid le residu"),

    ("particles-stars",
     ["Gd2-particles-sun", "Gparticles-stars"],
     "Gparticles-stars : « RE-DO (owner ground truth, prior Gd2 builder-count proxy false-green) »"),

    ("logo-smash",
     ["Glogo-smash", "Glogo-garble"],
     "Glogo-garble : « the prior Glogo-smash false-greened on tris+state »"),

    ("scout-fly-crash",
     ["Gcrash-mouche", "Gcrash-mouche2", "Gcrash-mouche3"],
     "mouche2 est le residu de mouche, mouche3 dit « Gcrash-mouche2 6/6 was a FALSE GREEN »"),

    ("swamp-crash",
     ["Gcrash-rockvillage", "Gcrash-swamp-load", "Gcrash-swamp-real", "Gswamp-fstore"],
     "swamp-load : « FALSE-GREEN REOPEN ... Gcrash-rockvillage » ; swamp-real : « 2nd "
     "FALSE-GREEN REOPEN » ; Gswamp-fstore : « TRUE swamp fix (follow-up to the shipped band-aid) »"),

    ("input-replay",
     ["Ginput-replay", "Ginput-replay-determinism", "Ginput-replay-liverecord",
      "Ginput-replay-realinput"],
     "trois suites qui nomment chacune l'echec de la precedente sur le meme harnais"),

    ("collision-arm64",
     ["Gcollision-arm", "Gcollision-wallslide", "Gcollision-systemic", "Gcollision-replay-diff",
      "Gcollision-nanroot", "Gcollision-glitchcapture"],
     "wallslide est le residu de collision-arm ; replay-diff dit « the Gcollision-systemic "
     "FCVTZS fix was a FALSE GREEN » ; nanroot et glitchcapture sont les deux methodes "
     "suivantes sur la meme divergence arm64"),

    ("recharged-buildsys",
     ["Grecharged-buildsys-flags", "Grecharged-buildsys-packaging", "Grecharged-buildsys-firstboot",
      "Grecharged-buildsys-cidocs"],
     "les jetons les nomment PILLAR P1 a P4 d'un seul chantier : « Pillar P1-P4 complete and shipped »"),
]

# Groupes d'epoque : le portage arm64/Android de mai-juin. Aucune de ces phases n'a de
# jeton owner, aucune n'est une feature que l'owner valide aujourd'hui : elles sont
# archivees en bloc, ids conserves dans `history`.
ERAS = [
    ("portage-jalons-initiaux",
     "Portage arm64 : les 26 jalons initiaux (harnais differentiel, emetteur, boot, APK, jak1/2/3)",
     ["00-harness", "01-scaffold", "02-intarith", "03-memops", "04-controlflow", "05-abi",
      "06-float", "07-neon", "08-coroutines", "09-boot-linux-arm", "10-android-ndk", "11-apk",
      "12-android-runtime", "13-real-apk", "14-jak1", "15-jak2", "16-jak3", "17-apk-assets",
      "18-sdl3-bridge", "19-emitter-stress", "20-goal-main", "21-gles-shaders",
      "22-bionic-portability", "23-input-audio", "24-emitter-audit", "25-cgo-regen"]),

    ("emetteur-arm64",
     "Portage arm64 : l'emetteur de code AArch64 de goalc (29 sprints A*, plus la regeneration CGO)",
     ["A1-emitter-enumerate", "A2-emitter-implement", "A3-emitter-differential", "A4-linker-fixups",
      "A5-emitter-far-relocs", "A6-emitter-off-register", "A7-emitter-unit-tests",
      "A8-qemu-repro-and-displaygc-fix", "A9-codegen-spill-ops", "A10-callee-save-area",
      "A11-texture-sym-binding", "A12-gsound-stack-fnptr", "A13-iop-kernel-mutex-init",
      "A14-pc-memmove-bind", "A15-regalloc-fnptr-livethrough", "A16-device-cpu-divergence-diag",
      "A17-idiv-emitter-spill", "A18-type-method-zero-bind", "A19-goalc-arm64-codegen-fixes",
      "A20-goalc-arm64-field-offset", "A21-arm64-codegen-deeper-investigation",
      "A22-arm64-codegen-h2-fix", "A23-arm64-blr-target-tracer", "A24-arm64-epilogue-x30-tracer",
      "A25-arm64-ir-regset-fpr-dispatch", "A26-arm64-xmm-symmetric-and-break-trap",
      "A27-arm64-catch-frame-chain-tracer", "A28-arm64-codegen-fix-sprint",
      "A29-arm64-gsound-iop-rpc-sprint", "B1-cgo-regen-strict", "B2-cgo-qemu-stress"]),

    ("boot-arm64-et-android",
     "Portage arm64 : boot Linux arm64, portage Android (bionic, GLES, SDL3) et premiere image",
     ["C1-linux-arm64-config", "C2-linux-arm64-symbols", "C3-linux-arm64-title",
      "C4-klink-arm64-execute", "D1-android-bionic-shims", "D2-android-gles-shaders",
      "D3-android-sdl3-surface", "D4-android-apk-title", "A30-android-runtime-surface-bringup",
      "A31-android-boot-to-titlescreen", "A32-android-renderer-path-bringup",
      "A33-arm64-regalloc-spill-sprint", "A34-android-display-loop-first-frame",
      "A35-android-renderer-dma-to-gles", "A36-android-kernel-steady-state-first-frame",
      "A37-android-camera-matrix-first-visible-frame", "A38-android-float-spray-tripwire-goal-frame",
      "A39-android-goal-frame-capture", "A40-android-hint-cursor-reset-goal-frame",
      "A41-android-texture-path-goal-frame", "A42-android-tfrag-init-village-flythrough"]),

    ("ux-android-initiale",
     "Portage arm64 : UX Android de depart (paysage/manette, superposition tactile, sauvegardes)",
     ["E1-ux-landscape-gamepad", "E2-ux-touch-overlay-optional", "E3-ux-save-load"]),

    ("premiere-scene-jouable",
     "Portage arm64 : la premiere scene jouable (camera, decompression des joints, entrees) a Geyser Rock",
     ["F1a-android-camera-merc-title-correct", "F1b-android-joint-decompress-start-geyser",
      "F1c-android-camera-channel-start-geyser", "F1e-android-reveal-crash-fix",
      "F1d-android-input-cpad-start-geyser"]),
]

# Phases bloquees dans state.json qui n'existent PAS dans milestones.yaml : recueillies pour
# ne rien perdre.
ORPHAN_BLOCKED = ["Gmenu-pixelmatch", "Grefen-english-pristine-frames-audit"]


# --------------------------------------------------------------------------------------
# 2. Decisions declarees (statut, feature, gate). Chaque override porte sa raison.
# --------------------------------------------------------------------------------------

# item_id -> (statut force, raison). Applique APRES la regle mecanique.
STATUS_OVERRIDE = {
    "cutscene-npc-flicker": ("open",
        "l'owner a redit le 2026-09-03 « c'est pas corrige du tout » ; la phase etait "
        "parquee « en attente de sa parole », ce qui est faux : il a parle, et c'est non"),
    "grass-overhang": ("archived",
        "l'owner a ordonne le 2026-07-15 « Parke, note tes echecs cuisants, desactive par "
        "defaut et passe a l'occlusion ambiante » ; livre par defaut ETEINT. Ce n'est ni une "
        "validation ni quelque chose a lui redemander"),
    "hd-skin-origin-stretch": ("open",
        "state.json la marque « blocked » parce que l'orchestrateur a halte sur trois "
        "empreintes d'echec identiques — un mecanisme du harnais, pas une attente de "
        "l'owner ; le defaut qu'il a signale le 2026-08-31 est entier"),
    "jak2-polish": ("blocked",
        "l'owner a ordonne le 2026-07-10 de parquer jak2 pour reprendre jak1"),
    "recharged-hud-jak1": ("blocked",
        "l'owner a ordonne le 2026-07-09 de parquer le HUD (« revisit later, more important "
        "work first ») ; livre par defaut ETEINT"),
    "vulkan-option": ("archived",
        "l'owner a decide le 2026-07-06 de remiser le portage Vulkan complet et d'accepter "
        "l'increment partiel ; l'echafaudage est conserve"),
    "final-acceptance": ("archived",
        "recette globale de juin jamais lancee, depassee par les phases qui ont suivi"),
    "echo-pool": ("open",
        "bloquee en juin sans raison enregistree dans state.json ; le defaut (la mare d'eco "
        "noire non rendue dans la cinematique d'intro) n'a jamais ete corrige"),
    "recharged-grass-wear": ("blocked",
        "spike de conception seulement, aucune ligne de code : le jeton dit que "
        "l'implementation attend le feu vert de l'owner, ses 14 criteres d'acceptation "
        "sont dans le document"),
    "firstperson-hd-hide": ("validated",
        "l'owner ferme la premiere personne ET la visiere dans la meme phrase, recopiee du "
        "jeton owner-ok/Gkeira-visor-deliver"),
}

# owner_ok pose a la main quand la phrase de l'owner vit dans le jeton d'une AUTRE phase.
OWNER_OK_OVERRIDE = {
    "firstperson-hd-hide": {
        "date": "2026-08-29",
        "text": "Pour la vue en premiere personne et la visiere de Keira c'est regle, bien joue",
        "source": "owner-ok/Gkeira-visor-deliver",
    },
}

# Le libelle que l'owner reconnait. Ecrit a la main pour tout item qui n'est pas archive.
FEATURE = {
    "cutscene-npc-flicker": "Les PNJ clignotent pendant les cinematiques",
    "cutscene-skip": "Passer une cinematique en maintenant Cercle, avec la cartouche « Skip »",
    "subtitle-style": "Les sous-titres : texte blanc plein et vraie ombre portee",
    "crate-collision": "Les caisses de Geyser Rock a travers lesquelles on passe",
    "anim-interp-low-fps": "Les animations saccadees quand le jeu descend vers 20 images/s",
    "grass-overhang": "L'herbe qui retombe par-dessus le bord des plateformes",
    "foliage-wind": "La brise dans les arbres et les buissons",
    "hd-models": "Les modeles HD de Jak, Daxter, Samos et Keira",
    "cutscene-vertical-frame": "Les bandes noires et le cadrage des cinematiques",
    "pbr-per-material": "Des proprietes PBR par matiere, pas deux curseurs globaux",
    "loading-screen": "L'ecran de chargement a la place de l'ecran noir",
    "font-urbanist": "La police moderne Urbanist a la place du tout-majuscules",
    "keira-hd-parts": "Les morceaux detaches du modele HD de Keira (visiere, bretelles, lunettes)",
    "hd-skin-origin-stretch": "Les modeles HD qui s'etirent vers un point lointain",
    "hd-eye-scale": "Les yeux HD de Daxter deformes par l'effet cartoon de Jak 1",
    "firstperson-hd-hide": "En vue premiere personne on se retrouve dans la tete de Jak",
    "jak-hd-rig-strap": "La sangle et la boucle de la veste de Jak qui traversent les polygones",
    "text-tone": "Le ton des textes du jeu, trop formel",
    "menu-census-cleanup": "Le menu contient des options inutiles ou incomprehensibles",
    "recharged-menu-overhaul": "La refonte des menus",
    "grass-density-presets": "Cinq paliers de densite d'herbe au lieu d'un curseur",
    "grass-crash": "L'herbe fait planter le jeu",
    "memory-ceiling-and-crash": "Chargement interminable et plantage par manque de memoire",
    "precompute-deterministic-bake": "Pre-calculer ce qui peut l'etre au lieu de le refaire a chaque chargement",
    "playability-input-and-loadgate": "La touche saut qui ne repond pas a la manette",
    "loadgate-crash-regression": "Le jeu ne charge plus une sauvegarde",
    "build-from-scratch": "Un build depuis zero doit donner le meme jeu que le notre",
    "recharged-materials-modern-parity": "Des materiaux au niveau des moteurs modernes",
    "recharged-secondary-motion": "Le mouvement secondaire des personnages HD (physique de Keira)",
    "recharged-pbr-realtime-fusion": "Les matieres PBR eclairees par la lumiere temps reel",
    "recharged-texture-hotreload": "Basculer les textures Recharged sans redemarrer le jeu",
    "recharged-loader-packfix": "Le build ne demarrait plus sur son Honor (pack de 420 Mo)",
    "recharged-managed-assets-merge": "Le gestionnaire d'assets avec installation reprenable",
    "recharged-mesh-consolidation": "Les coutures visibles sur les meshes du jeu",
    "recharged-mesh-browser": "Le navigateur de mesh de debug",
    "recharged-naming": "Le nom des jeux et de la collection Recharged",
    "recharged-master-toggle": "Un interrupteur global Recharged marche/arret",
    "recharged-bundled-textures": "Les textures PBR maison livrees dans l'APK",
    "recharged-lightprobes": "Les sondes de lumiere locales a la place de l'ambiante globale",
    "recharged-directional-ambient": "L'ambiante directionnelle (le relief dans les zones d'ombre)",
    "recharged-title-logo-fullres": "Le logo du titre pixelise a basse resolution de rendu",
    "recharged-hud-jak1": "Le HUD Recharged de jak1",
    "menu-flag-off": "Sortir la refonte de menu cassee des builds",
    "touch-longjump-regression": "Le long jump au tactile qui ne part plus",
    "cine-cut": "Les coupes de camera des cinematiques qui glissent au lieu de couper",
    "echo-pool": "La mare d'eco noire non rendue dans la cinematique d'intro",
    "jak2-polish": "Les finitions de Jak II (mapping L1/R1, cadrage, menus, particules)",
    "recharged-buildsys": "Le systeme de build unifie, le packaging et l'installation",
    "grass-precompute-mode": "L'herbe pre-calculee pour le temps de chargement",
    "vulkan-option": "Un moteur de rendu Vulkan en option",
}


FEATURE.update({
    # --- juin-juillet : livre, jeton owner-ok vide ou ecrit par le superviseur -----------
    "framerate-variable": "Le jeu tourne a la cadence de l'ecran, sans verrou 30/60",
    "res-picker": "Le choix de la resolution de jeu dans les options",
    "render-split": "L'interface reste nette quand on baisse l'echelle de rendu",
    "dynamic-renderscale": "L'echelle de rendu qui s'adapte toute seule pour tenir la cadence",
    "dynamic-fix": "L'echelle de rendu dynamique qui ne repondait pas aux reglages",
    "camera-smooth": "La camera qui saccade quand on tourne autour de Jak",
    "camera-interp": "La camera qui saute encore par petits pas",
    "options-reorder": "L'ordre des lignes du menu Graphismes",
    "launcher-collection": "Un APK par jeu, avec son nom et son icone",
    "touch-menus": "Naviguer les menus au doigt, sans la croix directionnelle",
    "touch-fix": "Les interrupteurs et les curseurs des menus au doigt",
    "warp-dpad": "Le stick fait office de croix directionnelle devant un teleporteur",
    "crash-blueeco": "Plantage a la source d'eco bleue de la Jungle Interdite",
    "perf-batching": "Le gain de cadence par regroupement des appels de dessin",
    "perf-particles": "La cadence dans les zones a particules (les feux)",
    "perf-particles2": "Les particules : image qui pope et textures qui clignotent",
    "orb-hud-regression": "Les orbes precurseurs blanches dans le HUD et les menus",
    "eco-spheres": "Les spheres d'eco mal rendues sur Android",
    "lang-mixed": "Des invites restent en anglais quand le texte est en francais",
    "ndskip": "Passer le logo Naughty Dog avec Start",
    "title-tap": "« Appuie sur start ou touche l'ecran » et le tap au titre",
    "jak2-boot": "Jak II demarre sur Android",
    "jak2-render": "Jak II affiche Haven City sur le telephone",
    "jak2-visuals": "La qualite d'image de Jak II au titre et dans l'intro",
    "jak1-intermittent-events": "Des mini-cinematiques et des plateformes qui ne se declenchent pas",
    "recharged-grass-object-clip": "L'herbe qui traverse les objets poses au sol",
    "recharged-grass-wear": "L'usure et la hauteur variable de l'herbe",
    "recharged-external-assets": "Les assets hors de l'APK, telecharges a part",
    "recharged-ambient-occlusion": "L'occlusion ambiante (le relief dans les creux)",
    "fixed-tick-interpolation": "Le pas de temps fixe et l'interpolation du rendu",
    # --- validees : libelle dans ses mots ------------------------------------------------
    "swamp-crash": "Le plantage en passant de Rock Village aux marais",
    "jak2-ingame": "Jak II jouable : collision et transition des deux ans",
    "jak2-pcmenus": "Les menus PC de Jak II (format d'image, resolution)",
    "jak2-movement": "Jak II : le personnage qui ne se deplacait pas",
    "recharged-grass-poc": "L'herbe 3D",
    "recharged-grass-precompute-mode": "L'herbe pre-calculee pour le temps de chargement",
    "jak1-shadow-cast": "L'ombre de Jak au sol",
    "recharged-pbr-materials": "Les matieres PBR (le systeme de remplacement de textures)",
    "recharged-realtime-lighting": "L'eclairage temps reel au soleil, avec ombres portees",
    "beach-actors-gate": "Les collecteurs d'eco vert au retour de Geyser Rock",
})

# Ou regarder, pour chaque item que l'owner doit tester. Une phrase, dans le jeu.
WHERE = {
    "hd-models": "Options > Recharged > Enhanced Models, puis regarde Jak, Daxter, Samos et Keira en cinematique",
    "pbr-per-material": "Options > Recharged > PBR Materials, puis regarde le sable, la pierre et le tissu de Sandover",
    "recharged-buildsys": "l'installation elle-meme : telecharge l'APK et l'archive d'assets, installe par-dessus, verifie que tes sauvegardes sont la",
    "framerate-variable": "n'importe ou en jeu : la cadence doit flotter librement et la vitesse du jeu ne doit pas changer",
    "res-picker": "Options > Graphismes > Game Resolution",
    "render-split": "baisse Render Scale a 50 % : le HUD et les menus doivent rester nets",
    "dynamic-renderscale": "Options > Graphismes > Dynamic Render Scale, puis une zone chargee",
    "dynamic-fix": "Options > Graphismes : change Min Render Scale en pleine partie, il doit s'appliquer tout de suite",
    "camera-smooth": "tourne la camera autour de Jak, a l'arret, dans Sandover",
    "camera-interp": "tourne la camera autour de Jak : elle ne doit plus avancer par paliers",
    "options-reorder": "Options > Graphismes : l'ordre des lignes",
    "launcher-collection": "l'ecran d'accueil Android : le nom et l'icone de l'application",
    "touch-menus": "ouvre les options au doigt seulement, sans manette",
    "touch-fix": "dans les options au doigt : les interrupteurs marche/arret et les curseurs",
    "warp-dpad": "devant un teleporteur, choisis la destination au stick",
    "crash-blueeco": "Jungle Interdite, la source d'eco bleue",
    "perf-batching": "Geyser Rock et Sandover : le compteur d'images",
    "perf-particles": "les feux de Rock Village de nuit",
    "perf-particles2": "les memes feux : la geometrie ne doit pas apparaitre/disparaitre et les textures ne doivent pas clignoter",
    "orb-hud-regression": "le compteur d'orbes dans le HUD et dans le menu",
    "eco-spheres": "ramasse de l'eco vert, bleu et rouge : la bulle lumineuse",
    "lang-mixed": "texte en francais, audio en anglais : les invites devant les objets et les PNJ",
    "ndskip": "appuie sur Start pendant le logo Naughty Dog",
    "title-tap": "l'ecran titre : le texte et un tap sur l'ecran",
    "jak2-boot": "lance Jak II",
    "jak2-render": "Jak II : l'ecran titre et le survol de Haven City",
    "jak2-visuals": "Jak II : le titre et la cinematique d'intro",
    "jak1-intermittent-events": "joue normalement : les mini-cinematiques, les plateformes mobiles et les ennemis doivent partir a chaque fois",
    "recharged-grass-object-clip": "le bouton du portail de l'ile de depart, et les decors poses au sol",
    "recharged-grass-wear": "rien a voir : c'est un document de conception, aucun code n'a ete ecrit",
    "recharged-external-assets": "la premiere installation : l'APK est petit et les assets se telechargent a part",
    "recharged-ambient-occlusion": "Options > Recharged > Ambient Occlusion : les creux et les angles de Sandover",
    "recharged-directional-ambient": "Options > Recharged : le relief des zones a l'ombre",
    "recharged-lightprobes": "les interieurs (hutte du Sage Vert) contre l'exterieur",
    "recharged-master-toggle": "Options > Recharged : l'interrupteur global doit tout rendre au jeu d'origine",
    "recharged-bundled-textures": "les sept textures de Sandover que tu as faites",
    "recharged-naming": "le nom des jeux dans le lanceur et dans les menus",
    "recharged-mesh-consolidation": "les coutures sur les personnages et les decors",
    "recharged-mesh-browser": "le navigateur de mesh de debug",
    "touch-longjump-regression": "au tactile : avance + R1/R2 + saut, tu dois partir en long jump",
    "menu-flag-off": "le menu doit etre l'ancien, complet, sans parametre fantome",
    "recharged-managed-assets-merge": "l'installation des assets : coupe-la en cours et relance-la, elle doit reprendre",
    "memory-ceiling-and-crash": "charge une sauvegarde et enchaine trois niveaux : plus de chargement interminable ni de plantage",
    "precompute-deterministic-bake": "le temps de chargement d'un niveau",
    "build-from-scratch": "rien a tester en jeu : c'est la reproductibilite du build",
    "loadgate-crash-regression": "charge ta sauvegarde de Geyser Rock",
    "fixed-tick-interpolation": "Options > Fixed timestep, puis joue autour de 20 images/s",
    "recharged-title-logo-fullres": "l'ecran titre a faible echelle de rendu : le logo Jak and Daxter",
    "recharged-materials-modern-parity": "Options > Recharged : le rendu des matieres",
    "menu-census-cleanup": "Options : les lignes qui ne servent a rien doivent avoir disparu",
    "cutscene-skip": "maintiens Cercle pendant une cinematique",
    "hd-skin-origin-stretch": "loin de Sandover (village3, boss final) : les modeles HD pendant un saut ou un demi-tour",
    "cutscene-npc-flicker": "la premiere cinematique avec le Maire",
    "anim-interp-low-fps": "joue autour de 20 images/s : les animations des personnages",
    "foliage-wind": "les palmiers et les buissons de Sandover, option de brise eteinte PUIS allumee",
    "grass-density-presets": "Options > Recharged > densite d'herbe : cinq paliers",
    "recharged-secondary-motion": "les personnages HD en mouvement brusque",
    "recharged-menu-overhaul": "les menus, du titre aux options",
    "recharged-texture-hotreload": "bascule les textures Recharged en pleine partie, sans redemarrer",
    "recharged-pbr-realtime-fusion": "les matieres PBR avec l'eclairage temps reel allume",
    "recharged-loader-packfix": "la premiere installation sur ton Honor",
    "cine-cut": "les changements de plan d'une cinematique : ils doivent couper, pas glisser",
    "echo-pool": "la cinematique de nouvelle partie, quand Daxter tombe dans l'eco noire",
}

# Le build ou la trouver, quand le jeton le nomme.
BUILD_RE = re.compile(r"(?:on the |on |the )?(v\d+ APK|jak1-buildsys-v1|jak2-alpha1)")
DEFAULT_BUILD = "dernier build publie sur jak-builds"
# Livre avant cette date = sur un build que l'owner n'a plus. On le dit, au lieu de laisser
# croire que ca se teste ce soir.
CURRENT_BUILD_SINCE = "2026-08-20"

# Plafonds d'un essai. Les valeurs de milestones.yaml (jusqu'a 3000 tours et 400 essais)
# faisaient partie du probleme : un essai de 3000 tours est un essai qui a perdu son chemin.
# Pour depasser, il faut une entree ici, avec sa raison, qui part dans `notes`.
DEFAULT_MAX_TURNS = 800
DEFAULT_MAX_RETRIES = 6
BUDGET_OVERRIDE = {}      # item_id -> (max_turns, max_retries, raison)

# La preuve de ces items ne vaut que sur le Redmi : leur ancien validateur exige
# `plateforme=redmi` / le serial. milestones.yaml disait `device: false`, c'est ce que la
# revue du 3 septembre reproche (« aucune porte artefact sur les phases recentes »).
DEVICE_TRUE = {
    "cutscene-npc-flicker": "validators/phase-Gcutscene-npc-flicker.sh exige plateforme=redmi",
    "hd-skin-origin-stretch": "validators/phase-Ghd-skin-origin-stretch.sh exige plateforme=redmi",
    "crate-collision": "validators/phase-Gjak1-crate-collision-2.sh exige le Redmi",
    "pbr-per-material": "validators/phase-Gpbr-props-reach-draw.sh exige le Redmi",
    "loadgate-crash-regression": "validators/phase-Gloadgate-crash-regression.sh exige le Redmi",
    "memory-ceiling-and-crash": "validators/phase-Gmemory-ceiling-and-crash.sh exige le Redmi",
    "recharged-loader-packfix": "validators/phase-Grecharged-loader-packfix.sh exige le Redmi",
    "recharged-pbr-realtime-fusion": "validators/phase-Grecharged-pbr-realtime-fusion.sh exige le Redmi",
    "cutscene-vertical-frame": "validators/phase-Gandroid-window-size.sh exige le Redmi",
}


# Ce que les cycles precedents ont ETABLI, en 3 lignes au plus. Va dans le prompt d'item.
KNOWN_CAUSE = {
    "cutscene-npc-flicker":
        "Le maire porte deja `culled=1` DANS SA PROPRE SCENE pendant que le compteur de "
        "cycles reste a 0 : le culling est range dans une categorie « justifiee » qui ne "
        "compte pas. Les trois portes precedentes ont mesure des scenes ou des acteurs qui "
        "ne sont pas ceux qui clignotent, et la preuve du 02/09 a ete prise sur PC.",
    "hd-skin-origin-stretch":
        "L'etirement vaut (1 - w3) x distance camera-origine : la ligne de translation des "
        "os du PILOTE porte w3 = 0,9982, que `bones-mtx-calc` multiplie par l'origine du "
        "monde en camera. Le correctif `hd-mat-affine!` est ecrit et debrayable. Le residu "
        "Redmi est attribue au squelette du pilote, pas a la chaine HD.",
    "foliage-wind":
        "L'anneau de vent a 48 slots morts sur 64 (index d'ecriture multiplie par "
        "`time-adjust-ratio`, index de lecture brut) : le ressort lit du vide trois images "
        "sur quatre. Le vent TIE est un affaissement lent VOULU ; le defaut du port est le "
        "pas de temps, qui avance par image RENDUE. La vegetation statique se classe par "
        "`TIE_PROTO_NAMES`, jamais par la geometrie.",
    "anim-interp-low-fps":
        "Le facteur d'interpolation n'est lu qu'a UN SEUL endroit du moteur. La porte du "
        "cycle 1 exigeait une mesure au-dessus de 60 img/s et releguait les mesures basses "
        "hors verdict : elle a valide un travail qui ne traitait pas le cas de l'owner, qui "
        "joue vers 20 img/s.",
    "recharged-secondary-motion":
        "Le deficit et l'exces vivent dans DEUX canaux differents (angulaire 9/10 au-dessus, "
        "lineaire centre) : aucun operateur d'amplitude ne ferme les deux. Le plafond d'apex "
        "de §22 ne bornait que translation+rotation et laissait le tenseur libre a 0,59 B0. "
        "Les echelles de forme sont au niveau de l'ORGANE, appliquees par maillon.",
    "recharged-menu-overhaul":
        "La refonte a deja ete livree une fois puis SORTIE des builds par menu-flag-off "
        "(owner 2026-08-04 : parametres inventes, displacement disparu). Elle ne redemarre "
        "qu'apres le recensement du menu et la fermeture du navigateur de mesh (memes fichiers).",
    "recharged-pbr-realtime-fusion":
        "25 rounds archives dans prompts/archive-Grecharged-pbr-realtime-fusion-rounds1-25.md. "
        "La branche rt-lighting du shader ignore encore les cartes PBR ; le chemin autonome "
        "u_pbr_mode est le repli faible. Jamais accepte par l'owner.",
    "recharged-loader-packfix":
        "Le pack de 190 Mo du 27/07 demarrait, ceux de 420 Mo des 28-29/07 mouraient AVANT "
        "l'extraction. Aucun cycle n'a tourne depuis, et les builds actuels demarrent chez "
        "l'owner : verifie d'abord que l'item a encore un objet.",
    "grass-density-presets":
        "Aucun cycle n'a tourne. L'owner a deja tranche la forme : cinq paliers nommes, pas "
        "un curseur continu.",
    "recharged-texture-hotreload": "Aucun cycle n'a tourne sur cet item.",
    "cine-cut":
        "Ouvert en juin, jamais pris. La logique de coupe est partagee avec x86 : le defaut "
        "peut s'y reproduire, ce qui rendrait la preuve possible au clavier.",
    "echo-pool":
        "Ouvert en juin, bloque par l'orchestrateur sans raison enregistree. La mare d'eco "
        "noire n'est pas rendue sur arm64, donc la forme d'ottsel de Daxter apparait trop tot.",
}

DELIVERABLE = {
    "cutscene-npc-flicker":
        "Zero PNJ ecarte du rendu pendant qu'il est dans le champ de la camera, sur la "
        "PREMIERE cinematique du MAIRE, mesure sur le Redmi avec les modeles HD installes, "
        "plus une garde de non-regression qui echoue si le symptome revient.",
    "hd-skin-origin-stretch":
        "`hd-mat-affine!` livre et arme par defaut, zero os etire et zero saut de racine sur "
        "au moins 10 minutes de jeu en mouvement sur le Redmi.",
    "foliage-wind":
        "La brise NATIVE conforme au chemin stock (option eteinte), le pivot des buissons a "
        "leur base, la couverture par instance dessinee complete, et un spectre de brise, "
        "pas une seule frequence.",
    "anim-interp-low-fps":
        "Le jitter reduit AUX DEUX BOUTS (a 30 img/s et moins, et au-dessus de 60), le "
        "comportement a 60 img/s identique au bit.",
    "grass-density-presets":
        "Cinq paliers nommes very low / low / medium / high / very high dans les options, "
        "pre-calcules, avec le cout memoire de chacun.",
}

OUT_OF_SCOPE = {
    "cutscene-npc-flicker":
        "Jak et Daxter ne sont pas concernes : l'owner parle des PNJ. Pas de refonte du "
        "culling general. Aucune capture d'ecran ne vaut preuve.",
    "hd-skin-origin-stretch":
        "Ne touche pas a la chaine de peau stock, ni aux modeles HD eux-memes. Le residu du "
        "squelette pilote se traite ici, pas dans hd-models.",
    "recharged-secondary-motion":
        "Aucune mesure visuelle. Ne rouvre pas les items deja valides (yeux de Daxter, "
        "visiere de Keira, sangle de la veste).",
}

# Dependances reelles, tirees du texte de la phase.
DEPENDS = {
    # « NE DEMARRE PAS avant fermeture de Grecharged-mesh-browser (memes fichiers) » et
    # menu-census-cleanup est declare « prealable a la refonte des menus ».
    "recharged-menu-overhaul": ["recharged-mesh-browser", "menu-census-cleanup"],
}

# gate: {key, op, value} deduit de l'ancien validateur. Jamais invente : chaque entree cite
# la ligne du validateur d'ou elle sort. gate absent => a ecrire (autoport lint le signale).
GATES = {
    "cutscene-npc-flicker": (
        {"key": "npc_culled_in_frustum", "op": "==", "value": 0},
        "validators/phase-Gcutscene-npc-flicker.sh : NPCCULL .*dans_frustum_et_culled=0"),
    "hd-skin-origin-stretch": (
        {"key": "hd_bones_stretched", "op": "==", "value": 0},
        "validators/phase-Ghd-skin-origin-stretch.sh : HDSTRETCHCOUNT os_etires=0 sur >=10 min Redmi"),
    "foliage-wind": (
        {"key": "wind_divergent_pairs", "op": "==", "value": 0},
        "validators/phase-Grecharged-foliage-wind3.sh : WINDPAIRS paires_identiques_divergentes=0"),
}


# --------------------------------------------------------------------------------------
# 3. Lecture des sources
# --------------------------------------------------------------------------------------

def _load_yaml(path):
    try:
        import yaml
    except ImportError:
        sys.exit("PyYAML requis")
    with open(path, encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def git_log():
    """[(date, subject, full)] du plus recent au plus ancien, prefixe [autoport/<id>]."""
    try:
        out = subprocess.run(
            ["git", "-C", REPO, "log", "--format=%x01%ad%x02%s%n%b", "--date=short"],
            capture_output=True, text=True, errors="replace", timeout=300).stdout
    except Exception:
        return {}
    per = {}
    pat = re.compile(r"\[autoport/([^\]]+)\]")
    for chunk in out.split("\x01"):
        if not chunk.strip():
            continue
        try:
            date, rest = chunk.split("\x02", 1)
        except ValueError:
            continue
        subject = rest.split("\n", 1)[0]
        m = pat.search(subject)
        if m:
            per.setdefault(m.group(1), []).append((date.strip(), subject.strip(), rest))
    return per


# --------------------------------------------------------------------------------------
# 4. Extraction des retours de l'owner (verbatim, jamais reformules)
# --------------------------------------------------------------------------------------

Q_GUILL = re.compile("[\u00ab]([^\u00bb]{1,900})[\u00bb]")
Q_DQUOT = re.compile(r'"([^"\n]{10,400})"')
Q_SQUOT = re.compile(r"'([^'\n]{15,400})'")
DATE_RE = re.compile(r"20\d\d-\d\d-\d\d")
CTX_RE = re.compile(r"(?i)(owner|retour|verdict|d[e\u00e9]cision|verbatim|il veut|il dit|"
                    r"playtest|play-test|refus|valid|signal)")
UI_RE = re.compile(r"<[A-Z_]+>|^(Press|Appuie|Appuyer|Utilise|Choisis|Loading)")
BAD_RE = re.compile(r"REOPEN #|\(DEBUG|ogflags:|^[A-Z][a-z]+-[a-z]+ |^G[a-z]+-[a-z]")
# Marques d'instrument : l'owner ne tape ni § ni -> ni des Hz dans le chat.
INSTRUMENT_RE = re.compile(r"[\u00a7]|->|--|\bHz\b|\b[A-Z]{3,}-[A-Z]{3,}\b")
# Un mot-outil francais au moins : sinon ce n'est pas lui qui parle.
FR_STOP = re.compile(r"(?i)\b(le|la|les|un|une|des|du|de|et|est|sont|ce|cette|qui|que|qu|"
                     r"pas|plus|ne|on|je|tu|il|elle|nous|vous|\u00e7a|ca|avec|sans|dans|"
                     r"pour|sur|sous|mais|donc|car|tr\u00e8s|tres|trop|bien|mal|faut|fait|"
                     r"quand|comme|tout|tous|toute|rien|encore|d\u00e9j\u00e0|deja|toujours|"
                     r"jamais|peut|\u00eatre|etre|au|aux|ses|son|sa|mes|ma|mon|notre|leur|"
                     r"beaucoup|vraiment|moins|aussi|alors|puis|l\u00e0|ici|oui|non|ok|"
                     r"j'ai|c'est|n'est|qu'il|d'un|l'|nickel|valid)\b")
EN_ONLY = re.compile(r"(?i)\b(the|and|is|was|were|not|with|from|this|that|have|has|been|does|"
                     r"will|must|should|they|their|which|when|what|but|any|more|than|then|only|"
                     r"also|into|over|after|before|still|again|no|for|are|its|our|you|your|"
                     r"already|because|about|there|here|would|could|each|both|same|other)\b")

# Le jeton owner-ok ne vaut « parole de l'owner » que derriere une de ces formules.
OWNER_MARKER = re.compile(
    r"(OWNER VALIDATED|OWNER-CONFIRMED|OWNER CONFIRMED|owner-confirmed|owner CONFIRMED|"
    r"OWNER PARTIAL-CONFIRM|Owner validation|Owner verbatim|OWNER VERBATIM|"
    r"Ferme par la parole de l['\u2019 ]?owner|L'owner a valid|OWNER-validated|"
    r"OWNER VERIFIED|owner\s+20\d\d-\d\d-\d\d)")
# « Ferme par la parole de l'owner, <date> : <phrase> » — la phrase suit le deux-points,
# sans guillemets, dans les jetons les plus recents.
PAROLE_RE = re.compile(r"Ferme par la parole de l['\u2019 ]?owner,?\s*(?:le\s*)?"
                       r"(20\d\d-\d\d-\d\d)\s*[:,]\s*(.+)", re.S)
# Formules qui retirent explicitement sa valeur au jeton.
DISCLAIM_RE = re.compile(r"(NOT a pass|NOT the owner's final subjective sign-off|VALIDATION FAIBLE)")


def _norm(s):
    """Une citation citee sur plusieurs lignes traine les marques du fichier qui la porte :
    le `#` des scripts et le `>` des blocs markdown. Ce ne sont pas ses mots."""
    s = re.sub(r"\n\s*[#>]+\s?", " ", s)
    s = re.sub(r"\s+[#>]+\s+", " ", s)
    return re.sub(r"\s+", " ", s).strip().strip(" .,;")


def _plausible_owner_quote(q):
    """L'owner ecrit en francais, court, dans le chat. On rejette ce qui ne peut pas etre lui."""
    if len(q) < 20:
        return False
    if q.upper() == q:                       # emphase du superviseur, pas une citation
        return False
    if q[0].isdigit():                       # ligne de mesure recopiee
        return False
    if UI_RE.search(q) or BAD_RE.search(q):  # chaine d'interface / identifiant de phase
        return False
    if len({w.lower() for w in EN_ONLY.findall(q)}) >= 2:   # prose anglaise du superviseur
        return False
    if INSTRUMENT_RE.search(q):              # ligne d'instrument, pas une phrase de chat
        return False
    if not FR_STOP.search(q):                # pas un mot-outil francais : pas lui
        return False
    return True


def harvest_quotes(text, fallback_date, need_ctx=True, patterns=(Q_GUILL,), window=450):
    """[(date, texte)] : chaque citation avec la date la plus proche en amont."""
    found = []
    for pat in patterns:
        for m in pat.finditer(text):
            q = _norm(m.group(1))
            if not _plausible_owner_quote(q):
                continue
            pre = text[max(0, m.start() - window):m.start()]
            # une citation qui occupe sa propre ligne (« … » en tete de ligne, eventuellement
            # apres un tiret ou une puce) est un retour recopie : on la garde sans contexte
            own_line = re.search(r"(?:^|\n)[\s>*\-]*$", text[max(0, m.start() - 12):m.start()])
            if need_ctx and not own_line and not CTX_RE.search(pre):
                continue
            dates = DATE_RE.findall(pre)
            if dates:
                d = dates[-1]
            else:
                nxt = DATE_RE.findall(text[m.end():m.end() + 200])
                d = nxt[0] if nxt else fallback_date
            found.append((d, q, m.start()))
    found.sort(key=lambda t: t[2])
    return [(d, q) for d, q, _ in found]


def token_owner_ok(text):
    """(date, phrase) si le jeton cite VRAIMENT l'owner, sinon None."""
    if DISCLAIM_RE.search(text):
        return None
    m = PAROLE_RE.search(text)
    if m:
        tail = _norm(m.group(2))
        q = Q_GUILL.search(tail)
        phrase = _norm(q.group(1)) if q else tail
        if len(phrase) >= 15:
            return (m.group(1), phrase)
    marks = [m.end() for m in OWNER_MARKER.finditer(text)]
    if not marks:
        return None
    best = None
    for pat in (Q_GUILL, Q_DQUOT, Q_SQUOT):
        for m in pat.finditer(text):
            q = _norm(m.group(1))
            if not _plausible_owner_quote(q):
                continue
            if not any(0 <= m.start() - mk <= 200 for mk in marks):
                continue
            if best is None or m.start() < best[1]:
                best = (q, m.start())
    if best is None:
        return None
    pre = text[:best[1]]
    dates = DATE_RE.findall(pre) or DATE_RE.findall(text)
    return ((dates[-1] if pre and DATE_RE.findall(pre) else (dates[0] if dates else "")), best[0])


def owner_feedback_for(phase_id, milestone_name, commits):
    """Tous les retours dates de l'owner qui concernent cette phase, dedupliques."""
    out = []
    fb_date = ""
    m = re.search(r"owner\s+(20\d\d-\d\d-\d\d)", milestone_name or "")
    if m:
        fb_date = m.group(1)
    else:
        d = DATE_RE.findall(milestone_name or "")
        fb_date = d[0] if d else ""
    if not fb_date and commits:
        fb_date = commits[-1][0]

    # a) le champ name: de milestones.yaml — c'est la ou les clones -2 cachent le vrai retour
    out += harvest_quotes(milestone_name or "", fb_date, need_ctx=False)

    # b) reports/<phase>/owner-defects.txt — la source la plus riche des phases recentes
    # reports/<phase>/owner-defects.txt n'existe que pour porter ses defauts : tout ce qui
    # y est entre guillemets est de lui, on ne demande pas de contexte.
    od = os.path.join(REPORTS, phase_id, "owner-defects.txt")
    if os.path.exists(od):
        with open(od, encoding="utf-8", errors="replace") as fh:
            out += harvest_quotes(fh.read(), fb_date, need_ctx=False)

    # c) le prompt de la phase. Le bloc « OWNER (date) » qui introduit une citation est
    #    parfois loin au-dessus d'elle : on prend une fenetre large plutot que de perdre
    #    un retour. Les filtres de forme (majuscules, chaine d'interface, prose anglaise)
    #    font le tri.
    pr = os.path.join(PROMPTS, "phase-%s.md" % phase_id)
    if os.path.exists(pr):
        with open(pr, encoding="utf-8", errors="replace") as fh:
            out += harvest_quotes(fh.read(), fb_date, window=2500)

    # d) les sujets de commit de la phase (le sujet doit nommer l'owner, sinon c'est le
    #    superviseur qui se cite lui-meme)
    for date, subject, _full in commits:
        out += [(date, q) for d, q in harvest_quotes(subject, date, need_ctx=True,
                                                     window=80)]

    # e) le jeton owner-ok
    tk = os.path.join(OWNER_OK, phase_id)
    if os.path.exists(tk):
        with open(tk, encoding="utf-8", errors="replace") as fh:
            out += harvest_quotes(fh.read(), fb_date, need_ctx=False,
                                  patterns=(Q_GUILL, Q_DQUOT, Q_SQUOT))

    return dedup_feedback([{"date": d, "text": q} for d, q in out])


def dedup_feedback(entries):
    """Deduplique par inclusion : « A » et « ...A... » sont le meme retour, on garde le long."""
    keyed = [(re.sub(r"[^a-z0-9]", "", e["text"].lower()), e) for e in entries]
    keyed.sort(key=lambda t: -len(t[0]))
    kept = []
    for k, e in keyed:
        if not k:
            continue
        core = k[len(k) // 4:len(k) // 4 + 45] or k     # 45 caracteres consecutifs du milieu
        if any(k in kk or core in kk for kk, _ in kept):
            continue
        kept.append((k, e))
    ded = [e for _, e in kept]
    ded.sort(key=lambda e: (e["date"], e["text"]))
    return ded


# --------------------------------------------------------------------------------------
# 5. Construction des items
# --------------------------------------------------------------------------------------

def slug(phase_id):
    s = phase_id
    if re.match(r"^G[a-z]", s):
        s = s[1:]
    s = s.replace("Grecharged-", "recharged-").replace("Gjak", "jak")
    s = re.sub(r"[^A-Za-z0-9]+", "-", s).strip("-").lower()
    return s


def short_feature(name):
    """Libelle de repli pour les items archives : la premiere idee du champ name:."""
    n = re.sub(r"\s+", " ", name or "").strip()
    n = re.sub(r"^(OWNER[^:]{0,40}:|PILLAR P\d\s*:|RECHARGED\s*\(?[^)]{0,60}\)?:)\s*", "", n)
    n = re.split(r"(?<=[a-z\)\u00e9])\.\s|\s—\s|\s\u2014\s|\s:\s", n)[0]
    n = n.strip(" .;,")
    return (n[:118] + "\u2026") if len(n) > 120 else (n or "(sans libelle)")


def build(args):
    ms = _load_yaml(MILESTONES)
    phases = ms["phases"]
    by_id = OrderedDict((p["id"], p) for p in phases)
    order = {p["id"]: i for i, p in enumerate(phases)}
    st = json.load(open(STATE, encoding="utf-8"))
    completed = set(st.get("completed", []))
    blocked = set(st.get("blocked", []))
    parked = dict(st.get("parked", {}))
    commits = git_log()

    tokens = {}
    for fn in sorted(os.listdir(OWNER_OK)):
        if fn == "README.txt":
            continue
        with open(os.path.join(OWNER_OK, fn), encoding="utf-8", errors="replace") as fh:
            tokens[fn] = fh.read()
    # owner-ok/Gfont-urbanist.CASSE-2026-09-02 : jeton renomme, il vaut pour Gfont-urbanist
    for fn in list(tokens):
        base = fn.split(".")[0]
        if base != fn and base in by_id and base not in tokens:
            tokens[base] = tokens[fn]

    # --- groupes ---------------------------------------------------------------------
    groups = []          # (item_id, [phase ids], evidence|None, era_feature|None)
    claimed = set()
    for iid, ids, evidence in FAMILIES:
        missing = [x for x in ids if x not in by_id]
        if missing:
            sys.exit("famille %s : phases inconnues %s" % (iid, missing))
        groups.append((iid, ids, evidence, None))
        claimed.update(ids)
    for iid, feat, ids in ERAS:
        missing = [x for x in ids if x not in by_id]
        if missing:
            sys.exit("epoque %s : phases inconnues %s" % (iid, missing))
        groups.append((iid, ids, "regroupement d'epoque : portage arm64/Android de mai-juin, "
                                 "aucun jeton owner, aucune feature a re-tester", feat))
        claimed.update(ids)
    for p in phases:
        if p["id"] not in claimed:
            groups.append((slug(p["id"]), [p["id"]], None, None))
    groups.append(("audits-abandonnes",
                   [], "ids bloques presents dans state.json mais absents de milestones.yaml",
                   "Audits de juin abandonnes (pixel-match du menu, images anglaises de reference)"))

    items = []
    for iid, ids, evidence, era_feature in groups:
        if iid == "audits-abandonnes":
            items.append(make_orphan_item(iid, era_feature, evidence, commits))
            continue
        items.append(make_item(iid, ids, evidence, era_feature, by_id, order, completed,
                               blocked, parked, tokens, commits))

    # --- controle : aucune phase perdue ----------------------------------------------
    covered = [pid for it in items for pid in it["history"]]
    assert len(covered) == len(set(covered)), "une phase apparait dans deux items"
    manque = set(by_id) - set(covered)
    assert not manque, "phases perdues par la migration : %s" % sorted(manque)
    assert len([c for c in covered if c in by_id]) == len(by_id), \
        "attendu %d phases couvertes, obtenu %d" % (len(by_id), len(covered))

    # --- priorites --------------------------------------------------------------------
    prioritise(items)

    doc = {"version": 1, "items": items}
    if args.dry_run:
        summarise(items)
        return doc
    write_yaml(doc, args.out)
    sys.path.insert(0, AP)
    from lib import backlog as bl
    written = [bl.write_prompt(it, AP) for it in items if it["status"] == "open"]
    print("%d prompts d'item ecrits (prompts/item-*.md)" % len(written))
    summarise(items)
    print("\n%d items ecrits dans %s (%d phases couvertes)" %
          (len(items), args.out, len([c for c in covered if c in by_id])))
    return doc


def make_orphan_item(iid, feature, evidence, commits):
    hist = list(ORPHAN_BLOCKED)
    fb = []
    for pid in hist:
        fb += owner_feedback_for(pid, "", commits.get(pid, []))
    return {
        "id": iid, "feature": feature, "status": "archived", "priority": None,
        "owner_feedback": fb, "gate": None, "game": "jak1",
        "max_turns": DEFAULT_MAX_TURNS, "max_retries": DEFAULT_MAX_RETRIES, "depends_on": [],
        "history": hist, "prompt": None, "owner_ok": None,
        "notes": evidence,
    }


def make_item(iid, ids, evidence, era_feature, by_id, order, completed, blocked, parked,
              tokens, commits):
    last = ids[-1]   # l'ordre declare dans FAMILIES/ERAS est chronologique, on ne retrie pas
    lastp = by_id[last]

    # --- retours de l'owner, tous les membres, dedupliques ---------------------------
    fb = []
    for pid in ids:
        fb += owner_feedback_for(pid, by_id[pid]["name"], commits.get(pid, []))
    fb = dedup_feedback(fb)

    # --- statut ----------------------------------------------------------------------
    owner_ok = None
    for pid in reversed(ids):
        tok = tokens.get(pid)
        if tok is None:
            continue
        got = token_owner_ok(tok)
        if got:
            owner_ok = {"date": got[0], "text": got[1], "build_sha": None,
                        "source": "owner-ok/%s" % pid}
            break

    has_token = any(pid in tokens for pid in ids)
    lastc = commits.get(last, [])
    last_subject_full = lastc[0][2] if lastc else ""
    says_not_done = bool(re.search(r"NOT done|AWAITING OWNER PLAY-TEST", last_subject_full, re.I))
    is_parked_awaiting = last in parked and "PAROLE" in (parked.get(last) or "").upper()
    owner_verify = bool(lastp.get("owner_verify"))
    era = era_feature is not None

    if owner_ok:
        status = "validated"
    elif era:
        status = "archived"
    elif last in blocked:
        status = "blocked"
    elif last in completed or last in parked:
        if has_token or says_not_done or is_parked_awaiting or owner_verify:
            status = "to-test"
        else:
            status = "archived"
    else:
        status = "open"

    forced = STATUS_OVERRIDE.get(iid)
    note = evidence
    if forced:
        status, why = forced
        note = ("%s | " % evidence if evidence else "") + "statut force : " + why
        if status != "validated":
            owner_ok = None

    ok_over = OWNER_OK_OVERRIDE.get(iid)
    if ok_over:
        owner_ok = {"date": ok_over["date"], "text": ok_over["text"],
                    "build_sha": None, "source": ok_over["source"]}

    # --- feature ---------------------------------------------------------------------
    feature = FEATURE.get(iid) or era_feature or short_feature(lastp["name"])

    budget = BUDGET_OVERRIDE.get(iid)
    if budget:
        note = (note + " | " if note else "") + "budget : " + budget[2]

    gate, gate_src = GATES.get(iid, (None, None))
    if gate_src:
        note = (note + " | " if note else "") + "gate deduit de " + gate_src

    item = {
        "id": iid,
        "feature": feature,
        "status": status,
        "priority": None,
        "owner_feedback": fb,
        "gate": gate,
        "game": "jak2" if last.startswith("Gjak2") else "jak1",
        "max_turns": DEFAULT_MAX_TURNS,
        "max_retries": DEFAULT_MAX_RETRIES,
        "depends_on": DEPENDS.get(iid, []),
        "history": ids,
        "prompt": None,
        "owner_ok": owner_ok,
    }
    # `device` dit ou la PREUVE se prend : il n'a de sens que sur un item que le harnais
    # peut encore travailler. Pour un `to-test`, c'est `where` et `build` qui disent a
    # l'owner ou aller voir.
    if status in ("open", "in-progress", "blocked"):
        item["device"] = bool(lastp.get("device")) or iid in DEVICE_TRUE
        if iid in DEVICE_TRUE and not lastp.get("device"):
            note = (note + " | " if note else "") + "device force a true : " + DEVICE_TRUE[iid]
    if status in ("to-test", "open"):
        w = WHERE.get(iid)
        if w:
            item["where"] = w
    if budget:
        item["max_turns"], item["max_retries"] = budget[0], budget[1]
    if status == "to-test":
        # quand la feature a ete livree : dernier commit de la derniere phase, sinon la
        # date du jeton, sinon le dernier retour de l'owner
        delivered = lastc[0][0] if lastc else ""
        if not delivered and owner_ok:
            delivered = owner_ok.get("date", "")
        if not delivered and fb:
            delivered = fb[-1]["date"]
        if delivered:
            item["delivered"] = delivered
        build = ""
        for pid in reversed(ids):
            m = BUILD_RE.search(tokens.get(pid, ""))
            if m:
                build = m.group(1)
                break
        if not build:
            build = (DEFAULT_BUILD if delivered >= CURRENT_BUILD_SINCE
                     else "build du %s, remplace depuis" % (delivered or "l'epoque"))
        item["build"] = build
    if note:
        item["notes"] = note
    if status == "blocked":
        item["block_reason"] = (forced[1] if forced else
                                "bloquee par l'orchestrateur, aucune raison enregistree dans "
                                "state.json ; a trancher par l'owner : rouvrir ou archiver")
    if status == "open":
        item["prompt"] = "prompts/item-%s.md" % iid
        for key, table in (("known_cause", KNOWN_CAUSE), ("deliverable", DELIVERABLE),
                           ("out_of_scope", OUT_OF_SCOPE)):
            if iid in table:
                item[key] = table[iid]
    return item


def prioritise(items):
    def last_date(it):
        return it["owner_feedback"][-1]["date"] if it["owner_feedback"] else ""

    def regression(it):
        blob = (it["feature"] + " " + " ".join(e["text"] for e in it["owner_feedback"])).lower()
        return bool(re.search(r"regress|est revenu|c'est revenu|revenu !|cass\u00e9e|cassee", blob))

    act = [it for it in items if it["status"] in ("open", "in-progress", "to-test", "blocked")]
    a = [it for it in act if last_date(it) >= RECENT_CUTOFF]
    rest = [it for it in act if it not in a]
    b = [it for it in rest if regression(it)]
    c = [it for it in rest if it not in b]
    for base, bucket in ((10, a), (100, b), (200, c)):
        bucket.sort(key=lambda it: (last_date(it), it["id"]), reverse=True)
        bucket.sort(key=lambda it: HEAD_ORDER.index(it["id"])
                    if it["id"] in HEAD_ORDER else len(HEAD_ORDER))
        for i, it in enumerate(bucket):
            it["priority"] = base + i


def write_yaml(doc, path):
    import yaml

    class D(yaml.SafeDumper):
        pass

    def rep_str(dumper, data):
        style = "|" if "\n" in data else None
        return dumper.represent_scalar("tag:yaml.org,2002:str", data, style=style)

    D.add_representer(str, rep_str)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write("# Genere par tools/migrate_backlog.py depuis milestones.yaml + state.json +\n"
                 "# owner-ok/ + prompts/ + reports/*/owner-defects.txt + git log. Rejouable.\n"
                 "# Les blocs owner_feedback sont les mots de l'owner, jamais reformules.\n")
        yaml.dump(doc, fh, Dumper=D, allow_unicode=True, sort_keys=False, width=100)
    os.replace(tmp, path)


def summarise(items):
    from collections import Counter
    c = Counter(it["status"] for it in items)
    print("items par statut :")
    for k in ("open", "in-progress", "to-test", "validated", "blocked", "archived"):
        print("  %-12s %d" % (k, c.get(k, 0)))
    print("total items        %d" % len(items))
    print("retours d'owner    %d" % sum(len(it["owner_feedback"]) for it in items))
    nog = [it["id"] for it in items
           if it["status"] in ("open", "in-progress", "to-test", "blocked") and not it["gate"]]
    dev = [it["id"] for it in items if it.get("device") and not it["gate"]]
    print("sans critere machine     %d (dont %d en device: true, refuses par lint)"
          % (len(nog), len(dev)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--dry-run", action="store_true")
    build(ap.parse_args())


if __name__ == "__main__":
    main()
