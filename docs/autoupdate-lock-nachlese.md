# Nachlese: neun Jahre Guard, der nichts bewachte

Aufgeschrieben am 2026-09-07, nachdem `/tmp/autoupdate.lock` aus diesem Feed
entfernt wurde. Nicht als Schuldzuweisung — der Fehler ist hier im Haus
entstanden —, sondern weil das Muster lehrreich ist: **was passiert, wenn man
eine selbstgebaute Schnittstelle nicht als solche festhält und andere das Paket
forken.**

## Worum es ging

Mehrere Pakete prüften vor einem Reboot oder WLAN-Neustart, ob gerade ein
Autoupdater läuft:

```sh
upgrade_started='/tmp/autoupdate.lock'
[ -f $upgrade_started ] && exit
```

Die Datei wird von nichts angelegt. Der Guard war wirkungslos — ein Reboot
mitten in einem laufenden Update war jederzeit möglich.

Beim Nachsehen fiel zuerst auf, dass `autoupdate.lock` in der **gesamten**
Gluon-Historie (5187 Commits, Tags zurück bis v2014.1) und im Paket-Feed
(892 Commits) **kein einziges Mal** vorkommt. Die naheliegende Hypothese — „das
war mal Gluon-Standard und hat sich geändert" — ist damit widerlegt. Es war nie
Gluon.

## Die Historie

