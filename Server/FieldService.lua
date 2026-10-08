-- FieldService (ServerScriptService > Modules 안의 ModuleScript, 이름: FieldService)
-- 로비 동쪽으로 길게 이어진 직선 사냥 필드. 모든 플레이어가 함께 쓰는 열린 공간이다.
--   * 8개 구역(초원 -> 숲 -> 황무지 -> 사막 -> 설원 -> 화산 -> 암흑 지대 -> 심연), 동쪽으로 갈수록 몬스터가 강해짐
--   * 구역 하나하나가 아주 넓다 (Config.Field.ZoneLength x Width). 구역마다 일반 몬스터 + 엘리트(★) 여러 마리
--   * 몬스터가 장비 아이템을 떨어뜨린다 (개인 전리품, LootService). 구역이 깊을수록 높은 등급
--   * 구역마다 입구에 캠프: 안전지대 + 워프 + 죽었을 때 부활 지점
--   * 공개 이벤트: 일정 시간마다 침공 보스가 나타나고, 같이 싸운 사람은 전리품을 받는다
--   * 맨 끝에 필드 보스 (처치하면 주변 플레이어에게 티켓 + 전리품)
--   * 어디까지 갔는지(MaxZone)가 머리 위 이름표에 남아 강함을 과시할 수 있다
-- 플레이어의 Zone Attribute 는 x좌표로 "Lobby" / "Field" 가 자동 전환된다 (던전 안에 있는 사람은 건드리지 않음).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local CollectionService = game:GetService("CollectionService")
local Effects = require(script.Parent:WaitForChild("Effects"))
local Dungeon = require(script.Parent:WaitForChild("DungeonService"))
local Quest = require(script.Parent:WaitForChild("QuestService"))
local Level = require(script.Parent:WaitForChild("LevelService"))
local MonsterTypes = require(script.Parent:WaitForChild("MonsterTypes"))
local Combo = require(script.Parent:WaitForChild("ComboService"))
local Loot = require(script.Parent:WaitForChild("LootService"))

local F = Config.Field
local TOP = 0.05

local Field = {}

local monsters = {}      -- [Part] = 몬스터 데이터
local baffleXs = {}      -- 시선을 막는 "꺾임 벽"의 x 위치 (몬스터가 벽 속에 나타나지 않게 피하는 용도)
local baffleRects = {}   -- 꺾임 벽이 차지한 사각형 { X0, X1, Z0, Z1 } (몬스터 / 탄 / 사격이 벽을 통과하지 못하게 하는 용도)

-- 걸을 수 있는 곳인가 (꺾임 벽 안쪽이 아닌 곳)
local function walkableAt(x, z)
	for _, rect in ipairs(baffleRects) do
		if x >= rect.X0 - 1.5 and x <= rect.X1 + 1.5 and z >= rect.Z0 and z <= rect.Z1 then
			return false
		end
	end
	return true
end

-- a -> b 선분이 벽에 막히는가. 막히지 않으면 true, 막히면 false 와 마지막으로 열려 있던 지점
local function segmentClear(a, b)
	local delta = b - a
	local steps = math.ceil(delta.Magnitude / 4)
	local lastOpen = a
	for i = 1, steps do
		local p = a + delta * (i / steps)
		if not walkableAt(p.X, p.Z) then
			return false, lastOpen
		end
		lastOpen = p
	end
	return true, b
end

-- x 범위 안에서 꺾임 벽 위가 아닌 곳을 무작위로 고른다
local function freeX(minX, maxX)
	for _ = 1, 12 do
		local x = math.random(minX, maxX)
		local blocked = false
		for _, wallX in ipairs(baffleXs) do
			if math.abs(x - wallX) < 18 then
				blocked = true
				break
			end
		end
		if not blocked then
			return x
		end
	end
	return math.random(minX, maxX)
end
local projectiles = {}
local worldFolder, monstersFolder
local campCFrames = {}      -- [zone] = 캠프 부활/워프 위치
local lobbySpawn = CFrame.new(0, 5, 102)
local activeEvent = nil     -- { Part, Data }

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

-- 각 구역 입구의 캠프 주변 / 로비 쪽은 안전지대: 몬스터가 노리지 않고 탄도 맞지 않는다
local function isSafe(position)
	local relative = position.X - F.StartX
	if relative < 0 then return true end
	return relative % F.ZoneLength < F.CampSafe
end

local function nearestFieldPlayer(position)
	local nearest, nearestDist = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Zone") == "Field" then
			local root = getAliveParts(player)
			if root and not isSafe(root.Position) then
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

-- 구역마다 "1층 → 2층"으로 올라갔다 내려오는 단차가 있다 (구역 입구 / 캠프는 항상 0층). 몬스터 / 전리품 높이도 이 함수를 쓴다.
-- 점 목록 {구역 안 x 거리, 높이}: 평지 → 경사로 → 1층(7) → 경사로 → 2층(14) → 내려옴
local FLOOR_POINTS = { { 0, 0 }, { 120, 0 }, { 160, 7 }, { 300, 7 }, { 340, 14 }, { 480, 14 }, { 520, 7 }, { 600, 7 }, { 640, 0 }, { 700, 0 } }
local function floorAt(x)
	local offset = (x - F.StartX) % F.ZoneLength
	for i = 2, #FLOOR_POINTS do
		local a, b = FLOOR_POINTS[i - 1], FLOOR_POINTS[i]
		if offset <= b[1] then
			local t = (offset - a[1]) / math.max(1e-6, b[1] - a[1])
			return TOP + a[2] + (b[2] - a[2]) * t
		end
	end
	return TOP
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
	gui.MaxDistance = 160
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
	for _ = 1, 90 do
		local x = rng:NextNumber(x0 + F.CampSafe + 10, x1 - 12)
		local z = rng:NextNumber(-half + 6, half - 6)
		local position = Vector3.new(x, floorAt(x), z)

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

-- 계곡: 필드 양옆을 높고 거대한 절벽으로 막아서 바깥이 전혀 보이지 않게 한다
local function buildCanyon(rng, totalLength, half)
	local endX = F.StartX + totalLength

	-- 뒤에 깔아두는 끊김 없는 절벽 벽 (절벽 덩어리 사이로 바깥이 비치지 않게)
	for _, side in ipairs({ -1, 1 }) do
		makePart({
			Name = "CanyonBack", Size = Vector3.new(totalLength + 120, 170, 8),
			Position = Vector3.new(F.StartX + totalLength / 2, 85, side * (half + 34)),
			Color = Color3.fromRGB(55, 50, 58), Material = Enum.Material.Slate,
		}, worldFolder)

		-- 구역 색을 띤 크고 울퉁불퉁한 절벽 덩어리들
		local x = F.StartX - 10
		while x < endX + 20 do
			local zone = zoneOfX(math.clamp(x, F.StartX, endX - 1))
			local width = rng:NextNumber(34, 52)
			local height = rng:NextNumber(70, 135)
			local depth = rng:NextNumber(18, 30)
			local inner = half + rng:NextNumber(-4, 4)
			makePart({
				Name = "Cliff", Size = Vector3.new(width, height, depth),
				CFrame = CFrame.new(x, height / 2 - 2, side * (inner + depth / 2)) * CFrame.Angles(0, math.rad(rng:NextNumber(-6, 6)), 0),
				Color = F.ZoneColors[zone]:Lerp(Color3.fromRGB(70, 65, 72), 0.55),
				Material = Enum.Material.Slate,
			}, worldFolder)
			x += width * 0.8
		end
	end

	-- 필드 끝 / 로비에서 들어오는 통로 양옆도 절벽으로 막는다
	makePart({
		Name = "CanyonEnd", Size = Vector3.new(40, 170, F.Width + 90),
		Position = Vector3.new(endX + 20, 85, 0), Color = Color3.fromRGB(35, 30, 45), Material = Enum.Material.Slate,
	}, worldFolder)
	for _, side in ipairs({ -1, 1 }) do
		makePart({
			Name = "CanyonGate", Size = Vector3.new(34, 80, 50),
			Position = Vector3.new(F.StartX - 16, 40, side * (21 + 25)),
			Color = Color3.fromRGB(95, 110, 85), Material = Enum.Material.Slate,
		}, worldFolder)
	end
