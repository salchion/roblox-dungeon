-- DungeonService (ServerScriptService > Modules 안의 ModuleScript, 이름: DungeonService)
-- 던전 진행 전체를 담당한다.
--   입장 -> 카운트다운 -> [웨이브 -> 클리어 -> 30초 스탯 분배] x TotalWaves -> 보스 -> 승리/패배 -> 로비 복귀
-- 던전 한 판(run)마다 로비에서 멀리 떨어진 곳에 아레나를 따로 만들기 때문에 여러 파티가 동시에 플레이할 수 있다.
-- 스탯 포인트(치명타/공격속도/최대체력)는 그 판에서만 유효하고, 던전을 나가면 초기화된다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Party = require(script.Parent:WaitForChild("PartyService"))
local Quest = require(script.Parent:WaitForChild("QuestService"))
local Advice = require(script.Parent:WaitForChild("AdviceService"))
local Level = require(script.Parent:WaitForChild("LevelService"))
local MonsterTypes = require(script.Parent:WaitForChild("MonsterTypes"))
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Combo = require(script.Parent:WaitForChild("ComboService"))
local Meta = require(script.Parent:WaitForChild("MetaService"))
local DungeonTerrain = require(script.Parent:WaitForChild("DungeonTerrain"))
local Keys = require(script.Parent:WaitForChild("KeyService"))
local Loot = require(script.Parent:WaitForChild("LootService"))

local D = Config.Dungeon
local P = Config.Player

local Dungeon = {}

local runs = {}          -- [runId] = run
local playerRun = {}     -- [player] = run
local usedSlots = {}     -- [slot] = true
local nextRunId = 1
local lobbySpawn = CFrame.new(0, 4, 25)

local STAT_ATTRIBUTES = { "StatPoints" }
for _, perkKey in ipairs(Config.Perks.Order) do
	table.insert(STAT_ATTRIBUTES, Config.Perks[perkKey].Attr)
end

------------------------------------------------------------
-- 유틸
------------------------------------------------------------
local function notify(player, text)
	Remotes.Notify:FireClient(player, text)
end

local function notifyAll(run, text)
	for _, member in ipairs(run.Members) do
		notify(member, text)
	end
end

local function getAliveParts(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and humanoid and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil
end

function Dungeon.GetMaxHealth(player)
	return P.BaseHealth + (player:GetAttribute("HealthPoints") or 0) * P.HealthPerPoint + (player:GetAttribute("GearHealth") or 0)
		+ Config.GetLevelHealth(player:GetAttribute("Level") or 1)
		+ (player:GetAttribute("TrainHealth") or 0)
end

-- 최대 체력을 스탯에 맞게 갱신하고 heal 만큼 회복 (math.huge면 완전 회복)
local function applyMaxHealth(player, heal)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	humanoid.MaxHealth = Dungeon.GetMaxHealth(player)
	if humanoid.Health > 0 then
		humanoid.Health = math.min(humanoid.Health + (heal or 0), humanoid.MaxHealth)
	end
end

-- 장비 변경 등으로 최대 체력이 달라졌을 때 (로비에서 호출)
function Dungeon.RefreshMaxHealth(player)
	applyMaxHealth(player, math.huge)
end

local function resetStats(player)
	for _, attribute in ipairs(STAT_ATTRIBUTES) do
		player:SetAttribute(attribute, 0)
	end
	applyMaxHealth(player, math.huge)
end

local function pivotTo(player, cframe)
	local character = player.Character
	if character then
		character:PivotTo(cframe)
	end
end

local function arenaSpawnCFrame(run)
	local angle = math.random() * math.pi * 2
	local offset = Vector3.new(math.cos(angle) * 6, 5, math.sin(angle) * 6)
	return CFrame.new((run.StartPos or run.Origin) + offset)
end

local function giveGold(run, amount)
	amount = math.floor(amount * run.GoldMult * Config.Economy.DungeonGoldMult * (Config.IsGoldenTime() and Config.Golden.GoldMult or 1) + 0.5)
	for _, member in ipairs(run.Members) do
		local bonus = math.floor(amount * Config.GoldBonus(member) + 0.5) -- 환생 골드 보너스
		member:SetAttribute("Gold", (member:GetAttribute("Gold") or 0) + bonus)
		run.Earned[member] = (run.Earned[member] or 0) + bonus
	end
end

-- 파티원 모두에게 경험치 (던전 종류 x 난이도 배율 적용)
local function giveXp(run, amount)
	amount = math.floor(amount * run.GoldMult + 0.5)
	for _, member in ipairs(run.Members) do
		Level.AddXP(member, amount)
	end
end

local function allDown(run)
	for _, member in ipairs(run.Members) do
		if getAliveParts(member) then
			return false
		end
	end
	return true
end

------------------------------------------------------------
-- 아레나 생성
------------------------------------------------------------
local function buildArena(run)
	local folder = Instance.new("Folder")
	folder.Name = "Dungeon_" .. run.Id
	folder.Parent = workspace

	-- 산맥 / 언덕 / 구덩이 / 협곡 / 동굴로 이루어진 지형 (판마다 모양이 다름)
	local terrain = DungeonTerrain.BuildColosseum(run, run.Type, D, folder)
	run.ArenaCenter = terrain.Center
	run.SpawnPoints = terrain.SpawnPoints
	run.Circles = terrain.Circles
	run.AllSpawns = terrain.SpawnPoints
	run.Rooms = terrain.Rooms
	run.StartPos = terrain.StartPos
	run.BossPos = terrain.BossPos
	run.LayoutName = terrain.LayoutName
	run.GroundY = terrain.GroundY

	local monsters = Instance.new("Folder")
	monsters.Name = "Monsters"
	monsters.Parent = folder

	run.Folder = folder
	run.MonstersFolder = monsters
end

------------------------------------------------------------
-- 몬스터 / 보스
------------------------------------------------------------
local function createHealthBar(part, text, width)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, width, 0, 28)
	gui.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 1.5, 0)
	gui.AlwaysOnTop = false -- 절벽 / 벽 너머의 몬스터 체력바가 비쳐 보이지 않게 (같은 방 / 시야 안에서만 보임)
	gui.MaxDistance = 110
	gui.Parent = part

	-- 벽 너머에서도 "저쪽에 몬스터가 있다"는 걸 알 수 있는 작은 붉은 화살표 (멀리서도 보이고 벽을 뚫고 보인다)
	local marker = Instance.new("BillboardGui")
	marker.Name = "FoeMarker"
	marker.Size = UDim2.fromOffset(26, 26)
	marker.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 6, 0)
	marker.AlwaysOnTop = true
	marker.MaxDistance = 260
	marker.Parent = part
	local arrow = Instance.new("TextLabel")
	arrow.Size = UDim2.fromScale(1, 1)
	arrow.BackgroundTransparency = 1
	arrow.Text = "▼"
	arrow.Font = Enum.Font.GothamBlack
	arrow.TextScaled = true
	arrow.TextColor3 = Color3.fromRGB(255, 80, 70)
	arrow.TextStrokeTransparency = 0.2
	arrow.TextTransparency = 0.15
	arrow.Parent = marker

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.5, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Text = text
	label.Parent = gui

	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, 0, 0.4, 0)
	back.Position = UDim2.new(0, 0, 0.6, 0)
	back.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	back.BorderSizePixel = 0
	back.Parent = gui

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(230, 60, 60)
	fill.BorderSizePixel = 0
	fill.Parent = back

	return fill
end

