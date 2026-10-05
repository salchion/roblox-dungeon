-- GameServer (ServerScriptService 안의 Script)
-- 몬스터가 갈수록 커지고, 플레이어는 맞힐수록 데미지가 오르고, 킬하면 스탯 포인트를 얻는 프로토타입

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

------------------------------------------------------------
-- 밸런스 설정값 (여기 숫자만 바꿔가며 조절하면 됨)
------------------------------------------------------------
local CONFIG = {
	BaseDamage = 10,        -- 시작 데미지
	HitsPerDamageUp = 5,    -- 몇 번 맞힐 때마다 데미지 +1
	BaseCooldown = 0.35,    -- 기본 공격 간격(초)
	AttackRange = 300,      -- 사거리
	MaxMonsters = 3,        -- 동시에 존재하는 몬스터 수
	SpawnDistance = 70,     -- 맵 중앙에서 몬스터가 나타나는 거리
	CritPerPoint = 0.03,    -- 치명타 포인트당 확률 +3% (치명타 = 2배)
	MaxCritPoints = 20,     -- 치명타 최대 60%
	SpeedPerPoint = 0.08,   -- 공격속도 포인트당 +8%
	HealthPerPoint = 15,    -- 최대 체력 포인트당 +15
}

-- 몬스터 레벨별 능력치: 레벨이 오를수록 커지고 단단해짐
local function getMonsterStats(level)
	return {
		Size = math.min(3 + (level - 1) * 0.8, 40),
		MaxHealth = math.floor(40 * 1.22 ^ (level - 1)),
		Speed = 10,
		ShotDamage = 8 + level * 2,
		ShotInterval = math.max(1.2, 2.6 - level * 0.05),
		ShotSpeed = 45,
	}
end

------------------------------------------------------------
-- 기본 준비
------------------------------------------------------------
local monsterLevel = 1      -- 다음에 나올 몬스터 레벨 (킬할 때마다 +1)
local monsters = {}         -- [몬스터 Part] = 몬스터 데이터
local projectiles = {}      -- 날아가는 몬스터 공격들
local lastAttack = {}       -- [플레이어] = 마지막 공격 시각

local monstersFolder = Instance.new("Folder")
monstersFolder.Name = "Monsters"
monstersFolder.Parent = workspace

local attackEvent = Instance.new("RemoteEvent")
attackEvent.Name = "Attack"
attackEvent.Parent = ReplicatedStorage

local upgradeEvent = Instance.new("RemoteEvent")
upgradeEvent.Name = "Upgrade"
upgradeEvent.Parent = ReplicatedStorage

------------------------------------------------------------
-- 플레이어
------------------------------------------------------------
local function getMaxHealth(player)
	return 100 + player:GetAttribute("HealthPoints") * CONFIG.HealthPerPoint
end

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.MaxHealth = getMaxHealth(player)
	humanoid.Health = humanoid.MaxHealth
end

local function setupPlayer(player)
	player.CameraMode = Enum.CameraMode.LockFirstPerson -- 1인칭 고정

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local damage = Instance.new("IntValue")
	damage.Name = "Damage"
	damage.Value = CONFIG.BaseDamage
	damage.Parent = leaderstats

	local kills = Instance.new("IntValue")
	kills.Name = "Kills"
	kills.Parent = leaderstats

	player:SetAttribute("HitCount", 0)
	player:SetAttribute("StatPoints", 0)
	player:SetAttribute("CritPoints", 0)
	player:SetAttribute("SpeedPoints", 0)
	player:SetAttribute("HealthPoints", 0)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	lastAttack[player] = nil
end)

