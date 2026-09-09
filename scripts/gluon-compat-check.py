#!/usr/bin/env python3
"""Prueft die Pakete dieses Feeds gegen einen Gluon-Stand.

    scripts/gluon-compat-check.py --gluon ~/projekte/freifunk/firmware/gluon --ref v2025.1.3

Geprueft wird, was ein Paket von Gluon erwartet und was Gluon in dem Stand
tatsaechlich mitbringt:

  DEPENDS   in den Makefiles genannte Gluon-Pakete
  check_site in check_site.lua benutzte Pruefhelfer
  require   aus Lua importierte gluon.*-Module
  API       auf diesen Modulen aufgerufene Funktionen
  Pfad      referenzierte Gluon-Dateien ausserhalb unserer eigenen Pakete

Der Sinn ist der Vergleich zweier Staende: einmal gegen den laufenden und
einmal gegen den Ziel-Stand laufen lassen, die Ausgaben diffen. Was dabei neu
als FEHLT auftaucht, ist die Regression.
"""
import argparse, os, re, subprocess, sys, json
from collections import defaultdict

def git(gluon, *args):
    return subprocess.run(['git', '-C', gluon, *args],
                          capture_output=True, text=True).stdout

def tree_files(gluon, ref):
    return set(git(gluon, 'ls-tree', '-r', '--name-only', ref).split('\n'))

