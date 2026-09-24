#!/usr/bin/env python3
"""acquis_budget.py — le delai qu'un acquis recoit a la fermeture, DERIVE de la duree de sa course.

Jusqu'au 24/09 la porte des acquis (`orchestrator.py`, GATE 3) coupait TOUS les scripts a 600 s.
Un acquis appareil dont la preuve est perimee relance une course complete
(`lib/proof_run.sh acquis-<x> device`) : 462 s murales mesurees pour une course de 420 s, 26 s de
recensement en plus, et une installation d'APK possible. Au-dela de ~550 s de course il aurait ete
tue AU MILIEU — et un acquis qui ne repond pas bloque TOUTES les fermetures.

REGLE : delai = max(PLANCHER, course + MARGE), ou course = le plus grand de
  - la duree MESUREE de sa derniere preuve (`duration_s` de `reports/acquis-<x>/proof.txt`) ;
  - le `proof_timeout` DECLARE par son item `acquis-<x>` dans le backlog.
Sans l'un ni l'autre (acquis local, sans item), le plancher : l'ancien comportement, inchange.
Le delai et sa derivation sont PUBLIES (journal de fermeture, `python3 lib/acquis_budget.py`).
"""
from pathlib import Path
import re
import sys

FLOOR_S = 600   # l'ancien plafond unique : un acquis local ne recoit jamais moins
MARGIN_S = 240  # amorcage + recensement (26 s mesurees) + installation d'APK possible (~2 min)


def _seconds(value):
    value = str(value if value is not None else '').strip()
    return int(value) if re.fullmatch(r'[0-9]{1,6}', value) and int(value) > 0 else None


def measured_duration(proof):
    try:
        for line in Path(proof).read_text(errors='replace').splitlines():
            if line.startswith('duration_s='):
                return _seconds(line.partition('=')[2])
    except OSError:
        pass
    return None


def budget(script, autoport_dir, get_item=None):
    name = Path(script).name[:-3] if Path(script).name.endswith('.sh') else Path(script).name
    item = 'acquis-' + name
    measured = measured_duration(Path(autoport_dir) / 'reports' / item / 'proof.txt')
    declared = None
    if get_item is not None:
        try:
            declared = _seconds((get_item(item) or {}).get('proof_timeout'))
        except Exception:  # noqa: BLE001 — un backlog illisible ne retire pas la mesure
            declared = None
    known = [v for v in (measured, declared) if v is not None]
    course = max(known) if known else None
    budget_s = FLOOR_S if course is None else max(FLOOR_S, course + MARGIN_S)
    why = ('aucune course connue, plancher %d s' % FLOOR_S if course is None else
           'course %d s (mesuree %s, declaree %s) + marge %d s, plancher %d s'
           % (course, measured if measured is not None else '-',
              declared if declared is not None else '-', MARGIN_S, FLOOR_S))
    return {'name': name, 'item': item, 'measured_s': measured, 'declared_s': declared,
            'course_s': course, 'budget_s': budget_s, 'why': why}


def main(argv):
    autoport_dir = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(autoport_dir / 'lib'))
    get_item = None
    try:
        import backlog
        get_item = backlog.load(autoport_dir / 'backlog.yaml').get
    except Exception:  # noqa: BLE001
        print('acquis_budget_backlog_read=0')
    scripts = [p for p in sorted((autoport_dir / 'acquis').glob('*.sh')) if p.name != '_lib.sh']
    print('acquis_budget_floor_s=%d' % FLOOR_S)
    print('acquis_budget_margin_s=%d' % MARGIN_S)
    print('acquis_budget_scripts=%d' % len(scripts))
    for script in scripts:
        b = budget(script, autoport_dir, get_item)
        key = re.sub(r'[^A-Za-z0-9_]', '_', b['name'])
        print('acquis_budget_%s=%d' % (key, b['budget_s']))
        print('acquis_budget_%s_course=%s' % (key, b['course_s'] if b['course_s'] is not None else -1))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
