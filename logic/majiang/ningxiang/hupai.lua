local cardDef = require "majiang.ningxiang.cardDef"
local syslog = require "syslog"

local m_table = {}
MJPAI_FENGZFB = 3
function m_table.clone(object)
    local lookup_table = {}
    local function _copy(object)
        if type(object) ~= "table" then
            return object
        elseif lookup_table[object] then
            return lookup_table[object]
        end
        local new_table = {}
        lookup_table[object] = new_table
        for key, value in pairs(object) do
            new_table[_copy(key)] = _copy(value)
        end
        return setmetatable(new_table, getmetatable(object))
    end
    return _copy(object)
end

function m_table.removebyvalue(array, value, removeall)
    local c, i, max = 0, 1, #array
    while i <= max do
        if array[i] == value then
            table.remove(array, i)
            c = c + 1
            i = i - 1
            max = max - 1
            if not removeall then break end
        end
        i = i + 1
    end
    return c
end

function m_table.printT(obj)
    if type(obj)~= "table" then
        print(obj)
        return 0
    end
    local looped_table = {}
    local function pt(key, obj, depth)
        local space = ""
        for i = 0, depth , 1 do space = space .. "    "end
        if depth == 0   then print("{") end
        looped_table[obj] = key
        for k, v in pairs(obj) do
            if type(k) == "string"  then
                io.write(space, k, " = ")
            else
                io.write(space,"[", k, "] = ")
            end
            if type(v) == "table"   then
                if looped_table[v] then
                   io.write(" looped_table: "..tostring(looped_table[v]).."\n")
                else
                    io.write("{\n")
                    pt(k, v, depth+1)
                    looped_table[v] = k
                    io.write(space, "}\n")
                end
            else
                local tmp = tostring(v)
                io.write(tmp, "\n")
            end
        end
        if depth == 0   then print("}") end
    end
    pt("self", obj, 0)
end

-- local needMinHuntable.needMinHunNum = LAIZINUM

local function  test3Combine(pai_1, pai_2, pai_3)
	-- body
	if pai_1 == pai_2 and pai_2 == pai_3 then
		return true
	end
	if math.ceil(pai_1 / 10) -1 == 4 then
		return false
	end
	if pai_2 - pai_1 == pai_3 - pai_2 and pai_3 - pai_2 == 1 then
		return true
	end
	return false
end

--检测是不是258
local function check258(card)
    local _type, index = math.modf(card/10)
    index = math.floor(index*10 + 0.5)
    if index == 2 or index == 5 or index == 8 then 
        return true
    end
    return false
end

local function test2Combine(pai_1, pai_2, luanjiang)
	if pai_1 == pai_2 then
        if luanjiang or check258(pai_1) then
            return true
        end
	end
	return false
end

local function getPaiType(pai)
	return math.ceil(pai/10) -1
end