local function ringPosition(run, size)
	local points = run.SpawnPoints
	if points and #points > 0 then
		return points[math.random(#points)] + Vector3.new(0, size / 2 + 0.5, 0)
	end
	local angle = math.random() * math.pi * 2
	return run.Origin + Vector3.new(math.cos(angle) * D.SpawnRadius, size / 2, math.sin(angle) * D.SpawnRadius)
end

-- 걸을 수 있는 곳인가: 길 / 방(원)들의 합집합 안쪽. 그 밖은 절벽이라 몬스터와 탄이 지나가지 못한다.
local function walkable(run, x, z)
	local circles = run.Circles
	if not circles then return true end
	for _, c in ipairs(circles) do
		local dx, dz = x - c.X, z - c.Z
		local r = c.R - 0.5
		if dx * dx + dz * dz <= r * r then
			return true
		end
	end
	return false
end

-- a -> b 선분이 절벽에 막히는가. 막히지 않으면 true, 막히면 false 와 마지막으로 열려 있던 지점을 돌려준다.
local function segmentClear(run, a, b)
	local delta = b - a
	local distance = delta.Magnitude
	local steps = math.ceil(distance / 4)
	local lastOpen = a
	for i = 1, steps do
		local p = a + delta * (i / steps)
		if not walkable(run, p.X, p.Z) then
			return false, lastOpen
		end
		lastOpen = p
	end
	return true, b
end

-- 길 안내: 방 / 길(원)들이 서로 겹쳐서 이어진 그래프에서 from 이 있는 원 -> to 가 있는 원까지 최단 경로를 찾고,
-- 다음에 갈 원의 중심을 돌려준다. (벽에 막혀 곧장 갈 수 없을 때 몬스터가 길을 따라 돌아가게 한다)
local function circleIndexAt(run, x, z)
	local best, bestScore = nil, math.huge
	for index, c in ipairs(run.Circles) do
		local dx, dz = x - c.X, z - c.Z
		local score = math.sqrt(dx * dx + dz * dz) - c.R -- 안쪽이면 음수
		if score < bestScore then
			best, bestScore = index, score
		end
	end
	return best
end

local function buildAdjacency(run)
	local circles = run.Circles
	local adjacency = {}
	for i = 1, #circles do
		adjacency[i] = {}
	end
	for i = 1, #circles do
		local a = circles[i]
		for j = i + 1, #circles do
			local b = circles[j]
			local dx, dz = a.X - b.X, a.Z - b.Z
			if math.sqrt(dx * dx + dz * dz) < a.R + b.R - 4 then
				table.insert(adjacency[i], j)
				table.insert(adjacency[j], i)
			end
		end
	end
	return adjacency
end

local function nextStep(run, data, from, to)
	if not run.Circles or #run.Circles == 0 then return nil end
	local now = os.clock()
	if data.NavUntil and now < data.NavUntil and data.NavTarget then
		return data.NavTarget
	end
	run.Adjacency = run.Adjacency or buildAdjacency(run)
	local start = circleIndexAt(run, from.X, from.Z)
	local goal = circleIndexAt(run, to.X, to.Z)
	if not start or not goal then return nil end
	if start == goal then
		data.NavTarget = Vector3.new(to.X, from.Y, to.Z)
	else
		-- 너비 우선 탐색
		local previous = { [start] = false }
		local queue, head = { start }, 1
		while head <= #queue and previous[goal] == nil do
			local current = queue[head]
			head += 1
			for _, neighbor in ipairs(run.Adjacency[current]) do
				if previous[neighbor] == nil then
					previous[neighbor] = current
					table.insert(queue, neighbor)
				end
			end
		end
		if previous[goal] == nil then return nil end
		local step = goal
		while previous[step] ~= start and previous[step] ~= false do
			step = previous[step]
		end
		local c = run.Circles[step]
		data.NavTarget = Vector3.new(c.X, from.Y, c.Z)
	end
	data.NavUntil = now + 0.35
	return data.NavTarget
end

-- 이 위치 아래의 땅 높이 (지형이 울퉁불퉁하므로 raycast 로 구한다)
local function groundAt(run, x, z, fromY)
	return run.GroundY and run.GroundY(x, z, fromY) or run.Origin.Y
end

local function registerMonster(run, part, stats, text, barWidth, extra)
	local data = {
		Stats = stats,
		Health = stats.MaxHealth,
		MaxHealth = stats.MaxHealth,
		HealthFill = createHealthBar(part, text, barWidth),
		NextShot = os.clock() + stats.ShotInterval,
		BaseColor = part.Color,
	}
	for key, value in pairs(extra or {}) do
		data[key] = value
	end
	run.Monsters[part] = data
	run.MonsterCount += 1
	return data
end

local function spawnMonster(run, level, position)
	-- 던전 종류마다 나오는 몬스터 종류가 다르다 (Config.Dungeon.Types[..].MonsterPool)
	local typeKey = MonsterTypes.Pick(run.Type.MonsterPool)
	local def = MonsterTypes.Defs[typeKey]

	local stats = Config.Monster.GetStats(level)
	stats.MaxHealth = math.floor(stats.MaxHealth * D.GetHealthScale(run.PartySize) * run.Difficulty.HealthMult)
	stats.ShotDamage = math.floor(stats.ShotDamage * run.Difficulty.DamageMult)
	MonsterTypes.ApplyDef(typeKey, stats)
	local mutator = run.Mutator
	if mutator then -- 던전 변이 (거대화 / 신속 / 떼거지 / 황금 / 광폭)
		stats.MaxHealth = math.floor(stats.MaxHealth * (mutator.HealthMult or 1))
		stats.ShotDamage = math.floor(stats.ShotDamage * (mutator.DamageMult or 1))
		stats.Speed *= mutator.SpeedMult or 1
		stats.ShotInterval *= mutator.IntervalMult or 1
	end
	if run.DepthScale then -- 심연 깊이: 구역(필드)과 같은 방식으로 체력 / 공격력 / 속도가 확 뛴다
		stats.MaxHealth = math.floor(stats.MaxHealth * run.DepthScale.Health)
		stats.ShotDamage = math.max(1, math.floor(stats.ShotDamage * run.DepthScale.Damage))
		stats.Speed *= run.DepthScale.Speed
	end
	if run.PenHealth then -- 랜덤 패널티로 누적된 적 강화
		stats.MaxHealth = math.floor(stats.MaxHealth * run.PenHealth)
		stats.ShotDamage = math.floor(stats.ShotDamage * run.PenDamage)
		stats.Speed *= run.PenSpeed
		stats.ShotInterval *= run.PenInterval
	end

	local color = def.Color:Lerp(run.Type.MonsterColor, 0.25)
	local part = MonsterTypes.Build(typeKey, stats.Size, color, position or ringPosition(run, stats.Size), run.MonstersFolder)
	-- 던전 분위기: 몬스터마다 던전 색의 은은한 빛을 두른다 (어두운 동굴에서도 실루엣이 보이게)
	local glow = Instance.new("PointLight")
	glow.Range = 10 + stats.Size
	glow.Brightness = 0.9
	glow.Color = run.Type.Torch or color
	glow.Parent = part

	return registerMonster(run, part, stats, string.format("Lv.%d %s", level, def.Name), 140, {
		TypeKey = typeKey,
		Def = def,
		Level = level,
		Phase = math.random() * math.pi * 2,
		NextAttack = os.clock() + stats.ShotInterval,
	})
end

-- 보스 외형: 단순한 공이 아니라 뿔 / 날개 / 눈 / 가시 / 꼬리 / 가슴의 룬이 달린 거대한 군주 (앞은 -Z, 보스는 항상 가장 가까운 플레이어를 바라본다)
local function decorateBoss(part, size, glow)
	local dark = part.Color:Lerp(Color3.new(0, 0, 0), 0.55)
	part.Material = Enum.Material.Slate
	part.Color = dark
	local function piece(shape, sx, sy, sz, x, y, z, color, material, rx, ry, rz, transparency)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, false, true
		p.Shape = shape
		p.Size = Vector3.new(math.max(0.1, sx), math.max(0.1, sy), math.max(0.1, sz))
		p.Color = color
		p.Material = material
		p.Transparency = transparency or 0
		p.CFrame = part.CFrame * CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = p
		weld.Parent = p
		p.Parent = part
		return p
	end
	local S = size
	local Ball, Block = Enum.PartType.Ball, Enum.PartType.Block
	local Neon, Metal, Slate = Enum.Material.Neon, Enum.Material.Metal, Enum.Material.Slate
	local bone = Color3.fromRGB(215, 205, 185)
	-- 눈 / 가슴 룬 / 이마의 보석
	for _, side in ipairs({ -1, 1 }) do
		piece(Ball, S * 0.13, S * 0.13, S * 0.13, side * S * 0.2, S * 0.18, -S * 0.45, Color3.fromRGB(255, 240, 120), Neon)
		-- 뿔 (휘어진 두 마디)
		piece(Block, S * 0.1, S * 0.42, S * 0.1, side * S * 0.28, S * 0.52, -S * 0.08, bone, Slate, 0, 0, side * -22)
		piece(Block, S * 0.08, S * 0.3, S * 0.08, side * S * 0.42, S * 0.8, -S * 0.12, bone, Slate, -15, 0, side * -48)
		-- 어깨 갑옷
		piece(Ball, S * 0.34, S * 0.34, S * 0.34, side * S * 0.52, S * 0.2, 0, dark:Lerp(Color3.new(1, 1, 1), 0.12), Metal)
		-- 날개 (뼈대 + 빛나는 막)
		piece(Block, S * 1.0, S * 0.07, S * 0.09, side * S * 0.95, S * 0.52, S * 0.28, bone, Slate, 0, 0, side * 28)
		piece(Block, S * 0.95, S * 0.04, S * 0.65, side * S * 0.92, S * 0.4, S * 0.4, glow, Neon, 0, 0, side * 28, 0.4)
		piece(Block, S * 0.7, S * 0.04, S * 0.5, side * S * 0.78, S * 0.14, S * 0.62, glow, Neon, 0, 0, side * 20, 0.5)
	end
	piece(Ball, S * 0.24, S * 0.24, S * 0.24, 0, S * 0.02, -S * 0.5, glow, Neon)
	piece(Ball, S * 0.12, S * 0.12, S * 0.12, 0, S * 0.36, -S * 0.42, Color3.fromRGB(255, 70, 90), Neon)
	-- 등 가시
	for i = 0, 4 do
		piece(Block, S * 0.09, S * (0.34 - i * 0.04), S * 0.09, 0, S * (0.5 - i * 0.07), S * (0.05 + i * 0.12), bone, Slate, 25 + i * 8, 0, 0)
	end
	-- 꼬리 (뒤쪽으로 점점 가늘어지는 구슬 + 끝의 불꽃)
	for i = 1, 4 do
		piece(Ball, S * (0.32 - i * 0.05), S * (0.32 - i * 0.05), S * (0.32 - i * 0.05), 0, -S * 0.1 * i, S * (0.45 + i * 0.22), dark, Slate)
	end
	local tip = piece(Ball, S * 0.22, S * 0.22, S * 0.22, 0, -S * 0.5, S * 1.45, glow, Neon)
	local fire = Instance.new("ParticleEmitter")
	fire.Rate = 40
	fire.Lifetime = NumberRange.new(0.4, 0.9)
	fire.Speed = NumberRange.new(3, 8)
	fire.SpreadAngle = Vector2.new(35, 35)
	fire.LightEmission = 1
	fire.Color = ColorSequence.new(glow, Color3.fromRGB(255, 240, 160))
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, S * 0.12), NumberSequenceKeypoint.new(1, 0) })
	fire.Parent = tip
	local halo = Instance.new("PointLight")
	halo.Range = S * 1.6
	halo.Brightness = 2
	halo.Color = glow
	halo.Parent = part
end

-- 약점 구슬: 보스 주위를 도는 노란 구슬. 직접 조준해서 맞히면 3배 치명타 + 데드아이 게이지 (자동 조준은 몸통을 노린다)
local function makeWeakOrb(part)
	local orb = Instance.new("Part")
	orb.Name = "WeakPoint"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(7.2, 7.2, 7.2) -- 맞히기 쉽게 크다
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = true -- 구슬을 직접 조준(클릭)할 수 있게: 조준선 / 총알 판정이 구슬에 맞는다
	orb.CanTouch = false
	orb.Color = Color3.fromRGB(255, 235, 80)
	orb.Material = Enum.Material.Neon
	orb.Position = part.Position
	orb.Parent = part
	local orbLight = Instance.new("PointLight")
	orbLight.Color = Color3.fromRGB(255, 235, 80)
	orbLight.Range = 22
	orbLight.Brightness = 2.5
	orbLight.Parent = orb
	local orbGui = Instance.new("BillboardGui")
	orbGui.Size = UDim2.new(0, 120, 0, 36)
	orbGui.StudsOffset = Vector3.new(0, 5.6, 0)
	orbGui.MaxDistance = 200
	orbGui.AlwaysOnTop = true
	orbGui.Parent = orb
	-- 눈에 확 띄게: 구슬을 감싸는 반투명 후광 + 반짝이는 입자 (몸통과 색이 다른 노란색)
	local halo = Instance.new("Part")
	halo.Name = "WeakHalo"
	halo.Shape = Enum.PartType.Ball
	halo.Size = Vector3.new(12, 12, 12)
	halo.Anchored = false
	halo.Massless = true
	halo.CanCollide = false
	halo.CanQuery = false
	halo.CanTouch = false
	halo.Material = Enum.Material.Neon
	halo.Color = Color3.fromRGB(255, 220, 60)
	halo.Transparency = 0.75
	halo.CFrame = orb.CFrame
	local haloWeld = Instance.new("WeldConstraint")
	haloWeld.Part0 = orb
	haloWeld.Part1 = halo
	haloWeld.Parent = halo
	halo.Parent = orb
	local sparks = Instance.new("ParticleEmitter")
	sparks.Rate = 18
	sparks.Lifetime = NumberRange.new(0.5, 1)
	sparks.Speed = NumberRange.new(2, 6)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.LightEmission = 1
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 240, 120))
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
	sparks.Parent = orb
	local orbText = Instance.new("TextLabel")
	orbText.Size = UDim2.new(1, 0, 1, 0)
	orbText.BackgroundTransparency = 1
	orbText.Font = Enum.Font.GothamBlack
	orbText.TextScaled = true
	orbText.TextColor3 = Color3.fromRGB(255, 240, 120)
	orbText.TextStrokeTransparency = 0
	orbText.Text = "🎯 약점! 여길 맞혀요"
	orbText.Parent = orbGui
	return orb
end

local function spawnBoss(run)
	local boss = Config.Boss
	local bossType = run.Type.Boss
	local stats = {
		Size = boss.Size * run.BossVariant.SizeMult,
		MaxHealth = math.floor(boss.MaxHealth * D.GetHealthScale(run.PartySize) * bossType.HealthMult * run.Difficulty.HealthMult * run.BossVariant.HealthMult),
		Speed = boss.Speed * run.BossVariant.SpeedMult,
		ShotDamage = math.floor(boss.ShotDamage * bossType.DamageMult * run.Difficulty.DamageMult * run.BossVariant.DamageMult),
		ShotInterval = boss.ShotInterval,
		ShotSpeed = boss.ShotSpeed,
		Gold = boss.Gold,
	}

	local part = Instance.new("Part")
	part.Name = "Boss"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(stats.Size, stats.Size, stats.Size)
	part.Anchored = true
	part.CanCollide = false
	part.Color = bossType.Color:Lerp(run.BossVariant.Color, 0.45)
	part.Material = Enum.Material.Neon
	local bossSpot = run.BossPos or (run.Origin + Vector3.new(0, 0, -D.SpawnRadius))
	part.Position = Vector3.new(bossSpot.X, groundAt(run, bossSpot.X, bossSpot.Z, run.Origin.Y + 10) + stats.Size / 2, bossSpot.Z)
	part.Parent = run.MonstersFolder
	decorateBoss(part, stats.Size, bossType.Color:Lerp(run.BossVariant.Color, 0.45):Lerp(Color3.fromRGB(255, 190, 90), 0.35))
	CollectionService:AddTag(part, "Monster")
	CollectionService:AddTag(part, "RadarBoss")

	local data = registerMonster(run, part, stats, run.BossName, 320, {
		IsBoss = true,
		Enraged = false,
		NextPattern = os.clock() + 3,
		Casting = false,
		LastPattern = nil,
	})
	local orb = makeWeakOrb(part)
	data.WeakPart = orb
	run.Boss = data
	run.BossPart = part
	for _, member in ipairs(run.Members) do
		Remotes.Tutorial:FireClient(member, "Prompt", { Key = "🎯", Title = "약점을 노려라!", Text = "보스 주위를 도는 노란 구슬을 마우스로 직접 조준해서 클릭하면 약점이 노출돼서 4초간 받는 피해 x3! + 데드아이 게이지 (자동 공격으로는 안 돼요)", Duration = 7, Top = true })
	end
