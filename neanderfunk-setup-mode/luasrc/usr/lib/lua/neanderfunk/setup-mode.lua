-- SPDX-FileCopyrightText: 2026 adorfer/Neanderfunk
-- SPDX-License-Identifier: BSD-3-Clause
--
-- The whole config mode on one page: the wizard and every form of
-- "Advanced settings", saved together by one "Save & restart".
--
-- The forms stay what they are. They are loaded, parsed and written the way
-- gluon-web-model does it; this module only decides which forms go on the
-- page, how they are rendered and in which order and under which rules
-- they are written:
--
--   * all or nothing: nothing is written unless every form is valid,
--   * only forms the user actually changed are written (the wizard always:
--     it is the one that finishes the setup),
--   * the advanced forms first, the wizard last - its write sets
--     "configured", runs gluon-reconfigure and reboots,
--   * while the advanced forms are written, uci commits become saves and
--     gluon-reconfigure / upgrade-script calls are skipped: the wizard's
--     gluon-reconfigure runs them all and commits everything once
--     (001-reset-uci starts with "uci commit"). On one page, the forms'
--     cursors were all loaded before the first write, so a form committing a
--     package it did not change would otherwise write back a stale copy.

local glob = require 'posix.glob'
local classes = require 'gluon.web.model.classes'
local webutil = require 'gluon.web.util'
local util = require 'gluon.util'

local instanceof = webutil.instanceof

local M = {}

local BASE = '/lib/gluon/config-mode'
local PKG = 'neanderfunk-setup-mode'
M.PKG = PKG

-- Wizard modules (lib/gluon/config-mode/wizard/NNNN-<name>.lua) and the group
-- of the page they go into. Modules not listed get a group of their own.
local WIZARD_GROUP = {
	['hostname'] = 'node',
	['domain-select'] = 'node',
	['contact-info'] = 'node',
	['geo-location'] = 'geo',
	['mesh-vpn'] = 'vpn',
	['outdoor'] = 'outdoor',
	['autoupdater-info'] = 'updates',
}

local WIZARD_GROUPS = {
	{key = 'node', title = 'Node'},
	{key = 'geo', title = 'Location'},
	{key = 'vpn', title = 'Internet connection'},
	{key = 'outdoor', title = 'Outdoor installation'},
}

-- Gluon's standard templates and their one-page counterparts. Nodes with any
-- other template (custom sections, warnings, the map) are left alone.
local TEMPLATES = {
	['model/form'] = PKG .. '/form',
	['model/section'] = PKG .. '/section',
	['model/valuewrapper'] = PKG .. '/value',
}


local function walk(node, fn)
	fn(node)
	for _, child in ipairs(node.children or {}) do
		walk(child, fn)
	end
end


