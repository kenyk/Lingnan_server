local skynet = require "skynet"
local sharedata = require "sharedata"


local handler = require "agent.handler"
local syslog = require "syslog"



local REQUEST = {}
handler = handler.new (REQUEST)

local user
local role_id
local room_address  --room services id 
local table_id
local chair_id

local fresh_time_list = os.time()
local fresh_time_dismiss = os.time()
local diff_time = 60 

handler:init (function (u)
	user = u
end)

function REQUEST:build_on_request_new_rooms()
	if user.room_address then
		return {code = 20006}
	end

	local uid = user.account
	self.uid = uid
	local r = skynet.call(".BUILD_ROOMS_SERVICE", "lua", "on_build_room",self)
	return r 
end

function REQUEST:get_batch_room_list()
	if user.room_address then
		return {code = 20006}
	end
	if fresh_time_list + 1 > os.time() then
		return {code = 20018}
	end
	fresh_time_list = os.time()
	local uid = user.account
	self.uid = uid
	local r, total = skynet.call(".BUILD_ROOMS_SERVICE", "lua", "get_room_info",self)
	return {code = 0, list = r, total = total}
end

function REQUEST:dismiss_batch_room()
	if user.room_address then
		return {code = 20006}
	end
	if fresh_time_dismiss + 1 > os.time() then
		return {code = 20018}
	end
	fresh_time_dismiss = os.time()
	local uid = user.account
	self.uid = uid
	local r = skynet.call(".BUILD_ROOMS_SERVICE", "lua", "dismiss_batch_room",self)
	return r 
end

function REQUEST:room_enter_room()
	if user.room_address then
		return {code = 20001}
	end
	local r,res = skynet.call(".BUILD_ROOMS_SERVICE", "lua", "get_room_service_id", self)
	if not r then
		return res
	end
    user.room_address = r.address
    user.room_name = r.room_name
    user.private_code = r.private_code
    local args = {}
    args.uid = user.account
    args.nickname = user.nickname or "test"..args.uid
    args.ip = user.ip or "127.0.0.1"
    args.address = skynet.self()
    local r, res = skynet.call(user.room_address, "lua", "room_enter_room", args)
    skynet.fork(function ()
    				if user and user.room_address then
	                	local s1, c1 = skynet.call(user.room_address, "lua", "room_sit_down", args.uid)
	                    if s1 == false and c1 and c1.chair_id then
	    	            	user.chair_id = c1.chair_id	
	                    end
	                    local s2, t2 = skynet.call(user.room_address, "lua", "room_enter_table", args.uid)
	                    if s2 == false and t2 and t2.table_id then
	    	                user.table_id = t2.table_id	
	                    end
	                end
                 end
                )
    return res
end


function REQUEST:room_exit_room()
	if not user.room_address then
		return {code = 20006}
	end
	local uid = user.account
	local r,res = skynet.call(user.room_address, "lua", "room_exit_room", uid)
	if r then
		user.room_address = nil
		user.room_name = nil
		user.table_id = nil
		user.chair_id = nil
	end
	return res
end

function REQUEST:room_enter_table()
	if not user.room_address then
		return {code = 20006}
    else
        return {code = 0}
	end
	local uid = user.account
	local r, res = skynet.call(user.room_address, "lua", "room_enter_table", uid)
	if r then
		user.table_id = res.table_id
	end
	return res
end


function REQUEST:room_exit_table()
	if not user.room_address or not user.table_id then
		return {code = -1}
	end
	local uid = user.account
	local r, res = skynet.call(user.room_address, "lua", "room_exit_table", uid)
	if r then
		user.chair_id = nil
		user.table_id = nil
	end
	return res
end

function REQUEST:room_sit_down()
	if not user.room_address or not user.table_id then
		return {code = -1}
    else
        return {code = 0}
	end
	local uid = user.account
	local r, res = skynet.call(user.room_address, "lua", "room_sit_down", uid)
	--table.printT(res)
	if r then
		user.chair_id = res.chair_id
	end
	return res
end

function REQUEST:room_stand_up()
	if not user.room_address or not user.chair_id then
		return {code = -1}
	end
	local uid = user.account
	local r,res = skynet.call(user.room_address, "lua", "room_stand_up", uid)
	if r then
		user.chair_id = nil
	end
	return res
end

function REQUEST:room_get_table_scene()
	if not user.room_address or not user.table_id then                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          
		return {code = -1}
	end
	local uid = user.account  
	local r,res = skynet.call(user.room_address, "lua", "room_get_table_scene", uid)
	--table.printT(res)
	return res
end

function REQUEST:room_get_ready()
	if not user.room_address or not user.chair_id then
		return {code = -1}
	end
	local uid = user.account
	local r, res =  skynet.call(user.room_address, "lua", "room_get_ready", uid)
	return res
	-- return res
end

function REQUEST:room_vote_dismiss_room()
	if not user.room_address or not user.chair_id then
		return {code = -1}
	end
	local uid = user.account
	local r, res = skynet.call(user.room_address, "lua", "room_vote_dismiss_room", uid, self)
	return res
end
function REQUEST:heartbeat()
	return {time = os.time()}
end

return handler

