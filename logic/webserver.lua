local skynet = require "skynet"
require "skynet.manager"
local socket = require "socket"
local httpd = require "http.httpd"
require "table_util"
local sockethelper = require "http.sockethelper"
local urllib = require "http.url"
local table = table
local string = string
local syslog = require "syslog"
local json = require "cjson"
local mode = ...
local httpc = require "http.httpc"
local datacenter = require "datacenter"

local http_ip = assert(skynet.getenv("http_ip"))

local httpStat = {

	total = {
		cnt = 0,
		time = 0.0,
		avg = 0.0,
	},
	create_room = {
		cnt = 0,
		time = 0.0,
		avg = 0.0,	
	},
	create_room_batch = {
		cnt = 0,
		time = 0.0,
		avg = 0.0,	
	},
	join_room = {
		cnt = 0,
		time = 0.0,
		avg = 0.0,	
	},	
	order = {
		cnt = 0,
		time = 0.0,
		avg = 0.0,	
	},
	game_over = {
		cnt = 0,
		time = 0.0,
		avg = 0.0,	
	},	
	pointLog = {
		cnt = 0,
		time = 0.0,
		avg = 0.0,	
	},		
}


local function HarborInfo()
	local function fmtStat(oneStat)
		local s = string.format("{harbor_id = %d, address = %d, out_ip = %s, num_entities = %d}",
			oneStat.harbor_id, oneStat.address, oneStat.out_ip, oneStat.num_entities)
		return s
	end
	local function httptStat(oneStat)
		local s = string.format("{cnt = %d, time = %.3f, avg = %.3f}",
			oneStat.cnt, oneStat.time, oneStat.avg)
		return s		
	end

	local statMsg = "harbor info:\n"
	statMsg = statMsg.."http rtt info:\n"
	statMsg = statMsg.."total : "..httptStat(httpStat.total).."\n"
	statMsg = statMsg.."create room : "..httptStat(httpStat.create_room).."\n"
	statMsg = statMsg.."create room batch : "..httptStat(httpStat.create_room_batch).."\n"
	statMsg = statMsg.."join room : "..httptStat(httpStat.join_room).."\n"
	statMsg = statMsg.."order : "..httptStat(httpStat.order).."\n"
	statMsg = statMsg.."game over : "..httptStat(httpStat.game_over).."\n"
	statMsg = statMsg.."point log : "..httptStat(httpStat.pointLog).."\n"

	return statMsg
end


local function dosqlStat(sql, startTime, endTime)
	local costTime = endTime - startTime

	httpStat.total.cnt  = httpStat.total.cnt + 1
	httpStat.total.time = httpStat.total.time + costTime
	httpStat.total.avg  = httpStat.total.time / httpStat.total.cnt

	if sql == "create_room" then
		httpStat.create_room.cnt  = httpStat.create_room.cnt + 1
		httpStat.create_room.time = httpStat.create_room.time + costTime
		httpStat.create_room.avg  = httpStat.create_room.time / httpStat.create_room.cnt
	elseif sql == "create_room_batch" then
		httpStat.create_room_batch.cnt  = httpStat.create_room_batch.cnt + 1
		httpStat.create_room_batch.time = httpStat.create_room_batch.time + costTime
		httpStat.create_room_batch.avg  = httpStat.create_room_batch.time / httpStat.create_room_batch.cnt	
	elseif sql == "join_room" then
		httpStat.join_room.cnt  = httpStat.join_room.cnt + 1
		httpStat.join_room.time = httpStat.join_room.time + costTime
		httpStat.join_room.avg  = httpStat.join_room.time / httpStat.join_room.cnt	
	elseif sql == "order" then
		httpStat.order.cnt  = httpStat.order.cnt + 1
		httpStat.order.time = httpStat.order.time + costTime
		httpStat.order.avg  = httpStat.order.time / httpStat.order.cnt	
	elseif sql == "game_over" then
		httpStat.game_over.cnt  = httpStat.game_over.cnt + 1
		httpStat.game_over.time = httpStat.game_over.time + costTime
		httpStat.game_over.avg  = httpStat.game_over.time / httpStat.game_over.cnt	
	elseif sql == "pointLog" then
		httpStat.pointLog.cnt  = httpStat.pointLog.cnt + 1
		httpStat.pointLog.time = httpStat.pointLog.time + costTime
		httpStat.pointLog.avg  = httpStat.pointLog.time / httpStat.pointLog.cnt		
	end	
end



