require "functions"
require "table_util"
local json = require "cjson"
-- local Scheduler = require "scheduler"
local majiang = require "majiang.changde.cardDef"
local majiang_opration = require "majiang.changde.majiang_opration"
local game_player_info = require "majiang.changde.game_player_info"
local game_record_ctor = require "game_record"
local syslog = require "syslog"
-- game demo 
local game_sink = class("game_sink")

function game_sink:ctor(interface, table_config)
	self.interface = interface
	self.table_config = interface.table_config
	self.game_config = json.decode(interface.table_config.data)
	self:init_game_config()
	self.is_playing = false
	self.players = {}
	self:init_game()
	majiang_opration:set_config(self.game_all_info, self.game_config, self.louHuChair )
	self.game_record = game_record_ctor.new(self.table_config)
end

--两人玩法不能抓鸟 没有癞子（防止客户端发错参数）
function game_sink:init_game_config()
	if self.table_config.player_count == 2 then
		self.game_config.find_bird = 0
		self.game_config.laizi = false
	end
	--首局庄为1
	if self.game_config.idle then
		self.banker = 1
	end
end

function game_sink:init_game()
	--游戏公共信息
	self.game_all_info = {}
	self.game_all_info.last_out_card = 0
	self.game_all_info.last_out_chair = 0
	self.game_all_info.cur_out_chair = 0
	self.game_all_info.find_bird_num = 0
    self.turn = 0
    self.turnCard = 0
    self.turnLock = false
    self.isqianggang = 0
    self.qianggang_card = 0
    self.zhama = {}


	--游戏私有信息
	self.game_privite_info = {}
	self.game_privite_info.canHu = {}
	self.game_privite_info.Hu = {}
	self.game_privite_info.canPeng = 0
    self.game_privite_info.pengcard = 0
	self.game_privite_info.canGang = {chair_id = 0}
	self.game_privite_info.canChi = 0
    self.game_privite_info.firstDraw = {}
    self.gang_cache = {}
	--游戏结束结算
	self.game_end_balance_info = {}
	self.game_end_balance_info.game_index = self.table_config.game_index
	self.game_end_balance_info.birdNum = 0
	self.game_end_balance_info.banker = 0
	self.game_end_balance_info.birdPlayer = 0
	self.game_end_balance_info.birdCard = {}
	self.game_end_balance_info.hu_chairs = {}
	self.game_end_balance_info.player_balance = {}
	--漏胡
	self.louHuChair = {}  
    --是不是第一次摸牌
    self.firstDrawInfo = {}
	--
	self.game_player_operation = {}
	self.is_Hu = false
	self.next_banker_chair = 0
	self.dianPao = 0
	self:init_player_operation()
end
function game_sink:close_sink()
	self.game_all_info = nil
	self.game_privite_info = nil
	self.game_end_balance_info = nil
	self.louHuChair = nil
	self.players = nil
	self.game_record = nil
	self.interface = nil
	self.table_config = nil
	self.game_config = nil
    self.firstDrawInfo = nil
    self.turn = nil
    self.turnCard = nil
    self.turnLock = nil
    self.isqianggang = nil
    self.zhama = nil
    self.qianggang_card = nil
    self.gang_cache = nil
end



--[[
	op: 1.自摸胡 2.接炮胡 3.抢杠胡
]]
function game_sink:count_can_operation(ret, chair_id, op, lose_chair,card)
	--漏胡该轮不能胡
	if ret.canHu then
		local param = {chair_id = chair_id, op = op, lose_chair = lose_chair, card = card}
		table.insert(self.game_privite_info.canHu, param)
	end
	if ret.canPeng then
		self.game_privite_info.canPeng = chair_id
        self.game_privite_info.pengcard = card
	end
	if ret.canGang then
		local tmp = {}
		tmp.chair_id = chair_id
		tmp.card = ret.canGang
		self.game_privite_info.canGang = tmp
	end
	if ret.canChi then
		self.game_privite_info.canChi = chair_id
	end
	-- table.printT(self.game_privite_info)
end

function game_sink:delete_player_can_operation(chair_id)
	-- for k, v in pairs(self.game_privite_info) do
	-- 	if k ~= "can_hu" then
	-- 		if v == chair_id then
	-- 			print("k", k,v)
	-- 			v = 0
	-- 		end
	-- 	end
	-- end
	if self.game_privite_info.canPeng == chair_id then
		self.game_privite_info.canPeng = 0
        self.game_privite_info.pengcard = 0
	end
	if self.game_privite_info.canGang.chair_id == chair_id then
		self.game_privite_info.canGang = {chair_id = 0}
	end
	if self.game_privite_info.canChi == chair_id then
		self.game_privite_info.canChi = 0
	end
	for k, v in pairs(self.game_privite_info["canHu"]) do
		if v.chair_id == chair_id then
			table.remove(self.game_privite_info["canHu"], k)
			break
		end
	end
end

local player_op_priority = {
	["chi"] = 1,
	["peng"] = 2,
	["gang"] = 3,
	["hu"] = 4
}

function game_sink:insert_player_operation(chair_id, option_type, card, gang_type)
	--[[
		option_type:hu
					gang {chair_id=1, card=12, gang_type = "gang_peng/gang_mo", op = 2,}
					peng {chair_id=1, card = 12}
					chi {chair_id=1, card = {card= 12, chi_card = {11,13}}}
					只存在一种操作,高优先级会替换掉低优先级的操作
	]]
	local param = {
				   chair_id = chair_id,
				   card = card, 
				   gang_type = gang_type, 
				   op = player_op_priority[option_type]
				}
	if next(self.game_player_operation) then
		if player_op_priority[option_type] > self.game_player_operation.op then
			self.game_player_operation = param
		end
	else
		self.game_player_operation = param
	end
end

