-- DungeonService (ServerScriptService > Modules 안의 ModuleScript, 이름: DungeonService)
-- 던전 진행 전체를 담당한다.
--   입장 -> 카운트다운 -> [웨이브 -> 클리어 -> 30초 스탯 분배] x TotalWaves -> 보스 -> 승리/패배 -> 로비 복귀
-- 던전 한 판(run)마다 로비에서 멀리 떨어진 곳에 아레나를 따로 만들기 때문에 여러 파티가 동시에 플레이할 수 있다.
-- 스탯 포인트(치명타/공격속도/최대체력)는 그 판에서만 유효하고, 던전을 나가면 초기화된다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Party = require(script.Parent:WaitForChild("PartyService"))
local Quest = require(script.Parent:WaitForChild("QuestService"))
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
	amount = math.floor(amount * run.GoldMult * (Config.IsGoldenTime() and Config.Golden.GoldMult or 1) + 0.5)
	for _, member in ipairs(run.Members) do
		member:SetAttribute("Gold", (member:GetAttribute("Gold") or 0) + amount)
		run.Earned[member] = (run.Earned[member] or 0) + amount
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
	local terrain = DungeonTerrain.Build(run, run.Type, D, folder)
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

	local color = def.Color:Lerp(run.Type.MonsterColor, 0.25)
	local part = MonsterTypes.Build(typeKey, stats.Size, color, position or ringPosition(run, stats.Size), run.MonstersFolder)

	return registerMonster(run, part, stats, string.format("Lv.%d %s", level, def.Name), 140, {
		TypeKey = typeKey,
		Def = def,
		Level = level,
		Phase = math.random() * math.pi * 2,
		NextAttack = os.clock() + stats.ShotInterval,
	})
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
	CollectionService:AddTag(part, "Monster")
	CollectionService:AddTag(part, "RadarBoss")

	local data = registerMonster(run, part, stats, run.BossName, 320, {
		IsBoss = true,
		Enraged = false,
		NextPattern = os.clock() + 3,
		Casting = false,
		LastPattern = nil,
	})
	run.Boss = data
	run.BossPart = part
end

local function fireProjectile(run, origin, direction, speed, damage, size, color)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(size, size, size)
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.Material = Enum.Material.Neon
	ball.Color = color or Color3.fromRGB(255, 120, 30)
	ball.Position = origin
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

local BOSS_PATTERNS = { Fan = bossFan, Ring = bossRing, Spiral = bossSpiral, Meteor = bossMeteor, Slam = bossSlam, Summon = bossSummon }

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
	data.Health -= amount
	data.Awake = true -- 맞은 몬스터는 거리와 상관없이 깨어난다
	data.HealthFill.Size = UDim2.new(math.max(data.Health, 0) / data.MaxHealth, 0, 1, 0)
	Effects.DamageNumber(hitPosition, amount, isCrit)
	Effects.Hit(player, part, isCrit, data.Health <= 0)

	if data.Health > 0 then
		if data.IsBoss and not data.Enraged and data.Health / data.MaxHealth <= Config.Boss.EnrageRatio then
			enrageBoss(run, part, data)
		end
		return
	end

	run.Monsters[part] = nil
	run.MonsterCount -= 1
	Effects.Burst(part.Position, part.Color, data.IsBoss and 80 or 22)
	Effects.FloatText(part.Position + Vector3.new(0, part.Size.Y / 2 + 2, 0), string.format("+%d G", math.floor(data.Stats.Gold * run.GoldMult + 0.5)), Color3.fromRGB(255, 220, 90))
	part:Destroy()
	Combo.Kill(player)
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
local function stepRun(run, dt)
	local now = os.clock()

	for part, data in pairs(run.Monsters) do
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
				part.Position = Vector3.new(part.Position.X, bossGround + data.Stats.Size / 2, part.Position.Z)

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
				if nearDist <= 70 then
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
			if root and (root.Position - projectile.Part.Position).Magnitude < projectile.Radius + 2 then
				humanoid:TakeDamage(projectile.Damage)
				hit = true
				break
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
		if run.Phase == "Wave" or run.Phase == "Boss" then
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
	local isCrit = math.random() < chance
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
	table.sort(list, function(a, b) return (a.Position - center).Magnitude < (b.Position - center).Magnitude end)
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
		endPosition = result.Position
		local part = result.Instance
		local data = run.Monsters[part]
		if not data then break end

		local damage, isCrit = Dungeon.ComputeDamage(player)
		local hitPosition = result.Position
		damageMonster(run, player, part, data, damage, isCrit, hitPosition)

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
	end
	for _, part in ipairs(skipped) do
		part.CanQuery = true
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

