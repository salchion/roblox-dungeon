-- RiftService (ServerScriptService > Modules 안의 ModuleScript, 이름: RiftService)
-- 보스러쉬(옛 심연 도전): 하루 입장 횟수 + 점수 정산 + 주간 전체 순위.
--   * 보스급이 일정 간격으로 하나씩 나타난다. 점수 = 버틴 시간(초) x 준 피해. 등급(쓰러뜨린 보스 수)에 따라 보상.
--   * 하루 입장 2회 (UTC 날짜 기준 초기화). 기록은 MetaService 의 Rift 표에 같이 저장된다.
--   * 순위: OrderedDataStore 에 "주 번호"별 이름으로 저장 -> 매주 자동으로 새 순위표 (주 번호 = os.time() // 604800, 목요일 00:00 UTC = 한국 시간 목요일 09:00 에 바뀐다).
--     DataStore 호출은 모두 pcall (Studio 에서 API 가 꺼져 있어도 게임은 돌아간다). 순위표는 서버에서 60초 캐시.
-- 진행 자체는 DungeonService(Dungeon.Start(..., true))가 맡고, 끝날 때 Dungeon.OnRiftFinished 로 정산한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Dungeon = require(script.Parent:WaitForChild("DungeonService"))
local Meta = require(script.Parent:WaitForChild("MetaService"))
local Quest = require(script.Parent:WaitForChild("QuestService"))
local Growth = require(script.Parent:WaitForChild("GrowthService"))
local Event = require(script.Parent:WaitForChild("EventService"))
local Journey = require(script.Parent:WaitForChild("JourneyService"))

local R = Config.Rift
local WEEK = 604800
local BOARD_NAME = "BossRushWeekly_v1_"
local BOARD_REFRESH = 60 -- 순위표 캐시 시간(초)
local SCORE_MAX = 9e15 -- OrderedDataStore 는 정수만: 정밀도를 지킬 수 있는 한계

local Rift = {}

local function notify(player, text)
	Remotes.Notify:FireClient(player, text)
end

local function today()
	return math.floor(os.time() / 86400)
end

local function thisWeek()
	return math.floor(os.time() / WEEK)
end

-- 오늘 / 이번 주 기준으로 정리된 내 기록 (날짜가 바뀌면 사용 횟수, 주가 바뀌면 주간 최고 초기화)
local function stateOf(player)
	local state = Meta.GetRift(player)
	if not state then return nil end
	if state.Day ~= today() then
		state.Day = today()
		state.Used = 0
	end
	if state.Week ~= thisWeek() then
		state.Week = thisWeek()
		state.WeekBest = 0
	end
	return state
end

------------------------------------------------------------
-- 주간 순위표
------------------------------------------------------------
local boardCache = { Week = 0, At = -1e9, List = {}, Ok = false }
local nameCache = {}

local function boardStore(week)
	local ok, store = pcall(function() return DataStoreService:GetOrderedDataStore(BOARD_NAME .. week) end)
	return ok and store or nil
end

local function nameOf(userId)
	if nameCache[userId] then return nameCache[userId] end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		nameCache[userId] = online.DisplayName
		return nameCache[userId]
	end
	local ok, name = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
	nameCache[userId] = ok and name or ("Player" .. userId)
	return nameCache[userId]
end

local function loadBoard()
	local week = thisWeek()
	if boardCache.Week == week and os.clock() - boardCache.At < BOARD_REFRESH then
		return boardCache
	end
	boardCache.Week, boardCache.At = week, os.clock() -- (실패해도 60초 동안은 다시 부르지 않는다)
	local store = boardStore(week)
	local list, okAll = {}, false
	if store then
		local ok, pages = pcall(function() return store:GetSortedAsync(false, R.RankShown) end)
		if ok and pages then
			local okPage, page = pcall(function() return pages:GetCurrentPage() end)
			if okPage and page then
				okAll = true
				for rank, entry in ipairs(page) do
					local userId = tonumber(entry.key)
					if userId then
						table.insert(list, { Rank = rank, UserId = userId, Name = nameOf(userId), Score = entry.value })
					end
				end
			end
		end
	end
	boardCache.List, boardCache.Ok = list, okAll
	return boardCache
end

-- 이번 주 상위 count 명 (명예의 전당 옆 "이번 주 챔피언" 전시대가 읽는다): { { Rank, UserId, Name, Score } ... }
function Rift.WeeklyTop(count)
	local board = loadBoard()
	local out = {}
	for index = 1, math.min(count, #board.List) do
		out[index] = board.List[index]
	end
	return out
end

local function submitScore(player, score)
	if score <= 0 then return end
	local value = math.floor(math.min(score, SCORE_MAX))
	task.spawn(function()
		local store = boardStore(thisWeek())
		if not store then return end
		local ok, err = pcall(function()
			store:UpdateAsync(tostring(player.UserId), function(old)
				if old and old >= value then return nil end -- 더 낮으면 그대로 둔다
				return value
			end)
		end)
		if not ok then
			warn("[BossRush] 순위 저장 실패 (Studio 면 Game Settings > Security > Enable Studio Access to API Services 확인): " .. tostring(err))
		end
		boardCache.At = -1e9 -- 다음 요청 때 순위표를 새로 읽는다
	end)
end

------------------------------------------------------------
-- 패널
------------------------------------------------------------
local function push(player, openPanel)
	local state = stateOf(player)
	if not state then return end
	local tier = Config.GetRiftTier(state.BestDealt or 0)
	local board = loadBoard()
	Remotes.Rift:FireClient(player, openPanel and "Open" or "State", {
		Left = math.max(0, R.FreeAttempts - state.Used), Max = R.FreeAttempts,
		Best = state.BestScore or 0, BestBoss = state.BestBoss or 0, BestDealt = state.BestDealt or 0, BestTime = state.BestTime or 0, WeekBest = state.WeekBest or 0,
		TierName = tier.Name, TierIcon = tier.Icon,
		WeekEndsIn = (thisWeek() + 1) * WEEK - os.time(),
		Board = board.List, BoardOk = board.Ok,
	})
end

local function giveReward(player, tier)
	local mult = R.RewardMult
	local gold = math.floor(tier.Gold * mult)
	player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + gold)
	if tier.Tickets > 0 then
		player:SetAttribute("Tickets", (player:GetAttribute("Tickets") or 0) + tier.Tickets)
	end
	if tier.TimeSkip > 0 then
		Growth.AddTimeSkip(player, tier.TimeSkip)
	end
	return gold, tier.Tickets, tier.TimeSkip
end

local function canPlay(player)
	if player:GetAttribute("Zone") ~= "Lobby" then return false, "This can only be done in town." end
	if player:GetAttribute("TutorialActive") then return false, "🔒 Finish all tutorial missions to unlock!" end
	if not Journey.RiftOpen(player) then return false, "🔒 Defeat the Zone 8 Lord in the field to unlock the Boss Rush!" end
	local state = stateOf(player)
	if not state then return false, "Please try again in a moment." end
	if state.Used >= R.FreeAttempts then return false, "You've used all of today's runs. Come back tomorrow!" end
	return true, nil, state
end

function Rift.Start(player)
	local ok, message, state = canPlay(player)
	if not ok then
		notify(player, message)
		return
	end
	state.Used += 1
	Dungeon.Start(player, "Rift", "Normal", true)
	if player:GetAttribute("Zone") ~= "Dungeon" then
		state.Used -= 1 -- 시작하지 못했으면 횟수를 돌려준다 (던전이 가득 참 등)
	end
	push(player, false)
end

-- 던전이 끝났을 때(제한 시간 / 전멸) 정산한다. result = { Score, Seconds, Dealt, Bosses }
local function onFinished(player, result)
	local state = stateOf(player)
	local tier = Config.GetRiftTier(result.Dealt)
	local gold, tickets, timeSkip = giveReward(player, tier)
	local newBest, newWeekBest = false, false
	local best, weekBest = 0, 0
	if state then
		best, weekBest = state.BestScore or 0, state.WeekBest or 0
		if result.Score > best then
			newBest = true
			state.BestScore = result.Score
			best = result.Score
			player:SetAttribute("RiftBest", best)
		end
		if result.Score > weekBest then
			newWeekBest = true
			state.WeekBest = result.Score
			weekBest = result.Score
		end
		if result.Dealt > (state.BestDealt or 0) then
			state.BestDealt = result.Dealt
		end
		if result.Bosses > (state.BestBoss or 0) then
			state.BestBoss = result.Bosses
			player:SetAttribute("RiftBossBest", result.Bosses)
		end
		if result.Seconds > (state.BestTime or 0) then
			state.BestTime = result.Seconds
			player:SetAttribute("RiftTimeBest", result.Seconds)
		end
	end
	if newWeekBest then
		submitScore(player, result.Score)
	end
	if result.Dealt >= R.Tiers[4].Min and newWeekBest then
		Event.Announce(string.format("📢 %s took down %d bosses in the Boss Rush! (%s)", player.DisplayName, result.Bosses, tier.Name))
	end
	-- 주간 상자: 이번 주 처음으로 Diamond 등급 이상이면 "유니크 확정 신화" 1개
	local boxLine = nil
	if state and result.Dealt >= R.Tiers[5].Min and (state.BoxWeek or 0) ~= thisWeek() then
		state.BoxWeek = thisWeek()
		local okInv, Inventory = pcall(function() return require(script.Parent:WaitForChild("InventoryService")) end)
		if okInv then
			local item = Inventory.GrantMythic(player, { Unique = true })
			local def = item.Unique and Config.Uniques[item.Unique]
			boxLine = string.format("🎁 Weekly Boss Rush chest: Mythic %s with ✦ %s!", item.Slot, def and def.Name or "?")
			notify(player, boxLine)
		end
	end
	Quest.Add(player, "RiftRuns", 1)
	task.spawn(push, player, false) -- (순위표를 읽느라 기다리지 않게)
	return { Gold = gold, Tickets = tickets, TimeSkip = timeSkip, Tier = tier.Name, TierIcon = tier.Icon, Best = best, NewBest = newBest, WeekBest = weekBest, NewWeekBest = newWeekBest }
end

function Rift.Init(prompt)
	Dungeon.OnRiftFinished = onFinished
	if prompt then
		prompt.Triggered:Connect(function(player)
			if player:GetAttribute("TutorialActive") then
				notify(player, "🔒 Finish all tutorial missions to unlock!")
				return
			end
			if not Journey.RiftOpen(player) then
				notify(player, "🔒 Defeat the Zone 8 Lord in the field to unlock the Boss Rush!")
				return
			end
			push(player, true)
		end)
	end
end

local lastRequest = setmetatable({}, { __mode = "k" })
Remotes.Rift.OnServerEvent:Connect(function(player, action)
	if action == "Request" then
		local now = os.clock()
		if now - (lastRequest[player] or 0) < 1 then return end
		lastRequest[player] = now
		push(player, false)
	elseif action == "Start" then
		Rift.Start(player)
	end
end)

return Rift
