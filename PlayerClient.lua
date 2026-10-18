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

local function makePanel(props, parent)
	local base = {
		BackgroundColor3 = Color3.fromRGB(16, 18, 30),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	local frame = create("Frame", base, parent)
	rounded(frame, (not props.BackgroundColor3 or (props.Size and props.Size.Y.Offset >= 100)) and 12 or 8)
	if not props.BackgroundColor3 then
		create("UIStroke", { Color = Color3.fromRGB(110, 130, 220), Thickness = 1.5, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
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
	rounded(button, 8)
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
}, gui)
create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 10) }, toastLabel)
create("UIStroke", { Color = Color3.fromRGB(225, 196, 118), Thickness = 1.5, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, toastLabel)
rounded(toastLabel, 12)

local toastToken = 0
local function toast(text)
	toastToken += 1
	local token = toastToken
	local base = (player:GetAttribute("Zone") == "Dungeon") and 210 or 112
	local pg = gui.Parent
	local cy = pg:GetAttribute(player:GetAttribute("SidePromptUp") and "UiToastYUp" or "UiToastY")
	local y = cy or -(base + 138)
	local tx = cy and pg:GetAttribute("UiToastX") or 14
	toastLabel.Text = text
	toastLabel.Position = UDim2.new(0, -430, 1, y)
	toastLabel.Visible = true
	TweenService:Create(toastLabel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0, tx, 1, y) }):Play()
	task.delay(4, function()
		if token == toastToken then
			toastLabel.Visible = false
		end
	end)
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
do
local E = {}
enhancePanel = makePanel({
	Size = UDim2.new(0, 400, 0, 620),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(18, 20, 34), BackgroundTransparency = 0.05,
	Visible = false,
}, gui)
create("UIStroke", { Color = Color3.fromRGB(225, 196, 118), Thickness = 2, Transparency = 0.2 }, enhancePanel)
create("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(70, 48, 90), Color3.fromRGB(22, 20, 32)), Rotation = 90,
}, enhancePanel)

makeLabel({
	Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 8),
	Text = "🔨 Weapon Upgrade", Font = Enum.Font.GothamBlack, TextSize = 20, TextColor3 = Color3.fromRGB(255, 220, 130),
}, enhancePanel)
makeButton({
	Size = UDim2.new(0, 64, 0, 30), Position = UDim2.new(1, -74, 0, 12), Text = "Close", TextSize = 13, BackgroundColor3 = Color3.fromRGB(110, 60, 70),
}, enhancePanel, function()
	enhancePanel.Visible = false
end)

local enhanceWeapon = makeLabel({
	Size = UDim2.new(1, -24, 0, 30), Position = UDim2.new(0, 12, 0, 50),
	Font = Enum.Font.GothamBlack, TextSize = 19, TextWrapped = true,
}, enhancePanel)

local medal = create("Frame", {
	Size = UDim2.new(0, 230, 0, 230), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 86),
	BackgroundColor3 = Color3.fromRGB(34, 30, 52), BorderSizePixel = 0,
}, enhancePanel)
create("UICorner", { CornerRadius = UDim.new(1, 0) }, medal)
local medalStroke = create("UIStroke", { Color = Color3.fromRGB(255, 200, 90), Thickness = 5 }, medal)
E.Stars = {}
for i = 1, 16 do
	local dot = 3 + (i % 3) * 2
	local star = create("Frame", {
		Size = UDim2.new(0, dot, 0, dot), Position = UDim2.new(math.random(), 0, math.random(), 0),
		BackgroundColor3 = Color3.fromRGB(255, 235, 170), BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 1,
	}, enhancePanel)
	create("UICorner", { CornerRadius = UDim.new(1, 0) }, star)
	E.Stars[i] = { Label = star, Phase = math.random() * 6.28, Speed = 1.5 + math.random() * 2 }
end
local rim = enhancePanel:FindFirstChildOfClass("UIStroke")
if rim then
	E.RimGradient = create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 80)), ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 120, 200)),
			ColorSequenceKeypoint.new(0.7, Color3.fromRGB(120, 200, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 80)),
		}),
	}, rim)
end

-- 무기 모형 대신 "해금 진행 길": 강화할수록 막대가 앞으로 나아가고, 도착하면 무엇이 해금되는지 보인다
medal.Visible = false
local track = create("Frame", {
	Size = UDim2.new(1, -24, 0, 230), Position = UDim2.new(0, 12, 0, 86), BackgroundTransparency = 1, BorderSizePixel = 0,
}, enhancePanel)

RunService.RenderStepped:Connect(function()
	if not enhancePanel.Visible then return end
	local t = os.clock()
	for _, star in ipairs(E.Stars) do
		star.Label.BackgroundTransparency = 0.25 + 0.7 * (0.5 + 0.5 * math.sin(t * star.Speed + star.Phase))
	end
	if E.RimGradient then E.RimGradient.Rotation = (t * 60) % 360 end
end)

local enhanceStage = makeLabel({
	Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 322), Font = Enum.Font.GothamBlack, TextSize = 29,
}, enhancePanel)
local segmentBar = create("Frame", {
	Size = UDim2.new(1, -60, 0, 14), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 366), BackgroundTransparency = 1,
}, enhancePanel)
create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, segmentBar)
local enhanceNext = makeLabel({
	Size = UDim2.new(1, -30, 0, 22), Position = UDim2.new(0, 15, 0, 386), TextSize = 12, RichText = true,
}, enhancePanel)

local enhanceInfo = makeLabel({
	Size = UDim2.new(1, -40, 0, 50), Position = UDim2.new(0, 20, 0, 414), TextSize = 13, RichText = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
}, enhancePanel)

-- 무기 특성: 지금 무기의 싸우는 방식 + 다음 시대로 진화하면 생기는 새 특성 (업그레이드할 이유를 눈에 보이게)
local enhancePerk = makeLabel({
	Size = UDim2.new(1, -40, 0, 62), Position = UDim2.new(0, 20, 0, 464), TextSize = 11, RichText = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
}, enhancePanel)

local enhanceBanner = makeLabel({
	Size = UDim2.new(1, 0, 0, 56), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 200),
	Font = Enum.Font.GothamBlack, TextSize = 37, TextStrokeTransparency = 0, Visible = false, ZIndex = 8,
}, enhancePanel)
local enhanceResult = makeLabel({
	Size = UDim2.new(1, -24, 0, 22), Position = UDim2.new(0, 12, 0, 530), Font = Enum.Font.GothamBold, TextSize = 12,
}, enhancePanel)

local hammer = makeLabel({
	Size = UDim2.new(0, 70, 0, 70), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 70, 0, 150),
	Text = "🔨", TextSize = 48, Visible = false, ZIndex = 9, Rotation = -50,
}, enhancePanel)

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
	Remotes.Enhance:FireServer(count)
	task.delay(1.1, function() E.EnhanceBusy = false end)
end
local enhanceTen = makeButton({
	Size = UDim2.new(0, 80, 0, 54), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 214, 1, -14),
	Text = "x10\nUpgrade", TextSize = 14, Font = Enum.Font.GothamBold, BackgroundColor3 = Color3.fromRGB(60, 120, 200),
}, enhancePanel, function() enhanceMany(10) end)
local enhanceMax = makeButton({
	Size = UDim2.new(0, 80, 0, 54), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 302, 1, -14),
	Text = "Max\nUpgrade", TextSize = 14, Font = Enum.Font.GothamBold, BackgroundColor3 = Color3.fromRGB(190, 110, 40),
}, enhancePanel, function() enhanceMany(50) end)
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
local enhanceButton = makeButton({
	Size = UDim2.new(0, 186, 0, 54), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20, 1, -14),
	Text = "Upgrade", TextSize = 15, Font = Enum.Font.GothamBold, BackgroundColor3 = GREEN,
}, enhancePanel, function()
	if E.EnhanceBusy then return end
	E.EnhanceBusy = true
	hammer.Visible = true
	hammer.Rotation = -50
	local swing = TweenService:Create(hammer, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Rotation = 25, Position = UDim2.new(0.5, 20, 0, 190) })
	swing:Play()
	swing.Completed:Connect(function()
		SoundBank.Play(sfxParent, "Enh_Hammer")
		for i = 1, 8 do
			local spark = create("Frame", {
				Size = UDim2.new(0, 8, 0, 8), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 205),
				BackgroundColor3 = i % 2 == 0 and Color3.fromRGB(255, 220, 110) or Color3.fromRGB(255, 140, 60), BorderSizePixel = 0, ZIndex = 7,
			}, enhancePanel)
			create("UICorner", { CornerRadius = UDim.new(1, 0) }, spark)
			local angle = (i / 8) * math.pi * 2
			TweenService:Create(spark, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5, math.cos(angle) * 130, 0, 205 + math.sin(angle) * 110), BackgroundTransparency = 1,
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
end)
create("UIStroke", { Color = Color3.fromRGB(190, 255, 190), ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 2 }, enhanceButton)
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

