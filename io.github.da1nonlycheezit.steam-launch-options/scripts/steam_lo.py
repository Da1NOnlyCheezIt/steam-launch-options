#!/usr/bin/env python3
"""Steam launch-options helper for Omarchy plugin.

Reads/writes localconfig.vdf LaunchOptions, lists installed games from
appmanifest_*.acf, resolves icons from library cache or CDN.

Usage (JSON on stdout):
  steam_lo.py list
  steam_lo.py get <appid>
  steam_lo.py set <appid> <options...>
  steam_lo.py apply-defaults <default_options...>
  steam_lo.py defaults-get
  steam_lo.py defaults-set <options...>
  steam_lo.py steam-path
"""

from __future__ import annotations

import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any

HOME = Path.home()
PLUGIN_STATE = HOME / ".config" / "omarchy" / "steam-launch-options"
DEFAULTS_FILE = PLUGIN_STATE / "defaults.txt"
BACKUP_DIR = PLUGIN_STATE / "backups"


def steam_roots() -> list[Path]:
    candidates = [
        HOME / ".steam" / "steam",
        HOME / ".local" / "share" / "Steam",
        HOME / ".var" / "app" / "com.valvesoftware.Steam" / ".local" / "share" / "Steam",
        Path("/usr/share/steam"),
    ]
    out: list[Path] = []
    seen: set[str] = set()
    for p in candidates:
        try:
            r = p.resolve()
        except OSError:
            continue
        if r.is_dir() and str(r) not in seen:
            seen.add(str(r))
            out.append(r)
    return out


def find_steam_root() -> Path | None:
    roots = steam_roots()
    return roots[0] if roots else None


def library_folders(steam_root: Path) -> list[Path]:
    """Return steamapps directories for all libraries."""
    libs: list[Path] = []
    main = steam_root / "steamapps"
    if main.is_dir():
        libs.append(main)

    for rel in ("config/libraryfolders.vdf", "steamapps/libraryfolders.vdf"):
        vdf = steam_root / rel
        if not vdf.is_file():
            continue
        text = vdf.read_text(encoding="utf-8", errors="replace")
        for m in re.finditer(r'"path"\s+"([^"]+)"', text):
            p = Path(m.group(1).replace("\\\\", "/"))
            apps = p / "steamapps"
            if apps.is_dir() and apps not in libs:
                libs.append(apps)
        for m in re.finditer(r'"\d+"\s+"([^"]+)"', text):
            p = Path(m.group(1).replace("\\\\", "/"))
            if p.name.lower() != "steamapps":
                apps = p / "steamapps"
            else:
                apps = p
            if apps.is_dir() and apps not in libs:
                libs.append(apps)
        break
    return libs


