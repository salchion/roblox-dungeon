-- QuestService (ServerScriptService > Modules 안의 ModuleScript, 이름: QuestService)
-- 일일 퀘스트 / 업적 / 칭호.
--   * 일일 퀘스트: 하루마다(UTC 기준) Config.Quests.Pool 에서 DailyCount 개가 무작위로 나오고 진행도가 초기화된다
--   * 업적: 한 번 달성하면 보상을 받고, 달성하면 칭호(Title)가 열린다
--   * 칭호: 메뉴(B)에서 골라 달면 머리 위 이름표에 표시된다 (플레이어 Attribute "Title")
-- 다른 서비스는 Quest.Add(player, "DummyHits", 1) 처럼 카운터를 올려주기만 하면 된다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Growth = require(script.Parent:WaitForChild("GrowthService"))
local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))

local Quest = {}

local COUNTERS = { "DummyHits", "FieldKills", "EliteKills", "Kills", "BossKills", "DungeonClears", "Enhances", "Rolls", "GoblinKills", "SkillUses", "FieldDeaths", "Trains", "DungeonWaves", "RiftRuns", "StatPoints", "PetPeek" }

-- 카운터가 아니라 플레이어의 현재 값을 읽는 Stat
local function readLive(player, stat)
	if stat == "MaxZone" then
		return player:GetAttribute("MaxZone") or 0
	elseif stat == "Prestige" then
		return player:GetAttribute("Prestige") or 0
	elseif stat == "RiftDepth" then
		return player:GetAttribute("RiftDepthDone") or 0
	elseif stat == "RiftBest" then
		return player:GetAttribute("RiftBest") or 0
	elseif stat == "Level" then
		return player:GetAttribute("Level") or 1
	elseif stat == "Power" then
		return player:GetAttribute("Power") or 0
	elseif stat == "WeaponLevel" then
		return player:GetAttribute("WeaponLevel") or 0
	elseif stat == "BestRarity" then
		local best = 0
		for _, slot in ipairs(Config.Gear.Slots) do
			best = math.max(best, player:GetAttribute("Gear_" .. slot.Key .. "_R") or 0)
		end
		return best
	end
	return nil
end

local states = {}   -- [player] = { Stats, Day, Progress, Claimed, AchClaimed, Equipped }
local pushQueued = {}

local function today()
	return math.floor(os.time() / 86400)
end

local function statValue(player, state, stat)
	local live = readLive(player, stat)
	if live ~= nil then
		return live
	end
	return state.Stats[stat] or 0
end

-- 오늘의 퀘스트: 날짜를 시드로 해서 모든 플레이어가 같은 퀘스트를 받는다
local function todaysQuests(day, player)
	local rng = Random.new(day)
	local indices = {}
	for i = 1, #Config.Quests.Pool do
		indices[i] = i
	end
	for i = #indices, 2, -1 do
		local j = rng:NextInteger(1, i)
		indices[i], indices[j] = indices[j], indices[i]
	end
	-- 던전 / 강화 퀘스트는 항상 포함한다 (처음 접속한 날부터 "던전에 가고 장비를 강화한다"가 자연스럽게 눈에 들어오게)
	local list, used = {}, {}
	local riftOpen = player == nil or player:GetAttribute("HintDone_FieldClear") == true
	local firstDay = player ~= nil and player:GetAttribute("LoginStreak") == 1 -- 첫날: 스탯 / 펫이 있다는 걸 퀘스트로 자연스럽게 알려 준다
	for _, quest in ipairs(Config.Quests.Pool) do
		if quest.Stat == "RiftRuns" and not riftOpen then used[quest.Id] = true end -- 심연이 열리기 전에는 심연 퀘스트가 나오지 않는다
		if quest.FirstDay and not firstDay then used[quest.Id] = true end -- 첫날 전용 퀘스트는 둘째 날부터 나오지 않는다
		if (quest.Always or quest.FirstDay) and not used[quest.Id] then
			table.insert(list, quest)
			used[quest.Id] = true
		end
	end
	for i = 1, #indices do
		if #list >= Config.Quests.DailyCount then break end
		local quest = Config.Quests.Pool[indices[i]]
		if not used[quest.Id] then table.insert(list, quest) end
	end
	return list
