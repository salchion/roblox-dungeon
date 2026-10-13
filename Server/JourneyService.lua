-- JourneyService (ServerScriptService > Modules 안의 ModuleScript, 이름: JourneyService)
-- 튜토리얼이 끝난 뒤의 "다음에 뭘 하지?"를 채운다. 카드를 한꺼번에 띄우지 않고, 조건이 맞는 순간 딱 한 번씩(저장됨) 알려 준다.
--   마을: 구역 2 열림 -> 필드 입구 표지 / 필드 8구역 정복 -> 심연 열림 + 포털 표지 / 레벨이 올라 새 던전 입장 가능 -> 그 게이트 표지
--   전투 중: 첫 위기 순간에 대시(Q) / 응급 치료(C) / 궁극기(V) 한 줄 (이미 아는 사람에게는 안 뜸)
-- 상태는 MetaService 의 Rift 표 안 Hints 에 저장되고, 클라이언트는 Attribute "HintDone_<키>" 로 본다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Meta = require(script.Parent:WaitForChild("MetaService"))
local Quest = require(script.Parent:WaitForChild("QuestService"))

local Journey = {}

local positions = {}  -- { Field = Vector3, Rift = Vector3, Gates = { [index] = Vector3 } }
local lastBeat = setmetatable({}, { __mode = "k" })   -- [player] = 마지막으로 마을 안내를 보낸 시각 (너무 자주 안 뜨게)
local dashedAt = setmetatable({}, { __mode = "k" })   -- [player] = 마지막으로 대시한 시각 (클라이언트가 알려 줌)

local function hintsOf(player)
	local rift = Meta.GetRift(player)
	if not rift then return nil end
	rift.Hints = rift.Hints or {}
	return rift.Hints
end

function Journey.IsDone(player, key)
	local hints = hintsOf(player)
	return hints ~= nil and hints[key] == true
end

function Journey.Mark(player, key)
	local hints = hintsOf(player)
	if not hints then return end
	hints[key] = true
	player:SetAttribute("HintDone_" .. key, true)
end

-- 심연은 필드 8구역을 끝까지 밀고(마지막 구역의 군주를 쓰러뜨리고) 나면 열린다. 이야기(필드)가 끝난 뒤의 끝없는 후반 콘텐츠.
-- (이미 심연 기록이 있는 사람은 그대로 열려 있다)
function Journey.RiftOpen(player)
	return Journey.IsDone(player, "FieldClear") or (player:GetAttribute("ClearedZone") or 0) >= Config.Field.ZoneCount
end

local function prompt(player, key, title, text, duration)
	Remotes.Tutorial:FireClient(player, "Prompt", { Key = key, Title = title, Text = text, Duration = duration or 9 })
end

-- 가야 할 곳에 하늘색 빛기둥 + 이름표를 잠깐 켠다
local function beacon(player, position, name, seconds)
	if not position then return end
	Remotes.Tutorial:FireClient(player, "Waypoint", { Pos = position, Name = name })
	task.delay(seconds or 30, function()
		if player.Parent then Remotes.Tutorial:FireClient(player, "WaypointClear") end
	end)
end

-- 최후의 군주를 쓰러뜨리고 돌아온 사람에게: 보스러쉬 포탈로 빛기둥을 켜 준다 (처음 한 번 뜨는 안내와 겹치지 않게 표시해 둔다)
function Journey.PointToRift(player)
	Journey.Mark(player, "RiftOpen")
	beacon(player, positions.Rift, "Boss Rush", 45)
end

function Journey.Init(info)
	positions = info or {}
end

-- 마을 안내: 조건이 맞는 것 중 가장 중요한 하나만 (30초에 하나)
local function townBeat(player, now)
	if now - (lastBeat[player] or 0) < 30 then return end
	if not player:GetAttribute("QuestHud") then return end -- 튜토리얼 미션이 끝나기 전에는 조용히

	if (player:GetAttribute("ClearedZone") or 0) >= 1 and not Journey.IsDone(player, "Zone2") then
		Journey.Mark(player, "Zone2")
		lastBeat[player] = now
		prompt(player, "🚪", "Zone 2 is open!", "Defeat the next zone's lord for better set gear and big rewards. A marker now points to the field entrance.")
		beacon(player, positions.Field, "Field Entrance")
		return
	end

	if Journey.RiftOpen(player) and not Journey.IsDone(player, "RiftOpen") then
		Journey.Mark(player, "RiftOpen")
		lastBeat[player] = now
		prompt(player, "👹", "Field conquered! Boss Rush is open!", "Challenge the Boss Rush at the purple portal in town. 2 runs a day - score = seconds survived x damage dealt, ranked weekly worldwide!")
		beacon(player, positions.Rift, "Boss Rush")
		return
	end

	-- 레벨이 올라 새로 들어갈 수 있게 된 던전 게이트 (여러 개가 한꺼번에 열렸으면 가장 높은 것만 알리고 나머지는 조용히 표시)
	local level = player:GetAttribute("Level") or 1
	local newest = nil
	for index, entry in ipairs(Config.Dungeon.List) do
		if index >= 2 and level >= entry.MinLevel and not Journey.IsDone(player, "Gate" .. index) then
			if newest then Journey.Mark(player, "Gate" .. newest) end
			newest = index
		end
	end
	if newest then
		Journey.Mark(player, "Gate" .. newest)
		local entry = Config.Dungeon.List[newest]
		local dungeonType = Config.Dungeon.Types[entry.Type]
		local difficulty = Config.Dungeon.Difficulties[entry.Diff]
		if dungeonType and difficulty and positions.Gates and positions.Gates[newest] and not player:GetAttribute("Journey_Silent") then
			lastBeat[player] = now
			prompt(player, "🏰", "New dungeon unlocked!", string.format("%s [%s] - Level %d or higher. Bigger rewards and tougher bosses await. A marker now points to the gate.", dungeonType.Name, difficulty.Name, entry.MinLevel))
			beacon(player, positions.Gates[newest], dungeonType.Name)
		end
	end