local function getNeedHunPaiNumToBeHu(pai, needNum, needMinHuntable)
	-- local needMinHuntable.needMinHunNum = LAIZINUM
	if needMinHuntable.needMinHunNum == 0 then
		return 
	end
	local paiNum = #pai
	if paiNum == 0 then
		needMinHuntable.needMinHunNum = math.min(needNum, needMinHuntable.needMinHunNum)
		return
	elseif paiNum == 1 then
		needMinHuntable.needMinHunNum = math.min(needNum + 2, needMinHuntable.needMinHunNum)
		return 
	elseif paiNum == 2 then
		local pai_1 = pai[1]
		local pai_2 = pai[2]
		if math.ceil(pai_1 / 10) -1 == 4 then
			if pai_1 == pai_2 then
				needMinHuntable.needMinHunNum = math.min(needNum + 1, needMinHuntable.needMinHunNum)
				return 
			end
		elseif pai_2 - pai_1 < 3 then
			needMinHuntable.needMinHunNum = math.min(needNum + 1, needMinHuntable.needMinHunNum)
			return 
		end
	end

	local pai_1 = pai[1]
	local pai_2 = pai[2]
	local pai_3 = pai[3]

	if needNum + 2 < needMinHuntable.needMinHunNum then
		local tmpcard = m_table.clone(pai)
		table.remove(tmpcard, 1)
		getNeedHunPaiNumToBeHu(tmpcard, needNum + 2, needMinHuntable)
		-- table.insert(pai, 1, pai_1)
	end

	if needNum + 1 < needMinHuntable.needMinHunNum then
		if math.ceil(pai_1 / 10) -1== 4 then
			if pai_1 == pai_2 then
				local tmpcard = m_table.clone(pai)
				table.remove(tmpcard, 1)
				table.remove(tmpcard, 1)
				getNeedHunPaiNumToBeHu(tmpcard, needNum + 1, needMinHuntable)
				-- table.insert(pai, 1, pai_2)
				-- table.insert(pai, 1, pai_1)
			end
		else
			for i = 2, #pai do
				if needNum + 1 > needMinHuntable.needMinHunNum then
					break
				end
				pai_2 = pai[i]
				local flag = true
				while true do
					if i ~= #pai then
						pai_3 = pai[i + 1]
						--455567这里可结合的可能为 45 46 否则是45 45 45 46
						--如果当前的value不等于下一个value则和下一个结合避免重复
						if pai_2 == pai_3 then
							--continue
							flag = false
							break
						end
					end
					if pai_2 - pai_1 < 3 then
						local tmpcard = m_table.clone(pai)
						m_table.removebyvalue(tmpcard, pai_1, false)
						m_table.removebyvalue(tmpcard, pai_2, false)
						getNeedHunPaiNumToBeHu(tmpcard, needNum + 1, needMinHuntable)
						-- table.insert(pai, i, pai_2)
						-- table.insert(pai, 1, pai_1)
						flag = false
						break
					else
						flag = true
						break
					end
				end
				--check break or continue
				if flag then
					break
				end
			end
		end
	end
	--[[
		//第一个和其它两个一扑
		//后面间隔两张张不跟前面一张相同222234 
		//可能性为222 234
	]]
	for i = 2, #pai do
		if needNum >= needMinHuntable.needMinHunNum then
			break
		end
		pai_2 = pai[i]
		while true do
			-- if i + 1 < #pai then
			-- 	if pai[i + 1] == pai_2 then
			-- 		break --continue for
			-- 	end
			-- end

			for j = i + 1, #pai do
				if needNum >= needMinHuntable.needMinHunNum then
					break
				end
				pai_3 = pai[j]
				if pai_1 == pai_3 then
					-- print("cao")
				end
				while true do
					-- if j + 1 <= #pai then
					-- 	if pai_3 == pai[j + 1] then
					-- 		break --continue for
					-- 	end
					-- end
					--判断是否能成顺
					if test3Combine(pai_1, pai_2, pai_3) then
						local tmpcard = m_table.clone(pai)
						m_table.removebyvalue(tmpcard, pai_1, false)
						m_table.removebyvalue(tmpcard, pai_2, false)
						m_table.removebyvalue(tmpcard, pai_3, false)
						getNeedHunPaiNumToBeHu(tmpcard, needNum, needMinHuntable)
						break
					end
					break
				end
			end -- end for
			break
		end
	end --end for
end


local function canHu(pai, hunNum, MAXHUNNUM, luanjiang)
	local paiNum = #pai
	if paiNum <= 0 then
		if hunNum >= 2 then
			return true
		else
			return false
		end
	end
	local copyPai = m_table.clone(pai)
	for i = 1, #copyPai do
		if i == #copyPai then
			if hunNum > 0 then
                if luanjiang or check258(copyPai[i]) then
                    hunNum = hunNum -1
                    local tmpcard = m_table.clone(copyPai)
				    m_table.removebyvalue(tmpcard, copyPai[i])
				    local needMinHuntable = {}
				    needMinHuntable.needMinHunNum = MAXHUNNUM
				    getNeedHunPaiNumToBeHu(tmpcard, 0,needMinHuntable)
				    if needMinHuntable.needMinHunNum <= hunNum then
					    return true
				    end
                    hunNum = hunNum + 1
                end
			end
		else
			if i + 2 == #copyPai or copyPai[i] ~= copyPai[i + 2] then
				if test2Combine(copyPai[i], copyPai[i+1], luanjiang) then
					local tmpcard = m_table.clone(copyPai)
					m_table.removebyvalue(tmpcard, copyPai[i])
					m_table.removebyvalue(tmpcard, copyPai[i+1])
					local needMinHuntable = {}
					needMinHuntable.needMinHunNum = MAXHUNNUM
					getNeedHunPaiNumToBeHu(tmpcard, 0,needMinHuntable)
					if needMinHuntable.needMinHunNum <= hunNum then
						return true
					end
				end
			end
			if hunNum >0 and copyPai[i] ~= copyPai[i+1] then
				local tmpcard = m_table.clone(copyPai)
                if luanjiang or  check258(copyPai[i]) then
                    hunNum = hunNum -1
                    m_table.removebyvalue(tmpcard, copyPai[i])
				    local needMinHuntable = {}
				    needMinHuntable.needMinHunNum = MAXHUNNUM
				    getNeedHunPaiNumToBeHu(tmpcard, 0,needMinHuntable)
				    if needMinHuntable.needMinHunNum <= hunNum then
					    return true
				    end
				    hunNum = hunNum + 1
                end
			end
		end
	end
	return false
