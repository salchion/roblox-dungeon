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
	local offset = Vector3.new(math.cos(angle) * 6, 4, math.sin(angle) * 6)
	return CFrame.new(run.Origin + offset)
end

local function giveGold(run, amount)
	amount = math.floor(amount * run.GoldMult + 0.5)
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
	gui.AlwaysOnTop = true
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

	local color = def.Color:Lerp(run.Type.MonsterColor, 0.25)
	local part = MonsterTypes.Build(typeKey, stats.Size, color, position or ringPosition(run, stats.Size), run.MonstersFolder)

	registerMonster(run, part, stats, string.format("Lv.%d %s", level, def.Name), 140, {
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
		Size = boss.Size,
		MaxHealth = math.floor(boss.MaxHealth * D.GetHealthScale(run.PartySize) * bossType.HealthMult * run.Difficulty.HealthMult),
		Speed = boss.Speed,
		ShotDamage = math.floor(boss.ShotDamage * bossType.DamageMult * run.Difficulty.DamageMult),
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
	part.Color = bossType.Color
	part.Material = Enum.Material.Neon
	part.Position = Vector3.new(run.Origin.X, groundAt(run, run.Origin.X, run.Origin.Z - D.SpawnRadius, run.Origin.Y + 10) + stats.Size / 2, run.Origin.Z - D.SpawnRadius)
	part.Parent = run.MonstersFolder

	local data = registerMonster(run, part, stats, bossType.Name, 320, {
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

local BOSS_PATTERNS = { Fan = bossFan, Ring = bossRing, Spiral = bossSpiral, Meteor = bossMeteor }

-- 던전 종류마다 패턴 비중이 다르다 (Config.Dungeon.Types[..].Boss.Weights).
-- 직전과 같은 패턴은 피하고, 광폭화하면 나선 / 메테오 비중이 커진다.
local function pickBossPattern(run, data)
	local weights = run.Type.Boss.Weights
	local entries, total = {}, 0
	for name, weight in pairs(weights) do
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
	data.HealthFill.Size = UDim2.new(math.max(data.Health, 0) / data.MaxHealth, 0, 1, 0)
	Effects.DamageNumber(hitPosition, amount, isCrit)

	if data.Health > 0 then
		if data.IsBoss and not data.Enraged and data.Health / data.MaxHealth <= Config.Boss.EnrageRatio then
			enrageBoss(run, part, data)
		end
		return
	end

	run.Monsters[part] = nil
	run.MonsterCount -= 1
	part:Destroy()
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
						part.Position += move.Unit * data.Stats.Speed * dt
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
			MonsterTypes.Update(run.Ctx, part, data, dt, now)
		end
	end

	for i = #run.Projectiles, 1, -1 do
		local projectile = run.Projectiles[i]
		projectile.Part.Position += projectile.Direction * projectile.Speed * dt

		local hit = false
		for _, member in ipairs(run.Members) do
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
		* (1 + (player:GetAttribute("GearDamage") or 0) + (player:GetAttribute("TrainDamage") or 0))
		* (1 + (player:GetAttribute("PerkPower") or 0) * Config.Perks.PowerPerStack)
	local chance = math.min(0.9, (player:GetAttribute("CritPoints") or 0) * P.CritPerPoint
		+ (player:GetAttribute("GearCrit") or 0) + (player:GetAttribute("TrainCrit") or 0) + (weaponType.CritBonus or 0))
	local isCrit = math.random() < chance
	if isCrit then
		damage *= P.CritMultiplier
	end
	return math.max(1, math.floor(damage + 0.5)), isCrit
end

-- 범위 피해: center 주변 radius 안의 모든 적에게 damage 를 준다 (스킬용). 맞은 위치 목록 반환
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

-- 던전 특성 효과(관통 / 폭발 / 연쇄 / 흡혈)를 포함한 사격
function Dungeon.Shoot(player, origin, direction)
	local run = playerRun[player]
	if not run or run.Destroyed then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { run.MonstersFolder }

	local range = Config.GetPlayerWeapon(player).Range
	local pierce = player:GetAttribute("PerkPierce") or 0
	local boom = player:GetAttribute("PerkBoom") or 0
	local chain = player:GetAttribute("PerkChain") or 0
	local vamp = player:GetAttribute("PerkVamp") or 0

	local endPosition = origin + direction * range
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

		-- 폭발: 맞은 지점 주변 적에게 피해
		if boom > 0 then
			local radius = 8 + boom * 4
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
			run.LootLines[member] = Loot.DungeonChest(member, run.TypeKey, run.DiffKey) -- 보스 상자: 장비 아이템
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
	local count = D.GetMonsterCount(wave, run.PartySize)
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
	-- 고르지 못한 사람은 후보 중 하나가 자동 선택된다
	for _, member in ipairs(run.Members) do
		local offer = run.Offers and run.Offers[member]
		if offer and #offer > 0 then
			Dungeon.Upgrade(member, offer[math.random(#offer)])
		end
	end
	return ok
end

local function runLoop(run)
	run.Phase = "Starting"
	run.PhaseEnd = os.clock() + D.StartCountdown
	if not waitFor(run, function() return os.clock() >= run.PhaseEnd end) then return end

	for wave = 1, run.TotalWaves do
		run.Wave = wave
		run.Phase = "Wave"
		run.PhaseEnd = nil
		spawnWave(run, wave)
		if not waitFor(run, function() return run.MonsterCount <= 0 end) then return end

		giveGold(run, D.WaveClearGold * wave)
		giveXp(run, Config.Xp.WaveClear * wave)
		if not statPhase(run) then return end
	end

	-- 모든 웨이브 클리어 -> 보스
	run.Phase = "Boss"
	run.PhaseEnd = nil
	notifyAll(run, "⚠ " .. run.BossName .. "이(가) 나타났다!")
	spawnBoss(run)
	if not waitFor(run, function() return run.BossDead end) then return end

	finish(run, true)
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
		Origin = D.ArenaOrigin + Vector3.new(slot * D.ArenaSpacing, 0, 0),
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
		BossName = dungeonType.Boss.Name,
		GoldMult = dungeonType.GoldMult * difficulty.GoldMult,
		LevelBonus = dungeonType.LevelOffset + difficulty.LevelOffset,
	}
	nextRunId += 1
	runs[run.Id] = run

	-- 몬스터 AI(MonsterTypes)가 던전 환경을 다루는 데 쓰는 함수들
	run.Ctx = {
		FloorY = run.Origin.Y,
		GroundY = function(x, z, fromY)
			return run.GroundY and run.GroundY(x, z, fromY) or nil
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
