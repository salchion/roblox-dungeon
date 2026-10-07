-- FieldService (ServerScriptService > Modules 안의 ModuleScript, 이름: FieldService)
-- 로비 동쪽으로 길게 이어진 직선 사냥 필드. 모든 플레이어가 함께 쓰는 열린 공간이다.
--   * 8개 구역(초원 -> 숲 -> 황무지 -> 사막 -> 설원 -> 화산 -> 암흑 지대 -> 심연), 동쪽으로 갈수록 몬스터가 강해짐
--   * 구역마다 일반 몬스터 + 엘리트(★) 1마리. 처치하면 골드, 엘리트는 확률로 티켓
--   * 맨 끝에 필드 보스 (처치하면 주변 플레이어에게 티켓)
--   * 어디까지 갔는지(MaxZone)가 머리 위 이름표에 남아 강함을 과시할 수 있다
-- 플레이어의 Zone Attribute 는 x좌표로 "Lobby" / "Field" 가 자동 전환된다 (던전 안에 있는 사람은 건드리지 않음).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Dungeon = require(script.Parent:WaitForChild("DungeonService"))

local F = Config.Field
local TOP = 0.05

local Field = {}

local monsters = {}      -- [Part] = 몬스터 데이터
local projectiles = {}
local worldFolder, monstersFolder

------------------------------------------------------------
-- 유틸
------------------------------------------------------------
local function notify(player, text)
	Remotes.Notify:FireClient(player, text)
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

local function nearestFieldPlayer(position)
	local nearest, nearestDist = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Zone") == "Field" then
			local root = getAliveParts(player)
			if root then
				local dist = (root.Position - position).Magnitude
				if dist < nearestDist then
					nearest, nearestDist = root, dist
				end
			end
		end
	end
	return nearest, nearestDist
end

local function zoneBounds(zone)
	local x0 = F.StartX + (zone - 1) * F.ZoneLength
	return x0, x0 + F.ZoneLength
end

local function zoneOfX(x)
	return math.clamp(math.floor((x - F.StartX) / F.ZoneLength) + 1, 1, F.ZoneCount)
end

local function makePart(props, parent)
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	part.Parent = parent
	return part
end

------------------------------------------------------------
-- 맵 생성
------------------------------------------------------------
local function makeSign(part, text, color, offsetY)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 360, 0, 90)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = 220
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.Text = text
	label.Parent = gui
end

local function decorateZone(zone, rng)
	local x0, x1 = zoneBounds(zone)
	local half = F.Width / 2
	for _ = 1, 14 do
		local x = rng:NextNumber(x0 + 12, x1 - 12)
		local z = rng:NextNumber(-half + 6, half - 6)
		local position = Vector3.new(x, TOP, z)

		if zone <= 2 or zone == 5 then
			-- 나무 (설원은 눈 덮인 나무)
			local height = rng:NextNumber(8, 14)
			makePart({ Name = "Trunk", Size = Vector3.new(2, height, 2), Position = position + Vector3.new(0, height / 2, 0), Color = Color3.fromRGB(90, 62, 40), Material = Enum.Material.Wood }, worldFolder)
			local leaf = rng:NextNumber(9, 14)
			makePart({
				Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(leaf, leaf, leaf),
				Position = position + Vector3.new(0, height + leaf / 3, 0),
				Color = zone == 5 and Color3.fromRGB(235, 245, 250) or Color3.fromRGB(rng:NextInteger(45, 75), rng:NextInteger(120, 165), rng:NextInteger(50, 80)),
				Material = zone == 5 and Enum.Material.Snow or Enum.Material.Grass, CanCollide = false,
			}, worldFolder)
		elseif zone == 3 or zone == 4 then
			-- 바위 / 선인장
			if zone == 4 and rng:NextNumber() < 0.5 then
				local height = rng:NextNumber(6, 11)
				makePart({ Name = "Cactus", Size = Vector3.new(2.2, height, 2.2), Position = position + Vector3.new(0, height / 2, 0), Color = Color3.fromRGB(70, 140, 70), Material = Enum.Material.Grass }, worldFolder)
			else
				local size = rng:NextNumber(4, 9)
				makePart({ Name = "Rock", Size = Vector3.new(size, size * 0.7, size * 1.1), Position = position + Vector3.new(0, size * 0.3, 0), Color = Color3.fromRGB(125, 110, 95), Material = Enum.Material.Slate }, worldFolder)
			end
		else
			-- 화산 / 암흑 / 심연: 빛나는 결정 기둥
			local height = rng:NextNumber(8, 16)
			local colors = { [6] = Color3.fromRGB(255, 110, 40), [7] = Color3.fromRGB(150, 80, 255), [8] = Color3.fromRGB(255, 60, 120) }
			local crystal = makePart({
				Name = "Crystal", Size = Vector3.new(2.5, height, 2.5),
				CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), math.rad(rng:NextNumber(-12, 12))),
				Color = colors[zone], Material = Enum.Material.Neon,
			}, worldFolder)
			local light = Instance.new("PointLight")
			light.Range = 22
			light.Brightness = 1.2
			light.Color = colors[zone]
			light.Parent = crystal
		end
	end
