-- GrowthService (ServerScriptService > Modules 안의 ModuleScript, 이름: GrowthService)
-- 시간이 걸리는 영구 성장: 훈련소 + 돌파. (BM 은 이 "시간"을 줄여준다 - Config.Growth 설명 참고)
--
--   훈련소: 공격 / 체력 / 치명타 / 이속을 단계별로 영구 강화. 단계마다 실제 시간(오프라인에서도 흐름)과 골드가 든다.
--           슬롯 수만큼 동시에 훈련할 수 있다 (기본 1개, VIP / 상품으로 늘어남).
--   돌파:   캐릭터 레벨이 10 / 20 / 30 / 40 에 도달하면 더 오르려면 돌파가 필요하다 (시간 + 골드).
--   시간 단축권(TimeSkip): 훈련 / 돌파의 남은 시간을 줄인다. 퀘스트로 조금씩 무료로 얻고, 상점에서도 산다.
--
-- 플레이어 Attribute: GatePassed(마친 돌파 레벨), TimeSkip(보유 단축권 초),
--   TrainDamage / TrainHealth / TrainCrit / TrainSpeed (훈련으로 얻은 영구 보너스 -> 전투 계산이 읽음)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local Level = require(script.Parent:WaitForChild("LevelService"))
local Keys = require(script.Parent:WaitForChild("KeyService"))

local R = Config.Growth

local Growth = {}

local states = {}   -- [player] = { Levels = { [stat] = n }, Jobs = { { Stat, EndAt } }, GateJob = { Level, EndAt } | nil }
local pushQueued = {}

-- 스킬 강화 / 펫 레벨업 대기열: state.UpJobs = { { Kind = "Skill" | "Pet", Key, EndAt } }. 끝나는 시각은 Attribute 로도 알린다 (UpSkill_<키> / UpPet)
local function upAttr(kind, key)
	return kind == "Pet" and "UpPet" or ("UpSkill_" .. tostring(key))
end

local function notify(player, text)
	Remotes.Notify:FireClient(player, text)
end

-- 2구역 클리어로 해금: 처음 해금될 때 한 번만 보상 + 안내 (state.Unlocked / Rewarded 는 Growth 저장 데이터에 같이 저장된다)
local function unlock(player, state, giveReward)
	if state.Unlocked then return end
	state.Unlocked = true
	player:SetAttribute("GrowthUnlocked", true)
	if giveReward and not state.Rewarded then
		state.Rewarded = true
		local reward = R.UnlockReward
		if reward.Gold then player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + reward.Gold) end
		if reward.Tickets then player:SetAttribute("Tickets", (player:GetAttribute("Tickets") or 0) + reward.Tickets) end
		if reward.Keys then Keys.Add(player, reward.Keys) end
		if reward.Xp then Level.AddXP(player, reward.Xp) end
		player:SetAttribute("GrowthNew", true) -- 클라이언트가 성장 탭 버튼을 반짝이게 한다 (탭을 열면 "Seen" 으로 꺼진다)
		notify(player, "💪 Growth unlocked! You cleared Zone 2. Start training and you'll get stronger even while offline")
		Remotes.Tutorial:FireClient(player, "Prompt", { Key = "💪", Title = "Growth Unlocked!", Text = "You cleared Zone 2! Open Menu (B) → Skills & Growth (Passive/Training) and start training to get stronger even while offline. Reward: 1000 G · 1 Key · 2 Tickets · 300 XP", Duration = 9 })
	end
	Growth.Push(player)
end

local function slotsOf(player)
	return R.BaseSlots + (player:GetAttribute("TrainSlotBonus") or 0)
end

-- VIP 는 훈련 / 돌파 시간이 짧다
local function timeMultiplier(player)
	if player:GetAttribute("Vip") then
		return 1 - Config.Shop.Vip.TrainTime
	end
	return 1
end

