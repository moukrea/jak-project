#!/usr/bin/env python3
"""acquis_device_guard.py — LA garde de preuve scellee des acquis APPAREIL, en un seul exemplaire.

Jusqu'au 24/09, `acquis/hud-eco-gauge.sh` et `acquis/perf-dma-chain-copies.sh` portaient chacun
~100 lignes identiques (sceau, md5 local/appareil, serial USB, TTL, sources de verdict) : un
correctif de la garde devait etre porte deux fois, un troisieme acquis appareil en aurait fait
trois (harness-device-acquis-hardening). Chaque acquis appareil ne dit plus ici que CE QUI LUI
EST PROPRE : son item, son site, les cles journal/preuve a recouper, ce que son recensement doit
rendre.

LE SITE PROPRE. La ligne `FEATURE acquis-<x> armed=1 hits=N` d'une course d'acquis porte le
compteur GLOBAL du binaire (`game/system/autoport_proof.cpp`, emit_locked) : aucun site du moteur
ne porte l'id `acquis-<x>`, la preuve le dit elle-meme (`proof_feature_state=absent`,
`proof_feature_own_hits=0`). Elle ne prouve donc que l'ARMEMENT. Le compteur de passage d'un acquis
est celui du SITE de la feature qu'il garde, lu dans `proof_feature_hits_table`, la table que le
moteur publie : `--site hud-eco-gauge` exige `hud-eco-gauge:N`, N > 0, dans une table non tronquee.
Absent ou nul = defaut NOMME (`site vacant`), jamais un vert.

Codes : 0 = preuve admise, chemin du journal sur stdout ; 2 = preuve absente, perimee ou invalide
(l'appelant relance UNE course) ; 1 = defaut MESURE dans une preuve valide (aucune relance).
`--report F` ecrit en plus `guard_*=` dans F, pour un recensement.
"""
import argparse
import datetime
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from impossible import arm_name  # noqa: E402

U64 = 2**64 - 1
BINARY = Path('build-android/lib/arm64-v8a/libgk.so')


def read_fields(text):
    fields = {}
    for line in text.splitlines():
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        # Une ligne FEATURE n'est pas une metadonnee ; une metadonnee repetee est ambigue.
        if not re.fullmatch(r'[A-Za-z0-9_]+', key):
            continue
        if key in fields:
            raise ValueError('cle dupliquee : ' + key)
        fields[key] = value
    return fields


def site_table(raw):
    table = {}
    for entry in raw.split(','):
        name, sep, count = entry.rpartition(':')
        if sep and re.fullmatch(r'[0-9]{1,20}', count):
            table[name] = int(count)
    return table


