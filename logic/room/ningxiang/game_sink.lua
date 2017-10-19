require "functions"
require "table_util"
local json = require "cjson"
-- local Scheduler = require "scheduler"
local majiang = require "majiang.ningxiang.cardDef"
local majiang_opration = require "majiang.ningxiang.majiang_opration"
local game_player_info = require "majiang.ningxiang.game_player_info"
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
--	if self.game_config.idle then
--		self.banker = 1
--	end
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
    self.isfirstOut = true
    self.isgangOut = false
    self.laizi = 0  -- 癞子
    self.laizipi = 0 --癞子皮
    self.onHaidi = 0 --海底状态
    self.haidiCount = 0 --海底问候的人数
    --杠牌的锁
    self.gangLock = {}
    self.gangCard = {}
    self.baoting = {}
    self.readybaoting = {}

	--游戏私有信息
	self.game_privite_info = {}
	self.game_privite_info.canHu = {}
	self.game_privite_info.Hu = {}
    self.game_privite_info.Hu_info = {}
	self.game_privite_info.canPeng = 0
    self.game_privite_info.pengcard = 0
	self.game_privite_info.canGang = {chair_id = 0}
    self.game_privite_info.canBu = {chair_id = 0}
	self.game_privite_info.canChi = 0
    self.game_privite_info.Chi_info = {}
	--游戏结束结算
	self.game_end_balance_info = {}
	self.game_end_balance_info.game_index = self.table_config.game_index
	self.game_end_balance_info.birdNum = 0
	self.game_end_balance_info.banker = 0
	self.game_end_balance_info.birdPlayer = 0
	self.game_end_balance_info.birdCard = {}
	self.game_end_balance_info.hu_chairs = {}
	self.game_end_balance_info.player_balance = {}
    --长沙麻将
    self.changsha_game_end_balance_info = {}
    self.changsha_game_end_balance_info.game_index = self.table_config.game_index
    self.changsha_game_end_balance_info.hu_chairs = {}
    self.changsha_game_end_balance_info.birdNum = 0
	self.changsha_game_end_balance_info.banker = 0
	self.changsha_game_end_balance_info.birdPlayer = 0
	self.changsha_game_end_balance_info.birdCard = {}
    self.changsha_game_end_balance_info.zhongbird = {}
    self.changsha_game_end_balance_info.changsha_player_balance = {}
    self.changsha_first_hu_lock = {}
    self.changsha_first_hu_tmp = {} --起手胡 缓存
    self.changsha_first_card = 0
    self.changsha_hu_chair_id = {}
    self.changsha_lose_chair_id = 0
    self.changsha_cache_card = 0
	--漏胡
	self.louHuChair = {}  
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
    self.turn = nil
    self.turnCard = nil
    self.turnLock = nil
    self.isqianggang = nil
    self.isfirstOut = nil
    self.changsha_first_hu_lock = nil
    self.changsha_first_card = nil
    self.changsha_hu_chair_id = nil
    self.changsha_lose_chair_id = nil
    self.gangCard = nil
    self.changsha_cache_card = nil
    self.laizi = nil  -- 癞子
    self.laizipi = nil --癞子皮
    self.onHaidi = nil --海底状态
    self.haidiCount = nil 
    self.qianggang_card = nil
end



--[[
	op: 1.自摸胡 2.接炮胡 3.抢杠胡
]]
function game_sink:count_can_operation(ret, chair_id, op, lose_chair,card, hucard)
	--漏胡该轮不能胡
--	if ret.canHu and not (self.louHuChair[chair_id] and self.louHuChair[chair_id][card]) then
    if ret.canHu then
		local param = {chair_id = chair_id, op = op, lose_chair = lose_chair, card = hucard}
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
    if ret.canBu then
		local tmp = {}
		tmp.chair_id = chair_id
		tmp.card = ret.canBu
		self.game_privite_info.canBu = tmp
    end
	if ret.canChi then
		self.game_privite_info.canChi = chair_id
        self.game_privite_info.Chi_info = ret.canChi
	end
end

function game_sink:delete_player_can_operation(chair_id)
	if self.game_privite_info.canPeng == chair_id then
		self.game_privite_info.canPeng = 0
        self.game_privite_info.pengcard = 0
	end
    if self.game_privite_info.canBu == chair_id then
        self.game_privite_info.canGang = {chair_id = 0}
    end
	if self.game_privite_info.canGang.chair_id == chair_id then
		self.game_privite_info.canGang = {chair_id = 0}
	end
	if self.game_privite_info.canChi == chair_id then
		self.game_privite_info.canChi = 0
        self.game_privite_info.Chi_info = {}
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
	["hu"] = 5,
    ["bu"] = 4
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
    if player_operation.op == 4 then
        flag = true
        if player_operation.gang_type == "bu_peng" then
            self:bu_peng_card(player_operation.chair_id, player_operation.card, true)
        elseif player_operation.gang_type == "bu_mo" then
            self:bu_peng_card(player_operation.chair_id, player_operation.card, true)
        end
	elseif player_operation.op == 3 then
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
		self:chi_card(player_operation.chair_id, player_operation.card, true)
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
	if option_type == "gang" or option_type == "bu" then
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
    self.game_privite_info.Chi_info = {}
    self.game_privite_info.Hu_info = {}
end

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
--		table.insert(ret, table.sort(v))
--        table.sort(v)
        table.insert(ret, v)
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
	if self.game_privite_info.canChi and self.game_privite_info.canChi ~= 0 and not next(self.game_privite_info.Hu) then
--		if player_operation_type == 1 then
			return false
