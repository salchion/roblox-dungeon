-- DummyService (ServerScriptService > Modules 안의 ModuleScript, 이름: DummyService)
-- 로비 허수아비 훈련장: 대미지 숫자 / DPS 를 확인하는 연습용 (골드는 없다). 방치 수입은 따로 있는 휴식 구역(BuildRest).
-- 1번(x1)부터 10번(x30)까지 한 줄로 나열되고, 배수가 높을수록 크고 화려하고 강해 보인다.
-- 더미마다 이름 / 배율(Multiplier) / 방어력(RequiredPower: 필요 전투력)이 다르다 -> Config.Dummy.List

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Quest = require(script.Parent:WaitForChild("QuestService"))

local Dummy = {}

local dummies = {}   -- [Model] = { Multiplier, RequiredLevel, Parts..., BaseColor, Flashing }
local folder

-- 번호별 몸 색/재질: 짚 -> 나무 -> 강철 -> 금 -> 진홍 -> 마력
local STYLES = {
	{ Color = Color3.fromRGB(205, 175, 110), Material = Enum.Material.Fabric },
	{ Color = Color3.fromRGB(190, 160, 100), Material = Enum.Material.Fabric },
	{ Color = Color3.fromRGB(160, 120, 75), Material = Enum.Material.Wood },
	{ Color = Color3.fromRGB(140, 105, 70), Material = Enum.Material.Wood },
	{ Color = Color3.fromRGB(150, 155, 165), Material = Enum.Material.Metal },
	{ Color = Color3.fromRGB(120, 140, 175), Material = Enum.Material.Metal },
	{ Color = Color3.fromRGB(95, 140, 200), Material = Enum.Material.DiamondPlate },
	{ Color = Color3.fromRGB(240, 190, 60), Material = Enum.Material.Foil },
	{ Color = Color3.fromRGB(200, 40, 55), Material = Enum.Material.Neon },
	{ Color = Color3.fromRGB(170, 70, 255), Material = Enum.Material.Neon },
}

local function newPart(props, parent)
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

local function formatMultiplier(multiplier)
	if multiplier == math.floor(multiplier) then
		return tostring(multiplier)
	end
	return string.format("%.1f", multiplier)
end

local function addGlow(part, color, range)
	local light = Instance.new("PointLight")
	light.Range = range
	light.Brightness = 1.5
	light.Color = color
	light.Parent = part
end

