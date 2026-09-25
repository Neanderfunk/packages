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

Add the feed to your site's `modules` file (next to `site.conf`):

```
GLUON_SITE_FEEDS="neanderfunk"
PACKAGES_NEANDERFUNK_REPO=https://github.com/Neanderfunk/packages.git
PACKAGES_NEANDERFUNK_BRANCH=v2023.2.x
PACKAGES_NEANDERFUNK_COMMIT=<commit>
```

Then add `neanderfunk-weeklyreboot` to your `site.mk` or `image-customization.lua`. Replace
`<commit>` with a commit of the `v2023.2.x` branch. If your site already uses
other feeds, append `neanderfunk` to the existing `GLUON_SITE_FEEDS` instead
of replacing it. See also [Using this feed](../README.md#using-this-feed).


Mutually exclusive packages
---------------------------

Declares `CONFLICTS:=ffac-weeklyreboot gluon-weeklyreboot`. `ffac-weeklyreboot`
installs the same two paths and does the same job; `gluon-weeklyreboot` is what
this package was called before the rename and still exists upstream.

Wann NICHT rebootet wird
------------------------

* **In den ersten 60 Minuten nach dem Boot.** Der Knoten ist gerade
  hochgekommen, ein weiterer Neustart bringt nichts. Geprueft wird nach der
  Zufallsverzoegerung, weil die bis zu 2h46 dauern kann.
* **Waehrend ein Autoupdater laeuft.** Zweistufig: `flock` auf
  `/var/lock/autoupdater.lock` deckt Download und Pruefung ab, `pgrep
  sysupgrade` den Flash selbst. Beides fail-safe - im Zweifel kein Reboot, denn
  ein Reboot in einen laufenden Flash brickt den Knoten.
* **Solange die Uhr nie per ntp gestellt wurde und die Uptime unter 7 Tagen
  liegt.** Ohne ntp startet die Uhr bei jedem Boot mit der Bauzeit der Firmware
  (`sysfixtime`). Wurde das Image an einem Donnerstag gegen 02:00 gebaut,
  erreicht so ein Knoten die Cron-Zeit `15 3 * * 4` etwa eine Stunde nach jedem
  Boot - und rebootet endlos. Der Knoten soll trotzdem regelmaessig neu
  starten, nur eben nach Laufzeit statt nach Wochentag: der Cron feuert auch
  mit falscher Uhr nur einmal pro (falscher) Woche, die 7-Tage-Bedingung macht
  daraus also einen echten Wochenrhythmus statt einer Stundenschleife.

Die Markierung fuer "Uhr wurde gestellt" setzt
`/etc/hotplug.d/ntp/99-neanderfunk-weeklyreboot`: ntpd laeuft mit
`-S /usr/sbin/ntpd-hotplug` und feuert bei Synchronisation ein Ereignis mit
`ACTION=stratum`. Die Datei liegt in `/tmp`, muss also nach jedem Boot neu
verdient werden.
