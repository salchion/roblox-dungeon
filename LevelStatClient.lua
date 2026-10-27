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
gui.IgnoreGuiInset = true
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
-- 왼쪽 위 상태 카드 아래, 메뉴 / 설정 버튼 옆에 둔다. 안 쓴 포인트가 있으면 반짝이며 숫자 배지가 뜬다.
local pill = button({
	Size = UDim2.new(0, 78, 0, 32), Position = UDim2.new(0, 180, 0, 244),
	BackgroundColor3 = Color3.fromRGB(34, 38, 60), Text = "✨ Stats (T)", TextSize = 10,
}, gui, function() end)
local pillStroke = make("UIStroke", { Color = Color3.fromRGB(150, 160, 255), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pill)
local badge = label({
	Size = UDim2.new(0, 24, 0, 24), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 2),
	BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(255, 80, 80), Text = "0", TextSize = 11, Visible = false, ZIndex = 5,
}, pill)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, badge)
local pulse = game:GetService("TweenService"):Create(pillStroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 4, Color = Color3.fromRGB(255, 225, 110) })

-- 창
local panel = make("Frame", {
	Size = UDim2.new(0, 460, 0, 452), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(26, 28, 42), BorderSizePixel = 0, Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, panel)
make("UIStroke", { Color = Color3.fromRGB(150, 160, 255), Thickness = 2, Transparency = 0.25 }, panel)
make("UISizeConstraint", { MaxSize = Vector2.new(460, 452) }, panel)

label({ Size = UDim2.new(1, -200, 0, 30), Position = UDim2.new(0, 16, 0, 10), Text = "✨ Level Stats", TextSize = 20, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left }, panel)
local pointsLabel = label({ Size = UDim2.new(1, -32, 0, 22), Position = UDim2.new(0, 16, 0, 40), Text = "", TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 225, 110) }, panel)
label({ Size = UDim2.new(1, -32, 0, 18), Position = UDim2.new(0, 16, 0, 62), Text = "These stats shape your play style, not your attack or HP. You can respec for free anytime!", TextSize = 10, TextColor3 = Color3.fromRGB(170, 175, 205), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true }, panel)
button({ Size = UDim2.new(0, 72, 0, 30), Position = UDim2.new(1, -84, 0, 12), BackgroundColor3 = Color3.fromRGB(54, 58, 82), Text = "Close", TextSize = 12 }, panel, function() panel.Visible = false end)

local paragonButton = button({ Size = UDim2.new(0, 104, 0, 30), Position = UDim2.new(1, -194, 0, 12), BackgroundColor3 = Color3.fromRGB(120, 86, 30), Text = "🌟 Paragon", TextSize = 12 }, panel, function() end)

local rows = {}
for index, key in ipairs(LS.Order) do
	local def = LS[key]
	local y = 92 + (index - 1) * 56
	local row = make("Frame", { Size = UDim2.new(1, -24, 0, 50), Position = UDim2.new(0, 12, 0, y), BackgroundColor3 = Color3.fromRGB(36, 39, 58), BorderSizePixel = 0 }, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, row)
	label({ Size = UDim2.new(0, 34, 1, 0), Position = UDim2.new(0, 6, 0, 0), Text = def.Icon, TextSize = 20 }, row)
	label({ Size = UDim2.new(0, 160, 0, 22), Position = UDim2.new(0, 44, 0, 4), Text = def.Name, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left }, row)
	local valueLabel = label({ Size = UDim2.new(0, 216, 0, 18), Position = UDim2.new(0, 44, 0, 27), Text = "", TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(150, 235, 190), TextTruncate = Enum.TextTruncate.AtEnd }, row)
	local countLabel = label({ Size = UDim2.new(0, 36, 1, 0), Position = UDim2.new(1, -168, 0, 0), Text = "0", TextSize = 15, TextColor3 = Color3.fromRGB(255, 225, 110) }, row)
	button({ Size = UDim2.new(0, 30, 0, 32), Position = UDim2.new(1, -132, 0.5, -16), BackgroundColor3 = Color3.fromRGB(110, 60, 70), Text = "−" }, row, function()
		Remotes.LevelStat:FireServer("Sub", key, 1)
	end)
	button({ Size = UDim2.new(0, 30, 0, 32), Position = UDim2.new(1, -98, 0.5, -16), BackgroundColor3 = Color3.fromRGB(60, 120, 80), Text = "+" }, row, function()
		Remotes.LevelStat:FireServer("Add", key, 1)
	end)
	button({ Size = UDim2.new(0, 56, 0, 32), Position = UDim2.new(1, -64, 0.5, -16), BackgroundColor3 = Color3.fromRGB(70, 90, 170), Text = "Max", TextSize = 11 }, row, function()
		Remotes.LevelStat:FireServer("Add", key, 99)
	end)
	rows[key] = { Value = valueLabel, Count = countLabel }
end