end


local function testHuPai(pai, MAXHUNNUM,curHunNum, luanjiang)
	local tmpcard = m_table.clone(pai)
	local paiTable = {}
	for i = 1, 5 do
		paiTable[i] = {}
		for k, v in pairs(pai) do
			if getPaiType(v) == i then
				table.insert(paiTable[i] , v)
			end
		end
	end
	local needMinHuntable = {}
	local needNum = 0
	local jiangNeedNum = 0
	needMinHuntable.needMinHunNum = MAXHUNNUM
	getNeedHunPaiNumToBeHu(paiTable[1],0, needMinHuntable)
	local wanToPuNeedNum = needMinHuntable.needMinHunNum

	needMinHuntable.needMinHunNum = MAXHUNNUM
	getNeedHunPaiNumToBeHu(paiTable[2],0, needMinHuntable)
	local bingToPuNeedNum = needMinHuntable.needMinHunNum

	needMinHuntable.needMinHunNum = MAXHUNNUM
	getNeedHunPaiNumToBeHu(paiTable[3],0, needMinHuntable)
	local tiaoToPuNeedNum = needMinHuntable.needMinHunNum

	needMinHuntable.needMinHunNum = MAXHUNNUM
	getNeedHunPaiNumToBeHu(paiTable[4],0, needMinHuntable)
	local fengToPuNeedNum = needMinHuntable.needMinHunNum

	needNum = bingToPuNeedNum + tiaoToPuNeedNum + fengToPuNeedNum
	if needNum <= curHunNum then
		local wanPaiNum = #paiTable[1]
		local hasNum = curHunNum - needNum 
		if canHu(paiTable[1], hasNum, MAXHUNNUM, luanjiang) then
			return true
		end
	end

	needNum = wanToPuNeedNum + tiaoToPuNeedNum + fengToPuNeedNum
	if needNum <= curHunNum then
		local bingPaiNum = #paiTable[2]
		local hasNum = curHunNum - needNum 
		if canHu(paiTable[2], hasNum, MAXHUNNUM, luanjiang) then
			return true
		end
	end

	needNum = wanToPuNeedNum + bingToPuNeedNum + fengToPuNeedNum
	if needNum <= curHunNum then
		local tiaoPaiNum = #paiTable[3]
		local hasNum = curHunNum - needNum 
		if canHu(paiTable[3], hasNum, MAXHUNNUM, luanjiang) then
			return true
		end
	end

	needNum = wanToPuNeedNum + bingToPuNeedNum + tiaoToPuNeedNum
	if needNum <= curHunNum then
		local fengPaiNum = #paiTable[4]
		local hasNum = curHunNum - needNum 
		if canHu(paiTable[4], hasNum, MAXHUNNUM, luanjiang) then
			return true
		end
	end
	return false
end


--七对胡牌判断（已包含癞子）
local function testSevenHu(stackCards, curHunNum)
	local siglelen = 0
	local twolen = 0
	local threelen = 0
	local fourlen = 0
	for k, v in pairs(stackCards) do
		if v == 1 then
			siglelen = siglelen + 1
		elseif v == 2 then
			twolen = twolen + 1
		elseif v == 3 then
			threelen = threelen + 1
		elseif v == 4 then
			fourlen = fourlen + 1
		end
	end
	local leftHunNum = curHunNum - siglelen 
	if leftHunNum < 0 then
		return false
	end
	leftHunNum = leftHunNum - threelen
	if leftHunNum < 0 then
		return false
	end
	if siglelen + twolen + 2 * threelen + 2 * fourlen  + (leftHunNum / 2) == 7 then
		return true, fourlen
	end
	return false
