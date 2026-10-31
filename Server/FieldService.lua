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
local Guard = require(script.Parent:WaitForChild("DamageGuard"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Effects = require(script.Parent:WaitForChild("Effects"))
local Dungeon = require(script.Parent:WaitForChild("DungeonService"))
local Keys = require(script.Parent:WaitForChild("KeyService"))
local Aug = require(script.Parent:WaitForChild("AugService"))
local BL = require(script.Parent:WaitForChild("BalanceLog")) -- Studio 전용 밸런스 로그
local Meta = require(script.Parent:WaitForChild("MetaService"))
local Quest = require(script.Parent:WaitForChild("QuestService"))
local Level = require(script.Parent:WaitForChild("LevelService"))
local MonsterTypes = require(script.Parent:WaitForChild("MonsterTypes"))
local Stage = require(script.Parent:WaitForChild("BossStage")) -- 군주 전투 연출 (등장 / 격노 / 처치)
local Combo = require(script.Parent:WaitForChild("ComboService"))
local Loot = require(script.Parent:WaitForChild("LootService"))
local PartyShare = require(script.Parent:WaitForChild("FieldPartyShare")) -- 파티 경험치 나눔 / 파티원별 드랍
local Inventory = require(script.Parent:WaitForChild("InventoryService"))
local Journey = require(script.Parent:WaitForChild("JourneyService"))

local F = Config.Field
local TOP = 0.05
local routeBeat = setmetatable({}, { __mode = "k" }) -- [player] = 튜토리얼 첫 구역 길목에서 이미 터진 사건 번호
local doomReady = setmetatable({}, { __mode = "k" }) -- [player] = (옛 방식) 첫 구역 군주를 쓰러뜨린 시각. 지금은 군주가 열쇠를 떨어뜨리고 던전으로 이어진다 (startTutorialRift)
local startTutorialRift -- 아래(최후의 군주 장면 근처)에서 정의

local Field = {}

local monsters = {}      -- [Part] = 몬스터 데이터
local baffleXs = {}      -- 시선을 막는 "꺾임 벽"의 x 위치 (몬스터가 벽 속에 나타나지 않게 피하는 용도)
local baffleRects = {}   -- 꺾임 벽이 차지한 사각형 { X0, X1, Z0, Z1 } (몬스터 / 탄 / 사격이 벽을 통과하지 못하게 하는 용도)

-- 걸을 수 있는 곳인가 (꺾임 벽 안쪽이 아닌 곳)
-- 벽 사각형을 x 50 칸마다 묶어 둔다: 몬스터 / 탄 / 시야 검사가 매번 벽 전부(수십 개)를 훑지 않고 근처 칸만 본다
local RECT_CELL = 50
local rectCells, rectIndexed = {}, -1
local function rectsNear(x, pad)
	if rectIndexed ~= #baffleRects then -- 벽이 새로 생겼으면(필드를 지을 때) 다시 묶는다
		rectIndexed = #baffleRects
		table.clear(rectCells)
		for _, rect in ipairs(baffleRects) do
			for cell = math.floor((rect.X0 - 40) / RECT_CELL), math.floor((rect.X1 + 40) / RECT_CELL) do -- (덩치 큰 몬스터의 pad 여유 40)
				rectCells[cell] = rectCells[cell] or {}
				table.insert(rectCells[cell], rect)
			end
		end
	end
	if pad > 38 then return baffleRects end
	return rectCells[math.floor(x / RECT_CELL)]
end
local function walkableAt(x, z, pad)
	pad = pad or 0 -- 덩치가 큰 몬스터(보스)는 몸 반지름만큼 벽에서 떨어져 있어야 한다
	local list = rectsNear(x, pad)
	if not list then return true end
	for _, rect in ipairs(list) do
		if x >= rect.X0 - 1.5 - pad and x <= rect.X1 + 1.5 + pad and z >= rect.Z0 - pad and z <= rect.Z1 + pad then
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
local lobbySpawn = CFrame.new(0, 33, 112)
local activeEvent = nil     -- { Part, Data }

------------------------------------------------------------
-- 유틸
------------------------------------------------------------
local SoundBank = require(game:GetService("ReplicatedStorage"):WaitForChild("SoundBank"))
local function playSfx(player, key) -- 그 플레이어 몸에서 나는 효과음 (소리 ID 가 있을 때만)
	if not SoundBank.Has(key) then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then SoundBank.Play(root, key) end
end

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
	return position.X - F.ZoneStart(F.ZoneOfX(position.X)) < F.CampSafe
end

-- 필드에 있는 살아 있는 플레이어 목록: 몬스터 수백 마리가 매 프레임 "가장 가까운 플레이어"를 물으므로 0.05초마다 한 번만 다시 만든다
local fieldRoots, fieldRootZones, fieldRootsAt = {}, {}, 0
local function nearestFieldPlayer(position)
	local now = os.clock()
	if now - fieldRootsAt > 0.05 then
		fieldRootsAt = now
		table.clear(fieldRoots)
		table.clear(fieldRootZones)
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("Zone") == "Field" then
				local root = getAliveParts(player)
				if root and not isSafe(root.Position) then
					table.insert(fieldRoots, root)
					table.insert(fieldRootZones, F.ZoneOfX(root.Position.X))
				end
			end
		end
	end
	local nearest, nearestDist = nil, math.huge
	local myZone = F.ZoneOfX(position.X)
	for index, root in ipairs(fieldRoots) do
		-- 다른 구역(특히 닫힌 관문 너머)에 있는 플레이어는 노리지 않는다: 옆 구역에서 쏘거나 가까이 서 있어도 몬스터가 끌려오지 않게
		if root.Parent and fieldRootZones[index] == myZone then
			local dist = (root.Position - position).Magnitude
			if dist < nearestDist then
				nearest, nearestDist = root, dist
			end
		end
	end
	return nearest, nearestDist
end

local function zoneBounds(zone)
	return F.ZoneStart(zone), F.ZoneEnd(zone)
end

local function zoneOfX(x)
	return F.ZoneOfX(x)
end

-- 관문을 열지 않은 구역의 몬스터는 관문 너머에서 때릴 수 없다 (자동공격 / 스킬로 벽 너머를 잡는 것 방지)
local function canHitZone(player, x)
	local allowed = math.min(F.ZoneCount, (player:GetAttribute("ClearedZone") or 0) + 1)
	return zoneOfX(x) <= allowed
end

-- 구역마다 넓은 계단으로 층을 올라갔다 내려온다 (구역 입구 / 캠프는 항상 0층). 계단은 맵 폭 전체라 좁은 길이 없다.
-- 계단 대신 완만한 "경사로": 작은 단차를 오르내릴 때 캐릭터가 위로 튕겨 나가는 문제를 없앴다 (경사가 약 14~22도라서 부드럽게 걷는다)
-- 세 번 연달아 올라 정상(+48)까지 간 뒤, 긴 내리막으로 다시 내려온다 (계속 올라가는 느낌). 구역 입구 / 캠프는 항상 0층.
local ZONE_LAYOUTS = require(script.Parent:WaitForChild("FieldLayouts")) -- (구역별 지형 배치: 경사로 / 벽. 따로 뺀 모듈)
local ZONE_SEGMENTS = {} -- [zone] = { { A, B, H, Kind = "Floor" | "Step", Stair } ... }
for zone, layout in ipairs(ZONE_LAYOUTS) do
	local segments = {}
	local height, cursor = 0, 0
	for _, stair in ipairs(layout.Stairs) do
		table.insert(segments, { A = cursor, B = stair.At, H = height, Kind = "Floor" })
		stair.From = height
		stair.Hi = math.max(height, height + stair.Rise)
		table.insert(segments, { A = stair.At, B = stair.At + stair.Run, H = height, Kind = "Step", Stair = stair, First = true })
		height += stair.Rise
		cursor = stair.At + stair.Run
		stair.Top = height
	end
	table.insert(segments, { A = cursor, B = F.ZoneLengths[zone] or F.ZoneLength, H = height, Kind = "Floor" })
	ZONE_SEGMENTS[zone] = segments
end
local function floorAt(x)
	local zone = F.ZoneOfX(x)
	local offset = x - F.ZoneStart(zone)
	for _, segment in ipairs(ZONE_SEGMENTS[zone] or ZONE_SEGMENTS[1]) do
		if offset < segment.B then
			if segment.Kind == "Step" then
				local stair = segment.Stair
				local t = math.clamp((offset - stair.At) / stair.Run, 0, 1)
				return TOP + stair.From + stair.Rise * t -- 경사로 위의 높이 (몬스터 / 전리품이 경사를 따라간다)
			end
			return TOP + segment.H
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
	gui.Size = UDim2.new(0, 400, 0, 130)
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

-- ===== 구역 꾸미기 (구역마다 완전히 다른 지형지물 + 그 구역의 랜드마크 하나) =====
-- 장식은 대부분 충돌이 없거나 작아서 길을 막지 않는다. 경사로 / 꺾임 벽 / 캠프 근처에는 놓지 않는다.
local function propBlocked(zone, offset)
	local layout = ZONE_LAYOUTS[zone] or ZONE_LAYOUTS[1]
	for _, stair in ipairs(layout.Stairs) do
		if offset > stair.At - 10 and offset < stair.At + stair.Run + 10 then return true end
	end
	for _, wall in ipairs(layout.Baffles) do
		if math.abs(offset - wall.Offset) < 20 then return true end
	end
	return false
end

local okZoneProps, FieldZoneProps = pcall(function() return require(script.Parent:WaitForChild("FieldZoneProps", 10)) end) -- (구역 꾸미기는 따로 뺀 모듈)
local function decorateZone(zone, rng)
	if not okZoneProps or not FieldZoneProps then warn("[FieldService] FieldZoneProps 모듈이 없어 구역 장식을 건너뜁니다 (던전 업데이트를 다시 해 주세요)") return end
	local ok, err = pcall(FieldZoneProps.Decorate, zone, rng, { ZoneBounds = zoneBounds, MakePart = makePart, FloorAt = floorAt, PropBlocked = propBlocked, Folder = worldFolder })
	if not ok then warn("[FieldService] 구역 " .. tostring(zone) .. " 장식 오류: " .. tostring(err)) end
end

local function buildCanyon(rng, totalLength, half)
	local endX = F.StartX + totalLength

	-- 뒤에 깔아두는 끊김 없는 절벽 벽 (절벽 덩어리 사이로 바깥이 비치지 않게)
	for _, side in ipairs({ -1, 1 }) do
		makePart({
			Name = "CanyonBack", Size = Vector3.new(totalLength + 120, 240, 8),
			Position = Vector3.new(F.StartX + totalLength / 2, 120, side * (half + 34)),
			Color = Color3.fromRGB(55, 50, 58), Material = Enum.Material.Slate,
		}, worldFolder)

		-- 구역 색을 띤 크고 울퉁불퉁한 절벽 덩어리들
		local x = F.StartX - 10
		while x < endX + 20 do
			local zone = zoneOfX(math.clamp(x, F.StartX, endX - 1))
			local width = rng:NextNumber(34, 52)
			local height = rng:NextNumber(120, 200)
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
		Name = "CanyonEnd", Size = Vector3.new(40, 240, F.Width + 90),
		Position = Vector3.new(endX + 150, 120, 0), -- (예전 endX + 20: 오프닝의 최후의 군주(endX + 6)가 이 벽 속에 파묻혀 안 보였다. 군주 뒤쪽으로 물린다)
		Color = Color3.fromRGB(35, 30, 45), Material = Enum.Material.Slate,
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
	makeSign(beacon, "⛺ Camp · Warp", Color3.fromRGB(255, 240, 200), 18)

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
	prompt.ActionText = "Warp / Camp"
	prompt.ObjectText = string.format("Zone %d Camp", zone)
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 18
	prompt.RequiresLineOfSight = false
	prompt.Parent = beacon
	prompt.Triggered:Connect(function(player)
		Remotes.Warp:FireClient(player, "Open")
	end)

	-- 안전지대 경계: 이 선 안에서는 사격이 통하지 않고 몬스터도 들어오지 않는다. 은은한 청록 선 + 작은 말뚝으로 어디까지인지 보이게 한다
	local boundaryX = x0 + F.CampSafe
	local teal = Color3.fromRGB(110, 205, 195)
	local line = makePart({
		Name = "SafeLine", Size = Vector3.new(0.7, 0.2, F.Width), Position = Vector3.new(boundaryX, TOP + 0.12, 0),
		Color = teal, Material = Enum.Material.Neon, Transparency = 0.55, CanCollide = false, CanQuery = false,
	}, worldFolder)
	local lineGui = Instance.new("BillboardGui") -- 작은 글씨: 가까이 갔을 때만 보인다
	lineGui.Size = UDim2.new(0, 240, 0, 26)
	lineGui.StudsOffset = Vector3.new(0, 4, 0)
	lineGui.MaxDistance = 55
	lineGui.Parent = line
	local lineText = Instance.new("TextLabel")
	lineText.Size = UDim2.new(1, 0, 1, 0)
	lineText.BackgroundTransparency = 1
	lineText.Font = Enum.Font.GothamBold
	lineText.TextScaled = true
	lineText.TextColor3 = Color3.fromRGB(190, 240, 232)
	lineText.TextStrokeTransparency = 0.4
	lineText.Text = "🛡 Safe Zone Edge (no shooting inside)"
	lineText.Parent = lineGui
	for z = -F.Width / 2 + 20, F.Width / 2 - 20, 40 do
		makePart({ Name = "SafePost", Size = Vector3.new(0.7, 3, 0.7), Position = Vector3.new(boundaryX, TOP + 1.5, z), Color = Color3.fromRGB(70, 90, 92), Material = Enum.Material.Slate, CanCollide = false, CanQuery = false }, worldFolder)
		makePart({ Name = "SafeCap", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9), Position = Vector3.new(boundaryX, TOP + 3.2, z), Color = teal, Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false, CanQuery = false }, worldFolder)
	end

	campCFrames[zone] = CFrame.new(x0 + 40, TOP + 4, 16)
end

-- 구역 관문: 구역마다 컨셉이 다른 성문 / 입구. 문은 활짝 열려 있고, 이름 / 컨셉 / 몬스터 레벨이 위에 걸려 있다.
--   1 초원 목책 문 · 2 숲속 고성 정문 · 3 무너진 요새 · 4 사막 신전 · 5 얼음 궁전 · 6 용암 요새 · 7 암흑 성 · 8 심연의 문
local GATE_THEMES = {
	{ Tag = "🌾 Adventure Begins", Wall = Color3.fromRGB(140, 105, 70), Mat = Enum.Material.Wood, Accent = Color3.fromRGB(255, 205, 90), Height = 24, Crenel = false },
	{ Tag = "🏰 Forest Castle Gate", Wall = Color3.fromRGB(105, 125, 105), Mat = Enum.Material.Brick, Accent = Color3.fromRGB(120, 230, 130), Height = 34, Crenel = true },
	{ Tag = "🏚 Ruined Fortress Gate", Wall = Color3.fromRGB(120, 105, 90), Mat = Enum.Material.Cobblestone, Accent = Color3.fromRGB(255, 170, 80), Height = 30, Crenel = true },
	{ Tag = "🏜 Desert Temple Entrance", Wall = Color3.fromRGB(205, 175, 110), Mat = Enum.Material.Sandstone, Accent = Color3.fromRGB(255, 215, 70), Height = 32, Crenel = false },
	{ Tag = "❄ Ice Palace Gate", Wall = Color3.fromRGB(180, 215, 235), Mat = Enum.Material.Ice, Accent = Color3.fromRGB(130, 220, 255), Height = 34, Crenel = true },
	{ Tag = "🌋 Lava Fortress Gate", Wall = Color3.fromRGB(70, 45, 42), Mat = Enum.Material.Basalt, Accent = Color3.fromRGB(255, 110, 40), Height = 34, Crenel = true },
	{ Tag = "🦇 Dark Castle Gate", Wall = Color3.fromRGB(45, 38, 62), Mat = Enum.Material.Slate, Accent = Color3.fromRGB(170, 100, 255), Height = 40, Crenel = true },
	{ Tag = "🌀 Gate of the Abyss", Wall = Color3.fromRGB(28, 24, 40), Mat = Enum.Material.Slate, Accent = Color3.fromRGB(255, 70, 130), Height = 40, Crenel = false },
}

local function buildGateway(zone, x0)
	local theme = GATE_THEMES[zone]
	local half = F.Width / 2
	local open = 56            -- 열린 통로 폭 (로비 쪽 통로 40보다 넓게)
	local H = theme.Height + (zone - 1) * 5 -- 동쪽으로 갈수록 관문이 점점 거대해진다
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

	-- 바닥 경고 줄무늬 (구역 번호만큼): 위험도가 눈에 보인다. (예전에 있던 구역 입구의 하늘 빛기둥 + 불빛은 눈이 부시고 시야를 가려서 껐다)
	do
		for stripe = 1, zone do -- 구역 번호만큼 줄무늬: 위험도가 눈에 보인다
			part("GateWarnStripe", Vector3.new(1.6, 0.25, open + 8), Vector3.new(x0 - 4 - stripe * 4, TOP + 0.2, 0), accent, Enum.Material.Neon,
				{ Transparency = 0.25 + 0.05 * (stripe % 2), CanCollide = false, CanQuery = false })
		end
	end

	-- 간판: 구역 이름 + 컨셉 + 몬스터 레벨
	local signPart = part("GateSign", Vector3.new(1, 1, 1), Vector3.new(x0 + 2, H + 24, 0), accent, Enum.Material.Neon, { Transparency = 1, CanCollide = false, CanQuery = false })
	local zoneSet = Config.Sets[Config.Sets.ZoneKeys[zone]]
	makeSign(signPart, string.format("Zone %d · %s\n%s · Rec. ⚡%d\nDanger %s\n%s New set from here: %s Set", zone, F.ZoneNames[zone], theme.Tag, F.RecommendPower[zone] or 0, string.rep("☠", zone), zoneSet.Icon, zoneSet.Name), Color3.fromRGB(255, 240, 190), 0)
end

local function buildWorld()
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "Field"
	worldFolder.Parent = workspace

	monstersFolder = Instance.new("Folder")
	monstersFolder.Name = "FieldMonsters"
	monstersFolder.Parent = workspace

	local half = F.Width / 2
	local totalLength = F.TotalLength()
	local rng = Random.new(77)

	for zone = 1, F.ZoneCount do
		local x0 = zoneBounds(zone)
		-- 바닥: 평지(층) 블록 + 좁은 계단통(양옆은 높은 벽, 가운데 폭 14 계단). 높은 층일수록 살짝 밝아져서 "층"이 구분된다
		for _, segment in ipairs(ZONE_SEGMENTS[zone]) do
			local top = TOP + segment.H
			local tint = F.ZoneColors[zone]:Lerp(Color3.new(1, 1, 1), 0.08 * segment.H / 24)
			if segment.Kind == "Floor" then
				makePart({
					Name = "Ground" .. zone, Size = Vector3.new(segment.B - segment.A, top + 1.95, F.Width),
					Position = Vector3.new(x0 + (segment.A + segment.B) / 2, (top - 1.95) / 2, 0), Color = tint, Material = F.ZoneMaterials[zone],
				}, worldFolder)
			else
				local stair = segment.Stair
				-- 경사로: 비스듬한 두꺼운 판 + 아래쪽을 받치는 바닥 덩어리 (표면은 시작 / 끝 높이에 딱 맞는다)
				local startY, endY = TOP + stair.From, TOP + stair.From + stair.Rise
				local length = math.sqrt(stair.Run * stair.Run + stair.Rise * stair.Rise)
				local angle = math.atan2(stair.Rise, stair.Run)
				local thickness = 6
				local midX, midY = x0 + stair.At + stair.Run / 2, (startY + endY) / 2
				-- 표면에서 두께의 절반만큼 아래(법선 반대 방향)로 중심을 내린다
				local center = Vector3.new(midX + math.sin(angle) * thickness / 2, midY - math.cos(angle) * thickness / 2, 0)
				makePart({
					Name = "Ramp" .. zone, Size = Vector3.new(length, thickness, F.Width),
					CFrame = CFrame.new(center) * CFrame.Angles(0, 0, angle),
					Color = Color3.fromRGB(205, 195, 180):Lerp(F.ZoneColors[zone], 0.3), Material = Enum.Material.Cobblestone,
				}, worldFolder)
				local lowY = math.min(startY, endY)
				makePart({
					Name = "RampBase" .. zone, Size = Vector3.new(stair.Run, math.max(0.5, lowY - thickness + 1.95), F.Width),
					Position = Vector3.new(midX, (lowY - thickness - 1.95) / 2, 0), Color = F.ZoneColors[zone], Material = F.ZoneMaterials[zone],
				}, worldFolder)
				for dx = 0, stair.Run, 14 do
					table.insert(baffleXs, x0 + stair.At + dx)
				end
			end
		end
		buildGateway(zone, x0)

		decorateZone(zone, rng)
		buildCamp(zone, x0)
	end

	-- 꺾임 벽: 구역마다 벽의 개수 / 종류 / 틈의 크기가 다르다 (ZONE_LAYOUTS). 길이 꺾이거나 갈라져서 한눈에 다 보이지 않는다.
	do
		for zone = 1, F.ZoneCount do
			local x0 = zoneBounds(zone)
			for _, wallSpec in ipairs(ZONE_LAYOUTS[zone].Baffles) do
				local offset, gapSize = wallSpec.Offset, wallSpec.Gap
				if zone == F.ZoneCount and x0 + offset > F.ZoneEnd(zone) - 110 then continue end -- 최후의 군주 포탈 주변은 벽 없이 탁 트이게
				local height = 110
				local color = F.ZoneColors[zone]:Lerp(Color3.fromRGB(70, 65, 72), 0.5)
				-- 이 위치의 땅 높이만큼 벽을 올려 세운다 (언덕 위에 서 있는 벽)
				local base = floorAt(x0 + offset) - TOP
				if wallSpec.Type == "Center" then
					local wallLength = F.Width - gapSize * 2
					makePart({
						Name = "Baffle", Size = Vector3.new(22, height, wallLength), Position = Vector3.new(x0 + offset, base + height / 2 - 2, 0),
						Color = color, Material = Enum.Material.Slate,
					}, worldFolder)
					table.insert(baffleXs, x0 + offset)
					table.insert(baffleRects, { X0 = x0 + offset - 11, X1 = x0 + offset + 11, Z0 = -wallLength / 2, Z1 = wallLength / 2 })
				else
					local side = wallSpec.Side or 1
					local wallLength = F.Width - gapSize
					local zCenter = -side * gapSize / 2
					makePart({
						Name = "Baffle", Size = Vector3.new(22, height, wallLength), Position = Vector3.new(x0 + offset, base + height / 2 - 2, zCenter),
						Color = color, Material = Enum.Material.Slate,
					}, worldFolder)
					table.insert(baffleXs, x0 + offset)
					table.insert(baffleRects, { X0 = x0 + offset - 11, X1 = x0 + offset + 11, Z0 = zCenter - wallLength / 2, Z1 = zCenter + wallLength / 2 })
				end
			end
		end
	end

	buildCanyon(rng, totalLength, half)

	-- 필드 가장자리 보이지 않는 벽 (옆면 / 끝 / 로비 쪽 입구 통로)
	local function wall(size, position)
		makePart({ Name = "Wall", Size = size, Position = position, Transparency = 1 }, worldFolder)
	end
	local centerX = F.StartX + totalLength / 2
	wall(Vector3.new(totalLength + 4, 240, 2), Vector3.new(centerX, 120, half + 1))
	wall(Vector3.new(totalLength + 4, 240, 2), Vector3.new(centerX, 120, -half - 1))
	wall(Vector3.new(2, 240, F.Width), Vector3.new(F.StartX + totalLength + 1, 120, 0))
	wall(Vector3.new(2, 50, half - 20), Vector3.new(F.StartX - 1, 25, (half + 20) / 2))
	wall(Vector3.new(2, 50, half - 20), Vector3.new(F.StartX - 1, 25, -(half + 20) / 2))
	wall(Vector3.new(26, 50, 2), Vector3.new(F.StartX - 14, 25, 21))
	wall(Vector3.new(26, 50, 2), Vector3.new(F.StartX - 14, 25, -21))

	-- 구역별 분위기 장식 (충돌 없는 장식 + 바닥 무늬, 실패해도 게임은 계속)
	local okDecor, decorErr = pcall(function() require(script.Parent:WaitForChild("FieldDecor")).Build(worldFolder, { FloorAt = floorAt, ZoneBounds = zoneBounds, Width = F.Width, Blocked = propBlocked, Baffles = baffleRects }) end)
	if not okDecor then warn("FieldDecor failed: " .. tostring(decorErr)) end
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

-- 구역 안의 "구간": 한 구역을 3등분해서 구간마다 주력 몬스터 2종이 많이 나온다 (같은 구역도 걸어 들어갈수록 구성이 달라진다)
local function segmentOf(zone, x)
	local x0, x1 = zoneBounds(zone)
	local start = x0 + F.CampSafe
	return math.clamp(math.floor((x - start) / math.max(1, x1 - start) * 3) + 1, 1, 3)
end

local segmentFeatureCache = {}
local function segmentFeatures(zone, segment)
	local id = zone * 10 + segment
	if segmentFeatureCache[id] then return segmentFeatureCache[id] end
	local keys = {}
	for key in pairs(F.ZonePools[zone]) do
		if key ~= "Healer" then table.insert(keys, key) end -- 치유 사제는 구간 "특산" 으로 뽑히지 않는다 (뽑히면 그 구간이 힐러투성이가 돼서 불쾌했다)
	end
	table.sort(keys)
	local rng = Random.new(zone * 7919 + segment * 104729)
	local picked = {}
	for _ = 1, math.min(2, #keys) do
		local index = rng:NextInteger(1, #keys)
		table.insert(picked, table.remove(keys, index))
	end
	segmentFeatureCache[id] = picked
	return picked
end

local function pickTypeAt(zone, x)
	local features = segmentFeatures(zone, segmentOf(zone, x))
	local pool = {}
	for key, weight in pairs(F.ZonePools[zone]) do
		pool[key] = weight * 0.6
	end
	for _, key in ipairs(features) do
		pool[key] = (F.ZonePools[zone][key] or 1) * 3.2
	end
	if pool.Healer then -- 주변(150칸 안)에 이미 치유 사제가 있거나 구역 전체에 3마리가 살아 있으면 더 나오지 않는다
		local near, total = 0, 0
		for part, data in pairs(monsters) do
			if data.TypeKey == "Healer" and data.Zone == zone and part.Parent then
				total += 1
				if math.abs(part.Position.X - x) < 150 then near += 1 end
			end
		end
		if near >= 1 or total >= 3 then pool.Healer = nil end -- 주변에 1마리만 / 구역 전체로도 3마리까지
	end
	return MonsterTypes.Pick(pool)
end

-- 구역 안에서 몬스터가 고르게 퍼지도록: 후보 자리를 6곳 뽑아 "이미 있는 같은 구역 몬스터와 가장 멀리 떨어진" 곳을 고른다.
-- (예전에는 입구 근처 35% / 군주 근처 25%에 몰려서 구역 한가운데가 휑했다. 몬스터가 죽고 다시 태어날 때도 같은 규칙이라 비는 곳이 먼저 채워진다)
local function evenX(zone, lo, hi)
	local bestX, bestGap = nil, -1
	for _ = 1, 6 do
		local x = freeX(lo, hi)
		local gap = math.huge
		for part, data in pairs(monsters) do
			if data.Zone == zone and part.Parent and data.Kind ~= "Boss" then
				local distance = math.abs(part.Position.X - x)
				if distance < gap then gap = distance end
			end
		end
		if gap > bestGap then bestX, bestGap = x, gap end
	end
	return bestX or freeX(lo, hi)
end

-- kind: "Normal" / "Elite" / "Boss"
local function spawnMonster(zone, kind, at, ambush)
	local stats, text, color, barWidth
	local level = F.GetZoneLevel(zone)
	local typeKey, def, xpLevel
	local preX -- 일반 / 엘리트 몬스터가 태어날 X (구간에 맞는 종류를 고르기 위해 먼저 정한다)

	if kind == "Boss" then
		-- 구역마다 하나씩 있는 구역 보스: 그 구역 몬스터 레벨 기준으로 체력 / 공격력이 훨씬 세고 크다. 관문을 열려면 이 보스를 쓰러뜨려야 한다.
		local boss = F.Boss
		local bossLevel = level + 3
		local base = Config.Monster.GetStats(bossLevel)
		local danger = F.ZoneDanger
		stats = {
			Size = (16 + zone * 2) * ((F.BossSizeMult and F.BossSizeMult[zone]) or 1),
			MaxHealth = math.floor(base.MaxHealth * 60 * danger.Health[zone]),
			Speed = boss.Speed * danger.Speed[zone],
			ShotDamage = math.max(10, math.floor(base.ShotDamage * (zone >= 7 and 1.3 or 1.5) * danger.Damage[zone])), -- (후반 군주는 한 방에 체력이 크게 깎이지 않게 살짝 낮춤)
			ShotInterval = math.max(0.9, boss.ShotInterval - zone * 0.05),
			ShotSpeed = boss.ShotSpeed,
			Gold = math.floor(boss.Gold * danger.Reward[zone]),
		}
		xpLevel = bossLevel
		text, color, barWidth = string.format("👑 Lord of %s (Zone %d) · Rec. ⚡%d", F.ZoneNames[zone], zone, F.RecommendPower[zone] or 0), Color3.fromRGB(255, 120, 120), 360
	else
		-- 구역마다 나오는 몬스터 종류가 다르다 (Config.Field.ZonePools)
		if at then
			preX = at.X
		else
			local bx0, bx1 = zoneBounds(zone)
			preX = evenX(zone, math.floor(bx0 + F.CampSafe + 70), math.floor(bx1 - 25)) -- 구역 전체에 고르게
			-- (몬스터가 안전지대 경계에 붙어 어정쩡하게 서 있지 않게 입구 쪽은 안전지대에서 조금 떨어진 곳부터)
		end
		typeKey = pickTypeAt(zone, preX)
		def = MonsterTypes.Defs[typeKey]
		if kind == "Elite" then
			xpLevel = level + 2
			stats = Config.Monster.GetStats(xpLevel)
			MonsterTypes.ApplyDef(typeKey, stats)
			stats.MaxHealth = math.floor(stats.MaxHealth * F.EliteMultiplier)
			stats.Size = stats.Size * 1.5
			stats.Gold *= 4
			text, color, barWidth = string.format("★ Elite %s", def.Name), Color3.fromRGB(255, 220, 90), 190
		else
			xpLevel = level
			stats = Config.Monster.GetStats(level)
			MonsterTypes.ApplyDef(typeKey, stats)
			stats.MaxHealth = math.max(1, math.floor(stats.MaxHealth * Config.Horde.Health)) -- 몬스터 떼: 더 많이, 대신 한 마리는 더 빨리 죽는다
			stats.Gold *= Config.Horde.Reward
			text, color, barWidth = def.Name, Color3.new(1, 1, 1), 140
		end
		-- 구역 난이도 배율: 구역이 넘어가면 몬스터가 확 강해진다 (체력 / 공격력 / 속도) 대신 보상도 크게 오른다
		local danger = F.ZoneDanger
		stats.MaxHealth = math.max(1, math.floor(stats.MaxHealth * danger.Health[zone] * (F.EarlyMobHealth[zone] or 1)))
		stats.ShotDamage = math.max(1, math.floor(stats.ShotDamage * danger.Damage[zone]))
		stats.Speed *= danger.Speed[zone]
		stats.Gold = math.floor(stats.Gold * danger.Reward[zone] * Config.Economy.FieldGoldMult)
	end

	local x0, x1 = zoneBounds(zone)
	local position
	if kind == "Boss" then
		position = Vector3.new(x1 - 45, floorAt(x1 - 45) + stats.Size / 2, 0)
		if not at then
			-- 구역 끝의 벽(기둥)에 몸이 끼어서 태어나지 않게: 몸 크기만큼 벽에서 떨어진 자리를 찾는다 (뒤로 물러나며 가운데 / 위 / 아래 순서로)
			local radius = stats.Size / 2 + 2
			local found = false
			for back = 0, 300, 10 do
				local x = x1 - 45 - back
				for _, z in ipairs({ 0, F.Width * 0.3, -F.Width * 0.3 }) do
					if walkableAt(x, z, radius) then
						position = Vector3.new(x, floorAt(x) + stats.Size / 2, z)
						found = true
						break
					end
				end
				if found then break end
			end
		end
		if at then -- 튜토리얼 "압도적인 존재": 플레이어 눈앞에서 나타난다
			position = Vector3.new(at.X, floorAt(at.X) + stats.Size / 2, at.Z)
		end
	else
		-- 필드에 나서자마자 바로 싸움이 시작되도록: 몬스터의 절반 가까이는 캠프 안전지대 바로 바깥(입구 근처)에 모여 있다
		local spawnX = preX or freeX(math.floor(x0 + F.CampSafe + 70), math.floor(x1 - 25))
		position = Vector3.new(spawnX, floorAt(spawnX) + stats.Size / 2, math.random(-F.Width / 2 + 25, F.Width / 2 - 25))
		if at then -- 습격: 플레이어 주변에 바로 나타난다
			position = Vector3.new(at.X, floorAt(at.X) + stats.Size / 2, at.Z)
		end
	end

	local part
	local weakOrb
	if kind == "Boss" then
		part = Instance.new("Part")
		part.Name = "FieldBoss"
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(stats.Size, stats.Size, stats.Size)
		part.Anchored = true
		part.CanCollide = false
		part.Position = position
		part.Color = F.ZoneColors[zone]:Lerp(Color3.fromRGB(150, 25, 45), 0.55)
		part.Material = Enum.Material.Neon
		part.Parent = monstersFolder
		Effects.DecorateZoneBoss(part, stats.Size, F.ZoneColors[zone]:Lerp(Color3.fromRGB(255, 120, 70), 0.6), zone)
		-- 약점 구슬: 보스 주위를 도는 노란 구슬. 직접 조준해서 맞히면 3배 치명타 (자동 조준은 몸통을 노린다)
		weakOrb = Instance.new("Part")
		weakOrb.Name = "WeakPoint"
		weakOrb.Shape = Enum.PartType.Ball
		weakOrb.Size = Vector3.new(7.2, 7.2, 7.2) -- 맞히기 쉽게 크다
		weakOrb.Anchored = true
		weakOrb.CanCollide = false
		weakOrb.CanQuery = true -- 구슬을 직접 조준(클릭)할 수 있게: 조준선 / 총알 판정이 구슬에 맞는다
		weakOrb.CanTouch = false
		weakOrb.Color = Color3.fromRGB(255, 235, 80)
		weakOrb.Material = Enum.Material.Neon
		weakOrb.Position = part.Position
		weakOrb.Parent = part
		local orbLight = Instance.new("PointLight")
		orbLight.Color = Color3.fromRGB(255, 235, 80)
		orbLight.Range = 22
		orbLight.Brightness = 2.5
		orbLight.Parent = weakOrb
		local orbGui = Instance.new("BillboardGui")
		orbGui.Size = UDim2.new(0, 70, 0, 28)
		orbGui.StudsOffset = Vector3.new(0, 5.6, 0)
		orbGui.MaxDistance = 200
		orbGui.AlwaysOnTop = true
		orbGui.Parent = weakOrb
		-- 구슬을 감싸는 반투명 후광 + 반짝이는 입자
		local halo = Instance.new("Part")
		halo.Name = "WeakHalo"
		halo.Shape = Enum.PartType.Ball
		halo.Size = Vector3.new(12, 12, 12)
		halo.Massless = true
		halo.CanCollide = false
		halo.CanQuery = false
		halo.CanTouch = false
		halo.Material = Enum.Material.Neon
		halo.Color = Color3.fromRGB(255, 220, 60)
		halo.Transparency = 0.75
		halo.CFrame = weakOrb.CFrame
		local haloWeld = Instance.new("Weld") -- (Weld + 명시적 오프셋: WeldConstraint 는 클라이언트가 받는 순간의 위치로 오프셋을 다시 계산해서, 움직이는 몬스터의 겉모양이 본체에서 어긋나 보였다)
		haloWeld.Part0 = weakOrb
		haloWeld.Part1 = halo
		haloWeld.C0 = weakOrb.CFrame:ToObjectSpace(halo.CFrame)
		haloWeld.Parent = halo
		halo.Parent = weakOrb
		local sparks = Instance.new("ParticleEmitter")
		sparks.Rate = 18
		sparks.Lifetime = NumberRange.new(0.5, 1)
		sparks.Speed = NumberRange.new(2, 6)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.LightEmission = 1
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 240, 120))
		sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
		sparks.Parent = weakOrb
		local orbText = Instance.new("TextLabel")
		orbText.Size = UDim2.new(1, 0, 1, 0)
		orbText.BackgroundTransparency = 1
		orbText.Font = Enum.Font.GothamBlack
		orbText.TextScaled = true
		orbText.TextColor3 = Color3.fromRGB(255, 240, 120)
		orbText.TextStrokeTransparency = 0
		orbText.Text = "🎯 Weak spot! Hit here"
		orbText.Parent = orbGui
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

	part:SetAttribute("MobZone", zone) -- 클라이언트가 내 전투력과 비교해서 이름 색을 칠한다 (MonsterLabelClient)
	part:SetAttribute("MobKind", kind)
	local newData = {
		BossLike = kind == "Boss",
		Zone = zone,
		Kind = kind,
		Level = level,
		XpLevel = xpLevel,
		TypeKey = typeKey,
		Hazard = (zone <= 5 and kind == "Normal" and math.random() < 0.3) or nil, -- 초반 구역(1~5)의 일부 몬스터는 맵 분위기에 맞는 바닥 경고 공격(번개 / 가시 / 얼음 ...)을 가끔 쓴다
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
		Ambush = ambush == true,
		Contrib = (kind ~= "Boss") and {} or nil, -- 누가 얼마나 때렸나 (일반 / 엘리트 보상을 준 피해로 나눈다: FieldPartyShare)
		LastHit = ambush and os.clock() or nil, -- 습격으로 나온 몬스터는 처음부터 플레이어를 노린다
	}
	newData.WeakPart = weakOrb
	monsters[part] = newData
	if ambush then -- 갑자기 나타나는 몬스터(습격 / 이벤트): 그냥 "띡" 나오지 않고 보랏빛 소환 고리 + 파편이 터지면서 나타난다
		local at = Vector3.new(part.Position.X, floorAt(part.Position.X) + 0.5, part.Position.Z)
		Effects.Raw(at, { "N", at, 7 + stats.Size * 0.35, Color3.fromRGB(190, 130, 255) })
		Effects.Burst(part.Position, Color3.fromRGB(190, 130, 255), 22)
	end
	return part, newData
end

local MAX_FIELD_PROJECTILES = 450 -- 동시에 날아다니는 적 탄 상한: 넘치면 가장 오래된 탄부터 지운다
-- opts (선택): 유도 / 포물선 / 뱀 / 곡선 / 갈라짐 같은 특수 움직임 (Effects.MakeShot 설명 참고). 없으면 직선탄.
-- 경사로 보정: 수평으로 쏜 탄(전방위 / 나선 / 일직선)은 땅이 오르내리는 곳에서 허공을 지나거나 땅에 박힌다.
-- 쏘는 자리의 땅 기울기(x 방향)만큼 위아래 성분을 더해서 탄이 땅을 따라 날아가게 한다. (클라이언트는 직선으로 그리므로 서버와 어긋나지 않는다)
local function slopeAdjusted(origin, direction)
	if math.abs(direction.Y) > 0.02 then return direction end -- 이미 위아래로 겨눈 탄(플레이어를 조준한 탄)은 그대로
	local h = math.sqrt(direction.X * direction.X + direction.Z * direction.Z)
	if h < 0.001 then return direction end
	local slope = math.clamp((floorAt(origin.X + 12) - floorAt(origin.X - 12)) / 24, -0.8, 0.8)
	if math.abs(slope) < 0.03 then return direction end
	local ux, uz = direction.X / h, direction.Z / h
	return Vector3.new(ux, slope * ux, uz)
end

local function fireProjectile(origin, direction, speed, damage, size, color, style, opts)
	direction = slopeAdjusted(origin, direction)
	if #projectiles >= MAX_FIELD_PROJECTILES then
		local oldest = table.remove(projectiles, 1)
		oldest.Part:Destroy()
	end
	-- 부품 없이 숫자로만 (그리기는 클라이언트)
	table.insert(projectiles, Effects.MakeShot(projectiles, origin, direction, speed, damage, size, color, style, opts))
	-- 탄막 밀도: 직선탄에는 가끔 옆으로 한 발 더 (서버가 힘들거나 탄이 많으면 안 나간다 - Config.Danmaku)
	if (not opts or opts.Kind == nil) and style ~= "Bomb" and Effects.ExtraShotOk(#projectiles) then
		local D = Config.Danmaku
		local degrees = (math.random() < 0.5 and -1 or 1) * D.ExtraSpread * (0.6 + 0.4 * math.random())
		local rotated = CFrame.Angles(0, math.rad(degrees), 0):VectorToWorldSpace(direction)
		table.insert(projectiles, Effects.MakeShot(projectiles, origin, rotated, speed, math.max(1, math.floor(damage * D.ExtraDamage)), size * 0.9, color, style))
	end
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
	local leftFrac = data.ExpireAt and math.clamp((data.ExpireAt - os.clock()) / Config.Events.Lifetime, 0, 1) or 0
	local bonus = 1 + Config.Events.TimeBonus * leftFrac -- 제한 시간이 많이 남을수록 보상이 커진다
	local tickets = leftFrac > 0.5 and 2 or 1
	for player, damage in pairs(data.Contrib) do
		if player.Parent and damage >= data.MaxHealth * Config.Events.ContribMin then
			rewarded += 1
			player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + math.floor(data.Stats.Gold * bonus * Config.GoldBonus(player) + 0.5))
			player:SetAttribute("Tickets", (player:GetAttribute("Tickets") or 0) + tickets)
			Level.AddXP(player, Config.Xp.FieldBoss * 1.5)
			Quest.Add(player, "BossKills", 1)
			Quest.Add(player, "Kills", 1)
			Loot.DropFor(player, position, "Event", data.Zone)
			Loot.DropFor(player, position, "Event", data.Zone) -- 월드 보스: 장비를 두 번 떨어뜨린다
			notify(player, string.format("🗿 Colossus defeated! Gear + 🎫 +%d + %d G (time bonus x%.1f)", tickets, math.floor(data.Stats.Gold * bonus + 0.5), bonus))
		end
	end
	for _, other in ipairs(Players:GetPlayers()) do
		notify(other, string.format("🏆 Colossus defeated! Everyone worked together (%d player(s) rewarded)", rewarded))
	end
end

-- 황금 고블린: 잡으면 골드 대박 + 전리품 3개
local function rewardGoblin(player, data, part)
	local gold = data.Stats.Gold
	player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + math.floor(gold * Config.GoldBonus(player) + 0.5))
	Effects.FloatText(part.Position + Vector3.new(0, 4, 0), string.format("💰 +%d G", gold), Color3.fromRGB(255, 225, 80))
	Effects.Burst(part.Position, Color3.fromRGB(255, 215, 60), 90)
	Level.AddXP(player, Config.Xp.FieldPerMonsterLevel * data.XpLevel * 6)
	local position = dropPosition(part)
	for _ = 1, 3 do
		Loot.DropFor(player, position, "Elite", data.Zone)
	end
	Quest.Add(player, "Kills", 1)
	Quest.Add(player, "GoblinKills", 1)
	notify(player, string.format("💰 Golden Goblin defeated! +%d G, 3 loot drops!", gold))