label({ Size = UDim2.new(1, -32, 0, 30), Position = UDim2.new(0, 16, 0, 376), Text = LS.Double.Note or "", TextSize = 10, TextColor3 = Color3.fromRGB(170, 175, 205), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true }, panel)
-- 최대 레벨을 찍은 뒤: 골드로 포인트 구매 (살수록 비싸진다)
local buyButton = button({ Size = UDim2.new(0, 250, 0, 32), Position = UDim2.new(0, 16, 1, -42), BackgroundColor3 = Color3.fromRGB(140, 104, 40), Text = "", TextSize = 11, Visible = false }, panel, function()
	Remotes.LevelStat:FireServer("Buy")
end)
button({ Size = UDim2.new(0, 150, 0, 32), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 1, -42), BackgroundColor3 = Color3.fromRGB(120, 70, 70), Text = "Reset All (Free)", TextSize = 11 }, panel, function()
	Remotes.LevelStat:FireServer("Reset")
end)

local function refresh()
	local left = player:GetAttribute("LvPointsLeft") or 0
	local level = player:GetAttribute("Level") or 1
	local total = player:GetAttribute("LvTotal") or Config.GetLevelStatPoints(level)
	pointsLabel.Text = string.format("Points left %d  /  total %d  (Level %d)", left, total, level)
	local bought, cost = player:GetAttribute("LvGoldBought") or 0, player:GetAttribute("LvGoldCost") or 0
	buyButton.Visible = level >= Config.Level.Max
	buyButton.Text = cost > 0 and string.format("💰 Buy Point %s G (%d/%d)", tostring(cost):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""), bought, LS.MaxGoldPoints) or "💰 All points bought"
	for _, key in ipairs(LS.Order) do
		local points = player:GetAttribute("LvPts_" .. key) or 0
		rows[key].Count.Text = tostring(points)
		rows[key].Value.Text = (points > 0 and Config.LevelStatText(key, points) or LS[key].Desc) .. string.format("  (max %d)", LS.Cap[key])
	end
	badge.Visible = left > 0
	badge.Text = tostring(math.min(99, left))
	if left > 0 then
		pulse:Play()
		pill.BackgroundColor3 = Color3.fromRGB(70, 60, 28)
	else
		pulse:Cancel()
		pillStroke.Thickness, pillStroke.Color = 1.5, Color3.fromRGB(150, 160, 255)
		pill.BackgroundColor3 = Color3.fromRGB(34, 38, 60)
	end
	pill.Visible = false -- (왼쪽 메뉴 버튼 줄의 "스탯" 버튼과 빨간 점이 대신한다: 창 위에 떠서 겹치던 버튼)
end

for _, name in ipairs({ "LvPointsLeft", "Level", "TutorialActive", "LvTotal", "LvGoldBought", "LvGoldCost" }) do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end
for _, key in ipairs(LS.Order) do
	player:GetAttributeChangedSignal("LvPts_" .. key):Connect(refresh)
end
refresh()

------------------------------------------------------------
-- 패러건 창 (400 레벨 이후): 최대 레벨 뒤에 쌓이는 경험치로 포인트를 얻어 공격력 / 치명 / 치명 피해 / 보스 피해에 찍는다. 400 레벨 전에는 잠겨 있다.
------------------------------------------------------------
local PG = Config.Paragon
local ppanel = make("Frame", {
	Size = UDim2.new(0, 460, 0, 398), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(32, 28, 40), BorderSizePixel = 0, Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, ppanel)
make("UIStroke", { Color = Color3.fromRGB(255, 205, 100), Thickness = 2, Transparency = 0.2 }, ppanel)
make("UISizeConstraint", { MaxSize = Vector2.new(460, 398) }, ppanel)
label({ Size = UDim2.new(1, -200, 0, 30), Position = UDim2.new(0, 16, 0, 10), Text = "🌟 Paragon", TextSize = 20, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left }, ppanel)
local ppoints = label({ Size = UDim2.new(1, -32, 0, 22), Position = UDim2.new(0, 16, 0, 40), Text = "", TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 225, 110) }, ppanel)
local pprogress = label({ Size = UDim2.new(1, -32, 0, 18), Position = UDim2.new(0, 16, 0, 62), Text = "", TextSize = 10, TextColor3 = Color3.fromRGB(190, 180, 210), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true }, ppanel)
button({ Size = UDim2.new(0, 72, 0, 30), Position = UDim2.new(1, -84, 0, 12), BackgroundColor3 = Color3.fromRGB(54, 58, 82), Text = "Close", TextSize = 12 }, ppanel, function() ppanel.Visible = false end)
button({ Size = UDim2.new(0, 104, 0, 30), Position = UDim2.new(1, -194, 0, 12), BackgroundColor3 = Color3.fromRGB(60, 64, 120), Text = "✨ Level Stats", TextSize = 12 }, ppanel, function()
	ppanel.Visible = false
	panel.Visible = true
end)
local prows = {}
for index, key in ipairs(PG.Order) do
	local def = PG[key]
	local y = 92 + (index - 1) * 56
	local row = make("Frame", { Size = UDim2.new(1, -24, 0, 50), Position = UDim2.new(0, 12, 0, y), BackgroundColor3 = Color3.fromRGB(46, 40, 56), BorderSizePixel = 0 }, ppanel)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, row)
	label({ Size = UDim2.new(0, 34, 1, 0), Position = UDim2.new(0, 6, 0, 0), Text = def.Icon, TextSize = 20 }, row)
	label({ Size = UDim2.new(0, 160, 0, 22), Position = UDim2.new(0, 44, 0, 4), Text = def.Name, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left }, row)
	local valueLabel = label({ Size = UDim2.new(0, 216, 0, 18), Position = UDim2.new(0, 44, 0, 27), Text = "", TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 215, 140), TextTruncate = Enum.TextTruncate.AtEnd }, row)
	local countLabel = label({ Size = UDim2.new(0, 36, 1, 0), Position = UDim2.new(1, -168, 0, 0), Text = "0", TextSize = 15, TextColor3 = Color3.fromRGB(255, 225, 110) }, row)
	button({ Size = UDim2.new(0, 30, 0, 32), Position = UDim2.new(1, -132, 0.5, -16), BackgroundColor3 = Color3.fromRGB(110, 60, 70), Text = "−" }, row, function()
		Remotes.LevelStat:FireServer("PSub", key, 1)
	end)
	button({ Size = UDim2.new(0, 30, 0, 32), Position = UDim2.new(1, -98, 0.5, -16), BackgroundColor3 = Color3.fromRGB(60, 120, 80), Text = "+" }, row, function()
		Remotes.LevelStat:FireServer("PAdd", key, 1)
	end)
	button({ Size = UDim2.new(0, 56, 0, 32), Position = UDim2.new(1, -64, 0.5, -16), BackgroundColor3 = Color3.fromRGB(150, 110, 40), Text = "Max", TextSize = 11 }, row, function()
		Remotes.LevelStat:FireServer("PAdd", key, 99)
	end)
	prows[key] = { Row = row, Value = valueLabel, Count = countLabel }
