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
