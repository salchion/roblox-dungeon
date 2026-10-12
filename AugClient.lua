-- AugClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: AugClient)
-- ✨ 세트 효과 창 (Y 키 또는 "세트" 버튼): 구역 군주를 잡으면 그 구역 효과가 열리고, 골드로 활성화 / 1~3단계 강화한다.
-- 동시에 켤 수 있는 칸(AugSlots)은 처음 1개이고 구역을 클리어할수록 늘어난다. 값은 서버가 정하는 Attribute 에서 읽는다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local ZONES = Config.Field.ZoneCount

local gui = Instance.new("ScreenGui")
gui.Name = "AugGui"
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
	props.TextSize = props.TextSize or 14
	props.AutoButtonColor = true
	local b = make("TextButton", props, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
	b.Activated:Connect(callback)
	return b
end

local function commas(n)
	return (tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- 왼쪽 상태 카드 아래, "스탯" 버튼 옆
local pill = button({
	Size = UDim2.new(0, 78, 0, 32), Position = UDim2.new(0, 264, 0, 244),
	BackgroundColor3 = Color3.fromRGB(34, 38, 60), Text = "🌟 Sets (Y)", TextSize = 12, Visible = false,
}, gui, function() end)
make("UIStroke", { Color = Color3.fromRGB(255, 190, 110), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pill)
local badge = label({
	Size = UDim2.new(0, 24, 0, 24), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 2),
	BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(255, 80, 80), Text = "!", TextSize = 13, Visible = false, ZIndex = 5,
}, pill)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, badge)

local panel = make("Frame", {
	Size = UDim2.new(0, 480, 0, 470), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(26, 28, 42), BorderSizePixel = 0, Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, panel)
make("UIStroke", { Color = Color3.fromRGB(255, 190, 110), Thickness = 2 }, panel)
make("UISizeConstraint", { MaxSize = Vector2.new(480, 470) }, panel)

label({ Size = UDim2.new(1, -90, 0, 30), Position = UDim2.new(0, 16, 0, 10), Text = "🌟 Set Effects", TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left }, panel)
local slotLabel = label({ Size = UDim2.new(1, -32, 0, 20), Position = UDim2.new(0, 16, 0, 40), Text = "", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 225, 110) }, panel)
label({ Size = UDim2.new(1, -32, 0, 32), Position = UDim2.new(0, 16, 0, 60), Text = "Tap a slot to toggle it. Defeat a lord to unlock its effect, then upgrade it with gold up to Lv.3. Wear that zone's set gear for Lv.4 at 1 piece · Lv.5 at 2 pieces · Lv.6 at 3 pieces! The real power shows up in field hunting.", TextSize = 12, TextColor3 = Color3.fromRGB(170, 175, 205), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true }, panel)
button({ Size = UDim2.new(0, 60, 0, 28), Position = UDim2.new(1, -72, 0, 10), BackgroundColor3 = Color3.fromRGB(70, 70, 90), Text = "Close", TextSize = 13 }, panel, function() panel.Visible = false end)

local list = make("ScrollingFrame", {
	Size = UDim2.new(1, -24, 1, -104), Position = UDim2.new(0, 12, 0, 94), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 5, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, panel)
make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, list)

local rows = {}
for zone = 1, ZONES do
	local attr = Config.Sets.ZoneAug[zone]
	local info = Config.AugInfo[attr]
	local row = make("Frame", { Size = UDim2.new(1, -8, 0, 62), BackgroundColor3 = Color3.fromRGB(36, 39, 58), BorderSizePixel = 0, LayoutOrder = zone }, list)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, row)
	label({ Size = UDim2.new(0, 34, 1, 0), Position = UDim2.new(0, 6, 0, 0), Text = info.Icon, TextSize = 24 }, row)
	local title = label({ Size = UDim2.new(1, -250, 0, 20), Position = UDim2.new(0, 44, 0, 5), Text = "", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, row)
	local desc = label({ Size = UDim2.new(1, -250, 0, 32), Position = UDim2.new(0, 44, 0, 25), Text = info.Desc, TextSize = 11, TextColor3 = Color3.fromRGB(170, 215, 190), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true }, row)
	-- 칸 어디를 눌러도 켜고 꺼진다 (맨 아래에 깔린 투명 버튼). 오른쪽 위 ON/OFF 는 상태만 보여 준다.
	local hit = make("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 1 }, row)
	hit.Activated:Connect(function() Remotes.Aug:FireServer("Toggle", zone) end)
	local toggle = make("TextLabel", {
		Size = UDim2.new(0, 64, 0, 24), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6), BackgroundColor3 = Color3.fromRGB(62, 64, 84),
		BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Color3.fromRGB(150, 154, 180), Text = "○ OFF", ZIndex = 2,
	}, row)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, toggle)
	local buy = button({ Size = UDim2.new(0, 150, 0, 26), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 32), BackgroundColor3 = Color3.fromRGB(140, 104, 40), Text = "", TextSize = 12 }, row, function()
		Remotes.Aug:FireServer("Buy", zone)
	end)
	-- ⓘ 자세히: 1~6단계 수치 (눌러서 펼치고 접는다)
	local detail = label({
		Size = UDim2.new(1, -20, 0, 0), Position = UDim2.new(0, 10, 0, 64), Text = "", TextSize = 11, RichText = true, Visible = false,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextColor3 = Color3.fromRGB(205, 210, 235), ZIndex = 2,
	}, row)
	local infoButton = button({ Size = UDim2.new(0, 74, 0, 26), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -166, 0, 32), BackgroundColor3 = Color3.fromRGB(64, 72, 112), Text = "ⓘ Details ▾", TextSize = 10 }, row, function() end)
	infoButton.ZIndex = 3
	-- 켜져 있으면 테두리가 효과 색으로 빛나며 천천히 도는 띠가 된다 (꺼져 있으면 테두리 없음)
	local rowStroke = make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Transparency = 1 }, row)
	local gradient = make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, info.Color),
			ColorSequenceKeypoint.new(0.3, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.6, info.Color:Lerp(Color3.new(0, 0, 0), 0.55)),
			ColorSequenceKeypoint.new(1, info.Color),
		}),
	}, rowStroke)
	rows[zone] = { Title = title, Toggle = toggle, Buy = buy, Row = row, Stroke = rowStroke, Gradient = gradient, Detail = detail, Info = infoButton, Desc = desc, Open = false }
	infoButton.Activated:Connect(function()
		rows[zone].Open = not rows[zone].Open
		rows[zone].Update()
	end)
	rows[zone].Update = function()
		local r = rows[zone]
		local levelNow = (player:GetAttribute("AugLvZ_" .. zone) or 0) + (player:GetAttribute("AugGearZ_" .. zone) or 0)
		local atk = Config.BaseAttackEstimate and Config.BaseAttackEstimate(player) or 0
		r.Info.Text = r.Open and "ⓘ Details ▴" or "ⓘ Details ▾"
		if not r.Open then
			r.Detail.Visible = false
			r.Row.Size = UDim2.new(1, -8, 0, 62)
			return
		end
		local lines = { "<b>Per level</b>  (Lv.1–3 from gold · Lv.4–6 with set gear; damage ≈ one hit at your current attack, before crit/combo)" }
		local attr = Config.Sets.ZoneAug[zone]
		for l = 1, 6 do
			local text, mult = Config.AugLevelLine(attr, l)
			local dmg = mult and atk > 0 and string.format("  <font color='#ffd966'>≈ %d dmg</font>", math.floor(atk * mult + 0.5)) or ""
			local line = string.format("Lv.%d  %s%s", l, text, dmg)
			if l == levelNow then line = "<font color='#78ff8c'><b>▶ " .. line .. "  (now)</b></font>" end
			table.insert(lines, line)
		end
		r.Detail.Text = table.concat(lines, "\n")
		r.Detail.Size = UDim2.new(1, -20, 0, 14 + 15 * 8)
		r.Detail.Visible = true
		r.Row.Size = UDim2.new(1, -8, 0, 62 + 14 + 15 * 8 + 6)
	end
