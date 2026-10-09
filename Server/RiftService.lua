-- RiftService (ServerScriptService > Modules 안의 ModuleScript, 이름: RiftService)
-- 심연 도전(점수 도전) + 소탕 + 하루 도전 횟수.
--   * 직접 도전: 90초 동안 버티며 점수를 쌓는다 (처치 + 콤보 + NEAR MISS + 웨이브 보너스). 점수 등급에 따라 보상.
--   * 소탕: 도전을 한 번이라도 했으면 버튼 한 번으로 "내 최고 점수 등급 보상의 70%" 를 받는다 (방치형).
--     -> 손맛으로 최고 점수를 올리면 소탕 보상의 한계도 같이 올라간다.
--   * 하루 무료 3회(도전 / 소탕 공유, UTC 날짜 기준 초기화). 기록은 MetaService 의 Rift 에 같이 저장된다.
-- 던전 진행 자체는 DungeonService(Dungeon.Start(..., true))가 맡고, 끝날 때 Dungeon.OnRiftFinished 로 정산한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Dungeon = require(script.Parent:WaitForChild("DungeonService"))
local Meta = require(script.Parent:WaitForChild("MetaService"))
local Quest = require(script.Parent:WaitForChild("QuestService"))
local Growth = require(script.Parent:WaitForChild("GrowthService"))
local Event = require(script.Parent:WaitForChild("EventService"))
local Journey = require(script.Parent:WaitForChild("JourneyService"))

local R = Config.Rift

local Rift = {}

local function notify(player, text)
	Remotes.Notify:FireClient(player, text)
end

local function today()
	return math.floor(os.time() / 86400)
end

-- 오늘 기준으로 정리된 내 기록 (날짜가 바뀌면 사용 횟수 초기화)
local function stateOf(player)
	local state = Meta.GetRift(player)
	if state and state.Day ~= today() then
		state.Day = today()
		state.Used = 0
	end
	return state
end

-- 열려 있는 가장 깊은 심연 깊이: 필드 관문을 연 구역 수 + 1 (최대 8) 또는 골드 등급 이상을 기록한 깊이 + 1 (그 뒤는 점수로 끝없이)
local function unlockedDepth(player, state)
	return math.clamp(math.max(1 + (player:GetAttribute("ClearedZone") or 0), (state.DepthDone or 0) + 1), 1, R.MaxDepth)
end

local function selectedDepth(player, state)
	return math.clamp(state.Depth or 1, 1, unlockedDepth(player, state))
end

local activeDepth = {} -- [player] = 지금 도전 중인 깊이

local function push(player, openPanel)
	local state = stateOf(player)
	if not state then return end
	local depth = selectedDepth(player, state)
	local best = state.Bests and state.Bests[depth] or 0
	local tier = Config.GetRiftTier(best)
	player:SetAttribute("RiftUnlocked", unlockedDepth(player, state)) -- "다음 목표" 패널이 읽는다
	player:SetAttribute("RiftDepthDone", state.DepthDone or 0) -- 업적("심연 깊이 N 돌파")이 읽는다
	Remotes.Rift:FireClient(player, openPanel and "Open" or "State", {
		Best = best, Left = math.max(0, R.FreeAttempts - state.Used), Max = R.FreeAttempts,
		TierName = best > 0 and tier.Name or "기록 없음", TierIcon = best > 0 and tier.Icon or "❔",
		Depth = depth, Unlocked = unlockedDepth(player, state), MaxDepth = R.MaxDepth, Reward = Config.GetRiftDepth(depth).Reward,
		DepthDone = state.DepthDone or 0, ClearedZone = player:GetAttribute("ClearedZone") or 0,
	})
end

local function giveReward(player, tier, rate, depthMult)
	local gold = math.floor(tier.Gold * rate * (depthMult or 1))
	local tickets = math.floor(tier.Tickets * rate)
	local timeSkip = math.floor(tier.TimeSkip * rate)
	player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + gold)
	if tickets > 0 then
		player:SetAttribute("Tickets", (player:GetAttribute("Tickets") or 0) + tickets)
	end
	if timeSkip > 0 then
		Growth.AddTimeSkip(player, timeSkip)
	end
	return gold, tickets, timeSkip
end

local function canPlay(player)
	if player:GetAttribute("Zone") ~= "Lobby" then return false, "마을에서만 할 수 있어요." end
	if player:GetAttribute("TutorialActive") then return false, "🔒 튜토리얼 미션을 모두 끝내면 열려요!" end
	if not Journey.RiftOpen(player) then return false, "🔒 필드 8구역의 군주를 쓰러뜨리면 심연이 열려요!" end
	local state = stateOf(player)
	if not state then return false, "잠시 후 다시 시도해주세요." end
	if state.Used >= R.FreeAttempts then return false, "오늘의 도전 횟수를 모두 썼어요. 내일 다시 오세요!" end
	return true, nil, state
