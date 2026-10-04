-- SPDX-License-Identifier: BSD-2-Clause
--
-- Parser for the verified body of a nodeplacer manifest (FORMAT=1).
-- Pure Lua, no side effects, testable on the host with lua5.1.
--
-- Body lines:
--   KEY=VALUE                       header (first occurrence wins)
--   # ...                           comment
--   <node_id> <method> key=value... entry
--
-- See docs/MANIFEST-FORMAT.md.

local M = {}

M.FORMAT = '1'

-- allowed keys per method; 1 = exactly once, true = repeatable
local KEYS = {
	domain = { target = 1 },
	firmware = { mirror = true, branch = 1, pubkey = true, good_signatures = 1, target = 1 },
}

local function only_keys(kv, allowed)
	for k, list in pairs(kv) do
		if not allowed[k] then
			return false
		end
		if allowed[k] == 1 and #list ~= 1 then
			return false
		end
	end
	return true
end

local function parse_kv(tokens, first)
	local kv = {}
	for i = first, #tokens do
		local k, v = tokens[i]:match('^([a-z_]+)=(.+)$')
		if not k then
			return nil
		end
		kv[k] = kv[k] or {}
		table.insert(kv[k], v)
	end
	return kv
end

local function parse_entry(tokens)
	local node_id, method = tokens[1], tokens[2]
	if not node_id or not node_id:match('^%x%x%x%x%x%x%x%x%x%x%x%x$') then
		return nil
	end
	if not method or not KEYS[method] then
		return nil
	end

	local kv = parse_kv(tokens, 3)
	if not kv or not only_keys(kv, KEYS[method]) then
		return nil
	end

	if method == 'domain' then
		if not kv.target then
			return nil
		end
		return node_id:lower(), { method = 'domain', target = kv.target[1] }
	end

	-- firmware
	if not kv.mirror then
		return nil
	end
	for _, url in ipairs(kv.mirror) do
		if not url:match('^https?://') then
			return nil
		end
	end
	if kv.pubkey then
		for _, pk in ipairs(kv.pubkey) do
			if not pk:match('^%x+$') then
				return nil
			end
		end
	end

	-- signature threshold for the target firmware; a foreign community may
	-- require a different number than this node's own firmware does
	local good_signatures
	if kv.good_signatures then
		if not kv.good_signatures[1]:match('^%d+$') then
			return nil
		end
		good_signatures = tonumber(kv.good_signatures[1])
		if good_signatures < 1 then
			return nil
		end
		if kv.pubkey and good_signatures > #kv.pubkey then
			return nil
		end
	end

	return node_id:lower(), {
		method = 'firmware',
		mirrors = kv.mirror,
		branch = kv.branch and kv.branch[1] or nil,
		pubkeys = kv.pubkey,
		good_signatures = good_signatures,
		-- optional, but strongly recommended (D-035): the site_code this
		-- node is expected to end up with. Without it, nodeplacer cannot
		-- tell "still needs to move" from "already moved, manifest entry
		-- just wasn't removed yet" and will keep trying (bounded by the
		-- attempt limiter, D-012). Left out on purpose when the exact
		-- site_code of a foreign community's target domain isn't known.
		target = kv.target and kv.target[1] or nil,
	}
end

-- Returns { header = {KEY = value}, entries = {[node_id] = entry}, errors = {line, ...} }
function M.parse(text)
	local header, entries, errors = {}, {}, {}

	for line in text:gmatch('[^\n]+') do
		-- comment and blank lines are skipped; they are hashed and signed
		-- like everything else, they just carry no instruction
		if line:match('^[A-Z_]+=') then
			local k, v = line:match('^([A-Z_]+)=(.*)$')
			if header[k] == nil then
				header[k] = v
			end
		elseif not (line:match('^#') or line:match('^%s*$')) then
			local tokens = {}
			for t in line:gmatch('%S+') do
				tokens[#tokens + 1] = t
			end
			local node_id, entry = parse_entry(tokens)
			if not node_id then
				table.insert(errors, line)
			elseif entries[node_id] == nil then
				-- duplicate node id: first line wins, silently
				entries[node_id] = entry
			end
		end
	end

	return { header = header, entries = entries, errors = errors }
end

-- Parses 'YYYY-MM-DD HH:MM:SS+HH:MM' (autoupdater DATE format) to a UTC
-- epoch without relying on the local timezone. Mirrors parse_rfc3339()
-- of the autoupdater.
function M.parse_date(str)
	local year, month, day, hour, min, sec, tzs, tzh, tzm =
		str:match('^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d):(%d%d)([%+%-])(%d%d):(%d%d)$')
	if not year then
		return nil
	end
	year, month, day = tonumber(year), tonumber(month), tonumber(day)
	hour, min, sec = tonumber(hour), tonumber(min), tonumber(sec)
	tzh, tzm = tonumber(tzh), tonumber(tzm)

	if month < 1 or month > 12 or day < 1 or day > 31 or hour > 23 or min > 59 or sec > 60 then
		return nil
	end

	local a = math.floor((14 - month) / 12)
	local y = year - a
	local m = month + 12 * a - 3
	local days = day + math.floor((153 * m + 2) / 5) + 365 * y
		+ math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400) - 719469

	local tz = 3600 * tzh + 60 * tzm
	if tzs == '-' then
		tz = -tz
	end

	return 86400 * days + hour * 3600 + min * 60 + sec - tz
end

-- Key under which attempts for an entry are counted
function M.target_key(entry)
	if entry.method == 'domain' then
		return 'domain:' .. entry.target
	end
	return 'firmware:' .. (entry.branch or '-') .. ':' .. entry.mirrors[1]
end

return M
