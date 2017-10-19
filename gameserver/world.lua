local skynet = require "skynet"
local sharedata = require "sharedata"
local syslog = require "syslog"

local mc = require "multicast"
local dc = require "datacenter"


local CMD = {}
local map_instance = {}
local online_character = {}

local channel

local online_character_num = 0


function CMD.kick (_, character)
	local a = online_character[character]
	if a then
		skynet.call (a, "lua", "kick")
		online_character[character] = nil
	end
end

function CMD.character_enter (agent, character)
	if online_character[character] ~= nil then
		syslog.notice (string.format ("multiple login detected, character %d", character))
		--CMD.kick (agent, character)
	end

	syslog.notice ("world character_enter")
	online_character[character] = agent
	online_character_num = online_character_num + 1
	syslog.notice (string.format ("character(%d) enter world", character))
	
	skynet.call (agent, "lua", "world_enter", skynet.self (),channel.channel,character)
end

function CMD.character_leave (agent, character)
	syslog.notice (string.format ("character(%d) leave world", character))
	online_character_num = online_character_num - 1
	online_character[character] = nil
end

function CMD.init_chat(gamed,id)
	channel = mc.new()
--	syslog.debug(" chat channel set up:",channel," for",id)
	
end

function CMD.send_message(agent,content)
	if not channel or not content then return end
	channel:publish(content)
end

function CMD.send_pmessage(agent,role_id,content)
	if not role_id or not content then return false end
	local online = online_character[role_id]
	if(not online) then return false end
	skynet.call (online, "lua", "receive_chat", content)
end

function CMD.character_num()
	return online_character_num
end


function checkchat()
	if not channel then return end
	syslog.debug("checkchat")
	channel:publish("test chat !!!!!!!!!")
end

local execute_time = 100 * 1800
skynet.start (function ()	
	skynet.dispatch ("lua", function (_, source, command, ...)
		local f = assert (CMD[command])
		skynet.retpack (f (source, ...))
	end)
end)

