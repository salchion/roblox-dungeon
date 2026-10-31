-- AugClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: AugClient)
-- ✨ 세트 효과 창 (Y 키 또는 "세트" 버튼): 구역 군주를 잡으면 그 구역 효과가 열리고, 골드로 활성화 / 1~3단계 강화한다.
-- 동시에 켤 수 있는 칸(AugSlots)은 처음 1개이고 구역을 클리어할수록 늘어난다. 값은 서버가 정하는 Attribute 에서 읽는다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))

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
	Name = "SetsPill", Size = UDim2.new(0, 78, 0, 32), Position = UDim2.new(0, 264, 0, 244),
	BackgroundColor3 = Color3.fromRGB(34, 38, 60), Text = "🌟 Sets (Y)", TextSize = 10, Visible = false,
}, gui, function() end)
make("UIStroke", { Color = Color3.fromRGB(255, 190, 110), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pill)
local badge = label({
	Size = UDim2.new(0, 24, 0, 24), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 2),
	BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(255, 80, 80), Text = "!", TextSize = 11, Visible = false, ZIndex = 5,
}, pill)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, badge)

-- 창 모양: 가운데 네모(고른 효과의 설명 + 버튼) 둘레에 구역 효과 8개가 원으로 둘러선다 (무협 게임의 팔괘 / 경혈처럼).
-- 한 화면에 다 들어와서 스크롤이 없다. 원을 누르면 가운데에 그 효과가 나온다.
local PANEL_W, PANEL_H = 680, 548
local RING_CX, RING_CY = PANEL_W / 2, 300 -- 원들이 둘러서는 중심
local RING_RX, RING_RY = 250, 178
local ORB = 66
local BOX_W, BOX_H = 244, 214

local panel = make("Frame", {
	Size = UDim2.new(0, PANEL_W, 0, PANEL_H), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(22, 20, 34), BorderSizePixel = 0, Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 14) }, panel)
make("UIStroke", { Color = Color3.fromRGB(255, 190, 110), Thickness = 2, Transparency = 0.25 }, panel)
make("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 130, 180)), Rotation = 90 }, panel)
local panelScale = make("UIScale", { Scale = 1 }, panel) -- 작은 화면에서는 통째로 줄인다
local function fitPanel()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local view = camera.ViewportSize
	panelScale.Scale = math.clamp(math.min((view.X - 20) / PANEL_W, (view.Y - 20) / PANEL_H), 0.45, 1)
end
fitPanel()
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitPanel) end

label({ Size = UDim2.new(1, -90, 0, 30), Position = UDim2.new(0, 16, 0, 10), Text = "🌟 Set Effects", TextSize = 20, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left }, panel)
local slotLabel = label({ Size = UDim2.new(1, -32, 0, 20), Position = UDim2.new(0, 16, 0, 40), Text = "", TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 225, 110) }, panel)
label({ Size = UDim2.new(1, -32, 0, 28), Position = UDim2.new(0, 16, 0, 60), Text = "Tap a slot to toggle it. Defeat a lord to unlock its effect, then upgrade it with gold up to Lv.3. Wear that zone's set gear for Lv.4 at 1 piece · Lv.5 at 2 pieces · Lv.6 at 3 pieces! The real power shows up in field hunting.", TextSize = 10, TextColor3 = Color3.fromRGB(170, 175, 205), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true }, panel)
button({ Size = UDim2.new(0, 72, 0, 30), Position = UDim2.new(1, -84, 0, 12), BackgroundColor3 = Color3.fromRGB(54, 58, 82), Text = "Close", TextSize = 12 }, panel, function() panel.Visible = false end)

-- 둘레의 은은한 고리 (원들을 잇는 길)
for i = 0, 47 do
	local angle = i / 48 * math.pi * 2
	make("Frame", {
		Size = UDim2.new(0, 4, 0, 4), AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0,
		Position = UDim2.new(0, RING_CX + math.cos(angle) * RING_RX, 0, RING_CY + math.sin(angle) * RING_RY),
		BackgroundColor3 = Color3.fromRGB(255, 200, 130), BackgroundTransparency = 0.6,
	}, panel)
