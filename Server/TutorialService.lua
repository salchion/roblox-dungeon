-- TutorialService (ServerScriptService > Modules 안의 ModuleScript, 이름: TutorialService)
-- 처음 가이드 미션: 허수아비 -> (바로 사냥) 필드 첫 군주 -> 최종 군주에게 패배 -> 전리품으로 10연 뽑기 / 무기 진화 (훈련은 2구역 클리어로 해금: GrowthService) (튜토리얼 던전 없음).
-- 미션마다 목표 위치에 빛기둥/표지가 나타나고, 완료하면 곧바로 보상이 터진다 (숫자가 빠르게 오르는 초반 쾌감).
-- Quest.Add 에 올라오는 카운터(DummyHits / Enhances / Rolls / Kills / DungeonClears)를 그대로 듣는다.
-- FreeEnhance 가 켜진 미션 동안은 무기 강화가 공짜 + 100% 성공 (TutorialFree Attribute 로 WeaponService 가 확인). 지금은 쓰는 미션이 없다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Quest = require(script.Parent:WaitForChild("QuestService"))
local FunnelLog = require(script.Parent:WaitForChild("FunnelLog")) -- 분석: 튜토리얼 몇 번째 미션까지 했는지
local Keys = require(script.Parent:WaitForChild("KeyService"))
local Level = require(script.Parent:WaitForChild("LevelService"))

local Steps = Config.Tutorial.Steps

local Tutorial = {}

local states = {}  -- [player] = { Step, Progress }
local targets = {} -- [targetKey] = Vector3

function Tutorial.SetTargets(map)
	targets = map
end

-- 시점 둘러보기 미션 동안은 몸을 고정한다 (카메라만 돌릴 수 있다)
local function applyFreeze(player)
	local step = Steps[states[player] and states[player].Step or 0]
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if step and step.Look then
		root.Anchored = true
		player:SetAttribute("TutorialFrozen", true)
	elseif player:GetAttribute("TutorialFrozen") then
		root.Anchored = false
		player:SetAttribute("TutorialFrozen", false)
	end
end

-- 안내 카드를 차례로 보여준다 (guard 가 false 를 돌려주면 중단)
local function playCards(player, cards, guard, firstDelay)
	task.spawn(function()
		task.wait(firstDelay or 0)
		for _, card in ipairs(cards) do
			if not guard() then return end
			Remotes.Tutorial:FireClient(player, "Prompt", { Key = card.Key, Title = card.Title, Text = card.Text, Duration = card.Duration or 7 })
			task.wait((card.Duration or 7) + 0.8)
		end
	end)
end