local function getAliveParts(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and humanoid and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil
end

local function getNearestTarget(position)
	local nearest, nearestDist = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local root = getAliveParts(player)
		if root then
			local dist = (root.Position - position).Magnitude
			if dist < nearestDist then
				nearest, nearestDist = root, dist
			end
		end
	end
	return nearest, nearestDist
end

------------------------------------------------------------
-- 이펙트 (총알 궤적, 데미지 숫자)
------------------------------------------------------------
local function drawTracer(from, to)
	local distance = (to - from).Magnitude
	if distance < 0.1 then return end
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 255, 150)
	beam.Size = Vector3.new(0.15, 0.15, distance)
	beam.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -distance / 2)
	beam.Parent = workspace
	Debris:AddItem(beam, 0.06)
end

local function showDamageNumber(position, amount, isCrit)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 90, 0, 40)
	gui.AlwaysOnTop = true
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextStrokeTransparency = 0
	label.Text = isCrit and (amount .. "!") or tostring(amount)
	label.TextColor3 = isCrit and Color3.fromRGB(255, 220, 60) or Color3.new(1, 1, 1)
	label.Parent = gui

	Debris:AddItem(anchor, 0.5)
end

------------------------------------------------------------
-- 몬스터
------------------------------------------------------------
local function createHealthBar(part, level)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 120, 0, 28)
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
	label.Text = "Lv." .. level
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

local function spawnMonster()
	local level = monsterLevel
	local stats = getMonsterStats(level)
	local angle = math.random() * math.pi * 2

	local part = Instance.new("Part")
	part.Name = "Monster"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(stats.Size, stats.Size, stats.Size)
	part.Anchored = true
	part.CanCollide = false
	part.Color = Color3.fromRGB(120, 40, 160)
	part.Position = Vector3.new(
		math.cos(angle) * CONFIG.SpawnDistance,
		stats.Size / 2,
		math.sin(angle) * CONFIG.SpawnDistance
	)
	part.Parent = monstersFolder

	monsters[part] = {
		Level = level,
		Stats = stats,
		Health = stats.MaxHealth,
		HealthFill = createHealthBar(part, level),
		NextShot = os.clock() + stats.ShotInterval,
		BaseColor = part.Color,
	}
end

local function fireProjectile(monster, data, targetPosition)
	local size = math.max(1.5, data.Stats.Size / 4)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(size, size, size)
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.fromRGB(255, 120, 30)
	ball.Position = monster.Position
	ball.Parent = workspace

	table.insert(projectiles, {
		Part = ball,
		Direction = (targetPosition - monster.Position).Unit,
		Speed = data.Stats.ShotSpeed,
		Damage = data.Stats.ShotDamage,
		Radius = size / 2,
		Expire = os.clock() + 4,
	})
end

local function damageMonster(player, part, data, amount, isCrit, hitPosition)
	data.Health -= amount
	data.HealthFill.Size = UDim2.new(math.max(data.Health, 0) / data.Stats.MaxHealth, 0, 1, 0)
	showDamageNumber(hitPosition, amount, isCrit)

	if data.Health <= 0 then
		monsters[part] = nil
		part:Destroy()
		monsterLevel += 1
		-- 킬 보상: 특수 스탯 포인트
		player.leaderstats.Kills.Value += 1
		player:SetAttribute("StatPoints", player:GetAttribute("StatPoints") + 1)
	end
end

------------------------------------------------------------
-- 플레이어 공격 처리 (판정은 서버에서)
------------------------------------------------------------
attackEvent.OnServerEvent:Connect(function(player, direction)
	if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.5 then return end

	local now = os.clock()
	local cooldown = CONFIG.BaseCooldown / (1 + player:GetAttribute("SpeedPoints") * CONFIG.SpeedPerPoint)
	if now - (lastAttack[player] or 0) < cooldown * 0.9 then return end -- 연타 제한 (네트워크 오차 10% 허용)
	lastAttack[player] = now

	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local _, humanoid = getAliveParts(player)
	if not head or not humanoid then return end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { monstersFolder }

	local origin = head.Position
	local result = workspace:Raycast(origin, direction.Unit * CONFIG.AttackRange, params)
	local endPosition = result and result.Position or (origin + direction.Unit * CONFIG.AttackRange)
	drawTracer(origin + Vector3.new(0, -0.6, 0) + head.CFrame.RightVector * 0.8, endPosition)

	if not result then return end
	local part = result.Instance
	local data = monsters[part]
	if not data then return end

	local damage = player.leaderstats.Damage.Value
	local isCrit = math.random() < player:GetAttribute("CritPoints") * CONFIG.CritPerPoint
	if isCrit then
		damage *= 2
	end

	-- 맞힐 때마다 조금씩 데미지 성장
	local hits = player:GetAttribute("HitCount") + 1
	player:SetAttribute("HitCount", hits)
	if hits % CONFIG.HitsPerDamageUp == 0 then
		player.leaderstats.Damage.Value += 1
	end

	damageMonster(player, part, data, damage, isCrit, result.Position)
end)