end

-- 전투 중 첫 위기 한 줄 (이미 해 본 사람 / 한 번 본 사람에게는 안 뜸)
local function combatBeat(player, now)
	if player:GetAttribute("TutorialActive") then return end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	local fraction = humanoid.Health / math.max(1, humanoid.MaxHealth)
	if now - (lastBeat[player] or 0) < 12 then return end

	if fraction < 0.35 and not Journey.IsDone(player, "Heal") and (player:GetAttribute("Level") or 1) >= 3 then
		Journey.Mark(player, "Heal")
		lastBeat[player] = now
		prompt(player, "C", "Low health!", "Press C for first aid to restore health. (green button on the skill bar)", 7)
	elseif fraction < 0.6 and not Journey.IsDone(player, "Dash") and now - (dashedAt[player] or -1000) > 120 then
		Journey.Mark(player, "Dash")
		lastBeat[player] = now
		prompt(player, "Q", "Dash to dodge!", "Press Q to dash past enemy bullets. A close shave earns a NEAR MISS bonus!", 7)
	elseif (player:GetAttribute("UltCharge") or 0) >= Config.Skills.Ult.Cost and not Journey.IsDone(player, "Ult") then
		Journey.Mark(player, "Ult")
		lastBeat[player] = now
		prompt(player, "V", "Ultimate ready!", "Press V for Dead Eye! Lock onto all nearby enemies and fire at once (invincible while active).", 7)
	end
end

function Journey.Start()
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for _, player in ipairs(Players:GetPlayers()) do
				local zone = player:GetAttribute("Zone")
				if zone == "Lobby" then
					townBeat(player, now)
				elseif zone == "Dungeon" or zone == "Field" then
					combatBeat(player, now)
				end
			end
		end
	end)
end

-- 저장된 안내 기록을 Attribute 로 알려 준다 (접속할 때)
function Journey.OnJoin(player)
	local hints = hintsOf(player)
	if not hints then return end
	-- 던전에서 돌아오면 결과 / "더 강해지는 법" 카드가 먼저 보이도록 마을 안내는 30초 뒤부터
	local lastZone = player:GetAttribute("Zone")
	player:GetAttributeChangedSignal("Zone"):Connect(function()
		local zone = player:GetAttribute("Zone")
		if zone == "Lobby" and lastZone == "Dungeon" then lastBeat[player] = os.clock() end
		lastZone = zone
	end)
	local rift = Meta.GetRift(player)
	if rift and not hints.FieldClear and ((rift.Best or 0) > 0 or (rift.DepthDone or 0) > 0) then
		hints.FieldClear = true -- 이미 심연을 해 본 사람은 그대로 열어 둔다
	end
	for key, value in pairs(hints) do
		if value == true then player:SetAttribute("HintDone_" .. key, true) end
	end
	-- 이미 진행한 사람은 지나간 안내를 다시 받지 않게 조용히 표시 (새 던전 게이트)
	local level = player:GetAttribute("Level") or 1
	if level >= 5 then
		for index, entry in ipairs(Config.Dungeon.List) do
			if index >= 2 and level >= entry.MinLevel and hints["Gate" .. index] == nil and (hints.RiftOpen or hints.Zone2) then
				Journey.Mark(player, "Gate" .. index)
			end
		end
	end
end

function Journey.Forget(player)
	lastBeat[player] = nil
	dashedAt[player] = nil
end

Quest.Listeners[#Quest.Listeners + 1] = function(player, stat)
	if stat == "DungeonClears" then
		Journey.Mark(player, "DungeonClear")
	end
end

Remotes.Tutorial.OnServerEvent:Connect(function(player, action)
	if action == "Dashed" then
		dashedAt[player] = os.clock()
	end
end)

return Journey