end

local function refresh()
	local gold = player:GetAttribute("Gold") or 0
	local slots = player:GetAttribute("AugSlots") or 1
	local used, affordable = 0, 0
	local anyOpen = false
	for zone = 1, ZONES do
		local open = player:GetAttribute("AugOpenZ_" .. zone) == true
		local level = player:GetAttribute("AugLvZ_" .. zone) or 0
		local on = player:GetAttribute("AugOnZ_" .. zone) == true
		local r = rows[zone]
		anyOpen = anyOpen or open
		if on then used += 1 end
		local info = Config.AugInfo[Config.Sets.ZoneAug[zone]]
		local gear = player:GetAttribute("AugGearZ_" .. zone) or 0
		r.Title.Text = string.format("Zone %d · %s  %s", zone, info.Name, level > 0 and (gear > 0 and string.format("<Lv.%d + gear %d = %d>", level, gear, level + gear) or ("<Lv." .. level .. ">")) or "")
		r.Title.TextColor3 = open and Color3.fromRGB(255, 240, 200) or Color3.fromRGB(130, 134, 156)
		r.Toggle.Visible = level > 0
		r.Toggle.Text = on and "● ON" or "○ OFF" -- 지금 상태를 보여 주고, 누르면 반대로 바뀐다
		r.Toggle.BackgroundColor3 = on and Color3.fromRGB(46, 112, 84) or Color3.fromRGB(62, 64, 84)
		r.Toggle.TextColor3 = on and Color3.fromRGB(190, 255, 215) or Color3.fromRGB(150, 154, 180)
		r.Stroke.Transparency = on and 0.1 or 1
		r.Row.BackgroundColor3 = on and Color3.fromRGB(50, 52, 74) or Color3.fromRGB(36, 39, 58)
		if not open then
			r.Buy.Text = string.format("🔒 Defeat the Zone %d lord", zone)
			r.Buy.BackgroundColor3 = Color3.fromRGB(60, 62, 80)
		elseif level >= 3 then
			r.Buy.Text = "Max level"
			r.Buy.BackgroundColor3 = Color3.fromRGB(60, 62, 80)
		else
			local cost = Config.Sets.AugCost(zone, level + 1)
			r.Buy.Text = string.format("%s %s G", level == 0 and "Activate" or "Upgrade", commas(cost))
			r.Buy.BackgroundColor3 = gold >= cost and Color3.fromRGB(150, 110, 40) or Color3.fromRGB(80, 74, 66)
			if gold >= cost and level == 0 then affordable += 1 end
		end
	end
	for zone = 1, ZONES do rows[zone].Update() end
	slotLabel.Text = string.format("Active %d / %d slots   (💰 %s G)", used, slots, commas(gold))
	pill.Visible = anyOpen and not player:GetAttribute("TutorialActive")
	badge.Visible = affordable > 0 and used < slots
