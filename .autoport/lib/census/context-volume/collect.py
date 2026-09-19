#!/usr/bin/env python3
"""OU PART LE VOLUME DE CONTEXTE DE L'AGENT PRINCIPAL — mesure sur nos propres journaux.

LA GRANDEUR. Pour un tour d'API, `cache_read + cache_creation + input` EST la taille du
contexte relu a ce tour : c'est l'API qui la publie, pas une estimation. Sa somme sur les tours
d'un essai est l'INTEGRALE DE CONTEXTE — les 20,7 M de jetons par essai de l'etude du 19/09.

CE QUI LA FAIT. Un bloc ajoute au tour k est relu par les N-k tours suivants : son cout est
taille x (N-k). C'est la MULTIPLICATION qui fait le volume, pas la taille d'un resultat pris
isolement. C'est pourquoi tronquer les gros resultats ne paie presque rien (mesure ci-dessous)
alors que supprimer des TOURS paie beaucoup.

TROIS PIEGES MESURES, PAS SUPPOSES :
  1. Le meme `message.id` est republie 3 a 5 fois par le flux, et chaque republication ne porte
     qu'UN bloc de contenu. Garder la premiere ligne perd le `tool_use` : l'attribution
     accusait alors « aucun outil » a 85 %.
  2. `usage.output_tokens` des lignes `assistant` est un ACOMPTE (FINDINGS 19/09). On ne s'en
     sert jamais.
  3. Le texte de REFLEXION est expurge des journaux (`thinking` vide, signature seule). Son
     volume se lit sur les evenements `system/thinking_tokens`, et il pese 26 % de l'integrale :
     l'ignorer faisait porter sa masse aux resultats d'outil.

L'ALLOCATION. On ne convertit jamais des caracteres en jetons pour faire un total : on repartit
l'ECART DE CONTEXTE MESURE entre les blocs du tour, au prorata de leur poids estime. Le facteur
chars/jeton s'annule donc dans les parts publiees.

Sortie : des lignes `cle=valeur` sans espace, moissonnables par `lib/proof_run.sh`.
"""
import json, os, re, sys, glob, statistics as st
from collections import Counter

CH = 3.5                      # chars par jeton (s'annule : l'allocation est proportionnelle)
REF_MODEL = 'claude-opus-5'   # le panel de reference de l'etude : 278 essais, 17,25 $/essai
ARM_FLAG = '--strict-mcp-config'

RX_SLEEP = re.compile(r'(?<![\w-])sleep\s+(\d+(?:\.\d+)?)')
RX_TAIL  = re.compile(r'\btail\b.*\.(log|txt|out)|\btail -f\b', re.I)
RX_PS    = re.compile(r'\b(pgrep|pidof|ps -|kill -0)\b')
RX_LOOP  = re.compile(r'\b(while|until|for)\b')


def _lire(path):
    """-> (modele, arme, tours) ; tours = liste de dict, un par tour de l'agent principal."""
    rows, seen, model, armed, cost = [], set(), '', None, None
    think, pend = 0, []
    with open(path, encoding='utf-8', errors='replace') as fh:
        for ln in fh:
            ln = ln.strip()
            if not ln.startswith('{'):
                continue
            try:
                d = json.loads(ln)
            except Exception:
                continue
            t = d.get('type') or d.get('event')
            if t in ('phase_start', 'attempt_start'):
                model = d.get('model') or model
                cmd = d.get('cmd')
                if isinstance(cmd, list):
                    armed = ARM_FLAG in cmd
                continue
            if t == 'system' and d.get('subtype') == 'thinking_tokens':
                think = max(think, d.get('estimated_tokens') or 0)
                continue
            if t == 'result':
                cost = d.get('total_cost_usd', cost)
                continue
            if d.get('parent_tool_use_id'):
                continue                      # tour de sous-agent : ce n'est pas ce contexte-ci
            if t == 'user':
                for c in d.get('message', {}).get('content') or []:
                    if isinstance(c, dict) and c.get('type') == 'tool_result':
                        pend.append(len(json.dumps(c.get('content'), ensure_ascii=False)))
                continue
            if t != 'assistant':
                continue
            m = d.get('message') or {}
            mid = m.get('id')
            if not mid:
                continue
            if mid not in seen:
                seen.add(mid)
                u = m.get('usage') or {}
                rows.append(dict(
                    ctx=(u.get('cache_read_input_tokens') or 0)
                        + (u.get('cache_creation_input_tokens') or 0)
                        + (u.get('input_tokens') or 0),
                    think=think, res=sum(pend), tu=0, txt=0, names=[], cmd=''))
                think, pend = 0, []
            for c in m.get('content') or []:
                if not isinstance(c, dict):
                    continue
                if c.get('type') == 'tool_use':
                    nm = c.get('name') or '?'
                    rows[-1]['names'].append(nm)
                    rows[-1]['tu'] += len(json.dumps(c.get('input'), ensure_ascii=False))
                    if nm == 'Bash':
                        rows[-1]['cmd'] += ' ' + str((c.get('input') or {}).get('command', ''))
                    elif nm == 'Monitor':
                        rows[-1]['cmd'] += ' [Monitor]'
                elif c.get('type') == 'text':
                    rows[-1]['txt'] += len(c.get('text') or '')
    return model, armed, cost, rows


