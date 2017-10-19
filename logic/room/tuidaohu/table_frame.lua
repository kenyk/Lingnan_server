require "table_util"
require "functions"
local skynet = require "skynet"
local trans = require "trans"
local datacenter = require "datacenter"
local printR = table.printR
local printT = table.printT
local syslog = require "syslog"
local ts = tostring

local table_frame = class("table_frame")

local REQUEST = {}

local user_game_state = {
	PLAYING = 1,
	READY = 2,
	SIT_DOWN = 3,
	LOOKON = 4
}

function table_frame:ctor(args)
    --table.printT(args)
    self.REQUEST = REQUEST
    self.table_id = 1
    self.table_players = {}
    self.lookon_players = {}
    self.lookon_players_num = 0
    self.table_players_num = 0
    self.table_config = args.table_config
    self.table_config.master_id = args.master_id
    self.table_config.game_index = 1
    self.table_config.createtime = args.create_time
    self.table_config.room_id = args.room_name
    self.table_config.data = self.table_config.data
    self.table_config.game_id = args.game_id
    self.address = args.address  --該房間服務的地址
    self.enter_code = args.enter_code
    self.room_name = args.room_name
    self.player_chairs = {}
    self.vote_sign = nil
end


function table_frame:set_game_sink(game_sink)
	self.game_sink = game_sink
end

function table_frame:close_sink()
	self.table_players = nil
    self.lookon_players = nil
    self.player_chairs = nil
end

function table_frame:enter_table(userinfo)
    local uid = userinfo.uid
    if  self.lookon_players[uid] or self.table_players[uid] then
        return false, {code = 20002, table_id = self.table_id}
    end
    self.lookon_players[uid] = userinfo
    self.lookon_players[uid].game_state = user_game_state.LOOKON
    self.lookon_players_num = self.lookon_players_num + 1
    return true, {code = 0, table_id = self.table_id, table_config = self.table_config, players = self:get_table_player_scene()}
end

function table_frame:exit_table(uid)
    if self.table_players[uid] then
        local success, reason = self:stand_up(uid)
        if not success then
            return success, reason
        end
    end
    if not self.lookon_players[uid] then
        return false, {code = 20010}
    end
    if self.game_sink.is_playing then
        return false, {code = 30002}
    end
    --TODO:check game
    self.lookon_players[uid] = nil
    self.lookon_players_num = self.lookon_players_num - 1
    self:send_table_scene()
    return true, {code = 0}
end

function table_frame:sit_down(uid)
    if self.table_players[uid] then
        return false, {code = 20003,chair_id = self.player_chairs[uid]}
    end
    if not self.lookon_players[uid] then
        return false, {code = 20010}
    end
    --TODO:game sit down
    if self.table_config.player_count <= self.table_players_num then
        return false, {code = 20008} --人数已满
    end
    local chair_id = self:get_free_chair()
    self.player_chairs[uid] = chair_id
    local userinfo = self.lookon_players[uid]
    self.lookon_players_num = self.lookon_players_num -1
    self.lookon_players[uid] = nil
    self.table_players[uid] = userinfo
    self.table_players[uid].game_state = user_game_state.SIT_DOWN

    self.table_players_num = self.table_players_num + 1
    self.game_sink:add_player(chair_id, uid)
    self:send_table_scene()
    return true, {code = 0, chair_id = chair_id}
end

function table_frame:stand_up(uid)
    if not self.table_players[uid] then
        return false, {code = 20010}
    end
    --TODO:check game can exit
    local userinfo = self.table_players[uid]
    if userinfo.game_state == user_game_state.PLAYING then
        return false, {code = 20011}
    end
    --先退出游戏玩家信息
    self.game_sink:exit_player(uid)
    --再改变桌子玩家信息
    self.player_chairs[uid] = nil
    self.lookon_players[uid] = userinfo
    self.lookon_players[uid].game_state = user_game_state.LOOKON
    self.table_players[uid] = nil
    self.lookon_players_num = self.lookon_players_num + 1
    self.table_players_num = self.table_players_num -1
    return true, {code = 0}