end

local function fireProjectile(run, origin, direction, speed, damage, size, color, style)
	local ball = Effects.MakeProjectile(origin, direction, size, color, style)
	ball.Parent = run.Folder

	table.insert(run.Projectiles, {
		Part = ball,
		Direction = direction.Unit,
		Speed = speed,
		Damage = damage,
		Radius = size / 2,
		Expire = os.clock() + 5,
	})
end

local function getNearestTarget(run, position)
	local nearest, nearestDist = nil, math.huge
	for _, member in ipairs(run.Members) do
		local root = getAliveParts(member)
		if root then
			local dist = (root.Position - position).Magnitude
			if dist < nearestDist then
				nearest, nearestDist = root, dist
			end
		end
	end
	return nearest, nearestDist
end

local function rotateY(vector, degrees)
	return CFrame.Angles(0, math.rad(degrees), 0):VectorToWorldSpace(vector)
end

-- 보스 패턴 5종 (Fan / Ring / Spiral / Meteor + 광폭화 시 더 빨라짐).
-- 아래 함수들은 task.spawn 안에서 실행되므로 task.wait 를 쓸 수 있고, 보스가 죽거나 던전이 끝나면 중단한다.
local function bossAlive(run, part, data)
	return run.Monsters[part] == data and run.Phase == "Boss"
end

-- 패턴 시작 전 예고: 보스 색을 잠깐 바꿈
local function bossWarn(run, part, data, color, seconds)
	part.Color = color
	task.wait(seconds)
	if bossAlive(run, part, data) then
		part.Color = data.BaseColor
	end
end

local function flatOrigin(run, part)
	return Vector3.new(part.Position.X, groundAt(run, part.Position.X, part.Position.Z, part.Position.Y) + 3, part.Position.Z)
end

-- 1) 부채꼴 조준 연발: 가장 가까운 플레이어를 향해 5갈래 탄을 2~3번
local function bossFan(run, part, data)
	bossWarn(run, part, data, Color3.fromRGB(255, 220, 80), 0.5)
	for _ = 1, data.Enraged and 3 or 2 do
		if not bossAlive(run, part, data) then return end
		local target = getNearestTarget(run, part.Position)
		if not target then return end
		local direction = (target.Position - part.Position).Unit
		for _, angle in ipairs({ -24, -12, 0, 12, 24 }) do
			fireProjectile(run, part.Position, rotateY(direction, angle), data.Stats.ShotSpeed, data.Stats.ShotDamage, 3.2, Color3.fromRGB(255, 80, 60))
		end
		task.wait(0.4)
	end
end

-- 2) 전방위 탄막: 고리 모양 탄을 2번 (두 번째는 엇갈리게)
local function bossRing(run, part, data)
	bossWarn(run, part, data, Color3.new(1, 1, 1), 0.8)
	local count = data.Enraged and 24 or Config.Boss.RingCount
	local radius = part.Size.X / 2 + 1
	for wave = 0, 1 do
		if not bossAlive(run, part, data) then return end
		local offset = wave * (math.pi / count)
		for i = 0, count - 1 do
			local angle = offset + (i / count) * math.pi * 2
			local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
			fireProjectile(run, flatOrigin(run, part) + direction * radius, direction, 32, math.floor(data.Stats.ShotDamage * 0.7), 2.5, Color3.fromRGB(255, 180, 60))
		end
		task.wait(0.6)
	end
end

-- 3) 나선 탄막: 두 갈래 탄이 빙글빙글 돌며 계속 나옴
local function bossSpiral(run, part, data)
	bossWarn(run, part, data, Color3.fromRGB(190, 90, 255), 0.7)
	local duration = data.Enraged and 4.5 or 3.2
	local started = os.clock()
	local angle = math.random() * math.pi * 2
	while os.clock() - started < duration and bossAlive(run, part, data) do
		for arm = 0, 1 do
			local a = angle + arm * math.pi
			local direction = Vector3.new(math.cos(a), 0, math.sin(a))
			fireProjectile(run, flatOrigin(run, part) + direction * (part.Size.X / 2 + 1), direction, 30, math.floor(data.Stats.ShotDamage * 0.6), 2.2, Color3.fromRGB(190, 110, 255))
		end
		angle += 0.42
		task.wait(0.09)
	end
end

-- 4) 메테오: 플레이어 발밑에 붉은 원이 나타나고, 1.4초 뒤 폭발 (그 안에 서 있으면 큰 피해)
local function bossMeteor(run, part, data)
	part.Color = Color3.fromRGB(255, 120, 40)
	local radius = 9
	local markers = {}

	for _, member in ipairs(run.Members) do
		local root = getAliveParts(member)
		if root then
			for i = 1, data.Enraged and 3 or 2 do
				local jitter = i == 1 and Vector3.zero or Vector3.new(math.random(-18, 18), 0, math.random(-18, 18))
				local center = Vector3.new(root.Position.X + jitter.X, groundAt(run, root.Position.X + jitter.X, root.Position.Z + jitter.Z, root.Position.Y) + 0.3, root.Position.Z + jitter.Z)

				local marker = Instance.new("Part")
				marker.Shape = Enum.PartType.Cylinder
				marker.Anchored = true
				marker.CanCollide = false
				marker.CanQuery = false
				marker.CanTouch = false
				marker.Material = Enum.Material.Neon
				marker.Color = Color3.fromRGB(255, 50, 40)
				marker.Transparency = 0.55
				marker.Size = Vector3.new(0.4, radius * 2, radius * 2)
				marker.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
				marker.Parent = run.Folder
				table.insert(markers, { Part = marker, Center = center })
			end
		end
	end

	task.wait(1.4)
	if bossAlive(run, part, data) then
		part.Color = data.BaseColor
		for _, marker in ipairs(markers) do
			for _, member in ipairs(run.Members) do
				local root, humanoid = getAliveParts(member)
				if root then
					local flat = Vector3.new(root.Position.X - marker.Center.X, 0, root.Position.Z - marker.Center.Z)
					if flat.Magnitude <= radius then
						humanoid:TakeDamage(math.floor(data.Stats.ShotDamage * 1.6))
					end
				end
			end
			Effects.Burst(marker.Center + Vector3.new(0, 2, 0), Color3.fromRGB(255, 120, 50), 40)
		end
	end
	for _, marker in ipairs(markers) do
		marker.Part:Destroy()
	end
end

-- 5) 대지 강타: 보스를 중심으로 충격파 고리가 퍼져 나간다. 땅에 닿아 있으면 맞으니 고리가 올 때 점프!
local function bossSlam(run, part, data)
	bossWarn(run, part, data, Color3.fromRGB(255, 70, 50), 0.8)
	if not bossAlive(run, part, data) then return end
	local center = Vector3.new(part.Position.X, groundAt(run, part.Position.X, part.Position.Z, part.Position.Y), part.Position.Z)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 90, 60)
	ring.Transparency = 0.35
	ring.Parent = run.Folder
	local hit = {}
	local radius, speed, maxRadius = 6, 48, 70
	local last = os.clock()
	while radius < maxRadius and bossAlive(run, part, data) do
		local now = os.clock()
		radius += speed * (now - last)
		last = now
		ring.Size = Vector3.new(1.2, radius * 2, radius * 2)
		ring.CFrame = CFrame.new(center + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
		for _, member in ipairs(run.Members) do
			local root, humanoid = getAliveParts(member)
			if root and not hit[member] then
				local flatDist = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z).Magnitude
				local height = root.Position.Y - groundAt(run, root.Position.X, root.Position.Z, root.Position.Y)
				if math.abs(flatDist - radius) < 3 and height < 4.5 then
					hit[member] = true
					humanoid:TakeDamage(math.floor(data.Stats.ShotDamage * 1.3))
					Effects.Burst(root.Position, Color3.fromRGB(255, 90, 60), 25)
				end
			end
		end
		task.wait(0.03)
	end
	ring:Destroy()
end

-- 6) 소환: 쫄병을 불러낸다 (이미 몬스터가 많으면 생략)
local function bossSummon(run, part, data)
	bossWarn(run, part, data, Color3.fromRGB(190, 90, 255), 0.7)
	if not bossAlive(run, part, data) or run.MonsterCount >= 14 then return end
	local level = math.max(1, Config.Boss.MinionLevel + run.LevelBonus + 2)
	for i = 1, data.Enraged and 5 or 3 do
		local angle = (i / 5) * math.pi * 2 + math.random()
		local x, z = part.Position.X + math.cos(angle) * 22, part.Position.Z + math.sin(angle) * 22
		local stats = Config.Monster.GetStats(level)
		spawnMonster(run, level, Vector3.new(x, groundAt(run, x, z, part.Position.Y) + stats.Size / 2, z))
		Effects.Burst(Vector3.new(x, part.Position.Y, z), Color3.fromRGB(190, 90, 255), 20)
	end
	notifyAll(run, "👹 " .. run.BossName .. "이(가) 부하를 불러냈다!")
end

-- 7) 화염 줄기 (디아블로 벨리알식): 보스 앞에 붉은 줄기 여러 개가 예고된 뒤 불길이 치솟는다. 줄기 "사이"로 피하고, 두 번째는 줄기 위치가 어긋난다
local function bossLanes(run, part, data)
	bossWarn(run, part, data, Color3.fromRGB(255, 120, 50), 0.5)
	if not bossAlive(run, part, data) then return end
	local target = getNearestTarget(run, part.Position)
	if not target then return end
	local origin = Vector3.new(part.Position.X, groundAt(run, part.Position.X, part.Position.Z, part.Position.Y) + 0.3, part.Position.Z)
	local dir = Vector3.new(target.Position.X - origin.X, 0, target.Position.Z - origin.Z)
	dir = dir.Magnitude > 1 and dir.Unit or Vector3.new(-1, 0, 0)
	local perp = Vector3.new(-dir.Z, 0, dir.X)
	local width, length = 9, 120
	for wave = 0, 1 do
		if not bossAlive(run, part, data) then return end
		local strips = {}
		for k = -3, 3 do
			local offset = k * 18 + wave * 9
			local center = origin + dir * (length / 2 + part.Size.X * 0.4) + perp * offset
			local strip = Instance.new("Part")
			strip.Anchored, strip.CanCollide, strip.CanQuery, strip.CanTouch = true, false, false, false
			strip.Material = Enum.Material.Neon
			strip.Color = Color3.fromRGB(255, 60, 40)
			strip.Transparency = 0.6
			strip.Size = Vector3.new(width, 0.4, length)
			strip.CFrame = CFrame.lookAt(center, center + dir)
			strip.Parent = run.Folder
			table.insert(strips, strip)
		end
		task.wait(1.5)
		if not bossAlive(run, part, data) then
			for _, strip in ipairs(strips) do strip:Destroy() end
			return
		end
		for _, strip in ipairs(strips) do
			strip.Color = Color3.fromRGB(255, 170, 60)
			strip.Transparency = 0.1
			strip.Size = Vector3.new(width, 6, length)
			strip.CFrame = strip.CFrame * CFrame.new(0, 3, 0)
			TweenService:Create(strip, TweenInfo.new(0.45), { Transparency = 1 }):Play()
			Effects.Burst(strip.Position, Color3.fromRGB(255, 140, 50), 18)
			Debris:AddItem(strip, 0.5)
		end
		for _, member in ipairs(run.Members) do
			local root, humanoid = getAliveParts(member)
			if root then
				local flat = Vector3.new(root.Position.X - origin.X, 0, root.Position.Z - origin.Z)
				local along = flat:Dot(dir)
				local lateral = flat:Dot(perp)
				local height = root.Position.Y - groundAt(run, root.Position.X, root.Position.Z, root.Position.Y)
				if along > 0 and along < length + part.Size.X and height < 7 then
					for k = -3, 3 do
						if math.abs(lateral - (k * 18 + wave * 9)) < width / 2 then
							humanoid:TakeDamage(math.floor(data.Stats.ShotDamage * 1.5))
							break
						end
					end
				end
			end
		end
		task.wait(0.4)
	end