end

-- 구역 관문: 지금 막 열어야 하는 구역(ClearedZone+1)에서 몬스터를 처치하면 진행도가 오르고, 다 채우면 다음 구역이 열린다
local function gateProgress(player, data)
	if data.Kind == "Boss" and data.Zone == F.ZoneCount and not Journey.IsDone(player, "FieldClear") then
		Journey.Mark(player, "FieldClear") -- 마지막 구역의 군주: 필드(이야기) 정복 -> 심연이 열린다
		notify(player, "🏆 Field conquered! You defeated the final Lord — the Boss Rush opened at the town portal!")
	end
	local cleared = player:GetAttribute("ClearedZone") or 0
	local frontier = cleared + 1
	local needed = F.Gate.KillsNeeded[frontier]
	if not needed or data.Zone ~= frontier then return end
	local weight = data.Kind == "Elite" and F.Gate.EliteWeight or (data.Kind == "Boss" and F.Gate.BossWeight or 1)
	local kills = (player:GetAttribute("GateKills") or 0) + weight
	if data.Kind == "Boss" then
		player:SetAttribute("GateBossDone", true)
	end
	if kills < needed or not player:GetAttribute("GateBossDone") then
		-- 처치 수를 채워도 구역 보스를 쓰러뜨리지 않으면 관문이 안 열린다
		local capped = math.min(kills, needed)
		if kills >= needed and not player:GetAttribute("GateBossDone") and (player:GetAttribute("GateKills") or 0) < needed then
			notify(player, string.format("👑 Kill goal reached! Defeat the Lord of Zone %d to open the gate!", frontier))
		end
		player:SetAttribute("GateKills", capped)
		return
	end
	player:SetAttribute("GateBossDone", false)
	player:SetAttribute("GateKills", 0)
	player:SetAttribute("ClearedZone", frontier)
	local gold = F.Gate.RewardGold * frontier
	local tickets = F.Gate.RewardTickets + (frontier >= 3 and 1 or 0)
	player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + math.floor(gold * Config.GoldBonus(player) + 0.5))
	player:SetAttribute("Tickets", (player:GetAttribute("Tickets") or 0) + tickets)
	local nextSet = Config.Sets[Config.Sets.ZoneKeys[frontier + 1]]
	notify(player, string.format("🔓 Zone %d gate opened! Reward 💰%d G · 🎫%d  — %s · %s-only drops: %s %s Set", frontier + 1, gold, tickets, F.ZoneNames[frontier + 1], F.ZoneNames[frontier + 1], nextSet.Icon, nextSet.Name))
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

	local gold = math.floor(data.Stats.Gold + 0.5)
	BL.Kill(player, data.Kind or "Normal")
	if data.Kind == "Boss" then -- 군주: 막타를 친 사람의 골드 (그 외는 아래에서 준 피해로 나눈다)
		player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + math.floor(gold * Config.GoldBonus(player) + 0.5))
		BL.Gold(player, "Kills", math.floor(gold * Config.GoldBonus(player) + 0.5))
		Effects.FloatText(part.Position + Vector3.new(0, part.Size.Y / 2, 0), string.format("+%d G", gold), Color3.fromRGB(255, 220, 90))
	end

	local xp
	if data.Kind == "Boss" then
		xp = Config.Xp.FieldBoss
	else
		xp = Config.Xp.FieldPerMonsterLevel * data.XpLevel * (data.Kind == "Elite" and Config.Xp.EliteMult or 1) * (data.Kind == "Normal" and Config.Horde.Reward or 1)
	end
	xp = xp * ((Config.Xp.ZoneMult and Config.Xp.ZoneMult[data.Zone]) or 1) -- 구역이 깊을수록 경험치 배율
	local rewarded = nil -- 골드 / 경험치를 받은 사람들 (드랍을 각자 굴린다)
	if data.Kind == "Boss" then Level.AddXP(player, xp) else rewarded = PartyShare.Distribute(player, data, part, gold, xp) end -- 군주는 근처 모두가 각자 받는다(아래). 그 외는 준 피해로 나눈다 (파티는 하나로)

	gateProgress(player, data)
	Quest.Add(player, "Kills", 1)
	local firstBoss = false -- 이 구역 군주를 처음 쓰러뜨렸나 (도감 기록 전에 확인)
	if data.Kind == "Boss" then
		local okF, MetaF = pcall(function() return require(script.Parent:WaitForChild("MetaService")) end)
		if okF and MetaF.BossKills then firstBoss = MetaF.BossKills(player, data.Zone) == 0 end
	end
	do -- 도감 기록
		local okM, MetaS = pcall(function() return require(script.Parent:WaitForChild("MetaService")) end)
		if okM and MetaS.CodexKill then
			if data.Kind == "Boss" then MetaS.CodexKill(player, nil, data.Zone) elseif data.TypeKey then MetaS.CodexKill(player, data.TypeKey) end
		end
	end
	if data.Kind == "Elite" then
		Quest.Add(player, "EliteKills", 1)
	elseif data.Kind == "Boss" then
		Quest.Add(player, "BossKills", 1)
		pcall(Stage.Victory, player, part, data, firstBoss) -- 승리 연출
	else
		Quest.Add(player, "FieldKills", 1)
	end

	-- 장비 전리품 (개인 전리품: 처치한 본인에게만 보임)
	if data.Kind ~= "Boss" then
		PartyShare.DropFor(rewarded or { player }, dropPosition(part), data.Kind, data.Zone)
	end

	if data.Kind == "Elite" and math.random() < F.EliteTicketChance then
		player:SetAttribute("Tickets", (player:GetAttribute("Tickets") or 0) + 1)
	elseif data.Kind == "Boss" then
		local bossPosition = part.Position
		for _, other in ipairs(Players:GetPlayers()) do
			local drop = Config.Keys.DropByZone and Config.Keys.DropByZone[data.Zone] or { Tier = 1, Chance = Config.Keys.BossDropChance }
			if other:GetAttribute("Zone") == "Field" and getAliveParts(other) and not other:GetAttribute("TutorialRiftBusy") and math.random() < drop.Chance then -- 던전 열쇠 (튜토리얼 군주는 큰 열쇠 아이템을 따로 떨어뜨린다: DoomScene): 구역마다 단계 / 확률이 다르다
				local rootForKey = getAliveParts(other)
				-- 하루 드랍 한도 (단계별, UTC 날짜 기준)
				local riftState = Meta.GetRift(other)
				local today = math.floor(os.time() / 86400)
				if riftState and riftState.KeyDay ~= today then
					riftState.KeyDay = today
					riftState.KeyDropsTier = { 0, 0, 0 }
				end
				riftState = riftState or {}
				riftState.KeyDropsTier = riftState.KeyDropsTier or { 0, 0, 0 }
				local capped = (riftState.KeyDropsTier[drop.Tier] or 0) >= (Config.Keys.DailyDropCapByTier[drop.Tier] or 0)
				if rootForKey and not capped and (rootForKey.Position - bossPosition).Magnitude <= 160 then
					local count = math.min(drop.Count or 1, (Config.Keys.DailyDropCapByTier[drop.Tier] or 0) - (riftState.KeyDropsTier[drop.Tier] or 0))
					riftState.KeyDropsTier[drop.Tier] = (riftState.KeyDropsTier[drop.Tier] or 0) + count
					Keys.Add(other, count)
					Effects.FloatText(rootForKey.Position + Vector3.new(0, 6, 0), "🔑 Key +" .. count, Color3.fromRGB(160, 255, 200))
				end
			end
			local root = getAliveParts(other)
			if other:GetAttribute("Zone") == "Field" and root and (root.Position - bossPosition).Magnitude <= 160 then
				other:SetAttribute("Tickets", (other:GetAttribute("Tickets") or 0) + F.BossTickets)
				Loot.DropFor(other, dropPosition(part), "Boss", data.Zone)
				Aug.NoteBoss(other, data.Zone) -- 이 구역 세트 효과가 열린다 (골드로 활성화)
				if other ~= player then
					Quest.Add(other, "BossKills", 1)
					Level.AddXP(other, Config.Xp.FieldBoss)
				end
				notify(other, string.format("👑 Field Boss defeated! Tickets +%d, loot dropped", F.BossTickets))
			end
		end
	end