def parse_simple_acf(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return data
    for key in ("appid", "name", "installdir", "StateFlags"):
        m = re.search(rf'"{key}"\s+"([^"]*)"', text, re.I)
        if m:
            data[key.lower()] = m.group(1)
    return data


def find_userdata_ids(steam_root: Path) -> list[str]:
    ud = steam_root / "userdata"
    if not ud.is_dir():
        return []
    ids = []
    for d in ud.iterdir():
        if d.is_dir() and d.name.isdigit() and (d / "config" / "localconfig.vdf").is_file():
            ids.append(d.name)
    return sorted(ids, key=lambda x: int(x))


def localconfig_path(steam_root: Path, userid: str | None = None) -> Path | None:
    ids = find_userdata_ids(steam_root)
    if not ids:
        return None
    uid = userid or ids[0]
    p = steam_root / "userdata" / uid / "config" / "localconfig.vdf"
    return p if p.is_file() else None


def read_launch_options_map(lc_path: Path) -> dict[str, str]:
    try:
        text = lc_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return {}
    result: dict[str, str] = {}
    for m in re.finditer(
        r'"(\d+)"\s*\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}',
        text,
        re.S,
    ):
        appid, body = m.group(1), m.group(2)
        lo = re.search(r'"LaunchOptions"\s+"([^"]*)"', body)
        if lo:
            result[appid] = lo.group(1)
        else:
            if appid not in result:
                result[appid] = ""
    return result


def set_launch_options(lc_path: Path, appid: str, options: str) -> bool:
    try:
        text = lc_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    bak = BACKUP_DIR / f"localconfig.vdf.bak.{os.getpid()}"
    try:
        shutil.copy2(lc_path, bak)
    except OSError:
        pass

    appid_re = re.compile(
        rf'("{re.escape(appid)}"\s*\{{)([^{{}}]*(?:\{{[^{{}}]*\}}[^{{}}]*)*)(\}})',
        re.S,
    )
    m = appid_re.search(text)
    if m:
        head, body, tail = m.group(1), m.group(2), m.group(3)
        if re.search(r'"LaunchOptions"\s+"[^"]*"', body):
            new_body = re.sub(
                r'"LaunchOptions"\s+"[^"]*"',
                f'"LaunchOptions"\t\t"{_escape_vdf(options)}"',
                body,
                count=1,
            )
        else:
            indent = "\t\t\t\t\t\t"
            new_body = body.rstrip() + f'\n{indent}"LaunchOptions"\t\t"{_escape_vdf(options)}"\n'
        new_text = text[: m.start()] + head + new_body + tail + text[m.end() :]
    else:
        apps_m = re.search(r'("apps"\s*\{)', text, re.I)
        if not apps_m:
            return False
        insert_at = apps_m.end()
        block = (
            f'\n\t\t\t\t\t"{appid}"\n'
            f"\t\t\t\t\t{{\n"
            f'\t\t\t\t\t\t"LaunchOptions"\t\t"{_escape_vdf(options)}"\n'
            f"\t\t\t\t\t}}\n"
        )
        new_text = text[:insert_at] + block + text[insert_at:]

    try:
        fd, tmp = tempfile.mkstemp(dir=str(lc_path.parent), prefix=".localconfig.", suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(new_text)
        os.replace(tmp, lc_path)
        return True
    except OSError:
        return False


def _escape_vdf(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def list_games(steam_root: Path) -> list[dict[str, Any]]:
    lo_map: dict[str, str] = {}
    lc = localconfig_path(steam_root)
    if lc:
        lo_map = read_launch_options_map(lc)

    games: list[dict[str, Any]] = []
    seen: set[str] = set()
    for lib in library_folders(steam_root):
        for acf in lib.glob("appmanifest_*.acf"):
            meta = parse_simple_acf(acf)
            appid = meta.get("appid") or acf.stem.replace("appmanifest_", "")
            if not appid or appid in seen:
                continue
            name = meta.get("name") or f"App {appid}"
            if "Steamworks" in name or name.startswith("Proton ") or "Redistributable" in name:
                continue
            seen.add(appid)
            options = lo_map.get(appid, "")
            icon = resolve_icon(steam_root, appid, lib)
            games.append(
                {
                    "appid": appid,
                    "name": name,
                    "launchOptions": options,
                    "hasOptions": bool(options.strip()),
                    "icon": icon or "",
                }
            )
    games.sort(key=lambda g: g["name"].lower())
    return games


def resolve_icon(steam_root: Path, appid: str, lib: Path | None = None) -> str | None:
    candidates = [
        steam_root / "appcache" / "librarycache" / f"{appid}_icon.jpg",
        steam_root / "appcache" / "librarycache" / f"{appid}.jpg",
        steam_root / "appcache" / "librarycache" / appid / "header.jpg",
        steam_root / "appcache" / "librarycache" / appid / "library_600x900.jpg",
        steam_root / "appcache" / "librarycache" / appid / "library_hero.jpg",
    ]
    if lib:
        candidates.insert(0, lib / "appcache" / "librarycache" / f"{appid}_icon.jpg")
    for c in candidates:
        if c.is_file():
            return str(c)
    return f"https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/header.jpg"


def apply_defaults(steam_root: Path, default_opts: str) -> dict[str, Any]:
    lc = localconfig_path(steam_root)
    if not lc:
        return {"ok": False, "error": "localconfig.vdf not found", "updated": []}
    lo_map = read_launch_options_map(lc)
    games = list_games(steam_root)
    updated: list[str] = []
    for g in games:
        appid = g["appid"]
        current = lo_map.get(appid, "")
        if current.strip():
            continue
        if set_launch_options(lc, appid, default_opts):
            updated.append(appid)
            lo_map = read_launch_options_map(lc)
    return {"ok": True, "updated": updated, "count": len(updated)}


def get_defaults() -> str:
    if DEFAULTS_FILE.is_file():
        return DEFAULTS_FILE.read_text(encoding="utf-8").rstrip("\n")
    return ""


def set_defaults(opts: str) -> None:
    PLUGIN_STATE.mkdir(parents=True, exist_ok=True)
    DEFAULTS_FILE.write_text(opts + ("\n" if opts and not opts.endswith("\n") else ""), encoding="utf-8")


def main() -> int:
    if len(sys.argv) < 2:
        print(json.dumps({"error": "usage: list|get|set|apply-defaults|defaults-get|defaults-set|steam-path"}))
        return 1
    cmd = sys.argv[1]
    root = find_steam_root()

    if cmd == "steam-path":
        print(json.dumps({"path": str(root) if root else None}))
        return 0

    if cmd == "defaults-get":
        print(json.dumps({"defaults": get_defaults()}))
        return 0

    if cmd == "defaults-set":
        opts = " ".join(sys.argv[2:]) if len(sys.argv) > 2 else ""
        set_defaults(opts)
        print(json.dumps({"ok": True, "defaults": opts}))
        return 0

    if not root:
        print(json.dumps({"error": "Steam root not found", "ok": False}))
        return 1

    if cmd == "list":
        print(json.dumps({"ok": True, "games": list_games(root), "steam": str(root)}))
        return 0

    if cmd == "get":
        if len(sys.argv) < 3:
            print(json.dumps({"error": "appid required"}))
            return 1
        appid = sys.argv[2]
        lc = localconfig_path(root)
        lo = ""
        if lc:
            lo = read_launch_options_map(lc).get(appid, "")
        print(json.dumps({"ok": True, "appid": appid, "launchOptions": lo}))
        return 0

    if cmd == "set":
        if len(sys.argv) < 3:
            print(json.dumps({"error": "appid required"}))
            return 1
        appid = sys.argv[2]
        opts = " ".join(sys.argv[3:]) if len(sys.argv) > 3 else ""
        lc = localconfig_path(root)
        if not lc:
            print(json.dumps({"ok": False, "error": "localconfig.vdf not found"}))
            return 1
        ok = set_launch_options(lc, appid, opts)
        print(json.dumps({"ok": ok, "appid": appid, "launchOptions": opts}))
        return 0 if ok else 1

    if cmd == "apply-defaults":
        opts = " ".join(sys.argv[2:]) if len(sys.argv) > 2 else get_defaults()
        result = apply_defaults(root, opts)
        print(json.dumps(result))
        return 0 if result.get("ok") else 1

    print(json.dumps({"error": f"unknown command {cmd}"}))
    return 1


if __name__ == "__main__":
    sys.exit(main())