local function buildDummy(index, info, position, nameIndex, bigScale)
	local model = Instance.new("Model")
	model.Name = "Dummy" .. (nameIndex or index)

	local style = STYLES[index] or STYLES[#STYLES]
	local s = (1 + 0.12 * (index - 1)) * (bigScale or 1) -- 번호가 오를수록 커짐 (1.0 ~ 2.1배)
	local V = function(x, y, z) return Vector3.new(x * s, y * s, z * s) end
	local O = function(x, y, z) return position + Vector3.new(x * s, y * s, z * s) end
	local wood = Color3.fromRGB(95, 65, 40)
	local metal = Color3.fromRGB(70, 75, 85)

	-- 받침대 + 기둥 + 팔
	newPart({ Name = "Base", Size = V(4, 0.6, 4), Position = O(0, 0.3, 0), Color = Color3.fromRGB(80, 75, 70), Material = Enum.Material.Cobblestone }, model)
	newPart({ Name = "Post", Size = V(0.9, 7, 0.9), Position = O(0, 3.5, 0), Color = wood, Material = Enum.Material.Wood }, model)
	newPart({ Name = "Arms", Size = V(6.4, 0.8, 0.8), Position = O(0, 5.7, 0), Color = wood, Material = Enum.Material.Wood }, model)

	-- 몸통 / 머리 (맞을 때 번쩍이는 부분)
	local body = newPart({ Name = "Body", Size = V(3, 3.6, 2), Position = O(0, 4.7, 0), Color = style.Color, Material = style.Material }, model)
	local head = newPart({ Name = "Head", Shape = Enum.PartType.Ball, Size = V(2.3, 2.3, 2.3), Position = O(0, 7.4, 0), Color = style.Color, Material = style.Material }, model)
	model.PrimaryPart = body
	local flashParts = { body, head }

	-- 4번~: 어깨 보호대
	if index >= 4 then
		for _, side in ipairs({ -1, 1 }) do
			local pad = newPart({ Name = "Shoulder", Size = V(1.6, 1.0, 1.8), Position = O(side * 2.6, 5.9, 0), Color = metal, Material = Enum.Material.Metal }, model)
			table.insert(flashParts, pad)
		end
	end

	-- 6번~: 투구
	if index >= 6 then
		local helm = newPart({ Name = "Helm", Size = V(2.6, 1.3, 2.6), Position = O(0, 8.3, 0), Color = metal, Material = Enum.Material.Metal }, model)
		table.insert(flashParts, helm)
	end

	-- 7번~: 뿔
	if index >= 7 then
		for _, side in ipairs({ -1, 1 }) do
			local horn = newPart({
				Name = "Horn", Size = V(0.5, 2.2, 0.5),
				CFrame = CFrame.new(O(side * 1.3, 9.2, 0)) * CFrame.Angles(0, 0, math.rad(-side * 25)),
				Color = Color3.fromRGB(235, 225, 200), Material = Enum.Material.SmoothPlastic,
			}, model)
			table.insert(flashParts, horn)
		end
	end

	-- 8번~: 가슴 갑옷 + 빛나는 눈
	if index >= 8 then
		local plate = newPart({ Name = "Chest", Size = V(3.4, 2.4, 2.4), Position = O(0, 4.9, 0), Color = style.Color:Lerp(Color3.new(1, 1, 1), 0.2), Material = style.Material }, model)
		table.insert(flashParts, plate)
		for _, side in ipairs({ -0.5, 0.5 }) do
			newPart({ Name = "Eye", Shape = Enum.PartType.Ball, Size = V(0.4, 0.4, 0.4), Position = O(side, 7.5, 1.1), Color = Color3.fromRGB(255, 240, 120), Material = Enum.Material.Neon, CanCollide = false }, model)
		end
	end

	-- 9번~: 오라(불꽃 입자 + 빛)
	if index >= 9 then
		local aura = Instance.new("ParticleEmitter")
		aura.Rate = index == 10 and 45 or 25
		aura.Lifetime = NumberRange.new(0.8, 1.4)
		aura.Speed = NumberRange.new(2, 5)
		aura.SpreadAngle = Vector2.new(30, 30)
		aura.EmissionDirection = Enum.NormalId.Top
		aura.LightEmission = 1
		aura.Color = ColorSequence.new(style.Color)
		aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2 * s), NumberSequenceKeypoint.new(1, 0) })
		aura.Parent = body
		addGlow(body, style.Color, 24)
	end

	-- 10번: 머리 위에 떠 있는 왕관 고리
	if index == 10 then
		newPart({
			Name = "Crown", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 4.2 * s, 4.2 * s),
			CFrame = CFrame.new(O(0, 10.4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(255, 220, 90), Material = Enum.Material.Neon, CanCollide = false,
		}, model)
	end

	-- 보스 더미: 어깨 가시 + 붉은 눈 + 떠 있는 파편으로 "진짜 보스 같은" 위압감
	if info.Boss then
		for i = -2, 2 do
			newPart({ Name = "Spike", Size = V(0.4, 1.8, 0.4), CFrame = CFrame.new(O(i * 1.1, 6.7, -1.1)) * CFrame.Angles(math.rad(-20), 0, 0), Color = Color3.fromRGB(235, 225, 200), Material = Enum.Material.SmoothPlastic }, model)
		end
		for i = 1, 5 do
			local a = i / 5 * math.pi * 2
			newPart({ Name = "Shard", Size = V(0.5, 1.2, 0.5), CFrame = CFrame.new(O(math.cos(a) * 4, 6 + math.sin(a * 2), math.sin(a) * 4)) * CFrame.Angles(a, a, 0), Color = Color3.fromRGB(255, 60, 70), Material = Enum.Material.Neon, CanCollide = false }, model)
		end
	end

	-- 이름표: 이름 + 배율 / 방어력(필요 전투력)
	local gui = Instance.new("BillboardGui")
	gui.Enabled = false -- (허수아비 이름표는 훈련장 표지와 중복이라 숨긴다)
	gui.Size = UDim2.new(0, 190, 0, 52)
	gui.StudsOffset = Vector3.new(0, 3.5 + 2.2 * s, 0)
	gui.MaxDistance = 40 -- 가까이 가야 이름 / 방어력이 보인다 (작은 화면에서 글자 겹침 방지)
	gui.Parent = head

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.55, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextStrokeTransparency = 0
	title.TextColor3 = style.Color:Lerp(Color3.new(1, 1, 1), 0.35)
	title.Text = info.Name
	title.Parent = gui

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, 0, 0.45, 0)
	sub.Position = UDim2.new(0, 0, 0.55, 0)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.TextStrokeTransparency = 0.3
	sub.TextColor3 = Color3.fromRGB(230, 230, 240)
	sub.Text = ""
	sub.Parent = gui

	model.Parent = folder

	local baseColors = {}
	for _, part in ipairs(flashParts) do
		baseColors[part] = part.Color
	end
	dummies[model] = {
		Multiplier = info.Multiplier,
		RequiredPower = info.RequiredPower,
		Name = info.Name,
		FlashParts = flashParts,
		BaseColors = baseColors,
		Flashing = false,
	}