end

local augRun -- 세트 효과(미사일 / 번개 / 칼날 ...)용 "run 비슷한 표": Field.Init 에서 만든다
-- 전투 기록 (Studio 출력창): 구역 / 종류별로 "처음 맞은 뒤 죽기까지 걸린 시간"을 모아 1분마다 한 줄로 찍는다. 난이도 조정 근거용.
local combatLog = setmetatable({}, { __mode = "k" }) -- [player] = { [키] = { N, Ttk, Hp } }
local function recordKill(player, data)
	if not data.FirstHit or data.Kind == "Goblin" or data.Kind == "Event" then return end
	local ttk = os.clock() - data.FirstHit
	local log = combatLog[player]
	if not log then log = {} combatLog[player] = log end
	local key = string.format("Zone %d %s%s", data.Zone or 0, data.Kind == "Boss" and "Lord" or (data.Kind == "Elite" and "Elite " or ""), (data.Kind ~= "Boss" and data.Def and data.Def.Name) or "")
	local entry = log[key]
	if not entry then entry = { N = 0, Ttk = 0, Hp = 0 } log[key] = entry end
	entry.N += 1
	entry.Ttk += ttk
	entry.Hp += data.MaxHealth
end
task.spawn(function()
	while true do
		task.wait(60)
		for player, log in pairs(combatLog) do
			if player.Parent then
				local lines = {}
				for key, entry in pairs(log) do
					table.insert(lines, string.format("  %s: %d kills · avg %.1fs · HP %d · actual DPS %d", key, entry.N, entry.Ttk / entry.N, entry.Hp / entry.N, (entry.Hp / entry.N) / math.max(0.1, entry.Ttk / entry.N)))
				end
				if #lines > 0 then
					table.sort(lines)
					print(string.format("[Combat Log] %s · Power %d · Weapon Lv.%d · Level %d\n%s", player.Name, player:GetAttribute("Power") or 0, player:GetAttribute("WeaponLevel") or 0, player:GetAttribute("Level") or 1, table.concat(lines, "\n")))
				end
				combatLog[player] = nil
			end
		end
	end
end)

