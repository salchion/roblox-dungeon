-- LobbyService (ServerScriptService > Modules 안의 ModuleScript, 이름: LobbyService)
-- 로비(마을)를 코드로 만든다.
--   남쪽 광장(스폰 + 분수) -> 북쪽 던전 게이트 / 서쪽 허수아비 훈련장 / 동쪽 강화대, 장비 뽑기 머신 / 동쪽 끝 필드 입구
-- 직접 만든 맵을 쓰고 싶다면 이 파일 대신 맵을 놓고 반환값(SpawnCFrame, GatePrompt, AnvilPrompt, GachaPrompt, DummyStart)만 맞춰주면 된다.

local Lighting = game:GetService("Lighting")

local Lobby = {}

local HALF = 130            -- 로비는 -130 ~ +130 의 정사각형
local TOP = 0.05            -- 바닥 윗면 높이 (기본 Baseplate 와 겹쳐 깜빡이는 것 방지)

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

-- 원판 (Cylinder 는 X축이 두께라 눕혀서 쓴다)
local function makeDisc(position, diameter, thickness, color, material, parent)
	return makePart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, diameter, diameter),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
	}, parent)
end

local function makeLabel(part, text, color, offsetY, width, height)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, width or 280, 0, height or 64)
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

local function addLight(part, range, brightness, color)
	local light = Instance.new("PointLight")
	light.Range = range
	light.Brightness = brightness
	light.Color = color
	light.Parent = part
end

local function makeLamp(position, parent)
	makePart({ Name = "LampPost", Size = Vector3.new(0.8, 9, 0.8), Position = position + Vector3.new(0, 4.5, 0), Color = Color3.fromRGB(45, 45, 55), Material = Enum.Material.Metal }, parent)
	local bulb = makePart({
		Name = "LampBulb", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2),
		Position = position + Vector3.new(0, 9.6, 0), Color = Color3.fromRGB(255, 235, 170),
		Material = Enum.Material.Neon, CanCollide = false,
	}, parent)
	addLight(bulb, 30, 1.2, Color3.fromRGB(255, 225, 160))
end

local function makeTree(position, rng, parent)
	local height = rng:NextNumber(7, 12)
	makePart({
		Name = "Trunk", Size = Vector3.new(2, height, 2), Position = position + Vector3.new(0, height / 2, 0),
		Color = Color3.fromRGB(95, 65, 40), Material = Enum.Material.Wood,
	}, parent)
	local leaf = rng:NextNumber(9, 14)
	makePart({
		Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(leaf, leaf, leaf),
		Position = position + Vector3.new(0, height + leaf / 3, 0),
		Color = Color3.fromRGB(rng:NextInteger(50, 80), rng:NextInteger(125, 170), rng:NextInteger(55, 85)),
		Material = Enum.Material.Grass, CanCollide = false,
	}, parent)
end

local function makeFountain(position, parent)
	makeDisc(position + Vector3.new(0, 1, 0), 22, 2, Color3.fromRGB(150, 150, 160), Enum.Material.Marble, parent)
	makeDisc(position + Vector3.new(0, 1.6, 0), 19, 1.2, Color3.fromRGB(70, 150, 230), Enum.Material.Glass, parent).Transparency = 0.35
	makePart({ Name = "FountainPillar", Size = Vector3.new(3, 8, 3), Position = position + Vector3.new(0, 4, 0), Color = Color3.fromRGB(180, 180, 190), Material = Enum.Material.Marble }, parent)
	local top = makePart({
		Name = "FountainTop", Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4),
		Position = position + Vector3.new(0, 9, 0), Color = Color3.fromRGB(120, 200, 255),
		Material = Enum.Material.Neon, CanCollide = false,
	}, parent)
	addLight(top, 26, 1.2, Color3.fromRGB(120, 200, 255))

	local spray = Instance.new("ParticleEmitter")
	spray.Rate = 40
	spray.Lifetime = NumberRange.new(1, 1.6)
	spray.Speed = NumberRange.new(8, 12)
	spray.SpreadAngle = Vector2.new(30, 30)
	spray.Acceleration = Vector3.new(0, -18, 0)
	spray.LightEmission = 0.6
	spray.Color = ColorSequence.new(Color3.fromRGB(170, 220, 255))
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.1) })
	spray.Parent = top
