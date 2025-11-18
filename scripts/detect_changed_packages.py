#!/usr/bin/env python3
import subprocess, sys
from pathlib import Path

def run(cmd):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)

def git_diff_names(base, head):
    """Return all changed file paths between two commits."""
    r = run(["git", "diff", "--name-only", f"{base}..{head}"])
    if r.returncode != 0:
        return []
    return [l.strip() for l in r.stdout.splitlines() if l.strip()]

def find_package_root(file_path: Path) -> Path | None:
    """
    Walk up from file path to find the directory containing publisher.json.
    Returns the package root directory or None if not found.
    """
    current = file_path.parent if file_path.is_file() else file_path
    
    # Walk up the directory tree
    while len(current.parts) > 0:
        publisher = current / "publisher.json"
        if publisher.exists():
            return current
        
        # Stop if we've left the packages directory
        if "packages" not in current.parts:
            break
            
        # Move up one level
        current = current.parent
    
    return None

def publisher_version_changed(pkg_dir: Path, base: str, head: str) -> bool:
    """Check if the version VALUE actually changed in publisher.json."""
    import json
    
    p = pkg_dir / "publisher.json"
    if not p.exists():
        return False

    # Get old version from base commit
    old = run(["git", "show", f"{base}:{p}"])
    if old.returncode != 0:
        # File didn't exist in base commit (new package)
        return False
    
    # Get new version from head commit
    new = run(["git", "show", f"{head}:{p}"])
    if new.returncode != 0:
        # File doesn't exist in head (deleted)
        return False
    
    try:
        old_data = json.loads(old.stdout)
        new_data = json.loads(new.stdout)
        
        old_version = old_data.get("version", "")
        new_version = new_data.get("version", "")

        old_name = old_data.get("name", "").lower()
        new_name = new_data.get("name", "").lower()
        
        # Only return True if the version VALUE actually changed
        return old_version != new_version or old_name != new_name
    except (json.JSONDecodeError, KeyError):
        # If we can't parse JSON, assume no version change
        # (bump will handle it or fail appropriately)
        return False

def main():
    base = sys.argv[1] if len(sys.argv) > 1 else ""
    head = sys.argv[2] if len(sys.argv) > 2 else "HEAD"

    if not base or base == "0000000000000000000000000000000000000000":
        run(["git", "fetch", "--no-tags", "--prune", "origin", "+refs/heads/*:refs/remotes/origin/*"])
        mb = run(["git", "merge-base", head, "origin/main"]).stdout.strip()
        base = mb if mb else head + "^"

    changed = git_diff_names(base, head)

    pkgs = set()
    for f in changed:
        if f.startswith("packages/"):
            file_path = Path(f)
            
            # Find the package root by looking for publisher.json
            pkg_root = find_package_root(file_path)
            
            if pkg_root:
                print(f"[detected] {f} → package: {pkg_root}")
                pkgs.add(pkg_root)
            else:
                print(f"[skip] {f} → no publisher.json found in parent directories")

    to_bump, already_bumped = [], []

    for pkg_dir in sorted(pkgs):
        if publisher_version_changed(pkg_dir, base, head):
            print(f"[skip bump] {pkg_dir}: version change detected in publisher.json")
            already_bumped.append(str(pkg_dir))
        else:
            to_bump.append(str(pkg_dir))

    print(f"TO_BUMP={' '.join(to_bump)}")
    print(f"ALREADY_BUMPED={' '.join(already_bumped)}")

if __name__ == "__main__":
    main()