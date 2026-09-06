neanderfunk-ch13to9
=================

this package moves nodes from channel 13 to 9 during initial upgrade.
this is done even if "keep wifi channel" is enabled via UCI

background: some clients (apple) do refuse to connect to channel13, so we
have to move existing nodes. 
This is a onetime-shot operation. 

Not defaulting to the "site.conf" channel but to go to migrate to (static) 9 was done on purpose. 
But having this configurable via the "new site.conf" would be an enhancement. 
(pull requests welcome)


To use the script in your firmware:

```
GLUON_SITE_FEEDS="eulenfunk"
PACKAGES_EULENFUNK_REPO=https://github.com/eulenfunk/packages.git
PACKAGES_EULENFUNK_COMMIT=*/missing/*
PACKAGES_EULENFUNK_BRANCH=v2020.1.x
```

With this done you can add the package `neanderfunk-ch13to9` to your `site.mk`

Stand 2026-09-06
----------------

Das Paket war wirkungslos: es waehlte die Radios ueber
`uci get wireless.radio0.hwmode`, und OpenWrt 21.02 hat `hwmode` durch `band`
ersetzt - auf jedem aktuellen Knoten liefert das nichts, der ganze
Erkennungsblock wurde uebersprungen. Ausserdem lag es doppelt im Feed
(`/lib/gluon/ch13to9/ch13to9.lua`, aufgerufen von einem selbstloeschenden
`/etc/init.d/ch13to9`, plus byte-identisch als Upgrade-Skript), und das Gate im
init.d war `if [ $(uci get ...) ]` - ein blosser String-Test, der fuer "0"
genauso wahr ist wie fuer "1".

Jetzt gibt es nur noch das Upgrade-Skript. Es laeuft bei jedem
`gluon-reconfigure`, iteriert die `wifi-device`-Sektionen statt radio0/radio1
von Hand durchzugehen, erkennt 2,4 GHz ueber `band` (mit `hwmode` als
Rueckfall) und schreibt nur, wenn wirklich etwas zu aendern ist.
