neanderfunk-node-whisperer
==========================

Kodiert Statusinformationen eines Gluon-Knotens in die Beacons der
Client-WLANs. Auslesbar mit der App
[NodeMonitor](https://github.com/freifunk-darmstadt/NodeMonitor).

Fork von `ffda-node-whisperer` aus den
[community-packages](https://github.com/freifunk-gluon/community-packages),
Branch `v2023.2.x`, Stand `91e5fa8a`. Der eigentliche Quelltext kommt
unveraendert von <https://github.com/blocktrron/node-whisperer> (GPL-2.0-or-later,
© David Bauer und Matthias Schiffer); unsere Aenderungen liegen als Patches
unter `patches/`.

Warum ein Fork
--------------

Zwei Fehler, beide am Geraet belegt, beide auch im aktuellen Upstream-`main`
noch vorhanden:

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
   Upstream-Commit setzen. **Achtung:** das Quell-Repo ist inzwischen von
   `blocktrron/node-whisperer` nach
   `freifunk-darmstadt/node-whisperer` umgezogen - dann auch
   `PKG_SOURCE_URL` mitziehen.
2. Patches gegen den neuen Stand pruefen:

   ```
   git clone https://github.com/freifunk-darmstadt/node-whisperer.git
   cd node-whisperer && git checkout <neuer-commit>
   for p in .../neanderfunk-node-whisperer/patches/*.patch; do
       patch -p1 --dry-run < "$p" || echo "KONFLIKT: $p"
   done
   ```
3. Ein Patch, der nicht mehr passt, ist eine gute Nachricht: entweder hat
   Upstream dieselbe Stelle angefasst (dann pruefen, ob unsere Aenderung
   ueberfluessig geworden ist und der Patch entfallen kann), oder der Kontext
   hat sich verschoben (dann neu erzeugen).

Stand der Pruefung (2026-09-06): zwischen unserem Pin und Upstream-`main`
(`43d1a90`, 2026-07-26) liegen 14 Commits. Keiner davon behebt einen der beiden
obigen Punkte. Vier betreffen neuere OpenWrt-Versionen (24.10/25.12, musl),
vier die CI, drei das separate `monitor`-Werkzeug, das dieses Paket gar nicht
installiert. Bleiben zwei echte Logikfixes:

* `f291cb0` korrigiert die `strncmp`-Grenze beim `mesh-vpn`-Vergleich. Betrifft
  nur Interfaces, deren Name ein *Praefix* von `mesh-vpn` ist (`mesh`, `mesh-`);
  unsere heissen `mesh0`, `mesh1`, `eth0`, `primary0`, also ohne Wirkung.
  Sollte beim naechsten Bump trotzdem mitkommen.
* `1c41339` bricht beim ubus-Timeout ab, statt die Vendor-Elemente
  zurueckzusetzen. An fuenf Knoten gemessen: null solche Fehler im Log, also
  aktuell ohne Wirkung fuer uns.
