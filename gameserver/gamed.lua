local skynet = require "skynet"

local gameserver = require "gameserver.gameserver"
local syslog = require "syslog"

local logind = tonumber (...)

local gamed = {}

local pending_agent = {}
local pool = {}

local online_account = {}

local online_person = 0

function gamed.open (config)
	syslog.notice ("gamed opened")

	local self = skynet.self ()
	local n = config.agent_pool or 1
	for i = 1, n do
		table.insert (pool, skynet.newservice ("agent", self))
	end

	--skynet.uniqueservice ("gdd")
    local world = skynet.uniqueservice ("world")

	skynet.call (world, "lua", "init_chat", "public")

	skynet.uniqueservice("dbRedis")
	skynet.uniqueservice("mysqlLog")

	skynet.uniqueservice("manage_room", world)
	--skynet.uniqueservice("build_rooms_service")


	
	
end

function gamed.command_handler (cmd, ...)
	local CMD = {}

	function CMD.close (agent, account)
		syslog.debugf ("agent %d recycled", agent)

		online_account[account] = nil
		online_person = online_person -1
		table.insert (pool, agent)
	end

	function CMD.kick (agent, fd)
		gameserver.kick (fd)
	end
	function CMD.online ()
		return online_person
	end
	

	local f = assert (CMD[cmd])
	return f (...)
end
--第三方渠道认证
function gamed.auth_handler (session, token)
	--return skynet.call (logind, "lua", "verify", session, token)	
	return session
end

function gamed.login_handler (fd, account)
	local agent

	agent = online_account[account]

	if agent then
		syslog.warningf ("multiple login detected for account %d", account)
		skynet.call (agent, "lua", "kick", account)
	end

	if #pool == 0 then
		agent = skynet.newservice ("agent", skynet.self ())
		syslog.noticef ("pool is empty, new agent(%d) created", agent)
	else
		agent = table.remove (pool, 1)
		syslog.debugf ("agent(%d) assigned, %d remain in pool", agent, #pool)
	end

	online_account[account] = agent

	online_person = online_person +1
	
	skynet.call (agent, "lua", "open", fd, account)
	gameserver.forward (fd, agent)
	return agent
end

gameserver.start (gamed)



