#!/usr/bin/env python3
import subprocess, sys
from pathlib import Path

def run(cmd):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)

def git_diff_names(base, head):
    r = run(["git", "diff", "--name-only", f"{base}..{head}"])
    if r.returncode != 0: return []
    return [l.strip() for l in r.stdout.splitlines() if l.strip()]

def main():
    base = sys.argv[1] if len(sys.argv) > 1 else ""
    head = sys.argv[2] if len(sys.argv) > 2 else "HEAD"
    if not base or base == "0000000000000000000000000000000000000000":
        run(["git", "fetch", "--no-tags", "--prune", "origin", "+refs/heads/*:refs/remotes/origin/*"])
        mb = run(["git", "merge-base", head, "origin/main"]).stdout.strip()
        base = mb if mb else head + "^"

    changed = git_diff_names(base, head)

    # Collect top-level package dirs under packages/<pkg>/...
    pkgs = set()
    for f in changed:
        if f.startswith("packages/"):
            parts = Path(f).parts
            # require at least packages/<pkg>/...
            if len(parts) >= 2:
                pkg_dir = str(Path(parts[0]) / parts[1])  # packages/<pkg>
                pkgs.add(pkg_dir)

    print(" ".join(sorted(pkgs)))

if __name__ == "__main__":
    main()
