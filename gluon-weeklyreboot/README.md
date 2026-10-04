weekly reboot
=============

this script basically reboots a node once a week on thursday morning at a random
time between 3h15 and 6h AM.

Create a file `modules` with the following content in your `./gluon/site/`
directory and add these lines: 

```
GLUON_SITE_FEEDS="eulenfunk"
PACKAGES_EULENFUNK_REPO=https://github.com/eulenfunk/packages.git
PACKAGES_EULENFUNK_COMMIT=*/missing/*
PACKAGES_EULENFUNK_BRANCH=v2018.1.x
```

Now you can add the package `gluon-weeklyreboot` to your site.mk
(`*/missing/*` has to be replaced by the github-commit-ID of the version you
want to use, you have to pick it manually.)

When it does NOT reboot (since 2026-10, backport of the v2023.2.x fixes)
------------------------------------------------------------------------

* within the first hour after boot (checked after the random delay),
* while the clock has not been set by ntp since boot and uptime is below
  7 days: without ntp the clock starts at the newest mtime under /etc
  (sysfixtime); if that falls on Thursday 2:15 to 3:14, the cron would fire
  about an hour after every boot, forever. The marker
  `/tmp/weeklyreboot.clock-synced` is set by `/etc/hotplug.d/ntp/99-weeklyreboot`
  (ACTION=stratum),
* while the autoupdater holds `/var/lock/autoupdater.lock` (it keeps it through
  the sysupgrade) or a sysupgrade is running.
