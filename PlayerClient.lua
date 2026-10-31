-- PlayerClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript)
-- 3인칭 시점. 마우스(또는 터치) 방향으로 공격하고, 상황에 따라 UI가 바뀐다.
--   로비   : 파티 패널(초대/수락/추방/나가기), 무기 강화창, 게이트 안내
--   던전   : 웨이브 정보, 보스 체력바, 스탯 분배 패널(숫자키 1/2/3), 결과 화면
-- UI 구역은 서버가 설정하는 플레이어 Attribute "Zone"("Lobby" / "Dungeon")으로 전환된다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))
local sfxParent = game:GetService("SoundService")
local ENH_VOLUME = 0.7 -- 강화 소리(망치 / 성공 / 실패 / 진화)가 너무 크다는 의견: 30% 줄임
local function enhSound(key, opts)
	opts = opts or {}
	opts.Volume = (opts.Volume or 1) * ENH_VOLUME
	return SoundBank.Play(sfxParent, key, opts)
end

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

task.spawn(function()
	for _ = 1, 10 do
		local okBag = pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
		local okHealth = pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Health, false) -- 오른쪽 위 기본 체력바는 숨긴다 (발밑 체력바 / 낮을 때 붉은 화면 / 상태 카드로 충분)
		local okList = pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, false) -- 오른쪽 위 Roblox 기본 플레이어 목록(Gold / Tickets / Lv / Weapon 표)도 숨긴다: 우리 전투력 랭킹 / 상점 버튼과 겹쳤다
		if okBag and okHealth and okList then
			break
		end
		task.wait(0.5)
	end
end)

local function create(className, props, parent)
	local instance = Instance.new(className)
	for key, value in pairs(props) do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function rounded(instance, radius)
	create("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, instance)
end

local Theme = require(ReplicatedStorage:WaitForChild("UiTheme")) -- 사탕 느낌 공통 색 / 모양
local function makePanel(props, parent)
	local base = {
		BackgroundColor3 = Theme.PANEL,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	local frame = create("Frame", base, parent)
	rounded(frame, (not props.BackgroundColor3 or (props.Size and props.Size.Y.Offset >= 100)) and 12 or 8)
	if not props.BackgroundColor3 then
		Theme.panelLook(frame)
	end
	return frame
end

local function makeLabel(props, parent)
	local base = {
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(240, 242, 250),
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextWrapped = true,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	if base.TextSize < 12 then base.TextSize = 10 end -- 작은 글씨 하한(모바일)
	return create("TextLabel", base, parent)
end

local function makeButton(props, parent, onClick)
	local base = {
		BackgroundColor3 = Color3.fromRGB(62, 96, 196),
		TextColor3 = Color3.fromRGB(240, 242, 250),
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		AutoButtonColor = true,
		BorderSizePixel = 0,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	local button = create("TextButton", base, parent)
	rounded(button, 10)
	Theme.glossy(button)
	if button.TextSize < 12 then button.TextSize = 10 end
	local hs = create("UIStroke", { Color = Color3.fromRGB(230, 236, 255), Thickness = 1.5, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button) -- 마우스 올리면 테두리
	button.MouseEnter:Connect(function() hs.Transparency = 0.55 end)
	button.MouseLeave:Connect(function() hs.Transparency = 1 end)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

local function clearChildren(container)
	for _, child in ipairs(container:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local GREEN = Color3.fromRGB(56, 156, 98)
local RED = Color3.fromRGB(196, 78, 82)
local GRAY = Color3.fromRGB(54, 58, 82)

local gui = create("ScreenGui", { Name = "HUD", ResetOnSpawn = false, IgnoreGuiInset = true }, player:WaitForChild("PlayerGui"))

local infoPanel = makePanel({ Size = UDim2.new(0, 240, 0, 176), Position = UDim2.new(0, 16, 0, 60), Visible = false }, gui)
local infoLabel = makeLabel({
	Size = UDim2.new(1, -20, 1, -16),
	Position = UDim2.new(0, 10, 0, 8),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	RichText = true,
	AutoLocalize = false, -- 숫자가 계속 바뀌는 긴 글자(레벨 / 골드 / 전투력 ...): 번역 표에 수없이 쌓이고 한도를 쓰는 걸 막는다 (로블록스 글자 캡처가 "too long" 으로 거부하던 글자)
}, infoPanel)

local xpBack = create("Frame", {
	Size = UDim2.new(1, -20, 0, 7), Position = UDim2.new(0, 10, 1, -14),
	BackgroundColor3 = Color3.fromRGB(45, 45, 60), BorderSizePixel = 0,
}, infoPanel)
rounded(xpBack, 4)
local xpFill = create("Frame", {
	Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(110, 200, 255), BorderSizePixel = 0,
}, xpBack)
rounded(xpFill, 4)

local toastLabel = makeLabel({
	Name = "ToastLabel", Size = UDim2.new(0, 400, 0, 74),
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, -430, 1, -250),
	BackgroundColor3 = Color3.fromRGB(16, 18, 30),
	BackgroundTransparency = 0.08,
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Visible = false,
	ZIndex = 60, -- 큰 창(메뉴 등) 위에 보이게
}, gui)
create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 10) }, toastLabel)
create("UIStroke", { Color = Color3.fromRGB(225, 196, 118), Thickness = 1.5, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, toastLabel)
rounded(toastLabel, 12)

local toast -- (상태는 do 블록 안에: PlayerClient 는 맨 바깥 지역 변수가 200개 한도에 닿아 있다)
do
	local toastToken = 0
	local lastToast, toastRepeat = nil, 1
	local toastCount = makeLabel({
		Size = UDim2.new(0, 44, 0, 22), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 6, 0, -8), BackgroundColor3 = Color3.fromRGB(255, 200, 70), BackgroundTransparency = 0,
		Font = Enum.Font.GothamBlack, TextSize = 13, TextColor3 = Color3.fromRGB(40, 24, 0), TextStrokeTransparency = 1, Visible = false, ZIndex = 61, AutoLocalize = false,
	}, toastLabel)
	rounded(toastCount, 11)
	toast = function(text)
		-- 같은 알림이 떠 있는 동안 또 오면 새로 띄우지 않고 "x2, x3..." 만 붙인다 (같은 글이 연달아 깜빡이며 화면을 덮던 것)
		if toastLabel.Visible and text == lastToast then
			toastRepeat += 1
			toastCount.Text = "x" .. toastRepeat -- (글자에 붙이면 번역이 깨져서 오른쪽 위 작은 배지로)
			toastCount.Visible = true
			return
		end
		lastToast, toastRepeat = text, 1
		toastCount.Visible = false
		toastToken += 1
		local token = toastToken
		local base = (player:GetAttribute("Zone") == "Dungeon") and 210 or 112
		local pg = gui.Parent
		local cy = pg:GetAttribute(player:GetAttribute("SidePromptUp") and "UiToastYUp" or "UiToastY")
		local y = cy or -(base + 138)
		local tx = cy and pg:GetAttribute("UiToastX") or 14
		toastLabel.Text = text
		toastLabel.Visible = true
		if pg:GetAttribute("UiCompact") ~= true then
			-- 큰 화면: 알림은 위쪽 가운데(접속자 표시 / 보스 시간 표시 아래)에서 내려온다: 왼쪽 메뉴 버튼 줄 / 미션 카드와 겹치지 않는다
			-- (메뉴가 열려 있으면 메뉴 윗부분을 가리지 않게 메뉴 바로 위에 띄운다)
			local targetY = 160
			for _, name in ipairs({ "MenuPanel", "EnhancePanel" }) do -- (메뉴 / 강화 창이 열려 있으면 그 창 윗부분을 가리지 않게 창 바로 위에)
				local window = gui:FindFirstChild(name)
				if window and window.Visible then targetY = math.max(4, math.min(targetY, window.AbsolutePosition.Y - 82)) end
			end
			toastLabel.AnchorPoint = Vector2.new(0.5, 0)
			toastLabel.Position = UDim2.new(0.5, 0, 0, -90)
			TweenService:Create(toastLabel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, targetY) }):Play()
		else
			toastLabel.AnchorPoint = Vector2.new(0, 1)
			toastLabel.Position = UDim2.new(0, -430, 1, y)
			TweenService:Create(toastLabel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0, tx, 1, y) }):Play()
		end
		local hold = string.sub(text, 1, 3) == "⚠" and 7 or math.clamp(#text / 14, 4, 7) -- 경고 / 긴 안내는 더 오래 보여 준다
		task.delay(hold, function()
			if token == toastToken then
				toastLabel.Visible = false
			end
		end)
	end
end

Remotes.Notify.OnClientEvent:Connect(toast)

local function currentZone()
	return player:GetAttribute("Zone") or "Lobby"
end

local function weaponText(level)
	local tier = Config.GetWeaponTier(level)
	return Config.FormatWeapon(level, player:GetAttribute("WeaponType")), tier.Color
end

local enhancePanel
local refreshEnhance
local resetEnhanceView -- 블록 밖(왼쪽 무기 버튼 신호)에서도 쓰는 "결과 글자 비우기"
do
-- 무기 강화 창: 둥근 다이얼. 위에 무기 구슬(+N), 가운데 성공 확률 링, 아래 재료 칸(필요 골드 / 가진 골드), 맨 아래 강화 버튼.
local E = {}
local PW, PH = 440, 644
local DX, DY = PW / 2, 300 -- 다이얼 중심
enhancePanel = makePanel({
	Name = "EnhancePanel", -- (EnhanceResultClient 가 이 창 위에 결과 카드를 그린다)
	Size = UDim2.new(0, PW, 0, PH), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(18, 20, 34), BackgroundTransparency = 0.05, Visible = false,
}, gui)
local rim = create("UIStroke", { Color = Color3.fromRGB(225, 196, 118), Thickness = 2, Transparency = 0.2 }, enhancePanel)
create("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(70, 48, 90), Color3.fromRGB(22, 20, 32)), Rotation = 90 }, enhancePanel)
E.RimGradient = create("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 80)), ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 120, 200)),
		ColorSequenceKeypoint.new(0.7, Color3.fromRGB(120, 200, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 80)),
	}),
}, rim)
E.Scale = create("UIScale", { Scale = 1 }, enhancePanel)
local function fitEnhance()
	local camera = workspace.CurrentCamera
	if camera then E.Scale.Scale = math.clamp((camera.ViewportSize.Y - 20) / PH, 0.45, 1) end
end
fitEnhance()
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitEnhance) end

makeLabel({ Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 8), Text = "🔨 Weapon Upgrade", Font = Enum.Font.GothamBlack, TextSize = 20, TextColor3 = Color3.fromRGB(255, 220, 130) }, enhancePanel)
makeButton({ Size = UDim2.new(0, 72, 0, 30), Position = UDim2.new(1, -84, 0, 12), Text = "Close", TextSize = 12, BackgroundColor3 = Color3.fromRGB(54, 58, 82) }, enhancePanel, function()
	enhancePanel.Visible = false
end)
local enhanceWeapon = makeLabel({ Size = UDim2.new(1, -24, 0, 24), Position = UDim2.new(0, 12, 0, 44), Font = Enum.Font.GothamBlack, TextSize = 16, RichText = true }, enhancePanel)

local function circle(size, x, y, color, z, parent)
	local f = create("Frame", { Size = UDim2.new(0, size, 0, size), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, x, 0, y), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z }, parent or enhancePanel)
	create("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
	return f
end

-- 바깥 원판 + 금테
E.Dial = circle(300, DX, DY, Color3.fromRGB(28, 24, 42), 1)
create("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 110, 150)), Rotation = 90 }, E.Dial)
E.DialStroke = create("UIStroke", { Color = Color3.fromRGB(225, 196, 118), Thickness = 4 }, E.Dial)
E.Glow = circle(340, DX, DY, Color3.fromRGB(255, 200, 90), 0)
E.Glow.BackgroundTransparency = 0.88
-- 성공 확률 링: 48칸이 시계 방향으로 켜진다
E.Segs = {}
for i = 1, 48 do
	local angle = -math.pi / 2 + (i - 0.5) / 48 * math.pi * 2
	local seg = create("Frame", {
		Size = UDim2.new(0, 8, 0, 18), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = math.deg(angle) + 90,
		Position = UDim2.new(0, DX + math.cos(angle) * 124, 0, DY + math.sin(angle) * 124), BackgroundColor3 = Color3.fromRGB(55, 50, 75), BorderSizePixel = 0, ZIndex = 2,
	}, enhancePanel)
	create("UICorner", { CornerRadius = UDim.new(0, 3) }, seg)
	E.Segs[i] = seg
end
-- 바깥을 천천히 도는 작은 별빛 점들
E.Orbit = {}
for i = 1, 12 do
	local dot = circle(i % 3 == 0 and 7 or 4, DX, DY, Color3.fromRGB(255, 225, 150), 2)
	dot.BackgroundTransparency = 0.3
	E.Orbit[i] = dot
end
-- 가운데: 성공 확률
local core = circle(150, DX, DY, Color3.fromRGB(20, 18, 32), 3)
create("UIStroke", { Color = Color3.fromRGB(225, 196, 118), Thickness = 2, Transparency = 0.3 }, core)
makeLabel({ Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, 30), Text = "Success", TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(200, 196, 225), ZIndex = 4 }, core)
E.Chance = makeLabel({ Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 0, 48), Text = "", TextSize = 38, Font = Enum.Font.GothamBlack, ZIndex = 4 }, core)
E.Damage = makeLabel({ Size = UDim2.new(1, -10, 0, 30), Position = UDim2.new(0, 5, 0, 94), Text = "", RichText = true, TextSize = 11, TextWrapped = true, Font = Enum.Font.GothamBold, ZIndex = 4 }, core)

-- 위: 무기 구슬 + 강화 수치
local medal = circle(96, DX, 120, Color3.fromRGB(34, 30, 52), 5)
create("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(120, 115, 150)), Rotation = 90 }, medal)
local medalStroke = create("UIStroke", { Color = Color3.fromRGB(255, 200, 90), Thickness = 5 }, medal)
E.MedalIcon = makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = "🔫", TextSize = 50, ZIndex = 6 }, medal)
local enhanceStage = makeLabel({
	Size = UDim2.new(0, 120, 0, 30), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, DX, 0, 172), Font = Enum.Font.GothamBlack, TextSize = 26,
	TextStrokeTransparency = 0.3, ZIndex = 7, RichText = true,
}, enhancePanel)

-- 아래: 재료 칸 (필요 골드 / 가진 골드)
local function materialOrb(x, y, title)
	local orb = circle(78, x, y, Color3.fromRGB(30, 26, 46), 5)
	local stroke = create("UIStroke", { Color = Color3.fromRGB(225, 196, 118), Thickness = 3 }, orb)
	makeLabel({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 8), Text = "💰", TextSize = 24, ZIndex = 6 }, orb)
	local value = makeLabel({ Size = UDim2.new(1, -6, 0, 18), Position = UDim2.new(0, 3, 0, 40), Text = "", TextSize = 13, Font = Enum.Font.GothamBlack, ZIndex = 6, TextScaled = false }, orb)
	makeLabel({ Size = UDim2.new(0, 110, 0, 14), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0, x, 0, y + 42), Text = title, TextSize = 10, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(190, 186, 215), ZIndex = 6 }, enhancePanel)
	return { Stroke = stroke, Value = value }
end
E.Cost = materialOrb(DX - 78, DY + 138, "Cost")
E.Owned = materialOrb(DX + 78, DY + 138, "You have")

local enhanceNext = makeLabel({ Size = UDim2.new(1, -30, 0, 18), Position = UDim2.new(0, 15, 0, 500), TextSize = 12, RichText = true, ZIndex = 6 }, enhancePanel)
local enhanceResult = makeLabel({ Size = UDim2.new(1, -24, 0, 34), Position = UDim2.new(0, 12, 0, 520), Font = Enum.Font.GothamBold, TextSize = 11, TextWrapped = true, ZIndex = 6 }, enhancePanel)
local hammer = makeLabel({
	Size = UDim2.new(0, 70, 0, 70), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 70, 0, 110),
	Text = "🔨", TextSize = 48, Visible = false, ZIndex = 9, Rotation = -50,
}, enhancePanel)

RunService.RenderStepped:Connect(function()
	if not enhancePanel.Visible then return end
	local t = os.clock()
	E.RimGradient.Rotation = (t * 60) % 360
	for i, dot in ipairs(E.Orbit) do
		local angle = t * 0.35 + i / #E.Orbit * math.pi * 2
		dot.Position = UDim2.new(0, DX + math.cos(angle) * 158, 0, DY + math.sin(angle) * 158)
	end
	E.Glow.BackgroundTransparency = 0.86 + 0.05 * math.sin(t * 2)
end)

local function manyLocked()
	return player:GetAttribute("TutorialActive") == true and player:GetAttribute("TutorialEnhanceCost") == nil
end
local function enhanceMany(count)
	if manyLocked() then
		toast("🔒 Do your first upgrades with [Upgrade] yourself! x10 / Max Upgrade unlock soon.")
		return
	end
	if E.EnhanceBusy then return end
	E.EnhanceBusy = true
	E.hammer()
	Remotes.Enhance:FireServer(count)
	task.delay(1.1, function() E.EnhanceBusy = false end)
end
-- 맨 아래 버튼 줄: [x10] [🔨 강화] [최대]
local function pill(button)
	create("UICorner", { CornerRadius = UDim.new(1, 0) }, button)
	return button
end
local enhanceTen = pill(makeButton({
	Size = UDim2.new(0, 84, 0, 56), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -14),
	Text = "x10\nUpgrade", TextSize = 13, Font = Enum.Font.GothamBold, BackgroundColor3 = Color3.fromRGB(60, 120, 200),
}, enhancePanel, function() enhanceMany(10) end))
local enhanceMax = pill(makeButton({
	Size = UDim2.new(0, 84, 0, 56), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -14),
	Text = "Max\nUpgrade", TextSize = 13, Font = Enum.Font.GothamBold, BackgroundColor3 = Color3.fromRGB(190, 110, 40),
}, enhancePanel, function() enhanceMany(50) end))
do
	local function lockMany()
		local locked = manyLocked()
		for _, button in ipairs({ enhanceTen, enhanceMax }) do
			button.AutoButtonColor = not locked
			button.BackgroundTransparency = locked and 0.6 or 0
			button.TextTransparency = locked and 0.5 or 0
		end
		enhanceTen.Text = locked and "🔒\nx10" or "x10\nUpgrade"
		enhanceMax.Text = locked and "🔒\nMax" or "Max\nUpgrade"
	end
	player:GetAttributeChangedSignal("TutorialActive"):Connect(lockMany)
	player:GetAttributeChangedSignal("TutorialEnhanceCost"):Connect(lockMany)
	lockMany()
end
local enhanceButton = pill(makeButton({
	Size = UDim2.new(0, 210, 0, 60), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12),
	Text = "Upgrade", TextSize = 17, Font = Enum.Font.GothamBlack, BackgroundColor3 = GREEN,
}, enhancePanel, function()
	if E.EnhanceBusy then return end
	E.EnhanceBusy = true
	hammer.Visible = true
	hammer.Rotation = -50
	hammer.Position = UDim2.new(0.5, 70, 0, 110)
	local swing = TweenService:Create(hammer, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Rotation = 25, Position = UDim2.new(0.5, 20, 0, 150) })
	swing:Play()
	swing.Completed:Connect(function()
		E.hammer()
		for i = 1, 8 do
			local spark = circle(8, DX, 120, i % 2 == 0 and Color3.fromRGB(255, 220, 110) or Color3.fromRGB(255, 140, 60), 8)
			local angle = (i / 8) * math.pi * 2
			TweenService:Create(spark, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0, DX + math.cos(angle) * 110, 0, 120 + math.sin(angle) * 70), BackgroundTransparency = 1,
			}):Play()
			game:GetService("Debris"):AddItem(spark, 0.5)
		end
		task.spawn(function()
			local base = medal.Position
			for i = 1, 6 do
				medal.Position = base + UDim2.new(0, (i % 2 == 0 and 1 or -1) * (8 - i), 0, 0)
				task.wait(0.03)
			end
			medal.Position = base
		end)
		Remotes.Enhance:FireServer()
		task.delay(0.15, function() hammer.Visible = false end)
		task.delay(0.9, function() E.EnhanceBusy = false end)
	end)
end))
create("UIStroke", { Color = Color3.fromRGB(190, 255, 190), ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 2.5 }, enhanceButton)
enhanceButton.ClipsDescendants = true
do
	local holding = false
	enhanceButton.MouseButton1Down:Connect(function()
		holding = true
		task.spawn(function()
			task.wait(0.45)
			while holding and enhancePanel.Visible and E.EnhanceAffordable do
				if not E.EnhanceBusy then
					E.EnhanceBusy = true
					E.hammer()
					Remotes.Enhance:FireServer()
					task.delay(0.35, function() E.EnhanceBusy = false end)
				end
				task.wait(0.1)
			end
		end)
	end)
	enhanceButton.MouseButton1Up:Connect(function() holding = false end)
	enhanceButton.MouseLeave:Connect(function() holding = false end)