-- 다시 태어나는 몬스터의 절반은 그 구역에서 싸우는 플레이어 근처(60~140 스터드 앞뒤)에 나온다: 잡은 자리가 비어서 썰렁해지지 않게.
-- (나머지 절반은 예전처럼 구역 어디서나 태어난다. 꺾임 벽 위는 피한다)
local function respawnSpot(zone)
	if math.random() < 0.5 then return nil end
	local spots = {}
	for _, other in ipairs(Players:GetPlayers()) do
		local root = other:GetAttribute("Zone") == "Field" and getAliveParts(other)
		if root and zoneOfX(root.Position.X) == zone then table.insert(spots, root.Position) end
	end
	if #spots == 0 then return nil end
	local center = spots[math.random(#spots)]
	local x0, x1 = zoneBounds(zone)
	local lo, hi = math.floor(x0 + F.CampSafe + 70), math.floor(x1 - 25)
	local x
	for _ = 1, 6 do
		x = freeX(math.floor(math.max(lo, center.X - 140)), math.floor(math.min(hi, center.X + 140)))
		if math.abs(x - center.X) >= 60 then break end
	end
	local half = F.Width / 2 - 25
	return Vector3.new(x, 0, math.clamp(center.Z + math.random(-60, 60), -half, half))
end

-- 피버 타임 포탈: 군주를 쓰러뜨리면 가끔 그 자리에 황금 균열이 15초 동안 열린다 (막타를 친 사람만 들어간다). 하루 횟수는 저장 / 재사용 대기(10분)는 접속 중에만 센다
local feverState = setmetatable({}, { __mode = "k" }) -- [player] = { Until }
local function maybeFeverPortal(player, bossAt, zone)
	local Fv = Config.Fever
	if not Fv or player:GetAttribute("TutorialActive") == true or player:GetAttribute("TutorialDoom") or player:GetAttribute("InDoomArena") then return end
	local today = math.floor(os.time() / 86400)
	local st = feverState[player]
	if not st then
		st = { Until = 0 }
		feverState[player] = st
	end
	-- 하루 횟수는 저장 데이터(MetaService 의 Rift 기록: FeverDay / FeverUsed)에 남긴다: 다시 접속해도 늘어나지 않는다
	local okMeta, Meta = pcall(function() return require(script.Parent:WaitForChild("MetaService")) end)
	local saved = okMeta and Meta.GetRift and Meta.GetRift(player)
	if not saved then return end -- (저장 데이터를 아직 못 불러왔으면 열지 않는다)
	if saved.FeverDay ~= today then
		saved.FeverDay, saved.FeverUsed = today, 0
	end
	if (saved.FeverUsed or 0) >= Fv.DailyMax or os.clock() < st.Until or math.random() >= Fv.PortalChance then return end
	st.Until = os.clock() + Fv.PortalSeconds + 1 -- (열려 있는 동안 다른 군주로 또 열리지 않게)
	local ground = Vector3.new(bossAt.X, floorAt(bossAt.X), bossAt.Z)
	local center = ground + Vector3.new(0, 7, 0)
	local model = Instance.new("Model")
	model.Name = "FeverPortal"
	local gold, deep = Color3.fromRGB(255, 205, 70), Color3.fromRGB(255, 140, 40)
	local function piece(size, cf, color, transparency, shape)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Size, p.CFrame, p.Color, p.Material, p.Transparency = size, cf, color, Enum.Material.Neon, transparency or 0
		if shape then p.Shape = shape end
		p.Parent = model
		return p
	end
	for i = 0, 13 do -- 세로로 선 고리 (필드 진행 방향 X 를 바라본다)
		local a = i / 14 * math.pi * 2
		piece(Vector3.new(1.2, 2.6, 1.2), CFrame.new(center + Vector3.new(0, math.sin(a) * 6.5, math.cos(a) * 6.5)) * CFrame.Angles(a, 0, 0), i % 2 == 0 and gold or deep)
	end
	local veil = piece(Vector3.new(0.4, 12, 12), CFrame.new(center) * CFrame.Angles(0, 0, 0), gold, 0.45, Enum.PartType.Cylinder)
	piece(Vector3.new(0.3, 26, 26), CFrame.new(ground + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), gold, 0.7, Enum.PartType.Cylinder)
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = gold, 40, 2
	light.Parent = veil
	local sparks = Instance.new("ParticleEmitter")
	sparks.Rate, sparks.Lifetime, sparks.Speed = 30, NumberRange.new(1, 2), NumberRange.new(4, 8)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Color = ColorSequence.new(gold)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	sparks.Parent = veil
	local sign = Instance.new("BillboardGui")
	sign.Size, sign.StudsOffset, sign.AlwaysOnTop, sign.MaxDistance = UDim2.fromOffset(260, 60), Vector3.new(0, 9, 0), true, 220
	sign.Parent = veil
	local text = Instance.new("TextLabel")
	text.Size, text.BackgroundTransparency = UDim2.fromScale(1, 1), 1
	text.Font, text.TextScaled = Enum.Font.GothamBlack, true
	text.TextColor3, text.TextStrokeTransparency = gold, 0.2
	text.Parent = sign
	model.Parent = worldFolder
	notify(player, string.format("🌟 A golden FEVER portal opened where the Colossus fell! Step in within %d seconds!", Fv.PortalSeconds))
	task.spawn(function()
		local expires = os.clock() + Fv.PortalSeconds
		while model.Parent and os.clock() < expires and player.Parent do
			text.Text = string.format("🌟 FEVER PORTAL  %ds", math.ceil(expires - os.clock()))
			veil.CFrame = veil.CFrame * CFrame.Angles(0.15, 0, 0)
			local root = getAliveParts(player)
			if root and player:GetAttribute("Zone") == "Field" and (root.Position - center).Magnitude <= 9 then
				saved.FeverUsed = (saved.FeverUsed or 0) + 1
				st.Until = os.clock() + Fv.Cooldown
				model:Destroy()
				Effects.Burst(center, gold, 90)
				if not Dungeon.StartFever(player, zone, CFrame.new(ground + Vector3.new(-14, 4, 0))) then
					saved.FeverUsed = math.max(0, (saved.FeverUsed or 1) - 1)
					st.Until = os.clock() + 20
				end
				return
			end
			task.wait(0.15)
		end
		if model.Parent then model:Destroy() end
		st.Until = math.min(st.Until, os.clock() + 5) -- 못 들어갔으면 다음 군주에서 다시 기회
	end)
end

local function killMonster(player, part, data)
	if data.Kind == "Event" and Config.Fever then
		-- 피버 포탈: 필드 보스(거신)를 쓰러뜨리면 보상을 받는 사람(막타 + 충분히 싸운 사람)마다 자기 포탈이 열린다
		local bossAt, bossZone = part.Position, data.Zone
		local index = 0
		for member, damage in pairs(data.Contrib or {}) do
			if typeof(member) == "Instance" and member.Parent and (member == player or damage >= data.MaxHealth * Config.Events.ContribMin) then
				index += 1
				task.defer(maybeFeverPortal, member, bossAt + Vector3.new(0, 0, (index - 1) * 18 * (index % 2 == 0 and 1 or -1)), bossZone)
			end
		end
		if index == 0 then task.defer(maybeFeverPortal, player, bossAt, bossZone) end
	end
	recordKill(player, data)
	if augRun then Dungeon.AugOnKill(augRun, player, part.Position) end -- 처치 폭발 / 화염 지대 (monsters 에서 지우기 전: 자기 자신은 다시 맞지 않는다)
	monsters[part] = nil
	if data.Kind == "Boss" and data.Zone == 1 then
		-- 튜토리얼: 군주를 한 대라도 때린 튜토리얼 플레이어는 막타를 누가 쳤든 각자 열쇠 이벤트를 받는다 (같은 군주를 여럿이 잡는 이벤트성 상황)
		local bossAt = part.Position
		local helpers = { [player] = true }
		for contributor in pairs(data.Contrib or {}) do helpers[contributor] = true end
		for member in pairs(helpers) do
			if typeof(member) == "Instance" and member.Parent and member:GetAttribute("TutorialDoom") then
				member:SetAttribute("TutorialRetryBuff", nil) -- 일회성 힘은 군주를 쓰러뜨리면 사라진다
				Remotes.Tutorial:FireClient(member, "WaypointClear") -- 길잡이 빛기둥도 끈다
				local memberRoot = getAliveParts(member)
				-- (보스 근처 160 안에 있어야 군주 처치로 인정되어 다음 단계로 넘어간다: 아래 reward 의 BossKills 와 같은 조건)
				if startTutorialRift and (member == player or (memberRoot and member:GetAttribute("Zone") == "Field" and (memberRoot.Position - bossAt).Magnitude <= 160)) then
					task.spawn(startTutorialRift, member, bossAt) -- 군주가 열쇠를 떨어뜨리고 던전의 문이 열린다
				end
			end
		end
	end
	Effects.Burst(part.Position, part.Color, data.Kind == "Boss" and 80 or 22)
	Effects.MonsterDeath(part, data) -- 조각 / 영혼 연기 (클라이언트)
	part:Destroy()
	Combo.Kill(player)
	reward(player, data, part)
	-- 처치 연출: 금화가 사방으로 튄다
	Effects.Burst(part.Position + Vector3.new(0, 2, 0), Color3.fromRGB(255, 215, 90), data.Kind == "Boss" and 60 or 14)

	local zone, kind = data.Zone, data.Kind
	if data.Ambush then return end -- 습격 몬스터는 다시 생기지 않는다
	if kind == "Goblin" then return end -- 다시 나타나지 않는다 (다음 출현은 타이머)
	if kind == "Event" then
		activeEvent = nil -- 이벤트 보스는 다시 나타나지 않는다
		return
	end
	local delay = F.RespawnTime
	if kind == "Boss" then
		delay = (F.BossRespawnByZone and F.BossRespawnByZone[zone]) or F.BossRespawn
		workspace:SetAttribute("BossNext_" .. zone, os.time() + delay) -- 다음 군주 등장 시각 (화면 표시용)
	end
	task.delay(delay, function()
		spawnMonster(zone, kind, kind ~= "Boss" and respawnSpot(zone) or nil)
		if kind == "Boss" then
			workspace:SetAttribute("BossNext_" .. zone, 0)
			for _, other in ipairs(Players:GetPlayers()) do -- 그 구역에 있는 사람들에게 알린다
				local root = getAliveParts(other)
				if other:GetAttribute("Zone") == "Field" and root and zoneOfX(root.Position.X) == zone then
					notify(other, string.format("👑 Zone %d · The Lord of %s has reappeared!", zone, F.ZoneNames[zone]))
				end
			end
		end
	end)
end

------------------------------------------------------------
-- 플레이어 공격 (판정은 서버에서). 필드 밖이면 nil
------------------------------------------------------------
-- 범위 피해 (스킬용). 맞은 위치 목록 반환
function Field.TargetsIn(player, center, radius, limit)
	if player:GetAttribute("Zone") ~= "Field" or player:GetAttribute("CombatLocked") then return nil end
	local list = {}
	if not player:GetAttribute("InDoomArena") and isSafe(center) then return list end -- 안전지대 안에서는 스킬(데드아이 등)도 적을 잡지 못한다
	for part in pairs(monsters) do
		if part.Parent and (part.Position - center).Magnitude <= radius + part.Size.X / 2 and canHitZone(player, part.Position.X) then
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
	if not canHitZone(player, part.Position.X) then return false end
	if data.ExposedUntil and os.clock() < data.ExposedUntil then damage = math.floor(damage * 3) end -- 약점 노출 중 x3
	if data.Kind == "Boss" and data.Zone == 1 and player:GetAttribute("TutorialDoom") then damage = damage * (player:GetAttribute("TutorialRetryBuff") and 10 or 5) end
	local shooterRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if shooterRoot and data.Def and data.Def.Shield then -- 방패 기사: 정면 공격은 막힌다
		local factor = MonsterTypes.ShieldFactor(part, data, shooterRoot.Position)
		if factor < 1 then damage = math.max(1, math.floor(damage * factor)) end
	end
	if data.Invincible then damage = 1 end
	if data.Doom then data.DoomHits = (data.DoomHits or 0) + 1 end
	if data.IntroUntil and os.clock() < data.IntroUntil then damage = 0 end -- 군주 등장 포효 중에는 피해 없음
	damage = math.floor(damage * Dungeon.MarkMult(player, data)) -- 펫 사냥 표식
	data.Health -= damage
	BL.Dmg(player, damage, false)
	local Meter = require(script.Parent.DamageMeter)
	Meter.Add(player, Meter.Source or "Other", damage) -- 대미지 미터기 (데드아이 / 튕김 / 관통 ...)
	if data.Invincible then data.Health = math.max(data.Health, data.MaxHealth * 0.08) end
	data.FirstHit = data.FirstHit or os.clock()
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
		if part.Parent and (part.Position - center).Magnitude <= radius + part.Size.X / 2 and canHitZone(player, part.Position.X) then
			table.insert(targets, { Part = part, Data = data })
		end
	end
	local positions = {}
	for _, target in ipairs(targets) do
		local data = target.Data
		if monsters[target.Part] == data then
			table.insert(positions, target.Part.Position)
			if data.Invincible then damage = 1 end
			if data.ExposedUntil and os.clock() < data.ExposedUntil then damage = math.floor(damage * 3) end -- 약점 노출 중 x3
			if data.IntroUntil and os.clock() < data.IntroUntil then damage = 0 end -- 군주 등장 포효 중에는 피해 없음
			local dealt = math.floor(damage * Dungeon.MarkMult(player, data)) -- 펫 사냥 표식
			data.Health -= dealt
			BL.Dmg(player, dealt, false)
			local Meter = require(script.Parent.DamageMeter)
			Meter.Add(player, Meter.Source or "Other", dealt) -- 대미지 미터기 (스킬 범위 피해)
			if data.Invincible then data.Health = math.max(data.Health, data.MaxHealth * 0.08) end
			data.FirstHit = data.FirstHit or os.clock()
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

local safeShotWarnAt = setmetatable({}, { __mode = "k" })
function Field.Shoot(player, origin, direction)
	if player:GetAttribute("Zone") ~= "Field" or not monstersFolder or player:GetAttribute("CombatLocked") then return nil end -- (연출 중: 끌려가는 동안은 공격이 나가지 않는다)
	-- 안전지대(캠프) 안에서는 사격이 통하지 않는다: 몬스터를 경계에 걸쳐 놓고 안전하게 잡는 꼼수 방지
	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if rootPart and not player:GetAttribute("InDoomArena") and isSafe(rootPart.Position) then -- (소환 결투장은 필드 좌표 밖이라 안전지대로 오인되지 않게 제외)
		if os.clock() - (safeShotWarnAt[player] or 0) > 4 then
			safeShotWarnAt[player] = os.clock()
			notify(player, "🛡 Shots do nothing inside the safe zone! Leave the camp to fight")
		end
		return origin + direction * 40
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { monstersFolder }

	local range = Config.GetRange(player, Config.GetPlayerWeapon(player))
	local result = workspace:Raycast(origin, direction * range, params)
	if not result then
		-- 조준 보정: 작은 일반 몬스터는 샷건 산탄 / 퍼지는 탄이 몸 옆으로 비껴가기 쉽다. 정확히 못 맞혔으면 두툼한 탄(구)으로 한 번 더 훑어 몸 근처를 지나간 탄을 맞은 것으로 쳐 준다
		local budget = Dungeon.AssistLeft[player] -- (서버 부담: 한 번 쏠 때 처음 2발까지만 보정)
		if budget == nil or budget > 0 then
			if budget then Dungeon.AssistLeft[player] = budget - 1 end
			local weapon = Config.GetPlayerWeapon(player)
			local assist = (weapon.Pellets or 1) > 1 and 3 or 1.2
			local okCast, swept = pcall(function() return workspace:Spherecast(origin, assist, direction * range, params) end)
			if okCast then result = swept end
		end
	end
	-- 약점 구슬을 직접 맞힌 경우: 보스를 맞힌 것으로 바꾸고 "약점 명중"으로 처리한다
	local weakDirect = false
	if result and result.Instance.Name == "WeakPoint" and result.Instance.Parent and monsters[result.Instance.Parent] then
		result = { Instance = result.Instance.Parent, Position = result.Position }
		weakDirect = true
	end
	local endPosition = result and result.Position or (origin + direction * range)
	-- 도중에 벽이 있으면 거기서 멈추고 맞히지 못한다
	local clear, stopAt = segmentClear(origin, endPosition)
	if not clear then
		return stopAt
	end

	local data = result and monsters[result.Instance]
	if data and not canHitZone(player, result.Instance.Position.X) then
		return endPosition -- 닫힌 관문 너머: 탄이 벽에 막힌다
	end
	if data then
		player:SetAttribute("HitTick", (player:GetAttribute("HitTick") or 0) + 1) -- 궁극기 게이지는 실제로 맞혔을 때만 찬다
		local damage, isCrit = Dungeon.ComputeDamage(player)
		if data.Invincible then damage, isCrit = 1, false end -- 최후의 군주: 맞는 느낌만 (피해는 1)
		if data.Doom then data.DoomHits = (data.DoomHits or 0) + 1 end -- (몇 번 맞으면 군주가 "스쳤다"고 반응한다)
		-- 약점 구슬: 탄이 지나간 선이 구슬에 닿으면 3배 치명타 + 데드아이 게이지
		if data.WeakPart and data.WeakPart.Parent and not data.WeakHidden and not data.Invincible and player:GetAttribute("ShotManual") == true then -- 직접 조준한 탄만
			local ab = result.Position - origin
			local t = math.clamp((data.WeakPart.Position - origin):Dot(ab) / math.max(ab:Dot(ab), 0.001), 0, 1)
			if weakDirect or (origin + ab * t - data.WeakPart.Position).Magnitude <= data.WeakPart.Size.X * 0.8 then
				-- 약점 명중: 이 공격만 세지는 게 아니라 약점이 "노출"되어 4초 동안 보스가 받는 모든 피해가 x3
				player:SetAttribute("UltCharge", math.min(Config.Skills.Ult.Cost, (player:GetAttribute("UltCharge") or 0) + 6))
				player:SetAttribute("WeakHitTick", (player:GetAttribute("WeakHitTick") or 0) + 1)
				Effects.Burst(data.WeakPart.Position, Color3.fromRGB(255, 235, 80), 24)
				Effects.ExposeBoss(result.Instance, data, Config.WeakExposeSeconds)
			end
		end
		if data.ExposedUntil and os.clock() < data.ExposedUntil then
			damage = math.floor(damage * 3)
			isCrit = true
		end
		-- 첫 구역 군주는 튜토리얼 중에는 훨씬 약하게 (군주를 쓰러뜨려야 다음 장면이 이어진다)
		if data.Kind == "Boss" and data.Zone == 1 and player:GetAttribute("TutorialDoom") then
			damage = damage * (player:GetAttribute("TutorialRetryBuff") and 10 or 5) -- 쓰러졌다 다시 도전하면 일회성 힘 (x10)
		end
		-- 로켓 런처 / 플라즈마 캐논: 맞은 곳 주변 적에게도 피해
		local splash = Config.GetPlayerWeapon(player).Splash
		if splash then
			for otherPart, otherData in pairs(monsters) do
				if otherPart ~= result.Instance and otherPart.Parent and not otherData.Goblin
					and (otherPart.Position - result.Position).Magnitude <= splash + otherPart.Size.X / 2 then
					local splashDamage = math.max(1, math.floor(damage * 0.5))
					otherData.Health -= splashDamage
					BL.DmgAs(player, "스플래시", splashDamage)
					require(script.Parent.DamageMeter).Add(player, "Gun", splashDamage)
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
		-- 무리 어그로: 처음 맞은 몬스터 주변 몬스터들이 같이 달려든다 (한 마리 건드리면 떼로 몰려온다)
		if not data.LastHit or os.clock() - data.LastHit > 8 then
			local woken = 0
			for otherPart, otherData in pairs(monsters) do
				if woken >= 8 then break end
				if otherData ~= data and otherPart.Parent and not otherData.BossLike and (otherPart.Position - result.Instance.Position).Magnitude < 38 then
					otherData.LastHit = os.clock()
					woken += 1
				end
			end
		end
		-- 타격감: 맞으면 살짝 뒤로 밀린다
		if not data.BossLike and data.Kind ~= "Event" then
			local away = Vector3.new(result.Instance.Position.X - origin.X, 0, result.Instance.Position.Z - origin.Z)
			if away.Magnitude > 0.1 then
				local pushed = result.Instance.Position + away.Unit * 1.3
				if walkableAt(pushed.X, pushed.Z) then
					result.Instance.Position = pushed
				end
			end
		end
		if data.Def and data.Def.Shield then -- 방패 기사: 정면 공격은 막힌다 (뒤 / 옆에서 쏴야 한다)
			local factor = MonsterTypes.ShieldFactor(result.Instance, data, origin)
			if factor < 1 then
				damage = math.max(1, math.floor(damage * factor))
				Effects.FloatText(result.Position + Vector3.new(0, 3, 0), "🛡 Blocked! Go around", Color3.fromRGB(200, 215, 240))
				if SoundBank.Has("Shield_Block") then SoundBank.Play(result.Instance, "Shield_Block") end
			end
		end
		if data.IntroUntil and os.clock() < data.IntroUntil then damage = 0 end -- 군주 등장 포효 중에는 피해 없음
		damage = math.floor(damage * Dungeon.MarkMult(player, data)) -- 펫 사냥 표식
		data.Health -= damage
		require(script.Parent.DamageMeter).Add(player, "Gun", damage)
		BL.Dmg(player, damage, isCrit)
		data.LastHit = os.clock() -- 맞은 몬스터는 멀리서 맞아도 깨어나 반응하고, 한동안 체력을 되찾지 않는다
		if data.Contrib then
			data.Contrib[player] = (data.Contrib[player] or 0) + damage
		end
		data.HealthFill.Size = UDim2.new(math.max(data.Health, 0) / data.MaxHealth, 0, 1, 0)
		Effects.DamageNumber(result.Position, damage, isCrit)
		Effects.Hit(player, result.Instance, isCrit, data.Health <= 0)
		if augRun then Dungeon.AugOnHit(augRun, player, result.Instance, data, damage, isCrit) end -- 크리 미사일 / 처형
		if data.Health <= 0 then
			killMonster(player, result.Instance, data)
		end
	end
	-- 레일건 등 관통: 첫 목표 뒤쪽, 같은 직선 위에 있는 몬스터도 맞힌다 (던전과 같은 규칙: 1 + 관통 수만큼. 필드에는 이 처리가 빠져 있어서 레일건이 한 마리만 맞혔다)
	local pierce = (player:GetAttribute("PerkPierce") or 0) + (Config.GetPlayerWeapon(player).Pierce or 0)
	if data and result and pierce > 0 then
		local hitParts = { [result.Instance] = true }
		local rayStart = result.Position
		local remaining = range - (result.Position - origin).Magnitude
		for _ = 1, pierce do
			if remaining <= 1 then break end
			local candidates = {}
			for otherPart in pairs(monsters) do
				if otherPart.Parent and not hitParts[otherPart] then table.insert(candidates, otherPart) end
			end
			if #candidates == 0 then break end
			local pierceParams = RaycastParams.new()
			pierceParams.FilterType = Enum.RaycastFilterType.Include
			pierceParams.FilterDescendantsInstances = candidates
			local nextResult = workspace:Raycast(rayStart + direction * 0.5, direction * remaining, pierceParams)
			if not nextResult or not monsters[nextResult.Instance] then break end
			if not (segmentClear(rayStart, nextResult.Position)) then break end -- 중간에 벽이 있으면 막힌다
			hitParts[nextResult.Instance] = true
			local pierceDamage = Dungeon.ComputeDamage(player)
			local Meter = require(script.Parent.DamageMeter)
			Meter.Source = "Gun" -- (관통탄도 총 피해로 센다)
			Field.HitPart(player, nextResult.Instance, pierceDamage)
			Meter.Source = nil
			player:SetAttribute("HitTick", (player:GetAttribute("HitTick") or 0) + 1)
			endPosition = nextResult.Position
			remaining -= (nextResult.Position - rayStart).Magnitude
			rayStart = nextResult.Position
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
	Slope = function(x, size) -- 몸 앞뒤 높이 차로 경사 각도를 구한다 (경사로 위에서 몸을 기울이는 데 쓴다)
		local half = math.max(2, size * 0.5)
		return math.clamp(math.atan2(floorAt(x + half) - floorAt(x - half), half * 2), -0.6, 0.6)
	end,
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
			if not rect.Solid and blockedAt.X >= rect.X0 - 6 and blockedAt.X <= rect.X1 + 6 then
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
	Fire = function(origin, direction, speed, damage, size, color, style, opts)
		fireProjectile(origin, direction, speed, damage, size, color, style, opts)
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
	Monsters = function() return monsters end,
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
		Size = 7, MaxHealth = base.MaxHealth * 7, Speed = 26, ShotDamage = 0, ShotInterval = 99, ShotSpeed = 0,
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
	light.Range = 48
	light.Brightness = 3.5
	light.Color = part.Color
	light.Parent = part

	-- 눈에 확 띄게: 하늘까지 닿는 금빛 기둥 + 금화 / 반짝이 입자 + 왕관 + 눈 + 돈자루 + 어디서든 보이는 큰 이름표
	local function piece(shape, size, offset, color, material)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, false, true
		p.Shape = shape
		p.Size = size
		p.Color = color
		p.Material = material
		p.CFrame = part.CFrame * CFrame.new(offset)
		local weld = Instance.new("Weld") -- (Weld + 명시적 오프셋: WeldConstraint 는 클라이언트가 받는 순간의 위치로 오프셋을 다시 계산해서, 움직이는 몬스터의 겉모양이 본체에서 어긋나 보였다)
		weld.Part0 = part
		weld.Part1 = p
		weld.C0 = part.CFrame:ToObjectSpace(p.CFrame)
		weld.Parent = p
		p.Parent = part
		return p
	end
	local gold = Color3.fromRGB(255, 215, 60)
	local beacon = piece(Enum.PartType.Block, Vector3.new(3, 220, 3), Vector3.new(0, 110, 0), gold, Enum.Material.Neon)
	beacon.Transparency = 0.55
	for i = -1, 1 do
		piece(Enum.PartType.Block, Vector3.new(0.8, 2.6, 0.8), Vector3.new(i * 1.5, stats.Size / 2 + 1, 0), gold, Enum.Material.Neon) -- 왕관 뿔
	end
	piece(Enum.PartType.Block, Vector3.new(4.6, 0.8, 4.6), Vector3.new(0, stats.Size / 2 - 0.2, 0), Color3.fromRGB(255, 240, 150), Enum.Material.Neon) -- 왕관 띠
	for _, side in ipairs({ -1, 1 }) do
		piece(Enum.PartType.Ball, Vector3.new(1.1, 1.1, 1.1), Vector3.new(side * 1.2, 0.6, -stats.Size / 2 + 0.3), Color3.fromRGB(30, 20, 10), Enum.Material.SmoothPlastic)
	end
	piece(Enum.PartType.Ball, Vector3.new(4.2, 4.2, 4.2), Vector3.new(0, -0.5, stats.Size / 2 + 1), Color3.fromRGB(150, 100, 40), Enum.Material.Fabric) -- 돈자루
	local coins = Instance.new("ParticleEmitter")
	coins.Rate = 28
	coins.Lifetime = NumberRange.new(0.8, 1.6)
	coins.Speed = NumberRange.new(4, 9)
	coins.SpreadAngle = Vector2.new(180, 180)
	coins.LightEmission = 1
	coins.Color = ColorSequence.new(gold, Color3.fromRGB(255, 250, 200))
	coins.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
	coins.Parent = part
	local label = Instance.new("BillboardGui")
	label.Size = UDim2.fromOffset(280, 64)
	label.StudsOffset = Vector3.new(0, stats.Size / 2 + 8, 0)
	label.AlwaysOnTop = true
	label.MaxDistance = 700
	label.Parent = part
	local labelText = Instance.new("TextLabel")
	labelText.Size = UDim2.fromScale(1, 1)
	labelText.BackgroundTransparency = 1
	labelText.Text = "💰 Golden Goblin!"
	labelText.Font = Enum.Font.GothamBlack
	labelText.TextScaled = true
	labelText.TextColor3 = Color3.fromRGB(255, 232, 100)
	labelText.TextStrokeTransparency = 0
	labelText.Parent = label

	local data = {
		Zone = zone, Kind = "Goblin", Goblin = true, Level = level, XpLevel = level + 2, Stats = stats,
		Health = stats.MaxHealth, MaxHealth = stats.MaxHealth, Contrib = {},
		HealthFill = createHealthBar(part, "💰 Golden Goblin", 200, Color3.fromRGB(255, 225, 80)),
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
				notify(player, "💨 The Golden Goblin ran away...")
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
	local function clampPosition(p)
		local cx = math.clamp(p.X, x0 + F.CampSafe + 10, x1 - 10)
		return Vector3.new(cx, floorAt(cx) + data.Stats.Size / 2 + math.abs(math.sin(now * 6)) * 1.2, math.clamp(p.Z, -F.Width / 2 + 12, F.Width / 2 - 12))
	end
	-- 벽(꺾임 벽 / 절벽 / 경사로 옆)을 뚫지 않는다: 가려는 방향이 막혀 있으면 옆으로 미끄러지거나 다른 방향을 고른다
	local function passable(a, b)
		return walkableAt(b.X, b.Z) and (segmentClear(Vector3.new(a.X, 0, a.Z), Vector3.new(b.X, 0, b.Z)))
	end
	local position = clampPosition(part.Position + flee)
	if flee.Magnitude > 0 and not passable(part.Position, position) then
		local chosen
		for _, angle in ipairs({ 55, -55, 100, -100, 150, -150 }) do
			local rotated = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(flee)
			local candidate = clampPosition(part.Position + rotated)
			if passable(part.Position, candidate) then
				chosen = candidate
				break
			end
		end
		position = chosen or part.Position
	end
	part.Position = position
end

-- 구역 군주 패턴 (기본 부채꼴 사격 + 전방위 탄막에 더해서 돌려 쓴다): 내려찍기 / 돌진 / 나선 탄막.
-- 체력이 절반 아래면 "격노": 패턴 간격이 짧아지고 한 번에 두 개씩 나온다.
local function playersNear(position, radius)
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Zone") == "Field" then
			local root, humanoid = getAliveParts(player)
			if root and humanoid.Health > 0 and not isSafe(root.Position) then
				local flat = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z)
				if flat.Magnitude <= radius then
					table.insert(list, { Root = root, Humanoid = humanoid })
				end
			end
		end
	end
	return list
end

-- 구역 군주의 기본 공격 탄 모양 / 색 (F.BossShot, 없으면 1구역 모양)
local function bossLook(zone)
	return (F.BossShot and (F.BossShot[zone] or F.BossShot[1])) or { Style = "Crystal", Color = Color3.fromRGB(235, 110, 100), RingStyle = "Crystal", RingColor = Color3.fromRGB(235, 175, 90), MissileStyle = "Missile", MissileColor = Color3.fromRGB(240, 170, 90) }
end

-- 구역 군주 움직임 변화 (F.BossMove): 좌우로 도는 움직임(Strafe) / 가까우면 물러나기(Kite)
local function bossSidestep(part, data, target, dt, mv, distance)
	local flat = Vector3.new(target.Position.X - part.Position.X, 0, target.Position.Z - part.Position.Z)
	if flat.Magnitude < 0.5 then return end
	local toward = flat.Unit
	local dir
	if mv.Kite and distance < data.Stats.Size / 2 + (mv.Keep or 16) - 6 then
		dir = -toward
	elseif mv.Strafe then
		if not data.StrafeUntil or os.clock() > data.StrafeUntil then
			data.StrafeUntil = os.clock() + 1.2 + math.random() * 1.4
			data.StrafeSign = math.random() < 0.5 and -1 or 1
		end
		dir = Vector3.new(-toward.Z, 0, toward.X) * data.StrafeSign * mv.Strafe
	else
		return
	end
	local radius = data.Stats.Size / 2 + 2
	local zx0, zx1 = zoneBounds(data.Zone)
	local half = F.Width / 2
	local factor = 1
	if mv.Burst then -- 멈칫했다가 휙 튀어 나가는 리듬 (약 1.6초 주기: 앞 0.5초는 빠르게, 나머지는 천천히)
		factor = (os.clock() * 0.625) % 1 < 0.3 and mv.Burst or 0.45
	end
	local base = mv.StrafeSpeed or (data.Stats.Speed * (mv.Speed or 1)) -- 옆으로 움직이는 속도는 칸/초로 따로 정한다 (큰 몸집에 비해 느려 보이지 않게)
	local step = dir * base * factor * dt
	local nx = math.clamp(part.Position.X + step.X, zx0 + F.CampSafe + radius, zx1 - radius - 4)
	local nz = math.clamp(part.Position.Z + step.Z, -half + radius + 4, half - radius - 4)
	if walkableAt(nx, nz, radius) then
		local bob = math.sin(os.clock() * 7) * data.Stats.Size * 0.03 -- 움직일 때 위아래로 살짝 흔들려서 살아 있는 느낌
		local newPos = Vector3.new(nx, floorAt(nx) + data.Stats.Size / 2 + bob, nz)
		part.CFrame = CFrame.lookAt(newPos, Vector3.new(target.Position.X, newPos.Y, target.Position.Z)) * CFrame.Angles(0, 0, math.sin(os.clock() * 5) * 0.06)
	else
		data.StrafeSign = -(data.StrafeSign or 1) -- 막히면 반대 방향으로 (제자리에서 떨리지 않게)
		data.StrafeUntil = os.clock() + 1
	end
end

local function bossCue(part, text, color)
	Effects.FloatText(part.Position + Vector3.new(0, part.Size.Y / 2 + 4, 0), text, color)
end

local function bossSlam(part, data)
	local target = nearestFieldPlayer(part.Position)
	if not target then return end
	bossCue(part, "⚠ Slam!", Color3.fromRGB(255, 120, 80))
	local spots = { Vector3.new(target.Position.X, 0, target.Position.Z) }
	if data.Enraged then
		table.insert(spots, spots[1] + Vector3.new(16, 0, 10))
		table.insert(spots, spots[1] + Vector3.new(-16, 0, -10))
	end
	for _, spot in ipairs(spots) do
		local radius = 12
		local warn = Instance.new("Part")
		warn.Shape = Enum.PartType.Cylinder
		warn.Size = Vector3.new(0.3, radius * 2, radius * 2)
		warn.CFrame = CFrame.new(spot.X, floorAt(spot.X) + 0.3, spot.Z) * CFrame.Angles(0, 0, math.rad(90))
		warn.Anchored = true
		warn.CanCollide = false
		warn.CanQuery = false
		warn.Material = Enum.Material.Neon
		warn.Color = Color3.fromRGB(255, 50, 50)
		warn.Transparency = 0.55
		warn.Parent = worldFolder
		TweenService:Create(warn, TweenInfo.new(1.2), { Transparency = 0.1 }):Play()
		task.delay(1.2, function()
			warn:Destroy()
			if monsters[part] ~= data then return end
			Effects.Burst(Vector3.new(spot.X, floorAt(spot.X) + 2, spot.Z), Color3.fromRGB(255, 140, 70), 60)
			for _, entry in ipairs(playersNear(spot, radius)) do
				Guard.Take(entry.Humanoid, math.floor(data.Stats.ShotDamage * 1.4))
			end
		end)
	end
end

local function bossCharge(part, data)
	local target = nearestFieldPlayer(part.Position)
	if not target then return end
	local direction = Vector3.new(target.Position.X - part.Position.X, 0, target.Position.Z - part.Position.Z)
	if direction.Magnitude < 1 then return end
	direction = direction.Unit
	bossCue(part, "⚠ Charge!", Color3.fromRGB(255, 200, 70))
	local length = 64
	local warn = Instance.new("Part")
	warn.Size = Vector3.new(10, 0.3, length)
	warn.CFrame = CFrame.lookAt(Vector3.new(part.Position.X, floorAt(part.Position.X) + 0.3, part.Position.Z) + direction * (length / 2), Vector3.new(part.Position.X, floorAt(part.Position.X) + 0.3, part.Position.Z) + direction * length)
	warn.Anchored = true
	warn.CanCollide = false
	warn.CanQuery = false
	warn.Material = Enum.Material.Neon
	warn.Color = Color3.fromRGB(255, 70, 40)
	warn.Transparency = 0.55
	warn.Parent = worldFolder
	TweenService:Create(warn, TweenInfo.new(1.0), { Transparency = 0.1 }):Play()
	data.BusyUntil = os.clock() + 2.0
	task.delay(1.0, function()
		warn:Destroy()
		if monsters[part] ~= data then return end
		local hitOnce = {}
		local radius = data.Stats.Size / 2 + 2
		for _ = 1, 12 do -- 약 0.5초 동안 돌진 (64칸)
			if monsters[part] ~= data then return end
			local nx, nz = part.Position.X + direction.X * length / 12, part.Position.Z + direction.Z * length / 12
			local zx0, zx1 = zoneBounds(data.Zone)
			if not walkableAt(nx, nz, radius) or nx < zx0 + F.CampSafe + radius or nx > zx1 - radius - 4 or math.abs(nz) > F.Width / 2 - radius - 4 then break end
			part.CFrame = CFrame.lookAt(Vector3.new(nx, floorAt(nx) + data.Stats.Size / 2, nz), Vector3.new(nx + direction.X, floorAt(nx) + data.Stats.Size / 2, nz + direction.Z))
			for _, entry in ipairs(playersNear(part.Position, radius + 4)) do
				if not hitOnce[entry.Humanoid] then
					hitOnce[entry.Humanoid] = true
					Guard.Take(entry.Humanoid, math.floor(data.Stats.ShotDamage * 1.6))
					Effects.Burst(entry.Root.Position, Color3.fromRGB(255, 200, 90), 30)
				end
			end
			task.wait(0.04)
		end
	end)
end

local function bossSpiral(part, data)
	bossCue(part, "⚠ Spiral Barrage!", Color3.fromRGB(255, 160, 255))
	data.BusyUntil = os.clock() + 0.4
	task.spawn(function()
		local started = os.clock()
		local arms = data.Enraged and 3 or 2
		while os.clock() - started < 2.6 and monsters[part] == data do
			local t = os.clock() - started
			for arm = 0, arms - 1 do
				local angle = t * 3.4 + arm * (math.pi * 2 / arms)
				local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
				fireProjectile(Vector3.new(part.Position.X, floorAt(part.Position.X) + 3, part.Position.Z) + direction * (part.Size.X / 2 + 1), direction, 22, math.floor(data.Stats.ShotDamage * 0.6), 2.4, Color3.fromRGB(235, 130, 215), arm % 2 == 0 and "Crystal" or "Skull") -- 나선 팔마다 모양이 다르다
			end
			task.wait(0.13) -- 탄 수 약 -40% (성기고 읽기 쉽게)
		end
	end)
end

Stage.Init({ GetWorldFolder = function() return worldFolder end, FloorAt = floorAt, Effects = Effects })
local ExtraBossPatterns = require(script.Parent:WaitForChild("FieldBossPatterns")).Init({
	Monsters = monsters, GetWorldFolder = function() return worldFolder end, FloorAt = floorAt, NearestFieldPlayer = nearestFieldPlayer,
	PlayersNear = playersNear, WalkableAt = walkableAt, Effects = Effects, Guard = Guard,
})
local bossPatterns = { { Fn = bossSlam, Weight = 3, Name = "slam" }, { Fn = bossCharge, Weight = 2, Name = "charge" }, { Fn = bossSpiral, Weight = 2, Name = "spiral" } }
local function pickBossPattern(data)
	-- 구역마다 비중이 다르다 (F.BossStyle) + 2~8구역은 고유 패턴이 하나 더 섞인다
	local style = F.BossStyle and F.BossStyle[data.Zone]
	local list = {}
	for _, entry in ipairs(bossPatterns) do
		table.insert(list, { Entry = entry, Weight = style and style[entry.Name] or entry.Weight })
	end
	local signature = ExtraBossPatterns[data.Zone]
	if signature then table.insert(list, { Entry = signature, Weight = F.BossSignatureWeight or 3.5 }) end
	local total = 0
	for _, item in ipairs(list) do
		if item.Entry.Name ~= data.LastPattern then total += item.Weight end
	end
	local roll = math.random() * total
	for _, item in ipairs(list) do
		if item.Entry.Name ~= data.LastPattern then
			roll -= item.Weight
			if roll <= 0 then
				return item.Entry
			end
		end
	end
	return bossPatterns[1]
end

-- 최적화: 아무도 없는 구역의 몬스터는 (제자리에서 쉬고 있다면) 계산을 건너뛴다. 8개 구역 수백 마리가 사람이 없어도 매 프레임 계산되던 것을 막는다.
local occupiedZones, occupiedAt = {}, 0
local function refreshOccupied(now)
	if now - occupiedAt < 0.25 then return end
	occupiedAt = now
	table.clear(occupiedZones)
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Zone") == "Field" then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then occupiedZones[F.ZoneOfX(root.Position.X)] = true end
		end
	end
end

-- 몬스터가 벽 / 땅에 끼면(돌진 / 경사로 / 구역 끝에서 생기던 문제) 가까운 빈 자리로 꺼내 준다. 정상일 때는 아무것도 하지 않는다.
local function unstick(part, data)
	local size = data.Stats.Size
	local r = size / 2
	local zx0, zx1 = zoneBounds(data.Zone)
	local pos = part.Position
	local x = math.clamp(pos.X, zx0 + F.CampSafe + r, zx1 - r - 4)
	local z = math.clamp(pos.Z, -F.Width / 2 + r + 4, F.Width / 2 - r - 4)
	if not walkableAt(x, z, r * 0.6) then
		local pad = r * 0.6 + 3
		for _, rect in ipairs(baffleRects) do
			if x >= rect.X0 - pad and x <= rect.X1 + pad and z >= rect.Z0 - pad and z <= rect.Z1 + pad then
				-- 벽 사각형의 네 변 중 가장 가까운 쪽으로 빠져나온다
				local options = {
					{ d = x - (rect.X0 - pad), nx = rect.X0 - pad - 1, nz = z },
					{ d = (rect.X1 + pad) - x, nx = rect.X1 + pad + 1, nz = z },
					{ d = z - (rect.Z0 - pad), nx = x, nz = rect.Z0 - pad - 1 },
					{ d = (rect.Z1 + pad) - z, nx = x, nz = rect.Z1 + pad + 1 },
				}
				table.sort(options, function(a, b) return a.d < b.d end)
				for _, option in ipairs(options) do
					if option.nx > zx0 + F.CampSafe + r and option.nx < zx1 - r - 4 and math.abs(option.nz) < F.Width / 2 - r - 4 and walkableAt(option.nx, option.nz, r * 0.6) then
						x, z = option.nx, option.nz
						break
					end
				end
				break
			end
		end
	end
	local y = floorAt(x) + r
	-- 몸이 눕거나 크게 기운 채로 남았으면(돌진 / 밀림 뒤) 바로 세운다: 앞 방향(yaw)만 남기고 평평하게
	local cf = part.CFrame
	if cf.UpVector.Y < 0.7 and not data.Static then
		local look = cf.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flatLook.Magnitude < 0.05 then flatLook = Vector3.new(0, 0, -1) end
		part.CFrame = CFrame.lookAt(Vector3.new(pos.X, y, pos.Z), Vector3.new(pos.X, y, pos.Z) + flatLook.Unit)
		data.Lean = 0
		pos = part.Position
	end
	if math.abs(pos.X - x) > 0.05 or math.abs(pos.Z - z) > 0.05 or pos.Y < y - r * 0.35 or pos.Y > y + r * 2.5 then
		part.CFrame = CFrame.new(Vector3.new(x, y, z)) * (part.CFrame - part.CFrame.Position)
	end
end

local function stepMonsters(dt)
	local now = os.clock()
	refreshOccupied(now)
	for part, data in pairs(monsters) do
		if not data.PlacedChecked then -- 태어난 직후 한 번: 벽 / 바위 속에 태어났으면 빈 자리로 꺼낸다 (총알도 타게팅도 안 되는 몬스터 방지)
			data.PlacedChecked = true
			if part.Parent and data.Home and not data.BossLike and not data.Falling and not data.Goblin and data.Kind ~= "Event" then
				unstick(part, data)
				data.Home = part.Position
			end
		end
		-- 벽 / 바위 뒤에 숨어서 총알도 조준도 닿지 않는 몬스터 구출: 플레이어와 시야가 20초 넘게 막혀 있으면 열린 자리(시야가 트인 곳)로 옮긴다
		-- (전투 기록에서 처치까지 100~600초씩 걸리던 몬스터들 = 벽 뒤에 박혀 있던 것)
		if occupiedZones[data.Zone] and not data.BossLike and not data.Falling and not data.Goblin and data.Kind ~= "Event" and part.Parent and now >= (data.NextHiddenCheck or 0) then
			data.NextHiddenCheck = now + 1
			local root, dist = nearestFieldPlayer(part.Position)
			if root and dist < 260 then
				if segmentClear(root.Position, part.Position) then
					data.HiddenFor = 0
				else
					data.HiddenFor = (data.HiddenFor or 0) + 1
				end
				if data.HiddenFor >= 20 or (data.FirstHit and now - data.FirstHit > 60) then -- (시야가 막혔거나 / 맞은 지 60초가 넘도록 못 잡은 몬스터)
					data.HiddenFor = 0
					data.FirstHit = nil
					local r = data.Stats.Size / 2
					local zx0, zx1 = zoneBounds(data.Zone)
					for _ = 1, 24 do
						local x = math.clamp(root.Position.X + math.random(30, 140), zx0 + F.CampSafe + r + 10, zx1 - r - 10)
						local z = math.random(-F.Width / 2 + r + 8, F.Width / 2 - r - 8)
						if walkableAt(x, z, r) and segmentClear(root.Position, Vector3.new(x, root.Position.Y, z)) then
							part.CFrame = CFrame.new(Vector3.new(x, floorAt(x) + r, z)) * (part.CFrame - part.CFrame.Position)
							data.Home = part.Position
							data.Aggro = false
							Effects.Burst(part.Position, part.Color, 12)
							break
						end
					end
				end
			else
				data.HiddenFor = 0
			end
		end
		if not occupiedZones[data.Zone] and not data.Aggro and not data.Goblin and not data.Falling and not data.Beam and not data.Static
			and data.Health >= data.MaxHealth and data.Home and (part.Position - data.Home).Magnitude < 2.5 then
			continue -- 이 구역에는 아무도 없고 몬스터는 제자리에서 멀쩡하다: 할 일이 없다
		end
		if data.Beam and data.Beam.Parent then data.Beam.CFrame = CFrame.new(part.Position + Vector3.new(0, 210, 0)) end -- 거신 빛기둥은 항상 몸 위에
		if data.WeakPart and data.WeakPart.Parent then -- 약점 구슬: 보스 몸 주위를 돌며 위아래로 흔들린다
			local radius = part.Size.X / 2 + 7 -- 보스 몸(날개 / 뿔 장식 포함) 밖으로 충분히 떨어져 돈다
			local angle = now * 1.5 + data.Phase
			data.WeakPart.Position = part.Position + Vector3.new(math.cos(angle) * radius, math.sin(now * 0.9) * radius * 0.35, math.sin(angle) * radius)
		end
		if data.Static then continue end -- 소환 결투의 군주: 제자리에서 연출만 한다
		if data.Falling then
			-- 공습 낙하병: 낙하산을 펴고 하늘에서 내려온다. 땅에 닿으면 충격으로 주변이 피해를 입고 그때부터 싸운다
			local landY = floorAt(part.Position.X) + data.Stats.Size / 2
			local newY = math.max(landY, part.Position.Y - 48 * dt)
			part.Position = Vector3.new(part.Position.X, newY, part.Position.Z)
			if newY <= landY + 0.01 then
				data.Falling = nil
				local chute = part:FindFirstChild("Chute")
				if chute then chute:Destroy() end
				local at = Vector3.new(part.Position.X, landY, part.Position.Z)
				Effects.Burst(at, Color3.fromRGB(230, 210, 170), 24)
				for _, other in ipairs(Players:GetPlayers()) do
					local otherRoot, humanoid = getAliveParts(other)
					if otherRoot and other:GetAttribute("Zone") == "Field" and not isSafe(otherRoot.Position)
						and (Vector3.new(otherRoot.Position.X, 0, otherRoot.Position.Z) - Vector3.new(at.X, 0, at.Z)).Magnitude < 8 then
						Guard.Take(humanoid, math.max(3, math.floor(data.Stats.ShotDamage * 0.8)))
					end
				end
			end
			continue
		end
		if data.Goblin then
			stepGoblin(part, data, dt, now)
			continue
		end
		local target, distance = nearestFieldPlayer(part.Position)
		local range = data.Aggro and F.LeashRange or F.AggroRange
		local fromHome = (part.Position - data.Home).Magnitude
		-- 최근에 맞았으면(저격 / 장거리 사격 포함) 거리와 상관없이 깨어나서 반응한다
		local recentlyHit = data.LastHit ~= nil and now - data.LastHit < 8

		if target and ((distance <= range and (not data.HitOnly or data.Aggro)) or recentlyHit) and fromHome <= F.LeashRange * 1.5 then
			data.Aggro = true

			if not data.BossLike then
				-- 일반 몬스터 / 엘리트: 종류별 움직임과 공격
				MonsterTypes.Update(fieldCtx, part, data, dt, now)
				if part.Parent and monsters[part] == data then unstick(part, data) end
			else
				local mv = F.BossMove and F.BossMove[data.Zone]
				local keepDistance = data.Stats.Size / 2 + ((mv and mv.Keep) or 16)
				if mv and distance <= keepDistance + 12 and now >= (data.BusyUntil or 0) then
					bossSidestep(part, data, target, dt, mv, distance) -- 구역마다 다른 움직임 (옆으로 돌기 / 물러나기)
				end
				if distance > keepDistance and now >= (data.BusyUntil or 0) then
					local flatTarget = Vector3.new(target.Position.X, part.Position.Y, target.Position.Z)
					local move = flatTarget - part.Position
					if move.Magnitude > 0.1 then
						local speed = data.Stats.Speed * ((mv and mv.Speed) or 1) * dt
						local step = move.Unit * speed
						local radius = data.Stats.Size / 2 + 2
						local zx0, zx1 = zoneBounds(data.Zone)
						local half = F.Width / 2
						local pos = part.Position
						local function place(dx, dz) -- 구역 끝 벽 / 옆 절벽에도 몸이 끼지 않게 범위를 자르고, 걸을 수 있으면 이동
							local nx = math.clamp(pos.X + dx, zx0 + F.CampSafe + radius, zx1 - radius - 4)
							local nz = math.clamp(pos.Z + dz, -half + radius + 4, half - radius - 4)
							if walkableAt(nx, nz, radius) then
								local newPos = Vector3.new(nx, floorAt(nx) + data.Stats.Size / 2, nz)
								part.CFrame = CFrame.lookAt(newPos, Vector3.new(target.Position.X, newPos.Y, target.Position.Z)) -- 항상 플레이어를 바라본다
								return true
							end
							return false
						end
						local moved = place(step.X, step.Z) or place(step.X, 0) or place(0, step.Z) -- 벽에 막히면 벽을 따라 미끄러진다
						if not moved then
							-- 정면이 벽: 벽의 틈(가까운 쪽 끝)으로 돌아간다. 이미 벽 안쪽 여유 공간에 끼어 있으면 먼저 빼낸다.
							for _, rect in ipairs(baffleRects) do
								if pos.X >= rect.X0 - radius - 30 and pos.X <= rect.X1 + radius + 30 then
									if not walkableAt(pos.X, pos.Z, radius) then
										local wallCenterX = (rect.X0 + rect.X1) / 2
										moved = place((pos.X < wallCenterX and -1 or 1) * speed * 2, 0)
									else
										local upper = rect.Z1 < half - 1 and (rect.Z1 + half) / 2 or nil
										local lower = rect.Z0 > -half + 1 and (-half + rect.Z0) / 2 or nil
										local gapZ = upper
										if upper and lower then
											gapZ = math.abs(upper - pos.Z) < math.abs(lower - pos.Z) and upper or lower
										elseif not upper then
											gapZ = lower
										end
										if gapZ then
											moved = place(0, (gapZ > pos.Z and 1 or -1) * speed)
										end
									end
									if moved then break end
								end
							end
						end
					end
				end

				if now >= data.NextShot then
					data.NextShot = now + data.Stats.ShotInterval
					telegraph(part, data, Color3.fromRGB(255, 220, 80), 0.4, function()
						local current = nearestFieldPlayer(part.Position)
						if not current then return end
						local direction = current.Position - part.Position
						-- 5갈래 -> 3갈래 수정 + (1구역 군주 제외) 느린 유도 미사일 한 발. 1구역 군주는 튜토리얼이라 순한 직선탄만.
						local gentle = data.Zone == 1
						local look = bossLook(data.Zone)
						for _, angle in ipairs(gentle and { -16, 0, 16 } or { -18, 0, 18 }) do
							fireProjectile(part.Position, rotateY(direction.Unit, angle), data.Stats.ShotSpeed * 0.9, math.floor(data.Stats.ShotDamage * (gentle and 1 or 1.2)), 3, look.Color, look.Style)
						end
						if not gentle and look.MissileStyle then
							fireProjectile(part.Position + Vector3.new(0, 2, 0), direction.Unit, 26, math.floor(data.Stats.ShotDamage * 1.1), 2.4, look.MissileColor, look.MissileStyle, { Kind = "homing", Turn = 1.6, Life = 3.5 })
						end
					end)
				end

				-- 보스: 주기적으로 전방위 탄막
				if now >= data.NextRing then
					data.NextRing = now + 7
					telegraph(part, data, Color3.new(1, 1, 1), 0.8, function()
						-- 16발 -> 11발, 더 느리게. 곧은 수정 고리와 휘어 도는 바람개비 고리를 번갈아 (1구역 군주는 곧은 고리만)
						data.RingN = (data.RingN or 0) + 1
						local swirl = data.RingN % 2 == 0 and data.Zone ~= 1
						local count = 11
						local offset = math.random() * math.pi * 2
						for i = 0, count - 1 do
							local angle = offset + (i / count) * math.pi * 2
							local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
							fireProjectile(Vector3.new(part.Position.X, floorAt(part.Position.X) + 3, part.Position.Z) + direction * (part.Size.X / 2 + 1), direction, 24, math.floor(data.Stats.ShotDamage * 0.85), 2.6,
								bossLook(data.Zone).RingColor, swirl and "Halo" or bossLook(data.Zone).RingStyle, swirl and { Kind = "curve", W = 0.4, Life = 4 } or nil)
						end
					end)
				end

				-- 체력이 절반 아래면 격노
				if not data.Enraged and data.Health / data.MaxHealth <= 0.5 then
					data.Enraged = true
					Effects.FloatText(part.Position + Vector3.new(0, part.Size.Y / 2 + 6, 0), "😡 Enraged!", Color3.fromRGB(255, 70, 70))
					Effects.Burst(part.Position, Color3.fromRGB(255, 70, 70), 80)
					if data.Kind == "Boss" then pcall(Stage.Enrage, part, data) end -- 격노 연출 (몸이 붉어지고 충격파 / 배너)
				end
				-- 보스전 박진감: 싸우는 동안 부하 몬스터가 주변에 나타난다 (2구역부터, 살아 있는 부하는 최대 7마리)
				data.NextAdds = data.NextAdds or (now + 6)
				if data.Zone > 1 and now >= data.NextAdds then
					data.NextAdds = now + (data.Enraged and 5 or 8)
					data.AddParts = data.AddParts or {}
					local alive = 0
					for i = #data.AddParts, 1, -1 do
						if monsters[data.AddParts[i]] then alive += 1 else table.remove(data.AddParts, i) end
					end
					for _ = 1, math.min(7 - alive, data.Enraged and 4 or 3) do
						local angle = math.random() * math.pi * 2
						local dist = data.Stats.Size / 2 + 14 + math.random() * 18
						local at = part.Position + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
						if walkableAt(at.X, at.Z) and not isSafe(at) and zoneOfX(at.X) == data.Zone then
							local addPart = spawnMonster(data.Zone, "Normal", at, true)
							if addPart then table.insert(data.AddParts, addPart) end
						end
					end
				end
				-- 다양한 패턴: 내려찍기 / 돌진 / 나선 탄막을 번갈아 (격노하면 더 자주, 두 개씩)
				data.NextPattern = data.NextPattern or (now + 2) -- (예전에는 이 값이 비어 있으면 조건이 항상 거짓이라 군주 패턴이 한 번도 나오지 않았다)
				if now >= data.NextPattern and now >= (data.BusyUntil or 0) then
					data.NextPattern = now + (data.Enraged and 4.2 or 6.5) * (F.BossTempo or 1) -- BossTempo < 1 이면 패턴이 더 자주 나온다
					local entry = pickBossPattern(data)
					data.LastPattern = entry.Name
					local okFn, errFn = pcall(entry.Fn, part, data) -- 패턴 하나가 오류가 나도 보스 전체가 멈추지 않게
					if not okFn then warn("[FieldBoss] pattern error: " .. tostring(errFn)) end
					if data.Enraged then
						task.delay(1.0, function()
							if monsters[part] == data then
								local second = pickBossPattern(data)
								if second.Name ~= "charge" and not second.Skip then
									local okSecond, errSecond = pcall(second.Fn, part, data)
									if not okSecond then warn("[FieldBoss] pattern error: " .. tostring(errSecond)) end
								end
							end
						end)
					end
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
				-- 돌아가는 길에도 층 높이를 따라간다 (경사를 오르내릴 때 땅에 파묻히거나 허공에 뜨지 않게)
				part.Position = Vector3.new(part.Position.X, floorAt(part.Position.X) + data.Stats.Size / 2, part.Position.Z)
			elseif data.Health < data.MaxHealth then
				data.Health = data.MaxHealth
				data.HealthFill.Size = UDim2.new(1, 0, 1, 0)
			end
		end
	end
	-- 몬스터끼리 한 점에 겹쳐 쌓이는 것(구역 끝 / 캠프 경계 / 벽 앞에서 몰려 뭉치던 것)을 막는다: 싸우는 중인 몬스터끼리 가까우면 서로 밀어낸다
	local fighters = {}
	for part, data in pairs(monsters) do
		if data.Aggro and not data.BossLike and not data.Static and not data.Falling and part.Parent then
			table.insert(fighters, { Part = part, Data = data })
		end
	end
	if #fighters > 1 and #fighters <= 60 then
		for i = 1, #fighters - 1 do
			local a = fighters[i]
			for j = i + 1, #fighters do
				local b = fighters[j]
				local pa, pb = a.Part.Position, b.Part.Position
				local dx, dz = pb.X - pa.X, pb.Z - pa.Z
				local dist = math.sqrt(dx * dx + dz * dz)
				local minDist = (a.Data.Stats.Size + b.Data.Stats.Size) * 0.35
				if dist < minDist then
					local nx, nz = dx, dz
					if dist < 0.05 then
						local angle = math.random() * math.pi * 2
						nx, nz = math.cos(angle), math.sin(angle)
					else
						nx, nz = dx / dist, dz / dist
					end
					local push = (minDist - dist) * 0.5
					a.Part.CFrame = CFrame.new(pa.X - nx * push, pa.Y, pa.Z - nz * push) * (a.Part.CFrame - pa)
					b.Part.CFrame = CFrame.new(pb.X + nx * push, pb.Y, pb.Z + nz * push) * (b.Part.CFrame - pb)
					unstick(a.Part, a.Data)
					unstick(b.Part, b.Data)
				end
			end
		end
	end
end

-- 아슬아슬한 회피(NEAR MISS): 공통 처리는 NearMissService (필드 / 던전 / 몬스터 AI 가 같이 쓴다)
local NearMiss = require(script.Parent:WaitForChild("NearMissService"))
local function isDashing(root, player) return NearMiss.IsDashing(player, root) end
local function awardNearMiss(player, root) NearMiss.Award(player, root) end
fieldCtx.NearMiss = function(root) NearMiss.AwardRoot(root) end -- 돌진 / 폭발 / 메테오 / 충격파 / 레이저를 아슬아슬하게 피했을 때 (MonsterTypes 가 부른다)

local function stepProjectiles(dt)
	local now = os.clock()
	if #projectiles == 0 then return end
	-- 탄마다 모든 플레이어를 다시 조회하지 않도록 이 프레임의 대상 목록을 한 번만 만든다
	local targets = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Zone") == "Field" then
			local root, humanoid = getAliveParts(player)
			if root and not isSafe(root.Position) then
				targets[#targets + 1] = { Player = player, Root = root, Humanoid = humanoid }
			end
		end
	end
	local spawnQueue -- 갈라지는 탄이 낳은 새 탄: 반복이 끝난 뒤에 쏜다 (반복 중에 목록이 밀리지 않게)
	for i = #projectiles, 1, -1 do
		local projectile = projectiles[i]
		local hit, pop = false, false
		local special = projectile.Kind ~= nil -- 유도 / 포물선 / 뱀 / 곡선 / 갈라짐
		if special then
			spawnQueue = spawnQueue or {}
			hit, pop = Effects.StepShot(projectile, dt, now, targets, spawnQueue)
		else
			projectile.Part.Position += projectile.Direction * projectile.Speed * dt
		end
		local flies = projectile.Flies == true -- 포물선 폭탄: 날아가는 동안은 벽 / 플레이어에 닿지 않는다
		if not hit and not flies then
			hit = not walkableAt(projectile.Part.Position.X, projectile.Part.Position.Z) -- 벽에 닿은 탄은 사라진다
		end
		for _, target in ipairs(targets) do
			if hit or flies then break end
			local player, root, humanoid = target.Player, target.Root, target.Humanoid
			do
				if humanoid.Health > 0 then
					local gap = (root.Position - projectile.Part.Position).Magnitude
					if gap < projectile.Radius + 2 then
						Guard.Take(humanoid, player:GetAttribute("TutorialDoom") and math.max(1, math.floor(projectile.Damage * 0.5)) or projectile.Damage) -- 튜토리얼 중에는 맞는 피해가 절반
						hit = true
						break
					elseif gap < projectile.Radius + 14 and isDashing(root, player) then -- 닿지는 않았지만 아슬아슬하게 스치며 대시
						projectile.NearMissed = projectile.NearMissed or {}
						if not projectile.NearMissed[player] then
							projectile.NearMissed[player] = true
							awardNearMiss(player, root)
						end
					end
				end
			end
		end

		if hit or now > projectile.Expire then
			projectile.Part:Destroy(pop or (special and hit))
			table.remove(projectiles, i)
		end
	end
	if spawnQueue then
		for _, q in ipairs(spawnQueue) do
			fireProjectile(q[1], q[2], q[3], q[4], q[5], q[6], q[7])
		end
	end
end

-- x좌표로 로비 / 필드 구역을 판별하고, 가장 멀리 간 구역(MaxZone)을 기록
local lastGateNotice = setmetatable({}, { __mode = "k" })
local lastZoneSeen = setmetatable({}, { __mode = "k" })
local lordPing = setmetatable({}, { __mode = "k" })
local tutorialLords = setmetatable({}, { __mode = "k" }) -- [player] = 튜토리얼용 첫 구역 군주 (입구 가까이에서 바로 나타난다)

-- 튜토리얼 첫 구역 군주: 1구역이 작아서(길이 340) 구역 끝의 군주 한 마리가 입구에서 가깝다. 별도 군주를 또 만들지 않고 이 군주를 길잡이로 가리킨다.
local function worldLordOfZone1()
	for part, data in pairs(monsters) do
		if data.Kind == "Boss" and data.Zone == 1 and part.Parent and not data.Ambush then
			return part
		end
	end
	return nil
end

local function updateZones()
	for _, player in ipairs(Players:GetPlayers()) do
		local zone = player:GetAttribute("Zone")
		if (zone == "Lobby" or zone == "Field") and not player:GetAttribute("InDoomArena") then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local inField = root.Position.X >= F.StartX - 5 and root.Position.X < F.StartX + F.TotalLength() + 20
				local newZone = inField and "Field" or "Lobby"
				if newZone ~= zone then
					player:SetAttribute("Zone", newZone)
					if newZone == "Lobby" then routeBeat[player] = nil end -- 마을로 돌아오면 길목 사건이 처음부터 다시
					if newZone == "Field" then
						if player:GetAttribute("TutorialDoom") then -- 첫 구역 군주 위치를 표지로 알려준다 (군주는 이 구역에 한 마리뿐)
							local lord = worldLordOfZone1()
							if lord then
								tutorialLords[player] = lord
								Remotes.Tutorial:FireClient(player, "Waypoint", { Pos = lord.Position, Name = "👑 First Zone Lord" })
							end
						end
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
							notify(player, string.format("🔒 The gate is closed! Defeat Zone %d monsters %d/%d + the zone Lord%s",
								allowed, player:GetAttribute("GateKills") or 0, F.Gate.KillsNeeded[allowed] or 0, player:GetAttribute("GateBossDone") and " (Lord ✔)" or ""))
						end
						fieldZone = allowed
					end
					do -- 튜토리얼 군주 길잡이 빛기둥이 군주를 따라가게 (군주는 플레이어에게 다가오며 움직인다)
						local lord = tutorialLords[player]
						if lord and lord.Parent and monsters[lord] then
							if os.clock() - (lordPing[player] or 0) > 0.4 then
								lordPing[player] = os.clock()
								Remotes.Tutorial:FireClient(player, "WaypointMove", { Pos = lord.Position })
							end
						end
					end
					-- 튜토리얼: 첫 구역 군주까지 가는 길이 밋밋하지 않게, 지점마다 사건이 터진다 (매복 -> 엘리트 -> 군주의 영역)
					if fieldZone == 1 and player:GetAttribute("TutorialDoom") and not player:GetAttribute("InDoomArena") then
						local x0 = zoneBounds(1)
						local offset = root.Position.X - x0
						local beat = routeBeat[player] or 0
						local function around(kind, count, minDist, maxDist)
							local spawned = 0
							for _ = 1, count * 4 do
								if spawned >= count then break end
								local angle = math.random() * math.pi * 2
								local distance = minDist + math.random() * (maxDist - minDist)
								local at = root.Position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
								if walkableAt(at.X, at.Z) and not isSafe(at) and zoneOfX(at.X) == 1 then
									spawnMonster(1, kind, at, true)
									spawned += 1
								end
							end
						end
						local function rumble(strength)
							player:SetAttribute("ShakeStrength", strength)
							player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
						end
						if beat < 1 and offset >= 85 then
							routeBeat[player] = 1
							notify(player, "🌿 The bushes are rustling strangely...! Ambush!")
							rumble(0.5)
							around("Normal", 7, 30, 46)
						elseif beat < 2 and offset >= 150 then
							routeBeat[player] = 2
							notify(player, "⚠ A powerful presence approaches! It's an Elite monster!")
							rumble(0.7)
							around("Elite", 1, 36, 46)
							around("Normal", 4, 32, 48)
						elseif beat < 3 and offset >= 215 then
							routeBeat[player] = 3
							notify(player, "🔥 The Lord's domain draws near... guards are swarming in!")
							rumble(0.8)
							around("Normal", 6, 30, 48)
						end
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
						notify(player, string.format("🏔 Zone %d · %s cleared!", fieldZone, F.ZoneNames[fieldZone]))
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

local lastWarp = setmetatable({}, { __mode = "k" })

-- 필드 밖으로 튕겨 나간 플레이어(대시 / 물리 버그로 벽 밖이나 허공)를 마을로 되돌린다
local function rescueOutOfBounds()
	local half = F.Width / 2
	local endX = F.StartX + F.TotalLength() + 60
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Zone") == "Field" and not player:GetAttribute("InDoomArena") then
			local root = getAliveParts(player)
			if root then
				local p = root.Position
				if p.Y > TOP + 95 or p.Y < TOP - 40 or math.abs(p.Z) > half + 30 or p.X > endX then
					root.AssemblyLinearVelocity = Vector3.zero
					player.Character:PivotTo(lobbySpawn)
					player:SetAttribute("Zone", "Lobby")
					notify(player, "You were knocked out of the Field and returned to town.")
				end
			end
		end
	end
end

-- zone 0 = 로비, 1~8 = 해당 구역 캠프 (도달한 구역까지만)
local function warp(player, zone)
	local now = os.clock()
	if now - (lastWarp[player] or 0) < 3 then return end
	if typeof(zone) ~= "number" or zone % 1 ~= 0 or zone < 0 or zone > F.ZoneCount then return end
	if player:GetAttribute("Zone") == "Dungeon" then
		notify(player, "You can't warp inside a dungeon.")
		return
	end
	local root = getAliveParts(player)
	if not root then return end

	if zone >= 1 and zone > math.max(1, math.min(player:GetAttribute("MaxZone") or 0, (player:GetAttribute("ClearedZone") or 0) + 1)) then
		notify(player, "You haven't reached that zone yet. Walk there first!")
		return
	end

	lastWarp[player] = now
	-- 이동 연출: 1초 동안 몸이 빛나고(무적) 화면이 밝아졌다가 이동한다 (바로 사라지면 어색하다)
	Effects.Burst(root.Position + Vector3.new(0, 3, 0), Color3.fromRGB(150, 195, 255), 70)
	Remotes.Warp:FireClient(player, "Cast", 1)
	local shield = Instance.new("ForceField")
	shield.Visible = false
	shield.Parent = player.Character
	game:GetService("Debris"):AddItem(shield, 1.6)
	task.delay(1, function()
		if not player.Parent or not getAliveParts(player) or player:GetAttribute("Zone") == "Dungeon" then return end
		if zone == 0 then
			player.Character:PivotTo(lobbySpawn)
			player:SetAttribute("Zone", "Lobby")
			notify(player, "Returned to town.")
		else
			player.Character:PivotTo(campCFrames[zone])
			player:SetAttribute("Zone", "Field")
			notify(player, string.format("⛺ Moved to Zone %d · %s Camp!", zone, F.ZoneNames[zone]))
		end
		local arrived = getAliveParts(player)
		if arrived then Effects.Burst(arrived.Position + Vector3.new(0, 3, 0), Color3.fromRGB(150, 195, 255), 70) end
	end)
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
-- 공개 이벤트: 거신
------------------------------------------------------------
local function spawnEvent(zone)
	local level = F.GetZoneLevel(zone) + 3
	local base = Config.Monster.GetStats(level)
	local E = Config.Events
	local stats = {
		Size = E.Size or 20, MaxHealth = base.MaxHealth * (E.HealthMult or 80), Speed = 7, ShotDamage = math.floor(base.ShotDamage * (E.DamageMult or 1.3)),
		ShotInterval = 1.4, ShotSpeed = 55, Gold = base.Gold * (E.GoldMult or 30),
	}

	local x0, x1 = zoneBounds(zone)
	local eventX = freeX(math.floor(x0 + 200), math.floor(x1 - 80))
	for _ = 1, 12 do -- 그 구역 군주(보스)와 150 이상 떨어진 곳을 고른다 (군주 근처에서 겹치지 않게)
		local tooClose = false
		for otherPart, otherData in pairs(monsters) do
			if otherData.Kind == "Boss" and otherData.Zone == zone and math.abs(otherPart.Position.X - eventX) < 150 then tooClose = true break end
		end
		if not tooClose then break end
		eventX = freeX(math.floor(x0 + 200), math.floor(x1 - 80))
	end
	local position = Vector3.new(eventX, floorAt(eventX) + stats.Size / 2, math.random(-F.Width / 2 + 70, F.Width / 2 - 70))

	local part = Instance.new("Part")
	part.Name = "EventBoss"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(stats.Size, stats.Size, stats.Size)
	part.Anchored = true
	part.CanCollide = false
	part.Position = position
	part.Color = Color3.fromRGB(108, 100, 94)
	part.Material = Enum.Material.Slate
	part.Parent = monstersFolder
	Effects.DecorateGolem(part, stats.Size, Color3.fromRGB(255, 140, 50)) -- 이끼 낀 용암 돌 거인
	CollectionService:AddTag(part, "Monster")
	CollectionService:AddTag(part, "RadarBoss")

	-- 멀리서도 보이는 하늘로 솟는 빛기둥 (보스에 붙어서 같이 움직임)
	local beam = Instance.new("Part")
	beam.Size = Vector3.new(3, 420, 3)
	beam.Color = Color3.fromRGB(255, 160, 70)
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.45
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Massless = true
	beam.Anchored = true -- 보스가 움직일 때마다 stepMonsters 가 몸 위로 다시 맞춘다 (용접은 보스를 따라오지 못해 빛기둥이 벌어졌다)
	beam.CFrame = part.CFrame * CFrame.new(0, 210, 0)
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
		HealthFill = createHealthBar(part, string.format("🗿 %s · World Boss (Zone %d)", Config.Events.Name, zone), 360, Color3.fromRGB(255, 190, 110)),
		Home = position,
		NextAttack = os.clock() + 3,
		NextShot = os.clock() + 3,
		NextRing = os.clock() + 6,
		BaseColor = part.Color,
		Aggro = false,
		HitOnly = true, -- (가까이 가도 깨지 않는다: 먼저 때려야 싸움이 시작된다)
		Contrib = {},
		Beam = beam,
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

		-- 거신은 2구역부터 나온다: 1구역은 튜토리얼 군주전이 있는 곳이라 월드 보스가 겹치면 흐름이 꼬인다
		local inTutorial = false
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("TutorialDoom") then inTutorial = true end
		end
		if anyone and maxZone >= 2 and not inTutorial then
			local zone = math.random(2, math.min(maxZone, F.ZoneCount))
			local part, data = spawnEvent(zone)
			activeEvent = { Part = part, Data = data }
			for _, player in ipairs(Players:GetPlayers()) do
				playSfx(player, "Event_Boss")
				notify(player, string.format("🗿 [World Boss] Zone %d · %s: %s appeared! Follow the orange light pillar and defeat it together for gear + tickets!", zone, F.ZoneNames[zone], Config.Events.Name))
			end

			local expire = os.clock() + Config.Events.Lifetime
			data.ExpireAt = expire
			workspace:SetAttribute("BossEventZone", zone) -- 화면 위 카운트다운(EventBossClient)이 읽는 값
			while monsters[part] == data and os.clock() < expire do
				workspace:SetAttribute("BossEventEnd", workspace:GetServerTimeNow() + (expire - os.clock()))
				workspace:SetAttribute("BossEventHp", math.clamp(data.Health / data.MaxHealth, 0, 1))
				task.wait(1)
			end
			workspace:SetAttribute("BossEventEnd", nil)
			workspace:SetAttribute("BossEventHp", nil)
			workspace:SetAttribute("BossEventZone", nil)
			if monsters[part] == data then
				monsters[part] = nil
				part:Destroy()
				activeEvent = nil
				for _, player in ipairs(Players:GetPlayers()) do
					notify(player, "The Colossus vanished underground... (wait for its next appearance)")
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
					playSfx(player, "Event_Goblin")
					notify(player, string.format("💰 A Golden Goblin appeared in Zone %d · %s! Catch it for a jackpot! (75s)", zone, F.ZoneNames[zone]))
				end
			end
			while monsters[part] == data do
				task.wait(1)
			end
		end
		task.wait(math.random(150, 300))
	end
end

-- 공습: 경보가 울리고 하늘을 가로지르는 폭격기가 지나가며 폭탄을 떨어뜨린다. 바닥에 붉은 원이 먼저 나타나니 그 밖으로 피한다.
local function airRaid(player, zone)
	local root = getAliveParts(player)
	if not root then return end
	player:SetAttribute("EventFx", "Raid") -- 사이렌 대신 화면 가장자리가 붉게 맥박친다 (PlayerFX)
	player:SetAttribute("EventFxTick", (player:GetAttribute("EventFxTick") or 0) + 1)
	player:SetAttribute("ShakeStrength", 0.35)
	player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
	local TweenService = game:GetService("TweenService")
	local Debris = game:GetService("Debris")
	local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))

	local level = F.GetZoneLevel(zone)
	local stats = Config.Monster.GetStats(level)
	local damage = math.max(5, math.floor(stats.ShotDamage * F.ZoneDanger.Damage[zone] * 1.8))
	local center = root.Position
	local heading = math.random() < 0.5 and 1 or -1
	local axis = Vector3.new(math.random() < 0.5 and 1 or 0, 0, 0)
	if axis.Magnitude == 0 then axis = Vector3.new(0, 0, 1) end
	axis *= heading
	local lateral = Vector3.new(-axis.Z, 0, axis.X)
	local altitude = 85
	local startPos = Vector3.new(center.X, center.Y + altitude, center.Z) - axis * 170
	local speed = 95

	-- 폭격기: 어두운 몸체 + 날개 + 깜빡이는 붉은 등
	local plane = Instance.new("Model")
	plane.Name = "RaidBomber"
	local function body(size, offset, color, material)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.Metal
		p.CFrame = CFrame.lookAt(startPos, startPos + axis) * CFrame.new(offset)
		p.Parent = plane
		return p
	end
	local hull = body(Vector3.new(5, 4, 22), Vector3.zero, Color3.fromRGB(45, 48, 58))
	body(Vector3.new(30, 0.8, 7), Vector3.new(0, 0, 2), Color3.fromRGB(55, 58, 70))
	body(Vector3.new(10, 0.8, 4), Vector3.new(0, 1.2, 10), Color3.fromRGB(55, 58, 70))
	body(Vector3.new(0.8, 5, 4), Vector3.new(0, 2.5, 10), Color3.fromRGB(55, 58, 70))
	for _, side in ipairs({ -1, 1 }) do
		local light = body(Vector3.new(1.2, 1.2, 1.2), Vector3.new(side * 14.5, 0.6, 1), Color3.fromRGB(255, 60, 50), Enum.Material.Neon)
		local glow = Instance.new("PointLight")
		glow.Range = 30
		glow.Color = Color3.fromRGB(255, 60, 50)
		glow.Brightness = 3
		glow.Parent = light
	end
	plane.PrimaryPart = hull
	plane.Parent = workspace
	Debris:AddItem(plane, 8)

	-- 폭격기가 지나가는 중간에 낙하산 부대가 투하된다: 플레이어 주변 하늘에서 몬스터가 내려온다
	task.delay(1.3, function()
		local target = getAliveParts(player)
		if not target then return end
		local count = 3 + math.min(4, zone // 2 + 1)
		for _ = 1, count do
			local angle = math.random() * math.pi * 2
			local distance = 16 + math.random() * 30
			local at = target.Position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
			if walkableAt(at.X, at.Z) and not isSafe(at) and zoneOfX(at.X) == zone then
				local part, data = spawnMonster(zone, "Normal", at, true)
				if part and data then
					data.Falling = true
					local drop = floorAt(at.X) + 90
					part.Position = Vector3.new(at.X, drop, at.Z)
					local canopy = Instance.new("Part")
					canopy.Name = "Chute"
					canopy.Anchored, canopy.CanCollide, canopy.CanQuery, canopy.CanTouch, canopy.Massless = false, false, false, false, true
					canopy.Shape = Enum.PartType.Ball
					canopy.Size = Vector3.new(data.Stats.Size * 2.4, data.Stats.Size * 1.2, data.Stats.Size * 2.4)
					canopy.Color = Color3.fromRGB(235, 90, 70)
					canopy.Material = Enum.Material.Fabric
					canopy.CFrame = part.CFrame * CFrame.new(0, data.Stats.Size * 1.6, 0)
					local weld = Instance.new("Weld") -- (Weld + 명시적 오프셋: WeldConstraint 는 클라이언트가 받는 순간의 위치로 오프셋을 다시 계산해서, 움직이는 몬스터의 겉모양이 본체에서 어긋나 보였다)
					weld.Part0 = part
					weld.Part1 = canopy
					weld.C0 = part.CFrame:ToObjectSpace(canopy.CFrame)
					weld.Parent = canopy
					canopy.Parent = part
				end
			end
		end
	end)

	local started = os.clock()
	local travel = 340 / speed
	local bombs = 8 + math.min(6, zone)
	local dropped = 0
	task.spawn(function()
		while os.clock() - started < travel and plane.Parent do
			local t = (os.clock() - started) / travel
			plane:PivotTo(CFrame.lookAt(startPos + axis * 340 * t, startPos + axis * 340 * t + axis))
			-- 비행 구간의 가운데 부분에서 폭탄을 떨어뜨린다
			local due = math.floor(math.clamp((t - 0.25) / 0.5, 0, 1) * bombs + 0.001)
			while dropped < due do
				dropped += 1
				local planePos = startPos + axis * 340 * t
				local lateralOffset = (math.random() - 0.5) * 70
				local spot = Vector3.new(planePos.X, 0, planePos.Z) + lateral * lateralOffset + axis * 18
				if dropped % 3 == 1 then -- 세 발에 한 발은 플레이어 위치를 노린다
					local target = getAliveParts(player)
					if target then spot = Vector3.new(target.Position.X, 0, target.Position.Z) end
				end
				local ground = floorAt(spot.X)
				local radius = 11
				local marker = Instance.new("Part")
				marker.Anchored, marker.CanCollide, marker.CanQuery, marker.CanTouch = true, false, false, false
				marker.Shape = Enum.PartType.Cylinder
				marker.Material = Enum.Material.Neon
				marker.Color = Color3.fromRGB(255, 50, 40)
				marker.Transparency = 0.55
				marker.Size = Vector3.new(0.4, radius * 2, radius * 2)
				marker.CFrame = CFrame.new(spot.X, ground + 0.4, spot.Z) * CFrame.Angles(0, 0, math.rad(90))
				marker.Parent = workspace
				local fuse = 1.5
				local bomb = Instance.new("Part")
				bomb.Anchored, bomb.CanCollide, bomb.CanQuery, bomb.CanTouch = true, false, false, false
				bomb.Shape = Enum.PartType.Ball
				bomb.Material = Enum.Material.Neon
				bomb.Color = Color3.fromRGB(255, 140, 50)
				bomb.Size = Vector3.new(3.2, 3.2, 3.2)
				bomb.Position = planePos - Vector3.new(0, 2, 0)
				bomb.Parent = workspace
				TweenService:Create(bomb, TweenInfo.new(fuse, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = Vector3.new(spot.X, ground + 1.5, spot.Z) }):Play()
				local trail = Instance.new("ParticleEmitter")
				trail.Rate = 40
				trail.Lifetime = NumberRange.new(0.3, 0.6)
				trail.Speed = NumberRange.new(0, 2)
				trail.LightEmission = 1
				trail.Color = ColorSequence.new(Color3.fromRGB(255, 190, 80), Color3.fromRGB(255, 80, 30))
				trail.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(1, 0) })
				trail.Parent = bomb
				task.delay(fuse, function()
					bomb:Destroy()
					marker:Destroy()
					local at = Vector3.new(spot.X, ground, spot.Z)
					Effects.Burst(at + Vector3.new(0, 2, 0), Color3.fromRGB(255, 140, 50), 36)
					local boom = Instance.new("Part")
					boom.Anchored, boom.CanCollide, boom.CanQuery, boom.CanTouch = true, false, false, false
					boom.Shape = Enum.PartType.Ball
					boom.Material = Enum.Material.Neon
					boom.Color = Color3.fromRGB(255, 170, 70)
					boom.Transparency = 0.3
					boom.Size = Vector3.new(2, 2, 2)
					boom.Position = at + Vector3.new(0, 2, 0)
					boom.Parent = workspace
					TweenService:Create(boom, TweenInfo.new(0.4), { Size = Vector3.new(radius * 2.2, radius * 2.2, radius * 2.2), Transparency = 1 }):Play()
					Debris:AddItem(boom, 0.5)
					SoundBank.Play(boom, "Boom", { Volume = 0.9 })
					for _, other in ipairs(Players:GetPlayers()) do
						local otherRoot, humanoid = getAliveParts(other)
						if otherRoot and other:GetAttribute("Zone") == "Field" and not isSafe(otherRoot.Position) then
							local flat = Vector3.new(otherRoot.Position.X - at.X, 0, otherRoot.Position.Z - at.Z)
							if flat.Magnitude <= radius and otherRoot.Position.Y - ground < 8 then
								Guard.Take(humanoid, damage)
							end
						end
					end
				end)
			end
			task.wait(0.03)
		end
		plane:Destroy()
	end)