local function buildTrack(level, color)
	for _, child in ipairs(track:GetChildren()) do child:Destroy() end
	local order = Config.WeaponTypes.Order
	local tiers = Config.Weapon.Tiers
	local unlocked = Config.GetUnlockedCount(level)
	local nodes = {}
	if unlocked < #order then -- 무기 10형 해금 길 (+ 끝에 새 시대)
		for i, key in ipairs(order) do
			table.insert(nodes, { Level = tiers[i].MinLevel, Name = Config.WeaponTypes[key].Name })
		end
		table.insert(nodes, { Level = tiers[#order + 1].MinLevel, Name = "New Era", Era = true })
	else -- 다 열었으면 시대 길
		for e = 1, 10 do
			table.insert(nodes, { Level = tiers[(e - 1) * #order + 1].MinLevel, Name = Config.GetEraName(e), Era = true })
		end
	end
	local n = #nodes
	local pos = n - 1
	for i = 1, n - 1 do
		if level < nodes[i + 1].Level then
			pos = (i - 1) + (level - nodes[i].Level) / math.max(1, nodes[i + 1].Level - nodes[i].Level)
			break
		end
	end
	local nextIndex = nil
	for i = 1, n do
		if nodes[i].Level > level then nextIndex = i break end
	end
	local milestone = Config.GetNextMilestone(level)

	-- 위쪽 카드: 다음에 무엇이 열리는지
	local cardText
	if milestone and milestone.Kind == "Form" then
		local info = Config.WeaponTypes[milestone.Key]
		cardText = string.format("<font size='12' color='#aab0cc'>Next unlock · +%d</font>\n<font size='22' color='#ffd966'><b>🔓 %s</b></font>\n<font size='12' color='#dfe6ff'>%s</font>\n<font size='12' color='#78ff8c'><b>%d more upgrades</b></font>", milestone.Level, info.Name, info.Trait, milestone.Level - level)
	elseif milestone then
		local perk = milestone.Tier.Perk
		cardText = string.format("<font size='12' color='#aab0cc'>Next era · +%d</font>\n<font size='22' color='#ffd966'><b>✨ %s</b></font>\n<font size='12' color='#dfe6ff'>%s</font>\n<font size='12' color='#78ff8c'><b>%d more upgrades</b></font>", milestone.Level, milestone.Name, perk and (perk.Icon .. " " .. perk.Name) or "New look and shot color", milestone.Level - level)
	else
		cardText = "<font size='22' color='#ffd966'><b>🏆 Max level!</b></font>"
	end
	makeLabel({
		Size = UDim2.new(1, 0, 0, 100), Position = UDim2.new(0, 0, 0, 8), RichText = true, TextSize = 14, Text = cardText,
		TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
	}, track)

	-- 길: 어두운 바탕 + 나아간 만큼 차오르는 막대 + 해금 지점(동그라미)
	local left, width, y = 18, 340, 150
	local bar = create("Frame", { Size = UDim2.new(0, width, 0, 10), Position = UDim2.new(0, left, 0, y - 5), BackgroundColor3 = Color3.fromRGB(52, 50, 72), BorderSizePixel = 0 }, track)
	create("UICorner", { CornerRadius = UDim.new(0, 5) }, bar)
	local fillWidth = math.max(4, width * math.min(1, pos / math.max(1, n - 1)))
	local fill = create("Frame", { Size = UDim2.new(0, fillWidth, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 96, 84), BorderSizePixel = 0 }, bar)
	create("UICorner", { CornerRadius = UDim.new(0, 5) }, fill)
	create("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 120, 90), Color3.fromRGB(255, 205, 100)) }, fill)
	makeLabel({ Size = UDim2.new(0, 40, 0, 16), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0, left + fillWidth, 0, y - 12), Text = "▼", TextSize = 13, TextColor3 = Color3.fromRGB(255, 205, 100) }, track)
	for i, node in ipairs(nodes) do
		local x = left + width * (i - 1) / math.max(1, n - 1)
		local done = level >= node.Level
		local isNext = i == nextIndex
		local dot = create("Frame", {
			Size = UDim2.new(0, 26, 0, 26), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, x, 0, y), BorderSizePixel = 0,
			BackgroundColor3 = done and color or (isNext and Color3.fromRGB(70, 60, 30) or Color3.fromRGB(36, 36, 52)),
		}, track)
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
		create("UIStroke", { Color = isNext and Color3.fromRGB(255, 217, 102) or (done and Color3.new(1, 1, 1) or Color3.fromRGB(80, 82, 110)), Thickness = isNext and 3 or 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, dot)
		makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = done and "✔" or (isNext and "★" or (node.Era and "✦" or "🔒")), TextSize = done and 13 or 11, TextColor3 = done and Color3.fromRGB(20, 20, 30) or Color3.fromRGB(190, 192, 215) }, dot)
		makeLabel({ Size = UDim2.new(0, 44, 0, 14), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0, x, 0, y + 17), Text = "+" .. node.Level, TextSize = 9, TextColor3 = done and Color3.fromRGB(200, 205, 230) or Color3.fromRGB(120, 122, 150) }, track)
		-- 이름은 칸이 좁아서 위아래로 엇갈려 쓴다 (다음 해금은 굵게)
		local above = i % 2 == 0
		makeLabel({
			Size = UDim2.new(0, 60, 0, 14), AnchorPoint = Vector2.new(0.5, above and 1 or 0), Position = UDim2.new(0, x, 0, above and (y - 20) or (y + 32)),
			Text = node.Name, TextSize = 9, TextColor3 = isNext and Color3.fromRGB(255, 217, 102) or (done and Color3.fromRGB(215, 220, 240) or Color3.fromRGB(130, 132, 160)),
			Font = isNext and Enum.Font.GothamBlack or Enum.Font.GothamBold,
		}, track)
	end
end

function refreshEnhance()
	local level = player:GetAttribute("WeaponLevel") or 0
	local gold = player:GetAttribute("Gold") or 0
	local typeKey = Config.ResolveWeaponType(level, player:GetAttribute("WeaponType"))
	local tier = Config.GetLookTier(level, typeKey) -- 고른 무기 형 + 지금 시대의 외모
	local tierIndex = tier.Index
	local milestone = Config.GetNextMilestone(level)
	local stage = level
	local color = tier.Rainbow and Color3.fromRGB(255, 120, 255) or tier.Color

	buildTrack(level, color)
	enhanceWeapon.Text = string.format("%s · %s", Config.GetWeaponName(typeKey, level), Config.GetEraName(tier.Era))
	enhanceWeapon.TextColor3 = color
	medalStroke.Color = color
	E.Milestone = Config.GetUnlockedCount(level) + 100 * tier.Era -- 새 무기 해금 / 새 시대 때만 "진화!" 연출
	E.EnhanceShownTier = tierIndex

	enhanceStage.Text = string.format("+%d", stage)
	enhanceStage.TextColor3 = color
	if E.LastStage and E.LastStage ~= stage then
		enhanceStage.TextSize = 46
		TweenService:Create(enhanceStage, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = 29 }):Play()
	end
	E.LastStage = stage
	for _, child in ipairs(segmentBar:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	-- 막대: 직전 큰 변화(해금 / 시대)부터 다음 큰 변화까지의 진행도
	local base = Config.Weapon.Tiers[(tier.Era - 1) * #Config.WeaponTypes.Order + 1].MinLevel
	if milestone and milestone.Kind == "Form" then base = Config.Weapon.Tiers[Config.GetUnlockedCount(level)].MinLevel end
	local span = milestone and math.max(1, milestone.Level - base) or 1
	local segs = math.clamp(span, 1, 20)
	local filled = milestone and math.floor((level - base) / span * segs + 0.0001) or segs
	for i = 1, segs do
		local seg = create("Frame", {
			Size = UDim2.new(1 / segs, -4, 1, 0), LayoutOrder = i, BorderSizePixel = 0,
			BackgroundColor3 = i <= filled and color or Color3.fromRGB(55, 52, 72),
		}, segmentBar)
		create("UICorner", { CornerRadius = UDim.new(0, 4) }, seg)
	end

	if level >= Config.Weapon.MaxLevel then
		enhanceNext.Text = "<font color='#ffd966'>You maxed out the final weapon!</font>"
		enhanceInfo.Text = ""
		enhanceButton.Text = "MAX"
		enhanceButton.BackgroundColor3 = GRAY
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
	if milestone and milestone.Kind == "Form" then
		enhanceNext.Text = string.format("▶ <b>%d more</b> to unlock <font color='#9ad7ff'><b>%s</b></font>!", milestone.Level - level, milestone.Name)
	elseif milestone then
		enhanceNext.Text = string.format("▶ <b>%d more</b> to evolve into <font color='#9ad7ff'><b>%s</b></font>!", milestone.Level - level, milestone.Name)
	else
		enhanceNext.Text = ""
	end
	enhanceInfo.Text = string.format("Damage  <b>x%.2f</b> <font color='#78ff8c'>▶ x%.2f</font>\nSuccess rate  <font color='#%s'><b>%d%%</b></font>   <font size='10' color='#aaaabb'>(level kept on failure)</font>",
		Config.GetDamageMultiplier(level), Config.GetDamageMultiplier(level + 1), chance >= 80 and "78ff8c" or (chance >= 60 and "ffd966" or "ff9a6e"), chance)
	do
		local perk = Config.GetWeaponPerk(level)
		local lines = {}
		if perk then
			table.insert(lines, string.format("<font color='#ffe9a0'>%s <b>%s</b></font> <font color='#c9cde0'>%s</font>", perk.Icon, perk.Name, perk.Desc))
		end
		if milestone and milestone.Kind == "Era" and milestone.Tier.Perk then
			local nextPerk = milestone.Tier.Perk
			table.insert(lines, string.format("<font color='#9affc0'>Next era → %s <b>%s</b></font> <font color='#aeb4cc'>%s</font>", nextPerk.Icon, nextPerk.Name, nextPerk.Desc))
		elseif milestone and milestone.Kind == "Form" then
			local info = Config.WeaponTypes[milestone.Key]
			table.insert(lines, string.format("<font color='#9affc0'>Next weapon → <b>%s</b></font> <font color='#aeb4cc'>%s</font>", info.Name, info.Trait))
		end
		enhancePerk.Text = table.concat(lines, "\n")
	end
	local affordable = gold >= cost
	enhanceButton.Text = freeNow and "✨ Free!\nUpgrade" or string.format("💰 %s G\nUpgrade", tostring(cost))
	enhanceButton.BackgroundColor3 = affordable and GREEN or Color3.fromRGB(95, 60, 62)
	E.EnhanceAffordable = affordable
end

player:GetAttributeChangedSignal("TutorialFree"):Connect(function() if enhancePanel.Visible then refreshEnhance() end end)
RunService.RenderStepped:Connect(function()
	if enhancePanel.Visible and E.EnhanceAffordable and not E.EnhanceBusy then
		local pulse = 1 + 0.02 * math.sin(os.clock() * 4)
		enhanceButton.Size = UDim2.new(0, 186 + (pulse - 1) * 300, 0, 54)
	end
end)

Remotes.Enhance.OnClientEvent:Connect(function(ok, message, summary)
	local oldMilestone = E.Milestone
	refreshEnhance()
	local evolved = oldMilestone ~= nil and E.Milestone ~= nil and E.Milestone > oldMilestone
	do
		local level = player:GetAttribute("WeaponLevel") or 0
		local tierNow = Config.GetWeaponTier(level)
		local stageFrac = (level - tierNow.MinLevel) / math.max(1, tierNow.Steps)
		if evolved then
			SoundBank.Play(sfxParent, "Enh_Evolve")
		elseif summary and summary.Attempts and summary.Attempts > 1 then
			for i = 1, math.min(8, summary.Successes or 0) do
				task.delay((i - 1) * 0.09, function() SoundBank.Play(sfxParent, "Enh_Success", { Pitch = 0.8 + 0.04 * i }) end)
			end
			if (summary.Successes or 0) == 0 then SoundBank.Play(sfxParent, "Enh_Fail") end
		elseif ok then
			SoundBank.Play(sfxParent, "Enh_Success", { Pitch = 0.8 + 0.3 * stageFrac })
		else
			SoundBank.Play(sfxParent, "Enh_Fail")
		end
	end
	enhanceBanner.Visible = true
	enhanceBanner.Position = UDim2.new(0.5, 0, 0, 200)
	enhanceBanner.TextTransparency = 0
	enhanceBanner.TextStrokeTransparency = 0
	if evolved then
		enhanceBanner.Text = "✨ Unlock · Evolve! ✨"
		enhanceBanner.TextColor3 = Color3.fromRGB(255, 225, 100)
		medalStroke.Thickness = 12
		TweenService:Create(medalStroke, TweenInfo.new(0.7), { Thickness = 5 }):Play()
	elseif summary and summary.Attempts > 1 then
		enhanceBanner.Text = string.format("%d upgrades! %d succeeded", summary.Attempts, summary.Successes)
		enhanceBanner.TextColor3 = ok and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 160, 120)
		enhanceBanner.TextSize = 29
		medalStroke.Thickness = 9
		TweenService:Create(medalStroke, TweenInfo.new(0.5), { Thickness = 5 }):Play()
	elseif ok then
		enhanceBanner.Text = "SUCCESS!"
		enhanceBanner.TextColor3 = Color3.fromRGB(120, 255, 140)
		medalStroke.Thickness = 9
		TweenService:Create(medalStroke, TweenInfo.new(0.5), { Thickness = 5 }):Play()
	else
		enhanceBanner.Text = "FAIL"
		enhanceBanner.TextColor3 = Color3.fromRGB(255, 120, 120)
	end
	TweenService:Create(enhanceBanner, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 150), TextTransparency = 1, TextStrokeTransparency = 1,
	}):Play()
	task.delay(1, function() enhanceBanner.Visible = false end)
	enhanceResult.Text = message
	enhanceResult.TextColor3 = ok and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 130, 130)
end)

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