class Agg:
    """Les totaux d'une population (avant ou apres)."""
    def __init__(self):
        self.n = 0; self.tours = 0; self.integrale = 0; self.prefixes = []
        self.cat = Counter(); self.attente = Counter(); self.attente_tours = Counter()
        self.tronq = Counter(); self.res_bash = []; self.cout = 0.0; self.cout_n = 0
        self.sleep_s = 0.0; self.sleep_ge = 0; self.sleep_lt = 0
        self.outils = Counter(); self.mcp_essais = 0

    def ajoute(self, cost, rows):
        n = len(rows)
        self.n += 1; self.tours += n
        self.integrale += sum(r['ctx'] for r in rows)
        self.prefixes.append(rows[0]['ctx'])
        if cost:
            self.cout += cost; self.cout_n += 1
        mcp = False
        for r in rows:
            for nm in r['names']:
                self.outils[nm] += 1
                if nm.startswith('mcp__'):
                    mcp = True
        if mcp:
            self.mcp_essais += 1
        # PREFIXE : le contexte du premier tour, relu a CHAQUE tour. Il ne depend d'aucune
        # hypothese — c'est la valeur que l'API a publiee au tour 1.
        self.cat['prefixe'] += rows[0]['ctx'] * n
        for k in range(n - 1):
            a, b = rows[k], rows[k + 1]
            d = b['ctx'] - a['ctx']
            if d <= 0:
                continue
            poids = {'reflexion': a['think'], 'appels': a['tu'] / CH,
                     'texte': a['txt'] / CH, 'resultats': b['res'] / CH}
            s = sum(poids.values())
            if s <= 0:
                continue
            mult = n - 1 - k
            for c, v in poids.items():
                self.cat[c] += d * v / s * mult
            # CONTREFACTUEL DE TRONCATURE : ce qu'on aurait economise en plafonnant le
            # resultat d'outil a C caracteres, RELECTURES COMPRISES.
            for C in (2000, 4000, 8000, 16000):
                exces = max(b['res'] - C, 0)
                if exces:
                    self.tronq[C] += d * (exces / CH) / s * (mult + 1)
        for r in rows:
            cmd = r['cmd']
            if not cmd:
                continue
            m = RX_SLEEP.findall(cmd)
            for x in m:
                self.sleep_s += float(x)
                if float(x) >= 10: self.sleep_ge += 1
                else: self.sleep_lt += 1
            if 'Bash' in r['names']:
                self.res_bash.append(r['res'])
            lab = None
            if m: lab = 'sleep'
            elif RX_TAIL.search(cmd): lab = 'tail'
            elif RX_PS.search(cmd): lab = 'ps'
            if lab:
                self.attente[lab] += r['ctx']
                self.attente_tours[lab] += 1


def pm(part, tot):
    return int(round(1000.0 * part / tot)) if tot else -1