local function recompute(player, state)
	player:SetAttribute("TrainDamage", state.Levels.Attack * R.Stats.Attack.Per)
	player:SetAttribute("TrainHealth", math.floor(state.Levels.Health * R.Stats.Health.Per + 0.5))
	player:SetAttribute("TrainCrit", state.Levels.Crit * R.Stats.Crit.Per)
	player:SetAttribute("TrainSpeed", state.Levels.Speed * R.Stats.Speed.Per)
end

------------------------------------------------------------
-- 클라이언트로 상태 보내기
------------------------------------------------------------
function Growth.Push(player)
	local state = states[player]
	if not state or pushQueued[player] then return end
	pushQueued[player] = true
	task.delay(0.2, function()
		pushQueued[player] = nil
		state = states[player]
		if not player.Parent or not state then return end

		local jobs = {}
		for _, job in ipairs(state.Jobs) do
			table.insert(jobs, { Stat = job.Stat, EndAt = job.EndAt })
		end
		Remotes.Growth:FireClient(player, "State", {
			UpJobs = state.UpJobs,
			Levels = state.Levels,
			Jobs = jobs,
			Slots = slotsOf(player),
			GatePassed = player:GetAttribute("GatePassed") or 0,
			GateJob = state.GateJob and { Level = state.GateJob.Level, EndAt = state.GateJob.EndAt } or nil,
			TimeSkip = player:GetAttribute("TimeSkip") or 0,
			ServerTime = os.time(),
		})
	end)
end

------------------------------------------------------------
-- 완료 처리
------------------------------------------------------------
local function completeJobs(player, state)
	local now = os.time()
	local changed = false

	for index = #state.Jobs, 1, -1 do
		local job = state.Jobs[index]
		if now >= job.EndAt then
			table.remove(state.Jobs, index)
			state.Levels[job.Stat] += 1
			changed = true
			local def = R.Stats[job.Stat]
			notify(player, string.format("%s %s complete! Lv.%d (%s)", def.Icon, def.Name, state.Levels[job.Stat], Config.FormatTrainEffect(job.Stat, state.Levels[job.Stat])))
		end
	end

	for index = #state.UpJobs, 1, -1 do
		local job = state.UpJobs[index]
		if now >= job.EndAt then
			local okMeta, Meta = pcall(function() return require(script.Parent:WaitForChild("MetaService")) end)
			if okMeta and Meta.CompleteUpgrade(player, job.Kind, job.Key) then
				table.remove(state.UpJobs, index)
				player:SetAttribute(upAttr(job.Kind, job.Key), nil)
				changed = true
			end
		end
	end

	if state.GateJob and now >= state.GateJob.EndAt then
		player:SetAttribute("GatePassed", state.GateJob.Level)
		notify(player, string.format("🌟 Level %d breakthrough complete! You can grow even more now.", state.GateJob.Level))
		state.GateJob = nil
		changed = true
	end

	if changed then
		recompute(player, state)
		Growth.Push(player)
	end
end

------------------------------------------------------------
-- 시작 / 단축
------------------------------------------------------------
function Growth.StartTrain(player, stat)
	local state = states[player]
	if not state then return end
	if not state.Unlocked then
		notify(player, "🔒 Clear Zone 2 to unlock Growth!")
		return
	end
	if typeof(stat) ~= "string" or not R.Stats[stat] or stat == "Order" then return end

	local level = state.Levels[stat]
	if level >= R.MaxLevel then
		notify(player, "⚠ Already at max level!")
		return
	end
	for _, job in ipairs(state.Jobs) do
		if job.Stat == stat then
			notify(player, "⚠ Already training.")
			return
		end
	end
	if #state.Jobs >= slotsOf(player) then
		notify(player, "⚠ Training slots are full. (Get more slots with VIP / in the Shop)")
		return
	end

	local cost = Config.GetTrainGold(level)
	local gold = player:GetAttribute("Gold") or 0
	if gold < cost then
		notify(player, string.format("⚠ Not enough gold. (%d G needed)", cost))
		return
	end
	player:SetAttribute("Gold", gold - cost)

	local duration = math.floor(Config.GetTrainTime(level) * timeMultiplier(player))
	table.insert(state.Jobs, { Stat = stat, EndAt = os.time() + duration })
	player:SetAttribute("TrainTick", (player:GetAttribute("TrainTick") or 0) + 1) -- 튜토리얼이 "훈련 시작"을 알아채는 신호
	Growth.Push(player)
