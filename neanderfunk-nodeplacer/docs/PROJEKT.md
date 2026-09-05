# Freifunk-Gluon NodePlacer

Community-Package fuer die Freifunk-Gluon-Router-Firmware: Knoten, die aus
welchen Gruenden auch immer in der falschen Layer-2-Domain laufen, werden
serverseitig gesteuert in die sinnvollere Domain transferiert.

Paketname: **neanderfunk-nodeplacer** (Community-Praefix, D-029). Das Ding
selbst heisst weiterhin `nodeplacer`: so heissen das Kommando, die
UCI-Config, der site.conf-Block und die Steuerdatei. Arbeitstitel war
"domainswitch", siehe D-001 in [docs/DECISIONS.md](docs/DECISIONS.md).

## Repositories

* https://github.com/Adorfer/neanderfunk-nodeplacer-dev: dieses Entwicklungs-Repo, das
  vollstaendige Projekt (Paket, Doku, Skizzen, Hilfsskripte, Tests).
  Hier wird gearbeitet.
* https://github.com/Neanderfunk/packages, Branch `v2023.2.x`: der
  Gluon-Package-Feed der Community. Dorthin wird nur eine Teilmenge
  gespiegelt, als Verzeichnis `neanderfunk-nodeplacer/`:

  | hier | im Feed |
  |---|---|
  | `neanderfunk-nodeplacer/` | `neanderfunk-nodeplacer/` |
  | `docs/` | `neanderfunk-nodeplacer/docs/` |
  | `README.md` | `neanderfunk-nodeplacer/docs/PROJEKT.md` |

  Erzeugt und nachgezogen mit `scripts/sync-to-feed.sh` (ein Commit je
  Lauf, die Feed-Historie wird nie umgeschrieben). Im Feed nichts direkt
  bearbeiten, Aenderungen gehen dort beim naechsten Lauf verloren.

## Status

Paket vorhanden (`neanderfunk-nodeplacer/`), auf x86-64 gebaut und getestet, siehe
[docs/TESTING.md](docs/TESTING.md). Erstes Ziel ist ein Release fuer
Single-Domain-Firmware (Methode `firmware`); Multidomain ist bis danach
zurueckgestellt (D-026). Bisher primaer bei Neanderfunk getestet - Erfahrung
mit anderen Site-Konfigurationen und Communities fehlt noch (D-038).
**PRs and suggestions welcome!**

| Dokument | Inhalt |
|---|---|
| [neanderfunk-web-nodeplacer/](neanderfunk-web-nodeplacer/) | optionales Config-Mode-Modul, Tab "Nodeplacer" unter "Advanced settings" mit dem disable-Schalter |
| [docs/DESIGN.md](docs/DESIGN.md) | Ziel, Mechanismus, Betriebsmodi, Sicherheits- und Robustheitsueberlegungen, offene Fragen |
| [docs/MANIFEST-FORMAT.md](docs/MANIFEST-FORMAT.md) | Entwurf des Steuerdatei-Formats |
| [docs/RESEARCH.md](docs/RESEARCH.md) | Was Gluon 2023.2.x bereits mitbringt, mit Fundstellen im Quellcode |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Laufendes Entscheidungs-Log (wird fortgeschrieben) |
| `sketches/`, `scripts/`, `tests/` | Skizzen, Hilfsskripte, Host-Tests (nur im Entwicklungs-Repo) |

## Werkzeug: Manifest-Linter

`scripts/lint-nodeplacer-manifest.py` prueft eine `nodeplacer.manifest`
**vor** dem Signieren gegen dieselben Regeln, die `nodeplacer-fetch` und
`nodeplacer.manifest` (Lua) auf dem Knoten anwenden, plus ein paar
zusaetzliche Warnungen fuer haeufige Tippfehler (D-036). Reiner
Python-3-Standardbibliothek-Code, keine Abhaengigkeiten, laeuft auf dem
Firmwareserver:

