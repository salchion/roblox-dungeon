-- LevelStatClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: LevelStatClient)
-- 레벨 스탯 창 (T 키 또는 오른쪽의 "스탯" 버튼): 레벨 업마다 받는 포인트를 이동 속도 / 사정거리 / 투사체 / 스킬 쿨타임 / 전리품 흡수에 배분한다.
-- 언제든 무료로 빼고 다시 넣을 수 있다. 값은 서버가 정하는 Attribute(LvPts_<키>, LvPointsLeft)에서 읽는다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local LS = Config.LevelStats

local gui = Instance.new("ScreenGui")
gui.Name = "LevelStatGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 12
gui.Parent = player:WaitForChild("PlayerGui")

local function make(class, props, parent)
	local instance = Instance.new(class)
	for key, value in pairs(props) do instance[key] = value end
	instance.Parent = parent
	return instance
end

local function label(props, parent)
	props.BackgroundTransparency = 1
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextSize = props.TextSize or 14
	return make("TextLabel", props, parent)
end

local function button(props, parent, callback)
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextSize = props.TextSize or 16
	props.AutoButtonColor = true
	local b = make("TextButton", props, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
	b.Activated:Connect(callback)
	return b
end

-- 오른쪽의 "스탯" 버튼 (안 쓴 포인트가 있으면 개수 배지)
local pill = button({
	Size = UDim2.new(0, 96, 0, 40), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 40),
	BackgroundColor3 = Color3.fromRGB(34, 38, 60), Text = "✨ 스탯 (T)", TextSize = 13,
}, gui, function() end)
make("UIStroke", { Color = Color3.fromRGB(150, 160, 255), Thickness = 1.5 }, pill)
local badge = label({
	Size = UDim2.new(0, 24, 0, 24), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0, 6, 0, 0),
	BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(255, 80, 80), Text = "0", TextSize = 13, Visible = false,
}, pill)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, badge)

-- 창
local panel = make("Frame", {
	Size = UDim2.new(0, 460, 0, 420), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(26, 28, 42), BorderSizePixel = 0, Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, panel)
make("UIStroke", { Color = Color3.fromRGB(150, 160, 255), Thickness = 2 }, panel)
make("UISizeConstraint", { MaxSize = Vector2.new(460, 420) }, panel)

label({ Size = UDim2.new(1, -90, 0, 30), Position = UDim2.new(0, 16, 0, 10), Text = "✨ 레벨 스탯", TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left }, panel)
local pointsLabel = label({ Size = UDim2.new(1, -32, 0, 22), Position = UDim2.new(0, 16, 0, 40), Text = "", TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 225, 110) }, panel)
label({ Size = UDim2.new(1, -32, 0, 18), Position = UDim2.new(0, 16, 0, 62), Text = "공격력 / 체력이 아니라 플레이 스타일을 고르는 스탯이에요. 언제든 무료로 다시 배분할 수 있어요!", TextSize = 11, TextColor3 = Color3.fromRGB(170, 175, 205), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true }, panel)
button({ Size = UDim2.new(0, 60, 0, 28), Position = UDim2.new(1, -72, 0, 10), BackgroundColor3 = Color3.fromRGB(70, 70, 90), Text = "닫기", TextSize = 13 }, panel, function() panel.Visible = false end)

local rows = {}
for index, key in ipairs(LS.Order) do
	local def = LS[key]
	local y = 92 + (index - 1) * 56
	local row = make("Frame", { Size = UDim2.new(1, -24, 0, 50), Position = UDim2.new(0, 12, 0, y), BackgroundColor3 = Color3.fromRGB(36, 39, 58), BorderSizePixel = 0 }, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, row)
	label({ Size = UDim2.new(0, 34, 1, 0), Position = UDim2.new(0, 6, 0, 0), Text = def.Icon, TextSize = 24 }, row)
	label({ Size = UDim2.new(0, 160, 0, 22), Position = UDim2.new(0, 44, 0, 4), Text = def.Name, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left }, row)
	local valueLabel = label({ Size = UDim2.new(0, 190, 0, 18), Position = UDim2.new(0, 44, 0, 27), Text = "", TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(150, 235, 190) }, row)
	local countLabel = label({ Size = UDim2.new(0, 36, 1, 0), Position = UDim2.new(1, -168, 0, 0), Text = "0", TextSize = 18, TextColor3 = Color3.fromRGB(255, 225, 110) }, row)
	button({ Size = UDim2.new(0, 30, 0, 32), Position = UDim2.new(1, -132, 0.5, -16), BackgroundColor3 = Color3.fromRGB(110, 60, 70), Text = "−" }, row, function()
		Remotes.LevelStat:FireServer("Sub", key, 1)
	end)
	button({ Size = UDim2.new(0, 30, 0, 32), Position = UDim2.new(1, -98, 0.5, -16), BackgroundColor3 = Color3.fromRGB(60, 120, 80), Text = "+" }, row, function()
		Remotes.LevelStat:FireServer("Add", key, 1)
	end)
	button({ Size = UDim2.new(0, 56, 0, 32), Position = UDim2.new(1, -64, 0.5, -16), BackgroundColor3 = Color3.fromRGB(70, 90, 170), Text = "몰빵", TextSize = 13 }, row, function()
		Remotes.LevelStat:FireServer("Add", key, 99)
	end)
	rows[key] = { Value = valueLabel, Count = countLabel }
end

button({ Size = UDim2.new(0, 150, 0, 32), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -42), BackgroundColor3 = Color3.fromRGB(120, 70, 70), Text = "전부 초기화 (무료)", TextSize = 13 }, panel, function()
	Remotes.LevelStat:FireServer("Reset")
end)

local function refresh()
	local left = player:GetAttribute("LvPointsLeft") or 0
	local total = Config.GetLevelStatPoints(player:GetAttribute("Level") or 1)
	pointsLabel.Text = string.format("남은 포인트 %d  /  전체 %d  (레벨 %d)", left, total, player:GetAttribute("Level") or 1)
	for _, key in ipairs(LS.Order) do
		local points = player:GetAttribute("LvPts_" .. key) or 0
		rows[key].Count.Text = tostring(points)
		rows[key].Value.Text = points > 0 and Config.LevelStatText(key, points) or LS[key].Desc
	end
	badge.Visible = left > 0
	badge.Text = tostring(math.min(99, left))
	pill.Visible = not player:GetAttribute("TutorialActive")
end

for _, name in ipairs({ "LvPointsLeft", "Level", "TutorialActive" }) do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end
for _, key in ipairs(LS.Order) do
	player:GetAttributeChangedSignal("LvPts_" .. key):Connect(refresh)
end
refresh()

pill.Activated:Connect(function() panel.Visible = not panel.Visible end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.T then panel.Visible = not panel.Visible end
end)