-- 웨이브 클리어 후 보여줄 특성 후보 3개 (특수 특성은 최소 1개 포함)
local function rollOffer(player)
	local specials, normals = {}, {}
	for _, key in ipairs(Config.Perks.Order) do
		if not perkMaxed(player, key) then
			table.insert(Config.Perks[key].Special and specials or normals, key)
		end
	end
	local offer = {}
	local function take(list)
		if #list == 0 then return end
		table.insert(offer, table.remove(list, math.random(#list)))
	end
	take(specials)
	local pool = table.clone(specials)
	for _, key in ipairs(normals) do
		table.insert(pool, key)
	end
	while #offer < Config.Perks.ChoiceCount and #pool > 0 do
		local key = table.remove(pool, math.random(#pool))
		if not table.find(offer, key) then
			table.insert(offer, key)
		end
	end
	return offer
end

local function applyPerk(player, perkKey)
	local perk = Config.Perks[perkKey]
	player:SetAttribute(perk.Attr, perkStacks(player, perkKey) + 1)
	if perk.Attr == "HealthPoints" then
		applyMaxHealth(player, P.HealthPerPoint)
	end
end

-- 특성 선택 (스탯 분배 시간에 후보 중 하나)
function Dungeon.Upgrade(player, perkKey)
	local run = playerRun[player]
	if not run or run.Phase ~= "StatPhase" or typeof(perkKey) ~= "string" then return end
	local offer = run.Offers and run.Offers[player]
	if not offer or not table.find(offer, perkKey) then return end
	if perkMaxed(player, perkKey) then return end

	run.Offers[player] = nil -- 한 번만 고를 수 있다
	run.Ready[player] = true -- 고르면 자동으로 준비 완료 (버튼을 따로 누르지 않는다)
	applyPerk(player, perkKey)
	Remotes.Dungeon:FireClient(player, "Perks", { Keys = {} })
	notify(player, string.format("%s %s 선택!", Config.Perks[perkKey].Icon, Config.Perks[perkKey].Name))
end

Remotes.Upgrade.OnServerEvent:Connect(Dungeon.Upgrade)

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
		MutatorText = run.Mutator and string.format("%s %s — %s", run.Mutator.Icon, run.Mutator.Name, run.Mutator.Desc) or nil,
		BossName = run.Boss and run.BossName or nil,
		BossRatio = run.Boss and math.max(run.Boss.Health, 0) / run.Boss.MaxHealth or nil,
	}
	for _, member in ipairs(run.Members) do
		Remotes.Dungeon:FireClient(member, "State", state)
	end
end

------------------------------------------------------------
-- 종료 / 정리
------------------------------------------------------------
local function returnToLobby(player)
	playerRun[player] = nil
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
		Remotes.Dungeon:FireClient(member, "Result", {
			Victory = victory,
			Gold = run.Earned[member] or 0,
			Tickets = run.TicketsEarned[member] or 0,
			Loot = run.LootLines[member] or {},
			Wave = run.Wave,
			TotalWaves = run.TotalWaves,
			TypeName = run.Type.Name,
			DifficultyName = run.Difficulty.Name,
			ReturnDelay = D.ReturnDelay,
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
			finish(run, false)
			return false
		end
		task.wait(0.25)
	end
	return false
end

local function spawnWave(run, wave)
	local count = math.min(36, math.floor(D.GetMonsterCount(wave, run.PartySize) * (run.Mutator and run.Mutator.CountMult or 1)))
	local level = math.max(1, D.GetWaveMonsterLevel(wave) + run.LevelBonus)
	for _ = 1, count do
		if run.Destroyed or run.Phase == "Ended" then return end
		spawnMonster(run, level)
		task.wait(0.2)
	end
end

local function allReady(run)
	for _, member in ipairs(run.Members) do
		if not run.Ready[member] then
			return false
		end
	end
	return #run.Members > 0
end

-- 웨이브 클리어 후 스탯 분배 시간
local function statPhase(run)
	run.Phase = "StatPhase"
	run.PhaseEnd = os.clock() + D.StatPhaseTime
	run.Ready = {}

	run.Offers = {}
	for _, member in ipairs(run.Members) do
		applyMaxHealth(member, math.huge)
		local offer = rollOffer(member)
		run.Offers[member] = offer
		Remotes.Dungeon:FireClient(member, "Perks", { Keys = offer })
	end
	notifyAll(run, string.format("웨이브 %d 클리어! 특성을 하나 고르세요 (%d초)", run.Wave, D.StatPhaseTime))

	local ok = waitFor(run, function()
		return os.clock() >= run.PhaseEnd or allReady(run)
	end)
	if ok and allReady(run) then
		task.wait(1.0) -- 다 골랐으면 잠깐 선택 연출을 보여준 뒤 자동으로 다음 구역으로
	end
	-- 고르지 못한 사람은 후보 중 하나가 자동 선택된다
	for _, member in ipairs(run.Members) do
		local offer = run.Offers and run.Offers[member]
		if offer and #offer > 0 then
			Dungeon.Upgrade(member, offer[math.random(#offer)])
		end
	end
	return ok
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

------------------------------------------------------------
-- 방 진행 (로그라이크식): 방을 하나씩 이동하며 전투 / 이벤트를 치르고 마지막에 보스방
------------------------------------------------------------
local function setWaypoint(run, position, name)
	for _, member in ipairs(run.Members) do
		Remotes.Tutorial:FireClient(member, "Waypoint", { Pos = position, Name = name })
	end
end

local function clearWaypoint(run)
	for _, member in ipairs(run.Members) do
		Remotes.Tutorial:FireClient(member, "WaypointClear")
	end
end

local function anyoneIn(run, room, ratio)
	for _, member in ipairs(run.Members) do
		local root = getAliveParts(member)
		if root then
			local flat = Vector3.new(root.Position.X - room.Pos.X, 0, root.Position.Z - room.Pos.Z).Magnitude
			if flat <= room.R * ratio then
				return true
			end
		end
	end
	return false
end

-- 이벤트 1) 보물방: 상자에 다가가면 열린다 (장비 + 골드)
local function eventTreasure(run, room, wave)
	run.Phase = "Event"
	run.StageText = D.Events.Treasure.Name
	local chest = Instance.new("Part")
	chest.Name = "TreasureChest"
	chest.Anchored = true
	chest.CanCollide = false
	chest.Size = Vector3.new(5, 4, 4)
	chest.Color = Color3.fromRGB(255, 200, 60)
	chest.Material = Enum.Material.Neon
	chest.Position = room.Pos + Vector3.new(0, groundAt(run, room.Pos.X, room.Pos.Z, room.Pos.Y + 10) - room.Pos.Y + 2.5, 0)
	chest.Parent = run.Folder
	local light = Instance.new("PointLight")
	light.Range = 30
	light.Brightness = 3
	light.Color = chest.Color
	light.Parent = chest
	notifyAll(run, D.Events.Treasure.Name .. " — " .. D.Events.Treasure.Desc)

	local opened = os.clock() + 45
	local ok = waitFor(run, function()
		for _, member in ipairs(run.Members) do
			local root = getAliveParts(member)
			if root and (root.Position - chest.Position).Magnitude < 14 then
				return true
			end
		end
		return os.clock() >= opened
	end)
	if not ok then
		chest:Destroy()
		return false
	end
	Effects.Burst(chest.Position, Color3.fromRGB(255, 220, 90), 120)
	chest:Destroy()
	giveGold(run, D.WaveClearGold * wave * 3)
	for _, member in ipairs(run.Members) do
		local lines = run.LootLines[member] or {}
		for _, line in ipairs(Loot.DungeonChest(member, run.TypeKey, run.DiffKey, 1)) do
			table.insert(lines, line)
		end
		run.LootLines[member] = lines
	end
	notifyAll(run, "💎 보물 상자를 열었어요! 장비와 골드를 얻었어요 (결과 화면에서 확인)")
	return true
end

-- 이벤트 2) 함정방: 하늘에서 운석이 떨어진다. 바닥의 붉은 원이 점점 커지고, 다 커지면 운석이 꽂힌다.
-- 라운드가 갈수록 운석이 많아진다. 끝까지 버티면 골드 + 특성.
local function eventTrap(run, room, wave)
	run.Phase = "Event"
	run.StageText = D.Events.Trap.Name
	notifyAll(run, D.Events.Trap.Name .. " — " .. D.Events.Trap.Desc)
	local level = math.max(1, D.GetWaveMonsterLevel(wave) + run.LevelBonus)
	local damage = math.floor(Config.Monster.GetStats(level).ShotDamage * 1.6 * run.Difficulty.DamageMult)
	local rounds = 12
	local radius = 10
	task.wait(2)

	local function shake(strength)
		for _, member in ipairs(run.Members) do
			member:SetAttribute("ShakeStrength", strength)
			member:SetAttribute("ShakeTick", (member:GetAttribute("ShakeTick") or 0) + 1)
		end
	end

	for round = 1, rounds do
		if run.Destroyed or run.Phase == "Ended" then return false end
		if allDown(run) then
			finish(run, false)
			return false
		end
		run.StageText = string.format("☄ 함정방  운석 %d / %d  — 계속 움직이세요!", round, rounds)

		-- 이번 라운드의 낙하 지점: 각 플레이어 근처 + 방 안 무작위 (뒤 라운드일수록 많다)
		local centers = {}
		for _, member in ipairs(run.Members) do
			local root = getAliveParts(member)
			if root then
				table.insert(centers, root.Position + Vector3.new(math.random(-6, 6), 0, math.random(-6, 6)))
				for _ = 1, round // 4 do
					local angle = math.random() * math.pi * 2
					local dist = math.random() * room.R * 0.7
					table.insert(centers, room.Pos + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist))
				end
			end
		end

		local strikes = {}
		for _, position in ipairs(centers) do
			local x, z = position.X, position.Z
			local groundY = groundAt(run, x, z, room.Pos.Y + 10)
			local center = Vector3.new(x, groundY + 0.3, z)

			local marker = Instance.new("Part") -- 바닥의 경고 원 (바깥 고리 + 점점 차오르는 안쪽 원)
			marker.Shape = Enum.PartType.Cylinder
			marker.Anchored = true
			marker.CanCollide = false
			marker.CanQuery = false
			marker.Size = Vector3.new(0.3, radius * 2, radius * 2)
			marker.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
			marker.Color = Color3.fromRGB(255, 70, 40)
			marker.Material = Enum.Material.Neon
			marker.Transparency = 0.75
			marker.Parent = run.Folder
			local fill = Instance.new("Part")
			fill.Shape = Enum.PartType.Cylinder
			fill.Anchored = true
			fill.CanCollide = false
			fill.CanQuery = false
			fill.Size = Vector3.new(0.4, 1, 1)
			fill.CFrame = CFrame.new(center + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
			fill.Color = Color3.fromRGB(255, 200, 60)
			fill.Material = Enum.Material.Neon
			fill.Transparency = 0.35
			fill.Parent = run.Folder
			TweenService:Create(fill, TweenInfo.new(1.4, Enum.EasingStyle.Linear), { Size = Vector3.new(0.4, radius * 2, radius * 2) }):Play()

			local meteor = Instance.new("Part") -- 하늘에서 떨어지는 불덩이
			meteor.Shape = Enum.PartType.Ball
			meteor.Anchored = true
			meteor.CanCollide = false
			meteor.CanQuery = false
			meteor.Size = Vector3.new(7, 7, 7)
			meteor.Color = Color3.fromRGB(255, 120, 40)
			meteor.Material = Enum.Material.Neon
			meteor.Position = center + Vector3.new(math.random(-10, 10), 85, math.random(-10, 10))
			meteor.Parent = run.Folder
			local trail = Instance.new("ParticleEmitter")
			trail.Rate = 80
			trail.Lifetime = NumberRange.new(0.4, 0.8)
			trail.Speed = NumberRange.new(2, 6)
			trail.SpreadAngle = Vector2.new(180, 180)
			trail.LightEmission = 1
			trail.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 60, 20))
			trail.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 0) })
			trail.Parent = meteor
			local light = Instance.new("PointLight")
			light.Range = 40
			light.Brightness = 3
			light.Color = Color3.fromRGB(255, 140, 60)
			light.Parent = meteor
			TweenService:Create(meteor, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = center + Vector3.new(0, 3, 0) }):Play()

			table.insert(strikes, { Center = center, Marker = marker, Fill = fill, Meteor = meteor })
		end

		task.wait(1.45)
		-- 충돌: 큰 폭발 + 화면 흔들림 + 피해, 바닥에 그을린 자국이 잠깐 남는다
		for _, strike in ipairs(strikes) do
			for _, member in ipairs(run.Members) do
				local root, humanoid = getAliveParts(member)
				if root then
					local flatDist = Vector3.new(root.Position.X - strike.Center.X, 0, root.Position.Z - strike.Center.Z).Magnitude
					if flatDist <= radius then
						humanoid:TakeDamage(damage)
					end
				end
			end
			Effects.Burst(strike.Center + Vector3.new(0, 2, 0), Color3.fromRGB(255, 130, 50), 90)
			Effects.Burst(strike.Center + Vector3.new(0, 4, 0), Color3.fromRGB(255, 230, 120), 40)
			strike.Meteor:Destroy()
			strike.Fill:Destroy()
			strike.Marker.Color = Color3.fromRGB(40, 20, 20) -- 그을린 자국
			strike.Marker.Material = Enum.Material.Slate
			strike.Marker.Transparency = 0.2
			Debris:AddItem(strike.Marker, 3)
		end
		if #strikes > 0 then
			shake(0.7)
		end
		task.wait(0.35)
	end
	run.StageText = D.Events.Trap.Name
	giveGold(run, D.WaveClearGold * wave * 2)
	giveXp(run, Config.Xp.WaveClear * wave)
	notifyAll(run, "☄ 함정방 돌파! 보너스 골드를 얻었어요")
	return statPhase(run)
end

-- 이벤트 3) 휴식방: 체력 완전 회복 + 특성 한 번 더
local function eventRest(run, room, wave)
	run.Phase = "Event"
	run.StageText = D.Events.Rest.Name
	for _, member in ipairs(run.Members) do
		applyMaxHealth(member, math.huge)
		local root = getAliveParts(member)
		if root then
			Effects.Burst(root.Position, Color3.fromRGB(110, 220, 255), 50)
		end
	end
	notifyAll(run, D.Events.Rest.Name .. " — " .. D.Events.Rest.Desc)
	task.wait(1.5)
	return statPhase(run)
