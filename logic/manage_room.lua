require "table_util"
local futil = require "futil"
local skynet = require "skynet"
require "skynet.manager"
local syslog = require "syslog"
local json = require "cjson"
local harbor = require "skynet.harbor"
local datacenter = require "datacenter"
local game_config = require "config.game"


local command = {}
local assert = assert
local tonumber = tonumber
local math = math

local room_code_table = {}
local room_code_table_batch = {}

local room_pool = {}

local world = assert(tonumber (...))



local ks_enter_code = "ENTER_CODE"
local harbor_id = assert(tonumber(skynet.getenv("harbor")))
local out_ip = assert(skynet.getenv("out_address"))


local function monitor_master()
	harbor.linkmaster()
	syslog.notice("master is down")
	--skynet.exit()
end


local function record_build_room_log(room_info)
    local param = {}
    param.room_id = room_info.room_name
    param.node_name = out_ip or "127.0.0.1"
    param.create_time = os.time()
    param.owner = room_info.master_id
    param.game_type = room_info.game_id or 1
    param.player_count = room_info.table_config.player_count
    param.game_count = room_info.table_config.game_count
    param.type = room_info.type or 1
    param.club_id = room_info.clubId or 0
    -- local table_config = json.decode(room_info.table_config.data)
    param.config = room_info.table_config.data
    -- table.printT(param)
    skynet.send(".MYSQL", "lua", "log", "db_game_log", "build_room_log", param)
end


function command.ON_BUILD_ROOM(args) 
	if type(args) ~= "table" then
		syslog.warningf("args must be a table")
		return {code = -1} --參數錯誤
	end
	syslog.debug("ON_BUILD_ROOM")
    table.printR(args)
    local enter_code = args.enter_code
    if enter_code == nil then
        local ran = math.random(100000,999999)
        enter_code = string.format("%06d",ran)
        while(room_code_table[enter_code] ~= nil) do
            ran = math.random(100000,999999)
            enter_code = string.format("%06d",ran)
        end
    end

    local room_name = enter_code
	local room_address
	if #room_pool == 0 then
		room_address = skynet.newservice("room_service")
	else
		room_address = table.remove (room_pool, 1)
	end
    local private_code = (math.random(1000) + os.time()) % 10000
    if room_address then
        --初始化房间
        local tmp = {
                    enter_code = enter_code, 
                    table_config = args, 
                    address = room_address, 
                    master_id = args.uid, 
                    create_time = os.time(), 
                    room_name = room_name,
                    order     = args.orderCode,
                    game_id   = args.gameId ,
                    clubId    = args.clubId ,
                }
        skynet.call(room_address, "lua", "init", tmp)
        local room_info = {}
        room_info.address = room_address
        room_info.room_name = room_name
        room_info.master_id = args.uid
        room_info.enter_code = enter_code
        room_info.create_time = os.time()
        room_info.users = {}
        room_info.order = args.orderCode
        room_info.private_code = private_code
        room_code_table[enter_code] = room_info
        record_build_room_log(tmp)
    end
	return {code = 0, enter_code = enter_code, address = room_address ,private_code = private_code}
end




