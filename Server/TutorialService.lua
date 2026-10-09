-- TutorialService (ServerScriptService > Modules 안의 ModuleScript, 이름: TutorialService)
-- 처음 1~5분 가이드 미션: 허수아비 -> 무기 강화(무료, +3에서 총이 진화) -> 장비 뽑기 -> 필드 사냥 -> 던전.
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

local function send(player)
	local state = states[player]
	if not state or not player.Parent then return end
	local step = Steps[state.Step]
	applyFreeze(player)
	player:SetAttribute("TutorialFree", step ~= nil and step.FreeEnhance == true)
	player:SetAttribute("TutorialActive", step ~= nil)
	-- 던전 미션이 나오기 전에는 던전에 들어갈 수 없다
	local dungeonStep = #Steps + 1
	for index, candidate in ipairs(Steps) do
		if candidate.Stat == "DungeonWaves" then dungeonStep = index break end
	end
	player:SetAttribute("TutorialDungeonLocked", step ~= nil and state.Step < dungeonStep)
	player:SetAttribute("TutorialRoll", step and step.RollMode or nil) -- 미션 중 뽑기 보정: Lowest = 항상 일반 / Hero = 10연에 영웅 1개 확정 (전설 이상 없음)
	player:SetAttribute("TutorialDoom", step ~= nil and step.Doom == true) -- 필드 "압도적인 습격" 장면 (쓰러지면 성장 단계로 이어진다)
	if not step then
		Remotes.Tutorial:FireClient(player, "Done")
		return
	end
	if step.Doom and not state.DashTipShown then
		state.DashTipShown = true
		Remotes.Tutorial:FireClient(player, "Prompt", { Key = "Q", Title = "대시로 빠르게!", Text = "Q 키를 누르면 앞으로 돌진해요. 동쪽 필드까지 빠르게 갈 수 있고, 적 탄을 아슬아슬하게 피하면 NEAR MISS 보너스!", Duration = 8 })
	end
	Remotes.Tutorial:FireClient(player, "Step", {
		Index = state.Step, Total = #Steps, Text = step.Text, Progress = state.Progress, Goal = step.Goal,
		Target = targets[step.Target], TargetName = step.TargetName, Highlight = step.Highlight,
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
		state = { Step = math.clamp(savedStep, 1, #Steps + 1), Progress = math.max(0, math.floor(tonumber(saved.Progress) or 0)) }
	elseif (player:GetAttribute("Level") or 1) >= 5 then
		state = { Step = #Steps + 1, Progress = 0 } -- 이미 진행한 유저는 건너뜀
	else
		state = { Step = 1, Progress = 0 }
	end
	states[player] = state
	send(player)
	player:GetAttributeChangedSignal("Zone"):Connect(function()
		local current = states[player]
		local step = current and Steps[current.Step]
		if step and step.AfterDungeon and current.Progress >= step.Goal and player:GetAttribute("Zone") ~= "Dungeon" then
			task.wait(1) -- 마을로 돌아와 화면이 자리 잡은 뒤 보상
			if states[player] == current and Steps[current.Step] == step then
				current.Notified = nil
				complete(player, current, step)
			end
		end
	end)
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
	return { Step = state.Step, Progress = state.Progress, V = 3 }
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
	if state.Step > #Steps then
		Remotes.Notify:FireClient(player, "🎉 튜토리얼 완료! 열쇠가 생겼으니 북쪽 던전에도 도전해보세요. (설정/도움말: H)")
	end
	send(player)
end

Quest.Listeners[#Quest.Listeners + 1] = function(player, stat, amount)
	local state = states[player]
	local step = state and Steps[state.Step]
	if not step or step.Stat ~= stat then return end
	state.Progress += amount
	if state.Progress >= step.Goal then
		if step.AfterDungeon and player:GetAttribute("Zone") == "Dungeon" then
			-- 던전 안에서는 보상 / 다음 미션을 미루고, 던전에서 나왔을 때 한꺼번에 준다
			state.Progress = step.Goal
			if not state.Notified then
				state.Notified = true
				Remotes.Notify:FireClient(player, "✅ 목표 달성! 던전에서 나가면 보상을 받아요 (티켓 10장)")
			end
			send(player)
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