end

local EVENT_HANDLERS = { Treasure = eventTreasure, Trap = eventTrap, Rest = eventRest }

-- 던전 진행 (앞으로 쭉 가는 구조): 입구에서 보스방까지 길이 이어지고, 방마다 몬스터 무리 / 이벤트가 미리 배치돼 있다.
-- 몬스터는 가까이 가면 깨어나서 덤비고, 방의 몬스터를 모두 잡으면 구역 클리어(보상 + 특성 선택).
-- 마지막 방에 들어서면 보스가 나타난다. 하늘색 빛기둥은 "다음에 갈 곳"을 알려주는 길잡이일 뿐 꼭 밟을 필요는 없다.
local function countByRoom(run)
	local counts = {}
	for _, data in pairs(run.Monsters) do
		if data.RoomIndex then
			counts[data.RoomIndex] = (counts[data.RoomIndex] or 0) + 1
		end
	end
	return counts
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
	if run.Type.Endless then
		run.PhaseEnd = os.clock() + D.StartCountdown
		if not waitFor(run, function() return os.clock() >= run.PhaseEnd end) then return end
		towerLoop(run)
		return
	end

	-- 방 계획: 시작방(1) / 중간 방들(전투 + 이벤트) / 보스방(마지막)
	local rooms = run.Rooms
	local inner = #rooms - 2
	local eventKinds = {}
	if inner >= 3 then
		local pool = table.clone(D.Events.Order)
		local slots = { math.max(2, math.floor(inner * 0.4 + 0.5)) }
		if inner >= 6 then
			table.insert(slots, math.floor(inner * 0.8 + 0.5))
		end
		for _, slot in ipairs(slots) do
			if not eventKinds[slot + 1] and #pool > 0 then
				eventKinds[slot + 1] = table.remove(pool, math.random(#pool))
			end
		end
	end

	local combatRooms = {}   -- 방 번호 목록
	for index = 2, #rooms - 1 do
		if not eventKinds[index] then
			table.insert(combatRooms, index)
		end
	end
	run.TotalWaves = #combatRooms

	-- 전투 방마다 몬스터를 미리 배치 (뒤쪽 방일수록 강하고 많다)
	for order, index in ipairs(combatRooms) do
		local room = rooms[index]
		room.WaveNo = order
		room.Combat = true
		run.SpawnPoints = (room.Spawns and #room.Spawns > 0) and room.Spawns or run.AllSpawns
		local count = math.min(14, math.floor(D.GetMonsterCount(order, run.PartySize) * (run.Mutator and run.Mutator.CountMult or 1)))
		local level = math.max(1, D.GetWaveMonsterLevel(order) + run.LevelBonus)
		for _ = 1, count do
			local data = spawnMonster(run, level)
			data.RoomIndex = index
		end
	end

	-- (확인용) 몬스터를 몇 마리 어느 방에 깔았는지 알려준다
	do
		local firstCombat = rooms[combatRooms[1] or 2]
		local startRoom = rooms[1]
		if firstCombat and startRoom then
			notifyAll(run, string.format("🧭 전투 구역 %d개 · 몬스터 %d마리 배치 (첫 전투 방까지 %dm)", #combatRooms, run.MonsterCount or 0, (firstCombat.Pos - startRoom.Pos).Magnitude))
		end
	end

	-- 몬스터는 카운트다운 전에 미리 깔아둔다 (카운트다운 중에 앞으로 뛰어나가도 뒤에서 몬스터가 생기지 않게)
	run.PhaseEnd = os.clock() + D.StartCountdown
	if not waitFor(run, function() return os.clock() >= run.PhaseEnd end) then return end

	run.Phase = "Wave"
	run.Wave = 1
	run.PhaseEnd = nil
	local cleared = 0
	local bossSpawned = false
	local lastWaypoint = nil
	notifyAll(run, "⚔ 앞으로 나아가며 몬스터를 처치하세요! 하늘색 빛기둥이 다음 목적지를 알려줘요.")

	while not run.Destroyed and run.Phase ~= "Ended" do
		-- 전멸하면 실패
		if allDown(run) then
			finish(run, false)
			return
		end

		local counts = countByRoom(run)
		for index = 2, #rooms - 1 do
			local room = rooms[index]
			-- 구역 클리어: 이 방의 몬스터를 모두 잡았다
			if room.Combat and not room.Cleared and (counts[index] or 0) == 0 then
				room.Cleared = true
				cleared += 1
				run.Wave = math.min(cleared + 1, run.TotalWaves)
				giveGold(run, D.WaveClearGold * room.WaveNo)
				giveXp(run, Config.Xp.WaveClear * room.WaveNo)
				notifyAll(run, string.format("✅ 구역 %d / %d 클리어!", cleared, run.TotalWaves))
				if not statPhase(run) then return end
				run.Phase = "Wave"
				run.StageText = nil
			end
			-- 이벤트 방: 처음 들어서면 시작
			local kind = eventKinds[index]
			if kind and not room.Entered and anyoneIn(run, room, 0.85) then
				room.Entered = true
				room.Cleared = true
				if not EVENT_HANDLERS[kind](run, room, math.max(1, cleared)) then return end
				run.Phase = "Wave"
				run.StageText = nil
			end
		end

		-- 보스방에 들어서면 보스 등장
		local bossRoom = rooms[#rooms]
		if not bossSpawned and anyoneIn(run, bossRoom, 0.8) then
			bossSpawned = true
			run.Phase = "Boss"
			run.StageText = nil
			clearWaypoint(run)
			notifyAll(run, "⚠ " .. run.BossName .. "이(가) 나타났다!")
			spawnBoss(run)
		end
		if bossSpawned and run.BossDead then
			finish(run, true)
			return
		end

		-- 길잡이: 아직 끝내지 않은 가장 가까운 앞쪽 방 (없으면 보스방)
		if not bossSpawned then
			local target = #rooms
			for index = 2, #rooms - 1 do
				local room = rooms[index]
				if not room.Cleared and not room.Entered then
					target = index
					break
				end
			end
			if target ~= lastWaypoint then
				lastWaypoint = target
				setWaypoint(run, rooms[target].Pos + Vector3.new(0, 4, 0), target == #rooms and "보스방" or "다음 구역")
			end
		end
		task.wait(0.3)
	end
end

------------------------------------------------------------
-- 입장 (던전 게이트에서 호출). 파티가 있으면 파티장만 가능, 없으면 혼자 입장.
------------------------------------------------------------
function Dungeon.Start(player, typeKey, diffKey)
	if player:GetAttribute("Zone") ~= "Lobby" then return end

	typeKey = typeKey or "Cave"
	diffKey = diffKey or "Normal"
	local dungeonType = D.Types[typeKey]
	local difficulty = D.Difficulties[diffKey]
	if not dungeonType or not dungeonType.Waves or not difficulty or not difficulty.HealthMult then return end -- "Order" 같은 잘못된 키 방어

	local party = Party.GetParty(player)
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
	local keyCost = difficulty.KeyCost or 1
	for _, member in ipairs(members) do
		if not Keys.Has(member, keyCost) then
			notify(player, string.format("%s 님의 던전 열쇠가 부족해요. (필요 %d개)", member.DisplayName, keyCost))
			if member ~= player then
				notify(member, "던전 열쇠가 부족해서 파티가 입장하지 못했어요.")
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
		Keys.Spend(member, keyCost)
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
	}
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
		Fire = function(origin, direction, speed, damage, size, color)
			fireProjectile(run, origin, direction, speed, damage, size, color)
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
		if typeof(typeKey) == "string" and typeof(diffKey) == "string" then
			Dungeon.Start(player, typeKey, diffKey)
		end
	elseif action == "Ready" then
		local run = playerRun[player]
		if run and run.Phase == "StatPhase" then
			local offer = run.Offers and run.Offers[player]
			if offer and #offer > 0 then
				notify(player, "먼저 특성을 하나 골라주세요! (1 / 2 / 3)")
				return
			end
			run.Ready[player] = true
		end
	elseif action == "Leave" then
		Dungeon.Leave(player)
	end
end)

return Dungeon