end

local function buildWorld()
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "Field"
	worldFolder.Parent = workspace

	monstersFolder = Instance.new("Folder")
	monstersFolder.Name = "FieldMonsters"
	monstersFolder.Parent = workspace

	local half = F.Width / 2
	local totalLength = F.ZoneLength * F.ZoneCount
	local rng = Random.new(77)

	for zone = 1, F.ZoneCount do
		local x0 = zoneBounds(zone)
		makePart({
			Name = "Ground" .. zone,
			Size = Vector3.new(F.ZoneLength, 2, F.Width),
			Position = Vector3.new(x0 + F.ZoneLength / 2, TOP - 1, 0),
			Color = F.ZoneColors[zone],
			Material = F.ZoneMaterials[zone],
		}, worldFolder)

		-- 구역 입구 아치: 이름 + 몬스터 레벨
		local stone = F.ZoneColors[zone]:Lerp(Color3.fromRGB(50, 50, 60), 0.6)
		makePart({ Name = "ArchL", Size = Vector3.new(5, 32, 5), Position = Vector3.new(x0 + 2, 16, -half + 3), Color = stone, Material = Enum.Material.Granite }, worldFolder)
		makePart({ Name = "ArchR", Size = Vector3.new(5, 32, 5), Position = Vector3.new(x0 + 2, 16, half - 3), Color = stone, Material = Enum.Material.Granite }, worldFolder)
		local beam = makePart({ Name = "ArchBeam", Size = Vector3.new(5, 5, F.Width), Position = Vector3.new(x0 + 2, 34, 0), Color = stone, Material = Enum.Material.Granite, CanCollide = false }, worldFolder)
		makeSign(beam, string.format("구역 %d · %s\n몬스터 Lv.%d", zone, F.ZoneNames[zone], F.GetZoneLevel(zone)), Color3.fromRGB(255, 240, 190), 8)

		decorateZone(zone, rng)
	end

	-- 필드 가장자리 보이지 않는 벽 (옆면 / 끝 / 로비 쪽 입구 통로)
	local function wall(size, position)
		makePart({ Name = "Wall", Size = size, Position = position, Transparency = 1 }, worldFolder)
	end
	local centerX = F.StartX + totalLength / 2
	wall(Vector3.new(totalLength + 4, 50, 2), Vector3.new(centerX, 25, half + 1))
	wall(Vector3.new(totalLength + 4, 50, 2), Vector3.new(centerX, 25, -half - 1))
	wall(Vector3.new(2, 50, F.Width), Vector3.new(F.StartX + totalLength + 1, 25, 0))
	wall(Vector3.new(2, 50, half - 20), Vector3.new(F.StartX - 1, 25, (half + 20) / 2))
	wall(Vector3.new(2, 50, half - 20), Vector3.new(F.StartX - 1, 25, -(half + 20) / 2))
	wall(Vector3.new(26, 50, 2), Vector3.new(F.StartX - 14, 25, 21))
	wall(Vector3.new(26, 50, 2), Vector3.new(F.StartX - 14, 25, -21))
