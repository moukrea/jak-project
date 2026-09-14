"""Recognize a first CMake configuration without executing any shell text.

Only a single invocation with literal, absolute -S/-B paths qualifies. Existing
build contents (including hidden files and symlink targets) keep the guard shut.
"""
from pathlib import Path
import shlex
import sys


def is_initial_configure(command: str) -> bool:
    # Do not interpret expansions, redirections, compound commands or continuations.
    if any(c in command.strip() for c in "$`\\\n\r;&|<>()*?[]{}~"):
        return False
    try:
        args = shlex.split(command)
        if not args or Path(args.pop(0)).name != "cmake":
            return False
        paths = {}
        while args:
            arg = args.pop(0)
            if arg[:2] in ("-S", "-B"):
                key = arg[:2]
                if key in paths:
                    return False
                value = arg[2:] if len(arg) > 2 else args.pop(0)
                # CMake uses -Bpath, not -B=path (the '=' is part of that path).
                path = Path(value)
                if not path.is_absolute():
                    return False
                paths[key] = path.resolve()
            elif arg in ("-G", "-D"):
                args.pop(0)
            elif arg.startswith("-D"):
                pass
            else:
                return False
        if set(paths) != {"-S", "-B"}:
            return False
        source, build = paths["-S"], paths["-B"]
        if source == build or not (source / "CMakeLists.txt").is_file():
            return False
        if build.exists():
            return build.is_dir() and next(build.iterdir(), None) is None
        return True
    except (ValueError, IndexError, OSError, RuntimeError):
        return False


if __name__ == "__main__":
    sys.exit(0 if is_initial_configure(sys.stdin.read()) else 1)
