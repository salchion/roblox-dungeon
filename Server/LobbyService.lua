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

-- 반환: { SpawnCFrame, GatePrompt, AnvilPrompt, GachaPrompt, DummyStart }
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
	makeLabel(makePart({ Name = "PlazaSign", Size = Vector3.new(1, 1, 1), Position = Vector3.new(0, 20, 70), Transparency = 1, CanCollide = false, CanQuery = false }, folder),
		"🏰 마을 광장", Color3.fromRGB(255, 240, 200), 0, 300, 70)

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

	-- 로비 테두리 (보이지 않는 벽). 동쪽은 필드로 가는 입구(z -20 ~ 20)를 열어 둔다
	local function wall(size, position)
		makePart({ Name = "Wall", Size = size, Position = position, Transparency = 1 }, folder)
	end
	wall(Vector3.new(2, 40, HALF * 2), Vector3.new(-HALF, 20, 0))
	wall(Vector3.new(HALF * 2, 40, 2), Vector3.new(0, 20, -HALF))
	wall(Vector3.new(HALF * 2, 40, 2), Vector3.new(0, 20, HALF))
	wall(Vector3.new(2, 40, HALF - 20), Vector3.new(HALF, 20, (HALF + 20) / 2))
	wall(Vector3.new(2, 40, HALF - 20), Vector3.new(HALF, 20, -(HALF + 20) / 2))

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
	local anvilPos = Vector3.new(62, TOP, 42)
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
	local gachaPos = Vector3.new(62, TOP, -28)
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

	-- 허수아비 훈련장 입구 표지 (서쪽, 실제 허수아비는 DummyService 가 놓는다)
	local trainingSign = makePart({ Name = "TrainingSign", Size = Vector3.new(1, 1, 1), Position = Vector3.new(-100, 22, -108), Transparency = 1, CanCollide = false, CanQuery = false }, folder)
	makeLabel(trainingSign, "🎯 허수아비 훈련장\n▼ 아래로 갈수록 배수 UP", Color3.fromRGB(255, 220, 120), 0, 360, 80)

	return {
		SpawnCFrame = CFrame.new(0, 5, 102),
		GatePrompt = gatePrompt,
		AnvilPrompt = anvilPrompt,
		GachaPrompt = gachaPrompt,
		DummyStart = Vector3.new(-100, TOP, -92),
	}
end

return Lobby
