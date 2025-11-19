#!/usr/bin/env python3
import json, sys, re
from pathlib import Path

def validate_package_name(name: str) -> bool:
    """
    Validate package name to prevent command injection.
    Allows: alphanumeric, spaces, hyphens, underscores, dots
    """
    if not name or len(name) > 255:
        return False
    # Allow safe characters only
    pattern = r'^[a-zA-Z0-9\s\-_.]+$'
    return bool(re.match(pattern, name))

def validate_version(version: str) -> bool:
    """Validate version format"""
    if not version or len(version) > 50:
        return False
    # Allow semver format: digits, dots, hyphens, plus (for prerelease/build)
    pattern = r'^[0-9.+\-a-zA-Z]+$'
    return bool(re.match(pattern, version))

def bump_patch(v: str) -> str:
    """
    Tolerant semver bump: x[.y[.z]][-prerelease][+build] → bump patch
    Handles full semantic versioning including prerelease and build metadata.
    Preserves prerelease and build metadata when bumping.
    
    Examples:
      1.0.0 → 1.0.1
      1.0.0-alpha.1 → 1.0.1-alpha.1 (preserves prerelease)
      1.0.0+build.123 → 1.0.1+build.123 (preserves build)
      1.0.0-rc.1+build → 1.0.1-rc.1+build (preserves both)
      2 → 2.0.1
    """
    # Check for prerelease (separated by -)
    prerelease_idx = v.find('-')
    # Check for build metadata (separated by +)
    build_idx = v.find('+')
    
    # Extract the suffix (everything after version numbers)
    suffix = ""
    if prerelease_idx != -1:
        version_part = v[:prerelease_idx]
        suffix = v[prerelease_idx:]  # Includes both -prerelease and +build
    elif build_idx != -1:
        version_part = v[:build_idx]
        suffix = v[build_idx:]  # Includes +build
    else:
        version_part = v
    
    # Split version into parts
    parts = version_part.split(".")
    
    # Validate all parts are numeric
    if not all(p.isdigit() for p in parts if p):
        raise ValueError(f"Invalid semver: {v}")
    
    # Ensure we have 3 parts (major.minor.patch)
    while len(parts) < 3:
        parts.append("0")
    
    # Convert to integers and bump patch
    parts = [int(p) for p in parts[:3]]
    
    # Validate max version part
    MAX_VERSION = 999999
    if any(p > MAX_VERSION for p in parts):
        raise ValueError(f"Version number too large (max: {MAX_VERSION})")
    
    parts[2] += 1
    
    # Return bumped version WITH prerelease/build preserved
    return ".".join(str(x) for x in parts) + suffix

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
            # Check file size (prevent reading huge files)
            if p.stat().st_size > 1024 * 1024:  # 1MB max
                print(f"ERROR: publisher.json too large in {pkg_dir}", file=sys.stderr)
                continue
            
            try:
                data = json.loads(p.read_text())
                if not isinstance(data, dict):
                    raise ValueError("publisher.json must be a JSON object")
            except json.JSONDecodeError as e:
                print(f"ERROR: Invalid JSON in {p}: {e}", file=sys.stderr)
                continue  # Skip this package, continue with others
            except Exception as e:
                print(f"ERROR: Failed to read {p}: {e}", file=sys.stderr)
                continue
        else:
            data = {"name": pkg.name, "version": "0.0.0", "description": ""}
        
        # Validate and sanitize package name
        pkg_name = str(data.get("name", pkg.name))
        if not validate_package_name(pkg_name):
            print(f"ERROR: Invalid package name '{pkg_name}' in {pkg_dir}", file=sys.stderr)
            print(f"       Package names must contain only alphanumeric, spaces, hyphens, underscores, dots", file=sys.stderr)
            continue
        
        cur_version = str(data.get("version", "0.0.0"))
        if not validate_version(cur_version):
            print(f"ERROR: Invalid version format '{cur_version}' in {pkg_dir}", file=sys.stderr)
            continue
        
        try:
            new_version = bump_patch(cur_version)
        except ValueError as e:
            print(f"ERROR: {e} in {pkg_dir}", file=sys.stderr)
            continue  # Skip this package, continue with others

        data["version"] = new_version
        data["name"] = pkg_name  # Use validated name
        p.write_text(json.dumps(data, indent=2) + "\n")

        results.append(f"{pkg_dir}|{data['name']}|{new_version}")

    output = " ".join(results).strip()
    print(output)

if __name__ == "__main__":
    main()
