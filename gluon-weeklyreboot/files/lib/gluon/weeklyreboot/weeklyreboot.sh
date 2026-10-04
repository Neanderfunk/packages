#!/bin/sh
# Wochen-Reboot, Do 3:15 (micron.d) plus Zufall bis 2h46. Nachbau von
# v2023.2.x 2fe958d/de7a7e9 fuer die Sackgasse 2021.1.
# (Kommentare entfernt gluonShellDiet.sh beim Bau.)
d=$(tr -dc 0-9 </dev/urandom | head -c4)
logger -t gluon-weeklyreboot -p 5 "scheduled reboot in ${d:=3600} seconds"
sleep $d
u=$(cut -d. -f1 /proc/uptime)
# Nicht kurz nach dem Boot (gemessen nach der Verzoegerung).
[ $u -gt 3600 ] || exit 0
# Ohne ntp startet die Uhr bei jedem Boot mit der neuesten mtime unter /etc
# (sysfixtime). Faellt die auf Do 2:15 bis 3:14, kaeme der Cron etwa eine
# Stunde nach jedem Boot: Endlos-Reboot. Ohne ntp-Marke daher erst nach
# 7 Tagen Laufzeit (der Cron feuert auch mit falscher Uhr nur woechentlich).
[ -f /tmp/weeklyreboot.clock-synced ] || [ $u -gt 604800 ] || exit 0
# Nicht in einen laufenden Autoupdater (haelt das flock bis in den
# sysupgrade) oder einen Flash von Hand.
flock -n /var/lock/autoupdater.lock true && ! pgrep sysupgrade >/dev/null || exit 2
logger -t gluon-weeklyreboot -p 5 "rebooting"
reboot
