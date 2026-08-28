#!/usr/bin/env python3
"""Gandroid-window-size — capture de la FENETRE x86 du jeu, par son nom X11.

CE QUE CETTE MESURE EST (les trois questions du contrat) :
  NATURE  — une IMAGE, la surface CLIENTE de la fenetre du jeu, celle dans laquelle
            le renderer compose. C'est la meme surface que `framebuffer-width/height`
            decrit cote GOAL : ce que le compositeur laisse noir sur ses bords EST la
            bande. On ne capture ni l'ecran entier ni les decorations du gestionnaire
            de fenetres : leurs pixels ne sont pas ceux du jeu et fausseraient le compte.
  REPERE  — pixels de la fenetre, origine en haut a gauche de la zone cliente.
  QUAND LE DEFAUT EST ABSENT — 0 colonne et 0 ligne noires aux quatre bords, avec un
            interieur eclaire (sinon l'image est VIDE et ne compte pas ; c'est
            gaw_bars.py qui tranche ca, pas ce fichier).

Deux chemins, dans cet ordre, et le rapport DIT lequel a servi :
  1. XGetImage sur la fenetre elle-meme (lit le pixmap de redirection : marche meme si
     la fenetre est partiellement couverte) ;
  2. repli : capture de la RACINE puis decoupe au rectangle absolu de la fenetre.
"""
import sys
import struct
from Xlib import display, X


def find_window(dpy, name):
    root = dpy.screen().root
    out = []

    def walk(w, depth=0):
        try:
            wm = w.get_wm_name()
        except Exception:
            wm = None
        try:
            g = w.get_geometry()
        except Exception:
            return
        if wm and name.lower() in str(wm).lower() and g.width > 100 and g.height > 100:
            out.append((w, g))
        try:
            for c in w.query_tree().children:
                walk(c, depth + 1)
        except Exception:
            pass

    walk(root)
    return out


def abs_pos(dpy, win):
    root = dpy.screen().root
    t = win.translate_coords(root, 0, 0)
    # translate_coords gives the offset of root's origin in win coords -> negate
    return -t.x, -t.y


def grab(win, g, out_path, mode):
    from PIL import Image
    if mode == "win":
        raw = win.get_image(0, 0, g.width, g.height, X.ZPixmap, 0xFFFFFFFF)
        data = raw.data
        if isinstance(data, str):
            data = data.encode("latin-1")
        im = Image.frombytes("RGB", (g.width, g.height), data, "raw", "BGRX")
    else:
        raise ValueError(mode)
    im.save(out_path)
    return im.size


def main():
    name = sys.argv[1]
    out = sys.argv[2]
    dpy = display.Display()
    cands = find_window(dpy, name)
    if not cands:
        print("GAW-GRAB ERREUR aucune fenetre nommee '%s'" % name)
        return 2
    # ATTENTION : le gestionnaire de fenetres REPARENTE la fenetre du jeu dans un
    # cadre qui porte le meme WM_NAME. Prendre la plus GRANDE prend le cadre, et ses
    # bordures/ombres sont comptees comme des bandes noires (mesure du 2026-08-28 :
    # cadre 1330x807 pour une fenetre demandee a 1280x720 -> 25 px "de bande" aux
    # QUATRE bords, qui n'appartiennent pas au jeu). On veut la surface CLIENTE :
    # celle qui vaut exactement la taille demandee, sinon la PLUS PETITE.
    want = None
    if len(sys.argv) > 4:
        want = (int(sys.argv[3]), int(sys.argv[4]))
    exact = [c for c in cands if want and (c[1].width, c[1].height) == want]
    if exact:
        win, g = exact[0]
    else:
        win, g = min(cands, key=lambda t: t[1].width * t[1].height)
    x, y = abs_pos(dpy, win)
    try:
        size = grab(win, g, out, "win")
        print("GAW-GRAB voie=xgetimage fenetre=%dx%d position=%d,%d candidats=%d "
              "exact=%s fichier=%s taille=%dx%d"
              % (g.width, g.height, x, y, len(cands), bool(exact), out, size[0], size[1]))
        return 0
    except Exception as e:
        print("GAW-GRAB xgetimage ECHEC (%s) -> repli racine, rect %dx%d+%d+%d"
              % (e, g.width, g.height, x, y))
        print("GAW-GRAB-RECT %d %d %d %d" % (g.width, g.height, x, y))
        return 3


if __name__ == "__main__":
    sys.exit(main())