end

-- 가운데 네모: 고른 효과
local box = make("Frame", {
	Size = UDim2.new(0, BOX_W, 0, BOX_H), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, RING_CX, 0, RING_CY),
	BackgroundColor3 = Color3.fromRGB(34, 30, 50), BorderSizePixel = 0, ZIndex = 2,
}, panel)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, box)
local boxStroke = make("UIStroke", { Color = Color3.fromRGB(255, 190, 110), Thickness = 2, Transparency = 0.2 }, box)
local boxIcon = label({ Size = UDim2.new(0, 34, 0, 34), Position = UDim2.new(0, 8, 0, 6), Text = "", TextSize = 24, ZIndex = 3 }, box)
local boxTitle = label({ Size = UDim2.new(1, -52, 0, 34), Position = UDim2.new(0, 46, 0, 6), Text = "", TextSize = 12, RichText = true, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }, box)
local boxBody = label({
	Size = UDim2.new(1, -16, 1, -94), Position = UDim2.new(0, 8, 0, 44), Text = "", TextSize = 10, RichText = true, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.fromRGB(205, 210, 235), ZIndex = 3,
}, box)
local selectedZone = 1
local toggleButton = button({ Size = UDim2.new(0.5, -12, 0, 38), Position = UDim2.new(0, 8, 1, -46), BackgroundColor3 = Color3.fromRGB(62, 64, 84), Text = "", TextSize = 12 }, box, function()
	Remotes.Aug:FireServer("Toggle", selectedZone)
end)
toggleButton.ZIndex = 3
local buyButton = button({ Size = UDim2.new(0.5, -8, 0, 38), Position = UDim2.new(0.5, 0, 1, -46), BackgroundColor3 = Color3.fromRGB(140, 104, 40), Text = "", TextSize = 10 }, box, function()
	Remotes.Aug:FireServer("Buy", selectedZone)
end)
buyButton.ZIndex = 3
buyButton.TextWrapped = true

local refresh -- (아래에서 정의)
local rows = {}
for zone = 1, ZONES do
	local attr = Config.Sets.ZoneAug[zone]
	local info = Config.AugInfo[attr]
	local angle = -math.pi / 2 + (zone - 1) / ZONES * math.pi * 2 -- 맨 위부터 시계 방향
	local cx, cy = RING_CX + math.cos(angle) * RING_RX, RING_CY + math.sin(angle) * RING_RY
	local orb = make("Frame", {
		Size = UDim2.new(0, ORB, 0, ORB), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, cx, 0, cy),
		BackgroundColor3 = Color3.fromRGB(36, 34, 52), BorderSizePixel = 0, ZIndex = 3,
	}, panel)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, orb)
	local icon = label({ Size = UDim2.new(1, 0, 1, 0), Text = info.Icon, TextSize = 28, ZIndex = 4 }, orb)
	local zoneTag = label({
		Size = UDim2.new(0, 22, 0, 22), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.15, 0, 0.15, 0), BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(60, 50, 80), Text = tostring(zone), TextSize = 11, Font = Enum.Font.GothamBlack, ZIndex = 5,
	}, orb)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, zoneTag)
	local levelTag = label({
		Size = UDim2.new(0, 34, 0, 16), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, 0), BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(30, 26, 44), Text = "", TextSize = 10, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 225, 120), ZIndex = 5,
	}, orb)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, levelTag)
	local caption = label({
		Size = UDim2.new(0, 120, 0, 14), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0, cx, 0, cy + ORB / 2 + 10),
		Text = info.Name, TextSize = 11, ZIndex = 4, TextTruncate = Enum.TextTruncate.AtEnd,
	}, panel)
	-- 켜져 있으면 테두리가 효과 색으로 빛나며 천천히 도는 띠가 된다. 고른 원은 흰 고리
	local rowStroke = make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Transparency = 1 }, orb)
	local gradient = make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, info.Color),
			ColorSequenceKeypoint.new(0.3, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.6, info.Color:Lerp(Color3.new(0, 0, 0), 0.55)),
			ColorSequenceKeypoint.new(1, info.Color),
		}),
	}, rowStroke)
	local selRing = make("Frame", { Size = UDim2.new(0, ORB + 12, 0, ORB + 12), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, cx, 0, cy), BackgroundTransparency = 1, ZIndex = 2, Visible = false }, panel)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, selRing)
	make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Transparency = 0.15 }, selRing)
	local hit = make("TextButton", { Size = UDim2.new(0, ORB + 30, 0, ORB + 34), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, cx, 0, cy + 10), BackgroundTransparency = 1, Text = "", ZIndex = 8 }, panel)
	hit.Activated:Connect(function()
		selectedZone = zone
		refresh()
	end)
	rows[zone] = { Orb = orb, Icon = icon, Level = levelTag, Caption = caption, Stroke = rowStroke, Gradient = gradient, Sel = selRing }
