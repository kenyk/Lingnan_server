local skynet = require "skynet"
require "skynet.manager"

local json = require "cjson"
local datacenter = require "datacenter"
local harbor = require "skynet.harbor"
require "table_util"
local command = {}
local assert = assert
local tonumber = tonumber

local syslog = require "syslog"
local httpc = require "http.httpc"
httpc.timeout = 100   -- timeout
local room_servers_map = {} -- {harbor , "ip:port", num}

local http_ip = assert(skynet.getenv("http_ip"))
local math = math

local max_habor_entities = 2000


local function HarborInfo()
	local function fmtStat(oneStat)
		local s = string.format("{harbor_id = %d, address = %d, out_ip = %s, num_entities = %d}",
			oneStat.harbor_id, oneStat.address, oneStat.out_ip, oneStat.num_entities)
		return s
	end

	local statMsg = "harbor info:\n"
	for k, v in pairs(room_servers_map) do
		statMsg = statMsg..k.." : "..fmtStat(v).."\n"
	end
	return statMsg
end




local function find_best_room_server(ismatch)  -- 优先游戏当地节点服务器，若无游戏当地节点服务器者中山机房,ismatch 比赛服务器默认在harbor 100以后
	local best = 1
	local numEntities = 0x7fffffff
	local filter ={}
	if ismatch == true then
		best = nil  --暂时屏蔽 正式服开启
		for k,v in pairs(room_servers_map) do
			if k >= 100 and v.num_entities <= numEntities then
				best = k
				numEntities = v.num_entities
			end
		end
		return 	best	
	else
		for k,v in pairs(room_servers_map) do
			if k ~= 1 and k < 100 and v.num_entities <= numEntities then
				best = k
				numEntities = v.num_entities
			end
		end
	end
	return best
end


function command.REGISTER_COMPONENT(harbor_id, address, out_ip, num_entities, world)
	if room_servers_map[harbor_id] then
		syslog.errf("on_component_init erro duplicate harbor_id : %d",harbor_id)
		error()
	end
	syslog.debugf("on_component_init add  harbor_id : %d,%d,%s,%d",harbor_id,address, out_ip, num_entities, world)
	room_servers_map[harbor_id] = {harbor_id = harbor_id, address = address , out_ip = out_ip , num_entities = num_entities, world = world}
	if harbor_id ~= 1 then
		skynet.timeout(0, function()
									syslog.debugf("harbor  connected %d, %s",harbor_id,type(harbor_id))
									harbor.connect(harbor_id)
									harbor.link(harbor_id)
									room_servers_map[harbor_id] = nil
									syslog.debugf("harbor  disconnected %d",harbor_id)
						  end)
	end
end


local ks_manager_user = "PLAYER_MANAGER_%d"

