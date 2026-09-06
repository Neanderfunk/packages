-- All optional: the defaults in /usr/sbin/wifi-blackout apply when a site sets
-- nothing. The old ath9kblackout spelling is still read at runtime, so a site
-- that has not been migrated keeps working.
need_number(in_site({'wifi_blackout','blackoutwait'}), false)
need_number(in_site({'wifi_blackout','resetwait'}), false)
need_number(in_site({'wifi_blackout','stepsize'}), false)