end

local function roleLine(attrKey)
	local role = Config.AugRoles and Config.AugRoles[attrKey]
	if not role then return nil end
	local names = {}
	for _, key in ipairs(role.Weapons) do
		local w = Config.WeaponTypes[key]
		table.insert(names, w and w.Name or key)
	end
	local match = Config.AugWeaponMatch(player, attrKey)
	return string.format("<b>%s</b>  ·  %s🔫 %s%s</font>",
		Config.AugRoleLabel[role.Role], match and "<font color='#78ff8c'>✔ " or "<font color='#c8cce0'>", table.concat(names, " / "), match and " (+40%)" or "")
end

function refresh()
	local gold = player:GetAttribute("Gold") or 0
	local slots = player:GetAttribute("AugSlots") or 1
	local used, affordable = 0, 0
	for zone = 1, ZONES do
		local open = player:GetAttribute("AugOpenZ_" .. zone) == true
		local level = player:GetAttribute("AugLvZ_" .. zone) or 0
		local gear = player:GetAttribute("AugGearZ_" .. zone) or 0
		local on = player:GetAttribute("AugOnZ_" .. zone) == true
		local r = rows[zone]
		if on then used += 1 end
		local info = Config.AugInfo[Config.Sets.ZoneAug[zone]]
		r.Orb.BackgroundColor3 = not open and Color3.fromRGB(28, 26, 38) or (on and info.Color:Lerp(Color3.fromRGB(20, 18, 30), 0.45) or Color3.fromRGB(44, 40, 62))
		r.Icon.Text = open and info.Icon or "🔒"
		r.Icon.TextTransparency = open and 0 or 0.3
		r.Level.Text = level + gear > 0 and ("Lv." .. (level + gear)) or ""
		r.Level.Visible = level + gear > 0
		r.Caption.TextColor3 = on and Color3.fromRGB(150, 255, 190) or (open and Color3.fromRGB(255, 240, 200) or Color3.fromRGB(130, 134, 156))
		r.Stroke.Transparency = on and 0.05 or (open and 0.6 or 0.85)
		r.Sel.Visible = zone == selectedZone
		if open and level == 0 and gold >= Config.Sets.AugCost(zone, 1) then affordable += 1 end
	end

	-- 가운데 네모: 고른 효과
	local zone = selectedZone
	local attr = Config.Sets.ZoneAug[zone]
	local info = Config.AugInfo[attr]
	local open = player:GetAttribute("AugOpenZ_" .. zone) == true
	local level = player:GetAttribute("AugLvZ_" .. zone) or 0
	local gear = player:GetAttribute("AugGearZ_" .. zone) or 0
	local on = player:GetAttribute("AugOnZ_" .. zone) == true
	boxIcon.Text = info.Icon
	boxStroke.Color = on and info.Color or Color3.fromRGB(255, 190, 110)
	boxTitle.Text = string.format("%sZone %d · %s  %s", on and "<font color='#78ffb4'>●</font> " or "", zone, info.Name,
		level > 0 and (gear > 0 and string.format("[Lv.%d + gear %d = %d]", level, gear, level + gear) or ("[Lv." .. level .. "]")) or "")
	local lines = { "<font color='#aaf0c8'>" .. info.Desc .. "</font>" }
	local role = roleLine(attr)
	if role then table.insert(lines, role) end
	-- 단계 수치: 지금 단계와 다음 단계만 (전부 보이면 네모가 넘친다)
	local atk = Config.BaseAttackEstimate and Config.BaseAttackEstimate(player) or 0
	local now = level + gear
	for l = math.max(1, now), math.min(6, math.max(1, now) + 1) do
		local text, mult = Config.AugLevelLine(attr, l)
		local dmg = mult and atk > 0 and string.format("  <font color='#ffd966'>≈ %d dmg</font>", math.floor(atk * mult + 0.5)) or ""
		local line = string.format("Lv.%d  %s%s", l, text, dmg)
		if l == now then line = "<font color='#78ff8c'><b>▶ " .. line .. "  (now)</b></font>" end
		table.insert(lines, line)
	end
	boxBody.Text = table.concat(lines, "\n")
	toggleButton.Text = on and "● ON" or "○ OFF"
	toggleButton.BackgroundColor3 = on and Color3.fromRGB(46, 112, 84) or Color3.fromRGB(62, 64, 84)
	toggleButton.TextColor3 = on and Color3.fromRGB(190, 255, 215) or Color3.fromRGB(170, 174, 200)
	toggleButton.Visible = open
	if not open then
		buyButton.Text = string.format("🔒 Defeat the Zone %d lord", zone)
		buyButton.BackgroundColor3 = Color3.fromRGB(60, 62, 80)
		buyButton.Size = UDim2.new(1, -16, 0, 38)
		buyButton.Position = UDim2.new(0, 8, 1, -46)
	else
		buyButton.Size = UDim2.new(0.5, -8, 0, 38)
		buyButton.Position = UDim2.new(0.5, 0, 1, -46)
		if level >= 3 then
			buyButton.Text = "Max level"
			buyButton.BackgroundColor3 = Color3.fromRGB(60, 62, 80)
		else
			local cost = Config.Sets.AugCost(zone, level + 1)
			buyButton.Text = string.format("%s %s G", level == 0 and "Activate" or "Upgrade", commas(cost))
			buyButton.BackgroundColor3 = gold >= cost and Color3.fromRGB(150, 110, 40) or Color3.fromRGB(80, 74, 66)
		end
	end
	slotLabel.Text = string.format("Active %d / %d slots   (💰 %s G)", used, slots, commas(gold))
	pill.Visible = false -- (왼쪽 메뉴 버튼 줄의 "세트" 버튼과 빨간 점이 대신한다: 창 위에 떠서 겹치던 버튼)
	badge.Visible = affordable > 0 and used < slots
