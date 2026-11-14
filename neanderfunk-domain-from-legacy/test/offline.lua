-- Offline-Test ohne Gluon (lua5.1, Module nachgebildet): lua5.1 test/offline.lua luasrc/lib/gluon/upgrade/004-neanderfunk-domain-from-legacy
local SKRIPT = arg[1]
local DOMS, OLD, RESULT, LOGS
package.preload['posix.unistd'] = function() return { access = function() return true end } end
package.preload['posix.sys.stat'] = function() return {
	lstat = function(p) local n = p:match('[^/]+$'); return DOMS[n] and { st_mode = DOMS[n].alias and 'l' or 'r' } end,
	S_ISREG = function(m) return m == 'r' and 1 or 0 end } end
package.preload['posix.dirent'] = function() return { files = function()
	local names = {}; for n in pairs(DOMS) do names[#names + 1] = n end; table.sort(names)
	local i = 0; return function() i = i + 1; return names[i] end end } end
package.preload['jsonc'] = function() return { load = function(p) return DOMS[p:match('[^/]+$')].d end } end
package.preload['simple-uci'] = function() return { cursor = function() return {
	get = function(_, c, s, o)
		if c == 'gluon' then return RESULT end
		if c == 'network_gluon-old' and s == 'local_node' and o == 'ipaddr' then return OLD.ip4 and (OLD.ip4 .. '/20') end
	end,
	foreach = function(_, c, t, f) if c == 'wireless_gluon-old' then for _, m in ipairs(OLD.mesh or {}) do f({ mode = 'mesh', mesh_id = m }) end end end,
	set = function(_, c, s, o, v) RESULT = v end, save = function() end } end } end
io.popen = function() return { write = function(_, m) LOGS[#LOGS + 1] = m:gsub('\n', '') end, close = function() end } end
io.stderr = { write = function() end }
local function dom(code, mesh, ip4, legacy)
	DOMS[code .. '.json'] = { d = { wifi24 = { mesh = { id = mesh } }, wifi5 = { mesh = { id = mesh } }, next_node = { ip4 = ip4 }, neanderfunk_legacy = legacy } }
end
local function setup()
	DOMS = {}
	dom('nef-01_vel', 'vel-mesh', '10.1.0.1', { mesh_id = { 'ffnef-vel-mesh' }, next_node_ip4 = { '10.40.0.1' }, next_node_ip4_fest = { '10.40.0.1' } })
	dom('nef-17_wip', 'wip-mesh', '10.17.0.1', { next_node_ip4 = { '10.31.0.1' }, next_node_ip4_fest = { '10.31.0.1' } })
	dom('lvrno-31_lvrno', 'lvrno-mesh', '10.31.0.1', { next_node_ip4 = { '10.51.224.1' } })
	dom('sim-40_sim', 'sim-mesh', '10.40.0.1', { next_node_ip4 = { '10.52.112.1' } })
	dom('nef-21_dias', 'dias-mesh', '10.21.0.1', { next_node_ip4 = { '10.51.64.1' } })
	DOMS['alias.json'] = { alias = true, d = {} }
end
local fail = 0
local function run(name, ip4, mesh, want)
	setup(); OLD = { ip4 = ip4, mesh = mesh }; RESULT = nil; LOGS = {}
	assert(loadfile(SKRIPT))()
	local ok = (RESULT or '-') == (want or '-')
	if not ok then fail = fail + 1 end
	print(string.format('%s %-48s erwartet %-15s bekommen %-15s | %s', ok and 'OK  ' or 'FEHL', name, want or '-', RESULT or '-', table.concat(LOGS, ' / ')))
end
run('ohne WLAN, 10.31.0.1 fest -> 17', '10.31.0.1', {}, 'nef-17_wip')
run('ohne WLAN, 10.40.0.1 fest -> 01', '10.40.0.1', {}, 'nef-01_vel')
run('ohne WLAN, neue 10.17.0.1 -> 17', '10.17.0.1', {}, 'nef-17_wip')
run('ohne WLAN, neue 10.1.0.1 -> 01', '10.1.0.1', {}, 'nef-01_vel')
run('ohne WLAN, alte 31er 10.51.224.1 -> 31', '10.51.224.1', {}, 'lvrno-31_lvrno')
run('ohne WLAN, alte 40er 10.52.112.1 -> 40', '10.52.112.1', {}, 'sim-40_sim')
run('Mesh 31, IPv4 10.31.0.1 -> Mesh gewinnt', '10.31.0.1', { 'lvrno-mesh' }, 'lvrno-31_lvrno')
run('Mesh 40, IPv4 10.40.0.1 -> Mesh gewinnt', '10.40.0.1', { 'sim-mesh' }, 'sim-40_sim')
run('Mesh 21 alt', '10.51.64.1', { 'dias-mesh' }, 'nef-21_dias')
run('ohne WLAN, unbekannt -> default', '10.99.0.1', {}, nil)
run('Neuinstallation -> still', nil, {}, nil)
print(fail == 0 and 'ALLE OK' or (fail .. ' FEHLER'))
os.exit(fail == 0 and 0 or 1)