end

-- start: 허수아비 위치. 허수아비는 하나만 놓고, 주변은 훈련장 바닥 + 빛나는 원으로 꾸민다.
function Dummy.Build(start)
	folder = Instance.new("Folder")
	folder.Name = "Dummies"
	folder.Parent = workspace

	newPart({
		Name = "TrainingGround",
		Size = Vector3.new(34, 0.3, 34),
		Position = start + Vector3.new(0, 0.15, 0),
		Color = Color3.fromRGB(125, 100, 70),
		Material = Enum.Material.Ground,
		CanCollide = false,
	}, folder)
	local ring = newPart({
		Name = "TrainingRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 26, 26),
		CFrame = CFrame.new(start + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 215, 90), Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, Transparency = 1, -- (눈에 안 보이는 받침: 안내판만 붙인다)
	}, folder)

	-- 훈련장 안내판
	local signGui = Instance.new("BillboardGui")
	signGui.Size = UDim2.new(0, 240, 0, 50)
	signGui.StudsOffset = Vector3.new(0, 15, 0)
	signGui.MaxDistance = 50
	signGui.Parent = ring
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.new(1, 0, 1, 0)
	signLabel.BackgroundTransparency = 1
	signLabel.Font = Enum.Font.GothamBlack
	signLabel.TextScaled = true
	signLabel.TextColor3 = Color3.fromRGB(255, 225, 120)
	signLabel.TextStrokeTransparency = 0
	signLabel.Text = ""
	signLabel.Visible = false -- (로비에 "허수아비 훈련장" 글자는 필요 없어서 뺐다)
	signLabel.Parent = signGui

	-- 허수아비 하나: 8번 모양(어깨 보호대 / 투구 / 뿔 / 가슴 갑옷 / 빛나는 눈)을 써서 크고 듬직하게. 이름은 Dummy1.
	buildDummy(8, Config.Dummy.List[1], start, 1, 0.8) -- 너무 크면 화면을 가려서 작게 (약 1.5배)
end

local restFire, restCenter = nil, Vector3.zero -- 휴식 구역 모닥불 (IdleHit 가 타오르게 한다)

