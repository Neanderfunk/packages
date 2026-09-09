# neanderfunk-common

Bausteine, die mehrere Pakete dieses Feeds brauchen. Sie liegen hier, damit es
sie nicht mehrfach gibt: zwei Kopien derselben Funktion in zwei Paketen laufen
irgendwann auseinander, und niemand merkt es — siehe
`docs/autoupdate-lock-nachlese.md`.

## Prozesssuche, die sich selbst nie findet

Zum Sourcen aus Shell-Skripten:

```sh
. /lib/gluon/neanderfunk/proc.sh

nf_running autoupdater      # 0, wenn mindestens einer laeuft
nf_count tunneldigger       # Anzahl, immer eine Zahl
nf_pids  watchdog.sh        # PIDs, eine je Zeile
```

Für alles, was nicht sourcen kann (Lua, andere Sprachen), dieselbe Funktion als
Kommando:

```sh
nf-pgrep autoupdater        # PIDs; Rueckgabe 1, wenn keiner laeuft
nf-pgrep -c tunneldigger    # nur die Anzahl
nf-pgrep -q autoupdater     # nur die Rueckgabe
nf-ps | grep -c hostapd     # ps-Ersatz fuer Stellen, die anschliessend greppen
```

### Warum

`ps | grep name` und `pgrep -f muster` finden regelmäßig den Suchenden statt des
Gesuchten. Am Knoten gemessen, 2026-09-09:

* `pgrep -f autoupdater` lieferte **drei PIDs, von denen keine der Autoupdater
  war** — darunter ein Skript, das seinerseits nur nach „autoupdater" suchte.
* `pgrep -f /usr/bin/tunneldigger` fand die SSH-Sitzung, die die Suche abgesetzt
  hatte, weil der String in ihrer Kommandozeile stand.
* Aus einem Aufrufer, dessen Kommandozeile das Wort führt, zählte
  `ps | grep -c "[t]unneldigger"` **fünf** statt drei. Der Klammertrick
  verhindert nur, dass das `grep` sich selbst sieht.

Das ist nicht bloß unsauber: zwei Prüfungen in `neanderfunk-hotfix` lösen bei zu
hohem Zählerstand einen **Reboot** aus.

### Wie

`nf_pids` vergleicht den Prozessnamen (`comm`) **exakt** — kein Muster, kein
Teilstring, und schon gar nicht die Kommandozeile. Ausgeblendet wird die eigene
Elternkette und alles, was ein Glied dieser Kette gestartet hat; damit fällt auch
das `grep` derselben Pipeline heraus.

Zwei Eigenheiten der Plattform, die dabei zu beachten waren:

* **Die Prozessgruppe taugt nicht als Kriterium.** Unter procd läuft alles ohne
  Job Control, deshalb steht auf diesen Geräten bei praktisch jedem Prozess
  `pgrp=1` — beim Suchenden wie beim Gesuchten. Ein erster Entwurf über die
  Prozessgruppe blendete schlicht alles aus.
* **PID 1 gehört nicht in die Kette.** Unter procd hängen fast alle Dienste
  direkt an der 1; wer deren Kinder ausblendet, findet nie wieder einen Daemon.

`comm` ist auf 15 Zeichen begrenzt und steht bei Skripten auf dem Skriptnamen
(`watchdog.sh`), Skripte sind also findbar. Bei Aufrufen der Form `sh -c …`
steht dort allerdings `sh` — solche Ziele lassen sich so nicht unterscheiden,
dafür bleibt `nf-ps | grep`.

### Was es nicht kann

Einen **fremden** Prozess erkennen, der zufällig denselben String führt — etwa
ein anderes Skript, das gleichzeitig nach demselben Namen sucht. Dagegen hilft
kein Selbstfilter, sondern nur der exakte Namensvergleich, also `nf_pids` statt
`nf-ps | grep`.

### Kosten

`/proc` einmal durchlesen: am Knoten 107 Prozesse in 0,03 s, fork-frei. Fünf
`nf-pgrep`-Aufrufe hintereinander brauchten 0,24 s inklusive Prozessstart.

## Gemeinsames Reboot-Log

Zum Sourcen aus Shell-Skripten:

```sh
. /lib/gluon/neanderfunk/reboot.sh
nf_reboot_log "[$check] $grund"
```

Schreibt eine Zeile nach `/lib/gluon/neanderfunk/reboot.log`: Datum plus den
übergebenen Grund. Die Zeile darf lang sein, aber es bleibt bei einer je
Reboot.

### Warum

Ein Reboot, den ein Check auslöst, ist danach nicht mehr nachweisbar — die
Logzeile stand im Ringpuffer, und der ist weg. Bis hierher schrieb nur
`neanderfunk-hotfix` seine Gründe mit, unter einem eigenen Pfad;
`neanderfunk-linkcheck` rief in der vierten Stufe direkt `reboot -f` und
hinterließ nichts. Auf die Frage „warum ist der Knoten neu gestartet" gab es
für die Hälfte der Reboots keine Antwort mehr.

Der Pfad liegt deshalb jetzt hier und nicht in einem der beiden Pakete: es
schreiben zwei hinein, und keines soll vom anderen abhängen.

### Deckel

Voreingestellt sechs Zeilen, gemeinsam über alle Pakete. Es geht um die
**ersten** Reboots nach einem Firmwarestand, nicht um eine Chronik — ein Knoten,
der in einer Schleife hängt, soll nicht über Jahre in den Flash schreiben.

Auf dem Knoten:

```sh
uci set neanderfunk.settings.reboot_log_max='10'
uci commit neanderfunk
```

Gemeinschaftsweit in der `site.conf`, optional:

```lua
neanderfunk = {
  reboot_log_max = 6,   -- 0 = kein Reboot-Log
},
```

`0` schaltet das Log ganz ab: es wird nichts geschrieben und die Datei nicht
angelegt. Ein bereits vorhandenes Exemplar wird nicht gelöscht — beim nächsten
Firmware-Update ist es ohnehin weg.

Fehlt der Schlüssel in der `site.conf`, bleibt es bei der eingebauten Vorgabe;
es gibt bewusst keine `check_site.lua` dafür, damit eine Site, die ihn nicht
kennt, weiter baut. Der uci-Wert auf dem Knoten gewinnt immer über die
`site.conf`. Ein Wert, der nicht aus reinen Ziffern besteht, fällt auf die
Vorgabe zurück statt das Log stillschweigend abzuschalten.

Der Deckel ist eine Obergrenze, keine Punktbedingung (`-ge`, nicht `-eq`):
findet sich dort aus irgendeinem Grund schon eine zu lange Datei, wächst sie
trotzdem nicht weiter.

### Lebensdauer

Die Datei liegt unter `/lib/gluon/` und überlebt ein Firmware-Update
absichtlich **nicht** — `sysupgrade` bewahrt dort nur
`/lib/gluon/core/sysconfig/`. Nach einem Update zählt es wieder von vorn.
