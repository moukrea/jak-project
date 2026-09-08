"""One official loading run; invoked only by diagnostic.py after explicit GO."""
import json
import shutil
import re
import time


def run(ctx):
    args = ['bash', '-c',
            'pkill(){ printf "%s\\n" "DIRECTIVES: nettoyage PID uniquement" >&2; return 1; }; '
            'export -f pkill; exec bash "$@"', '_',
            '.autoport/lib/proof_run.sh', 'lighting-hdr', 'device', '--timeout', '240',
            '--hdr-campaign', 'essai37-loading-diag', '--hdr-vantages', 'village1-out',
            '--hdr-hours', '12']
    props = ['refset.cam=village1-out:-10:-108:152:33', 'refset.temporal=2',
             'level.warp=village1-hut', 'refset.loadsettle=660', 'refset.orderhour=1',
             'refset.settle=660', 'refset.warpat=900', 'want.display=village1,display',
             'want.levels=beach,village1', 'hdr.load_diag=1']
    for prop in props:
        args += ['--hdr-prop', 'debug.opengoal.' + prop]
    (ctx.n / 'command.json').write_text(json.dumps(args, indent=2) + '\n')
    # Exclusive sentinel: no identical automatic retry, including failed/absent runs.
    (ctx.n / 'run-started').open('x').close()
    result = None
    started_ns = time.time_ns()
    try:
        result = ctx.command(args, 'run.log', check=False, timeout=420)
        (ctx.n / 'run.exitcode').write_text(str(result.returncode) + '\n')
    finally:
        for name in ['proof.txt', 'proof-engine.log']:
            src = ctx.report / name
            if src.exists() and src.stat().st_mtime_ns >= started_ns:
                shutil.copy2(src, ctx.n / ('diagnostic-' + name))
        proof = ctx.n / 'diagnostic-proof.txt'
        if proof.exists():
            match = re.search(r'^hdr_batch_manifest=(.+)$', proof.read_text(), re.M)
            if match:
                (ctx.n / 'batch-path.txt').write_text(str(ctx.root / match[1]) + '\n')
        # Preserve all generated batch files in their official location, including crash/absence.
        (ctx.n / 'batches-after.json').write_text(json.dumps(
            [str(p) for p in (ctx.report / 'batches').rglob('*')
             if 'essai37-loading-diag' in str(p)], indent=2) + '\n')
    if result is not None:
        result.check_returncode()
