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

local function send(player)
	local state = states[player]
	if not state or not player.Parent then return end
	local step = Steps[state.Step]
	player:SetAttribute("TutorialFree", step ~= nil and step.FreeEnhance == true)
	player:SetAttribute("TutorialActive", step ~= nil)
	if not step then
		Remotes.Tutorial:FireClient(player, "Done")
		return
	end
	Remotes.Tutorial:FireClient(player, "Step", {
		Index = state.Step, Total = #Steps, Text = step.Text, Progress = state.Progress, Goal = step.Goal,
		Target = targets[step.Target], TargetName = step.TargetName,
	})
end

function Tutorial.Load(player, saved)
	local state
	if typeof(saved) == "table" then
		state = { Step = math.clamp(math.floor(tonumber(saved.Step) or 1), 1, #Steps + 1), Progress = math.max(0, math.floor(tonumber(saved.Progress) or 0)) }
	elseif (player:GetAttribute("Level") or 1) >= 5 then
		state = { Step = #Steps + 1, Progress = 0 } -- 이미 진행한 유저는 건너뜀
	else
		state = { Step = 1, Progress = 0 }
	end
	states[player] = state
	send(player)
end

function Tutorial.Serialize(player)
	return states[player] or { Step = #Steps + 1, Progress = 0 }
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

local function complete(player, state, step)
	local reward = step.Reward
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
		Remotes.Notify:FireClient(player, "🎉 튜토리얼 완료! 열쇠가 생겼으니 북쪽 던전에도 도전해보세요. (도움말: H)")
	end
	send(player)
end

Quest.Listeners[#Quest.Listeners + 1] = function(player, stat, amount)
	local state = states[player]
	local step = state and Steps[state.Step]
	if not step or step.Stat ~= stat then return end
	state.Progress += amount
	if state.Progress >= step.Goal then
		complete(player, state, step)
	else
		send(player)
	end
end

return Tutorial