def pub(k, v):
    print('%s=%s' % (k, str(v).replace(' ', '_') if str(v).strip() else '-'))


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else '.autoport/logs'
    avant, apres = Agg(), Agg()
    lus = 0; sans_cmd = 0
    for p in sorted(glob.glob(os.path.join(root, '*', 'attempt-*.jsonl'))):
        lus += 1
        try:
            model, armed, cost, rows = _lire(p)
        except Exception:
            continue
        if model != REF_MODEL or len(rows) < 4:
            continue
        if armed is None:
            sans_cmd += 1
            continue
        (apres if armed else avant).ajoute(cost, rows)

    pub('cv_journaux_lus', lus)
    pub('cv_sans_ligne_de_lancement', sans_cmd)
    pub('cv_modele_de_reference', REF_MODEL)
    for nom, a in (('', avant), ('apres_', apres)):
        pub('cv_%sessais' % nom, a.n)
        if not a.n:
            continue
        I = a.integrale
        pub('cv_%stours_x10_par_essai' % nom, int(round(10.0 * a.tours / a.n)))
        pub('cv_%sintegrale_par_essai' % nom, int(I / a.n))
        pub('cv_%sprefixe_moyen' % nom, int(st.mean(a.prefixes)))
        pub('cv_%sprefixe_median' % nom, int(st.median(a.prefixes)))
        pub('cv_%scout_centimes_par_essai' % nom,
            int(round(100.0 * a.cout / a.cout_n)) if a.cout_n else -1)
        pub('cv_%scout_essais' % nom, a.cout_n)
        for c in ('prefixe', 'resultats', 'reflexion', 'appels', 'texte'):
            pub('cv_%spart_%s_pm' % (nom, c), pm(a.cat[c], I))
        pub('cv_%spart_attente_pm' % nom, pm(sum(a.attente.values()), I))
        for lab in ('sleep', 'tail', 'ps'):
            pub('cv_%sattente_%s_pm' % (nom, lab), pm(a.attente[lab], I))
        pub('cv_%sattente_tours_x10' % nom,
            int(round(10.0 * sum(a.attente_tours.values()) / a.n)))
        pub('cv_%ssleep_heures' % nom, int(a.sleep_s / 3600))
        pub('cv_%ssleep_ge10' % nom, a.sleep_ge)
        pub('cv_%ssleep_lt10' % nom, a.sleep_lt)
        for C in (2000, 4000, 8000, 16000):
            pub('cv_%stronque_%dk_pm' % (nom, C // 1000), pm(a.tronq[C], I))
        rb = [x for x in a.res_bash if x > 0]
        pub('cv_%sres_bash_median' % nom, int(st.median(rb)) if rb else -1)
        pub('cv_%sres_bash_n' % nom, len(rb))
        pub('cv_%sappels_outil' % nom, sum(a.outils.values()))
        pub('cv_%sappels_mcp' % nom, sum(v for k, v in a.outils.items() if k.startswith('mcp__')))
        pub('cv_%sessais_avec_mcp' % nom, a.mcp_essais)

    # LA COMPARAISON QUE DEMANDE L'ITEM : integrale et cout par essai, AVANT contre APRES,
    # sur le MEME modele et le MEME effort. Tant qu'il n'y a pas d'essais APRES, on le DIT :
    # -1 n'est pas 0, et aucune porte ne doit lire un zero de population vide comme un succes.
    if apres.n and avant.n:
        av = avant.integrale / avant.n; ap = apres.integrale / apres.n
        pub('cv_baisse_integrale_pm', int(round(1000.0 * (av - ap) / av)))
        if avant.cout_n and apres.cout_n:
            ca = avant.cout / avant.cout_n; cp = apres.cout / apres.cout_n
            pub('cv_baisse_cout_pm', int(round(1000.0 * (ca - cp) / ca)))
        else:
            pub('cv_baisse_cout_pm', -1)
        pub('cv_gain_prefixe', int(st.mean(avant.prefixes) - st.mean(apres.prefixes)))
    else:
        pub('cv_baisse_integrale_pm', -1)
        pub('cv_baisse_cout_pm', -1)
        pub('cv_gain_prefixe', -1)


if __name__ == '__main__':
    main()