end

-- 구역 입구 캠프: 안전지대 + 워프 비콘 + 부활 지점
local function buildCamp(zone, x0)
	local center = Vector3.new(x0 + 40, TOP, 0)
	local accent = F.ZoneColors[zone]:Lerp(Color3.fromRGB(255, 255, 255), 0.35)

	makePart({
		Name = "CampFloor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 64, 64),
		CFrame = CFrame.new(center + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(120, 112, 100), Material = Enum.Material.Cobblestone,
	}, worldFolder)

	local beacon = makePart({
		Name = "CampBeacon", Size = Vector3.new(3, 26, 3), Position = center + Vector3.new(0, 13, 0),
		Color = accent, Material = Enum.Material.Neon,
	}, worldFolder)
	local light = Instance.new("PointLight")
	light.Range = 45
	light.Brightness = 1.6
	light.Color = accent
	light.Parent = beacon
	makeSign(beacon, "⛺ 캠프 · 워프", Color3.fromRGB(255, 240, 200), 18)

	for index = 0, 3 do
		local angle = math.rad(index * 90 + 45)
		local post = center + Vector3.new(math.cos(angle) * 24, 0, math.sin(angle) * 24)
		makePart({ Name = "CampPost", Size = Vector3.new(1, 8, 1), Position = post + Vector3.new(0, 4, 0), Color = Color3.fromRGB(70, 50, 38), Material = Enum.Material.Wood }, worldFolder)
		local flame = makePart({
			Name = "CampFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), Position = post + Vector3.new(0, 9, 0),
			Color = Color3.fromRGB(255, 150, 60), Material = Enum.Material.Neon, CanCollide = false,
		}, worldFolder)
		local flameLight = Instance.new("PointLight")
		flameLight.Range = 26
		flameLight.Color = Color3.fromRGB(255, 170, 90)
		flameLight.Parent = flame
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "워프 / 캠프"
	prompt.ObjectText = string.format("구역 %d 캠프", zone)
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 18
	prompt.RequiresLineOfSight = false
	prompt.Parent = beacon
	prompt.Triggered:Connect(function(player)
		Remotes.Warp:FireClient(player, "Open")
	end)

	campCFrames[zone] = CFrame.new(x0 + 40, TOP + 4, 16)
end

-- 구역 관문: 구역마다 컨셉이 다른 성문 / 입구. 문은 활짝 열려 있고, 이름 / 컨셉 / 몬스터 레벨이 위에 걸려 있다.
--   1 초원 목책 문 · 2 숲속 고성 정문 · 3 무너진 요새 · 4 사막 신전 · 5 얼음 궁전 · 6 용암 요새 · 7 암흑 성 · 8 심연의 문
local GATE_THEMES = {
	{ Tag = "🌾 모험의 시작", Wall = Color3.fromRGB(140, 105, 70), Mat = Enum.Material.Wood, Accent = Color3.fromRGB(255, 205, 90), Height = 24, Crenel = false },
	{ Tag = "🏰 숲속 고성 정문", Wall = Color3.fromRGB(105, 125, 105), Mat = Enum.Material.Brick, Accent = Color3.fromRGB(120, 230, 130), Height = 34, Crenel = true },
	{ Tag = "🏚 무너진 요새 관문", Wall = Color3.fromRGB(120, 105, 90), Mat = Enum.Material.Cobblestone, Accent = Color3.fromRGB(255, 170, 80), Height = 30, Crenel = true },
	{ Tag = "🏜 사막 신전 입구", Wall = Color3.fromRGB(205, 175, 110), Mat = Enum.Material.Sandstone, Accent = Color3.fromRGB(255, 215, 70), Height = 32, Crenel = false },
	{ Tag = "❄ 얼음 궁전 성문", Wall = Color3.fromRGB(180, 215, 235), Mat = Enum.Material.Ice, Accent = Color3.fromRGB(130, 220, 255), Height = 34, Crenel = true },
	{ Tag = "🌋 용암 요새 관문", Wall = Color3.fromRGB(70, 45, 42), Mat = Enum.Material.Basalt, Accent = Color3.fromRGB(255, 110, 40), Height = 34, Crenel = true },
	{ Tag = "🦇 암흑 성 정문", Wall = Color3.fromRGB(45, 38, 62), Mat = Enum.Material.Slate, Accent = Color3.fromRGB(170, 100, 255), Height = 40, Crenel = true },
	{ Tag = "🌀 심연의 문", Wall = Color3.fromRGB(28, 24, 40), Mat = Enum.Material.Slate, Accent = Color3.fromRGB(255, 70, 130), Height = 40, Crenel = false },
}

local function buildGateway(zone, x0)
	local theme = GATE_THEMES[zone]
	local half = F.Width / 2
	local open = 56            -- 열린 통로 폭 (로비 쪽 통로 40보다 넓게)
	local H = theme.Height
	local thick = 8
	local accent = theme.Accent

	local function part(name, size, position, color, material, extra)
		local props = { Name = name, Size = size, Position = position, Color = color or theme.Wall, Material = material or theme.Mat }
		for key, value in pairs(extra or {}) do
			props[key] = value
		end
		if props.CFrame then
			props.Position = nil -- CFrame 이 위치를 정한다 (둘 다 있으면 적용 순서가 불확실)
		end
		return makePart(props, worldFolder)
	end
	local function torch(position)
		local flame = part("GateFlame", Vector3.new(2.4, 2.4, 2.4), position, accent, Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
		local light = Instance.new("PointLight")
		light.Range = 36
		light.Brightness = 1.6
		light.Color = accent
		light.Parent = flame
	end

	for _, side in ipairs({ -1, 1 }) do
		-- 성벽 + 흉벽
		local length = half - open / 2
		local zc = side * (open / 2 + length / 2)
		part("GateWall", Vector3.new(thick, H, length), Vector3.new(x0 + 2, H / 2, zc))
		if theme.Crenel then
			for z = open / 2 + 8, half - 4, 12 do
				part("Crenel", Vector3.new(thick, 4, 6), Vector3.new(x0 + 2, H + 2, side * z))
			end
		end

		-- 문루(탑) + 지붕 띠 + 창
		local towerZ = side * (open / 2 + 8)
		part("GateTower", Vector3.new(16, H + 14, 16), Vector3.new(x0 + 2, (H + 14) / 2, towerZ))
		part("TowerCap", Vector3.new(19, 3, 19), Vector3.new(x0 + 2, H + 15.5, towerZ), accent, Enum.Material.Neon)
		part("TowerWindow", Vector3.new(1, 7, 3.5), Vector3.new(x0 + 10.4, H * 0.72, towerZ), accent, Enum.Material.Neon, { CanCollide = false })
		part("TowerWindow", Vector3.new(1, 7, 3.5), Vector3.new(x0 - 6.4, H * 0.72, towerZ), accent, Enum.Material.Neon, { CanCollide = false })
		torch(Vector3.new(x0 + 11, 15, side * (open / 2 - 1)))

		-- 활짝 열린 문짝: 통로 가장자리에 경첩을 두고 안쪽(+x)으로 거의 활짝 젖혀 놓는다
		if zone ~= 8 then
			local hinge = Vector3.new(x0 + 2, 0, side * (open / 2 - 0.5))
			local angle = math.rad(78)
			local doorLength = 26
			local vector = Vector3.new(math.sin(angle), 0, -side * math.cos(angle)) * doorLength
			local center = hinge + vector / 2 + Vector3.new(0, H * 0.45, 0)
			part("GateDoor", Vector3.new(2, H * 0.9, doorLength), center, theme.Wall:Lerp(Color3.fromRGB(60, 45, 35), 0.5), Enum.Material.Wood,
				{ CFrame = CFrame.lookAt(center, center + vector) })
			-- 문짝 장식 띠
			part("DoorBand", Vector3.new(2.2, 2, doorLength), center + Vector3.new(0, H * 0.25, 0), accent, Enum.Material.Neon,
				{ CFrame = CFrame.lookAt(center + Vector3.new(0, H * 0.25, 0), center + Vector3.new(0, H * 0.25, 0) + vector), CanCollide = false })
		end
	end

	-- 상인방(문 위 가로보) + 컨셉 장식
	if zone ~= 8 then
		part("GateLintel", Vector3.new(thick, 7, open + 2), Vector3.new(x0 + 2, H - 0.5, 0))
		part("LintelGlow", Vector3.new(thick + 0.4, 1.2, open + 2.4), Vector3.new(x0 + 2, H - 4.5, 0), accent, Enum.Material.Neon, { CanCollide = false })
	end

	if zone == 1 then -- 목책: 문 앞뒤로 말뚝 울타리 + 깃발
		for _, side in ipairs({ -1, 1 }) do
			for index = 0, 5 do
				part("Fence", Vector3.new(1.4, 6, 1.4), Vector3.new(x0 + 14 + index * 7, 3, side * (open / 2 + 14)))
			end
			part("FenceRail", Vector3.new(42, 1, 0.8), Vector3.new(x0 + 35, 4.5, side * (open / 2 + 14)))
			part("Banner", Vector3.new(0.4, 9, 5), Vector3.new(x0 + 2, H + 6, side * (open / 2 + 8)), Color3.fromRGB(210, 70, 60), Enum.Material.Fabric, { CanCollide = false })
		end
	elseif zone == 2 then -- 이끼 낀 성: 덩굴 + 녹색 깃발
		for _, side in ipairs({ -1, 1 }) do
			part("Banner", Vector3.new(0.4, 14, 6), Vector3.new(x0 + 11, H - 4, side * (open / 2 + 8)), Color3.fromRGB(50, 130, 70), Enum.Material.Fabric, { CanCollide = false })
			part("Moss", Vector3.new(thick + 0.3, 6, 22), Vector3.new(x0 + 2, H - 3, side * (open / 2 + 30)), Color3.fromRGB(60, 120, 60), Enum.Material.Grass, { CanCollide = false })
		end
	elseif zone == 3 then -- 폐허: 부러진 기둥 + 잔해
		for _, side in ipairs({ -1, 1 }) do
			part("BrokenPillar", Vector3.new(5, 16, 5), Vector3.new(x0 - 8, 8, side * (open / 2 + 28)), nil, nil, { CFrame = CFrame.new(x0 - 8, 8, side * (open / 2 + 28)) * CFrame.Angles(0, 0.4, math.rad(side * 14)) })
			part("Rubble", Vector3.new(7, 3.5, 6), Vector3.new(x0 + 16, 1.7, side * (open / 2 + 6)), nil, nil, { CFrame = CFrame.new(x0 + 16, 1.7, side * (open / 2 + 6)) * CFrame.Angles(0.2, 0.8, 0.1) })
		end
	elseif zone == 4 then -- 사막 신전: 오벨리스크
		for _, side in ipairs({ -1, 1 }) do
			part("Obelisk", Vector3.new(6, 42, 6), Vector3.new(x0 - 12, 21, side * (open / 2 + 34)))
			part("ObeliskTip", Vector3.new(4, 6, 4), Vector3.new(x0 - 12, 45, side * (open / 2 + 34)), accent, Enum.Material.Neon)
		end
	elseif zone == 5 then -- 얼음 궁전: 기울어진 얼음 첨탑
		for _, side in ipairs({ -1, 1 }) do
			for index = 1, 3 do
				local z = side * (open / 2 + 18 + index * 9)
				local height = 14 + index * 4
				part("IceSpike", Vector3.new(4, height, 4), Vector3.new(x0 + 6, height / 2, z), Color3.fromRGB(190, 230, 250), Enum.Material.Ice,
					{ CFrame = CFrame.new(x0 + 6, height / 2, z) * CFrame.Angles(0, 0, math.rad(side * -10)), Transparency = 0.25 })
			end
		end
	elseif zone == 6 then -- 용암 요새: 바닥 용암 줄기 + 불기둥
		for _, side in ipairs({ -1, 1 }) do
			part("LavaStream", Vector3.new(30, 0.4, 7), Vector3.new(x0 + 22, 0.25, side * (open / 2 + 5)), accent, Enum.Material.Neon, { CanCollide = false })
			torch(Vector3.new(x0 - 6, 22, side * (open / 2 + 20)))
		end
	elseif zone == 7 then -- 암흑 성: 보랏빛 룬과 박쥐 깃발
		for _, side in ipairs({ -1, 1 }) do
			part("Banner", Vector3.new(0.4, 18, 6), Vector3.new(x0 + 11, H - 2, side * (open / 2 + 8)), Color3.fromRGB(60, 25, 90), Enum.Material.Fabric, { CanCollide = false })
			part("FloatRune", Vector3.new(4, 4, 4), Vector3.new(x0 + 6, H + 26, side * 16), accent, Enum.Material.Neon, { CanCollide = false, CFrame = CFrame.new(x0 + 6, H + 26, side * 16) * CFrame.Angles(0.8, 0.6, 0.3) })
		end
	elseif zone == 8 then -- 심연의 문: 거대한 고리 + 빛나는 막
		local segments = 18
		local radius = 30
		for index = 0, segments - 1 do
			local angle = index / segments * math.pi * 2
			local position = Vector3.new(x0 + 2, 32 + math.sin(angle) * radius, math.cos(angle) * radius)
			part("PortalRing", Vector3.new(4, 7, 7), position, accent, Enum.Material.Neon, { CanCollide = false,
				CFrame = CFrame.new(position) * CFrame.Angles(angle, 0, 0) })
		end
		part("PortalVeil", Vector3.new(1, 50, 56), Vector3.new(x0 + 2, 27, 0), accent, Enum.Material.Neon, { Transparency = 0.85, CanCollide = false, CanQuery = false })
	end

	-- 관문 봉인막: 구역 2부터. 보이는 모습은 클라이언트(GoalClient)가 내 진행도에 맞춰 열고 닫는다 (서버는 위치로 막는다)
	if zone >= 2 then
		local seal = part("GateSeal", Vector3.new(1, H - 4, open), Vector3.new(x0 - 1, (H - 4) / 2, 0), accent, Enum.Material.Neon,
			{ Transparency = 0.45, CanCollide = false, CanQuery = false })
		seal:SetAttribute("SealZone", zone)
		CollectionService:AddTag(seal, "ZoneSeal")
		local gui = Instance.new("BillboardGui")
		gui.Name = "SealGui"
		gui.Size = UDim2.new(0, 340, 0, 90)
		gui.StudsOffset = Vector3.new(-6, 0, 0)
		gui.MaxDistance = 140
		gui.Parent = seal
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0
		label.Text = "🔒"
		label.Parent = gui
	end

	-- 간판: 구역 이름 + 컨셉 + 몬스터 레벨
	local signPart = part("GateSign", Vector3.new(1, 1, 1), Vector3.new(x0 + 2, H + 24, 0), accent, Enum.Material.Neon, { Transparency = 1, CanCollide = false, CanQuery = false })
	local zoneSet = Config.Sets[Config.Sets.ZoneKeys[zone]]
	makeSign(signPart, string.format("구역 %d · %s\n%s · 몬스터 Lv.%d\n%s 여기서만 드랍: %s 세트", zone, F.ZoneNames[zone], theme.Tag, F.GetZoneLevel(zone), zoneSet.Icon, zoneSet.Name), Color3.fromRGB(255, 240, 190), 0)
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
		-- 바닥: 평지 / 경사로 조각을 이어 붙인 "층" 지형
		for i = 2, #FLOOR_POINTS do
			local a, b = FLOOR_POINTS[i - 1], FLOOR_POINTS[i]
			local length = b[1] - a[1]
			local ax, bx = x0 + a[1], x0 + b[1]
			local tint = F.ZoneColors[zone]:Lerp(Color3.new(1, 1, 1), 0.07 * math.max(a[2], b[2]) / 7)
			if a[2] == b[2] then
				local top = TOP + a[2]
				makePart({
					Name = "Ground" .. zone, Size = Vector3.new(length, top + 1.95, F.Width),
					Position = Vector3.new((ax + bx) / 2, (top - 1.95) / 2, 0), Color = tint, Material = F.ZoneMaterials[zone],
				}, worldFolder)
			else -- 경사로: 기울어진 판 (위 표면이 두 높이를 잇는다) + 아래를 메우는 받침
				local ha, hb = TOP + a[2], TOP + b[2]
				local angle = math.atan2(hb - ha, length)
				local slabLength = math.sqrt(length * length + (hb - ha) ^ 2)
				local midX, midH = (ax + bx) / 2, (ha + hb) / 2
				makePart({
					Name = "Ramp" .. zone, Size = Vector3.new(slabLength, 2, F.Width),
					CFrame = CFrame.new(midX + math.sin(angle), midH - math.cos(angle), 0) * CFrame.Angles(0, 0, angle),
					Color = tint, Material = F.ZoneMaterials[zone],
				}, worldFolder)
				makePart({
					Name = "RampFill" .. zone, Size = Vector3.new(length, math.min(ha, hb) + 1.95, F.Width),
					Position = Vector3.new(midX, (math.min(ha, hb) - 1.95) / 2, 0), Color = tint, Material = F.ZoneMaterials[zone],
				}, worldFolder)
			end
		end

		buildGateway(zone, x0)

		decorateZone(zone, rng)
		buildCamp(zone, x0)
	end

	-- 꺾임 벽: 구역마다 벽 3개가 길을 가로막고, 틈이 위쪽 / 아래쪽 가장자리에 번갈아 뚫려 있다.
	-- 길이 ㄹ 자로 꺾이는 느낌이 나고, 멀리 있는 몬스터가 한눈에 다 보이지 않는다.
	do
		local gapSize = 64
		local side = 1
		for zone = 1, F.ZoneCount do
			local x0 = zoneBounds(zone)
			for _, offset in ipairs({ 230, 400, 570 }) do
				local wallLength = F.Width - gapSize
				local height = 110
				makePart({
					Name = "Baffle", Size = Vector3.new(22, height, wallLength),
					Position = Vector3.new(x0 + offset, height / 2 - 2, -side * gapSize / 2),
					Color = F.ZoneColors[zone]:Lerp(Color3.fromRGB(70, 65, 72), 0.5), Material = Enum.Material.Slate,
				}, worldFolder)
				-- 틈 쪽을 알리는 빛 기둥 (이쪽으로 지나가라는 표시)
				local marker = makePart({
					Name = "BaffleGlow", Size = Vector3.new(3, 30, 3), Position = Vector3.new(x0 + offset, 15, side * (half - gapSize / 2)),
					Color = F.ZoneColors[zone]:Lerp(Color3.new(1, 1, 1), 0.55), Material = Enum.Material.Neon, CanCollide = false,
				}, worldFolder)
				local glow = Instance.new("PointLight")
				glow.Range = 40
				glow.Brightness = 1.4
				glow.Color = marker.Color
				glow.Parent = marker
				table.insert(baffleXs, x0 + offset)
				local zCenter = -side * gapSize / 2
				table.insert(baffleRects, { X0 = x0 + offset - 11, X1 = x0 + offset + 11, Z0 = zCenter - wallLength / 2, Z1 = zCenter + wallLength / 2 })
				side = -side
			end
		end
	end

	buildCanyon(rng, totalLength, half)

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
	gui.MaxDistance = 110 -- 멀리 있는 몬스터 체력바가 다 보이지 않게
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
	local typeKey, def, xpLevel

	if kind == "Boss" then
		local boss = F.Boss
		stats = {
			Size = boss.Size, MaxHealth = boss.MaxHealth, Speed = boss.Speed, ShotDamage = boss.ShotDamage,
			ShotInterval = boss.ShotInterval, ShotSpeed = boss.ShotSpeed, Gold = boss.Gold,
		}
		text, color, barWidth = "👑 " .. boss.Name, Color3.fromRGB(255, 120, 120), 300
	else
		-- 구역마다 나오는 몬스터 종류가 다르다 (Config.Field.ZonePools)
		typeKey = MonsterTypes.Pick(F.ZonePools[zone])
		def = MonsterTypes.Defs[typeKey]
		if kind == "Elite" then
			xpLevel = level + 2
			stats = Config.Monster.GetStats(xpLevel)
			MonsterTypes.ApplyDef(typeKey, stats)
			stats.MaxHealth = math.floor(stats.MaxHealth * F.EliteMultiplier)
			stats.Size = stats.Size * 1.5
			stats.Gold *= 4
			text, color, barWidth = string.format("★ 엘리트 Lv.%d %s", xpLevel, def.Name), Color3.fromRGB(255, 220, 90), 190
		else
			xpLevel = level
			stats = Config.Monster.GetStats(level)
			MonsterTypes.ApplyDef(typeKey, stats)
			text, color, barWidth = string.format("Lv.%d %s", level, def.Name), Color3.new(1, 1, 1), 140
		end
		-- 구역 난이도 배율: 구역이 넘어가면 몬스터가 확 강해진다 (체력 / 공격력 / 속도) 대신 보상도 크게 오른다
		local danger = F.ZoneDanger
		stats.MaxHealth = math.floor(stats.MaxHealth * danger.Health[zone])
		stats.ShotDamage = math.max(1, math.floor(stats.ShotDamage * danger.Damage[zone]))
		stats.Speed *= danger.Speed[zone]
		stats.Gold = math.floor(stats.Gold * danger.Reward[zone])
	end

	local x0, x1 = zoneBounds(zone)
	local position
	if kind == "Boss" then
		position = Vector3.new(x1 - 45, floorAt(x1 - 45) + stats.Size / 2, 0)
	else
		local spawnX = freeX(math.floor(x0 + F.CampSafe + 40), math.floor(x1 - 25))
		position = Vector3.new(spawnX, floorAt(spawnX) + stats.Size / 2, math.random(-F.Width / 2 + 25, F.Width / 2 - 25))
	end

	local part
	if kind == "Boss" then
		part = Instance.new("Part")
		part.Name = "FieldBoss"
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(stats.Size, stats.Size, stats.Size)
		part.Anchored = true
		part.CanCollide = false
		part.Position = position
		part.Color = Color3.fromRGB(150, 25, 45)
		part.Material = Enum.Material.Neon
		part.Parent = monstersFolder
		CollectionService:AddTag(part, "Monster")
		CollectionService:AddTag(part, "RadarBoss")
	else
		local baseColor = def.Color:Lerp(F.ZoneColors[zone], 0.2)
		if kind == "Elite" then
			baseColor = def.Color:Lerp(Color3.fromRGB(240, 190, 50), 0.45)
		end
		part = MonsterTypes.Build(typeKey, stats.Size, baseColor, position, monstersFolder)
		part.Name = "FieldMonster"
		if kind == "Elite" then
			CollectionService:AddTag(part, "RadarElite")
		end
	end

	monsters[part] = {
		BossLike = kind == "Boss",
		Zone = zone,
		Kind = kind,
		Level = level,
		XpLevel = xpLevel,
		TypeKey = typeKey,
		Def = def,
		Phase = math.random() * math.pi * 2,
		Stats = stats,
		Health = stats.MaxHealth,
		MaxHealth = stats.MaxHealth,
		HealthFill = createHealthBar(part, text, barWidth, color),
		Home = position,
		NextAttack = os.clock() + stats.ShotInterval,
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

local function dropPosition(part)
	return Vector3.new(part.Position.X, floorAt(part.Position.X), part.Position.Z)
end

-- 공개 이벤트 보스 보상: 충분히 싸운(체력의 3% 이상 피해) 참가자 모두에게 골드 / 경험치 / 티켓 / 전리품
local function rewardEvent(data, part)
	local position = dropPosition(part)
	local rewarded = 0
	for player, damage in pairs(data.Contrib) do
		if player.Parent and damage >= data.MaxHealth * Config.Events.ContribMin then
			rewarded += 1
			player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + data.Stats.Gold)
			player:SetAttribute("Tickets", (player:GetAttribute("Tickets") or 0) + 1)
			Level.AddXP(player, Config.Xp.FieldBoss * 1.5)
			Quest.Add(player, "BossKills", 1)
			Quest.Add(player, "Kills", 1)
			Loot.DropFor(player, position, "Event", data.Zone)
			notify(player, string.format("⚔ 공개 이벤트 승리! 전리품이 떨어졌어요 (+%d G, 🎫 +1)", data.Stats.Gold))
		end
	end
	for _, other in ipairs(Players:GetPlayers()) do
		notify(other, string.format("🏆 침공 사령관 격파! (참여 %d명)", rewarded))
	end
end

-- 황금 고블린: 잡으면 골드 대박 + 전리품 3개
local function rewardGoblin(player, data, part)
	local gold = data.Stats.Gold
	player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + gold)
	Effects.FloatText(part.Position + Vector3.new(0, 4, 0), string.format("💰 +%d G", gold), Color3.fromRGB(255, 225, 80))
	Effects.Burst(part.Position, Color3.fromRGB(255, 215, 60), 90)
	Level.AddXP(player, Config.Xp.FieldPerMonsterLevel * data.XpLevel * 6)
	local position = dropPosition(part)
	for _ = 1, 3 do
		Loot.DropFor(player, position, "Elite", data.Zone)
	end
	Quest.Add(player, "Kills", 1)
	Quest.Add(player, "GoblinKills", 1)
	notify(player, string.format("💰 황금 고블린 처치! +%d G, 전리품 3개!", gold))
end

-- 구역 관문: 지금 막 열어야 하는 구역(ClearedZone+1)에서 몬스터를 처치하면 진행도가 오르고, 다 채우면 다음 구역이 열린다
local function gateProgress(player, data)
	local cleared = player:GetAttribute("ClearedZone") or 0
	local frontier = cleared + 1
	local needed = F.Gate.KillsNeeded[frontier]
	if not needed or data.Zone ~= frontier then return end
	local weight = data.Kind == "Elite" and F.Gate.EliteWeight or (data.Kind == "Boss" and F.Gate.BossWeight or 1)
	local kills = (player:GetAttribute("GateKills") or 0) + weight
	if kills < needed then
		player:SetAttribute("GateKills", kills)
		return
	end
	player:SetAttribute("GateKills", 0)
	player:SetAttribute("ClearedZone", frontier)
	local gold = F.Gate.RewardGold * frontier
	local tickets = F.Gate.RewardTickets + (frontier >= 3 and 1 or 0)
	player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + gold)
	player:SetAttribute("Tickets", (player:GetAttribute("Tickets") or 0) + tickets)
	local nextSet = Config.Sets[Config.Sets.ZoneKeys[frontier + 1]]
	notify(player, string.format("🔓 구역 %d 관문 개방! 보상 💰%d G · 🎫%d장  — %s · %s 에서만 %s %s 세트 장비가 나와요!", frontier + 1, gold, tickets, F.ZoneNames[frontier + 1], F.ZoneNames[frontier + 1], nextSet.Icon, nextSet.Name))
	local root = getAliveParts(player)
	if root then
		Effects.Burst(root.Position, Color3.fromRGB(255, 225, 100), 60)
	end