httpc.timeout = 300  -- timeout == 3s
local http_request =
{
	create_room = "/GameService/addOrder?userId=$userId&appId=$appId&appCode=$appCode&token=$token&gameId=$gameId&useNum=$useNum&roomCate=$roomCate&orderType=$orderType",
	join_room = "/GameService/getUserInfo?userId=$userId&appId=$appId&appCode=$appCode&token=$token",
	order     = "/GameService/updateOrder?orderCode=$orderCode&status=$status&roomId=$roomId",
	redbag = "/GameService/redpackageSend?appId=$appId&appCode=$appCode&userIds=$userIds&orderCode=$orderCode&roomId=$roomId",
	pattern = "$([%w_]+)",
}
local http_request_club =
{
	create_room = "/GameClub/addOrder?userId=$userId&appId=$appId&appCode=$appCode&token=$token&gameId=$gameId&useNum=$useNum&roomCate=$roomCate&orderType=$orderType&clubId=$clubId&useDiamondNum=$useDiamondNum",
	create_room_batch = "/GameClub/batchAddOrder?userId=$userId&appId=$appId&appCode=$appCode&token=$token&gameId=$gameId&useNum=$useNum&orderType=$orderType&clubId=$clubId&useDiamondNum=$useDiamondNum&roomNum=$roomNum",
	join_room = "/GameClub/getUserInfo?userId=$userId&appId=$appId&appCode=$appCode&token=$token&clubId=$clubId&orderCode=$orderCode",
	order     = "/GameClub/updateOrder?orderCode=$orderCode&status=$status&roomId=$roomId",
	game_over = "/GameClub/gameOver?orderCode=$orderCode&roomId=$roomId&bigWinner=$bigWinner",
	pointLog  = "/GameClub/pointLog?orderCode=$orderCode&roomId=$roomId&logInfo=$logInfo",

	pattern = "$([%w_]+)",
}



if mode == "agent" then


local function create_room_http(args)
	if not args or not (tonumber(args.game_count) == 8 or tonumber(args.game_count) == 16)  then
		return {status = 1,errCode = -10,error = "参数不完整" }
	end
	if tonumber(args.game_count) == 8 then
		args.useNum = 1
	elseif tonumber(args.game_count) == 16 then
		args.useNum = 2
	else
		return {status = 1,errCode = -10,error = "参数不正确" }
	end
	if not args.gameId then
		return {status = 1,errCode = -10,error = "参数不完整" }
	end 
	local uid = assert(tonumber(args.userId))
	--if datacenter.get("on_player", uid) then
	--	syslog.warning("create  room  on_player not nil : %d", uid)
	--	return {status = 1,errCode = -3, error = "erro" }
	--end	
	--syslog.debug("gameId : %s" ,args.gameId)
	--antiCheatLon 经度
	--antiCheatLat 纬度 
	local str 
	if  args.clubId and args.useDiamondNum then
		str =  string.gsub(http_request_club.create_room, http_request_club.pattern, args)
	else
		str =  string.gsub(http_request.create_room, http_request.pattern, args)
	end

	local header = {}
	local send_time = skynet.time()
	local status, body = httpc.get(http_ip, str, header)
	dosqlStat("create_room", send_time, skynet.time())
	syslog.debugf("create room anywhere sql:%s cost time :%s",str, skynet.time() - send_time)
	

	if status ~= 200 then
		return {status = 1,errCode = -11,error = "请求错误返回" }
	end
	body = json.decode(body)
	table.printR(body)
	if  body.errCode and tonumber(body.errCode) ~= 0 then
		return {status = 1, errCode = body.errCode, error = body.error }
	end

	return skynet.call("CENTER_MGR", "lua","create_room_anywhere", args, status, body)
end 





local function create_room_http_batch(args)
	if not args or not (tonumber(args.game_count) == 8 or tonumber(args.game_count) == 16)  then
		return {status = 1,errCode = -10,error = "参数不完整" }
	end
