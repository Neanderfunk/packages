# neanderfunk-erx-migrate

Bringt einen EdgeRouter X unbeaufsichtigt vom alten auf das neue
Flash-Layout und damit von Gluon 2023.2 auf 2025.1.

## Warum es das gibt

Der Kernel 6.6 aus OpenWrt 24.10 ist 3.173.564 Bytes gross. Das alte
ERX-Layout hat zwei Kernel-Slots zu je 3 MB — es fehlen **27 Kilobyte**.
OpenWrt riegelt den Wechsel ueber `compat_version 1.x -> 2.0` ab.

Der Riegel sitzt an der teuersten denkbaren Stelle. Der Autoupdater

1. findet seine Manifestzeile,
2. sieht eine neuere Version,
3. laedt das Image vollstaendig (7,2 MB),
4. prueft SHA256 und Signatur — beides stimmt,
5. ruft `sysupgrade --test` auf, und **erst dort** faellt der major-Vergleich
   durch. `--ignore-minor-compat-version` hilft nicht, der major-Zweig von
   `fwtool_check_image()` wertet das Flag gar nicht aus.
6. Danach fliegt der Mirror aus der Liste und der naechste ist dran.

Bei vier Mirrors und 24 Cronlaeufen am Tag sind das rund **690 MB taeglich je
Knoten** — und ausser in `logread` sieht das niemand.

## Zwei Stufen

**Stufe 1** ist ein 2023.2-Zwischenimage, das dieses Paket mitbringt. Es kommt
ueber den ganz normalen Autoupdater: 2023.2 auf 2023.2 ist `compat 1.x -> 1.x`
und funktioniert heute.

**Stufe 2** laeuft auf dem Knoten:

    /etc/init.d/erx-migrate   START=99, erster Versuch 5 Minuten nach dem Boot
    /usr/lib/micron.d/…       stuendlicher Neuversuch
    /usr/sbin/erx-migrate-run Zustandsmodell, holt und prueft das Image
    …/erx-migrate.sh          schreibt Kernel und Rootfs, setzt den Boot-Index
    …/erx-migrate-stage2.sh   baut die UBI-Volumes neu auf, aus dem RAM-Root

`/etc/rc.local` waere der falsche Haken: es steht in den conffiles von
`base-files`, reist in `/sysupgrade.tgz` mit und ueberschreibt beim Upgrade die
Fassung aus dem neuen Image. Ein Hook dort kaeme auf keinem Knoten an, der
seine Konfiguration behaelt. `init.d`-Skripte liegen im squashfs.

## Was das Paket nicht anfasst

* **Kein Schreibzugriff aufs Flash**, solange die Migration nicht wirklich
  losgeht. Der einzige Schreibvorgang ist die Migration selbst.
* **Log und Image liegen in `/tmp`.** Bei jedem Fehlschlag wird das Image
  geloescht — ein ERX hat 256 MB RAM, aber 7 MB je Versuch summieren sich.
* **Kein Zustand ueber Neustarts.** Nach einem Reboot faengt alles von vorn an,
  auch nach einer endgueltigen Absage. Ein Neuversuch je Boot kostet nichts,
  und der Verzicht spart die Frage, wann persistenter Zustand wieder
  aufzuraeumen waere.

## Aufschub oder Absage

`erx-migrate-run` unterscheidet zwei Enden, und daran haengt der Neuversuch:

| | Beispiel | Folge |
|---|---|---|
| Aufschub | kein Uplink, zu wenige Signaturen, Mirror hinkt hinterher, Image fehlt oder ist kaputt | micron.d probiert in einer Stunde |
| endgueltig | Vorpruefung durchgefallen, Migration nicht durchgefuehrt | Marker in `/tmp`, Ruhe bis zum Boot |

## Einrichten

`/lib/gluon/erx-migrate/ziel.conf` nennt nur die Modelle, nach denen im
Manifest gesucht wird. Beim Bau wird nichts eingetragen. Ohne Modell tut das
Paket nichts und beendet sich still.

    ZIEL_MODELL_ERX="ubiquiti-edgerouter-x-ka"
    ZIEL_MODELL_ERX_SFP="ubiquiti-edgerouter-x-sfp-ka"

Das Ziel steht nicht im Image. `erx-migrate-run` liest Zweig, Mirrors, Schluessel
und `good_signatures` aus der uci-Konfiguration des Autoupdaters, holt
`<mirror>/<zweig>.manifest`, prueft die Signaturen mit `ecdsaverify` (Paket
`ecdsautils`) und nimmt Version, Dateiname, Groesse und SHA256 aus der
Modellzeile. Die Pruefung ist die eines normalen Updates, nur die Schwelle ist
gedeckelt: `ZIEL_SIGNATUREN` in `ziel.conf` (2), ein Zweig mit weniger behaelt
seinen Wert. Das Paket laedt selbst, weil der Autoupdater als Downloader nicht taugt:
sein `--no-action` greift erst **nach** `sysupgrade --test`, und genau das
scheitert hier — die Datei ist dann schon geloescht.

**Folge:** Jedes neue Release im Zweig ist ohne weiteren Schritt das Ziel der
Migration. Solange unmigrierte ERX im Feld stehen, gehoert eine ERX-Migration
vor jedes Release.

## Die Uebergabe an Stufe 2

`ubus call system sysupgrade` kehrt auch im Erfolgsfall sofort zurueck, mit
Fehler 10, und Stufe 2 liest das Image erst rund 10 s spaeter. Der Exitcode sagt
also nichts. `erx-migrate.sh` legt deshalb vorher
`/tmp/erx-migrate.uebergabe` an und wartet, bis der Abbau es beendet.
`erx-migrate-run` raeumt nicht auf, solange die Datei liegt. Lebt das Skript nach
fuenf Minuten noch, ist Stufe 2 nicht gestartet: Es entfernt Datei und
Watchdog-Marker und startet micrond wieder, der Knoten laeuft normal weiter.

## Wenn etwas schiefgeht

    http://[<knoten>]/cgi-bin/erx-migrate-log

Die Seite ist bewusst offen, wie die Statusseite daneben. Im Log steht nichts
Vertrauliches: Partitionslayout, Groessen, Pruefsummen, Mirrors,
Fehlermeldungen. Es liegt nur im RAM und ist nach einem Neustart weg.

Wer die Kandidaten sucht: in der Kartenstatistik die EdgeRouter X **ohne
`-ka`** im Imagenamen. Das sind die, die die Migration noch vor sich haben.
Unsere 2025.1-Images heissen `ubiquiti-edgerouter-x-ka`, damit ein nicht
migrierter Knoten seine Manifestzeile gar nicht erst findet und der
Autoupdater bei `model_ok` abbricht — vor dem Download, fuer ein paar KB.

## Herkunft

`erx-migrate.sh` und `erx-migrate-stage2.sh` sind Kopien aus der
Routerwerkstatt (`werkzeug/`). Dort liegt die massgebliche Fassung; Aenderungen
gehoeren dorthin und werden hierher uebernommen.