end

local function reward(player, data, part)
	if data.Kind == "Goblin" then
		rewardGoblin(player, data, part)
		return
	end
	if data.Kind == "Event" then
		rewardEvent(data, part)
		return
	end

	local gold = math.floor(data.Stats.Gold * (Config.IsGoldenTime() and Config.Golden.GoldMult or 1) + 0.5)
	player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + gold)
	Effects.FloatText(part.Position + Vector3.new(0, part.Size.Y / 2, 0), string.format("+%d G", gold), Color3.fromRGB(255, 220, 90))

	local xp
	if data.Kind == "Boss" then
		xp = Config.Xp.FieldBoss
	else
		xp = Config.Xp.FieldPerMonsterLevel * data.XpLevel * (data.Kind == "Elite" and Config.Xp.EliteMult or 1)
	end
	Level.AddXP(player, xp)

	gateProgress(player, data)
	Quest.Add(player, "Kills", 1)
	if data.Kind == "Elite" then
		Quest.Add(player, "EliteKills", 1)
	elseif data.Kind == "Boss" then
		Quest.Add(player, "BossKills", 1)
	else
		Quest.Add(player, "FieldKills", 1)
	end

	-- 장비 전리품 (개인 전리품: 처치한 본인에게만 보임)
	if data.Kind ~= "Boss" then
		Loot.DropFor(player, dropPosition(part), data.Kind, data.Zone)
	end

	if data.Kind == "Elite" and math.random() < F.EliteTicketChance then
		player:SetAttribute("Tickets", (player:GetAttribute("Tickets") or 0) + 1)
		notify(player, "🎫 엘리트에게서 장비 뽑기 티켓을 얻었어요!")
	elseif data.Kind == "Boss" then
		local bossPosition = part.Position
		for _, other in ipairs(Players:GetPlayers()) do
			local root = getAliveParts(other)
			if other:GetAttribute("Zone") == "Field" and root and (root.Position - bossPosition).Magnitude <= 160 then
				other:SetAttribute("Tickets", (other:GetAttribute("Tickets") or 0) + F.BossTickets)
				Loot.DropFor(other, dropPosition(part), "Boss", data.Zone)
				if other ~= player then
					Quest.Add(other, "BossKills", 1)
					Level.AddXP(other, Config.Xp.FieldBoss)
				end
				notify(other, string.format("👑 필드 보스 처치! 티켓 +%d, 전리품이 떨어졌어요", F.BossTickets))
			end
		end
	end