--[[
	if tonumber(args.game_count) == 8 then
		args.useNum = 1
	elseif tonumber(args.game_count) == 16 then
		args.useNum = 2
	else
		return {status = 1,errCode = -10,error = "参数不正确" }
	end
	]]
	if not args.gameId then
		return {status = 1,errCode = -10,error = "参数不完整" }
	end 
	local uid = assert(tonumber(args.userId))
	--if datacenter.get("on_player", uid) then
	--	syslog.warning("create  room  on_player not nil : %d", uid)
	--	return {status = 1,errCode = -3, error = "erro" }
	--end	
	--syslog.debug("gameId : %s" ,args.gameId)
	--antiCheatLon 经度
	--antiCheatLat 纬度 
	if not args.roomNum or (args.roomNum and tonumber(args.roomNum) > 30) then
		return {status = 1,errCode = -202,error = "请求错误返回" }
	end



	local str 
	if  args.clubId and args.useDiamondNum and args.orderType  then
		str =  string.gsub(http_request_club.create_room_batch, http_request_club.pattern, args)
	end
	local header = {}
	local send_time = skynet.time()
	local status, body = httpc.get(http_ip, str, header)
	dosqlStat("create_room_batch", send_time, skynet.time())
	syslog.debugf("create_room_batch sql:%s cost time :%s",str, skynet.time() - send_time)

	if status ~= 200 then
		return {status = 1,errCode = -11,error = "请求错误返回" }
	end
	body = json.decode(body)
	table.printR(body)
	if  body.errCode and tonumber(body.errCode) ~= 0 then
		return {status = 1, errCode = body.errCode, error = body.error }
	end 
	return skynet.call("CENTER_MGR", "lua","create_room_anywhere_batch", args, status, body, count)
end 








local function query_room_http(args)
	local enter_code = args.enter_code
	if not enter_code then
		return {status = 1,errCode = -1,error = "缺少 enter code" }
	end
	local uid = assert(tonumber(args.userId))
	--if datacenter.get("on_player", uid) then
	--	syslog.warning("query room  on_player not nil : %d", uid)
	--	return {status = 1,errCode = -3, error = "erro" }
	--end
	local room = datacenter.get("room_manager", enter_code)
	if not room then
		return {status = 1,errCode = -2,error = "房间不存在" }
	end
	local address = assert(room.address)
	local choose = assert(room.service_id)

	local header = {}
	local str = nil
	if   room.clubId then
		args.clubId = room.clubId
		args.orderCode = room.orderCode
		str =  string.gsub(http_request_club.join_room, http_request_club.pattern, args)
	else
		str =  string.gsub(http_request.join_room, http_request.pattern, args)
	end

	
	local send_time = skynet.time()
	local status, body = httpc.get(http_ip, str, header)

	dosqlStat("join_room", send_time, skynet.time())
	syslog.debugf("query code sql : %s , cost time :%s ",str, skynet.time() - send_time)
	if status ~= 200 then
		return {status = 1,errCode = -11,error = "请求错误返回" }
	end
	body = json.decode(body)
	if body.errCode and tonumber(body.errCode)  ~= 0 then
		return {status = 1, errCode = body.errCode, error = body.error }
	end

	return skynet.call("CENTER_MGR", "lua","query_room", args, status, body)
end




local function response(id, ...)
	local ok, err = httpd.write_response(sockethelper.writefunc(id), ...)
	if not ok then
		-- if err == sockethelper.socket_error , that means socket closed.
		syslog.debug(string.format("fd = %d, %s", id, err))
	end
end

skynet.start(function()
	skynet.dispatch("lua", function (_,_,id)
		socket.start(id)
		-- limit request body size to 8192 (you can pass nil to unlimit)
		local code, url, method, header, body = httpd.read_request(sockethelper.readfunc(id), 8192)
		if code then
			if code ~= 200 then
				response(id, code)
			else
				local path, query = urllib.parse(url)
				local tmp = {}
				if query then
					local q = urllib.parse_query(query)
					table.printR(q)
					if path == "/create_room" and q['userId'] and q['appId'] and  q['appCode'] and  q['token'] and q['useNum'] and q['rate'] and q['orderType'] then
						tmp = create_room_http(q)
					elseif path == "/create_room_batch" and q['userId'] and q['appId'] and  q['appCode'] and  q['token'] and q['roomNum'] and q['clubId'] and q['orderType'] then
						tmp = create_room_http_batch(q)
					elseif path == "/query_room" and q['userId'] and q['appId'] and  q['appCode'] and  q['token']  then
						tmp = query_room_http(q)
					elseif path == "/player_status" and  q['userId'] then
						tmp = skynet.call("CENTER_MGR", "lua","query_status", q )
					else
						syslog.warning("webserver client request args  wrong ")
					end
					table.printR(tmp)
				end
				
				response(id, code, json.encode(tmp))
			end
		else
			if url == sockethelper.socket_error then
				syslog.debug("socket closed")
			else
				syslog.debug(url)
			end
		end
		socket.close(id)
	end)
	skynet.info_func(HarborInfo)
end)
elseif mode == "inner_agent" then

