require "table_util"
local futil = require "futil"
local skynet = require "skynet"
local netpack = require "netpack"
local socket = require "socket"
local sproto = require "sproto"
local datacenter = require "datacenter"
local proto = require "gameserver.proto"

local syslog = require "syslog"

local room_handler = require "agent.room_handler" -- room handler
local game_handler = require "agent.game_handler" -- game handler

local harbor_id = assert(tonumber(skynet.getenv("harbor")))

local host
local send_request

local agent_id

local CMD = {}
local REQUEST = {}
local client_fd

local role_id

local server_id

local gamed = tonumber (...)

local user

local function send_msg (fd, msg)
	local package = string.pack (">s2", msg)
	socket.write (fd, package)
end


host = sproto.new(proto.c2s):host "package"
send_request = host:attach(sproto.new(proto.s2c))

local function request(name, args, response)
	local f = assert(REQUEST[name])
	local r = f(args)
	if response then
		return response(r)
	end
end

local function send_package(user_fd,pack)
	local package = string.pack (">s2", pack)
	socket.write (user_fd, package)
end


local user_fd
local session = {}
local session_id = 0
local function server_request (name, args)
	session_id = session_id + 1
	local str = send_request (name, args, session_id)
	send_package (user_fd,str)
	if not session then
		session = {}
	end
 	session[session_id] = { name = name, args = args }
end

local function kick_self (tag)
	if(user and user.send_request and not tag) then
		user.send_request("kick_game")
	end
	skynet.call (gamed, "lua", "kick", skynet.self (), user_fd)
end




local last_heartbeat_time
local HEARTBEAT_TIME_MAX =  100 * 30
local recyclied_fd = nil




--local REQUEST
local function handle_request (name, args, response)
	local f = REQUEST[name]
	if f then
		local ok, ret = pcall(f, args)
		if not ok then
			syslog.warningf ("handle message(%s) failed : %s", name, ret) 
			kick_self ()
		else
			last_heartbeat_time = skynet.now ()
			if response and ret and user_fd then
				send_package (user_fd,response (ret))
			end
		end
	else
		syslog.warningf ("unhandled message : %s", name)
		kick_self ()
	end
end


local RESPONSE
local function handle_response (id, args)
	local s = session[id]
	if not s then
		syslog.warningf ("session %d not found", id)
		kick_self ()
		return
	end

	local f = RESPONSE[s.name]
	if not f then
		syslog.warningf ("unhandled response : %s", s.name)
		kick_self ()
		return
	end

	local ok, ret = pcall(f, s.args, args)
	if not ok then
		syslog.warningf ("handle response(%d-%s) failed : %s", id, s.name, ret) 
		kick_self ()
	end
end

local ks_user = "USER_%d"
local function write_user_to_redis(info)
	local key = string.format(ks_user, info.account)
	syslog.debugf ("write_user_to_redis :%d", info.account)
	local param = {}
	param.room_name = info.room_name or 0
	param.table_id = info.table_id or 0
	param.chair_id = info.chair_id or 0
	param.private_code = info.private_code or 0
	skynet.call(".DBREDIS", "lua", "hmset", key, {"room_name", param.room_name, "table_id", param.table_id, "chair_id" , param.chair_id, "private_code", param.private_code})
	skynet.call(".DBREDIS", "lua", "expire", key, 100 * 3600 * 24)
end



local function load_user_from_redis()
	local key = string.format(ks_user, user.account)
	syslog.debugf ("load_user_from_redis :%d", user.account)
	local r = skynet.call(".DBREDIS", "lua", "hmget", key, {"room_name","table_id","chair_id","private_code"})
	--table.printR(r)
	if r and r[1] then
		if r[1] ~= 0 and r[3] ~= 0 then
			--删除redis玩家房间信息
			--skynet.call(".DBREDIS", "lua", "DEL", key)
			local args = {}
			args.uid = user.account
			args.address = skynet.self()
			--TODO:先检查房间服务是否存在
			local enter_code = r[1]
			if not enter_code then
				return 
			end
			local ret = skynet.call(".BUILD_ROOMS_SERVICE", "lua", "get_room_info_by_room_name", enter_code, assert(tonumber(r[4])))
			if not ret then
				return
			end
			--syslog.debug ("load_user_from_redis 111:%d", user.account)
			--TODO:推送桌子信息给玩家 如果成功会写房间信息到agent
			if skynet.call(ret.address, "lua", "RECONNECT", args) then
				user.room_address = ret.address
				user.room_name = ret.room_name
				user.table_id = r[2]
				user.chair_id = r[3]
				user.private_code = r[4]
				--syslog.debug ("load_user_from_redis 22222:%d", user.account)
			end
		end
	end
	-- table.printT(r)
end


skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = function (msg, sz)
		return host:dispatch(msg, sz)
	end,
	dispatch = function (_, _, type, ...)
		if type == "REQUEST" then
			handle_request (...)
		elseif type == "RESPONSE" then
			handle_response (...)		
		else
			--assert(type == "RESPONSE")
			--error "This example doesn't support request client"
			syslog.warningf ("invalid message type : %s", type) 
			kick_self ()
		end
	end
}


local S1  
local thread_id

local function heartbeat_check ()
	thread_id = coroutine.running()
	while true do
		if HEARTBEAT_TIME_MAX <= 0 or not user_fd then
			break 
		end
		local t = last_heartbeat_time + HEARTBEAT_TIME_MAX - skynet.now ()

		if t <= 0 then
			syslog.warning ("heatbeat check failed")
			kick_self (1)
			break
		else
			skynet.sleep(t)
		end
	end
end

function CMD.open (fd, account)
	local name = string.format ("agent:%d", account)
	syslog.debug("agent opened")
	user = { 
		fd = fd, 
		account = account,
		REQUEST = {},
		RESPONSE = {},
		CMD = CMD,
		send_request = server_request,
	}
	
	user_fd = user.fd
	REQUEST = user.REQUEST
	RESPONSE = user.RESPONSE
	
	local world = skynet.uniqueservice ("world")
	skynet.call (world, "lua", "character_enter", account)

	--datacenter.set("on_player", account, harbor_id)
	skynet.send(".BUILD_ROOMS_SERVICE", "lua", "update_player_status", account, harbor_id)
	load_user_from_redis()

	
	room_handler:register (user)
	game_handler:register (user)
	
	session = nil
	session_id = 0
	last_heartbeat_time = skynet.now ()
	
	skynet.fork(heartbeat_check)

	

end

function CMD.kick ()
	--error ()
	if user and user.room_address then
		write_user_to_redis(user)
	end
	if user and user.world then
		skynet.call (user.world, "lua", "character_leave",user.character)
		user.world = nil
	end
	syslog.debug ("agent kicked")
	kick_self()

end

function CMD.send (cmd, args)
	if(user and user.send_request ) then
		--syslog.debug ("agent send :%s,%d ", cmd, user.account)
		user.send_request(cmd,args)
	end	
end

function CMD.world_enter (world,channel,character)
	syslog.debug ("agent world_enter")
	
	role_id = character
	user.character = character
	user.world = world
	
end
function CMD.kick_room (args)
	if user then
		if user.room_address and user.room_address ~= args.address then
			syslog.warningf ("user.room_address :%d ~= args.room_service_id : %d ", user.room_address , args.address)
		end
		if not args.normal then
			user.send_request("room_post_room_dismiss",{code = 0, list = args.list})
		end
		session = nil
		session_id = 0
		user.room_address = nil
		user.room_name = nil
		user.table_id = nil
		user.chair_id = nil
		user.private_code = nil
	end
end

function CMD.close ()
	syslog.debug ("agent closed")

	local account
	
	if user then
		account = user.account
		local address = user.room_address
		local world = user.world
		room_handler:unregister (user)
		game_handler:unregister (user)
		local info = {}
		if address then
			info = {account = account, room_name = user.room_name, table_id = user.table_id, chair_id = user.chair_id, private_code = user.private_code}
		end
		user = nil
		if address then
			write_user_to_redis(info)
			skynet.call(address, "lua", "disconnection", account, skynet.self())
		else -- todo xuhui
			syslog.debugf ("agent close and  cross center set on_player : %d nil",account)
			skynet.send(".BUILD_ROOMS_SERVICE", "lua", "update_player_status", account, nil)
			--datacenter.set("on_player", account, nil)
		end
		
		if world then
			skynet.call (world, "lua", "character_leave", account)		
		end
		user_fd = nil
		REQUEST = nil
		RESPONSE = nil
	end
	session = nil
	session_id = 0

	if thread_id then
		skynet.wakeup(thread_id)
		thread_id = nil
	end

	skynet.send(skynet.self(), "debug", "GC")
	if account then
		skynet.call (gamed, "lua", "close", skynet.self (), account)
	end


end

skynet.start(function()
	skynet.dispatch("lua", function(_session,_, command, ...)
		local f = CMD[command]
		
		if not f then
			syslog.warningf ("unhandled message(%s)", command) 
			if _session ~= 0  then
				return skynet.ret ()
			end
		end

		local ok, ret = pcall (f, ...)
		if not ok then
			syslog.warningf ("handle message(%s) failed : %s", command, ret) 
			kick_self ()
			if _session ~= 0  then
				return skynet.ret ()
			end
		end
		if _session ~= 0 then
			skynet.retpack (ret)
		end
	end)
end)
