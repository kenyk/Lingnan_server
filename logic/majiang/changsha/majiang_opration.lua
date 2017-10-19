require "table_util"
local hupai = require "majiang.changsha.hupai"
local json = require "cjson"
local syslog = require "syslog"
local majiang_operation = {}
local math = math
local table = table


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
	if cards[card] and cards[card] >= 2 then
		return true
	end
	return false
end

local function canChi(cards, card, chair_id,config)
    local group = {}
	if cards[card + 1] and cards[card + 2] then
        group[1] = card
		table.insert(group, {card + 1, card,card + 2})
    end
	if cards[card -1] and cards[card + 1] then 
        group[1] = card
		table.insert(group, {card -1,card ,card + 1})
    end
	if cards[card -2] and cards[card -1] then
        group[1] = card
		table.insert(group, {card - 2,card ,card - 1})
	end
	return group
end

local function canPengGang(cards, card, config) 
	local ret = {}
	if cards[card] and cards[card] == 3 then
		table.insert(ret,card)
		-- return true, card
	end
	return ret
end
--目前没调用
local function canGang(cards, card, config)
	if cards[card] == 3 then
		return true
	end
	return false
end
----------------------------------------
local function canAnGang(cardInfo, config)
    local ret = {}
    for i , k in pairs(cardInfo.stackCards) do
        if k == 4 then
            table.insert(ret,i)
        end
        if cardInfo.pengCards[i] then
            table.insert(ret,i)
        end
    end
    return ret
end

local function moCanGang(stackCard, pengCard, card, config)
	local ret = {}
	for k, v in pairs(stackCard) do
		if v == 4 then
			table.insert(ret, k)
		end
	end
	if stackCard[card] == 3 then
		table.insert(ret, card)
	elseif pengCard[card] then
		table.insert(ret, card)
	end
    for i , k in pairs(pengCard) do
        if stackCard[i] and i ~= card then
            table.insert(ret, i)
        end
    end
	return ret
end
--[[
	handcard:手上的牌 {11,11,13,14,22,33,44...}
	stackCard:理过的手牌 {[11]=2,[13]=1,[14]=1,[22]=1,[33]=1,[44]=1...}
	card:要打出的牌 44
	pengCard:碰过的牌 {[33]=1,[23] =1}
	gangCard:杠过的牌{[24]=1}
]]


--function majiang_operation:mo_card(handCard, stackCard, pengCard, card, last, chair_id, louHuChair)
function majiang_operation:mo_card(cardInfo, card, chair_id, louHuChair, istianhu, lock, haidiChair, isgang, cardnum)
	local ret = {}
    local config = {}
    local hu_ret = {}
--    if last == -1 then
--        config.gang = true
--    end
    config.menqing = true
    if haidiChair then
        if haidiChair > 0 and haidiChair == chair_id then
            config.haidilao = true
        else
            config.haidipao = true
        end
    end
    if istianhu then
        config.tianhu = true
    end
    if isgang then
        config.gang = true
    end
    local testCard = table.clone(cardInfo.handCards)
    table.insert(testCard, card)
    if not lock and not (haidiChair and haidiChair > 0) then
        local canGang = moCanGang(cardInfo.stackCards, cardInfo.pengCards, card, self.table_config)
        if next(canGang) then
        	local tab = {}
            for a , b in pairs(canGang) do
                local testCardTmp = table.clone(testCard)
                for i=#testCardTmp , 1,-1 do
                    if testCardTmp[i] == b then
                        table.remove(testCardTmp, i)
                    end
                end
                if hupai:check_can_ting(testCardTmp, cardInfo, config, laizi) and cardnum > 1 then
                    -- ret.canGang = canGang
                    table.insert(tab, b)
                end
            end
            if next(tab) then
            	ret.canGang = tab
        	end
		    ret.canBu = canGang
	    end
    end
    --TODO:判断是否能胡
	hu_ret = hupai:check_can_hu(testCard, cardInfo, config, self.table_config,laizi)
    if next(hu_ret) and not (louHuChair[chair_id] and louHuChair[chair_id][card]) then
		ret.canHu = true
        ret.hutype = 1
        ret.hucard = card
        hu_ret.hucard = card
        if config.haidipao then
            ret.hutype = 2
        end
	end
	return ret , hu_ret
end