end

local function killMonster(player, part, data)
	monsters[part] = nil
	Effects.Burst(part.Position, part.Color, data.Kind == "Boss" and 80 or 22)
	part:Destroy()
	Combo.Kill(player)
	reward(player, data, part)

	local zone, kind = data.Zone, data.Kind
	if kind == "Goblin" then return end -- 다시 나타나지 않는다 (다음 출현은 타이머)
	if kind == "Event" then
		activeEvent = nil -- 이벤트 보스는 다시 나타나지 않는다
		return
	end
	task.delay(kind == "Boss" and F.BossRespawn or F.RespawnTime, function()
		spawnMonster(zone, kind)
	end)
end

------------------------------------------------------------
-- 플레이어 공격 (판정은 서버에서). 필드 밖이면 nil
------------------------------------------------------------
-- 범위 피해 (스킬용). 맞은 위치 목록 반환
function Field.TargetsIn(player, center, radius, limit)
	if player:GetAttribute("Zone") ~= "Field" then return nil end
	local list = {}
	for part in pairs(monsters) do
		if part.Parent and (part.Position - center).Magnitude <= radius + part.Size.X / 2 then
			table.insert(list, part)
		end
	end
	table.sort(list, function(a, b) return (a.Position - center).Magnitude < (b.Position - center).Magnitude end)
	while #list > (limit or 12) do table.remove(list) end
	return list