end
E.Shimmer = create("Frame", {
	Size = UDim2.new(0, 36, 1.8, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(-0.2, 0, 0.5, 0), Rotation = 20,
	BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.7, BorderSizePixel = 0, ZIndex = 3,
}, enhanceButton)
task.spawn(function()
	while enhancePanel.Parent do
		if enhancePanel.Visible then
			E.Shimmer.Position = UDim2.new(-0.1, 0, 0.5, 0)
			TweenService:Create(E.Shimmer, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { Position = UDim2.new(1.1, 0, 0.5, 0) }):Play()
		end
		task.wait(2.2)
	end
end)

-- 강화 소리: 망치는 금속 "땡땡" 두 번, 결과는 한 번만 (x10 / 최대 / 꾹 누르기로 여러 번 해도 소리가 섞이지 않게)
function E.hammer()
	local now = os.clock()
	if now - (E.LastHammer or 0) < 0.3 then return end
	E.LastHammer = now
	enhSound("Enh_Hammer")
	task.delay(0.13, function() enhSound("Enh_Hammer", { Pitch = 1.12, Volume = 0.8 }) end)
end
function E.result(key, opts)
	local now = os.clock()
	if E.LastResultKey == key and now - (E.LastResultAt or 0) < 0.6 then return end -- (같은 결과가 연달아 오면 앞 소리를 그대로 둔다)
	local old = E.LastResultSound
	if old and old.Parent then -- 다른 결과 소리가 울리고 있으면 짧게 줄여 끊는다
		TweenService:Create(old, TweenInfo.new(0.08), { Volume = 0 }):Play()
		task.delay(0.1, function() if old.Parent then old:Stop() end end)
	end
	E.LastResultKey, E.LastResultAt = key, now
	E.LastResultSound = enhSound(key, opts)
end

function E.comma(n)
	return (tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local WEAPON_ICONS = { Pistol = "🔫", Smg = "🔭", Revolver = "💣", Rifle = "🏹", Shotgun = "✴", Flamer = "📖", Cannon = "🧨", Sniper = "🎯", Rocket = "🚀", Rail = "⚡" }

local function paintRing(fraction, color)
	local lit = math.floor(fraction * #E.Segs + 0.5)
	for i, seg in ipairs(E.Segs) do
		seg.BackgroundColor3 = i <= lit and color or Color3.fromRGB(55, 50, 75)
	end
end

function refreshEnhance()
	local level = player:GetAttribute("WeaponLevel") or 0
	local gold = player:GetAttribute("Gold") or 0
	local typeKey = Config.ResolveWeaponType(level, player:GetAttribute("WeaponType"))
	local tier = Config.GetLookTier(level, typeKey) -- 고른 무기 형 + 지금 시대의 외모
	local milestone = Config.GetNextMilestone(level)
	local color = tier.Rainbow and Color3.fromRGB(255, 120, 255) or tier.Color

	enhanceWeapon.Text = string.format("<b>%s</b> · <b>%s</b>", Config.GetWeaponName(typeKey, level), Config.GetEraName(tier.Era)) -- (이름 / 시대를 따로 감싸야 각각 번역된다)
	enhanceWeapon.TextColor3 = color
	medalStroke.Color = color
	E.MedalIcon.Text = WEAPON_ICONS[typeKey] or "🔫"
	medal.BackgroundColor3 = color:Lerp(Color3.fromRGB(20, 18, 32), 0.7)
	E.Glow.BackgroundColor3 = color
	E.DialStroke.Color = color:Lerp(Color3.fromRGB(225, 196, 118), 0.5)
	E.Milestone = Config.GetUnlockedCount(level) + 100 * tier.Era -- 새 무기 해금 / 새 시대 때만 "진화!" 연출
	E.EnhanceShownTier = tier.Index
	E.Owned.Value.Text = E.comma(gold)

	if level >= Config.Weapon.MaxLevel then
		enhanceStage.Text = string.format("<font color='#ffd966'>+%d MAX</font>", level)
		enhanceNext.Text = "<font color='#ffd966'>You maxed out the final weapon!</font>"
		E.Chance.Text = "MAX"
		E.Chance.TextColor3 = Color3.fromRGB(255, 217, 102)
		E.Damage.Text = string.format("⚔ x%.2f", Config.GetDamageMultiplier(level))
		paintRing(1, Color3.fromRGB(255, 217, 102))
		E.Cost.Value.Text = "—"
		enhanceButton.Text = "MAX"
		enhanceButton.BackgroundColor3 = GRAY
		E.EnhanceAffordable = false
		return
	end
	local cost = Config.GetEnhanceCost(level)
	local chance = math.floor(Config.GetEnhanceChance(level) * 100 + 0.5)
	-- 튜토리얼: 처음 3번은 무료 + 100% 성공 (서버 WeaponService 와 같은 규칙), 진화 미션은 낮은 비용 + 100%
	local freeNow = player:GetAttribute("TutorialFree") == true and level < 3
	local tutorialCost = player:GetAttribute("TutorialEnhanceCost")
	if freeNow then
		cost, chance = 0, 100
	elseif tutorialCost then
		cost, chance = math.min(cost, tutorialCost), 100
	end
	enhanceStage.Text = string.format("+%d <font color='#6ec3ff'>→</font> <font color='#78ff8c'>+%d</font>", level, level + 1)
	enhanceStage.TextColor3 = Color3.new(1, 1, 1)
	if E.LastStage and E.LastStage ~= level then
		enhanceStage.TextSize = 36
		TweenService:Create(enhanceStage, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = 26 }):Play()
	end
	E.LastStage = level
	if milestone and milestone.Kind == "Form" then
		enhanceNext.Text = string.format("▶ <b>%d more</b> to unlock <font color='#9ad7ff'><b>%s</b></font>!", milestone.Level - level, milestone.Name)
	elseif milestone then
		enhanceNext.Text = string.format("▶ <b>%d more</b> to evolve into <font color='#9ad7ff'><b>%s</b></font>!", milestone.Level - level, milestone.Name)
	else
		enhanceNext.Text = ""
	end
	local chanceColor = Color3.fromRGB(255, 90, 80):Lerp(Color3.fromRGB(110, 230, 120), math.clamp((chance / 100 - 0.35) / 0.65, 0, 1))
	E.Chance.Text = chance .. "%"
	E.Chance.TextColor3 = chanceColor
	paintRing(chance / 100, chanceColor)
	E.Damage.Text = string.format("⚔ x%.2f <font color='#78ff8c'>→ x%.2f</font>", Config.GetDamageMultiplier(level), Config.GetDamageMultiplier(level + 1))
	local affordable = gold >= cost
	E.Cost.Value.Text = freeNow and "Free!" or E.comma(cost)
	E.Cost.Value.TextColor3 = affordable and Color3.fromRGB(255, 235, 160) or Color3.fromRGB(255, 120, 110)
	E.Cost.Stroke.Color = affordable and Color3.fromRGB(225, 196, 118) or Color3.fromRGB(200, 80, 80)
	enhanceButton.Text = freeNow and "✨ Free!\nUpgrade" or "🔨 Upgrade"
	enhanceButton.BackgroundColor3 = affordable and GREEN or Color3.fromRGB(95, 60, 62)
	E.EnhanceAffordable = affordable
end

player:GetAttributeChangedSignal("TutorialFree"):Connect(function() if enhancePanel.Visible then refreshEnhance() end end)
RunService.RenderStepped:Connect(function()
	if enhancePanel.Visible and E.EnhanceAffordable and not E.EnhanceBusy then
		local pulse = 1 + 0.02 * math.sin(os.clock() * 4)
		enhanceButton.Size = UDim2.new(0, 210 + (pulse - 1) * 300, 0, 60)
	end
end)

Remotes.Enhance.OnClientEvent:Connect(function(ok, message, summary)
	local oldMilestone = E.Milestone
	refreshEnhance()
	local evolved = oldMilestone ~= nil and E.Milestone ~= nil and E.Milestone > oldMilestone
	local level = player:GetAttribute("WeaponLevel") or 0
	local tierNow = Config.GetWeaponTier(level)
	local stageFrac = (level - tierNow.MinLevel) / math.max(1, tierNow.Steps)
	if evolved then
		E.result("Enh_Evolve")
	elseif summary and summary.Attempts and summary.Attempts > 1 then -- 여러 번 강화: 한 번이라도 오르면 성공 소리 한 번, 아니면 실패 소리 한 번
		E.result((summary.Successes or 0) > 0 and "Enh_Success" or "Enh_Fail")
	elseif ok then
		E.result("Enh_Success", { Pitch = 0.95 + 0.1 * stageFrac })
	else
		E.result("Enh_Fail")
	end
	-- (결과는 EnhanceResultClient 의 카드가 크게 보여 준다) 여기서는 구슬 테두리만 번쩍
	if evolved or ok then
		medalStroke.Thickness = evolved and 12 or 9
		TweenService:Create(medalStroke, TweenInfo.new(0.6), { Thickness = 5 }):Play()
	end
	enhanceResult.Text = message
	enhanceResult.TextColor3 = ok and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 130, 130)
end)

function resetEnhanceView()
	enhanceResult.Text = ""
	E.EnhanceShownTier = nil
end

Remotes.OpenEnhance.OnClientEvent:Connect(function()
	enhanceResult.Text = ""
	E.EnhanceShownTier = nil
	refreshEnhance()
	enhancePanel.Visible = true
end)

local lastStepIndex = 0
Remotes.Tutorial.OnClientEvent:Connect(function(action, data)
	if action ~= "Step" then return end
	local advanced = data.Index > lastStepIndex and lastStepIndex > 0
	lastStepIndex = data.Index
	if advanced and data.TargetName ~= "Anvil" and enhancePanel.Visible then
		task.delay(1.2, function()
			enhancePanel.Visible = false
		end)
	end
end)
end -- (강화창 do 블록 끝)

-- 로비 뽑기 기계 창: 뽑기만 크게 보여 준다 (GachaPanel 모듈). 장비 착용 / 강화는 장비 창(캐릭터 탭)에서
local gearPanel, gearMessage, refreshGear, gachaFlash
do
	local okG, gacha = pcall(function()
		return require(ReplicatedStorage:WaitForChild("GachaPanel", 10)).Init({ Config = Config, Remotes = Remotes, TweenService = TweenService, RunService = RunService,
			create = create, makeLabel = makeLabel, makeButton = makeButton, makePanel = makePanel, rounded = rounded, player = player, gui = gui })
	end)
	if okG and gacha then
		gearPanel, gearMessage, refreshGear, gachaFlash = gacha.Panel, gacha.Message, gacha.Refresh, gacha.Flash
	else
		warn("[PlayerClient] 뽑기 창 모듈(GachaPanel) 오류: " .. tostring(gacha))
		gearPanel = create("Frame", { Visible = false }, gui)
		gearMessage = create("TextLabel", { Visible = false }, gearPanel)
		refreshGear = function() end
	end
end

Remotes.Gear.OnClientEvent:Connect(function(action, result)
	if action ~= "Result" then return end
	local color
	if result.Roll then
		color = Config.Gear.RarityColors[result.Roll.Rarity]
	else
		color = result.Ok and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 130, 130)
	end
	gearMessage.Text = result.Message
	gearMessage.TextColor3 = color
	if result.Roll and gachaFlash and gearPanel.Visible then gachaFlash(color) end
	if not result.Roll then
		enhSound("Enh_Hammer")
		task.delay(0.12, function() SoundBank.Play(sfxParent, result.Ok and "Enh_Success" or "Enh_Fail") end)
	end
	refreshGear()
end)

do
	local ICONS = { "🔱", "💥", "⚡", "🔥", "⏩", "🎯", "❤", "💚", "⭐", "💰", "🎫", "🌪" }
	local PEN_ICONS = { "🪨", "😡", "💨", "🐺", "🔫", "☠" }
	local popup = create("Frame", {
		Name = "RollPopup", Size = UDim2.new(0, 520, 0, 80), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.155, 0), -- 위쪽 HUD(버티기 막대 / 안내 줄)와 겹치지 않게 HUD 바로 아래
		BackgroundColor3 = Color3.fromRGB(18, 20, 30), BackgroundTransparency = 0.12, BorderSizePixel = 0, Visible = false, ZIndex = 75,
	}, gui)
	rounded(popup, 14)
	local popScale = create("UIScale", { Scale = 1 }, popup)
	-- 위 칸 = 좋은 것 (윗줄: 일반 스탯 강화 / 아랫줄: + 세트 효과), 아래 가는 칸 = 패널티
	local function half(color, x)
		local frame = create("Frame", { Size = UDim2.new(0.5, -9, 1, -12), Position = UDim2.new(x, x == 0 and 6 or 3, 0, 6), BackgroundColor3 = color, BackgroundTransparency = 0.78, BorderSizePixel = 0, ZIndex = 76 }, popup)
		rounded(frame, 10)
		local stroke = create("UIStroke", { Color = color, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
		local icon = makeLabel({ Size = UDim2.new(0, 44, 0, 44), Position = UDim2.new(0, 2, 0, 12), TextSize = 26, ZIndex = 77 }, frame)
		local title = makeLabel({
			Size = UDim2.new(1, -52, 0, 32), Position = UDim2.new(0, 48, 0, 3), Font = Enum.Font.GothamBlack, TextSize = 11, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 77,
		}, frame)
		local desc = makeLabel({
			Size = UDim2.new(1, -52, 0, 32), Position = UDim2.new(0, 48, 0, 36), TextSize = 10, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.fromRGB(215, 215, 230), ZIndex = 77,
		}, frame)
		return { Frame = frame, Stroke = stroke, Icon = icon, Title = title, Desc = desc }
	end
	local card = half(Color3.fromRGB(110, 210, 255), 0)
	local penCard = half(Color3.fromRGB(255, 90, 80), 0.5)
	local token = 0
	local function paint(c, icon, title, desc, color)
		c.Icon.Text, c.Title.Text, c.Desc.Text = icon, title, desc
		c.Title.TextColor3, c.Desc.TextColor3, c.Stroke.Color, c.Frame.BackgroundColor3 = color, Color3.fromRGB(215, 215, 230), color, color
	end
	Remotes.Dungeon.OnClientEvent:Connect(function(action, data)
		if action ~= "Roll" then return end
		token += 1
		local mine = token
		popup.Visible = true
		popScale.Scale = 0.6
		TweenService:Create(popScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		paint(card, "🎲", "Rolling…", "", Color3.fromRGB(150, 150, 170))
		paint(penCard, "🎲", "Rolling…", "", Color3.fromRGB(150, 150, 170))
		task.spawn(function()
			-- 주사위 돌아가는 연출: 점점 느려지며 멈춘다
			for step = 1, 12 do
				if token ~= mine then return end
				card.Icon.Text = ICONS[math.random(#ICONS)]
				penCard.Icon.Text = data.Penalty and PEN_ICONS[math.random(#PEN_ICONS)] or ICONS[math.random(#ICONS)]
				card.Title.Text = "Rolling" .. string.rep(".", step % 3 + 1)
				SoundBank.Play(sfxParent, "Gacha_Tick")
				task.wait(0.05 + step * 0.014)
			end
			if token ~= mine then return end
			local buff = data.Buff
			local setInfo = data.Set
			if (buff and buff.Special) or (setInfo and (setInfo.Completed or data.Jackpot)) then
				local flash = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 215, 120), BackgroundTransparency = 0.7, BorderSizePixel = 0, ZIndex = 74 }, gui)
				TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
				game:GetService("Debris"):AddItem(flash, 0.55)
				SoundBank.Play(sfxParent, "Gacha_Card")
				TweenService:Create(popScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.15 }):Play()
			end
			-- 좋은 칸: 윗줄 = 일반 스탯 강화, 아랫줄 = + 세트 효과
			local setLine
			if setInfo then
				local pips = {}
				for i = 1, setInfo.Max or 3 do table.insert(pips, i <= setInfo.Count and "●" or "○") end
				setLine = "+ " .. (data.Jackpot and "🌟 " or "") .. setInfo.Name .. " piece " .. table.concat(pips, " ")
				if setInfo.Completed then setLine = setLine .. string.format("   ✨ %d-piece set complete! %s Lv.%d", setInfo.Count, setInfo.EffectName or "", setInfo.Level or 1) end
			elseif data.Note then
				setLine = "+ 🏆 " .. data.Note
			else
				setLine = "" -- 세트 조각은 주사위에서 주지 않는다: 줄 자체를 비운다
			end
			local color = (buff and buff.Special) and Color3.fromRGB(255, 195, 70) or (setInfo and setInfo.Color) or Color3.fromRGB(110, 210, 255)
			if buff then
				paint(card, buff.Icon, (buff.Special and (data.Jackpot and "🌟 Guaranteed Rare! " or "★ Rare ") or "✨ ") .. buff.Name .. " " .. (buff.Desc or ""), setLine, color)
			else
				paint(card, "💤", "No buff (already maxed)", setLine, color)
			end
			if setInfo and setInfo.Icon then card.Icon.Text = buff and buff.Icon or setInfo.Icon end
			enhSound("Enh_Success")
			if data.Penalty then
				paint(penCard, data.Penalty.Icon, "⚠ " .. data.Penalty.Name, string.format("%s\nGold +%d%% instead", data.Penalty.Desc, data.Penalty.Gold), Color3.fromRGB(255, 130, 120))
				task.delay(0.12, function() enhSound("Enh_Fail") end)
			else
				paint(penCard, "🍀", "No penalty!", "Lucky this time", Color3.fromRGB(150, 255, 170))
			end
			TweenService:Create(popScale, TweenInfo.new(0.12), { Scale = 1.08 }):Play()
			task.wait(0.14)
			TweenService:Create(popScale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			task.wait(3.2)
			if token == mine then popup.Visible = false end
		end)
	end)
end

-- ("더 좋은 장비가 떨어졌어요" 자동 장착 팝업은 뺐다: 왼쪽 장비 버튼의 느낌표가 이미 알려 준다)

do -- 장비 뽑기 결과 연출: ReplicatedStorage.GachaReveal 모듈 (용량 때문에 떼어 냈다)
	local ok, err = pcall(function()
		require(ReplicatedStorage:WaitForChild("GachaReveal", 10)).Init({ Config = Config, Remotes = Remotes, SoundBank = SoundBank, TweenService = TweenService,
			create = create, gui = gui, makeLabel = makeLabel, rounded = rounded, sfxParent = sfxParent })
	end)
	if not ok then warn("[PlayerClient] 뽑기 연출 모듈(GachaReveal) 오류: " .. tostring(err)) end
end

Remotes.OpenGear.OnClientEvent:Connect(function()
	gearMessage.Text = ""
	gearPanel.Visible = true
	refreshGear()
end)

local lastGearStep = 0
Remotes.Tutorial.OnClientEvent:Connect(function(action, data)
	if action ~= "Step" then return end
	local advanced = data.Index > lastGearStep and lastGearStep > 0
	lastGearStep = data.Index
	if advanced and data.TargetName ~= "Gacha Machine" and gearPanel.Visible then
		task.delay(3, function()
			gearPanel.Visible = false
		end)
	end
end)

local lobbyFrame = create("Frame", { Name = "LobbyFrame", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1 }, gui)

local partyPanel = makePanel({
	Name = "PartyPanel", Size = UDim2.new(0, 270, 0, 420),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 16),
}, lobbyFrame)

local partyTitle = makeLabel({
	Size = UDim2.new(1, -20, 0, 28), Position = UDim2.new(0, 10, 0, 8),
	Font = Enum.Font.GothamBlack, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
}, partyPanel)

local memberList = create("Frame", {
	Size = UDim2.new(1, -20, 0, 140), Position = UDim2.new(0, 10, 0, 40), BackgroundTransparency = 1,
}, partyPanel)
create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, memberList)

local leaveButton = makeButton({
	Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 186),
	Text = "Leave Party", BackgroundColor3 = RED,
}, partyPanel, function()
	Remotes.Party:FireServer("Leave")
end)

makeLabel({
	Size = UDim2.new(1, -20, 0, 22), Position = UDim2.new(0, 10, 0, 224),
	Text = "Lobby Players (Invite)", Font = Enum.Font.GothamBold, TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(190, 190, 210),
}, partyPanel)

local playerList = create("ScrollingFrame", {
	Size = UDim2.new(1, -20, 1, -256), Position = UDim2.new(0, 10, 0, 248),
	BackgroundTransparency = 1, BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 4,
}, partyPanel)
create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, playerList)

local partyData = nil

local function isPartyLeaderOrSolo()
	return partyData == nil or partyData.Leader == player.UserId
end

local function refreshParty()
	local count = partyData and #partyData.Members or 1
	partyTitle.Text = string.format("Party (%d/%d)", count, Config.Party.MaxSize)

	clearChildren(memberList)
	if partyData then
		for index, member in ipairs(partyData.Members) do
			local row = makePanel({ Size = UDim2.new(1, 0, 0, 30), LayoutOrder = index, BackgroundColor3 = Color3.fromRGB(36, 39, 58) }, memberList)
			local isLeader = member.UserId == partyData.Leader
			local target = Players:GetPlayerByUserId(member.UserId)
			local level = target and target:GetAttribute("WeaponLevel") or 0
			makeLabel({
				Size = UDim2.new(1, -60, 1, 0), Position = UDim2.new(0, 8, 0, 0),
				Text = string.format("%s%s  (+%d)", isLeader and "👑 " or "", member.Name, level),
				TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12,
			}, row)
			if partyData.Leader == player.UserId and member.UserId ~= player.UserId then
				makeButton({
					Size = UDim2.new(0, 48, 0, 22), Position = UDim2.new(1, -52, 0.5, -11),
					Text = "Kick", TextSize = 10, BackgroundColor3 = RED,
				}, row, function()
					Remotes.Party:FireServer("Kick", member.UserId)
				end)
			end
		end
	else
		makeLabel({
			Size = UDim2.new(1, 0, 0, 40), Text = "No party yet.\nInvite someone below!",
			TextSize = 12, TextColor3 = Color3.fromRGB(190, 190, 210),
		}, memberList)
	end
	leaveButton.Visible = partyData ~= nil

	clearChildren(playerList)
	local canInvite = isPartyLeaderOrSolo() and (not partyData or #partyData.Members < Config.Party.MaxSize)
	local order = 0
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other:GetAttribute("Zone") == "Lobby" then
			order += 1
			local inParty = (other:GetAttribute("PartyId") or 0) ~= 0
			local row = makePanel({ Size = UDim2.new(1, 0, 0, 30), LayoutOrder = order, BackgroundColor3 = Color3.fromRGB(36, 39, 58) }, playerList)
			makeLabel({
				Size = UDim2.new(1, -64, 1, 0), Position = UDim2.new(0, 8, 0, 0),
				Text = string.format("%s  (+%d)", other.DisplayName, other:GetAttribute("WeaponLevel") or 0),
				TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12,
			}, row)
			if inParty then
				makeLabel({
					Size = UDim2.new(0, 56, 1, 0), Position = UDim2.new(1, -60, 0, 0),
					Text = "In party", TextSize = 10, TextColor3 = Color3.fromRGB(150, 150, 170),
				}, row)
			elseif canInvite then
				makeButton({
					Size = UDim2.new(0, 48, 0, 22), Position = UDim2.new(1, -52, 0.5, -11),
					Text = "Invite", TextSize = 10, BackgroundColor3 = GREEN,
				}, row, function()
					Remotes.Party:FireServer("Invite", other.UserId)
				end)
			end
		end
	end
end

local partyRefreshQueued = false
local function queuePartyRefresh()
	if partyRefreshQueued then return end
	partyRefreshQueued = true
	task.defer(function()
		partyRefreshQueued = false
		refreshParty()
	end)
end

do -- (이 구역의 지역 변수는 아래에서 쓰지 않는다: 맨 바깥 지역 변수 200개 한도 여유를 만들려고 블록으로 감쌌다)
local watched = {}
local function watchPlayer(other)
	if watched[other] then return end
	watched[other] = true
	other:GetAttributeChangedSignal("Zone"):Connect(queuePartyRefresh)
	other:GetAttributeChangedSignal("PartyId"):Connect(queuePartyRefresh)
	other:GetAttributeChangedSignal("WeaponLevel"):Connect(queuePartyRefresh)
end

for _, other in ipairs(Players:GetPlayers()) do
	watchPlayer(other)
end
Players.PlayerAdded:Connect(function(other)
	watchPlayer(other)
	queuePartyRefresh()
end)
Players.PlayerRemoving:Connect(function(other)
	watched[other] = nil
	queuePartyRefresh()
end)

end -- (지역 변수 범위 블록 끝)
local invitePanel = makePanel({
	Size = UDim2.new(0, 340, 0, 100),
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 160),
	Visible = false,
}, gui)
do -- (이 구역의 지역 변수는 아래에서 쓰지 않는다: 맨 바깥 지역 변수 200개 한도 여유를 만들려고 블록으로 감쌌다)
local inviteLabel = makeLabel({
	Size = UDim2.new(1, -20, 0, 44), Position = UDim2.new(0, 10, 0, 6),
	Font = Enum.Font.GothamBold, TextSize = 14,
}, invitePanel)
local pendingInvite = nil

