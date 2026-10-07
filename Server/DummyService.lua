-- DummyService (ServerScriptService > Modules 안의 ModuleScript, 이름: DummyService)
-- 로비 허수아비 훈련장. 허수아비를 공격할 때마다 골드가 자동으로 들어온다 (줍기 없음).
-- 1번(x1)부터 10번(x30)까지 한 줄로 나열되고, 배수가 높을수록 크고 화려하고 강해 보인다.
-- 허수아비마다 배율(Multiplier)과 필요 무기 레벨(RequiredLevel)이 다르다 -> Config.Dummy.List

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

local function buildDummy(index, info, position)
	local model = Instance.new("Model")
	model.Name = "Dummy" .. index

	local style = STYLES[index] or STYLES[#STYLES]
	local s = 1 + 0.12 * (index - 1)             -- 번호가 오를수록 커짐 (1.0 ~ 2.1배)
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

	-- 이름표: 배율 + 필요 무기 레벨
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 210, 0, 62)
	gui.StudsOffset = Vector3.new(0, 3.5 + 2.2 * s, 0)
	gui.MaxDistance = 100
	gui.Parent = head

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.58, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextStrokeTransparency = 0
	title.TextColor3 = style.Color:Lerp(Color3.new(1, 1, 1), 0.35)
	title.Text = string.format("x%s 허수아비", formatMultiplier(info.Multiplier))
	title.Parent = gui

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, 0, 0.42, 0)
	sub.Position = UDim2.new(0, 0, 0.58, 0)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextScaled = true
	sub.TextStrokeTransparency = 0.3
	sub.TextColor3 = Color3.fromRGB(230, 230, 240)
	sub.Text = info.RequiredLevel > 0 and string.format("무기 +%d 이상", info.RequiredLevel) or "제한 없음"
	sub.Parent = gui

	model.Parent = folder

	local baseColors = {}
	for _, part in ipairs(flashParts) do
		baseColors[part] = part.Color
	end
	dummies[model] = {
		Multiplier = info.Multiplier,
		RequiredLevel = info.RequiredLevel,
		FlashParts = flashParts,
		BaseColors = baseColors,
		Flashing = false,
	}
end

-- start: 1번 허수아비 위치. +Z 방향으로 Config.Dummy.Spacing 간격으로 한 줄로 놓는다.
function Dummy.Build(start)
	folder = Instance.new("Folder")
	folder.Name = "Dummies"
	folder.Parent = workspace

	local count = #Config.Dummy.List
	local spacing = Config.Dummy.Spacing
	local length = spacing * (count - 1) + 24

	newPart({
		Name = "TrainingGround",
		Size = Vector3.new(30, 0.3, length),
		Position = start + Vector3.new(0, 0.15, spacing * (count - 1) / 2),
		Color = Color3.fromRGB(125, 100, 70),
		Material = Enum.Material.Ground,
		CanCollide = false,
	}, folder)

	-- 바닥에 번호/배수가 보이는 화살표 띠: 아래로 갈수록 배수 UP
	newPart({
		Name = "ProgressStrip",
		Size = Vector3.new(2, 0.35, length - 8),
		Position = start + Vector3.new(14, 0.2, spacing * (count - 1) / 2),
		Color = Color3.fromRGB(255, 215, 90),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, folder)

	for index, info in ipairs(Config.Dummy.List) do
		buildDummy(index, info, start + Vector3.new(0, 0, (index - 1) * spacing))
	end
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
function Dummy.Shoot(player, origin, direction)
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

	local weaponLevel = player:GetAttribute("WeaponLevel") or 0
	if weaponLevel < data.RequiredLevel then
		Effects.FloatText(result.Position, string.format("🔒 무기 +%d 필요", data.RequiredLevel), Color3.fromRGB(190, 190, 200))
		return result.Position
	end

	-- 무기 종류별 한 발 위력(DamageMult)에 비례: 샷건은 6발이 나가므로 한 발당 0.5, 저격총은 4
	local gold = math.max(1, math.floor(Config.Dummy.GoldPerHit * data.Multiplier * weaponType.DamageMult + 0.5))
	player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + gold)
	Quest.Add(player, "DummyHits", 1)
	Effects.FloatText(result.Position, string.format("+%d G", gold), Color3.fromRGB(255, 220, 90))
	return result.Position
end

return Dummy