------------------------------------------------------------
-- 스탯 포인트 투자 (1: 치명타, 2: 공격속도, 3: 최대체력)
------------------------------------------------------------
local UPGRADE_ATTRIBUTES = {
	Crit = "CritPoints",
	Speed = "SpeedPoints",
	Health = "HealthPoints",
}

upgradeEvent.OnServerEvent:Connect(function(player, statName)
	local attribute = UPGRADE_ATTRIBUTES[statName]
	if not attribute then return end

	local points = player:GetAttribute("StatPoints")
	if points <= 0 then return end
	if attribute == "CritPoints" and player:GetAttribute("CritPoints") >= CONFIG.MaxCritPoints then return end

	player:SetAttribute("StatPoints", points - 1)
	player:SetAttribute(attribute, player:GetAttribute(attribute) + 1)

	if attribute == "HealthPoints" then
		local _, humanoid = getAliveParts(player)
		if humanoid then
			humanoid.MaxHealth = getMaxHealth(player)
			humanoid.Health += CONFIG.HealthPerPoint
		end
	end
end)

------------------------------------------------------------
-- 매 프레임: 몬스터 이동/공격, 투사체 이동/명중
------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()

	for part, data in pairs(monsters) do
		local target, distance = getNearestTarget(part.Position)
		if target then
			-- 일정 거리까지만 다가옴 (덩치가 클수록 멀리서 멈춤)
			local keepDistance = data.Stats.Size + 12
			if distance > keepDistance then
				local flatTarget = Vector3.new(target.Position.X, part.Position.Y, target.Position.Z)
				local move = flatTarget - part.Position
				if move.Magnitude > 0.1 then
					part.Position += move.Unit * data.Stats.Speed * dt
				end
			end

			if now >= data.NextShot then
				data.NextShot = now + data.Stats.ShotInterval
				-- 예고: 0.4초 동안 노랗게 빛난 뒤 발사 → 보고 피할 수 있게
				part.Color = Color3.fromRGB(255, 220, 80)
				task.delay(0.4, function()
					if not monsters[part] then return end
					part.Color = data.BaseColor
					local currentTarget = getNearestTarget(part.Position)
					if currentTarget then
						fireProjectile(part, data, currentTarget.Position)
					end
				end)
			end
		end
	end

	for i = #projectiles, 1, -1 do
		local projectile = projectiles[i]
		projectile.Part.Position += projectile.Direction * projectile.Speed * dt

		local hit = false
		for _, player in ipairs(Players:GetPlayers()) do
			local root, humanoid = getAliveParts(player)
			if root and (root.Position - projectile.Part.Position).Magnitude < projectile.Radius + 2 then
				humanoid:TakeDamage(projectile.Damage)
				hit = true
				break
			end
		end

		if hit or now > projectile.Expire then
			projectile.Part:Destroy()
			table.remove(projectiles, i)
		end
	end
end)

------------------------------------------------------------
-- 몬스터 스폰 루프
------------------------------------------------------------
task.spawn(function()
	while true do
		local count = 0
		for _ in pairs(monsters) do
			count += 1
		end
		if count < CONFIG.MaxMonsters and #Players:GetPlayers() > 0 then
			spawnMonster()
		end
		task.wait(3)
	end
end)
