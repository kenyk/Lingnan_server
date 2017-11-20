require "table_util"
local skynet = require "skynet"
local syslog = require "syslog"
local datacenter = require "datacenter"
local command = {}
local assert = assert
local tonumber = tonumber
local json = require "json"
local room_name 
local enter_code
local batch_room

local table_creator = require "table_frame"
local game_creator = require "game_sink"
local changsha_table_creator = require "changsha.table_frame"
local changsha_game_creator = require "changsha.game_sink"
local chenzhou_table_creator = require "chenzhou.table_frame"
local chenzhou_game_creator = require "chenzhou.game_sink"
local ningxiang_table_creator = require "ningxiang.table_frame"
local ningxiang_game_creator = require "ningxiang.game_sink"
local changde_game_creator = require "changde.game_sink"
local changde_table_creator = require "changde.table_frame"
local tuidaohu_game_creator = require "tuidaohu.game_sink"
local tuidaohu_table_creator = require "tuidaohu.table_frame"
local zhaoqing_game_creator = require "zhaoqing.game_sink"
local zhaoqing_table_creator = require "zhaoqing.table_frame"
local yunfu_game_creator = require "yunfu.game_sink"
local yunfu_table_creator = require "yunfu.table_frame"

local table_sink = {}
local room_player = {}
local room_num = 0
local table_interface = {}
local room_recycled  = false 

local expend_time = nil

local thread_id 

local player_info = {}

local function get_chairid_by_uid(uid)
	if table_interface then
		return table_interface.get_chairid_by_uid(uid)
	else
		return 0
	end
end
-- local 
-- local game = require "game.game"