end

-- 현재 레벨이 막혀 있는 돌파(다음 Gate)를 시작한다
function Growth.StartGate(player)
	local state = states[player]
	if not state then return end
	if not state.Unlocked then
		notify(player, "🔒 Clear Zone 2 to unlock Growth!")
		return
	end
	if state.GateJob then
		notify(player, "⚠ Already breaking through.")
		return
	end

	local passed = player:GetAttribute("GatePassed") or 0
	local gateIndex
	for index, gate in ipairs(R.Gates) do
		if gate > passed then
			gateIndex = index
			break
		end
	end
	if not gateIndex then
		notify(player, "⚠ Nothing left to break through!")
		return
	end

	local gateLevel = R.Gates[gateIndex]
	if (player:GetAttribute("Level") or 1) < gateLevel then
		notify(player, string.format("⚠ Reach level %d to break through.", gateLevel))
		return
	end

	local cost = R.GateGold[gateIndex]
	local gold = player:GetAttribute("Gold") or 0
	if gold < cost then
		notify(player, string.format("⚠ Not enough gold. (%d G needed)", cost))
		return
	end
	player:SetAttribute("Gold", gold - cost)

	local duration = math.floor(R.GateTime[gateIndex] * timeMultiplier(player))
	state.GateJob = { Level = gateLevel, EndAt = os.time() + duration }
	if gateIndex == 1 then -- 첫 돌파는 30분이라 너무 길다: 같은 시간만큼 단축권을 선물해서 바로 끝낼 수 있게 한다
		Growth.AddTimeSkip(player, duration)
		notify(player, string.format("🎁 First breakthrough gift! Received %s Time Skip — press [Use Time Skip] in Growth to finish right away!", Config.FormatDuration(duration)))
	end
	Growth.Push(player)
end

-- 시간 단축권 사용: 남은 시간만큼(보유량 한도 안에서) 줄인다
function Growth.Skip(player, kind, stat)
	local state = states[player]
	if not state then return end

	local job
	if kind == "Gate" then
		job = state.GateJob
	elseif kind == "Skill" or kind == "Pet" then
		for _, candidate in ipairs(state.UpJobs) do
			if candidate.Kind == kind and (kind == "Pet" or candidate.Key == stat) then
				job = candidate
			end
		end
	elseif kind == "Train" then
		for _, candidate in ipairs(state.Jobs) do
			if candidate.Stat == stat then
				job = candidate
			end
		end
	end
	if not job then return end

	local balance = player:GetAttribute("TimeSkip") or 0
	if balance <= 0 then
		notify(player, "⚠ You have no Time Skips.")
		return
	end

	local remaining = job.EndAt - os.time()
	if remaining <= 0 then return end
	local used = math.min(balance, remaining)
	job.EndAt -= used
	if kind == "Skill" or kind == "Pet" then player:SetAttribute(upAttr(kind, job.Key), job.EndAt) end
	player:SetAttribute("TimeSkip", balance - used)
	if balance - used <= 0 then player:SetAttribute("TimeSkipCap", 0) end
	notify(player, string.format("⏱ Used %s Time Skip!", Config.FormatDuration(used)))

	completeJobs(player, state)
	Growth.Push(player)
end

