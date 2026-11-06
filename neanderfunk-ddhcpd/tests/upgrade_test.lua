-- Host-Test fuer 500-neanderfunk-ddhcpd mit Attrappen fuer gluon.site und
-- simple-uci. Aufruf aus dem Paketverzeichnis: lua5.1 tests/upgrade_test.lua

local function proxy(t)
	return setmetatable({}, {
		__index = function(_, k) return proxy(t and t[k]) end,
		__call = function(_, default)
			if t == nil then return default end
			return t
		end,
	})
end

local function run(site_data, initial)
	local store = initial or {}
	package.loaded['gluon.site'] = proxy(site_data)
	package.loaded['simple-uci'] = {cursor = function()
		return {
			section = function(_, _, _, name, values)
				store[name] = store[name] or {}
				for k, v in pairs(values) do
					if type(v) == 'boolean' then v = v and '1' or '0' end
					store[name][k] = tostring(v)
				end
			end,
			set = function(_, _, name, option, value)
				store[name] = store[name] or {}
				store[name][option] = type(value) == 'table' and table.concat(value, ' ') or tostring(value)
			end,
			delete = function(_, _, name, option)
				if option then
					if store[name] then store[name][option] = nil end
				else
					store[name] = nil
				end
			end,
			save = function() end,
		}
	end}
	dofile('luasrc/lib/gluon/upgrade/500-neanderfunk-ddhcpd')
	return store
end

local fails = 0
local function check(name, got, want)
	if got ~= want then
		print(('FAIL %s: %s statt %s'):format(name, tostring(got), tostring(want)))
		fails = fails + 1
	end
end

-- Domain 21 mit allem
local s = run({
	next_node = {ip4 = '10.51.64.1'},
	ddhcpd = {
		enabled = true, range = '10.51.72.0/21', client_prefix4 = '10.51.64.0/20',
		router = '10.51.64.2', dns = {'10.51.64.1', '10.51.64.2'}, dhcp_lease_time = 600,
	},
})
check('enabled', s.settings.enabled, '1')
check('range', s.settings.block_network, '10.51.72.0/21')
check('spare', s.settings.spare_leases, '8')
check('learning', s.settings.learning_time, '30')
check('if', s.settings.dhcp_interface, 'local-node')
check('netmask', s.netmask.payload, '255.255.240.0')
check('router', s.router.payload, '10.51.64.2')
check('dns len', s.dns.len, '8')
check('dns', s.dns.payload, '10.51.64.1.10.51.64.2')
check('lease', s.lease_time.payload, '0.0.2.88')
check('server id', s.server_identify.payload, '10.51.64.1')
check('foreign default', s.settings.foreign_network, '10.51.64.0/20')

-- eigene Liste; {} schaltet -F ab
s = run({next_node = {ip4 = '10.51.64.1'}, ddhcpd = {enabled = true, range = '10.51.72.0/21',
	client_prefix4 = '10.51.64.0/20', foreign_prefix4 = {'10.51.64.0/21', '10.200.0.0/24'}}}, s)
check('foreign liste', s.settings.foreign_network, '10.51.64.0/21 10.200.0.0/24')
s = run({next_node = {ip4 = '10.51.64.1'}, ddhcpd = {enabled = true, range = '10.51.72.0/21',
	client_prefix4 = '10.51.64.0/20', foreign_prefix4 = {}}}, s)
check('foreign aus', s.settings.foreign_network, nil)
local nine = {}
for i = 1, 9 do nine[i] = '10.' .. i .. '.0.0/16' end
s = run({next_node = {ip4 = '10.51.64.1'}, ddhcpd = {enabled = true, range = '10.51.72.0/21',
	client_prefix4 = '10.51.64.0/20', foreign_prefix4 = nine}}, s)
check('foreign max 8', select(2, s.settings.foreign_network:gsub(' ', '')) + 1, 8)

-- ohne client_prefix4: bleibt aus, keine Netzmaske; Domainwechsel nimmt
-- Router und DNS der alten Domain weg
s = run({next_node = {ip4 = '10.51.64.1'}, ddhcpd = {enabled = true, range = '10.51.72.0/21'}}, s)
check('aus ohne prefix', s.settings.enabled, '0')
check('netmask weg', s.netmask, nil)
check('router weg', s.router, nil)
check('dns weg', s.dns, nil)
check('foreign weg', s.settings.foreign_network, nil)

-- Domain ohne ddhcpd
s = run({next_node = {ip4 = '10.51.64.1'}})
check('ohne ddhcpd', s.settings.enabled, '0')
check('lease default', s.lease_time.payload, '0.0.1.44')

for _, p in ipairs({{'10.0.0.0/8', '255.0.0.0'}, {'10.51.64.0/22', '255.255.252.0'}, {'10.1.2.3/32', '255.255.255.255'}, {'10.51.64.0/21', '255.255.248.0'}}) do
	s = run({next_node = {ip4 = '10.0.0.1'}, ddhcpd = {enabled = true, range = '10.0.0.0/24', client_prefix4 = p[1]}})
	check('maske ' .. p[1], s.netmask.payload, p[2])
end

print(fails == 0 and 'alle Tests gruen' or (fails .. ' Fehler'))
os.exit(fails == 0 and 0 or 1)