end

------------------------------------------------------------
-- 몬스터
------------------------------------------------------------
local function createHealthBar(part, text, width, color)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, width, 0, 28)
	gui.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 1.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 200
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.5, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
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

-- kind: "Normal" / "Elite" / "Boss"
local function spawnMonster(zone, kind)
	local stats, text, color, barWidth
	local level = F.GetZoneLevel(zone)

	if kind == "Boss" then
		local boss = F.Boss
		stats = {
			Size = boss.Size, MaxHealth = boss.MaxHealth, Speed = boss.Speed, ShotDamage = boss.ShotDamage,
			ShotInterval = boss.ShotInterval, ShotSpeed = boss.ShotSpeed, Gold = boss.Gold,
		}
		text, color, barWidth = "👑 " .. boss.Name, Color3.fromRGB(255, 120, 120), 300
	elseif kind == "Elite" then
		stats = Config.Monster.GetStats(level + 2)
		stats.MaxHealth = math.floor(stats.MaxHealth * F.EliteMultiplier)
		stats.Size = stats.Size * 1.5
		stats.Gold *= 4
		text, color, barWidth = string.format("★ 엘리트 Lv.%d", level + 2), Color3.fromRGB(255, 220, 90), 160
	else
		stats = Config.Monster.GetStats(level)
		text, color, barWidth = "Lv." .. level, Color3.new(1, 1, 1), 120
	end

	local x0, x1 = zoneBounds(zone)
	local position
	if kind == "Boss" then
		position = Vector3.new(x1 - 45, TOP + stats.Size / 2, 0)
	else
		position = Vector3.new(
			math.random(math.floor(x0 + 25), math.floor(x1 - 25)),
			TOP + stats.Size / 2,
			math.random(-F.Width / 2 + 20, F.Width / 2 - 20)
		)
	end

	local part = Instance.new("Part")
	part.Name = kind == "Boss" and "FieldBoss" or "FieldMonster"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(stats.Size, stats.Size, stats.Size)
	part.Anchored = true
	part.CanCollide = false
	part.Position = position
	if kind == "Boss" then
		part.Color = Color3.fromRGB(150, 25, 45)
		part.Material = Enum.Material.Neon
	elseif kind == "Elite" then
		part.Color = Color3.fromRGB(230, 180, 40)
		part.Material = Enum.Material.Neon
	else
		part.Color = Color3.fromHSV((0.78 - zone * 0.09) % 1, 0.55, 0.75)
	end
	part.Parent = monstersFolder

	monsters[part] = {
		Zone = zone,
		Kind = kind,
		Level = level,
		Stats = stats,
		Health = stats.MaxHealth,
		MaxHealth = stats.MaxHealth,
		HealthFill = createHealthBar(part, text, barWidth, color),
		Home = position,
		NextShot = os.clock() + stats.ShotInterval,
		NextRing = os.clock() + 7,
		BaseColor = part.Color,
		Aggro = false,
	}
end

local function fireProjectile(origin, direction, speed, damage, size, color)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(size, size, size)
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.Material = Enum.Material.Neon
	ball.Color = color or Color3.fromRGB(255, 120, 30)
	ball.Position = origin
	ball.Parent = worldFolder

	table.insert(projectiles, {
		Part = ball, Direction = direction.Unit, Speed = speed, Damage = damage,
		Radius = size / 2, Expire = os.clock() + 5,
	})
end

