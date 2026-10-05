Manifest-Werkzeuge für alte Knoten
==================================

Damit Knoten mit sehr alter Gluon-Firmware ein heutiges Manifest überhaupt
lesen und darin ihr Image finden. Gedacht für Communities, die
`neanderfunk-legacy-migrate` einbinden. Das Paket übernimmt die Konfiguration
beim Sprung, diese Skripte sorgen dafür, dass der Sprung angeboten wird.

Alle drei sind Bash, BSD-3, ohne weitere Dateien, für jede Gluon-Community
nutzbar (erwartet wird nur die übliche Ablage
`<wurzel>/<domain>/{sysupgrade,factory,other}`). Hilfe jeweils mit `--help`;
die Pfade dort sind Beispiele von Neanderfunk.

| Skript | wofür |
|---|---|
| `manifest-altformat.sh` | ein vorhandenes Manifest um die alten Zeilenformate (4 Felder, sha256 und sha512) und alte Modellnamen ergänzen. **Vor** dem Unterschreiben, es verwirft alle Signaturen. |
| `manifeste-zusammenfuehren.sh` | neues Firmware-Verzeichnis aus zwei Linien per Symlinks: alles aus der Basis (z. B. aktuelles Gluon), dazu aus dem Zusatz (z. B. letzte Version für 4/32-Geräte) die Modelle, die der Basis fehlen; Manifest mit allen Formaten und Aliasen, unsigniert. |
| `manifest-pruefen.sh` | sha256, Größe und Dateiliste der Manifeste gegen die Images prüfen. |

Ablauf: zusammenführen bzw. altformat, prüfen, dann wie gewohnt mit
`ecdsasign` unterschreiben. Achtung: Der Autoupdater prüft mit den
Schlüsseln der **laufenden** Firmware. Signer, die nur noch in alten
Firmwares stehen, zählen für genau diese Knoten.

Was migriert und was nicht, steht im README des Pakets (Abschnitt
„Manifeste für alte Knoten“).

Herkunft: Neanderfunk Router-Werkstatt `werkzeug/firmwareserver/`, Stand
bea3722 (05.10.2026). Änderungen bitte dort, diese Kopie wird nachgezogen.
