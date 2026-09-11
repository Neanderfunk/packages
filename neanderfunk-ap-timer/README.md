neanderfunk-ap-timer
====================

Fork of `ff-ap-timer` and `ff-web-ap-timer` from the Gluon community packages
(commit `91e5fa8`), merged into one package.

Timer for the client wifi with three modes (daily, weekly, monthly). It turns
the `client_radio*` interfaces on and off, but does not touch mesh or private
wifi configuration. The config-mode page (Advanced settings, "AP Timer") sets
up the daily schedule.

site.conf
---------

```lua
ap_timer = {
  web = true,   -- show the config-mode page (optional, default true)
},
```

With `web = false` the page is hidden - except on nodes where the timer is
already enabled, so it can still be switched off there.

Differences to the originals
----------------------------

* One package instead of two; `CONFLICTS` with `ff-ap-timer` and
  `ff-web-ap-timer`. The uci config keeps its name `ap-timer`, so existing
  schedules survive the switch.
* `000-neanderfunk-ap-timer`: the timer switches the client APs only as an
  uncommitted uci delta. `gluon-reconfigure` commits everything first
  (`001-reset-uci`), and `320-gluon-client-bridge-wireless` keeps `disabled`
  from the existing `client_radio*` - so a reconfigure during the off period
  used to store "off" for good. This script drops the timer's runtime deltas
  before 001; a reconfigure in the off period now behaves like a reboot in the
  off period (client wifi on until the next off time).

/etc/config/ap-timer
--------------------

**ap-timer.settings.enabled:**
- `0` disables the ap-timer (default)
- `1` enables the ap-timer

**ap-timer.settings.type:**
- `day`, $day = all
- `week`, $day = [Mon|Tue|Wed|Thu|Fri|Sat|Sun]
- `month`, $day = [01-31]

**ap-timer.$day.on:**
- List of time to enable wireless

**ap-timer.$day.off:**
- List of time to disable wireless

### example
```
config ap-timer 'settings'
	option enabled '1'
	option type 'week'

config week 'Sun'
	list on '06:00'
	list off '23:00'
```
