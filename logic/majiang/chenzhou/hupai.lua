local cardDef = require "majiang.cardDef"
local syslog = require "syslog"
local math = math
local table = table

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

local function test2Combine(pai_1, pai_2)
	if pai_1 == pai_2 then
		return true
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


local function canHu(pai, hunNum, MAXHUNNUM)
	local paiNum = #pai
    if #pai == 0 then
        return -1
    end
    local needlaizi = 9
	local copyPai = m_table.clone(pai)
	for i = 1, #copyPai do
		if i == #copyPai then
			if hunNum > 0 then
				hunNum = hunNum -1
				local tmpcard = m_table.clone(copyPai)
				m_table.removebyvalue(tmpcard, copyPai[i])
				local needMinHuntable = {}
				needMinHuntable.needMinHunNum = MAXHUNNUM
				getNeedHunPaiNumToBeHu(tmpcard, 0, needMinHuntable)
--				if needMinHuntable.needMinHunNum <= hunNum and needlaizi > hunNum - needMinHuntable.needMinHunNum then
                if needlaizi > needMinHuntable.needMinHunNum then
                    needlaizi =  needMinHuntable.needMinHunNum
--					return hunNum - needMinHuntable.needMinHunNum
				end
				hunNum = hunNum + 1
			end
		else
			if i + 2 == #copyPai or copyPai[i] ~= copyPai[i + 2] then
				if test2Combine(copyPai[i], copyPai[i+1]) then
					local tmpcard = m_table.clone(copyPai)
					m_table.removebyvalue(tmpcard, copyPai[i])
					m_table.removebyvalue(tmpcard, copyPai[i+1])
					local needMinHuntable = {}
					needMinHuntable.needMinHunNum = MAXHUNNUM
					getNeedHunPaiNumToBeHu(tmpcard, 0,needMinHuntable)
--					if needMinHuntable.needMinHunNum <= hunNum and needlaizi > hunNum - needMinHuntable.needMinHunNum then
--                        needlaizi = hunNum - needMinHuntable.needMinHunNum
--						return hunNum - needMinHuntable.needMinHunNum
                    if needlaizi > needMinHuntable.needMinHunNum then
                        needlaizi =  needMinHuntable.needMinHunNum
					end
				end
			end
			if hunNum >0 and copyPai[i] ~= copyPai[i+1] then
				hunNum = hunNum -1
				local tmpcard = m_table.clone(copyPai)
				m_table.removebyvalue(tmpcard, copyPai[i])
				local needMinHuntable = {}
				needMinHuntable.needMinHunNum = MAXHUNNUM
				getNeedHunPaiNumToBeHu(tmpcard, 0,needMinHuntable)
--				if needMinHuntable.needMinHunNum <= hunNum and needlaizi > hunNum - needMinHuntable.needMinHunNum then
--                    needlaizi = hunNum - needMinHuntable.needMinHunNum
--					return hunNum - needMinHuntable.needMinHunNum
                if needlaizi > needMinHuntable.needMinHunNum then
                    needlaizi =  needMinHuntable.needMinHunNum
				end
				hunNum = hunNum + 1
			end
		end
	end
	return hunNum - needlaizi
end