function command.CREATE_ROOM_ANYWHERE(args, status, body)
	local uid = assert(tonumber(args.userId))
	local clubId = args.clubId
	local antiCheatRoom, antiCheatLon ,antiCheatLat   = args.antiCheat, args.antiCheatLon , args.antiCheatLat

	if antiCheatRoom and tonumber(antiCheatRoom) == 1 then  -- 开启反作弊房间
		if not antiCheatLon or not antiCheatLat then
			return {status = 1,errCode = -100,error = "gps" }
		end
		antiCheatRoom = true
	end 

	--table.printT(body)
	if status == 200 then
		--table.printR(body)
		if body.errCode == 0 and body.data.orderCode then	
			if 	body.data.isNew == "1"  then
	 			local best_id = find_best_room_server()
				if best_id then
				    local enter_code = string.format("%06d",math.random(100000,999999))
				    local _cnt = 1
				    while(datacenter.get("room_manager",  enter_code) ~= nil) do
						enter_code = string.format("%06d",math.random(100000,999999))
						if _cnt > 100 then
							syslog.err("create room generate enter code  timeout:")
							return {status = 1,errCode = -1,error = "erro" }
						end
						_cnt = _cnt + 1
				    end
				    			
					local re = skynet.call(room_servers_map[best_id].address, "lua","on_build_room", {
																										enter_code = enter_code, orderCode = body.data.orderCode, uid = uid, 
																									  	player_count = assert(tonumber(args.player_count)), rate = assert(tonumber(args.rate)), 
																									  	game_count = assert(tonumber(args.game_count)), data = args.data, clubId = clubId,
																									  	gameId = assert(tonumber(args.gameId))})
					--table.printR(re)
					if re and re.code == 0 then
						local antiCheat = {}
						local antiCheatInfo = {}
						antiCheatInfo.antiCheatLat = antiCheatLat
						antiCheatInfo.antiCheatLon = antiCheatLon
						antiCheat[uid] = antiCheatInfo
						room_servers_map[best_id].num_entities = room_servers_map[best_id].num_entities + 1
						datacenter.set("room_manager"  , re.enter_code, {
																			address = re.address, num = 0, service_id = best_id ,private_code = re.private_code, clubId = clubId, orderCode = body.data.orderCode,
																			antiCheat = antiCheat, uid = uid, ip = {body.data.ip},
																			antiCheatRoom = antiCheatRoom
																		}
									  )
						skynet.call(".DBREDIS", "lua", "hmset" , string.format(ks_manager_user, uid), {"enter_code", re.enter_code,"private_code", re.private_code})
						skynet.call(".DBREDIS", "lua", "expire", string.format(ks_manager_user, uid), 100 * 3600 * 24)
						return {status = 1, errCode = re.code, error = "success", data = {enter_code = re.enter_code }}
					end
				end
			elseif body.data.isNew == "0" then
				local redis_code = skynet.call(".DBREDIS", "lua", "hmget", string.format(ks_manager_user, uid), {"enter_code", "private_code"})
				
				if  redis_code and redis_code[1] and redis_code[2] then  -- query from redis for enter_code  and private_code
					local center_code = datacenter.get("room_manager" , redis_code[1] )
					if center_code and  tonumber(redis_code[2]) == center_code.private_code then -- player enter code in room manager and player private code equal room manager  
						return {status = 1, errCode = 0, error = "success", data = {enter_code = redis_code[1] }}
					end
				end
				syslog.warningf(" CREATE_ROOM_ANYWHERE isNew == 0 and  enter_code == nil uid, orderCode: %d, %s",uid, body.data.orderCode)
		 		local best_id = find_best_room_server()
				if best_id then
					local enter_code = string.format("%06d",math.random(100000,999999))
					local _cnt = 1
					while(datacenter.get("room_manager",  enter_code) ~= nil) do
						enter_code = string.format("%06d",math.random(100000,999999))
						if _cnt > 100 then
							syslog.err("create room generate enter code  timeout:")
							return {status = 1,errCode = -1,error = "erro" }
						end
						_cnt = _cnt + 1
					end
					    			
					local re = skynet.call(room_servers_map[best_id].address, "lua","on_build_room", {
																									    enter_code = enter_code, orderCode = body.data.orderCode, uid = uid, 
																										player_count = assert(tonumber(args.player_count)), rate = assert(tonumber(args.rate)), 
																										game_count = assert(tonumber(args.game_count)), data = args.data, clubId = clubId,
																										gameId = assert(tonumber(args.gameId))})
						--table.printR(re)
					if re and re.code == 0 then
						local antiCheat = {}
						local antiCheatInfo = {}
						antiCheatInfo.antiCheatLat = antiCheatLat
						antiCheatInfo.antiCheatLon = antiCheatLon
						antiCheat[uid] = antiCheatInfo
						room_servers_map[best_id].num_entities = room_servers_map[best_id].num_entities + 1
						datacenter.set("room_manager"  , re.enter_code, {
																			address = re.address, num = 0, service_id = best_id ,private_code = re.private_code, clubId = clubId, orderCode = body.data.orderCode,
																			antiCheat = antiCheat, uid = uid, ip = {body.data.ip},
																			antiCheatRoom = antiCheatRoom 
																		}
									  )
						skynet.call(".DBREDIS", "lua", "hmset" , string.format(ks_manager_user, uid), {"enter_code", re.enter_code, "private_code", re.private_code})
						skynet.call(".DBREDIS", "lua", "expire", string.format(ks_manager_user, uid), 100 * 3600 * 24)
						return {status = 1, errCode = re.code, error = "success", data = {enter_code = re.enter_code }}
					end
				end
			end
		end
	end		
	return {status = 1,errCode = -12,error = "status 错误" }	
end


function command.CREATE_ROOM_ANYWHERE_BATCH(args, status, body)
	local uid = assert(tonumber(args.userId))
	local clubId = args.clubId
