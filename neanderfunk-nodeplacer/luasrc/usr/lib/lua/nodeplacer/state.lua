-- SPDX-License-Identifier: BSD-2-Clause
--
-- Attempt counter and replay guard, kept in RAM only (/tmp), see D-012.
-- Plain key=value file so that neither jsonc nor uci is needed and the
-- module can be tested on the host.
--
--   target=<key>            what the attempts refer to
--   attempts=<n>
--   first_attempt=<uptime>  seconds of uptime at the first attempt
--   last_date=<epoch>       DATE of the last manifest we acted on

local M = {}

M.FILE = '/tmp/nodeplacer.state'

function M.load(path)
	path = path or M.FILE
	local st = { attempts = 0, first_attempt = 0, last_date = 0 }
	local f = io.open(path, 'r')
	if not f then
		return st
	end
	for line in f:lines() do
		local k, v = line:match('^([%w_]+)=(.*)$')
		if k == 'target' then
			st.target = v
		elseif k == 'attempts' or k == 'first_attempt' or k == 'last_date' then
			st[k] = tonumber(v) or 0
		end
	end
	f:close()
	return st
end

function M.save(st, path)
	path = path or M.FILE
	local f = io.open(path, 'w')
	if not f then
		return false
	end
	f:write('target=', st.target or '', '\n')
	f:write('attempts=', st.attempts, '\n')
	f:write('first_attempt=', st.first_attempt, '\n')
	f:write('last_date=', st.last_date, '\n')
	f:close()
	return true
end

-- A manifest is applied only if it is not older than the last one applied.
-- Equal is allowed: a retry after a failed attempt uses the same manifest.
function M.newer_or_equal(st, date)
	return date >= (st.last_date or 0)
end

-- Number of attempts already made for 'target' inside the rolling window.
-- A different target or an expired window starts over.
function M.attempts_in_window(st, target, uptime, window)
	if st.target ~= target then
		return 0
	end
	if uptime - st.first_attempt > window then
		return 0
	end
	return st.attempts
end

function M.record_attempt(st, target, date, uptime, window)
	window = window or (7 * 86400)
	if st.target ~= target or uptime - st.first_attempt > window then
		st.target = target
		st.attempts = 0
		st.first_attempt = uptime
	end
	st.attempts = st.attempts + 1
	st.last_date = date
end

return M