local function closeInvite(decline)
	if pendingInvite and decline then
		Remotes.Party:FireServer("Decline", pendingInvite.UserId)
	end
	pendingInvite = nil
	invitePanel.Visible = false
end

makeButton({
	Size = UDim2.new(0, 140, 0, 36), Position = UDim2.new(0, 20, 1, -46),
	Text = "Accept", BackgroundColor3 = GREEN,
}, invitePanel, function()
	if pendingInvite then
		Remotes.Party:FireServer("Accept", pendingInvite.UserId)
	end
	closeInvite(false)
end)
makeButton({
	Size = UDim2.new(0, 140, 0, 36), Position = UDim2.new(1, -160, 1, -46),
	Text = "Decline", BackgroundColor3 = RED,
}, invitePanel, function()
	closeInvite(true)
end)

Remotes.Party.OnClientEvent:Connect(function(action, a, b)
	if action == "State" then
		partyData = a
		queuePartyRefresh()
	elseif action == "Invite" then
		local invite = { UserId = a, Name = b }
		pendingInvite = invite
		inviteLabel.Text = string.format("%s invited you to a party!", b)
		invitePanel.Visible = true
		task.delay(Config.Party.InviteTimeout, function()
			if pendingInvite == invite then
				closeInvite(false)
			end
		end)
	end
end)


makeLabel({
	Name = "ControlsHint", Size = UDim2.new(0, 560, 0, 40), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -78),
	Text = "North: Dungeon Gate · West: Training Dummy · Far East: Hunting Field   |   Q Dash · R Auto-Attack · I Menu · M Music",
	TextSize = 12, TextColor3 = Color3.fromRGB(220, 220, 235), TextStrokeTransparency = 0.5,
}, lobbyFrame)

end -- (지역 변수 범위 블록 끝)
local dungeonFrame = create("Frame", { Name = "DungeonFrame", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false }, gui)

local banner = makePanel({
	Name = "WaveBanner", Size = UDim2.new(0, 340, 0, 30), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6),
}, dungeonFrame)
local bannerTitle = makeLabel({
	Size = UDim2.new(1, 0, 1, 0), Position = UDim2.new(0, 0, 0, 0),
	Font = Enum.Font.GothamBlack, TextSize = 14, TextTruncate = Enum.TextTruncate.AtEnd,
}, banner)
local bannerSub = makeLabel({
	Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0, 44), Visible = false, -- (맵 이름 / 난이도는 왼쪽 위 정보 줄에 표시한다)
	TextSize = 14, TextColor3 = Color3.fromRGB(210, 210, 230),
}, banner)
local bannerMutator = makeLabel({
	Size = UDim2.new(1, -16, 0, 18), Position = UDim2.new(0, 8, 0, 78), TextStrokeTransparency = 0.5,
	TextSize = 10, TextColor3 = Color3.fromRGB(255, 205, 100), Font = Enum.Font.GothamBold,
}, banner)

local bonusBar = makePanel({
	Name = "BonusBar", Size = UDim2.new(0, 340, 0, 18), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 40), Visible = false,
}, dungeonFrame)
local bonusFill = create("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 200, 70), BorderSizePixel = 0 }, bonusBar)
rounded(bonusFill)
local bonusText = makeLabel({ Size = UDim2.new(1, 0, 1, 0), Font = Enum.Font.GothamBold, TextSize = 10, TextStrokeTransparency = 0.4 }, bonusBar)
local limitBar = makePanel({
	Name = "LimitBar", Size = UDim2.new(0, 340, 0, 18), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), Visible = false,
}, dungeonFrame)
local limitFill = create("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(110, 210, 120), BorderSizePixel = 0 }, limitBar)
rounded(limitFill)
local limitText = makeLabel({ Size = UDim2.new(1, 0, 1, 0), Font = Enum.Font.GothamBold, TextSize = 10, TextStrokeTransparency = 0.4 }, limitBar)

local bossBar = makePanel({
	Name = "BossBar", Size = UDim2.new(0, 400, 0, 22), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 40), Visible = false,
}, dungeonFrame)
local bossFill = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(200, 40, 50), BorderSizePixel = 0 }, bossBar)
rounded(bossFill)
local bossName = makeLabel({
	Size = UDim2.new(1, 0, 1, 0), Font = Enum.Font.GothamBold, TextSize = 13, TextStrokeTransparency = 0.4,
}, bossBar)

local statPanel = makePanel({
	Name = "StatPanel", Size = UDim2.new(0, 270, 0, 84), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16),
}, dungeonFrame)

local statPoints = makeLabel({
	Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 10, 0, 5),
	Font = Enum.Font.GothamBlack, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
}, statPanel)

local perkSummary = makeLabel({
	Size = UDim2.new(1, -20, 0, 32), Position = UDim2.new(0, 10, 0, 23),
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	TextSize = 10, TextWrapped = true, RichText = true, TextColor3 = Color3.fromRGB(200, 200, 220),
}, statPanel)

makeButton({
	Size = UDim2.new(1, -20, 0, 20), Position = UDim2.new(0, 10, 1, -24),
	Text = "Leave Dungeon", TextSize = 10, BackgroundColor3 = GRAY,
}, statPanel, function()
	Remotes.Dungeon:FireServer("Leave")
end)

local dungeonState = nil
local openDungeonSelect