end

for _, name in ipairs({ "Gold", "AugSlots", "TutorialActive", "WeaponType", "WeaponLevel" }) do
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
		if r.Stroke.Transparency < 0.5 then -- (켜진 원만)
			r.Gradient.Rotation = (t * 110 + zone * 40) % 360
			r.Stroke.Thickness = 3 + 0.8 * math.sin(t * 3 + zone)
		end
	end
end)

pill.Activated:Connect(function() panel.Visible = not panel.Visible end)

-- 처음 세트 효과가 열리면 버튼이 빛나고 "Press Y!" 말풍선이 뜬다. 한 번 열어 보면 서버에 기록되어 다시 안 뜬다 (HintDone_SetsOpened)
local callout = label({
	Size = UDim2.new(0, 96, 0, 18), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -3),
	BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(255, 190, 110), TextColor3 = Color3.fromRGB(40, 28, 10),
	Text = "▼ Press Y!", TextSize = 11, Visible = false, ZIndex = 6,
}, pill)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, callout)
local pillStroke = pill:FindFirstChildOfClass("UIStroke")
RunService.Heartbeat:Connect(function()
	local hinting = pill.Visible and not player:GetAttribute("HintDone_SetsOpened")
	callout.Visible = hinting
	if pillStroke then pillStroke.Thickness = hinting and (2 + 1.6 * (0.5 + 0.5 * math.sin(os.clock() * 4))) or 1.5 end
end)
panel:GetPropertyChangedSignal("Visible"):Connect(function()
	if panel.Visible and not player:GetAttribute("HintDone_SetsOpened") then
		player:SetAttribute("HintDone_SetsOpened", true) -- 바로 멈추게 여기서도 켠다 (서버가 저장한다)
		Remotes.Tutorial:FireServer("SetsOpened")
	end
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Y then panel.Visible = not panel.Visible end
end)
player:GetAttributeChangedSignal("OpenAug"):Connect(function() panel.Visible = not panel.Visible end) -- 왼쪽 메뉴 버튼(MenuDockClient)

