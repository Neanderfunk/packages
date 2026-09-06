weekly reboot
=============

this script basically reboots a node once a week on thursday morning at a random
time between 3h15 and 6h AM.

This clears up long-running memory/state issues on nodes that otherwise stay up
for months. If an autoupdater run is in progress (`/tmp/autoupdate.lock`
present), the reboot is skipped for that week rather than interrupting the
update. The schedule is fixed in `files/usr/lib/micron.d/weeklyreboot`; there
is no site.conf option to change it, so to change the day/time you have to
edit that cron line and rebuild.

Create a file `modules` with the following content in your `./gluon/site/`
directory and add these lines: 

```
GLUON_SITE_FEEDS="eulenfunk"
PACKAGES_EULENFUNK_REPO=https://github.com/eulenfunk/packages.git
PACKAGES_EULENFUNK_COMMIT=*/missing/*
PACKAGES_EULENFUNK_BRANCH=v2018.1.x
```

Now you can add the package `neanderfunk-weeklyreboot` to your site.mk
(`*/missing/*` has to be replaced by the github-commit-ID of the version you
want to use, you have to pick it manually.)


Mutually exclusive packages
---------------------------

Declares `CONFLICTS:=ffac-weeklyreboot gluon-weeklyreboot`. `ffac-weeklyreboot`
installs the same two paths and does the same job; `gluon-weeklyreboot` is what
this package was called before the rename and still exists upstream.