end

function table_frame:get_ready(uid)
    local userinfo = self.table_players[uid]
    if not userinfo then
        return false, {code = 20010}
    end
    if userinfo.game_state == user_game_state.READY then
        return false, {code = 20009}
    end
    if userinfo.game_state == user_game_state.PLAYING then
        return false, {code = 20011}
    end
    self.table_players[uid].game_state = user_game_state.READY
    local data = {}
    data.uid = uid
    data.chair_id = self:get_chairid_by_uid(uid)
    self:SendAllUserClient("room_post_get_ready", data)
    if self:check_start() then
        --TODO:START GAME
        syslog.debug("game_start")
        self:start_game()
    end
    return true, {code = 0}
end

function table_frame:start_game()
    for k, v in pairs(self.table_players) do
        v.game_state = user_game_state.PLAYING
    end
    self.game_sink:start_game()
end

function table_frame:check_start()
    if self.table_players_num < self.table_config.player_count then
        return false
    end
    for k, v in pairs(self.table_players) do
        if v.game_state ~= user_game_state.READY then
            return false
        end
    end
    return true
end

--根据uid查找chair_id
function table_frame:get_chairid_by_uid(uid)
    if self.player_chairs[uid] then
        return self.player_chairs[uid]
    end
    return 0
end

--根据chaid_id查找uid
function table_frame:get_uid_by_chairid(chair_id)
    for k, v in pairs(self.player_chairs) do
        if v == chair_id then
            return k
        end
    end
    return 0
end

function table_frame:get_table_scene()
    local ret = {}
    ret.table_config = table.clone(self.table_config)
    ret.players = self:get_table_player_scene()
    return true,ret
end

function table_frame:send_table_scene()
    local _, data = self:get_table_scene()
    self:SendAllUserClient("room_post_table_scene", data)
end

function table_frame:get_table_player_scene()
    local players = {}
    for k, v in pairs(self.table_players) do
        local chair_id = self:get_chairid_by_uid(k)
        local tmp = table.clone(v)
        tmp.chair_id = chair_id
        tmp.point = self.game_sink:get_point(chair_id)
        table.insert(players, tmp)
    end
    return players
end

