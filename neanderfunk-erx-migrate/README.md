# neanderfunk-erx-migrate

Bringt einen EdgeRouter X unattended vom alten auf das neue Flash-Layout und
damit von Gluon 2023.2 auf 2025.1.

## Warum es das gibt

Der Kernel 6.6 aus OpenWrt 24.10 ist 3.173.564 Bytes groß. Das alte
ERX-Layout hat zwei Kernel-Slots zu je 3 MB, es fehlen **27 Kilobyte**.
OpenWrt gatet den Wechsel über `compat_version 1.x -> 2.0`.

Das Gate sitzt an der teuersten denkbaren Stelle. Der Autoupdater

1. findet seine Manifest-Zeile,
2. sieht eine neuere Version,
3. lädt das Image komplett (7,2 MB),
4. prüft SHA256 und Signatur, beides stimmt,
5. ruft `sysupgrade --test` auf, und **erst dort** failt der Major-Check.
   `--ignore-minor-compat-version` hilft nicht, der Major-Branch von
   `fwtool_check_image()` wertet das Flag gar nicht aus.
6. Danach fliegt der Mirror aus der Liste und der nächste ist dran.

Bei vier Mirrors und 24 Cron-Runs am Tag sind das rund **690 MB täglich je
Knoten**, und außer in `logread` sieht das niemand.

## Zwei Stages

**Stage 1** ist ein 2023.2-Intermediate-Image, das dieses Paket mitbringt. Es
kommt über den ganz normalen Autoupdater: 2023.2 auf 2023.2 ist
`compat 1.x -> 1.x` und funktioniert heute.

**Stage 2** läuft auf dem Knoten:

    /usr/lib/micron.d/…       einziger Trigger, stündlich zur Minute 37
    /usr/sbin/erx-migrate-run State Machine, holt und prüft das Image
    …/erx-migrate.sh          schreibt Kernel und Rootfs, setzt den Boot-Index
    …/erx-migrate-stage2.sh   baut die UBI-Volumes neu auf, aus dem RAM-Root

Vor einer Stunde Uptime passiert nichts. Failt Stage 2, rebootet der Knoten,
und ein Start kurz nach dem Boot würde daraus einen Boot-Loop im Minutentakt
machen, jetzt liegen mindestens 60 Minuten dazwischen.

Der ganze Run hält `/var/lock/autoupdater.lock`, wie der Autoupdater selbst.
Ist der Lock belegt, wird der Run übersprungen, ein Autoupdater neben der
Migration bricht seinerseits ab.

## Was das Paket nicht anfasst

* **Kein Flash-Write**, solange die Migration nicht wirklich losgeht. Der
  einzige Write ist die Migration selbst.
* **Log und Image liegen in `/tmp`.** Bei jedem Failure wird das Image
  gelöscht, ein ERX hat 256 MB RAM, aber 7 MB je Versuch summieren sich.
* **Kein State über Reboots.** Nach einem Reboot fängt alles von vorn an,
  auch nach einem Abort. Ein Retry je Boot kostet nichts, und der Verzicht
  spart die Frage, wann persistenter State wieder aufzuräumen wäre.

## Deferred oder aborted

`erx-migrate-run` kennt zwei Resultate, und daran hängt der Retry:

| Resultat | Beispiel | Folge |
|---|---|---|
| deferred (im Log `AUFSCHUB`) | kein Uplink, Manifest noch nicht ausreichend signiert, Mirror noch nicht aktuell, Image fehlt oder ist corrupt | micron.d macht in einer Stunde einen Retry |
| aborted (im Log `ABBRUCH`) | Pre-Check failed, Migration nicht durchgeführt | Marker in `/tmp`, kein Retry bis zum nächsten Boot |

## Konfiguration

`/lib/gluon/erx-migrate/ziel.conf` nennt nur die Modelle, nach denen im
Manifest gesucht wird. Beim Build wird nichts eingetragen. Ohne Modell tut das
Paket nichts und beendet sich still.

    ZIEL_MODELL_ERX="ubiquiti-edgerouter-x-ka"
    ZIEL_MODELL_ERX_SFP="ubiquiti-edgerouter-x-sfp-ka"