end

function Rift.Start(player)
	local ok, message, state = canPlay(player)
	if not ok then
		notify(player, message)
		return
	end
	state.Used += 1
	local depth = selectedDepth(player, state)
	activeDepth[player] = depth
	Dungeon.Start(player, "Rift", "Normal", true, depth)
	if player:GetAttribute("Zone") ~= "Dungeon" then
		state.Used -= 1 -- 시작하지 못했으면 횟수를 돌려준다 (던전이 가득 참 등)
	end
	push(player, false)
end

function Rift.Sweep(player)
	local ok, message, state = canPlay(player)
	if not ok then
		notify(player, message)
		return
	end
	local depth = selectedDepth(player, state)
	local depthBest = state.Bests and state.Bests[depth] or 0
	if depthBest <= 0 then
		notify(player, "이 깊이에서 먼저 한 번 도전해서 기록을 만들어주세요! (소탕은 그 깊이의 최고 점수 기준이에요)")
		return
	end
	state.Used += 1
	local tier = Config.GetRiftTier(depthBest)
	local gold, tickets, timeSkip = giveReward(player, tier, R.SweepRate, Config.GetRiftDepth(depth).Reward)
	Quest.Add(player, "RiftRuns", 1)
	notify(player, string.format("⚡ 소탕 완료! (%s %s) 골드 +%d%s%s", tier.Icon, tier.Name, gold,
		tickets > 0 and (" · 티켓 +" .. tickets) or "", timeSkip > 0 and string.format(" · 단축권 %d분", timeSkip // 60) or ""))
	push(player, false)
end

-- 던전이 끝났을 때(시간 종료 / 전멸) 점수를 정산한다
local function tierIndex(score)
	local index = 1
	for i, candidate in ipairs(R.Tiers) do
		if score >= candidate.Min then index = i end
	end
	return index
end

local function onFinished(player, score)
	local state = stateOf(player)
	local depth = activeDepth[player] or 1
	activeDepth[player] = nil
	local tier = Config.GetRiftTier(score)
	local gold, tickets, timeSkip = giveReward(player, tier, 1, Config.GetRiftDepth(depth).Reward)
	local newBest = false
	local best = 0
	local unlockedNext = nil
	if state then
		state.Bests = state.Bests or {}
		best = state.Bests[depth] or 0
		if score > best then
			newBest = true
			state.Bests[depth] = score
			best = score
		end
		if score > state.Best then
			state.Best = score
			player:SetAttribute("RiftBest", score)
		end
		if newBest and score >= R.Tiers[4].Min then
			Event.Announce(string.format("📢 %s 님이 심연 깊이 %d 에서 %d점(%s)을 달성했어요!", player.DisplayName, depth, score, tier.Name))
		end
		-- 골드 등급 이상을 기록하면 다음 깊이가 열린다
		if tierIndex(score) >= R.UnlockTier and depth > (state.DepthDone or 0) then
			state.DepthDone = depth
			if depth + 1 <= R.MaxDepth and depth + 1 > 1 + (player:GetAttribute("ClearedZone") or 0) then
				unlockedNext = depth + 1
			end
		end
		state.Depth = math.clamp(depth + (unlockedNext and 1 or 0), 1, R.MaxDepth) -- 새로 열리면 바로 다음 깊이를 고른 상태로
	end
	Quest.Add(player, "RiftRuns", 1)
	push(player, false)
	return { Gold = gold, Tickets = tickets, TimeSkip = timeSkip, Tier = tier.Name, TierIcon = tier.Icon, Best = best, NewBest = newBest, Depth = depth, UnlockedNext = unlockedNext }
end

function Rift.Init(prompt)
	Dungeon.OnRiftFinished = onFinished
	if prompt then
		prompt.Triggered:Connect(function(player)
			if player:GetAttribute("TutorialActive") then
				notify(player, "🔒 튜토리얼 미션을 모두 끝내면 열려요!")
				return
			end
			if not Journey.RiftOpen(player) then
				notify(player, "🔒 필드 8구역의 군주를 쓰러뜨리면 심연이 열려요!")
				return
			end
			push(player, true)
		end)
	end
end

Remotes.Rift.OnServerEvent:Connect(function(player, action, arg)
	if action == "SetDepth" and typeof(arg) == "number" then
		local state = stateOf(player)
		if state then
			state.Depth = math.clamp(math.floor(arg), 1, unlockedDepth(player, state))
			push(player, false)
		end
	elseif action == "Request" then
		push(player, false)
	elseif action == "Start" then
		Rift.Start(player)
	elseif action == "Sweep" then
		Rift.Sweep(player)
	end
end)

return Rift
