#pragma once

// A55-RSS — RECENSEMENT DE LA MEMOIRE RESIDENTE DU PROCESSUS, A UN INSTANT NOMME.
//
// NATURE de la grandeur : octets RESIDENTS (`Rss:` de /proc/self/smaps), sommes par FAMILLE
// de mapping, plus le total VmRSS/VmSize de /proc/self/status et les octets vivants de
// l'allocateur (`mallinfo().uordblks`). Ce n'est PAS une mesure de notre seul tas : sur un
// appareil a memoire unifiee (Adreno, Tegra) le pilote GPU prend sa memoire dans la meme RAM,
// donc un gros bloc peut venir de nous OU de lui — c'est precisement ce que la famille `gpu`
// sert a trancher.
// REPERE : le processus entier.
// LIGNE DE BASE : le meme label a l'appel precedent — l'information est le DELTA entre deux
// marqueurs, pas la valeur absolue.
//
// Pose : 2026-08-26, phase Gmemory-ceiling-and-crash, pour nommer DEUX blocs de 157 626 368
// octets, 100 % residents, apparus pendant l'initialisation du renderer et jamais rendus.
// RESOLU par ce marqueur : 157 625 280 = 2 462 895 x sizeof(MercVertex) — le pool de sommets
// merc du GAME.fr3 des modeles HD, une fois en RAM (le vecteur deserialise) et une fois dans
// le GPU (`A55-RSS merc-bufdata gpu=+152Mo`). Sur un allocateur qui nomme ses gros blocs
// (scudo) on voyait les deux ; sur celui du Redmi (arene unique `libc_malloc`) on ne voyait
// que la copie GPU, d'ou « deux blocs sur un appareil, un sur l'autre ».
//
// En-tete seul, aucune modification du systeme de construction.

#include <cstdio>
#include <cstdlib>
#include <cstring>

#if defined(__ANDROID__) || defined(__GLIBC__)
#include <malloc.h>
#endif