local tracks = {}
local playlists = {}
local function nextInPlaylist(name, sound)
	local list = playlists[name]
	if not list or #list < 2 then return end
	local current = sound.SoundId
	local pick
	repeat pick = "rbxassetid://" .. list[math.random(#list)] until pick ~= current
	sound.SoundId = pick
	sound:Play()
end
for name, value in pairs(Config.Audio.Music) do
	local list = {}
	if typeof(value) == "table" then
		for _, id in ipairs(value) do
			if id ~= 0 then table.insert(list, id) end
		end
	elseif value ~= 0 then
		list[1] = value
	end
	if #list > 0 then
		local sound = Instance.new("Sound")
		sound.Name = "Music_" .. name
		sound.SoundId = "rbxassetid://" .. list[math.random(#list)]
		sound.Looped = #list == 1
		sound.Volume = 0
		sound.Parent = SoundService
		tracks[name] = sound
		if #list > 1 then
			playlists[name] = list
			sound.Ended:Connect(function() nextInPlaylist(name, sound) end)
		end
	end
end

if RunService:IsStudio() then -- 음악이 안 나오거나 안 바뀔 때 원인을 알 수 있게: 어떤 ID 가 로드됐는지 6초 뒤에 한 번 알려 준다
	task.delay(6, function()
		for trackName, sound in pairs(tracks) do
			print(string.format("[Music] %s = %s · loaded=%s · length=%.0fs", trackName, sound.SoundId, tostring(sound.IsLoaded), sound.TimeLength))
		end
	end)
end

if next(tracks) == nil and RunService:IsStudio() then
	print("[Music] Background music is empty. Enter audio IDs (numbers) in the ReplicatedStorage > AudioIds script to get lobby / field / dungeon / boss music. (See 'How to add sound' in the README)")
end

local settings = { Shake = true, Radar = true, ShotVolume = 1 }
local toggleHelp

local musicEnabled = true   -- M 키로 켜고 끈다
local currentMusic = nil
local musicScale = 1
local function musicVolume(name)
	return musicEnabled and Config.Audio.MusicVolume * musicScale * ((Config.Audio.TrackScale or {})[name or currentMusic] or 1) or 0
end

local function playMusic(name)
	if name == currentMusic then return end
	currentMusic = name
	for trackName, sound in pairs(tracks) do
		if trackName == name then
			if not sound.IsPlaying then
				if trackName == "Boss" and playlists.Boss then -- (보스전: 들어갈 때마다 2곡 중 무작위로 처음부터)
					local list = playlists.Boss
					sound.SoundId = "rbxassetid://" .. list[math.random(#list)]
					sound.TimePosition = 0
				end
				sound:Play()
			end
			TweenService:Create(sound, TweenInfo.new(1.5), { Volume = musicVolume(trackName) }):Play()
		else
			local fade = TweenService:Create(sound, TweenInfo.new(1.5), { Volume = 0 })
			fade.Completed:Connect(function()
				if currentMusic ~= trackName then
					sound:Pause()
				end
			end)
			fade:Play()
		end
	end
end

local function toggleMusic()
	musicEnabled = not musicEnabled
	for name, sound in pairs(tracks) do
		if name == currentMusic then
			TweenService:Create(sound, TweenInfo.new(0.4), { Volume = musicVolume(name) }):Play()
		end
	end
	toast(musicEnabled and "🔊 Music ON (M)" or "🔇 Music OFF (M)")
end

do -- (이 구역의 지역 변수는 아래에서 쓰지 않는다: 맨 바깥 지역 변수 200개 한도 여유를 만들려고 블록으로 감쌌다)
local function updateMusic()
	local zone = currentZone()
	if tracks.Boss then tracks.Boss.PlaybackSpeed = 1 end
	if player:GetAttribute("InDoomArena") then
		if tracks.Doom then
			playMusic("Doom")
		elseif tracks.Boss then
			tracks.Boss.PlaybackSpeed = 1.12
			playMusic("Boss")
		else
			playMusic(tracks.Dungeon and "Dungeon" or "Lobby")
		end
		return
	end
	if zone == "Lobby" then
		playMusic("Lobby")
	elseif zone == "Field" then
		if player:GetAttribute("BossFight") then
			if tracks.Boss then
				tracks.Boss.PlaybackSpeed = player:GetAttribute("BossEnrage") and 1.1 or 1 -- 군주 격노: 음악이 한 단계 빨라진다
				playMusic("Boss")
			else
				playMusic(tracks.Dungeon and "Dungeon" or (tracks.Field and "Field" or "Lobby"))
			end
		else
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local zoneKey = root and ("Field" .. Config.Field.ZoneOfX(root.Position.X))
			playMusic((zoneKey and tracks[zoneKey]) and zoneKey or (tracks.Field and "Field" or "Lobby"))
		end
	elseif dungeonState and dungeonState.Phase == "Boss" then
		playMusic("Boss")
	else
		playMusic("Dungeon")
	end
end
player:GetAttributeChangedSignal("BossFight"):Connect(function() updateMusic() end)
player:GetAttributeChangedSignal("BossEnrage"):Connect(function() updateMusic() end)
player:GetAttributeChangedSignal("InDoomArena"):Connect(function() updateMusic() end)
task.spawn(function()
	while true do
		task.wait(2)
		if currentZone() == "Field" then updateMusic() end
	end
end)

local function refreshStats()
	statPoints.Text = "Perks (this dungeon only)"
	statPoints.TextColor3 = Color3.new(1, 1, 1)

	local parts = {}
	for _, key in ipairs(Config.Perks.Order) do
		local perk = Config.Perks[key]
		local stacks = player:GetAttribute(perk.Attr) or 0
		if stacks > 0 then
			table.insert(parts, string.format("%s%s %d", perk.Icon, perk.Name, stacks))
		end
	end
	perkSummary.Text = #parts > 0 and ("" .. table.concat(parts, " · ")) or "None yet"
end

local function refreshBanner()
	local state = dungeonState
	banner.Visible = state ~= nil and state.Phase ~= "Ended"
	bossBar.Visible = state ~= nil and state.BossRatio ~= nil
	local surviving = state ~= nil and state.Phase == "Wave" and state.SurviveLeft ~= nil
	bonusBar.Visible = surviving and state.BonusLeft ~= nil
	limitBar.Visible = surviving and state.MonsterLimit ~= nil
	if surviving and state.BonusLeft and state.BonusSpan then
		local ratio = math.clamp(1 - state.BonusLeft / math.max(1, state.BonusSpan), 0, 1)
		TweenService:Create(bonusFill, TweenInfo.new(0.5, Enum.EasingStyle.Linear), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
		bonusFill.BackgroundColor3 = state.BonusLeft <= 3 and Color3.fromRGB(255, 120, 60) or Color3.fromRGB(255, 200, 70)
		bonusText.Text = state.BonusLeft <= 3 and "🎲 Coming up!!" or string.format("🎲 Random bonus in %ds", state.BonusLeft)
	end
	if surviving and state.MonsterLimit then
		local ratio = math.clamp(state.MonstersLeft / state.MonsterLimit, 0, 1)
		TweenService:Create(limitFill, TweenInfo.new(0.5, Enum.EasingStyle.Linear), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
		if state.OverrunLeft then
			limitFill.BackgroundColor3 = Color3.fromRGB(235, 50, 50)
			limitText.Text = string.format("⚠ Monster overrun! Thin them out within %ds!  (%d / %d)", state.OverrunLeft, state.MonstersLeft, state.MonsterLimit)
		else
			limitFill.BackgroundColor3 = ratio >= 0.75 and Color3.fromRGB(240, 150, 50) or Color3.fromRGB(110, 210, 120)
			limitText.Text = string.format("👹 Monsters %d / %d%s", state.MonstersLeft, state.MonsterLimit, ratio >= 0.75 and "  — Danger!" or "")
		end
	end
	if not state then return end
	bannerMutator.Text = state.MutatorText or ""
	local mapLabel = string.format("%s · %s", state.TypeName or "Dungeon", state.DifficultyName or "")
	if player:GetAttribute("DungeonLabel") ~= mapLabel then player:SetAttribute("DungeonLabel", mapLabel) end -- 왼쪽 위 정보 줄이 읽는다

	if state.BossRatio then
		bossFill.Size = UDim2.new(math.clamp(state.BossRatio, 0, 1), 0, 1, 0)
		bossName.Text = state.BossName or "BOSS"
	end

	if state.Phase == "Starting" then
		bannerTitle.Text = string.format("Entering %s!", state.TypeName or "Dungeon")
		bannerSub.Text = string.format("[%s] Starts in %ds! Survive the incoming monsters", state.DifficultyName or "", state.TimeLeft)
	elseif state.Phase == "Wave" and state.SurviveLeft then
		bannerTitle.Text = string.format("🛡 Survive!  %ds", state.SurviveLeft)
		bannerSub.Text = string.format("%s · %s · Fail if monsters pile up! Survive to the end and the boss appears", state.TypeName or "", state.DifficultyName or "")
	elseif state.Phase == "Wave" then
		bannerTitle.Text = state.TotalWaves == 0 and string.format("🏯 Floor %d", state.Wave) or string.format("Zone %d / %d", state.Wave, state.TotalWaves)
		bannerSub.Text = string.format("%s · %s · Monsters left %d · Keep going!", state.TypeName or "", state.DifficultyName or "", state.MonstersLeft)
	elseif state.Phase == "StatPhase" then
		bannerTitle.Text = "🎁 Bonus triggered!"
		bannerSub.Text = "A random buff was applied"
	elseif state.Phase == "Moving" then
		bannerTitle.Text = state.StageText or "Head to the next room"
		bannerSub.Text = "Follow the sky-blue light beam"
	elseif state.Phase == "Event" then
		bannerTitle.Text = state.StageText or "Event Room"
		bannerSub.Text = "A special room!"
	elseif state.Phase == "Boss" then
		bannerTitle.Text = "BOSS"
		bannerSub.Text = string.format("Monsters left: %d", state.MonstersLeft)
	end
end

local resultPanel = makePanel({
	Size = UDim2.new(0, 460, 0, 340), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.45, 0), Visible = false,
}, dungeonFrame)
local resultTitle = makeLabel({
	Size = UDim2.new(1, 0, 0, 56), Position = UDim2.new(0, 0, 0, 12), Font = Enum.Font.GothamBlack, TextSize = 31,
}, resultPanel)
local resultInfo = makeLabel({
	Size = UDim2.new(1, -20, 0, 200), Position = UDim2.new(0, 10, 0, 72), TextSize = 14, RichText = true, TextYAlignment = Enum.TextYAlignment.Top,
}, resultPanel)
makeButton({
	Size = UDim2.new(0, 200, 0, 40), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
	Text = "Back to Lobby", TextSize = 14,
}, resultPanel, function()
	Remotes.Dungeon:FireServer("Leave")
end)

local resultToken = 0
local function showResult(result)
	if result.Fever then return end -- 피버 타임은 FeverResultClient 의 황금 결과 카드
	resultToken += 1
	local token = resultToken
	resultPanel.Visible = true
	resultTitle.Text = result.Victory and "🏆 Dungeon Cleared!" or "💀 Dungeon Failed"
	resultTitle.TextColor3 = result.Victory and Color3.fromRGB(255, 220, 90) or Color3.fromRGB(255, 110, 110)

	task.spawn(function()
		for remaining = result.ReturnDelay, 1, -1 do
			if token ~= resultToken or not resultPanel.Visible then return end
			local lootLines = {}
			if player:GetAttribute("ChestOpening") then -- 상자 열기 연출(ChestOpenClient) 중에는 결과를 미리 보여 주지 않는다
				if #(result.Loot or {}) > 0 then lootLines[1] = "<font color='#c9c0e0' size='13'>Opening the chest...</font>" end
			else
				for _, entry in ipairs(result.Loot or {}) do
					table.insert(lootLines, string.format("<font color='#%s' size='13'>%s</font>", Config.Gear.RarityColors[entry.Rarity]:ToHex(), entry.Text))
				end
			end
			resultInfo.Text = string.format(
				"%s\nGold earned  +%d G   🎫 Tickets +%d\n%s\nReturning to lobby in %ds",
				(result.Victory and "Survived and defeated the boss!" or "You couldn't hold out"), result.Gold, result.Tickets or 0,
				#lootLines > 0 and ("<b>📦 Boss Chest</b>\n" .. table.concat(lootLines, "\n")) or "", remaining
			)
			task.wait(1)
		end
	end)
end

Remotes.Dungeon.OnClientEvent:Connect(function(action, data)
	if action == "State" then
		dungeonState = data
		refreshBanner()
		refreshStats()
		updateMusic()
	elseif action == "Result" then
		showResult(data)
	elseif action == "OpenSelect" then
		openDungeonSelect()
	end
end)

local function refreshInfo()
	local level = player:GetAttribute("WeaponLevel") or 0
	local name, color = weaponText(level)
	local zone = currentZone()
	local zoneText = zone == "Lobby" and "Lobby" or zone == "Dungeon" and "Dungeon" or string.format("Field (best: Zone %d)", player:GetAttribute("MaxZone") or 0)

	local characterLevel = player:GetAttribute("Level") or 1
	local xp = player:GetAttribute("XP") or 0
	local xpNeeded = player:GetAttribute("XPNeeded") or 1
	local maxed = characterLevel >= Config.Level.Max
	local blocked = not maxed and characterLevel >= Config.GetLevelCap(player:GetAttribute("GatePassed") or 0)
	xpFill.Size = UDim2.new((maxed or blocked) and 1 or math.clamp(xp / xpNeeded, 0, 1), 0, 1, 0)
	xpFill.BackgroundColor3 = blocked and Color3.fromRGB(255, 170, 60) or Color3.fromRGB(110, 200, 255)
	local xpText = maxed and "MAX" or blocked and "Breakthrough needed!" or string.format("%d / %d XP", xp, xpNeeded)

	local keys = (player:GetAttribute("Keys") or 0) -- 쉬움 열쇠
	local keyCap = Config.Keys.Max + (player:GetAttribute("KeyCapBonus") or 0)
	local keyNext = player:GetAttribute("KeyNext") or 0
	local keyText = string.format("Free today %d/%d", player:GetAttribute("DungeonFree") or 0, Config.Keys.FreeDaily)

	infoLabel.Text = string.format(
		"🎖 <font color='#8fd8ff'>Lv.%d</font>  <font size='10' color='#aaaacc'>%s</font>\n💰 <font color='#ffd966'>%d G</font>   🎫 <font color='#d9a6ff'>%d</font>\n🔑<font color='#ffe08a'>%d</font> <font size='10' color='#aaaacc'>(%s)</font>\n⚡ Power <font color='#ffe16e'>%d</font>\n⚔ <font color='#%s'>%s</font>\n📍 %s",
		characterLevel, xpText,
		player:GetAttribute("Gold") or 0, player:GetAttribute("Tickets") or 0,
		keys, keyText,
		player:GetAttribute("Power") or 0,
		color:ToHex(), name, zoneText
	)
end

task.spawn(function()
	while true do
		task.wait(1)
		local keys = player:GetAttribute("Keys") or 0
		if keys < Config.Keys.Max + (player:GetAttribute("KeyCapBonus") or 0) then
			refreshInfo()
		end
	end
end)

local function refreshZone()
	local zone = currentZone()
	lobbyFrame.Visible = zone ~= "Dungeon"
	dungeonFrame.Visible = zone == "Dungeon"
	local hint = lobbyFrame:FindFirstChild("ControlsHint")
	if hint then hint.Visible = zone == "Lobby" end
	for _, child in ipairs(lobbyFrame:GetChildren()) do
		if child.Name == "LobbyOnlyButton" then
			child.Visible = zone == "Lobby"
		end
	end
	if zone ~= "Lobby" then
		enhancePanel.Visible = false
		gearPanel.Visible = false
	end
	if zone ~= "Dungeon" then
		dungeonState = nil
		resultToken += 1
		resultPanel.Visible = false
		bossBar.Visible = false
	else
		enhancePanel.Visible = false
		gearPanel.Visible = false
		invitePanel.Visible = false
	end
	refreshInfo()
	refreshStats()
	refreshBanner()
	queuePartyRefresh()
	updateMusic()
end

player.AttributeChanged:Connect(function(attribute)
	if attribute == "Zone" then
		refreshZone()
		return
	end
	refreshInfo()
	refreshStats()
	if enhancePanel.Visible then
		refreshEnhance()
	end
	if gearPanel.Visible then
		refreshGear()
	end
end)

refreshZone()
refreshEnhance()

end -- (지역 변수 범위 블록 끝)
local holding = false
local nextAttack = 0

local sprinting = false
local sliding = false

local function applySpeed()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local bonus = (player:GetAttribute("GearSpeed") or 0) + (player:GetAttribute("TrainSpeed") or 0) + (player:GetAttribute("PetSpeed") or 0) + (player:GetAttribute("LvMove") or 0)
		humanoid.WalkSpeed = (sprinting and Config.Player.RunSpeed or Config.Player.WalkSpeed) + bonus
	end
end

player:GetAttributeChangedSignal("GearSpeed"):Connect(applySpeed)
player:GetAttributeChangedSignal("TrainSpeed"):Connect(applySpeed)
player:GetAttributeChangedSignal("PetSpeed"):Connect(applySpeed)

settings.DashCharges = Config.Player.DashCharges
settings.DashRefillAt = 0

local function spawnAfterimage(character, color)
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Transparency < 0.9 then
			local ghost = Instance.new("Part")
			ghost.Anchored, ghost.CanCollide, ghost.CanQuery, ghost.CanTouch = true, false, false, false
			ghost.Size = part.Size * 1.05
			ghost.CFrame = part.CFrame
			ghost.Material = Enum.Material.Neon
			ghost.Color = color
			ghost.Transparency = 0.45
			ghost.Parent = workspace
			TweenService:Create(ghost, TweenInfo.new(0.35), { Transparency = 1, Size = part.Size * 0.6 }):Play()
			game:GetService("Debris"):AddItem(ghost, 0.4)
		end
	end
end

local function slide()
	if sliding then return end
	local now = os.clock()
	local P = Config.Player
	if settings.DashCharges <= 0 then
		if settings.ShakeSlot then settings.ShakeSlot(settings.DashUi) end -- 대시 횟수가 없을 때: Q 칸이 흔들린다
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return end
	if settings.DashCharges == P.DashCharges then
		settings.DashRefillAt = now + P.DashCooldown
	end
	settings.DashCharges -= 1
	SoundBank.Play(sfxParent, "Dash")
	sliding = true

	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = root.CFrame.LookVector
	end
	direction = Vector3.new(direction.X, 0, direction.Z).Unit
	local airborne = false
	if humanoid.FloorMaterial == Enum.Material.Air then
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { character }
		params.FilterType = Enum.RaycastFilterType.Exclude
		airborne = workspace:Raycast(root.Position, Vector3.new(0, -8, 0), params) == nil
	end

	local attachment = Instance.new("Attachment")
	attachment.Parent = root

	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	velocity.MaxAxesForce = Vector3.new(math.huge, airborne and math.huge or 0, math.huge)
	velocity.VectorVelocity = direction * P.DashSpeed
	velocity.Parent = root

	local trailTop = Instance.new("Attachment")
	trailTop.Position = Vector3.new(0, 1.6, 0)
	trailTop.Parent = root
	local trailBottom = Instance.new("Attachment")
	trailBottom.Position = Vector3.new(0, -2.6, 0)
	trailBottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = trailTop
	trail.Attachment1 = trailBottom
	trail.Lifetime = 0.35
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.fromRGB(160, 230, 255), Color3.fromRGB(255, 255, 255))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = root

	local puff = Instance.new("Attachment")
	puff.Position = Vector3.new(0, -2.6, 0)
	puff.Parent = root
	local dust = Instance.new("ParticleEmitter")
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(0.3, 0.6)
	dust.Speed = NumberRange.new(8, 18)
	dust.SpreadAngle = Vector2.new(70, 70)
	dust.Color = ColorSequence.new(Color3.fromRGB(235, 235, 245))
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 4) })
	dust.Parent = puff
	dust:Emit(airborne and 14 or 26)

	local autoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false
	root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)

	local started = os.clock()
	local lastGhost = 0
	local connection
	local function finish()
		connection:Disconnect()
		velocity:Destroy()
		attachment:Destroy()
		trail.Enabled = false
		if humanoid.Parent then
			humanoid.AutoRotate = autoRotate
		end
		if root.Parent then
			local vertical = root.AssemblyLinearVelocity.Y
			root.AssemblyLinearVelocity = direction * P.RunSpeed * 1.1 + Vector3.new(0, vertical, 0)
		end
		sliding = false
		task.delay(0.6, function()
			puff:Destroy()
			trail:Destroy()
			trailTop:Destroy()
			trailBottom:Destroy()
		end)
	end
	connection = RunService.Heartbeat:Connect(function()
		local t = (os.clock() - started) / P.DashTime
		if t >= 1 or not root.Parent or humanoid.Health <= 0 then
			finish()
			return
		end
		velocity.VectorVelocity = direction * (P.DashSpeed * (1 - t * t * 0.7))
		if os.clock() - lastGhost > 0.035 then
			lastGhost = os.clock()
			spawnAfterimage(character, airborne and Color3.fromRGB(255, 190, 120) or Color3.fromRGB(120, 210, 255))
		end
	end)
end

player.CharacterAdded:Connect(function(character)
	character:WaitForChild("Humanoid")
	applySpeed()
	sliding = false
end)
task.spawn(function() -- 이동 속도를 0.5초마다 다시 맞춘다 (스크립트가 캐릭터보다 늦게 켜지거나 다른 곳에서 16 으로 되돌려도 느려진 채로 남지 않게)
	while true do
		applySpeed()
		task.wait(0.5)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local target = player:GetAttribute("DeadeyeActive") and 62 or (sliding and 108 or sprinting and 80 or 70) -- 데드아이: 줌인
	camera.FieldOfView += (target - camera.FieldOfView) * math.min(1, dt * 8)
end)

local autoMode = false
local lockTarget = nil
local nextSearch = 0

local autoLabel = makeLabel({
	Size = UDim2.new(0, 460, 0, 30), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -128),
	BackgroundColor3 = Color3.fromRGB(20, 20, 30), BackgroundTransparency = 0.25,
	Font = Enum.Font.GothamBold, TextSize = 14, Visible = false, RichText = true,
}, gui)
rounded(autoLabel)

local lockHighlight = Instance.new("Highlight")
lockHighlight.FillTransparency = 1
lockHighlight.OutlineColor = Color3.fromRGB(255, 220, 80)
lockHighlight.OutlineTransparency = 0
lockHighlight.Enabled = false
lockHighlight.Parent = workspace

local function targetName(target)
	if not target then return "Finding target..." end
	if target.Kind == "Dummy" then
		local index = tonumber(string.sub(target.Instance.Name, 6))
		local info = index and Config.Dummy.List[index]
		return info and info.Name or "Training Dummy"
	end
	return "Monster"
end

local function updateLockVisual()
	autoLabel.Visible = false
	if autoMode and lockTarget and lockTarget.Instance.Parent then
		lockHighlight.Adornee = lockTarget.Instance
		lockHighlight.Enabled = true
	else
		lockHighlight.Adornee = nil
		lockHighlight.Enabled = false
	end
end

local function weaponRange()
	return Config.GetRange(player, Config.GetPlayerWeapon(player))
end

local function dummyUsable(model)
	local index = tonumber(string.sub(model.Name, 6))
	local info = index and Config.Dummy.List[index]
	return info ~= nil and (player:GetAttribute("Power") or 0) >= info.RequiredPower
end

local function resolveTarget(instance)
	if not instance then return nil end

	local dummies = workspace:FindFirstChild("Dummies")
	if dummies and instance:IsDescendantOf(dummies) then
		local model = instance:FindFirstAncestorOfClass("Model")
		if model and model.PrimaryPart and string.sub(model.Name, 1, 5) == "Dummy" then
			return { Kind = "Dummy", Instance = model, Part = model.PrimaryPart }
		end
		return nil
	end

	local parent = instance.Parent
	if parent and parent.Name == "FieldMonsters" and parent.Parent == workspace then
		return { Kind = "Monster", Instance = instance, Part = instance }
	end
	if parent and parent.Name == "Monsters" and parent.Parent and string.sub(parent.Parent.Name, 1, 8) == "Dungeon_" then
		return { Kind = "Monster", Instance = instance, Part = instance }
	end
	return nil
end

local function isTargetVisible(target, root)
	local position = target.Part.Position
	local _, onScreen = camera:WorldToViewportPoint(position)
	if not onScreen then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	-- 가는 길을 막는 게 "벽"일 때만 보이지 않는 것으로 본다: 다른 몬스터 / 날아다니는 탄 / 이펙트 / 투명한 부품은 그냥 지나친다
	-- (예전에는 이런 것에 광선이 한 번이라도 걸리면 그 몬스터는 조준 대상에서 빠져서, 탄막이 많을 때 "타겟팅이 안 된다"처럼 보였다)
	local ignore = { player.Character }
	for _ = 1, 8 do
		params.FilterDescendantsInstances = ignore
		local result = workspace:Raycast(origin, position - origin, params)
		if result == nil or result.Instance == target.Part or result.Instance:IsDescendantOf(target.Instance) then return true end
		local hit = result.Instance
		local isMonster = hit:FindFirstAncestor("FieldMonsters") ~= nil or hit:FindFirstAncestor("Monsters") ~= nil
		if isMonster or not hit.CanCollide or hit.Transparency >= 0.5 then
			table.insert(ignore, hit)
		else
			return false -- 단단한 벽
		end
	end
	return true
end

local function isTargetValid(target, root)
	if not target or not target.Instance.Parent or not target.Part.Parent then return false end
	if target.Kind == "Dummy" and not dummyUsable(target.Instance) then return false end
	if target.Kind == "Monster" and currentZone() == "Field" then
		local F = Config.Field
		local zoneIndex = F.ZoneOfX(target.Part.Position.X)
		if zoneIndex > math.min(F.ZoneCount, (player:GetAttribute("ClearedZone") or 0) + 1) then return false end
	end
	local reach = currentZone() == "Dungeon" and math.min(weaponRange() * 0.95, 200) or weaponRange() * 0.95 -- (예전 80: 긴 길 던전 시절 제한. 지금 투기장은 지름 약 220이라 자동 조준이 가까운 적만 잡아 사거리가 짧게 느껴졌다)
	if (target.Part.Position - root.Position).Magnitude > reach then return false end
	return isTargetVisible(target, root)
end

local function findNearestTarget(root)
	local zone = currentZone()
	local best, bestDistance = nil, math.huge

	local function consider(target)
		if isTargetValid(target, root) then
			local screen = camera:WorldToViewportPoint(target.Part.Position)
			local viewport = camera.ViewportSize
			local fromCenter = math.min(1.5, (Vector2.new(screen.X, screen.Y) - viewport / 2).Magnitude / viewport.Y) -- 0 = 정중앙
			local distance = (target.Part.Position - root.Position).Magnitude
			-- 가까운 적이 먼저: 거리가 기본이고, 화면 가운데에 있으면 조금만 가산점 (예전: 화면 가운데 비중이 커서 멀리 있는 적에게 먼저 쏘는 일이 많았다)
			local score = distance * (1 + 0.6 * fromCenter)
			if screen.Z < 0 then score *= 1.3 end -- 카메라 뒤쪽 적은 살짝 뒤로
			if score < bestDistance then
				best, bestDistance = target, score
			end
		end
	end

	if zone == "Lobby" then
		local dummies = workspace:FindFirstChild("Dummies")
		local bestDummy = -1
		if dummies then
			for _, model in ipairs(dummies:GetChildren()) do
				if model:IsA("Model") and model.PrimaryPart then
					local target = { Kind = "Dummy", Instance = model, Part = model.PrimaryPart }
					if isTargetValid(target, root) then
						local order = tonumber(string.sub(model.Name, 6)) or 0
						if order > bestDummy then
							bestDummy = order
							best = target
						end
					end
				end
			end
		end
	elseif zone == "Field" then
		local folder = workspace:FindFirstChild("FieldMonsters")
		if folder then
			for _, part in ipairs(folder:GetChildren()) do
				consider({ Kind = "Monster", Instance = part, Part = part })
			end
		end
	elseif zone == "Dungeon" then
		for _, child in ipairs(workspace:GetChildren()) do
			if string.sub(child.Name, 1, 8) == "Dungeon_" then
				local monsters = child:FindFirstChild("Monsters")
				if monsters then
					for _, part in ipairs(monsters:GetChildren()) do
						consider({ Kind = "Monster", Instance = part, Part = part })
					end
				end
			end
		end
	end
	return best
end

-- 마우스가 가리키는 곳: 화면에서 쏜 광선이 처음 맞는 "보이는" 물체. 투명한 부품(보이지 않는 벽 / 안전지대 판정 / 투명 장식)은 건너뛴다.
-- (예전엔 투명 부품에 먼저 맞아 조준점이 캐릭터 바로 앞에 찍혀서, 탄이 마우스가 아니라 캐릭터가 보는 쪽으로 나갔다)
-- 몬스터의 판정용 몸통은 투명이지만 조준 대상이므로 맞힌다 (태그 "Monster")
local CollectionServiceAim = game:GetService("CollectionService")
local function aimable(hit)
	if not hit:IsA("BasePart") then return true end
	if hit.Transparency < 0.9 then return true end
	local node = hit
	for _ = 1, 3 do
		if not node then break end
		if CollectionServiceAim:HasTag(node, "Monster") then return true end
		node = node.Parent
	end
	return false
end
local function getAimPoint(screenPosition)
	local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { player.Character }
	for _ = 1, 8 do
		params.FilterDescendantsInstances = ignore
		local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
		if not result then break end
		if aimable(result.Instance) then
			return result.Position, result.Instance
		end
		table.insert(ignore, result.Instance) -- 투명 부품은 빼고 다시 쏜다
	end
	return ray.Origin + ray.Direction * 300, nil
end

local hitMarker = 0
local hitMarkerCrit = false
local shake = 0
local crosshairKick = 0

local function fireAt(worldPoint, manual)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	if not sliding then
		local flat = Vector3.new(worldPoint.X - root.Position.X, 0, worldPoint.Z - root.Position.Z)
		if flat.Magnitude > 1 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		end
	end
	crosshairKick = 10
	Remotes.Attack:FireServer(worldPoint, manual == true)
end

local function attack(screenPosition)
	local point, instance = getAimPoint(screenPosition)

	if autoMode then
		local target = resolveTarget(instance)
		if target then
			if target.Kind == "Dummy" and not dummyUsable(target.Instance) then
				toast("🛡 This dummy has high defense, so your attacks bounce off at your current Power")
			else
				lockTarget = target
				updateLockVisual()
			end
		end
	end
	fireAt(point, true)
end

local function toggleAuto()
	autoMode = not autoMode
	lockTarget = nil
	nextSearch = 0
	updateLockVisual()
	toast(autoMode and "🔒 Auto-Attack ON — click a dummy/monster to lock onto it (R to turn off)" or "Auto-Attack OFF")
end

player:GetAttributeChangedSignal("Zone"):Connect(function()
	if autoMode and player:GetAttribute("Zone") == "Lobby" and not player:GetAttribute("TutorialDoom") then toggleAuto() end
end)

player:GetAttributeChangedSignal("AutoOffTick"):Connect(function()
	if autoMode and player:GetAttribute("Zone") == "Lobby" then
		toggleAuto()
	end
end)

do
	local autoButton = makeButton({
		Name = "AutoButton", Size = UDim2.new(0, 140, 0, 54), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0.5, 150, 1, -14),
		Text = "", BackgroundColor3 = Theme.SLOT,
	}, gui, toggleAuto)
	local autoStroke = create("UIStroke", { Color = Color3.fromRGB(120, 130, 190), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, autoButton)
	local keycap = create("Frame", { Size = UDim2.new(0, 34, 0, 34), Position = UDim2.new(0, 10, 0.5, -17), BackgroundColor3 = Color3.fromRGB(235, 235, 245), BorderSizePixel = 0 }, autoButton)
	rounded(keycap, 8)
	makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = "R", TextSize = 19, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(30, 30, 50) }, keycap)
	local autoText = makeLabel({
		Size = UDim2.new(1, -54, 1, -6), Position = UDim2.new(0, 50, 0, 3), TextSize = 12, Font = Enum.Font.GothamBold, RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, autoButton)

	local hint = create("Frame", {
		Size = UDim2.new(0, 400, 0, 120), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.6, 0),
		BackgroundColor3 = Color3.fromRGB(16, 18, 30), BackgroundTransparency = 0.15, BorderSizePixel = 0, Visible = false, ZIndex = 30,
	}, gui)
	rounded(hint, 16)
	create("UIStroke", { Color = Color3.fromRGB(255, 225, 110), Thickness = 3 }, hint)
	local bigKey = create("Frame", { Size = UDim2.new(0, 84, 0, 84), Position = UDim2.new(0, 18, 0.5, -42), BackgroundColor3 = Color3.fromRGB(245, 245, 252), BorderSizePixel = 0, ZIndex = 31 }, hint)
	rounded(bigKey, 16)
	create("UIStroke", { Color = Color3.fromRGB(255, 200, 70), Thickness = 4 }, bigKey)
	makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = "R", TextSize = 51, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(30, 30, 50), ZIndex = 32 }, bigKey)
	makeLabel({
		Size = UDim2.new(1, -130, 1, -16), Position = UDim2.new(0, 118, 0, 8), RichText = true, TextSize = 17, ZIndex = 31, TextXAlignment = Enum.TextXAlignment.Left,
		Text = UserInputService.TouchEnabled and "<b>Auto-Attack!</b>\n<font size='13' color='#cfd3ea'>Tap the <b>R Auto-Attack</b> button\nat the bottom right to fire automatically</font>" or "<b>Auto-Attack!</b>\n<font size='13' color='#cfd3ea'>Press <b>R</b> to automatically\naim at and shoot nearby enemies</font>",
	}, hint)
	TweenService:Create(bigKey, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Size = UDim2.new(0, 94, 0, 94), Position = UDim2.new(0, 13, 0.5, -47) }):Play()

	local shownAt = os.clock() + 9
	local used = false
	-- 필드에 나갔는데 자동 공격이 꺼져 있으면: 큰 R 안내를 잠깐(최대 2번, 6초) 띄우고, 버튼이 계속 금빛으로 뛴다
	local fieldHintUntil, fieldHintCount = 0, 0
	local function onZone()
		if player:GetAttribute("Zone") == "Field" and not autoMode and fieldHintCount < 2 then
			fieldHintCount += 1
			fieldHintUntil = os.clock() + 6
		end
	end
	player:GetAttributeChangedSignal("Zone"):Connect(onZone)
	task.defer(onZone)
	RunService.RenderStepped:Connect(function()
		if autoMode then used = true end
		local nudge = not autoMode and currentZone() == "Field"
		autoStroke.Color = autoMode and Color3.fromRGB(110, 255, 150) or (nudge and Color3.fromRGB(255, 215, 90) or Color3.fromRGB(120, 130, 190))
		autoStroke.Thickness = autoMode and 3 or (nudge and 3 + 3 * math.abs(math.sin(os.clock() * 4)) or 2)
		autoButton.BackgroundColor3 = autoMode and Theme.SLOT_ON or Theme.SLOT
		autoText.Text = autoMode and "<font color='#8fffb0'><b>Auto-Attack</b>\nON</font>" or "<b>Auto-Attack</b>\n<font color='#9aa0c8'>OFF</font>"
		local zone = currentZone()
		autoButton.Visible = (zone == "Lobby" or zone == "Field" or zone == "Dungeon") and not (player:GetAttribute("ModalOpen") == true and gui.Parent:GetAttribute("UiCompact") ~= true) -- (큰 화면: 큰 창이 열려 있는 동안은 창 위에 겹쳐 보이지 않게 숨긴다)
		local showHint = not used and player:GetAttribute("TutorialActive") == true and os.clock() > shownAt and os.clock() < shownAt + 40 and zone ~= "Dungeon" and not (settings.MenuPanel and settings.MenuPanel.Visible)
		showHint = showHint or (not autoMode and os.clock() < fieldHintUntil and not (settings.MenuPanel and settings.MenuPanel.Visible))
		hint.Visible = showHint
	end)
end

local function attackCooldown()
	local speedPoints = player:GetAttribute("SpeedPoints") or 0
	return Config.Player.BaseCooldown * Config.GetPlayerWeapon(player).Cooldown / ((1 + speedPoints * Config.Player.SpeedPerPoint) * (1 + (player:GetAttribute("PetAtkSpeed") or 0) + (player:GetAttribute("TrainAtkSpeed") or 0) + (player:GetAttribute("GearAtkSpeed") or 0))) -- 펫 / 훈련 / 장비 가속 포함
end

local questState = nil
local rankList = {}

