require "table_util"
local futil = require "futil"
local skynet = require "skynet"
require "skynet.manager"
local syslog = require "syslog"
local json = require "cjson"
local command = {}
local assert = assert
local tonumber = tonumber
local math = math

-- local room_list_table = {}
local room_code_table = {}

local room_pool = {}


local ks_enter_code = "ENTER_CODE"


local function record_build_room_log(room_info)
    local param = {}
    param.room_id = room_info.room_name
    param.node_name = room_info.node_name or "127.0.0.1"
    param.create_time = os.date("%Y-%m-%d %H:%M:%S", os.time())
    param.owner = room_info.master_id
    param.game_type = room_info.game_type or 1
    param.player_count = room_info.table_config.player_count
    param.game_count = room_info.table_config.game_count
    param.type = room_info.type or 1
    -- local table_config = json.decode(room_info.table_config.data)
    param.config = room_info.table_config.data
    -- table.printT(param)
    skynet.call("MYSQL", "lua", "log", "db_game_log", "build_room_log", param)
end

function command.ON_BUILD_ROOM(args) 

   -- table.printT(args)
	if type(args) ~= "table" then
		syslog.warning("args must be a table")
		return {code = -1} --參數錯誤
	end
	
	local ran = math.random(100000,999999)
    local enter_code = string.format("%06d",ran)
    while(true) do
		local r = skynet.call(".DBREDIS", "lua", "sadd", ks_enter_code ,enter_code)
		if r and tonumber(r) == 1 then
			break
		end
		ran = math.random(100000,999999)
		enter_code = string.format("%06d",ran)
    end
    -- local enter_code = 234567
    local room_name = ".ROOM_"..enter_code
	local room_address
	if #room_pool == 0 then
		room_address = skynet.newservice("room_service")
	else
		room_address = table.remove (room_pool, 1)
	end
    

    if room_address then
        --初始化房间
        local tmp = {
                    enter_code = enter_code, 
                    table_config = args, 
                    address = room_address, 
                    master_id = args.uid, 
                    create_time = os.time(), 
                    room_name = room_name
                }
        skynet.call(room_address, "lua", "init", tmp)
        local room_info = {}
        room_info.address = room_address
        room_info.room_name = room_name
        room_info.master_id = args.uid
        room_info.enter_code = enter_code
        room_info.create_time = os.time()
        room_info.users = {}
        -- room_list_table[room_name] = room_info
        room_code_table[enter_code] = room_info

        record_build_room_log(tmp)

    end
	return {code = 0, enter_code = tonumber(enter_code)}
end

--[[
    进入房间
    args{uid,enter_code}
]]
function command.GET_ROOM_SERVICE_ID(args)
	if not args or not args.enter_code then
		return false, {code = 20005}
	end

    local room_info = room_code_table[args.enter_code]
    if not room_info then
        return false, {code = 20005}
    end
    return room_info
end

function command.GET_ROOM_INFO_BY_ROOM_NAME(enter_code)
    return room_code_table[enter_code]
end

function command.ON_CLOSE_ROOM(address, args)
    -- local room_info = room_list_table[args.room_name]
    -- room_list_table[args.room_name]       = nil
    room_code_table[args.enter_code] = nil
    skynet.call(address, "lua", "close", args)
    syslog.debugf ("room service %d recycled", address)
	table.insert (room_pool, address)
    
end


local function init()
	local n = 10 
	for i = 1, n do
		table.insert (room_pool, skynet.newservice ("room_service"))
	end	
end


local function update_datacenter(key, value)
    -- datacenter.set("on_player", key, value)
end


function command.UPDATE_PLAYER_STATUS(role_id , value)
    -- skynet.fork(update_datacenter, role_id, value)
end

function command.UPDATE_ORDER_STATUS(enter_code, status)
    -- if not room_code_table[enter_code]  then
    --     return
    -- end
    -- skynet.call("CENTER_MGR", "lua","update_order_status", room_code_table[enter_code].order, status, enter_code)
end

skynet.start(function()
	init()
	skynet.dispatch("lua", function(session, address, cmd, ...)
		local f = command[string.upper(cmd)]
		if f then
            if session ~= 0 then
                skynet.ret(skynet.pack(f(...)))
            else
                f(...)
            end
		else
			error(string.format("Unknown command %s", tostring(cmd)))
		end
	end)
	skynet.register ".BUILD_ROOMS_SERVICE"
end)



