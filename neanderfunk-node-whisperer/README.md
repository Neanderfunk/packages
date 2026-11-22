neanderfunk-node-whisperer
==========================

Kodiert Statusinformationen eines Gluon-Knotens in die Beacons der
Client-WLANs. Auslesbar mit der App
[NodeMonitor](https://github.com/freifunk-darmstadt/NodeMonitor).

Wie das technisch funktioniert – Vendor-Element im Beacon, Empfang ohne
Assoziierung, Android-API der App: [HOW-IT-WORKS.md](HOW-IT-WORKS.md)
(English).

Fork von `ffda-node-whisperer` aus den
[community-packages](https://github.com/freifunk-gluon/community-packages),
Branch `v2023.2.x`, Stand `91e5fa8a`. Der eigentliche Quelltext kommt
unveraendert von <https://github.com/fnsh/node-whisperer> (frueher
`blocktrron/node-whisperer`, GitHub leitet um; GPL-2.0-or-later, © David Bauer
und Matthias Schiffer), gepinnt auf `c2d410d` (12.11.2026, derselbe Stand wie
`ffda-node-whisperer` in den community-packages); unsere Aenderungen liegen als
Patches unter `patches/`.

Warum ein Fork
--------------

Zwei Fehler, beide am Geraet belegt, beide auch in Upstream `c2d410d`
(12.11.2026) noch vorhanden:

**1. Syslog-Spam auf Single-Domain-Firmware.** `gluonutil_get_domain()` liefert
auf einer Firmware ohne Multidomain nichts. Der Sammler meldete dafuer `-1`,
und der Daemon loggt jeden negativen Rueckgabewert auf Error-Level - also alle
30 Sekunden, endlos, auf jedem Knoten:

```
node-whisperer: Error collecting Information for id=4 name=domain code=-1
```

Auf einem Knoten nachgesehen: `/lib/gluon/domains/` existiert nicht,
`gluon.core.domain` ist ungesetzt, `domain_code` in der site.json ist leer.
`patches/0001` meldet stattdessen `-ENODATA`, und der Daemon ueberspringt eine
so gemeldete Quelle still. Echte Sammelfehler behalten ihre Fehlermeldung.

**2. Das Byte, das die App "Gateway" nennt, war der VPN-Nachbar-TQ.** Byte 1
des `batman_adv`-Datensatzes trug `stats.vpn.tq`, und das wird in `batadv.c`
ausschliesslich innerhalb von

```c
if (!strncmp(ifname, "mesh-vpn", ...))
```

gesetzt. Auf einem Knoten ohne `mesh-vpn`-Interface ist es also
konstruktionsbedingt 0, und die App zeigt "Gateway: Nicht Erreichbar" - egal wie
gut das echte Gateway erreichbar ist. An zwei Knoten gemessen:

| Knoten | Mesh ueber | echtes Gateway | gesendet |
| --- | --- | --- | --- |
| ZyXEL NWA50AX Pro | `eth0` (LAN) | TQ 240 | `vpn.tq = 0` |
| MERCUSYS MR90X v1 | `mesh1` (WLAN) | TQ 236 | `vpn.tq = 0` |

`patches/0002` fragt `BATADV_CMD_GET_GATEWAYS` ab und nimmt den TQ des
Eintrags, den batman mit `BATADV_ATTR_FLAG_BEST` markiert.

**Das Drahtformat bleibt unveraendert**: Byte 0 beantwortet weiterhin die
separate Frage "gibt es einen VPN-Uplink", Byte 1 steht an derselben Stelle im
selben Wertebereich und heisst in der App weiterhin "Gateway". Die App
funktioniert also unveraendert weiter - das Gateway-Byte sagt nur endlich die
Wahrheit.

"Knoten im Netz" zaehlte jeden Weg
----------------------------------

Bytes 2-3 des `batman_adv`-Datensatzes zeigt die App als "Knoten im Netz". Der
Daemon zaehlte dafuer jeden Eintrag der Originator-Tabelle
(`BATADV_CMD_GET_ORIGINATORS`) - und die hat einen Eintrag je Originator,
Next-Hop und Interface. Ein Knoten, den man ueber mehrere Nachbarn auf 2,4 GHz,
5 GHz und ueber das VPN hoert, zaehlte mehrfach. Am Archer C25 (9 Nachbarn,
15.09.2026): 338 Eintraege, 91 verschiedene Originatoren, die App zeigte 338.

Behoben: Gezaehlt wird nur der Eintrag mit `BATADV_ATTR_FLAG_BEST` - genau
einen je Originator, die Zeile, die `batctl o` mit `*` markiert (am C25: 91 von
338). Bis 18.11.2026 war das unser `patches/0004`, seit dem Pin `c2d410d` macht
es Upstream selbst (`e194120`, gleiche Logik).
Die Nachbarzahl (Bytes 4-5) bleibt, wie sie ist: direkte Links, einer je
Nachbar und Interface, wie `batctl n`. Drahtformat und App unveraendert.

`patches/0004` (bis 18.11.2026 `0005`): Das init-Skript verglich
`settings.disabled` numerisch (`-gt 0`). Bei `true` oder `yes` scheiterte der
Test, und der Daemon startete, obwohl er abgeschaltet war. Jetzt `get_bool` aus
`/lib/functions.sh`, also jede Schreibweise, die OpenWrt fuer einen
Wahrheitswert kennt.

`patches/0003` benennt den Dienst nach dem Paket (siehe Namensraum).

Namensraum
----------

Alle installierten Pfade tragen den Paketnamen:

```
/usr/bin/neanderfunk-node-whisperer
/etc/init.d/neanderfunk-node-whisperer
/etc/config/neanderfunk-node-whisperer
/lib/gluon/upgrade/150-neanderfunk-node-whisperer
```

Damit kollidiert nichts mit `ffda-node-whisperer` oder einem anderen Paket.
Trotzdem ist `CONFLICTS:=ffda-node-whisperer` gesetzt: zwei Daemons, die
dieselben Interfaces mit Vendor-Elementen bespielen, ergeben keinen Sinn.

**Nicht** umbenannt ist das ubus-Objekt `node_whisperer`. Es ist im C-Quelltext
verankert, existiert nur zur Laufzeit, und laufen kann ohnehin immer nur einer
von beiden.

Der site.conf-Schluessel heisst weiterhin `node_whisperer`. Eine Site muss beim
Wechsel auf dieses Paket also nichts aendern, und ein Wechsel zurueck kostet
ebenfalls nichts.

site.conf
---------

```lua
  node_whisperer = {
    enabled = true,
    information = {
      'hostname',
      'node_id',
      'uptime',
      'site_code',
      'system_load',
      'firmware_version',
      'batman_adv',
    }
  },
```

`domain` gehoert auf einer Single-Domain-Firmware nicht in die Liste: die
Information waere leer. Seit `patches/0001` ist sie kein Fehler mehr, aber
anfordern muss man sie deswegen nicht.

Backport von Upstream
---------------------

Der Quelltext ist gepinnt und unveraendert, unsere Aenderungen sind Patches.
Ein Update laeuft damit so:

1. Im Makefile `PKG_SOURCE_VERSION` und `PKG_SOURCE_DATE` auf den neuen
   Upstream-Commit setzen. Das Quell-Repo heisst heute `fnsh/node-whisperer`
   (`blocktrron/` und `freifunk-darmstadt/` leiten dorthin um).
2. Patches gegen den neuen Stand pruefen:

   ```
   git clone https://github.com/fnsh/node-whisperer.git
   cd node-whisperer && git checkout <neuer-commit>
   for p in .../neanderfunk-node-whisperer/patches/*.patch; do
       patch -p1 --dry-run < "$p" || echo "KONFLIKT: $p"
   done
   ```
3. Ein Patch, der nicht mehr passt, ist eine gute Nachricht: entweder hat
   Upstream dieselbe Stelle angefasst (dann pruefen, ob unsere Aenderung
   ueberfluessig geworden ist und der Patch entfallen kann), oder der Kontext
   hat sich verschoben (dann neu erzeugen).

Upstream baut in der CI gegen Gluon `v2025.1.x` (OpenWrt 24.10) und `main`
(OpenWrt 25.12). Ein Stand, der dort gruen ist, passt also zu unserer
2025.1-Linie.

Letzter Bump am 18.11.2026 (Wunsch adorfer), von `8f1e5560` (2024-11-09) auf
`c2d410d` (2026-11-12), rund 60 Upstream-Commits, vor allem Haertung von
Grische: unausgerichtete Lesezugriffe im batman-Parser (`4af77e6`, betrifft
MIPS), `va_list`-Wiederverwendung im Log (`6d8e671`), Freigabe eines nicht
initialisierten Zeigers (`376ecd5`), `calloc`-Argumente (`09653dd`),
Puffer- und `fread`-Pruefungen, und Hex-Umwandlung nur noch bei Debug-Log
(`c2d410d`, weniger CPU je Runde). Damit entfielen unsere alten Patches
`0004` (Originator-Zaehlung, Upstream `e194120`) und die Cherry-Picks
`0006`-`0009` (`f291cb0`, `b7ca4dd`, `1c41339`, `aa409ee`). `0001` und `0002`
passten wegen geaenderten Kontexts (bereinigte Leerzeichen, neue Debug-Pruefung)
nicht mehr und sind inhaltlich unveraendert neu erzeugt; die alte `0005` heisst jetzt `0004`.
Upstream baut inzwischen auch `node-monitor` mit; das Paket installiert ihn
weiterhin nicht. Gebaut mit der x86_64-Toolchain von Gluon 2025.1 (`-Werror`).

Platzbedarf
-----------

Schätzung (22.11.2026, Bau 26112210bro). Methode und alle Pakete im
Vergleich: [docs/platzbedarf.md](../docs/platzbedarf.md).

- **Flash:** etwa 8 KB im squashfs (xz).
- **RAM dauerhaft:** der Daemon: 164 KB eigener Speicher am M60. Auf Geräten mit 64 MB RAM nicht im Image (FirmwareConfigs, am TL-WR1043ND v2 waren es 1,5 MB RSS samt Datei-Seiten).
- **RAM kurzzeitig:** nichts Nennenswertes.
