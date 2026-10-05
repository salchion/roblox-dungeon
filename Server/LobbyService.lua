-- LobbyService (ServerScriptService > Modules 안의 ModuleScript, 이름: LobbyService)
-- 로비 맵을 코드로 만든다: 바닥, 스폰, 던전 게이트(포탈), 무기 강화대(모루).
-- 직접 만든 맵을 쓰고 싶다면 이 파일 대신 맵을 놓고 GatePrompt / AnvilPrompt / SpawnCFrame 만 맞춰주면 된다.

local Lobby = {}

local ORIGIN = Vector3.new(0, 0, 0)

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

local function makeLabel(part, text, color, offsetY)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 260, 0, 60)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 120
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

local function makeTorch(position, parent)
	local post = makePart({
		Size = Vector3.new(1, 6, 1),
		Position = position + Vector3.new(0, 3, 0),
		Color = Color3.fromRGB(60, 45, 35),
		Material = Enum.Material.Wood,
	}, parent)
	local flame = makePart({
		Size = Vector3.new(1.4, 1.4, 1.4),
		Position = position + Vector3.new(0, 6.7, 0),
		Color = Color3.fromRGB(255, 150, 50),
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Ball,
		CanCollide = false,
	}, parent)
	local light = Instance.new("PointLight")
	light.Range = 24
	light.Brightness = 1.4
	light.Color = Color3.fromRGB(255, 170, 90)
	light.Parent = flame
	return post
end

-- 반환: { SpawnCFrame, GatePrompt, AnvilPrompt }
function Lobby.Build()
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = workspace

	-- 바닥 (윗면이 y = 0)
	makePart({
		Name = "Floor",
		Size = Vector3.new(200, 2, 200),
		Position = ORIGIN + Vector3.new(0, -1, 0),
		Color = Color3.fromRGB(120, 125, 135),
		Material = Enum.Material.Slate,
	}, folder)

	-- 중앙 광장 (스폰 지점)
	makePart({
		Name = "Plaza",
		Size = Vector3.new(30, 0.4, 30),
		Position = ORIGIN + Vector3.new(0, 0.2, 25),
		Color = Color3.fromRGB(200, 190, 160),
		Material = Enum.Material.Cobblestone,
	}, folder)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = ORIGIN + Vector3.new(0, 0.9, 25)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder

	-- 로비 테두리 벽 (떨어짐/이탈 방지)
	for _, side in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local horizontal = side[1] ~= 0
		makePart({
			Name = "Wall",
			Size = horizontal and Vector3.new(2, 30, 200) or Vector3.new(200, 30, 2),
			Position = ORIGIN + Vector3.new(side[1] * 100, 15, side[2] * 100),
			Transparency = 1,
		}, folder)
	end

	-- 횃불
	for _, offset in ipairs({
		Vector3.new(-15, 0, 10), Vector3.new(15, 0, 10),
		Vector3.new(-15, 0, -30), Vector3.new(15, 0, -30),
		Vector3.new(-30, 0, 25), Vector3.new(30, 0, 25),
	}) do
		makeTorch(ORIGIN + offset, folder)
	end

	-- 던전 게이트 (포탈 문)
	local gatePos = ORIGIN + Vector3.new(0, 0, -40)
	local stone = Color3.fromRGB(55, 50, 70)
	makePart({ Name = "GatePillarL", Size = Vector3.new(4, 24, 4), Position = gatePos + Vector3.new(-10, 12, 0), Color = stone, Material = Enum.Material.Granite }, folder)
	makePart({ Name = "GatePillarR", Size = Vector3.new(4, 24, 4), Position = gatePos + Vector3.new(10, 12, 0), Color = stone, Material = Enum.Material.Granite }, folder)
	makePart({ Name = "GateBeam", Size = Vector3.new(24, 4, 4), Position = gatePos + Vector3.new(0, 26, 0), Color = stone, Material = Enum.Material.Granite }, folder)

	local portal = makePart({
		Name = "DungeonGate",
		Size = Vector3.new(16, 24, 1),
		Position = gatePos + Vector3.new(0, 12, 0),
		Color = Color3.fromRGB(150, 70, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
	}, folder)
	local glow = Instance.new("PointLight")
	glow.Range = 40
	glow.Brightness = 2
	glow.Color = Color3.fromRGB(170, 90, 255)
	glow.Parent = portal

	local swirl = Instance.new("ParticleEmitter")
	swirl.Rate = 30
	swirl.Lifetime = NumberRange.new(1, 2)
	swirl.Speed = NumberRange.new(1, 4)
	swirl.SpreadAngle = Vector2.new(180, 180)
	swirl.Shape = Enum.ParticleEmitterShape.Box
	swirl.LightEmission = 1
	swirl.Color = ColorSequence.new(Color3.fromRGB(200, 140, 255))
	swirl.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	swirl.Parent = portal

	makeLabel(portal, "⚔ 던전 게이트 ⚔\n(파티장만 입장)", Color3.fromRGB(230, 190, 255), 15)

	local gatePrompt = Instance.new("ProximityPrompt")
	gatePrompt.ActionText = "던전 입장"
	gatePrompt.ObjectText = "던전 게이트"
	gatePrompt.HoldDuration = 1
	gatePrompt.MaxActivationDistance = 16
	gatePrompt.RequiresLineOfSight = false
	gatePrompt.Parent = portal

	-- 무기 강화대 (모루)
	local anvilPos = ORIGIN + Vector3.new(35, 0, 25)
	makePart({ Name = "AnvilBase", Size = Vector3.new(6, 2, 4), Position = anvilPos + Vector3.new(0, 1, 0), Color = Color3.fromRGB(45, 45, 50), Material = Enum.Material.Metal }, folder)
	local anvil = makePart({ Name = "Anvil", Size = Vector3.new(8, 2, 3), Position = anvilPos + Vector3.new(0, 3, 0), Color = Color3.fromRGB(70, 70, 80), Material = Enum.Material.Metal }, folder)
	local ember = makePart({ Name = "Ember", Size = Vector3.new(2, 0.4, 2), Position = anvilPos + Vector3.new(0, 4.2, 0), Color = Color3.fromRGB(255, 120, 40), Material = Enum.Material.Neon, CanCollide = false }, folder)
	local fire = Instance.new("ParticleEmitter")
	fire.Rate = 15
	fire.Lifetime = NumberRange.new(0.5, 1)
	fire.Speed = NumberRange.new(3, 6)
	fire.SpreadAngle = Vector2.new(25, 25)
	fire.LightEmission = 1
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 160, 60))
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	fire.Parent = ember
	makeLabel(anvil, "🔨 무기 강화", Color3.fromRGB(255, 210, 120), 5)

	local anvilPrompt = Instance.new("ProximityPrompt")
	anvilPrompt.ActionText = "무기 강화"
	anvilPrompt.ObjectText = "강화대"
	anvilPrompt.HoldDuration = 0
	anvilPrompt.MaxActivationDistance = 14
	anvilPrompt.Parent = anvil

	return {
		SpawnCFrame = CFrame.new(ORIGIN + Vector3.new(0, 4, 25)),
		GatePrompt = gatePrompt,
		AnvilPrompt = anvilPrompt,
	}
end

return Lobby
