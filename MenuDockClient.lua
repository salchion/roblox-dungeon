-- MenuDockClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: MenuDockClient)
-- 왼쪽 아래 HUD 카드 밑에 모바일 게임처럼 큰 아이콘 버튼 줄을 만든다 (아이콘 + 굵은 글씨 + 진한 테두리).
-- 누를 수 있는 것이 한눈에 보이게, 할 일이 생긴 버튼에는 빨간 점이 뜨고 살짝 뛴다.
-- 실제 창은 PlayerClient / ShopClient / PetClient 가 연다: 여기서는 신호(Attribute)만 보낸다.
--   OpenMenuTab = "Character:Gear" 처럼 "탭:하위" / OpenHelp = 설정 창 / OpenShop / OpenPet
-- 데스크톱(큰 화면)에서만 보이고, 폰(작은 화면)은 기존 버튼 배치(MobileLayoutClient)를 그대로 쓴다.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SIZE, GAP = 66, 6 -- (미션 카드 / 던전 상태창과 겹치지 않게 줄였다: 5줄 높이 = 5 * 72 - 6)
local TOP_Y = 252 -- HUD 카드(60 ~ 236) 바로 아래

-- 색은 진하지만 채도를 낮춰 눈이 편하게 (위쪽이 조금 밝은 그라데이션)
local function attr(name) return player:GetAttribute(name) end
local function gold() return attr("Gold") or 0 end

-- 빨간 점 조건 (전부 내 Attribute 로만 계산: 서버 호출 없음). 할 일이 생기면 true
-- 골드로 하는 일(무기 강화 / 스킬 / 세트 / 펫)은 재화가 하나라서, 하나를 쓰면 다른 점이 한꺼번에 사라지면 어색하다.
-- 그래서 "우선순위대로 골드를 차례로 나눠 보고, 모두 함께 살 수 있는 것에만" 점을 켠다: 무기 -> 세트 -> 스킬 -> 펫.
-- (하나를 사면 그 점만 꺼지고, 나머지는 남은 골드로도 살 수 있을 때만 남는다)
local function weaponCost()
	local level = attr("WeaponLevel") or 0
	if attr("DataReady") ~= true or level >= Config.Weapon.MaxLevel then return nil end
	local ok, cost = pcall(Config.GetEnhanceCost, level)
	return ok and cost or nil
end
local function skillCost()
	local best
	for _, key in ipairs(Config.Skills.UpgradeOrder) do
		local level = math.max(1, attr("SkillLv_" .. key) or 1)
		if level < Config.SkillUpgrade.MaxLevel then
			local cost = Config.GetSkillUpgradeCost(level)
			if not best or cost < best then best = cost end
		end
	end
	return best
end
local function setsCost() -- 군주를 쓰러뜨려 열린 세트 효과 중 가장 싼 강화
	local best
	for zone = 1, Config.Field.ZoneCount do
		if attr("AugOpenZ_" .. zone) == true then
			local level = attr("AugLvZ_" .. zone) or 0
			if level < 3 then
				local cost = Config.Sets.AugCost(zone, level + 1)
				if not best or cost < best then best = cost end
			end
		end
	end
	return best
end
local function petCost()
	if attr("DataReady") ~= true then return nil end
	local level = attr("PetLevel") or 0
	if level <= 0 then return Config.Pet.UnlockCost end
	return level < Config.Pet.MaxLevel and Config.GetPetLevelCost(level) or nil
end
local GOLD_ORDER = { { "Weapon", weaponCost }, { "Sets", setsCost }, { "Growth", skillCost }, { "Pets", petCost } }
local goldDots = {}
local function computeGoldDots()
	local budget = gold()
	for _, entry in ipairs(GOLD_ORDER) do
		local cost = entry[2]()
		if cost and cost <= budget then
			goldDots[entry[1]] = true
			budget -= cost
		else
			goldDots[entry[1]] = false
		end
	end
end
local function dotGear() return attr("DotGear") == true end
local function dotQuest() return attr("DotQuest") == true end
local function dotWeapon() return goldDots.Weapon == true end
local function dotGrowth() return attr("GrowthNew") == true or goldDots.Growth == true end
local function dotPet() return goldDots.Pets == true end
local function dotSets() return goldDots.Sets == true end