function game_sink:deal_player_operation()
	if not next(self.game_player_operation) then
		return false
	end
	local player_operation = self.game_player_operation
	local flag = false
	--gang
	if player_operation.op == 3 then
		flag = true
		if player_operation.gang_type == "gang_peng" then
			self:gang_peng_card(player_operation.chair_id, player_operation.card, true)
		elseif player_operation.gang_type == "gang_mo" then
			self:gang_mo_card(player_operation.chair_id, player_operation.card)
		end
	--peng
	elseif player_operation.op == 2 then
		flag = true
		self:peng_card(player_operation.chair_id, player_operation.card, true)
	--chi
	elseif player_operation.op == 1 then
		flag = true
		self:chi_card(chair_id, player_operation.card.card, player_operation.card.chi_card)
	end
    if flag then 
        self:init_player_operation()
    end
	return flag
end

function game_sink:init_player_operation()
	self.game_player_operation = {}
end

function game_sink:check_player_gang_need_wait(chair_id)
	for k, v in pairs(self.game_privite_info["canHu"]) do
		if v.chair_id ~= chair_id then
			return false
		end
	end
	return true
end

function game_sink:check_player_peng_need_wait(chair_id)
	if not self:check_player_gang_need_wait(chair_id) then
		return false
	end
	if self.game_privite_info["canGang"].chair_id ~= 0 and self.game_privite_info["canGang"].chair_id ~= chair_id then
		return false
	end
	return true
end

function game_sink:check_player_chi_need_wait(chair_id)
	if not self:check_player_peng_need_wait(chair_id) then
		return false
	end
	if self.game_privite_info["canPeng"] ~= 0 and self.game_privite_info["canPeng"] ~= chair_id then
		return false
	end
	return true
end

function game_sink:check_player_operation_need_wait(chair_id, option_type)
	if option_type == "gang" then
		return not self:check_player_gang_need_wait(chair_id)
	elseif option_type == "peng" then
		return not self:check_player_peng_need_wait(chair_id)
	elseif option_type == "chi" then
		return not self:check_player_chi_need_wait(chair_id)
	end
	return false
end

function game_sink:init_can_operation()
	self.game_privite_info = {}
	self.game_privite_info.canHu = {}
	self.game_privite_info.Hu = {}
	self.game_privite_info.canPeng = 0
	self.game_privite_info.canGang = {chair_id = 0}
	self.game_privite_info.canChi = 0
end
--isnotjson:true 不转json
local function group_card(pcardinfo, isnotjson)
	-- table.printT(pcardinfo)
	local cardinfo = table.clone(pcardinfo)
	local handCards = cardinfo.handCards
	-- table.printT(handCards)
	local pengCards = cardinfo.pengCards
	local gangCards = cardinfo.gangCards
	local chiCards = cardinfo.chiCards
	local ret = {}
	for k, v in pairs(pengCards) do
		local tmp = {}
		table.insert(tmp,k)
		table.insert(tmp,k)
		table.insert(tmp,k)
		table.insert(ret, tmp)
	end

	for k, v in pairs(gangCards) do
		local tmp = {}
		table.insert(tmp,k)
		table.insert(tmp,k)
		table.insert(tmp,k)
		table.insert(tmp,k)
		table.insert(ret, tmp)
	end

	for k,v in pairs(chiCards) do
		table.insert(ret, table.sort(v))
	end
	--小局结算 把胡的牌拿出来独立显示
	if pcardinfo.huCard ~= 0 then
		table.removebyvalue(handCards, pcardinfo.huCard)
	end
	table.insert(ret, handCards)
    if not isjson then
        return json.encode(ret)
    else
        return ret
    end
end

--[[
	判断是否存在需要等待的操作
]]
function game_sink:check_can_operation_empty()
	local player_operation_type = 0
	if self.game_player_operation.op then
		player_operation_type = self.game_player_operation.op
	end
	local info = self.game_privite_info.canHu
	if next(info) and info[next(info)].chair_id ~= self.game_player_operation.chair_id then
		return false
	end
	if self.game_privite_info.canGang and self.game_privite_info.canGang.chair_id ~= 0 and not next(self.game_privite_info.Hu) then
		if player_operation_type < 3 then
			return false
		end
	end
	if self.game_privite_info.canPeng and self.game_privite_info.canPeng ~= 0 and not next(self.game_privite_info.Hu) then
		if player_operation_type < 2 then
			return false
		end
	end
	--如果要加吃 这里要处理
	if self.game_privite_info.canChi and self.game_privite_info.canChi ~= 0 then
		if player_operation_type == 0 then
			return false
		end
	end
	return true
end

function game_sink:delete_louHu_limit(chair_id)
	if chair_id == 0 then
		self.louHuChair = {}
	else
		self.louHuChair[chair_id] = {}
	end
end

-----------------------------------------------------------------
----------------------interface function-------------------------
-----------------------------------------------------------------
function game_sink:game_send_table_sink(chair_id, cmd, ...)
	local uid = chair_id
	if chair_id ~= 0 then
		uid = self:get_uid_by_chairid(chair_id)
	end
	self.interface.game_send_table_sink(uid, cmd, ...)
end

function game_sink:game_call_table_sink(chair_id, cmd, ...)
	local uid = chair_id
	if chair_id ~= 0 then
		uid = self:get_uid_by_chairid(chair_id)
	end
	return self.interface.game_call_table_sink(uid, cmd, ...)
end

function game_sink:send_table_client(chair_id, cmd, data)
	local uid = chair_id
	if chair_id ~= 0 then
		uid = self:get_uid_by_chairid(chair_id)
	end
	return self.interface.send_table_client(uid, cmd, data)
end

function game_sink:send_lookon_client(uid, cmd, data)
	return self.interface.send_lookon_client(uid, cmd, data)
end

function game_sink:get_chairid_by_uid(uid)
	return self.interface.get_chairid_by_uid(uid)
end

