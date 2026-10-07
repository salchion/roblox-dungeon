-- DailyService (ServerScriptService > Modules 안의 ModuleScript, 이름: DailyService)
-- 출석 보상: 하루에 한 번 접속하면 자동 지급. 연속 출석일이 늘수록 보상이 커지고 7일 주기로 반복.
-- 저장: { Day = 마지막 출석 날짜(UTC 일수), Streak = 연속 출석 일수 }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Keys = require(script.Parent:WaitForChild("KeyService"))

local Daily = {}

local state = {} -- [player] = { Day, Streak }

local function today()
	return math.floor(os.time() / 86400)
end

function Daily.Load(player, saved)
	local day = today()
	local lastDay = saved and tonumber(saved.Day) or nil
	local streak = saved and math.max(0, math.floor(tonumber(saved.Streak) or 0)) or 0
	state[player] = { Day = lastDay or 0, Streak = streak }
	player:SetAttribute("LoginStreak", streak)
	if lastDay == day then return end -- 오늘은 이미 받음

	streak = (lastDay == day - 1) and streak + 1 or 1
	local rewards = Config.Daily.Rewards
	local reward = rewards[(streak - 1) % #rewards + 1]
	state[player] = { Day = day, Streak = streak }
	player:SetAttribute("LoginStreak", streak)

	if reward.Gold then
		player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + reward.Gold)
	end
	if reward.Tickets then
		player:SetAttribute("Tickets", (player:GetAttribute("Tickets") or 0) + reward.Tickets)
	end
	if reward.Keys then
		Keys.Add(player, reward.Keys)
	end

	local parts = {}
	if reward.Gold then table.insert(parts, reward.Gold .. " G") end
	if reward.Tickets then table.insert(parts, "티켓 " .. reward.Tickets) end
	if reward.Keys then table.insert(parts, "열쇠 " .. reward.Keys) end
	task.delay(5, function()
		if player.Parent then
			Remotes.Notify:FireClient(player, string.format("📅 %d일 연속 출석! 보상: %s", streak, table.concat(parts, " + ")))
		end
	end)
end

function Daily.Serialize(player)
	return state[player] or { Day = 0, Streak = 0 }
end

function Daily.Forget(player)
	state[player] = nil
end

return Daily
