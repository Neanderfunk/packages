neanderfunk-preserve-wifichannel
================================

Macht `wifi24.preserve_channels` aus der site.conf zum Default fuer Gluons
uci-Option `gluon.wireless.preserve_channels` - und uebernimmt nach einem Site-
oder Domainwechsel einmal die Kanaele der neuen Site.

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

Aufbau
------

* `185-neanderfunk-preserve-wifichannel` - vor `190-preserve-wireless-channels`
  (legt den Schluessel mit 0 an, wenn er fehlt) und vor `200-wireless`:
  fehlenden Schluessel setzen bzw. vormerken, bei Site-/Domainwechsel aufheben.
* `225-neanderfunk-preserve-wifichannel` - nach `200-wireless` und nach
  `neanderfunk-txpowerfix` (215): Aufhebung zuruecknehmen, Vormerkung einloesen,
  Stand merken.

`neanderfunk-txpowerfix` laesst htmode stehen, solange `preserve_channels`
gesetzt ist. Im Lauf eines Wechsels sieht es den aufgehobenen Schalter und
setzt die Breite wie nach jeder Neukonfiguration.

Was das Paket nicht abdeckt: Outdoor-Schalter in der Oberflaeche
---------------------------------------------------------------

Mit `preserve_channels=1` zeigt `gluon-web-wifi-config` den Outdoor-Schalter in
den Erweiterten Einstellungen gar nicht erst an (`wifi-config.lua`, Bedingung
`not wireless.preserve_channels(uci)`), und selbst wenn: beim Speichern ruft es
nur `200-wireless` auf, nicht `gluon-reconfigure`, und `200-wireless` laesst die
Kanaele dann stehen. Beides liegt in Gluon selbst und ist aus einem Paket heraus
nicht zu aendern; dafuer braeuchte es einen Patch am Build nebenan.

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
