neanderfunk-ap-timer
====================

Fork of `ff-ap-timer` and `ff-web-ap-timer` from the Gluon community packages
(commit `91e5fa8`), merged into one package.

Timer for the client wifi with three modes (daily, weekly, monthly). It turns
the `client_radio*` interfaces on and off, but does not touch mesh or private
wifi configuration. The config-mode page (Advanced settings, "AP Timer") sets
up the daily schedule.

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
