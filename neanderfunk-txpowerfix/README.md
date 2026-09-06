neanderfunk-txpowerfix
================

Up to OpenWRT BarrierBreaker, the wifi stack did take automatically the
highest available txpower. 

introduction with ChaosCalmer, OpenWRT does take into account the antenna
gain, stored as value in the ART partition of the SPI flash. 
for numerous reasons the values are wrong calculated or just
over-optimistic, as a result, the available "on air" is for many devices
lower than the goal of 20dBm/100mW. 
by consequence meshlinks tend to degrade "from green to red" when upgrading
from gluon 2015.x to 2016.x

This runs as a `/lib/gluon/upgrade/` script, i.e. every time `gluon-reconfigure`
runs: on every firmware upgrade, on leaving setup mode, and on a domain switch -
not just once. Whether the workaround actually helps is chipset-dependent and
there's no reliable way to detect that up front, so re-running it on every
upgrade is intentional (it used to run exactly once via a self-deleting
`/etc/init.d` script gated on setup-mode, which - besides being duplicated
logic in two separate files - had a broken guard and so it could get
re-triggered on any upgrade anyway; this is the same effect, done on purpose
and in one place).

For each present radio it derives a regulatory country (DE/JP/TW/US, from the
configured 2.4/5GHz channels), applies it, and re-queries the highest available
htmode and txpower under that country via `iwinfo`, storing the result in
`/etc/config/wireless`.

Since `iwinfo`/`iw` are known to hang on some chipsets when the radio is
already up and meshing (which is the normal case here, since this now runs on
every upgrade of an already-configured node), every such call is run
backgrounded with a 20-second watchdog that `kill -9`'s it if it hasn't
finished by itself. An empty result is handled differently depending on why
it's empty: if the process had to be killed, that's a genuine hang and the
whole run aborts rather than committing a half-applied change; if the process
finished on its own with nothing to show (e.g. no txpower/htmode entry for
this device and channel), that's a legitimate outcome - it's logged and that
one value (txpower or htmode) is just left unset/at its HT20 default instead
of aborting. Progress and the final applied country/htmode/txpower values are
logged via `logger` (visible in `logread` and during a live
`gluon-reconfigure`/setup-mode run). Note: BusyBox's `timeout` applet is not
available on all targets, so the watchdog is implemented manually
(background + `sleep` + `kill -0`/`kill -9`), not via `timeout`.

(pull requests wellcome)


To use the script in your firmware:

```
GLUON_SITE_FEEDS="eulenfunk"
PACKAGES_EULENFUNK_REPO=https://github.com/eulenfunk/packages.git
PACKAGES_EULENFUNK_COMMIT=*/missing/*
PACKAGES_EULENFUNK_BRANCH=v2018.1.x
```

With this done you can add the package `neanderfunk-txpowerfix` to your `site.mk`

Radio-Erkennung (Stand 2026-09-06)
----------------------------------

Welches Radio 2,4 GHz ist und welches 5 GHz, wurde frueher aus der Kanalnummer
geschlossen: unter 16 heisst 2,4, darueber 5, und ein nicht lesbarer Kanal
wurde zu 999. Das ging an zwei Stellen schief:

* **Ein Knoten mit nur einem Radio bekam ein Phantom-5-GHz-Radio.** Auf einem
  TP-Link WR1043ND v2 gibt es kein `radio1`; `uci get wireless.radio1.channel`
  liefert nichts, daraus wurde 999, und 999 > 15 ergab `interface50 = radio1`.
  Folge: die Landeskennung wurde vom Phantom-Zweig entschieden und ueberschrieb
  die richtige Entscheidung aus dem 2,4-GHz-Zweig (bei Kanal 12 oder 13 also
  falsch), dazu zwei ueberfluessige `wifi reconf` und `iwinfo`-Aufrufe auf ein
  Geraet, das es nicht gibt.
* **Ein 2,4-GHz-Radio auf `channel=auto`** wurde ebenfalls zu 999 und landete im
  5-GHz-Zweig.

Seit OpenWrt 21.02 beantwortet `band` (`2g`/`5g`) die Frage direkt; `hwmode`
bleibt als aeltere Schreibweise als Rueckfall. Ausserdem werden jetzt die
`wifi-device`-Sektionen durchlaufen statt fest `radio0`/`radio1` anzunehmen.