Das Target steht nicht im Image. `erx-migrate-run` liest Branch, Mirrors, Keys
und `good_signatures` aus der uci-Konfiguration des Autoupdaters, holt
`<mirror>/<branch>.manifest`, prüft die Signaturen mit `ecdsaverify` (Paket
`ecdsautils`) und nimmt Version, Dateiname, Größe und SHA256 aus der
Manifest-Zeile des Modells. Die Prüfung ist die eines normalen Updates, nur
der Threshold ist gedeckelt: `ZIEL_SIGNATUREN` in `ziel.conf` (2), ein Branch
mit weniger behält seinen Wert. Das Paket lädt selbst, weil der Autoupdater
als Downloader nicht taugt: sein `--no-action` greift erst **nach**
`sysupgrade --test`, und genau das failt hier, die Datei ist dann schon
gelöscht.

**Folge:** Jedes neue Release im Branch ist ohne weiteren Schritt das Target
der Migration. Solange unmigrierte ERX im Feld stehen, gehört eine
ERX-Migration vor jedes Release.

## Der Handover an Stage 2

`ubus call system sysupgrade` kehrt auch im Erfolgsfall sofort zurück, mit
Fehler 10, und Stage 2 liest das Image erst rund 10 s später. Der Exit-Code
sagt also nichts. `erx-migrate.sh` legt deshalb vorher
`/tmp/erx-migrate.uebergabe` an und wartet, bis der Teardown es beendet.
`erx-migrate-run` räumt nicht auf, solange die Datei liegt. Lebt das Skript
nach fünf Minuten noch, ist Stage 2 nicht gestartet: Es entfernt Datei und
Watchdog-Marker und startet micrond wieder, der Knoten läuft normal weiter.

## Wenn etwas schiefgeht

    http://[<knoten>]/cgi-bin/erx-migrate-log

Die Seite ist bewusst offen, wie die Statusseite daneben. Im Log steht nichts
Vertrauliches: Partition-Layout, Größen, Checksums, Mirrors, Fehlermeldungen.
Es liegt nur im RAM und ist nach einem Reboot weg.

Wer die Kandidaten sucht: in der Kartenstatistik die EdgeRouter X **ohne
`-ka`** im Imagenamen. Das sind die, die die Migration noch vor sich haben.
Unsere 2025.1-Images heißen `ubiquiti-edgerouter-x-ka`, damit ein nicht
migrierter Knoten seine Manifest-Zeile gar nicht erst findet und der
Autoupdater bei `model_ok` abbricht, vor dem Download, für ein paar KB.

## Das Gegenstück in 2025.1

Zwei Dinge gehören zur Migration, stehen aber nicht in diesem Paket.

**Imagename `-ka`.** Dass ein ERX auf 2025.1 nur noch nach `-ka`-Images sucht,
kommt aus [`devices/erx-ka-imagename.sh`](https://github.com/Neanderfunk/gluon-patches-hardware/blob/v2025.1.x/devices/erx-ka-imagename.sh)
in `gluon-patches-hardware`. Das Skript beschreibt auch, warum der Name da ist
und wie er wieder entfällt. Es wendet zwei Patches an, die zusammengehören:

* Der [OpenWrt-Patch](https://github.com/Neanderfunk/gluon-patches-hardware/blob/v2025.1.x/devices/erx-ka-imagename-openwrt.patch)
  ändert das DTS-`model`, daraus leitet der Knoten seinen Imagenamen ab.
* Der [Gluon-Patch](https://github.com/Neanderfunk/gluon-patches-hardware/blob/v2025.1.x/devices/erx-ka-imagename-gluon.patch)
  ändert das erste Argument von `device()`, also Dateiname und Manifest-Key.

`compatible` bleibt unverändert. `fwtool_check_image()` und das Sysupgrade
merken von der Umbenennung nichts.

**`compat_version` 2.0.** Der höhere Wert ist kein Patch von uns, er kommt aus
OpenWrt 24.10 (`DEVICE_COMPAT_VERSION` in `Device/ubnt_edgerouter_common`,
[`mt7621.mk`](https://github.com/openwrt/openwrt/blob/openwrt-24.10/target/linux/ramips/image/mt7621.mk)).
Der Wert muss aber auch auf dem Gerät ankommen: `/etc/config/system` wandert
mit der Konfiguration zurück, und ein migrierter Knoten stünde sonst wieder auf
`1.1` und würde später Images für das alte Layout annehmen. Deshalb liest
`compat_version_des_images()` in [`erx-migrate.sh`](files/lib/gluon/erx-migrate/erx-migrate.sh)
den Wert aus dem Image, und `hebe_compat_version()` trägt ihn in die
Konfigurationssicherung ein.

## Herkunft

`erx-migrate.sh` und `erx-migrate-stage2.sh` sind Kopien aus einem internen
Repo (`werkzeug/`). Dort liegt die Source of Truth; Änderungen gehören dorthin
und werden hierher übernommen.