end
--碰碰胡
local function testPengPengHu(cardInfo, stackCards, ischeckting, laiziCount)
    if next(cardInfo.chiCards) then
        return false
    end
    laiziCount = laiziCount or 0
    local count = 1
    --2张数量(只能是1对)
    if ischeckting then
        laiziCount = laiziCount + 1
    end
--    if ischeckting then
--        local pai_type = 1 --碰碰胡2种  3+1 2+2   1：2+2  2： 1+3
--        for i , k in pairs(stackCards) do
--            if k == 2 then
--                if pai_type ~= 1 then 
--                    return false
--                end
--                count = count - 1
--                if count < 0 then
--                    return false
--                end
--            elseif k == 1 then 
--                if count ~= 2 or pai_type ~= 1 then
--                    return false
--                end
--                pai_type = 2
--            end
--        end
--    else
        for i , k in pairs(stackCards) do
            if k == 2 then
                count = count - 1
                if count < 0 then
                    laiziCount = laiziCount - 1
                end
            elseif k == 1 or k ==4 then
                if count > 0 then
                    laiziCount = laiziCount - 1
                    count = count - 1
                else
                    laiziCount = laiziCount - 2
                end
            end
            if laiziCount < 0 then
                return false
            end
        end
--    end
    return true
end
--将将胡
local function testJiangJiangHu(cardInfo, stackCards, card)
    if next(cardInfo.chiCards) then
        return false
    end
    for i , k in pairs(cardInfo.pengCards) do
        if not check258(i) then
            return false
        end
    end
    for i, k in pairs(cardInfo.gangCards) do
        if not check258(i) then
            return false
        end
    end
    for i, k in pairs(stackCards) do 
        if not check258(i) then
            return false
        end
    end
    if card then
        if not check258(card) then
            return false
        end
    end
    return true
end
--判断是否都是同一类型的牌
local function testSingcolor(cardInfo, stackCards, card, laizi)
    local type = 0
    for i, k in pairs(stackCards) do
        if type == 0 and i ~= laizi then 
            type = getPaiType(i)
        end
        if type ~= getPaiType(i) and i ~= laizi then
            return false
        end
    end
    for i, k in pairs(cardInfo.pengCards) do
        if type ~= getPaiType(i) then
            return false
        end
    end
    for i, k in pairs(cardInfo.gangCards) do
        if type ~= getPaiType(i) then
            return false
        end
    end
    for i, k in pairs(cardInfo.chiCards) do
        if getPaiType(k[1]) ~= type then 
            return false
        end
    end
    if card then
        if getPaiType(card) ~= type and card ~= laizi then
            return false
        end
    end
    return true
end
-- 海底捞月  海底炮 