-- 큰 창은 한 번에 하나만: 세트 효과 창을 열면 메뉴 창을 닫고, 메뉴 창을 열면 세트 효과 창을 닫는다 (두 창이 겹쳐 떠 있었다)
task.spawn(function()
	local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD", 30)
	local menu = hud and hud:WaitForChild("MenuPanel", 30)
	if not menu then return end
	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if panel.Visible and menu.Visible then menu.Visible = false end
	end)
	menu:GetPropertyChangedSignal("Visible"):Connect(function()
		if menu.Visible and panel.Visible then panel.Visible = false end
	end)
end)

------------------------------------------------------------
-- 켜 둔 세트 효과 상태창: 필드 / 던전에서 오른쪽 위에 작게 (효과 이름 + 현재 몇 단계인지, 골드 단계 + 장비 단계)
------------------------------------------------------------
local hudBox = make("TextLabel", {
	Size = UDim2.new(0, 210, 0, 40), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 176),
	BackgroundColor3 = Color3.fromRGB(22, 24, 38), BackgroundTransparency = 0.2, BorderSizePixel = 0, Font = Enum.Font.GothamMedium,
	TextSize = 10, TextColor3 = Color3.new(1, 1, 1), RichText = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	Text = "", Visible = false, ZIndex = 3,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, hudBox)
local hudStroke = make("UIStroke", { Color = Color3.fromRGB(255, 190, 110), Thickness = 1.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Transparency = 0.4 }, hudBox)
make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 5), PaddingRight = UDim.new(0, 6) }, hudBox)