function table_frame:check_vote_win(option)
	local list =  {}
	if self.vote_table == nil then
		return false, list
	end
	if option == 1 then
		local total = self.table_config.player_count
		local current = #self.vote_table.vote_reject

		for k,v in pairs(self.vote_table.vote_reject) do
			list[#list + 1] = v.uid
		end
		
		if (total == 2 or total == 3) and current > 0 then
			return true ,list
		elseif total == 4 then
			if current >= 2 then
				return true ,list
			else
				return false,list
			end
		end
	elseif option == 0 then
		local total = self.table_config.player_count
		local current = #self.vote_table.vote_agree

		for k,v in pairs(self.vote_table.vote_agree) do
			list[#list + 1] = v.uid
		end
		
		if total == current and total < 4 then
			return true ,list
		elseif total == 4 then
			if current > 2 then
				return true ,list
			else
				return false,list
			end
		end		
	
	end
	
	return false, list
end

function table_frame:check_have_vote(uid)
    for k, v in pairs(self.vote_table.vote_agree) do
        if v.uid == uid then
            return true
        end
    end
    for k, v in pairs(self.vote_table.vote_reject) do
        if v.uid == uid then
            return true
        end
    end   
    return false
end

function table_frame:vote_dismiss_reconnection(uid)
    syslog.debugf("vote_dismiss_reconnection uid :%d", uid)
    if self.vote_master and uid then
        self:SendtableClient(uid, "room_post_vote_dismiss", {uid = self.vote_master, option = 0, apply = self.vote_master} )

        for k, v in pairs(self.vote_table.vote_agree) do
            if v.uid ~= self.vote_master then
                self:SendtableClient(uid, "room_post_vote_dismiss", {uid = v.uid, option = v.option, apply = self.vote_master})
            end
        end
        for k, v in pairs(self.vote_table.vote_reject) do
            self:SendtableClient(uid, "room_post_vote_dismiss", {uid = v.uid, option = v.option, apply = self.vote_master})
        end
    end
end



function table_frame:vote_dismiss_room(uid, args)
    if not uid == self.table_config.master_id or not self.table_players[uid] or self.vote_sign then
        return false, {code = 20013}
    end
    local tmp = {}
    tmp.uid = uid
    tmp.option = args.option
    if self.vote_table then
        if self:check_have_vote(uid) then
            return false, {code = 20014}
        end
        self:SendtableClient(0, "room_post_vote_dismiss", {uid = tmp.uid, option = tmp.option, apply = self.vote_master})
		if args.option == 0 then
			table.insert(self.vote_table.vote_agree, tmp)
		elseif args.option == 1 then
			table.insert(self.vote_table.vote_reject, tmp)
		else
			return false, {code = 20014}
		end
        syslog.debugf("vote vote_dismiss_room  player_id, option:%d,%d",uid, args.option)
       
        if args.option == 0 then
        	local sign , list = self:check_vote_win(args.option)
            if  sign then
                self.vote_table = nil
                self.vote_master = nil
                self.vote_sign = true
                syslog.debug("vote_dismiss_room will dismiss caused by voted")
                local result, sclub, point_wms
                if self.table_config.game_index == 1 then
                    skynet.send(".BUILD_ROOMS_SERVICE", "lua", "update_order_status", self.enter_code, "giveup")
                else
                    result, sclub, point_wms = self.game_sink:get_all_balance_result()
                end
                skynet.send(".BUILD_ROOMS_SERVICE", "lua", "on_close_room",skynet.self(),{address = self.address, room_name = self.room_name, list = list , enter_code = self.enter_code, sclub = sclub, point_wms = point_wms})
                
            end
        elseif args.option == 1 then
        	local sign , list = self:check_vote_win(args.option)
            if sign then
                --TODO:
                syslog.debug("vote_dismiss_room cancel dismiss caused by voted")
				self:SendtableClient(0, "room_post_room_dismiss", {code = 1, list = list } )
               
                self.vote_table = nil
                self.vote_master = nil
            end
        end
    else
        if args.option == 1 then -- 发起者必须是同意解散
            return false, {code = 20012}
        else
			if self.table_config.game_index == 1 and uid == self.table_config.master_id and self.game_sink:can_exit() then
                self.vote_sign = true
				syslog.debug("vote_dismiss_room will dismiss caused by  master_id")
				skynet.send(".BUILD_ROOMS_SERVICE", "lua", "update_order_status", self.enter_code, "giveup")
				skynet.send(".BUILD_ROOMS_SERVICE", "lua", "on_close_room", skynet.self(), {address = self.address, room_name = self.room_name, list = {}, enter_code = self.enter_code})
				return
			end
			self.vote_master = uid
            self:SendtableClient(0, "room_post_vote_dismiss", {uid = tmp.uid, option = tmp.option, apply = self.vote_master})

            self.vote_table = {vote_agree = {},vote_reject = {}, vote_time = skynet.time()}
           
            syslog.debugf("poll vote_dismiss_room  master:%d time :%f",uid,self.vote_table.vote_time)
            table.insert(self.vote_table.vote_agree, tmp)
           
            skynet.timeout(30000, function() 
                        			syslog.debugf("check vote_dismiss_room dismiss caused by 300s timeout now time:%f", skynet.time())
			                        if(self.vote_table and self.vote_table.vote_time and (skynet.time() - self.vote_table.vote_time >= 299)) then
			                        	local sign, list = self:check_vote_win(1)
			                        	if not sign then
			                       			self.vote_table = nil
				                        	self.vote_master = nil
                                            self.vote_sign = true
				                        	syslog.debug("vote_dismiss_room will dismiss caused by 300s timeout")
                                            local result, sclub, point_wms
                                            if self.table_config.game_index == 1 then
                                                skynet.send(".BUILD_ROOMS_SERVICE", "lua", "update_order_status", self.enter_code, "giveup")
                                            else
                                                result, sclub ,point_wms= self.game_sink:get_all_balance_result()
                                            end
				                        	skynet.send(".BUILD_ROOMS_SERVICE", "lua", "on_close_room",skynet.self(),{address = self.address, room_name = self.room_name, list = list, enter_code = self.enter_code, sclub = sclub, point_wms = point_wms})
				                        end
			                        end
                                 end
                           )
        end
    end
    return true, {code = 0}
end

function table_frame:dismiss(args)
    for k, v in pairs(self.lookon_players) do   
        if v.address  then
            skynet.send(v.address, "lua", "kick_room",{address = self.address, list = args.list})
        else
            skynet.send(".BUILD_ROOMS_SERVICE", "lua", "update_player_status", k, nil)
        end
    end
    for k, v in pairs(self.table_players) do
        if v.address then
            skynet.send(v.address, "lua", "kick_room",{address = self.address, list = args.list, normal = args.normal})
        else
            skynet.send(".BUILD_ROOMS_SERVICE", "lua", "update_player_status", k, nil)
        end
    end
end

function table_frame:game_end()

end

local function get_format_time(time)
    return os.date("%Y-%m-%d %H:%M:%S", time)
end

function table_frame:record_room_result(room_result)
    local param = {}
    param.room_id = self.room_name
    param.end_time = os.time()
    param.game_num = (self.table_players_num ~=  self.table_config.player_count) and 0 or (self.table_config.game_index -1)
    param.owner    = self.table_config.master_id
    for i = 1, 4 do
        local tmp_result = room_result[i] or nil
        if tmp_result then
            param["chair_"..i.."_uid"] = tmp_result.uid
            param["chair_"..i.."_name"] = self.table_players[tmp_result.uid].nickname
            param["chair_"..i.."_point"] = tmp_result.point
            param["chair_"..i.."_image"] = self.table_players[tmp_result.uid].image_url
        else
            param["chair_"..i.."_uid"] = 0
            param["chair_"..i.."_name"] = " "
            param["chair_"..i.."_point"] = 0
            param["chair_"..i.."_image"] = " "
        end
    end
    -- table.printT(param)
    skynet.send(".MYSQL", "lua", "log", "db_game_log", "room_result", param)
end

function table_frame:on_game_end(args)
    for k, v in pairs(self.table_players) do
        v.game_state = user_game_state.SIT_DOWN
    end
    self.table_config.game_index = self.table_config.game_index + 1
	
	if self.table_config.game_index == 2 then -- first playing game end for change order status
		syslog.debug("begin update order status")
		skynet.send(".BUILD_ROOMS_SERVICE", "lua", "update_order_status", self.enter_code, "used")
	end
    
    if (self.table_config.game_index == self.table_config.game_count + 1)  or ( args )   then
    	local ret = {}
        local sclub, point_wms
    	ret.room_id = self.room_name
    	ret.player_result, sclub, point_wms = self.game_sink:get_all_balance_result()
        ret.win = sclub
    	self:SendAllUserClient("game_balance_result", ret)
       self:record_room_result(ret.player_result)
       if not args then
       	  skynet.send(".BUILD_ROOMS_SERVICE", "lua", "on_close_room", skynet.self(), {normal = true ,address = self.address, room_name = self.room_name, list = args and args.list or {}, enter_code = self.enter_code, sclub = sclub, point_wms = point_wms})
       end
    end
end

function table_frame:send_red_bag()
    local str = ""
    local tt = {"","","",""}    
    for a, b in pairs(self.player_chairs) do
        tt[b] = a
    end
    str = tt[1].."-"..tt[2]..(tt[3] == "" and "" or "-")..tt[3]..(tt[4] == "" and "" or "-")..tt[4]

    local param = {}
    param.enter_code = self.enter_code
    param.userIds = str
    skynet.send(".BUILD_ROOMS_SERVICE", "lua", "send_red_bag", param)
end

function table_frame:post_table_reconnect(uid, chair_id)
    
    local _,ret = self:get_table_scene()
    ret.is_playing = self.game_sink:get_game_status()
    ret.enter_code = self.enter_code
    ret.game_index = self.table_config.game_index
    -- table.printT(ret)
    --推送给玩家桌子信息
    self:SendtableClient(uid, "room_post_table_reconnect", ret)
    --推送給其他玩家 玩家uid重連了
    self:SendtableClient(0, "room_post_player_connect", {chair_id = chair_id, connect = true}, uid)
end

function table_frame:post_player_disconnect(uid, chair_id)
    self:SendtableClient(0, "room_post_player_connect", {chair_id = chair_id, connect = false}, uid)
end

function table_frame:get_free_chair()
    if table.nums(self.player_chairs) == 0 then
        return 1
    end
    local map = {}
    for uid, chairid in pairs(self.player_chairs) do
        map[chairid] = uid
    end

    local ret_chairid = #map + 1
    return ret_chairid
end

function table_frame:can_exit(uid)
    if self.lookon_players[uid] then
        return true
    end
    local userinfo = self.table_players[uid]
    if userinfo then
        if userinfo.game_state == user_game_state.PLAYING then
            return false, {code = 20011}
        end
        return self.game_sink:can_exit(uid)
    else
        return true
    end
end

function table_frame:get_interface()
    return {
        send_table_client = function (uid, cmd, args)
            return self:SendtableClient(uid, cmd, args)
        end,
        send_lookon_client = function (uid, cmd, args)
            return self:SendLookonClient(uid, cmd, args)
        end,
        get_uid_by_chairid = function(chair_id)
            return self:get_uid_by_chairid(chair_id)
        end,
        get_chairid_by_uid = function(uid)
            return self:get_chairid_by_uid(uid)
        end,
        on_game_end = function ( game_record )
            return self:on_game_end(game_record)
        end,
        send_red_bag = function ()
            return self:send_red_bag()
        end,
        table_id = self.table_id,
        lookon_players = table.get_readonly_table(self.lookon_players),
        table_players = table.get_readonly_table(self.table_players),
        table_config = self.table_config,
    }
end

function table_frame:SendAllUserClient(cmd, args)
    self:SendtableClient(0, cmd, args)
end

--发送话或图片
function table_frame:post_talk_picture(tab)
    self:SendtableClient(0,"game_talk_and_picture", tab)
end

---------------------send client func ---------------------------------
function table_frame:SendLookonClient(uid, cmd, data)
    if uid == 0 then
        -- send all players
        for uid,v in pairs(self.lookon_players) do
        	if v.address then
            	skynet.send(v.address, "lua", "send", cmd, data)
            end
        end
    else
        -- send single player
        if self.lookon_players[uid] and self.lookon_players[uid].address then
            skynet.send(self.lookon_players[uid].address, "lua", "send", cmd, data)
        end
    end
end

function table_frame:SendtableClient(uid, cmd, data, except)
    if uid == 0 then
        -- send all players
        for k,v in pairs(self.table_players) do
        	if(v.address and except and except ~= k) then
            	skynet.send(v.address, "lua", "send", cmd, data)
            elseif (v.address and not except) then
            	skynet.send(v.address, "lua", "send", cmd, data)
            end
        end
    else
        -- send single player
        if self.table_players[uid] and self.table_players[uid].address then
            skynet.send(self.table_players[uid].address, "lua", "send", cmd, data)
        end
    end
end

return table_frame
