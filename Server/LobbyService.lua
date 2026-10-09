-- LobbyService (ServerScriptService > Modules 안의 ModuleScript, 이름: LobbyService)
-- 로비(마을)를 코드로 만든다.
--   남쪽 광장(스폰 + 분수) -> 북쪽 던전 게이트 / 서쪽 허수아비 훈련장 / 동쪽 강화대, 장비 뽑기 머신 / 동쪽 끝 필드 입구
-- 직접 만든 맵을 쓰고 싶다면 이 파일 대신 맵을 놓고 반환값(SpawnCFrame, GatePrompt, AnvilPrompt, GachaPrompt, DummyStart)만 맞춰주면 된다.

local Lighting = game:GetService("Lighting")
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))

local Lobby = {}

local HALF = 130            -- 로비는 -130 ~ +130 의 정사각형
local TOP = 0.05            -- 바닥 윗면 높이 (기본 Baseplate 와 겹쳐 깜빡이는 것 방지)
local HILL_Z, HILL_H, HILL_R = 112, 28, 18 -- 시작 언덕: 마을 남쪽 끝의 높은 언덕 (여기서 마을 전체가 내려다보인다)

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

-- maxDistance: 이 거리 안에서만 글자가 보인다 (작은 화면에서 멀리 있는 글자들이 겹치는 것을 막는다)
local function makeLabel(part, text, color, offsetY, width, height, maxDistance, alwaysOnTop)
	local gui = Instance.new("BillboardGui")
	gui.AlwaysOnTop = alwaysOnTop == true -- 지붕 / 벽에 가려 글자가 잘리지 않게(가게 간판용)
	gui.Size = UDim2.new(0, (width or 280) * 0.75, 0, (height or 64) * 0.75)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = maxDistance or 70
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
	makeDisc(position + Vector3.new(0, 1, 0), 18, 2, Color3.fromRGB(150, 150, 160), Enum.Material.Marble, parent)
	makeDisc(position + Vector3.new(0, 1.6, 0), 15, 1.2, Color3.fromRGB(70, 150, 230), Enum.Material.Glass, parent).Transparency = 0.35
	makePart({ Name = "FountainPillar", Size = Vector3.new(2.4, 4, 2.4), Position = position + Vector3.new(0, 2, 0), Color = Color3.fromRGB(180, 180, 190), Material = Enum.Material.Marble }, parent)
	local top = makePart({
		Name = "FountainTop", Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4),
		Position = position + Vector3.new(0, 5, 0), Color = Color3.fromRGB(120, 200, 255),
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
		ring.Transparency = 0.9
	end
	-- 분수 테두리 빛
	local rim = makeDisc(center + Vector3.new(0, 2.25, 0), 23, 0.2, Color3.fromRGB(70, 140, 190), Enum.Material.Neon, parent)
	rim.CanCollide = false
	rim.CanQuery = false

	-- 광장 가장자리의 낮은 등불 (높이 3.5): 시야를 가리지 않고 은은하게 분위기만 낸다
	for i = 0, 15 do
		local angle = i / 16 * math.pi * 2
		local position = center + Vector3.new(math.cos(angle) * 36, 0, math.sin(angle) * 36)
		local blocked = false
		for _, spot in ipairs(avoid) do
			if (Vector3.new(position.X, 0, position.Z) - Vector3.new(spot.X, 0, spot.Z)).Magnitude < spot.R then
				blocked = true
			end
		end
		if not blocked then
			local color = Color3.fromHSV(i / 16, 0.45, 1)
			makePart({ Name = "Bollard", Size = Vector3.new(1.4, 2.4, 1.4), Position = position + Vector3.new(0, 1.2, 0), Color = Color3.fromRGB(70, 72, 88), Material = Enum.Material.Metal }, parent)
			local lamp = makePart({
				Name = "BollardLamp", Shape = Enum.PartType.Ball, Size = Vector3.new(1.8, 1.8, 1.8), Position = position + Vector3.new(0, 3.2, 0),
				Color = color, Material = Enum.Material.Neon, CanCollide = false,
			}, parent)
			addLight(lamp, 14, 1, color)
		end
	end

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
	local pad = makeDisc(Vector3.new(0, TOP + HILL_H + 0.35, HILL_Z), 16, 0.12, Color3.fromRGB(110, 230, 255), Enum.Material.Neon, parent)
	pad.CanCollide = false
	pad.CanQuery = false
	pad.Transparency = 0.35
	local padInner = makeDisc(Vector3.new(0, TOP + HILL_H + 0.4, HILL_Z), 9, 0.12, Color3.fromRGB(255, 255, 255), Enum.Material.Neon, parent)
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
	local northHeight = 80 -- 북쪽 성벽은 명예의 전당(랭커 전시)을 걸 수 있게 높다
	solid("TownWall", Vector3.new(HALF * 2 + thickness, northHeight, thickness), Vector3.new(0, northHeight / 2, -HALF), brick, Enum.Material.Brick)
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
	-- 해 질 녘 분위기: 앞은 또렷하게 보이되 전체적으로 차분하고 어둑한 톤 (등불 / 네온이 은은하게 돋보인다)
	Lighting.ClockTime = 18.2
	Lighting.Brightness = 1.2
	Lighting.Ambient = Color3.fromRGB(95, 98, 128)
	Lighting.OutdoorAmbient = Color3.fromRGB(125, 128, 165)
	Lighting.ExposureCompensation = -0.15
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.5
	do
		local bloom = Lighting:FindFirstChild("LobbyBloom") or Instance.new("BloomEffect")
		bloom.Name = "LobbyBloom"
		bloom.Intensity = 0.04
		bloom.Size = 16
		bloom.Threshold = 3.2
		bloom.Parent = Lighting
		local grade = Lighting:FindFirstChild("LobbyGrade") or Instance.new("ColorCorrectionEffect")
		grade.Name = "LobbyGrade"
		grade.Saturation = -0.12
		grade.Contrast = 0.03
		grade.TintColor = Color3.fromRGB(235, 232, 255)
		grade.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.3
		atmosphere.Offset = 0.2
		atmosphere.Color = Color3.fromRGB(120, 125, 170)
		atmosphere.Parent = Lighting
	end

	-- 바닥 (잔디) + 동쪽 필드로 이어지는 다리
	makePart({
		Name = "Floor", Size = Vector3.new(HALF * 2, 2, HALF * 2), Position = Vector3.new(0, TOP - 1, 0),
		Color = Color3.fromRGB(58, 60, 78), Material = Enum.Material.Slate,
	}, folder)
	-- 바닥 타일: 큰 정사각 석판을 번갈아 깔아서 풀밭이 아니라 "돌로 포장된 마을"처럼 보이게 한다
	do
		local tile = 20
		local count = HALF * 2 // tile
		for ix = 0, count - 1 do
			for iz = 0, count - 1 do
				local dark = (ix + iz) % 2 == 0
				makePart({
					Name = "FloorTile", Size = Vector3.new(tile - 0.6, 0.1, tile - 0.6),
					Position = Vector3.new(-HALF + tile * (ix + 0.5), TOP + 0.04, -HALF + tile * (iz + 0.5)),
					Color = dark and Color3.fromRGB(74, 78, 100) or Color3.fromRGB(88, 93, 118),
					Material = Enum.Material.Slate, CanCollide = false, CanQuery = false,
				}, folder)
			end
		end
	end
	makePart({
		Name = "FieldBridge", Size = Vector3.new(32, 2, 40), Position = Vector3.new(HALF + 4, TOP - 1, 0),
		Color = Color3.fromRGB(150, 140, 120), Material = Enum.Material.Cobblestone,
	}, folder)

	-- 길 (남북 중앙로 + 동서로)
	local pathColor = Color3.fromRGB(205, 195, 175)
	makePart({ Name = "PathNS", Size = Vector3.new(18, 0.2, 206), Position = Vector3.new(0, TOP + 0.1, -10), Color = pathColor, Material = Enum.Material.Marble, CanCollide = false }, folder)
	makePart({ Name = "PathEW", Size = Vector3.new(260, 0.2, 14), Position = Vector3.new(0, TOP + 0.1, 0), Color = pathColor, Material = Enum.Material.Marble, CanCollide = false }, folder)

	-- 남쪽 광장: 스폰 + 분수
	makeDisc(Vector3.new(0, TOP + 0.1, 70), 70, 0.2, Color3.fromRGB(205, 195, 165), Enum.Material.Marble, folder).CanCollide = false
	makeFountain(Vector3.new(0, TOP, 70), folder)
	decoratePlaza(folder, Vector3.new(0, TOP, 70), {
		{ X = -44, Z = 28, R = 20 },  -- 대장간
		{ X = 44, Z = 28, R = 20 },   -- 뽑기 상점
		{ X = 0, Z = 28, R = 26 },    -- 훈련 구역
		{ X = 78, Z = 90, R = 26 },   -- 심연 도전 포탈
		{ X = 0, Z = HILL_Z, R = 36 },   -- 시작 언덕
		{ X = -34, Z = 72, R = 26 },     -- 왼쪽 경사로
		{ X = 34, Z = 72, R = 26 },      -- 오른쪽 경사로
		{ X = -40, Z = 92, R = 20 },  -- 랭킹판 / 명예의 전당
	})

	-- 기본 맵에 원래 있던 스폰 패드는 지운다 (남겨두면 플레이어가 엉뚱한 곳에서 시작할 수 있음)
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("SpawnLocation") then
			descendant:Destroy()
		end
	end

	-- 시작 언덕: 높은 바위 단 위에 풀밭 / 가로등 / 나무 + 마을 쪽(북쪽)으로 내려가는 두 갈래 완만한 경사로
	do
		local center = Vector3.new(0, 0, HILL_Z)
		makePart({ Name = "HillBody", Shape = Enum.PartType.Cylinder, Size = Vector3.new(HILL_H + 1.5, HILL_R * 2 + 4, HILL_R * 2 + 4),
			CFrame = CFrame.new(center + Vector3.new(0, (HILL_H - 1.5) / 2 + TOP, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(96, 92, 100), Material = Enum.Material.Slate }, folder)
		makePart({ Name = "HillGrass", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, HILL_R * 2 + 2, HILL_R * 2 + 2),
			CFrame = CFrame.new(center + Vector3.new(0, TOP + HILL_H - 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(88, 130, 84), Material = Enum.Material.Grass }, folder)
		makeLamp(Vector3.new(-11, TOP + HILL_H, HILL_Z + 6), folder)
		makeLamp(Vector3.new(11, TOP + HILL_H, HILL_Z + 6), folder)
		-- 경사로: 언덕 가장자리(y = HILL_H)에서 광장 가장자리(y = 0)까지 비스듬히 내려간다
		local function ramp(topPoint, bottomPoint, width)
			local direction = bottomPoint - topPoint
			local thickness = 4
			local middle = (topPoint + bottomPoint) / 2
			local look = CFrame.lookAt(middle, middle + direction)
			local center3 = middle - look.UpVector * (thickness / 2)
			makePart({ Name = "HillRamp", Size = Vector3.new(width, thickness, direction.Magnitude), CFrame = CFrame.lookAt(center3, center3 + direction),
				Color = Color3.fromRGB(205, 195, 175), Material = Enum.Material.Cobblestone }, folder)
		end
		for _, side in ipairs({ -1, 1 }) do
			ramp(Vector3.new(side * 9.8, TOP + HILL_H, HILL_Z - 15.1), Vector3.new(side * 54, TOP, 44), 14)
			-- 경사로 양옆 가로등
			makeLamp(Vector3.new(side * 18, TOP + 8, 94), folder)
		end
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, TOP + HILL_H + 0.5, HILL_Z)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder

	-- 심연 도전 포탈 (동쪽 광장, 서쪽 작업 광장의 맞은편): 하루 3회 점수 도전 + 소탕. 눈에 띄는 분홍 빛 고리와 빛기둥
	local riftPrompt
	do
		local rift = Vector3.new(78, TOP, 90)
		local pink = Color3.fromRGB(255, 80, 170)
		makeDisc(rift + Vector3.new(0, 0.1, 0), 26, 0.4, Color3.fromRGB(46, 30, 66), Enum.Material.Slate, folder)
		makeDisc(rift + Vector3.new(0, 0.35, 0), 22, 0.15, pink, Enum.Material.Neon, folder).CanCollide = false
		for index = 0, 23 do
			local angle = index / 24 * math.pi * 2
			local position = rift + Vector3.new(0, 10 + math.sin(angle) * 9, math.cos(angle) * 9)
			local piece = makePart({ Name = "RiftRing", Size = Vector3.new(1.4, 2.6, 2.6), Position = position, Color = pink, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false }, folder)
			piece.CFrame = CFrame.new(position) * CFrame.Angles(angle, 0, 0)
		end
		makePart({ Name = "RiftVeil", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 17, 17), Position = rift + Vector3.new(0, 10, 0),
			Color = Color3.fromRGB(190, 60, 255), Material = Enum.Material.Neon, Transparency = 0.55, CanCollide = false, CanQuery = false }, folder)
		local beam = makePart({ Name = "RiftBeacon", Size = Vector3.new(6, 220, 6), Position = rift + Vector3.new(0, 110, 0), Color = pink, Material = Enum.Material.Neon,
			Transparency = 0.88, CanCollide = false, CanQuery = false }, folder)
		addLight(beam, 60, 1.2, pink)
		local pedestal = makePart({ Name = "RiftPedestal", Size = Vector3.new(4, 3, 4), Position = rift + Vector3.new(-9, 1.5, 0), Color = Color3.fromRGB(60, 40, 90), Material = Enum.Material.Slate }, folder)
		makeLabel(pedestal, "🌀 심연 도전\n하루 3회 · 최고 점수가 소탕 보상을 정해요!", Color3.fromRGB(255, 180, 230), 6, 420, 90, 140)
		riftPrompt = Instance.new("ProximityPrompt")
		riftPrompt.ActionText = "도전 / 소탕"
		riftPrompt.ObjectText = "🌀 심연 도전"
		riftPrompt.HoldDuration = 0
		riftPrompt.MaxActivationDistance = 16
		riftPrompt.RequiresLineOfSight = false
		riftPrompt.Parent = pedestal
	end

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
		local nearNorthGate = z < -HALF + 45
		local nearPlaza = math.abs(x) < 40 and z > 40
		if onEdge and not nearWest and not nearEastGate and not nearNorthGate and not nearPlaza then
			makeTree(Vector3.new(x, TOP, z), rng, folder)
		end
	end

	-- 던전 게이트 (북쪽 끝)
	-- 던전 게이트 8개: 북쪽 성벽 앞에 나란히. 던전마다 입구가 따로 있고, 필요 레벨이 낮은 순서(서쪽 -> 동쪽)로 어려워진다.
	local gates = {}
	local stone = Color3.fromRGB(55, 50, 70)
	local listCount = #Config.Dungeon.List
	local spacing = 26
	makePart({ Name = "GatePlaza", Size = Vector3.new(spacing * listCount + 10, 0.3, 40), Position = Vector3.new(0, TOP + 0.15, -HALF + 30), Color = Color3.fromRGB(70, 60, 90), Material = Enum.Material.Basalt, CanCollide = false }, folder)
	for index, entry in ipairs(Config.Dungeon.List) do
		local dungeonType = Config.Dungeon.Types[entry.Type]
		local difficulty = Config.Dungeon.Difficulties[entry.Diff]
		local x = (index - (listCount + 1) / 2) * spacing
		local gatePos = Vector3.new(x, TOP, -HALF + 22)
		-- 오른쪽으로 갈수록 무서워진다: t = 0(맨 왼쪽, 입문) ~ 1(맨 오른쪽, 최고 난이도). 문이 점점 커지고 어두워지고 붉어지며 가시 / 해골 / 불꽃 / 연기가 붙는다.
		local t = (index - 1) / math.max(1, listCount - 1)
		local dread = Color3.fromRGB(170, 20, 40)
		local color = dungeonType.Torch:Lerp(dread, t * 0.75)
		local gateStone = Color3.fromRGB(105, 98, 115):Lerp(Color3.fromRGB(20, 14, 24), t)
		local stoneMat = t > 0.55 and Enum.Material.Basalt or Enum.Material.Granite
		local H = 24 + 20 * t      -- 문 높이 24 -> 44
		local pillar = 3.5 + 2.5 * t
		makePart({ Name = "GatePillarL", Size = Vector3.new(pillar, H, pillar), Position = gatePos + Vector3.new(-8.5, H / 2, 0), Color = gateStone, Material = stoneMat }, folder)
		makePart({ Name = "GatePillarR", Size = Vector3.new(pillar, H, pillar), Position = gatePos + Vector3.new(8.5, H / 2, 0), Color = gateStone, Material = stoneMat }, folder)
		makePart({ Name = "GateBeam", Size = Vector3.new(21 + 2 * t, 3.5 + 2 * t, 3.5 + 2 * t), Position = gatePos + Vector3.new(0, H + 1.5, 0), Color = gateStone, Material = stoneMat }, folder)
		makePart({ Name = "GateRune", Size = Vector3.new(6, 2, 3.8 + 2 * t), Position = gatePos + Vector3.new(0, H + 1.5, 0), Color = difficulty.Color:Lerp(dread, t * 0.5), Material = Enum.Material.Neon }, folder)
		-- 가시: 위쪽으로 뻗은 뿔 (뒤로 갈수록 많고 길다)
		local spikes = math.floor(t * 7)
		for spike = 1, spikes do
			local across = (spike / (spikes + 1) - 0.5) * 22
			makePart({ Name = "GateSpike", Size = Vector3.new(1.2, 4 + 6 * t, 1.2), Position = gatePos + Vector3.new(across, H + 5 + 3 * t, 0), Color = Color3.fromRGB(30, 22, 30), Material = Enum.Material.Basalt }, folder)
		end
		-- 불꽃: 오른쪽(강한 던전)으로 갈수록 기둥 / 들보 / 바닥에서 불이 더 많이, 더 크게 타오른다
		local function flame(position, size)
			local holder = makePart({ Name = "GateFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), Position = position, Color = Color3.fromRGB(255, 70, 40), Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false, CanQuery = false }, folder)
			local fire = Instance.new("Fire")
			fire.Size = size
			fire.Heat = 10
			fire.Color = Color3.fromRGB(255, 100, 40)
			fire.SecondaryColor = Color3.fromRGB(150, 15, 25)
			fire.Parent = holder
			return holder
		end
		if t >= 0.15 then
			for _, side in ipairs({ -1, 1 }) do
				local f = flame(gatePos + Vector3.new(side * 8.5, H + 2, 0), 6 + 10 * t)
				addLight(f, 24 + 20 * t, 1.4 + 1.5 * t, Color3.fromRGB(255, 90, 40))
			end
		end
		if t >= 0.35 then -- 기둥 옆면을 따라 불이 번진다
			for _, side in ipairs({ -1, 1 }) do
				for k = 1, math.floor(1 + t * 4) do
					flame(gatePos + Vector3.new(side * 8.5, H * (k / (2 + t * 4)), 2.6), 5 + 6 * t)
				end
			end
		end
		if t >= 0.5 then -- 들보 위로 줄지어 타오른다
			for k = 1, math.floor(2 + t * 5) do
				flame(gatePos + Vector3.new(((k / (math.floor(2 + t * 5) + 1)) - 0.5) * 20, H + 3.5, 0), 6 + 8 * t)
			end
		end
		if t >= 0.6 then -- 문 아래쪽 가장자리에서도 불길이 솟는다
			for k = 1, math.floor(2 + t * 3) do
				flame(gatePos + Vector3.new(((k / (math.floor(2 + t * 3) + 1)) - 0.5) * 13, 1.2, 1.5), 8 + 10 * t)
			end
		end
		-- 문 앞 바닥에 번지는 붉은 기운
		if t > 0.2 then
			local glow = makeDisc(gatePos + Vector3.new(0, 0.35, 8), 20 + 6 * t, 0.12, Color3.fromRGB(180, 20, 40), Enum.Material.Neon, folder)
			glow.CanCollide = false
			glow.Transparency = 0.75 - 0.35 * t
		end

		local portal = makePart({
			Name = "DungeonGate" .. index, Size = Vector3.new(14, H, 1), Position = gatePos + Vector3.new(0, H / 2, 0),
			Color = color, Material = Enum.Material.Neon, Transparency = 0.4 - 0.15 * t, CanCollide = false,
		}, folder)
		addLight(portal, 36 + 20 * t, 1.8 + 1.2 * t, color)

		local swirl = Instance.new("ParticleEmitter")
		swirl.Rate = 30 + 40 * t
		swirl.Lifetime = NumberRange.new(1, 2)
		swirl.Speed = NumberRange.new(1, 4 + 6 * t)
		swirl.SpreadAngle = Vector2.new(180, 180)
		swirl.Shape = Enum.ParticleEmitterShape.Box
		swirl.LightEmission = 1
		swirl.Color = ColorSequence.new(color)
		swirl.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8 + t), NumberSequenceKeypoint.new(1, 0) })
		swirl.Parent = portal
		-- 문(막) 가운데에서 불꽃이 튀어나온다: 강한 문일수록 더 많이, 더 멀리, 더 빠르게
		local embers = Instance.new("ParticleEmitter")
		embers.Rate = 6 + 110 * t
		embers.Lifetime = NumberRange.new(0.7, 1.4)
		embers.Speed = NumberRange.new(4 + 10 * t, 9 + 20 * t)
		embers.EmissionDirection = Enum.NormalId.Front
		embers.SpreadAngle = Vector2.new(35, 55)
		embers.Acceleration = Vector3.new(0, 6 + 10 * t, 0)
		embers.Shape = Enum.ParticleEmitterShape.Box
		embers.LightEmission = 1
		embers.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 70, 30))
		embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 + 0.9 * t), NumberSequenceKeypoint.new(1, 0) })
		embers.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		embers.Parent = portal
		if t >= 0.5 then -- 뒤쪽 문은 막 자체가 일렁이며 불길이 번지는 느낌
			local blaze = Instance.new("ParticleEmitter")
			blaze.Rate = 25 * t
			blaze.Lifetime = NumberRange.new(0.8, 1.6)
			blaze.Speed = NumberRange.new(1, 4)
			blaze.EmissionDirection = Enum.NormalId.Top
			blaze.SpreadAngle = Vector2.new(20, 20)
			blaze.Shape = Enum.ParticleEmitterShape.Box
			blaze.LightEmission = 0.8
			blaze.Color = ColorSequence.new(Color3.fromRGB(255, 120, 40), Color3.fromRGB(120, 10, 20))
			blaze.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3 + 4 * t), NumberSequenceKeypoint.new(1, 0) })
			blaze.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
			blaze.Parent = portal
		end
		if t >= 0.35 then -- 뒤쪽 문에서는 어두운 연기가 흘러나온다
			local smoke = Instance.new("ParticleEmitter")
			smoke.Rate = 12 + 20 * t
			smoke.Lifetime = NumberRange.new(2, 4)
			smoke.Speed = NumberRange.new(2, 5)
			smoke.EmissionDirection = Enum.NormalId.Front
			smoke.SpreadAngle = Vector2.new(25, 25)
			smoke.Color = ColorSequence.new(Color3.fromRGB(25, 12, 30))
			smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9) })
			smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
			smoke.Parent = portal
		end

		makeLabel(portal, string.format("⚔ %s\n[%s] Lv.%d+", dungeonType.Name, difficulty.Name, entry.MinLevel), difficulty.Color, 17, 260, 64, 70)

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "입장 (Lv." .. entry.MinLevel .. ")"
		prompt.ObjectText = string.format("%s · %s · %s · 권장 전투력 %d", dungeonType.Name, difficulty.Name, Config.Keys.TierIcons[difficulty.KeyTier or 1], dungeonType.RecommendedPower)
		prompt.HoldDuration = 0.8
		prompt.MaxActivationDistance = 16
		prompt.RequiresLineOfSight = false
		-- 문이 높아서(24~44) 문 한가운데에 달면 땅에서 닿지 않는다: 땅에서 가까운 높이(발 앞)에 붙인다
		local promptAnchor = Instance.new("Attachment")
		promptAnchor.Name = "PromptAnchor"
		promptAnchor.Position = Vector3.new(0, -H / 2 + 3, 3)
		promptAnchor.Parent = portal
		prompt.Parent = promptAnchor
		table.insert(gates, { Prompt = prompt, Index = index })
	end
	local gatePrompt = gates[1].Prompt

	-- 상점가: 광장에서 북쪽 중앙로로 올라가는 길 양옆에 가게 두 곳이 마주 보고 서 있다.
	--   왼쪽 대장간(무기 강화) / 오른쪽 장비 뽑기 상점. 지붕 + 줄무늬 차양 + 간판 + 카운터 + 등불 + 소품으로 "마을 가게" 느낌.
	local function makeStall(center, roofA, roofB, signText, signColor, props, lookTarget)
		local base = CFrame.lookAt(center, lookTarget or Vector3.new(0, center.Y, center.Z)) -- 앞면(-Z)이 lookTarget(기본: 중앙로)을 향한다
		local function part(name, size, offset, color, material, extra)
			local data = { Name = name, Size = size, CFrame = base * CFrame.new(offset), Color = color, Material = material or Enum.Material.Wood }
			for key, value in pairs(extra or {}) do data[key] = value end
			return makePart(data, folder)
		end
		local wood = Color3.fromRGB(110, 78, 50)
		local darkWood = Color3.fromRGB(80, 56, 38)
		part("StallFloor", Vector3.new(20, 0.6, 16), Vector3.new(0, 0.3, 0), Color3.fromRGB(135, 100, 68), Enum.Material.WoodPlanks)
		part("StallBack", Vector3.new(20, 11, 0.8), Vector3.new(0, 6, 7.6), Color3.fromRGB(150, 120, 90), Enum.Material.Brick)
		for _, side in ipairs({ -1, 1 }) do
			part("StallPost", Vector3.new(0.9, 12, 0.9), Vector3.new(side * 9.6, 6, -7.4), wood)
			part("StallSide", Vector3.new(0.8, 11, 15), Vector3.new(side * 9.8, 6, 0), Color3.fromRGB(150, 120, 90), Enum.Material.Brick)
		end
		part("StallBeam", Vector3.new(21, 0.9, 1), Vector3.new(0, 11.8, -7.4), darkWood)
		-- 줄무늬 차양 (두 색이 번갈아): 앞쪽이 낮게 기울어져 처마처럼 내려온다
		for i = 0, 9 do
			local stripe = part("Awning", Vector3.new(2.1, 0.5, 18), Vector3.new(-9.45 + i * 2.1, 12.4, 0), i % 2 == 0 and roofA or roofB, Enum.Material.Fabric,
				{ CFrame = base * CFrame.new(-9.45 + i * 2.1, 12.4, -0.8) * CFrame.Angles(math.rad(-10), 0, 0) })
			stripe.Name = "Awning"
			part("AwningFringe", Vector3.new(2.1, 1.4, 0.3), Vector3.new(-9.45 + i * 2.1, 10.6, -9.6), i % 2 == 0 and roofA or roofB, Enum.Material.Fabric,
				{ CanCollide = false })
		end
		-- 카운터 + 손님 쪽 장식
		part("Counter", Vector3.new(14, 3.2, 2.2), Vector3.new(0, 2.2, -6), wood)
		part("CounterTop", Vector3.new(14.8, 0.5, 3), Vector3.new(0, 3.95, -6), darkWood)
		-- 걸려 있는 간판 + 양옆 등불
		local sign = part("StallSign", Vector3.new(11, 3.2, 0.5), Vector3.new(0, 9.6, -9.9), Color3.fromRGB(70, 48, 32), Enum.Material.Wood)
		part("SignRopeL", Vector3.new(0.15, 1.6, 0.15), Vector3.new(-4.5, 11.2, -9.9), Color3.fromRGB(200, 190, 160), Enum.Material.Fabric, { CanCollide = false })
		part("SignRopeR", Vector3.new(0.15, 1.6, 0.15), Vector3.new(4.5, 11.2, -9.9), Color3.fromRGB(200, 190, 160), Enum.Material.Fabric, { CanCollide = false })
		makeLabel(sign, signText, signColor, 3.4, 360, 80, 70, true) -- 지붕 위로 띄우고 항상 보이게: 가게 이름이 지붕에 가려 잘리던 문제
		for _, side in ipairs({ -1, 1 }) do
			local lantern = part("StallLantern", Vector3.new(1.4, 1.8, 1.4), Vector3.new(side * 9.6, 8.5, -8.6), Color3.fromRGB(255, 200, 110), Enum.Material.Neon, { CanCollide = false })
			addLight(lantern, 24, 1.3, Color3.fromRGB(255, 205, 130))
		end
		-- 가게 앞 소품: 나무 상자 / 통
		part("Crate", Vector3.new(2.6, 2.6, 2.6), Vector3.new(-8, 1.9, -3.2), wood, Enum.Material.Wood, { CFrame = base * CFrame.new(-8, 1.9, -3.2) * CFrame.Angles(0, 0.3, 0) })
		part("Crate", Vector3.new(2, 2, 2), Vector3.new(-8, 3.8, -3.4), darkWood, Enum.Material.Wood, { CFrame = base * CFrame.new(-8, 3.8, -3.4) * CFrame.Angles(0, -0.2, 0) })
		part("Barrel", Vector3.new(3, 2.6, 2.6), Vector3.new(8, 1.9, -3), Color3.fromRGB(120, 85, 55), Enum.Material.Wood, { Shape = Enum.PartType.Cylinder, CFrame = base * CFrame.new(8, 1.9, -3) * CFrame.Angles(0, 0, math.rad(90)) })
		-- 바닥 돌길 (가게 앞 보도)
		part("StallPavement", Vector3.new(22, 0.35, 8), Vector3.new(0, 0.2, -12), Color3.fromRGB(150, 140, 125), Enum.Material.Cobblestone, { CanCollide = false })
		if props then props(base, part) end
		return base
	end

	-- 대장간 (왼쪽 / 서): 모루 + 화로 + 무기 걸이
	-- (서쪽 "작업 광장": 허수아비 훈련장 - 대장간 - 뽑기 상점이 한 광장을 둘러싸서, 허수아비 앞에서 두 가게가 바로 보인다)
	local workshop = Vector3.new(0, TOP, 28) -- 훈련 / 강화 / 뽑기 구역: 스폰 언덕에서 북쪽을 보면 한눈에 들어오고 던전 길 쪽에 있다
	local forgeCenter = Vector3.new(-44, TOP, 28)
	local anvilPart
	makeStall(forgeCenter, Color3.fromRGB(190, 70, 55), Color3.fromRGB(235, 225, 205), "🔨 대장간 · 무기 강화", Color3.fromRGB(255, 210, 120), function(base, part)
		part("AnvilBase", Vector3.new(4, 2.2, 3), Vector3.new(0, 1.7, 1), Color3.fromRGB(45, 45, 50), Enum.Material.Metal)
		anvilPart = part("Anvil", Vector3.new(7, 1.8, 2.8), Vector3.new(0, 3.7, 1), Color3.fromRGB(78, 78, 90), Enum.Material.Metal)
		local ember = part("Ember", Vector3.new(2, 0.4, 2), Vector3.new(5.5, 3.3, 3.5), Color3.fromRGB(255, 120, 40), Enum.Material.Neon, { CanCollide = false })
		local fire = Instance.new("ParticleEmitter")
		fire.Rate = 18
		fire.Lifetime = NumberRange.new(0.5, 1)
		fire.Speed = NumberRange.new(3, 6)
		fire.SpreadAngle = Vector2.new(25, 25)
		fire.LightEmission = 1
		fire.Color = ColorSequence.new(Color3.fromRGB(255, 160, 60))
		fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
		fire.Parent = ember
		addLight(ember, 22, 1.4, Color3.fromRGB(255, 150, 70))
		part("Forge", Vector3.new(5, 4.4, 4), Vector3.new(5.5, 2.6, 4.5), Color3.fromRGB(95, 80, 75), Enum.Material.Brick) -- 화로
		part("Chimney", Vector3.new(2, 8, 2), Vector3.new(5.5, 9, 6), Color3.fromRGB(80, 66, 62), Enum.Material.Brick)
		for i = -1, 1 do -- 벽에 걸린 칼
			part("WallSword", Vector3.new(0.3, 4.4, 0.15), Vector3.new(-6 + i * 1.6, 7, 7.1), Color3.fromRGB(200, 205, 215), Enum.Material.Metal, { CanCollide = false })
			part("WallHilt", Vector3.new(1.2, 0.3, 0.2), Vector3.new(-6 + i * 1.6, 5, 7.1), Color3.fromRGB(150, 110, 60), Enum.Material.Wood, { CanCollide = false })
		end
	end, workshop)

	-- 뽑기 상점 (오른쪽 / 동): 반짝이는 뽑기 머신 + 선반
	local shopCenter = Vector3.new(44, TOP, 28)
	local gachaBody
	makeStall(shopCenter, Color3.fromRGB(120, 70, 200), Color3.fromRGB(255, 225, 150), "🎰 장비 뽑기 상점", Color3.fromRGB(255, 225, 140), function(base, part)
		part("GachaBase", Vector3.new(8, 2, 6), Vector3.new(0, 1.6, 1.5), Color3.fromRGB(60, 40, 90), Enum.Material.Metal)
		gachaBody = part("GachaBody", Vector3.new(7, 8, 5), Vector3.new(0, 6.6, 1.5), Color3.fromRGB(150, 70, 230), Enum.Material.SmoothPlastic)
		part("GachaGlass", Vector3.new(5, 4.6, 0.6), Vector3.new(0, 7.2, -1.2), Color3.fromRGB(180, 230, 255), Enum.Material.Glass, { Transparency = 0.4, CanCollide = false })
		local dome = part("GachaDome", Vector3.new(5.6, 5.6, 5.6), Vector3.new(0, 12, 1.5), Color3.fromRGB(255, 220, 110), Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
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
		for _, side in ipairs({ -1, 1 }) do -- 벽 선반 위의 상품(빛나는 상자 / 포션)
			part("Shelf", Vector3.new(5, 0.4, 2), Vector3.new(side * 6.8, 6.5, 6.2), Color3.fromRGB(110, 78, 50), Enum.Material.Wood)
			part("ShelfItem", Vector3.new(1.4, 1.4, 1.4), Vector3.new(side * 7.8, 7.4, 6.2), side < 0 and Color3.fromRGB(90, 170, 255) or Color3.fromRGB(255, 130, 220), Enum.Material.Neon, { CanCollide = false })
			part("ShelfItem", Vector3.new(1.2, 1.8, 1.2), Vector3.new(side * 5.8, 7.6, 6.2), Color3.fromRGB(120, 255, 170), Enum.Material.Neon, { CanCollide = false })
		end
	end, workshop)

	-- 작업 광장 바닥 + 마을 중앙 광장에서 이어지는 길 + 가로등
	makeDisc(workshop + Vector3.new(0, 0.12, 0), 32, 0.2, Color3.fromRGB(196, 186, 168), Enum.Material.Cobblestone, folder).CanCollide = false
	for _, lampOffset in ipairs({ Vector3.new(-18, 0, -6), Vector3.new(18, 0, -6), Vector3.new(-18, 0, 6), Vector3.new(18, 0, 6) }) do
		makeLamp(workshop + lampOffset, folder)
	end

	local anvilPrompt = Instance.new("ProximityPrompt")
	anvilPrompt.ActionText = "무기 강화"
	anvilPrompt.ObjectText = "대장간"
	anvilPrompt.HoldDuration = 0
	anvilPrompt.MaxActivationDistance = 18
	anvilPrompt.RequiresLineOfSight = false
	anvilPrompt.Parent = anvilPart

	local gachaPrompt = Instance.new("ProximityPrompt")
	gachaPrompt.ActionText = "장비 뽑기 / 강화"
	gachaPrompt.ObjectText = "뽑기 상점"
	gachaPrompt.HoldDuration = 0
	gachaPrompt.MaxActivationDistance = 18
	gachaPrompt.RequiresLineOfSight = false
	gachaPrompt.Parent = gachaBody

	-- 필드 입구 (동쪽 끝)
	local fieldGate = Vector3.new(HALF - 6, TOP, 0)
	local gateStone = Color3.fromRGB(70, 85, 70)
	local green = Color3.fromRGB(120, 255, 160)
	-- 양쪽 탑 (높이 46): 멀리서도 보이는 큰 문
	for _, side in ipairs({ -1, 1 }) do
		local tower = fieldGate + Vector3.new(0, 0, side * 24)
		makePart({ Name = "FieldTower", Size = Vector3.new(10, 46, 10), Position = tower + Vector3.new(0, 23, 0), Color = gateStone, Material = Enum.Material.Cobblestone }, folder)
		makePart({ Name = "FieldTowerCap", Size = Vector3.new(13, 3, 13), Position = tower + Vector3.new(0, 47.5, 0), Color = Color3.fromRGB(50, 60, 50), Material = Enum.Material.Slate }, folder)
		local flame = makePart({ Name = "FieldBrazier", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 5, 5), Position = tower + Vector3.new(0, 52, 0), Color = Color3.fromRGB(120, 255, 170), Material = Enum.Material.Neon, CanCollide = false }, folder)
		addLight(flame, 60, 3, green)
		local torchFire = Instance.new("ParticleEmitter")
		torchFire.Rate = 40
		torchFire.Lifetime = NumberRange.new(0.8, 1.4)
		torchFire.Speed = NumberRange.new(4, 9)
		torchFire.SpreadAngle = Vector2.new(25, 25)
		torchFire.LightEmission = 1
		torchFire.Color = ColorSequence.new(Color3.fromRGB(170, 255, 200), Color3.fromRGB(60, 200, 120))
		torchFire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 0) })
		torchFire.Parent = flame
		-- 세로로 흐르는 빛 줄 (룬)
		makePart({ Name = "FieldRune", Size = Vector3.new(1, 36, 2), Position = tower + Vector3.new(-5.2, 22, 0), Color = green, Material = Enum.Material.Neon, CanCollide = false }, folder)
	end
	local beam = makePart({ Name = "FieldBeam", Size = Vector3.new(9, 8, 58), Position = fieldGate + Vector3.new(0, 40, 0), Color = gateStone, Material = Enum.Material.Cobblestone }, folder)
	makePart({ Name = "FieldBeamGlow", Size = Vector3.new(9.4, 1.2, 58.4), Position = fieldGate + Vector3.new(0, 35.4, 0), Color = green, Material = Enum.Material.Neon, CanCollide = false }, folder)
	-- 필드 입구임을 한눈에 알 수 있게: 문 위에 큰 글자 (멀리서도 보이는 빛나는 표지 + 문 안쪽 면의 큰 글씨)
	local gateSign = makePart({ Name = "FieldGateSign", Size = Vector3.new(1, 1, 1), Position = fieldGate + Vector3.new(0, 52, 0), Transparency = 1, CanCollide = false, CanQuery = false }, folder)
	local signGui = Instance.new("BillboardGui")
	signGui.Size = UDim2.new(0, 560, 0, 150)
	signGui.MaxDistance = 700
	signGui.AlwaysOnTop = true
	signGui.Parent = gateSign
	local signTitle = Instance.new("TextLabel")
	signTitle.Size = UDim2.new(1, 0, 0.62, 0)
	signTitle.BackgroundTransparency = 1
	signTitle.Font = Enum.Font.GothamBlack
	signTitle.TextScaled = true
	signTitle.TextColor3 = Color3.fromRGB(190, 255, 190)
	signTitle.TextStrokeTransparency = 0
	signTitle.Text = "🏔 사냥 필드 입구  ▶"
	signTitle.Parent = signGui
	local signSub = Instance.new("TextLabel")
	signSub.Size = UDim2.new(1, 0, 0.32, 0)
	signSub.Position = UDim2.new(0, 0, 0.66, 0)
	signSub.BackgroundTransparency = 1
	signSub.Font = Enum.Font.GothamBold
	signSub.TextScaled = true
	signSub.TextColor3 = Color3.fromRGB(255, 255, 255)
	signSub.TextStrokeTransparency = 0.2
	signSub.Text = "이 문을 지나면 몬스터가 있는 필드예요"
	signSub.Parent = signGui
	local faceGui = Instance.new("SurfaceGui") -- 문 위 가로보 안쪽(마을 쪽) 면에도 큰 글씨
	faceGui.Face = Enum.NormalId.Left
	faceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	faceGui.PixelsPerStud = 24
	faceGui.LightInfluence = 0
	faceGui.Parent = beam
	local faceText = Instance.new("TextLabel")
	faceText.Size = UDim2.new(1, 0, 1, 0)
	faceText.BackgroundTransparency = 1
	faceText.Font = Enum.Font.GothamBlack
	faceText.TextScaled = true
	faceText.TextColor3 = Color3.fromRGB(190, 255, 190)
	faceText.TextStrokeTransparency = 0
	faceText.Text = "▶ 사냥 필드 입구 ◀"
	faceText.Parent = faceGui

	-- 문 사이를 채우는 반투명 빛의 막 (지나가면 필드)
	local veil = makePart({ Name = "FieldVeil", Size = Vector3.new(1, 36, 40), Position = fieldGate + Vector3.new(0, 18, 0), Color = green, Material = Enum.Material.Neon, Transparency = 0.82, CanCollide = false, CanQuery = false }, folder)
	local mist = Instance.new("ParticleEmitter")
	mist.Rate = 30
	mist.Lifetime = NumberRange.new(2, 3)
	mist.Speed = NumberRange.new(2, 5)
	mist.SpreadAngle = Vector2.new(60, 60)
	mist.EmissionDirection = Enum.NormalId.Right
	mist.Shape = Enum.ParticleEmitterShape.Box
	mist.LightEmission = 1
	mist.Color = ColorSequence.new(green)
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
	mist.Parent = veil

	-- 광장에서 필드 문까지 이어지는 바닥 화살표(빛나는 ▶ 띠): 어디로 가야 하는지 한눈에
	for step = 0, 11 do
		local x = 52 + step * 6
		local chevron = makePart({
			Name = "FieldChevron", Size = Vector3.new(3, 0.2, 7), Position = Vector3.new(x, TOP + 0.4, 0),
			Color = green, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, Transparency = 0.25,
		}, folder)
		chevron.CFrame = CFrame.new(chevron.Position) * CFrame.Angles(0, math.rad(45), 0)
		local chevron2 = chevron:Clone()
		chevron2.CFrame = CFrame.new(chevron.Position) * CFrame.Angles(0, math.rad(-45), 0)
		chevron2.Parent = folder
	end

	-- 필드로 가는 "길"의 느낌: 광장 갈림길의 이정표 + 필드 쪽으로 이어지는 등불 가로수 길 + 멀리서도 보이는 빛기둥 + 문 앞 고리
	-- 1) 갈림길 이정표 (중앙 교차로 한켠): 동쪽 필드 / 북쪽 던전 / 서쪽 훈련장 화살표 판
	do
		local boards = {
			{ Text = "▶ 사냥 필드 (동쪽)", Y = 11, Color = Color3.fromRGB(70, 140, 80), Dir = 1 },
			{ Text = "▲ 던전 게이트 (북쪽)", Y = 8, Color = Color3.fromRGB(120, 85, 160), Dir = 0 },
			{ Text = "◀ 허수아비 훈련장 (서쪽)", Y = 5, Color = Color3.fromRGB(170, 120, 60), Dir = -1 },
		}
		-- 판 앞뒤 양쪽 면에 글자를 붙인다 (어느 쪽에서 봐도 읽히고, 판에 가려 잘리지 않는다)
		local function buildSignpost(origin, scale)
			makePart({ Name = "CrossPost", Size = Vector3.new(2.2 * scale, 14 * scale, 2.2 * scale), Position = origin + Vector3.new(0, 7 * scale, 0), Color = Color3.fromRGB(95, 65, 40), Material = Enum.Material.Wood }, folder)
			for _, board in ipairs(boards) do
				local plank = makePart({ Name = "CrossBoard", Size = Vector3.new(12 * scale, 2.8 * scale, 0.8), Position = origin + Vector3.new(board.Dir * 4.4 * scale, (board.Y + 1) * scale, 0), Color = board.Color, Material = Enum.Material.Wood }, folder)
				for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
					local surface = Instance.new("SurfaceGui")
					surface.Face = face
					surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
					surface.PixelsPerStud = 40
					surface.LightInfluence = 0
					surface.Parent = plank
					local text = Instance.new("TextLabel")
					text.Size = UDim2.new(1, 0, 1, 0)
					text.BackgroundTransparency = 1
					text.Font = Enum.Font.GothamBlack
					text.TextScaled = true
					text.TextColor3 = Color3.fromRGB(255, 252, 230)
					text.TextStrokeTransparency = 0
					text.Text = board.Text
					text.Parent = surface
				end
			end
			-- 멀리서도 보이게 꼭대기 등불
			local bulb = makePart({ Name = "CrossLamp", Shape = Enum.PartType.Ball, Size = Vector3.new(2.6 * scale, 2.6 * scale, 2.6 * scale), Position = origin + Vector3.new(0, 15.5 * scale, 0), Color = Color3.fromRGB(255, 225, 140), Material = Enum.Material.Neon, CanCollide = false }, folder)
			addLight(bulb, 45, 2, Color3.fromRGB(255, 225, 140))
		end
		buildSignpost(Vector3.new(13, 0, 13), 1)
	end

	-- 2) 필드로 이어지는 길가의 등불 (필드 문에 가까울수록 초록빛이 짙어진다) + 깃발
	for step = 0, 9 do
		local x = 30 + step * 10
		for _, side in ipairs({ -1, 1 }) do
			local fade = step / 9
			local lampColor = Color3.fromRGB(255, 225, 160):Lerp(green, fade)
			makePart({ Name = "RoadPost", Size = Vector3.new(0.7, 7, 0.7), Position = Vector3.new(x, 3.5, side * 9), Color = Color3.fromRGB(60, 56, 70), Material = Enum.Material.Metal }, folder)
			local bulb = makePart({ Name = "RoadLamp", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), Position = Vector3.new(x, 7.6, side * 9), Color = lampColor, Material = Enum.Material.Neon, CanCollide = false }, folder)
			addLight(bulb, 22, 1.1, lampColor)
			if step % 2 == 1 then
				makePart({ Name = "RoadBanner", Size = Vector3.new(0.3, 4, 2.4), Position = Vector3.new(x, 5.4, side * 9.8), Color = green:Lerp(Color3.fromRGB(30, 80, 50), 0.4), Material = Enum.Material.Fabric, CanCollide = false }, folder)
			end
		end
	end

	-- 3) 문 위로 솟는 빛기둥: 마을 어디서든 "저쪽이 필드"라는 게 보인다
	local pillar = makePart({ Name = "FieldBeacon", Size = Vector3.new(14, 320, 14), Position = fieldGate + Vector3.new(0, 160, 0), Color = green, Material = Enum.Material.Neon, Transparency = 0.88, CanCollide = false, CanQuery = false }, folder)
	addLight(pillar, 80, 1.2, green)

	-- 4) 문 앞의 큰 빛 고리 (통과하는 느낌)
	for ring = 1, 3 do
		for index = 0, 19 do
			local angle = index / 20 * math.pi * 2
			local radius = 12 + ring * 2.5
			local piece = makePart({
				Name = "FieldRing", Size = Vector3.new(1, 2.4, 2.4), Position = fieldGate + Vector3.new(-6 - ring * 3, 17 + math.sin(angle) * radius, math.cos(angle) * radius),
				Color = green, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, Transparency = 0.15 + ring * 0.15,
			}, folder)
			piece.CFrame = CFrame.new(piece.Position) * CFrame.Angles(angle, 0, 0)
		end
	end

	-- 도달한 필드 구역 캠프로 바로 워프 (캠프의 비콘에서도 같은 메뉴가 열린다)
	local warpPrompt = Instance.new("ProximityPrompt")
	warpPrompt.ActionText = "필드 워프"
	warpPrompt.ObjectText = "필드 입구"
	warpPrompt.HoldDuration = 0
	warpPrompt.MaxActivationDistance = 40
	warpPrompt.RequiresLineOfSight = false
	warpPrompt.Parent = beam

	-- 허수아비 훈련장 입구 표지 (서쪽, 실제 허수아비는 DummyService 가 놓는다)
	local trainingSign = makePart({ Name = "TrainingSign", Size = Vector3.new(1, 1, 1), Position = Vector3.new(0, 24, 38), Transparency = 1, CanCollide = false, CanQuery = false }, folder)
	makeLabel(trainingSign, "🎯 허수아비 훈련장\n대미지 / DPS 를 확인해요", Color3.fromRGB(255, 220, 120), 0, 340, 76, 110)

	-- 쨍한 느낌 줄이기: 네온 부품은 색을 살짝 가라앉히고, 조명은 약하게 (은은하게 빛나는 정도)
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("PointLight") then
			descendant.Brightness *= 0.4
			descendant.Range *= 0.8
		elseif descendant:IsA("BasePart") and descendant.Material == Enum.Material.Neon and descendant.Transparency < 0.6 then
			-- 전구 / 등불 / 장식 공은 눈이 아픈 네온 대신 은은한 불투명 재질 + 따뜻한 색으로 (빛은 PointLight 가 맡는다)
			if descendant.Shape == Enum.PartType.Ball and (string.find(descendant.Name, "Lamp") or string.find(descendant.Name, "Bulb") or string.find(descendant.Name, "Lantern") or string.find(descendant.Name, "Flame")) then
				descendant.Material = Enum.Material.SmoothPlastic
				descendant.Color = descendant.Color:Lerp(Color3.fromRGB(235, 190, 120), 0.4):Lerp(Color3.fromRGB(70, 66, 76), 0.25)
			else
				descendant.Color = descendant.Color:Lerp(Color3.fromRGB(90, 90, 110), 0.5)
			end
		elseif descendant:IsA("ParticleEmitter") then
			descendant.LightEmission = math.min(descendant.LightEmission, 0.55)
		end
	end

	return {
		SpawnCFrame = CFrame.new(0, HILL_H + 5, HILL_Z),
		GatePrompt = gatePrompt, -- (호환용: 첫 번째 게이트)
		Gates = gates,
		AnvilPrompt = anvilPrompt,
		GachaPrompt = gachaPrompt,
		WarpPrompt = warpPrompt,
		RiftPrompt = riftPrompt,
		DummyStart = Vector3.new(0, TOP, 28), -- 허수아비 하나가 서는 자리
		RestStart = Vector3.new(-84, TOP, 70), -- 휴식 구역(방치 수입): 훈련장과 따로 떨어진 아늑한 모닥불 쉼터
		RankBoardCFrame = CFrame.lookAt(Vector3.new(-52, TOP + 16.5, 100), Vector3.new(0, TOP + 16.5, 72)),
	}
end

return Lobby