do
	local mini = makePanel({
		Name = "RankMini", Size = UDim2.new(0, 270, 0, 138), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 444),
	}, lobbyFrame)
	makeLabel({
		Size = UDim2.new(1, -20, 0, 22), Position = UDim2.new(0, 10, 0, 6), Text = "🏆 Power Ranking",
		Font = Enum.Font.GothamBlack, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 225, 120),
	}, mini)
	local body = makeLabel({
		Size = UDim2.new(1, -20, 1, -32), Position = UDim2.new(0, 10, 0, 28), RichText = true, TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "Tallying...",
	}, mini)
	Remotes.Rank.OnClientEvent:Connect(function(action, data)
		if action ~= "List" then return end
		local lines = {}
		for index = 1, math.min(5, #data) do
			local entry = data[index]
			local medal = index == 1 and "🥇" or index == 2 and "🥈" or index == 3 and "🥉" or (index .. ".")
			local mine = entry.Name == player.DisplayName
			table.insert(lines, string.format("%s <font color='#%s'>%s</font>  <font color='#ffe16e'>⚡%d</font>", medal, mine and "78ff8c" or "ffffff", entry.Name, entry.Power))
		end
		body.Text = #lines > 0 and table.concat(lines, "\n") or "No records yet"
	end)
	Remotes.Rank:FireServer("Request")
end

local menuPanel = makePanel({
	Name = "MenuPanel",
	Size = UDim2.new(0, 860, 0, 580),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.55, 0),
	BackgroundColor3 = Color3.fromRGB(16, 18, 30),
	BackgroundTransparency = 0.03,
	Visible = false,
}, gui)
settings.MenuPanel = menuPanel
create("UIStroke", { Color = Color3.fromRGB(110, 130, 220), Thickness = 1.5, Transparency = 0.35 }, menuPanel)

makeLabel({
	Size = UDim2.new(1, -90, 0, 36), Position = UDim2.new(0, 16, 0, 8),
	Text = "📋 Menu", Font = Enum.Font.GothamBlack, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left,
}, menuPanel)
-- 메뉴 제목 옆 재화 줄: 장비 탭일 때 가방 칸 수 / 에센스를 여기에 보여 준다 (장비 / 강화 버튼이 더 위로 올라오게)
settings.MenuInfo = makeLabel({
	Size = UDim2.new(1, -330, 0, 36), Position = UDim2.new(0, 130, 0, 8), RichText = true, TextSize = 13, Text = "",
	TextXAlignment = Enum.TextXAlignment.Left,
}, menuPanel)

makeButton({
	Size = UDim2.new(0, 72, 0, 30), Position = UDim2.new(1, -84, 0, 12), Text = "Close (B)", TextSize = 12, BackgroundColor3 = Color3.fromRGB(54, 58, 82),
}, menuPanel, function()
	menuPanel.Visible = false
end)

local TABS = {
	{ Key = "Character", Name = "Character" }, -- 장비 / 무기 / 정보
	{ Key = "Growth", Name = "Skills·Growth" }, -- 액티브 스킬 / 패시브(스킬 + 훈련·돌파) / 펫
	{ Key = "Quest", Name = "Quests" },     -- 오늘의 퀘스트 / 업적
	{ Key = "Rank", Name = "Ranking" },
}
local MENU = { Sub = { Character = "Gear", Growth = "Active", Quest = "Daily" } }
MENU.Subs = { -- 탭 안의 작은 버튼 줄
	Character = { { "Gear", "🛡 Gear" }, { "Weapon", "🔫 Weapon" }, { "Info", "📊 Info" } },
	Quest = { { "Daily", "Today's Quests" }, { "Ach", "Achievements" } },
}
MENU.Alias = {
	Inventory = { "Character", "Gear" }, Weapon = { "Character", "Weapon" }, Info = { "Character", "Info" },
	Skill = { "Growth", "Active" }, Train = { "Growth", "Passive" }, Pet = { "Growth", "Pet" }, Ach = { "Quest", "Ach" },
}
local currentTab = "Character"
local tabButtons = {}

local menuContent = create("ScrollingFrame", {
	Size = UDim2.new(1, -24, 1, -108), Position = UDim2.new(0, 12, 0, 96),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, menuPanel)
create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, menuContent)

local rowOrder = 0
local activeContent = menuContent
local function newRow(height, color)
	rowOrder += 1
	return makePanel({
		Size = UDim2.new(1, -10, 0, height), LayoutOrder = rowOrder,
		BackgroundColor3 = color or Color3.fromRGB(36, 39, 58),
	}, activeContent)
end

local function rowText(row, text, size, rightMargin)
	return makeLabel({
		Size = UDim2.new(1, -(rightMargin or 24), 1, -10), Position = UDim2.new(0, 12, 0, 5),
		Text = text, TextSize = size or 15, RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
	}, row)
end

local function sectionTitle(text)
	local row = newRow(30, Color3.fromRGB(26, 28, 42))
	rowText(row, "<font color='#e1c476'><b>" .. text .. "</b></font>", 16)
end

local function hex(color)
	return color:ToHex()
end

