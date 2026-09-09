#!/usr/bin/lua

local uci = require('simple-uci').cursor()

-- Safety check functions
local function log_debug(...)
	if uci:get('ssid-changer', 'settings', 'debug_log_enabled') == '1' then
		os.execute('logger -t "neanderfunk-ssid-changer" -p debug "' .. table.concat({...}, ' ') .. '"')
	end
end

local function log(...)
	os.execute('logger -t "neanderfunk-ssid-changer" "' .. table.concat({...}, ' ') .. '"')
end

local function safety_exit(message)
	log_debug(message .. ", exiting with error code 2")
	os.exit(2)
end

-- Check if the script is enabled
if uci:get('ssid-changer', 'settings', 'enabled') == '0' then
	os.exit(0)  -- Exit silently if the script is disabled
end

-- Check for autoupdater running
--
-- Hier stand "pgrep -f autoupdater", und das war die einzige Stelle im Feed,
-- die wirklich anfaellig war: "-f" durchsucht die Kommandozeile, findet also
-- jeden fremden Prozess, der das Wort fuehrt - am Knoten gemessen drei PIDs,
-- von denen keine der Autoupdater war, darunter ein Skript, das seinerseits
-- nur danach suchte. Der Check haette dann dauerhaft "laeuft" gemeldet und
-- den ssid-changer stillgelegt.
--
-- nf-pgrep vergleicht stattdessen den Prozessnamen exakt und blendet die
-- eigene Prozesskette aus; die Kunstgriffe, die hier frueher noetig waren
-- (ein einzelnes einfaches Kommando, damit busybox' "sh -c" es exec't statt
-- zu forken), entfallen damit.
--
-- os.execute liefert unter Lua 5.1 den rohen wait-Status; 0 heisst, nf-pgrep
-- hat etwas gefunden.
local function is_autoupdater_running()
	return os.execute('nf-pgrep -q autoupdater') == 0
end

if is_autoupdater_running() then
	safety_exit('autoupdater running')
end

-- Read uptime
local function get_uptime()
	local file = io.open('/proc/uptime', 'r')
	local uptime = file:read("*n")  -- Read only the first number (uptime in seconds)
	file:close()
	return uptime
end

local uptime = get_uptime()
local uptime_minutes = math.floor(uptime / 60)
local monitor_duration = tonumber(uci:get('ssid-changer', 'settings', 'switch_timeframe') or 30)
-- Das "or 30" oben faengt nur einen FEHLENDEN Wert. Steht dort etwas
-- Unnumerisches, ist monitor_duration nil und das Modulo unten wirft; eine 0
-- ergibt in Lua 5.1 ein nan, mit dem alle folgenden Vergleiche still
-- fehlschlagen.
if not monitor_duration or monitor_duration < 1 then
	monitor_duration = 30
end
local is_switch_time = uptime_minutes % monitor_duration

if uptime < 60 then
	safety_exit('uptime less than one minute')
end

-- Check for hostapd processes
local function has_hostapd_processes()
	local handle = io.popen('find /var/run -name "hostapd-*.conf" | wc -l')
	local result = handle:read("*a")
	handle:close()
	return tonumber(result) > 0
end

if not has_hostapd_processes() then
	safety_exit('no hostapd-*')
end