function game_sink:get_uid_by_chairid(chair_id)
	return self.interface.get_uid_by_chairid(chair_id)
end
-----------------------------------------------------------------
-----------------------------------------------------------------

function game_sink:add_player(chair_id, uid)
	local player_info = table.clone(game_player_info)
	player_info.base_info.chair_id = chair_id
	player_info.base_info.uid = uid
	self.players[chair_id] = player_info
	self.game_record:init_player_record(chair_id, uid)
	return true
end

function game_sink:exit_player(uid)
	local chair_id = self:get_chairid_by_uid(uid)
	self.players[chair_id] = nil
end

function game_sink:can_exit(uid)
	if self.is_playing == true then
		return false
	end
	return true
end

function game_sink:get_banker_chair()
	return self.banker or 1
end

function game_sink:get_card_index(chair_id)
	local banker = self:get_banker_chair()
--	if banker == 0 then banker = 1 end
	local offset = banker -1
	if chair_id == banker then
		return 1
	end
	if offset == 0 then
		return chair_id
	end
	if chair_id > banker then
		return chair_id - offset
	else
		return self.table_config.player_count + chair_id - offset
	end
end

function game_sink:get_next_chair(chair_id)
	if chair_id == self.table_config.player_count then
		return 1
	else
		return chair_id + 1
	end
end

----洗牌
--function game_sink:shuffle_cards()
--	self.cards = majiang:randCards(self.game_config.laizi, self.table_config.player_count)
--	-- self.cards = majiang:testCard()
--end

--发牌
function game_sink:deal_cards()
	local player_cards = {}
    --self.cards = majiang:randCards(self.game_config.laizi, self.table_config.player_count)
	--player_cards, self.aftercards = majiang:dealCards(self.cards, self.table_config.player_count, 0)
    player_cards, self.aftercards = majiang:init_cards(self.game_config.laizi, self.table_config.player_count)
	self.game_record:record_init_card(self.aftercards)
	local card_num = {}
	local card_first = self:get_banker_chair()
	for i = 1,self.table_config.player_count do
		card_num[i] = #player_cards[i]
	end
	for k, v in pairs(self.players) do
		local index = self:get_card_index(k)
		v.card_info.handCards = table.clone(player_cards[index])
		self.game_record:record_deal_card(k, v.card_info.handCards)
		v.card_info.stackCards = majiang:stackCards(v.card_info.handCards)
		self:send_table_client(k, "game_deal_card", {cards = table.clone(v.card_info.handCards),card_num = card_num,card_first = card_first})
--		local ret = majiang_opration:deal_card(v.card_info.stackCards)
--		if next(ret) then
--			self:count_can_operation(ret, k, 1, 0, 0)
--			self:send_table_client(k, "game_have_operation", {operation = json.encode(ret)})
--		end
	end
end

--摸牌 ：last(-1摸最后一张 1第一次摸牌 0正常摸牌)
function game_sink:draw_card(chair_id, last)
	if #self.aftercards == 0 then
		self.next_banker_chair = chair_id
		self:game_end()
		return
	end
	if last ~= 1 then
		self:delete_louHu_limit(chair_id)
		self:init_can_operation()
		self:init_player_operation()
	end
	local card 