local gearHooks = {}
local gearPanel
local gearMessage
local refreshGear
do
local GEAR_ICONS = { Armor = "🛡", Gloves = "🧤", Boots = "👢", Helmet = "⛑", Ring = "💍", Necklace = "📿" }
local LEFT_SLOTS = { "Helmet", "Armor", "Gloves" }
local RIGHT_SLOTS = { "Necklace", "Ring", "Boots" }
local state = { Selected = "Armor", Boxes = {} }

gearPanel = makePanel({
	Size = UDim2.new(0, 760, 0, 560),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(18, 20, 34), BackgroundTransparency = 0.05,
	Visible = false,
}, gui)
create("UIStroke", { Color = Color3.fromRGB(150, 130, 230), Thickness = 2, Transparency = 0.2 }, gearPanel)
create("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(70, 46, 100), Color3.fromRGB(22, 18, 34)), Rotation = 90 }, gearPanel)

makeLabel({
	Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 8),
	Text = "🛡 Gear · Gacha", Font = Enum.Font.GothamBlack, TextSize = 20, TextColor3 = Color3.fromRGB(235, 200, 255),
}, gearPanel)
makeButton({
	Size = UDim2.new(0, 64, 0, 30), Position = UDim2.new(1, -74, 0, 12), Text = "Close", TextSize = 13, BackgroundColor3 = Color3.fromRGB(110, 60, 70),
}, gearPanel, function()
	gearPanel.Visible = false
end)

local viewport = create("ViewportFrame", {
	Size = UDim2.new(0, 210, 0, 330), Position = UDim2.new(0, 135, 0, 54), BackgroundColor3 = Color3.fromRGB(26, 24, 44), BorderSizePixel = 0,
	Ambient = Color3.fromRGB(190, 190, 200), LightColor = Color3.new(1, 1, 1),
}, gearPanel)
rounded(viewport, 12)
create("UIStroke", { Color = Color3.fromRGB(150, 110, 220), Thickness = 2 }, viewport)
local cam = create("Camera", { FieldOfView = 38 }, viewport)
viewport.CurrentCamera = cam
local clone, pivot
local function rebuildCharacter()
	if clone then clone:Destroy() clone = nil end
	local character = player.Character
	if not character then return end
	character.Archivable = true
	clone = character:Clone()
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("BillboardGui") or descendant:IsA("ForceField") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	clone.Parent = viewport
	pivot = clone:GetPivot()
end
RunService.RenderStepped:Connect(function(dt)
	if not gearPanel.Visible or not clone or not pivot then return end
	state.Spin = (state.Spin or 0) + dt * 0.9
	clone:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(0, state.Spin, 0))
	cam.CFrame = CFrame.lookAt(pivot.Position + Vector3.new(0, 1.2, 12.5), pivot.Position + Vector3.new(0, 0.4, 0))
end)
local powerLabel = makeLabel({
	Size = UDim2.new(0, 210, 0, 24), Position = UDim2.new(0, 135, 0, 390), TextSize = 14, Font = Enum.Font.GothamBlack,
	TextColor3 = Color3.fromRGB(255, 225, 110),
}, gearPanel)

local function makeSlotBox(slotKey, x, y)
	local box = create("TextButton", {
		Size = UDim2.new(0, 104, 0, 100), Position = UDim2.new(0, x, 0, y), BackgroundColor3 = Color3.fromRGB(34, 32, 54), BorderSizePixel = 0, Text = "", AutoButtonColor = false,
	}, gearPanel)
	rounded(box, 12)
	local stroke = create("UIStroke", { Color = Color3.fromRGB(90, 90, 120), Thickness = 2 }, box)
	local icon = makeLabel({ Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 0, 6), TextSize = 27 }, box)
	local name = makeLabel({ Size = UDim2.new(1, -6, 0, 30), Position = UDim2.new(0, 3, 0, 48), TextSize = 9, Font = Enum.Font.GothamBold, TextWrapped = true }, box)
	local level = makeLabel({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -20), TextSize = 11, Font = Enum.Font.GothamBlack }, box)
	box.Activated:Connect(function()
		state.Selected = slotKey
		refreshGear()
	end)
	state.Boxes[slotKey] = { Box = box, Stroke = stroke, Icon = icon, Name = name, Level = level }
end
for index, slotKey in ipairs(LEFT_SLOTS) do makeSlotBox(slotKey, 18, 54 + (index - 1) * 112) end
for index, slotKey in ipairs(RIGHT_SLOTS) do makeSlotBox(slotKey, 358, 54 + (index - 1) * 112) end

local detail = create("Frame", { Size = UDim2.new(0, 262, 0, 336), Position = UDim2.new(1, -278, 0, 54), BackgroundColor3 = Color3.fromRGB(24, 22, 40), BorderSizePixel = 0 }, gearPanel)
rounded(detail, 12)
local detailStroke = create("UIStroke", { Color = Color3.fromRGB(110, 90, 160), Thickness = 2 }, detail)
local detailText = makeLabel({
	Size = UDim2.new(1, -20, 0, 214), Position = UDim2.new(0, 10, 0, 10), RichText = true, TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
}, detail)
local enhanceSlotButton = makeButton({
	Size = UDim2.new(1, -24, 0, 50), Position = UDim2.new(0, 12, 1, -112), Text = "Upgrade", TextSize = 15, Font = Enum.Font.GothamBold, BackgroundColor3 = GREEN,
}, detail, function()
	Remotes.Gear:FireServer("Enhance", state.Selected)
end)
create("UIStroke", { Color = Color3.fromRGB(190, 255, 190), ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 2 }, enhanceSlotButton)
gearMessage = makeLabel({
	Size = UDim2.new(1, -16, 0, 40), Position = UDim2.new(0, 8, 1, -54), Font = Enum.Font.GothamBold, TextSize = 12, RichText = true,
}, detail)