namespace rss_census {

// Seuil au-dessus duquel un mapping est nomme individuellement (octets).
constexpr unsigned long long kBigMappingBytes = 32ull * 1024 * 1024;

// Imprime une ligne `A55-RSS <label> rss=... vsz=... gros=<n> [taille@adresse ...]`.
// Cout : une lecture de /proc/self/maps (quelques ms). A n'appeler qu'aux
// etapes NOMMEES du demarrage et des chargements, jamais par frame.
inline void mark(const char* label) {
#if defined(__linux__)
  unsigned long long rss_kb = 0, vsz_kb = 0;
  if (FILE* st = fopen("/proc/self/status", "r")) {
    char line[256];
    while (fgets(line, sizeof(line), st)) {
      if (!strncmp(line, "VmRSS:", 6)) rss_kb = strtoull(line + 6, nullptr, 10);
      else if (!strncmp(line, "VmSize:", 7)) vsz_kb = strtoull(line + 7, nullptr, 10);
    }
    fclose(st);
  }
  // FAMILLES, EN RESIDENCE. `/proc/self/maps` ne donne que la taille MAPPEE, et sur ce
  // processus l'ecart est enorme (une arene de 963 Mo mappes pour 522 Mo residents, des
  // centaines de tampons GPU mappes non residents) : lire la taille mappee revient a
  // confondre une reservation avec de la memoire occupee. On lit donc `/proc/self/smaps`,
  // qui donne `Rss:` PAR MAPPING, et on somme par famille :
  //   gpu     = /dev/kgsl-3d0 (Adreno) et /dev/nv* — memoire GPU, prise dans la RAM systeme
  //             sur un appareil a memoire unifiee, donc bien dans le RSS du processus ;
  //   tas     = [anon:libc_malloc] / [anon:scudo:*] — notre C++ ;
  //   ee      = la memoire principale EE de GOAL (l'unique mapping rwxp) ;
  //   dalvik  = la machine virtuelle Android ;
  //   fichier = tout mapping adosse a un fichier (.so, .jar, .apk, .art) ;
  //   anon    = le reste (piles de threads, tampons anonymes).
  // NATURE : octets RESIDENTS. REPERE : le processus entier. LIGNE DE BASE : le meme label
  // au marqueur precedent — l'information est le DELTA.
  // COUT : une lecture de /proc/self/smaps (quelques milliers de lignes, ~10-20 ms). A
  // n'appeler qu'aux etapes NOMMEES du demarrage et des chargements, jamais par frame.
  unsigned long long r_gpu = 0, r_heap = 0, r_ee = 0, r_dalvik = 0, r_file = 0, r_anon = 0;
  char big[640];
  big[0] = '\0';
  int nbig = 0;
  if (FILE* mp = fopen("/proc/self/smaps", "r")) {
    char line[512];
    int fam = 5;  // 0 gpu, 1 tas, 2 ee, 3 dalvik, 4 fichier, 5 anon
    unsigned long long cur_lo = 0, cur_sz = 0;
    while (fgets(line, sizeof(line), mp)) {
      unsigned long long lo = 0, hi = 0;
      if (sscanf(line, "%llx-%llx", &lo, &hi) == 2 && strchr(line, ' ')) {
        cur_lo = lo;
        cur_sz = hi - lo;
        if (strstr(line, "kgsl") || strstr(line, "/dev/nv")) fam = 0;
        else if (strstr(line, "libc_malloc") || strstr(line, "[anon:scudo:")) fam = 1;
        else if (strstr(line, "[anon:dalvik")) fam = 3;
        else if (strstr(line, "rwxp") && cur_sz >= 64ull * 1024 * 1024) fam = 2;
        else if (strstr(line, " /")) fam = 4;
        else fam = 5;
        continue;
      }
      if (strncmp(line, "Rss:", 4)) continue;
      const unsigned long long rss = strtoull(line + 4, nullptr, 10) * 1024ull;
      switch (fam) {
        case 0: r_gpu += rss; break;
        case 1: r_heap += rss; break;
        case 2: r_ee += rss; break;
        case 3: r_dalvik += rss; break;
        case 4: r_file += rss; break;
        default: r_anon += rss; break;
      }
      if (rss >= kBigMappingBytes) {
        static const char* kFam[] = {"gpu", "tas", "ee", "dalvik", "fichier", "anon"};
        ++nbig;
        char one[80];
        snprintf(one, sizeof(one), " %lluMo/%s@%llx", rss >> 20, kFam[fam], cur_lo);
        if (strlen(big) + strlen(one) + 1 < sizeof(big)) strcat(big, one);
      }
    }
    fclose(mp);
  }
  // Octets REELLEMENT alloues et non rendus (`uordblks`), pour separer « on tient vraiment
  // cette memoire » de « l'allocateur ne l'a pas rendue au systeme ». Sans ce chiffre, un tas
  // resident de 522 Mo ne dit pas s'il faut chercher une allocation ou regler l'allocateur.
  unsigned long long live_mo = 0;
#if defined(__ANDROID__) || defined(__GLIBC__)
  {
    struct mallinfo mi = mallinfo();
    live_mo = ((unsigned long long)(unsigned)mi.uordblks) >> 20;
  }
#endif
  fprintf(stderr,
          "A55-RSS %s rss=%lluMo vsz=%lluMo R:gpu=%lluMo tas=%lluMo ee=%lluMo dalvik=%lluMo "
          "fichier=%lluMo anon=%lluMo vif=%lluMo gros=%d%s\n",
          label, rss_kb / 1024, vsz_kb / 1024, r_gpu >> 20, r_heap >> 20, r_ee >> 20,
          r_dalvik >> 20, r_file >> 20, r_anon >> 20, live_mo, nbig, big);
  fflush(stderr);
#else
  (void)label;
#endif
}

}  // namespace rss_census