end

-- 광장 꾸미기: 빛나는 바닥 고리 / 무지개 기둥 / 떠도는 수정 / 반짝이 가루 / 스폰 패드
local function decoratePlaza(parent, center, avoid)
	-- 바닥의 빛나는 고리 (금색 / 청록 / 분홍)
	local ringColors = { Color3.fromRGB(255, 215, 90), Color3.fromRGB(90, 230, 255), Color3.fromRGB(255, 130, 220) }
	for index, diameter in ipairs({ 66, 54, 42 }) do
		local ring = makeDisc(center + Vector3.new(0, 0.3, 0), diameter, 0.12, ringColors[index], Enum.Material.Neon, parent)
		ring.CanCollide = false
		ring.CanQuery = false
		ring.Transparency = 0.45
	end
	-- 분수 테두리 빛
	local rim = makeDisc(center + Vector3.new(0, 2.25, 0), 23, 0.2, Color3.fromRGB(120, 210, 255), Enum.Material.Neon, parent)
	rim.CanCollide = false
	rim.CanQuery = false

	-- 광장 가장자리 기둥 12개 (색이 무지개처럼 이어지는 빛 구슬)
	for i = 0, 11 do
		local angle = i / 12 * math.pi * 2
		local position = center + Vector3.new(math.cos(angle) * 37, 0, math.sin(angle) * 37)
		local blocked = false
		for _, spot in ipairs(avoid) do
			if (Vector3.new(position.X, 0, position.Z) - Vector3.new(spot.X, 0, spot.Z)).Magnitude < spot.R then
				blocked = true
			end
		end
		if not blocked then
			local color = Color3.fromHSV(i / 12, 0.55, 1)
			makePart({ Name = "PlazaPillar", Size = Vector3.new(3, 14, 3), Position = position + Vector3.new(0, 7, 0), Color = Color3.fromRGB(235, 232, 225), Material = Enum.Material.Marble }, parent)
			makePart({ Name = "PillarCap", Size = Vector3.new(4.4, 1.2, 4.4), Position = position + Vector3.new(0, 14.6, 0), Color = Color3.fromRGB(200, 170, 90), Material = Enum.Material.Metal }, parent)
			local orb = makePart({
				Name = "PillarOrb", Shape = Enum.PartType.Ball, Size = Vector3.new(3.2, 3.2, 3.2), Position = position + Vector3.new(0, 17, 0),
				Color = color, Material = Enum.Material.Neon, CanCollide = false,
			}, parent)
			addLight(orb, 24, 1.4, color)
		end
	end

	-- 분수 둘레를 천천히 도는 수정 8개
	local crystals = {}
	for i = 1, 8 do
		local color = Color3.fromHSV(i / 8, 0.6, 1)
		local crystal = makePart({
			Name = "FloatingCrystal", Size = Vector3.new(2.4, 4.4, 2.4), Position = center + Vector3.new(0, 14, 0), Color = color,
			Material = Enum.Material.Neon, CanCollide = false, CanQuery = false,
		}, parent)
		addLight(crystal, 16, 1, color)
		crystals[i] = crystal
	end
	task.spawn(function()
		while parent.Parent do
			local t = os.clock()
			for i, crystal in ipairs(crystals) do
				local angle = t * 0.5 + i / #crystals * math.pi * 2
				local bob = math.sin(t * 1.6 + i) * 1.4
				crystal.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * 19, 14 + bob, math.sin(angle) * 19))
					* CFrame.Angles(t * 0.8 + i, t * 1.1, 0)
			end
			task.wait(0.05)
		end
	end)

	-- 하늘에서 천천히 내려오는 반짝이 가루
	local sky = makePart({ Name = "PlazaSparkles", Size = Vector3.new(70, 1, 70), Position = center + Vector3.new(0, 38, 0), Transparency = 1, CanCollide = false, CanQuery = false }, parent)
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Rate = 22
	sparkle.Lifetime = NumberRange.new(7, 9)
	sparkle.Speed = NumberRange.new(2, 4)
	sparkle.EmissionDirection = Enum.NormalId.Bottom
	sparkle.Shape = Enum.ParticleEmitterShape.Box
	sparkle.Acceleration = Vector3.new(0, -1, 0)
	sparkle.LightEmission = 1
	sparkle.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 225, 120)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 150, 230)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(130, 220, 255)),
	})
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.2) })
	sparkle.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.1), NumberSequenceKeypoint.new(1, 1) })
	sparkle.Parent = sky

	-- 스폰 자리: 빛나는 환영 패드
	local pad = makeDisc(Vector3.new(0, TOP + 0.35, 102), 16, 0.12, Color3.fromRGB(110, 230, 255), Enum.Material.Neon, parent)
	pad.CanCollide = false
	pad.CanQuery = false
	pad.Transparency = 0.35
	local padInner = makeDisc(Vector3.new(0, TOP + 0.4, 102), 9, 0.12, Color3.fromRGB(255, 255, 255), Enum.Material.Neon, parent)
	padInner.CanCollide = false
	padInner.CanQuery = false
	padInner.Transparency = 0.6