local CMD = {}

function CMD.update_order_status(order_id, stat, enter_code ,clubId)
	local header = {}
	local str
	if clubId then
		str =  string.gsub(http_request_club.order, http_request_club.pattern, {orderCode = order_id, status = stat, roomId = enter_code})
	else
		str =  string.gsub(http_request.order, http_request.pattern, {orderCode = order_id, status = stat, roomId = enter_code})
	end
	local send_time = skynet.time()
	local status, body = httpc.get(http_ip, str, header)
	dosqlStat("order", send_time, skynet.time())
	syslog.debugf("update order sql : %s , cost time :%s ",str, skynet.time() - send_time)
	if status == 200 then
		syslog.debug("update order status : "..body)
	else
		syslog.errf("error reponese  from wms order_id,status,error_code: %s, %s,%d ",order_id,stat,status)
	end
end
function CMD.update_room_servers(args)
	if args then
		local header = {}
		local str =  string.gsub(http_request_club.game_over, http_request_club.pattern, args)
		local send_time = skynet.time()
        local status, body = httpc.get(http_ip, str, header)
		dosqlStat("game_over", send_time, skynet.time())
		syslog.debugf("game_over sql : %s , cost time :%s ",str, skynet.time() - send_time)
		if status == 200 then
			syslog.debug("update game_over status : "..body)
		else
			syslog.errf("error reponese  from wms game_over status,error_code: %s, %d ",args.orderCode,status)
		end		
	end

end

function CMD.update_pointlog_servers(args)
	if args then
		local header = {}
		local str =  string.gsub(http_request_club.pointLog, http_request_club.pattern, args)
		local send_time = skynet.time()
        local status, body = httpc.get(http_ip, str, header)
		dosqlStat("pointLog", send_time, skynet.time())
		syslog.debugf("pointLog sql : %s , cost time :%s ",str, skynet.time() - send_time)
		if status == 200 then
			syslog.debug("update game_over status : "..body)
		else
			syslog.errf("error reponese  from wms pointLog status,error_code: %s, %d ",args.orderCode,status)
		end		
	end

end

function CMD.send_red_bag(args)
    if args then
        local header = {}
        local str = string.gsub(http_request.redbag, http_request.pattern, args)
        local send_time = skynet.time()
        local status, body = httpc.get(http_ip, str, header)
		syslog.debugf("red bag : %s , cost time :%s ",str, skynet.time() - send_time)
		if status == 200 then
			syslog.debug("update red bag status : "..body)
		else
			syslog.err("error reponese  from wms red bag status,error_code: %s, %d ",args.orderCode,status)
		end	
    end
end

skynet.start(function()
	skynet.dispatch("lua", function (_session,_, command, ...)
		local f = CMD[command]
		
		if not f then
			syslog.warningf ("unhandled message(%s)", command) 
			if _session ~= 0  then
				return skynet.ret ()
			end
		end

		local ok, ret = pcall (f, ...)
		if not ok then
			syslog.warningf ("handle message(%s) failed : %s", command, ret) 
			kick_self ()
			if _session ~= 0  then
				return skynet.ret ()
			end
		end
		if _session ~= 0 then
			skynet.retpack (ret)
		end
	end)
	skynet.info_func(HarborInfo)
end)

else

skynet.start(function()
	local agent = {}
	for i= 1, 15 do
		agent[i] = skynet.newservice(SERVICE_NAME, "agent")
	end
	local balance = 1
	local id = socket.listen("0.0.0.0", 8001)
	syslog.debug("Listen web port 8001")
	socket.start(id , function(id, addr)
		--syslog.debug(string.format("%s connected, pass it to agent :%08x", addr, agent[balance]))
		skynet.send(agent[balance], "lua", id)
		balance = balance + 1
		if balance > #agent then
			balance = 1
		end
	end)
	local inner_agent = {}
	for i= 1, 5 do
		inner_agent[i] = skynet.newservice(SERVICE_NAME, "inner_agent")
	end	
	local inner_balance = 1
	skynet.dispatch("lua", function(_session,_, command, ...)
								skynet.send(inner_agent[inner_balance], "lua", command, ...)
								inner_balance = inner_balance + 1
								if inner_balance > #inner_agent then
									inner_balance = 1
								end							
							end)
end)
	skynet.register "WEBSERVER_MGR"
end