local hupai = {}
--乱将 就是可以不用258做将
--config = {}  .gang .qianggang .haidi .qianghaidi .tianhu .dihu
function hupai:check_can_hu(pai, cardInfo, config, game_config, laizi)
	local tmpcard = m_table.clone(pai)
	table.sort(tmpcard)
	--计算癞子数
	local curHunNum = 0
    for i = #tmpcard, 1 ,-1 do
        if tmpcard[i] == laizi then
            curHunNum = curHunNum + 1
            table.remove(tmpcard, i)
        end
    end
    local ret = {}
	--判断是否胡7对
	local tmpcardtable = cardDef:stackCards(tmpcard)
    local isHu, count = testSevenHu(tmpcardtable, curHunNum)
    --是否同一色（清一色）
    local issingleType = testSingcolor(cardInfo, tmpcardtable, nil,laizi)
    --全求人
    local allAsk = false
    --门清
    local menqing = false
    if #pai == 2 then
        allAsk = true 
    end
    if config.menqing and #pai == 14 then
        menqing = true
    end
    --乱将
    local luanjiang = false
    --全求人  青一色 天胡  可以乱将
    if issingleType or allAsk or config.tianhu then
        luanjiang = true
    end
	if isHu then
        if testJiangJiangHu(cardInfo, tmpcardtable) then
            ret.jiangjianghu = 1
            isHu = true
            syslog.info("testJiangJiangHu:胡了")
        end
        if count == 1 then
            ret.hao_seven_hu = 1
            syslog.info("hao_seven_hu:胡了")
        elseif count >= 2 then
            ret.shuang_hao_seven_hu = 1
             syslog.info("shuang_hao_seven_hu:胡了")
        else
            syslog.info("testSevenHu:胡了")
            ret.seven_hu = 1
        end
    else
        if testJiangJiangHu(cardInfo, tmpcardtable) then
            ret.jiangjianghu = 1
            isHu = true
            syslog.info("testJiangJiangHu:胡了")
        end
        if testPengPengHu(cardInfo, tmpcardtable, false,curHunNum) then
            ret.pengpenghu = 1
            syslog.info("testPengPengHu:胡了")
            isHu = true
        end
	    --判断正常胡牌
        if not isHu then
    		if not next(tmpcard) then
				isHu = true
			else
		        if testHuPai(tmpcard, 4, curHunNum, luanjiang) then
	                isHu = true
			        syslog.info("testHu:胡了")
		        else
	                isHu = false
			        syslog.info("testHu:没胡")
		        end
			end
        end
	end
    if isHu then
        if issingleType then
            ret.qingyise = 1
            syslog.info("testSingcolor:胡了")
        end
        if config.tianhu then
            ret.tianhu = 1
        end
        if config.dihu then
            ret.dihu = 1
        end
        if allAsk then
            ret.allask = 1
        end
        if config.qianggang then
            ret.qiangganghu = 1
        end
        if config.gang then
            ret.ganghua = 1
        end
        if config.gangshangpao then 
            ret.gangpao = 1
        end
        if menqing then
            ret.menqing = 1
        end
        if game_config.kaiwang and curHunNum == 0 then
            ret.nolaizihu = 1
        end
        if config.haidilao then
            ret.haidilao = 1
        end
        if config.haidipao then
            ret.haidipao = 1
        end
        if config.baoting then
            ret.baoting = 1
        end
        --什么都没有就是平湖
        if not next(ret) then
            ret.pinghu = 1
        end
    end
    return ret
end

function hupai:check_can_ting(pai, cardInfo, config, laizi)
	local tmpcard = m_table.clone(pai)
	table.sort(tmpcard)
	--计算癞子数
	local curHunNum = 1
    for i = #tmpcard, 1 ,-1 do
        if tmpcard[i] == laizi then
            curHunNum = curHunNum + 1
            table.remove(tmpcard, i)
        end
    end
	--判断是否胡7对
	local tmpcardtable = cardDef:stackCards(tmpcard)
--    local isHu, count = testSevenHu(tmpcardtable, curHunNum)
    --是否同一色（清一色）
    local issingleType = testSingcolor(cardInfo, tmpcardtable, card, laizi)
    --全求人
    local allAsk = false
    if #pai == 1 then
        allAsk = true
    end
    --乱将
    local luanjiang = false
    --全求人  青一色  可以乱将(天胡听牌不要算乱将)
    if issingleType or allAsk then 
        luanjiang = true
    end
    if testJiangJiangHu(cardInfo, tmpcardtable, card) then
        return true
    end
    if testPengPengHu(cardInfo, tmpcardtable, true, curHunNum) then
        return true
    end
	if not next(tmpcard) then
		return true
	end
	--判断正常胡牌
	if testHuPai(tmpcard, 4, curHunNum, luanjiang) then
        return true
	else
		syslog.info("testHu:没听")
        return false
	end
    return false
end

--起手小胡------------------------------------------------------------

function hupai:check_First_hu(stackCards, cards)
    local ret = {}
    local bigfour = {}
    local banban = true
    local cards_type = {}
    local liuliu = false
    local kezicard = {}
    for i, k in pairs (stackCards) do 
        --大四喜
        if k == 4 then
            table.insert(bigfour, i)
        end
        local _type, index = math.modf(i/10)
        --板板胡 没有一张是2，5，8
        if banban and check258(i) then
            banban = false
        end
        --缺一色  筒条万 缺一个种类
        cards_type[_type] = true
        --六六顺
        if k == 3 then 
            table.insert(kezicard , i)
        end
    end
    if next(bigfour) then
        ret.bigfour = bigfour
    end
    if banban then
        ret.banban = true
    end
    if #cards_type < 3 then
        ret.lose_one_color = true
    end
    if #kezicard > 1 then
        ret.liuliushun = kezicard
    end
    return ret
end


return hupai