local procUntil = {} -- 효과 이름 -> 이 시각까지 "방금 발동" 표시
local function refreshHud()
	local zone = player:GetAttribute("Zone")
	local lines = { "<font color='#ffd966'><b>🌟 Set Effects</b></font>" }
	for z = 1, ZONES do
		if player:GetAttribute("AugOnZ_" .. z) == true then
			local info = Config.AugInfo[Config.Sets.ZoneAug[z]]
			local gold = player:GetAttribute("AugLvZ_" .. z) or 0
			local gear = player:GetAttribute("AugGearZ_" .. z) or 0
			local fired = (procUntil[Config.Sets.ZoneAug[z]] or 0) > os.clock() -- 방금 발동한 효과는 노랗게 켜진다
			table.insert(lines, string.format("%s%s %s  <font color='#8fe0ff'><b>Lv.%d</b></font>%s", fired and "<font color='#ffff70'><b>▶ </b></font>" or "", info.Icon, fired and ("<font color='#ffff70'><b>" .. info.Name .. "</b></font>") or info.Name, gold + gear,
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
	BackgroundColor3 = Color3.fromRGB(26, 28, 42), BackgroundTransparency = 0.25, Font = Enum.Font.GothamBold, TextSize = 11,
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
		corner.Text = string.format("%s <b>%s</b>  <font size='9' color='#ffd966'>Zone %d · Trial Lv.3</font>\n<font size='9' color='#c8d0e8'>%s</font>", info.Icon, info.Name, zone, info.Desc)
		cornerStroke.Color = info.Color
	end
end
player:GetAttributeChangedSignal("AugDemo"):Connect(refreshCorner)
player:GetAttributeChangedSignal("Zone"):Connect(refreshCorner)

local function playRollCompact(pick)
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
	label({ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 0, 6), Text = "🎲 This Dungeon's Trial Effect", TextSize = 12, ZIndex = 61 }, box)
	local icon = label({ Size = UDim2.new(0, 60, 0, 44), Position = UDim2.new(0, 14, 0, 32), Text = "?", TextSize = 29, ZIndex = 61 }, box)
	local name = label({ Size = UDim2.new(1, -88, 0, 44), Position = UDim2.new(0, 78, 0, 32), Text = "", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, RichText = true, ZIndex = 61 }, box)
	local detail = label({ Size = UDim2.new(1, -24, 0, 40), Position = UDim2.new(0, 12, 0, 80), Text = "", TextSize = 10, TextWrapped = true, TextColor3 = Color3.fromRGB(200, 208, 232), Font = Enum.Font.GothamMedium, ZIndex = 61 }, box)
	local startedAt = os.clock()
	while os.clock() - startedAt < 1.3 do
		local info = Config.AugInfo[Config.Sets.ZoneAug[math.random(#Config.Sets.ZoneAug)]]
		icon.Text, name.Text = info.Icon, info.Name
		name.TextColor3 = Color3.fromRGB(170, 175, 205)
		task.wait(0.07)
	end
	local winZone = table.find(Config.Sets.ZoneAug, pick) or 0
	icon.Text, name.Text = winner.Icon, string.format("%s\n<font size='10' color='#ffd966'>Zone %d set effect · Trial Lv.3</font>", winner.Name, winZone)
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

-- 튜토리얼 던전(처음 체험): 세트 효과 8개를 한 줄로 쭉 늘어놓고, 커서가 빠르게 훑다가 천천히 멈추며 하나가 "선택된다".
-- "세트 효과라는 게 구역마다 하나씩 8가지가 있구나" 를 알려 주는 안내를 겸한다.
local function tick(key, volume)
	pcall(function() if SoundBank.Has(key) then SoundBank.Play(game:GetService("SoundService"), key, { Volume = volume or 0.6 }) end end)
end
local function playRollFull(pick)
	local winner = Config.AugInfo[pick]
	if not winner then return end
	corner:SetAttribute("Rolling", true)
	corner.Visible = false
	local phoneLayout = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	local cols = phoneLayout and 4 or 8
	local rows = 8 // cols
	local cardW, cardH, gap = 64, 86, 6
	local panelW = cols * cardW + (cols + 1) * gap + 20
	local panelH = 78 + rows * (cardH + gap) + 96
	local box = make("CanvasGroup", {
		Size = UDim2.new(0, panelW, 0, panelH), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.09, 0),
		BackgroundColor3 = Color3.fromRGB(22, 24, 38), BackgroundTransparency = 0.04, BorderSizePixel = 0, ZIndex = 60, GroupTransparency = 1,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 14) }, box)
	local stroke = make("UIStroke", { Color = Color3.fromRGB(190, 168, 110), Thickness = 2 }, box)
	label({ Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0, 10), Text = "✨ SET EFFECTS", TextSize = 18, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(235, 215, 160), ZIndex = 61 }, box)
	label({ Size = UDim2.new(1, -24, 0, 34), Position = UDim2.new(0, 12, 0, 36), Text = "8 effects, one for every zone. Defeat a zone's Lord and collect its gear to make that effect stronger. Here is one to try!", TextSize = 11, TextWrapped = true, TextColor3 = Color3.fromRGB(190, 196, 220), Font = Enum.Font.GothamMedium, ZIndex = 61 }, box)
	local cards = {}
	for index = 1, 8 do
		local info = Config.AugInfo[Config.Sets.ZoneAug[index]]
		local col, row = (index - 1) % cols, (index - 1) // cols
		local card = make("Frame", {
			Size = UDim2.new(0, cardW, 0, cardH), Position = UDim2.new(0, 10 + gap + col * (cardW + gap), 0, 78 + row * (cardH + gap)),
			BackgroundColor3 = Color3.fromRGB(34, 36, 56), BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 61,
		}, box)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, card)
		local cardStroke = make("UIStroke", { Color = Color3.fromRGB(70, 74, 104), Thickness = 1.5 }, card)
		local scale = make("UIScale", { Scale = 1 }, card)
		local zoneText = label({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 4), Text = "ZONE " .. index, TextSize = 9, TextColor3 = Color3.fromRGB(150, 156, 184), ZIndex = 62 }, card)
		local iconText = label({ Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 20), Text = info.Icon, TextSize = 28, ZIndex = 62 }, card)
		local nameText = label({ Size = UDim2.new(1, -6, 0, 26), Position = UDim2.new(0, 3, 0, 56), Text = info.Name, TextSize = 9, TextWrapped = true, TextColor3 = Color3.fromRGB(205, 210, 232), ZIndex = 62 }, card)
		cards[index] = { Card = card, Stroke = cardStroke, Scale = scale, Texts = { zoneText, iconText, nameText }, Color = info.Color }
	end
	local function setState(index, state)
		local c = cards[index]
		if not c then return end
		local active = state == "hover" or state == "win"
		c.Card.BackgroundTransparency = state == "dim" and 0.6 or (active and 0 or 0.1)
		c.Card.BackgroundColor3 = state == "win" and c.Color:Lerp(Color3.fromRGB(34, 36, 56), 0.65) or Color3.fromRGB(34, 36, 56)
		c.Stroke.Color = state == "win" and c.Color or (state == "hover" and Color3.fromRGB(255, 217, 102) or Color3.fromRGB(70, 74, 104))
		c.Stroke.Thickness = state == "win" and 4 or (state == "hover" and 3 or 1.5)
		c.Scale.Scale = state == "win" and 1.14 or (state == "hover" and 1.08 or 1)
		for _, text in ipairs(c.Texts) do text.TextTransparency = state == "dim" and 0.65 or 0 end
	end
	local nameLine = label({ Size = UDim2.new(1, -20, 0, 24), Position = UDim2.new(0, 10, 0, panelH - 92), Text = "", TextSize = 16, Font = Enum.Font.GothamBlack, ZIndex = 61, RichText = true }, box)
	local descLine = label({ Size = UDim2.new(1, -28, 0, 38), Position = UDim2.new(0, 14, 0, panelH - 66), Text = "", TextSize = 11, TextWrapped = true, TextColor3 = Color3.fromRGB(200, 208, 232), Font = Enum.Font.GothamMedium, ZIndex = 61 }, box)
	local hintLine = label({ Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 10, 1, -26), Text = "", TextSize = 10, TextColor3 = Color3.fromRGB(255, 217, 102), ZIndex = 61 }, box)
	TweenService:Create(box, TweenInfo.new(0.35), { GroupTransparency = 0 }):Play()
	task.wait(0.9) -- 8개를 먼저 훑어볼 시간

	local winIndex = table.find(Config.Sets.ZoneAug, pick) or 1
	local startIndex = math.random(8)
	local steps = 16 + ((winIndex - startIndex) % 8) + 1 -- 두 바퀴를 돌고 정확히 뽑힌 칸에서 멈춘다
	local previous
	for i = 1, steps do
		local index = ((startIndex - 1 + i - 1) % 8) + 1
		if previous then setState(previous, "idle") end
		setState(index, "hover")
		previous = index
		tick("Gacha_Tick", 0.5)
		task.wait(0.045 + 0.24 * (i / steps) ^ 3) -- 처음엔 빠르게, 끝에서 천천히
	end
	for index = 1, 8 do setState(index, index == winIndex and "win" or "dim") end
	stroke.Color = winner.Color
	nameLine.Text = string.format("%s  %s", winner.Icon, winner.Name)
	nameLine.TextColor3 = winner.Color
	descLine.Text = winner.Desc
	hintLine.Text = string.format("Zone %d set effect · Trial Lv.3 — for this dungeon only", winIndex)
	tick("Rare_Drop", 0.8)
	task.wait(3.6)
	TweenService:Create(box, TweenInfo.new(0.4), { GroupTransparency = 1 }):Play()
	task.wait(0.45)
	box:Destroy()
	corner:SetAttribute("Rolling", nil)
	refreshCorner()