-- 스킬 강화 / 펫 레벨업 시작 (MetaService 가 골드를 받기 전에 CanStartUpgrade 로 확인하고, 받은 뒤 StartUpgrade 를 부른다). 동시에 진행하는 스킬 강화는 훈련 슬롯 수만큼
function Growth.CanStartUpgrade(player, kind, key)
	local state = states[player]
	if not state then return false, "Not ready yet." end
	local skills = 0
	for _, job in ipairs(state.UpJobs) do
		if job.Kind == kind and job.Key == key then return false, "Already upgrading." end
		if job.Kind == "Skill" then skills += 1 end
	end
	if kind == "Skill" and skills >= slotsOf(player) then
		return false, "Upgrade slots are full. (Get more slots with VIP / in the Shop)"
	end
	return true
end

function Growth.StartUpgrade(player, kind, key, seconds)
	local state = states[player]
	if not state then return 0 end
	local duration = math.max(1, math.floor(seconds * timeMultiplier(player)))
	local endAt = os.time() + duration
	table.insert(state.UpJobs, { Kind = kind, Key = key, EndAt = endAt })
	player:SetAttribute(upAttr(kind, key), endAt)
	Growth.Push(player)
	return duration
end

-- 비어 있는 훈련 슬롯 수 (훈련을 안 걸어 둔 칸) - 조언 서비스가 "훈련을 걸어 두세요"를 말할 때 쓴다
function Growth.IdleSlots(player)
	local state = states[player]
	if not state or not state.Unlocked then return 0 end
	return math.max(0, slotsOf(player) - #state.Jobs)
end

function Growth.AddTimeSkip(player, seconds)
	local balance = (player:GetAttribute("TimeSkip") or 0) + seconds
	player:SetAttribute("TimeSkip", balance)
	player:SetAttribute("TimeSkipCap", balance) -- 단축칸: 얻는 순간 가득 찬다 (쓰면 이 값 대비 줄어드는 게 보인다)
	Growth.Push(player)
end

------------------------------------------------------------
-- 저장 / 불러오기
------------------------------------------------------------
function Growth.Load(player, saved)
	local state = { Levels = {}, Jobs = {}, UpJobs = {}, GateJob = nil }
	for _, stat in ipairs(R.Stats.Order) do
		state.Levels[stat] = 0
	end

	if typeof(saved) == "table" then
		if typeof(saved.Levels) == "table" then
			for _, stat in ipairs(R.Stats.Order) do
				state.Levels[stat] = math.clamp(math.floor(tonumber(saved.Levels[stat]) or 0), 0, R.MaxLevel)
			end
		end
		if typeof(saved.Jobs) == "table" then
			for _, job in ipairs(saved.Jobs) do
				if typeof(job) == "table" and R.Stats[job.Stat] and job.Stat ~= "Order" and tonumber(job.EndAt) then
					table.insert(state.Jobs, { Stat = job.Stat, EndAt = tonumber(job.EndAt) })
				end
			end
		end
		if typeof(saved.UpJobs) == "table" then
			for _, job in ipairs(saved.UpJobs) do
				if typeof(job) == "table" and (job.Kind == "Skill" or job.Kind == "Pet") and typeof(job.Key) == "string" and tonumber(job.EndAt) then
					table.insert(state.UpJobs, { Kind = job.Kind, Key = job.Key, EndAt = tonumber(job.EndAt) })
					player:SetAttribute(upAttr(job.Kind, job.Key), tonumber(job.EndAt))
				end
			end
		end
		if typeof(saved.GateJob) == "table" and tonumber(saved.GateJob.Level) and tonumber(saved.GateJob.EndAt) then
			state.GateJob = { Level = tonumber(saved.GateJob.Level), EndAt = tonumber(saved.GateJob.EndAt) }
		end
		player:SetAttribute("GatePassed", math.max(0, math.floor(tonumber(saved.GatePassed) or 0)))
		player:SetAttribute("TimeSkip", math.max(0, math.floor(tonumber(saved.TimeSkip) or 0)))
		player:SetAttribute("TimeSkipCap", player:GetAttribute("TimeSkip"))
	end

	states[player] = state
	-- 해금 상태: 저장된 값 / 이미 훈련해 본 사람(옛 튜토리얼에서 마친 것) / 이미 2구역을 깬 사람은 조용히 해금 (보상은 훈련 경험이 없을 때만 한 번)
	local trained = #state.Jobs > 0
	for _, stat in ipairs(R.Stats.Order) do
		if state.Levels[stat] > 0 then trained = true end
	end
	state.Rewarded = (typeof(saved) == "table" and saved.Rewarded == true) or trained
	if typeof(saved) == "table" and saved.Unlocked == true then
		state.Unlocked = true
		player:SetAttribute("GrowthUnlocked", true)
	elseif trained then
		unlock(player, state, false)
	end
	local function checkZone()
		if not state.Unlocked and states[player] == state and (player:GetAttribute("ClearedZone") or 0) >= R.UnlockZone then
			unlock(player, state, true)
		end
	end
	player:GetAttributeChangedSignal("ClearedZone"):Connect(checkZone)
	task.defer(checkZone)
	recompute(player, state)
	completeJobs(player, state) -- 접속하지 않은 동안 끝난 훈련 / 돌파를 바로 완료 처리
	Growth.Push(player)
end

-- 운영자 테스트용 (AdminService "MaxOut"): 훈련 스탯 전부 만렙, 진행 중인 훈련 / 돌파는 정리
function Growth.AdminMax(player)
	local state = states[player]
	if not state then return false end
	for _, stat in ipairs(R.Stats.Order) do state.Levels[stat] = R.MaxLevel end
	state.Jobs = {}
	for _, job in ipairs(state.UpJobs) do player:SetAttribute(upAttr(job.Kind, job.Key), nil) end
	state.UpJobs = {}
	state.GateJob = nil
	state.Rewarded = true
	if not state.Unlocked then unlock(player, state, false) end
	player:SetAttribute("GatePassed", #Config.Growth.Gates)
	recompute(player, state)
	Growth.Push(player)
	return true
end

function Growth.Serialize(player)
	local state = states[player]
	if not state then return nil end
	local jobs = {}
	for _, job in ipairs(state.Jobs) do
		table.insert(jobs, { Stat = job.Stat, EndAt = job.EndAt })
	end
	return {
		Levels = state.Levels, Jobs = jobs, UpJobs = state.UpJobs,
		GateJob = state.GateJob and { Level = state.GateJob.Level, EndAt = state.GateJob.EndAt } or nil,
		GatePassed = player:GetAttribute("GatePassed") or 0,
		TimeSkip = player:GetAttribute("TimeSkip") or 0,
		Unlocked = state.Unlocked == true, Rewarded = state.Rewarded == true,
	}
end

function Growth.Forget(player)
	states[player] = nil
	pushQueued[player] = nil
end

------------------------------------------------------------
-- 요청 처리 / 완료 확인 루프
------------------------------------------------------------
local lastRequest = setmetatable({}, { __mode = "k" })

Remotes.Growth.OnServerEvent:Connect(function(player, action, arg1, arg2)
	if action == "Request" then
		Growth.Push(player)
		return
	elseif action == "Seen" then
		player:SetAttribute("GrowthNew", nil)
		return
	end

	local now = os.clock()
	if now - (lastRequest[player] or 0) < 0.2 then return end
	lastRequest[player] = now

	if action == "Train" then
		Growth.StartTrain(player, arg1)
	elseif action == "Gate" then
		Growth.StartGate(player)
	elseif action == "Skip" and typeof(arg1) == "string" then
		Growth.Skip(player, arg1, arg2)
	end
end)

task.spawn(function()
	while true do
		task.wait(2)
		for player, state in pairs(states) do
			if player.Parent then
				completeJobs(player, state)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
end)

return Growth