local function rotateY(vector, degrees)
	return CFrame.Angles(0, math.rad(degrees), 0):VectorToWorldSpace(vector)
end

local function telegraph(part, data, color, delay, action)
	part.Color = color
	task.delay(delay, function()
		if monsters[part] ~= data then return end
		part.Color = data.BaseColor
		action()
	end)
end

local function reward(player, data, part)
	local gold = data.Stats.Gold
	player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + gold)
	Effects.FloatText(part.Position + Vector3.new(0, part.Size.Y / 2, 0), string.format("+%d G", gold), Color3.fromRGB(255, 220, 90))

	if data.Kind == "Elite" and math.random() < F.EliteTicketChance then
		player:SetAttribute("Tickets", (player:GetAttribute("Tickets") or 0) + 1)
		notify(player, "🎫 엘리트에게서 장비 뽑기 티켓을 얻었어요!")
	elseif data.Kind == "Boss" then
		local bossPosition = part.Position
		for _, other in ipairs(Players:GetPlayers()) do
			local root = getAliveParts(other)
			if other:GetAttribute("Zone") == "Field" and root and (root.Position - bossPosition).Magnitude <= 160 then
				other:SetAttribute("Tickets", (other:GetAttribute("Tickets") or 0) + F.BossTickets)
				notify(other, string.format("👑 필드 보스 처치! 티켓 +%d", F.BossTickets))
			end
		end
	end
end

local function killMonster(player, part, data)
	monsters[part] = nil
	part:Destroy()
	reward(player, data, part)

	local zone, kind = data.Zone, data.Kind
	task.delay(kind == "Boss" and F.BossRespawn or F.RespawnTime, function()
		spawnMonster(zone, kind)
	end)
end

------------------------------------------------------------
-- 플레이어 공격 (판정은 서버에서). 필드 밖이면 nil
------------------------------------------------------------
function Field.Shoot(player, origin, direction)
	if player:GetAttribute("Zone") ~= "Field" or not monstersFolder then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { monstersFolder }

	local result = workspace:Raycast(origin, direction * Config.Player.AttackRange, params)
	local endPosition = result and result.Position or (origin + direction * Config.Player.AttackRange)

	local data = result and monsters[result.Instance]
	if data then
		local damage, isCrit = Dungeon.ComputeDamage(player)
		data.Health -= damage
		data.HealthFill.Size = UDim2.new(math.max(data.Health, 0) / data.MaxHealth, 0, 1, 0)
		Effects.DamageNumber(result.Position, damage, isCrit)
		if data.Health <= 0 then
			killMonster(player, result.Instance, data)
		end
	end
	return endPosition
end

