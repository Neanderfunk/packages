# gluon-reconfigure: wie Gluon seine Konfiguration erzeugt

Stand 2026-09-10. Gelesen im Quelltext von Gluon **v2023.2.6** und **v2025.1.3**
(Baum `~/projekte/freifunk/firmware/gluon`, Tags). Was am Gerät nachgeprüft
ist, steht ausdrücklich dabei.

Anlass: Die offizielle Doku beschreibt `gluon-reconfigure` nur knapp. Beim
Bauen von `neanderfunk-txpowerfix` und `neanderfunk-preserve-wifichannel` haben
wir uns an mehreren Stellen auf Annahmen gestützt, die nicht stimmten — etwa,
dass im Setup-Mode keine Upgrade-Skripte laufen. Das hier ist das, was im Code
steht.

## Was es ist

`/usr/bin/gluon-reconfigure` (gluon-core) ist ein kurzes Shell-Skript:

```sh
cd /lib/gluon/upgrade || exit 1
for script in *; do
	./"$script" || err=1
done
```

* Die Skripte laufen **alphabetisch**, jedes als **eigener Prozess**. Deshalb
  müssen sie ausführbar sein, und keine Lua-Variable überlebt von einem Skript
  zum nächsten.
* Ein fehlschlagendes Skript bricht den Lauf **nicht** ab. Alle folgenden
  laufen trotzdem, am Ende gibt `gluon-reconfigure` 1 zurück.
* Die Skripte kommen aus allen installierten Paketen, Gluons und unseren,
  gemischt in einem Verzeichnis. Die Nummer im Dateinamen ist die einzige
  Reihenfolge-Regel.

## Wer es auslöst

