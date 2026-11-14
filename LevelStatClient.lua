-- LevelStatClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: LevelStatClient)
-- 레벨 스탯 창 (T 키 또는 오른쪽의 "스탯" 버튼): 레벨 업마다 받는 포인트를 이동 속도 / 사정거리 / 투사체 / 스킬 쿨타임 / 전리품 흡수에 배분한다.
-- 언제든 무료로 빼고 다시 넣을 수 있다. 값은 서버가 정하는 Attribute(LvPts_<키>, LvPointsLeft)에서 읽는다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local okSound, SoundBank = pcall(function() return require(ReplicatedStorage:WaitForChild("SoundBank", 10)) end)

local player = Players.LocalPlayer
local upStreak, lastUp = 0, 0
local function sfx(key, opts) -- 스탯 창 소리: + 를 연달아 누르면 음이 조금씩 올라간다 (최대 6단계)
	if not okSound then return end
	if key == "Stat_Up" then
		upStreak = (os.clock() - lastUp < 0.7) and math.min(6, upStreak + 1) or 0
		lastUp = os.clock()
		opts = { Pitch = 1 + upStreak * 0.07 }
	end
	pcall(SoundBank.Play, game:GetService("SoundService"), key, opts)
end
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

-- 게임 같은 스탯 줄 (표처럼 네모난 칸 대신): 스탯 색 띠 / 메달 아이콘 / 이름 + 찍은 수 / 효과 / 칸 막대(포인트 하나 = 한 칸) / 동그란 - + 버튼 / 최대 알약
local Kit = require(ReplicatedStorage:WaitForChild("ClientKit"))
local STAT_COLORS = {
	Move = Color3.fromRGB(90, 210, 255), Range = Color3.fromRGB(255, 210, 90), Double = Color3.fromRGB(255, 160, 90), Haste = Color3.fromRGB(154, 140, 255), CritDmg = Color3.fromRGB(255, 110, 90),
	Attack = Color3.fromRGB(255, 120, 90), Crit = Color3.fromRGB(255, 210, 90), Boss = Color3.fromRGB(255, 80, 120),
}
local function roundButton(parent, size, x, y, text, color, glow, onClick)
	local b = button({ Size = UDim2.new(0, size, 0, size), Position = UDim2.new(0, x, 0, y), BackgroundColor3 = color, Text = text, TextSize = math.floor(size * 0.5), Font = Enum.Font.GothamBlack }, parent, onClick)
	b:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)
	make("UIStroke", { Color = Color3.fromRGB(22, 18, 44), Thickness = 2.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 165)) }, b)
	if glow then
		local halo = make("Frame", { Size = UDim2.new(1.35, 0, 1.35, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundColor3 = color, BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 0 }, b)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, halo)
	end
	return b
end
local function statRow(parent, y, key, def, cap, onSub, onAdd, onMax)
	local color = STAT_COLORS[key] or Color3.fromRGB(150, 160, 255)
	local strip = make("Frame", { Size = UDim2.new(1, -28, 0, 52), Position = UDim2.new(0, 14, 0, y), BackgroundColor3 = color, BackgroundTransparency = 0.78, BorderSizePixel = 0 }, parent)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, strip)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.85), NumberSequenceKeypoint.new(1, 1) }) }, strip)
	Kit.medal(strip, { Size = 46, Position = UDim2.new(0, 4, 0, 3), Color = color, Icon = def.Icon, TextSize = 20, ZIndex = 2 })
	local name = label({ Size = UDim2.new(0, 230, 0, 18), Position = UDim2.new(0, 60, 0, 4), Text = def.Name, RichText = true, TextSize = 13, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left }, strip)
	local value = label({ Size = UDim2.new(0, 230, 0, 14), Position = UDim2.new(0, 60, 0, 21), Text = "", TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(150, 235, 190), TextTruncate = Enum.TextTruncate.AtEnd }, strip)
	local bar = make("Frame", { Size = UDim2.new(0, 220, 0, 7), Position = UDim2.new(0, 60, 0, 39), BackgroundTransparency = 1 }, strip)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2) }, bar)
	local pips, fill = {}, nil
	if cap <= 20 then -- 포인트 하나 = 한 칸
		local width = (220 - 2 * (cap - 1)) / math.max(1, cap)
		for i = 1, cap do
			local pip = make("Frame", { Size = UDim2.new(0, width, 1, 0), BackgroundColor3 = Color3.fromRGB(42, 42, 62), BorderSizePixel = 0, LayoutOrder = i }, bar)
			make("UICorner", { CornerRadius = UDim.new(1, 0) }, pip)
			pips[i] = pip
		end
	else -- (칸이 너무 많으면: 이어진 막대 하나. 초월 스탯은 최대 100)
		local back = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(42, 42, 62), BorderSizePixel = 0 }, bar)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, back)
		fill = make("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0 }, back)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
	end
	roundButton(strip, 30, 300, 11, "−", Color3.fromRGB(130, 80, 92), false, onSub)
	roundButton(strip, 38, 336, 7, "+", Color3.fromRGB(90, 200, 120), true, onAdd)
	local maxB = button({ Size = UDim2.new(0, 40, 0, 24), Position = UDim2.new(0, 380, 0, 14), BackgroundColor3 = Color3.fromRGB(62, 74, 140), Text = "Max", TextSize = 10, Font = Enum.Font.GothamBlack }, strip, onMax)
	maxB:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)
	make("UIStroke", { Color = Color3.fromRGB(22, 18, 44), Thickness = 1.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, maxB)
	local function set(points, text)
		name.Text = string.format("%s <font size='11' color='#ffe16e'>%d/%d</font>", def.Name, points, cap)
		value.Text = text
		for i, pip in ipairs(pips) do pip.BackgroundColor3 = i <= points and color or Color3.fromRGB(42, 42, 62) end
		if fill then fill.Size = UDim2.new(math.clamp(points / math.max(1, cap), 0, 1), 0, 1, 0) end
	end
	return { Set = set, Strip = strip }
end
local function pointsGem(parent) -- 가운데 보석: 남은 포인트를 크게
	local gem = make("Frame", { Size = UDim2.new(0, 210, 0, 46), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 48), BackgroundColor3 = Color3.fromRGB(255, 217, 106), BackgroundTransparency = 0.82, BorderSizePixel = 0 }, parent)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, gem)
	make("UIStroke", { Color = Color3.fromRGB(255, 217, 106), Thickness = 1.5, Transparency = 0.45 }, gem)
	local big = label({ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0, 2), Text = "💎 0", TextSize = 22, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 225, 110) }, gem)
	local small = label({ Size = UDim2.new(1, -10, 0, 14), Position = UDim2.new(0, 5, 0, 28), Text = "", TextSize = 9, TextColor3 = Color3.fromRGB(216, 207, 168) }, gem)
	return big, small