end

for _, name in ipairs({ "Gold", "AugSlots", "TutorialActive" }) do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end
for zone = 1, ZONES do
	for _, prefix in ipairs({ "AugOpenZ_", "AugLvZ_", "AugOnZ_", "AugGearZ_" }) do
		player:GetAttributeChangedSignal(prefix .. zone):Connect(refresh)
	end
end
refresh()

-- 켜진 효과의 테두리 빛이 천천히 돈다 (창이 열려 있을 때만)
RunService.RenderStepped:Connect(function()
	if not panel.Visible then return end
	local t = os.clock()
	for zone = 1, ZONES do
		local r = rows[zone]
		if r.Stroke.Transparency < 1 then
			r.Gradient.Rotation = (t * 110 + zone * 40) % 360
			r.Stroke.Thickness = 2 + 0.6 * math.sin(t * 3 + zone)
		end
	end
end)

pill.Activated:Connect(function() panel.Visible = not panel.Visible end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Y then panel.Visible = not panel.Visible end
end)

------------------------------------------------------------
-- 켜 둔 세트 효과 상태창: 필드 / 던전에서 오른쪽 위에 작게 (효과 이름 + 현재 몇 단계인지, 골드 단계 + 장비 단계)
------------------------------------------------------------
local hudBox = make("TextLabel", {
	Size = UDim2.new(0, 210, 0, 40), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 176),
	BackgroundColor3 = Color3.fromRGB(22, 24, 38), BackgroundTransparency = 0.2, BorderSizePixel = 0, Font = Enum.Font.GothamMedium,
	TextSize = 12, TextColor3 = Color3.new(1, 1, 1), RichText = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	Text = "", Visible = false, ZIndex = 3,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, hudBox)
make("UIStroke", { Color = Color3.fromRGB(255, 190, 110), Thickness = 1.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Transparency = 0.4 }, hudBox)
make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 5), PaddingRight = UDim.new(0, 6) }, hudBox)