end

function Field.HitPart(player, part, damage)
	local data = monsters[part]
	if not data or not part.Parent then return false end
	data.Health -= damage
	data.LastHit = os.clock()
	if data.Contrib then
		data.Contrib[player] = (data.Contrib[player] or 0) + damage
	end
	data.HealthFill.Size = UDim2.new(math.max(data.Health, 0) / data.MaxHealth, 0, 1, 0)
	Effects.DamageNumber(part.Position, damage, false)
	if data.Health <= 0 then
		killMonster(player, part, data)
	end
	return true
end

function Field.AreaDamage(player, center, radius, damage)
	if player:GetAttribute("Zone") ~= "Field" then return nil end
	local targets = {}
	for part, data in pairs(monsters) do
		if part.Parent and (part.Position - center).Magnitude <= radius + part.Size.X / 2 then
			table.insert(targets, { Part = part, Data = data })
		end
	end
	local positions = {}
	for _, target in ipairs(targets) do
		local data = target.Data
		if monsters[target.Part] == data then
			table.insert(positions, target.Part.Position)
			data.Health -= damage
			data.LastHit = os.clock()
			if data.Contrib then
				data.Contrib[player] = (data.Contrib[player] or 0) + damage
			end
			data.HealthFill.Size = UDim2.new(math.max(data.Health, 0) / data.MaxHealth, 0, 1, 0)
			Effects.DamageNumber(target.Part.Position, damage, false)
			if data.Health <= 0 then
				killMonster(player, target.Part, data)
			end
		end
	end
	return positions
