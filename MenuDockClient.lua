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

local SIZE, GAP = 58, 5 -- (미션 카드 / 던전 상태창과 겹치지 않게 줄였다: 6줄 높이 = 6 * 63 - 5 = 373, 손을 올리면 1.1배)
local PHONE_PC = Config.PhonePcStyle == true and game:GetService("UserInputService").TouchEnabled and not game:GetService("UserInputService").MouseEnabled -- 폰: 메뉴 버튼 줄은 ☰ 하나로 접어 둔다
local TOP_Y = 226 -- HUD 카드(60 ~ 210, 전투력 / 경험치 줄을 아래로 옮겨 줄였다) 바로 아래

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
	if attr("Zone") ~= "Lobby" then return nil end -- 무기 강화는 마을에서만 된다: 필드 / 던전에서는 눌러도 할 일이 없으니 점을 켜지 않는다
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
	if attr("TutorialActive") == true then -- 튜토리얼 중에는 골드 빨간 점을 켜지 않는다 (막 시작했는데 "강화하세요" 점이 먼저 뜨면 어색하다)
		for _, entry in ipairs(GOLD_ORDER) do goldDots[entry[1]] = false end
		return
	end
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
local function dotStats() return (attr("LvPointsLeft") or 0) > 0 and attr("TutorialActive") ~= true end -- 안 쓴 스탯 포인트가 있으면 (골드와 상관없다)

local closeOtherWindows
local BUTTONS = {
	{ Icon = "🎒", Text = "Gear",     Color = Color3.fromRGB(70, 110, 190), Tab = "Character:Gear", Window = "HUD", Dot = dotGear },
	{ Icon = "🔫", Text = "Weapon",   Color = Color3.fromRGB(190, 95, 70),  Tab = "Character:Weapon", Window = "HUD", LobbySignal = "OpenEnhance", Dot = dotWeapon },
	{ Icon = "📈", Text = "Growth",   Color = Color3.fromRGB(70, 150, 100), Tab = "Growth", Window = "HUD", Dot = dotGrowth },
	{ Icon = "✨", Text = "Stats",    Color = Color3.fromRGB(120, 95, 190), Signal = "OpenStats", Window = "LevelStatGui", Dot = dotStats },
	{ Icon = "📜", Text = "Quests",   Color = Color3.fromRGB(175, 130, 60), Tab = "Quest", Window = "HUD", Dot = dotQuest },
	{ Icon = "🐾", Text = "Pets",     Color = Color3.fromRGB(150, 90, 170), Signal = "OpenPet", Window = "PetGui", Dot = dotPet },
	{ Icon = "🌟", Text = "Sets",     Color = Color3.fromRGB(60, 130, 160), Signal = "OpenAug", Window = "AugGui", Dot = dotSets },
	{ Icon = "📖", Text = "Codex",    Color = Color3.fromRGB(110, 100, 170), Signal = "OpenCodex", Window = "CodexGui" },
	{ Icon = "🎁", Text = "Shop",     Color = Color3.fromRGB(185, 75, 105), Signal = "OpenShop", Window = "ShopGui" },
	{ Icon = "🏆", Text = "Ranking",  Color = Color3.fromRGB(170, 150, 60), Tab = "Rank", Window = "HUD" },
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

local entries = {} -- { Button, Icon, Label } (위치 / 글자 크기는 layout() 이 화면에 맞게 정한다)
local menuOpen = false -- 폰: 접힌 메뉴(☰)가 열려 있나

-- 큰 창은 한 번에 하나: 어떤 버튼을 누르면 지금 열려 있는 다른 큰 창(펫 / 스탯 / 세트 / 도감 / 상점 / 메뉴)을 먼저 닫는다 (창끼리 겹쳐 보이지 않게). def.Window = 이 버튼이 여는 창이 들어 있는 화면 이름 (그 창은 그대로 둔다: 같은 버튼을 한 번 더 누르면 닫히는 토글이 유지된다)
local WINDOW_GUIS = { "PetGui", "ShopGui", "LevelStatGui", "CodexGui", "AugGui", "OddsGui" }
function closeOtherWindows(keep)
	for _, name in ipairs(WINDOW_GUIS) do
		local g = playerGui:FindFirstChild(name)
		if g and name ~= keep then
			for _, child in ipairs(g:GetChildren()) do
				if child:IsA("Frame") and child.Visible and child.AbsoluteSize.Y >= 300 then child.Visible = false end
			end
		end
	end
	if keep ~= "HUD" then
		local hud = playerGui:FindFirstChild("HUD")
		local menu = hud and hud:FindFirstChild("MenuPanel")
		if menu and menu.Visible then menu.Visible = false end
	end
end

local function build(index, def)
	local button = Instance.new("TextButton")
	button.Name = "Dock" .. def.Text
	button.Size = UDim2.new(0, SIZE, 0, SIZE)
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
	icon.Size = UDim2.new(1, 0, 0.6, 0)
	icon.Position = UDim2.new(0, 0, 0.03, 0)
	icon.Text = def.Icon
	icon.TextSize = 30
	icon.Font = Enum.Font.GothamBold
	icon.Parent = button

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0.3, 0)
	label.Position = UDim2.new(0, 0, 0.67, 0)
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
	entries[index] = { Button = button, Icon = icon, Label = label }

	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.08 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	button.Activated:Connect(function()
		closeOtherWindows(def.Window)
		scale.Scale = 0.92
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		menuOpen = false -- (폰: 고르면 메뉴가 접힌다)
		if def.LobbySignal and player:GetAttribute("Zone") == "Lobby" then
			player:SetAttribute(def.LobbySignal, os.clock()) -- 마을에서는 무기 버튼이 곧바로 강화 창을 연다 (메뉴의 무기 탭은 고르기만 되고 강화는 못 한다)
		elseif def.Tab then
			player:SetAttribute("OpenMenuTab", def.Tab .. "|" .. tostring(os.clock())) -- (뒤에 시각을 붙여 매번 값이 달라지게: 같은 값을 다시 넣으면 변화 신호가 안 와서 "껐다 바로 다시 켜기"가 안 됐다)
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

-- 폰(작은 화면)용: 왼쪽 위 카드 아래에 "☰ Menu" 버튼 하나만 두고, 누르면 작은 아이콘 5 x 2 격자가 펼쳐진다 (화면을 가리지 않게). 빨간 점이 하나라도 있으면 ☰ 버튼에도 점이 뜬다.
local toggle = Instance.new("TextButton")
toggle.Name = "DockToggle"
toggle.Size = UDim2.new(0, 84, 0, 34)
toggle.BackgroundColor3 = Color3.fromRGB(120, 86, 200)
toggle.BorderSizePixel = 0
toggle.AutoButtonColor = true
toggle.Text = "☰ Menu"
toggle.TextSize = 14
toggle.Font = Enum.Font.GothamBlack
toggle.TextColor3 = Color3.new(1, 1, 1)
toggle.TextStrokeColor3 = Color3.fromRGB(20, 22, 36)
toggle.TextStrokeTransparency = 0.2
toggle.Visible = false
toggle.Parent = gui
do
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = toggle
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 22, 36)
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = toggle
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 190, 200))
	gradient.Rotation = 90
	gradient.Parent = toggle