--[[
	if antiCheatRoom and tonumber(antiCheatRoom) == 1 then  -- 开启反作弊房间
		if not antiCheatLon or not antiCheatLat then
			return {status = 1,errCode = -100,error = "gps" }
		end
		antiCheatRoom = true
	end 
]]
	if status == 200 then
		--table.printR(body)
		if body.errCode == 0 and body.data.orderCodes then	
			local total = #body.data.orderCodes
			if total > 30 then
				return {status = 1,errCode = -202,error = "fail" }	
			end

	 		local best_id = find_best_room_server(true)
			if best_id then
				if room_servers_map[best_id].num_entities >= max_habor_entities then
					return {status = 1, errCode = -201, error = "fail"}
				end
				local enter_code_set = {}
				for i = 1, total do
					local enter_code = string.format("%06d",math.random(100000,999999))
					local _cnt = 1
					while(datacenter.get("room_manager",  enter_code) ~= nil) do
					    enter_code = string.format("%06d",math.random(100000,999999))
						if _cnt > 100 then
							syslog.err("create room generate enter code  timeout:")
							return {status = 1,errCode = -1,error = "erro" }
						end
						_cnt = _cnt + 1
					end
					enter_code_set[#enter_code_set + 1 ] = enter_code
				end
			    local re = skynet.call(room_servers_map[best_id].address, "lua","on_build_room_batch", {
																										enter_code_set = enter_code_set, orderCode = body.data.orderCodes, uid = uid, 
																									  	player_count = assert(tonumber(args.player_count)), rate = assert(tonumber(args.rate)), 
																									  	game_count = assert(tonumber(args.game_count)), data = args.data, clubId = clubId,
																									  	gameId = assert(tonumber(args.gameId)),

																									  })
					--table.printR(re)
				if re and re.code == 0 then
					for i = 1, #re.enter_code_set do
							if  re.enter_code_set[i] and re.room_address_set[i] and re.private_code_set[i] then
								room_servers_map[best_id].num_entities = room_servers_map[best_id].num_entities + 1
								datacenter.set("room_manager"  , re.enter_code_set[i], {
																							address = re.room_address_set[i], num = 0, service_id = best_id ,private_code = re.private_code_set[i], clubId = clubId, orderCode = body.data.orderCodes[i]
																					    }
											   )

							end
					end
					return {status = 1, errCode = re.code, error = "success", data = {ip = room_servers_map[best_id].out_ip }}
				end
			else
				return {status = 1, errCode = -200, error = "fail"}
		    end
		end
	end		
	return {status = 1,errCode = -12,error = "status 错误" }	
end







--lat 维度
local function distance_earth(lat1, lng1, lat2, lng2)
	--print(lat1, lng1, lat2, lng2)
	local radLat1 = lat1 * math.pi / 180.0
	local radLat2 = lat2 * math.pi / 180.0
	local a = radLat1 - radLat2
	local b = lng1 * math.pi / 180.0 - lng2 * math.pi / 180.0
	local s = 2 * math.asin(math.sqrt(math.sin(a/2) * math.sin(a/2)  + math.cos(radLat1) * math.cos(radLat2) * math.sin(b/2) * math.sin(b/2)))
	s = s * 6378.137 * 1000
	--print(s)
	return s
end

--print(distance_earth(23.17484,113.408314,23.17484,113.408314))

function command.QUERY_ROOM(args, status, body)
	local enter_code = args.enter_code
	local room = datacenter.get("room_manager", enter_code)
	if not room then
		return {status = 1,errCode = -2,error = "房间不存在" }
	end
	local address = assert(room.address)
	local choose = assert(room.service_id)
	table.printT(room)
	if status == 200 then
		if body.errCode == 0 then
			local para = {}
			para.uid = assert(tonumber( body.data.userId))
			para.nickname = body.data.nickName or "test"..args.uid
			para.ip = body.data.ip or "127.0.0.1"	
			para.image_url = body.data.avatar
			para.gender = tonumber(body.data.gender)


			if room.antiCheatRoom  then
				if args.antiCheatLon == nil or args.antiCheatLat == nil or para.ip == nil then
					return {status = 1,errCode = -100,error = "gps" }
				else
					if para.uid ~= room.uid then
						for k,v in pairs(room.antiCheat) do
							if k ~= para.uid then
								local distance = distance_earth(tonumber(v.antiCheatLat), tonumber(v.antiCheatLon), tonumber(args.antiCheatLat), tonumber(args.antiCheatLon))
								syslog.debugf("antiCheat gps %f, %f, %f, %f, %f",v.antiCheatLat, v.antiCheatLon, args.antiCheatLat, args.antiCheatLon,	distance)
								if distance <= 600  then
							 		syslog.debugf("too closed return errCode=-101")
							 		return {status = 1,errCode = -101,error = "too closed" }
							 	end
						 	end
						end

						for k,v in pairs(room.ip) do
							if v == para.ip then
								syslog.debugf("ip  closed return errCode=-101")
								return {status = 1,errCode = -101,error = "ip  closed" }
							end
						end		
						local antiCheatInfo = {}
						antiCheatInfo.antiCheatLat = args.antiCheatLat
						antiCheatInfo.antiCheatLon = args.antiCheatLon
						room.antiCheat[para.uid] = antiCheatInfo	
						room.ip[para.uid] = para.ip
						datacenter.set("room_manager", enter_code, room)
					else
						room.ip[para.uid] = para.ip	
						datacenter.set("room_manager", enter_code, room)
					end
				end
			end

			if args.antiCheatLon then
				para.ip = para.ip.."_"..args.antiCheatLon
			end
			if args.antiCheatLat then
				para.ip = para.ip.."_"..args.antiCheatLat
			end		
				--table.printR(args)		    
			skynet.call(address, "lua","register_player", para.uid, para)
			return {status = 1, errCode = 0, error = "success", data = {address = room_servers_map[choose].out_ip}}
		end
	end
	return {status = 1,errCode = -12,error = "status 错误" }
end

function command.UPDATE_ORDER_STATUS(order_id, stat, enter_code)
	local room = datacenter.get("room_manager", enter_code)
	if not room then
		return
	end	
	skynet.send("WEBSERVER_MGR", "lua","update_order_status", order_id, stat, enter_code, room.clubId)
end

function command.UPDATE_ROOM_INFO(enter_code, uid)
	local room = datacenter.get("room_manager", enter_code)
	if not room then
		return
	end
	room.ip[uid] = nil
	room.antiCheat[uid] = nil
	datacenter.set("room_manager",  enter_code, room)
end

function command.UPDATE_ROOM_SERVERS(harbor_id, enter_code, sclub, point_wms)
	local room = datacenter.get("room_manager", enter_code)
	if not room then
		return
	end
	if room.clubId then
		local args = {}
		args.orderCode = room.orderCode
		args.roomId = enter_code
		args.bigWinner = sclub
		skynet.send("WEBSERVER_MGR", "lua","update_room_servers", args)	

		if point_wms then
			syslog.errf(" point_wms  %s ",point_wms)
			args.logInfo = point_wms
			skynet.send("WEBSERVER_MGR", "lua","update_pointlog_servers", args)			
		end
	end

	datacenter.set("room_manager",  enter_code, nil)
	if not room_servers_map[harbor_id] then
		return
	end
	local current_num = room_servers_map[harbor_id].num_entities
	if current_num <= 0 then
		syslog.errf("error room num  from harbor_id,num:%d, %d",harbor_id,current_num)
		room_servers_map[harbor_id].num_entities = 0
	else
		room_servers_map[harbor_id].num_entities = current_num  - 1
	end
end



function command.QUERY_STATUS(args)
	if not args.userId  then
		return {status = 1, errCode = -1, error = "erro"}
	else
		local uid = assert(tonumber(args.userId)) 
		local last = datacenter.get("on_player", uid)
		if last and room_servers_map[last] then
			skynet.call(room_servers_map[last].world, "lua", "kick", uid)
			return {status = 1, errCode = 0, error = "success", data = {address = room_servers_map[last].out_ip}}
		end
	end
	return {status = 1, errCode = -1, error = "erro"}
end

function command.SEND_RED_BAG(args)
    local room = datacenter.get("room_manager", args.enter_code)
	if not room then
		return
	end	
    skynet.send("WEBSERVER_MGR", "lua","send_red_bag", args)	
end


local execute_time = 100 * 300

local function task_mysql()
	while true do
		skynet.sleep(100)
		local room_peak = 0
		local online_peak = 0
		for k, v in pairs(room_servers_map) do
			local ok, res = pcall(skynet.call, v.world, "lua", "character_num")
			if ok then
				online_peak = online_peak + res
				room_peak   = room_peak  + v.num_entities
			else
				syslog.errf("task mysql to game_statistics harbor_id : %d", k)
			end
		end
		skynet.send(".MYSQL", "lua", "log", "db_game_log", "game_statistics_log", {room_peak = room_peak, online_peak = online_peak, time = os.time()})
		skynet.sleep(execute_time)
	end
end

skynet.start(function()
	skynet.dispatch("lua", function(session, address, cmd, ...)
		local f = command[string.upper(cmd)]
		if f then
			skynet.ret(skynet.pack(f(...)))
		else
			error(string.format("Unknown command %s", tostring(cmd)))
		end
	end)
	skynet.fork(task_mysql)


	skynet.info_func(HarborInfo)

	skynet.register "CENTER_MGR"
end)