local function buildCharacterTab()
	local weaponType = Config.GetPlayerWeapon(player)
	local health = Config.Player.BaseHealth + (player:GetAttribute("HealthPoints") or 0) * Config.Player.HealthPerPoint + (player:GetAttribute("GearHealth") or 0) + (player:GetAttribute("TrainHealth") or 0) + Config.GetLevelHealth(player:GetAttribute("Level") or 1)
	-- 실제 공식(DungeonService.ComputeDamage)과 같게: 훈련 / 펫 치명타 포함, 최대 90%
	local rawCrit = (player:GetAttribute("CritPoints") or 0) * Config.Player.CritPerPoint + (player:GetAttribute("GearCrit") or 0)
		+ (player:GetAttribute("TrainCrit") or 0) + (player:GetAttribute("PetCrit") or 0) + (weaponType.CritBonus or 0)
	local crit = math.min(0.9, rawCrit) * 100
	local critOver = math.max(0, rawCrit - 0.9) * 100 -- 넘친 만큼 치명타 피해로
	local speed = Config.Player.WalkSpeed + (player:GetAttribute("GearSpeed") or 0)

	-- 정보 카드: 레벨 + 경험치 막대 / 전투력 / 능력치 타일 8칸 (예전: 이모지 섞인 글자 덩어리 한 장)
	local menuLevel = player:GetAttribute("Level") or 1
	local function groupDigits(n)
		return (tostring(math.floor(n or 0)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
	end
	local function shortNum(n)
		n = n or 0
		if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
		if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
		return groupDigits(n)
	end
	local summary = newRow(116)
	local xp, xpNeeded = player:GetAttribute("XP") or 0, math.max(1, player:GetAttribute("XPNeeded") or 1)
	local maxed = menuLevel >= Config.Level.Max
	makeLabel({ Size = UDim2.new(0, 120, 0, 34), Position = UDim2.new(0, 14, 0, 10), Text = "Lv." .. menuLevel, TextSize = 26, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(143, 216, 255), TextXAlignment = Enum.TextXAlignment.Left }, summary)
	makeLabel({ Size = UDim2.new(1, -150, 0, 34), Position = UDim2.new(0, 136, 0, 10), Text = "⚡ " .. groupDigits(player:GetAttribute("Power") or 0), TextSize = 24, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 225, 110), TextXAlignment = Enum.TextXAlignment.Right }, summary)
	local xpBack = create("Frame", { Size = UDim2.new(1, -28, 0, 8), Position = UDim2.new(0, 14, 0, 48), BackgroundColor3 = Color3.fromRGB(20, 22, 34), BorderSizePixel = 0 }, summary)
	rounded(xpBack, 4)
	local xpFill = create("Frame", { Size = UDim2.new(maxed and 1 or math.clamp(xp / xpNeeded, 0, 1), 0, 1, 0), BackgroundColor3 = Color3.fromRGB(110, 200, 255), BorderSizePixel = 0 }, xpBack)
	rounded(xpFill, 4)
	makeLabel({ Size = UDim2.new(0.5, 0, 0, 16), Position = UDim2.new(0.5, -14, 0, 58), Text = maxed and "MAX LEVEL" or string.format("%s / %s XP", groupDigits(xp), groupDigits(xpNeeded)), TextSize = 12, TextColor3 = Color3.fromRGB(150, 158, 190), TextXAlignment = Enum.TextXAlignment.Right }, summary)
	-- 진행 칩 (골드 / 티켓 / 최고 구역 / 던전)
	local chips = {
		"💰 " .. shortNum(player:GetAttribute("Gold") or 0), "🎫 " .. groupDigits(player:GetAttribute("Tickets") or 0),
		"🗺 Zone " .. tostring(player:GetAttribute("MaxZone") or 0) .. " / " .. Config.Field.ZoneCount, "🏰 Dungeons " .. groupDigits(questState and questState.Stats and questState.Stats.DungeonClears or 0),
	}
	for i, text in ipairs(chips) do
		local chip = makeLabel({ Size = UDim2.new(0.25, -12, 0, 26), Position = UDim2.new((i - 1) * 0.25, 10, 0, 80), Text = text, TextSize = 12, Font = Enum.Font.GothamBold, BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(26, 28, 44) }, summary)
		rounded(chip, 13)
	end

	-- 능력치: 공격 / 방어 / 유틸 세 장의 카드 (각 줄 = 아이콘 구슬 + 이름 + 큰 값)
	local weaponNow = weaponType
	local critMult = Config.Player.CritMultiplier + (player:GetAttribute("LvCritDmg") or 0) + (player:GetAttribute("TrainCritDmg") or 0) + (player:GetAttribute("GearCritDmg") or 0) + (player:GetAttribute("ParCritDmg") or 0) + critOver / 100
	local D = Config.Defense
	local defense = menuLevel * D.LevelDef + (player:GetAttribute("GearHealth") or 0) * D.GearDef
	local reduction = 1 - (1 - math.min(D.MaxReduction, defense / (defense + D.K))) * (1 - (player:GetAttribute("GearBulwark") or 0))
	local moveSpeed = Config.Player.WalkSpeed + (player:GetAttribute("GearSpeed") or 0) + (player:GetAttribute("TrainSpeed") or 0) + (player:GetAttribute("PetSpeed") or 0) + (player:GetAttribute("LvMove") or 0)
	local function pct(v, digits) return string.format(digits and "%.1f%%" or "%d%%", digits and v * 100 or math.floor(v * 100 + 0.5)) end
	local groups = {
		{ "⚔ Offense", Color3.fromRGB(255, 120, 90), {
			{ "⚔", "Attack", groupDigits(Config.BaseAttackEstimate(player) * (1 + (player:GetAttribute("ParAttack") or 0))) },
			{ "🎯", "Crit Chance", string.format("%.1f%%", crit) },
			{ "💥", "Crit Damage", string.format("x%.2f", critMult) },
			{ "⏩", "Attack Speed", string.format("%.1f/s", 1 / math.max(0.05, attackCooldown())) },
			{ "🔫", "Double Shot", pct((player:GetAttribute("LvDouble") or 0) + (player:GetAttribute("TrainDouble") or 0), true) },
			{ "👑", "Boss Damage", "+" .. pct((player:GetAttribute("GearBossDmg") or 0) + (player:GetAttribute("ParBoss") or 0)) },
			{ "📏", "Range", tostring(math.floor(Config.GetRange(player, weaponNow) + 0.5)) },
		} },
		{ "🛡 Defense", Color3.fromRGB(110, 170, 255), {
			{ "❤", "Max HP", groupDigits(health) },
			{ "🛡", "Damage Taken", "-" .. pct(reduction, true) },
			{ "🩸", "Heal on Kill", pct(player:GetAttribute("GearLifeOnKill") or 0, true) },
		} },
		{ "🧭 Utility", Color3.fromRGB(110, 220, 150), {
			{ "💨", "Move Speed", string.format("%.1f", moveSpeed) },
			{ "⏱", "Skill Cooldown", "-" .. pct((player:GetAttribute("GearHaste") or 0) + (player:GetAttribute("PetHaste") or 0) + (player:GetAttribute("LvHaste") or 0)) },
			{ "🍀", "Luck", "+" .. pct(player:GetAttribute("GearLuck") or 0) },
			{ "📘", "XP", "+" .. pct((player:GetAttribute("GearXp") or 0) + (player:GetAttribute("PetXp") or 0)) },
			{ "💰", "Gold", "+" .. pct(Config.GoldBonus(player) - 1) },
		} },
	}
	local cardRow = newRow(46 + 7 * 38 + 10, Color3.fromRGB(20, 22, 34))
	for gi, group in ipairs(groups) do
		local card = create("Frame", { Size = UDim2.new(1 / 3, -12, 1, -12), Position = UDim2.new((gi - 1) / 3, 8, 0, 6), BackgroundColor3 = group[2]:Lerp(Color3.fromRGB(22, 24, 38), 0.86), BorderSizePixel = 0 }, cardRow)
		rounded(card, 14)
		create("UIStroke", { Color = group[2], Thickness = 1.5, Transparency = 0.35 }, card)
		makeLabel({ Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 0, 6), Text = group[1], TextSize = 16, Font = Enum.Font.GothamBlack, TextColor3 = group[2] }, card)
		for si, stat in ipairs(group[3]) do
			local y = 44 + (si - 1) * 38
			local orb = create("Frame", { Size = UDim2.new(0, 30, 0, 30), Position = UDim2.new(0, 10, 0, y), BackgroundColor3 = group[2]:Lerp(Color3.fromRGB(20, 22, 34), 0.6), BorderSizePixel = 0 }, card)
			rounded(orb, 15)
			makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = stat[1], TextSize = 15 }, orb)
			makeLabel({ Size = UDim2.new(0.55, -46, 0, 30), Position = UDim2.new(0, 46, 0, y), Text = stat[2], TextSize = 12, TextColor3 = Color3.fromRGB(190, 196, 220), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, card)
			makeLabel({ Size = UDim2.new(0.45, -12, 0, 30), Position = UDim2.new(0.55, 0, 0, y), Text = stat[3], TextSize = 16, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Right }, card)
		end
	end

	sectionTitle("Titles (unlocked via achievements, shown on your nameplate)")
	local titles = questState and questState.Titles or {}
	local equipped = questState and questState.Equipped
	if #titles == 0 then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>No titles unlocked yet. Try the achievements under Quests!</font>")
	end
	for _, title in ipairs(titles) do
		local row = newRow(40)
		rowText(row, string.format("『%s』", title), 16, 150)
		local isEquipped = title == equipped
		makeButton({
			Size = UDim2.new(0, 110, 0, 28), Position = UDim2.new(1, -122, 0.5, -14),
			Text = isEquipped and "Remove" or "Equip", BackgroundColor3 = isEquipped and RED or GREEN,
		}, row, function()
			Remotes.Quest:FireServer("Title", isEquipped and "" or title)
		end)
	end
end

do
	require(ReplicatedStorage:WaitForChild("FireDemo"))(settings, { create = create })
end

local function buildWeaponTab()
	local level = player:GetAttribute("WeaponLevel") or 0
	local order = Config.WeaponTypes.Order
	local equippedKey = Config.ResolveWeaponType(level, player:GetAttribute("WeaponType"))
	local eraTier = Config.GetWeaponTier(level)
	sectionTitle(string.format("🔫 5 Weapon Types — one unlocks per upgrade milestone (every 15). Pick which unlocked weapon to fight with · Now: %s", Config.GetEraName(eraTier.Era)))

	local previewKey = Config.WeaponTypes[settings.PreviewForm or ""] and settings.PreviewForm ~= "Order" and settings.PreviewForm or equippedKey
	local shown = Config.GetLookTier(level, previewKey) -- 그 무기 형 + 지금 시대의 외모 / 탄 색
	local classInfo = Config.WeaponTypes[previewKey]
	local unlocked = Config.IsWeaponUnlocked(level, previewKey)
	local isMine = previewKey == equippedKey

	local header = newRow(262)
	do
		local viewport = create("ViewportFrame", {
			Size = UDim2.new(0, 270, 0, 238), Position = UDim2.new(0, 12, 0, 12), BackgroundColor3 = Color3.fromRGB(24, 26, 42), BorderSizePixel = 0,
			Ambient = Color3.fromRGB(190, 190, 200), LightColor = Color3.new(1, 1, 1),
		}, header)
		rounded(viewport, 10)
		create("UIStroke", { Color = shown.Rainbow and Color3.fromRGB(255, 120, 255) or shown.Color, Thickness = 2 }, viewport)
		settings.BuildFireDemo(viewport, shown, classInfo)
		makeLabel({ Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -22), Text = isMine and "My Weapon · Fire Demo" or "👀 Preview · Fire Demo", TextSize = 9, TextColor3 = Color3.fromRGB(170, 180, 210) }, viewport)
	end

	local SHOT_NAMES = { Ball = "Small Bullet", Bolt = "Light Bolt", Orb = "Energy Orb", Cannon = "Heavy Shell", Fire = "Fireball", Rocket = "Rocket", Rainbow = "Rainbow Orb" }
	local shotInfo = shown.Shot or { Style = "Ball" }
	local behavior = {}
	if classInfo.Pellets > 1 then table.insert(behavior, string.format("Fires %d pellets in a spread", classInfo.Pellets)) end
	if classInfo.Splash then table.insert(behavior, string.format("Explodes on hit (radius %d)", classInfo.Splash)) end
	if classInfo.Pierce then table.insert(behavior, string.format("Pierces up to %d enemies", classInfo.Pierce + 1)) end
	if classInfo.Bounce then table.insert(behavior, string.format("Bounces to %d nearby enemies (within %d)", classInfo.Bounce, classInfo.BounceRange or 34)) end
	if (classInfo.CritBonus or 0) > 0 then table.insert(behavior, string.format("Crit +%d%%", math.floor(classInfo.CritBonus * 100 + 0.5))) end
	if #behavior == 0 then table.insert(behavior, "Flies straight and hits one enemy") end
	local rate = 1 / math.max(0.05, classInfo.Cooldown * Config.Player.BaseCooldown)
	local status
	if isMine then
		status = "<font color='#78ff8c'>▶ In use</font>"
	elseif unlocked then
		status = "<font color='#ffd966'>✔ Unlocked</font>"
	else
		status = string.format("<font color='#ff9a6e'>🔒 Unlocks at +%d (%d to go)</font>", Config.GetUnlockLevel(previewKey), math.max(0, Config.GetUnlockLevel(previewKey) - level))
	end
	local power = Config.WeaponDpsFactor(classInfo)
	local nameColor = hex(shown.Rainbow and Color3.fromRGB(255, 120, 255) or shown.Color)
	makeLabel({
		Size = UDim2.new(1, -366, 1, -64), Position = UDim2.new(0, 294, 0, 10), RichText = true, TextSize = 12, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		Text = string.format(
			"<font size='17'><b><font color='#%s'>%s</font></b></font>  <font size='10' color='#aab0cc'>%s</font>\n%s\n<font color='#ffe9a0'><b>%s</b></font>\n<font color='#bbbbcc'>%s</font>\n\n<b>🔫 Attack Style</b>\n<font color='#dfe6ff'>• Shot type: %s\n• %s\n• About %.1f shots/sec · Firepower %d · Range %d</font>",
			nameColor, classInfo.Name, Config.GetEraName(shown.Era), status, classInfo.Trait, classInfo.Desc,
			SHOT_NAMES[shotInfo.Style] or "Bullet", table.concat(behavior, " · "),
			rate, math.floor(power * 100 + 0.5), classInfo.Range
		),
	}, header)
	if unlocked and not isMine then
		makeButton({
			Size = UDim2.new(0, 190, 0, 40), Position = UDim2.new(1, -202, 1, -52), Text = "🔫 Fight with this weapon", BackgroundColor3 = GREEN,
		}, header, function()
			Remotes.Weapon:FireServer("Equip", previewKey)
			settings.PreviewForm = nil
			task.delay(0.3, function() settings.RefreshMenu() end)
		end)
	end

	-- 목록 대신 < > 화살표로 넘긴다 (+ 아래 무기 구슬 줄: 지금 보는 무기 / 쓰는 무기 / 잠김)
	local function show(key)
		settings.PreviewForm = key
		settings.DemoClock = 0
		settings.RefreshMenu()
	end
	local index = table.find(order, previewKey) or 1
	for _, arrow in ipairs({ { "◀", -1, UDim2.new(0, 16, 0, 108) }, { "▶", 1, UDim2.new(1, -60, 0, 108) } }) do
		local b = makeButton({ Size = UDim2.new(0, 44, 0, 44), Position = arrow[3], Text = arrow[1], TextSize = 18, Font = Enum.Font.GothamBlack, BackgroundColor3 = Color3.fromRGB(46, 50, 84), ZIndex = 6 }, header, function()
			show(order[(index - 1 + arrow[2]) % #order + 1])
		end)
		rounded(b, 22)
		create("UIStroke", { Color = Color3.fromRGB(225, 196, 118), Thickness = 1.5, Transparency = 0.3 }, b)
	end
	local pips = newRow(64, Color3.fromRGB(26, 28, 44))
	local spacing = 64
	for i, key in ipairs(order) do
		local info = Config.WeaponTypes[key]
		local look = Config.GetLookTier(level, key)
		local open = Config.IsWeaponUnlocked(level, key)
		local here = key == previewKey
		local orb = create("TextButton", {
			Size = UDim2.new(0, here and 46 or 38, 0, here and 46 or 38), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, (i - (#order + 1) / 2) * spacing, 0.5, 0),
			BackgroundColor3 = open and look.Color:Lerp(Color3.fromRGB(20, 22, 36), 0.55) or Color3.fromRGB(34, 34, 46), BorderSizePixel = 0, Text = open and (key == equippedKey and "▶" or "") or "🔒",
			TextSize = 14, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(150, 255, 170), AutoButtonColor = true,
		}, pips)
		rounded(orb, here and 23 or 19)
		create("UIStroke", { Color = here and Color3.new(1, 1, 1) or (open and look.Color or Color3.fromRGB(70, 72, 100)), Thickness = here and 3 or 1.5 }, orb)
		if i < #order then
			create("Frame", { Size = UDim2.new(0, spacing - 48, 0, 2), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, (i - (#order + 1) / 2) * spacing + 24, 0.5, 0), BackgroundColor3 = Color3.fromRGB(80, 80, 110), BorderSizePixel = 0 }, pips)
		end
		orb:SetAttribute("Tip", info.Name)
		orb.Activated:Connect(function() show(key) end)
	end
end

local function buildProgressRows(entries, remoteAction, showTitle)
	if not entries then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>Loading...</font>")
		return
	end
	-- 받을 수 있는 것 -> 진행 중 -> 받은 것 순서 (업적이 많아도 받을 것부터 보인다) + 받을 게 있으면 맨 위에 "모두 받기"
	local function rank(entry) return entry.Claimed and 3 or (entry.Progress >= entry.Goal and 1 or 2) end
	local sorted = table.clone(entries)
	for i, entry in ipairs(sorted) do entry._order = i end
	table.sort(sorted, function(a, b)
		if rank(a) ~= rank(b) then return rank(a) < rank(b) end
		return a._order < b._order
	end)
	entries = sorted
	local claimable = 0
	for _, entry in ipairs(entries) do
		if not entry.Claimed and entry.Progress >= entry.Goal then claimable += 1 end
	end
	if claimable > 0 then
		local allRow = newRow(48, Color3.fromRGB(46, 70, 52))
		makeButton({
			Size = UDim2.new(0, 220, 0, 36), Position = UDim2.new(0.5, -110, 0.5, -18), Text = string.format("🎁 Claim All (%d)", claimable),
			TextSize = 14, Font = Enum.Font.GothamBlack, BackgroundColor3 = GREEN,
		}, allRow, function()
			Remotes.Quest:FireServer("ClaimAll")
		end)
	end
	for _, entry in ipairs(entries) do
		local done = entry.Progress >= entry.Goal
		local row = newRow(66, entry.Claimed and Color3.fromRGB(32, 38, 36) or Color3.fromRGB(40, 40, 58))
		local titleText = showTitle and entry.Title and string.format("   <font color='#9ad7ff'>Title 『%s』</font>", entry.Title) or ""
		rowText(row, string.format(
			"<font size='14'><b>%s</b></font>%s\n<font color='#bbbbcc'>%s</font>\n<font color='#%s'>%d / %d</font>   <font color='#ffd966'>Reward: %s</font>",
			entry.Name, titleText, entry.Desc, done and "78ff8c" or "ffffff", entry.Progress, entry.Goal, entry.Reward
		), 14, 160)

		local label, color, enabled
		if entry.Claimed then
			label, color = "Done", GRAY
		elseif done then
			label, color, enabled = "Claim", GREEN, true
		else
			label, color = "In progress", GRAY
		end
		makeButton({
			Size = UDim2.new(0, 120, 0, 32), Position = UDim2.new(1, -132, 0.5, -16), Text = label, BackgroundColor3 = color,
		}, row, function()
			if enabled then
				Remotes.Quest:FireServer(remoteAction, entry.Id)
			end
		end)
	end
end

local function buildRankTab()
	sectionTitle("🏆 Power Ranking TOP 10 (same as the small ranking on the right of the screen)")
	if #rankList == 0 then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>Tallying...</font>")
	end
	for index, entry in ipairs(rankList) do
		local row = newRow(36, entry.Name == player.DisplayName and Color3.fromRGB(60, 52, 28) or nil)
		local medal = index == 1 and "🥇" or index == 2 and "🥈" or index == 3 and "🥉" or string.format("%d.", index)
		rowText(row, string.format("%s  <b>%s</b>   ⚡ %d", medal, entry.Name, entry.Power), 16)
	end
end

local refreshMenu
local inventoryState = nil
local growthState = nil      -- 훈련소 / 돌파 상태
local growthReceivedAt = 0

local SLOT_NAMES = {}
for _, slot in ipairs(Config.Gear.Slots) do
	SLOT_NAMES[slot.Key] = slot.Name
end

local InventoryTabModule = require(script.Parent:WaitForChild("InventoryTabUI")) -- 장비 탭 그리기는 따로 뺐다 (파일 크기 한도)
local buildInventoryTabImpl = InventoryTabModule.Init({
	player = player, create = create, rounded = rounded, makeLabel = makeLabel, makeButton = makeButton,
	GREEN = GREEN, RED = RED, GRAY = GRAY, settings = settings, menuContent = menuContent,
	newRow = newRow, rowText = rowText, hex = hex, refreshMenu = function() refreshMenu() end,
})
local function buildInventoryTab()
	buildInventoryTabImpl(inventoryState)
end

local function growthRemaining(endAt)
	return endAt - (growthState.ServerTime + (os.clock() - growthReceivedAt))
end

local function buildGrowthTab() -- (돌파 칸만: 시간 건너뛰기 / 훈련 칸 수는 맨 위 한 줄 buildSkipGaugeRow 가 보여 준다)
	local state = growthState
	if not state then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>Loading...</font>")
		return
	end

	local gateIndex
	for index, gate in ipairs(Config.Growth.Gates) do
		if gate > state.GatePassed then
			gateIndex = index
			break
		end
	end

	if not gateIndex then return end -- 돌파를 다 마쳤으면 이 칸은 아예 보여 주지 않는다
	sectionTitle("🚧 Breakthrough — pass the level caps")
	local gateRow = newRow(92)
	do
		local gateLevel = Config.Growth.Gates[gateIndex]
		local myLevel = player:GetAttribute("Level") or 1
		local text
		if state.GateJob then
			text = string.format("<font size='14'><b>Level %d Breakthrough in progress</b></font>\n<font color='#ffd966'>Time left %s</font>", state.GateJob.Level, Config.FormatDuration(growthRemaining(state.GateJob.EndAt)))
		else
			text = string.format("<font size='14'><b>Level %d Breakthrough</b></font>   (Current Lv.%d)\n<font color='#bbbbcc'>Time needed %s · 💰 %d G</font>\n<font size='11' color='#bbbbcc'>%s</font>",
				gateLevel, myLevel, Config.FormatDuration(Config.Growth.GateTime[gateIndex]), Config.Growth.GateGold[gateIndex],
				myLevel >= gateLevel and "You can break through now!" or string.format("Reach level %d to break through", gateLevel))
		end
		rowText(gateRow, text, 14, 190)

		if state.GateJob then
			makeButton({
				Size = UDim2.new(0, 160, 0, 34), Position = UDim2.new(1, -172, 0.5, -17),
				Text = "⏱ Use Time Skip", TextSize = 12, BackgroundColor3 = state.TimeSkip > 0 and Color3.fromRGB(200, 130, 40) or GRAY,
			}, gateRow, function()
				Remotes.Growth:FireServer("Skip", "Gate")
			end)
		else
			makeButton({
				Size = UDim2.new(0, 160, 0, 34), Position = UDim2.new(1, -172, 0.5, -17),
				Text = "Start Breakthrough", TextSize = 13, BackgroundColor3 = myLevel >= gateLevel and GREEN or GRAY,
			}, gateRow, function()
				Remotes.Growth:FireServer("Gate")
			end)
		end
	end
end

local metaState = nil

-- 스킬 강화 / 펫 레벨업 중인 것의 남은 시간 (서버가 UpSkill_<키> Attribute 에 끝나는 시각을 적어 둔다). 없으면 nil
local function upgradeRemaining(key)
	local endAt = player:GetAttribute("UpSkill_" .. key)
	if not endAt then return nil end
	return math.max(0, endAt - workspace:GetServerTimeNow())
end

local function anyUpgradePending()
	for _, key in ipairs(Config.Skills.UpgradeOrder) do
		if player:GetAttribute("UpSkill_" .. key) then return true end
	end
	return false
end

-- 시간 단축 게이지 (훈련 / 돌파 / 스킬 강화 / 펫이 함께 쓴다)
local function buildSkipGaugeRow() -- 성장 탭 맨 위 한 줄: ⏱ 시간 건너뛰기 보유량 + 게이지 + 훈련 칸 수
	local owned = player:GetAttribute("TimeSkip") or 0
	local row = newRow(40, Color3.fromRGB(30, 28, 46))
	makeLabel({ Size = UDim2.new(0.62, -12, 1, 0), Position = UDim2.new(0, 12, 0, 0), RichText = true, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
		Text = growthState and string.format("⏱ Time Skip <font color='#ffe16e'><b>%s</b></font> owned      🏋 Training slots <b>%d / %d</b> in use", Config.FormatDuration(owned), #growthState.Jobs, growthState.Slots)
			or string.format("⏱ Time Skip <font color='#ffe16e'><b>%s</b></font> owned", Config.FormatDuration(owned)) }, row)
	local cap = math.max(player:GetAttribute("TimeSkipCap") or 0, owned, 1)
	local gaugeBack = makePanel({ Size = UDim2.new(0.34, 0, 0, 14), Position = UDim2.new(0.64, 0, 0.5, -7), BackgroundColor3 = Color3.fromRGB(22, 24, 36) }, row)
	makePanel({ Size = UDim2.new(math.clamp(owned / cap, 0, 1), 0, 1, 0), BackgroundColor3 = Color3.fromRGB(215, 150, 60) }, gaugeBack)
end

-- 스킬 노드 상세 설명 한 줄 (TrainingTree 가 부른다)
local function skillDetail(key, level)
	local U = Config.SkillUpgrade
	local cfg = Config.Skills[key]
	local lv = level - 1
	local detail
	if key == "Barrier" then
		detail = string.format("Lasts %.1fs", cfg.Duration + U.BarrierDuration * lv)
	elseif key == "Blast" then
		detail = string.format("Radius %.1f · Damage x%.2f", cfg.Radius + U.BlastRadius * lv, cfg.Mult * (1 + U.BlastMult * lv))
	elseif key == "Focus" then
		detail = string.format("NEAR MISS lasts %.1fs · keeps at least %d stacks even if broken", Config.NearMiss.Duration + U.FocusDuration * lv, math.floor(Config.NearMiss.MaxStacks * 0.5 * lv / math.max(1, U.MaxLevel - 1)))
	elseif key == "Spirit" then
		detail = string.format("%.1fs · %d daggers every %.2fs · Damage x%.2f each", cfg.Duration, cfg.Daggers, cfg.Interval, cfg.Mult * (1 + U.BlastMult * lv))
	elseif key == "Heal" then
		detail = string.format("Restores %d%% HP", math.floor((cfg.Ratio + U.HealRatio * lv) * 100 + 0.5))
	else
		detail = string.format("Damage x%.2f · %d targets (gauge %d)", cfg.Mult * (1 + U.UltMult * lv), cfg.MaxTargets + math.floor(U.UltTargets * lv + 0.001), cfg.Cost)
	end
	return detail .. (cfg.Passive and "" or string.format(" · Cooldown %.1fs", cfg.Cooldown * (1 - U.CooldownPerLevel * lv)))
end

Remotes.Meta.OnClientEvent:Connect(function(action, data)
	if action == "State" then
		metaState = data
		if menuPanel.Visible and currentTab == "Growth" then
			refreshMenu()
		end
	end
end)

function MENU.seg(options, current, onPick)
	local row = newRow(44, Color3.fromRGB(26, 28, 42))
	for index, option in ipairs(options) do
		local active = option[1] == current
		local button = makeButton({
			Size = UDim2.new(0, 150, 0, 32), Position = UDim2.new(0, 10 + (index - 1) * 158, 0.5, -16), Text = option[2], TextSize = 13,
			BackgroundColor3 = active and Color3.fromRGB(70, 104, 206) or Color3.fromRGB(44, 48, 72),
			TextColor3 = active and Color3.fromRGB(255, 232, 160) or Color3.fromRGB(170, 176, 200),
		}, row, function()
			onPick(option[1])
		end)
		if MENU.HasClaim(option[1]) then -- 받을 보상이 있는 칸: 빨간 점
			local dot = makeLabel({ Size = UDim2.new(0, 20, 0, 20), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4), Text = "!", TextSize = 12, Font = Enum.Font.GothamBlack,
				BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(235, 60, 60), ZIndex = 5 }, button)
			create("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
			create("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.5 }, dot)
		end
	end
end

-- 퀘스트 / 업적 칸에 받을 보상이 있는가 (진행이 목표에 닿았고 아직 안 받음)
function MENU.HasClaim(key)
	local list = questState and (key == "Ach" and questState.Achievements or (key == "Daily" and questState.Daily))
	if type(list) ~= "table" then return false end
	for _, entry in ipairs(list) do
		if not entry.Claimed and (entry.Progress or 0) >= (entry.Goal or math.huge) then return true end
	end
	return false
end

function MENU.locked()
	local row = newRow(120)
	rowText(row, "<font size='19'><b>🔒 Unlocks after clearing Zone 2</b></font>\n<font size='12' color='#bbbbcc'>Open the gate of Field Zone 2 to unlock training.\nTraining continues even while offline, making you permanently stronger. (Skills / Pets are available now)</font>", 15)
end

local selectTab
function refreshMenu()
	local newGrowth = player:GetAttribute("GrowthNew") == true
	local locked = player:GetAttribute("GrowthUnlocked") ~= true
	for _, tab in ipairs(TABS) do
		local active = tab.Key == currentTab
		local button = tabButtons[tab.Key]
		button.BackgroundColor3 = active and Color3.fromRGB(70, 104, 206) or Color3.fromRGB(34, 38, 58)
		button.TextColor3 = active and Color3.fromRGB(255, 232, 160) or Color3.fromRGB(170, 176, 200)
		button.Font = active and Enum.Font.GothamBlack or Enum.Font.GothamBold
		if tab.Key == "Growth" then
			button.Text = (locked and "🔒 " or "") .. tab.Name
			local glow = button:FindFirstChild("GrowthGlow")
			if glow then glow.Enabled = newGrowth end
		end
	end

	local renderKey = currentTab .. ":" .. tostring(MENU.Sub[currentTab])
	local keepScroll = (MENU.LastKey == renderKey) and menuContent.CanvasPosition or nil -- 같은 화면을 다시 그릴 때는 스크롤 위치를 유지
	MENU.LastKey = renderKey
	clearChildren(menuContent)
	if settings.MenuInfo then settings.MenuInfo.Text = "" end -- (장비 탭이 아니면 비운다)
	rowOrder = 0
	local sub = MENU.Sub[currentTab]
	if MENU.Subs[currentTab] then
		MENU.seg(MENU.Subs[currentTab], sub, function(key)
			selectTab(currentTab, key)
		end)
	end
	if currentTab == "Character" then
		if sub == "Gear" then
			buildInventoryTab()
		elseif sub == "Weapon" then
			buildWeaponTab()
		else
			buildCharacterTab()
		end
	elseif currentTab == "Growth" then
		-- 스킬 / 훈련 / 펫을 한 화면의 특성 나무로 (TrainingTree 모듈)
		buildSkipGaugeRow() -- 시간 건너뛰기는 맨 위 한 줄
		local okTree, treeErr = pcall(function()
			require(ReplicatedStorage:WaitForChild("TrainingTree", 5)).BuildAll({
				Config = Config, Remotes = Remotes, Player = player, Meta = metaState, Growth = growthState, Remaining = growthRemaining,
				UpgradeRemaining = upgradeRemaining, SkillDetail = skillDetail, TrainLocked = locked or nil,
				NewRow = newRow, MakeLabel = makeLabel, MakeButton = makeButton, Create = create, GREEN = GREEN, GRAY = GRAY, Refresh = refreshMenu,
			})
		end)
		if not okTree then warn("[TrainingTree] " .. tostring(treeErr)) end
		if not locked then buildGrowthTab() end -- 돌파는 나무 아래에
	elseif currentTab == "Quest" then
		if sub == "Ach" then
			sectionTitle("🏅 Achievements — earn rewards and titles")
			buildProgressRows(questState and questState.Achievements, "ClaimAch", true)
		else
			sectionTitle("📅 Today's Daily Quests (changes every day)")
			buildProgressRows(questState and questState.Daily, "Claim", false)
		end
	elseif currentTab == "Rank" then
		buildRankTab()
	end
	if keepScroll then menuContent.CanvasPosition = keepScroll end
end
settings.RefreshMenu = refreshMenu

function selectTab(key, subKey)
	if key == "Shop" then
		player:SetAttribute("OpenShop", os.clock()) -- 상점은 ShopClient 가 연다
		return
	end
	local alias = MENU.Alias[key]
	if alias then key, subKey = alias[1], subKey or alias[2] end
	if key == "Growth" and subKey == "Pet" then -- 펫은 한 번 더 들어가지 않고 바로 펫 창(P)을 연다
		menuPanel.Visible = false
		player:SetAttribute("OpenPet", os.clock())
		return
	end
	currentTab = key
	if subKey and MENU.Subs[key] then MENU.Sub[key] = subKey end
	if key == "Growth" and not subKey and (player:GetAttribute("GrowthNew") == true or (player:GetAttribute("TutorialActive") == true and player:GetAttribute("GrowthUnlocked") == true)) then
		MENU.Sub.Growth = "Passive" -- 방금 해금된 훈련을 바로 보여 준다
	end
	local sub = MENU.Sub[key]
	if key == "Quest" or key == "Character" then
		Remotes.Quest:FireServer("Request")
	end
	if key == "Rank" then
		Remotes.Rank:FireServer("Request")
	elseif key == "Character" and sub == "Gear" then
		Remotes.Inventory:FireServer("Request")
	elseif key == "Growth" then
		Remotes.Growth:FireServer("Request")
		Remotes.Meta:FireServer("Request")
		if player:GetAttribute("GrowthNew") then Remotes.Growth:FireServer("Seen") end
	end
	refreshMenu()
end

local tabWidth = 140
for index, tab in ipairs(TABS) do
	tabButtons[tab.Key] = makeButton({
		Size = UDim2.new(0, tabWidth, 0, 36), Position = UDim2.new(0, 14 + (index - 1) * (tabWidth + 6), 0, 50), Text = tab.Name, TextSize = 14,
	}, menuPanel, function()
		selectTab(tab.Key)
	end)
end
do
	local glow = create("UIStroke", { Name = "GrowthGlow", Color = Color3.fromRGB(255, 225, 90), Thickness = 3, Enabled = false, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tabButtons.Growth)
	TweenService:Create(glow, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 7 }):Play()
end

local menuToggleAt = 0
local function toggleMenu()
	local now = os.clock()
	if now - menuToggleAt < 0.15 then return end
	menuToggleAt = now
	menuPanel.Visible = not menuPanel.Visible
	if menuPanel.Visible then
		local shopGui = player.PlayerGui:FindFirstChild("ShopGui") -- 큰 창은 한 번에 하나 (상점은 ShopClient)
		local shopPanel = shopGui and shopGui:FindFirstChild("ShopPanel")
		if shopPanel then shopPanel.Visible = false end
		local ok, err = pcall(selectTab, currentTab)
		if not ok then warn("[Menu] " .. tostring(err)) end
	end
end

do
	local menuButton = makeButton({
		Name = "MenuButton", Size = UDim2.new(0, 78, 0, 32), Position = UDim2.new(0, 16, 0, 244), Text = "📋 Menu(B)", TextSize = 10,
		BackgroundColor3 = Color3.fromRGB(34, 40, 70),
	}, gui, toggleMenu)
	local menuStroke = create("UIStroke", { Color = Color3.fromRGB(110, 130, 220), Thickness = 1.5, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, menuButton)
	local pulse = TweenService:Create(menuStroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 5 })
	local function syncPulse()
		if player:GetAttribute("GrowthNew") == true then
			menuStroke.Color = Color3.fromRGB(255, 225, 90)
			menuStroke.Transparency = 0
			pulse:Play()
		else
			pulse:Cancel()
			menuStroke.Color, menuStroke.Thickness, menuStroke.Transparency = Color3.fromRGB(110, 130, 220), 1.5, 0.35
		end
	end
	player:GetAttributeChangedSignal("GrowthNew"):Connect(syncPulse)
	syncPulse()
end

Remotes.Quest.OnClientEvent:Connect(function(action, data)
	if action == "State" then
		questState = data
		local ready = false
		for _, list in ipairs({ data and data.Daily or {}, data and data.Achievements or {} }) do
			for _, entry in ipairs(list) do
				if not entry.Claimed and entry.Progress >= entry.Goal then ready = true end
			end
		end
		player:SetAttribute("DotQuest", ready) -- 왼쪽 메뉴 버튼의 빨간 점
		if menuPanel.Visible then
			refreshMenu()
		end
	end
end)

Remotes.Inventory.OnClientEvent:Connect(function(action, data)
	if action == "State" then
		inventoryState = data
		local better = false -- 가방에 지금 입은 것보다 좋은 장비가 있으면 왼쪽 메뉴 버튼에 빨간 점
		local worn = {}
		for _, item in ipairs(data and data.Items or {}) do
			if item.Equipped then worn[item.Slot] = item end
		end
		for _, item in ipairs(data and data.Items or {}) do
			if not item.Equipped and (not worn[item.Slot] or item.Score > worn[item.Slot].Score) then better = true break end
		end
		player:SetAttribute("DotGear", better)
		if menuPanel.Visible and currentTab == "Character" and MENU.Sub.Character == "Gear" then
			refreshMenu()
		end
	end
end)

Remotes.Gear.OnClientEvent:Connect(function(action, result) -- 메뉴에서 장비를 강화했을 때 결과를 바로 알려 준다
	if action == "Result" and menuPanel.Visible and result and not result.Roll and result.Message then
		toast(result.Message)
	end
end)

Remotes.Growth.OnClientEvent:Connect(function(action, data)
	if action == "State" then
		growthState = data
		growthReceivedAt = os.clock()
		if menuPanel.Visible and (currentTab == "Growth" or currentTab == "Character") then
			refreshMenu()
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(1)
		if menuPanel.Visible and currentTab == "Growth" and (MENU.Sub.Growth == "Passive" or anyUpgradePending()) then
			refreshMenu()
		end
	end
end)

Remotes.Rank.OnClientEvent:Connect(function(action, data)
	if action == "List" then
		rankList = data
		if menuPanel.Visible and currentTab == "Rank" then
			refreshMenu()
		end
	end
end)

-- 메뉴 자동 갱신: 방치 중에는 골드 / 방치 게이지 속성이 매초 바뀌므로, 전부 다시 그리면 창이 툭툭 끊겨 보인다.
-- 화면에 영향이 없는 값은 무시하고, 골드 / 경험치처럼 자주 바뀌는 값은 2초에 한 번만 갱신한다.
do -- (이 구역의 지역 변수는 아래에서 쓰지 않는다: 맨 바깥 지역 변수 200개 한도 여유를 만들려고 블록으로 감쌌다)
local menuRefreshQueued = false
local MENU_IGNORE = {
	IdleSeconds = true, IdleEarned = true, IdleRate = true, IdleMultTotal = true, IdleCapHours = true, IdleFullGold = true, IdleActive = true,
	DummyDps = true, DummyTick = true, UltCharge = true, Combo = true, ShakeTick = true, ShakeStrength = true, NearMissStacks = true,
	NearMissEnd = true, NearMissLen = true, Power = true, Stamina = true, DungeonLabel = true,
}
local MENU_SLOW = { Gold = true, XP = true, XPNeeded = true }
local lastMenuRefresh = 0
local lastMenuClick = 0 -- 메뉴에서 마지막으로 누른 시각: 방금 누른 것(강화 / 장착 ...)의 결과만 바로 보여 주고, 싸우면서 바뀌는 값은 천천히
UserInputService.InputBegan:Connect(function(input)
	if menuPanel.Visible and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
		lastMenuClick = os.clock()
	end
end)
player.AttributeChanged:Connect(function(name)
	if not menuPanel.Visible or menuRefreshQueued or MENU_IGNORE[name] then return end
	menuRefreshQueued = true
	-- (싸우는 중 메뉴를 열어 두면 처치할 때마다 바뀌는 값 때문에 메뉴 전체(3D 미리보기 포함)를 계속 다시 그려 렉이 걸렸다:
	--  방금 메뉴를 누른 게 아니면 2.5초에 한 번만 다시 그린다)
	local recentClick = os.clock() - lastMenuClick < 1.5
	local wait = (recentClick and not MENU_SLOW[name]) and 0 or math.max(0, 2.5 - (os.clock() - lastMenuRefresh))
	task.delay(wait, function()
		menuRefreshQueued = false
		if menuPanel.Visible then
			lastMenuRefresh = os.clock()
			refreshMenu()
		end
	end)
end)

end -- (지역 변수 범위 블록 끝)
local refreshSelect
local selectedType = "Cave"
local selectedDifficulty = "Normal"

local selectPanel = makePanel({
	Size = UDim2.new(0, 890, 0, 500),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Visible = false,
}, gui)

makeLabel({
	Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 8),
	Text = "⚔ Select Dungeon", Font = Enum.Font.GothamBlack, TextSize = 20,
}, selectPanel)

do -- (이 구역의 지역 변수는 아래에서 쓰지 않는다: 맨 바깥 지역 변수 200개 한도 여유를 만들려고 블록으로 감쌌다)
local typeCards = {}
for index, key in ipairs(Config.Dungeon.Types.Order) do
	local info = Config.Dungeon.Types[key]
	local card = makeButton({
		Size = UDim2.new(0, 200, 0, 170), Position = UDim2.new(0, 14 + (index - 1) * 212, 0, 54),
		Text = "", BackgroundColor3 = Color3.fromRGB(40, 40, 58), AutoButtonColor = true,
	}, selectPanel, function()
		selectedType = key
		refreshSelect()
	end)
	create("UIStroke", { Color = info.Torch, Thickness = 0, Name = "Stroke" }, card)
	makeLabel({
		Size = UDim2.new(1, -16, 1, -12), Position = UDim2.new(0, 8, 0, 6), RichText = true,
		Text = string.format("<font size='17'><b>%s</b></font>\n\n<font color='#bbbbcc' size='11'>%s</font>\n\n%s\nRecommended Power %d",
			info.Name, info.Desc, string.format("Survive %ds + Boss", Config.Dungeon.GetSurviveSeconds(info.Waves)), info.RecommendedPower),
		TextSize = 13, TextYAlignment = Enum.TextYAlignment.Top,
	}, card)
	typeCards[key] = card
end

makeLabel({
	Size = UDim2.new(1, -28, 0, 22), Position = UDim2.new(0, 14, 0, 236),
	Text = "Difficulty", Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
}, selectPanel)

local difficultyButtons = {}
for index, key in ipairs(Config.Dungeon.Difficulties.Order) do
	local info = Config.Dungeon.Difficulties[key]
	difficultyButtons[key] = makeButton({
		Size = UDim2.new(0, 200, 0, 40), Position = UDim2.new(0, 14 + (index - 1) * 212, 0, 262),
		Text = string.format("%s  %s", info.Name, Config.Keys.TierIcons[info.KeyTier or 1]), TextSize = 15, BackgroundColor3 = GRAY,
	}, selectPanel, function()
		selectedDifficulty = key
		refreshSelect()
	end)
end

makeButton({ Size = UDim2.new(0, 150, 0, 28), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 234), Text = "📊 Chest Odds", TextSize = 13, BackgroundColor3 = Color3.fromRGB(60, 72, 130) }, selectPanel, function()
	player:SetAttribute("OddsKind", "Chest") -- 보스 상자 확률 (유료 랜덤 아이템 정책: 열쇠로 들어가는 던전의 상자)
	player:SetAttribute("OddsOpen", os.clock())
end)

local summaryLabel = makeLabel({
	Size = UDim2.new(1, -28, 0, 110), Position = UDim2.new(0, 14, 0, 314), RichText = true,
	TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
}, selectPanel)

function refreshSelect()
	for key, card in pairs(typeCards) do
		card.Stroke.Thickness = key == selectedType and 3 or 0
	end
	for key, button in pairs(difficultyButtons) do
		local info = Config.Dungeon.Difficulties[key]
		button.BackgroundColor3 = key == selectedDifficulty and info.Color:Lerp(Color3.fromRGB(30, 30, 40), 0.35) or GRAY
	end

	local dungeonType = Config.Dungeon.Types[selectedType]
	local difficulty = Config.Dungeon.Difficulties[selectedDifficulty]
	summaryLabel.Text = string.format(
		"<b>%s · %s</b>\n%s → Boss <font color='#ff9a9a'>%s</font>\nRecommended Power <font color='#ffe16e'>%d</font>  (Your Power %d)\nGold x%.1f · Tickets %d · Boss chest gear %d\n🎟 Free entries today <b>%d / %d</b> · After that you need <b>🔑 %d Key(s)</b> (you have %d)\n🔑 Keys are dropped by field zone lords (more and more often in later zones). Easy 1 · Normal 2 · Hard 3",
		dungeonType.Name, difficulty.Name, string.format("Survive %ds", Config.Dungeon.GetSurviveSeconds(dungeonType.Waves)), dungeonType.Boss.Name,
		Config.DungeonPower(dungeonType, difficulty), player:GetAttribute("Power") or 0,
		dungeonType.GoldMult * difficulty.GoldMult, difficulty.Tickets, Config.Loot.DungeonChestCount,
		player:GetAttribute("DungeonFree") or 0, Config.Keys.FreeDaily, difficulty.KeyCost,
		player:GetAttribute("Keys") or 0
	)
end

makeButton({
	Size = UDim2.new(0, 280, 0, 46), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14),
	Text = "Enter", TextSize = 17, BackgroundColor3 = GREEN,
}, selectPanel, function()
	selectPanel.Visible = false
	Remotes.Dungeon:FireServer("Start", selectedType, selectedDifficulty)
end)

makeButton({
	Size = UDim2.new(0, 280, 0, 46), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -14),
	Text = "Close", TextSize = 17, BackgroundColor3 = GRAY,
}, selectPanel, function()
	selectPanel.Visible = false
end)

openDungeonSelect = function()
	refreshSelect()
	selectPanel.Visible = true
end

player:GetAttributeChangedSignal("Zone"):Connect(function()
	if currentZone() == "Dungeon" then
		selectPanel.Visible = false
	end
	lockTarget = nil
	updateLockVisual()
end)

end -- (지역 변수 범위 블록 끝)
local warpPanel = makePanel({
	Size = UDim2.new(0, 440, 0, 520),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Visible = false,
}, gui)

makeLabel({
	Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 8),
	Text = "⛺ Warp", Font = Enum.Font.GothamBlack, TextSize = 20,
}, warpPanel)
makeLabel({
	Size = UDim2.new(1, -28, 0, 36), Position = UDim2.new(0, 14, 0, 44),
	Text = "Warp to the camp of any zone you've reached. If you die in the field, you respawn at the nearest camp.",
	TextSize = 11, TextColor3 = Color3.fromRGB(190, 190, 210),
}, warpPanel)

local warpList = create("Frame", { Size = UDim2.new(1, -28, 1, -140), Position = UDim2.new(0, 14, 0, 84), BackgroundTransparency = 1 }, warpPanel)
create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, warpList)

makeButton({
	Size = UDim2.new(1, -28, 0, 36), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14),
	Text = "Close", TextSize = 14, BackgroundColor3 = GRAY,
}, warpPanel, function()
	warpPanel.Visible = false
end)

local function refreshWarp()
	clearChildren(warpList)
	local reached = math.max(1, player:GetAttribute("MaxZone") or 0)

	local function addRow(order, text, unlocked, zone)
		makeButton({
			Size = UDim2.new(1, 0, 0, 36), LayoutOrder = order, Text = text, TextSize = 13,
			BackgroundColor3 = unlocked and Color3.fromRGB(60, 90, 160) or GRAY, TextXAlignment = Enum.TextXAlignment.Left,
		}, warpList, function()
			if unlocked then
				warpPanel.Visible = false
				Remotes.Warp:FireServer("Go", zone)
			end
		end)
	end

	addRow(0, "  🏠 Town (Lobby)", true, 0)
	for zone = 1, Config.Field.ZoneCount do
		local unlocked = zone <= reached
		local zoneSet = Config.Sets[Config.Sets.ZoneKeys[zone]]
		addRow(zone, string.format("  %s Zone %d · %s   (Rec. ⚡%d)  %s %s Set", unlocked and "⛺" or "🔒", zone, Config.Field.ZoneNames[zone], Config.Field.RecommendPower[zone] or 0, zoneSet.Icon, zoneSet.Name), unlocked, zone)
	end
end

do -- (파일 뒷부분은 블록 안에: 맨 바깥 지역 변수가 Luau 한도 200개를 넘으면 스크립트 전체가 시작하자마자 멈춘다 - "Out of local registers")
player:GetAttributeChangedSignal("Zone"):Connect(function()
	if currentZone() == "Dungeon" then
		warpPanel.Visible = false
	end
end)

Remotes.Warp.OnClientEvent:Connect(function(action, seconds)
	if action == "Open" then
		refreshWarp()
		warpPanel.Visible = true
	elseif action == "Cast" then -- 이동 연출: 화면이 연한 푸른빛으로 밝아졌다가 이동 직후 걷힌다
		local fade = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(150, 190, 245), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 95, Active = false }, gui)
		TweenService:Create(fade, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { BackgroundTransparency = 0.35 }):Play()
		task.delay(seconds or 1, function()
			TweenService:Create(fade, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
			game:GetService("Debris"):AddItem(fade, 0.6)
		end)
	end
end)

do
local hurtFlash = create("Frame", {
	Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(220, 20, 20), BackgroundTransparency = 1,
	BorderSizePixel = 0, ZIndex = 0, Active = false,
}, gui)
local flashStrength = 0
local lowHealthRatio = 1

local comboLabel = makeLabel({
	Size = UDim2.new(0, 260, 0, 60), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0.4, 0),
	Font = Enum.Font.GothamBlack, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Right, Visible = false,
	TextColor3 = Color3.fromRGB(255, 190, 60), TextStrokeTransparency = 0.2,
}, gui)

local function watchHealth(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	local last = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < last - 0.5 then
			flashStrength = math.clamp(flashStrength + (last - health) / humanoid.MaxHealth * 3 + 0.25, 0, 0.6)
		end
		last = health
		lowHealthRatio = health / math.max(1, humanoid.MaxHealth)
	end)
end
if player.Character then
	task.spawn(watchHealth, player.Character)
end
player.CharacterAdded:Connect(watchHealth)

RunService.RenderStepped:Connect(function(dt)
	flashStrength = math.max(0, flashStrength - dt * 1.4)
	local pulse = 0
	if lowHealthRatio < 0.3 and lowHealthRatio > 0 then
		pulse = (0.12 + 0.1 * math.sin(os.clock() * 6)) * (1 - lowHealthRatio / 0.3)
	end
	hurtFlash.BackgroundTransparency = 1 - math.max(flashStrength, pulse)

	local combo = player:GetAttribute("Combo") or 0
	comboLabel.Visible = combo >= 2
	if combo >= 2 then
		local bonus = math.min(Config.Combo.MaxStacks, combo) * Config.Combo.DamagePerStack
		comboLabel.Text = string.format("🔥 Combo x%d\nDamage +%d%%", combo, math.floor(bonus * 100 + 0.5))
		comboLabel.TextSize = math.clamp(24 + combo * 0.4, 24, 40)
		local left = (player:GetAttribute("ComboUntil") or 0) - os.clock()
		comboLabel.TextTransparency = left < 1 and 0.5 or 0
	end
end)
end


local useSkill
local skillByKey = {}
local skillSlots = {}
local skillCooldownTotal = {}
local skillReadyAt = {}
local skillBar = create("Frame", {
	Name = "SkillBar", Size = UDim2.new(0, (#Config.Skills.Order + 1) * 68, 0, 64), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
	BackgroundTransparency = 1, Visible = false,
}, gui)
for index, skillKey in ipairs(Config.Skills.Order) do
	local cfg = Config.Skills[skillKey]
	skillByKey[Enum.KeyCode[cfg.KeyCode]] = skillKey
	local slot = create("Frame", {
		Size = UDim2.new(0, 62, 0, 62), Position = UDim2.new(0, index * 68, 0, 0),
		BackgroundColor3 = Theme.SLOT, BorderSizePixel = 0,
	}, skillBar)
	rounded(slot)
	local slotStroke = create("UIStroke", { Color = skillKey == "Ult" and Color3.fromRGB(255, 90, 90) or Color3.fromRGB(110, 150, 220), Thickness = 3 }, slot)
	makeLabel({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 4), Text = cfg.Icon, TextSize = 20 }, slot)
	makeLabel({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 34), Text = cfg.Name, TextSize = 9 }, slot)
	makeLabel({ Size = UDim2.new(0, 18, 0, 16), Position = UDim2.new(0, 3, 0, 3), Text = cfg.Key, TextSize = 10, Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(255, 220, 90) }, slot)
	local cover = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0,
	}, slot)
	rounded(cover)
	local timer = makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = "", TextSize = 17, Font = Enum.Font.GothamBlack }, slot)
	if UserInputService.TouchEnabled then
		local tap = create("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 5 }, slot)
		tap.Activated:Connect(function()
			useSkill(skillKey)
		end)
	end
	skillSlots[skillKey] = { Cover = cover, Timer = timer, Stroke = slotStroke, Slot = slot }
end

-- 지금 쓸 수 없는 스킬을 누르면 (쿨타임 / 게이지 부족 / 주변에 적 없음) 그 칸이 하얗게 번쩍이며 좌우로 흔들린다
function settings.ShakeSlot(ui)
	if not ui or not ui.Slot or ui.Shaking then return end
	ui.Shaking = true
	local base = ui.Slot.Position
	local flash = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 6 }, ui.Slot)
	rounded(flash)
	TweenService:Create(flash, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
	task.spawn(function()
		for i = 1, 6 do
			ui.Slot.Position = base + UDim2.new(0, (i % 2 == 0 and 1 or -1) * (7 - i), 0, 0)
			task.wait(0.035)
		end
		ui.Slot.Position = base
		flash:Destroy()
		ui.Shaking = false
	end)
end
function settings.ShakeSkill(skillKey)
	settings.ShakeSlot(skillSlots[skillKey])
end

do
	local slot = create("Frame", { Size = UDim2.new(0, 62, 0, 62), Position = UDim2.new(0, 0, 0, 0), BackgroundColor3 = Theme.SLOT, BorderSizePixel = 0 }, skillBar)
	rounded(slot)
	create("UIStroke", { Color = Color3.fromRGB(120, 210, 255), Thickness = 2 }, slot)
	settings.DashUi = { Slot = slot }
	makeLabel({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 4), Text = "💨", TextSize = 20 }, slot)
	makeLabel({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 34), Text = "Dash", TextSize = 9 }, slot)
	makeLabel({ Size = UDim2.new(0, 18, 0, 16), Position = UDim2.new(0, 3, 0, 3), Text = "Q", TextSize = 10, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 220, 90) }, slot)
	local cover = create("Frame", { Size = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0 }, slot)
	rounded(cover)
	local charges = makeLabel({ Size = UDim2.new(0, 20, 0, 18), Position = UDim2.new(1, -22, 0, 3), TextSize = 12, Font = Enum.Font.GothamBlack }, slot)
	local timer = makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = "", TextSize = 17, Font = Enum.Font.GothamBlack }, slot)
	if UserInputService.TouchEnabled then
		create("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 5 }, slot).Activated:Connect(function()
			slide()
		end)
	end
	RunService.RenderStepped:Connect(function()
		local P = Config.Player
		local now = os.clock()
		if settings.DashCharges < P.DashCharges and now >= settings.DashRefillAt then
			settings.DashCharges += 1
			settings.DashRefillAt = settings.DashCharges < P.DashCharges and now + P.DashCooldown or 0
		end
		charges.Text = tostring(settings.DashCharges)
		charges.TextColor3 = settings.DashCharges > 0 and Color3.fromRGB(150, 230, 255) or Color3.fromRGB(255, 120, 120)
		if settings.DashCharges < P.DashCharges then
			local remain = settings.DashRefillAt - now
			cover.Size = UDim2.new(1, 0, settings.DashCharges == 0 and math.clamp(remain / P.DashCooldown, 0, 1) or 0.25, 0)
			timer.Text = settings.DashCharges == 0 and string.format("%.1f", math.max(0, remain)) or ""
		else
			cover.Size = UDim2.new(1, 0, 0, 0)
			timer.Text = ""
		end
	end)
