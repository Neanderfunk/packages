neanderfunk-ddhcpd
==================

Verteilter DHCP-Server auf den Knoten: Die Knoten einer Domain teilen sich
einen IPv4-Bereich in Blöcken und vergeben Adressen an ihre Clients selbst,
statt jede Anfrage zum DHCP-Server des Supernodes zu schicken.

* Daemon: [Neanderfunk/ddhcpd](https://github.com/Neanderfunk/ddhcpd), Zweig
  `neanderfunk` (Fork von
  [freifunk-gluon/ddhcpd](https://github.com/freifunk-gluon/ddhcpd); was der
  Zweig ändert, steht dort in `NEANDERFUNK.md`).
* Paket: nach `ffgraz-ddhcpd` aus den
  [Gluon-community-packages](https://github.com/freifunk-gluon/community-packages)
  (Stand `61fd9019e013`, Maciej Krüger).

Domain-Konfiguration
--------------------

Alles steht je Domain (in der Domain-Datei oder site-weit in `site.conf`).
Ohne `enabled = true` läuft der Daemon nicht.

```lua
ddhcpd = {
  enabled = true,
  range = '10.51.72.0/21',           -- Bereich, den ddhcpd in Blöcken vergibt
  client_prefix4 = '10.51.64.0/18',  -- Client-Netz: daraus die Netzmaske (Option 1)
  router = '10.51.64.2',             -- Option 3
  dns = { '10.51.64.1', '10.51.64.2' }, -- Option 6
  -- optional, mit Vorgabe:
  -- block_size = 2,          -- Zweierpotenz der Blockgröße (0-7)
  -- block_timeout = 300,     -- Sekunden, bis ein nicht erneuerter Block frei wird
  -- learning_time = 30,      -- Lernphase nach dem Start, so lange vergibt der Knoten nichts
  -- dhcp_lease_time = 300,   -- Option 51
  -- spare_leases = 8,        -- so viele freie Adressen hält der Knoten vor
  -- tentative_timeout = 15,  -- Sekunden vom Ankündigen bis zum Besitz eines Blocks
},
```

* `range` und `client_prefix4` müssen beide gesetzt sein, sonst bleibt
  ddhcpd aus (Meldung beim `gluon-reconfigure`).
* Die Netzmaske kommt nur aus `client_prefix4`. Nicht aus `prefix4`
  (bei uns site-weit `/8`, die Clients bekämen `/8`) und nicht aus `range`
  (bei `/21` läge der Router nicht mehr im Netz des Clients).
* Option 54 (Server-Identifier) ist `next_node.ip4`.
* `range` darf sich nicht mit dem Bereich überschneiden, den der
  DHCP-Server des Supernodes vergibt, und der darf Anfragen für Adressen aus
  `range` nicht bestätigen.

Unterschiede zu ffgraz-ddhcpd
-----------------------------

* `enabled` und alle Werte je Domain; `enabled` wird bei jedem
  `gluon-reconfigure` aus der Domain geschrieben, damit ein Domainwechsel es
  mitnimmt. Ab Werk aus.
* Von Hand nur `disabled_local`:
  `uci set ddhcpd.settings.disabled_local=1; uci commit ddhcpd` schaltet
  ddhcpd auf diesem Knoten ab, egal was die Domain sagt.
* Der Daemon hört an `local-node` (Zone `loc_client`, dort ist UDP 67 offen)
  und redet mit den anderen Knoten über `br-client`. An `br-client` (Zone
  `mesh`) bliebe UDP 67 zu, und ddhcpd vergäbe nie etwas. Die
  mmfd-Firewallregel ist entfallen.
* Router, DNS, Netzmaske und Lease-Zeit aus der Domain (die Lease-Zeit war
  bei ffgraz-ddhcpd fest 300 s, `dhcp_lease_time` wurde nicht benutzt).
* Lernphase eigener Wert (Vorgabe 30 s statt `block_timeout`, also 300 s).
* `spare_leases` Vorgabe 8 statt 2.
* Mehr Log: `uci set ddhcpd.settings.verbosity=2` (je Stufe ein `-v`), Ausgabe
  im `logread`.
* `check_site.lua` läuft beim Bau (`BuildPackageGluon`).
* `CONFLICTS:=ffgraz-ddhcpd`: beide installieren dieselben Dateien.

Test
----

`lua5.1 tests/upgrade_test.lua` aus dem Paketverzeichnis prüft
`500-neanderfunk-ddhcpd` mit Attrappen für `gluon.site` und `simple-uci`.

Lizenz
------

Daemon GPL-3.0 (wie freifunk-gluon/ddhcpd). Die Paketdateien stammen aus
ffgraz-ddhcpd und stehen wie dort unter MIT.