local gachaBar = create("Frame", { Size = UDim2.new(1, -36, 0, 128), Position = UDim2.new(0, 18, 1, -142), BackgroundColor3 = Color3.fromRGB(58, 38, 92), BorderSizePixel = 0 }, gearPanel)
rounded(gachaBar, 14)
create("UIStroke", { Color = Color3.fromRGB(255, 210, 120), Thickness = 2 }, gachaBar)
create("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(110, 60, 170), Color3.fromRGB(48, 30, 80)), Rotation = 0 }, gachaBar)
local ticketLabel = makeLabel({
	Size = UDim2.new(1, -420, 0, 30), Position = UDim2.new(0, 20, 0, 8), Font = Enum.Font.GothamBlack, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left,
}, gachaBar)
makeButton({ Size = UDim2.new(0, 104, 0, 26), Position = UDim2.new(0, 20, 1, -34), Text = "📊 Odds", TextSize = 13, BackgroundColor3 = Color3.fromRGB(60, 72, 130) }, gachaBar, function()
	player:SetAttribute("OddsKind", "Gacha") -- OddsClient 가 확률 창을 연다 (유료 랜덤 아이템 정책)
	player:SetAttribute("OddsOpen", os.clock())
end)
local rateParts = {}
for index, rate in ipairs(Config.Gacha.Rates) do
	table.insert(rateParts, string.format("<font color='#%s'>%s %d%%</font>", Config.Gear.RarityColors[index]:ToHex(), Config.Gear.RarityNames[index], rate))
end
makeLabel({
	Size = UDim2.new(1, -420, 0, 50), Position = UDim2.new(0, 20, 0, 40), RichText = true, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	Text = table.concat(rateParts, "  ") .. "\n<font color='#c9c0e0'>Same or lower rarity converts to Gold · Tickets drop from dungeons / field bosses</font>",
}, gachaBar)
local rollOne = makeButton({
	Size = UDim2.new(0, 176, 0, 80), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -218, 0.5, 0),
	Text = "🎰 Roll x1\n1 Ticket", TextSize = 17, Font = Enum.Font.GothamBold, BackgroundColor3 = Color3.fromRGB(120, 80, 210),
}, gachaBar, function()
	Remotes.Gear:FireServer("Roll", 1)
end)
create("UIStroke", { Color = Color3.fromRGB(190, 170, 255), ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 2 }, rollOne)
local rollButton = makeButton({
	Size = UDim2.new(0, 200, 0, 80), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
	Text = "🎰 Multi Roll!\nUses all Tickets (max 10)", TextSize = 19, Font = Enum.Font.GothamBold, BackgroundColor3 = Color3.fromRGB(165, 70, 245),
}, gachaBar, function()
	local many = math.min(10, player:GetAttribute("Tickets") or 0)
	if many >= 2 then Remotes.Gear:FireServer("Roll", many) end
end)
create("UIStroke", { Color = Color3.fromRGB(255, 225, 140), ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 3 }, rollButton)
rollButton.ClipsDescendants = true
local rollShimmer = create("Frame", {
	Size = UDim2.new(0, 40, 1.8, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(-0.2, 0, 0.5, 0), Rotation = 20,
	BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.7, BorderSizePixel = 0, ZIndex = 3,
}, rollButton)
task.spawn(function()
	while gearPanel.Parent do
		if gearPanel.Visible and (player:GetAttribute("Tickets") or 0) > 0 then
			rollShimmer.Position = UDim2.new(-0.1, 0, 0.5, 0)
			TweenService:Create(rollShimmer, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { Position = UDim2.new(1.1, 0, 0.5, 0) }):Play()
		end
		task.wait(2)
	end
end)

function refreshGear()
	local gold = player:GetAttribute("Gold") or 0
	local tickets = player:GetAttribute("Tickets") or 0
	local maxLevel = Config.Gear.MaxLevel
	if not clone and gearPanel.Visible then rebuildCharacter() end

	for _, slot in ipairs(Config.Gear.Slots) do
		local ui = state.Boxes[slot.Key]
		local rarity = player:GetAttribute("Gear_" .. slot.Key .. "_R") or 0
		local level = player:GetAttribute("Gear_" .. slot.Key .. "_L") or 0
		ui.Icon.Text = GEAR_ICONS[slot.Key] or "?"
		if rarity > 0 then
			local color = Config.Gear.RarityColors[rarity]
			ui.Stroke.Color = color
			ui.Stroke.Thickness = (slot.Key == state.Selected) and 5 or ({ 2, 2, 3, 3.5, 4 })[rarity]
			ui.Name.Text = slot.Names[rarity]
			ui.Name.TextColor3 = color
			ui.Level.Text = string.format("+%d", level)
			ui.Level.TextColor3 = Color3.new(1, 1, 1)
			ui.Icon.TextTransparency = 0
		else
			ui.Stroke.Color = (slot.Key == state.Selected) and Color3.fromRGB(255, 225, 120) or Color3.fromRGB(90, 90, 120)
			ui.Stroke.Thickness = (slot.Key == state.Selected) and 4 or 2
			ui.Name.Text = slot.Name .. " (empty)"
			ui.Name.TextColor3 = Color3.fromRGB(130, 130, 150)
			ui.Level.Text = ""
			ui.Icon.TextTransparency = 0.6
		end
		ui.Box.BackgroundColor3 = slot.Key == state.Selected and Color3.fromRGB(52, 48, 82) or Color3.fromRGB(34, 32, 54)
	end

	local slot = Config.GetGearSlot(state.Selected)
	local rarity = player:GetAttribute("Gear_" .. slot.Key .. "_R") or 0
	local level = player:GetAttribute("Gear_" .. slot.Key .. "_L") or 0
	if rarity <= 0 then
		detailText.Text = string.format("<font size='15'><b>%s</b></font>\n<font color='#9a9ab5'>Empty</font>\n\n%s effect\n<font color='#c9c0e0'>Get gear with the gacha below, or equip gear dropped in the field from your Bag (B).</font>", slot.Name, slot.StatName)
		enhanceSlotButton.Text = "—"
		enhanceSlotButton.BackgroundColor3 = GRAY
		detailStroke.Color = Color3.fromRGB(110, 90, 160)
	else
		local color = Config.Gear.RarityColors[rarity]
		detailStroke.Color = color
		local lines = {
			string.format("<font size='15'><b><font color='#%s'>[%s] %s</font></b></font>  <b>+%d</b>", color:ToHex(), Config.Gear.RarityNames[rarity], slot.Names[rarity], level),
			"",
			"<font color='#c9c0e0'>" .. slot.StatName .. "</font>",
		}
		local now = Config.FormatGearStat(slot.Key, Config.GetGearStat(slot.Key, rarity, level))
		if level < maxLevel then
			local cost = Config.GetGearCost(slot.Key, rarity, level, player:GetAttribute("WeaponLevel") or 0)
			local chance = math.floor(Config.GetGearEnhanceChance(level) * 100 + 0.5)
			table.insert(lines, string.format("<b>%s</b>\n<font color='#78ff8c'>▶ %s</font>", now, Config.FormatGearStat(slot.Key, Config.GetGearStat(slot.Key, rarity, level + 1))))
			table.insert(lines, "")
			table.insert(lines, string.format("Success rate <b><font color='#%s'>%d%%</font></b>   <font size='10' color='#aaaabb'>(kept on failure)</font>", chance >= 80 and "78ff8c" or (chance >= 60 and "ffd966" or "ff9a6e"), chance))
			enhanceSlotButton.Text = string.format("💰 %d G   Upgrade", cost)
			enhanceSlotButton.BackgroundColor3 = gold >= cost and GREEN or Color3.fromRGB(95, 60, 62)
		else
			table.insert(lines, "<b>" .. now .. "</b>")
			table.insert(lines, "\n<font color='#ffd966'>Max upgrade level!</font>")
			enhanceSlotButton.Text = "MAX"
			enhanceSlotButton.BackgroundColor3 = GRAY
		end
		detailText.Text = table.concat(lines, "\n")
	end

	powerLabel.Text = string.format("⚡ Power %d", player:GetAttribute("Power") or 0)
	ticketLabel.Text = string.format("🎫 Tickets: %d", tickets)
	rollOne.BackgroundColor3 = tickets > 0 and Color3.fromRGB(120, 80, 210) or Color3.fromRGB(80, 70, 100)
	local many = math.min(10, tickets)
	local canTen = many >= 2
	rollButton.AutoButtonColor = canTen
	rollButton.BackgroundColor3 = canTen and Color3.fromRGB(165, 70, 245) or Color3.fromRGB(62, 58, 78)
	rollButton.TextTransparency = canTen and 0 or 0.45
	rollButton.Text = canTen and string.format("🎰 Roll x%d!\n%d Tickets", many, many) or "🎰 Multi Roll\nNeeds 2+ Tickets (max 10)"
	state.Rebuild = rebuildCharacter
end
state.Reopen = function() rebuildCharacter() end
gearHooks.Rebuild = rebuildCharacter
end -- (장비 창 do 블록 끝)

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
	if not result.Roll then
		SoundBank.Play(sfxParent, "Enh_Hammer")
		task.delay(0.12, function() SoundBank.Play(sfxParent, result.Ok and "Enh_Success" or "Enh_Fail") end)
	end
	task.delay(0.3, function() if gearHooks.Rebuild then gearHooks.Rebuild() end end)
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
			SoundBank.Play(sfxParent, "Enh_Success")
			if data.Penalty then
				paint(penCard, data.Penalty.Icon, "⚠ " .. data.Penalty.Name, string.format("%s\nGold +%d%% instead", data.Penalty.Desc, data.Penalty.Gold), Color3.fromRGB(255, 130, 120))
				task.delay(0.12, function() SoundBank.Play(sfxParent, "Enh_Fail") end)
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

do
	local popup = create("Frame", {
		Name = "UpgradePopup", Size = UDim2.new(0, 330, 0, 84), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96),
		BackgroundColor3 = Color3.fromRGB(28, 40, 34), BorderSizePixel = 0, Visible = false, ZIndex = 80,
	}, gui)
	rounded(popup, 14)
	create("UIStroke", { Color = Color3.fromRGB(120, 255, 150), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, popup)
	local popupText = makeLabel({ Size = UDim2.new(1, -20, 0, 26), Position = UDim2.new(0, 10, 0, 6), Font = Enum.Font.GothamBlack, TextSize = 14, ZIndex = 81 }, popup)
	local popupButton = makeButton({
		Size = UDim2.new(1, -24, 0, 38), Position = UDim2.new(0, 12, 0, 38), Text = "⬆ Auto-equip stronger gear", TextSize = 15,
		Font = Enum.Font.GothamBlack, BackgroundColor3 = Color3.fromRGB(60, 190, 100), ZIndex = 81,
	}, popup)
	local shownAt = 0
	local function hide() popup.Visible = false end
	popupButton.Activated:Connect(function()
		Remotes.Inventory:FireServer("AutoEquip")
		hide()
	end)
	Remotes.Gear.OnClientEvent:Connect(function(action, result)
		if action ~= "Result" or not result.Roll or (result.Upgrades or 0) <= 0 then return end
		task.delay(1.8, function()
			popupText.Text = string.format("🔥 Better gear dropped! (%d slot(s))", result.Upgrades)
			popup.Visible = true
			shownAt = os.clock()
			local mine = shownAt
			task.delay(14, function() if shownAt == mine then hide() end end)
		end)
	end)
end

do
	local ICONS = { Armor = "🛡", Gloves = "🧤", Boots = "👢", Helmet = "⛑", Ring = "💍", Necklace = "📿" }
	local SHAKE = { 0.35, 0.5, 0.85, 1.25, 1.7 }  -- 등급별 흔들리는 시간
	local HOLD = { 1.0, 1.1, 1.6, 2.2, 3.0 }       -- 카드 유지 시간
	Remotes.Gear.OnClientEvent:Connect(function(action, result)
		local roll = action == "Result" and result.Roll
		if not roll then return end
		local multi = result.Rolls ~= nil and #result.Rolls > 1
		local old = gui:FindFirstChild("GachaReveal")
		if old then old:Destroy() end

		local rarity = roll.Rarity
		local color = Config.Gear.RarityColors[rarity]
		local root = create("TextButton", {
			Name = "GachaReveal", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
			Text = "", AutoButtonColor = false, ZIndex = 60,
		}, gui)
		local skipped = false
		root.Activated:Connect(function() skipped = true end)
		local function fade(object, goal, time, style, direction)
			TweenService:Create(object, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal):Play()
		end
		local function pause(seconds)
			local untilTime = os.clock() + seconds
			while not skipped and root.Parent and os.clock() < untilTime do task.wait() end
		end
		fade(root, { BackgroundTransparency = 0.35 }, 0.2)

		task.spawn(function()
			local capsule = create("Frame", {
				Size = UDim2.new(0, 96, 0, 96), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, -80),
				BackgroundColor3 = Color3.fromRGB(235, 235, 245), BorderSizePixel = 0, ZIndex = 62,
			}, root)
			create("UICorner", { CornerRadius = UDim.new(1, 0) }, capsule)
			local capStroke = create("UIStroke", { Color = Color3.fromRGB(160, 160, 190), Thickness = 4 }, capsule)
			local band = create("Frame", { Size = UDim2.new(1, 0, 0, 8), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = Color3.fromRGB(90, 90, 120), BorderSizePixel = 0, ZIndex = 63 }, capsule)
			create("Frame", { Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(0.2, 0, 0.18, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 63 }, capsule)
			fade(capsule, { Position = UDim2.new(0.5, 0, 0.5, 0) }, 0.5, Enum.EasingStyle.Bounce)
			task.delay(0.4, function() SoundBank.Play(sfxParent, "Gacha_Drop") end)
			pause(0.55)

			local shakeTime = SHAKE[rarity]
			local started = os.clock()
			local hintColor = rarity >= 3 and color or Color3.fromRGB(190, 190, 210)
			local nextTick = 0
			while not skipped and root.Parent and os.clock() - started < shakeTime do
				local t = (os.clock() - started) / shakeTime
				if os.clock() >= nextTick then -- 점점 빨라지는 틱틱 소리
					nextTick = os.clock() + 0.2 - 0.12 * t
					SoundBank.Play(sfxParent, "Gacha_Tick", { Pitch = 0.8 + t * 0.8 })
				end
				capsule.Rotation = math.sin((os.clock() - started) * 40) * (6 + t * 14)
				capStroke.Color = Color3.fromRGB(160, 160, 190):Lerp(hintColor, t)
				capStroke.Thickness = 4 + t * (rarity >= 3 and 10 or 3)
				capsule.Position = UDim2.new(0.5, math.sin(os.clock() * 55) * t * 6, 0.5, 0)
				task.wait()
			end
			if not root.Parent then return end

			capsule:Destroy()
			SoundBank.Play(sfxParent, "Gacha_Pop" .. rarity)
			if rarity >= 4 then SoundBank.Play(sfxParent, "Skill_Ult", { Volume = 0.5 }) end
			for i = 1, math.max(1, rarity - 1) do
				task.delay((i - 1) * 0.18, function()
					if not root.Parent then return end
					local ring = create("Frame", {
						Size = UDim2.new(0, 40, 0, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundTransparency = 1, ZIndex = 61,
					}, root)
					create("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
					local stroke = create("UIStroke", { Color = color, Thickness = 8 }, ring)
					fade(ring, { Size = UDim2.new(0, 900, 0, 900) }, 0.9)
					fade(stroke, { Transparency = 1, Thickness = 1 }, 0.9)
				end)
			end
			local flash = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = rarity == 5 and Color3.new(1, 1, 1) or color, BackgroundTransparency = rarity >= 3 and 0.2 or 0.65, BorderSizePixel = 0, ZIndex = 70 }, root)
			fade(flash, { BackgroundTransparency = 1 }, 0.5)

			if multi then
				local grid = create("Frame", { Size = UDim2.new(0, 660, 0, 380), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundTransparency = 1, ZIndex = 62 }, root)
				makeLabel({ Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 0, 0), Text = string.format("🎰 %d-Roll Results", #result.Rolls), TextSize = 22, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 230, 150), ZIndex = 63 }, grid)
				local counts = {}
				local STATUS = { Equipped = "Equipped!", Bag = "Bag" }
				for index, r in ipairs(result.Rolls) do
					counts[r.Rarity] = (counts[r.Rarity] or 0) + 1
					task.delay((index - 1) * 0.1, function()
						if not root.Parent then return end
						SoundBank.Play(sfxParent, "Gacha_Card", { Pitch = 0.9 + 0.12 * r.Rarity })
						local col, row = (index - 1) % 5, (index - 1) // 5
						local rc = Config.Gear.RarityColors[r.Rarity]
						local cx, cy = 66 + col * 132, 122 + row * 158
						local cardM = create("Frame", {
							Size = UDim2.new(0, 10, 0, 10), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, cx, 0, cy),
							BackgroundColor3 = Color3.fromRGB(24, 22, 36), BorderSizePixel = 0, ZIndex = 63,
						}, grid)
						rounded(cardM, 12)
						local st = create("UIStroke", { Color = rc, Thickness = ({ 2, 2, 3, 4, 5 })[r.Rarity] }, cardM)
						if r.Rarity == 5 then
							local g = create("UIGradient", { Color = ColorSequence.new({
								ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 80)),
								ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 220, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
							}) }, st)
							task.spawn(function()
								local rot = 0
								while cardM.Parent do rot += 8 g.Rotation = rot task.wait() end
							end)
						end
						fade(cardM, { Size = UDim2.new(0, 120, 0, 146) }, 0.3, Enum.EasingStyle.Back)
						makeLabel({ Size = UDim2.new(1, 0, 0, 56), Position = UDim2.new(0, 0, 0, 10), Text = ICONS[r.Slot] or "🎁", TextSize = 36, ZIndex = 64 }, cardM)
						makeLabel({ Size = UDim2.new(1, -8, 0, 34), Position = UDim2.new(0, 4, 0, 64), Text = r.Name or "", TextSize = 11, Font = Enum.Font.GothamBold, TextColor3 = rc, ZIndex = 64 }, cardM)
						makeLabel({ Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, 100), Text = string.format("★ %s", Config.Gear.RarityNames[r.Rarity]), TextSize = 11, Font = Enum.Font.GothamBlack, TextColor3 = rc, ZIndex = 64 }, cardM)
						makeLabel({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -20), Text = STATUS[r.Status] or "Scrap", TextSize = 10, TextColor3 = Color3.fromRGB(190, 190, 210), ZIndex = 64 }, cardM)
						if r.Rarity >= 3 then
							local ringM = create("Frame", { Size = UDim2.new(0, 40, 0, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, cx, 0, cy), BackgroundTransparency = 1, ZIndex = 61 }, grid)
							create("UICorner", { CornerRadius = UDim.new(1, 0) }, ringM)
							local rs = create("UIStroke", { Color = rc, Thickness = 6 }, ringM)
							fade(ringM, { Size = UDim2.new(0, 260, 0, 260) }, 0.6)
							fade(rs, { Transparency = 1, Thickness = 1 }, 0.6)
						end
					end)
				end
				pause(#result.Rolls * 0.1 + 0.4)
				local parts = {}
				for rarity = 5, 1, -1 do
					if counts[rarity] then
						table.insert(parts, string.format("<font color='#%s'>%s %d</font>", Config.Gear.RarityColors[rarity]:ToHex(), Config.Gear.RarityNames[rarity], counts[rarity]))
					end
				end
				makeLabel({ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 1, -26), RichText = true, Text = table.concat(parts, "   ") .. "   <font color='#aaaabb' size='11'>(tap to close)</font>", TextSize = 15, Font = Enum.Font.GothamBold, ZIndex = 63 }, grid)
				skipped = false
				pause(6)
				if not root.Parent then return end
				fade(root, { BackgroundTransparency = 1 }, 0.25)
				game:GetService("Debris"):AddItem(root, 0.3)
				return
			end

			local card = create("Frame", {
				Size = UDim2.new(0, 60, 0, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
				BackgroundColor3 = Color3.fromRGB(24, 22, 36), BorderSizePixel = 0, ZIndex = 62,
			}, root)
			rounded(card, 16)
			local stroke = create("UIStroke", { Color = color, Thickness = 5 }, card)
			if rarity == 5 then
				local gradient = create("UIGradient", {
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 80)),
						ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 220, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
					}),
				}, stroke)
				task.spawn(function()
					local rotation = 0
					while root.Parent do
						rotation += 6
						gradient.Rotation = rotation
						task.wait()
					end
				end)
			end
			fade(card, { Size = UDim2.new(0, 340, 0, 220) }, 0.45, Enum.EasingStyle.Back)
			pause(0.3)
			if not root.Parent then return end
			makeLabel({ Size = UDim2.new(1, 0, 0, 70), Position = UDim2.new(0, 0, 0, 14), Text = ICONS[roll.Slot] or "🎁", TextSize = 48, ZIndex = 63 }, card)
			makeLabel({
				Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 92), Text = string.format("★ %s ★", Config.Gear.RarityNames[rarity]),
				TextSize = rarity >= 4 and 30 or 26, Font = Enum.Font.GothamBlack, TextColor3 = color, ZIndex = 63,
			}, card)
			makeLabel({
				Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 134), Text = roll.Name or "", TextSize = 17,
				Font = Enum.Font.GothamBold, ZIndex = 63,
			}, card)
			makeLabel({
				Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -28), Text = roll.Equipped and "Equipped!" or "Added to bag",
				TextSize = 11, TextColor3 = Color3.fromRGB(190, 190, 210), ZIndex = 63,
			}, card)

			skipped = false
			pause(HOLD[rarity])
			if not root.Parent then return end
			fade(root, { BackgroundTransparency = 1 }, 0.25)
			fade(card, { Size = UDim2.new(0, 60, 0, 40) }, 0.25)
			game:GetService("Debris"):AddItem(root, 0.3)
		end)
	end)
