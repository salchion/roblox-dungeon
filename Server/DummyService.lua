-- DummyService (ServerScriptService > Modules 안의 ModuleScript, 이름: DummyService)
-- 로비 허수아비 훈련장. 허수아비를 공격할 때마다 골드가 자동으로 들어온다 (줍기 없음).
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
	gui.Size = UDim2.new(0, 190, 0, 52)
	gui.StudsOffset = Vector3.new(0, 3.5 + 2.2 * s, 0)
	gui.MaxDistance = 55 -- 가까이 가야 이름 / 방어력이 보인다 (작은 화면에서 글자 겹침 방지)
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
	sub.Text = "💰 전투력이 높을수록 골드 UP"
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
		Color = Color3.fromRGB(255, 215, 90), Material = Enum.Material.Neon, CanCollide = false, Transparency = 0.75,
	}, folder)
	addGlow(ring, Color3.fromRGB(255, 215, 90), 30)

	-- 방치 구역 안내판: 훈련장 안에 서 있으면 자동으로 쏘며 골드가 쌓이고, 접속을 꺼도 쌓인다
	local signGui = Instance.new("BillboardGui")
	signGui.Size = UDim2.new(0, 300, 0, 64)
	signGui.StudsOffset = Vector3.new(0, 17, 0)
	signGui.MaxDistance = 120
	signGui.Parent = ring
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.new(1, 0, 1, 0)
	signLabel.BackgroundTransparency = 1
	signLabel.Font = Enum.Font.GothamBlack
	signLabel.TextScaled = true
	signLabel.TextColor3 = Color3.fromRGB(255, 225, 120)
	signLabel.TextStrokeTransparency = 0
	signLabel.Text = "💤 방치 구역\n서 있으면 자동 사격 · 접속을 꺼도 골드가 쌓여요"
	signLabel.Parent = signGui

	-- 허수아비 하나: 8번 모양(어깨 보호대 / 투구 / 뿔 / 가슴 갑옷 / 빛나는 눈)을 써서 크고 듬직하게. 이름은 Dummy1.
	buildDummy(8, Config.Dummy.List[1], start, 1, 1.7) -- 멀리서도 눈에 띄도록 1.7배 크기
end

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
	for model, data in pairs(dummies) do
		flash(data)
		local root = model.PrimaryPart
		if root and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			Effects.Burst(root.Position + Vector3.new(0, 2, 0), Color3.fromRGB(255, 225, 120), 6)
		end
		break
	end
end

local goldRemainder = {} -- [player] = 아직 지급하지 못한 소수점 골드

function Dummy.Shoot(player, origin, direction, shotDamage)
	if not folder or player:GetAttribute("Zone") ~= "Lobby" then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }

	local weaponType = Config.GetPlayerWeapon(player)
	local result = workspace:Raycast(origin, direction * weaponType.Range, params)
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

	-- 골드는 "탄 하나의 실제 기대 피해량"에 비례한다. 탄이 여러 발이든 연사가 빠르든 합치면 초당 피해량(DPS)에 비례해서,
	-- 산탄 / 연사 무기가 따로 더 벌지 않고 "정말 세지면 그만큼 더 번다". (소수점은 모아 두었다가 정수가 되면 지급)
	local owed = (goldRemainder[player] or 0) + Config.Dummy.GoldPerDamage * (shotDamage or 10) * data.Multiplier
	local gold = math.floor(owed)
	goldRemainder[player] = owed - gold
	if gold < 1 then
		Quest.Add(player, "DummyHits", 1)
		return result.Position
	end
	player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + gold)
	Quest.Add(player, "DummyHits", 1)
	Effects.FloatText(result.Position, string.format("+%d G", gold), Color3.fromRGB(255, 220, 90))
	return result.Position
end

return Dummy