function command.ROOM_INFO_ROOM(uid) 
	if not table_sink or not table_sink.table_config or table_sink.table_config.master_id ~= uid then
		return false,{code = 20016}
	end
	local players = {}
	for uid,v in pairs(room_player) do
		local info = player_info[uid]
		if info then
			players[#players  + 1] = {uid = uid, nickname = info.nickname, ip = info.ip, image_url = info.image_url , gender = info.gender}
		end
	end
	local progress = 0 
	local total = table_sink.table_config.game_count
	local player_num = table_sink.table_config.player_count
	local data  = json.encode(game_sink.game_config)

	if table_sink.table_config.player_count == room_num then
		progress =  table_sink.table_config.game_index -- string.format("%d:%d",table_sink.table_config.game_index ,table_config.game_count)
	end

	progress = string.format("%d:%d",progress,total)


	return true, {progress = progress , players = players ,player_num = player_num, data = data}
end
--[[ 
	room
--]]
function command.ROOM_ENTER_ROOM(args) 
	local uid = args.uid
    if not batch_room and room_num == 0 and uid ~= table_sink.table_config.master_id then
        return false, {code = 20015}
    end
	if room_player[uid] then
		return false, {code = 20001}
	end
	if table_sink and table_sink.table_config.player_count <= room_num then
		return false, {code = 20008}
	end
	-- game_sink:post_game_reconnect(1)
	if player_info[uid] then
		args.nickname = player_info[uid].nickname 
		args.ip = player_info[uid].ip 
		args.image_url = player_info[uid].image_url
		args.gender = player_info[uid].gender
	end


	skynet.fork(function ()
					if table_sink then
						--进入桌子
						table_sink:enter_table(room_player[uid])
						--坐下
						table_sink:sit_down(uid)
						--准备
						table_sink:get_ready(uid)
					end
		-- body
	end)

	room_player[uid] = args
	room_num = room_num + 1
	--if table_sink.table_config.player_count <= room_num then
	--	datacenter.set("room_manager", enter_code,nil)
	-- end
	return true, {code = 0}
end

function command.ROOM_EXIT_ROOM(uid) 
	if not room_player[uid] then
		return false, {code = 20006}
	end

	--先退出桌子再退出房间
	local issucc , code =  table_sink:exit_table(uid)
	if not issucc then
        return false, {code = code}
    end
	room_player[uid] = nil
	room_num = room_num - 1
	return true, {code = 0}
end

function command.ROOM_ENTER_TABLE(uid) 
	local player = room_player[uid]
	if not player then
		return false, {code = 20006}
	end
	return table_sink:enter_table(player)
end

function command.ROOM_EXIT_TABLE(uid) 
	local player = room_player[uid]
	if not player then
		return false, {code = 20006}
	end
	return table_sink:exit_table(uid)
end

function command.ROOM_SIT_DOWN(uid) 
	local player = room_player[uid]
	if not player then
		return false, {code = 20006}
	end
	local r, res = table_sink:sit_down(uid)
	-- if r then
	-- 	game_sink:add_player(uid)
	-- end
	--table.printT(res)
	return r,res
end

function command.ROOM_STAND_UP(uid) 
	local player = room_player[uid]
	if not player then
		return false, {code = 20006}
	end
	local r, res =  table_sink:stand_up(uid)
	if r then
		game_sink:exit_player(uid)
	end
	return res
end


function command.ROOM_GET_TABLE_SCENE(uid) 
	local player = room_player[uid]
	if not player then
		return false, {code = 20006}
	end
	return table_sink:get_table_scene()
end

function command.ROOM_GET_READY(uid) 
	local player = room_player[uid]
	if not player then
		return false, {code = 20006}
	end
	return table_sink:get_ready(uid)
end

function command.ROOM_VOTE_DISMISS_ROOM(uid,args) 
	local player = room_player[uid]
	if not player then
		return false, {code = 20006}
	end
	return table_sink:vote_dismiss_room(uid,args)
end

--[[ 
--]]
function command.GAME_OUT_CARD(uid,args) 
	local chairid = get_chairid_by_uid(uid)
	if chairid == 0 then
		return false, {code = -1}
	end
	if expend_time then
		expend_time = expend_time + 1
	end
	return game_sink:out_card(chairid, args.card)
end

function command.GAME_PENG_CARD(uid,args) 
	local chairid = get_chairid_by_uid(uid)
	if chairid == 0 then
		return false, {code = -1}
	end
	if expend_time then
		expend_time = expend_time + 1
	end
	return game_sink:peng_card(chairid,args.card)
end

function command.GAME_GANG_CARD(uid,args) 
	local chairid = get_chairid_by_uid(uid)
	if chairid == 0 then
		return false, {code = -1}
	end

	if expend_time then
		expend_time = expend_time + 1
	end
	return game_sink:gang_card(chairid, args.card)
end

function command.GAME_BU_CARD(uid, args)
	local chairid = get_chairid_by_uid(uid)
	if chairid == 0 then
		return false, {code = -1}
	end
	if expend_time then
		expend_time = expend_time + 1
	end
	return game_sink:bu_card(chairid, args.card)
end

function command.GAME_CHI_CARD(uid,args) 
	local chairid = get_chairid_by_uid(uid)
	if chairid == 0 then
		return false, {code = -1}
	end
	if expend_time then
		expend_time = expend_time + 1
	end
	return game_sink:chi_card(chairid, args)
end

function command.GAME_HU_CARD(uid,args) 
	local chairid = get_chairid_by_uid(uid)
	if chairid == 0 then
		return false, {code = -1}
	end
	if expend_time then
		expend_time = expend_time + 1
	end
    if args then
        return game_sink:hu_card(chairid, args.card)
    else
        return game_sink:hu_card(chairid)
    end
	
end

function command.GAME_CANCEL_ACTION(uid,args) 
	local chairid = get_chairid_by_uid(uid)
	if chairid == 0 then
		return false, {code = -1}
	end
	if expend_time then
		expend_time = expend_time + 1
	end
	return game_sink:cancel_action(chairid)
end

function command.GAME_RECONNECT_GAMEINFO(uid)
	local chairid = get_chairid_by_uid(uid)
	if chairid == 0 then
		return false, {code = -1}
	end
	return game_sink:post_game_reconnect(chairid)
end  

function command.GAME_FIRST_HU(uid)
    local chairid = get_chairid_by_uid(uid)
	if chairid == 0 then
		return false, {code = -1}
	end
    return game_sink:first_hu_handler(chairid)
end

function command.REGISTER_PLAYER(uid, args)
	player_info[uid] = args
	return 
end

function command.BLACKHOLE() -- for batch 
	if not enter_code or not room_name then
		return 
	end
	local result, sclub ,point_wms
    if table_sink and table_sink.table_config then
    	if table_sink.table_config.game_index == 1 then
    		skynet.send(".BUILD_ROOMS_SERVICE", "lua", "update_order_status", enter_code, "giveup")
    	else
    		result, sclub ,point_wms= self.game_sink:get_all_balance_result()
    	end    	
    end

	skynet.send(".BUILD_ROOMS_SERVICE", "lua", "on_close_room",skynet.self(),{room_name = room_name, list = {}, enter_code = enter_code, sclub = sclub, point_wms = point_wms})

end


local revert_time = 100 * 3600 * 24 - 100 * 60
local function checkSleepFromNow()
	 thread_id = coroutine.running()
	 syslog.debugf ("room_server begin closed expend_time :%d",revert_time)
	 skynet.sleep(revert_time)
	 if room_recycled then
	 	syslog.debug ("room_server closed caused by 24h  timeout")
		skynet.send(".BUILD_ROOMS_SERVICE", "lua", "on_close_room",skynet.self(),{room_name = room_name, list = {}, enter_code = enter_code})
	 else
	 	syslog.debug ("room_server closed cancel by room_recycled")
	 end
end

function command.INIT(args)
	room_num = 0
	room_recycled = true
	room_name = args.room_name
	player_info = {}
	enter_code = args.enter_code
	batch_room = args.batch_room

	syslog.debugf ("command.INIT game_id, enter_code :%d ,%d ",args.game_id, tonumber(enter_code))
	math.randomseed(tonumber(enter_code))
    --2长沙 1转转 7郴州 8红中（用转转的game_sink） 10宁乡麻将 28常德麻将
    --100岭南麻将 101云浮麻将 102肇庆麻将
	if args.game_id == 2 then
		table_sink = changsha_table_creator.new(args)
		table_interface = table_sink:get_interface()
		game_sink = changsha_game_creator.new(table_interface)
		table_sink:set_game_sink(game_sink)		
    elseif args.game_id == 7 then
        table_sink = chenzhou_table_creator.new(args)
		table_interface = table_sink:get_interface()
		game_sink = chenzhou_game_creator.new(table_interface)
		table_sink:set_game_sink(game_sink)
    elseif args.game_id == 10 then
        table_sink = ningxiang_table_creator.new(args)
        table_interface = table_sink:get_interface()
        game_sink = ningxiang_game_creator.new(table_interface)
        table_sink:set_game_sink(game_sink)
    elseif args.game_id == 28 then
        table_sink = changde_table_creator.new(args)
        table_interface = table_sink:get_interface()
        game_sink = changde_game_creator.new(table_interface)
        table_sink:set_game_sink(game_sink)
    elseif args.game_id == 100 then
  		table_sink = tuidaohu_table_creator.new(args)
		table_interface = table_sink:get_interface()
		game_sink = tuidaohu_game_creator.new(table_interface)
		table_sink:set_game_sink(game_sink)  
	elseif args.game_id == 101 then
		-- print("=========args.game_id==============="..args.game_id)
  		table_sink = yunfu_table_creator.new(args)
		table_interface = table_sink:get_interface()
		game_sink = yunfu_game_creator.new(table_interface)
		table_sink:set_game_sink(game_sink)  
    elseif args.game_id == 102 then
  		table_sink = zhaoqing_table_creator.new(args)
		table_interface = table_sink:get_interface()
		game_sink = zhaoqing_game_creator.new(table_interface)
		table_sink:set_game_sink(game_sink) 			
	else
		table_sink = table_creator.new(args)
		table_interface = table_sink:get_interface()
		game_sink = game_creator.new(table_interface)
		table_sink:set_game_sink(game_sink)
	end
	skynet.fork(checkSleepFromNow)
end
function command.CLOSE(args)

	table_sink:dismiss(args)   -- agent lose  connection to room service 
	if not args.normal then
		game_sink:force_exit(args) -- send total result to all agent
	end
	
	table_sink:set_game_sink(nil)
	table_sink:close_sink()
	game_sink:close_sink()
	
	room_recycled = false
	if thread_id then
		skynet.wakeup(thread_id)
		thread_id = nil
	end
	room_player = {}
	player_info = {}
	room_num = 0 
	table_sink = nil
	game_sink  = nil
	table_interface = nil
	batch_room = nil
	syslog.debugf("room_server closed :%d",skynet.self())
	skynet.send(skynet.self(), "debug", "GC")
	--skynet.timeout(0,function() skynet.exit() end)
end

function command.RECONNECT(args)
	local player = room_player[args.uid]
	if not player then
		return false
	end
	local chairid = get_chairid_by_uid(args.uid)
	if chairid ~= 0 then
		player.address = args.address
		table_sink:post_table_reconnect(args.uid, chairid)
		skynet.fork(function() 
						table_sink:vote_dismiss_reconnection(args.uid)
					end)

		return true
	end
	return false
end

function command.DISCONNECTION(uid, address) 
	local player = room_player[uid]
	if not player then
		return 
	end	
	--TODO:通知其他玩家有人掉線了
	if address and address == player.address then
		local chairid = get_chairid_by_uid(uid)
		table_sink:post_player_disconnect(uid, chairid)
		player.address = nil
	end
end

function command.GAME_TALK_AND_PICTURE(uid, args)
	local player = room_player[uid]
	if not player then
		return
	end
	args.uid = uid
	return table_sink:post_talk_picture(args)
end

function command.GAME_PIAO_POINT(uid, args)
    local player = room_player[uid]
	if not player then
		return
	end
    local chairid = get_chairid_by_uid(uid)
    return game_sink:piao_handler(chairid, args.point)
end

function command.GAME_TING_CARD(uid, args)
    local player = room_player[uid]
    if not player then
        return
    end
    local chairid = get_chairid_by_uid(uid)
    return game_sink:deal_baoting(chairid)
end

function command.GAME_HAIDI_CARD(uid, args)
    local player = room_player[uid]
    if not player then
        return
    end
    local chairid = get_chairid_by_uid(uid)
    return game_sink:deal_haidi_card(chairid)
end

skynet.start(function()
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
end)