local function testHuPai(pai, MAXHUNNUM,curHunNum)
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
    local wanToPuNeedNum 
    local bingToPuNeedNum 
    local tiaoToPuNeedNum 
    local fengToPuNeedNum 
    needMinHuntable.needMinHunNum = MAXHUNNUM
    local count = canHu(paiTable[1], curHunNum, MAXHUNNUM)
    if count >= 0 then
        if not bingToPuNeedNum then
            getNeedHunPaiNumToBeHu(paiTable[2],0, needMinHuntable)
            bingToPuNeedNum = needMinHuntable.needMinHunNum
        end 
        if count >= bingToPuNeedNum then
            if not tiaoToPuNeedNum then
                needMinHuntable.needMinHunNum = MAXHUNNUM
                getNeedHunPaiNumToBeHu(paiTable[3],0, needMinHuntable)
                tiaoToPuNeedNum = needMinHuntable.needMinHunNum
            end
            if count >= bingToPuNeedNum + tiaoToPuNeedNum then
                if not fengToPuNeedNum then
                    needMinHuntable.needMinHunNum = MAXHUNNUM
                    getNeedHunPaiNumToBeHu(paiTable[4],0, needMinHuntable)
                    fengToPuNeedNum = needMinHuntable.needMinHunNum
                end
                if count >= bingToPuNeedNum + tiaoToPuNeedNum + fengToPuNeedNum then
                    return true
                end
            end
        end
    end
    count = canHu(paiTable[2], curHunNum, MAXHUNNUM)
    if count >= 0 then
        if not wanToPuNeedNum then
            needMinHuntable.needMinHunNum = MAXHUNNUM
            getNeedHunPaiNumToBeHu(paiTable[1],0, needMinHuntable)
            wanToPuNeedNum = needMinHuntable.needMinHunNum
        end 
        if count >= wanToPuNeedNum then
            if not tiaoToPuNeedNum then
                needMinHuntable.needMinHunNum = MAXHUNNUM
                getNeedHunPaiNumToBeHu(paiTable[3],0, needMinHuntable)
                tiaoToPuNeedNum = needMinHuntable.needMinHunNum
            end
            if count >= tiaoToPuNeedNum + wanToPuNeedNum then
                if not fengToPuNeedNum then
                    needMinHuntable.needMinHunNum = MAXHUNNUM
                    getNeedHunPaiNumToBeHu(paiTable[4],0, needMinHuntable)
                    fengToPuNeedNum = needMinHuntable.needMinHunNum
                end
                if count >= wanToPuNeedNum + tiaoToPuNeedNum + fengToPuNeedNum then
                    return true
                end
            end
        end
    end
    count = canHu(paiTable[3], curHunNum, MAXHUNNUM)
    if count >= 0 then
        if not wanToPuNeedNum then
            needMinHuntable.needMinHunNum = MAXHUNNUM
            getNeedHunPaiNumToBeHu(paiTable[1],0, needMinHuntable)
            wanToPuNeedNum = needMinHuntable.needMinHunNum
        end 
        if count >= wanToPuNeedNum then
            if not bingToPuNeedNum then
                needMinHuntable.needMinHunNum = MAXHUNNUM
                getNeedHunPaiNumToBeHu(paiTable[2],0, needMinHuntable)
                bingToPuNeedNum = needMinHuntable.needMinHunNum
            end
            if count >= bingToPuNeedNum + wanToPuNeedNum then
                if not fengToPuNeedNum then
                    needMinHuntable.needMinHunNum = MAXHUNNUM
                    getNeedHunPaiNumToBeHu(paiTable[4],0, needMinHuntable)
                    fengToPuNeedNum = needMinHuntable.needMinHunNum
                end
                if count >= bingToPuNeedNum + wanToPuNeedNum + fengToPuNeedNum then
                    return true
                end
            end
        end
    end
    count = canHu(paiTable[4], curHunNum, MAXHUNNUM)
    if count >= 0 then
        if not wanToPuNeedNum then
            needMinHuntable.needMinHunNum = MAXHUNNUM
            getNeedHunPaiNumToBeHu(paiTable[1],0, needMinHuntable)
            wanToPuNeedNum = needMinHuntable.needMinHunNum
        end 
        if count >= wanToPuNeedNum then
            if not bingToPuNeedNum then
                needMinHuntable.needMinHunNum = MAXHUNNUM
                getNeedHunPaiNumToBeHu(paiTable[2],0, needMinHuntable)
                bingToPuNeedNum = needMinHuntable.needMinHunNum
            end
            if count >= bingToPuNeedNum + wanToPuNeedNum then
                if not tiaoToPuNeedNum then
                    needMinHuntable.needMinHunNum = MAXHUNNUM
                    getNeedHunPaiNumToBeHu(paiTable[3],0, needMinHuntable)
                    tiaoToPuNeedNum = needMinHuntable.needMinHunNum
                end
                if count >= bingToPuNeedNum + tiaoToPuNeedNum + wanToPuNeedNum then
                    return true
                end
            end
        end
    end
    return false
end

--七对胡牌判断（已包含癞子）
local function testSevenHu(stackCards, curHunNum)
    local leftHunNum = curHunNum 
    for i , k in pairs(stackCards) do
        if k ~= 2 and k ~= 4 then
            leftHunNum = leftHunNum - 1
        end
    end
    if leftHunNum < 0 then
        return false
    end
	return true
end

local hupai = {}
function hupai:check_can_hu(pai, MAXHUNNUM, seven_hu)
	local tmpcard = m_table.clone(pai)
	table.sort(tmpcard)
	--计算癞子数
	local curHunNum = 0
	if MAXHUNNUM ~= 0 then
        for i = #tmpcard, 1 ,-1 do
            if tmpcard[i] == 45 then
                curHunNum = curHunNum + 1
                table.remove(tmpcard, i)
            end
        end
	end

	--判断是否胡7对(14张手牌才能七小对)
	if seven_hu and (#tmpcard+curHunNum) == 14 then
		local tmpcardtable = cardDef:stackCards(tmpcard)
		if testSevenHu(tmpcardtable, curHunNum) then
			syslog.info("testSevenHu:胡了")
			return true
		end
	end

	--判断正常胡牌
	if not next(tmpcard) then
		return true
	end
	if testHuPai(tmpcard, 4, curHunNum) then
		syslog.info("testHu:胡了")
		return true
	else
		syslog.info("testHu:没胡")
		return false
	end
end

return hupai

