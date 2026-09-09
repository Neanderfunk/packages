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

Aus Lua oder von der Kommandozeile:

```sh
nf-reboot-log "[$check] $grund"
```

Und der Reboot selbst, statt `sync` plus `reboot -f`:

```sh
nf_reboot_hard        # aus der Shell
nf-reboot             # aus Lua oder von der Kommandozeile
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

Der Pfad liegt deshalb hier und nicht in einem der Pakete: es schreiben mehrere
hinein, und keines soll vom anderen abhängen. Erfasst sind alle Stellen im
Feed, die einen Knoten neu starten — `hotfix` (`now_reboot()` und der
Watchdog), `linkcheck` (vierte Stufe und Gateway) und `wifi-blackout`.

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

### Sparsam mit forks

`watchdog.sh` arbeitet ab einem bestimmten Punkt bewusst fork-frei: der Fall,
für den es den Watchdog gibt, schließt Speichermangel ein, und dann kann das
Starten eines weiteren Prozesses schlicht fehlschlagen. Damit dort trotzdem
etwas ins Log kommt, ist `nf_reboot_log()` so sparsam wie möglich:

* Gezählt wird mit `read` statt mit `wc -l` — ein Builtin, kein fork.
* Wer den Deckel vorab auflösen will, ruft beim Start
  `nf_reboot_log_preload` auf; danach fragt `nf_reboot_log()` kein `uci`
  mehr.
* Bleibt `date` als einziger fork. Schlägt der fehl, steht statt der Uhrzeit
  `uptime=NNNNs` in der Zeile — die kommt aus `/proc/uptime` und braucht
  keinen. Ohne RTC ist das ohnehin oft die ehrlichere Angabe.

Geschrieben wird unmittelbar vor einem harten Reboot. Ein abgerissener
Schreibvorgang ist deshalb keine Ausnahme, sondern zu erwarten: eine letzte
Zeile ohne `\n` wird mitgezählt und bekommt ihr Newline nachgereicht, damit
der nächste Eintrag nicht an die halbe Zeile geklebt wird.

## Der Reboot selbst

`nf_reboot_hard` macht der Reihe nach: alles auf den Flash bringen, `reboot -f`,
und wenn das Gerät danach immer noch läuft, über sysrq nachhelfen. Die drei
Teile gibt es auch einzeln (`nf_reboot_flush`, `nf_reboot_wait`,
`nf_reboot_escalate`) — `watchdog.sh` braucht sie so.

### Warum nicht einfach `sync`

Keiner der Wege genügt für sich:

| | forkt | kann hängen | wartet bis fertig |
|---|---|---|---|
| `sync` | **ja** (bei busybox kein Builtin) | **ja** (klemmender Flash) | ja |
| `echo s > /proc/sysrq-trigger` | nein | nein | **nein** |

Dazu kommt beim sysrq-Weg ein Detail aus `fs/sync.c`: `emergency_sync()` holt
sein work item mit `kmalloc(GFP_ATOMIC)`, und schlägt das fehl, fällt der Sync
ersatzlos und stillschweigend aus. Ausgerechnet unter Speichermangel — also
genau dann, wenn der Watchdog zuschlägt — ist darauf kein Verlass.

`nf_reboot_flush` stößt deshalb beides an: `sync` im **Hintergrund**, damit es
uns nicht aufhalten kann, plus sysrq `s`, und wartet danach ein paar Sekunden.
Gewartet wird bevorzugt mit `sleep`; lässt sich das nicht forken, über
`/proc/uptime` busy — `read` ist ein Builtin. CPU zu verbrennen ist auf einem
Gerät, das gleich neu startet, der kleinere Preis.

### Wenn der Reboot selbst hängenbleibt

`reboot -f` ruft `reboot(RB_AUTOBOOT)`, der Kernel geht durch
`device_shutdown()`, und ein Treiber, dessen `shutdown` hängt, hält dort alles
an: kein Warmstart, kein Zurückkommen — und der aufrufende Prozess klebt im
Syscall fest. Deshalb schickt `nf_reboot_hard` den Reboot in den Hintergrund;
sonst wartet die Shell mit ihm zusammen ewig und käme zur Eskalation nie.

`nf_reboot_escalate` wartet 60 s und schickt dann sysrq `b`. Das geht über
`emergency_restart()`, überspringt `device_shutdown()` und startet sofort neu —
also genau das richtige Mittel gegen einen hängenden regulären Reboot. Vorher
geht eine Zeile nach `/dev/kmsg`, damit der Fall überhaupt auffällt.

Bewusst `b` und nicht `o`: `o` ist poweroff. Ein Knoten, der aus ist, ist
schlechter dran als einer, der hängt — er kommt ohne Hand am Stecker nie wieder,
und bei den meisten Routern tut `o` ohnehin nichts, weil es gar keine
Abschaltmöglichkeit gibt.

`/proc/sysrq-trigger` ignoriert übrigens die `kernel.sysrq`-Maske
(`write_sysrq_trigger` ruft `__handle_sysrq(c, false)`), der Weg steht also
unabhängig von der sysctl-Einstellung offen. Nachgesehen im Buildtree: auf
allen Zielen, die wir bauen — ath79 (generic/nand/mikrotik), ramips mt7621,
mediatek filogic und mt7622, x86 — ist `CONFIG_MAGIC_SYSRQ=y`. Das `[ -w ]` vor
dem Schreiben bleibt trotzdem stehen, für den Fall, dass ein Ziel dazukommt, wo
das nicht gilt.