local function flash(data)
	if data.Flashing then return end
	data.Flashing = true
	for _, part in ipairs(data.FlashParts) do
		part.Color = Color3.new(1, 1, 1)
	end
	task.delay(0.08, function()
		for _, part in ipairs(data.FlashParts) do
			part.Color = data.BaseColors[part]
		end
		data.Flashing = false
	end)
end

-- 로비에서 쏜 탄이 허수아비에 맞았는지 판정하고 골드를 지급. 반환: 탄이 끝나는 지점 (아무것도 안 맞으면 nil)
-- 방치 모드: 허수아비가 맞는 것처럼 번쩍인다 (훈련장 원 안에 서 있는 동안 IdleService 가 1초마다 부른다)
function Dummy.IdleHit(player)
	if restFire and restFire.Parent then -- 휴식 구역: 모닥불이 한 번 확 타오른다
		restFire.Size = 14
		task.delay(0.25, function()
			if restFire and restFire.Parent then restFire.Size = 8 end
		end)
		Effects.Burst(restCenter + Vector3.new(0, 3, 0), Color3.fromRGB(255, 200, 110), 6)
	end
end

-- 허수아비 머리 위 DPS 표시: 최근 5초 동안 쏜 피해의 평균 + 지금까지의 최고 기록 (쏘는 사람마다 따로 계산, 마지막으로 쏜 사람 기준으로 보여 준다)
local dpsLog = setmetatable({}, { __mode = "k" })  -- [player] = { Hits = { { t, amount } }, Best = 0 }
local function showDps(model, data, player, damage)
	local now = os.clock()
	local log = dpsLog[player]
	if not log then
		log = { Hits = {}, Best = 0 }
		dpsLog[player] = log
	end
	table.insert(log.Hits, { now, damage })
	local total, first = 0, now
	for i = #log.Hits, 1, -1 do
		local hit = log.Hits[i]
		if now - hit[1] > 5 then
			table.remove(log.Hits, i)
		else
			total += hit[2]
			first = math.min(first, hit[1])
		end
	end
	local dps = total / math.max(1.5, now - first)
	if dps > log.Best then log.Best = dps end
	-- 머리 위 글자 대신 쏘는 사람 화면의 작은 패널(DpsPanelClient)이 이 값을 읽어 보여 준다
	player:SetAttribute("DummyDps", math.floor(dps))
	player:SetAttribute("DummyBest", math.floor(log.Best))
	player:SetAttribute("DummyHit", damage)
	player:SetAttribute("DummyTick", (player:GetAttribute("DummyTick") or 0) + 1)
end

local goldRemainder = setmetatable({}, { __mode = "k" }) -- [player] = 아직 지급하지 못한 소수점 골드

function Dummy.Shoot(player, origin, direction)
	if not folder or player:GetAttribute("Zone") ~= "Lobby" then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }

	local weaponType = Config.GetPlayerWeapon(player)
	local result = workspace:Raycast(origin, direction * Config.GetRange(player, weaponType), params)
	if not result then return nil end

	local model = result.Instance:FindFirstAncestorOfClass("Model")
	local data = model and dummies[model]
	if not data then return result.Position end

	flash(data)

	-- (방어력이 있는 허수아비가 남아 있을 때만) 내 전투력이 모자라면 공격이 튕겨 나간다
	local power = player:GetAttribute("Power") or 0
	if power < data.RequiredPower then
		Effects.FloatText(result.Position, string.format("🛡 튕겨 나가요! 전투력 %d 필요 (지금 %d)", data.RequiredPower, power), Color3.fromRGB(255, 130, 120))
		Effects.Burst(result.Position, Color3.fromRGB(190, 195, 210), 6)
		return result.Position
	end

	-- 직접 쏴서는 골드를 받지 않는다 (골드는 방치 수입 / 필드 / 던전에서): 허수아비는 대미지 / DPS 를 확인하는 연습용이다
	Quest.Add(player, "DummyHits", 1)
	local okDungeon, Dungeon = pcall(function() return require(script.Parent:WaitForChild("DungeonService")) end)
	if okDungeon then
		local damage, isCrit = Dungeon.ComputeDamage(player)
		Effects.DamageNumber(result.Position, damage, isCrit)
		showDps(model, data, player, damage)
	end
	return result.Position
