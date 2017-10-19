local skynet = require "skynet"
local sharedata = require "sharedata"
local handler = require "agent.handler"
local syslog = require "syslog"



local REQUEST = {}
handler = handler.new (REQUEST)

local user
local role_id

handler:init (function (u)
	user = u
end)

function REQUEST:game_out_card()
	if not user.room_address or not user.chair_id then
		return {code = -1}
	end
	local uid = user.account
	local r,res = skynet.call(user.room_address,"lua","game_out_card",uid, self)
	return res
end


function REQUEST:game_peng_card()
	if not user.room_address or not user.chair_id then
		return {code = -1}
	end
	local uid = user.account
	local r,res = skynet.call(user.room_address, "lua", "game_peng_card", uid, self)
	return res
end


function REQUEST:game_gang_card()
	if not user.room_address or not user.chair_id then
		return {code = -1}
	end
	local uid = user.account
	local r,res = skynet.call(user.room_address, "lua", "game_gang_card", uid, self)
	return res
end

function REQUEST:game_bu_card()
	if not user.room_address or not user.chair_id then
		return {code = -1}
	end
	local uid = user.account
	local r,res = skynet.call(user.room_address, "lua", "game_bu_card", uid, self)
	return res
end

function REQUEST:game_chi_card()
	if not user.room_address or not user.chair_id then
		return {code = -1}
	end
	local uid = user.account
	local r,res = skynet.call(user.room_address, "lua", "game_chi_card", uid, self)
	return res
end

function REQUEST:game_hu_card()
	if not user.room_address or not user.chair_id then
		return {code = -1}
	end
	local uid = user.account
	local r,res = skynet.call(user.room_address, "lua", "game_hu_card", uid, self)
	return res
end

function REQUEST:game_cancel_action()
	if not user.room_address or not user.chair_id then
		return {code = -1}
	end
	local uid = user.account
	local r,res = skynet.call(user.room_address, "lua", "game_cancel_action", uid, self)
	return res
end

function REQUEST:game_reconnect_gameinfo()
	if not user.room_address or not user.chair_id then
		return {code = -1}
	end
	local uid = user.account
	local r,res = skynet.call(user.room_address, "lua", "game_reconnect_gameinfo", uid, self)
	return res
end

function REQUEST:game_talk_and_picture()
	if not user.room_address or not user.chair_id then
		return {code = -1}
	end
	local uid = user.account
	local r,res = skynet.call(user.room_address, "lua", "game_talk_and_picture", uid, self)
	return res
end

function REQUEST:game_first_hu()
	if not user.room_address or not user.chair_id then
		return {code = -1}
	end
	local uid = user.account
	local r,res = skynet.call(user.room_address, "lua", "game_first_hu", uid, self)
	return res
end

function REQUEST:game_piao_point()
    if not user.room_address or not user.chair_id then
        return {code = -1}
    end
    local uid = user.account
    local r, res = skynet.call(user.room_address, "lua", "game_piao_point", uid, self)
    return res
end

function REQUEST:game_ting_card()
    if not user.room_address or not user.chair_id then
        return {code = -1}
    end
    local uid = user.account
    local r, res = skynet.call(user.room_address, "lua", "game_ting_card", uid, self)
    return res
end

function REQUEST:game_haidi_card()
    if not user.room_address or not user.chair_id then
        return {code = -1}
    end
    local uid = user.account
    local r, res = skynet.call(user.room_address, "lua", "game_haidi_card", uid, self)
    return res
end

return handler

