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

local SIZE, GAP = 74, 8
local TOP_Y = 252 -- HUD 카드(60 ~ 236) 바로 아래

-- 색은 진하지만 채도를 낮춰 눈이 편하게 (위쪽이 조금 밝은 그라데이션)
local BUTTONS = {
	{ Icon = "🎒", Text = "Gear",     Color = Color3.fromRGB(70, 110, 190), Tab = "Character:Gear" },
	{ Icon = "🔫", Text = "Weapon",   Color = Color3.fromRGB(190, 95, 70),  Tab = "Character:Weapon", Dot = "CanEnhance" },
	{ Icon = "📈", Text = "Growth",   Color = Color3.fromRGB(70, 150, 100), Tab = "Growth", Dot = "GrowthNew" },
	{ Icon = "📜", Text = "Quests",   Color = Color3.fromRGB(175, 130, 60), Tab = "Quest", Dot = "DotQuest" },
	{ Icon = "🐾", Text = "Pets",     Color = Color3.fromRGB(150, 90, 170), Signal = "OpenPet" },
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
	icon.Size = UDim2.new(1, 0, 0, 44)
	icon.Position = UDim2.new(0, 0, 0, 4)
	icon.Text = def.Icon
	icon.TextSize = 32
	icon.Font = Enum.Font.GothamBold
	icon.Parent = button

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 20)
	label.Position = UDim2.new(0, 0, 1, -23)
	label.Text = def.Text
	label.TextSize = 14
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

-- 무기 강화에 쓸 골드가 모이면 Weapon 버튼에 빨간 점 (골드는 자주 바뀌어서 0.5초마다 한 번 확인)
local function refreshEnhance()
	local level = player:GetAttribute("WeaponLevel") or 0
	local ready = false
	if player:GetAttribute("DataReady") then
		local ok, cost = pcall(Config.GetEnhanceCost, level)
		ready = ok and (player:GetAttribute("Gold") or 0) >= cost and level < Config.Weapon.MaxLevel
	end
	if player:GetAttribute("CanEnhance") ~= ready then player:SetAttribute("CanEnhance", ready) end
end

local function refreshDots()
	for def, dot in pairs(dots) do
		dot.Visible = def.Dot ~= nil and player:GetAttribute(def.Dot) == true
	end
end
for _, def in ipairs(BUTTONS) do
	if def.Dot then player:GetAttributeChangedSignal(def.Dot):Connect(refreshDots) end
end
refreshDots()

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
		pcall(refreshEnhance)
		sync()
		task.wait(0.5)
	end
end)