end

function Field.Shoot(player, origin, direction)
	if player:GetAttribute("Zone") ~= "Field" or not monstersFolder then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { monstersFolder }

	local range = Config.GetPlayerWeapon(player).Range
	local result = workspace:Raycast(origin, direction * range, params)
	local endPosition = result and result.Position or (origin + direction * range)
	-- 도중에 벽이 있으면 거기서 멈추고 맞히지 못한다
	local clear, stopAt = segmentClear(origin, endPosition)
	if not clear then
		return stopAt
	end

	local data = result and monsters[result.Instance]
	if data then
		local damage, isCrit = Dungeon.ComputeDamage(player)
		-- 로켓 런처 / 플라즈마 캐논: 맞은 곳 주변 적에게도 피해
		local splash = Config.GetPlayerWeapon(player).Splash
		if splash then
			for otherPart, otherData in pairs(monsters) do
				if otherPart ~= result.Instance and otherPart.Parent and not otherData.Goblin
					and (otherPart.Position - result.Position).Magnitude <= splash + otherPart.Size.X / 2 then
					local splashDamage = math.max(1, math.floor(damage * 0.5))
					otherData.Health -= splashDamage
					otherData.LastHit = os.clock()
					if otherData.Contrib then
						otherData.Contrib[player] = (otherData.Contrib[player] or 0) + splashDamage
					end
					otherData.HealthFill.Size = UDim2.new(math.max(otherData.Health, 0) / otherData.MaxHealth, 0, 1, 0)
					Effects.DamageNumber(otherPart.Position, splashDamage, false)
					if otherData.Health <= 0 then
						killMonster(player, otherPart, otherData)
					end
				end
			end
			Effects.Burst(result.Position, Color3.fromRGB(255, 160, 60), 40)
		end
		data.Health -= damage
		data.LastHit = os.clock() -- 맞은 몬스터는 멀리서 맞아도 깨어나 반응하고, 한동안 체력을 되찾지 않는다
		if data.Contrib then
			data.Contrib[player] = (data.Contrib[player] or 0) + damage
		end
		data.HealthFill.Size = UDim2.new(math.max(data.Health, 0) / data.MaxHealth, 0, 1, 0)
		Effects.DamageNumber(result.Position, damage, isCrit)
		Effects.Hit(player, result.Instance, isCrit, data.Health <= 0)
		if data.Health <= 0 then
			killMonster(player, result.Instance, data)
		end
	end
	return endPosition
end

------------------------------------------------------------
-- 매 프레임: 몬스터 AI / 투사체 / 구역 갱신
------------------------------------------------------------
-- 몬스터 AI(MonsterTypes)가 필드 환경을 다루는 데 쓰는 함수들
local fieldCtx = {
	FloorY = TOP,
	GroundY = function(x) return floorAt(x) end, -- 층 지형에 맞춰 몬스터 높이를 잡는다
	Walkable = walkableAt,
	LineOfSight = function(a, b)
		return (segmentClear(a, b))
	end,
	-- 꺾임 벽이 막고 있으면 그 벽의 틈(위 / 아래 가장자리)을 먼저 지나가도록 안내한다
	NextStep = function(_, from, to)
		local clear, blockedAt = segmentClear(from, to)
		if clear then return nil end
		local half = F.Width / 2
		for _, rect in ipairs(baffleRects) do
			if blockedAt.X >= rect.X0 - 6 and blockedAt.X <= rect.X1 + 6 then
				local gapZ
				if rect.Z1 < half - 1 then
					gapZ = (rect.Z1 + half) / 2 -- 벽 위쪽 끝에 틈
				else
					gapZ = (-half + rect.Z0) / 2 -- 벽 아래쪽 끝에 틈
				end
				return Vector3.new((rect.X0 + rect.X1) / 2, from.Y, gapZ)
			end
		end
		return nil
	end,
	GetTarget = nearestFieldPlayer,
	Fire = function(origin, direction, speed, damage, size, color)
		fireProjectile(origin, direction, speed, damage, size, color)
	end,
	Players = function()
		local list = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("Zone") == "Field" then
				local root, humanoid = getAliveParts(player)
				if root and not isSafe(root.Position) then
					table.insert(list, { Root = root, Humanoid = humanoid })
				end
			end
		end
		return list
	end,
	Alive = function(part, data)
		return monsters[part] == data
	end,
	Kill = function(part, data) -- 자폭 등 보상 없이 사라짐 (다시 나타남)
		if monsters[part] ~= data then return end
		monsters[part] = nil
		part:Destroy()
		task.delay(F.RespawnTime, function()
			spawnMonster(data.Zone, data.Kind)
		end)
	end,
}