def blob(gluon, ref, path):
    r = subprocess.run(['git', '-C', gluon, 'show', f'{ref}:{path}'],
                       capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None

# Module, die nicht aus Gluon kommen - die pruefen wir hier nicht
# Nicht aus dem Gluon-Baum: OpenWrt/Lua-Bibliotheken, der packages-Feed, und
# Module, die ein Paket selbst mitbringt.
EXTERNAL = {'simple-uci', 'iwinfo', 'posix', 'ubus', 'uci', 'nixio', 'cjson',
            'os', 'io', 'string', 'table', 'math', 'bit32', 'bit',
            'platform_info', 'nodeplacer', 'jsonc', 'json'}

# gluon.site gibt es im Baum nicht als Datei: das Modul wird beim Bauen aus der
# site.conf erzeugt (gluon-site). Vorhanden ist es trotzdem immer, und seine
# Felder kommen aus der site.conf, nicht aus Gluon - eine API-Pruefung waere
# hier sinnlos.
GENERATED = {'gluon.site'}

def collect(feed):
    pkgs = defaultdict(lambda: {'deps': set(), 'requires': set(),
                                'api': set(), 'paths': set()})
    for name in sorted(os.listdir(feed)):
        d = os.path.join(feed, name)
        if not name.startswith('neanderfunk-') or not os.path.isdir(d):
            continue
        p = pkgs[name]
        mk = os.path.join(d, 'Makefile')
        if os.path.exists(mk):
            for m in re.finditer(r'DEPENDS:=(.*?)(?:\n(?!\t|  ))', open(mk).read(), re.S):
                for dep in re.findall(r'\+([A-Za-z0-9_.-]+)', m.group(1)):
                    p['deps'].add(dep)
        for root, _, files in os.walk(d):
            for f in files:
                fp = os.path.join(root, f)
                try:
                    txt = open(fp, errors='replace').read()
                except OSError:
                    continue
                if '\x00' in txt[:200]:
                    continue
                mods = set()
                for m in re.finditer(r"""require\s*\(?\s*['"]([\w.\-]+)['"]""", txt):
                    mod = m.group(1)
                    if mod.split('.')[0] not in EXTERNAL:
                        p['requires'].add(mod); mods.add(mod)
                for mod in mods:
                    short = mod.split('.')[-1]
                    for m in re.finditer(rf'\b{re.escape(short)}\.([a-z_][a-z_0-9]*)\s*\(', txt):
                        p['api'].add((mod, m.group(1)))
                for m in re.finditer(r'(/lib/gluon/[\w./*-]+|/usr/lib/autoupdater/[\w./*-]+)', txt):
                    path = m.group(1)
                    if 'neanderfunk' in path or path.endswith(('*', '.')):
                        continue
                    p['paths'].add(path)
    return pkgs

def gluon_lua_modules(gluon, ref, files):
    """gluon.X -> Dateipfad im Baum"""
    out = {}
    for f in files:
        m = re.search(r'luasrc/usr/lib/lua/gluon/([\w-]+)\.lua$', f)
        if m:
            out['gluon.' + m.group(1)] = f
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--gluon', required=True)
    ap.add_argument('--ref', required=True)
    ap.add_argument('--feed', default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    a = ap.parse_args()

    files = tree_files(a.gluon, a.ref)
    if not files or files == {''}:
        sys.exit(f'kein Baum fuer {a.ref} in {a.gluon}')
    gpkgs = {f.split('/')[1] for f in files if f.startswith('package/')}
    lmods = gluon_lua_modules(a.gluon, a.ref, files)

    # Dateien, die Gluon auf den Knoten legt: alles unter files/ oder luasrc/
    # eines Pakets, der Rest des Pfades ist der Zielpfad.
    delivered = set()
    for f in files:
        for marker in ('/files/', '/luasrc/'):
            if marker in f:
                rest = f.split(marker, 1)[1]
                if rest.startswith(('lib/', 'usr/', 'etc/', 'sbin/', 'bin/')):
                    delivered.add('/' + rest)
                break
    # Verzeichnisse mitzaehlen, damit ein Verweis auf /lib/gluon/upgrade passt
    delivered |= {os.path.dirname(d) for d in list(delivered)}

    # check_site-Helfer: bis 2023.2 Funktionen im Framework, ab 2025.1
    # Methoden einer Validator-Klasse, die per Metatabelle sichtbar gemacht
    # wird. Beide Orte pruefen, sonst meldet man einen Bruch, wo nur ein
    # Refactoring stattfand.
    cs_src = blob(a.gluon, a.ref, 'package/gluon-core/luasrc/lib/gluon/check-site.lua') or ''
    cs_val = blob(a.gluon, a.ref, 'package/gluon-core/luasrc/usr/lib/lua/gluon/validator.lua') or ''
    def helper_ok(h):
        if re.search(rf'(^|[^a-z_]){re.escape(h)}( *=|\()', cs_src, re.M):
            return 'ok'
        if re.search(rf':{re.escape(h)}\b', cs_val):
            return 'ok'
        return None

    pkgs = collect(a.feed)
    print(f"# gluon-compat-check gegen {a.ref}")
    problems = 0
    for name in sorted(pkgs):
        p = pkgs[name]
        lines = []
        for dep in sorted(p['deps']):
            if dep.startswith('neanderfunk-'):
                continue
            if dep.startswith('gluon-') or dep in ('micrond', 'autoupdater'):
                ok = dep in gpkgs or dep in ('micrond', 'autoupdater')
                lines.append(f"    DEPENDS  {dep:<34} {'ok' if ok else 'FEHLT'}")
                problems += 0 if ok else 1
        for mod in sorted(p['requires']):
            if mod in GENERATED:
                lines.append(f"    require  {mod:<34} ok (beim Bauen erzeugt)")
                continue
            ok = mod in lmods
            lines.append(f"    require  {mod:<34} {'ok' if ok else 'FEHLT'}")
            problems += 0 if ok else 1
        for mod, fn in sorted(p['api']):
            if mod in GENERATED or mod not in lmods:
                continue
            src = blob(a.gluon, a.ref, lmods[mod]) or ''
            ok = re.search(rf'^\s*function M\.{re.escape(fn)}\b', src, re.M) is not None
            if not ok and re.search(rf'M\.{re.escape(fn)}\s*=', src):
                ok = True
            lines.append(f"    API      {mod}.{fn:<26} {'ok' if ok else 'FEHLT'}")
            problems += 0 if ok else 1
        csf = os.path.join(a.feed, name, 'check_site.lua')
        if os.path.exists(csf):
            used = sorted(set(re.findall(r'\b(need[a-z_]*|alternatives|in_site)\b',
                                         open(csf).read())))
            for h in used:
                r = helper_ok(h)
                lines.append(f"    check_site {h:<32} {r or 'FEHLT'}")
                problems += 0 if r else 1
        for path in sorted(p['paths']):
            ok = path in delivered
            lines.append(f"    Pfad     {path:<34} {'ok' if ok else '?'}")
        if lines:
            print(f"  {name}")
            for l in lines:
                print(l)
    print(f"# Probleme: {problems}")

main()