--		end
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
    if not self.banker then
        self.banker = math.random(#self.players)
    end
	return self.banker 
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

--发牌
function game_sink:deal_cards()
	local player_cards = {}
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
	end
    if self.game_config.kaiwang then
        self:kaiwang_handler()
    end
end

function game_sink:deal_first_hu(chair_id, card)
    for i , k in pairs(self.players) do
        local ret
        if chair_id == i then
            local stackCards = table.clone(k.card_info.stackCards)
            if stackCards[card] then
                stackCards[card] = stackCards[card]+1
            else
                stackCards[card] = 1
            end
            local handCards = table.clone(k.card_info.handCards)
            table.insert(handCards, card)
            ret = majiang_opration:handle_first_hu(stackCards, handCards)
        else
            ret = majiang_opration:handle_first_hu(k.card_info.stackCards, k.card_info.handCards)
        end
        if next(ret) then
            self.changsha_first_hu_tmp[i] = ret
        end
    end
    return self.changsha_first_hu_tmp
end

function game_sink:first_hu_handler(chair_id, iscancel)
    self.changsha_first_hu_lock[chair_id] = nil
    if not iscancel then
        self:deal_hu_card(1, self.changsha_first_hu_tmp[chair_id], chair_id)
        self.players[chair_id].changsha_balance_info.first_hu = json.encode(self.changsha_first_hu_tmp[chair_id])
    end
    if not next(self.changsha_first_hu_lock) then
        local tmp = {}
        for i , k in pairs(self.changsha_first_hu_tmp) do
            local tmp1 = {}
            tmp1.huCard = self.players[i].card_info.handCards
            if i == self:get_banker_chair() then
                tmp1.huCard = table.clone(self.players[i].card_info.handCards)
                table.insert(tmp1.huCard, self.changsha_first_card)
            end
            tmp1.huType = {}
            for a, b in pairs(k) do
                table.insert(tmp1.huType, a)
            end
            tmp[string.format("%d",i)] = tmp1
        end
        if next(tmp) then
            self:send_table_client(0, "first_hu_info", {hu_info= json.encode(tmp)})
        end
        --报听
        if self:check_baoting() then
            return
        end
        self:operationHandler(self:get_banker_chair() ,self.changsha_first_card, nil , true)
    end
end


function game_sink:operationHandler(chair_id, card, card1, istipsClent, ishaidi)
    if istipsClent then
        self:send_table_client(chair_id, "changsha_start_out")
    end
    local user_card_info = self.players[chair_id].card_info
	self.game_all_info.cur_out_chair = chair_id
    local ret, hu_ret = majiang_opration:mo_card(user_card_info, card, chair_id, self.louHuChair, self.isfirstOut, self.baoting[chair_id],card1, self.gangLock[chair_id], self.laizi)
    if not self.game_privite_info.Hu_info then
        self.game_privite_info.Hu_info = {}
    end 
    self.game_privite_info.Hu_info[chair_id] = hu_ret
	self:send_table_client(0,"game_post_timeout_chair", {chair_id = chair_id})
	self.game_record:record_game_action(chair_id, 1, card, card1)
    self.turn = chair_id
	table.printForMajiang(chair_id, user_card_info.handCards)
    if card1 then
        if not next(ret) then
            self:out_card(chair_id, card, card1)
        else
            self.gangCard = {card, card1}
        end
    else
        majiang_opration:handle_mo_card(user_card_info.handCards, user_card_info.stackCards, card)
    end
	if next(ret) then
		--先推可以进行的操作 再推摸的牌
		syslog.debug("玩家:["..chair_id.."]可操作:xxxxx"..json.encode(ret))
		self:count_can_operation(ret, chair_id, 1, 0, card, ret.hucard)
		self:send_table_client(chair_id, "game_have_operation", {operation = json.encode(ret)})
	else
		if self:check_can_game_end("draw_card", chair_id) then
		--结束游戏
			self:game_end()
		end
	end
    if self.gangLock[chair_id] then
        self.changsha_cache_card = card
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
    local card1 
	if last == -1 then
		--杠
        card = self.aftercards[1]
		table.remove(self.aftercards, 1)
        card1 = self.aftercards[1]
		table.remove(self.aftercards, 1)
        syslog.info("chair_id:["..chair_id.."]摸牌["..card.."]"..card1)
        self:send_table_client(0, "game_out_card", {chair_id = chair_id, card = card, addtion_bit =1, addition_card= {card1}})
        local user_card_info = self.players[chair_id].card_info
        table.insert(user_card_info.outCards,card)
        table.insert(user_card_info.outCards,card1)
        self.gangLock[chair_id] = true
	elseif last == -2 then
		card = self.aftercards[1]
		table.remove(self.aftercards, 1)
        syslog.info("chair_id:["..chair_id.."]摸牌["..card.."]")
	    for k, v in pairs(self.players) do
		    if k ~= chair_id then
			    self:send_table_client(k, "game_draw_card", {chair_id = chair_id,card = 0})
		    end
	    end
        self:send_table_client(chair_id, "game_draw_card", {chair_id = chair_id,card = card})
    else
        if #self.aftercards == 1 then
            self:deal_haidi(chair_id)
            return
        end
		card = self.aftercards[1]
		table.remove(self.aftercards, 1)
        syslog.info("chair_id:["..chair_id.."]摸牌["..card.."]")
	    for k, v in pairs(self.players) do
		    if k ~= chair_id then
			    self:send_table_client(k, "game_draw_card", {chair_id = chair_id,card = 0})
		    end
	    end
        self:send_table_client(chair_id, "game_draw_card", {chair_id = chair_id,card = card})
	end
    self.turnCard = 0
    --起手胡
    if last == 1 then
        self.changsha_first_card = card
        if self.game_config.firstHu then
            local needWait = false
            local ret = self:deal_first_hu(chair_id, card)
            for i, k in pairs(ret) do
                if next(k) then
                    needWait = true
                    local tab = {}
                    tab.canFirstHu = true
                    self:send_table_client(i, "game_have_operation", {operation = json.encode(tab)})
                    self.changsha_first_hu_lock[i] = true
                end
            end 
            if needWait then
                self.changsha_first_card = card
                return
            end

        end
        --报听
        if self:check_baoting() then
            return 
        end
    end
    self:operationHandler(chair_id, card, card1, last == 1)
end

function game_sink:deal_haidi(chair_id)
    self.haidiCount = self.haidiCount + 1
    if self.haidiCount > #self.players then
        self:game_end()
        return
    end
    self.onHaidi = chair_id
    local tab = {}
    tab.canHaidi = true
    self:send_table_client(chair_id, "game_have_operation", {operation = json.encode(tab)})
    self:send_table_client(0,"game_post_timeout_chair", {chair_id = chair_id})
end

function game_sink:deal_haidi_card(chair_id)
--要海底没胡就是他下局庄家
    self.next_banker_chair = chair_id
    local card = table.remove(self.aftercards, 1)
    syslog.info("翻海底玩家["..chair_id.."]牌"..card)
    self:send_table_client(0, "game_open_haidi", {card = card})
    if not self.game_privite_info.Hu_info then
        self.game_privite_info.Hu_info = {}
    end 
    local cardInfo = self.players[chair_id].card_info
    local ret, hu_ret = majiang_opration:mo_card(cardInfo, card, chair_id, self.louHuChair, false, self.baoting[chair_id], nil, false, self.laizi, chair_id)
    local has_hu = false
    if not next(ret) then
        for i , k in pairs(self.players) do
            if i ~= chair_id then
                cardInfo = self.players[i].card_info
                local ret1, hu_ret1 = majiang_opration:mo_card(cardInfo, card, i, self.louHuChair, false, self.baoting[i],nil, false, self.laizi, chair_id)
                if next(ret1) then
                	syslog.debug("玩家:["..i.."]可操作:xxxxx"..json.encode(ret1))
		            self:count_can_operation(ret1, i, 1, chair_id, card, ret1.hucard)
		            self:send_table_client(i, "game_have_operation", {operation = json.encode(ret1)})
                    self.game_privite_info.Hu_info[i] = hu_ret1
                    self.game_record:record_game_action(i, 1, card)
                    has_hu = true
                end
            end
        end
    else
        has_hu = true
        syslog.debug("玩家:["..chair_id.."]可操作:xxxxx"..json.encode(ret))
		self:count_can_operation(ret, chair_id, 1, 0, card, ret.hucard)
		self:send_table_client(chair_id, "game_have_operation", {operation = json.encode(ret)})
        self.game_privite_info.Hu_info[chair_id] = hu_ret
        self.game_record:record_game_action(chair_id, 1, card)
    end
    if not has_hu then
        self:game_end()
    end
end

function game_sink:check_baoting()
    local need_wait = false
    for i , k in pairs(self.players) do
        if i ~= self:get_banker_chair() then
            if majiang_opration:check_ting_card(k.card_info, self.laizi) then
                self.readybaoting[i] = true
                local ret = {}
                ret.canTing = true
                self:send_table_client(i, "game_have_operation", {operation = json.encode(ret)})
                syslog.debug("玩家:["..i.."]可操作:xxxxx"..json.encode(ret))
                need_wait = true
            end
        end
    end
    return need_wait
end

function game_sink:deal_baoting(chair_id)
    if self.readybaoting[chair_id] then
        self.baoting[chair_id] = true
        self.readybaoting[chair_id] = nil
        self.gangLock[chair_id] = true
        syslog.err("玩家["..chair_id.."]报听成功")
        if not next(self.readybaoting) then
            local tab = {}
            for i, k in pairs(self.baoting) do
                table.insert(tab, i)
            end 
            self:send_table_client(0, "game_ting_card", {chair_id = tab})
            self:operationHandler(self:get_banker_chair() ,self.changsha_first_card, nil , true)
        end
        return true, {code = 0}
    end
    syslog.err("玩家["..chair_id.."]报听失败")
    return false, {code = 30002}
end

--出牌
function game_sink:out_card(chair_id, card, card1)
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
    if card1 then
        syslog.info("chair_id:["..chair_id.."]出杠牌:["..card1.."]")
    end
	if not self.is_playing then
		return false, {code = 30001}
	end
    --非法操作
--    if self.turn ~= chair_id or next(self.game_privite_info.canHu) or next(self.game_privite_info.canGang) or self.game_privite_info.canPeng ~= 0 then
    if self.turn ~= chair_id or not self:check_player_chi_need_wait(chair_id) or self.game_privite_info.canChi ~= 0 then
        syslog.err("chair_id:["..chair_id.."]非法出牌:["..card.."]turn "..self.turn)
        return false, {code = 30005}
    end
    --杠牌后不能换牌
    if self.gangLock[chair_id] and self.changsha_cache_card ~= 0 then
        card = self.changsha_cache_card
    end
    self.turnCard = card
	local user_hand_card_info = self.players[chair_id].card_info.handCards
	local can_out_card = false
    if not card1 then
	    for k, v in pairs(user_hand_card_info) do
		    if card == v then
			    can_out_card = true
			    break
		    end
	    end
	    if not can_out_card then
            syslog.err("chair_id:["..chair_id.."]非法出牌:["..card.."]没有这个牌")
		    return true, {code = -2}
	    end
    end
	local will_wait = false
	local user_card_info = self.players[chair_id].card_info
    if not card1 then
        self:send_table_client(0, "game_out_card", {chair_id = chair_id, card = card})
        majiang_opration:handle_out_card(user_card_info.handCards,user_card_info.stackCards, user_card_info.outCards,card, card1)
    end
    --牌的数量检测
    local _, tmp = math.modf((#user_hand_card_info-1)/3)
    if tmp ~= 0 then
       syslog.err("error:mahjong count:"..#user_hand_card_info)
    end
	self.game_record:record_game_action(chair_id, 2, card, card1)
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
    if not card1 then
	    for k, v in pairs(self.players) do
		    if k ~= chair_id then
			    table.printForMajiang(k, v.card_info.handCards)
    --			local ret = majiang_opration:other_out_card(v.card_info.handCards, v.card_info.stackCards,card, k, self.louHuChair)
                local ret, hu_ret = majiang_opration:other_out_card(v.card_info, card, k, self.louHuChair, self.isfirstOut, self.baoting[k],self:get_next_chair(chair_id)== k,card1, self.gangLock[k], self.laizi)
                if not self.game_privite_info.Hu_info then
                    self.game_privite_info.Hu_info = {}
                end
                self.game_privite_info.Hu_info[k] = hu_ret
			    if next(ret) then
				    self:count_can_operation(ret, k, 2, chair_id,card, ret.hucard)
				    will_wait = true
				    --TODO:推送给玩家可以进行的操作
				    syslog.debug("玩家:["..k.."]可操作:"..json.encode(ret))	
				    self:send_table_client(k, "game_have_operation", {operation = json.encode(ret)})
			    end
		    end
	    end
    else
        for k, v in pairs(self.players) do
            if k ~= chair_id then 
                table.printForMajiang(k, v.card_info.handCards)
                local ret, hu_ret = majiang_opration:other_out_card(v.card_info, card, k, self.louHuChair, self.isfirstOut, self.baoting[k],self:get_next_chair(chair_id)== k, card1, self.gangLock[k], self.laizi)
                if not self.game_privite_info.Hu_info then
                    self.game_privite_info.Hu_info = {}
                end
                self.game_privite_info.Hu_info[k] = hu_ret
			    if next(ret) then
				    self:count_can_operation(ret, k, 2, chair_id,card, ret.hucard)
				    will_wait = true
				    --TODO:推送给玩家可以进行的操作
				    syslog.debug("玩家:["..k.."]可操作:"..json.encode(ret))	
				    self:send_table_client(k, "game_have_operation", {operation = json.encode(ret)})
			    end
            end
        end
    end
    self.isfirstOut = false
    if not card1 then
        self.isgangOut = false
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
    local last_cardsTmp = table.clone(out_user_card_info)
    majiang_opration:handle_mo_card(last_cardsTmp.handCards, last_cardsTmp.stackCards, card)
    self.game_record:add_game_replay(chair_id, self.game_all_info.last_out_chair, card, group_card(last_cardsTmp,true))
	for k, v in pairs(self.players) do
		-- if k ~= chair_id then
			self:send_table_client(k, "game_peng_card", {chair_id = chair_id, card = card, out_chair = self.game_all_info.last_out_chair})
		-- end
	end
	self:delete_louHu_limit(chair_id)
	self.game_all_info.cur_out_chair = chair_id
	self:send_table_client(0,"game_post_timeout_chair", {chair_id = chair_id})
    self:init_player_operation()
    self.turn = chair_id
    local ret = majiang_opration:check_gang_after(user_card_info, self.laizi)
    if next(ret) then
        self:count_can_operation(ret, chair_id, 1, 0)
		self:send_table_client(chair_id, "game_have_operation", {operation = json.encode(ret)})
    end
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
    self.isgangOut = true
	if gang_type == 1 then
        --非法操作
        if self.turn ~= chair_id then
            return false, {code = 30005}
        end
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
    self:delete_louHu_limit(chair_id)
--    local will_wait = false
	for k, v in pairs(self.players) do
		if true then
			local param = {chair_id = chair_id, card = card, gang_type = 3, out_chair = self.game_all_info.last_out_chair}
			self:send_table_client(k, "game_gang_card",param)
		end
--        if k ~= chair_id then
----            local ret = majiang_opration:other_out_card(v.card_info.handCards, v.card_info.stackCards,card, k, self.louHuChair)
--            --v.card_info, card, k, self.louHuChair
--            local ret = majiang_opration:other_self_gang(v.card_info, card, k, self.louHuChair, self.laizi, self.baoting[k])
--            if next(ret) then
--			    self:count_can_operation(ret, k, 2, chair_id,card, ret.hucard)
--			    will_wait = true
--			    --TODO:推送给玩家可以进行的操作
--			    syslog.debug("玩家:["..k.."]可操作:"..json.encode(ret))	
--			    self:send_table_client(k, "game_have_operation", {operation = json.encode(ret)})
--                self.isqianggang = chair_id
--		    end
--        end
	end
--    if will_wait then
--        return ture, {code= 0}
--    end

--	self:deal_gang_balance(chair_id, self.game_all_info.last_out_chair, 3)
--	self:add_balance_option(chair_id, "suoGang")
    self:init_player_operation()
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
	local will_wait = false
	local user_card_info = self.players[chair_id].card_info
	local ret = majiang_opration:handle_gang_mo_card(user_card_info.handCards, user_card_info.stackCards, user_card_info.pengCards, user_card_info.gangCards, card, chair_id)
	self.game_record:record_game_action(chair_id, 4, card)
	self:delete_louHu_limit(chair_id)
	local out_chair = user_card_info.pengCards[card] or chair_id
	for k, v in pairs(self.players) do
		if true then
			local param = {chair_id = chair_id, card = card, gang_type = ret.gang_type, out_chair = out_chair}
			self:send_table_client(k, "game_gang_card", param)
            if k ~= chair_id and ret.gang_type == 1 then
                local ret, hu_ret = majiang_opration:other_self_gang(v.card_info, card, k, self.louHuChair, self.laizi, self.baoting[k])
				if ret.canHu then
					will_wait = true
					syslog.debug("玩家:["..k.."]可操作:"..json.encode(ret))
					self:count_can_operation(ret, k, 3, chair_id, nil, {card})
                    self.game_privite_info.Hu_info[k] = hu_ret
					self:send_table_client(k, "game_have_operation", {operation = json.encode(ret)})
                    self.isqianggang = chair_id
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
		majiang_opration:handle_mingGang_success(user_card_info.pengCards, user_card_info.gangCards, card)
	elseif ret.gang_type == 2 then
--		self:add_balance_option(chair_id, "anGang")
	end
--	self:deal_gang_balance(chair_id, 0, ret.gang_type)
    self:init_player_operation()
	self:draw_card(chair_id, -1)

	return true, {code = 0}
end

function game_sink:deal_qianggang_cancel(chair_id, card)
	--记录玩家杠牌次数
    local user_card_info = self.players[chair_id].card_info
--	self:add_balance_option(chair_id, "mingGang")
	majiang_opration:handle_mingGang_success(user_card_info.pengCards, user_card_info.gangCards, card)
--	self:deal_gang_balance(chair_id, 0, 1)
    self:init_player_operation()
	self:draw_card(chair_id, -1)
end

function game_sink:bu_peng_card(chair_id, card, iscallback)
    syslog.info("chair_id:["..chair_id.."]碰补张:["..card.."]")
	if self.game_privite_info.canBu.chair_id ~= chair_id and not iscallback then
		syslog.err("chair_id:["..chair_id.."]补张:["..card.."] 失败")
		return true, {code = -1}
	end
	if self:check_player_operation_need_wait(chair_id, "bu") then
		self:insert_player_operation(chair_id, "bu", card, "bu_peng")
		self:delete_player_can_operation(chair_id, "canBu")
		return true, {code = 30003}  --TODO:code可能会改
	end
	local user_card_info = self.players[chair_id].card_info
	majiang_opration:handle_gang_peng_card(user_card_info.handCards, user_card_info.stackCards, user_card_info.gangCards, card, self.game_all_info.last_out_chair)
	--把牌从出过的牌中拿走
	local out_user_card_info = self.players[self.game_all_info.last_out_chair].card_info
	majiang_opration:handle_kick_out_card(out_user_card_info.outCards, card)
	self.game_record:record_game_action(chair_id, 8, card)
    local last_cardsTmp = table.clone(out_user_card_info)
    majiang_opration:handle_mo_card(last_cardsTmp.handCards, last_cardsTmp.stackCards, card)
    self.game_record:add_game_replay(chair_id, self.game_all_info.last_out_chair, card, group_card(last_cardsTmp,true))
	for k, v in pairs(self.players) do
		if true then
			local param = {chair_id = chair_id, card = card, bu_type = 3, out_chair = self.game_all_info.last_out_chair}
			self:send_table_client(k, "game_bu_card",param)
		end
	end
	self:delete_louHu_limit(chair_id)
    self:init_player_operation()
	self:draw_card(chair_id, -2)
    local ret = majiang_opration:check_gang_after(user_card_info, self.laizi)
    if next(ret) then
        self:count_can_operation(ret, chair_id, 1, 0)
		self:send_table_client(chair_id, "game_have_operation", {operation = json.encode(ret)})
    end
	return true, {code = 0}
end

function game_sink:bu_mo_card(chair_id, card)
	syslog.info("chair_id:["..chair_id.."]摸补张:["..card.."]")
	if self.game_privite_info.canBu.chair_id ~= chair_id then
		syslog.err("chair_id:["..chair_id.."]补张:["..card.."] 失败")
		return true, {code = 30001}
	end
	if self:check_player_operation_need_wait(chair_id, "bu") then
		self:insert_player_operation(chair_id, "bu",card,  "bu_mo")
		self:delete_player_can_operation(chair_id, "canBu")
		return true, {code = 30003}  --TODO:code可能会改
	end
--	local will_wait = false
	local user_card_info = self.players[chair_id].card_info
	local ret = majiang_opration:handle_gang_mo_card(user_card_info.handCards, user_card_info.stackCards, user_card_info.pengCards, user_card_info.gangCards, card,chair_id)
	local out_chair = user_card_info.pengCards[card] or chair_id
	for k, v in pairs(self.players) do
		local param = {chair_id = chair_id, card = card, bu_type = ret.gang_type, out_chair = out_chair}
		self:send_table_client(k, "game_bu_card", param)
--        local ret_2, hu_ret = majiang_opration:other_self_gang(v.card_info, card, k, self.louHuChair)
--		if ret_2.canHu then
--			will_wait = true
--			syslog.debug("玩家:["..k.."]可操作:"..json.encode(ret_2))
--			self:count_can_operation(ret_2, k, 3, chair_id,card)
--			self:send_table_client(k, "game_have_operation", {operation = json.encode(ret_2)})
--            self.isqianggang = chair_id
--		end
	end
--	if will_wait then
--		return true, {code = 0}
--	end
    if ret.gang_type == 1 then
        majiang_opration:handle_mingGang_success(user_card_info.pengCards, user_card_info.gangCards, card)
    end
    self.game_record:record_game_action(chair_id, 8, card)
	self:delete_louHu_limit(chair_id)
    self:init_player_operation()
	self:draw_card(chair_id, -2)
    local ret = majiang_opration:check_gang_after(user_card_info, self.laizi)
    if next(ret) then
        self:count_can_operation(ret, chair_id, 1, 0)
		self:send_table_client(chair_id, "game_have_operation", {operation = json.encode(ret)})
    end
	return true, {code = 0}
end


function game_sink:bu_card(chair_id, card)
    syslog.info("chair_id:["..chair_id.."]补张:["..card.."]")
	if not self.is_playing then
		return false, {code = 30001}
	end
	if self.game_privite_info.canBu.chair_id ~= chair_id then
		return true, {code = 30002}
	end
	local user_card_info = self.players[chair_id].card_info
	local gang_type = majiang_opration:get_gang_type(user_card_info.handCards, user_card_info.stackCards, user_card_info.pengCards, card)
    self.turnCard = card
	if gang_type == 1 then
        --非法操作
        if self.turn ~= chair_id then
            return false, {code = 30005}
        end
--		return self:gang_mo_card(chair_id, card)
        return self:bu_mo_card(chair_id, card)
	elseif gang_type == 2 then
--		return self:gang_peng_card(chair_id, card)
        return self:bu_peng_card(chair_id, card)
	else
		return false, {code = 30002}
	end
end

function game_sink:chi_card(chair_id, card_table, iscallBack)
    syslog.info("chair_id:["..chair_id.."]吃:[]")
	if not self.is_playing then
        syslog.err("chair_id:["..chair_id.."]吃1:[] 失败")
        table.printR(card_table)
		return false, {code = 30001}
	end
	if self.game_privite_info.canChi ~= chair_id and not iscallBack then
        syslog.err("chair_id:["..chair_id.."]吃2:[] 失败")
        table.printR(card_table)
		return true, {code = 30002}
	end
	if self.game_all_info.last_out_card ~= card_table.chi_card then 
		syslog.err("chair_id:["..chair_id.."]吃的信息有问题")
		table.printR(card_table)
		return false, {code = 30002}
	end
    if self:check_player_operation_need_wait(chair_id, "chi") then
		self:insert_player_operation(chair_id, "chi", card_table)
		self:delete_player_can_operation(chair_id, "canChi")
		return true, {code = 30003}  --TODO:code可能会改
	end
    local user_card_info = self.players[chair_id].card_info
	local ret = majiang_opration:handle_chi_card(user_card_info.handCards, user_card_info.stackCards, user_card_info.chiCards,card_table)
    local chi_card_tmp = card_table.will_chi_card[1].."-"..card_table.will_chi_card[2]
	self.game_record:record_game_action(chair_id, 5, card_table.chi_card, chi_card_tmp)
    local out_user_card_info = self.players[self.game_all_info.last_out_chair].card_info
    local last_cardsTmp = table.clone(out_user_card_info)
    majiang_opration:handle_mo_card(last_cardsTmp.handCards, last_cardsTmp.stackCards, card_table.chi_card)
    self.game_record:add_game_replay(chair_id, self.game_all_info.last_out_chair, card, group_card(last_cardsTmp,true))
	for k, v in pairs(self.players) do
		local param = {chair_id = chair_id, card_table = card_table.will_chi_card, card = card_table.chi_card}
		self:send_table_client(k, "game_chi_card", param)
	end
	self.game_all_info.cur_out_chair = chair_id
	self:delete_louHu_limit(chair_id)
	self:send_table_client(0,"game_post_timeout_chair", {chair_id = chair_id})
    majiang_opration:handle_kick_out_card(out_user_card_info.outCards, self.game_all_info.last_out_card)
    self.turn = chair_id
    self:init_player_operation()
    self:delete_player_can_operation(chair_id, "canChi")
    local ret = majiang_opration:check_gang_after(user_card_info, self.laizi)
    if next(ret) then
        self:count_can_operation(ret, chair_id, 1, 0)
		self:send_table_client(chair_id, "game_have_operation", {operation = json.encode(ret)})
    end
	return true , {code = 0}
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
				if (win_chair == self.banker or k == self.banker) then
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
			if (self.banker == win_chair or self.banker == lose_chair) then
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
					if (win_chair == self.banker or k == self.banker) then
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

local spacetransbirdTab = {
    [1] = 1,
    [2] = 2,
    [3] = 3,
    [4] = 4,
    [5] = 1,
    [6] = 2,
    [7] = 3,
    [8] = 4,
    [9] = 1,
}

local function getiszhongBird(birds)
    local tab = {}
    for i , k in pairs(birds) do 
        local _, index = math.modf(k/10)
        local num = math.floor(index*10+0.5)
        if not tab[spacetransbirdTab[num]] then
            tab[spacetransbirdTab[num]] = {}
        end
        table.insert(tab[spacetransbirdTab[num]], k)
    end
    return tab
end

--hu_type 1 起手胡 2 胡     info内容    chair_id胡的人 ， chair_id1点的人（自摸就没有）
function game_sink:deal_hu_card(hu_type, info, chair_id, chair_id1)
    local smallzimo = 2
    local smalldianpao = 1
    local bigzimo = self.game_config.bighu or 6
    local bigdianpao = self.game_config.bighu or 6
    local Count = #self.players - 1
    local player = self.players[chair_id]
    local hu_count = 0
  --  local bird_point = self.game_config.bird_point or 1
    if hu_type == 1 then
        syslog.debug("first hu player:   "..chair_id)
        for i , k in pairs(info) do
            if i == "bigfour" then
                hu_count = hu_count + #k
            else
                hu_count = hu_count + 1
            end
        end
        local point = hu_count*smallzimo
        for i , k in pairs(self.players) do
            if i ~= chair_id then
                k.changsha_balance_info.getpoint = k.changsha_balance_info.getpoint - point
            else
                k.changsha_balance_info.getpoint = k.changsha_balance_info.getpoint + point*Count
            end
        end
        player.changsha_balance_info.first_hu = info
        self:add_balance_option(chair_id, "xiaohuzimo", hu_count)
    elseif hu_type == 2 then
        syslog.debug("hu player:   "..chair_id)
        local point = 0
        local player1
        local hucount = 0
        if info.pinghu then
            if chair_id1 then
                point = smalldianpao
            else
                point = smallzimo
            end
        else
            for i , k in pairs(info) do
                hucount = hucount + 1
                if i == "shuang_hao_seven_hu" then
                    hu_count = hu_count + 3*k
                elseif i == "hao_seven_hu" then
                    hu_count = hu_count + 2*k
                else
                    hu_count = hu_count + k
                end
            end
            point = bigzimo*hu_count
        end
        if chair_id1 then
            player1 = self.players[chair_id1]
            local bank_point = 0
            if self.banker == chair_id1 or self.banker == chair_id then
                bank_point = 1
            end
            player1.changsha_balance_info.getpoint = player1.changsha_balance_info.getpoint - point - bank_point
            player.changsha_balance_info.getpoint = player.changsha_balance_info.getpoint + point + bank_point
        else
            local tmpPoint = 0
            for i , k in pairs(self.players) do
                if i ~= chair_id then 
                    if  self.banker == i or self.banker == chair_id then
                        k.changsha_balance_info.getpoint = k.changsha_balance_info.getpoint - point - 1
                    else
                        k.changsha_balance_info.getpoint = k.changsha_balance_info.getpoint - point 
                    end
                end
            end
            if self.banker == chair_id then
                player.changsha_balance_info.getpoint = player.changsha_balance_info.getpoint + point*Count + Count
            else
                player.changsha_balance_info.getpoint = player.changsha_balance_info.getpoint + point*Count + 1
            end
        end
        player.changsha_balance_info.hu_info = json.encode(info)
        if info.pinghu then 
            if chair_id1 then 
                self:add_balance_option(chair_id1, "xiaohudianpao", 1)
                self:add_balance_option(chair_id, "xiaohujiepao", 1)
                player.changsha_balance_info.huType = 3
                if player1.changsha_balance_info.huType ~= 4 then
                    player1.changsha_balance_info.huType = 2
                end
            else
                self:add_balance_option(chair_id, "xiaohuzimo", 1)
                player.changsha_balance_info.huType = 1
            end 
        else
            if chair_id1 then
                self:add_balance_option(chair_id1, "dahudianpao", hucount)
                self:add_balance_option(chair_id, "dahujiepao", hucount)
                player.changsha_balance_info.huType = 5
                player1.changsha_balance_info.huType = 4
            else
                self:add_balance_option(chair_id, "dahuzimo", hucount)
                player.changsha_balance_info.huType = 1
            end
        end
    end
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
	self.next_banker_chair = chair_id
    --长沙最后算鸟用的
    table.insert(self.changsha_hu_chair_id, chair_id)
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
                if #v.card == 1 then 
				    table.insert(self.players[chair_id].card_info.handCards, v.card[1])
                end
			end
			if not next(self.changsha_game_end_balance_info.birdCard) then
				local ret = majiang_opration:handle_find_bird(self.aftercards)
				self.changsha_game_end_balance_info.birdCard = ret.birds
			end
			table.insert(self.changsha_game_end_balance_info.hu_chairs, chair_id)
            self.changsha_lose_chair_id = v.lose_chair
			if v.lose_chair ~= 0 then
				self.dianPao = self.dianPao + 1
				if self.dianPao > 1 or v.op == 3 then
					self.next_banker_chair = v.lose_chair
				else
					self.next_banker_chair = chair_id
				end
                self:deal_hu_card(2, self.game_privite_info.Hu_info[chair_id], chair_id, v.lose_chair)
                if v.op == 3 then
                    hutype = 3
                else
                    hutype = 2
                end
			elseif v.lose_chair == 0 then
                self:deal_hu_card(2, self.game_privite_info.Hu_info[chair_id], chair_id)
                hutype = 1
			end
		end
	end
	-- self:init_player_operation()
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
			self:game_end(nil, hutype==1)
		end
	elseif huIndex == 0 then
		syslog.err("chair_id:["..chair_id.."]胡失败")
		return false, {code = 30002}
	end
	return true, {code = 0}
end


function game_sink:cancel_action(chair_id)
	syslog.info("chair_id:["..chair_id.."]取消")
    --不要海底
    if self.onHaidi == chair_id then
        local id = chair_id + 1 
        if id > #self.players then
            id = 1
        end
        self:deal_haidi(id)
        return true , {code = 0}
    end
    --不要报听
    if self.readybaoting[chair_id] then
        self.readybaoting[chair_id] = nil
        if not next(self.readybaoting) then
            local tab = {}
            for i, k in pairs(self.baoting) do
                table.insert(tab, i)
            end 
            self:send_table_client(0, "game_ting_card", {chair_id = tab})
            self:operationHandler(self:get_banker_chair() ,self.changsha_first_card, nil , true)
        end
        return true, {code = 0}
    end
    local hu_card = 0
	if not self.is_playing then
		return false, {code = 30001}
	end
    if next(self.changsha_first_hu_lock) then
        self.changsha_first_hu_tmp[chair_id] = nil
        self:first_hu_handler(chair_id, true)
        return true, {code = 0}
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
            hu_card = v.card[1]
			table.remove(self.game_privite_info.canHu, k)
            table.remove(self.game_privite_info.Hu_info, k)
		end
	end
	if self.game_privite_info.canPeng ~= chair_id and self.game_privite_info.canGang.chair_id ~= chair_id and self.game_privite_info.canChi ~= chair_id then
		if not can_cancel then
			return false, {code = 30002}
		end
	end
	self.game_record:record_game_action(chair_id, 7)
	self:delete_player_can_operation(chair_id)
	if self:check_can_operation_empty() and self.isqianggang == 0 then
		if not self.is_Hu then
			if not self:deal_player_operation() then
				if self.game_all_info.cur_out_chair ~= chair_id then
		 			self:draw_card(self:get_next_chair(self.game_all_info.last_out_chair), 0)
                elseif self.gangLock[chair_id] then
                    if next(self.gangCard) then
                        self:out_card(chair_id, self.gangCard[1], self.gangCard[2])
                        self.gangCard = {}
                        return true, {code = 0}
                    else
                        self:out_card(chair_id, hu_card)
                    end
		 		end
		 	end
		else
			self:game_end()
		end
    elseif self.isqianggang ~= 0 and not next(self.game_privite_info.canHu) then
--        self:draw_card(self.isqianggang, -1)
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
        local changsha_balance_info = table.clone(game_player_info.changsha_balance_info)
		v.card_info = card_info
		v.balance_info = balance_info
        v.changsha_balance_info = table.clone(game_player_info.changsha_balance_info)
	end
	self:init_game()
	self.game_record:init_record()
	--table.printT(self.game_end_balance_info)
end

--开始游戏
function game_sink:start_game()
    self.game_record:init_game_replay(self.table_config.player_count)
	self:init_game()
	self.is_playing = true
	self:send_table_client(0, "game_start_game", {time = os.time()})
--	self:shuffle_cards()
	self:deal_cards()
	self:draw_card(self:get_banker_chair(), 1)
	-- {chair_id = chair_id, op = op, lose_chair = lose_chair, card = card}
end

--确认癞子 癞子皮
function game_sink:kaiwang_handler()
    local card = majiang:getNingxianglaizi()
	self.laizipi = card
	local card1
	if  math.floor((card+1)/10) ~= math.floor(card/10) then
		card1 = card-8
		self.laizi = card1
	else
		card1 = card+1
		self.laizi = card1
	end
	syslog.info("癞子为"..card1.."癞子皮是"..card)
	self:send_table_client(0, "game_open_laizi", {laizipi = card, laizi = card1})
end

function game_sink:deal_game_end_bird(iszimo)
    if not next(self.changsha_game_end_balance_info.birdCard) then
        return
    end
    local bird_point = self.game_config.bird_point or 1
    local birdTmp = getiszhongBird(self.changsha_game_end_balance_info.birdCard)
    if iszimo then
        local tmpPoint = 0
        if self.table_config.player_count == 3 then
            for i ,k in pairs(self.changsha_game_end_balance_info.birdCard) do
                if majiang_opration:check_is_bird(k) then
                    table.insert(self.changsha_game_end_balance_info.zhongbird, k)
                end
            end
        else
            local space = self.next_banker_chair - self:get_banker_chair() +1
            if space <= 0 then
               space = space + #self.players
            end
            self.changsha_game_end_balance_info.zhongbird = birdTmp[space] or {}
        end
        local point = #self.changsha_game_end_balance_info.zhongbird*bird_point
        for i , k in pairs(self.players) do
            if i ~= self.next_banker_chair then 
                k.changsha_balance_info.getpoint = k.changsha_balance_info.getpoint - point
            else
                k.changsha_balance_info.getpoint = k.changsha_balance_info.getpoint + (#self.players -1)*point
                k.changsha_balance_info.getbird = #self.changsha_game_end_balance_info.zhongbird
            end
        end
    else
        local player = self.players[self.changsha_lose_chair_id]
        if self.dianPao > 1 then
            if self.table_config.player_count == 3 then
                for i ,k in pairs(self.changsha_game_end_balance_info.birdCard) do
                    if majiang_opration:check_is_bird(k) then
                        table.insert(self.changsha_game_end_balance_info.zhongbird, k)
                    end
                end
            else
                local space = self.changsha_lose_chair_id - self:get_banker_chair() + 1
                if space <= 0 then
                   space = space + 4
                end
                self.changsha_game_end_balance_info.zhongbird = birdTmp[space] or {}
            end
            local point = #self.changsha_game_end_balance_info.zhongbird*bird_point
            for i , k in pairs(self.changsha_hu_chair_id) do 
                local player1 = self.players[k]
                player1.changsha_balance_info.getpoint =  player1.changsha_balance_info.getpoint + point
            end
            player.changsha_balance_info.getpoint =  player.changsha_balance_info.getpoint - (point*#self.changsha_hu_chair_id)
            player.changsha_balance_info.getbird = #self.changsha_game_end_balance_info.zhongbird
        else
            if self.table_config.player_count == 3 then
                for i ,k in pairs(self.changsha_game_end_balance_info.birdCard) do
                    if majiang_opration:check_is_bird(k) then
                        table.insert(self.changsha_game_end_balance_info.zhongbird, k)
                    end
                end
            else
                local space = self.changsha_hu_chair_id[1] - self:get_banker_chair() +1
                if space <= 0 then
                   space = space + 4
                end
                self.changsha_game_end_balance_info.zhongbird = birdTmp[space] or {}
            end
            local point = #self.changsha_game_end_balance_info.zhongbird*bird_point
            local player1 = self.players[self.changsha_hu_chair_id[1]]
            player.changsha_balance_info.getpoint =  player.changsha_balance_info.getpoint - point
            player1.changsha_balance_info.getpoint =  player1.changsha_balance_info.getpoint + point
            player1.changsha_balance_info.getbird = #self.changsha_game_end_balance_info.zhongbird
        end
    end
end

--hu_type =1 自摸  别的放炮
--function game_sink:deal_game_end_bird(iszimo)
----    self.next_banker_chair

--    if not next(self.changsha_game_end_balance_info.birdCard) then
--        return 
--    end
--    local bird_point = self.game_config.bird_point or 1
--    local birdTmp = getiszhongBird(self.changsha_game_end_balance_info.birdCard)
--    local player = self.players[self.next_banker_chair]
--    local birdtab = birdTmp[1] or {}
--    if iszimo then
--        local tmpPoint = 0
--        for i , k in pairs(self.players) do
--            if i ~= self.next_banker_chair then 
--                local space1 = i - self:get_banker_chair() + 1
--                if space1 <= 0 then
--                    space1 = space1 + #self.players
--                end
--                local birdtab1 = birdTmp[space1] or {}
--                tmpPoint = tmpPoint + #birdtab1*bird_point
--                k.changsha_balance_info.getpoint = k.changsha_balance_info.getpoint - #birdtab*bird_point - #birdtab1*bird_point
--                k.changsha_balance_info.getbird = #birdtab1
--                --给客户端筛选鸟
--                for i1, k1 in pairs(birdtab1) do
--                    local ishas = false
--                    for a, b in pairs(self.changsha_game_end_balance_info.zhongbird) do
--                        if b == k1 then
--                            ishas = true
--                        end
--                    end
--                    if not ishas then
--                        table.insert(self.changsha_game_end_balance_info.zhongbird, k1)
--                    end
--                end
--            end
--        end
--        player.changsha_balance_info.getpoint = player.changsha_balance_info.getpoint + #birdtab*(#self.players - 1)*bird_point + tmpPoint
--        player.changsha_balance_info.getbird = #birdtab
--        for i, k in pairs(birdtab) do
--            local ishas = false
--            for a, b in pairs(self.changsha_game_end_balance_info.zhongbird) do
--                if b == k then
--                    ishas = true
--                end
--            end
--            if not ishas then
--                table.insert(self.changsha_game_end_balance_info.zhongbird, k)
--            end
--        end
--    else
--        if self.dianPao == 1 then
--            player = self.players[self.changsha_lose_chair_id]
--            space = self.changsha_lose_chair_id - self:get_banker_chair() + 1
--            if space <= 0 then
--                space = space + #self.players
--            end
--            birdtab = birdTmp[space] or {}
--        end
--        for i, k in pairs(self.changsha_hu_chair_id) do
--            player1 = self.players[k]
--            local space1 = k - self:get_banker_chair() + 1
--            if space1 <= 0 then
--                space1 = space1 + #self.players
--            end
--            local birdtab1 = birdTmp[space1] or {}
--            player1.changsha_balance_info.getpoint = player1.changsha_balance_info.getpoint + #birdtab*bird_point + #birdtab1*bird_point
--			player1.changsha_balance_info.getbird = #birdtab1
--			player.changsha_balance_info.getpoint = player.changsha_balance_info.getpoint - #birdtab*bird_point - #birdtab1*bird_point
--            for i1, k1 in pairs(birdtab1) do
--                local ishas = false
--                for a, b in pairs(self.changsha_game_end_balance_info.zhongbird) do
--                    if b == k1 then
--                        ishas = true
--                    end
--                end
--                if not ishas then
--                    table.insert(self.changsha_game_end_balance_info.zhongbird, k1)
--                end
--            end
--        end
--		player.changsha_balance_info.getbird = #birdtab
--        for i, k in pairs(birdtab) do
--            local ishas = false
--            for a, b in pairs(self.changsha_game_end_balance_info.zhongbird) do
--                if b == k then
--                    ishas = true
--                end
--            end
--            if not ishas then
--                table.insert(self.changsha_game_end_balance_info.zhongbird, k)
--            end
--        end
--    end
--end

--游戏结束
function game_sink:game_end(args, iszimo)
	syslog.info("game end")
	self.is_playing = false
    if self.table_config.game_index == 8 then
        self.interface.send_red_bag()
    end
    self:deal_game_end_bird(iszimo)
    self.changsha_game_end_balance_info.ningxiang_player_balance = {}
    self.changsha_game_end_balance_info.banker = self.banker or 1
    for k , v in pairs(self.players) do 
        local tmp = {}
        tmp.getpoint = v.changsha_balance_info.getpoint
        tmp.getbird = v.changsha_balance_info.getbird
        tmp.handCard = group_card(v.card_info)
        if v.card_info.huCard == 0 then
            tmp.huCard = {}
        else
            tmp.huCard = v.card_info.huCard
        end
        tmp.first_hu = v.changsha_balance_info.first_hu
        tmp.hu_info = v.changsha_balance_info.hu_info
        tmp.huType = v.changsha_balance_info.huType
        tmp.point = self:add_balance_point(k ,tmp.getpoint) + 1000
        table.insert(self.changsha_game_end_balance_info.ningxiang_player_balance, tmp)
    end
	self.game_record:write_game_record()
	table.printR(self.changsha_game_end_balance_info)
	self:send_table_client(0, "game_game_end", self.changsha_game_end_balance_info)
--    self:send_table_client(0, "game_replay", {info= json.encode(self.game_record:get_game_replay())})
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
        if k == chair_id then
            if (next(self.changsha_first_hu_lock) or next(self.readybaoting)) and chair_id == self:get_banker_chair() then
                tmp.cardNum = #v.card_info.handCards + 1
			    tmp.handCards = table.clone(v.card_info.handCards)
                table.insert(tmp.handCards, self.changsha_first_card)
                ret.state = true
            else
		        tmp.cardNum = #v.card_info.handCards
			    tmp.handCards = v.card_info.handCards
		    end
        else
            tmp.cardNum = #v.card_info.handCards
        end
		tmp.point = v.base_info.point
		-- ret.playerCard[K] = json.encode(tmp)
		table.insert(ret.playerCard, tmp)
	end
	ret.canOperation = {}
    --选择海底
    if self.onHaidi == chair_id then
        ret.canOperation["canHaidi"] = true
    end
    --选择报听
    if self.readybaoting[chair_id] then
        ret.canOperation["canTing"] = true
    end
	for k, v in pairs(self.game_privite_info) do
		if k == "canHu" then
			for hk, hv in pairs(v) do
				if hv.chair_id == chair_id then
                    ret.canOperation[k] = true
                    ret.canOperation.hutype = hv.op
                    ret.canOperation.hucard = hv.card
				end
			end
		elseif k == "canGang" then
			if v.chair_id == chair_id then
				local tmp = {}
				tmp[k] = v.card
                ret.canOperation[k] = v.card
			end
		elseif k == "canPeng" then
			if v == chair_id then
				local tmp = {}
				tmp[k] = true
                ret.canOperation.canPeng = self.game_privite_info.pengcard
			end
        elseif k == "canChi" then
            if v == chair_id then
                local tmp = {}
				tmp[k] = true
                ret.canOperation.canChi = self.game_privite_info.Chi_info
            end
        elseif k == "canBu" then
			if v.chair_id == chair_id then
				local tmp = {}
				tmp[k] = v.card
                ret.canOperation[k] = v.card
			end
		end
	end
    for i, k in pairs(self.changsha_first_hu_lock) do
        if i == chair_id then
            ret.canOperation.canFirstHu = true
        end
    end
	ret.canOperation = json.encode(ret.canOperation)
	ret.curOutCHair = self.game_all_info.cur_out_chair 
	ret.lastOutChair = self.game_all_info.last_out_chair
	ret.lastOutCard = self.game_all_info.last_out_card
	ret.banker = self.banker or 1
	ret.leftNum = #self.aftercards
	ret.gameIndex = self.game_end_balance_info.game_index
    if self.gangLock[chair_id] then
        ret.gangLock = true
    end
    ret.laizi = self.laizi
    ret.laizipi = self.laizipi
	--table.printR(ret)
	return true, ret
end

---------------------------------------------------------------
-----------------------all balance record----------------------
---------------------------------------------------------------

--function game_sink:add_balance_option(chair_id, balance_type)
--    local balance_result = self.players[chair_id].balance_result
--    if balance_result then
--        if balance_type == "ziMo" then
--            balance_result.ziMo = balance_result.ziMo + 1
--        elseif balance_type == "jiePao" then
--            balance_result.jiePao = balance_result.jiePao + 1
--        elseif balance_type == "dianPao" then
--            balance_result.dianPao = balance_result.dianPao + 1
--        elseif balance_type == "mingGang" then
--            balance_result.mingGang = balance_result.mingGang + 1
--        elseif balance_type == "anGang" then
--            balance_result.anGang = balance_result.anGang + 1
--        elseif balance_type == "suoGang" then
--            balance_result.suoGang = balance_result.suoGang + 1
--        end
--    end
--end

function game_sink:add_balance_option(chair_id, balance_type, count)
    local changsha_balance_result = self.players[chair_id].changsha_balance_result
    count = count or 1
    if changsha_balance_result then
        if balance_type == "dahuzimo" then
            changsha_balance_result.dahuzimo = changsha_balance_result.dahuzimo + count
        elseif balance_type == "xiaohuzimo" then
            changsha_balance_result.xiaohuzimo = changsha_balance_result.xiaohuzimo + count
        elseif balance_type == "dahudianpao" then
            changsha_balance_result.dahudianpao = changsha_balance_result.dahudianpao + count
        elseif balance_type == "xiaohudianpao" then
            changsha_balance_result.xiaohudianpao = changsha_balance_result.xiaohudianpao + count
        elseif balance_type == "dahujiepao" then
            changsha_balance_result.dahujiepao = changsha_balance_result.dahujiepao + count
        elseif balance_type == "xiaohujiepao" then
            changsha_balance_result.xiaohujiepao = changsha_balance_result.xiaohujiepao + count
        end
    end
end

function game_sink:add_balance_point(chair_id, point)
	--保存玩家分数
    local base_info = self.players[chair_id].base_info
    base_info.point = base_info.point + point
    --保存总结算分数
    local changsha_balance_result = self.players[chair_id].changsha_balance_result
    self.game_record:add_player_balance(chair_id, point)
    if changsha_balance_result then
        changsha_balance_result.point = changsha_balance_result.point + point
        return changsha_balance_result.point
    end
    return 0
end

function game_sink:get_all_balance_result()
	local ret = {}
	local sclub = {}
	for k, v in pairs(self.players) do
		local tmp = v.changsha_balance_result
		tmp.uid = v.base_info.uid
		table.insert(sclub,{uid = v.base_info.uid, point = v.base_info.point or 0,  dahuzimo = tmp.dahuzimo or 0, xiaohuzimo = tmp.xiaohuzimo or 0 , dahudianpao = tmp.dahudianpao or 0, xiaohudianpao = tmp.xiaohudianpao or 0})
		table.insert(ret, tmp)
	end
	table.sort(sclub , function(a,b) 
							if a.point > b.point then
								return true
							elseif a.point == b.point  then
								if  a.dahuzimo + a.xiaohuzimo > b.dahuzimo + b.xiaohuzimo then
									return true
								elseif  a.dahuzimo + a.xiaohuzimo == b.dahuzimo + b.xiaohuzimo and a.dahudianpao + a.xiaohudianpao < b.dahudianpao + b.xiaohudianpao then
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