-- 황금 고블린 소환: 구역 하나에 나타나 플레이어에게서 도망친다. 일정 시간이 지나면 사라진다.
local function spawnGoblin(zone)
	local level = F.GetZoneLevel(zone)
	local base = Config.Monster.GetStats(level)
	local stats = {
		Size = 5, MaxHealth = base.MaxHealth * 7, Speed = 26, ShotDamage = 0, ShotInterval = 99, ShotSpeed = 0,
		Gold = base.Gold * 40,
	}
	local x0, x1 = zoneBounds(zone)
	local goblinX = freeX(math.floor(x0 + F.CampSafe + 60), math.floor(x1 - 40))
	local position = Vector3.new(goblinX, floorAt(goblinX) + stats.Size / 2, math.random(-F.Width / 2 + 30, F.Width / 2 - 30))
	local part = Instance.new("Part")
	part.Name = "GoldenGoblin"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(stats.Size, stats.Size, stats.Size)
	part.Anchored = true
	part.CanCollide = false
	part.Position = position
	part.Color = Color3.fromRGB(255, 205, 40)
	part.Material = Enum.Material.Neon
	part.Parent = monstersFolder
	CollectionService:AddTag(part, "Monster")
	CollectionService:AddTag(part, "RadarGold")
	local light = Instance.new("PointLight")
	light.Range = 26
	light.Brightness = 2
	light.Color = part.Color
	light.Parent = part

	local data = {
		Zone = zone, Kind = "Goblin", Goblin = true, Level = level, XpLevel = level + 2, Stats = stats,
		Health = stats.MaxHealth, MaxHealth = stats.MaxHealth, Contrib = {},
		HealthFill = createHealthBar(part, "💰 황금 고블린", 200, Color3.fromRGB(255, 225, 80)),
		Home = position, Expire = os.clock() + 75, NextShot = math.huge, NextAttack = math.huge, NextRing = math.huge,
		BaseColor = part.Color, Aggro = false, Phase = math.random() * 6,
	}
	monsters[part] = data
	return part, data
end

-- 고블린 이동: 가까운 플레이어에게서 도망 (좌우로 흔들리며)
local function stepGoblin(part, data, dt, now)
	if now > data.Expire then
		monsters[part] = nil
		part:Destroy()
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("Zone") == "Field" then
				notify(player, "💨 황금 고블린이 도망쳐 버렸어요...")
			end
		end
		return
	end
	local target, distance = nearestFieldPlayer(part.Position)
	local flee = Vector3.zero
	if target and distance < 80 then
		local away = Vector3.new(part.Position.X - target.Position.X, 0, part.Position.Z - target.Position.Z)
		if away.Magnitude > 0.1 then
			local side = Vector3.new(-away.Unit.Z, 0, away.Unit.X)
			flee = (away.Unit + side * math.sin(now * 3 + data.Phase) * 0.6).Unit * data.Stats.Speed * dt
		end
	end
	local x0, x1 = zoneBounds(data.Zone)
	local position = part.Position + flee
	position = Vector3.new(
		math.clamp(position.X, x0 + F.CampSafe + 10, x1 - 10), floorAt(math.clamp(position.X, x0 + F.CampSafe + 10, x1 - 10)) + data.Stats.Size / 2 + math.abs(math.sin(now * 6)) * 1.2,
		math.clamp(position.Z, -F.Width / 2 + 12, F.Width / 2 - 12)
	)
	part.Position = position
end

local function stepMonsters(dt)
	local now = os.clock()
	for part, data in pairs(monsters) do
		if data.Goblin then
			stepGoblin(part, data, dt, now)
			continue
		end
		local target, distance = nearestFieldPlayer(part.Position)
		local range = data.Aggro and F.LeashRange or F.AggroRange
		local fromHome = (part.Position - data.Home).Magnitude
		-- 최근에 맞았으면(저격 / 장거리 사격 포함) 거리와 상관없이 깨어나서 반응한다
		local recentlyHit = data.LastHit ~= nil and now - data.LastHit < 8

		if target and (distance <= range or recentlyHit) and fromHome <= F.LeashRange * 1.5 then
			data.Aggro = true

			if not data.BossLike then
				-- 일반 몬스터 / 엘리트: 종류별 움직임과 공격
				MonsterTypes.Update(fieldCtx, part, data, dt, now)
			else
				local keepDistance = data.Stats.Size / 2 + 16
				if distance > keepDistance then
					local flatTarget = Vector3.new(target.Position.X, part.Position.Y, target.Position.Z)
					local move = flatTarget - part.Position
					if move.Magnitude > 0.1 then
						local step = move.Unit * data.Stats.Speed * dt
						if walkableAt(part.Position.X + step.X, part.Position.Z + step.Z) then
							part.Position += step
						end
					end
				end

				if now >= data.NextShot then
					data.NextShot = now + data.Stats.ShotInterval
					telegraph(part, data, Color3.fromRGB(255, 220, 80), 0.4, function()
						local current = nearestFieldPlayer(part.Position)
						if not current then return end
						local direction = current.Position - part.Position
						for _, angle in ipairs({ -20, -10, 0, 10, 20 }) do
							fireProjectile(part.Position, rotateY(direction.Unit, angle), data.Stats.ShotSpeed, data.Stats.ShotDamage, 3, Color3.fromRGB(255, 80, 60))
						end
					end)
				end

				-- 보스: 주기적으로 전방위 탄막
				if now >= data.NextRing then
					data.NextRing = now + 7
					telegraph(part, data, Color3.new(1, 1, 1), 0.8, function()
						for i = 0, 15 do
							local angle = (i / 16) * math.pi * 2
							local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
							fireProjectile(Vector3.new(part.Position.X, floorAt(part.Position.X) + 3, part.Position.Z) + direction * (part.Size.X / 2 + 1), direction, 30, math.floor(data.Stats.ShotDamage * 0.7), 2.4, Color3.fromRGB(255, 180, 60))
						end
					end)
				end
			end
		elseif recentlyHit then
			-- 너무 멀리 끌려 나왔지만 아직 맞고 있는 중: 체력을 회복하지 않고 가만히 있는다
			data.Aggro = true
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

		local hit = not walkableAt(projectile.Part.Position.X, projectile.Part.Position.Z) -- 벽에 닿은 탄은 사라진다
		for _, player in ipairs(Players:GetPlayers()) do
			if hit then break end
			if player:GetAttribute("Zone") == "Field" then
				local root, humanoid = getAliveParts(player)
				if root and not isSafe(root.Position) and (root.Position - projectile.Part.Position).Magnitude < projectile.Radius + 2 then
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
local lastGateNotice = {}
local lastZoneSeen = {}
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
					-- 관문이 잠긴 구역에는 못 들어간다: 관문 앞으로 되돌려 보낸다
					local allowed = math.min(F.ZoneCount, (player:GetAttribute("ClearedZone") or 0) + 1)
					if fieldZone > allowed then
						local lockedX = zoneBounds(allowed + 1)
						player.Character:PivotTo(CFrame.new(lockedX - 12, TOP + 4, root.Position.Z))
						root.AssemblyLinearVelocity = Vector3.zero
						if os.clock() - (lastGateNotice[player] or 0) > 3 then
							lastGateNotice[player] = os.clock()
							notify(player, string.format("🔒 관문이 닫혀 있어요! 구역 %d 몬스터를 %d마리 처치하세요 (%d/%d)",
								allowed, F.Gate.KillsNeeded[allowed] or 0, player:GetAttribute("GateKills") or 0, F.Gate.KillsNeeded[allowed] or 0))
						end
						fieldZone = allowed
					end
					-- 새 구역에 들어서면 큰 경고 배너 (난이도가 얼마나 뛰는지 숫자로 보여준다)
					if fieldZone ~= lastZoneSeen[player] then
						local previous = lastZoneSeen[player] or 0
						lastZoneSeen[player] = fieldZone
						if fieldZone >= 2 and fieldZone > previous then
							local danger = F.ZoneDanger
							Remotes.Banner:FireClient(player, "Zone", {
								Zone = fieldZone, Name = F.ZoneNames[fieldZone], Level = F.GetZoneLevel(fieldZone), Stars = fieldZone,
								HealthMult = danger.Health[fieldZone] / danger.Health[fieldZone - 1], DamageMult = danger.Damage[fieldZone] / danger.Damage[fieldZone - 1],
								RewardMult = danger.Reward[fieldZone] / danger.Reward[fieldZone - 1],
							})
						end
					end
					if fieldZone > (player:GetAttribute("MaxZone") or 0) then
						player:SetAttribute("MaxZone", fieldZone)
						notify(player, string.format("🏔 구역 %d · %s 돌파!", fieldZone, F.ZoneNames[fieldZone]))
					end
				end
			end
		end
	end