end

-- 8) 회전 레이저 (엔더 드래곤식 브레스): 가는 붉은 선이 방향을 잡은 뒤 굵은 빛줄기가 부채꼴로 휩쓴다. 빛줄기를 따라 돌거나 뒤로 빠져서 피한다
local function bossSweep(run, part, data)
	bossWarn(run, part, data, Color3.fromRGB(255, 80, 80), 0.4)
	if not bossAlive(run, part, data) then return end
	local target = getNearestTarget(run, part.Position)
	if not target then return end
	local origin = Vector3.new(part.Position.X, groundAt(run, part.Position.X, part.Position.Z, part.Position.Y) + 2, part.Position.Z)
	local toTarget = Vector3.new(target.Position.X - origin.X, 0, target.Position.Z - origin.Z)
	local baseAngle = math.atan2(toTarget.Z, toTarget.X)
	local sign = math.random() < 0.5 and -1 or 1
	local span = math.rad(100)
	local length = 130
	local beam = Instance.new("Part")
	beam.Anchored, beam.CanCollide, beam.CanQuery, beam.CanTouch = true, false, false, false
	beam.Material = Enum.Material.Neon
	beam.Parent = run.Folder
	local function place(angle, thickness, color, transparency)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		beam.Color = color
		beam.Transparency = transparency
		beam.Size = Vector3.new(thickness, thickness, length)
		beam.CFrame = CFrame.lookAt(origin, origin + dir) * CFrame.new(0, 0, -length / 2)
		return dir
	end
	local startAngle = baseAngle - sign * span / 2
	place(startAngle, 0.6, Color3.fromRGB(255, 60, 60), 0.35) -- 예고선
	task.wait(1.0)
	local duration = data.Enraged and 3.2 or 4.0
	local started = os.clock()
	local lastHit = {}
	while bossAlive(run, part, data) do
		local t = (os.clock() - started) / duration
		if t >= 1 then break end
		local angle = startAngle + sign * span * t
		local dir = place(angle, 6, Color3.fromRGB(255, 230, 170), 0.1)
		for _, member in ipairs(run.Members) do
			local root, humanoid = getAliveParts(member)
			if root and os.clock() - (lastHit[member] or 0) > 0.5 then
				local flat = Vector3.new(root.Position.X - origin.X, 0, root.Position.Z - origin.Z)
				local along = flat:Dot(dir)
				local lateral = (flat - dir * along).Magnitude
				local height = root.Position.Y - groundAt(run, root.Position.X, root.Position.Z, root.Position.Y)
				if along > 0 and along < length and lateral < 3.8 and height < 6 then
					lastHit[member] = os.clock()
					humanoid:TakeDamage(math.floor(data.Stats.ShotDamage * 0.9))
					Effects.Burst(root.Position, Color3.fromRGB(255, 200, 120), 15)
				end
			end
		end
		task.wait(0.03)
	end
	beam:Destroy()
end

-- 9) 양옆 부하 소환: 보스방 좌우 가장자리에서 빛기둥이 솟으며 쫄병이 몰려나와 중앙으로 달려든다 (체력 75 / 50 / 25% 에서도 자동 발동)
local function bossSideAdds(run, part, data, announce)
	if not bossAlive(run, part, data) then return end
	local center = run.ArenaCenter or run.BossPos or part.Position
	if announce then
		notifyAll(run, "⚠ " .. run.BossName .. "의 부하들이 양옆에서 몰려온다!")
	end
	local level = math.max(1, Config.Boss.MinionLevel + run.LevelBonus + 1)
	local spots = {}
	for _, side in ipairs({ -1, 1 }) do
		for i = 1, 3 do
			local x, z = center.X - 48 + i * 22, center.Z + side * (62 - i * 4)
			if walkable(run, x, z) then
				table.insert(spots, Vector3.new(x, 0, z))
			end
		end
	end
	for _, spot in ipairs(spots) do
		local ground = groundAt(run, spot.X, spot.Z, run.Origin.Y + 10)
		local column = Instance.new("Part")
		column.Anchored, column.CanCollide, column.CanQuery, column.CanTouch = true, false, false, false
		column.Material = Enum.Material.Neon
		column.Color = Color3.fromRGB(190, 90, 255)
		column.Transparency = 0.5
		column.Size = Vector3.new(5, 60, 5)
		column.Position = Vector3.new(spot.X, ground + 30, spot.Z)
		column.Parent = run.Folder
		TweenService:Create(column, TweenInfo.new(1.0), { Transparency = 1 }):Play()
		Debris:AddItem(column, 1.1)
	end
	task.wait(1.0)
	if not bossAlive(run, part, data) then return end
	for _, spot in ipairs(spots) do
		if run.MonsterCount >= 24 then break end
		local stats = Config.Monster.GetStats(level)
		local ground = groundAt(run, spot.X, spot.Z, run.Origin.Y + 10)
		spawnMonster(run, level, Vector3.new(spot.X, ground + stats.Size / 2, spot.Z))
		Effects.Burst(Vector3.new(spot.X, ground + 2, spot.Z), Color3.fromRGB(190, 90, 255), 20)
	end
end

local BOSS_PATTERNS = { Fan = bossFan, Ring = bossRing, Spiral = bossSpiral, Meteor = bossMeteor, Slam = bossSlam, Summon = bossSummon,
	Lanes = bossLanes, Sweep = bossSweep, SideAdds = function(run, part, data) bossSideAdds(run, part, data, true) end }