```bash
scripts/lint-nodeplacer-manifest.py nodeplacer.manifest
echo $?   # 0 = in Ordnung, 1 = Fehler gefunden (nicht signieren), 2 = Aufruffehler
```

## Ziel

* Package (Community-Erweiterung) fuer Freifunk-Gluon.
* Verschieben eines Knotens in eine andere Domain der **gleichen Community**
  (gleicher Firmware-Server, gleiche Signaturschluessel).
* Zwei Wege, je nach Firmware-Typ:
  * **Multidomain-Firmware:** lokale Konfigurationsaenderung
    (`gluon.core.domain`), sofern die Zieldomain in der installierten Firmware
    enthalten ist.
  * **Single-Domain-Firmware:** Laden der passenden Ziel-Firmware vom
    Autoupdate-Server der Zieldomain ueber den regulaeren Autoupdater.
* Steuerung ueber eine signierte Manifest-Datei auf einem Server, analog zum
  Autoupdater-Manifest. Adressierung einzelner Knoten ueber ihre Node-ID.

## Grenzen

nodeplacer ist fuer Umzuege innerhalb einer Community gedacht. Umzuege in
Domains fremder Communities verlangen ein zwischen den Communities
abgestimmtes Verfahren (Registrierung in der Zieldomain, passende
Migrations-Firmware, Zeitpunkt). Knoten "kalt" in eine fremde Domain zu
schieben ist off limits. Details in DESIGN.md Abschnitt 15.

## Kompatibilitaet

* Primaeres Ziel: **Gluon v2023.2.x** (aktueller Firmware-Stand von
  Neanderfunk/Eulenfunk).
* Perspektive: v2025.1.x.
* Backport: v2021.1.x (Hinweis: es gibt kein Gluon "2021.2"; die letzte
  2021er-Reihe ist v2021.1.x).

## Aehnliche Projekte (andere Umsetzung)

* [gluon-hoodselector](https://gluon.readthedocs.io/en/latest/package/gluon-hoodselector.html)
  waehlt die Domain dezentral anhand der Geokoordinaten des Knotens.
* [gluon-config-mode-domain-select](https://gluon.readthedocs.io/en/latest/package/gluon-config-mode-domain-select.html)
  laesst den Besitzer die Domain im Config-Mode waehlen.
* [gluon-scheduled-domain-switch](https://gluon.readthedocs.io/en/latest/package/gluon-scheduled-domain-switch.html)
  (Gluon-Core) schaltet eine ganze Domain zu einem Zeitpunkt auf eine andere um.
* [ffac-scheduled-sysupgrade](https://github.com/freifunk-gluon/community-packages/tree/v2023.2.x/ffac-scheduled-sysupgrade)
  zieht per Autoupdater ein Image von einem festen Server und flasht es
  zeitgesteuert.
* [ffac-change-autoupdater](https://github.com/freifunk-gluon/community-packages/tree/v2023.2.x/ffac-change-autoupdater)
  und das eigene
  [eulenfunk-migrate-updatebranch](https://github.com/eulenfunk/packages/tree/v2023.2.x/eulenfunk-migrate-updatebranch)
  setzen beim Upgrade den Autoupdater-Branch um.

Keines davon adressiert einzelne Knoten von einem Server aus. Das ist die
Luecke, die dieses Package fuellen soll.

## Umfeld

* Firmware-Build: `~/projekte/freifunk/firmware` (build.sh, Sites-Dateien,
  Templates), Gluon-Checkout unter `firmware/gluon` auf Branch v2023.2.x.
* Eigener Package-Feed: https://github.com/eulenfunk/packages (Branch
  v2023.2.x), wird ueber `modules` der Site als Feed `eulenfunk` eingebunden.
* Die Neanderfunk-Firmware ist **Single-Domain** pro Site (eine site.conf pro
  Domain, z. B. `10_wlf`, `21_dias`), mit Branches `stable` und `broken`
  und eigenen Mirror-URLs je Domain.