| Auslöser | wann | Hinweis |
| --- | --- | --- |
| `/etc/uci-defaults/zzz-gluon-upgrade` | erster Boot nach Flash oder sysupgrade | läuft über `S10boot`, mit `sleep 3` davor (Gluon #2779). **Auch im Setup-Mode:** `gluon-setup-mode` verlinkt `S10boot` und `S10gluon-core-reconfigure` per Makefile (`init_links`) in sein rc.d, in der Dateiliste des Pakets tauchen die Links nicht auf. Der erste Lauf einer Neuinstallation findet also beim Erstboot statt, **vor** dem Config-Mode-Wizard. |
| `/etc/init.d/gluon-core-reconfigure` (S10) | Boot, wenn `gluon.core.reconfigure=1` | gesetzt von `gluon-switch-domain`; gelöscht von `998-commit` |
| Config-Mode-Wizard (`wizard.lua`) | „Speichern & Neustarten" | läuft im CGI-Prozess von uhttpd, siehe [Zeitlimit](#zeitlimit-im-config-mode) |
| `gluon-switch-domain <domain>` | Domainwechsel, z. B. durch den nodeplacer | im Setup-Mode direkt `gluon-reconfigure`; sonst `reconfigure=1` und Reboot, mit `--no-reboot` stattdessen `gluon-reload` (stoppt Netz und Dienste, ruft über `reload.d/710-gluon-core-reconfigure-start` den Reconfigure auf, startet wieder). Der nodeplacer nimmt den Weg über den Reboot. |
| Erweiterte Einstellungen | Speichern | **nur 2025.1**: `wifi-config` (seit Upstream `e742f024`) und `privatewifi` rufen `gluon-reconfigure`. In 2023.2 ruft `wifi-config` nur `/lib/gluon/upgrade/200-wireless` auf; die übrigen Skripte laufen dann nicht. |
| von Hand | per SSH | siehe [Per SSH](#per-ssh) |

## Ablauf eines Laufs

Die Stellen, die man beim Schreiben eigener Skripte kennen muss, in
Laufreihenfolge. Unsere Skripte stehen mit dabei.

| Skript | Paket | tut |
| --- | --- | --- |
| `001-reset-uci` | gluon-core | **zuerst `uci commit`** (alles, was bis dahin offen war), dann `network` und `system` nach `*_gluon-old` verschieben und **neu erzeugen** (`config_generate`). 2025.1 legt zusätzlich eine Kopie von `wireless` ab, erzeugt es aber nicht neu. Liegt schon ein `*_gluon-old` (abgebrochener Lauf), bleibt es. |
| `005-set-domain` | gluon-core | `gluon.core.switch_domain` → `gluon.core.domain` (nur Multi-Domain) |
| `180-outdoors` | gluon-core | legt `gluon.wireless.outdoor` an, wenn es fehlt; bei Neuinstallation aus `wifi5.outdoors` (Default `preset`: Outdoor-Geräte mit 5 GHz) |
| `185-neanderfunk-preserve-wifichannel` | unser | `preserve_channels` aus der Site setzen oder vormerken; bei Site-/Domain-/Outdoor-Wechsel für diesen Lauf aufheben |
| `190-preserve-wireless-channels` | gluon-core | schreibt `gluon.wireless.preserve_channels` (0, wenn es fehlt). Andere Optionen der Sektion bleiben stehen. |
| `200-wireless` | gluon-core | Radios, Kanäle, htmode, Mesh-Interfaces. Bei `preserve_channels=1` bleiben Kanal, Kanalliste und htmode stehen, `country3` und das 5-GHz-Mesh im Outdoor-Modus werden trotzdem gesetzt. |
| `205-neanderfunk-preserve-wifichannel` | unser | nach reinem Outdoor-Wechsel die übrigen Bänder zurückschreiben |
| `215-neanderfunk-txpower-fix` | unser | Country, htmode; einmalig festgeschriebene txpower entfernen |
| `225-neanderfunk-preserve-wifichannel` | unser | Aufhebung zurücknehmen, Vormerkung einlösen, Stand merken |
| `300-setup-mode` | gluon-setup-mode | bei `setup_mode.skip` → `configured=1`. **Läuft nach allen 2xx-Skripten**; wer vorher wissen will, ob ein Wizard kommt, liest `site.setup_mode.skip` selbst. |
| `320-gluon-client-bridge-wireless` | gluon-client-bridge | legt `client_radioN`/`owe_radioN` an — wer die aufzählen will, muss danach laufen |
| `490` … `910` | unser | übrige Neanderfunk-Pakete |
| `997-migrate-preserved` | gluon-core | holt **benannte** Sektionen mit `gluon_preserve='1'` aus `*_gluon-old` zurück (`system`, `network`; 2025.1 auch `wireless`), ohne vorhandene zu überschreiben |
| `998-commit` | gluon-core | `gluon.core.reconfigure` löschen, **`uci commit` für alles**, `*_gluon-old` löschen |
| `999-version` | gluon-core | `sysconfig.gluon_version` schreiben |

## Was daraus folgt

**Neuinstallation erkennen.** `not require('gluon.sysconfig').gluon_version`.
`999-version` schreibt den Wert am Ende jedes Laufs, und
`/lib/gluon/core/sysconfig/` übersteht jedes sysupgrade (`keep.d`). Leer ist er
nur im allerersten Lauf nach frischem Flash, Werksreset oder sysupgrade ohne
Einstellungen. Gluon selbst nutzt das in `030-system`, `110-network`,
`150-poe-passthrough` und `180-outdoors`.

**Nur `uci:save()`, nie selbst committen.** `998-commit` committet alles in
einem Schritt. Das spart Flash-Schreibzugriffe, und ein abgebrochener Lauf
hinterlässt keinen halben Stand: vor `998` ist nichts committet, und das Delta
in `/tmp/.uci` ist mit dem nächsten Reboot weg. Die `*_gluon-old` bleiben
liegen, und der nächste `001` übernimmt sie, statt sie zu überschreiben.

**`network` und `system` werden bei jedem Lauf neu erzeugt.** Eigene
Einstellungen dort überleben nur als benannte Sektion mit
`gluon_preserve='1'`. `wireless` wird dagegen an Ort und Stelle geändert.

**Sysconfig für Zustand, der ein Update überleben muss.** Das Modul
`gluon.sysconfig` liest und schreibt Dateien unter `/lib/gluon/core/sysconfig/`;
Setzen auf `nil` löscht den Schlüssel. Achtung: das schreibt **direkt auf den
Flash**, nicht ins uci-Delta. `/tmp` taugt nur innerhalb eines Laufs; für
Zustand über einen Stromzyklus hinweg reicht es nicht.

**Reihenfolge bewusst wählen.** Wer beeinflussen will, was `200-wireless`
entscheidet, muss davor laufen; wer dessen Ergebnis sehen will, danach. Werte,
die erst ein späteres Skript setzt (`300-setup-mode`), sind noch nicht da.

**Nur Config erzeugen, nichts betreiben.** Kein `wifi reconf`, kein
Dienst-Neustart, keine Messung am laufenden Radio. Übernommen wird die Config
ohnehin erst beim nächsten Start: im Config-Mode folgt der Reboot direkt, und
beim ersten Boot nach einem sysupgrade laufen die Radios noch gar nicht. Gluons
eigene Upgrade-Skripte rufen nirgends `/sbin/wifi` auf.

**Syslog-Tags höchstens 31 Zeichen.** logd kürzt längere, und dann findet
`logread | grep <paketname>` nichts mehr (so geschehen mit
`neanderfunk-preserve-wifichannel`).

## Zeitlimit im Config-Mode

„Speichern & Neustarten" im Wizard ruft `gluon-reconfigure` innerhalb des
CGI-Prozesses von uhttpd auf; erst danach forkt `wizard.lua` den Reboot. Der
Setup-Mode-uhttpd läuft ohne `-t`, also mit `script_timeout` 60 s. Der Timer
wird beim Start des CGI **einmal** gesetzt und nie verlängert, auch nicht durch
Ausgabe. Nach 60 s wird der CGI mit SIGKILL beendet: der Browser zeigt „Bad
Gateway — The process did not produce any response", der Reboot findet nie
statt, und der verwaiste `gluon-reconfigure` läuft im Hintergrund zu Ende.

Am 2026-09-10 auf einem Xiaomi 4A Gigabit genau so nachgestellt: die damalige
Fassung von `neanderfunk-txpowerfix` brauchte allein 85 s. Mit `-t 300` am
uhttpd startete der Knoten neu.

**Der ganze Lauf muss also deutlich unter 60 s bleiben**, auch auf den
langsamsten Geräten.

## Setup-Mode

* Aktiv, wenn `gluon-setup-mode.@setup_mode[0].enabled=1` oder `configured≠1`
  ist; `preinit/90_setup_mode` legt dann `/var/gluon/setup-mode` an (Marker
  für Skripte, `posix.unistd.access()`), und procd arbeitet
  `/lib/gluon/setup-mode/rc.d` statt `/etc/rc.d` ab.
* netifd läuft dort mit `-c /var/gluon/setup-mode/config`, darin nur das
  Interface `setup` (192.168.1.1).
* `S20network` setzt `iw reg set <site.regdom>`, hostapd läuft nicht. Eine in
  uci gesetzte Country ist dort also **nicht** angewandt.

## Per SSH

Nach Änderungen an der Konfiguration braucht es `gluon-reconfigure` und einen
Reboot — ohne übernimmt Gluon die meisten Änderungen nicht. Weil dabei das Netz
neu aufgesetzt wird, **fliegt man vermutlich aus der SSH-Sitzung**. Dann den
Lauf von der Sitzung lösen, sonst stirbt er womöglich mit ihr.

Auf 2023.2-Images gibt es weder `nohup` noch `setsid`, wohl aber
`start-stop-daemon` (2025.1 hat zusätzlich `setsid`):

```sh
start-stop-daemon -S -b -m -p /tmp/gluon-reconfigure.pid -x /bin/sh -- \
	-c 'gluon-reconfigure >/tmp/gluon-reconfigure.log 2>&1; reboot'
```

`-m -p` ist nötig: ohne eigene PID-Datei sucht `start-stop-daemon` nach einem
laufenden `/bin/sh`, findet die eigene Shell und startet gar nicht („/bin/sh is
already running"). Am TL-WDR3600 geprüft: der Befehl läuft nach dem Ende der
Sitzung in einer eigenen Session zu Ende.

Das Log in `/tmp` ist nach dem Reboot weg. Wer es lesen will, lässt das
`; reboot` weg, sieht sich `/tmp/gluon-reconfigure.log` an und startet danach
von Hand neu.

## Testen, ohne den Flash anzufassen

Weil Upgrade-Skripte nur `uci:save()` benutzen, lassen sie sich am laufenden
Knoten gefahrlos ausprobieren:

1. `uci changes` muss vorher leer sein (sonst verwirft der Revert fremde
   Änderungen).
2. Skript oder Kette laufen lassen, `uci changes` ansehen.
3. `uci revert <paket>` für jedes berührte Paket.

`sysconfig` schreibt dagegen direkt auf den Flash. Im Lua-Prozess ersetzen, so
dass Lesen auf die echten Werte durchfällt und Schreiben im Speicher bleibt:

```lua
local real = dofile('/usr/lib/lua/gluon/sysconfig.lua')
local mem = {}
package.preload['gluon.sysconfig'] = function() return setmetatable({}, {
	__index = function(_, k) if mem[k] ~= nil then return mem[k] end return real[k] end,
	__newindex = function(_, k, v) mem[k] = v end }) end
for _, f in ipairs({ '/lib/gluon/upgrade/190-preserve-wireless-channels',
                     '/lib/gluon/upgrade/200-wireless' }) do
	dofile(f)
end
```

Eine Neuinstallation lässt sich so simulieren, indem `mem` ohne `gluon_version`
startet und der Rückfall auf `real` für diesen Schlüssel unterbleibt.

Vorsicht bei Skripten, die mehr tun als Config zu schreiben. Ein älteres
`neanderfunk-txpowerfix` auf dem Knoten löst `wifi reconf` aus — nie das
installierte laufen lassen, nur die neue Fassung aus dem Repo.

## Quellen im Gluon-Baum

* `package/gluon-core/files/usr/bin/gluon-reconfigure`
* `package/gluon-core/files/etc/uci-defaults/zzz-gluon-upgrade`,
  `package/gluon-core/files/etc/init.d/gluon-core-reconfigure`
* `package/gluon-core/{files,luasrc}/lib/gluon/upgrade/{001-reset-uci,005-set-domain,180-outdoors,190-preserve-wireless-channels,200-wireless,997-migrate-preserved,998-commit,999-version}`
* `package/gluon-core/luasrc/usr/bin/gluon-switch-domain`, `package/gluon-core/files/lib/gluon/reload.d/`
* `package/gluon-core/luasrc/usr/lib/lua/gluon/sysconfig.lua`, `package/gluon-core/files/lib/upgrade/keep.d/gluon`
* `package/gluon-setup-mode/Makefile` (`init_links`), `files/lib/preinit/90_setup_mode`,
  `files/lib/gluon/setup-mode/rc.d/S20network`, `luasrc/lib/gluon/upgrade/300-setup-mode`
* `package/gluon-config-mode-core/luasrc/lib/gluon/config-mode/model/gluon-config-mode/wizard.lua`
* `package/gluon-web-wifi-config/luasrc/lib/gluon/config-mode/model/admin/wifi-config.lua`
* uhttpd `main.c` (`script_timeout = 60`), `proc.c` (Timer einmal gesetzt, 502 bei fehlender Antwort)
