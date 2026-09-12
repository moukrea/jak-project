"""lib/freshness.py — LE SEUL COMPARATEUR DE FRAICHEUR DU HARNAIS (cote python).

Jumeau de `lib/freshness.sh`, et pour la meme raison
(`harness-subsecond-freshness-is-blind`, 2026-09-12) : trois comparaisons de fraicheur du
harnais lisaient leurs deux cotes a la SECONDE ENTIERE et acceptaient l'EGALITE comme une
preuve de fraicheur. Les deux erreurs vont du cote PERMISSIF — elles declarent frais un
artefact perime — et une fraicheur fausse est le defaut le plus cher du projet : une preuve
qui decrit un autre binaire que celui qu'on croit.

LES DEUX REGLES :

  1. LA MEME RESOLUTION DES DEUX COTES. `resolution()` rend la resolution EFFECTIVEMENT lue
     d'une valeur, pour qu'une troncature d'un seul cote se COMPTE au lieu de se deviner.

  2. L'EGALITE NE VAUT PAS FRAICHEUR. A horodatage egal, rien ne dit lequel des deux a ete
     ecrit en premier : le verdict est DOUTEUX, et l'appelant refuse.

LE CAS DE L'APPAREIL EST PARTICULIER, ET C'EST LUI QUI A MOTIVE LA REGLE 2. Sur le telephone
les DEUX cotes sont a la seconde entiere et le resteront : le `stat` de toybox n'a pas de
`%.9Y`, et `date` n'y rend que des secondes. La resolution y est donc SYMETRIQUE — la regle 1
est tenue — mais GROSSIERE : la fenetre d'ambiguite fait une seconde pleine, pas 300 us. C'est
exactement la ou l'egalite ne peut pas valoir fraicheur, et c'est pour ca que
`classer_artefacts` rend DEUX listes au lieu d'une.
"""

FRAIS = "frais"
PERIME = "perime"
DOUTEUX = "douteux"

# Ce que l'appareil sait rendre, des deux cotes. Publie plutot que suppose : le jour ou toybox
# apprend la sous-seconde, c'est cette constante qui doit changer, et elle est LUE par le banc.
RESOLUTION_APPAREIL = "s"


def ns_de(valeur) -> int:
    """`1789236416.611605185` ou `1789236416,6116051850` -> nanosecondes entieres.

    La fraction est completee OU TRONQUEE a neuf chiffres : GNU `find -printf %T@` en rend dix
    (un zero de remplissage en queue) et les prendre tels quels decalerait tout d'un facteur dix.
    La virgule est acceptee : `stat -c %.9Y` suit la locale.
    """
    if isinstance(valeur, int):
        return valeur * 1_000_000_000
    texte = str(valeur).strip().replace(",", ".")
    if not texte:
        return 0
    entier, _, frac = texte.partition(".")
    if not entier.isdigit() or (frac and not frac.isdigit()):
        return 0
    return int(entier) * 1_000_000_000 + int((frac + "000000000")[:9])


def mtime_ns(chemin) -> int:
    import os
    try:
        return os.stat(chemin).st_mtime_ns
    except OSError:
        return 0


def resolution(ns: int) -> str:
    """`ns` si la sous-seconde porte de l'information, `s` si elle est nulle.

    Une sous-seconde nulle est soit un horodatage tombe pile sur la seconde (1 chance sur 1e9),
    soit — et c'est le cas qui nous occupe — QUELQU'UN QUI L'A TRONQUEE.
    """
    if not ns:
        return "absent"
    return "s" if ns % 1_000_000_000 == 0 else "ns"


def verdict(artefact_ns: int, source_ns: int) -> str:
    """STRICTEMENT plus recent = frais. Egal = DOUTEUX. L'appelant refuse le douteux."""
    if artefact_ns > source_ns:
        return FRAIS
    if artefact_ns < source_ns:
        return PERIME
    return DOUTEUX


def classer_artefacts(stat_out: str, t0: int):
    """La sortie d'un `stat -c "%Y %n"` d'appareil, triee contre `t0` (secondes entieres).

    Rend `(frais, douteux)` : les artefacts STRICTEMENT posterieurs a `t0`, et ceux qui portent
    EXACTEMENT `t0`. Un artefact ecrit 0,9 s AVANT `t0` porte le meme entier que lui : le
    declarer frais, c'est accepter comme preuve d'une course un fichier de la course d'avant.
    Les lignes illisibles sont ignorees — elles ne peuvent rien prouver, dans aucun sens.
    """
    frais, douteux = [], []
    for ligne in (stat_out or "").splitlines():
        morceaux = ligne.split(None, 1)
        if len(morceaux) != 2 or not morceaux[0].strip().isdigit():
            continue
        nom = morceaux[1].strip()
        v = verdict(int(morceaux[0]) * 1_000_000_000, int(t0) * 1_000_000_000)
        if v == FRAIS:
            frais.append(nom)
        elif v == DOUTEUX:
            douteux.append(nom)
    return frais, douteux