end

function useSkill(skillKey)
	local zone = currentZone()
	if zone ~= "Field" and zone ~= "Dungeon" then
		toast("Skills can only be used in the field and dungeons.")
		return
	end
	if os.clock() < (skillReadyAt[skillKey] or 0) then
		settings.ShakeSkill(skillKey) -- 쿨타임 중: 칸만 흔들린다
		return
	end
	-- 주변에 적이 없으면 (데드아이 / 죽음의 연꽃) 서버에 보내지 않고 칸만 흔들린다 (알림이 쌓이지 않게)
	local function enemyWithin(range)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root then return false end
		for _, monster in ipairs(game:GetService("CollectionService"):GetTagged("Monster")) do
			if monster:IsA("BasePart") and (monster.Position - root.Position).Magnitude <= range then return true end
		end
		return false
	end
	if skillKey == "Spirit" and not enemyWithin((Config.Skills.Spirit.Range or 44) + 5) then
		settings.ShakeSkill(skillKey)
		return
	end
	if skillKey == "Ult" then
		if (player:GetAttribute("UltCharge") or 0) < Config.Skills.Ult.Cost then
			settings.ShakeSkill(skillKey) -- (게이지가 덜 찼을 때 누르면 알림 대신 V 칸만 번쩍이며 흔들린다: 연타하면 알림이 x6 처럼 쌓이던 것)
			return
		end
		if not enemyWithin(Config.Skills.Ult.Radius + 5) then
			settings.ShakeSkill(skillKey)
			return
		end
	end
	Remotes.Skill:FireServer("Use", skillKey, getAimPoint(UserInputService:GetMouseLocation()))
end

Remotes.Skill.OnClientEvent:Connect(function(action, skillKey, cooldown)
	if action == "Cast" and Config.Skills[skillKey] then
		skillCooldownTotal[skillKey] = cooldown or Config.Skills[skillKey].Cooldown
		skillReadyAt[skillKey] = os.clock() + skillCooldownTotal[skillKey]
		if skillKey == "Ult" then
			local flash = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 70, 60), BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 58, Active = false }, gui)
			TweenService:Create(flash, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			task.delay(0.5, function() flash:Destroy() end)
			local big = makeLabel({ Size = UDim2.new(1, 0, 0, 120), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.3, 0), Text = "◎ DEADEYE ◎", Font = Enum.Font.GothamBlack, TextSize = 54, TextColor3 = Color3.fromRGB(255, 60, 60), TextStrokeTransparency = 0, ZIndex = 60 }, gui)
			TweenService:Create(big, TweenInfo.new(1.6), { TextTransparency = 1, TextStrokeTransparency = 1, Position = UDim2.new(0.5, 0, 0.24, 0) }):Play()
			task.delay(1.7, function() big:Destroy() end)
		end
	end
end)

