neanderfunk-status-page
=======================

Ergänzungen zur Statusseite von Gluon. Die Zeilen selbst kommen aus den
Patches in gluon-patches-packages (`status-page/`), dieses Paket liefert,
was sie zur Laufzeit brauchen:

- **Übersetzungen** (de, fr) der Neanderfunk-Zeilen: Temperatur,
  Offline-SSID mit ihren Zählern, Hardware-Angaben, Domain-Helfer. Das
  gepatchte Template liest sie mit `i18n('neanderfunk-status-page')`,
  Gluons eigener Katalog von gluon-status-page bleibt unberührt. Ohne das
  Paket erscheinen die Zeilen englisch.
- **`/cgi-bin/dyn/gateway-name`**: der Hostname eines batman-Gateways,
  beim Gateway selbst per respondd erfragt (Patch
  `statuspage-gateway-name`). Ohne das Paket zeigt die Seite wie bisher
  die MAC. Das Ergebnis liegt 1 h unter `/tmp/neanderfunk-gateway-name`,
  „kein Name“ 5 min.

Platzbedarf
-----------

Schätzung (22.11.2026, Bau 26112210bro). Methode und alle Pakete im
Vergleich: [docs/platzbedarf.md](../docs/platzbedarf.md).

- **Flash:** etwa 2,5 KB im squashfs (xz). Das ist nur das Paket; die Zeilen in Gluons Statusseite kommen aus gluon-patches-packages und sind hier nicht mitgezählt.
- **RAM dauerhaft:** nur der Cache von `gateway-name` unter `/tmp`: je Gateway eine kleine Datei (4 KB).
- **RAM kurzzeitig:** je Aufruf der Statusseite kurz `gateway-name` (Shell, eine respondd-Abfrage beim Gateway).