end

local function playRoll(pick)
	if player:GetAttribute("TutorialDungeonRun") == true then
		playRollFull(pick)
	else
		playRollCompact(pick)
	end
end

-- 세트 효과가 발동했을 때: 조준점 아래에 이름 팝업이 떠올랐다 사라지고, 오른쪽 위 목록의 그 효과가 잠깐 노랗게 켜지며 상자 테두리가 번쩍인다
local procLabels = {}
-- 발동 체감: 내 발밑에 그 효과 색의 고리가 퍼지고, 효과가 터진 자리 위로 아이콘이 떠오른다 (은은하게: 반투명 / 짧게). 저사양 모드면 생략
local procFolder = Instance.new("Folder")
procFolder.Name = "AugProcFx"
procFolder.Parent = workspace
local function procWorldFx(info, position)
	if player:GetAttribute("LowSpec") then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		local ring = Instance.new("Part")
		ring.Shape = Enum.PartType.Cylinder
		ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
		ring.Material = Enum.Material.Neon
		ring.Color = info.Color:Lerp(Color3.fromRGB(40, 40, 50), 0.25)
		ring.Transparency = 0.5
		ring.Size = Vector3.new(0.2, 3, 3)
		ring.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = procFolder
		TweenService:Create(ring, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.2, 15, 15), Transparency = 1 }):Play()
		task.delay(0.45, function() ring:Destroy() end)
	end
	if typeof(position) == "Vector3" then
		local anchor = Instance.new("Part")
		anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.Position = position + Vector3.new(0, 5, 0)
		anchor.Parent = procFolder
		local board = Instance.new("BillboardGui")
		board.Size = UDim2.new(0, 54, 0, 54)
		board.AlwaysOnTop = true
		board.MaxDistance = 160
		board.Parent = anchor
		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.new(1, 0, 1, 0)
		icon.BackgroundTransparency = 1
		icon.Text = info.Icon
		icon.TextScaled = true
		icon.Font = Enum.Font.GothamBlack
		icon.Parent = board
		TweenService:Create(anchor, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = anchor.Position + Vector3.new(0, 5, 0) }):Play()
		task.delay(0.4, function() TweenService:Create(icon, TweenInfo.new(0.4), { TextTransparency = 1 }):Play() end)
		task.delay(0.85, function() anchor:Destroy() end)
	end