end
local toggleDot = Instance.new("Frame")
toggleDot.Size = UDim2.new(0, 18, 0, 18)
toggleDot.AnchorPoint = Vector2.new(0.5, 0.5)
toggleDot.Position = UDim2.new(1, -2, 0, 2)
toggleDot.BackgroundColor3 = Color3.fromRGB(225, 60, 60)
toggleDot.BorderSizePixel = 0
toggleDot.Visible = false
toggleDot.ZIndex = 5
toggleDot.Parent = toggle
do
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = toggleDot
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 2
	stroke.Parent = toggleDot
	local mark = Instance.new("TextLabel")
	mark.BackgroundTransparency = 1
	mark.Size = UDim2.new(1, 0, 1, 0)
	mark.Text = "!"
	mark.TextSize = 12
	mark.Font = Enum.Font.GothamBlack
	mark.TextColor3 = Color3.new(1, 1, 1)
	mark.ZIndex = 6
	mark.Parent = toggleDot
end
toggle.Activated:Connect(function() menuOpen = not menuOpen end)

-- 화면에 맞게 버튼 자리 / 크기를 정한다 (0.5초마다). 큰 화면: 왼쪽 카드 아래 2열 5줄 / 폰: ☰ 아래에 5열 2줄 (펼쳤을 때만)
local function layout(compact, hud)
	local size, gap, columns, x, y, iconSize, labelSize
	if compact then
		local old = hud and hud:FindFirstChild("MenuButton")
		local baseY = old and old.Position.Y.Offset or 190 -- MobileLayoutClient 가 정한 "메뉴 / 설정 버튼 줄" 높이를 그대로 쓴다
		if PHONE_PC then baseY = TOP_Y - 4 end -- 폰(PC 배치): 카드 바로 아래에 ☰ 버튼 (세로로 긴 버튼 줄이 왼쪽 조이스틱 자리를 가리지 않게)
		toggle.Position = UDim2.new(0, PHONE_PC and 16 or 12, 0, baseY)
		size, gap, columns, x, y, iconSize, labelSize = 50, 6, 5, PHONE_PC and 16 or 12, baseY + 42, 22, 10
	else
		size, gap, columns, x, y, iconSize, labelSize = SIZE, GAP, 2, 16, TOP_Y, 30, 13
	end
	toggle.Visible = compact
	local anyDot = false
	for index, entry in ipairs(entries) do
		local column = (index - 1) % columns
		local row = math.floor((index - 1) / columns)
		entry.Button.Size = UDim2.new(0, size, 0, size)
		entry.Button.Position = UDim2.new(0, x + column * (size + gap), 0, y + row * (size + gap))
		entry.Button.Visible = (not compact) or menuOpen
		entry.Icon.TextSize = iconSize
		entry.Label.TextSize = labelSize
		local dot = dots[BUTTONS[index]]
		if dot and dot.Visible then anyDot = true end
	end
	toggleDot.Visible = compact and anyDot and not menuOpen
end

-- 기존 작은 Menu / Settings 버튼은 숨긴다 (단축키 B / H 는 그대로, 설정은 Settings 버튼으로)
local function sync()
	local compact = playerGui:GetAttribute("UiCompact") == true or PHONE_PC
	local hud = playerGui:FindFirstChild("HUD")
	local hudOn = hud ~= nil and hud.Enabled
	gui.Enabled = hudOn
	if not hudOn then return end
	if not compact then menuOpen = false end
	for _, name in ipairs({ "MenuButton", "HelpButton" }) do
		local old = hud:FindFirstChild(name)
		if old then old.Visible = false end
	end
	layout(compact, hud)
end
task.spawn(function()
	while true do
		pcall(refreshDots)
		pcall(sync)
		task.wait(0.5)
	end
end)