--function majiang_operation:other_out_card(handCard, stackCard, otherCard, chair_id, louHuChair)
--isnext 是不是下家
function majiang_operation:other_out_card(cardInfo, otherCard, chair_id, louHuChair, isfirst, isnext, lock, isgang, cardnum)
	local ret = {}
	local tmpCard = table.clone(cardInfo.handCards)
    local config = {}
    local hu_ret = {}
    if isfirst then
        config.dihu = true
    end
    if isgang then
        config.gangshangpao = true
    end
    if not lock then
        local canGang = canPengGang(cardInfo.stackCards, otherCard, self.table_config)
	    if next(canGang) then
            local testCardTmp = table.clone(tmpCard)
            for i=#testCardTmp , 1,-1 do
                if testCardTmp[i] == otherCard then
                    table.remove(testCardTmp, i)
                end
            end
            if hupai:check_can_ting(testCardTmp, cardInfo, config) and cardnum > 1 then
                ret.canGang = canGang
            end
		    ret.canBu = table.clone(canGang)
	    end
	    table.insert(tmpCard, otherCard)
        local chi_ret = canChi(cardInfo.stackCards, otherCard, chair_id)
	    if next(chi_ret) and isnext then
		    ret.canChi = chi_ret
	    end
	    if canPeng(cardInfo.stackCards, otherCard, self.table_config) then
		    ret.canPeng = otherCard
	    end
    else
        table.insert(tmpCard, otherCard)
    end
	hu_ret = hupai:check_can_hu(tmpCard, cardInfo, config)
	if next(hu_ret) and not (louHuChair[chair_id] and louHuChair[chair_id][otherCard]) then
		ret.canHu = true
        ret.hutype = 2
        ret.hucard = otherCard
        hu_ret.hucard = otherCard
	end
	return ret, hu_ret
end

function majiang_operation:deal_card(stackCards)
--	local ret = {}
	if self.table_config.laizi then
		if stackCards[45] == 4 then
--			ret.canHu = true
            return true
		end
	end
	return nil
end

function majiang_operation:get_gang_type(handCard, stackCard,pengCard, card)

	if stackCard[card] == 4 or pengCard[card] then
		return 1
	elseif stackCard[card] == 3 then
		return 2
	end
	return 0
end

--function majiang_operation:other_self_gang(handCard, stackCard, otherCard, chair_id, louHuChair)
function majiang_operation:other_self_gang(cardInfo, otherCard, chair_id, louHuChair, isgang)
	local ret = {}
	local tmpCard = table.clone(cardInfo.handCards)
	table.insert(tmpCard, otherCard)
    local config = {}
    config.qianggang = isgang
	local hu_ret = hupai:check_can_hu(tmpCard, cardInfo, config)
--	if next(hu_ret) and not (louHuChair[chair_id] and louHuChair[chair_id][otherCard]) then
    if next(hu_ret) then
		ret.canHu = true
        ret.hutype = 3
        ret.hucard = otherCard
        hu_ret.hucard = otherCard
	end
	return ret, hu_ret
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
--function majiang_operation:handle_chi_card(handCard,stackCard,chiCard, other_card, chicards)
function majiang_operation:handle_chi_card(handCard,stackCard,chiCard, card_table)
    local chicards = {}
	for k, v in pairs(card_table.will_chi_card) do
		table.removebyvalue(handCard,v,false)
		sub_stackCard(stackCard,v)
        table.insert(chicards, v)
	end
	table.insert(chicards, 2, card_table.chi_card)
	table.insert(chiCard, chicards)
end

--其他操作后判断是不是有暗杠
function majiang_operation:check_gang_after(cardInfo, cardnum)
    local ret = {}
--    local canGang = canAnGang(cardInfo.stackCards, self.table_config)
    local canGang = canAnGang(cardInfo, self.table_config)
    if next(canGang) then
        ret.canBu = canGang
        for a , b in pairs(canGang) do
            local testCardTmp = table.clone(cardInfo.handCards)
            for i=#testCardTmp , 1,-1 do
                if testCardTmp[i] == b then
                    table.remove(testCardTmp, i)
                end
            end
            if hupai:check_can_ting(testCardTmp, cardInfo, config, b) and cardnum > 1 then 
                ret.canGang = canGang
            end
        end
	end
--    if hupai:check_can_ting(testCardTmp, cardInfo, config, b) then 
--        ret.canGang = canGang
--    end
    return ret
end

function majiang_operation:handle_kick_out_card(outCards, card)
	table.removebyvalue(outCards, card, false)
end

function majiang_operation:check_is_bird(card)
	if self.table_config.laizi and card == 45 then 
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
	if #leftcard == 0 or self.table_config.find_bird == 0 then
		return ret
	end
	local num
	if #leftcard > self.table_config.find_bird then
		num = self.table_config.find_bird
	else
		num = #leftcard
	end
	for i = 1, num do
		table.insert(ret.birds, leftcard[1])
		if self:check_is_bird(leftcard[1]) then
			ret.bird_num = ret.bird_num + self.table_config.bird_point
		end
		table.remove(leftcard, 1)
	end
	return ret
end
--起手胡
function majiang_operation:handle_first_hu(stackCards,cards)
    local ret = hupai:check_First_hu(stackCards,cards)
    return ret
end

--------------------------------------------------------------------

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
	self.table_config.find_bird = self.table_config.find_bird or 0
	self.table_config.laizi = self.table_config.laizi or false
	self.table_config.qiang_gang = self.table_config.qiang_gang or false
	self.table_config.seven_hu = self.table_config.seven_hu or false

	self.table_config.idle = self.table_config.idle or false
	self.LAIZI = 0
	if self.table_config.laizi then
		self.LAIZI = 4
	end
	self.bird_table = {}
	self.bird_table[1] = true
	self.bird_table[5] = true
	self.bird_table[9] = true

	self.louHuChair = louHuChair
end

return majiang_operation