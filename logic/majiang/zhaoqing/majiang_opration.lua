require "table_util"
local hupai = require "majiang.zhaoqing.hupai"
local json = require "cjson"
local syslog = require "syslog"
local table  = table
local majiang_operation = {}

local function add_stackCard(cards,card)
	if cards[card] then
		cards[card] = cards[card] +1
	else
		cards[card] = 1
	end
end

local function sub_stackCard(cards,card)
	if not cards[card] then
		return
	end
	cards[card] = cards[card] - 1 
	if cards[card] == 0 then
		cards[card] = nil
	end
end

local function is_laizi_card(card,config)
	if config.laizi == false then
		return false
	end
	if config.laizi_card ~= card then
		return false
	end
	-- if table.indexof(config.laizi_card,card) == false then
	-- 	return false
	-- end
	return true
end


--[[
把牌分类
 	cards[11] = num
 	cards[32] = num
]]
local function stackCards(cards)
	local newcard = {}
	for k, v in pairs(cards) do
		add_stackCard(newcard, v)
	end
	return newcard
end

local function canPeng(cards, card, config)
	if is_laizi_card(card,config) then
		return false
	end
	if cards[card] and cards[card] >= 2 then
		return true
	end
	return false
end

local function canChi(cards, card, chair_id,config)
	if is_laizi_card(card,config) then
		return false
	end
	if card >= 41 then --风牌暂时不支持吃
		return false
	end	
	if cards[card +1] and cards[card +2] then
		if is_laizi_card(card + 1,config) then
			return false
		end
		if is_laizi_card(card +2,config) then
			return false
		end
		return true
	elseif cards[card -1] and cards[card +1] then
		if is_laizi_card(card -1,config) then
			return false
		end
		if is_laizi_card(card +1,config) then
			return false
		end	 
		return true
	elseif cards[card -2] and cards[card -1] then
		if is_laizi_card(card - 2,config) then
			return false
		end
		if is_laizi_card(card - 1,config) then
			return false
		end	 		
		return true
	end
	return false
end

local function canPengGang(cards, card, config) 
	local ret = {}
	if is_laizi_card(card,config) then
		return ret
	end
	if cards[card] and cards[card] == 3 then
		table.insert(ret,card)
		-- return true, card
	end
	return ret
end

local function canAnGang(cards, config)
    local ret = {}
    for i , k in pairs(cards) do
        if k == 4  then
            if is_laizi_card(card,config) == false then
                table.insert(ret,i)
            end
        end
    end
    return ret
end

--目前没调用
local function canGang(cards, card, config)
	if is_laizi_card(card,config) then
		return false
	end
	if cards[card] == 3 then
		return true
	end
	return false
end
----------------------------------------

local function moCanGang(stackCard, pengCard, card, config)
	local ret = {}
	if is_laizi_card(card,config) then
		return ret
	end
	for k, v in pairs(stackCard) do 
		if v == 4 then
			if is_laizi_card(k,config) == false then
				table.insert(ret, k) --手上有4张同样牌的情况(上轮能杠没杠，这轮需要判断)
			end		
		elseif v == 1 then
			if pengCard[k] then
				table.insert(ret, k) --手上有一只牌，有碰的同样牌(上轮能杠没杠，这轮需要判断)
			end
		end
	end
	if stackCard[card] == 3 then
		table.insert(ret, card)
	elseif pengCard[card] then
		table.insert(ret, card)
	end
	return ret
end

function majiang_operation:check_is_laizi_card(card)
	if self.table_config.laizi == false then
		return false
	end
	if self.laizi_card ~= card then
		return false
	end
	-- if table.indexof(self.laizi_card,card) == false then
	-- 	return false
	-- end
	return true
end

--[[
	handcard:手上的牌 {11,11,13,14,22,33,44...}
	stackCard:理过的手牌 {[11]=2,[13]=1,[14]=1,[22]=1,[33]=1,[44]=1...}
	card:要打出的牌 44
	pengCard:碰过的牌 {[33]=1,[23] =1}
	gangCard:杠过的牌{[24]=1}
]]