function command.ON_BUILD_ROOM_BATCH(args) 
    if type(args) ~= "table" then
        syslog.warningf("args must be a table")
        return {code = -1} --參數錯誤
    end
    syslog.debug("ON_BUILD_ROOM_BATCH")
    --table.printR(args)
    local enter_code_set = args.enter_code_set
    if enter_code_set == nil or not args.uid then
        assert(nil)
    end
    local  private_code_set = {}
    local  room_address_set = {}
    for i = 1 , #enter_code_set do
        if enter_code_set[i] and args.orderCode[i] then
            local room_name = enter_code_set[i]
            local enter_code = room_name
            local room_address
            if #room_pool == 0 then
                room_address = skynet.newservice("room_service")
            else
                room_address = table.remove (room_pool, 1)
            end
            local private_code = (math.random(1000) + os.time()) % 10000
            if room_address then
                --初始化房间
                local tmp = {
                            enter_code = enter_code, 
                            table_config = args, 
                            address = room_address, 
                            master_id = args.uid, 
                            create_time = os.time(), 
                            room_name = room_name,
                            order     = args.orderCode[i],
                            game_id   = args.gameId ,
                            batch_room = true,
                            clubId    = args.clubId ,
                        }
                skynet.call(room_address, "lua", "init", tmp)
                local room_info = {}
                room_info.address = room_address
                room_info.room_name = room_name
                room_info.master_id = args.uid
                room_info.enter_code = enter_code
                room_info.create_time = os.time()
                room_info.users = {}
                room_info.order = args.orderCode[i]
                room_info.private_code = private_code
                room_info.batch_room = true
                room_code_table[enter_code] = room_info
                local uid_batch = room_code_table_batch[args.uid]
                if uid_batch then
                    uid_batch[#uid_batch + 1] =  room_name
                else
                    room_code_table_batch[args.uid] =  {room_name}
                end
                record_build_room_log(tmp)
                private_code_set[#private_code_set + 1] = private_code
                room_address_set[#room_address_set + 1] = room_address
            end
        end

    end
    return {code = 0, enter_code_set = enter_code_set, room_address_set = room_address_set ,private_code_set = private_code_set}
end


function command.GET_ROOM_INFO(args)

    local uid  = assert(args.uid)
    local page = assert(args.page)


    local batch_room = room_code_table_batch[uid]
    local list = {}
    if not batch_room or not page then
        return list
    end
    if page <  1 then
        return list 
    end
    if 1 + (page-1)*10 > #batch_room then
        return list
    end
    local max = page * 10 > #batch_room and #batch_room or page*10
    local min = 1 + (page-1)*10
    for i = min, max do
         local enter_code = batch_room[i]
         if enter_code then
             local room  = room_code_table[enter_code]
             if room and room.address then
                local sign,info = skynet.call(room.address, "lua","room_info_room", uid)
                if sign then
                    info.room_id = enter_code
                    list[#list + 1] = info
                end
            end
        end
    end
    return list, #batch_room
end

function command.DISMISS_BATCH_ROOM(args)
    local uid = assert(args.uid)
    local handle_map = assert(args.handle)
    local batch_room = room_code_table_batch[uid]
    if not batch_room then
        return {code = 20017}
    end
    for i = 1 , #handle_map do
        local enter_code = tostring(handle_map[i])
        if enter_code then
            local room  = room_code_table[enter_code]
             if room and room.address then
                skynet.send(room.address, "lua", "blackhole")
            end
        end
    end
    return {code = 0}
end




function command.ON_CLOSE_ROOM(address, args)
    local room = room_code_table[args.enter_code]
    local point_wms 
    if room and room.batch_room == true then
        point_wms = args.point_wms
        local owner = room.master_id
        if room_code_table_batch[owner] then
            local uid_batch = room_code_table_batch[owner]
            local pre_value = {}
            for k,v in pairs(uid_batch) do
                if v ~= args.enter_code then
                    pre_value[#pre_value + 1 ] = v
                end
            end
            room_code_table_batch[owner] = pre_value
        end
    end

    room_code_table[args.enter_code] = nil
    skynet.call(address, "lua", "close", args)
    skynet.call("CENTER_MGR", "lua","update_room_servers", harbor_id, args.enter_code, args.sclub, point_wms)
    syslog.debugf ("room service %d recycled", address)
	table.insert (room_pool, address)
    
end
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

function command.GET_ROOM_INFO_BY_ROOM_NAME(enter_code, private_code)
    if enter_code and private_code then
        local room  = room_code_table[enter_code]
        if room and room.private_code == private_code then
            return room_code_table[enter_code] 
        end
    end
    return nil
end

local function init()
	local n = game_config.room_pool or 1 
	for i = 1, n do
		table.insert (room_pool, skynet.newservice ("room_service"))
	end	
	skynet.call("CENTER_MGR", "lua","register_component", harbor_id, skynet.self(), out_ip, 0, world)
	syslog.noticef("harbor register center cross is  ok : %d",harbor_id)
end

local function update_datacenter(key, value)
    datacenter.set("on_player", key, value)
end


function command.UPDATE_PLAYER_STATUS(role_id , value)
    skynet.fork(update_datacenter, role_id, value)
end



function command.UPDATE_ORDER_STATUS(enter_code, status)
	if not room_code_table[enter_code]  then
		return
	end
	skynet.call("CENTER_MGR", "lua","update_order_status", room_code_table[enter_code].order, status, enter_code)
end

function command.SEND_RED_BAG(args)
    args.appId = 1
    args.appCode = "klmj"
    if not room_code_table[args.enter_code]  then
        syslog.err("没有订单"..args.enter_code)
		return
	end
    local room_info = room_code_table[args.enter_code]
    args.roomId = room_info.room_name
    args.orderCode = room_info.order
    skynet.send("CENTER_MGR", "lua", "send_red_bag", args)
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
	skynet.fork(monitor_master)
end)



