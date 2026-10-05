-- DummyService (ServerScriptService > Modules 안의 ModuleScript, 이름: DummyService)
-- 로비 허수아비 훈련장. 허수아비를 공격할 때마다 골드가 자동으로 들어온다 (줍기 없음).
-- 허수아비마다 배율(Multiplier)과 필요 무기 레벨(RequiredLevel)이 다르다 -> Config.Dummy.List

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Effects = require(script.Parent:WaitForChild("Effects"))

local Dummy = {}

local dummies = {}   -- [Model] = { Multiplier, RequiredLevel, Body, BaseColor, Flashing }
local folder

local STRAW = Color3.fromRGB(205, 175, 110)
local HOT = Color3.fromRGB(255, 90, 60)

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

local function buildDummy(index, info, position)
	local model = Instance.new("Model")
	model.Name = "Dummy" .. index

	local tint = STRAW:Lerp(HOT, math.clamp((index - 1) / (#Config.Dummy.List - 1), 0, 1))
	local wood = Color3.fromRGB(95, 65, 40)

	newPart({ Name = "Base", Size = Vector3.new(3.5, 0.5, 3.5), Position = position + Vector3.new(0, 0.25, 0), Color = Color3.fromRGB(80, 75, 70), Material = Enum.Material.Cobblestone }, model)
	newPart({ Name = "Post", Size = Vector3.new(0.8, 7, 0.8), Position = position + Vector3.new(0, 3.5, 0), Color = wood, Material = Enum.Material.Wood }, model)
	newPart({ Name = "Arms", Size = Vector3.new(6, 0.7, 0.7), Position = position + Vector3.new(0, 5.6, 0), Color = wood, Material = Enum.Material.Wood }, model)
	local body = newPart({ Name = "Body", Size = Vector3.new(2.8, 3.4, 1.8), Position = position + Vector3.new(0, 4.6, 0), Color = tint, Material = Enum.Material.Fabric }, model)
	local head = newPart({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(2.2, 2.2, 2.2), Position = position + Vector3.new(0, 7.2, 0), Color = tint, Material = Enum.Material.Fabric }, model)
	model.PrimaryPart = body

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 190, 0, 56)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.MaxDistance = 90
	gui.Parent = head

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.55, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextStrokeTransparency = 0
	title.TextColor3 = tint:Lerp(Color3.new(1, 1, 1), 0.3)
	title.Text = string.format("x%s 허수아비", formatMultiplier(info.Multiplier))
	title.Parent = gui

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, 0, 0.45, 0)
	sub.Position = UDim2.new(0, 0, 0.55, 0)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextScaled = true
	sub.TextStrokeTransparency = 0.3
	sub.TextColor3 = Color3.fromRGB(230, 230, 240)
	sub.Text = info.RequiredLevel > 0 and string.format("무기 +%d 이상", info.RequiredLevel) or "제한 없음"
	sub.Parent = gui

	model.Parent = folder
	dummies[model] = {
		Multiplier = info.Multiplier,
		RequiredLevel = info.RequiredLevel,
		Body = body,
		Head = head,
		BaseColor = tint,
		Flashing = false,
	}
end

-- center: 훈련장 중앙 위치. 5열 x 2행으로 허수아비 10개를 배치
function Dummy.Build(center)
	folder = Instance.new("Folder")
	folder.Name = "Dummies"
	folder.Parent = workspace

	local ground = newPart({
		Name = "TrainingGround",
		Size = Vector3.new(50, 0.3, 90),
		Position = center + Vector3.new(0, 0.15, 0),
		Color = Color3.fromRGB(125, 100, 70),
		Material = Enum.Material.Ground,
		CanCollide = false,
	}, workspace)
	ground.Parent = folder

	local signAnchor = newPart({
		Name = "SignAnchor",
		Size = Vector3.new(1, 1, 1),
		Position = center + Vector3.new(0, 14, -48),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	}, folder)
	local signGui = Instance.new("BillboardGui")
	signGui.Size = UDim2.new(0, 380, 0, 80)
	signGui.MaxDistance = 200
	signGui.Parent = signAnchor
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.new(1, 0, 1, 0)
	signLabel.BackgroundTransparency = 1
	signLabel.Font = Enum.Font.GothamBlack
	signLabel.TextScaled = true
	signLabel.TextStrokeTransparency = 0
	signLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
	signLabel.Text = "🎯 허수아비 훈련장\n때릴 때마다 골드 자동 획득!"
	signLabel.Parent = signGui

	for index, info in ipairs(Config.Dummy.List) do
		local column = (index - 1) % 5
		local row = (index - 1) // 5
		local position = center + Vector3.new(row == 0 and 12 or -12, 0, -32 + column * 16)
		buildDummy(index, info, position)
	end
end

local function flash(data)
	if data.Flashing then return end
	data.Flashing = true
	data.Body.Color = Color3.new(1, 1, 1)
	data.Head.Color = Color3.new(1, 1, 1)
	task.delay(0.08, function()
		data.Body.Color = data.BaseColor
		data.Head.Color = data.BaseColor
		data.Flashing = false
	end)
end

-- 로비에서 쏜 탄이 허수아비에 맞았는지 판정하고 골드를 지급. 반환: 탄이 끝나는 지점 (아무것도 안 맞으면 nil)
function Dummy.Shoot(player, origin, direction)
	if not folder or player:GetAttribute("Zone") ~= "Lobby" then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }

	local result = workspace:Raycast(origin, direction * Config.Player.AttackRange, params)
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

	local gold = math.max(1, math.floor(Config.Dummy.GoldPerHit * data.Multiplier + 0.5))
	player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + gold)
	Effects.FloatText(result.Position, string.format("+%d G", gold), Color3.fromRGB(255, 220, 90))
	return result.Position
end

return Dummy