end

-- 보스(구역 군주 / 이벤트 보스)가 나를 노리고 있으면 BossFight 가 켜진다 -> 클라이언트가 음악을 던전(전투) 곡으로 바꾼다
local powerWarnedAt = setmetatable({}, { __mode = "k" })
local weakTipShown = setmetatable({}, { __mode = "k" })
local eventTipShown = setmetatable({}, { __mode = "k" }) -- [player] = 거신 안내를 이미 보여 줌
local rescueAt = setmetatable({}, { __mode = "k" }) -- [player] = 튜토리얼 군주전에서 위험할 때 마지막으로 보호막을 받은 시각
local weakLesson = setmetatable({}, { __mode = "k" }) -- [player] = { Base = 시작할 때 약점 명중 수, Taught = 약점을 맞힌 뒤 설명까지 끝났는지, NextHint = 다음 힌트 시각 }
local function updateBossFight()
	for _, player in ipairs(Players:GetPlayers()) do
		local fighting = false
		local bossZone
		local bossKind
		local bossPart, bossData
		if player:GetAttribute("Zone") == "Field" then
			local root = getAliveParts(player)
			if root then
				for part, data in pairs(monsters) do
					if data.BossLike and not data.Static and data.Aggro and part.Parent and (part.Position - root.Position).Magnitude < 150 then
						fighting = true
						bossZone = data.Zone
						bossKind = data.Kind
						bossPart, bossData = part, data
						if data.Kind == "Boss" then break end -- 지역 군주가 가까이 있으면 군주를 기준으로 (거신보다 우선)
					end
				end
			end
		end
		-- 튜토리얼 첫 구역 군주전: 싸우는 도중에 약점을 직접 맞혀 보게 한다 (맞힐 때까지 힌트를 반복하고, 맞히면 "노출" 효과를 알려준다)
		if fighting and bossKind == "Boss" and bossZone == 1 and player:GetAttribute("TutorialDoom") then
			local lesson = weakLesson[player]
			if not lesson then
				lesson = { Base = player:GetAttribute("WeakHitTick") or 0, NextHint = os.clock() + 6 }
				weakLesson[player] = lesson
			end
			if not lesson.Taught then
				if (player:GetAttribute("WeakHitTick") or 0) > lesson.Base then
					lesson.Taught = true
					Remotes.Tutorial:FireClient(player, "Prompt", { Key = "💥", Title = "Weak Spot Exposed!", Text = "Hit the yellow orb like that and the boss takes triple damage for 4 seconds! Fire away!", Duration = 7 })
				elseif os.clock() >= lesson.NextHint then
					lesson.NextHint = os.clock() + 11
					Remotes.Tutorial:FireClient(player, "Prompt", { Key = "🎯", Title = "Aim for the yellow orb!", Text = "Aim at the yellow glowing orb (🎯) circling the boss with your mouse and click it. Hit it to expose a weak spot!", Duration = 9 })
				end
			end
		elseif not fighting then
			weakLesson[player] = nil
		end
		-- 튜토리얼 첫 구역 군주전은 반드시 이겨야 다음 장면이 이어진다: 체력이 20% 아래로 떨어지면 보호막 + 회복 (20초에 한 번)
		if fighting and bossKind == "Boss" and bossZone == 1 and player:GetAttribute("TutorialDoom") then
			local _, humanoid = getAliveParts(player)
			if humanoid and humanoid.Health < humanoid.MaxHealth * 0.2 and os.clock() - (rescueAt[player] or -999) > 20 then
				rescueAt[player] = os.clock()
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * 0.4)
				local shield = Instance.new("ForceField")
				shield.Parent = player.Character
				game:GetService("Debris"):AddItem(shield, 4)
				notify(player, "🛡 Danger! A shield wrapped around you. Now is your chance!")
			end
		end
		if player:GetAttribute("BossFight") ~= fighting then
			player:SetAttribute("BossFight", fighting)
			if fighting and bossKind == "Boss" and bossPart and bossData and not player:GetAttribute("TutorialDoom") then
				pcall(Stage.Intro, bossPart, bossData, player) -- 등장 연출 (배너 / 흔들림 / 충격파)
			elseif not fighting then
				Stage.ClearEnrage(player)
			end
			if fighting and bossKind == "Boss" and player:GetAttribute("TutorialRetryBuff") then
				-- 쓰러졌다가 다시 도전: 일회성 힘 (군주에게 주는 피해 x8 + 궁극기 가득)
				player:SetAttribute("UltCharge", Config.Skills.Ult.Cost)
				Remotes.Tutorial:FireClient(player, "Prompt", { Key = "💪", Title = "A one-time surge of power!", Text = "Damage to the Lord is greatly increased and your ultimate is full. Use V-key Dead Eye and the yellow orb weak spot to take it down this time!", Duration = 9 })
			elseif fighting and bossKind == "Event" and not player:GetAttribute("TutorialActive") and not eventTipShown[player] then
				eventTipShown[player] = true -- (예전에는 player .. "_event" 로 Instance 와 글자를 이어 붙여 오류가 났다)
				Remotes.Tutorial:FireClient(player, "Prompt", { Key = "⚔", Title = "Colossus!", Text = "Everyone who fought gets loot. Keep shooting from afar while dodging shots!", Duration = 7 })
			elseif fighting and bossKind == "Boss" and bossZone and not player:GetAttribute("TutorialActive") then
				-- 지역 군주를 만나면: 전투력이 모자라면 무기 강화를 권하고(골드 사용처), 처음이면 약점 구슬 사용법을 알려준다
				local recommended = F.RecommendPower[bossZone] or 0
				local power = player:GetAttribute("Power") or 0
				if power < recommended * 0.85 and os.clock() - (powerWarnedAt[player] or -999) > 90 then
					powerWarnedAt[player] = os.clock()
					Remotes.Tutorial:FireClient(player, "Prompt", { Key = "⚒", Title = string.format("Not enough power! (You %d / Rec. %d)", power, recommended),
						Text = "Upgrade your weapon with gold at the town blacksmith to raise your power. Upgrade and try again — it'll be much easier!", Duration = 9 })
				elseif not weakTipShown[player] then
					weakTipShown[player] = true
					Remotes.Tutorial:FireClient(player, "Prompt", { Key = "🎯", Title = "Target the weak spot!",
						Text = "Aim at the yellow orb circling the boss with your mouse and click it to expose a weak spot: x3 damage taken for 4s! + Dead Eye gauge (auto-attack won't work)", Duration = 8 })
				end
			end
		end
	end
