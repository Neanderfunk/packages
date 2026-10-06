# ffac-autoupdater-wifi-fallback

**Neanderfunk feed, branch v2021.1.x (Sackgasse, OpenWrt 19.07):** copy of
freifunk-gluon/community-packages 1493e17 (BSD-2-Clause, see LICENSE). Only change:
no dependency on gluon-state-check (not in Gluon 2021.1); its has_default_gw4
check (batman gateways listed, or gw_mode server) is done inline. Tested on a
TL-WR841N v9: Lua modules present, scan via radio name, update hosts, gateway
check, respondd module (built with the 19.07 SDK) loads. The fallback itself
(-f) was not run on the test node, it would flash.

If a node has no connection to the mesh, neither via wlan-mesh nor via
mesh-vpn, it ist not possible to update this node via `autoupdater`. Therefor
the *wifi-fallback* was developed. It checks hourly whether the node is part of
a fully operative mesh or not. Else the node connects to a visible "Freifunknetz"
and tries downloads an update as wlan-client via executing `autoupdater -f`.

This is compatible with gluon/openwrt versions >= v2022.x (upstream statement;
this copy runs on Gluon 2021.1, see above).

## Verhalten laut Code (Neanderfunk, 07.10.2026)

Ausführlich, mit Praxistest und Zeitablauf:
[docs/autoupdater-wifi-fallback.md im Zweig v2025.1.x](https://github.com/Neanderfunk/packages/blob/v2025.1.x/docs/autoupdater-wifi-fallback.md).
Der Code dieser Kopie ist bis auf die eingebaute Gateway-Prüfung derselbe.

Kurz, und wo die Beschreibung oben ungenau ist:

- **Wann:** stündlich, 10 Minuten nach der Minute des Autoupdaters
  (`510-autoupdater-wifi-fallback` schreibt `/usr/lib/micron.d/autoupdater-wifi-fallback`).
  Nur mit `enabled=1` **und** eingeschaltetem Autoupdater, und erst ab 1 h
  Uptime.
- **„Offline“** heißt: kein Gateway (`has_default_gw4`) **und** kein Mirror-Host
  des Zweigs antwortet auf `ping`. Ein Mesh-Nachbar ohne Gateway zählt nicht.
- **Zeitgrenze:** Der erste Offline-Lauf merkt sich die Uhrzeit
  (`unreachable_since`, nur `uci save`, also im RAM; ein Neustart setzt sie
  zurück). Fallback, wenn **mehr als** 2 h vergangen sind. Weil der Lauf
  stündlich zur selben Minute kommt, ist das meist erst der Lauf 3 h nach dem
  Vermerk.
- **Fallback:** `wifi down`, Scan je Radio nach SSIDs mit „freifunk“ (Groß/klein
  egal, also auch „Freifunk verschluesselt“, nicht aber `FF_Offline_...`), je
  Treffer offener `iw connect`, DHCP/DHCPv6 auf `fallback_if`, dann
  `autoupdater -f -b <zweig>`. Der Rückgabewert wird nicht ausgewertet: ohne
  Update werden alle Treffer nacheinander versucht, danach `wifi up`, und das
  wiederholt sich jede Stunde.
- `network.fallback`/`fallback6` stehen dauerhaft in der Konfiguration (von
  `510` angelegt), im Normalbetrieb ohne Gerät.
- `autoupdater-wifi-fallback -f` überspringt Vorbedingungen und Zeitgrenze und
  **flasht**, wenn es ein Image gibt.

Praxistest unter Gluon 2025.1 am 06.10.2026 (TL-WR1043ND v2): erster
Offline-Vermerk 19:59:26, Fallback 22:59:06, um 23:02:26 lief die neue Firmware
mit erhaltener Konfiguration. Unter 2021.1 wurde der Fallback selbst nicht
ausgelöst.

## /etc/config/autoupdater-wifi-fallback

**autoupdater-wifi-fallback.settings.enabled:**
- `0` disables the fallback mode
- `1` enables the fallback mode

### example
```
config autoupdater-wifi-fallback 'settings'
	option enabled '1'
```

## Credits

This includes gluon-state-check from tecff to be mesh protocol independent.
As well as using upstream wpa-supplicant-mini to support new version.
It was formerly created by ffho as `ffho-autoupdater-wifi-fallback`