end

------------------------------------------------------------
-- 워프 / 부활 (캠프)
------------------------------------------------------------
function Field.ZoneOf(player)
	if player:GetAttribute("Zone") ~= "Field" then return 0 end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root and zoneOfX(root.Position.X) or 0
end

-- 필드에서 죽으면 가장 가까웠던 구역의 캠프에서 부활 (로비로 돌아가 다시 걸어오지 않아도 됨)
function Field.RespawnAtCamp(player, character, zone)
	local camp = campCFrames[zone]
	if not camp then return end
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if root then
		character:PivotTo(camp)
		player:SetAttribute("Zone", "Field")
	end
end

local lastWarp = {}

-- zone 0 = 로비, 1~8 = 해당 구역 캠프 (도달한 구역까지만)
local function warp(player, zone)
	local now = os.clock()
	if now - (lastWarp[player] or 0) < 3 then return end
	if typeof(zone) ~= "number" or zone % 1 ~= 0 or zone < 0 or zone > F.ZoneCount then return end
	if player:GetAttribute("Zone") == "Dungeon" then
		notify(player, "던전 안에서는 워프할 수 없어요.")
		return
	end
	local root = getAliveParts(player)
	if not root then return end

	if zone >= 1 and zone > math.max(1, math.min(player:GetAttribute("MaxZone") or 0, (player:GetAttribute("ClearedZone") or 0) + 1)) then
		notify(player, "아직 도달하지 않은 구역이에요. 걸어서 먼저 가보세요!")
		return
	end

	lastWarp[player] = now
	if zone == 0 then
		player.Character:PivotTo(lobbySpawn)
		player:SetAttribute("Zone", "Lobby")
		notify(player, "마을로 돌아왔어요.")
	else
		player.Character:PivotTo(campCFrames[zone])
		player:SetAttribute("Zone", "Field")
		notify(player, string.format("⛺ 구역 %d · %s 캠프로 이동!", zone, F.ZoneNames[zone]))
	end
end

Remotes.Warp.OnServerEvent:Connect(function(player, action, zone)
	if action == "Go" then
		warp(player, zone)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastWarp[player] = nil
end)

------------------------------------------------------------
-- 공개 이벤트: 침공 사령관
------------------------------------------------------------
local function spawnEvent(zone)
	local level = F.GetZoneLevel(zone) + 3
	local base = Config.Monster.GetStats(level)
	local stats = {
		Size = 15, MaxHealth = base.MaxHealth * 80, Speed = 7, ShotDamage = math.floor(base.ShotDamage * 1.3),
		ShotInterval = 1.4, ShotSpeed = 55, Gold = base.Gold * 30,
	}

	local x0, x1 = zoneBounds(zone)
	local eventX = freeX(math.floor(x0 + 200), math.floor(x1 - 80))
	local position = Vector3.new(eventX, floorAt(eventX) + stats.Size / 2, math.random(-F.Width / 2 + 70, F.Width / 2 - 70))

	local part = Instance.new("Part")
	part.Name = "EventBoss"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(stats.Size, stats.Size, stats.Size)
	part.Anchored = true
	part.CanCollide = false
	part.Position = position
	part.Color = Color3.fromRGB(190, 60, 255)
	part.Material = Enum.Material.Neon
	part.Parent = monstersFolder
	CollectionService:AddTag(part, "Monster")
	CollectionService:AddTag(part, "RadarBoss")

	-- 멀리서도 보이는 하늘로 솟는 빛기둥 (보스에 붙어서 같이 움직임)
	local beam = Instance.new("Part")
	beam.Size = Vector3.new(3, 420, 3)
	beam.Color = Color3.fromRGB(200, 90, 255)
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.45
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Massless = true
	beam.CFrame = part.CFrame * CFrame.new(0, 210, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = beam
	weld.Parent = beam
	beam.Parent = part

	local data = {
		BossLike = true,
		Kind = "Event",
		Zone = zone,
		Level = level,
		XpLevel = level,
		Stats = stats,
		Health = stats.MaxHealth,
		MaxHealth = stats.MaxHealth,
		HealthFill = createHealthBar(part, string.format("⚔ %s (구역 %d)", Config.Events.Name, zone), 320, Color3.fromRGB(230, 150, 255)),
		Home = position,
		NextAttack = os.clock() + 3,
		NextShot = os.clock() + 3,
		NextRing = os.clock() + 6,
		BaseColor = part.Color,
		Aggro = false,
		Contrib = {},
	}
	monsters[part] = data
	return part, data
end

local function runEvents()
	task.wait(Config.Events.FirstDelay)
	while true do
		-- 필드에 사람이 있을 때만 이벤트를 연다 (도달한 구역 중에서 무작위)
		local maxZone, anyone = 1, false
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("Zone") == "Field" then
				anyone = true
				maxZone = math.max(maxZone, player:GetAttribute("MaxZone") or 1)
			end
		end

		if anyone then
			local zone = math.random(1, math.min(maxZone, F.ZoneCount))
			local part, data = spawnEvent(zone)
			activeEvent = { Part = part, Data = data }
			for _, player in ipairs(Players:GetPlayers()) do
				notify(player, string.format("⚔ [공개 이벤트] 구역 %d · %s 에 %s 출현! 하늘의 보라색 빛기둥을 따라가세요!", zone, F.ZoneNames[zone], Config.Events.Name))
			end

			local expire = os.clock() + Config.Events.Lifetime
			while monsters[part] == data and os.clock() < expire do
				task.wait(1)
			end
			if monsters[part] == data then
				monsters[part] = nil
				part:Destroy()
				activeEvent = nil
				for _, player in ipairs(Players:GetPlayers()) do
					notify(player, "침공 사령관이 사라졌어요...")
				end
			end
		end

		task.wait(math.random(Config.Events.MinInterval, Config.Events.MaxInterval))
	end
end

-- 황금 고블린 출현 타이머: 필드에 누군가 있으면 몇 분마다 한 마리
local function runGoblins()
	task.wait(90)
	while true do
		local maxZone, anyone = 1, false
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("Zone") == "Field" then
				anyone = true
				maxZone = math.max(maxZone, player:GetAttribute("MaxZone") or 1)
			end
		end
		if anyone then
			local zone = math.random(1, math.min(maxZone, F.ZoneCount))
			local part, data = spawnGoblin(zone)
			for _, player in ipairs(Players:GetPlayers()) do
				if player:GetAttribute("Zone") == "Field" then
					notify(player, string.format("💰 구역 %d · %s 에 황금 고블린 출현! 잡으면 대박! (75초)", zone, F.ZoneNames[zone]))
				end
			end
			while monsters[part] == data do
				task.wait(1)
			end
		end
		task.wait(math.random(150, 300))
	end
end

function Field.Init(lobbySpawnCFrame)
	lobbySpawn = lobbySpawnCFrame or lobbySpawn
	buildWorld()

	for zone = 1, F.ZoneCount do
		for _ = 1, F.MonstersPerZone do
			spawnMonster(zone, "Normal")
		end
		for _ = 1, F.ElitesPerZone do
			spawnMonster(zone, "Elite")
		end
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

	task.spawn(runEvents)
	task.spawn(runGoblins)
end

return Field