class Verdict(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code, self.message = code, message


def judge(args, data):
    item = args.item
    directory = Path('.autoport/reports') / item
    proof, log, seal = (directory / arm_name(kind) for kind in ('proof', 'engine', 'seal'))
    args.proof_path = proof

    def verdict_sources(mode, *extra):
        return subprocess.check_output(
            ['bash', '.autoport/lib/verdict_sources.sh', item, mode, *map(str, extra)],
            text=True).strip()

    try:
        raw = proof.read_bytes()
        proof_text = raw.decode()
        data.update(read_fields(proof_text))
        sealed = read_fields(seal.read_text())
        digest = hashlib.sha256(raw).hexdigest()
        if any(sealed.get(key) != digest for key in ('seal_sha', 'exit_sha')) or any(
                sealed.get(key) != str(len(raw)) for key in ('seal_bytes', 'exit_bytes')):
            raise ValueError('preuve incomplete ou sceau divergent')
        if data.get('source') != 'device' or data.get('binary') != str(BINARY):
            raise ValueError('source/binaire Android attendu')
        binary_bytes = BINARY.read_bytes()
        if data.get('sha') != hashlib.sha256(binary_bytes).hexdigest()[:16]:
            raise ValueError('sha binaire divergent')
        md5 = hashlib.md5(binary_bytes).hexdigest()
        if any(data.get(key) != md5 for key in (
                'local_lib_md5', 'device_lib_md5', 'proof_binary_local_md5', 'proof_binary_device_md5')):
            raise ValueError('md5 local/appareil ou garde binaire divergent')
        serial = data.get('serial', '')
        if (not serial or re.search(r'[:\s]|_adb-tls-|(?:\d{1,3}\.){3}\d{1,3}', serial, re.I)
                or any(data.get(key) != serial for key in ('device_serial', 'proof_binary_serial'))):
            raise ValueError('identite USB absente, interdite ou divergente')
        model = data.get('device_model', '')
        if not model or 'shield' in model.lower():
            raise ValueError('modele absent ou SHIELD interdit')
        if (data.get('proof_binary_gate_ran') != '1'
                or data.get('proof_binary_checked_before_measure') != '1'
                or data.get('proof_binary_rc') != '0'):
            raise ValueError('garde binaire non verifiee avant mesure')
        if not data.get('proof_run_id', '').strip():
            raise ValueError('run_id absent')
        # L'ARMEMENT, et lui seul : `hits=` est ici le compteur GLOBAL (voir l'en-tete).
        features = re.findall(r'^FEATURE ' + re.escape(item) + r' armed=([01]) hits=([0-9]+)(?: .*)?$',
                              proof_text, re.M)
        if len(features) != 1 or features[0][0] != '1' or int(features[0][1]) > U64:
            raise ValueError('FEATURE propre a cet item absente, ambigue ou desarmee')
        if 'proof_feature_hits_table' not in data or data.get('proof_feature_hits_table_truncated') not in ('0', '1'):
            raise ValueError('table des sites du moteur absente')
        ttl = args.ttl
        started = data.get('started_at', '')
        if not re.fullmatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z', started):
            raise ValueError('started_at malforme')
        start = datetime.datetime.fromisoformat(started.replace('Z', '+00:00')).timestamp()
        now = time.time()
        if ttl <= 0 or not 0 <= now - start < ttl:
            raise ValueError('TTL invalide, course perimee ou future')
        if BINARY.stat().st_mtime > start:
            raise ValueError('binaire plus recent que le debut de course')
        for root in ('game', 'common', 'android', 'goal_src'):
            for directory_name, _, names in os.walk(root, onerror=lambda exc: (_ for _ in ()).throw(exc)):
                for name in names:
                    source = Path(directory_name) / name
                    if source.suffix in {'.cpp', '.h', '.gc', '.vert', '.frag'} and source.stat().st_mtime > start:
                        raise ValueError('source plus recente que le debut de course : ' + str(source))
        if not log.is_file() or log.stat().st_size == 0 or not (
                start <= log.stat().st_mtime <= proof.stat().st_mtime <= seal.stat().st_mtime <= now):
            raise ValueError('journal vide ou dates journal/preuve/sceau incoherentes')
        for field, mode in (('verdict_sources_sha', 'sha'), ('verdict_sources_count', 'count'),
                            ('verdict_criterion_sha', 'criterion_sha'), ('verdict_acquis_sha', 'acquis_sha'),
                            ('verdict_acquis_count', 'acquis_count')):
            expected = verdict_sources(mode)
            if not expected or data.get(field) != expected:
                raise ValueError('sources de verdict divergentes : ' + field)
        newer = verdict_sources('newer', proof)
        if newer:
            raise ValueError('sources de verdict plus recentes : ' + newer.replace('\n', ','))
        text = log.read_text(errors='replace')
        for key in args.log_key:
            matches = re.findall(r'(?<![\w])' + re.escape(key) + r'\b=([^\r\n]*)', text)
            if not matches or matches[-1].strip() != data.get(key):
                raise ValueError('journal/preuve divergent : ' + key)
    except (OSError, ValueError, UnicodeDecodeError, subprocess.CalledProcessError) as exc:
        raise Verdict(2, str(exc))

    if data.get('crash') != '0' or not re.fullmatch(r'[0-9]{1,20}', data.get('frames', '')) or not 0 < int(data['frames']) <= U64:
        raise Verdict(1, 'crash ou population frames invalide')
    table = site_table(data['proof_feature_hits_table'])
    hits = table.get(args.site, 0)
    data['_site_hits'] = hits
    if hits <= 0:
        if data['proof_feature_hits_table_truncated'] == '1':
            raise Verdict(1, 'site %s illisible : table des sites tronquee' % args.site)
        raise Verdict(1, 'site vacant : %s n a aucune prise dans cette course' % args.site)
    for pair in args.expect:
        key, _, expected = pair.partition('=')
        if data.get(key) != expected:
            raise Verdict(1, 'recensement refuse : ' + key + '=' + data.get(key, '?'))
    for key in args.positive:
        value = data.get(key, '')
        if not re.fullmatch(r'[0-9]{1,20}', value) or not 0 < int(value) <= U64:
            raise Verdict(1, 'population du recensement invalide : ' + key)
    for pair in args.same:
        left, _, right = pair.partition('=')
        if data.get(left) != data.get(right):
            raise Verdict(1, 'recensement incomplet : %s != %s' % (left, right))
    return log


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--item', required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--site', required=True)
    parser.add_argument('--ttl', type=int, required=True)
    parser.add_argument('--log-key', action='append', default=[])
    parser.add_argument('--expect', action='append', default=[])
    parser.add_argument('--positive', action='append', default=[])
    parser.add_argument('--same', action='append', default=[])
    parser.add_argument('--report')
    args = parser.parse_args(argv)
    args.proof_path = None
    data = {}
    code, message, log = 0, 'preuve admise', None
    try:
        log = judge(args, data)
    except Verdict as verdict:
        code, message = verdict.code, verdict.message
    if args.report:
        Path(args.report).write_text(
            'guard_code=%d\nguard_site=%s\nguard_site_hits=%s\nguard_reason=%s\n' % (
                code, args.site, data.get('_site_hits', -1), re.sub(r'\s+', '_', message)))
    if code:
        print(f'[acquis/{args.tag}] NON PROUVE : {args.proof_path} '
              f'run_id={data.get("proof_run_id", "?")} : {message}', file=sys.stderr)
        return code
    print(f'[acquis/{args.tag}] preuve admise : {args.proof_path} run_id={data["proof_run_id"]} '
          f'site={args.site} prises={data["_site_hits"]}', file=sys.stderr)
    print(log)
    return 0


if __name__ == '__main__':
    sys.exit(main())