end

-- 시체 청소: 몬스터 표(monsters)에 없는데 필드에 남은 몬스터 부품(죽었는데 안 지워진 것)을 지운다
local function cleanOrphans()
	if not monstersFolder then return end
	for _, child in ipairs(monstersFolder:GetChildren()) do
		if child:IsA("BasePart") and not monsters[child] then
			child:Destroy()
		end
	end
end

-- 튜토리얼 "압도적인 습격": 첫 필드 방문 때 잠깐 싸우게 한 뒤, 사방에서 훨씬 강한 몬스터 떼가 몰려와 필연적으로 쓰러지게 한다.
-- (쓰러지면 마을로 돌아가고, 다음 미션이 "훈련 -> 던전 -> 10연 뽑기 -> 다시 필드(이제 쉽다)" 로 이어진다)
local doomTimers = setmetatable({}, { __mode = "k" })
-- 튜토리얼 연출(열쇠 -> 던전 추락 / 최후의 군주 결투)은 DoomScene 모듈로 분리했다 (이 파일이 Studio 스크립트 한도에 가까워서)
local DoomScene = require(script.Parent:WaitForChild("DoomScene"))
DoomScene.Init({
	getAliveParts = getAliveParts, notify = notify, playSfx = playSfx, createHealthBar = createHealthBar,
	isDashing = isDashing, awardNearMiss = awardNearMiss, monsters = monsters,
	getMonstersFolder = function() return monstersFolder end, SoundBank = SoundBank,
})
startTutorialRift = DoomScene.StartRift
local doomWave = DoomScene.Wave
task.spawn(function() -- 8구역 끝의 최후의 군주 포탈 (월드가 만들어진 뒤에)
	task.wait(10)
	local okPortal, errPortal = pcall(DoomScene.BuildPortal, { ZoneEnd = F.ZoneEnd, FloorAt = floorAt, ZoneCount = F.ZoneCount })
	if not okPortal then warn("[FinalLord] portal build failed: " .. tostring(errPortal)) end
end)