| Datum | Commit | Repo | Was geschah |
| --- | --- | --- | --- |
| 2016-05-06 | `e783d3a` | eulenfunk/packages | Die **Prüfung** entsteht: `upgrade_started='/tmp/autoupdate.lock'` in vier Dateien von `gluon-hotfix`. Commit-Titel: „remove possible race condition during autoupdate" |
| 2016-05-07 | `19d53ae` | eulenfunk/packages | Der **Schreiber** kommt einen Tag später: `gluon-hotfix/files/usr/lib/autoupdater/upgrade.d/00lockfile`, ein `touch`. Titel: „lockfile sicher ist sicher" |
| 2016-09-08 | `1acb4b1` | freifunk-gluon/packages | Gluon bekommt einen **eigenen** Autoupdater-Lock: `/var/lock/autoupdater.lock`, `flock(LOCK_EX\|LOCK_NB)`. Zwölf Zeilen. Niemand merkt, dass es jetzt zwei Mechanismen gibt |
| 2017-02-27 | `49cb4b3` | freifunk-gluon/packages | „autoupdater: new implementation" — der Autoupdater wird von Lua auf C umgeschrieben. Die Hook-Verzeichnisse bleiben, der Lock bleibt |
| 2017-05-28 | `535b9e3` / `6b37acb` | eulenfunk/packages | Zwei Pakete werden zusammengelegt („will be merged with gluon-quickfix"). Der Hook wandert von `gluon-hotfix` nach `gluon-quickfix` |
| 2017-10-04 | `52685ec` | eulenfunk/packages | Merge eines fremden PR (#29, lede-eulenfunk). Der Hook wird **gelöscht** und nie wieder angelegt. Die Prüfungen bleiben |
| 2023-05-10 | `657231f` | freifunk-gluon/community-packages | `ffac-weeklyreboot` wird angelegt, ausdrücklich „taken from https://github.com/eulenfunk/packages" — samt Prüfung, ohne Schreiber |
| 2024-07-02 | `b8359e5` | ffac/gluon-packages | `ffac-mt7915-hotfix` und `ffac-threetime-reboot` mit demselben Muster |
| 2024-08-12 | `3df6ac2` | freifunk-gluon/community-packages | `ffac-mt7915-hotfix` auch dort |
| 2026-09-06 | `ba1a0b8` | Neanderfunk/packages | Befund: die Datei existiert auf keinem Knoten. `now_reboot()` bekommt einen Guard, der wirkt |
| 2026-09-07 | `359de08` | Neanderfunk/packages | Alle Verweise entfernt, samt dem Check `stale_lock`, der allein dazu da war, eine liegengebliebene Kopie dieser Datei zu bemerken |

Stand heute lesen **zehn Dateien in vier fremden Feeds** diese Datei. In keinem
davon legt sie irgendetwas an.

## Was daran wirklich schiefging

Drei Dinge, und keines davon ist „jemand hat schlampig programmiert".

**Der Hook lag im falschen Verzeichnis.** `upgrade.d` läuft unmittelbar vor
dem `sysupgrade`, nicht beim Download. Selbst als alles funktionierte, war nur
die Flash-Phase geschützt — die langen Minuten des Downloads nie. Für
`download.d` gab es das Verzeichnis schon 2016.

**Der Zusammenhang war nirgends festgehalten.** Prüfung und Schreiber standen in
zwei verschiedenen Paketen, verbunden nur durch einen Dateinamen in `/tmp`. Der
Kommentar im Hook sagt zwar „for 3rd-party scripts", aber die 3rd-party-Skripte
selbst sagten nirgends, woher ihr Lock kommt. Beim Zusammenlegen zweier Pakete
war deshalb nicht erkennbar, dass der Hook eine Schnittstelle bedient.

**Der Verlust war unsichtbar.** Ein fehlender Schreiber macht keinen Fehler,
keine Meldung, keinen roten Test. Er macht nur, dass eine Bedingung nie wahr
wird — und ein Guard, der nie greift, verhält sich genau wie ein Guard, den man
nie braucht. Neun Jahre lang.

Und weil das Paket funktionierte, wurde es kopiert. Zweimal ausdrücklich mit
Quellenangabe, was die Übernahme ehrlich macht — aber eben auch den Fehler.

## Was ich daraus mitnehme

* **Eine selbstgebaute Schnittstelle braucht einen Namen und einen Ort.** Wenn
  Paket A etwas anlegt, worauf Paket B sich verlässt, gehört das in beide
  READMEs, nicht in einen Dateinamen unter `/tmp`.
* **Guards muss man scheitern sehen können.** Der Guard, der jetzt drin ist,
  prüft drei Wege (Marker der eigenen Hooks, `/var/lock/autoupdater.lock` per
  `flock`, `pgrep autoupdater|sysupgrade`). Fällt einer weg, tragen die anderen
  — und es fällt eher auf, weil er auch *positiv* auslöst und das ins Log
  schreibt.
* **Beim Übernehmen fremder Pakete gilt dieselbe Frage wie beim eigenen Code:
  wer schreibt das eigentlich?** Ein `grep` nach dem Schreiber hätte den Fehler
  in jedem der vier Feeds in einer Minute gefunden.
* **Ein Merge ist kein neutraler Vorgang.** Der Hook ging beim Zusammenlegen
  zweier Pakete und beim Merge eines fremden PR verloren, zweimal ohne dass es
  jemandem auffiel.

## Wie es heute richtig geht

Der Autoupdater legt seinen Lock selbst an, seit 2016. Aus
`admin/autoupdater/src/autoupdater.c`:

```c
static const char *const download_d_dir = "/usr/lib/autoupdater/download.d";
static const char *const abort_d_dir    = "/usr/lib/autoupdater/abort.d";
static const char *const upgrade_d_dir  = "/usr/lib/autoupdater/upgrade.d";
static const char *const lockfile       = "/var/lock/autoupdater.lock";
...
if (flock(fd, LOCK_EX|LOCK_NB)) { ... }
...
/* Unset FD_CLOEXEC so the lockfile stays locked during sysupgrade */
fcntl(lock_fd, F_SETFD, 0);
```

Die letzten beiden Zeilen sind der Punkt: der Lock wird über den `sysupgrade`
hinweg gehalten, deckt also Download **und** Flash ab. Aus der Shell:

```sh
autoupdater_running() {
	flock -n /var/lock/autoupdater.lock true 2>/dev/null || return 0
	pgrep autoupdater >/dev/null 2>&1 && return 0
	pgrep sysupgrade  >/dev/null 2>&1 && return 0
	return 1
}
```

Ein Wermutstropfen bleibt: weder die Hook-Verzeichnisse noch der Lock stehen in
`docs/features/autoupdater.rst`. Beides ist gelebte, aber ungeschriebene
Schnittstelle — genau die Sorte, um die es in dieser Nachlese geht. Deshalb
prüfen unsere Skripte drei Wege statt einem.