--	if last == -1 then
--		--杠摸最后一张牌
--		card = self.aftercards[#self.aftercards]
--		table.remove(self.aftercards)
--	else
		card = self.aftercards[1]
		table.remove(self.aftercards, 1)
--	end
    self.turnCard = 0
	syslog.info("chair_id:["..chair_id.."]摸牌["..card.."]")
	local user_card_info = self.players[chair_id].card_info
	-- self:send_table_client(chair_id, "game_draw_card", {chair_id = chair_id,card = card})
	for k, v in pairs(self.players) do
		if k ~= chair_id then
			self:send_table_client(k, "game_draw_card", {chair_id = chair_id,card = 0})
		end
	end
	self.game_all_info.cur_out_chair = chair_id
    --判断是不是第一次摸牌 （第一次4红中能胡）
    local isfirstDraw = false
    if not self.firstDrawInfo[chair_id] then
        self.firstDrawInfo[chair_id] = true
        isfirstDraw = true
    end
	local ret = majiang_opration:mo_card(user_card_info.handCards, user_card_info.stackCards, user_card_info.pengCards, card, last, chair_id, self.louHuChair, isfirstDraw)
	self:send_table_client(0,"game_post_timeout_chair", {chair_id = chair_id})
	majiang_opration:handle_mo_card(user_card_info.handCards, user_card_info.stackCards, card)
	self.game_record:record_game_action(chair_id, 1, card)
    self.turn = chair_id
	table.printForMajiang(chair_id, user_card_info.handCards)
	if next(ret) then
		--先推可以进行的操作 再推摸的牌
		syslog.debug("玩家:["..chair_id.."]可操作:"..json.encode(ret))
		self:count_can_operation(ret, chair_id, 1, 0, card)
		self:send_table_client(chair_id, "game_draw_card", {chair_id = chair_id,card = card})
		self:send_table_client(chair_id, "game_have_operation", {operation = json.encode(ret)})
	else
		self:send_table_client(chair_id, "game_draw_card", {chair_id = chair_id,card = card})
		--自模胡：摸光牌游戏结束
		if self:check_can_game_end("draw_card", chair_id) then
		--结束游戏
			self:game_end()
		end
	end
end

--出牌
function game_sink:out_card(chair_id, card)
--[[
	game_player_info.card_info = {
	handCards = {},
	outCards = {},
	pengCards = {},
	gangCards = {},
	stackCards = {},
	chiCards = {}
}
]]	
	syslog.info("chair_id:["..chair_id.."]出牌:["..card.."]")
	if not self.is_playing then
		return false, {code = 30001}
	end
    --非法操作
--    if self.turn ~= chair_id or next(self.game_privite_info.canHu) or next(self.game_privite_info.canGang) or self.game_privite_info.canPeng ~= 0 then
    if self.turn ~= chair_id or not self:check_player_chi_need_wait(chair_id) then
        syslog.info("chair_id:["..chair_id.."]非法出牌:["..card.."]turn "..self.turn)
        return false, {code = 30005}
    end
    self.turnCard = card
	local user_hand_card_info = self.players[chair_id].card_info.handCards
    --牌的数量检测
    local _, tmp = math.modf((#user_hand_card_info-2)/3)
    if tmp ~= 0 then
       syslog.err("error:mahjong count:"..#user_hand_card_info)
    end
--	local can_out_card = false
--	for k, v in pairs(user_hand_card_info) do
--		if card == v then
--			can_out_card = true
--			break
--		end
--	end
--	if not can_out_card then
--		return true, {code = -2}
--	end
    if not self.players[chair_id].card_info.stackCards[card] then
        return true, {code = -2}
    end
	local will_wait = false
	local user_card_info = self.players[chair_id].card_info
	self:send_table_client(0, "game_out_card", {chair_id = chair_id, card = card})
	majiang_opration:handle_out_card(user_card_info.handCards,user_card_info.stackCards, user_card_info.outCards,card)
	self.game_record:record_game_action(chair_id, 2, card)
	-- self.cur_out_chair = chair_id
	-- self.game_all_info.cur_out_chair = chair_id
	self.game_all_info.last_out_chair = chair_id
	self.game_all_info.last_out_card = card
    --漏胡
    if self.turnLock then
        self.turnLock = false
        if not self.louHuChair[chair_id] then
            self.louHuChair[chair_id] = {}
        end
        self.louHuChair[chair_id][card] = true
    end
	for k, v in pairs(self.players) do
		if k ~= chair_id then
			table.printForMajiang(k, v.card_info.handCards)
			local ret = majiang_opration:other_out_card(v.card_info.handCards, v.card_info.stackCards,card, k, self.louHuChair)
			if next(ret) then
				self:count_can_operation(ret, k, 2, chair_id,card)
				will_wait = true
				--TODO:推送给玩家可以进行的操作
				syslog.debug("玩家:["..k.."]可操作:"..json.encode(ret))	
				self:send_table_client(k, "game_have_operation", {operation = json.encode(ret)})
			end
		end
	end
	if will_wait then
		return true, {code = 0}
	end
	--下一个玩家摸牌
	if self:check_can_game_end("out_card", chair_id) then
		--结束游戏
		self:game_end()
	else
		self:draw_card(self:get_next_chair(chair_id), 0)
	end
	
	return true, {code = 0}
end
--iswait是否等待调用的碰 
function game_sink:peng_card(chair_id, card, iswait)
	card = self.game_all_info.last_out_card
	syslog.info("chair_id:["..chair_id.."]碰:["..card.."]")
	if not self.is_playing then
		return false, {code = 30001}
	end
	if self.game_privite_info.canPeng ~= chair_id and not iswait then
		syslog.err("chair_id:["..chair_id.."]碰:["..card.."] 失败")
		return true, {code = 30002}
	end
	if next(self.game_privite_info.Hu) then
		syslog.err("chair_id:["..chair_id.."]碰:["..card.."] 失败,有人胡牌，自己不胡而碰")
		--有人胡  去碰相当于取消（只有在别人胡 你也胡还有碰， 点碰会进这里）
		self:cancel_action(chair_id, card)
		return true, {code = 30002}
	end
	if self:check_player_operation_need_wait(chair_id, "peng") then
		syslog.debug("peng need wait")
		self:insert_player_operation(chair_id, "peng", card)
		self:delete_player_can_operation(chair_id, "canPeng")
		return true, {code = 30003}  --TODO:code可能会改
	end
	self:init_can_operation()
	local user_card_info = self.players[chair_id].card_info
	majiang_opration:handle_peng_card(user_card_info.handCards, user_card_info.stackCards, user_card_info.pengCards, card, self.game_all_info.last_out_chair)
	--把牌从出过的牌中拿走
	local out_user_card_info = self.players[self.game_all_info.last_out_chair].card_info
	majiang_opration:handle_kick_out_card(out_user_card_info.outCards, card)
	self.game_record:record_game_action(chair_id, 3, card)
    --chair_id, chair_id1, card, cards
    local last_cardsTmp = table.clone(out_user_card_info)
    majiang_opration:handle_mo_card(last_cardsTmp.handCards, last_cardsTmp.stackCards, card)
    self.game_record:add_game_replay(chair_id, self.game_all_info.last_out_chair, card, group_card(last_cardsTmp, true))
	for k, v in pairs(self.players) do
		-- if k ~= chair_id then
			self:send_table_client(k, "game_peng_card", {chair_id = chair_id, card = card, out_chair = self.game_all_info.last_out_chair})
		-- end
	end
--    local ret =  majiang_opration:check_gang_after(user_card_info.stackCards)
--    if next(ret) then
--        self:count_can_operation(ret, chair_id, 1, 0, card)
--        self:send_table_client(chair_id, "game_have_operation", {operation = json.encode(ret)})
--    end
	self:delete_louHu_limit(0)
	self.game_all_info.cur_out_chair = chair_id
	self:send_table_client(0,"game_post_timeout_chair", {chair_id = chair_id})
    self.turn = chair_id
	return true , {code = 0}
end

function game_sink:gang_card(chair_id, card)
	if not self.is_playing then
		return false, {code = 30001}
	end
	if self.game_privite_info.canGang.chair_id ~= chair_id then
		return true, {code = 30002}
	end
	local user_card_info = self.players[chair_id].card_info
	local gang_type = majiang_opration:get_gang_type(user_card_info.handCards, user_card_info.stackCards, user_card_info.pengCards, card)
    self.turnCard = card
	if gang_type == 1 then
        --非法操作
--        if self.turn == chair_id then
--            syslog.err("oioooooooooooooooooooooo")
--            return false, {code = 30005}
--        end
		return self:gang_mo_card(chair_id, card)
	elseif gang_type == 2 then
		return self:gang_peng_card(chair_id, card)
	else
		return false, {code = 30002}
	end
end

function game_sink:gang_peng_card(chair_id, card, iscallback)
	syslog.info("chair_id:["..chair_id.."]杠:["..card.."]")
	if self.game_privite_info.canGang.chair_id ~= chair_id and not iscallback then
		syslog.err("chair_id:["..chair_id.."]杠:["..card.."] 失败")
		return true, {code = -1}
	end

	if self:check_player_operation_need_wait(chair_id, "gang") then
		self:insert_player_operation(chair_id, "gang", card, "gang_peng")
		self:delete_player_can_operation(chair_id, "canGang")
		return true, {code = 30003}  --TODO:code可能会改
	end

	local user_card_info = self.players[chair_id].card_info
	majiang_opration:handle_gang_peng_card(user_card_info.handCards, user_card_info.stackCards, user_card_info.gangCards, card, self.game_all_info.last_out_chair)
	--把牌从出过的牌中拿走
	local out_user_card_info = self.players[self.game_all_info.last_out_chair].card_info
	majiang_opration:handle_kick_out_card(out_user_card_info.outCards, card)
	self.game_record:record_game_action(chair_id, 4, card)
    local last_cardsTmp = table.clone(out_user_card_info)
    majiang_opration:handle_mo_card(last_cardsTmp.handCards, last_cardsTmp.stackCards, card)
    self.game_record:add_game_replay(chair_id, self.game_all_info.last_out_chair, card, group_card(last_cardsTmp,true))
    local will_wait = false
	for k, v in pairs(self.players) do
		if true then
			local param = {chair_id = chair_id, card = card, gang_type = 3, out_chair = self.game_all_info.last_out_chair}
			self:send_table_client(k, "game_gang_card",param)
--            if k ~= chair_id and self.game_config.qiang_gang then
--                local ret = majiang_opration:other_self_gang(v.card_info.handcards, v.card_info.stackcards, card, k, self.louhuchair)
--				if ret.canhu then
--					will_wait = true
--					syslog.debug("玩家:["..k.."]可操作:"..json.encode(ret))
--					self:count_can_operation(ret, k, 3, chair_id,card)
--					self:send_table_client(k, "game_have_operation", {operation = json.encode(ret)})
--                    self.isqianggang = chair_id
--                    self.qianggang_card = card
--				end
--            end
		end
	end
    if will_wait then
        return true, {code = 0}
    end
	self:deal_gang_balance(chair_id, self.game_all_info.last_out_chair, 3)
    table.insert(self.gang_cache, {chair_id, "suoGang"})
	self:delete_louHu_limit(0)
	self:draw_card(chair_id, -1)
	return true, {code = 0}
end

function game_sink:gang_mo_card(chair_id, card)
	syslog.info("chair_id:["..chair_id.."]杠:["..card.."]")
	if self.game_privite_info.canGang.chair_id ~= chair_id then
		syslog.err("chair_id:["..chair_id.."]杠:["..card.."] 失败")
		return true, {code = 30001}
	end
	if self:check_player_operation_need_wait(chair_id, "gang") then
		self:insert_player_operation(chair_id, "gang",card,  "gang_mo")
		self:delete_player_can_operation(chair_id, "canGang")
		return true, {code = 30003}  --TODO:code可能会改
	end
    self:init_can_operation()
	local user_card_info = self.players[chair_id].card_info
	local ret = majiang_opration:handle_gang_mo_card(user_card_info.handCards, user_card_info.stackCards, user_card_info.pengCards, user_card_info.gangCards, card, chair_id)
	self.game_record:record_game_action(chair_id, 4, card)
	self:delete_louHu_limit(0)
    local will_wait = false
    local out_chair = user_card_info.pengCards[card] or chair_id
	for k, v in pairs(self.players) do
		if true then
			local param = {chair_id = chair_id, card = card, gang_type = ret.gang_type, out_chair = out_chair}
			self:send_table_client(k, "game_gang_card", param)
            if k ~= chair_id and ret.gang_type == 1 then
                local ret = majiang_opration:other_self_gang(v.card_info.handCards, v.card_info.stackCards, card, k, self.louHuChair)
				if ret.canHu then
					will_wait = true
					syslog.debug("玩家:["..k.."]可操作:"..json.encode(ret))
					self:count_can_operation(ret, k, 3, chair_id,card)
					self:send_table_client(k, "game_have_operation", {operation = json.encode(ret)})
                    self.isqianggang = chair_id
                    self.qianggang_card = card
				end
            end
		end
	end
	if will_wait then
		return true, {code = 0}
	end
	--记录玩家杠牌次数
	if ret.gang_type == 1 then
--		self:add_balance_option(chair_id, "mingGang")
        table.insert(self.gang_cache, {chair_id, "mingGang"})
		majiang_opration:handle_mingGang_success(user_card_info.pengCards, user_card_info.gangCards, card)
	elseif ret.gang_type == 2 then
        table.insert(self.gang_cache, {chair_id, "anGang"})
--		self:add_balance_option(chair_id, "anGang")
	end
	self:deal_gang_balance(chair_id, 0, ret.gang_type)
	self:draw_card(chair_id, -1)
	return true, {code = 0}
end

function game_sink:deal_qianggang_cancel(chair_id, card)
	--记录玩家杠牌次数
    local user_card_info = self.players[chair_id].card_info
--	self:add_balance_option(chair_id, "mingGang")
    table.insert(self.gang_cache, {chair_id, "mingGang"})
	majiang_opration:handle_mingGang_success(user_card_info.pengCards, user_card_info.gangCards, card)
	self:deal_gang_balance(chair_id, 0, 1)
	self:draw_card(chair_id, -1)
end

function game_sink:chi_card(chair_id, card_table, card)
	local user_card_info = self.players[chair_id].card_info
	-- handCard,stackCard,chiCard, other_card, chicards
	local ret = majiang_opration:handle_chi_card(user_card_info.handCards, user_card_info.stackCards, user_card_info.chiCards,card_table ,card)
	self.game_record:record_game_action(chair_id, 5, card)
	for k, v in pairs(self.players) do
		local param = {chair_id = chair_id, card_table = ret.card_table, card = card}
		self:send_table_client(k, "game_chi_card", param)
	end
	self.game_all_info.cur_out_chair = chair_id
end

function game_sink:deal_gang_balance(gang_chair, lose_chair, gangType)
	local win_point = 0
	local GangType = ""
	if lose_chair == 0 then
		for k, v in pairs(self.players) do
			if k ~= gang_chair then
				--明杠每人1分
				if gangType == 1 then
					v.balance_info.gangPoint = v.balance_info.gangPoint -1
					win_point = win_point + 1
					GangType = "mingGang"
				--暗杠每人2分
				else
					v.balance_info.gangPoint = v.balance_info.gangPoint -2
					win_point = win_point + 2
					GangType = "anGang"
				end
			end
		end
	else
		if self.table_config.player_count == 2 then
			--两人玩法点杠1分
			local lose_player_balance_info = self.players[lose_chair].balance_info
			lose_player_balance_info.gangPoint = lose_player_balance_info.gangPoint -1
			win_point = win_point + 1
			self:add_gangType(lose_player_balance_info.gangType, "fangGang")
		else
			--点杠3分
			local lose_player_balance_info = self.players[lose_chair].balance_info
			lose_player_balance_info.gangPoint = lose_player_balance_info.gangPoint -3
			win_point = win_point + 3
			self:add_gangType(lose_player_balance_info.gangType, "fangGang")
		end
		GangType = "jieGang"
	end
	--杠的玩家获得的积分
	local win_player_balance_info = self.players[gang_chair].balance_info
	win_player_balance_info.gangPoint = win_player_balance_info.gangPoint + win_point
	self:add_gangType(win_player_balance_info.gangType,GangType)
end

function game_sink:add_gangType(gangTypeInfo, gangType)
	local gangNum = gangTypeInfo[gangType] or 0
	gangTypeInfo[gangType] = gangNum + 1
end

function game_sink:deal_hu_balance(win_chair, lose_chair, pbirdPoint, op)
	local win_point = 0
	local birdPoint = 0
	--自摸
	if lose_chair == 0 then
		for k, v in pairs(self.players) do
			if k ~= win_chair then
				if (win_chair == self.banker or k == self.banker) and self.game_config.idle then
					v.balance_info.huPoint = - (2 + 1)
				else
					v.balance_info.huPoint = - 2
				end
				v.balance_info.birdPoint = -pbirdPoint
				birdPoint = birdPoint + pbirdPoint
				win_point = win_point + (-v.balance_info.huPoint)
			end
		end
	elseif lose_chair ~= 0 then
		--接炮
		if op == 2 then
			local lose_point = 0
			if (self.banker == win_chair or self.banker == lose_chair) and self.game_config.idle then
				lose_point = -2
				win_point = 2
			else
				lose_point = -1
				win_point = 1
			end
			local game_balance_info = self.players[lose_chair].balance_info
			game_balance_info.huPoint = lose_point
			game_balance_info.birdPoint = -pbirdPoint
			game_balance_info.huType = 4
			birdPoint = birdPoint + pbirdPoint
		--抢杠
		elseif op == 3 then
			for k, v in pairs(self.players) do
				local lose_point = 0
				if k ~= win_chair then
					if (win_chair == self.banker or k == self.banker) and self.game_config.idle then
						win_point = win_point - 3
					else
						win_point = win_point - 2
					end
					birdPoint = birdPoint + pbirdPoint
				end
			end
			local game_balance_info = self.players[lose_chair].balance_info
			game_balance_info.huPoint = win_point
			game_balance_info.birdPoint = -birdPoint 
			game_balance_info.huType = 5
			win_point = -win_point
		end 
	end
	local win_balance_info = self.players[win_chair].balance_info
	win_balance_info.huPoint = win_point
	win_balance_info.birdPoint =  birdPoint
	win_balance_info.huType = op
end

local function checkHashongzhong(cards)
    for i , k in pairs(cards) do
        if k == 45 then
            return true
        end
    end
    return false
end

--胡牌
function game_sink:hu_card(chair_id, card)
	syslog.info("chair_id:["..chair_id.."]胡")
	if not self.is_playing then
		return false, {code = 30001}
	end
	--处理多胡的问题
	self.game_privite_info.Hu[chair_id] = true
	local huIndex = 0
    local hutype = 0
	-- self.game_privite_info.canHu = {{chair_id = 1, op = 1, lose_chair = 0, card = 11}}
	self.next_banker_chair = chair_id
	for k, v in pairs(self.game_privite_info.canHu) do
		--结算
		if v.chair_id == chair_id then
			self.game_record:record_game_action(chair_id, 6, card)
			self.is_Hu = true
			huIndex = k
			--胡的牌
			self.players[chair_id].card_info.huCard = v.card
			--接炮 or 抢杠胡 把胡的牌加到手牌里
			if v.lose_chair ~= 0 then
				table.insert(self.players[chair_id].card_info.handCards, v.card)
			end
			if not next(self.game_end_balance_info.birdCard) then
				local ret = majiang_opration:handle_find_bird(self.aftercards, checkHashongzhong(self.players[chair_id].card_info.handCards), v.op == 3)
				self.game_end_balance_info.birdCard = ret.birds
				self.game_end_balance_info.birdNum = ret.bird_num
			end
			self:deal_hu_balance(chair_id, v.lose_chair, self.game_end_balance_info.birdNum, v.op)
			table.insert(self.game_end_balance_info.hu_chairs, chair_id)
			if v.lose_chair ~= 0 then
				self.dianPao = self.dianPao + 1
				if self.dianPao > 1 or v.op == 3 then
					self.next_banker_chair = v.lose_chair
				else
					self.next_banker_chair = chair_id
				end
				self:add_balance_option(chair_id, "jiePao")
				self:add_balance_option(v.lose_chair, "dianPao")
                if v.op == 3 then
                    hutype = 3
                else
                    hutype = 2
                end
			elseif v.lose_chair == 0 then
				self:add_balance_option(chair_id, "ziMo")
                hutype = 1
			end
		end
	end
	if huIndex ~= 0 then
		local args = {}
		args.chair_id = chair_id
		args.card_table = self.players[chair_id].card_info.handCards
        args.hu_type = hutype
		self:send_table_client(0, "game_hu_card", args)
		table.remove(self.game_privite_info.canHu, huIndex)
		if not next(self.game_privite_info.canHu) then
			--游戏结束
			if self.dianPao > 1 then
				local huTmp = 0 
				local niaoTmp = 0
				for i , k in pairs(self.players) do
					if i ~= self.next_banker_chair then
						huTmp = k.balance_info.huPoint + huTmp
						niaoTmp = k.balance_info.birdPoint + niaoTmp
					end
				end
				self.players[self.next_banker_chair].balance_info.huPoint = -huTmp
				self.players[self.next_banker_chair].balance_info.birdPoint = -niaoTmp
			end
			self:game_end()
		end
	elseif huIndex == 0 then
		syslog.err("chair_id:["..chair_id.."]胡失败")
		return false, {code = 30002}
	end
	return true, {code = 0}
end


function game_sink:cancel_action(chair_id)
	syslog.info("chair_id:["..chair_id.."]取消")
	if not self.is_playing then
		return false, {code = 30001}
	end
	local can_cancel = false
	for k, v in  pairs(self.game_privite_info.canHu) do
		if v.chair_id == chair_id then
			can_cancel = true
            if self.turnCard ~= 0 then
                card = self.turnCard
                if not self.louHuChair[chair_id] then
                    self.louHuChair[chair_id] = {}
                end
			    self.louHuChair[chair_id][card] = true
            else
                self.turnLock = true
            end
			table.remove(self.game_privite_info.canHu, k)
		end
	end
	if self.game_privite_info.canPeng ~= chair_id and self.game_privite_info.canGang.chair_id ~= chair_id and self.game_privite_info.canChi ~= chair_id then
		if not can_cancel then
			return false, {code = 30002}
		end
	end
	self.game_record:record_game_action(chair_id, 7)
	self:delete_player_can_operation(chair_id)
	if self:check_can_operation_empty() then
		if not self.is_Hu then
			if not self:deal_player_operation() then
				if self.game_all_info.cur_out_chair ~= chair_id then
		 			self:draw_card(self:get_next_chair(self.game_all_info.last_out_chair), 0)
		 		end
		 	end
		else
			self:game_end()
		end
    elseif self.isqianggang ~= 0 and not next(self.game_privite_info.canHu) then
        self:deal_qianggang_cancel(self.isqianggang, self.qianggang_card)
        self.isqianggang = 0
        self.qianggang_card = 0
	end
	return true, {code = 0}
end

function game_sink:clear()
	--初始化玩家的牌&小局结算
	for k, v in pairs(self.players) do
		local card_info = table.clone(game_player_info.card_info)
		local balance_info = table.clone(game_player_info.balance_info)
		v.card_info = card_info
		v.balance_info = balance_info
	end
	self:init_game()
	self.game_record:init_record()
	--table.printT(self.game_end_balance_info)
end

--开始游戏
function game_sink:start_game()
    --清理复盘信息
    self.game_record:init_game_replay(self.table_config.player_count)
	self:init_game()
	self.is_playing = true
	self:send_table_client(0, "game_start_game", {time = os.time()})
--	self:shuffle_cards()
	self:deal_cards()
	self:draw_card(self:get_banker_chair(), 1)
	-- {chair_id = chair_id, op = op, lose_chair = lose_chair, card = card}
end

function game_sink:deal_gang_cache()
    for i , k in pairs(self.gang_cache) do
        self:add_balance_option(k[1], k[2])
    end
end

--游戏结束
function game_sink:game_end(args)
	syslog.info("game end")
--    if self.table_config.game_index == 8 then
--        self.interface.send_red_bag()
--    end
	self.is_playing = false
	-- self.game_end_balance_info
	self.game_end_balance_info.player_balance = {}
	self.game_end_balance_info.banker = self.banker or 1
	for k, v in pairs(self.players) do
		local tmp = {}
		tmp.huPoint = v.balance_info.huPoint
		tmp.birdPoint = v.balance_info.birdPoint
		tmp.birdCard = v.balance_info.birdCard or nil
		tmp.handCard = group_card(v.card_info)
		tmp.huCard = v.card_info.huCard
		tmp.huType = v.balance_info.huType
        if not next(self.game_privite_info.Hu) and self.game_config.huangzhuang then
            tmp.point = 1000 + self:add_balance_point(k, tmp.huPoint + tmp.birdPoint)
            tmp.gangType = json.encode({})
            tmp.gangPoint = 0
        else
            --处理杠缓存 （总结算用）
            self:deal_gang_cache()
            tmp.gangType = json.encode(v.balance_info.gangType)
            tmp.gangPoint = v.balance_info.gangPoint
            tmp.point = 1000 + self:add_balance_point(k, tmp.huPoint + tmp.birdPoint + tmp.gangPoint)
        end
		table.insert(self.game_end_balance_info.player_balance, tmp)
	end
	--显示中鸟的玩家
	if self.game_end_balance_info.birdNum > 0 then
		self.game_end_balance_info.birdPlayer = self.next_banker_chair
	end
	self.game_record:write_game_record()
	table.printR(self.game_end_balance_info)
	self:send_table_client(0, "game_game_end", self.game_end_balance_info)
    --self:send_table_client(0, "game_replay", {info= json.encode(self.game_record:get_game_replay())})
	self.interface.on_game_end(args)
	self.banker = self.next_banker_chair or 1
	self:clear()
end

--判断游戏结束标志
function game_sink:check_can_game_end(option_type, chair_id)
	if option_type == "draw_card" then
		if #self.aftercards == 0 then
			self.next_banker_chair = chair_id
			if self.table_config.game_type == 2 then
				return true
			end 
		end
	elseif option_type == "out_card" then
		if #self.aftercards == 0 then
            self.next_banker_chair = chair_id
			return true
		end
	end
	return false
end

--强制流局
function game_sink:force_exit(args)
	-- body
	self.is_playing = false
	self:game_end(args)
end

function game_sink:get_game_status()
	return self.is_playing
end

--玩家重登推送游戏信息
--[[
	1.玩家自己的牌的信息
	2.其他玩家出的牌（杠，碰，吃，出）的信息
	3.玩家待操作 game_privite_info
	4.当前出牌玩家
	5.上次出牌的玩家
]]
function game_sink:post_game_reconnect(chair_id)
	local ret = {}
	if not self.is_playing then
		return false, {code = -1}
	end
	ret.code = 0
	ret.playerCard = {}
	for k, v in pairs(self.players) do
		local tmp = {}
		tmp.outCards = v.card_info.outCards
		json.encode_sparse_array(true)   --處理稀疏矩陣的json
		tmp.pengCards = json.encode(v.card_info.pengCards)
		tmp.gangCards = json.encode(v.card_info.gangCards)
		tmp.chiCards = json.encode(v.card_info.chiCards)
		tmp.cardNum = #v.card_info.handCards
		if k == chair_id then
			tmp.handCards = v.card_info.handCards
		end
		tmp.point = v.base_info.point
		-- ret.playerCard[K] = json.encode(tmp)
		table.insert(ret.playerCard, tmp)
	end
	ret.canOperation = {}
--	local canOperation = {}
	for k, v in pairs(self.game_privite_info) do
		if k == "canHu" then
			for hk, hv in pairs(v) do
				if hv.chair_id == chair_id then
--					local tmp = {}
--					tmp[k] = true
--					table.insert(ret.canOperation,tmp)
                    ret.canOperation[k] = true
                    ret.canOperation.hutype = hv.op
                    ret.canOperation.hucard = hv.card
				end
			end
		elseif k == "canGang" then
			if v.chair_id == chair_id then
				local tmp = {}
				tmp[k] = v.card
				--table.insert(ret.canOperation,tmp)
                ret.canOperation[k] = v.card
			end
		elseif k == "canPeng" then
			if v == chair_id then
				local tmp = {}
				tmp[k] = true
--				table.insert(ret.canOperation,tmp)
                ret.canOperation.canPeng = self.game_privite_info.pengcard
			end
		end
	end
	-- ret.canOperation = canOperation
	ret.canOperation = json.encode(ret.canOperation)
	ret.curOutCHair = self.game_all_info.cur_out_chair 
	ret.lastOutChair = self.game_all_info.last_out_chair
	ret.lastOutCard = self.game_all_info.last_out_card
	ret.banker = self.banker or 1
	ret.leftNum = #self.aftercards
	ret.gameIndex = self.game_end_balance_info.game_index
	-- table.printT(ret)
	return true, ret
end

---------------------------------------------------------------
-----------------------all balance record----------------------
---------------------------------------------------------------

function game_sink:add_balance_option(chair_id, balance_type)
    local balance_result = self.players[chair_id].balance_result
    if balance_result then
        if balance_type == "ziMo" then
            balance_result.ziMo = balance_result.ziMo + 1
        elseif balance_type == "jiePao" then
            balance_result.jiePao = balance_result.jiePao + 1
        elseif balance_type == "dianPao" then
            balance_result.dianPao = balance_result.dianPao + 1
        elseif balance_type == "mingGang" then
            balance_result.mingGang = balance_result.mingGang + 1
        elseif balance_type == "anGang" then
            balance_result.anGang = balance_result.anGang + 1
        elseif balance_type == "suoGang" then
            balance_result.suoGang = balance_result.suoGang + 1
        end
    end
end

function game_sink:add_balance_point(chair_id, point)
	--保存玩家分数
    local base_info = self.players[chair_id].base_info
    base_info.point = base_info.point + point
    --保存总结算分数
    local balance_result = self.players[chair_id].balance_result
    self.game_record:add_player_balance(chair_id, point)
    if balance_result then
        balance_result.point = balance_result.point + point
        return balance_result.point
    end
    return 0
end
function game_sink:get_all_balance_result()
	local ret = {}
	local sclub = {}
	for k, v in pairs(self.players) do
		local tmp = v.balance_result
		tmp.uid = v.base_info.uid
		table.insert(sclub,{uid = v.base_info.uid, point = v.base_info.point,  ziMo = tmp.ziMo or 0 , dianPao = tmp.dianPao or 0 })
		table.insert(ret, tmp)
	end
	table.sort(sclub , function(a,b) 
							if a.point > b.point then
								return true
							elseif a.point == b.point  then
								if  a.ziMo > b.ziMo then
									return true
								elseif  a.ziMo == b.ziMo and a.dianPao < b.dianPao then
									return true
								else
									return false
								end
							else
								return false
							end
					   end
			  )

	-- table.printR(ret)
	return ret, sclub[1] and sclub[1].uid or nil
end

function game_sink:get_point(chair_id)
	return self.players[chair_id].base_info.point or 0
end

return game_sink