end

-- 마을을 둘러싸는 성벽 + 바깥의 거대한 절벽: 마을 밖(필드 절벽, 허공)이 전혀 보이지 않게 한다.
-- 동쪽에는 필드로 가는 통로(z -20 ~ 20)만 열어 둔다.
local function buildPerimeter(folder)
	local rng = Random.new(31)
	local brick = Color3.fromRGB(125, 118, 110)
	local rock = Color3.fromRGB(88, 86, 92)
	local GAP = 22

	local function solid(name, size, position, color, material)
		return makePart({ Name = name, Size = size, Position = position, Color = color, Material = material or Enum.Material.Slate }, folder)
	end

	-- 1) 성벽 (높이 44, 두께 6): 북/남/서는 이어서, 동쪽은 통로를 비워둔다
	local wallHeight, thickness = 44, 6
	solid("TownWall", Vector3.new(HALF * 2 + thickness, wallHeight, thickness), Vector3.new(0, wallHeight / 2, -HALF), brick, Enum.Material.Brick)
	solid("TownWall", Vector3.new(HALF * 2 + thickness, wallHeight, thickness), Vector3.new(0, wallHeight / 2, HALF), brick, Enum.Material.Brick)
	solid("TownWall", Vector3.new(thickness, wallHeight, HALF * 2 + thickness), Vector3.new(-HALF, wallHeight / 2, 0), brick, Enum.Material.Brick)
	local eastLength = HALF - GAP
	solid("TownWall", Vector3.new(thickness, wallHeight, eastLength), Vector3.new(HALF, wallHeight / 2, GAP + eastLength / 2), brick, Enum.Material.Brick)
	solid("TownWall", Vector3.new(thickness, wallHeight, eastLength), Vector3.new(HALF, wallHeight / 2, -(GAP + eastLength / 2)), brick, Enum.Material.Brick)

	-- 2) 모서리 탑 + 횃불
	for _, corner in ipairs({ Vector3.new(-HALF, 0, -HALF), Vector3.new(HALF, 0, -HALF), Vector3.new(-HALF, 0, HALF), Vector3.new(HALF, 0, HALF) }) do
		makeDisc(corner + Vector3.new(0, 30, 0), 18, 60, brick, Enum.Material.Brick, folder)
		local flame = makePart({
			Name = "TowerFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4), Position = corner + Vector3.new(0, 64, 0),
			Color = Color3.fromRGB(255, 150, 60), Material = Enum.Material.Neon, CanCollide = false,
		}, folder)
		addLight(flame, 40, 1.4, Color3.fromRGB(255, 170, 90))
	end

	-- 3) 성벽 뒤의 거대한 절벽 (높이 70~135, 들쭉날쭉)
	local function cliffs(alongX, fixed, sign, skipGap, depthMax)
		local t = -HALF - 30
		while t < HALF + 30 do
			local width = rng:NextNumber(30, 46)
			local height = rng:NextNumber(70, 135)
			local depth = rng:NextNumber(18, depthMax)
			if not (skipGap and math.abs(t) < GAP + width / 2) then
				local offset = sign * (fixed + depth / 2 + 2)
				local size = alongX and Vector3.new(width, height, depth) or Vector3.new(depth, height, width)
				local position = alongX and Vector3.new(t, height / 2, offset) or Vector3.new(offset, height / 2, t)
				local shade = rng:NextNumber(-8, 8)
				solid("Cliff", size, position, Color3.fromRGB(88 + shade, 86 + shade, 92 + shade), Enum.Material.Slate)
			end
			t += width * 0.8
		end
	end
	cliffs(true, HALF, -1, false, 34)   -- 북
	cliffs(true, HALF, 1, false, 34)    -- 남
	cliffs(false, HALF, -1, false, 34)  -- 서
	cliffs(false, HALF, 1, true, 16)    -- 동 (필드 쪽으로 튀어나가지 않게 얇게, 통로는 비움)

	-- 4) 끊김 없는 뒷벽: 절벽 덩어리 사이로 바깥이 비치지 않게. (동쪽은 필드가 바로 붙어 있어서 뒷벽 없이 위 절벽만)
	solid("CliffBack", Vector3.new(HALF * 2 + 200, 180, 8), Vector3.new(0, 90, -(HALF + 42)), rock)
	solid("CliffBack", Vector3.new(HALF * 2 + 200, 180, 8), Vector3.new(0, 90, HALF + 42), rock)
	solid("CliffBack", Vector3.new(8, 180, HALF * 2 + 200), Vector3.new(-(HALF + 42), 90, 0), rock)