end

-- 휴식 구역: 훈련장과 따로 떨어진 아늑한 쉼터. 모닥불 + 통나무 의자 + 등불 + 푸른 원. 원 안에 서 있으면 방치 수입이 쌓이고, 접속을 꺼도 쌓인다.
function Dummy.BuildRest(position)
	restCenter = position
	local pad = newPart({
		Name = "RestGround", Size = Vector3.new(36, 0.3, 36), Position = position + Vector3.new(0, 0.15, 0),
		Color = Color3.fromRGB(80, 110, 85), Material = Enum.Material.Grass, CanCollide = false,
	}, folder)
	local ring = newPart({
		Name = "RestRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 30, 30),
		CFrame = CFrame.new(position + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(120, 210, 230), Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, Transparency = 1,
	}, folder)

	-- 아늑한 캠프: 전부 고정 부품 (충돌 / 질의 / 접촉 없음, 그림자 없음). 모닥불 하나 + 은은한 등불 2개만 빛난다.
	local gy = position + Vector3.new(0, 0.3, 0)
	local function deco(name, size, cf, color, material, extra)
		local data = { Name = name, Size = size, CFrame = cf, Color = color, Material = material, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
		for key, value in pairs(extra or {}) do data[key] = value end
		return newPart(data, folder)
	end
	local function box(name, size, pos, color, material, yaw)
		return deco(name, size, CFrame.new(pos) * CFrame.Angles(0, yaw or 0, 0), color, material)
	end
	local function ball(name, diameter, pos, color, material, sizeY)
		return deco(name, Vector3.new(diameter, sizeY or diameter, diameter), CFrame.new(pos), color, material, { Shape = Enum.PartType.Ball })
	end
	local function pole(name, height, diameter, basePos, color, material)
		return deco(name, Vector3.new(height, diameter, diameter), CFrame.new(basePos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, material, { Shape = Enum.PartType.Cylinder })
	end
	local wood, darkWood = Color3.fromRGB(120, 84, 54), Color3.fromRGB(84, 60, 42)
	local function around(radius, angle) return gy + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius) end

	-- 모닥불 자리: 흙 바닥 + 돌 고리 + 장작 + 불 + 삼각 걸이 냄비
	pole("CampDirt", 0.1, 15, gy, Color3.fromRGB(112, 90, 66), Enum.Material.Ground)
	for i = 1, 10 do
		local angle = i / 10 * math.pi * 2
		ball("FireStone", 1.5, position + Vector3.new(math.cos(angle) * 2.8, 0.65, math.sin(angle) * 2.8), Color3.fromRGB(116, 112, 106), Enum.Material.Slate, 1.1)
	end
	for i = 1, 3 do
		deco("Log", Vector3.new(0.7, 0.7, 3.6), CFrame.new(position + Vector3.new(0, 0.9, 0)) * CFrame.Angles(math.rad(14), math.rad(i * 60), 0), Color3.fromRGB(95, 62, 38), Enum.Material.Wood)
	end
	local flameBase = newPart({ Name = "RestFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), Position = position + Vector3.new(0, 1.6, 0), Transparency = 1, CanCollide = false, CanQuery = false }, folder)
	restFire = Instance.new("Fire")
	restFire.Size = 8
	restFire.Heat = 6
	restFire.Parent = flameBase
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 170, 90)
	glow.Range = 22
	glow.Brightness = 1
	glow.Shadows = false
	glow.Parent = flameBase
	for i = 0, 2 do -- 삼각 걸이 + 냄비
		local angle = i / 3 * math.pi * 2 + 0.5
		deco("TripodLeg", Vector3.new(0.25, 4.6, 0.25), CFrame.lookAt(position + Vector3.new(math.cos(angle) * 1.3, 2.4, math.sin(angle) * 1.3), position + Vector3.new(0, 4.6, 0)) * CFrame.Angles(math.rad(90), 0, 0), darkWood, Enum.Material.Wood)
	end
	ball("CampPot", 1.5, position + Vector3.new(0, 3.1, 0), Color3.fromRGB(46, 44, 48), Enum.Material.Metal, 1.2)

	-- 통나무 의자 4개 (불을 둘러싼다) + 바닥 담요
	local blanketColors = { Color3.fromRGB(176, 88, 76), Color3.fromRGB(86, 120, 150), Color3.fromRGB(204, 164, 84), Color3.fromRGB(110, 140, 96) }
	for i = 1, 4 do
		local angle = i / 4 * math.pi * 2 + 0.4
		local seat = position + Vector3.new(math.cos(angle) * 7.5, 0.9, math.sin(angle) * 7.5)
		newPart({ Name = "LogSeat", Size = Vector3.new(4.4, 1.4, 1.6), CFrame = CFrame.lookAt(seat, position + Vector3.new(0, 0.9, 0)), Color = Color3.fromRGB(120, 82, 52), Material = Enum.Material.Wood, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }, folder)
		local blanketPos = around(10.6, angle + math.pi / 4) + Vector3.new(0, 0.05, 0)
		deco("Blanket", Vector3.new(3.2, 0.08, 2.2), CFrame.lookAt(blanketPos, position + Vector3.new(0, blanketPos.Y - position.Y, 0)), blanketColors[i], Enum.Material.Fabric)
	end

	-- 텐트 2개 (A자): 불 쪽으로 입구가 열려 있다
	for _, angle in ipairs({ math.rad(205), math.rad(250) }) do
		local tentPos = around(14.5, angle)
		local base = CFrame.lookAt(tentPos, Vector3.new(position.X, tentPos.Y, position.Z))
		local cloth = angle < math.rad(220) and Color3.fromRGB(196, 170, 120) or Color3.fromRGB(150, 98, 84)
		for _, side in ipairs({ -1, 1 }) do
			deco("TentPanel", Vector3.new(5, 0.2, 7), base * CFrame.new(side * 1.6, 1.9, 0) * CFrame.Angles(0, 0, -side * math.rad(50)), cloth, Enum.Material.Fabric)
		end
		deco("TentRidge", Vector3.new(0.3, 0.3, 7.6), base * CFrame.new(0, 3.85, 0), darkWood, Enum.Material.Wood)
		deco("TentBack", Vector3.new(3.4, 3.2, 0.2), base * CFrame.new(0, 1.6, 3.4), cloth:Lerp(Color3.fromRGB(60, 50, 44), 0.35), Enum.Material.Fabric)
		deco("TentDoor", Vector3.new(2.6, 3, 0.2), base * CFrame.new(0, 1.5, -3.4), Color3.fromRGB(46, 38, 36), Enum.Material.Fabric)
		for _, side in ipairs({ -1, 1 }) do
			deco("TentPole", Vector3.new(0.3, 4, 0.3), base * CFrame.new(side * 0.9, 2, -3.7) * CFrame.Angles(0, 0, side * math.rad(-10)), darkWood, Enum.Material.Wood)
		end
	end

	-- 비스듬한 처마 (기대어 세운 지붕) + 탁자
	do
		local leanPos = around(14.5, math.rad(120))
		local base = CFrame.lookAt(leanPos, Vector3.new(position.X, leanPos.Y, position.Z))
		for _, side in ipairs({ -1, 1 }) do
			pole("LeanPost", 5, 0.4, base:PointToWorldSpace(Vector3.new(side * 3.4, 0, -2.4)), wood, Enum.Material.Wood)
			pole("LeanPost", 3.4, 0.4, base:PointToWorldSpace(Vector3.new(side * 3.4, 0, 2.4)), wood, Enum.Material.Wood)
		end
		deco("LeanRoof", Vector3.new(8.4, 0.25, 6.6), base * CFrame.new(0, 4.5, 0) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(176, 88, 76), Enum.Material.Fabric)
		deco("LeanTable", Vector3.new(4.4, 0.4, 1.8), base * CFrame.new(0, 1.8, 0.4), wood, Enum.Material.WoodPlanks)
		for _, side in ipairs({ -1, 1 }) do
			deco("LeanTableLeg", Vector3.new(0.3, 1.6, 1.4), base * CFrame.new(side * 1.9, 1, 0.4), darkWood, Enum.Material.Wood)
		end
		ball("CampCup", 0.6, base:PointToWorldSpace(Vector3.new(-1, 2.3, 0.4)), Color3.fromRGB(220, 200, 170), Enum.Material.SmoothPlastic)
	end

	-- 해먹: 나무 두 그루 사이
	do
		local treeA, treeB = around(15.5, math.rad(300)), around(15.5, math.rad(335))
		for _, treePos in ipairs({ treeA, treeB }) do
			pole("CampTrunk", 8, 1.6, treePos, Color3.fromRGB(96, 68, 44), Enum.Material.Wood)
			ball("CampLeaves", 8, treePos + Vector3.new(0, 9, 0), Color3.fromRGB(88, 130, 82), Enum.Material.Grass, 6.5)
		end
		local mid = (treeA + treeB) / 2
		local span = (treeB - treeA)
		local yaw = math.atan2(-span.Z, span.X)
		deco("Hammock", Vector3.new(span.Magnitude * 0.5, 0.15, 2.2), CFrame.new(mid + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, yaw, 0), Color3.fromRGB(190, 150, 96), Enum.Material.Fabric)
		for _, t in ipairs({ -1, 1 }) do
			deco("HammockRope", Vector3.new(span.Magnitude * 0.3, 0.1, 0.1), CFrame.new(mid + span.Unit * (t * span.Magnitude * 0.34) + Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, yaw, t * math.rad(-20)), Color3.fromRGB(200, 188, 150), Enum.Material.Fabric)
		end
	end

	-- 등불 기둥 3개: 나무 기둥 + 종이등. 가로등이 아니라 낮은 캠프 등불이고, 둘만 아주 은은하게 빛난다.
	for i = 1, 3 do
		local lampPos = around(12.2, i / 3 * math.pi * 2 + 1.1)
		pole("CampPost", 3.6, 0.35, lampPos, darkWood, Enum.Material.Wood)
		box("CampArm", Vector3.new(0.9, 0.2, 0.2), lampPos + Vector3.new(0.4, 3.5, 0), darkWood, Enum.Material.Wood)
		local lantern = box("CampLantern", Vector3.new(0.9, 1.1, 0.9), lampPos + Vector3.new(0.8, 2.9, 0), Color3.fromRGB(236, 200, 140), Enum.Material.SmoothPlastic)
		if i <= 2 then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 200, 130)
			light.Range = 12
			light.Brightness = 0.45
			light.Shadows = false
			light.Parent = lantern
		end
	end

	-- 상자 / 통 / 자루 / 돌 화덕 옆 장작 더미
	do
		local cratePos = around(14.5, math.rad(40))
		box("CampCrate", Vector3.new(2.4, 2.4, 2.4), cratePos + Vector3.new(0, 1.2, 0), wood, Enum.Material.Wood, 0.3)
		box("CampCrate", Vector3.new(2, 2, 2), cratePos + Vector3.new(2.8, 1, 0.4), darkWood, Enum.Material.Wood, -0.2)
		box("CampCrate", Vector3.new(1.8, 1.8, 1.8), cratePos + Vector3.new(0.4, 3.3, 0), darkWood, Enum.Material.Wood, 0.6)
		pole("CampBarrel", 2.6, 2.2, cratePos + Vector3.new(-2.8, 0, 0.6), Color3.fromRGB(122, 88, 58), Enum.Material.Wood)
		pole("CampBarrel", 2.6, 2.2, cratePos + Vector3.new(-1.4, 0, 3), Color3.fromRGB(110, 78, 52), Enum.Material.Wood)
		ball("CampSack", 2, cratePos + Vector3.new(3, 0.9, 2.8), Color3.fromRGB(196, 176, 134), Enum.Material.Fabric, 1.8)
		for k = 0, 2 do -- 장작 더미
			box("CampFirewood", Vector3.new(0.6, 0.6, 2.6), around(11.8, math.rad(85)) + Vector3.new(k * 0.7 - 0.7, 0.3, 0), Color3.fromRGB(100, 70, 44), Enum.Material.Wood, 1.57)
		end
	end

	-- 가장자리 덤불 / 꽃 / 모서리 나무
	for i = 0, 15 do
		if i % 4 ~= 1 then -- (입구 쪽 몇 군데는 비워 둔다)
			local angle = i / 16 * math.pi * 2 + 0.2
			ball("CampBush", 2.8 + (i % 3) * 0.5, around(17 + (i % 2) * 0.8, angle) + Vector3.new(0, 1, 0), Color3.fromRGB(80 + (i % 3) * 10, 124 + (i % 4) * 6, 78), Enum.Material.Grass, 2.2)
		end
	end
	local flowerColors = { Color3.fromRGB(230, 150, 160), Color3.fromRGB(240, 200, 110), Color3.fromRGB(200, 130, 180), Color3.fromRGB(236, 232, 220) }
	for i = 0, 7 do
		ball("CampFlower", 0.8, around(9 + (i % 3) * 1.8, i / 8 * math.pi * 2 + 0.9) + Vector3.new(0, 0.5, 0), flowerColors[i % 4 + 1], Enum.Material.SmoothPlastic)
	end
	for _, corner in ipairs({ Vector3.new(-16, 0, -16), Vector3.new(16, 0, -16), Vector3.new(-17, 0, 16) }) do
		pole("CampTrunk", 7, 1.6, gy + corner, Color3.fromRGB(96, 68, 44), Enum.Material.Wood)
		ball("CampLeaves", 8.5, gy + corner + Vector3.new(0, 8, 0), Color3.fromRGB(92, 136, 84), Enum.Material.Grass, 7)
	end

	-- 작은 나무 팻말 (오는 길인 동쪽을 향한다)
	do
		local signPos = around(17.5, math.rad(-12))
		pole("CampSignPost", 3.4, 0.5, signPos, darkWood, Enum.Material.Wood)
		local board = deco("CampSignBoard", Vector3.new(0.3, 2.4, 5.2), CFrame.new(signPos + Vector3.new(0, 3.6, 0)), Color3.fromRGB(150, 108, 70), Enum.Material.WoodPlanks)
		local face = Instance.new("SurfaceGui")
		face.Face = Enum.NormalId.Right
		face.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		face.PixelsPerStud = 40
		face.LightInfluence = 0
		face.Parent = board
		local faceText = Instance.new("TextLabel")
		faceText.Size = UDim2.new(1, 0, 1, 0)
		faceText.BackgroundTransparency = 1
		faceText.Font = Enum.Font.GothamBlack
		faceText.TextScaled = true
		faceText.TextColor3 = Color3.fromRGB(255, 244, 214)
		faceText.TextStrokeTransparency = 0.3
		faceText.Text = "💤 휴식 구역"
		faceText.Parent = face
	end

	-- 안내판
	local signGui = Instance.new("BillboardGui")
	signGui.Size = UDim2.new(0, 320, 0, 70)
	signGui.StudsOffset = Vector3.new(0, 16, 0)
	signGui.MaxDistance = 50
	signGui.Parent = ring
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.new(1, 0, 1, 0)
	signLabel.BackgroundTransparency = 1
	signLabel.Font = Enum.Font.GothamBlack
	signLabel.TextScaled = true
	signLabel.TextColor3 = Color3.fromRGB(190, 240, 255)
	signLabel.TextStrokeTransparency = 0
	signLabel.Text = "💤 휴식 구역"
	signLabel.Parent = signGui
end

return Dummy