local function send(player)
	local state = states[player]
	if not state or not player.Parent then return end
	local step = Steps[state.Step]
	applyFreeze(player)
	player:SetAttribute("TutorialFree", step ~= nil and step.FreeEnhance == true)
	player:SetAttribute("TutorialActive", step ~= nil)
	-- 무기 진화 미션: 목표 무기가 될 때까지 필요한 강화 횟수를 이 미션이 시작될 때 한 번 계산한다
	if step and step.EvolveToTier and state.DynFor ~= state.Step then
		local tier = Config.Weapon.Tiers[step.EvolveToTier]
		local need = tier and (tier.MinLevel - (player:GetAttribute("WeaponLevel") or 0)) or 0
		state.DynFor = state.Step
		if need <= 0 then
			state.DynGoal = 1
			task.defer(function() Quest.Add(player, step.Stat, 1) end) -- 이미 그 무기 이상이면 바로 완료
		else
			state.DynGoal = need + state.Progress -- (다시 접속했다면 이미 한 횟수는 목표에 더해 준다)
		end
	end
	-- 진화 미션 중 강화: 100% 성공 + 던전에서 번 골드(약 5천)로 끝까지 갈 수 있게 1회 비용을 낮춘다 (WeaponService 가 읽는다)
	if step and step.EvolveToTier and state.DynGoal and state.DynGoal > 1 then
		local remaining = math.max(1, state.DynGoal - state.Progress)
		player:SetAttribute("TutorialEnhanceCost", math.max(20, math.floor(4000 / math.max(remaining, state.DynGoal))))
	else
		player:SetAttribute("TutorialEnhanceCost", nil)
	end
	-- 첫 던전(웨이브 미션) 동안은 거의 무적: 체력이 바닥나면 한 번씩 되살려 준다 (DungeonService 가 읽는다)
	local goal = (state and state.DynGoal) or (step and step.Goal)
	local text = step and step.Text
	if step and step.EvolveToTier and Config.Weapon.Tiers[step.EvolveToTier] then
		text = string.gsub(string.gsub(text, "{무기}", Config.Weapon.Tiers[step.EvolveToTier].Name), "{weapon}", Config.Weapon.Tiers[step.EvolveToTier].Name)
	end
	-- 미션 소개 카드(Intro): 이 미션이 처음 시작될 때 한 번 차례로 보여준다 (던전에 들어가면 중단. 첫 미션은 MinSeconds 동안 끝까지 보여준다)
	if step and step.Intro and state.IntroShown ~= state.Step then
		state.IntroShown = state.Step
		local introStep = state.Step
		playCards(player, step.Intro, function()
			return states[player] == state and (state.Step == introStep or step.MinSeconds ~= nil)
				and (player:GetAttribute("Zone") == "Lobby" or (step.IntroAnyZone and player:GetAttribute("Zone") == "Field"))
		end, step.IntroDelay or 0.6)
	end
	-- 최종 군주에게 쓰러져 마을로 돌아온 뒤(ShowQuests 미션부터)에 오늘의 퀘스트가 화면에 나타나고 던전 게이트가 열린다
	local questStep = #Steps + 1
	for index, candidate in ipairs(Steps) do
		if candidate.ShowQuests then questStep = index break end
	end
	player:SetAttribute("QuestHud", step == nil or state.Step >= questStep)
	player:SetAttribute("TutorialDungeonLocked", step ~= nil and state.Step < questStep and step.Dungeon ~= true)
	player:SetAttribute("TutorialRoll", step and step.RollMode or nil) -- 미션 중 뽑기 보정: Lowest = 항상 일반 / Hero = 10연에 영웅 1개 확정 (전설 이상 없음)
	player:SetAttribute("TutorialDungeonRun", step ~= nil and step.Dungeon == true) -- 첫 던전 미션: 받는 피해 절반 (DungeonService)
	player:SetAttribute("TutorialDungeonDoom", step ~= nil and step.DungeonDoom == true) -- 이 던전의 보스를 쓰러뜨리면 최후의 군주가 나타난다 (DungeonService -> FieldService)
	player:SetAttribute("TutorialDoom", step ~= nil and step.Doom == true) -- 필드 "압도적인 습격" 장면 (쓰러지면 다음 단계로 이어진다)
	if not step then
		Remotes.Tutorial:FireClient(player, "Done")
		return
	end
	Remotes.Tutorial:FireClient(player, "Step", {
		Index = state.Step, Total = #Steps, Text = text, Progress = state.Progress, Goal = goal,
		Target = targets[step.Target], TargetName = step.TargetName, TargetKey = step.Target, Highlight = step.Highlight, Look = step.Look == true,
	})
end

local complete -- 아래에서 정의 (Load 안의 콜백이 쓴다)
local giveReelGear -- 아래에서 정의 (필드에 처음 나갈 때 Load 안의 콜백이 부른다)