function majiang_operation:mo_card(handCard, stackCard, pengCard, card, last, chair_id, louHuChair, isfirstDraw)
	local ret = {}
	local canGang = moCanGang(stackCard, pengCard, card, self.table_config)

	if next(canGang) then
		ret.canGang = canGang
	end
	--TODO:判断是否能胡
	local testCard = table.clone(handCard)
	table.insert(testCard, card)
	local canHu,fanType = hupai:check_can_hu(testCard,self.LAIZI, self.table_config.seven_hu,self.laizi_card)
    if canHu and not (louHuChair[chair_id] and louHuChair[chair_id][card]) then
		ret.canHu = true
        ret.hucard = card
        ret.hutype = 1
        ret.fanType = fanType
	end
    -- --第一次摸牌的时候判断4癞子(canhu没有false 只有nil)
    -- if isfirstDraw and not ret.canHu then
    --     ret.canHu = self:check_four_laizi(stackCard, card)
    --     if ret.canHu then
    --         ret.hucard = card
    --         ret.hutype = 1
    --         ret.fanType = 1--4鬼胡牌，为平胡
    --     end
    -- end
    table.printT(ret)
	return ret
end
function majiang_operation:other_out_card(handCard, stackCard, otherCard, chair_id, louHuChair)
	local ret = {}
	local tmpCard = table.clone(handCard)
	table.insert(tmpCard, otherCard)

	if self.table_config.game_type == 3  and canChi(stackCard, otherCard, chair_id, self.table_config) then
		-- table.insert(ret, "canChi")
		ret.canChi = true
	end
	if canPeng(stackCard, otherCard, self.table_config) then
		ret.canPeng = otherCard
	end
	local canGang = canPengGang(stackCard, otherCard, self.table_config)
	if next(canGang) then
		ret.canGang = canGang
	end
	--TODO:判断是否能胡
    if louHuChair[chair_id] then
        table.printR(louHuChair[chair_id])
    end
    local fanType
    local canHu 
	if self.table_config.game_type == 1 and not (self.table_config.laizi and otherCard == self.laizi_card) then
		canHu,fanType = hupai:check_can_hu(tmpCard,self.LAIZI, self.table_config.seven_hu,self.laizi_card)
		if canHu and not (louHuChair[chair_id] and louHuChair[chair_id][otherCard]) then
			ret.canHu = true
            ret.hutype = 2
            ret.hucard = otherCard
            ret.fanType = fanType
		end
	end
	return ret
end

function majiang_operation:check_four_laizi(stackCards, card)
	if self.table_config.laizi then
		if stackCards[self.laizi_card] == 4 then
            return true
        elseif stackCards[self.laizi_card] == 3 and card == self.laizi_card then
            return true
		end
	end
	return nil
end
--其他操作后判断是不是有暗杠
function majiang_operation:check_gang_after(stackCard)
    local ret = {}
    local canGang = canAnGang(stackCard, self.table_config)
    if next(canGang) then
        ret.canGang = canGang
    end
    return ret
end

function majiang_operation:get_gang_type(handCard, stackCard,pengCard, card)
	if stackCard[card] == 4 or pengCard[card] then
		return 1
	elseif stackCard[card] == 3 then
		return 2
	end
	return 0
end

function majiang_operation:other_self_gang(handCard, stackCard, otherCard, chair_id, louHuChair)
	local ret = {}
	local tmpCard = table.clone(handCard)
	table.insert(tmpCard, otherCard)
	local canHu,fanType = hupai:check_can_hu(tmpCard, self.LAIZI, self.table_config.seven_hu,self.laizi_card)
    if canHu then
		ret.canHu = true
        ret.hutype = 3
        ret.hucard = otherCard
        ret.fanType = fanType
	end
	return ret
end

-------------------------------------------------------
function majiang_operation:handle_mo_card(handCard, stackCard, card)
	table.insert(handCard, card)
	add_stackCard(stackCard, card)
end

function majiang_operation:handle_out_card(handCard, stackCard, outCards,card)
	table.removebyvalue(handCard, card, false)
	sub_stackCard(stackCard, card)
	table.insert(outCards,card)
end

function majiang_operation:handle_peng_card(handCard, stackCard, pengCard, card, out_chair)
	for i=1, 2 do
		table.removebyvalue(handCard, card, false)
		sub_stackCard(stackCard, card)
	end
	pengCard[card] = out_chair
end

function majiang_operation:handle_gang_peng_card(handCard, stackCard, gangCard, card, out_chair)
	for i =1, 3 do
		table.removebyvalue(handCard, card, false)
		sub_stackCard(stackCard, card)
	end
	gangCard[card] = {3, out_chair}
end

