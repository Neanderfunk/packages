# Shared helpers for the eulenfunk-hotfix scripts (Sackgasse 2021.1).
# Backported from neanderfunk-hotfix/neanderfunk-common in v2025.1.x, cut down
# to what 2021.1 needs. Sourced, not executed.

# strike <prefix>: add one strike file, print the count
strike() {
	local n=1
	while [ -e "$1.$n" ] ; do n=$((n + 1)) ; done
	: > "$1.$n"
	echo "$n"
}

# unstrike <prefix>: remove all strike files
unstrike() {
	set -- "$1".*
	[ -e "$1" ] || return 0
	rm -f "$@" 2>/dev/null
}

uptime_s() {
	cut -d. -f1 /proc/uptime
}

# The autoupdater holds this flock from the start through the sysupgrade
# (it clears FD_CLOEXEC on it); a manual sysupgrade shows up in pgrep.
autoupdater_busy() {
	flock -n /var/lock/autoupdater.lock true 2>/dev/null || return 0
	pgrep sysupgrade >/dev/null && return 0
	return 1
}

# One wifi restart at a time across all checks (linkcheck, hotfix,
# wifi-blackout share this lock).
WIFI_LOCK=/var/lock/neanderfunk-wifi.lock
wifi_lock() {
	exec 201>>"$WIFI_LOCK" 2>/dev/null || return 0
	flock -n 201 2>/dev/null
}
wifi_unlock() {
	exec 201>&- 2>/dev/null
	return 0
}

# Flush in the background (a hanging flash must not block the reboot),
# reboot -f, and sysrq if the node is still there after a minute.
reboot_hard() {
	sync &
	echo s > /proc/sysrq-trigger 2>/dev/null
	sleep 3
	reboot -f &
	sleep 60
	echo b > /proc/sysrq-trigger 2>/dev/null
}