function Tutorial.Load(player, saved)
	local state
	if typeof(saved) == "table" then
		local savedStep = math.floor(tonumber(saved.Step) or 1)
		local version = tonumber(saved.V) or 1
		if version < 2 then savedStep += 1 end -- 예전 저장본: 맨 앞에 "둘러보기" 미션이 추가되어 한 칸씩 밀린다
		if version < 3 and savedStep >= 10 then savedStep += 1 end -- 마지막 필드 미션 앞에 "골드로 강화" 미션이 끼어들었다
		if version < 4 then savedStep = math.max(1, savedStep - 1) end -- 맨 앞의 "마을 둘러보기"(이동 잠금) 미션을 없앴다: 바로 쏘면서 시작한다
		if version < 5 then -- 튜토리얼 던전 / 마지막 필드 미션을 없앴다: 옛 6~10번 -> 새 6(10연) 6 6 7(진화) 8(훈련)
			local map = { [6] = 6, [7] = 6, [8] = 6, [9] = 7, [10] = 8 }
			local mapped = savedStep >= 11 and #Steps + 1 or (map[savedStep] or savedStep)
			if mapped ~= savedStep then saved.Progress = 0 end
			savedStep = mapped
		end
		if version < 6 and savedStep >= 7 then -- 뽑기와 무기 진화 사이에 "첫 던전" 미션이 끼어들었다
			savedStep += 1
		end
		if version < 7 then -- 강화 2단계를 하나로 합치고 "뽑기 1번" 미션을 없앴다 (옛 8단계 -> 새 6단계)
			local map = { [1] = 1, [2] = 2, [3] = 2, [4] = 3, [5] = 3, [6] = 4, [7] = 5, [8] = 6 }
			local mapped = savedStep >= 9 and #Steps + 1 or (map[savedStep] or savedStep)
			if mapped ~= savedStep then saved.Progress = 0 end
			savedStep = mapped
		end
		if version < 8 then -- 던전이 군주 앞으로 왔다 (옛 6단계: 필드 / 뽑기10 / 던전 / 강화 -> 새: 필드 / 던전+군주 / 뽑기10 / 강화)
			local map = { [1] = 1, [2] = 2, [3] = 3, [4] = 5, [5] = 4, [6] = 6 }
			local mapped = savedStep >= 7 and #Steps + 1 or (map[savedStep] or savedStep)
			if mapped ~= savedStep then saved.Progress = 0 end
			savedStep = mapped
		end
		local owedReel = false
		if version < 10 and savedStep == 1 then -- 첫 미션이 허수아비에서 "몬스터 5마리"로 바뀌었다: 이전 진행도는 버리고, 첫 장비는 필드에 서는 순간 받는다
			saved.Progress = 0
			owedReel = true
		end
		if version < 9 then -- "모루에서 강화 2번" 미션(옛 2번)을 없앴다: 옛 2~6 -> 새 2~5 (옛 2번에 있던 사람은 필드 미션 + 첫 장비를 받는다)
			local map = { [1] = 1, [2] = 2, [3] = 2, [4] = 3, [5] = 4, [6] = 5 }
			local mapped = savedStep >= 7 and #Steps + 1 or (map[savedStep] or savedStep)
			if savedStep == 2 then owedReel = true end
			if mapped ~= savedStep or savedStep == 2 then saved.Progress = 0 end
			savedStep = mapped
		end
		state = { Step = math.clamp(savedStep, 1, #Steps + 1), Progress = math.max(0, math.floor(tonumber(saved.Progress) or 0)), OwedReel = owedReel }
	elseif (player:GetAttribute("Level") or 1) >= 5 then
		state = { Step = #Steps + 1, Progress = 0 } -- 이미 진행한 유저는 건너뜀
	else
		state = { Step = 1, Progress = 0 }
		FunnelLog.Onboarding(player, 1, "Start")
	end
	state.StepStartedAt = os.clock()
	state.FieldStarted = typeof(saved) == "table" and saved.FieldStarted == true
	state.ReelDone = not (typeof(saved) == "table" and saved.ReelDone == false) and not state.OwedReel -- 예전 저장본 / 새 사용자는 이미 받았거나 아직 때가 아니다
	states[player] = state
	-- 첫 던전 미션 중 던전에서 나왔거나(죽음 / 나가기 / 접속 종료) 다시 접속했다면: 게이트로 다시 들어가면 된다고 알려 준다 (열쇠 / 무료 입장 소모 없음)
	local function nudgeDungeon()
		if states[player] ~= state or player:GetAttribute("Zone") ~= "Lobby" or player:GetAttribute("TutorialDungeonRun") ~= true then return end
		if os.clock() - (state.LastDungeonNudge or -100) < 20 then return end
		state.LastDungeonNudge = os.clock()
		Remotes.Tutorial:FireClient(player, "Prompt", { Key = "🗝", Title = "Take on the dungeon again!", Text = "You can re-enter from the town Dungeon Gate (follow the mission arrow). No key needed. It picks up right where the scene left off!", Duration = 9, Top = true })
	end
	task.delay(10, nudgeDungeon) -- 이 던전 미션 도중 접속을 껐다가 다시 들어온 경우
	player:GetAttributeChangedSignal("Zone"):Connect(function()
		local current = states[player]
		if current == state and player:GetAttribute("Zone") == "Lobby" then task.delay(2, nudgeDungeon) end
		if current ~= state or player:GetAttribute("Zone") ~= "Field" then return end
		if state.ReelDone == false then -- 필드로 나가는 순간 첫 장비 3개 지급 (슬롯 릴)
			state.ReelDone = true
			task.delay(1.2, function() if player.Parent then giveReelGear(player) end end)
		end
		if state.Step >= 4 and not state.ShadowHint then -- 최후의 군주를 만난 뒤 처음 필드에 나가면: 동쪽 끝 그림자 안내
			state.ShadowHint = true
			task.delay(3, function()
				if player.Parent and player:GetAttribute("Zone") == "Field" then
					Remotes.Tutorial:FireClient(player, "Prompt", { Key = "👁", Title = "Far off in the eastern sky…", Text = "A giant shadow looms at the end of the field. It is the Final Lord. It grows clearer the further east you go through the zones.", Duration = 8, Top = true })
				end
			end)
		end
	end)
	send(player)
	-- 처음 접속하면 캐릭터가 나타나는 순간부터 고정한다 (캐릭터가 아직 없을 수도 있어 몇 초간 반복 확인)
	local function freezeSoon(character)
		character:WaitForChild("HumanoidRootPart", 10)
		for _ = 1, 8 do
			if states[player] ~= state then return end
			applyFreeze(player)
			task.wait(0.25)
		end
	end
	player.CharacterAdded:Connect(freezeSoon)
	if player.Character then task.spawn(freezeSoon, player.Character) end
	player:GetAttributeChangedSignal("TrainTick"):Connect(function()
		Quest.Add(player, "Trains", 1)
	end)
end

-- 데이터를 불러오는 동안(튜토리얼 상태를 알기 전)에는 몸을 고정해 둔다. Load 가 끝나면 필요 없는 사람은 풀린다.
function Tutorial.EarlyFreeze(player, character)
	do return end -- 정보를 불러오는 동안 몸을 묶어 두면 시작이 멈춘 것처럼 느껴져서 더 이상 고정하지 않는다 (화면에는 "불러오는 중" 표시가 뜬다)
	if states[player] then return end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root and not states[player] then
		root.Anchored = true
		player:SetAttribute("TutorialFrozen", true)
	end
	task.delay(25, function() -- 안전장치: 끝내 못 불러오면 풀어준다
		if player.Parent and not states[player] and player:GetAttribute("TutorialFrozen") then
			local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if r then r.Anchored = false end
			player:SetAttribute("TutorialFrozen", false)
		end
	end)
end

-- 운영자 테스트용: 튜토리얼 진행만 처음으로 되돌린다 (레벨 / 장비 / 골드는 그대로)
function Tutorial.Restart(player)
	local state = states[player]
	if not state then return false end
	state.Step = 1
	state.Progress = 0
	state.DynGoal = nil
	state.DynFor = nil
	state.IntroShown = nil
	state.StepStartedAt = os.clock()
	send(player)
	return true
end

-- 운영자 테스트용 (AdminService "MaxOut"): 튜토리얼을 끝난 상태로
function Tutorial.Finish(player)
	local state = states[player]
	if not state then return false end
	state.Step = #Steps + 1
	state.Progress = 0
	state.DynGoal = nil
	state.DynFor = nil
	send(player)
	return true
end

-- 오프닝을 끝까지 본 새 유저(첫 미션 단계)를 바로 1구역 캠프에 세우고 첫 장비를 준다. R 키 자동 공격 안내도 같이 띄운다.
function Tutorial.StartInField(player)
	local state = states[player]
	if not state or state.Step ~= 1 or state.Progress > 0 or state.FieldStarted then return end
	local character = player.Character
	if not character or player:GetAttribute("Zone") == "Dungeon" then return end
	local okF, Field = pcall(function() return require(script.Parent:WaitForChild("FieldService")) end)
	if not okF or not Field.RespawnAtCamp then return end
	state.FieldStarted = true
	state.ReelDone = true -- 이 자리에서 바로 주므로 "필드에 처음 나갈 때" 지급은 다시 하지 않는다
	Field.RespawnAtCamp(player, character, 1)
	task.delay(1.5, function() if player.Parent then giveReelGear(player) end end)
	task.delay(4, function()
		if player.Parent and states[player] == state and state.Step == 1 then
			Remotes.Tutorial:FireClient(player, "Prompt", { Key = "R", Title = "Press R: auto-attack!", Text = "R aims and fires at nearby monsters for you.", Duration = 10, Top = true })
		end
	end)
end

function Tutorial.Serialize(player)
	local state = states[player] or { Step = #Steps + 1, Progress = 0 }
	return { Step = state.Step, Progress = state.Progress, V = 10, ReelDone = state.ReelDone, FieldStarted = state.FieldStarted == true }
end

function Tutorial.Forget(player)
	states[player] = nil
end

local function rewardText(reward)
	local parts = {}
	if reward.Gold then table.insert(parts, reward.Gold .. " G") end
	if reward.Tickets then table.insert(parts, "Tickets " .. reward.Tickets) end
	if reward.Keys then table.insert(parts, "Keys " .. reward.Keys) end
	if reward.Xp then table.insert(parts, "XP " .. reward.Xp) end
	return table.concat(parts, " + ")
end

-- 첫 장비 지급: 겹치지 않는 부위 3개 (희귀 1 + 일반 2)를 바로 주고(빈 부위는 자동 장착), 화면에는 슬롯 릴이 돌아간다
function giveReelGear(player)
	local okI, Inventory = pcall(function() return require(script.Parent:WaitForChild("InventoryService")) end)
	if not okI then return end
	local G = Config.Gear
	local slots = table.clone(G.Slots)
	for i = #slots, 2, -1 do
		local j = math.random(i)
		slots[i], slots[j] = slots[j], slots[i]
	end
	local rarities = { 2, 1, 1 }
	for i = #rarities, 2, -1 do
		local j = math.random(i)
		rarities[i], rarities[j] = rarities[j], rarities[i]
	end
	local list = {}
	for index = 1, 3 do
		local slot, rarity = slots[index], rarities[index]
		Inventory.Add(player, Inventory.NewItem(slot.Key, rarity, 0))
		table.insert(list, { Slot = slot.Name, Name = slot.Names[rarity], Rarity = rarity })
	end
	Remotes.Tutorial:FireClient(player, "Reel", list)
end

function complete(player, state, step)
	local reward = step.Reward
	player:SetAttribute("TutorialRollCount", nil)
	player:SetAttribute("TutorialHero", nil)
	if step.Stat == "DummyHits" then -- 허수아비 미션이 끝나면 자동 공격(R)을 꺼 달라고 클라이언트에 알린다
		player:SetAttribute("AutoOffTick", (player:GetAttribute("AutoOffTick") or 0) + 1)
	end
	if reward.Gold then
		player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + reward.Gold)
	end
	if reward.Tickets then
		player:SetAttribute("Tickets", (player:GetAttribute("Tickets") or 0) + reward.Tickets)
	end
	if reward.Keys then
		Keys.Add(player, reward.Keys)
	end
	if reward.Xp then
		Level.AddXP(player, reward.Xp)
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		Effects.Burst(root.Position + Vector3.new(0, 3, 0), Color3.fromRGB(255, 225, 110), 80)
		Effects.FloatText(root.Position + Vector3.new(0, 6, 0), "✅ Mission complete!", Color3.fromRGB(130, 255, 150))
	end
	Remotes.Notify:FireClient(player, string.format("✅ Mission complete! Reward: %s", rewardText(reward)))
	if step.Reel then
		state.ReelDone = false -- 장비는 필드로 처음 나갈 때 준다 (아래 Zone 감시)
	end
	state.Step += 1
	FunnelLog.Onboarding(player, state.Step, string.format("Mission%d_%s", state.Step - 1, tostring(step.Stat)))
	state.Progress = 0
	state.DynGoal = nil
	state.StepStartedAt = os.clock()
	if step.Outro then -- 완료한 뒤 차례로 안내 (방치 / 매일 할 일 등)
		playCards(player, step.Outro, function()
			return states[player] == state and player:GetAttribute("Zone") ~= "Dungeon"
		end, 2.5)
	end
	if state.Step > #Steps then
		Remotes.Notify:FireClient(player, "🎉 Tutorial complete! The giant shadow flickering at the end of the field is your final goal. Grow stronger by clearing zones, and gather gear in dungeons too. (Settings/Help: H)")
	end
	send(player)
end

Quest.Listeners[#Quest.Listeners + 1] = function(player, stat, amount)
	local state = states[player]
	local step = state and Steps[state.Step]
	if not step or step.Stat ~= stat then return end
	state.Progress += amount
	if state.Progress >= (state.DynGoal or step.Goal) then
		if step.MinSeconds and os.clock() - (state.StepStartedAt or 0) < step.MinSeconds then
			-- 소개 카드를 다 읽을 시간이 지난 뒤에 완료한다
			state.Progress = (state.DynGoal or step.Goal)
			if not state.MinWaiting then
				state.MinWaiting = true
				send(player)
				task.delay(step.MinSeconds - (os.clock() - (state.StepStartedAt or 0)), function()
					state.MinWaiting = nil
					if states[player] == state and Steps[state.Step] == step then
						complete(player, state, step)
					end
				end)
			end
		else
			complete(player, state, step)
		end
	else
		send(player)
	end
end

-- 클라이언트가 시점을 10% 돌릴 때마다 한 번씩 알려온다
Remotes.Tutorial.OnServerEvent:Connect(function(player, action)
	if action ~= "Look" then return end
	local state = states[player]
	local step = state and Steps[state.Step]
	if step and step.Look then
		Quest.Add(player, "Look", 1)
	end
end)

return Tutorial