end
local function titleRibbon(parent, text, stroke)
	local ribbon = make("Frame", { Size = UDim2.new(1, -24, 0, 30), Position = UDim2.new(0, 12, 0, 10), BackgroundColor3 = Color3.fromRGB(90, 68, 46), BorderSizePixel = 0 }, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, ribbon)
	make("UIStroke", { Color = stroke or Color3.fromRGB(225, 196, 118), Thickness = 1.2, Transparency = 0.35 }, ribbon)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.6) }) }, ribbon)
	label({ Size = UDim2.new(1, 0, 1, 0), Text = text, TextSize = 16, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 226, 150) }, ribbon)
	return ribbon
end

-- 창
local panel = make("Frame", {
	Size = UDim2.new(0, 460, 0, 452), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(20, 18, 31), BorderSizePixel = 0, Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 16) }, panel)
make("UIStroke", { Color = Color3.fromRGB(225, 196, 118), Thickness = 2, Transparency = 0.45 }, panel)
make("UISizeConstraint", { MaxSize = Vector2.new(460, 452) }, panel)

titleRibbon(panel, "✨ Level Stats")
local pointsBig, pointsSmall = pointsGem(panel)
button({ Size = UDim2.new(0, 26, 0, 22), Position = UDim2.new(1, -46, 0, 14), BackgroundColor3 = Color3.fromRGB(54, 58, 82), Text = "✕", TextSize = 12 }, panel, function() panel.Visible = false end)
local paragonButton = button({ Size = UDim2.new(0, 96, 0, 22), Position = UDim2.new(0, 20, 0, 14), BackgroundColor3 = Color3.fromRGB(120, 86, 30), Text = "🌟 Paragon", TextSize = 11 }, panel, function() end)

local rows = {}
for index, key in ipairs(LS.Order) do
	rows[key] = statRow(panel, 100 + (index - 1) * 55, key, LS[key], LS.Cap[key],
		function() sfx("Stat_Down") Remotes.LevelStat:FireServer("Sub", key, 1) end,
		function() sfx("Stat_Up") Remotes.LevelStat:FireServer("Add", key, 1) end,
		function() sfx("Stat_Max") Remotes.LevelStat:FireServer("Add", key, 99) end)
end

label({ Size = UDim2.new(1, -200, 0, 28), Position = UDim2.new(0, 18, 1, -40), Text = "These stats shape your play style. Respec for free anytime.", TextSize = 10, TextColor3 = Color3.fromRGB(170, 176, 204), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true }, panel)
-- 최대 레벨을 찍은 뒤: 골드로 포인트 구매 (살수록 비싸진다)
local buyButton = button({ Size = UDim2.new(0, 250, 0, 30), Position = UDim2.new(0, 16, 1, -74), BackgroundColor3 = Color3.fromRGB(140, 104, 40), Text = "", TextSize = 11, Visible = false }, panel, function()
	sfx("Stat_Up")
	Remotes.LevelStat:FireServer("Buy")
end)
button({ Size = UDim2.new(0, 150, 0, 30), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 1, -40), BackgroundColor3 = Color3.fromRGB(110, 60, 60), Text = "🔁 Reset (Free)", TextSize = 11 }, panel, function()
	sfx("Stat_Reset")
	Remotes.LevelStat:FireServer("Reset")