-- Generate the offline SSID
local function calculate_offline_ssid()
	local prefix = uci:get('ssid-changer', 'settings', 'prefix') or 'FF_Offline_'
	local settings_suffix = uci:get('ssid-changer', 'settings', 'suffix') or 'nodename'
	local suffix

	if settings_suffix == 'nodename' then
		suffix = io.popen('uname -n'):read("*a"):gsub("%s+", "")
		if #suffix > (30 - #prefix) then
			local max_suffix_length = math.floor((28 - #prefix) / 2)
			local suffix_first_chars = suffix:sub(1, max_suffix_length)
			local suffix_last_chars = suffix:sub(-max_suffix_length)
			suffix = suffix_first_chars .. '...' .. suffix_last_chars
		end
	elseif settings_suffix == 'mac' then
		suffix = io.popen('uci -q get network.bat0.macaddr | sed "s/://g"'):read("*a"):gsub("%s+", "")
	else
		suffix = ''
	end

	return prefix .. suffix
end

local offline_ssid = calculate_offline_ssid()

-- Count offline incidents
local tmp = '/tmp/ssid-changer-count'
local tmp_state = '/tmp/ssid-changer-offline'
local tmp_gwoffstate = '/tmp/ssid-changer-gwofflinecount'
local gwoffmaxcount = tonumber(uci:get('ssid-changer', 'settings', 'gwofflinemaxcount') or 3)
local off_count = 0
-- Muss hier stehen, nicht erst in der Zuweisung unten. gwoffcount war eine
-- implizite globale Variable und wurde nur im if-Zweig gesetzt - beim ersten
-- Lauf nach einem Boot existiert /tmp/ssid-changer-gwofflinecount aber noch
-- nicht, der else-Zweig legt sie an und laesst gwoffcount auf nil. Kommt dann
-- noch dazu, dass has_default_gw4() falsch ist (also genau die Lage, fuer die
-- dieses Skript da ist), stirbt es an
--   ssid-changer.lua:NNN: attempt to compare number with nil
-- und schaltet gar nichts. Am Knoten im Feld beobachtet, 2026-09-06.
local gwoffcount = 0
local file = io.open(tmp, 'r')

-- tmp_state is only a diagnostic now ("was the node considered offline at the
-- last window boundary?", handy when chasing reports about stuck SSIDs). It is
-- deliberately not read back for any decision: see offline_ssid_is_configured().
local state_file = io.open(tmp_state, 'r')
local gwoffstate_file = io.open(tmp_gwoffstate, 'r')

if state_file then
	state_file:close()
else
	state_file = io.open(tmp_state, 'w')
	state_file:write("0")
	state_file:close()
end

if file then
	off_count = tonumber(file:read("*a")) or 0
	file:close()
else
	file = io.open(tmp, 'w')
	file:write("0")
	file:close()
end

if gwoffstate_file then
	gwoffcount = tonumber(gwoffstate_file:read("*a")) or 0
	gwoffstate_file:close()
else
	gwoffstate_file = io.open(tmp_gwoffstate, 'w')
	gwoffstate_file:write("0")
	gwoffstate_file:close()
end

-- Gemeinsame Sperre fuer WLAN-Eingriffe, dieselbe Datei wie in
-- neanderfunk-hotfix und -linkcheck. Auf einem Knoten koennen
-- sieben Stellen das WLAN anfassen, dieses Skript als einziges jede Minute.
-- Laeuft gerade ein Neustart, wird nicht dazwischengefunkt.
--
-- os.execute liefert unter Lua 5.1 den rohen wait-Status; 0 heisst Erfolg.
-- flock gibt 1 zurueck, wenn die Sperre belegt ist.
local function wifi_reconf()
	local rc = os.execute("flock -n /var/lock/neanderfunk-wifi.lock -c 'wifi reconf'")
	if type(rc) == 'number' and rc ~= 0 then
		return false
	end
	return rc ~= false
end

local function calculate_tq_limit()
	local tq_limit_max = tonumber(uci:get('ssid-changer', 'settings', 'tq_limit_max') or 45)
	local tq_limit_min = tonumber(uci:get('ssid-changer', 'settings', 'tq_limit_min') or 35)
	local gateway_tq

	-- Das awk-Programm MUSS einfach gequotet sein. Vorher stand es in doppelten
	-- Anführungszeichen, also expandierte die Shell das $2 zu leer, awk bekam
	-- "{print }" und gab damit die ganze Zeile aus statt des TQ-Werts:
	--
	--   [*02:ca:ff:ee:21:03(255)02:ca:ff:ee:21:03[mesh-vpn]:1024.0/1024.0MBit]
	--
	-- tonumber() darauf ist nil, calculate_tq_limit() lief also bei jedem Aufruf
	-- in den Rückfall unten und lieferte immer 'online'. Die TQ-Schwelle war
	-- damit wirkungslos, obwohl tq_limit_enabled=1 auf den Knoten gesetzt ist.
	-- An zwei Geräten gemessen; mit einfachen Anführungszeichen kommt 255.
	local handle = io.popen([[batctl gwl -H | grep -e "^ *\*" | awk -F'[()]' '{print $2}' | tr -d " "]])
	gateway_tq = tonumber(handle:read("*a"))
	handle:close()

	if not gateway_tq then
		-- We only get here when has_default_gw4() was true, so a gateway does
		-- exist - batctl just didn't report a parsable TQ for the selected one
		-- right now (e.g. while gateway election is still settling after a
		-- reconnect). Do NOT exit the script here: that would skip the
		-- "revert to the normal SSID" path below and keep a recovered node on
		-- the offline SSID. Fall back to what the non-tq_limit path would say
		-- for an existing gateway instead.
		log('no parsable gateway TQ, falling back to online for this run')
		return 'online'
	end
	local is_online

	if gateway_tq >= tq_limit_max then
		is_online = true
	elseif gateway_tq < tq_limit_min then
		is_online = false
	else
		-- in the middle part we consider us offline if there was at least one offline incidents
		-- or we were offline before the current monitor interval
		is_online = off_count == 0
	end

	if is_online then
		return 'online'
	else
		return 'offline'
	end
end

local function has_default_gw4()
	local default_gw4 = io.open('/var/gluon/state/has_default_gw4', 'r')
	if default_gw4 then
		default_gw4:close()
		return true
	end
	return false
end

local status
if has_default_gw4() then
	gwoffstate_file = io.open(tmp_gwoffstate, 'w')
	gwoffstate_file:write("0")
	gwoffstate_file:close()

	local tq_limit_enabled = tonumber(uci:get('ssid-changer', 'settings', 'tq_limit_enabled') or 0)

	if tq_limit_enabled == 1 then
		status = calculate_tq_limit()
	else
		status = 'online'
	end
else
	if gwoffcount >= gwoffmaxcount then
		status = 'offline'
	else
		gwoffcount = gwoffcount + 1
		gwoffstate_file = io.open(tmp_gwoffstate, 'w')
		gwoffstate_file:write(tostring(gwoffcount))
		gwoffstate_file:close()
		status = 'online'
	end
end

-- Is any client radio currently carrying the offline SSID? The /tmp bookkeeping
-- can be lost (files are truncated on open and only flushed on close, so a kill
-- in between leaves them empty, and tonumber('') silently becomes 0), while the
-- offline SSID lives on in the uncommitted wireless delta. Deciding the revert
-- from off_count alone would then never fire again and the node would stay on
-- the offline SSID until its next reboot, with the config looking untouched.
local function offline_ssid_is_configured()
	for i = 0, 2 do
		if uci:get('wireless', 'client_radio' .. i, 'ssid') == offline_ssid then
			return true
		end
	end
	return false
end

if status == 'online' then
	log_debug("node is online")
	-- only revert and reconf if we were offline in the current monitoring timeframe or before
	-- to reduce impact
	if off_count > 0 or offline_ssid_is_configured() then
		log("reverting offline ssid back to default wireless config")
		uci:revert('wireless')
		if not wifi_reconf() then
			-- Hier NICHT aufraeumen. Der revert hat den uci-Delta bereits
			-- verworfen, offline_ssid_is_configured() sieht die Offline-SSID
			-- also nicht mehr - wuerde jetzt auch off_count auf 0 fallen,
			-- gaebe es keinen Ausloeser mehr und der Knoten bliebe auf der
			-- Offline-SSID haengen. Genau der Fehler, den dieses Paket schon
			-- einmal hatte. off_count bleibt stehen, der naechste Lauf in
			-- einer Minute versucht es erneut.
			log("wifi reconf skipped, another check is restarting wifi - retrying next run")
			os.exit(0)
		end

		-- Clear the offline bookkeeping right away. Without this, off_count
		-- keeps its old value until the next switch_timeframe boundary, so
		-- this branch would run again on every single following minute -
		-- reverting an already reverted config and restarting wifi (kicking
		-- clients) once a minute for up to switch_timeframe minutes.
		off_count = 0
		file = io.open(tmp, 'w')
		file:write("0")
		file:close()
		state_file = io.open(tmp_state, 'w')
		state_file:write("0")
		state_file:close()
	end
elseif status == 'offline' then
	log_debug("node is considered offline")
	local first = tonumber(uci:get('ssid-changer', 'settings', 'first') or 5)
	-- set SSID offline, only if uptime is less than FIRST or exactly a multiplicative of switch_timeframe
	if uptime_minutes < first or is_switch_time == 0 then

		-- Check if off_count is more than half of the monitor duration.
		-- The "is it already applied?" half of this guard is answered from the
		-- actual wireless config rather than from the is_offline bookkeeping:
		-- is_offline is written from `status` at every window boundary, even on
		-- boundaries where the SSID was NOT switched (off_count below the
		-- threshold). It then reads as "already offline" forever after, which
		-- blocked the switch for the whole time a node stayed offline.
		if not offline_ssid_is_configured() and off_count >= math.floor(monitor_duration / 2) then
			-- if has been offline for at least half checks in monitor duration
			-- set the SSID to the offline SSID
			-- and disable owe client radios
			for i = 0, 2 do
				local client_ssid = uci:get('wireless', 'client_radio' .. i, 'ssid')
				if client_ssid then
					uci:set('wireless', 'client_radio' .. i, 'ssid', offline_ssid)
				end

				local owe_ssid = uci:get('wireless', 'owe_radio' .. i, 'ssid')
				if owe_ssid then
					uci:set('wireless', 'owe_radio' .. i, 'disabled', 1)
				end
				-- save does not commit
				uci:save('wireless')
			end
			log("reconfiguring wifi to offline ssid")
			if not wifi_reconf() then
				-- Der uci-Delta traegt die Offline-SSID schon, angewendet ist
				-- sie nicht. Das ist unkritisch: kommt der Knoten zurueck,
				-- sieht offline_ssid_is_configured() den Delta und raeumt auf;
				-- bleibt er offline, versucht es der naechste Schaltzeitpunkt.
				log("wifi reconf skipped, another check is restarting wifi")
			end
		end
	end
	off_count = off_count + 1
	file = io.open(tmp, 'w')
	file:write(tostring(off_count))
	file:close()
end

if is_switch_time == 0 then
	file = io.open(tmp, 'w')
	state_file = io.open(tmp_state, 'w')

	if status == 'offline' then
		file:write("1")
		state_file:write("1")
	else
		file:write("0")
		state_file:write("0")
	end
	file:close()
	state_file:close()
end
