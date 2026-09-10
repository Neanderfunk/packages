neanderfunk-preserve-wifichannel
================================

Macht `wifi24.preserve_channels` aus der site.conf zum Default fuer Gluons
uci-Option `gluon.wireless.preserve_channels` - und uebernimmt nach einem Site-
oder Domainwechsel einmal die Kanaele der neuen Site, nach einem
Outdoor-Wechsel einmal die 5-GHz-Kanaele.

Hintergrund
-----------

Gluon schreibt bei jedem Update Kanal, Kanalliste und Kanalbreite neu (Doku:
*"During upgrades the wifi channel of the 2.4GHz and 5GHz radio will be restored
to the channel configured in the site.conf. The channel width will be reset to
Gluon's default."*). Verhindern laesst sich das nur mit

```
uci set gluon.wireless.preserve_channels='1'
```

Das ist seit der Einfuehrung 2016 (Gluon 388d264f, v2016.2) eine reine
uci-Option. **`wifi24.preserve_channels = 1` in der site.conf wird von Gluon
nirgends gelesen und hat nie gewirkt** - weder in v2023.2.6 noch in v2025.1.3.
Am 2026-09-10 standen 7 von 9 Testknoten auf 0; nur die zwei, bei denen jemand
den Schalter von Hand gesetzt hatte, behielten abweichende Kanaele.

Verhalten
---------

| Lage auf dem Knoten | was passiert |
| --- | --- |
| Schluessel steht auf 0 oder 1 | bleibt, wie er ist - egal ob von Hand oder von Gluon gesetzt. Bestandsknoten aendern sich also nicht. |
| Schluessel fehlt, Neuinstallation | Wert aus der Site, gesetzt sobald die Erstkonfiguration abgeschlossen ist (siehe unten) |
| Schluessel fehlt, Bestandsknoten | Wert aus der Site, sofort - er greift schon in diesem Lauf |
| Site oder Domain gewechselt, Schluessel steht auf 1 | Kanaele der neuen Site werden **einmal** eingetragen, der Schluessel bleibt auf 1 |
| Outdoor ein- oder ausgeschaltet (oder Outdoor-Breite geaendert), Schluessel steht auf 1 | 5-GHz-Kanaele werden **einmal** eingetragen, die anderen Baender bleiben, der Schluessel bleibt auf 1 |
| Site setzt `wifi24.preserve_channels` nicht | nichts, es bleibt bei Gluons Verhalten |

Je Knoten abschalten:

```
uci set gluon.wireless.preserve_channels='0'
uci commit gluon
```

Neuinstallation
---------------

Der erste `gluon-reconfigure` einer Neuinstallation laeuft beim Erstboot im
Setup-Mode (`zzz-gluon-upgrade` ueber `S10boot`, das `gluon-setup-mode` in sein
rc.d verlinkt), also **vor** dem Config-Mode-Wizard. Wuerde der Schalter dort
schon gesetzt,

* blendete der Wizard den Outdoor-Schritt aus (`0250-outdoor.lua` fragt
  `preserve_channels` ab, in 2023.2 wie in 2025.1), und
* liesse der Reconfigure-Lauf des Wizards die Kanaele stehen - auch die einer
  dort gewaehlten Domain.

Deshalb wird beim Erstboot nur vorgemerkt (in `/lib/gluon/core/sysconfig/`, das
einen Stromzyklus zwischen Erstboot und Wizard uebersteht) und im naechsten
Lauf eingeloest, nachdem `200-wireless` Outdoor- und Domain-Wahl eingetragen
hat. Wird der Setup-Mode uebersprungen (`setup_mode.skip`, bei uns 44 der 86
Stable-Sites), kommt kein Wizard; dann wird noch im ersten Lauf gesetzt, nach
`200-wireless`. `setup_mode.skip` wird dafuer direkt aus der Site gelesen -
Gluons `300-setup-mode`, das `configured` setzt, laeuft erst nach diesem Paket.

Site- oder Domainwechsel
------------------------

Die Domains haben nicht alle dieselben Kanaele (Stand `sites.nefall.sta`:
68 x 9/44, 10 x 1/36, 8 x 9/48). Mit `preserve_channels=1` behielte ein Knoten
nach einem Wechsel seine alten Kanaele und funkte am WLAN-Mesh seiner neuen
Nachbarn vorbei.

Das Paket merkt sich nach jedem Lauf `<site_code>/<gluon.core.domain>`. Ist
beides beim naechsten Lauf anders - `gluon-switch-domain` (auch aus dem
nodeplacer) oder das Image einer anderen Site -, wird der Schalter fuer
**genau diesen Lauf** aufgehoben: `200-wireless` traegt die Kanaele der neuen
Site ein, danach steht er wieder auf 1. Unterm Strich aendert sich an ihm
nichts: Aufheben und Wiedersetzen liegen beide nur im uci-Delta, committet wird
erst von Gluons `998-commit`. Bricht ein Lauf vorher ab, gibt es keinen Commit,
und das Delta in `/tmp` ist mit dem Reboot weg.

Outdoor-Wechsel
---------------

Outdoor betrifft nur das 5-GHz-Radio: Kanal `auto` aus `wifi5.outdoor_chanlist`
(bei uns 100-140, also DFS-Kanaele mit Radarpruefung), `country3=0x4f` (Regdomain
auf die draussen erlaubten Kanaele gefiltert), 5-GHz-Mesh aus. Mit
`preserve_channels=1` setzt Gluons `200-wireless` davon nur `country3` und das
Mesh um, Kanal, Kanalliste und Breite bleiben stehen - ein Innenkanal wie 44
unter Outdoor-Regdomain, und zurueck auf Indoor bliebe 5 GHz auf `auto`.

Das Paket merkt sich deshalb auch den Outdoor-Stand (`gluon.wireless.outdoor`
und die Outdoor-Breiten `outdoor_<radio>_htmode`). Aendert er sich, wird der
Schalter wie beim Domainwechsel fuer einen Lauf aufgehoben. Die anderen Baender
bleiben dabei stehen: Kanal, Kanalliste und Breite der Nicht-5-GHz-Radios
werden vorher festgehalten und danach zurueckgeschrieben - Kanal und Kanalliste
gleich nach `200-wireless`, weil `neanderfunk-txpowerfix` die Country aus dem
2,4-GHz-Kanal ableitet (Kanal 13 -> JP), die Breite nach txpowerfix.

Das wirkt bei jedem vollstaendigen `gluon-reconfigure`:

| Wo wird umgeschaltet? | wirkt? |
| --- | --- |
| Config-Mode-Wizard, 2023.2 und 2025.1 | ja - der Outdoor-Schritt ist bei `preserve_channels=1` aber ausgeblendet, das braucht einen Gluon-Patch nebenan |
| Erweiterte Einstellungen, 2025.1 | ja (speichert mit `gluon-reconfigure`) - Schalter ebenfalls ausgeblendet, Patch nebenan |
| Erweiterte Einstellungen, 2023.2 | nur wenn nebenan das Speichern auf `gluon-reconfigure` umgestellt wird; heute laeuft dort nur `200-wireless`, und dieses Paket laeuft gar nicht |
| per SSH: `uci set gluon.wireless.outdoor=…` + `gluon-reconfigure` | ja |

**Das 5-GHz-Mesh fasst das Paket nicht an.** Beim Ausschalten von Outdoor
loescht der Wizard die Mesh-Sektionen selbst, die Erweiterten Einstellungen
setzen die Mesh-Checkbox, und in 2025.1 kommt das Mesh ueber die Rollen
(`gluon.band_5g.role`) ohnehin wieder. Nur wer in 2023.2 per SSH zurueck auf
Indoor schaltet, muss das Mesh selbst wieder einschalten - `200-wireless` laesst
das `disabled=1` aus der Outdoor-Zeit stehen, auch ganz ohne dieses Paket:

```
uci set gluon.wireless.outdoor='0'
uci set wireless.mesh_radio1.disabled='0'
uci commit
gluon-reconfigure
```

Aufbau
------

* `185-neanderfunk-preserve-wifichannel` - vor `190-preserve-wireless-channels`
  (legt den Schluessel mit 0 an, wenn er fehlt) und vor `200-wireless`:
  fehlenden Schluessel setzen bzw. vormerken, bei Site-/Domainwechsel aufheben.
* `205-neanderfunk-preserve-wifichannel` - gleich nach `200-wireless`, vor
  `neanderfunk-txpowerfix`: bei einem reinen Outdoor-Wechsel Kanal und
  Kanalliste der uebrigen Baender zurueckschreiben.
* `225-neanderfunk-preserve-wifichannel` - nach `200-wireless` und nach
  `neanderfunk-txpowerfix` (215): Breite der uebrigen Baender zurueckschreiben,
  Aufhebung zuruecknehmen, Vormerkung einloesen, Site/Domain- und
  Outdoor-Stand merken.

`neanderfunk-txpowerfix` laesst htmode stehen, solange `preserve_channels`
gesetzt ist. Im Lauf eines Wechsels sieht es den aufgehobenen Schalter und
setzt die Breite wie nach jeder Neukonfiguration.

Was das Paket nicht abdeckt: Outdoor-Schalter in der Oberflaeche
---------------------------------------------------------------

Mit `preserve_channels=1` blendet `gluon-web-wifi-config` den Outdoor-Schalter
in den Erweiterten Einstellungen aus (`wifi-config.lua`, Bedingung
`not wireless.preserve_channels(uci)`), der Wizard seinen Outdoor-Schritt
(`0250-outdoor.lua`). Beides liegt in Gluon selbst; dafuer braucht es einen
Patch am Build nebenan - ebenso fuer das Speichern mit `gluon-reconfigure` in
2023.2. Bei einer Neuinstallation ist der Wizard-Schritt sichtbar, weil der
Schalter erst danach gesetzt wird.

Einbindung
----------

`neanderfunk-preserve-wifichannel` in `image-customization.lua` aufnehmen und in
der site.conf

```
wifi24 = {
  preserve_channels = 1,
  ...
},
```

(steht bei uns schon so drin). Zahl oder Boolean, beides wird angenommen; der
Wert wird per `check_site.lua` geprueft.