end)

local function refresh()
	local left = player:GetAttribute("LvPointsLeft") or 0
	local level = player:GetAttribute("Level") or 1
	local total = player:GetAttribute("LvTotal") or Config.GetLevelStatPoints(level)
	-- 몇 레벨마다 포인트가 생기는지 + 다음 포인트가 생기는 레벨 (최고 레벨이면 생략)
	local nextLevel
	for candidate = level + 1, Config.Level.StatCap do
		if Config.GetLevelStatPoints(candidate) > Config.GetLevelStatPoints(level) then nextLevel = candidate break end
	end
	pointsBig.Text = "💎 " .. left
	pointsSmall.Text = nextLevel and string.format("Points left · next +1 at Lv.%d", nextLevel) or string.format("Points left · total %d", total)
	local bought, cost = player:GetAttribute("LvGoldBought") or 0, player:GetAttribute("LvGoldCost") or 0
	buyButton.Visible = level >= Config.Level.Max
	buyButton.Text = cost > 0 and string.format("💰 Buy Point %s G (%d/%d)", tostring(cost):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""), bought, LS.MaxGoldPoints) or "💰 All points bought"
	for _, key in ipairs(LS.Order) do
		local points = player:GetAttribute("LvPts_" .. key) or 0
		rows[key].Set(points, points > 0 and Config.LevelStatText(key, points) or LS[key].Desc)
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
	BackgroundColor3 = Color3.fromRGB(26, 20, 30), BorderSizePixel = 0, Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 16) }, ppanel)
make("UIStroke", { Color = Color3.fromRGB(255, 205, 100), Thickness = 2, Transparency = 0.35 }, ppanel)
make("UISizeConstraint", { MaxSize = Vector2.new(460, 398) }, ppanel)
titleRibbon(ppanel, "🌟 Paragon", Color3.fromRGB(255, 205, 100))
local ppoints, pprogress = pointsGem(ppanel)
button({ Size = UDim2.new(0, 26, 0, 22), Position = UDim2.new(1, -46, 0, 14), BackgroundColor3 = Color3.fromRGB(54, 58, 82), Text = "✕", TextSize = 12 }, ppanel, function() ppanel.Visible = false end)
button({ Size = UDim2.new(0, 96, 0, 22), Position = UDim2.new(0, 20, 0, 14), BackgroundColor3 = Color3.fromRGB(60, 64, 120), Text = "✨ Level Stats", TextSize = 11 }, ppanel, function()
	ppanel.Visible = false
	panel.Visible = true
end)
local prows = {}
for index, key in ipairs(PG.Order) do
	prows[key] = statRow(ppanel, 100 + (index - 1) * 55, key, PG[key], PG.Cap[key],
		function() sfx("Stat_Down") Remotes.LevelStat:FireServer("PSub", key, 1) end,
		function() sfx("Stat_Up") Remotes.LevelStat:FireServer("PAdd", key, 1) end,
		function() sfx("Stat_Max") Remotes.LevelStat:FireServer("PAdd", key, 99) end)
end
label({ Size = UDim2.new(1, -200, 0, 30), Position = UDim2.new(0, 18, 1, -40), Text = "After level 400, the XP you earn turns into Paragon points. Spend them here; you can respec for free anytime.", TextSize = 10, TextColor3 = Color3.fromRGB(190, 180, 210), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true }, ppanel)
button({ Size = UDim2.new(0, 150, 0, 30), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 1, -40), BackgroundColor3 = Color3.fromRGB(110, 60, 60), Text = "🔁 Reset (Free)", TextSize = 11 }, ppanel, function()
	sfx("Stat_Reset")
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
		ppoints.Text = "💎 " .. left
		pprogress.Text = earned >= Config.ParagonMaxPoints and "All Paragon points earned!" or string.format("Next point: %s / %s XP", commas(player:GetAttribute("ParagonXp") or 0), commas(player:GetAttribute("ParagonXpNeeded") or Config.ParagonXpPerPoint()))
	else
		ppoints.Text = "🔒"
		pprogress.Text = string.format("🔒 Unlocks at level %d  (you are level %d)", Config.Level.Max, level)
	end
	for _, key in ipairs(PG.Order) do
		local points = player:GetAttribute("ParagonPts_" .. key) or 0
		prows[key].Set(points, points > 0 and Config.ParagonText(key, points) or PG[key].Desc)
		prows[key].Strip.BackgroundTransparency = unlocked and 0.78 or 0.95
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