local BUTTONS = {
	{ Icon = "🎒", Text = "Gear",     Color = Color3.fromRGB(70, 110, 190), Tab = "Character:Gear", Dot = dotGear },
	{ Icon = "🔫", Text = "Weapon",   Color = Color3.fromRGB(190, 95, 70),  Tab = "Character:Weapon", Dot = dotWeapon },
	{ Icon = "📈", Text = "Growth",   Color = Color3.fromRGB(70, 150, 100), Tab = "Growth", Dot = dotGrowth },
	{ Icon = "📜", Text = "Quests",   Color = Color3.fromRGB(175, 130, 60), Tab = "Quest", Dot = dotQuest },
	{ Icon = "🐾", Text = "Pets",     Color = Color3.fromRGB(150, 90, 170), Signal = "OpenPet", Dot = dotPet },
	{ Icon = "🌟", Text = "Sets",     Color = Color3.fromRGB(60, 130, 160), Signal = "OpenAug", Dot = dotSets },
	{ Icon = "📖", Text = "Codex",    Color = Color3.fromRGB(110, 100, 170), Signal = "OpenCodex" },
	{ Icon = "🎁", Text = "Shop",     Color = Color3.fromRGB(185, 75, 105), Signal = "OpenShop" },
	{ Icon = "🏆", Text = "Ranking",  Color = Color3.fromRGB(170, 150, 60), Tab = "Rank" },
	{ Icon = "⚙", Text = "Settings", Color = Color3.fromRGB(95, 105, 130), Signal = "OpenHelp" },
}

local gui = Instance.new("ScreenGui")
gui.Name = "MenuDockGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2
gui.Enabled = false
gui.Parent = playerGui

local dots = {} -- [버튼 정의] = 빨간 점

local function build(index, def)
	local column = (index - 1) % 2
	local row = math.floor((index - 1) / 2)
	local button = Instance.new("TextButton")
	button.Name = "Dock" .. def.Text
	button.Size = UDim2.new(0, SIZE, 0, SIZE)
	button.Position = UDim2.new(0, 16 + column * (SIZE + GAP), 0, TOP_Y + row * (SIZE + GAP))
	button.BackgroundColor3 = def.Color
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = false
	button.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 22, 36)
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 190, 200))
	gradient.Rotation = 90
	gradient.Parent = button
	local scale = Instance.new("UIScale")
	scale.Parent = button

	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(1, 0, 0, 40)
	icon.Position = UDim2.new(0, 0, 0, 4)
	icon.Text = def.Icon
	icon.TextSize = 30
	icon.Font = Enum.Font.GothamBold
	icon.Parent = button

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 20)
	label.Position = UDim2.new(0, 0, 1, -21)
	label.Text = def.Text
	label.TextSize = 13
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(20, 22, 36)
	label.TextStrokeTransparency = 0.1
	label.Parent = button

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.new(0, 20, 0, 20)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.new(1, -4, 0, 4)
	dot.BackgroundColor3 = Color3.fromRGB(225, 60, 60)
	dot.BorderSizePixel = 0
	dot.Visible = false
	dot.ZIndex = 5
	dot.Parent = button
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot
	local dotStroke = Instance.new("UIStroke")
	dotStroke.Color = Color3.fromRGB(255, 255, 255)
	dotStroke.Thickness = 2
	dotStroke.Parent = dot
	local dotMark = Instance.new("TextLabel")
	dotMark.BackgroundTransparency = 1
	dotMark.Size = UDim2.new(1, 0, 1, 0)
	dotMark.Text = "!"
	dotMark.TextSize = 14
	dotMark.Font = Enum.Font.GothamBlack
	dotMark.TextColor3 = Color3.fromRGB(255, 255, 255)
	dotMark.ZIndex = 6
	dotMark.Parent = dot
	local dotScale = Instance.new("UIScale")
	dotScale.Parent = dot
	TweenService:Create(dotScale, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.25 }):Play()
	dots[def] = dot

	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.08 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	button.Activated:Connect(function()
		scale.Scale = 0.92
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		if def.Tab then
			player:SetAttribute("OpenMenuTab", def.Tab)
		else
			player:SetAttribute(def.Signal, os.clock())
		end
	end)
end

for index, def in ipairs(BUTTONS) do build(index, def) end

-- 할 일이 생겼는지 0.5초마다 확인해서 빨간 점을 켜고 끈다 (골드는 자주 바뀌어서 이벤트 대신 주기 확인)
local function refreshDots()
	computeGoldDots()
	for def, dot in pairs(dots) do
		local ok, on = pcall(function() return def.Dot ~= nil and def.Dot() end)
		dot.Visible = ok and on == true
	end
end

-- 큰 화면에서만 보이고, 그때는 기존 작은 Menu / Settings 버튼을 숨긴다 (단축키 B / H 는 그대로)
local function sync()
	local compact = playerGui:GetAttribute("UiCompact") == true
	local hud = playerGui:FindFirstChild("HUD")
	local hudOn = hud ~= nil and hud.Enabled
	local show = hudOn and not compact
	gui.Enabled = show
	if hud then
		for _, name in ipairs({ "MenuButton", "HelpButton" }) do
			local old = hud:FindFirstChild(name)
			if old then old.Visible = compact end
		end
	end
end
task.spawn(function()
	while true do
		pcall(refreshDots)
		sync()
		task.wait(0.5)
	end
end)
