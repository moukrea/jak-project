#!/usr/bin/env python3
"""Recu de fabrication : seule une paire complete peut etre livree.

Le constructeur et le publieur tiennent .delivery-artifacts.lock pendant leurs
acces. Le recu atomique reste absent entre le debut d'une passe et son succes.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import zipfile

RECEIPT = Path('.autoport/.delivery-ready.json')
FILES = ('android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk',
         'out/artifacts/jak1_hd_assets.zip', 'out/artifacts/BUILD-INFO.txt')


def git(*args):
    return subprocess.check_output(['git', *args])


def sources():
    """Contenu versionne + modifications, sans l'etat continuellement reecrit du harnais."""
    # Ces deux manifestes sont versionnes mais produits par Gradle : les inclure
    # ferait refuser chaque nouvelle paire au motif qu'elle a produit ses sorties.
    paths = ('.', ':(exclude).autoport/**',
             ':(exclude)android/app/src/jak1/assets-slim/bundle/jak1_cgo.manifest.properties',
             ':(exclude)android/app/src/jak1/assets-slim/bundle/jak1_custom.manifest.properties')
    digest = hashlib.sha256(git('ls-files', '--stage', '-z', '--', *paths))
    digest.update(git('diff', '--binary', '--', *paths))
    for name in git('ls-files', '--others', '--exclude-standard', '-z', '--', *paths).split(b'\0'):
        if name:
            digest.update(name)
            digest.update(Path(os.fsdecode(name)).read_bytes())
    return digest.hexdigest()


def fingerprint(name):
    path = Path(name)
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f'artefact absent/vide: {name}')
    with path.open('rb') as stream:
        sha = hashlib.file_digest(stream, 'sha256').hexdigest()
    return {'sha256': sha, 'size': path.stat().st_size}


def seal(commit, identity):
    if sources() != identity:
        raise ValueError('sources modifiees pendant la fabrication')
    for name in FILES[:2]:
        with zipfile.ZipFile(name) as archive:
            if not archive.namelist() or archive.testzip() is not None:
                raise ValueError(f'archive incomplete: {name}')
    apk_size = Path(FILES[0]).stat().st_size
    if apk_size > 700000000:
        raise ValueError(f'APK trop gros: {apk_size}')
    info = Path(FILES[2]).read_text()
    if not any(commit.startswith(value) for value in re.findall(r'commit: ([0-9a-f]{7,40})', info)):
        raise ValueError('BUILD-INFO ne nomme pas le commit de depart')
    data = {'commit': commit, 'sources': identity,
            'files': {name: fingerprint(name) for name in FILES}}
    if sources() != identity:
        raise ValueError('sources modifiees pendant le scellement')
    temporary = RECEIPT.with_name(f'{RECEIPT.name}.{os.getpid()}')
    try:
        temporary.write_text(json.dumps(data, sort_keys=True) + '\n')
        temporary.replace(RECEIPT)
    finally:
        temporary.unlink(missing_ok=True)


def check():
    data = json.loads(RECEIPT.read_text())
    if set(data['files']) != set(FILES):
        raise ValueError('liste des artefacts incomplete')
    for name in FILES:
        if fingerprint(name) != data['files'][name]:
            raise ValueError(f'artefact different du recu: {name}')
    return data


if __name__ == '__main__':
    try:
        if sys.argv[1:] == ['sources']:
            print(sources())
        elif sys.argv[1:] == ['check']:
            print(check()['commit'])
        elif len(sys.argv) == 4 and sys.argv[1] == 'seal':
            seal(sys.argv[2], sys.argv[3])
        else:
            raise ValueError('usage: delivery_artifact.py sources|check|seal COMMIT SOURCES')
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f'[delivery-artifact] refuse: {error}', file=sys.stderr)
        sys.exit(1)
