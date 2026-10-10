-- TutorialService (ServerScriptService > Modules 안의 ModuleScript, 이름: TutorialService)
-- 처음 가이드 미션: 허수아비 -> 무기 강화(무료) -> 장비 뽑기 -> 필드 첫 군주 -> 최종 군주에게 패배 -> 전리품으로 10연 뽑기 / 무기 진화 (훈련은 2구역 클리어로 해금: GrowthService) (튜토리얼 던전 없음).
-- 미션마다 목표 위치에 빛기둥/표지가 나타나고, 완료하면 곧바로 보상이 터진다 (숫자가 빠르게 오르는 초반 쾌감).
-- Quest.Add 에 올라오는 카운터(DummyHits / Enhances / Rolls / Kills / DungeonClears)를 그대로 듣는다.
-- 미션 2~3 동안은 무기 강화가 공짜 + 100% 성공 (TutorialFree Attribute 로 WeaponService 가 확인).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Quest = require(script.Parent:WaitForChild("QuestService"))
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
		text = string.gsub(text, "{무기}", Config.Weapon.Tiers[step.EvolveToTier].Name)
	end
	-- 미션 소개 카드(Intro): 이 미션이 처음 시작될 때 한 번 차례로 보여준다 (던전에 들어가면 중단. 첫 미션은 MinSeconds 동안 끝까지 보여준다)
	if step and step.Intro and state.IntroShown ~= state.Step then
		state.IntroShown = state.Step
		local introStep = state.Step
		playCards(player, step.Intro, function()
			return states[player] == state and (state.Step == introStep or step.MinSeconds ~= nil) and player:GetAttribute("Zone") == "Lobby"
		end, step.IntroDelay or 0.6)
	end
	-- 최종 군주에게 쓰러져 마을로 돌아온 뒤(ShowQuests 미션부터)에 오늘의 퀘스트가 화면에 나타나고 던전 게이트가 열린다
	local questStep = #Steps + 1
	for index, candidate in ipairs(Steps) do
		if candidate.ShowQuests then questStep = index break end
	end
	player:SetAttribute("QuestHud", step == nil or state.Step >= questStep)
	player:SetAttribute("TutorialDungeonLocked", step ~= nil and state.Step < questStep)
	player:SetAttribute("TutorialRoll", step and step.RollMode or nil) -- 미션 중 뽑기 보정: Lowest = 항상 일반 / Hero = 10연에 영웅 1개 확정 (전설 이상 없음)
	player:SetAttribute("TutorialDoom", step ~= nil and step.Doom == true) -- 필드 "압도적인 습격" 장면 (쓰러지면 다음 단계로 이어진다)
	if not step then
		Remotes.Tutorial:FireClient(player, "Done")
		return
	end
	Remotes.Tutorial:FireClient(player, "Step", {
		Index = state.Step, Total = #Steps, Text = text, Progress = state.Progress, Goal = goal,
		Target = targets[step.Target], TargetName = step.TargetName, Highlight = step.Highlight, Look = step.Look == true,
	})
end

local complete -- 아래에서 정의 (Load 안의 콜백이 쓴다)

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
		state = { Step = math.clamp(savedStep, 1, #Steps + 1), Progress = math.max(0, math.floor(tonumber(saved.Progress) or 0)) }
	elseif (player:GetAttribute("Level") or 1) >= 5 then
		state = { Step = #Steps + 1, Progress = 0 } -- 이미 진행한 유저는 건너뜀
	else
		state = { Step = 1, Progress = 0 }
	end
	state.StepStartedAt = os.clock()
	states[player] = state
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

function Tutorial.Serialize(player)
	local state = states[player] or { Step = #Steps + 1, Progress = 0 }
	return { Step = state.Step, Progress = state.Progress, V = 5 }
end

function Tutorial.Forget(player)
	states[player] = nil
end

local function rewardText(reward)
	local parts = {}
	if reward.Gold then table.insert(parts, reward.Gold .. " G") end
	if reward.Tickets then table.insert(parts, "티켓 " .. reward.Tickets) end
	if reward.Keys then table.insert(parts, "열쇠 " .. reward.Keys) end
	if reward.Xp then table.insert(parts, "경험치 " .. reward.Xp) end
	return table.concat(parts, " + ")
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
		Effects.FloatText(root.Position + Vector3.new(0, 6, 0), "✅ 미션 완료!", Color3.fromRGB(130, 255, 150))
	end
	Remotes.Notify:FireClient(player, string.format("✅ 미션 완료! 보상: %s", rewardText(reward)))
	state.Step += 1
	state.Progress = 0
	state.DynGoal = nil
	state.StepStartedAt = os.clock()
	if step.Outro then -- 완료한 뒤 차례로 안내 (방치 / 매일 할 일 등)
		playCards(player, step.Outro, function()
			return states[player] == state and player:GetAttribute("Zone") ~= "Dungeon"
		end, 2.5)
	end
	if state.Step > #Steps then
		Remotes.Notify:FireClient(player, "🎉 튜토리얼 완료! 북쪽 던전 게이트가 열렸어요! 던전에서 장비와 재화를 더 모아보세요. (설정/도움말: H)")
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