end

-- 반환: { SpawnCFrame, GatePrompt, AnvilPrompt, GachaPrompt, WarpPrompt, DummyStart, RankBoardCFrame }
function Lobby.Build()
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = workspace

	-- 하늘 / 분위기
	Lighting.ClockTime = 14
	Lighting.Brightness = 2.2
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.25
		atmosphere.Offset = 0.2
		atmosphere.Color = Color3.fromRGB(200, 215, 235)
		atmosphere.Parent = Lighting
	end

	-- 바닥 (잔디) + 동쪽 필드로 이어지는 다리
	makePart({
		Name = "Floor", Size = Vector3.new(HALF * 2, 2, HALF * 2), Position = Vector3.new(0, TOP - 1, 0),
		Color = Color3.fromRGB(95, 150, 85), Material = Enum.Material.Grass,
	}, folder)
	makePart({
		Name = "FieldBridge", Size = Vector3.new(32, 2, 40), Position = Vector3.new(HALF + 4, TOP - 1, 0),
		Color = Color3.fromRGB(150, 140, 120), Material = Enum.Material.Cobblestone,
	}, folder)

	-- 길 (남북 중앙로 + 동서로)
	local pathColor = Color3.fromRGB(190, 175, 140)
	makePart({ Name = "PathNS", Size = Vector3.new(18, 0.2, 206), Position = Vector3.new(0, TOP + 0.1, -10), Color = pathColor, Material = Enum.Material.Cobblestone, CanCollide = false }, folder)
	makePart({ Name = "PathEW", Size = Vector3.new(260, 0.2, 14), Position = Vector3.new(0, TOP + 0.1, 0), Color = pathColor, Material = Enum.Material.Cobblestone, CanCollide = false }, folder)

	-- 남쪽 광장: 스폰 + 분수
	makeDisc(Vector3.new(0, TOP + 0.1, 70), 70, 0.2, Color3.fromRGB(205, 195, 165), Enum.Material.Marble, folder).CanCollide = false
	makeFountain(Vector3.new(0, TOP, 70), folder)
	decoratePlaza(folder, Vector3.new(0, TOP, 70), {
		{ X = 32, Z = 92, R = 16 },   -- 강화대
		{ X = 36, Z = 58, R = 16 },   -- 뽑기 머신
		{ X = 0, Z = 102, R = 12 },   -- 스폰
		{ X = -40, Z = 92, R = 20 },  -- 랭킹판 / 명예의 전당
	})
	makeLabel(makePart({ Name = "PlazaSign", Size = Vector3.new(1, 1, 1), Position = Vector3.new(0, 20, 70), Transparency = 1, CanCollide = false, CanQuery = false }, folder),
		"🏰 마을 광장", Color3.fromRGB(255, 240, 200), 0, 300, 70)

	-- 기본 맵에 원래 있던 스폰 패드는 지운다 (남겨두면 플레이어가 엉뚱한 곳에서 시작할 수 있음)
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("SpawnLocation") then
			descendant:Destroy()
		end
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, TOP + 0.5, 102)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder

	-- 마을 테두리: 성벽 + 절벽 (안에서 바깥이 보이지 않게)
	buildPerimeter(folder)

	-- 가로등: 중앙로와 동서로 양옆
	for z = -90, 50, 35 do
		makeLamp(Vector3.new(-12, TOP, z), folder)
		makeLamp(Vector3.new(12, TOP, z), folder)
	end
	for x = -60, 100, 40 do
		if math.abs(x) > 14 then
			makeLamp(Vector3.new(x, TOP, 10), folder)
		end
	end

	-- 나무: 가장자리 숲 (길 / 시설 주변은 피함)
	local rng = Random.new(2026)
	for _ = 1, 90 do
		local x = rng:NextNumber(-HALF + 6, HALF - 6)
		local z = rng:NextNumber(-HALF + 6, HALF - 6)
		local onEdge = math.max(math.abs(x), math.abs(z)) > HALF - 28
		local nearWest = x < -80 and math.abs(z) < 105
		local nearEastGate = x > HALF - 35 and math.abs(z) < 28
		local nearNorthGate = math.abs(x) < 30 and z < -HALF + 40
		local nearPlaza = math.abs(x) < 40 and z > 40
		if onEdge and not nearWest and not nearEastGate and not nearNorthGate and not nearPlaza then
			makeTree(Vector3.new(x, TOP, z), rng, folder)
		end
	end

	-- 던전 게이트 (북쪽 끝)
	local gatePos = Vector3.new(0, TOP, -HALF + 22)
	local stone = Color3.fromRGB(55, 50, 70)
	makeDisc(gatePos + Vector3.new(0, 0.3, 14), 50, 0.6, Color3.fromRGB(70, 60, 90), Enum.Material.Basalt, folder)
	makePart({ Name = "GatePillarL", Size = Vector3.new(5, 30, 5), Position = gatePos + Vector3.new(-12, 15, 0), Color = stone, Material = Enum.Material.Granite }, folder)
	makePart({ Name = "GatePillarR", Size = Vector3.new(5, 30, 5), Position = gatePos + Vector3.new(12, 15, 0), Color = stone, Material = Enum.Material.Granite }, folder)
	makePart({ Name = "GateBeam", Size = Vector3.new(30, 5, 5), Position = gatePos + Vector3.new(0, 32, 0), Color = stone, Material = Enum.Material.Granite }, folder)

	local portal = makePart({
		Name = "DungeonGate", Size = Vector3.new(19, 30, 1), Position = gatePos + Vector3.new(0, 15, 0),
		Color = Color3.fromRGB(150, 70, 255), Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false,
	}, folder)
	addLight(portal, 45, 2, Color3.fromRGB(170, 90, 255))

	local swirl = Instance.new("ParticleEmitter")
	swirl.Rate = 40
	swirl.Lifetime = NumberRange.new(1, 2)
	swirl.Speed = NumberRange.new(1, 4)
	swirl.SpreadAngle = Vector2.new(180, 180)
	swirl.Shape = Enum.ParticleEmitterShape.Box
	swirl.LightEmission = 1
	swirl.Color = ColorSequence.new(Color3.fromRGB(200, 140, 255))
	swirl.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	swirl.Parent = portal

	makeLabel(portal, "⚔ 던전 게이트 ⚔\n(파티장만 입장)", Color3.fromRGB(230, 190, 255), 20, 300, 72)

	local gatePrompt = Instance.new("ProximityPrompt")
	gatePrompt.ActionText = "던전 입장"
	gatePrompt.ObjectText = "던전 게이트"
	gatePrompt.HoldDuration = 1
	gatePrompt.MaxActivationDistance = 18
	gatePrompt.RequiresLineOfSight = false
	gatePrompt.Parent = portal

	-- 무기 강화대 (모루): 동쪽
	local anvilPos = Vector3.new(32, TOP, 92) -- 스폰 바로 옆 광장 (처음부터 눈에 들어오게)
	makeDisc(anvilPos + Vector3.new(0, 0.2, 0), 22, 0.4, Color3.fromRGB(110, 100, 90), Enum.Material.Cobblestone, folder)
	makePart({ Name = "AnvilBase", Size = Vector3.new(6, 2, 4), Position = anvilPos + Vector3.new(0, 1.2, 0), Color = Color3.fromRGB(45, 45, 50), Material = Enum.Material.Metal }, folder)
	local anvil = makePart({ Name = "Anvil", Size = Vector3.new(8, 2, 3), Position = anvilPos + Vector3.new(0, 3.2, 0), Color = Color3.fromRGB(70, 70, 80), Material = Enum.Material.Metal }, folder)
	local ember = makePart({ Name = "Ember", Size = Vector3.new(2, 0.4, 2), Position = anvilPos + Vector3.new(0, 4.4, 0), Color = Color3.fromRGB(255, 120, 40), Material = Enum.Material.Neon, CanCollide = false }, folder)
	local fire = Instance.new("ParticleEmitter")
	fire.Rate = 15
	fire.Lifetime = NumberRange.new(0.5, 1)
	fire.Speed = NumberRange.new(3, 6)
	fire.SpreadAngle = Vector2.new(25, 25)
	fire.LightEmission = 1
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 160, 60))
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	fire.Parent = ember
	addLight(ember, 18, 1, Color3.fromRGB(255, 150, 70))
	makeLabel(anvil, "🔨 무기 강화", Color3.fromRGB(255, 210, 120), 6)

	local anvilPrompt = Instance.new("ProximityPrompt")
	anvilPrompt.ActionText = "무기 강화"
	anvilPrompt.ObjectText = "강화대"
	anvilPrompt.HoldDuration = 0
	anvilPrompt.MaxActivationDistance = 14
	anvilPrompt.Parent = anvil

	-- 장비 뽑기 머신 (티켓): 동쪽
	local gachaPos = Vector3.new(36, TOP, 58)
	makeDisc(gachaPos + Vector3.new(0, 0.2, 0), 24, 0.4, Color3.fromRGB(80, 60, 110), Enum.Material.Basalt, folder)
	makePart({ Name = "GachaBase", Size = Vector3.new(8, 2, 6), Position = gachaPos + Vector3.new(0, 1.2, 0), Color = Color3.fromRGB(60, 40, 90), Material = Enum.Material.Metal }, folder)
	local body = makePart({ Name = "GachaBody", Size = Vector3.new(7, 9, 5), Position = gachaPos + Vector3.new(0, 6.7, 0), Color = Color3.fromRGB(150, 70, 230), Material = Enum.Material.SmoothPlastic }, folder)
	makePart({ Name = "GachaGlass", Size = Vector3.new(5, 5, 0.6), Position = gachaPos + Vector3.new(0, 7.5, 2.6), Color = Color3.fromRGB(180, 230, 255), Material = Enum.Material.Glass, Transparency = 0.4, CanCollide = false }, folder)
	local dome = makePart({ Name = "GachaDome", Shape = Enum.PartType.Ball, Size = Vector3.new(6, 6, 6), Position = gachaPos + Vector3.new(0, 12.5, 0), Color = Color3.fromRGB(255, 220, 110), Material = Enum.Material.Neon, CanCollide = false }, folder)
	addLight(dome, 28, 1.5, Color3.fromRGB(255, 220, 130))
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Rate = 20
	sparkle.Lifetime = NumberRange.new(0.8, 1.4)
	sparkle.Speed = NumberRange.new(2, 5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.LightEmission = 1
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 140))
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Parent = dome
	makeLabel(body, "🎰 장비 뽑기 · 강화\n(보스 티켓 1장)", Color3.fromRGB(255, 225, 140), 11, 300, 72)

	local gachaPrompt = Instance.new("ProximityPrompt")
	gachaPrompt.ActionText = "장비 뽑기 / 강화"
	gachaPrompt.ObjectText = "장비 머신"
	gachaPrompt.HoldDuration = 0
	gachaPrompt.MaxActivationDistance = 14
	gachaPrompt.Parent = body

	-- 필드 입구 (동쪽 끝)
	local fieldGate = Vector3.new(HALF - 6, TOP, 0)
	local gateStone = Color3.fromRGB(80, 90, 70)
	makePart({ Name = "FieldPillarL", Size = Vector3.new(5, 26, 5), Position = fieldGate + Vector3.new(0, 13, -20), Color = gateStone, Material = Enum.Material.Cobblestone }, folder)
	makePart({ Name = "FieldPillarR", Size = Vector3.new(5, 26, 5), Position = fieldGate + Vector3.new(0, 13, 20), Color = gateStone, Material = Enum.Material.Cobblestone }, folder)
	local beam = makePart({ Name = "FieldBeam", Size = Vector3.new(5, 5, 45), Position = fieldGate + Vector3.new(0, 27, 0), Color = gateStone, Material = Enum.Material.Cobblestone }, folder)
	makeLabel(beam, "▶ 사냥 필드 (동쪽)\n오른쪽으로 갈수록 강한 몬스터!", Color3.fromRGB(190, 255, 180), 8, 340, 76)

	-- 도달한 필드 구역 캠프로 바로 워프 (캠프의 비콘에서도 같은 메뉴가 열린다)
	local warpPrompt = Instance.new("ProximityPrompt")
	warpPrompt.ActionText = "필드 워프"
	warpPrompt.ObjectText = "필드 입구"
	warpPrompt.HoldDuration = 0
	warpPrompt.MaxActivationDistance = 24
	warpPrompt.RequiresLineOfSight = false
	warpPrompt.Parent = beam

	-- 허수아비 훈련장 입구 표지 (서쪽, 실제 허수아비는 DummyService 가 놓는다)
	local trainingSign = makePart({ Name = "TrainingSign", Size = Vector3.new(1, 1, 1), Position = Vector3.new(-100, 22, -108), Transparency = 1, CanCollide = false, CanQuery = false }, folder)
	makeLabel(trainingSign, "🎯 허수아비 훈련장\n▼ 아래로 갈수록 배수 UP", Color3.fromRGB(255, 220, 120), 0, 360, 80)

	return {
		SpawnCFrame = CFrame.new(0, 5, 102),
		GatePrompt = gatePrompt,
		AnvilPrompt = anvilPrompt,
		GachaPrompt = gachaPrompt,
		WarpPrompt = warpPrompt,
		DummyStart = Vector3.new(-100, TOP, -92),
		RankBoardCFrame = CFrame.lookAt(Vector3.new(-52, TOP + 16.5, 100), Vector3.new(0, TOP + 16.5, 72)),
	}
end

return Lobby