end

Remotes.OpenGear.OnClientEvent:Connect(function()
	gearMessage.Text = ""
	gearPanel.Visible = true
	if gearHooks.Rebuild then gearHooks.Rebuild() end
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

local invitePanel = makePanel({
	Size = UDim2.new(0, 340, 0, 100),
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 160),
	Visible = false,
}, gui)
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
		bannerSub.Text = string.format("%s · %s · Fail if monsters pile up! Survive to the end and the boss appears", state.TypeName or "", state.DifficultyName or "", state.MonstersLeft)
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
	if settings.DashCharges <= 0 then return end

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
	local reach = currentZone() == "Dungeon" and math.min(weaponRange() * 0.95, 80) or weaponRange() * 0.95
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
			local fromCenter = (Vector2.new(screen.X, screen.Y) - viewport / 2).Magnitude / viewport.Y -- 0 = 정중앙
			local distance = (target.Part.Position - root.Position).Magnitude
			local score = fromCenter * 100 + distance * 0.35
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

local function getAimPoint(screenPosition)
	local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	if result then
		return result.Position, result.Instance
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
		Text = "", BackgroundColor3 = Color3.fromRGB(34, 36, 58),
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
	RunService.RenderStepped:Connect(function()
		if autoMode then used = true end
		autoStroke.Color = autoMode and Color3.fromRGB(110, 255, 150) or Color3.fromRGB(120, 130, 190)
		autoStroke.Thickness = autoMode and 3 or 2
		autoButton.BackgroundColor3 = autoMode and Color3.fromRGB(32, 70, 52) or Color3.fromRGB(34, 36, 58)
		autoText.Text = autoMode and "<font color='#8fffb0'><b>Auto-Attack</b>\nON</font>" or "<b>Auto-Attack</b>\n<font color='#9aa0c8'>OFF</font>"
		local zone = currentZone()
		autoButton.Visible = zone == "Lobby" or zone == "Field" or zone == "Dungeon"
		local showHint = not used and player:GetAttribute("TutorialActive") == true and os.clock() > shownAt and os.clock() < shownAt + 40 and zone ~= "Dungeon" and not (settings.MenuPanel and settings.MenuPanel.Visible)
		hint.Visible = showHint
	end)
