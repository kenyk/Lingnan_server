require "table_util"
require "functions"
local json = require "cjson"
local skynet = require "skynet"
local game_record = class("game_record")

local function get_format_time(time)
	return os.date("%Y-%m-%d %H:%M:%S", time)
end

function game_record:ctor(table_config)
	--print("===game_record====")

	--[[
	table_config = {
	    game_count = 8
    	data = {"game_type":2,"laizi":false,"find_bird":0,"seven_hu":false,"idle":false,"qiang_gang":false}
    	game_index = 1
    	rate = 1
    	createtime = 1479202095
    	player_count = 2
    	}
	]]
	--table.printT(table_config)
	self.table_config = table_config
	self.config = table_config.data
	self:init_record()
	--[[
		point = 0
		uid = 0
		nickname = "--"
	]]
	self.player_record = {}
	self.room_id = self.table_config.room_id
	self.master_id = self.table_config.master_id
    self.replay = {}
	-- self.game_index = game_index
end

function game_record:init_record()
	--[[
		table_card = ""
		player_init_card = {
			[1] = ""
			[2] = ""
			...
		}
		game_action = ""
	]]
	self.game_index = self.table_config.game_index
	self.game_record = {}
	self.game_action = ""
	self.player_card = {}
	self.init_card = {}
	--[[

	]]
	self.game_result = ""
end

function game_record:record_game_result(str)
	if self.game_result ~= "" then
		self.game_result = self.game_result..";"..str
	else
		self.game_result = str
	end
end



function game_record:record_game_action(chair_id,action,card,card1)
	--[[
        杠牌连出2张
		action:chair_id-card-card1
        正常
        action:chair_id-card
1 摸牌
2 出牌
3 碰牌
4 杠牌
5 吃牌
6 胡牌
7 取消
8 补张
9 飘
10 鸟
	]]
	local tmpstr = ""
	if card then
		tmpstr = action..":"..chair_id.."-"..card
        if card1 then
            tmpstr = tmpstr.."-"..card1
        end
	else
		tmpstr = action..":"..chair_id
		if action == 6 then
			self:record_game_result(tmpstr)
		end
	end
	if self.game_action ~= "" then
		self.game_action = self.game_action..";"..tmpstr
	else
		self.game_action = tmpstr
	end
end

function game_record:record_deal_card(chair_id,card)
	self.player_card[chair_id] = table.clone(card)
	-- table.printT(self.player_card)
end

function game_record:record_init_card(card)
	self.init_card = table.clone(card)
	-- table.printT(self.init_card)
end

function game_record:init_player_record(chair_id, uid)
	local player_info = {point = 0, nickname = "player"..uid, uid = uid}
	self.player_record[chair_id] = player_info
	-- table.printT(self.player_record)
end

function game_record:add_player_balance(chair_id, point)
	self.player_record[chair_id].point = point
end

function game_record:write_game_record()
	self.game_record.init_card = json.encode(self.init_card)
	self.game_record.player_card = json.encode(self.player_card)
	self.game_record.game_action = self.game_action
	-- table.printT(self.game_record)

	local param = {}
	param.game_action = json.encode(self.game_record)
	param.room_id = self.room_id
	param.game_index = self.game_index
	param.end_time = os.time()
	param.game_result = self.game_result
	param.owner = self.master_id
	for i = 1, 4 do
        local tmp_result = self.player_record[i] or nil
        if tmp_result then
            param["chair_"..i.."_uid"] = tmp_result.uid
            param["chair_"..i.."_point"] = tmp_result.point
        else
            param["chair_"..i.."_uid"] = 0
            param["chair_"..i.."_point"] = 0
        end
    end
	skynet.send(".MYSQL", "lua", "log", "db_game_log", "store_log", param)
end

function game_record:write_room_record()
	
end

function game_record:get_game_replay(chair_id)
    return self.replay[chair_id] or {}
end

function game_record:add_game_replay(chair_id, chair_id1, card, cards)
    table.insert(self.replay[chair_id], {chair_id1, card, cards})
end

function game_record:init_game_replay(player_count)
    for i=1 , player_count do
        self.replay[i] = {}
    end
end

return game_record