function majiang_operation:handle_gang_mo_card(handCard, stackCard, pengCard, gangCard, card, out_chair)
	local ret = {}
	if pengCard[card] then
		table.removebyvalue(handCard, card, false)
		sub_stackCard(stackCard, card)
		ret.gang_type = 1
		-- pengCard[card] = nil
	else
		for i = 1, 4 do
			table.removebyvalue(handCard, card, false)
			sub_stackCard(stackCard, card)
		end
		ret.gang_type = 2
		gangCard[card] = {2, out_chair}
	end
	return ret
end

--明杠没有被抢杠胡才把杠牌写上
function majiang_operation:handle_mingGang_success(pengCard, gangCard, card)
	gangCard[card] = {1, pengCard[card]}
	pengCard[card] = nil
end

--[[
	other_card:上家出的牌
	chicards :手牌要被吃的牌
]]
function majiang_operation:handle_chi_card(handCard,stackCard,chiCard, other_card, chicards)
	for k, v in pairs(chicards) do
		table.removebyvalue(handCard,v,false)
		sub_stackCard(stackCard,v)
	end
	table.insert(chicards, other_card)
	table.insert(chiCard, chicards)
end

function majiang_operation:handle_kick_out_card(outCards, card)
	table.removebyvalue(outCards, card, false)
end

function majiang_operation:check_is_bird(card)
	if self.table_config.laizi and card == self.laizi_card then 
		return true
	elseif math.ceil(card / 10) <= 4 then
		local tail_num = card % 10 
		if self.bird_table[tail_num] then
			return true
		end
	end
	return false
end

function majiang_operation:handle_find_bird(leftcard)
	local ret = {}
	ret.bird_num = 0
	ret.birds = {}
	ret.zhong_bird = {}
	if #leftcard == 0 or self.table_config.find_bird == 0 then
		return ret
	end
	local num
	if self.table_config.find_bird == 1 then --爆炸马，胡牌的人只抓1匹马，马的点数是几就几分
		local bird_point = 0
		local card = leftcard[1]
		if card >= 11 and card <= 39 then
			if card == 11 or card == 21 or card == 31 then
				bird_num = 10
			else
				bird_num = card % 10
			end
		elseif card >= 41 and card <= 47 then --风牌为5分
			bird_num = 5
		else
			bird_num = 0
		end
		ret.bird_num = bird_num * self.table_config.bird_point

		table.insert(ret.zhong_bird, leftcard[1])
		table.insert(ret.birds, leftcard[1])
		table.remove(leftcard, 1)	
	else
		if #leftcard > self.table_config.find_bird then
			num = self.table_config.find_bird
		else
			num = #leftcard
		end
		for i = 1, num do
			table.insert(ret.birds, leftcard[1])
			if self:check_is_bird(leftcard[1]) then
				ret.bird_num = ret.bird_num + self.table_config.bird_point
				table.insert(ret.zhong_bird, leftcard[1])
			end
			table.remove(leftcard, 1)
		end
	end
	return ret
end

--------------------------------------------------------------------

function majiang_operation:check_is_laizi(card)
	if self.table_config.laizi == true then
		if self.laizi_card == card then
			return true
		end
	end
end

function majiang_operation:set_fan_laizi(card)
	self.table_config.laizi = true
	self.laizi_card = card
	self.table_config.laizi_card = card
end

function majiang_operation:set_config(game_config, table_config, louHuChair )
	--[[
		game_config = {}
		game_config.curCard = nil
		game_config.last_out_chair = 0
		game_config.cur_out_chair = 0
		game_config.find_bird_num = 2
	]]
	self.game_config = game_config

	--[[
		idle = true
        laizi = true
        card_num = 16
        find_bird = 2
        seven_hu = true
        game_type = 1
        bird_point = 1
        qiang_gang = true
	]]
	self.table_config = table_config
	--table.printT(self.table_config)
	local bird_point = self.table_config.bird_point or 1
	self.table_config.bird_point = bird_point
	self.table_config.find_bird = self.table_config.find_bird
	self.table_config.laizi = self.table_config.laizi or false
	self.table_config.qiang_gang = self.table_config.qiang_gang or false
	self.table_config.seven_hu = self.table_config.seven_hu or false

	self.table_config.idle = self.table_config.idle or false
	self.LAIZI = 0
	if self.table_config.laizi then
		self.LAIZI = 4
	end
	--现在翻牌，只做单鬼
	if self.table_config.laizi and self.table_config.baiban == true then
		self.laizi_card = 47
		self.table_config.laizi_card = 47
	end  

	self.bird_table = {}
	self.bird_table[1] = true
	self.bird_table[5] = true
	self.bird_table[9] = true

	self.louHuChair = louHuChair
end

return majiang_operation