------------------------------------------------------------
-- 매 프레임: 몬스터 AI / 투사체 / 구역 갱신
------------------------------------------------------------
local function stepMonsters(dt)
	local now = os.clock()
	for part, data in pairs(monsters) do
		local target, distance = nearestFieldPlayer(part.Position)
		local range = data.Aggro and F.LeashRange or F.AggroRange
		local fromHome = (part.Position - data.Home).Magnitude

		if target and distance <= range and fromHome <= F.LeashRange * 1.5 then
			data.Aggro = true

			local keepDistance = data.Stats.Size / 2 + 16
			if distance > keepDistance then
				local flatTarget = Vector3.new(target.Position.X, part.Position.Y, target.Position.Z)
				local move = flatTarget - part.Position
				if move.Magnitude > 0.1 then
					part.Position += move.Unit * data.Stats.Speed * dt
				end
			end

			if now >= data.NextShot then
				data.NextShot = now + data.Stats.ShotInterval
				telegraph(part, data, Color3.fromRGB(255, 220, 80), 0.4, function()
					local current = nearestFieldPlayer(part.Position)
					if not current then return end
					local direction = current.Position - part.Position
					if data.Kind == "Boss" then
						for _, angle in ipairs({ -20, -10, 0, 10, 20 }) do
							fireProjectile(part.Position, rotateY(direction.Unit, angle), data.Stats.ShotSpeed, data.Stats.ShotDamage, 3, Color3.fromRGB(255, 80, 60))
						end
					else
						fireProjectile(part.Position, direction, data.Stats.ShotSpeed, data.Stats.ShotDamage, math.max(1.5, data.Stats.Size / 4))
					end
				end)
			end

			-- 보스: 주기적으로 전방위 탄막
			if data.Kind == "Boss" and now >= data.NextRing then
				data.NextRing = now + 7
				telegraph(part, data, Color3.new(1, 1, 1), 0.8, function()
					for i = 0, 15 do
						local angle = (i / 16) * math.pi * 2
						local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
						fireProjectile(Vector3.new(part.Position.X, TOP + 3, part.Position.Z) + direction * (part.Size.X / 2 + 1), direction, 30, math.floor(data.Stats.ShotDamage * 0.7), 2.4, Color3.fromRGB(255, 180, 60))
					end
				end)
			end
		else
			-- 목표가 없거나 멀어지면 제자리로 돌아가서 체력을 회복
			data.Aggro = false
			local toHome = Vector3.new(data.Home.X - part.Position.X, 0, data.Home.Z - part.Position.Z)
			if toHome.Magnitude > 1 then
				part.Position += toHome.Unit * data.Stats.Speed * 1.5 * dt
			elseif data.Health < data.MaxHealth then
				data.Health = data.MaxHealth
				data.HealthFill.Size = UDim2.new(1, 0, 1, 0)
			end
		end
	end
end

local function stepProjectiles(dt)
	local now = os.clock()
	for i = #projectiles, 1, -1 do
		local projectile = projectiles[i]
		projectile.Part.Position += projectile.Direction * projectile.Speed * dt

		local hit = false
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("Zone") == "Field" then
				local root, humanoid = getAliveParts(player)
				if root and (root.Position - projectile.Part.Position).Magnitude < projectile.Radius + 2 then
					humanoid:TakeDamage(projectile.Damage)
					hit = true
					break
				end
			end
		end

		if hit or now > projectile.Expire then
			projectile.Part:Destroy()
			table.remove(projectiles, i)
		end
	end
end

-- x좌표로 로비 / 필드 구역을 판별하고, 가장 멀리 간 구역(MaxZone)을 기록
local function updateZones()
	for _, player in ipairs(Players:GetPlayers()) do
		local zone = player:GetAttribute("Zone")
		if zone == "Lobby" or zone == "Field" then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local inField = root.Position.X >= F.StartX - 5 and root.Position.X < F.StartX + F.ZoneLength * F.ZoneCount + 20
				local newZone = inField and "Field" or "Lobby"
				if newZone ~= zone then
					player:SetAttribute("Zone", newZone)
					if newZone == "Field" then
						notify(player, "필드 입장! 동쪽으로 갈수록 몬스터가 강해져요.")
					end
				end

				if inField then
					local fieldZone = zoneOfX(root.Position.X)
					if fieldZone > (player:GetAttribute("MaxZone") or 0) then
						player:SetAttribute("MaxZone", fieldZone)
						notify(player, string.format("🏔 구역 %d · %s 돌파!", fieldZone, F.ZoneNames[fieldZone]))
					end
				end
			end
		end
	end
end

function Field.Init()
	buildWorld()

	for zone = 1, F.ZoneCount do
		for _ = 1, F.MonstersPerZone do
			spawnMonster(zone, "Normal")
		end
		spawnMonster(zone, "Elite")
	end
	spawnMonster(F.ZoneCount, "Boss")

	local zoneTimer = 0
	RunService.Heartbeat:Connect(function(dt)
		stepMonsters(dt)
		stepProjectiles(dt)
		zoneTimer += dt
		if zoneTimer >= 0.4 then
			zoneTimer = 0
			updateZones()
		end
	end)
end

return Field
