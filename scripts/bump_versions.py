#!/usr/bin/env python3
import json, sys
from pathlib import Path

def bump_patch(v: str) -> str:
    """Tolerant semver bump: x[.y[.z]] → bump patch"""
    parts = v.split(".")
    if not all(p.isdigit() for p in parts if p):
        raise ValueError(f"Invalid semver: {v}")
    while len(parts) < 3:
        parts.append("0")
    parts = [int(p) for p in parts[:3]]
    parts[2] += 1
    return ".".join(str(x) for x in parts)

def main():
    if len(sys.argv) < 2:
        print("ERROR: No package directories specified.", file=sys.stderr)
        sys.exit(1)

    results = []
    for pkg_dir in sys.argv[1:]:
        pkg = Path(pkg_dir)
        if not pkg.exists():
            print(f"ERROR: Package directory not found: {pkg_dir}", file=sys.stderr)
            continue

        p = pkg / "publisher.json"
        if p.exists():
            try:
                data = json.loads(p.read_text())
            except Exception as e:
                print(f"ERROR: Failed to parse {p}: {e}", file=sys.stderr)
                sys.exit(1)
        else:
            data = {"name": pkg.name, "version": "0.0.0", "description": ""}
        
        cur_version = str(data.get("version", "0.0.0"))
        try:
            new_version = bump_patch(cur_version)
        except ValueError as e:
            print(f"ERROR: {e} in {pkg_dir}", file=sys.stderr)
            sys.exit(1)

        data["version"] = new_version
        data.setdefault("name", pkg.name)
        p.write_text(json.dumps(data, indent=2) + "\n")

        results.append(f"{pkg_dir}|{data['name']}|{new_version}")

    output = " ".join(results).strip()
    print(output)

if __name__ == "__main__":
    main()