-- 던전 종류마다 패턴 비중이 다르다 (Config.Dungeon.Types[..].Boss.Weights).
-- 직전과 같은 패턴은 피하고, 광폭화하면 나선 / 메테오 비중이 커진다.
local function pickBossPattern(run, data)
	local weights = run.Type.Boss.Weights
	local entries, total = {}, 0
	for name, weight in pairs(weights) do
		weight *= run.BossVariant.Weights[name] or 1
		if name ~= data.LastPattern then
			if data.Enraged and (name == "Spiral" or name == "Meteor") then
				weight *= 1.7
			end
			table.insert(entries, { Name = name, Weight = weight })
			total += weight
		end
	end
	local roll = math.random() * total
	for _, entry in ipairs(entries) do
		roll -= entry.Weight
		if roll <= 0 then
			return entry.Name
		end
	end
	return entries[#entries].Name
end

local function enrageBoss(run, part, data)
	data.Enraged = true
	data.BaseColor = Color3.fromRGB(255, 60, 20)
	part.Color = data.BaseColor
	notifyAll(run, "⚠ " .. run.BossName .. "이(가) 분노했다!")
	for _ = 1, Config.Boss.MinionCount do
		local angle = math.random() * math.pi * 2
		local position = part.Position + Vector3.new(math.cos(angle) * 20, 0, math.sin(angle) * 20)
		local minionLevel = math.max(1, Config.Boss.MinionLevel + run.LevelBonus)
		local minionStats = Config.Monster.GetStats(minionLevel)
		spawnMonster(run, minionLevel, Vector3.new(position.X, groundAt(run, position.X, position.Z, position.Y) + minionStats.Size / 2, position.Z))
	end
end

local function damageMonster(run, player, part, data, amount, isCrit, hitPosition)
	if data.ExposedUntil and os.clock() < data.ExposedUntil then -- 약점 노출 중: 보스가 받는 피해 x3
		amount = math.floor(amount * 3)
		isCrit = true
	end
	data.Health -= amount
	if data.Invincible then data.Health = math.max(data.Health, data.MaxHealth * 0.5) end -- 연습 표적은 쓰러지지 않는다
	data.Awake = true -- 맞은 몬스터는 거리와 상관없이 깨어난다
	data.HealthFill.Size = UDim2.new(math.max(data.Health, 0) / data.MaxHealth, 0, 1, 0)
	Effects.DamageNumber(hitPosition, amount, isCrit)
	Effects.Hit(player, part, isCrit, data.Health <= 0)

	if data.Health > 0 then
		if data.IsBoss and not data.Enraged and data.Health / data.MaxHealth <= Config.Boss.EnrageRatio then
			enrageBoss(run, part, data)
		end
		-- 체력 75 / 50 / 25% 를 지날 때마다 양옆에서 부하가 몰려온다
		if data.IsBoss then
			local ratio = data.Health / data.MaxHealth
			local phases = { 0.75, 0.5, 0.25 }
			data.PhaseIndex = data.PhaseIndex or 0
			while data.PhaseIndex < #phases and ratio <= phases[data.PhaseIndex + 1] do
				data.PhaseIndex += 1
				task.spawn(bossSideAdds, run, part, data, true)
			end
		end
		return
	end

	run.Monsters[part] = nil
	run.MonsterCount -= 1
	Effects.Burst(part.Position, part.Color, data.IsBoss and 80 or 22)
	Effects.FloatText(part.Position + Vector3.new(0, part.Size.Y / 2 + 2, 0), string.format("+%d G", math.floor(data.Stats.Gold * run.GoldMult * Config.Economy.DungeonGoldMult + 0.5)), Color3.fromRGB(255, 220, 90))
	part:Destroy()
	Combo.Kill(player)
	if run.Score then -- 심연 도전 점수: 처치 + 현재 콤보 (최대 60) + 보스
		local R = Config.Rift
		run.Score[player] = (run.Score[player] or 0) + R.KillScore + math.min(player:GetAttribute("Combo") or 0, 60) + (data.IsBoss and R.BossScore or 0)
		player:SetAttribute("RiftScore", math.floor(run.Score[player]))
	end
	giveGold(run, data.Stats.Gold)
	giveXp(run, data.IsBoss and Config.Xp.DungeonBoss or Config.Xp.DungeonPerMonsterLevel * data.Level)
	Quest.Add(player, "Kills", 1)
	if data.IsBoss then
		run.BossDead = true
		run.Boss = nil
		run.BossPart = nil
		local tickets = run.Difficulty.Tickets
		for _, member in ipairs(run.Members) do
			member:SetAttribute("Tickets", (member:GetAttribute("Tickets") or 0) + tickets)
			run.TicketsEarned[member] = (run.TicketsEarned[member] or 0) + tickets
			Quest.Add(member, "BossKills", 1)
		end
	end
end

------------------------------------------------------------
-- 매 프레임: 몬스터 이동/공격, 투사체 이동/명중
------------------------------------------------------------
-- 하루 무료 입장 (MetaService 의 Rift 기록에 같이 저장): { DungeonDay, DungeonUsed }
local function freeState(player)
	local state = Meta.GetRift(player)
	if not state then return nil end
	local day = math.floor(os.time() / 86400)
	if state.DungeonDay ~= day then
		state.DungeonDay = day
		state.DungeonUsed = 0
	end
	return state
end
function Dungeon.FreeLeft(player)
	local state = freeState(player)
	if not state then return 0 end
	return math.max(0, Config.Keys.FreeDaily - (state.DungeonUsed or 0))
end
function Dungeon.UseFree(player)
	local state = freeState(player)
	if state then
		state.DungeonUsed = (state.DungeonUsed or 0) + 1
		player:SetAttribute("DungeonFree", Dungeon.FreeLeft(player))
	end
end
task.spawn(function() -- 접속 직후 / 날짜가 바뀔 때 화면 표시용 값을 맞춘다
	while true do
		for _, member in ipairs(Players:GetPlayers()) do
			local left = Dungeon.FreeLeft(member)
			if member:GetAttribute("DungeonFree") ~= left then
				member:SetAttribute("DungeonFree", left)
			end
		end
		task.wait(10)
	end
end)

local nearMissAt = {}
local dashSeenAt = {}
function Dungeon.AwardNearMiss(run, player, root)
	local now = os.clock()
	if now - (nearMissAt[player] or 0) < 0.7 then return end
	local streak = (now - (nearMissAt[player] or 0) < 6) and ((player:GetAttribute("NearMissStreak") or 0) + 1) or 1
	nearMissAt[player] = now
	player:SetAttribute("NearMissStreak", streak)
	player:SetAttribute("UltCharge", math.min(Config.Skills.Ult.Cost, (player:GetAttribute("UltCharge") or 0) + 10 + math.min(streak, 4) * 3))
	player:SetAttribute("NearMissUntil", now + 4)
	if run.Score then
		run.Score[player] = (run.Score[player] or 0) + Config.Rift.NearMissScore * math.min(streak, 5)
		player:SetAttribute("RiftScore", math.floor(run.Score[player]))
	end
	local rift = Meta.GetRift(player) -- 처음 한 번만 NEAR MISS 설명 카드를 띄운다 (저장됨)
	local firstTime = rift ~= nil and not rift.Tip
	if rift then rift.Tip = true end
	Effects.FloatText(root.Position + Vector3.new(0, 4, 0), streak > 1 and string.format("NEAR MISS! x%d", streak) or "NEAR MISS!", Color3.fromRGB(120, 255, 255))
	Remotes.Banner:FireClient(player, "NearMiss", { Streak = streak, First = firstTime })
end

local function stepRun(run, dt)
	local now = os.clock()

	-- 시체 청소: 몬스터 표에 없는데 남은 몬스터 부품을 2초마다 지운다
	if not run.NextOrphanCheck or now >= run.NextOrphanCheck then
		run.NextOrphanCheck = now + 2
		if run.MonstersFolder then
			for _, child in ipairs(run.MonstersFolder:GetChildren()) do
				if child:IsA("BasePart") and not run.Monsters[child] then
					child:Destroy()
				end
			end
		end
	end

	for part, data in pairs(run.Monsters) do
		if data.WeakPart and data.WeakPart.Parent then -- 약점 구슬: 보스 몸 주위를 돌며 위아래로 흔들린다
			local radius = part.Size.X / 2 + 7 -- 보스 몸(날개 / 뿔 장식 포함) 밖으로 충분히 떨어져 돈다
			local angle = now * 1.5
			data.WeakPart.Position = part.Position + Vector3.new(math.cos(angle) * radius, math.sin(now * 0.9) * radius * 0.35, math.sin(angle) * radius)
		end
		if data.Static then continue end -- 연습 표적: 가만히 서 있다
		if data.IsBoss then
			-- 보스: 천천히 다가오면서, 패턴을 하나 골라 끝까지 실행한 뒤 잠깐 쉬고 다음 패턴
			local target, distance = getNearestTarget(run, part.Position)
			if target then
				local keepDistance = data.Stats.Size + 12
				if distance > keepDistance then
					local flatTarget = Vector3.new(target.Position.X, part.Position.Y, target.Position.Z)
					local move = flatTarget - part.Position
					if move.Magnitude > 0.1 then
						local step = move.Unit * data.Stats.Speed * dt
						local nextPos = part.Position + step
						if walkable(run, nextPos.X, nextPos.Z) then
							part.Position += step
						end
					end
				end
				-- 보스도 땅 높이를 따라간다 (언덕 / 구덩이)
				local bossGround = groundAt(run, part.Position.X, part.Position.Z, part.Position.Y)
				local bossAt = Vector3.new(part.Position.X, bossGround + data.Stats.Size / 2, part.Position.Z)
				local faceAt = Vector3.new(target.Position.X, bossAt.Y, target.Position.Z)
				if (faceAt - bossAt).Magnitude > 1 then
					part.CFrame = CFrame.lookAt(bossAt, faceAt) -- 항상 플레이어를 바라본다 (날개 / 뿔 / 꼬리가 같이 돈다)
				else
					part.Position = bossAt
				end

				if not data.Casting and now >= data.NextPattern then
					data.Casting = true
					local name = pickBossPattern(run, data)
					data.LastPattern = name
					task.spawn(function()
						BOSS_PATTERNS[name](run, part, data)
						data.Casting = false
						data.NextPattern = os.clock() + (data.Enraged and 1.6 or 2.6)
					end)
				end
			end
		else
			-- 일반 몬스터: 종류(슬라임/독충/박쥐/마법사/골렘/멧돼지/폭탄병)마다 움직임과 공격이 다르다
			-- 방에 미리 배치된 몬스터는 플레이어가 가까이 올 때까지 가만히 있다 (한 번 깨어나면 계속 추격)
			if data.RoomIndex and not data.Awake then
				local _, nearDist = getNearestTarget(run, part.Position)
				if nearDist <= 100 then
					data.Awake = true
				end
			end
			if not data.RoomIndex or data.Awake then
				MonsterTypes.Update(run.Ctx, part, data, dt, now)
			end
		end
	end

	for i = #run.Projectiles, 1, -1 do
		local projectile = run.Projectiles[i]
		projectile.Part.Position += projectile.Direction * projectile.Speed * dt

		local hit = false
		-- 절벽에 닿은 탄은 사라진다 (벽 너머로 공격이 들어오지 않게)
		if not walkable(run, projectile.Part.Position.X, projectile.Part.Position.Z) then
			hit = true
		end
		for _, member in ipairs(run.Members) do
			if hit then break end
			local root, humanoid = getAliveParts(member)
			if root then
				local gap = (root.Position - projectile.Part.Position).Magnitude
				if gap < projectile.Radius + 2 then
					humanoid:TakeDamage(projectile.Damage)
					hit = true
					break
				elseif gap < projectile.Radius + 14 then -- 아슬아슬하게 스치며 대시: NEAR MISS (필드와 같은 보상 + 심연 도전 점수). 방금(0.6초 안) 대시했어도 인정
					local v = root.AssemblyLinearVelocity
					if Vector3.new(v.X, 0, v.Z).Magnitude > 50 then
						dashSeenAt[member] = os.clock()
					end
					if os.clock() - (dashSeenAt[member] or -10) < 0.6 then
						projectile.NearMissed = projectile.NearMissed or {}
						if not projectile.NearMissed[member] then
							projectile.NearMissed[member] = true
							Dungeon.AwardNearMiss(run, member, root)
						end
					end
				end
			end
		end

		if hit or now > projectile.Expire then
			projectile.Part:Destroy()
			table.remove(run.Projectiles, i)
		end
	end
end

RunService.Heartbeat:Connect(function(dt)
	for _, run in pairs(runs) do
		if run.Phase == "Wave" or run.Phase == "Boss" or run.Phase == "Drill" then -- 연습장(Drill)에서도 약점 구슬이 돌고 미사일이 날아가야 한다
			stepRun(run, dt)
		end
	end
end)

------------------------------------------------------------
-- 플레이어 공격 (판정은 서버에서). 반환: 탄이 끝나는 지점
------------------------------------------------------------
-- 공격 데미지 계산 (무기 강화 + 치명타 스탯/장갑). 던전 / 필드에서 같이 사용. 반환: 데미지, 치명타 여부
function Dungeon.ComputeDamage(player)
	local weaponType = Config.GetPlayerWeapon(player)
	local weaponLevel = player:GetAttribute("WeaponLevel") or 0
	local damage = P.BaseDamage * Config.GetDamageMultiplier(weaponLevel) * weaponType.DamageMult
		* Config.GetLevelDamageMult(player:GetAttribute("Level") or 1)
		* (1 + (player:GetAttribute("GearDamage") or 0) + (player:GetAttribute("TrainDamage") or 0) + (player:GetAttribute("PetDamage") or 0))
		* (1 + (player:GetAttribute("PerkPower") or 0) * Config.Perks.PowerPerStack)
		* Combo.GetDamageMult(player)
		* (1 + (player:GetAttribute("Prestige") or 0) * Config.Prestige.DamagePerRank)
		* Dungeon.PartyBonus(player)
	local chance = math.min(0.9, (player:GetAttribute("CritPoints") or 0) * P.CritPerPoint
		+ (player:GetAttribute("GearCrit") or 0) + (player:GetAttribute("TrainCrit") or 0) + (player:GetAttribute("PetCrit") or 0) + (weaponType.CritBonus or 0))
	local isCrit = os.clock() < (player:GetAttribute("NearMissUntil") or 0) or math.random() < chance -- NEAR MISS 보상: 4초간 전부 치명타
	if isCrit then
		damage *= P.CritMultiplier
	end
	return math.max(1, math.floor(damage + 0.5)), isCrit
end

-- 범위 피해: center 주변 radius 안의 모든 적에게 damage 를 준다 (스킬용). 맞은 위치 목록 반환
-- 범위 안의 몬스터(가까운 순) 목록 / 한 마리만 공격 (궁극기 락온 난사용)
function Dungeon.TargetsIn(player, center, radius, limit)
	local run = playerRun[player]
	if not run or run.Destroyed then return nil end
	local list = {}
	for part in pairs(run.Monsters) do
		if part.Parent and (part.Position - center).Magnitude <= radius + part.Size.X / 2 then
			table.insert(list, part)
		end
	end
	table.sort(list, function(a, b)
		local aBoss, bBoss = run.Monsters[a] and run.Monsters[a].IsBoss, run.Monsters[b] and run.Monsters[b].IsBoss
		if aBoss ~= bBoss then return aBoss == true end -- 보스는 대상이 제한돼도 항상 포함
		return (a.Position - center).Magnitude < (b.Position - center).Magnitude
	end)
	while #list > (limit or 12) do table.remove(list) end
	return list
end

function Dungeon.HitPart(player, part, damage)
	local run = playerRun[player]
	local data = run and run.Monsters[part]
	if not data or not part.Parent then return false end
	damageMonster(run, player, part, data, damage, false, part.Position)
	return true
end

function Dungeon.AreaDamage(player, center, radius, damage)
	local run = playerRun[player]
	if not run or run.Destroyed then return nil end
	local targets = {}
	for part, data in pairs(run.Monsters) do
		if part.Parent and (part.Position - center).Magnitude <= radius + part.Size.X / 2 then
			table.insert(targets, { Part = part, Data = data })
		end
	end
	local positions = {}
	for _, target in ipairs(targets) do
		if run.Monsters[target.Part] then
			table.insert(positions, target.Part.Position)
			damageMonster(run, player, target.Part, target.Data, damage, false, target.Part.Position)
		end
	end
	return positions
end

-- 파티 시너지: 가까이 있는 파티원 1명당 공격력 +4% (최대 3명)
function Dungeon.PartyBonus(player)
	local partyId = player:GetAttribute("PartyId") or 0
	if partyId == 0 then return 1 end
	local root = getAliveParts(player)
	if not root then return 1 end
	local count = 0
	for _, other in ipairs(game:GetService("Players"):GetPlayers()) do
		if other ~= player and other:GetAttribute("PartyId") == partyId and other:GetAttribute("Zone") == player:GetAttribute("Zone") then
			local otherRoot = getAliveParts(other)
			if otherRoot and (otherRoot.Position - root.Position).Magnitude <= 70 then
				count += 1
			end
		end
	end
	return 1 + math.min(3, count) * 0.04
end

-- 던전 특성 효과(관통 / 폭발 / 연쇄 / 흡혈)를 포함한 사격
function Dungeon.Shoot(player, origin, direction)
	local run = playerRun[player]
	if not run or run.Destroyed then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { run.MonstersFolder }

	local weaponType = Config.GetPlayerWeapon(player)
	local range = weaponType.Range
	local pierce = (player:GetAttribute("PerkPierce") or 0) + (weaponType.Pierce or 0) -- 레일건 등 무기 고유 관통
	local boom = player:GetAttribute("PerkBoom") or 0
	local chain = player:GetAttribute("PerkChain") or 0
	local vamp = player:GetAttribute("PerkVamp") or 0

	local endPosition = origin + direction * range
	do -- 사정거리 끝까지 가는 도중 절벽이 있으면 거기서 멈춘다
		local clear, stopAt = segmentClear(run, origin, endPosition)
		if not clear then
			endPosition = stopAt
			range = (stopAt - origin).Magnitude
		end
	end
	local skipped = {}
	for _ = 1, 1 + pierce do
		local result = workspace:Raycast(origin, direction * range, params)
		if not result then break end
		-- 약점 구슬을 직접 맞힌 경우: 보스를 맞힌 것으로 바꾸고 "약점 명중"으로 처리한다
		local weakDirect = false
		local orbPart
		if result.Instance.Name == "WeakPoint" and result.Instance.Parent and run.Monsters[result.Instance.Parent] then
			orbPart = result.Instance
			result = { Instance = result.Instance.Parent, Position = result.Position }
			weakDirect = true
		end
		endPosition = result.Position
		local part = result.Instance
		local data = run.Monsters[part]
		if not data then break end

		local damage, isCrit = Dungeon.ComputeDamage(player)
		local hitPosition = result.Position
		if data.WeakPart and data.WeakPart.Parent and not data.WeakHidden and player:GetAttribute("ShotManual") == true then -- 탄이 지나간 선이 약점 구슬에 닿으면 약점 노출 (직접 조준한 탄만)
			local ab = result.Position - origin
			local t = math.clamp((data.WeakPart.Position - origin):Dot(ab) / math.max(ab:Dot(ab), 0.001), 0, 1)
			if weakDirect or (origin + ab * t - data.WeakPart.Position).Magnitude <= data.WeakPart.Size.X * 0.8 then
				-- 이 공격만 세지는 게 아니라 약점이 노출되어 4초간 보스가 받는 모든 피해가 x3 (damageMonster 가 적용)
				player:SetAttribute("UltCharge", math.min(Config.Skills.Ult.Cost, (player:GetAttribute("UltCharge") or 0) + 6))
				player:SetAttribute("WeakHitTick", (player:GetAttribute("WeakHitTick") or 0) + 1)
				Effects.Burst(data.WeakPart.Position, Color3.fromRGB(255, 235, 80), 24)
				Effects.ExposeBoss(part, data, 4)
			end
		end
		damageMonster(run, player, part, data, damage, isCrit, hitPosition)
		player:SetAttribute("HitTick", (player:GetAttribute("HitTick") or 0) + 1) -- 궁극기 게이지는 실제로 맞혔을 때만 찬다

		if vamp > 0 then
			local _, humanoid = getAliveParts(player)
			if humanoid then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + vamp)
			end
		end

		-- 폭발: 맞은 지점 주변 적에게 피해 (폭발탄 특성 + 로켓 런처 / 플라즈마 캐논 고유 폭발)
		local splash = weaponType.Splash or 0
		if boom > 0 or splash > 0 then
			local radius = math.max(boom > 0 and (8 + boom * 4) or 0, splash)
			boom = math.max(boom, 1)
			Effects.Burst(hitPosition, Color3.fromRGB(255, 140, 50), 10 + boom * 8)
			for otherPart, otherData in pairs(run.Monsters) do
				if otherPart ~= part and otherPart.Parent and (otherPart.Position - hitPosition).Magnitude <= radius + otherPart.Size.X / 2 then
					damageMonster(run, player, otherPart, otherData, math.max(1, math.floor(damage * Config.Perks.BoomRatio)), false, otherPart.Position)
				end
			end
		end

		-- 연쇄 번개: 가장 가까운 다른 적들에게 튄다
		if chain > 0 then
			local candidates = {}
			for otherPart in pairs(run.Monsters) do
				if otherPart ~= part and otherPart.Parent then
					local dist = (otherPart.Position - hitPosition).Magnitude
					if dist <= 40 then
						table.insert(candidates, { Part = otherPart, Dist = dist })
					end
				end
			end
			table.sort(candidates, function(a, b) return a.Dist < b.Dist end)
			for k = 1, math.min(chain, #candidates) do
				local target = candidates[k].Part
				local targetData = run.Monsters[target]
				if targetData then
					Effects.Tracer(hitPosition, target.Position, Color3.fromRGB(120, 200, 255), 0.35)
					damageMonster(run, player, target, targetData, math.max(1, math.floor(damage * Config.Perks.ChainRatio)), false, target.Position)
				end
			end
		end

		-- 다음 관통 대상을 찾기 위해 이 몬스터를 잠깐 판정에서 뺀다 (몬스터가 죽어 사라졌으면 필요 없음)
		if part.Parent then
			part.CanQuery = false
			table.insert(skipped, part)
		end
		if orbPart and orbPart.Parent then -- 관통할 때 같은 구슬이 또 잡히지 않게
			orbPart.CanQuery = false
			table.insert(skipped, orbPart)
		end
	end
	for _, part in ipairs(skipped) do
		part.CanQuery = part.Name ~= "WeakPoint" or part.Transparency < 1 -- 노출 때문에 숨겨진 구슬은 계속 판정에서 뺀다
	end

	return endPosition
end

------------------------------------------------------------
-- 스탯 분배 (던전 안에서만 / 스탯 포인트가 있을 때)
------------------------------------------------------------
local function perkStacks(player, perkKey)
	return player:GetAttribute(Config.Perks[perkKey].Attr) or 0
end

local function perkMaxed(player, perkKey)
	local perk = Config.Perks[perkKey]
	local max = perk.Max
	if perk.Attr == "CritPoints" then
		max = math.min(max, P.MaxCritPoints)
	end
	return perkStacks(player, perkKey) >= max
end

local function applyPerk(player, perkKey)
	local perk = Config.Perks[perkKey]
	player:SetAttribute(perk.Attr, perkStacks(player, perkKey) + 1)
	if perk.Attr == "HealthPoints" then
		applyMaxHealth(player, P.HealthPerPoint)
	end
end

------------------------------------------------------------
-- 상태 전송 (클라이언트 HUD용)
------------------------------------------------------------
local function broadcast(run)
	local readyCount = 0
	for _, member in ipairs(run.Members) do
		if run.Ready[member] then
			readyCount += 1
		end
	end

	local state = {
		Phase = run.Phase,
		Wave = run.Wave,
		TotalWaves = run.TotalWaves,
		TypeName = run.Type.Name,
		DifficultyName = run.Difficulty.Name,
		MonstersLeft = run.MonsterCount,
		TimeLeft = run.PhaseEnd and math.max(0, math.ceil(run.PhaseEnd - os.clock())) or 0,
		ReadyCount = readyCount,
		MemberCount = #run.Members,
		StageText = run.StageText,
		SurviveLeft = run.SurviveEnd and math.max(0, math.ceil(run.SurviveEnd - os.clock())) or nil,
		BonusLeft = run.NextBonusAt and math.max(0, math.ceil(run.NextBonusAt - os.clock())) or nil,
		BonusSpan = run.BonusSpan,
		MonsterLimit = run.MonsterLimit,
		OverrunLeft = run.OverrunLeft and math.ceil(run.OverrunLeft) or nil,
		MutatorText = run.Mutator and string.format("%s %s — %s", run.Mutator.Icon, run.Mutator.Name, run.Mutator.Desc) or nil,
		BossName = run.Boss and run.BossName or nil,
		BossRatio = run.Boss and math.max(run.Boss.Health, 0) / run.Boss.MaxHealth or nil,
	}
	for _, member in ipairs(run.Members) do
		if run.RiftMode and run.Phase ~= "Ended" then
			member:SetAttribute("RiftScore", math.floor(run.Score[member] or 0))
			member:SetAttribute("RiftLeft", run.RiftEndAt and math.max(0, math.ceil(run.RiftEndAt - os.clock())) or Config.Rift.Duration)
		end
		Remotes.Dungeon:FireClient(member, "State", state)
	end
end

------------------------------------------------------------
-- 종료 / 정리
------------------------------------------------------------
local function returnToLobby(player)
	playerRun[player] = nil
	player:SetAttribute("RiftLeft", 0)
	player:SetAttribute("RiftScore", 0)
	player:SetAttribute("Zone", "Lobby")
	resetStats(player)
	pivotTo(player, lobbySpawn)
end

local function destroyRun(run)
	if run.Destroyed then return end
	run.Destroyed = true
	runs[run.Id] = nil
	usedSlots[run.Slot] = nil
	for _, member in ipairs(table.clone(run.Members)) do
		returnToLobby(member)
	end
	run.Members = {}
	run.Folder:Destroy()
	DungeonTerrain.Clear(run, D)
end

local function finish(run, victory)
	if run.Phase == "Ended" then return end
	run.Phase = "Ended"
	run.PhaseEnd = nil

	for part in pairs(run.Monsters) do
		part:Destroy()
	end
	run.Monsters = {}
	run.MonsterCount = 0
	for _, projectile in ipairs(run.Projectiles) do
		projectile.Part:Destroy()
	end
	run.Projectiles = {}

	if victory then
		giveGold(run, D.VictoryGold)
		giveXp(run, Config.Xp.DungeonClear)
		for _, member in ipairs(run.Members) do
			Quest.Add(member, "DungeonClears", 1)
			local lines = run.LootLines[member] or {}
			for _, line in ipairs(Loot.DungeonChest(member, run.TypeKey, run.DiffKey)) do -- 보스 상자: 장비 아이템
				table.insert(lines, line)
			end
			run.LootLines[member] = lines
		end
	end
	for _, member in ipairs(run.Members) do
		if not victory then
			task.delay(2, function() Advice.AfterDefeat(member) end) -- 던전에서 졌을 때: 지금 부족한 것 / 안 쓴 것 조언
		end
		Remotes.Dungeon:FireClient(member, "Result", {
			Victory = victory,
			Gold = run.Earned[member] or 0,
			Tickets = run.TicketsEarned[member] or 0,
			Loot = run.LootLines[member] or {},
			Wave = run.Wave,
			TotalWaves = run.TotalWaves, Endless = run.Type.Endless == true,
			TypeName = run.Type.Name,
			DifficultyName = run.Difficulty.Name,
			ReturnDelay = D.ReturnDelay,
		})
	end
	broadcast(run)

	task.delay(D.ReturnDelay, function()
		local members = table.clone(run.Members)
		destroyRun(run)
		if not run.RiftMode then
			for _, member in ipairs(members) do -- 처음 던전을 마치고 돌아오면 한 번: 다음 목표 + 강해지는 방법
				task.delay(3, function() if member.Parent then Advice.GrowthGuide(member) end end)
			end
		end
	end)
end

-- 심연 도전 종료: 점수로 등급을 매기고 (RiftService 가 보상 / 기록) 결과 카드를 보낸다. 시간이 끝나거나 전멸하면 호출된다.
Dungeon.OnRiftFinished = nil -- RiftService 가 채운다: function(player, score) -> { Gold, Tickets, TimeSkip, Tier, Best, NewBest }
local function riftFinish(run)
	if run.Phase == "Ended" then return end
	run.Phase = "Ended"
	run.PhaseEnd = nil
	for part in pairs(run.Monsters) do
		part:Destroy()
	end
	run.Monsters = {}
	run.MonsterCount = 0
	for _, projectile in ipairs(run.Projectiles) do
		projectile.Part:Destroy()
	end
	run.Projectiles = {}
	for _, member in ipairs(run.Members) do
		local score = math.floor(run.Score[member] or 0)
		local info = Dungeon.OnRiftFinished and Dungeon.OnRiftFinished(member, score) or {}
		member:SetAttribute("RiftLeft", 0)
		Remotes.Dungeon:FireClient(member, "Result", {
			Victory = true, Gold = info.Gold or 0, Tickets = info.Tickets or 0, Loot = {}, Wave = run.Wave, TotalWaves = 0,
			TypeName = run.Type.Name, DifficultyName = "", ReturnDelay = D.ReturnDelay,
			Rift = { Score = score, Tier = info.Tier, TierIcon = info.TierIcon, Best = info.Best, NewBest = info.NewBest, TimeSkip = info.TimeSkip or 0, Depth = info.Depth, UnlockedNext = info.UnlockedNext },
		})
	end
	broadcast(run)
	task.delay(D.ReturnDelay, function()
		destroyRun(run)
	end)
end

function Dungeon.Leave(player)
	local run = playerRun[player]
	if not run then return end

	local index = table.find(run.Members, player)
	if index then
		table.remove(run.Members, index)
	end
	run.Ready[player] = nil
	returnToLobby(player)

	if #run.Members == 0 then
		destroyRun(run)
	end
end

------------------------------------------------------------
-- 진행 루프
------------------------------------------------------------
-- predicate 가 true 가 될 때까지 대기. 던전이 끝났거나(false) 전멸하면 중단한다.
local function waitFor(run, predicate)
	while not run.Destroyed and run.Phase ~= "Ended" do
		if predicate() then
			return true
		end
		if (run.Phase == "Wave" or run.Phase == "Boss") and allDown(run) then
			if run.RiftMode then
				riftFinish(run) -- 쓰러져도 그때까지 쌓은 점수로 정산
			else
				finish(run, false)
			end
			return false
		end
		task.wait(0.25)
	end
	return false
end

local function spawnWave(run, wave)
	local count = math.min(36, math.floor(D.GetMonsterCount(wave, run.PartySize) * (run.Mutator and run.Mutator.CountMult or 1) * (run.PenCount or 1)))
	local level = math.max(1, D.GetWaveMonsterLevel(wave) + run.LevelBonus)
	-- 한 마리씩 야금야금 나오면 맛이 떨어진다: 세 번에 나눠 "우르르" 한꺼번에 쏟아낸다 (그룹 사이 0.7초)
	local groups = count >= 6 and 3 or 1
	local perGroup = math.ceil(count / groups)
	local spawned = 0
	for group = 1, groups do
		for _ = 1, perGroup do
			if spawned >= count then break end
			if run.Destroyed or run.Phase == "Ended" then return end
			spawnMonster(run, level)
			spawned += 1
		end
		if group < groups then
			task.wait(0.7)
		end
	end
end

-- 랜덤 보너스: 고르지 않고 무작위로 "강화" 하나가 모두에게 걸리고, 가끔 "패널티"(적이 강해지는 대신 골드 증가)가 같이 터진다.
local function pickWeighted(list, allowed)
	local total = 0
	for _, entry in ipairs(list) do
		if not allowed or allowed(entry) then total += entry.Weight or 1 end
	end
	if total <= 0 then return nil end
	local roll = math.random() * total
	for _, entry in ipairs(list) do
		if not allowed or allowed(entry) then
			roll -= entry.Weight or 1
			if roll <= 0 then return entry end
		end
	end
end

local function applyBuff(run, member, buff)
	if buff.Perk then
		for _ = 1, buff.Stacks or 1 do
			if not perkMaxed(member, buff.Perk) then applyPerk(member, buff.Perk) end
		end
	elseif buff.Combo then
		for _, key in ipairs(buff.Combo) do
			if not perkMaxed(member, key) then applyPerk(member, key) end
		end
	elseif buff.Effect == "Heal" then
		applyMaxHealth(member, math.huge)
	elseif buff.Effect == "Shield" then
		if member.Character then
			local shield = Instance.new("ForceField")
			shield.Parent = member.Character
			game:GetService("Debris"):AddItem(shield, 10)
		end
	elseif buff.Effect == "Ult" then
		member:SetAttribute("UltCharge", Config.Skills.Ult.Cost)
	elseif buff.Effect == "Gold" then
		run.GoldMult *= 1.2
	elseif buff.Effect == "Xp" then
		Level.AddXP(member, math.floor(Config.Xp.WaveClear * math.max(1, run.Wave or 1) * 2 * run.GoldMult + 0.5))
	elseif buff.Effect == "Ticket" then
		member:SetAttribute("Tickets", (member:GetAttribute("Tickets") or 0) + 1)
		run.TicketsEarned[member] = (run.TicketsEarned[member] or 0) + 1
	end
end

local function applyPenalty(run, pen)
	run.PenHealth = math.min(3, (run.PenHealth or 1) * (pen.HealthMult or 1))
	run.PenDamage = math.min(2.5, (run.PenDamage or 1) * (pen.DamageMult or 1))
	run.PenSpeed = math.min(1.5, (run.PenSpeed or 1) * (pen.SpeedMult or 1))
	run.PenCount = math.min(2, (run.PenCount or 1) * (pen.CountMult or 1))
	run.PenInterval = math.max(0.6, (run.PenInterval or 1) * (pen.IntervalMult or 1))
	run.GoldMult *= 1 + (pen.Gold or 0)
end

local function rollBonus(run, penaltyChance)
	local pen = math.random() < penaltyChance and pickWeighted(Config.RunPenalties) or nil
	if pen then applyPenalty(run, pen) end
	for _, member in ipairs(run.Members) do
		local buff = pickWeighted(Config.RunBuffs, function(entry)
			if entry.Perk then return not perkMaxed(member, entry.Perk) end
			return true
		end)
		if buff then applyBuff(run, member, buff) end
		local root = getAliveParts(member)
		if root and buff then
			local color = buff.Special and Color3.fromRGB(255, 190, 60) or Color3.fromRGB(120, 220, 255)
			Effects.Burst(root.Position, color, buff.Special and 90 or 55)
			Effects.FloatText(root.Position + Vector3.new(0, 7, 0), string.format("%s %s!", buff.Icon, buff.Name), color)
		end
		Remotes.Dungeon:FireClient(member, "Roll", {
			Buff = buff and { Icon = buff.Icon, Name = buff.Name, Desc = buff.Desc, Special = buff.Special == true } or nil,
			Penalty = pen and { Icon = pen.Icon, Name = pen.Name, Desc = pen.Desc, Gold = math.floor((pen.Gold or 0) * 100) } or nil,
		})
	end
end

-- 웨이브 클리어 후(탑 / 이벤트방): 잠깐 숨 돌리는 사이 랜덤 보너스가 터진다 (선택은 없다)
local function statPhase(run)
	run.Phase = "StatPhase"
	run.PhaseEnd = os.clock() + 2.5
	run.Ready = {}
	for _, member in ipairs(run.Members) do
		applyMaxHealth(member, math.huge)
	end
	rollBonus(run, 0.5)
	return waitFor(run, function() return os.clock() >= run.PhaseEnd end)
end

-- 무한의 탑: 쓰러질 때까지 웨이브가 계속된다. 클리어한 층이 기록되고, 5층마다 티켓.
local function towerLoop(run)
	local wave = 0
	while not run.Destroyed and run.Phase ~= "Ended" do
		wave += 1
		run.Wave = wave
		run.Phase = "Wave"
		run.PhaseEnd = nil
		spawnWave(run, wave)
		if not waitFor(run, function() return run.MonsterCount <= 0 end) then return end

		giveGold(run, D.WaveClearGold * wave)
		giveXp(run, Config.Xp.WaveClear * wave)
		for _, member in ipairs(run.Members) do
			Meta.RecordTower(member, wave)
			if wave % 5 == 0 then
				member:SetAttribute("Tickets", (member:GetAttribute("Tickets") or 0) + 1)
				run.TicketsEarned[member] = (run.TicketsEarned[member] or 0) + 1
			end
		end
		notifyAll(run, wave % 5 == 0 and string.format("🏯 %d층 돌파! 티켓 +1", wave) or string.format("🏯 %d층 돌파!", wave))
		if not statPhase(run) then return end
	end
end

-- 가장 가까운 살아 있는 플레이어 주변의 몬스터 등장 지점들 (minD ~ maxD 거리). 웨이브 없이 계속 쏟아내는 용도.
local function nearSpawnPoints(run, minD, maxD)
	local sum, n = Vector3.zero, 0
	for _, member in ipairs(run.Members) do
		local root = getAliveParts(member)
		if root then sum += root.Position n += 1 end
	end
	if n == 0 or not run.AllSpawns then return nil end
	local center = sum / n
	local list, all = {}, {}
	for _, point in ipairs(run.AllSpawns) do
		local d = Vector3.new(point.X - center.X, 0, point.Z - center.Z).Magnitude
		table.insert(all, { Point = point, D = d })
		if d >= minD and d <= maxD then table.insert(list, point) end
	end
	if #list < 3 then
		table.sort(all, function(a, b) return a.D < b.D end)
		list = {}
		for _, entry in ipairs(all) do
			if entry.D >= 10 and #list < 6 then table.insert(list, entry.Point) end
		end
	end
	return list
end

-- 버티기 진행: 웨이브 없이 정해진 시간 동안 몬스터가 계속 몰려오고(점점 빨라진다), 중간중간 랜덤 강화 / 패널티가 터진다.
-- 끝까지 버티면 보스가 나타난다. (심연 도전과 비슷하지만 점수제가 아니라 보스 / 보상이 있는 일반 던전)
local function surviveLoop(run)
	run.PhaseEnd = os.clock() + D.StartCountdown
	notifyAll(run, "🛡 몰려오는 몬스터를 처치하세요! 너무 많이 쌓이면 압도당해 실패, 끝까지 버티면 보스가 나타나요")
	if not waitFor(run, function() return os.clock() >= run.PhaseEnd end) then return end
	run.PhaseEnd = nil

	local waves = math.max(1, run.Type.Waves or 5)
	local duration = D.GetSurviveSeconds(waves)
	local startedAt = os.clock()
	run.SurviveEnd = startedAt + duration
	run.Phase = "Wave"
	run.TotalWaves = 0
	run.Wave = 1
	local nextSpawn = startedAt
	local nextBonus = startedAt + 8 -- 첫 보너스는 일찍: 시작하자마자 "뭔가 터진다"
	run.NextBonusAt, run.BonusSpan = nextBonus, 8
	local bonusCount = 0
	local partyScale = 1 + 0.5 * (run.PartySize - 1)
	-- 몬스터가 한도를 넘어 쌓이면 졌다: 가만히 버티기만 해서는 클리어할 수 없다 (한도를 넘긴 채 OverrunSeconds 가 지나면 실패)
	local limit = math.floor(D.MonsterLimit * partyScale)
	run.MonsterLimit = limit

	while not run.Destroyed and run.Phase ~= "Ended" do
		if allDown(run) then
			finish(run, false)
			return
		end
		local now = os.clock()
		if now >= run.SurviveEnd then break end
		local progress = (now - startedAt) / duration
		run.Wave = 1 + math.floor(progress * waves)

		-- 한도 초과 감시
		if run.MonsterCount > limit then
			run.OverrunSince = run.OverrunSince or now
			run.OverrunLeft = math.max(0, D.OverrunSeconds - (now - run.OverrunSince))
			if run.OverrunLeft <= 0 then
				notifyAll(run, "💀 몬스터가 너무 많아졌어요! 압도당했습니다")
				finish(run, false)
				return
			end
		else
			run.OverrunSince, run.OverrunLeft = nil, nil
		end

		if now >= nextSpawn then
			local cap = math.floor(limit * 1.3) -- 성능 보호용 상한 (한도를 넘겨 쌓이긴 하지만 무한정은 아니다)
			if run.MonsterCount < cap then
				run.SpawnPoints = nearSpawnPoints(run, 22, 75) or run.AllSpawns
				local level = math.max(1, D.GetWaveMonsterLevel(run.Wave) + run.LevelBonus)
				local burst = (now - startedAt < 1) and 7 or math.random(3, 4) -- 시작하자마자 우르르
				for _ = 1, burst do
					spawnMonster(run, level)
				end
			end
			nextSpawn = now + (2.0 - 0.7 * progress) / (run.PenCount or 1)
		end

		if now >= nextBonus then
			bonusCount += 1
			nextBonus = now + D.BonusInterval
			run.NextBonusAt, run.BonusSpan = nextBonus, D.BonusInterval
			giveGold(run, D.WaveClearGold * bonusCount)
			giveXp(run, Config.Xp.WaveClear * bonusCount)
			for _, member in ipairs(run.Members) do
				Quest.Add(member, "DungeonWaves", 1)
			end
			rollBonus(run, bonusCount >= 2 and 0.6 or 0.3)
		end
		task.wait(0.25)
	end
	if run.Destroyed or run.Phase == "Ended" then return end

	-- 보스: 플레이어 가까이에서 등장
	run.SurviveEnd = nil
	run.NextBonusAt, run.MonsterLimit, run.OverrunSince, run.OverrunLeft = nil, nil, nil, nil
	run.Phase = "Boss"
	run.StageText = nil
	local spots = nearSpawnPoints(run, 35, 90)
	if spots and #spots > 0 then run.BossPos = spots[math.random(#spots)] end
	notifyAll(run, "⚠ " .. run.BossName .. "이(가) 나타났다! 공격을 피하며 쓰러뜨리세요!")
	spawnBoss(run)
	if not waitFor(run, function() return run.BossDead == true end) then return end
	finish(run, true)
end

-- 심연 도전: 시간제한 안에 웨이브를 이어서 상대한다 (특성 선택 없음). 점수는 처치 / 콤보 / NEAR MISS / 웨이브 보너스.
local function riftLoop(run)
	run.PhaseEnd = os.clock() + D.StartCountdown
	notifyAll(run, string.format("🌀 심연 도전! %d초 동안 최대한 많이 처치하고 아슬아슬하게 피해서 점수를 쌓으세요!", Config.Rift.Duration))
	if not waitFor(run, function() return os.clock() >= run.PhaseEnd end) then return end
	run.PhaseEnd = nil
	run.RiftEndAt = os.clock() + Config.Rift.Duration
	local wave = 0
	while not run.Destroyed and run.Phase ~= "Ended" do
		wave += 1
		run.Wave = wave
		run.Phase = "Wave"
		run.Spawning = true
		task.spawn(function()
			spawnWave(run, wave)
			run.Spawning = false
		end)
		local ok = waitFor(run, function() return (run.MonsterCount <= 0 and not run.Spawning) or os.clock() >= run.RiftEndAt end)
		if not ok then return end
		if os.clock() >= run.RiftEndAt then break end
		for _, member in ipairs(run.Members) do
			run.Score[member] = (run.Score[member] or 0) + Config.Rift.WaveBonus * wave
			member:SetAttribute("RiftScore", math.floor(run.Score[member]))
		end
		notifyAll(run, string.format("✅ 웨이브 %d 클리어! 보너스 +%d", wave, Config.Rift.WaveBonus * wave))
	end
	riftFinish(run)
end

local function runLoop(run)
	run.Phase = "Starting"
	if run.LayoutName then
		notifyAll(run, "🗺 이번 던전 지형: " .. run.LayoutName .. " (들어갈 때마다 달라져요)")
	end
	notifyAll(run, string.format("👹 이번 보스: %s — %s", run.BossName, run.BossVariant.Desc))
	if run.Mutator then
		notifyAll(run, string.format("%s 이번 던전 변이: %s — %s", run.Mutator.Icon, run.Mutator.Name, run.Mutator.Desc))
	end
	if run.RiftMode then
		riftLoop(run)
		return
	end
	if run.Type.Endless then
		run.PhaseEnd = os.clock() + D.StartCountdown
		if not waitFor(run, function() return os.clock() >= run.PhaseEnd end) then return end
		towerLoop(run)
		return
	end
	surviveLoop(run)
end

------------------------------------------------------------
-- 입장 (던전 게이트에서 호출). 파티가 있으면 파티장만 가능, 없으면 혼자 입장.
------------------------------------------------------------
function Dungeon.Start(player, typeKey, diffKey, riftMode, riftDepth)
	if player:GetAttribute("Zone") ~= "Lobby" then return end
	if player:GetAttribute("TutorialDungeonLocked") then
		notify(player, "🔒 아직 던전에 들어갈 수 없어요. 튜토리얼 미션을 먼저 진행해주세요!")
		return
	end

	typeKey = typeKey or "Cave"
	diffKey = diffKey or "Normal"
	local dungeonType = D.Types[typeKey]
	local difficulty = D.Difficulties[diffKey]
	if not dungeonType or not dungeonType.Waves or not difficulty or not difficulty.HealthMult then return end -- "Order" 같은 잘못된 키 방어

	local party = nil
	if not riftMode then
		party = Party.GetParty(player) -- 심연 도전은 혼자 한다
	end
	if party and party.Leader ~= player then
		notify(player, "파티장만 던전에 입장시킬 수 있어요.")
		return
	end

	local members = {}
	for _, candidate in ipairs(party and party.Members or { player }) do
		if candidate:GetAttribute("Zone") == "Lobby" and getAliveParts(candidate) then
			table.insert(members, candidate)
		end
	end
	if not table.find(members, player) then return end

	-- 던전 입장 제한: 열쇠 (파티원 모두 필요). 시간이 지나면 자동으로 차오른다.
	local keyCost = riftMode and 0 or (difficulty.KeyCost or 1) -- 심연 도전은 열쇠 대신 하루 도전 횟수를 쓴다 (RiftService 가 관리)
	local useFree = {}
	for _, member in ipairs(members) do
		if keyCost > 0 and Dungeon.FreeLeft(member) > 0 then
			useFree[member] = true -- 오늘의 무료 입장 사용 (열쇠 소모 없음)
		elseif not Keys.HasTier(member, difficulty.KeyTier or 1, keyCost) then
			notify(player, string.format("%s 님은 오늘의 무료 입장을 다 썼고 %s(이상)도 없어요. 필드 구역 군주를 잡으면 열쇠가 나와요 (뒤 구역일수록 높은 단계)", member.DisplayName, Config.Keys.TierNames[difficulty.KeyTier or 1]))
			if member ~= player then
				notify(member, "무료 입장 / 열쇠가 부족해서 파티가 입장하지 못했어요.")
			end
			return
		end
	end

	local slot
	for i = 0, D.MaxArenas - 1 do
		if not usedSlots[i] then
			slot = i
			break
		end
	end
	if not slot then
		notify(player, "지금은 던전이 가득 찼어요. 잠시 후 다시 시도해주세요.")
		return
	end
	usedSlots[slot] = true
	for _, member in ipairs(members) do
		if useFree[member] then
			Dungeon.UseFree(member)
			notify(member, string.format("🎟 오늘의 무료 입장 사용! (남은 횟수 %d / %d)", Dungeon.FreeLeft(member), Config.Keys.FreeDaily))
		else
			Keys.SpendTier(member, difficulty.KeyTier or 1, keyCost)
		end
	end

	local run = {
		Id = nextRunId,
		Slot = slot,
		Origin = D.ArenaOrigin + Vector3.new(0, 0, slot * D.ArenaSpacing),
		Members = members,
		PartySize = #members,
		Phase = "Starting",
		Wave = 0,
		PhaseEnd = nil,
		Monsters = {},      -- [Part] = 몬스터 데이터
		MonsterCount = 0,
		Projectiles = {},
		Ready = {},
		Earned = {},        -- [player] = 이번 판에서 번 골드
		TicketsEarned = {}, -- [player] = 이번 판에서 얻은 장비 뽑기 티켓
		BossDead = false,
		Destroyed = false,
		RiftMode = riftMode == true,
		Score = riftMode == true and {} or nil,
		Type = dungeonType,
		TypeKey = typeKey,
		DiffKey = diffKey,
		LootLines = {},
		Difficulty = difficulty,
		TotalWaves = dungeonType.Waves,
		BossVariant = D.BossVariants[D.BossVariants.Order[math.random(#D.BossVariants.Order)]],
		BossName = dungeonType.Boss.Name,
		GoldMult = dungeonType.GoldMult * difficulty.GoldMult,
		LevelBonus = dungeonType.LevelOffset + difficulty.LevelOffset,
		DepthScale = riftMode == true and Config.GetRiftDepth(riftDepth or 1) or nil, -- 심연 깊이별 난이도
	}
	if run.DepthScale then run.LevelBonus += run.DepthScale.LevelBonus end
	run.BossName = run.BossVariant.Prefix .. " " .. run.BossName -- 보스 변종 (매번 다름)
	-- 던전 변이: 확률로 한 가지가 붙는다 (위험 + 보상)
	if math.random() < D.MutatorChance then
		local key = D.Mutators.Order[math.random(#D.Mutators.Order)]
		run.Mutator = D.Mutators[key]
		run.GoldMult *= run.Mutator.GoldMult or 1
	end
	nextRunId += 1
	runs[run.Id] = run

	-- 몬스터 AI(MonsterTypes)가 던전 환경을 다루는 데 쓰는 함수들
	run.Ctx = {
		FloorY = run.Origin.Y,
		GroundY = function(x, z, fromY)
			return run.GroundY and run.GroundY(x, z, fromY) or nil
		end,
		Walkable = function(x, z)
			return walkable(run, x, z)
		end,
		LineOfSight = function(a, b)
			return (segmentClear(run, a, b))
		end,
		NextStep = function(data, from, to)
			return nextStep(run, data, from, to)
		end,
		GetTarget = function(position)
			return getNearestTarget(run, position)
		end,
		Fire = function(origin, direction, speed, damage, size, color, style)
			fireProjectile(run, origin, direction, speed, damage, size, color, style)
		end,
		Players = function()
			local list = {}
			for _, member in ipairs(run.Members) do
				local root, humanoid = getAliveParts(member)
				if root then
					table.insert(list, { Root = root, Humanoid = humanoid })
				end
			end
			return list
		end,
		Alive = function(part, data)
			return run.Monsters[part] == data and run.Phase ~= "Ended"
		end,
		Kill = function(part, data)
			if run.Monsters[part] == data then
				run.Monsters[part] = nil
				run.MonsterCount -= 1
				part:Destroy()
			end
		end,
	}
	buildArena(run)

	for _, member in ipairs(members) do
		playerRun[member] = run
		member:SetAttribute("Zone", "Dungeon")
		resetStats(member)
		pivotTo(member, arenaSpawnCFrame(run))
	end

	task.spawn(function()
		while not run.Destroyed do
			broadcast(run)
			task.wait(0.5)
		end
	end)
	task.spawn(runLoop, run)
end

------------------------------------------------------------
-- 외부 이벤트
------------------------------------------------------------
function Dungeon.GetRun(player)
	return playerRun[player]
end

function Dungeon.Init(lobbySpawnCFrame)
	lobbySpawn = lobbySpawnCFrame
end

-- 던전 안에서 죽었다가 리스폰되면 아레나 중앙으로 다시 보낸다
function Dungeon.OnCharacterAdded(player, character)
	local run = playerRun[player]
	if run and not run.Destroyed then
		character:WaitForChild("HumanoidRootPart", 5)
		character:PivotTo(arenaSpawnCFrame(run))
	end
end

function Dungeon.OnPlayerRemoving(player)
	local run = playerRun[player]
	if not run then return end
	local index = table.find(run.Members, player)
	if index then
		table.remove(run.Members, index)
	end
	run.Ready[player] = nil
	playerRun[player] = nil
	if #run.Members == 0 then
		destroyRun(run)
	end
end

-- 던전 게이트: 파티장(또는 솔로)에게 던전 종류 / 난이도 선택창을 띄운다
-- 로비의 던전 게이트(Config.Dungeon.List[index])에서 입장: 레벨 확인 후 바로 시작한다
function Dungeon.StartGate(player, index)
	if player:GetAttribute("Zone") ~= "Lobby" then return end
	if player:GetAttribute("TutorialDungeonLocked") then
		notify(player, "🔒 아직 던전에 들어갈 수 없어요. 튜토리얼 미션을 먼저 진행해주세요!")
		return
	end
	local entry = typeof(index) == "number" and D.List[index]
	if not entry then return end
	local party = Party.GetParty(player)
	if party and party.Leader ~= player then
		notify(player, "파티장만 던전에 입장시킬 수 있어요.")
		return
	end
	local who = party and party.Members or { player }
	for _, member in ipairs(who) do
		if (member:GetAttribute("Level") or 1) < entry.MinLevel then
			notify(player, string.format("%s 님은 레벨이 부족해요. (이 던전은 Lv.%d 이상)", member.DisplayName, entry.MinLevel))
			return
		end
	end
	Dungeon.Start(player, entry.Type, entry.Diff)
end

function Dungeon.OpenSelect(player)
	if player:GetAttribute("Zone") ~= "Lobby" then return end
	local party = Party.GetParty(player)
	if party and party.Leader ~= player then
		notify(player, "파티장만 던전에 입장시킬 수 있어요.")
		return
	end
	Remotes.Dungeon:FireClient(player, "OpenSelect")
end

Remotes.Dungeon.OnServerEvent:Connect(function(player, action, typeKey, diffKey)
	if action == "Start" then
		if typeof(typeKey) == "string" and typeof(diffKey) == "string" and typeKey ~= "Rift" then -- 심연 도전은 RiftService 만 시작할 수 있다
			Dungeon.Start(player, typeKey, diffKey)
		end
	elseif action == "Leave" then
		Dungeon.Leave(player)
	end
end)

return Dungeon