local function updateDoom()
	local anyDoom = false
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InDoomArena") then
			anyDoom = true -- 소환 결투 중에는 군주 / 연출을 건드리지 않는다
		elseif player:GetAttribute("TutorialDoom") and player:GetAttribute("Zone") == "Field" then
			local root, humanoid = getAliveParts(player)
			if root and not isSafe(root.Position) then
				anyDoom = true
				local state = doomTimers[player]
				if not state then
					state = { Since = os.clock() }
					doomTimers[player] = state
				end
				if not state.Fired and doomReady[player] and os.clock() - doomReady[player] >= 2.5 then
					state.Fired = true
					Loot.CollectAll(player) -- 소환 결투로 끌려가기 전에, 바닥에 남은 전리품을 모두 챙겨 준다 (못 줍고 잡혀가지 않게)
					state.FiredAt = os.clock()
					local doomZone = zoneOfX(root.Position.X)
					task.spawn(function() -- 오래 걸리는 연출이라 필드 업데이트 루프를 막지 않게 따로 돌린다
						local ok, err = pcall(doomWave, player, doomZone)
						if not ok then
							warn("[Doom] Summon duel error: " .. tostring(err))
							player:SetAttribute("InDoomArena", nil)
							local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
							if r then r.Anchored = false end
						end
					end)
				end
				if state.Fired and os.clock() - state.FiredAt >= 70 and humanoid.Health > 0 then
					notify(player, "💀 You were crushed by overwhelming power...")
					humanoid.Health = 0
				end
			else
				doomTimers[player] = nil
			end
		else
			doomTimers[player] = nil
		end
	end
	if not anyDoom then
		for part, data in pairs(monsters) do
			if data.Doom then
				monsters[part] = nil
				part:Destroy()
			end
		end
	end
