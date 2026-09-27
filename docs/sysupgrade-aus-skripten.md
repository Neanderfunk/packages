# sysupgrade aus Skripten: nach dem Aufruf kommt nichts mehr

Aufgeschrieben am 2026-09-27, nachdem `flash` aus neanderfunk-banner
monatelang jedes Upgrade mit selbst geladenem Image zerstört hatte
(behoben in 3ecb6e2). Das Muster betrifft jedes Skript, das
`sysupgrade` aufruft und danach noch etwas tut. Das kommt beim Scripten
für Geräte mit wenig RAM oder Flash besonders leicht vor, weil man dort
gern hinter sich aufräumt.

## Kurzfassung

- `sysupgrade` **per `exec`** aufrufen, so wie der Gluon-Autoupdater
  (`execl("/sbin/sysupgrade", ...)`). Nach dem Aufruf darf vom Skript
  nichts mehr laufen.
- Dass `sysupgrade` zurückkehrt, heißt **nicht**, dass nichts geflasht wird.
  Rückgabewert 10 mit "Command failed: Connection failed" heißt: übergeben,
  stage2 läuft.
- Prüfen und aufräumen nur **vorher**: `sysupgrade -T`, sha256, Platz.
  Danach das Image nicht anfassen, keine Dienste starten, keine Hooks
  (`abort.d`) laufen lassen.
- Ruft ein Skript ein anderes auf, das mit `sysupgrade` endet, gilt dasselbe
  für den Aufrufer: `exec`, oder nach der Rückkehr nichts mehr tun.

## Was beim Aufruf passiert (OpenWrt 23.05)

1. `/sbin/sysupgrade` prüft das Image, sichert die Konfiguration und endet
   mit `ubus call system sysupgrade '{ "path": "<image>", ... }'`.
2. procd hält alle Dienste an (`service_stop_all()`) und ersetzt sich dann
   per `execvp()` durch `/sbin/upgraded`. PID 1 ist ab jetzt upgraded.
3. Die ubus-Verbindung von procd trägt `FD_CLOEXEC`, sie geht beim exec zu.
   ubusd verliert damit den Anbieter von `system`, und der wartende
   `ubus call` bekommt sofort "Command failed: Connection failed"
   (`UBUS_STATUS_CONNECTION_FAILED`, 10). **`sysupgrade` kehrt zurück.**
4. upgraded startet `/lib/upgrade/stage2`. Der löscht die Dienste,
   beendet dropbear und alle Prozesse namens `ash`, schickt allen übrigen
   TERM, wartet 4 s, schickt KILL, wartet 6 s, leert den Cache und zieht in
   die Ramdisk um.
5. **Erst dann** liest `do_stage2` das Image (`get_image`) und schreibt es.

Zwischen 3 und 5 liegen rund zehn Sekunden. In QEMU (x86-64) gemessen:
"Commencing upgrade" um 04:21:34, "Performing system upgrade" um 04:21:44.
Ein Skript, das mit `#!/bin/sh` läuft, heißt nicht `ash` und überlebt
Schritt 4 bis zum TERM. Es hat also reichlich Zeit, in diesem Fenster
Schaden anzurichten.

## Was schiefgeht

`flash` hat nach der Rückkehr sein selbst geladenes Image gelöscht, weil es
"kam zurück" als "nichts geflasht" las. stage2 fand die Datei nicht mehr:

```
/lib/upgrade/do_stage2: line 96: can't open /tmp/gluon-...-sysupgrade.img.gz: no such file
upgrade: Invalid partition table on /tmp/image.bs
reboot: Restarting system
```

Der Knoten startet dann mit der alten Firmware neu. Geschrieben wird nichts,
das Gerät ist also nie in Gefahr, das Upgrade findet aber auch nicht statt.

Genauso schädlich wäre alles andere, was ein Aufrufer an dieser Stelle für
"Aufräumen nach Fehlschlag" hält:

- Image oder entpackte Teile löschen, `/tmp` freiräumen;
- `abort.d` des Autoupdaters laufen lassen, also Netz, WLAN und Dienste
  wieder starten, während stage2 das System abbaut;
- Marker für "gescheitert" oder "aufgegeben" setzen, die einen Neuversuch
  auslösen oder verhindern.

## Warum es wie ein RAM-Problem aussah

Aufgefallen ist es zuerst auf einem Archer C25 mit 64 MB. Die serielle
Konsole zeigte dort vor dem eigentlichen Fehler "mount ... /overlay failed:
Resource busy" und "Busy inodes", und mit vorher von Hand geladenem Image
ging es. Beides führte auf die falsche Spur: Die Overlay-Meldungen sind
Begleitrauschen, und das vorgeladene Image ging nur deshalb, weil `flash`
fremde Dateien nie löscht. Erst derselbe Fehler auf einer x86-VM mit fast
1 GB freiem RAM zeigte, dass Speicher keine Rolle spielt.

Merksatz: Geht es mit einer von Hand vorbereiteten Datei und ohne sie
nicht, zuerst nachsehen, was das eigene Skript mit seinen Dateien macht,
bevor man den Speicher verdächtigt.

## Richtig machen

```sh
# Pruefen, solange man noch zurueck kann
sysupgrade -T "$@" "$file" || { rm -f "$file"; exit 1; }

# Hooks des Autoupdaters, falls noetig, VOR dem Aufruf
# (upgrade.d nimmt Netz und WLAN weg: losgeloest laufen, siehe flash)

exec /sbin/sysupgrade "$@" "$file"
```

Kehrt `sysupgrade` doch einmal vor der Übergabe zurück (praktisch
ausgeschlossen, wenn `-T` vorher durchlief), bleiben Image und angehaltene
Dienste stehen. So hält es auch der Autoupdater, und der nächste Reboot
räumt beides weg: `/tmp` liegt im RAM.

Wer ein Upgrade aus einer SSH-Sitzung anstößt, die gleich wegbricht (WLAN
oder Mesh aus), startet den Rest losgelöst:
`start-stop-daemon -S -b -m -p <pidfile> -x /bin/sh -- <skript> ...`. Ohne
eigenes Pidfile vergleicht start-stop-daemon über das Programm, und
`/bin/sh` ist busybox: Jede laufende Shell gälte als "läuft schon". Gluon
hat weder `setsid` noch `nohup`.

## Testen

Ein Upgrade lässt sich ohne zweites Image beweisen: `/lib/gluon/release`
auf einen alten Wert setzen (`echo 20160101 > /lib/gluon/release`) und
dasselbe Image noch einmal flashen. Steht danach wieder die echte Release
drin, wurde geflasht. Die x86-64-Images laufen in QEMU mit serieller
Konsole, dort ist stage2 vollständig zu sehen. Die Key-Firmware erspart den
Setup-Mode, und ohne VPN kommt der Knoten mit `gluon-wan <befehl>` über das
QEMU-Nutzernetz an einen Webserver auf dem Host (10.0.2.2).

## Weitere Stelle im Feed

`neanderfunk-erx-migrate` (zurückgestellt, nicht in der Firmware) hat
dasselbe Muster: `erx-migrate.sh` endet mit `ubus call system sysupgrade`,
und `erx-migrate-run` wertet die Rückkehr als Fehlschlag. Es setzt dann
`/tmp/erx-migrate.aufgegeben` und löscht das Image. Die Migration würde so
scheitern und der Knoten neu starten, stündlich wieder. Vor jedem Einsatz
beheben: den Aufruf von `erx-migrate.sh` per `exec` machen oder nach der
Übergabe nichts mehr tun.
