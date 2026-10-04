neanderfunk-txpowerfix (Sackgasse 2021.1)
=========================================

Port of `neanderfunk-txpowerfix` from `v2025.1.x` (decision adorfer,
2026-10-04): keep the country logic and the htmode, remove pinned txpower
values, never set a new one.

Runs as `/lib/gluon/upgrade/215-neanderfunk-txpower-fix` on every reconfigure:

* **country** per radio from the configured channels (DE/JP/TW/US, logic
  unchanged),
* **htmode**: best 20 MHz mode on 2.4 GHz, widest 80/40 MHz mode on 5 GHz
  (5 GHz only if the channel is not `auto` and outdoor mode is off), read via
  the iwinfo Lua binding; left alone while `preserve_channels` is set
  (`gluon-core`, 2021.1 spelling),
* **txpower** is removed **once per node** (marker
  `/lib/gluon/core/sysconfig/neanderfunk_txpowerfix_unpinned`), unless
  `gluon.wireless.preserve_txpower` is set. Without a value the kernel uses
  min(hardware, regdomain) per channel; a pinned value can only lower it.

Only config is written (`uci:save()`, `998-commit` commits). The old init
script and `txpowerfix.lua` (first boot: wifi down/up, txpower set as a row
index of `iwinfo txpowerlist`) are gone, as is the dependency on
wireless-tools.

Background and measurements: README of `neanderfunk-txpowerfix` in
`v2025.1.x`.