end

local function attackCooldown()
	local speedPoints = player:GetAttribute("SpeedPoints") or 0
	return Config.Player.BaseCooldown * Config.GetPlayerWeapon(player).Cooldown / ((1 + speedPoints * Config.Player.SpeedPerPoint) * (1 + (player:GetAttribute("PetAtkSpeed") or 0))) -- 펫 가속 포함
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
	Size = UDim2.new(0, 64, 0, 28), Position = UDim2.new(1, -76, 0, 10), Text = "Close (B)", TextSize = 11, BackgroundColor3 = GRAY,
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
	Growth = { { "Active", "⚔ Active Skills" }, { "Passive", "🌿 Passive · Training" }, { "Pet", "🐾 Pet (P)" } },
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
	local health = Config.Player.BaseHealth + (player:GetAttribute("HealthPoints") or 0) * Config.Player.HealthPerPoint + (player:GetAttribute("GearHealth") or 0) + Config.GetLevelHealth(player:GetAttribute("Level") or 1)
	local crit = ((player:GetAttribute("CritPoints") or 0) * Config.Player.CritPerPoint + (player:GetAttribute("GearCrit") or 0) + (weaponType.CritBonus or 0)) * 100
	local speed = Config.Player.WalkSpeed + (player:GetAttribute("GearSpeed") or 0)

	local summary = newRow(142)
	local menuLevel = player:GetAttribute("Level") or 1
	rowText(summary, string.format(
		"🎖 <font color='#8fd8ff'>Lv.%d</font>  (%s)   Damage +%d%% · HP +%d\n⚡ Power <font color='#ffe16e'>%d</font>\n❤ Max HP %d    🎯 Crit Chance %.1f%%    💨 Move Speed %.1f\n💰 %d G    🎫 Tickets %d\n🏔 Best field zone cleared: %d    🏰 Dungeons cleared: %d",
		menuLevel,
		menuLevel >= Config.Level.Max and "MAX" or string.format("%d / %d XP", player:GetAttribute("XP") or 0, player:GetAttribute("XPNeeded") or 1),
		math.floor((Config.GetLevelDamageMult(menuLevel) - 1) * 100 + 0.5), Config.GetLevelHealth(menuLevel),
		player:GetAttribute("Power") or 0, health, crit, speed,
		player:GetAttribute("Gold") or 0, player:GetAttribute("Tickets") or 0,
		player:GetAttribute("MaxZone") or 0, questState and questState.Stats and questState.Stats.DungeonClears or 0
	), 16)

	sectionTitle("Equipped Gear")
	local level = player:GetAttribute("WeaponLevel") or 0
	local weaponName, weaponColor = weaponText(level)
	local weaponRow = newRow(40)
	rowText(weaponRow, string.format("🔫 Weapon   <font color='#%s'>%s</font>", hex(weaponColor), weaponName))

	for _, slot in ipairs(Config.Gear.Slots) do
		local rarity = player:GetAttribute("Gear_" .. slot.Key .. "_R") or 0
		local gearLevel = player:GetAttribute("Gear_" .. slot.Key .. "_L") or 0
		local row = newRow(40)
		if rarity <= 0 then
			rowText(row, string.format("🛡 %s   <font color='#888888'>Empty (roll with Boss Tickets)</font>", slot.Name))
		else
			local color = Config.Gear.RarityColors[rarity]
			rowText(row, string.format("🛡 %s   <font color='#%s'>[%s] %s +%d</font>   %s", slot.Name, hex(color),
				Config.Gear.RarityNames[rarity], slot.Names[rarity], gearLevel,
				Config.FormatGearStat(slot.Key, Config.GetGearStat(slot.Key, rarity, gearLevel))))
		end
	end

	sectionTitle("📖 Stat Guide")
	do
		local glossary = {}
		for _, key in ipairs({ "Health", "Crit", "Speed", "Damage", "Xp", "Luck", "Haste", "Shot" }) do
			local info = Config.StatDesc[key]
			table.insert(glossary, string.format("<b>%s</b>  <font color='#bbbbcc'>%s</font>", info.Name, info.Desc))
		end
		local row = newRow(#glossary * 22 + 16)
		rowText(row, table.concat(glossary, "\n"), 13)
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
	sectionTitle(string.format("🔫 10 Weapon Types — one unlocks per upgrade milestone (every 15). Pick which unlocked weapon to fight with · Now: %s", Config.GetEraName(eraTier.Era)))

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
		Size = UDim2.new(1, -306, 1, -64), Position = UDim2.new(0, 294, 0, 10), RichText = true, TextSize = 12,
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

	-- 무기 목록은 높이가 정해진 작은 창 안에서만 스크롤된다: 위쪽 시연 / 설명이 목록을 내려도 화면 밖으로 밀려나지 않는다 (엑셀 틀 고정처럼)
	local listHost = newRow(178)
	local inner = create("ScrollingFrame", {
		Size = UDim2.new(1, -12, 1, -12), Position = UDim2.new(0, 6, 0, 6), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 5, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, listHost)
	create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, inner)
	local outerContent, outerOrder = activeContent, rowOrder
	activeContent, rowOrder = inner, 0
	task.defer(function() inner.CanvasPosition = Vector2.new(0, settings.WeaponListY or 0) end)
	for _, key in ipairs(order) do
		local info = Config.WeaponTypes[key]
		local look = Config.GetLookTier(level, key)
		local open = Config.IsWeaponUnlocked(level, key)
		local using = key == equippedKey
		local row = newRow(34, using and Color3.fromRGB(45, 70, 50) or (open and Color3.fromRGB(34, 38, 48) or Color3.fromRGB(28, 28, 38)))
		local mark = using and "▶" or (open and "✔" or "🔒")
		rowText(row, string.format("%s  <font color='#%s'><b>%s</b></font>   <font size='10' color='#8888aa'>%s%s</font>",
			mark, open and hex(look.Color) or "777788", info.Name, info.Trait, open and "" or string.format(" · Unlocks at +%d", Config.GetUnlockLevel(key))), 14, 24)
		if previewKey == key then
			create("UIStroke", { Color = Color3.fromRGB(255, 225, 120), Thickness = 2 }, row)
		end
		local pick = create("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 5 }, row)
		pick.Activated:Connect(function()
			settings.PreviewForm = key
			settings.DemoClock = 0
			settings.WeaponListY = inner.CanvasPosition.Y -- 다시 그려도 보던 자리에 머문다
			settings.RefreshMenu()
		end)
	end
	activeContent, rowOrder = outerContent, outerOrder
end

local function buildProgressRows(entries, remoteAction, showTitle)
	if not entries then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>Loading...</font>")
		return
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

local skipShownFrac = 0 -- 단축칸 게이지가 마지막으로 보여 준 비율 (줄어드는 연출용)
local function buildGrowthTab()
	local state = growthState
	if not state then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>Loading...</font>")
		return
	end

	local header = newRow(78)
	rowText(header, string.format(
		"⏱ Time Skip <font color='#ffe16e'><b>%s</b></font> owned      🏋 Training slots <b>%d / %d</b> in use\n<font size='11' color='#bbbbcc'>Training and breakthroughs finish on their own over time (even while offline). Time Skips shorten the wait, and you also earn them slowly from quests. You can reach everything without spending money.</font>",
		Config.FormatDuration(state.TimeSkip), #state.Jobs, state.Slots
	), 15, 24)

	local gaugeRow = newRow(40) -- 단축칸: 얻으면 가득 차고, 쓰면 줄어든다
	local cap = math.max(player:GetAttribute("TimeSkipCap") or 0, state.TimeSkip, 1)
	local frac = math.clamp(state.TimeSkip / cap, 0, 1)
	local gaugeBack = makePanel({ Size = UDim2.new(1, -24, 0, 18), Position = UDim2.new(0, 12, 0, 11), BackgroundColor3 = Color3.fromRGB(22, 24, 36) }, gaugeRow)
	local gaugeFill = makePanel({ Size = UDim2.new(skipShownFrac, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(215, 150, 60) }, gaugeBack)
	makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = "⏱ Skip gauge " .. Config.FormatDuration(state.TimeSkip), TextSize = 10, ZIndex = 3 }, gaugeBack)
	game:GetService("TweenService"):Create(gaugeFill, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(frac, 0, 1, 0) }):Play()
	skipShownFrac = frac

	sectionTitle("🏋 Training Grounds — get permanently stronger")
	for _, stat in ipairs(Config.Growth.Stats.Order) do
		local def = Config.Growth.Stats[stat]
		local level = state.Levels[stat] or 0
		local job
		for _, candidate in ipairs(state.Jobs) do
			if candidate.Stat == stat then
				job = candidate
			end
		end

		local current = Config.FormatTrainEffect(stat, level)
		local nextText = level < Config.Growth.MaxLevel and ("  →  " .. Config.FormatTrainEffect(stat, level + 1)) or "  (max)"
		local status
		if job then
			status = string.format("<font color='#ffd966'>Training · Time left %s</font>", Config.FormatDuration(growthRemaining(job.EndAt)))
		elseif level >= Config.Growth.MaxLevel then
			status = "<font color='#78ff8c'>Max level!</font>"
		else
			status = string.format("<font color='#bbbbcc'>Time needed %s · 💰 %d G</font>", Config.FormatDuration(Config.GetTrainTime(level)), Config.GetTrainGold(level))
		end

		local row = newRow(84)
		rowText(row, string.format("<font size='14'><b>%s %s</b></font>  Lv.%d / %d\n<font color='#ddddee'>%s%s</font>\n%s",
			def.Icon, def.Name, level, Config.Growth.MaxLevel, current, nextText, status), 14, 190)

		if job then
			makeButton({
				Size = UDim2.new(0, 160, 0, 34), Position = UDim2.new(1, -172, 0.5, -17),
				Text = "⏱ Use Time Skip", TextSize = 12, BackgroundColor3 = state.TimeSkip > 0 and Color3.fromRGB(200, 130, 40) or GRAY,
			}, row, function()
				Remotes.Growth:FireServer("Skip", "Train", stat)
			end)
		elseif level < Config.Growth.MaxLevel then
			makeButton({
				Size = UDim2.new(0, 160, 0, 34), Position = UDim2.new(1, -172, 0.5, -17),
				Text = "Start Training", TextSize = 13, BackgroundColor3 = GREEN,
			}, row, function()
				Remotes.Growth:FireServer("Train", stat)
			end)
		end
	end

	sectionTitle("🚧 Breakthrough — pass the level caps")
	local gateIndex
	for index, gate in ipairs(Config.Growth.Gates) do
		if gate > state.GatePassed then
			gateIndex = index
			break
		end
	end

	local gateRow = newRow(92)
	if not gateIndex then
		rowText(gateRow, "<font color='#78ff8c'>All breakthroughs complete! You can now grow freely up to max level.</font>")
	else
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