end

local lastProcPop = 0
local function showProc(attr, position)
	local info = Config.AugInfo[attr]
	if not info then return end
	procWorldFx(info, position)
	if os.clock() - lastProcPop < 1.4 then return end -- 화면 가운데 "충격파 샷!" 같은 글자는 1.4초에 한 번만 (세트 효과가 계속 터져서 글자가 쉴 새 없이 떴다. 효과 자체의 연출은 그대로)
	lastProcPop = os.clock()
	if player:GetAttribute("ModalOpen") then return end -- 메뉴 같은 큰 창이 열려 있으면 화면 가운데 글자를 띄우지 않는다 (창 위에 겹쳐 보였다)
	procUntil[attr] = os.clock() + 0.5
	refreshHud()
	task.delay(0.55, refreshHud)
	hudStroke.Thickness = 3
	hudStroke.Transparency = 0
	TweenService:Create(hudStroke, TweenInfo.new(0.5), { Thickness = 1.2, Transparency = 0.4 }):Play()
	local slot = #procLabels
	local pop = label({
		Size = UDim2.new(0, 260, 0, 26), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.64, 26 * slot), Text = info.Icon .. "  " .. info.Name .. "!",
		TextSize = 17, TextColor3 = info.Color:Lerp(Color3.new(1, 1, 1), 0.35), TextStrokeTransparency = 0.35, TextStrokeColor3 = Color3.fromRGB(10, 10, 20), ZIndex = 40,
	}, gui)
	table.insert(procLabels, pop)
	local scale = make("UIScale", { Scale = 0.6 }, pop)
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.25, function()
		TweenService:Create(pop, TweenInfo.new(0.5), { Position = pop.Position - UDim2.new(0, 0, 0, 28), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	task.delay(0.8, function()
		local at = table.find(procLabels, pop)
		if at then table.remove(procLabels, at) end
		pop:Destroy()
	end)
end

Remotes.Aug.OnClientEvent:Connect(function(action, pick, extra)
	if action == "Demo" then task.spawn(playRoll, pick)
	elseif action == "Proc" then showProc(pick, extra) end
end)
refreshCorner()