end
label({ Size = UDim2.new(1, -32, 0, 30), Position = UDim2.new(0, 16, 0, 322), Text = "After level 400, the XP you earn turns into Paragon points. Spend them here; you can respec for free anytime.", TextSize = 10, TextColor3 = Color3.fromRGB(190, 180, 210), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true }, ppanel)
button({ Size = UDim2.new(0, 150, 0, 32), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 1, -42), BackgroundColor3 = Color3.fromRGB(120, 70, 70), Text = "Reset All (Free)", TextSize = 11 }, ppanel, function()
	Remotes.LevelStat:FireServer("PReset")
end)
paragonButton.Activated:Connect(function()
	panel.Visible = false
	ppanel.Visible = true
end)

local function commas(n)
	return (tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function refreshParagon()
	local level = player:GetAttribute("Level") or 1
	local unlocked = level >= Config.Level.Max
	local left = player:GetAttribute("ParagonLeft") or 0
	local earned = player:GetAttribute("ParagonEarned") or 0
	if unlocked then
		ppoints.Text = string.format("Points left %d  /  earned %d  (max %d)", left, earned, Config.ParagonMaxPoints)
		pprogress.Text = earned >= Config.ParagonMaxPoints and "All Paragon points earned!" or string.format("Next point: %s / %s XP", commas(player:GetAttribute("ParagonXp") or 0), commas(player:GetAttribute("ParagonXpNeeded") or Config.ParagonXpPerPoint()))
	else
		ppoints.Text = string.format("🔒 Unlocks at level %d  (you are level %d)", Config.Level.Max, level)
		pprogress.Text = "Reach the max level to start earning Paragon points."
	end
	for _, key in ipairs(PG.Order) do
		local points = player:GetAttribute("ParagonPts_" .. key) or 0
		prows[key].Count.Text = tostring(points)
		prows[key].Value.Text = (points > 0 and Config.ParagonText(key, points) or PG[key].Desc) .. string.format("  (max %d)", PG.Cap[key])
		prows[key].Row.BackgroundTransparency = unlocked and 0 or 0.5
	end
	paragonButton.Text = (unlocked and left > 0) and string.format("🌟 Paragon (%d)", left) or "🌟 Paragon"
end
for _, name in ipairs({ "Level", "ParagonLeft", "ParagonEarned", "ParagonXp", "ParagonXpNeeded" }) do
	player:GetAttributeChangedSignal(name):Connect(refreshParagon)
end
for _, key in ipairs(PG.Order) do
	player:GetAttributeChangedSignal("ParagonPts_" .. key):Connect(refreshParagon)
end
refreshParagon()

pill.Activated:Connect(function() panel.Visible = not panel.Visible end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.T then
		ppanel.Visible = false
		panel.Visible = not panel.Visible
	end
end)

player:GetAttributeChangedSignal("OpenStats"):Connect(function()
	ppanel.Visible = false
	panel.Visible = not panel.Visible
end) -- 왼쪽 메뉴 버튼(MenuDockClient)