local function buildSkillTab(passiveOnly)
	if passiveOnly then
		sectionTitle("🌿 Passive Skills — always active, no key press needed. Level up with Gold")
	else
		sectionTitle("⚔ Active Skills — press the key in the field / dungeons (C Heal · V Ultimate). Level up with Gold to get stronger and cut cooldowns")
	end
	local U = Config.SkillUpgrade
	for _, key in ipairs(Config.Skills.UpgradeOrder) do
		local cfg = Config.Skills[key]
		if (cfg.Passive == true) ~= (passiveOnly == true) then continue end
		local level = metaState and metaState.Skills[key] or 1
		local lv = level - 1
		local detail
		if key == "Barrier" then
			detail = string.format("Lasts %.1fs", cfg.Duration + U.BarrierDuration * lv)
		elseif key == "Blast" then
			detail = string.format("Radius %.1f · Damage x%.2f", cfg.Radius + U.BlastRadius * lv, cfg.Mult * (1 + U.BlastMult * lv))
		elseif key == "Focus" then
			detail = string.format("NEAR MISS lasts %.1fs · keeps at least %d stacks even if broken", Config.NearMiss.Duration + U.FocusDuration * lv, math.floor(Config.NearMiss.MaxStacks * 0.5 * lv / math.max(1, U.MaxLevel - 1)))
		elseif key == "Heal" then
			detail = string.format("Restores %d%% HP", math.floor((cfg.Ratio + U.HealRatio * lv) * 100 + 0.5))
		else
			detail = string.format("Damage x%.2f · %d targets (gauge %d)", cfg.Mult * (1 + U.UltMult * lv), cfg.MaxTargets + math.floor(U.UltTargets * lv + 0.001), cfg.Cost)
		end
		local row = newRow(74)
		rowText(row, string.format("<font size='14'><b>[%s] %s %s</b></font>  <font color='#ffd966'>Lv.%d / %d</font>\n<font color='#bbbbcc'>%s</font>\n<font color='#9ad7ff'>%s%s</font>",
			cfg.Key, cfg.Icon, cfg.Name, level, U.MaxLevel, cfg.Desc, detail, cfg.Passive and "" or string.format(" · Cooldown %.1fs", cfg.Cooldown * (1 - U.CooldownPerLevel * lv))), 14, 190)
		local maxed = level >= U.MaxLevel
		makeButton({
			Size = UDim2.new(0, 150, 0, 34), Position = UDim2.new(1, -162, 0.5, -17),
			Text = maxed and "MAX" or string.format("Upgrade %d G", Config.GetSkillUpgradeCost(level, player:GetAttribute("WeaponLevel"))),
			BackgroundColor3 = maxed and GRAY or GREEN,
		}, row, function()
			if not maxed then
				Remotes.Meta:FireServer("SkillUp", key)
			end
		end)
	end
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
		makeButton({
			Size = UDim2.new(0, 150, 0, 32), Position = UDim2.new(0, 10 + (index - 1) * 158, 0.5, -16), Text = option[2], TextSize = 13,
			BackgroundColor3 = active and Color3.fromRGB(70, 104, 206) or Color3.fromRGB(44, 48, 72),
			TextColor3 = active and Color3.fromRGB(255, 232, 160) or Color3.fromRGB(170, 176, 200),
		}, row, function()
			onPick(option[1])
		end)
	end
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
		if sub == "Passive" then
			buildSkillTab(true)
			sectionTitle("🏋 Training · Breakthrough — permanent growth that runs even while offline (a kind of passive)")
			if locked then
				MENU.locked()
			else
				buildGrowthTab()
			end
		else
			buildSkillTab(false)
		end
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
		if menuPanel.Visible then
			refreshMenu()
		end
	end