end

-- 습격 / 공습: 필드에서 싸우는 플레이어에게 일정 시간마다 갑자기 닥친다 (가만히 있으면 위험하다)
--   습격 = 사방에서 몬스터 떼가 몰려온다 / 공습 = 하늘에서 폭격기가 폭탄을 떨어뜨린다
-- 주변에서 떨어진 걷기 가능한 자리를 찾는다
local function ringSpot(root, zone, minDistance, maxDistance)
	for _ = 1, 8 do
		local angle = math.random() * math.pi * 2
		local distance = minDistance + math.random() * (maxDistance - minDistance)
		local at = root.Position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		if walkableAt(at.X, at.Z) and not isSafe(at) and zoneOfX(at.X) == zone then return at end
	end
	return nil
end

-- 이벤트(습격 / 엘리트 부대 / 대이동 / 공습)로 나온 몬스터 수: zone 을 주면 그 구역만 센다 (여러 명이 서로 다른 구역에 있어도 한 구역의 몬스터가 다른 구역 이벤트를 막지 않게)
local function ambushCount(zone)
	local alive = 0
	for _, data in pairs(monsters) do
		if data.Ambush and (not zone or data.Zone == zone) then alive += 1 end
	end
	return alive
end

-- 구역별 이벤트 몬스터 상한: 기본 12마리 + 그 구역에 있는 사람 1명당 4마리 (여럿이 함께 싸우면 그만큼 더 나온다)
local function ambushCap(zone)
	local present = 0
	for _, member in ipairs(Players:GetPlayers()) do
		if member:GetAttribute("Zone") == "Field" then
			local memberRoot = getAliveParts(member)
			if memberRoot and zoneOfX(memberRoot.Position.X) == zone then present += 1 end
		end
	end
	return 12 + 4 * present
end

-- 필드 랜덤 이벤트: 몇십 초마다 한 가지가 터진다. 같은 이벤트가 연달아 나오지 않는다.
local FIELD_EVENTS = {
	{ Key = "Raid",    Weight = 3.8 },  -- 공습 (폭격기 + 낙하산 부대): 화면이 심심하지 않게 조금 더 자주 (2.5 -> 3.8)
	{ Key = "Ambush",  Weight = 3 },    -- 사방 습격
	{ Key = "Elite",   Weight = 2.2 },  -- 엘리트 부대 습격
	{ Key = "Barrage", Weight = 3 },    -- 포격: 뒤쪽 / 사방에 붉은(구역 테마) 경고 원이 줄줄이 떨어진다 (뒤로 빠지며 쏘기만 해서는 안 되게)
	-- (몬스터 대이동 Stampede 는 뺐다: 줄지어 달려오는 몬스터가 타격되지 않는 문제 + 피하기 어려운 연출. eventStampede 코드는 남겨 둔다)
}

local function eventAmbush(player, root, zone)
	player:SetAttribute("ShakeStrength", 0.5)
	player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
	local count = 6 + math.min(6, zone)
	for _ = 1, count do
		local at = ringSpot(root, zone, 42, 58)
		if at then spawnMonster(zone, "Normal", at, true) end
	end
end

local function eventBarrage(player, root, zone)
	player:SetAttribute("ShakeStrength", 0.25)
	player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
	local base = Config.Monster.GetStats(F.GetZoneLevel(zone))
	local stats = { ShotDamage = math.max(1, math.floor(base.ShotDamage * F.ZoneDanger.Damage[zone] * 0.9)) }
	local look = root.CFrame.LookVector
	MonsterTypes.Barrage(fieldCtx, root.Position, 7 + math.min(4, zone // 2), zone, stats, Vector3.new(look.X, 0, look.Z))
end

local function eventElite(player, root, zone)
	player:SetAttribute("EventFx", "Elite") -- 나팔 대신 화면 가장자리가 금빛으로 번쩍인다
	player:SetAttribute("EventFxTick", (player:GetAttribute("EventFxTick") or 0) + 1)
	notify(player, "👑 Elite squad incoming! Elite monsters approach — defeat them for big rewards!")
	player:SetAttribute("ShakeStrength", 0.4)
	player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
	for _ = 1, 3 + zone // 3 do
		local at = ringSpot(root, zone, 46, 62)
		if at then spawnMonster(zone, "Elite", at, true) end
	end
end

-- 대이동: 한쪽에서 몬스터가 줄지어 빠르게 몰려온다 (옆으로 비켜서 한 줄로 쓸어버리는 재미)
local function eventStampede(player, root, zone)
	local dirX = math.random() < 0.5 and 1 or -1
	local center = root.Position + Vector3.new(dirX * 70, 0, 0)
	if not walkableAt(center.X, center.Z) or zoneOfX(center.X) ~= zone then
		dirX = -dirX
		center = root.Position + Vector3.new(dirX * 70, 0, 0)
	end
	if zoneOfX(center.X) ~= zone then return false end
	player:SetAttribute("EventFx", dirX > 0 and "StampedeR" or "StampedeL") -- 몰려오는 쪽 가장자리가 주황빛으로 번쩍인다
	player:SetAttribute("EventFxTick", (player:GetAttribute("EventFxTick") or 0) + 1)
	player:SetAttribute("ShakeStrength", 0.35)
	player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
	local count = 9 + math.min(6, zone)
	for index = 1, count do
		local z = math.clamp(root.Position.Z + (index - (count + 1) / 2) * 7, -F.Width / 2 + 20, F.Width / 2 - 20)
		local at = Vector3.new(center.X + math.random(-6, 6), 0, z)
		if walkableAt(at.X, at.Z) and not isSafe(at) and zoneOfX(at.X) == zone then
			local part, data = spawnMonster(zone, "Normal", at, true)
			if part and data and data.Stats then
				data.Aggro = true
				data.Stats.Speed *= 1.35
			end
		end
	end
	return true
end

-- 2구역(숲) 덤불 매복: 길가에 평범해 보이는 덤불이 흩어져 있다가, 가까이 가면 흔들리고(!) 잠시 뒤 몬스터 서너 마리가 튀어나온다.
-- 덤불은 터진 뒤 2분 30초 뒤에 다시 생긴다. 이벤트 몬스터 상한(ambushCap)을 지킨다.
local BUSH_ZONE = 2
local function runBushAmbush()
	task.wait(6)
	local folder = Instance.new("Folder")
	folder.Name = "AmbushBushes"
	folder.Parent = workspace
	local rng = Random.new(7742)
	local x0, x1 = zoneBounds(BUSH_ZONE)
	local bushes = {}
	local tries = 0
	while #bushes < 11 and tries < 300 do
		tries += 1
		local x = x0 + 80 + rng:NextNumber() * math.max(10, x1 - x0 - 160)
		local z = (rng:NextNumber() - 0.5) * (F.Width - 70)
		local pos = Vector3.new(x, floorAt(x), z)
		local ok = walkableAt(x, z, 6) and not isSafe(pos) and zoneOfX(x) == BUSH_ZONE
		for _, other in ipairs(bushes) do
			if (other.Pos - pos).Magnitude < 60 then ok = false break end
		end
		if ok then table.insert(bushes, { Pos = pos, State = "Idle", ReadyAt = 0 }) end
	end
	local GREENS = { Color3.fromRGB(52, 112, 48), Color3.fromRGB(64, 130, 56), Color3.fromRGB(46, 98, 44) }
	local function build(bush)
		local model = Instance.new("Model")
		model.Name = "Bush"
		bush.Bases = {}
		for i = 1, 4 do
			local ball = Instance.new("Part")
			ball.Shape = Enum.PartType.Ball
			ball.Anchored, ball.CanCollide, ball.CanQuery, ball.CanTouch = true, false, false, false
			ball.Material = Enum.Material.Grass
			ball.Color = GREENS[(i % #GREENS) + 1]
			local size = i == 1 and 8 or (5 + (i % 2) * 1.5)
			ball.Size = Vector3.new(size, size * 0.8, size)
			local angle = (i / 4) * math.pi * 2
			ball.CFrame = CFrame.new(bush.Pos + Vector3.new(i == 1 and 0 or math.cos(angle) * 3.2, size * 0.32, i == 1 and 0 or math.sin(angle) * 3.2))
			ball.Parent = model
			bush.Bases[ball] = ball.CFrame
		end
		model.Parent = folder
		bush.Model = model
		bush.State = "Idle"
	end
	for _, bush in ipairs(bushes) do build(bush) end

	local function trigger(bush)
		bush.State = "Rustle"
		for _, member in ipairs(Players:GetPlayers()) do
			local memberRoot = member:GetAttribute("Zone") == "Field" and getAliveParts(member)
			if memberRoot and (memberRoot.Position - bush.Pos).Magnitude < 60 then
				notify(member, "🌿 The bush is rustling strangely...!")
			end
		end
		Effects.FloatText(bush.Pos + Vector3.new(0, 10, 0), "❗", Color3.fromRGB(255, 235, 90))
		Effects.Burst(bush.Pos + Vector3.new(0, 4, 0), Color3.fromRGB(110, 210, 90), 24)
		task.spawn(function()
			for _ = 1, 16 do -- 0.8초 동안 부르르 떤다
				if not bush.Model then return end
				for ball, base in pairs(bush.Bases) do
					if ball.Parent then ball.CFrame = base * CFrame.new((math.random() - 0.5) * 0.9, (math.random() - 0.5) * 0.4, (math.random() - 0.5) * 0.9) end
				end
				task.wait(0.05)
			end
			local present = 0
			for _, member in ipairs(Players:GetPlayers()) do
				local memberRoot = member:GetAttribute("Zone") == "Field" and getAliveParts(member)
				if memberRoot and (memberRoot.Position - bush.Pos).Magnitude < 45 then present += 1 end
			end
			local count = 3 + (present >= 2 and 1 or 0)
			Effects.Burst(bush.Pos + Vector3.new(0, 3, 0), Color3.fromRGB(110, 210, 90), 40)
			for _ = 1, count do
				local angle = math.random() * math.pi * 2
				local at = bush.Pos + Vector3.new(math.cos(angle) * 6, 0, math.sin(angle) * 6)
				if not (walkableAt(at.X, at.Z) and not isSafe(at) and zoneOfX(at.X) == BUSH_ZONE) then at = bush.Pos end
				local _, data = spawnMonster(BUSH_ZONE, "Normal", at, true)
				if data then data.Aggro = true end
			end
			if bush.Model then
				for ball in pairs(bush.Bases) do
					if ball.Parent then TweenService:Create(ball, TweenInfo.new(0.35), { Size = Vector3.new(0.5, 0.5, 0.5), Transparency = 1 }):Play() end
				end
				Debris:AddItem(bush.Model, 0.5)
				bush.Model = nil
			end
			bush.State = "Cooldown"
			bush.ReadyAt = os.clock() + 150
		end)
	end

	while true do
		task.wait(0.4)
		local now = os.clock()
		for _, bush in ipairs(bushes) do
			if bush.State == "Idle" then
				for _, member in ipairs(Players:GetPlayers()) do
					if member:GetAttribute("Zone") == "Field" then
						local memberRoot = getAliveParts(member)
						if memberRoot and (memberRoot.Position - bush.Pos).Magnitude < 28 and ambushCount(BUSH_ZONE) <= ambushCap(BUSH_ZONE) then
							trigger(bush)
							break
						end
					end
				end
			elseif bush.State == "Cooldown" and now >= bush.ReadyAt then
				local nearby = false
				for _, member in ipairs(Players:GetPlayers()) do
					local memberRoot = member:GetAttribute("Zone") == "Field" and getAliveParts(member)
					if memberRoot and (memberRoot.Position - bush.Pos).Magnitude < 70 then nearby = true end
				end
				if not nearby then build(bush) end
			end
		end
	end
end

local function runAmbush()
	task.wait(20)
	local lastEvent = setmetatable({}, { __mode = "k" })
	local zoneEventAt = {} -- [구역] = 마지막 이벤트 시각: 같은 구역에서 여러 명이 있어도 이벤트가 동시에 겹쳐 터지지 않게 10초 간격을 둔다
	while true do
		task.wait(math.random(18, 32))
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("Zone") == "Field" then
				local root = getAliveParts(player)
				if root and not isSafe(root.Position) then
					local zone = zoneOfX(root.Position.X)
					local allowed = zone <= math.min(F.ZoneCount, (player:GetAttribute("ClearedZone") or 0) + 1)
					if allowed and zone >= 1 then
						local total = 0
						for _, entry in ipairs(FIELD_EVENTS) do
							if entry.Key ~= lastEvent[player] then total += entry.Weight end
						end
						local roll, picked = math.random() * total, nil
						for _, entry in ipairs(FIELD_EVENTS) do
							if entry.Key ~= lastEvent[player] then
								roll -= entry.Weight
								if roll <= 0 then picked = entry.Key break end
							end
						end
						if ambushCount(zone) <= ambushCap(zone) and os.clock() - (zoneEventAt[zone] or 0) > 10 then -- (공습도 같은 상한을 지킨다)
							zoneEventAt[zone] = os.clock()
							lastEvent[player] = picked
							if picked == "Raid" then
								task.spawn(airRaid, player, zone)
							elseif picked == "Ambush" then
								eventAmbush(player, root, zone)
							elseif picked == "Elite" then
								eventElite(player, root, zone)
							elseif picked == "Barrage" then
								eventBarrage(player, root, zone)
							elseif picked == "Stampede" then
								eventStampede(player, root, zone)
							end
						end
					end
				end
			end
		end
	end
end

-- 세트 효과가 필드 몬스터에게 주는 피해 (미사일 / 번개 / 칼날 / 폭발 ... 가 모두 이 함수를 지난다)
local function fieldAugHit(player, entry, amount, quiet)
	local part, data = entry.Part, entry.Data
	if monsters[part] ~= data or data.Health <= 0 or data.Invincible then return end
	if not canHitZone(player, part.Position.X) then return end -- 아직 못 가는 구역(닫힌 관문 너머)의 몬스터는 세트 효과로도 못 때린다
	amount = math.max(1, math.floor(amount * Dungeon.MarkMult(player, data)))
	if data.IntroUntil and os.clock() < data.IntroUntil then return end
	data.Health -= amount
	BL.DmgAs(player, "세트·펫", amount)
	data.LastHit = os.clock()
	if data.Contrib then data.Contrib[player] = (data.Contrib[player] or 0) + amount end
	data.HealthFill.Size = UDim2.new(math.max(data.Health, 0) / data.MaxHealth, 0, 1, 0)
	if not quiet then
		Effects.DamageNumber(part.Position, amount, false)
		Effects.Hit(player, part, false, data.Health <= 0)
	end
	Dungeon.AugOnHit(augRun, player, part, data, amount, false)
	if data.Health <= 0 then
		killMonster(player, part, data)
	end
end

function Field.Init(lobbySpawnCFrame)
	lobbySpawn = lobbySpawnCFrame or lobbySpawn
	buildWorld()
	do -- 세트 효과(어그먼트): 필드에서도 작동한다
		local fx = Instance.new("Folder")
		fx.Name = "FieldFx"
		fx.Parent = workspace
		augRun = {
			Monsters = monsters, Folder = fx, Phase = "Wave", Destroyed = false, HitFn = fieldAugHit,
			ValidTarget = function(part) -- 세트 효과가 노리는 몬스터: 지금 필드에 있는 누군가가 갈 수 있는 구역까지만 (닫힌 관문 너머는 제외)
				local best = 0
				for _, member in ipairs(Players:GetPlayers()) do
					if member:GetAttribute("Zone") == "Field" then
						best = math.max(best, math.min(F.ZoneCount, (member:GetAttribute("ClearedZone") or 0) + 1))
					end
				end
				return zoneOfX(part.Position.X) <= math.max(best, 1)
			end,
			MembersFn = function()
				local list = {}
				for _, member in ipairs(Players:GetPlayers()) do
					if member:GetAttribute("Zone") == "Field" and getAliveParts(member) and not isSafe(getAliveParts(member).Position) then
						table.insert(list, member)
					end
				end
				return list
			end,
		}
		Dungeon.StartAugLoop(augRun)
		task.spawn(function() -- 마을 / 던전에서도 세트 오라는 보이게 (1초마다 맞춘다)
			while true do
				task.wait(1)
				for _, member in ipairs(Players:GetPlayers()) do
					pcall(Dungeon.SyncAura, member)
				end
			end
		end)
	end

	for zone = 1, F.ZoneCount do
		local countMult = F.ZoneCountMult and F.ZoneCountMult[zone] or 1 -- 구역이 올라갈수록 몬스터가 더 많다
		for _ = 1, math.floor(F.MonstersPerZone * countMult * Config.Horde.Count + 0.5) do
			spawnMonster(zone, "Normal")
		end
		for _ = 1, math.floor(F.ElitesPerZone * countMult + 0.5) do
			spawnMonster(zone, "Elite")
		end
	end
	for bossZone = 1, F.ZoneCount do
		spawnMonster(bossZone, "Boss") -- 구역마다 군주 한 마리 (다음 구역으로 가려면 쓰러뜨려야 한다)
	end

	local zoneTimer = 0
	local orphanTimer = 0
	RunService.Heartbeat:Connect(function(dt)
		stepMonsters(dt)
		stepProjectiles(dt)
		zoneTimer += dt
		if zoneTimer >= 0.4 then
			zoneTimer = 0
			updateZones()
			rescueOutOfBounds()
			updateBossFight()
			updateDoom()
			orphanTimer += 0.4
			if orphanTimer >= 2 then
				orphanTimer = 0
				cleanOrphans()
			end
		end
	end)

	task.spawn(runEvents)
	task.spawn(runGoblins)
	task.spawn(function() -- 구간이 바뀌면 "이 구간엔 이런 몬스터가 많아요" 알림 (같은 구역도 구간마다 구성이 달라진다)
		local lastKey = setmetatable({}, { __mode = "k" })
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				if player:GetAttribute("Zone") == "Field" then
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if root and not isSafe(root.Position) then
						local zone = F.ZoneOfX(root.Position.X)
						local key = zone * 10 + segmentOf(zone, root.Position.X)
						if lastKey[player] ~= key then
							local first = lastKey[player] == nil
							lastKey[player] = key
							if not first then
								-- ("이 구간엔 ~가 많아요" 알림은 쓸모가 적어 뺐다. 구간마다 몬스터 구성은 그대로 다르다)
							end
						end
					end
				end
			end
		end
	end)
	task.spawn(runAmbush)
	task.spawn(runBushAmbush)
	if RunService:IsStudio() then
		-- Studio 진단: 내 주변 40 안의 몬스터 상태를 4초마다 출력한다 ("맞지도 않고 반응도 없는 몬스터" 원인 추적용. 게임 서버에서는 안 돈다)
		task.spawn(function()
			while true do
				task.wait(4)
				for _, player in ipairs(Players:GetPlayers()) do
					local root = player:GetAttribute("Zone") == "Field" and getAliveParts(player)
					if root then
						local lines = {}
						for part, data in pairs(monsters) do
							local distance = (part.Position - root.Position).Magnitude
							if part.Parent and distance <= 40 and #lines < 6 then
								table.insert(lines, string.format("  %s zone%s %s dist%d HP %d/%d aggro=%s hittable=%s ambush=%s falling=%s safe=%s",
									tostring(data.TypeKey), tostring(data.Zone), tostring(data.Kind), distance, data.Health or -1, data.MaxHealth or -1,
									tostring(data.Aggro), tostring(canHitZone(player, part.Position.X)), tostring(data.Ambush), tostring(data.Falling ~= nil), tostring(isSafe(part.Position))))
							end
						end
						if #lines > 0 then print("[MobDiag] " .. player.Name .. " zone " .. tostring(zoneOfX(root.Position.X)) .. " my zone gate " .. tostring(player:GetAttribute("ClearedZone")) .. "\n" .. table.concat(lines, "\n")) end
					end
				end
			end
		end)
	end
	-- 이벤트 몬스터 정리: 주변 170 안에 필드의 어떤 플레이어도 없는 상태가 30초 넘게 이어지면 사라진다 (싸우는 중이거나 누군가 가까이 있으면 그대로)
	task.spawn(function()
		local lonelySince = setmetatable({}, { __mode = "k" })
		while true do
			task.wait(5)
			local positions = {}
			for _, member in ipairs(Players:GetPlayers()) do
				if member:GetAttribute("Zone") == "Field" then
					local memberRoot = getAliveParts(member)
					if memberRoot then table.insert(positions, memberRoot.Position) end
				end
			end
			local now = os.clock()
			for part, data in pairs(monsters) do
				if data.Ambush and data.Kind ~= "Boss" and part.Parent then
					local near = false
					for _, position in ipairs(positions) do
						if (position - part.Position).Magnitude <= 170 then near = true break end
					end
					if near then
						lonelySince[part] = nil
					else
						lonelySince[part] = lonelySince[part] or now
						if now - lonelySince[part] > 30 then
							monsters[part] = nil
							lonelySince[part] = nil
							part:Destroy()
						end
					end
				end
			end
		end
	end)
end

return Field