-- Evaluates the controllers once more, as the dispatcher does, but in an
-- environment that records instead of building the tree: which entries are
-- forms (model()), with which package, title and order. The dispatcher's tree
-- keeps only closures, from which the model name cannot be read back.
-- Our own controller is skipped, so the original wizard entry is found.
function M.scan()
	local entries = {}

	local files = {}
	for _, pattern in ipairs({'*.lua', '*/*.lua'}) do
		for _, path in ipairs(glob.glob(BASE .. '/controller/' .. pattern, 0) or {}) do
			if not path:find('/' .. PKG .. '/', 1, true) then
				table.insert(files, path)
			end
		end
	end

	for _, path in ipairs(files) do
		local pkg
		local function marker(kind, arg)
			return {kind = kind, arg = arg}
		end
		local env = setmetatable({
			package = function(name) pkg = name end,
			node = function() return {nodes = {}} end,
			entry = function(p, target, title, order)
				local e = {path = p, target = target or {}, title = title, order = order, pkg = pkg}
				entries[table.concat(p, '/')] = e
				return e
			end,
			alias = function(...) return marker('alias', {...}) end,
			call = function() return marker('call') end,
			template = function(view) return marker('template', view) end,
			model = function(name) return marker('model', name) end,
			_ = function(text) return text end,
		}, {__index = _G})

		local ctl = loadfile(path)
		if ctl then
			setfenv(ctl, env)
			pcall(ctl)
		end
	end

	local scan = {forms = {}, pages = {}}
	for _, e in pairs(entries) do
		local p = e.path
		if #p == 1 and p[1] == 'wizard' and e.target.kind == 'model' then
			scan.wizard = {model = e.target.arg, pkg = e.pkg}
		elseif #p == 2 and p[1] == 'admin' and e.title then
			local item = {name = p[2], title = e.title, order = e.order or 100, pkg = e.pkg}
			if e.target.kind == 'model' then
				item.model = e.target.arg
				table.insert(scan.forms, item)
			else
				table.insert(scan.pages, item)
			end
		end
	end

	local function byorder(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.name < b.name
	end
	table.sort(scan.forms, byorder)
	table.sort(scan.pages, byorder)

	return scan
end


-- Loads a model file. Mirrors load() in gluon/web/model.lua, which is not
-- exported: the file runs in an environment of the model classes and the
-- i18n of its package, and returns one or more forms.
local function load_model(renderer, name, pkg)
	local func = assert(loadfile(BASE .. '/model/' .. name .. '.lua'))

	local i18n = setmetatable({
		i18n = renderer.i18n,
	}, {
		__index = renderer.i18n(pkg),
	})

	setfenv(func, setmetatable({}, {
		__index = function(_, key)
			return classes[key] or i18n[key] or _G[key]
		end,
	}))

	local maps = {func()}
	for k, map in ipairs(maps) do
		assert(instanceof(map, classes.Node), 'model definition returned an invalid model object')
		map.index = k
	end
	return maps
end

-- Loads the wizard and notes which module added which section. wizard.lua
-- runs every module as "setfenv(assert(loadfile(file)), getfenv())()(f, uci)";
-- for that one call loadfile is wrapped so the module function reports the
-- sections it appended. Should wizard.lua ever load its modules differently,
-- the origins stay empty and the page falls back to one untitled group.
local function load_wizard(renderer, wizard)
	local origin = {}
	local real = loadfile

	_G.loadfile = function(path, ...)
		local chunk, err = real(path, ...)
		local name = chunk and type(path) == 'string'
			and path:match('/config%-mode/wizard/%d*%-?([^/]+)%.lua$')
		if not name then
			return chunk, err
		end

		return function(...)
			setfenv(chunk, getfenv(1))
			local section = chunk(...)
			return function(form, ...)
				local before = #form.children
				section(form, ...)
				for i = before + 1, #form.children do
					origin[form.children[i]] = name
				end
			end
		end
	end

	local ok, maps = pcall(load_model, renderer, wizard.model, wizard.pkg)
	_G.loadfile = real
	if not ok then
		error(maps, 0)
	end

	return maps[1], origin
end


local function normalize(node, value)
	if instanceof(node, classes.Flag) then
		return value and '1' or '0'
	end
	if type(value) == 'table' then
		local list = {}
		for _, v in ipairs(value) do
			if v ~= '' then
				table.insert(list, tostring(v))
			end
		end
		if instanceof(node, classes.MultiListValue) then
			table.sort(list)
		end
		return table.concat(list, '\n')
	end
	if value == nil then
		return ''
	end
	value = tostring(value)
	if instanceof(node, classes.TextValue) then
		-- Browsers send textarea lines with CRLF.
		value = util.trim(value:gsub('\r', ''))
	end
	return value
end

-- What the page showed, per field, taken before the request is parsed.
local function snapshot(map)
	walk(map, function(node)
		if instanceof(node, classes.AbstractValue) then
			node.nf_initial = normalize(node, node:cfgvalue())
		end
	end)
end

local function changed(map)
	local result = false
	walk(map, function(node)
		if instanceof(node, classes.AbstractValue) and node.state == classes.FORM_VALID
				and normalize(node, node.data) ~= node.nf_initial then
			result = true
		end
	end)
	return result
end

local function has_error(map)
	local result = map.errmessage ~= nil
	walk(map, function(node)
		if node.error then
			result = true
		end
	end)
	return result
end

local function find_option(map, name)
	local found
	walk(map, function(node)
		if not found and node.name == name and instanceof(node, classes.AbstractValue) then
			found = node
		end
	end)
	return found
end

local function retemplate(map)
	walk(map, function(node)
		local t = TEMPLATES[node.template]
		if t and node.package == 'gluon-web-model' then
			node.template = t
			node.package = PKG
		end
	end)
end


-- The message under a field that failed its check, from what the field
-- expects. gluon-web-model itself only knows "invalid".
local function error_text(t, node)
	if instanceof(node, classes.Flag) then
		return nil -- a switch cannot be wrong
	end
	local dt = node.datatype
	local name, a, b = (dt or ''):match('^([%w]+)%(([^,%)]+),?([^%)]*)%)$')
	name = name or dt

	if name == 'minlength' then
		if tonumber(a) and tonumber(a) <= 1 then
			return t('This field is required.')
		end
		return t('At least %s characters.'):format(a)
	elseif name == 'maxlength' then
		return t('At most %s characters.'):format(a)
	elseif name == 'ipaddr' then
		return t('Not a valid IP address.')
	elseif name == 'ip4addr' then
		return t('Not a valid IPv4 address.')
	elseif name == 'ip6addr' then
		return t('Not a valid IPv6 address.')
	elseif name == 'float' or name == 'ufloat' then
		return t('Please enter a number.')
	elseif name == 'integer' or name == 'uinteger' then
		return t('Please enter a whole number.')
	elseif name == 'irange' then
		return t('A whole number from %s to %s.'):format(a, b)
	elseif name == 'range' then
		return t('A number from %s to %s.'):format(a, b)
	elseif name == 'wpakey' then
		return t('The key needs 8 to 63 characters.')
	elseif not dt and not node.optional then
		return t('This field is required.')
	end
	return t('Please check this input.')
end

-- Whether root has a password (gluon-web-admin locks it with passwd -l).
local function password_is_set()
	for line in io.lines('/etc/shadow') do
		local hash = line:match('^root:([^:]*):')
		if hash then
			return hash ~= '' and not hash:match('^[!*]')
		end
	end
	return false
end

-- On the one page an empty password field means "unchanged", so removing a
-- password needs a switch of its own. It is added to gluon-web-admin's
-- password form and hides both fields; the form's own write() then does
-- what it always did with empty fields: passwd -l root. Only offered while
-- a password is set.
local function add_password_removal(t, map)
	local pw1, pw2 = find_option(map, 'pw1'), find_option(map, 'pw2')
	if not (pw1 and pw2 and pw1.parent == pw2.parent) or not password_is_set() then
		return
	end

	local section = pw1.parent
	local remove = section:option(classes.Flag, 'nf_pwremove', t('Remove password'),
		t('Log in with the SSH keys above only. Without keys there is no remote access at all.'))
	remove.default = false

	-- first in the section, above the password fields
	table.insert(section.children, 1, table.remove(section.children))
	for i, child in ipairs(section.children) do
		child.index = i
	end

	pw1:depends(remove, false)
	pw2:depends(remove, false)
end


-- Runs fn with commits turned into saves and reconfigure calls skipped, see
-- the top of this file.
local function deferred(fn)
	local Cursor = getmetatable(require('simple-uci').cursor()).__index
	local execute = os.execute

	Cursor.commit = function(self, config)
		return self:save(config)
	end
	os.execute = function(cmd)
		if type(cmd) == 'string' and (cmd:find('gluon-reconfigure', 1, true)
				or cmd:find('/lib/gluon/upgrade/', 1, true)) then
			return 0
		end
		return execute(cmd)
	end

	local ok, err = pcall(fn)

	Cursor.commit = nil
	os.execute = execute

	if not ok then
		error(err, 0)
	end
end


local function build(renderer, scan)
	local t = renderer.i18n(PKG).translate
	local page = {groups = {}, setup = {}, intro = {}, maps = {}, links = scan.links or {}}

	local wizard, origin = load_wizard(renderer, scan.wizard)
	wizard.name = 'nf-wizard'
	page.wizard = wizard

	for _, form in ipairs(scan.forms) do
		local group = {
			key = form.name,
			title = renderer.i18n(form.pkg).translate(form.title),
			url = 'admin/' .. form.name,
		}
		local ok, maps = pcall(load_model, renderer, form.model, form.pkg)
		if ok then
			group.maps = maps
			for k, map in ipairs(maps) do
				map.name = 'nf-' .. form.name .. (#maps > 1 and ('-' .. (map.name or k)) or '')
				map.nf_title = map.title and #map.title > 0 and map.title ~= group.title
				table.insert(page.maps, map)
			end
		else
			group.maps = {}
			group.err = tostring(maps)
		end
		table.insert(page.groups, group)
	end

	-- Outdoor installation is asked twice upstream: in the wizard
	-- (gluon-config-mode-outdoor, outdoor devices only) and in the WLAN
	-- settings. On one page it appears once. The WLAN one stays - its HT mode
	-- options and the 5 GHz mesh switch depend on it. Where the wizard asked
	-- (outdoor devices), it moves up into the setup part in place of the
	-- wizard's; elsewhere it stays in the WLAN settings.
	local wizard_asks_outdoor = false
	for _, name in pairs(origin) do
		if name == 'outdoor' then
			wizard_asks_outdoor = true
		end
	end

	local outdoor_moved
	for _, group in ipairs(page.groups) do
		if group.key == 'wifi-config' and wizard_asks_outdoor then
			for _, map in ipairs(group.maps) do
				for _, section in ipairs(map.children) do
					for _, option in ipairs(section.children) do
						if option.name == 'outdoor' then
							outdoor_moved = section
						end
					end
				end
			end
		end
	end

	local groups = {}
	local function group(key, title)
		if not groups[key] then
			groups[key] = {key = key, title = title and t(title), sections = {}}
		end
		return groups[key]
	end
	for _, g in ipairs(WIZARD_GROUPS) do
		group(g.key, g.title)
	end
	group('updates')

	local order = {'node', 'geo', 'vpn', 'outdoor'}
	local kept = {}
	for i, section in ipairs(wizard.children) do
		local name = origin[section]
		local key = name and (WIZARD_GROUP[name] or name)
		if i == 1 and not name then
			table.insert(page.intro, section)
			table.insert(kept, section)
		elseif key == 'outdoor' and outdoor_moved then
			-- dropped: not parsed, not written, not shown
		else
			key = key or 'wizard'
			if not groups[key] then
				group(key)
				table.insert(order, key)
			end
			table.insert(groups[key].sections, section)
			table.insert(kept, section)
		end
	end
	wizard.children = kept

	if outdoor_moved then
		-- Still a section of the WLAN form (parsed and written with it); the
		-- form template skips it, the setup part renders it.
		outdoor_moved.nf_moved = true
		outdoor_moved.title = nil -- the group heading says it already
		table.insert(groups.outdoor.sections, outdoor_moved)
	end

	table.insert(order, 'updates')
	for _, key in ipairs(order) do
		local g = groups[key]
		if g and #g.sections > 0 then
			g.callout = (key == 'updates')
			table.insert(page.setup, g)
		end
	end

	table.insert(page.maps, wizard)
	for _, map in ipairs(page.maps) do
		if map ~= wizard then
			add_password_removal(t, map)
		end
		retemplate(map)
		snapshot(map)
		walk(map, function(node)
			if instanceof(node, classes.AbstractValue) then
				node.nf_errtext = error_text(t, node)
			end
		end)
	end

	page.text = {
		on = t('On'),
		off = t('Off'),
		client = t('Client'),
		mesh = t('Mesh'),
		noclient = t('no client'),
		nochanges = t('No changes'),
		change1 = t('1 change, not saved yet'),
		changeN = t('%d changes, not saved yet'),
		invalid1 = t('One field needs a correction. Nothing was saved.'),
		invalidN = t('%d fields need a correction. Nothing was saved.'),
		saving = t('Saving...'),
		keys0 = t('No SSH keys'),
		keys1 = t('1 SSH key'),
		keysN = t('%d SSH keys'),
		pwset = t('password set'),
		pwnone = t('no password'),
		pwnew = t('new password'),
		pwremove = t('password will be removed'),
		pwmismatch = t('The passwords do not match.'),
	}

	return page
end


local function submit(http, page)
	local state = {}
	local wizard = page.wizard

	for _, map in ipairs(page.maps) do
		map:parse(http)
	end
	if wizard.state == classes.FORM_NODATA then
		return state
	end

	for _, map in ipairs(page.maps) do
		if map.state == classes.FORM_INVALID then
			state.invalid = true
		end

		-- Password and confirmation (gluon-web-admin) are compared only in the
		-- form's write, after everything else would have been written.
		local pw1, pw2 = find_option(map, 'pw1'), find_option(map, 'pw2')
		if pw1 and pw2 and pw1.data ~= pw2.data then
			pw2.error = true
			pw2.nf_errtext = page.text.pwmismatch
			state.invalid = true
		end
	end
	if state.invalid then
		return state
	end

	deferred(function()
		for _, group in ipairs(page.groups) do
			for _, map in ipairs(group.maps) do
				if changed(map) then
					map:handle()
				end
			end
		end
	end)

	for _, group in ipairs(page.groups) do
		for _, map in ipairs(group.maps) do
			if map.errmessage then
				state.failed = true
			end
		end
	end
	if state.failed then
		return state
	end

	wizard:handle()
	state.done = (wizard.template == 'wizard/reboot')
	return state
end


function M.run(http, renderer, scan)
	local page = build(renderer, scan)
	local state = {}

	-- A "Save & restart" is already running or done: with the firmware's
	-- wizard-save-lock patch, wizard.lua then waits for it and returns an
	-- empty form with the reboot template instead of the wizard. Show the
	-- reboot page - for a GET, and above all for a second POST (double tap),
	-- which must not write the advanced forms again. Without the patch the
	-- template is never the reboot one at this point.
	if page.wizard.template == 'wizard/reboot' then
		renderer.render_layout(PKG .. '/reboot', {wizard = page.wizard}, PKG, {hidenav = true})
		return
	end

	if http:getenv('REQUEST_METHOD') == 'POST' then
		state = submit(http, page)
		if state.done then
			renderer.render_layout(PKG .. '/reboot', {wizard = page.wizard}, PKG, {hidenav = true})
			return
		end
	end

	for _, group in ipairs(page.groups) do
		for _, map in ipairs(group.maps) do
			if has_error(map) then
				group.open = true
			end
		end
	end

	renderer.render_layout(PKG .. '/page', {
		page = page,
		state = state,
		release = util.trim(util.readfile('/lib/gluon/release') or ''),
	}, PKG)
end

return M