end)

Remotes.Inventory.OnClientEvent:Connect(function(action, data)
	if action == "State" then
		inventoryState = data
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
		if menuPanel.Visible and currentTab == "Growth" and MENU.Sub.Growth == "Passive" then
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
local menuRefreshQueued = false
local MENU_IGNORE = {
	IdleSeconds = true, IdleEarned = true, IdleRate = true, IdleMultTotal = true, IdleCapHours = true, IdleFullGold = true, IdleActive = true,
	DummyDps = true, DummyTick = true, UltCharge = true, Combo = true, ShakeTick = true, ShakeStrength = true, NearMissStacks = true,
	NearMissEnd = true, NearMissLen = true, Power = true, Stamina = true, DungeonLabel = true,
}
local MENU_SLOW = { Gold = true, XP = true, XPNeeded = true }
local lastMenuRefresh = 0
player.AttributeChanged:Connect(function(name)
	if not menuPanel.Visible or menuRefreshQueued or MENU_IGNORE[name] then return end
	menuRefreshQueued = true
	local wait = MENU_SLOW[name] and math.max(0, 2 - (os.clock() - lastMenuRefresh)) or 0
	task.delay(wait, function()
		menuRefreshQueued = false
		if menuPanel.Visible then
			lastMenuRefresh = os.clock()
			refreshMenu()
		end
	end)
end)

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

do
local RADAR_SIZE, RADAR_RANGE = 150, 100
local radarFrame = create("Frame", {
	Name = "RadarFrame", Size = UDim2.new(0, RADAR_SIZE, 0, RADAR_SIZE), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16),
	BackgroundColor3 = Color3.fromRGB(14, 18, 28), BackgroundTransparency = 0.25, BorderSizePixel = 0, Visible = false,
}, gui)
create("UICorner", { CornerRadius = UDim.new(1, 0) }, radarFrame)
create("UIStroke", { Color = Color3.fromRGB(110, 150, 220), Thickness = 2 }, radarFrame)
create("Frame", { -- 나 (중앙)
	Size = UDim2.new(0, 8, 0, 8), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(90, 220, 255), BorderSizePixel = 0, ZIndex = 3,
}, radarFrame)
local radarDots = {}

local function radarDot(index)
	local dot = radarDots[index]
	if not dot then
		dot = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, ZIndex = 2 }, radarFrame)
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
		radarDots[index] = dot
	end
	return dot
end

local radarClock = 0
local radarState = {}
RunService.RenderStepped:Connect(function(dt)
	radarClock += dt
	if radarClock < 0.05 then return end
	radarClock = 0
	local zone = currentZone()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	radarFrame.Visible = settings.Radar and (zone == "Field" or zone == "Dungeon") and root ~= nil
	if not radarFrame.Visible then return end

	local look = camera.CFrame.LookVector
	local yaw = math.atan2(look.X, -look.Z) -- 카메라가 -Z를 볼 때 0
	local cosY, sinY = math.cos(yaw), math.sin(yaw)
	local used = 0
	for _, part in ipairs(CollectionService:GetTagged("Monster")) do
		if part:IsDescendantOf(workspace) and used < 60 then
			local offset = part.Position - root.Position
			local rx = offset.X * cosY + offset.Z * sinY   -- 오른쪽
			local ry = offset.X * sinY - offset.Z * cosY   -- 앞쪽 (+)
			local dist = math.sqrt(rx * rx + ry * ry)
			if dist < 400 then
				used += 1
				local clamped = dist > RADAR_RANGE
				local scale = clamped and RADAR_RANGE / dist or 1
				local px = 0.5 + (rx * scale) / RADAR_RANGE * 0.47
				local py = 0.5 - (ry * scale) / RADAR_RANGE * 0.47
				local dot = radarDot(used)
				local boss, gold = CollectionService:HasTag(part, "RadarBoss"), CollectionService:HasTag(part, "RadarGold")
				local size = boss and 11 or (gold and 10 or 6)
				if clamped then size = math.max(4, size - 2) end
				dot.Position = UDim2.new(px, 0, py, 0)
				local cache = radarState[dot]
				if not cache then
					cache = {}
					radarState[dot] = cache
				end
				if cache.Size ~= size then
					cache.Size = size
					dot.Size = UDim2.new(0, size, 0, size)
				end
				local color = boss and Color3.fromRGB(190, 90, 255) or gold and Color3.fromRGB(255, 215, 50)
					or CollectionService:HasTag(part, "RadarElite") and Color3.fromRGB(255, 190, 60) or Color3.fromRGB(255, 80, 80)
				if cache.Color ~= color then
					cache.Color = color
					dot.BackgroundColor3 = color
				end
				if cache.Clamped ~= clamped then
					cache.Clamped = clamped
					dot.BackgroundTransparency = clamped and 0.5 or 0
				end
				if not dot.Visible then dot.Visible = true end
			end
		end
	end
	for i = used + 1, #radarDots do
		radarDots[i].Visible = false
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
		BackgroundColor3 = Color3.fromRGB(28, 28, 42), BorderSizePixel = 0,
	}, skillBar)
	rounded(slot)
	local slotStroke = create("UIStroke", { Color = skillKey == "Ult" and Color3.fromRGB(255, 90, 90) or Color3.fromRGB(110, 150, 220), Thickness = 2 }, slot)
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
	skillSlots[skillKey] = { Cover = cover, Timer = timer, Stroke = slotStroke }
end

do
	local slot = create("Frame", { Size = UDim2.new(0, 62, 0, 62), Position = UDim2.new(0, 0, 0, 0), BackgroundColor3 = Color3.fromRGB(28, 28, 42), BorderSizePixel = 0 }, skillBar)
	rounded(slot)
	create("UIStroke", { Color = Color3.fromRGB(120, 210, 255), Thickness = 2 }, slot)
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
	if os.clock() < (skillReadyAt[skillKey] or 0) then return end
	if skillKey == "Ult" then
		if (player:GetAttribute("UltCharge") or 0) < Config.Skills.Ult.Cost then
			toast("🎯 Ultimate gauge not full yet! (Attack enemies to fill it)")
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local found = false
		if root then
			for _, monster in ipairs(game:GetService("CollectionService"):GetTagged("Monster")) do
				if monster:IsA("BasePart") and (monster.Position - root.Position).Magnitude <= Config.Skills.Ult.Radius + 5 then
					found = true
					break
				end
			end
		end
		if not found then
			toast("🎯 Deadeye: an enemy must be within " .. Config.Skills.Ult.Radius .. " range to lock on! (Camps are safe zones with no enemies)")
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
	skillBar.Visible = zone == "Lobby" or zone == "Field" or zone == "Dungeon"
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

local function isMouseOverButton(position)
	for _, object in ipairs(playerGui:GetGuiObjectsAtPosition(position.X, position.Y)) do
		if object:IsA("GuiButton") and object.Visible then
			return true
		end
	end
	return false
end

RunService.RenderStepped:Connect(function(dt)
	local modalOpen = menuPanel.Visible or enhancePanel.Visible or gearPanel.Visible or selectPanel.Visible or warpPanel.Visible
	if not modalOpen then
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
	end
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

Remotes.Hit.OnClientEvent:Connect(function(isCrit, killed)
	hitMarker = killed and 0.3 or 0.18
	hitMarkerCrit = isCrit or killed
	if killed then
		shake = math.max(shake, 0.5)
		local combo = player:GetAttribute("Combo") or 0
		SoundBank.Play(sfxParent, "Kill", { Pitch = 1 + math.min(0.7, combo * 0.02) })
	elseif isCrit then
		shake = math.max(shake, 0.25)
		SoundBank.Play(sfxParent, "Hit", { Pitch = 1.1 + math.random() * 0.15 })
	else
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
	Size = UDim2.new(0, 560, 0, 580), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Visible = false,
}, gui)
makeLabel({ Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 8), Text = "⚙ Settings / ❓ Help", Font = Enum.Font.GothamBlack, TextSize = 19 }, helpPanel)
makeLabel({
	Size = UDim2.new(1, -40, 0, 280), Position = UDim2.new(0, 20, 0, 50), RichText = true, TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	Text = table.concat({
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
		"4. Clearing Zone 2 unlocks Growth (training). Queue up training, and collect gear sets/uniques to boost your Power",
		"5. Once the field is conquered, challenge the Final Lord, then the weekly <b>Boss Rush</b> ranking",
	}, "\n"),
}, helpPanel)

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
settingButton(468, function() return "📡 Radar: " .. (settings.Radar and "ON" or "OFF") end, function() settings.Radar = not settings.Radar end)
makeButton({
	Size = UDim2.new(0, 160, 0, 36), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Text = "Close (H)", BackgroundColor3 = GRAY,
}, helpPanel, function()
	helpPanel.Visible = false
end)

function toggleHelp()
	helpPanel.Visible = not helpPanel.Visible
end

workspace.DescendantAdded:Connect(function(instance)
	if instance:IsA("Sound") and instance.Name == "GunShot" then
		instance.Volume = instance.Volume * settings.ShotVolume
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
		uiScale.Scale = math.clamp(math.min(viewport.X / 1100, viewport.Y / 720), 0.55, 1)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
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