local function refreshHud()
	local zone = player:GetAttribute("Zone")
	local lines = { "<font color='#ffd966'><b>🌟 Set Effects</b></font>" }
	for z = 1, ZONES do
		if player:GetAttribute("AugOnZ_" .. z) == true then
			local info = Config.AugInfo[Config.Sets.ZoneAug[z]]
			local gold = player:GetAttribute("AugLvZ_" .. z) or 0
			local gear = player:GetAttribute("AugGearZ_" .. z) or 0
			table.insert(lines, string.format("%s %s  <font color='#8fe0ff'><b>Lv.%d</b></font>%s", info.Icon, info.Name, gold + gear,
				gear > 0 and string.format(" <font color='#aab0c8'>(gold %d + gear %d)</font>", gold, gear) or ""))
		end
	end
	hudBox.Visible = #lines > 1 and (zone == "Field" or zone == "Dungeon") and not player:GetAttribute("TutorialActive")
	hudBox.Text = table.concat(lines, "\n")
	hudBox.Size = UDim2.new(0, 210, 0, 12 + #lines * 16)
end
for _, name in ipairs({ "Zone", "TutorialActive" }) do player:GetAttributeChangedSignal(name):Connect(refreshHud) end
for z = 1, ZONES do
	for _, prefix in ipairs({ "AugOnZ_", "AugLvZ_", "AugGearZ_" }) do player:GetAttributeChangedSignal(prefix .. z):Connect(refreshHud) end
end
refreshHud()

------------------------------------------------------------
-- 던전 시작 체험 효과: 8개 중 하나를 뽑는 연출(약 2.5초) -> 화면 오른쪽 위 구석에 작은 표시
------------------------------------------------------------
local TweenService = game:GetService("TweenService")
local corner = make("TextLabel", {
	Size = UDim2.new(0, 240, 0, 46), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 96), RichText = true, TextWrapped = true,
	BackgroundColor3 = Color3.fromRGB(26, 28, 42), BackgroundTransparency = 0.25, Font = Enum.Font.GothamBold, TextSize = 13,
	TextColor3 = Color3.new(1, 1, 1), Text = "", Visible = false, BorderSizePixel = 0,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, corner)
local cornerStroke = make("UIStroke", { Color = Color3.fromRGB(255, 190, 110), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, corner) -- (Border: 글자가 아니라 상자 테두리에만)

local function refreshCorner()
	local attr = player:GetAttribute("AugDemo")
	local info = typeof(attr) == "string" and Config.AugInfo[attr]
	local show = info and player:GetAttribute("Zone") == "Dungeon" and not corner:GetAttribute("Rolling")
	corner.Visible = show == true
	if show then
		local zone = table.find(Config.Sets.ZoneAug, attr) or 0
		corner.Text = string.format("%s <b>%s</b>  <font size='11' color='#ffd966'>Zone %d · Trial Lv.3</font>\n<font size='11' color='#c8d0e8'>%s</font>", info.Icon, info.Name, zone, info.Desc)
		cornerStroke.Color = info.Color
	end
end
player:GetAttributeChangedSignal("AugDemo"):Connect(refreshCorner)
player:GetAttributeChangedSignal("Zone"):Connect(refreshCorner)

local function playRoll(pick)
	local winner = Config.AugInfo[pick]
	if not winner then return end
	corner:SetAttribute("Rolling", true)
	corner.Visible = false
	local box = make("Frame", {
		Size = UDim2.new(0, 320, 0, 128), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.14, 0),
		BackgroundColor3 = Color3.fromRGB(26, 28, 42), BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 60,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, box)
	local stroke = make("UIStroke", { Color = Color3.fromRGB(255, 190, 110), Thickness = 2 }, box)
	label({ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 0, 6), Text = "🎲 This Dungeon's Trial Effect", TextSize = 14, ZIndex = 61 }, box)
	local icon = label({ Size = UDim2.new(0, 60, 0, 44), Position = UDim2.new(0, 14, 0, 32), Text = "?", TextSize = 34, ZIndex = 61 }, box)
	local name = label({ Size = UDim2.new(1, -88, 0, 44), Position = UDim2.new(0, 78, 0, 32), Text = "", TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, RichText = true, ZIndex = 61 }, box)
	local detail = label({ Size = UDim2.new(1, -24, 0, 40), Position = UDim2.new(0, 12, 0, 80), Text = "", TextSize = 12, TextWrapped = true, TextColor3 = Color3.fromRGB(200, 208, 232), Font = Enum.Font.GothamMedium, ZIndex = 61 }, box)
	local startedAt = os.clock()
	while os.clock() - startedAt < 1.3 do
		local info = Config.AugInfo[Config.Sets.ZoneAug[math.random(#Config.Sets.ZoneAug)]]
		icon.Text, name.Text = info.Icon, info.Name
		name.TextColor3 = Color3.fromRGB(170, 175, 205)
		task.wait(0.07)
	end
	local winZone = table.find(Config.Sets.ZoneAug, pick) or 0
	icon.Text, name.Text = winner.Icon, string.format("%s\n<font size='12' color='#ffd966'>Zone %d set effect · Trial Lv.3</font>", winner.Name, winZone)
	detail.Text = winner.Desc
	name.TextColor3 = winner.Color
	stroke.Color = winner.Color
	task.wait(2.2)
	TweenService:Create(box, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	task.wait(0.3)
	box:Destroy()
	corner:SetAttribute("Rolling", nil)
	refreshCorner()
end

Remotes.Aug.OnClientEvent:Connect(function(action, pick)
	if action == "Demo" then task.spawn(playRoll, pick) end
end)
refreshCorner()
