#!/usr/bin/env python3
import json, sys
from pathlib import Path

def bump_patch(v: str) -> str:
    # tolerant semver-ish bump: x[.y[.z]] -> bump z; default 0.0.0
    try:
        parts = [int(p) for p in v.split(".")]
    except Exception:
        parts = []
    while len(parts) < 3:
        parts.append(0)
    parts[2] += 1
    return ".".join(str(x) for x in parts[:3])

def main():
    if len(sys.argv) < 2:
        print("", end="")
        return
    results = []
    for pkg_dir in sys.argv[1:]:
        p = Path(pkg_dir) / "publisher.json"
        if not p.exists():
            # initialize publisher.json if missing
            data = {"name": Path(pkg_dir).name, "version": "0.0.1", "description": ""}
        else:
            try:
                data = json.loads(p.read_text())
            except Exception:
                data = {"name": Path(pkg_dir).name, "version": "0.0.0", "description": ""}

            cur = str(data.get("version") or "0.0.0")
            data["version"] = bump_patch(cur)

        # ensure name present
        data.setdefault("name", Path(pkg_dir).name)
        # write back
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(data, indent=2) + "\n")

        results.append(f"{pkg_dir}|{data['name']}|{data['version']}")

    # space-separated, each item path|name|version
    print(" ".join(results))

if __name__ == "__main__":
    main()