RunService.RenderStepped:Connect(function()
	local zone = currentZone()
	skillBar.Visible = (zone == "Lobby" or zone == "Field" or zone == "Dungeon") and not (player:GetAttribute("ModalOpen") == true and gui.Parent:GetAttribute("UiCompact") ~= true) -- (큰 화면: 큰 창이 열려 있는 동안은 창 위에 겹쳐 보이지 않게 숨긴다)
	if not skillBar.Visible then return end
	for skillKey, slot in pairs(skillSlots) do
		local cfg = Config.Skills[skillKey]
		local remain = (skillReadyAt[skillKey] or 0) - os.clock()
		if skillKey == "Ult" then
			local charge = player:GetAttribute("UltCharge") or 0
			local full = charge >= cfg.Cost
			slot.Cover.Size = UDim2.new(1, 0, 1 - math.clamp(charge / cfg.Cost, 0, 1), 0)
			slot.Timer.Text = full and "" or string.format("%d%%", math.floor(charge))
			slot.Timer.TextSize = 14
			slot.Stroke.Thickness = full and (3 + 2 * math.abs(math.sin(os.clock() * 5))) or 2
			slot.Stroke.Color = full and Color3.fromRGB(255, 225, 90) or Color3.fromRGB(255, 90, 90)
			-- 처음 게이지가 가득 찼을 때 한 번만: 스킬 버튼 바로 위에 작은 표식 (메시지 카드 대신 눈에 잘 띄는 자리). 초반(레벨 10 이하)에만, 쓰거나 12초가 지나면 사라진다
			if full and not slot.CueDone and (player:GetAttribute("Level") or 1) <= 10 and not player:GetAttribute("UltCueShown") then
				slot.CueDone = true
				player:SetAttribute("UltCueShown", true)
				local cue = create("TextLabel", {
					Name = "UltCue", Size = UDim2.new(0, 96, 0, 26), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -8),
					BackgroundColor3 = Color3.fromRGB(46, 38, 20), BackgroundTransparency = 0.05, BorderSizePixel = 0, Font = Enum.Font.GothamBlack, TextSize = 13,
					TextColor3 = Color3.fromRGB(255, 225, 120), Text = UserInputService.TouchEnabled and "▼ Tap Deadeye!" or "▼ Press V!", ZIndex = 20,
				}, slot.Slot)
				rounded(cue, 8)
				create("UIStroke", { Color = Color3.fromRGB(255, 217, 102), Thickness = 1.5 }, cue)
				-- 놓칠 수 없게: 캐릭터 머리 위에도 큼직한 스킬 아이콘 + "PRESS V" 를 띄운다 (처음 한 번만, 쓰거나 12초가 지나면 사라진다)
				local board
				local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if rootPart then
					board = create("BillboardGui", {
						Name = "UltCueBillboard", Adornee = rootPart, Size = UDim2.new(0, 200, 0, 170), StudsOffset = Vector3.new(0, 7.5, 0),
						AlwaysOnTop = true, MaxDistance = 300, ResetOnSpawn = false,
					}, player:WaitForChild("PlayerGui"))
					local scale = create("UIScale", { Scale = 1 }, board)
					local glowRing = create("Frame", { Size = UDim2.new(0, 128, 0, 128), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -4), BackgroundColor3 = Color3.fromRGB(255, 217, 102), BackgroundTransparency = 0.7, BorderSizePixel = 0 }, board)
					create("UICorner", { CornerRadius = UDim.new(1, 0) }, glowRing)
					local disc = create("Frame", { Size = UDim2.new(0, 96, 0, 96), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), BackgroundColor3 = Color3.fromRGB(40, 32, 18), BackgroundTransparency = 0.05, BorderSizePixel = 0 }, board)
					create("UICorner", { CornerRadius = UDim.new(1, 0) }, disc)
					create("UIStroke", { Color = Color3.fromRGB(255, 217, 102), Thickness = 3.5 }, disc)
					makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = cfg.Icon, TextSize = 58 }, disc)
					local pill = create("Frame", { Size = UDim2.new(0, 170, 0, 38), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 116), BackgroundColor3 = Color3.fromRGB(40, 32, 18), BackgroundTransparency = 0.05, BorderSizePixel = 0 }, board)
					rounded(pill, 10)
					create("UIStroke", { Color = Color3.fromRGB(255, 217, 102), Thickness = 2 }, pill)
					makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = UserInputService.TouchEnabled and "TAP DEADEYE!" or "PRESS  [ V ]", TextSize = 19, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 225, 120) }, pill)
					pcall(function() if SoundBank.Has("Rare_Drop") then SoundBank.Play(sfxParent, "Rare_Drop", { Volume = 0.9 }) end end)
					task.spawn(function()
						local began = os.clock()
						while board.Parent and os.clock() - began < 12 and (player:GetAttribute("UltCharge") or 0) >= cfg.Cost do
							local t = os.clock() - began
							scale.Scale = 1 + 0.1 * math.sin(t * 6)
							glowRing.BackgroundTransparency = 0.55 + 0.3 * (0.5 + 0.5 * math.sin(t * 6))
							task.wait()
						end
						board:Destroy()
					end)
				end
				task.spawn(function()
					local started = os.clock()
					while cue.Parent and os.clock() - started < 12 and (player:GetAttribute("UltCharge") or 0) >= cfg.Cost do
						cue.Position = UDim2.new(0.5, 0, 0, -8 - 4 * math.abs(math.sin((os.clock() - started) * 4)))
						task.wait()
					end
					cue:Destroy()
				end)
			end
		elseif remain > 0 then
			slot.Cover.Size = UDim2.new(1, 0, math.clamp(remain / (skillCooldownTotal[skillKey] or cfg.Cooldown), 0, 1), 0)
			slot.Timer.Text = string.format("%.0f", math.ceil(remain))
		else
			slot.Cover.Size = UDim2.new(1, 0, 0, 0)
			slot.Timer.Text = ""
		end
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holding = true
	elseif input.KeyCode == Enum.KeyCode.H then
		toggleHelp()
	elseif skillByKey[input.KeyCode] then
		useSkill(skillByKey[input.KeyCode])
	elseif input.KeyCode == Enum.KeyCode.Q then
		slide()
	elseif input.KeyCode == Enum.KeyCode.R then
		toggleAuto()
	elseif input.KeyCode == Enum.KeyCode.I or input.KeyCode == Enum.KeyCode.B then
		toggleMenu()
	elseif input.KeyCode == Enum.KeyCode.M then
		toggleMusic()
	elseif input.UserInputType == Enum.UserInputType.Touch then
		local inset = GuiService:GetGuiInset()
		attack(Vector2.new(input.Position.X, input.Position.Y) + inset)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holding = false
	end
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now < nextAttack then return end

	if holding then
		nextAttack = now + attackCooldown()
		attack(UserInputService:GetMouseLocation())
	elseif autoMode then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 then return end

		if not isTargetValid(lockTarget, root) and now >= nextSearch then
			nextSearch = now + 0.4
			lockTarget = findNearestTarget(root)
			updateLockVisual()
		end
		if lockTarget and isTargetValid(lockTarget, root) then
			nextAttack = now + attackCooldown()
			fireAt(lockTarget.Part.Position)
		end
	end
end)

local hasMouse = UserInputService.MouseEnabled
local playerGui = player:WaitForChild("PlayerGui")

local crosshair = create("Frame", {
	Name = "Crosshair", Size = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 1, Visible = false, ZIndex = 100,
}, gui)

local function makeCrosshairPart(width, height)
	local part = create("Frame", {
		Size = UDim2.new(0, width, 0, height), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 100,
	}, crosshair)
	create("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, part)
	return part
end

local barUp = makeCrosshairPart(2, 11)
local barDown = makeCrosshairPart(2, 11)
local barLeft = makeCrosshairPart(11, 2)
local barRight = makeCrosshairPart(11, 2)
local centerDot = makeCrosshairPart(3, 3)

local overPos, overResult, overAt = nil, false, 0
local function isMouseOverButton(position) -- (매 프레임 불린다: 마우스가 그대로면 0.15초 동안 결과를 재사용)
	local now = os.clock()
	if overPos == position and now - overAt < 0.15 then return overResult end
	overPos, overAt, overResult = position, now, false
	-- 마우스 위치는 위쪽 바(약 36픽셀)를 포함한 값이라, 화면 안쪽 기준(IgnoreGuiInset 가 꺼진 화면)과 전체 기준 둘 다 확인한다 (한쪽만 보면 DPS 미터기 같은 곳 위에서 커서가 십자선으로 남는다)
	local inset = GuiService:GetGuiInset()
	for _, point in ipairs({ position, position - inset }) do
		for _, object in ipairs(playerGui:GetGuiObjectsAtPosition(point.X, point.Y)) do
			if object.Visible and (object:IsA("GuiButton") or object.Active) then
				overResult = true
				break
			end
		end
		if overResult then break end
	end
	return overResult
end

local otherModalOpen, otherModalUntil = false, 0
RunService.RenderStepped:Connect(function(dt)
	local helpOpen = gui:FindFirstChild("HelpPanel")
	local modalOpen = menuPanel.Visible or enhancePanel.Visible or gearPanel.Visible or selectPanel.Visible or warpPanel.Visible or (helpOpen ~= nil and helpOpen.Visible) -- (설정 창도 큰 창: 아래 HUD 가 비쳐 보이지 않게)
	if not modalOpen and os.clock() < otherModalUntil then
		modalOpen = otherModalOpen -- (다른 창 훑기는 0.2초에 한 번: 매 프레임 창 9개의 자식을 훑던 것)
	elseif not modalOpen then
		otherModalUntil = os.clock() + 0.2
		-- 다른 스크립트의 큰 창(펫 / 상점 / 스탯)이 열려 있으면 진짜 마우스 커서를 되살린다
		for _, name in ipairs({ "PetGui", "ShopGui", "LevelStatGui", "CodexGui", "AdminGui", "AugGui", "DepthGui", "OddsGui", "ChestGui" }) do
			local g = playerGui:FindFirstChild(name)
			if g and g:IsA("ScreenGui") and g.Enabled then
				for _, child in ipairs(g:GetChildren()) do
					if child:IsA("Frame") and child.Visible and (child.Size.Y.Offset >= 300 or child.Size.Y.Scale >= 0.4) then modalOpen = true break end
				end
			end
			if modalOpen then break end
		end
		otherModalOpen = modalOpen
	end
	if player:GetAttribute("ModalOpen") ~= modalOpen then player:SetAttribute("ModalOpen", modalOpen) end -- (무기 슬롯 바 같은 다른 화면이 큰 창이 열렸는지 알 수 있게)
	local position = UserInputService:GetMouseLocation()
	local show = hasMouse and not modalOpen and player.Character ~= nil and not isMouseOverButton(position)

	UserInputService.MouseIconEnabled = not show
	crosshair.Visible = show
	if not show then return end

	crosshairKick = math.max(0, crosshairKick - dt * 55)
	local gap = 7 + crosshairKick + (holding and 2 or 0)
	local color = (autoMode and lockTarget) and Color3.fromRGB(255, 225, 90) or Color3.new(1, 1, 1)
	hitMarker = math.max(0, hitMarker - dt)
	if hitMarker > 0 then
		color = hitMarkerCrit and Color3.fromRGB(255, 70, 60) or Color3.fromRGB(255, 200, 70)
		gap += 4 * (hitMarker / 0.18)
	end

	crosshair.Position = UDim2.fromOffset(position.X, position.Y)
	barUp.Position = UDim2.fromOffset(0, -gap - 5)
	barDown.Position = UDim2.fromOffset(0, gap + 5)
	barLeft.Position = UDim2.fromOffset(-gap - 5, 0)
	barRight.Position = UDim2.fromOffset(gap + 5, 0)
	for _, part in ipairs({ barUp, barDown, barLeft, barRight, centerDot }) do
		part.BackgroundColor3 = color
	end
end)

do
local function playUiSound(id, volume, pitch)
	if not id or id == 0 then return end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. id
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	sound.Parent = game:GetService("SoundService")
	sound:Play()
	game:GetService("Debris"):AddItem(sound, 3)
end

local lastHitSfx = 0
Remotes.Hit.OnClientEvent:Connect(function(isCrit, killed)
	hitMarker = killed and 0.3 or 0.18
	hitMarkerCrit = isCrit or killed
	if killed then
		shake = math.max(shake, 0.5)
		-- (처치음은 뺐다: 연달아 잡을 때 거슬린다는 의견. 다시 켜려면 SoundBank.Play(sfxParent, "Kill") 를 부르면 된다)
	elseif isCrit then
		shake = math.max(shake, 0.25)
		SoundBank.Play(sfxParent, "Hit", { Pitch = 1.1 + math.random() * 0.15 })
	elseif os.clock() - lastHitSfx >= 0.14 then -- 자동 공격은 초당 수십 번 맞혀서 "찡찡" 소리가 이어졌다: 일반 적중음은 0.14초에 한 번만
		lastHitSfx = os.clock()
		SoundBank.Play(sfxParent, "Hit", { Pitch = 0.9 + math.random() * 0.25 })
	end
end)

player:GetAttributeChangedSignal("ShakeTick"):Connect(function()
		shake = math.max(shake, player:GetAttribute("ShakeStrength") or 0.5)
	end)

	RunService:BindToRenderStep("HitShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if shake <= 0.01 or not settings.Shake then
		shake = 0
		return
	end
	shake = math.max(0, shake - dt * 2.5)
	local amount = shake * 0.012
	camera.CFrame = camera.CFrame * CFrame.Angles((math.random() - 0.5) * amount, (math.random() - 0.5) * amount, 0)
end)
end

do
local helpPanel = makePanel({
	Name = "HelpPanel", Size = UDim2.new(0, 560, 0, 748), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Visible = false,
}, gui)
makeLabel({ Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 8), Text = "⚙ Settings / ❓ Help", Font = Enum.Font.GothamBlack, TextSize = 19 }, helpPanel)
do -- 도움말 글: 한 줄을 글자 하나(라벨 하나)로 나눈다 (한 덩어리로 길게 두면 로블록스 번역용 글자 캡처가 "too long" 으로 거부해서 번역이 안 된다)
	local helpLines = {
		"<b>Move/Attack</b>  WASD move · Q dash · Mouse click (hold for rapid fire) to attack",
		"<b>Auto-Attack</b>  R — auto-aims at the nearest enemy (click an enemy to lock onto it)",
		"<b>Skills</b>  C Emergency Heal · V Ultimate (usable when the gauge is 100% from attacking enemies)  — field/dungeons only",
		"<b>Menu</b>  I — Character (Gear·Weapon·Info) · Growth (Training·Skills·Pets) · Quests (Achievements) · Ranking   |   🎁 Shop button is on the right of the screen",
		"<b>Music</b>  M — on/off",
		"",
		"<b>🎯 Game Flow</b>",
		"1. Collect Gold in the field / dungeons to upgrade your weapon (the lobby dummy is for damage / DPS practice; standing in the rest area earns idle Gold)",
		"2. Defeat monsters in the eastern <b>Field</b> to get gear and level up (don't miss the Golden Goblin!)",
		"3. The northern <b>Dungeon</b> needs a Key. Survive the set time and the boss appears. Random buffs (and penalties) pop up along the way, and you get gear from the boss chest",
		"4. Growth (training) is open from the start. Queue up training, and collect gear sets/uniques to boost your Power",
		"5. Once the field is conquered, challenge the Final Lord, then the weekly <b>Boss Rush</b> ranking",
		}
	local helpList = create("Frame", { Size = UDim2.new(1, -40, 0, 280), Position = UDim2.new(0, 20, 0, 50), BackgroundTransparency = 1 }, helpPanel)
	create("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, helpList)
	for index, line in ipairs(helpLines) do
		if line == "" then
			create("Frame", { Size = UDim2.new(1, 0, 0, 6), BackgroundTransparency = 1, LayoutOrder = index }, helpList)
		else
			makeLabel({
				Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, RichText = true, TextSize = 12, TextWrapped = true, LayoutOrder = index,
				TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = line,
			}, helpList)
		end
	end
end

local function settingButton(y, labelFn, onClick)
	local button
	button = makeButton({
		Size = UDim2.new(1, -40, 0, 32), Position = UDim2.new(0, 20, 0, y), Text = labelFn(), TextSize = 12, BackgroundColor3 = Color3.fromRGB(55, 65, 100),
	}, helpPanel, function()
		onClick()
		button.Text = labelFn()
	end)
end
local function settingSlider(y, title, getValue, setValue)
	local maxValue = 2
	local caption = makeLabel({
		Size = UDim2.new(1, -40, 0, 18), Position = UDim2.new(0, 20, 0, y), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
	}, helpPanel)
	local bar = create("Frame", {
		Size = UDim2.new(1, -40, 0, 12), Position = UDim2.new(0, 20, 0, y + 22), BackgroundColor3 = Color3.fromRGB(55, 65, 100), BorderSizePixel = 0,
	}, helpPanel)
	rounded(bar, 6)
	local fill = create("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(110, 170, 255), BorderSizePixel = 0 }, bar)
	rounded(fill, 6)
	local knob = create("Frame", {
		Size = UDim2.new(0, 18, 0, 18), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 3,
	}, bar)
	rounded(knob, 9)

	local function refresh()
		local value = getValue()
		local ratio = math.clamp(value / maxValue, 0, 1)
		fill.Size = UDim2.new(ratio, 0, 1, 0)
		knob.Position = UDim2.new(ratio, 0, 0.5, 0)
		caption.Text = string.format("%s: %d%%", title, math.floor(value * 100 + 0.5))
	end
	local function setFromX(x)
		local ratio = math.clamp((x - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1)
		setValue(math.floor(ratio * maxValue * 100 + 0.5) / 100)
		refresh()
	end
	local dragging = false
	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	refresh()
end

settingSlider(334, "🔊 Music Volume", function() return musicScale end, function(value)
	musicScale = value
	for name, sound in pairs(tracks) do
		if name == currentMusic then
			sound.Volume = musicVolume(name)
		end
	end
end)
settingSlider(380, "🔫 Gunshot Volume", function() return settings.ShotVolume end, function(value)
	settings.ShotVolume = value
end)
settingButton(428, function() return "📳 Screen Shake: " .. (settings.Shake and "ON" or "OFF") end, function() settings.Shake = not settings.Shake end)
settingButton(508, function() return "🖥 Low-spec mode (less lag): " .. (player:GetAttribute("LowSpec") and "ON" or "OFF") end, function() player:SetAttribute("LowSpec", not player:GetAttribute("LowSpec")) end)
settingButton(548, function() return "👕 Hide gear look (weapon stays): " .. (player:GetAttribute("HideGear") and "ON" or "OFF") end, function() player:SetAttribute("HideGear", not player:GetAttribute("HideGear")) end)
do
	local sizes = { { 0.85, "Small" }, { 1, "Normal" }, { 1.25, "Large" }, { 1.5, "X-Large" } }
	local function sizeIndex()
		local pref = player:GetAttribute("UiPref") or 1
		for index, entry in ipairs(sizes) do
			if math.abs(entry[1] - pref) < 0.01 then return index end
		end
		return 2
	end
	-- (언어는 접속할 때 정해진다: 나라가 한국이거나 로블록스 언어가 한국어면 한국어. 전환 버튼은 뺐다)
	settingButton(588, function() return "🔍 UI Size: " .. sizes[sizeIndex()][2] .. " (PC)" end, function()
		player:SetAttribute("UiPref", sizes[sizeIndex() % #sizes + 1][1])
	end)
end
makeButton({
	Size = UDim2.new(0, 160, 0, 36), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Text = "Close (H)", BackgroundColor3 = GRAY,
}, helpPanel, function()
	helpPanel.Visible = false
end)

function toggleHelp()
	helpPanel.Visible = not helpPanel.Visible
	if helpPanel.Visible then menuPanel.Visible = false end -- 큰 창은 한 번에 하나 (설정 창 뒤에 메뉴가 겹쳐 비치지 않게)
end

-- 왼쪽 메뉴 버튼 줄(MenuDockClient)이 보내는 신호: "OpenMenuTab" = "탭" 또는 "탭:하위", "OpenHelp" = 설정 창
player:GetAttributeChangedSignal("OpenHelp"):Connect(toggleHelp)
player:GetAttributeChangedSignal("OpenEnhance"):Connect(function() -- 왼쪽 무기 버튼(마을): 대장장이 모루와 같은 강화 창
	if player:GetAttribute("Zone") ~= "Lobby" then return end
	menuPanel.Visible = false
	if enhancePanel.Visible then
		enhancePanel.Visible = false
		return
	end
	resetEnhanceView()
	enhancePanel.Visible = true -- (먼저 연다: 아래 갱신에서 오류가 나도 창은 뜨게)
	local ok, err = pcall(refreshEnhance)
	if not ok then warn("[무기 창] 갱신 오류: " .. tostring(err)) end
end)
player:GetAttributeChangedSignal("OpenMenuTab"):Connect(function()
	local want = player:GetAttribute("OpenMenuTab")
	if type(want) ~= "string" then return end
	local key, subKey = string.match(want, "^([^:|]+):?([^|]*)") -- ("탭:하위|시각" 형태: 시각은 같은 버튼을 연달아 눌러도 신호가 오게 하는 용도)
	if subKey == "" then subKey = nil end
	if menuPanel.Visible and currentTab == key and (not subKey or MENU.Sub[key] == subKey) then
		menuPanel.Visible = false -- 같은 버튼을 한 번 더 누르면 닫는다
		return
	end
	enhancePanel.Visible = false -- 무기 강화 창이 열려 있으면 먼저 닫는다 (메뉴 위에 겹쳐 보이던 문제)
	if not menuPanel.Visible then toggleMenu() end
	local ok, err = pcall(selectTab, key, subKey)
	if not ok then warn("[Menu] " .. tostring(err)) end
end)

workspace.DescendantAdded:Connect(function(instance)
	if instance:IsA("Sound") then
		if instance.Name == "GunShot" then
			instance.Volume = instance.Volume * settings.ShotVolume
		elseif SoundBank.RecentShot() then
			instance.Volume = instance.Volume * 0.5 -- 덕킹: 서버가 만든 소리(세트 효과 폭발 / 몬스터 등)도 내가 쏘는 중에는 절반으로 (총소리가 묻히지 않게)
		end
	end
end)

do
	local helpButton = makeButton({
		Name = "HelpButton", Size = UDim2.new(0, 78, 0, 32), Position = UDim2.new(0, 98, 0, 244), Text = "⚙ Settings(H)", TextSize = 10,
		BackgroundColor3 = Color3.fromRGB(34, 40, 70),
	}, gui, toggleHelp)
	create("UIStroke", { Color = Color3.fromRGB(110, 130, 220), Thickness = 1.5, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, helpButton)
end


end

do
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui
	local function fit()
		local viewport = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min(viewport.X / 1100, viewport.Y / 720), 0.55, math.max(1, player:GetAttribute("UiMul") or 1))
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	player:GetAttributeChangedSignal("UiMul"):Connect(fit)
end

do
	local ContextActionService = game:GetService("ContextActionService")
	ContextActionService:BindActionAtPriority("DungeonMenuToggle", function(_, state)
		if state == Enum.UserInputState.Begin then
			toggleMenu()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.I, Enum.KeyCode.B)
end

do
	local jd = { Used = 0, Last = 0 }

	local function bindCharacter(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not humanoid or not root then return end
		jd.Used = 0
		humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running or new == Enum.HumanoidStateType.Climbing then
				jd.Used = 0
			end
		end)
	end
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end
	player.CharacterAdded:Connect(bindCharacter)

	jd.Try = function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root or humanoid.Health <= 0 then return end
		if humanoid.FloorMaterial ~= Enum.Material.Air then
			jd.Used = 0
			return
		end
		local now = os.clock()
		if jd.Used >= 1 or now - jd.Last < 0.2 then return end
		jd.Used += 1
		jd.Last = now
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, 52, velocity.Z)
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		local ring = Instance.new("Part")
		ring.Shape = Enum.PartType.Cylinder
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.Material = Enum.Material.Neon
		ring.Color = Color3.fromRGB(150, 220, 255)
		ring.Transparency = 0.3
		ring.Size = Vector3.new(0.3, 3, 3)
		ring.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = workspace
		TweenService:Create(ring, TweenInfo.new(0.4), { Size = Vector3.new(0.3, 11, 11), Transparency = 1 }):Play()
		game:GetService("Debris"):AddItem(ring, 0.5)
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.Space then
			jd.Try()
		end
	end)
	UserInputService.JumpRequest:Connect(jd.Try)
	player:GetAttributeChangedSignal("TapJump"):Connect(function() -- 모바일: 화면 두 번 터치 (MobileLayoutClient)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end
		if humanoid.FloorMaterial ~= Enum.Material.Air then humanoid.Jump = true else jd.Try() end
	end)
	RunService.Heartbeat:Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
			jd.Used = 0
		end
	end)
end
end