end

local function ensureDay(state)
	local day = today()
	if state.Day ~= day then
		state.Day = day
		state.Progress = {}
		state.Claimed = {}
	end
end

local function achievementDone(player, state, achievement)
	return statValue(player, state, achievement.Stat) >= achievement.Goal
end

local function unlockedTitles(player, state)
	local titles = {}
	for _, achievement in ipairs(Config.Achievements) do
		if achievement.Title and achievementDone(player, state, achievement) then
			table.insert(titles, achievement.Title)
		end
	end
	return titles
end

local function applyReward(player, reward)
	if reward.Gold then
		player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + reward.Gold)
	end
	if reward.Tickets then
		player:SetAttribute("Tickets", (player:GetAttribute("Tickets") or 0) + reward.Tickets)
	end
	if reward.TimeSkip then
		Growth.AddTimeSkip(player, reward.TimeSkip)
	end
end

local function rewardText(reward)
	local parts = {}
	if reward.Gold then
		table.insert(parts, string.format("%d G", reward.Gold))
	end
	if reward.Tickets then
		table.insert(parts, string.format("🎫 %d", reward.Tickets))
	end
	if reward.TimeSkip then
		table.insert(parts, string.format("⏱ %d분", reward.TimeSkip // 60))
	end
	return table.concat(parts, " + ")
end

-- 클라이언트로 보낼 전체 상태
local function buildPayload(player, state)
	ensureDay(state)

	local daily = {}
	for _, quest in ipairs(todaysQuests(state.Day, player)) do
		local progress = state.Progress[quest.Id] or 0
		table.insert(daily, {
			Id = quest.Id, Name = quest.Name, Desc = string.format(quest.Desc, quest.Goal),
			Progress = math.min(progress, quest.Goal), Goal = quest.Goal,
			Claimed = state.Claimed[quest.Id] == true, Reward = rewardText(quest.Reward),
		})
	end

	local achievements = {}
	for _, achievement in ipairs(Config.Achievements) do
		local value = statValue(player, state, achievement.Stat)
		table.insert(achievements, {
			Id = achievement.Id, Name = achievement.Name, Desc = string.format(achievement.Desc, achievement.Goal),
			Progress = math.min(value, achievement.Goal), Goal = achievement.Goal,
			Claimed = state.AchClaimed[achievement.Id] == true, Reward = rewardText(achievement.Reward),
			Title = achievement.Title,
		})
	end

	return {
		Daily = daily,
		Achievements = achievements,
		Titles = unlockedTitles(player, state),
		Equipped = state.Equipped,
		Stats = state.Stats,
	}
end

function Quest.Push(player)
	local state = states[player]
	if not state or pushQueued[player] then return end
	pushQueued[player] = true
	task.delay(0.4, function()
		pushQueued[player] = nil
		if player.Parent and states[player] then
			Remotes.Quest:FireClient(player, "State", buildPayload(player, states[player]))
		end
	end)
end

-- 장착 중인 칭호가 아직 유효한지 확인하고 Attribute 에 반영
local function syncTitle(player, state)
	local valid = false
	for _, title in ipairs(unlockedTitles(player, state)) do
		if title == state.Equipped then
			valid = true
		end
	end
	if not valid then
		state.Equipped = nil
	end
	player:SetAttribute("Title", state.Equipped or "")
end

------------------------------------------------------------
-- 외부 API
------------------------------------------------------------
-- 카운터 증가 이벤트를 듣고 싶은 다른 서비스(튜토리얼 등)가 여기에 함수를 등록한다: fn(player, stat, amount)
Quest.Listeners = {}

-- 카운터 증가 (오늘의 퀘스트 진행도도 같이 오름)
function Quest.Add(player, stat, amount)
	local state = states[player]
	if not state then return end
	amount = amount or 1
	ensureDay(state)

	state.Stats[stat] = (state.Stats[stat] or 0) + amount
	for _, quest in ipairs(todaysQuests(state.Day, player)) do
		if quest.Stat == stat then
			state.Progress[quest.Id] = (state.Progress[quest.Id] or 0) + amount
		end
	end
	Quest.Push(player)
	for _, listener in ipairs(Quest.Listeners) do
		listener(player, stat, amount)
	end
end

-- 현재 값 기준 Stat(전투력, 무기 레벨 등)이 바뀌었을 때 호출: 칭호/화면 갱신
function Quest.Refresh(player)
	local state = states[player]
	if not state then return end
	syncTitle(player, state)
	Quest.Push(player)
end

function Quest.Load(player, saved)
	local state = { Stats = {}, Day = 0, Progress = {}, Claimed = {}, AchClaimed = {}, Equipped = nil }
	if typeof(saved) == "table" then
		if typeof(saved.Stats) == "table" then
			for _, name in ipairs(COUNTERS) do
				state.Stats[name] = math.max(0, math.floor(tonumber(saved.Stats[name]) or 0))
			end
		end
		state.Day = tonumber(saved.Day) or 0
		if typeof(saved.Progress) == "table" then state.Progress = saved.Progress end
		if typeof(saved.Claimed) == "table" then state.Claimed = saved.Claimed end
		if typeof(saved.AchClaimed) == "table" then state.AchClaimed = saved.AchClaimed end
		if typeof(saved.Equipped) == "string" then state.Equipped = saved.Equipped end
	end
	states[player] = state
	ensureDay(state)
	syncTitle(player, state)
	Quest.Push(player)
end

function Quest.Serialize(player)
	local state = states[player]
	if not state then return nil end
	return {
		Stats = state.Stats, Day = state.Day, Progress = state.Progress,
		Claimed = state.Claimed, AchClaimed = state.AchClaimed, Equipped = state.Equipped,
	}
end

-- 업적을 달성했는지 (오라 해금 등에서 사용)
function Quest.IsDone(player, achievementId)
	local state = states[player]
	if not state then return false end
	for _, achievement in ipairs(Config.Achievements) do
		if achievement.Id == achievementId then
			return achievementDone(player, state, achievement)
		end
	end
	return false
end

function Quest.Forget(player)
	states[player] = nil
	pushQueued[player] = nil
end

------------------------------------------------------------
-- 클라이언트 요청
------------------------------------------------------------
local function notify(player, text)
	Remotes.Notify:FireClient(player, text)
end

local function claimSound(player) -- 보상 수령 소리 (소리 ID 가 있을 때만)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and SoundBank.Has("Quest_Claim") then SoundBank.Play(root, "Quest_Claim") end
end

Remotes.Quest.OnServerEvent:Connect(function(player, action, arg)
	local state = states[player]
	if not state then return end
	ensureDay(state)

	if action == "Request" then
		Quest.Push(player)

	elseif action == "Claim" and typeof(arg) == "string" then
		for _, quest in ipairs(todaysQuests(state.Day, player)) do
			if quest.Id == arg then
				if state.Claimed[quest.Id] then return end
				if (state.Progress[quest.Id] or 0) < quest.Goal then return end
				state.Claimed[quest.Id] = true
				applyReward(player, quest.Reward)
				claimSound(player)
				notify(player, string.format("✅ 일일 퀘스트 완료! 보상: %s", rewardText(quest.Reward)))
				Quest.Push(player)
				return
			end
		end

	elseif action == "ClaimAch" and typeof(arg) == "string" then
		for _, achievement in ipairs(Config.Achievements) do
			if achievement.Id == arg then
				if state.AchClaimed[achievement.Id] then return end
				if not achievementDone(player, state, achievement) then return end
				state.AchClaimed[achievement.Id] = true
				applyReward(player, achievement.Reward)
				claimSound(player)
				notify(player, string.format("🏅 업적 달성! 보상: %s%s", rewardText(achievement.Reward),
					achievement.Title and ("  / 칭호 『" .. achievement.Title .. "』 해금") or ""))
				Quest.Push(player)
				return
			end
		end

	elseif action == "Title" then
		-- arg 가 nil/빈 문자열이면 칭호 해제
		if arg == nil or arg == "" then
			state.Equipped = nil
		elseif typeof(arg) == "string" then
			state.Equipped = arg
		end
		syncTitle(player, state)
		Quest.Push(player)
	end
end)

return Quest
