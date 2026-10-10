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
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false) then
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
		TextSize = 16,
		TextWrapped = true,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	if base.TextSize < 12 then base.TextSize = 12 end -- 작은 글씨 하한(모바일)
	return create("TextLabel", base, parent)
end

local function makeButton(props, parent, onClick)
	local base = {
		BackgroundColor3 = Color3.fromRGB(62, 96, 196),
		TextColor3 = Color3.fromRGB(240, 242, 250),
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		AutoButtonColor = true,
		BorderSizePixel = 0,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	local button = create("TextButton", base, parent)
	rounded(button, 8)
	if button.TextSize < 12 then button.TextSize = 12 end
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

local infoPanel = makePanel({ Size = UDim2.new(0, 240, 0, 176), Position = UDim2.new(0, 16, 0, 60), Visible = false }, gui) -- (예전 글자 패널: 이제 HudClient 의 카드가 대신한다. 값 계산 코드가 이 라벨을 쓰고 있어서 숨겨서만 둔다)
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
	TextSize = 16,
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
	local pg = gui.Parent -- 작은 화면: MobileLayoutClient 가 정한 아래 가운데 자리
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
	return Config.FormatWeapon(level), tier.Color
end

local enhancePanel   -- (아래 do 블록 안에서 만든다: 지역 변수 개수 제한 때문에 블록으로 감쌌다)
local refreshEnhance
do
local E = {} -- 이 블록 안에서만 쓰는 상태 (EnhanceBusy / EnhanceShownTier / EnhanceAffordable)
enhancePanel = makePanel({
	Size = UDim2.new(0, 400, 0, 560),
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
	Text = "🔨 무기 강화", Font = Enum.Font.GothamBlack, TextSize = 24, TextColor3 = Color3.fromRGB(255, 220, 130),
}, enhancePanel)
makeButton({
	Size = UDim2.new(0, 64, 0, 30), Position = UDim2.new(1, -74, 0, 12), Text = "닫기", TextSize = 15, BackgroundColor3 = Color3.fromRGB(110, 60, 70),
}, enhancePanel, function()
	enhancePanel.Visible = false
end)

local enhanceWeapon = makeLabel({
	Size = UDim2.new(1, -24, 0, 30), Position = UDim2.new(0, 12, 0, 50),
	Font = Enum.Font.GothamBlack, TextSize = 22, TextWrapped = true,
}, enhancePanel)

local medal = create("Frame", {
	Size = UDim2.new(0, 230, 0, 230), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 86),
	BackgroundColor3 = Color3.fromRGB(34, 30, 52), BorderSizePixel = 0,
}, enhancePanel)
create("UICorner", { CornerRadius = UDim.new(1, 0) }, medal)
local medalStroke = create("UIStroke", { Color = Color3.fromRGB(255, 200, 90), Thickness = 5 }, medal)
local medalGlow = create("Frame", {
	Size = UDim2.new(1.18, 0, 1.18, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(255, 200, 90), BackgroundTransparency = 0.82, BorderSizePixel = 0, ZIndex = 0,
}, medal)
create("UICorner", { CornerRadius = UDim.new(1, 0) }, medalGlow)
local medalGradient = create("UIGradient", {
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.5, 0.9), NumberSequenceKeypoint.new(1, 0.2) }),
}, medalGlow)

E.Rays = {}
for i = 1, 14 do
	local ray = create("Frame", {
		Size = UDim2.new(0, 10, 0, 190), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(255, 220, 130), BackgroundTransparency = 0.82, BorderSizePixel = 0, ZIndex = 0,
	}, medal)
	create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1) }) }, ray)
	E.Rays[i] = ray
end
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

local medalView = create("ViewportFrame", {
	Size = UDim2.new(0.86, 0, 0.86, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundTransparency = 1, Ambient = Color3.fromRGB(235, 235, 245), LightColor = Color3.fromRGB(255, 250, 235), LightDirection = Vector3.new(-0.4, -0.7, -0.6), ZIndex = 2,
}, medal)
local medalCam = create("Camera", { FieldOfView = 36 }, medalView)
medalView.CurrentCamera = medalCam
local medalModel, medalCenter, medalReach
local function showMedalWeapon(tierIndex)
	if medalModel then medalModel:Destroy() medalModel = nil end
	local previews = ReplicatedStorage:FindFirstChild("WeaponPreviews")
	local source = previews and previews:FindFirstChild("W" .. tierIndex)
	if not source then return end
	medalModel = source:Clone()
	medalModel.Parent = medalView
	local cf, size = medalModel:GetBoundingBox()
	medalCenter, medalReach = cf.Position, math.max(size.X, size.Y, size.Z)
end
RunService.RenderStepped:Connect(function()
	if not enhancePanel.Visible then return end
	local t = os.clock()
	medalGradient.Rotation = (t * 40) % 360
	medalGlow.BackgroundTransparency = 0.78 + 0.08 * math.sin(t * 2.2)
	for i, ray in ipairs(E.Rays) do
		ray.Rotation = (i - 1) * (360 / #E.Rays) + t * 14
		ray.BackgroundTransparency = 0.78 + 0.1 * math.sin(t * 2 + i)
	end
	for _, star in ipairs(E.Stars) do
		star.Label.BackgroundTransparency = 0.25 + 0.7 * (0.5 + 0.5 * math.sin(t * star.Speed + star.Phase))
	end
	if E.RimGradient then E.RimGradient.Rotation = (t * 60) % 360 end
	if medalModel and medalCenter then -- 무기가 천천히 돈다 (카메라가 주위를 도는 방식)
		local angle = t * 0.9
		local d = medalReach * 1.35
		medalCam.CFrame = CFrame.lookAt(medalCenter + Vector3.new(math.sin(angle) * d, d * 0.28, math.cos(angle) * d), medalCenter)
	end
end)

local enhanceStage = makeLabel({
	Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 322), Font = Enum.Font.GothamBlack, TextSize = 34,
}, enhancePanel)
local segmentBar = create("Frame", {
	Size = UDim2.new(1, -60, 0, 14), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 366), BackgroundTransparency = 1,
}, enhancePanel)
create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, segmentBar)
local enhanceNext = makeLabel({
	Size = UDim2.new(1, -30, 0, 22), Position = UDim2.new(0, 15, 0, 386), TextSize = 14, RichText = true,
}, enhancePanel)

local enhanceInfo = makeLabel({
	Size = UDim2.new(1, -40, 0, 50), Position = UDim2.new(0, 20, 0, 414), TextSize = 15, RichText = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
}, enhancePanel)

local enhanceBanner = makeLabel({
	Size = UDim2.new(1, 0, 0, 56), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 200),
	Font = Enum.Font.GothamBlack, TextSize = 44, TextStrokeTransparency = 0, Visible = false, ZIndex = 8,
}, enhancePanel)
local enhanceResult = makeLabel({
	Size = UDim2.new(1, -24, 0, 22), Position = UDim2.new(0, 12, 0, 468), Font = Enum.Font.GothamBold, TextSize = 14,
}, enhancePanel)

local hammer = makeLabel({
	Size = UDim2.new(0, 70, 0, 70), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 70, 0, 150),
	Text = "🔨", TextSize = 56, Visible = false, ZIndex = 9, Rotation = -50,
}, enhancePanel)

local function manyLocked()
	return player:GetAttribute("TutorialActive") == true and player:GetAttribute("TutorialEnhanceCost") == nil
end
local function enhanceMany(count)
	if manyLocked() then
		toast("🔒 처음 강화는 [강화하기]로 직접 해 보세요! 곧 x10 / 최대 강화가 열려요.")
		return
	end
	if E.EnhanceBusy then return end
	E.EnhanceBusy = true
	Remotes.Enhance:FireServer(count)
	task.delay(1.1, function() E.EnhanceBusy = false end)
end
local enhanceTen = makeButton({
	Size = UDim2.new(0, 80, 0, 54), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 214, 1, -14),
	Text = "x10\n강화", TextSize = 16, Font = Enum.Font.GothamBold, BackgroundColor3 = Color3.fromRGB(60, 120, 200),
}, enhancePanel, function() enhanceMany(10) end)
local enhanceMax = makeButton({
	Size = UDim2.new(0, 80, 0, 54), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 302, 1, -14),
	Text = "최대\n강화", TextSize = 16, Font = Enum.Font.GothamBold, BackgroundColor3 = Color3.fromRGB(190, 110, 40),
}, enhancePanel, function() enhanceMany(50) end)
do
	local function lockMany()
		local locked = manyLocked()
		for _, button in ipairs({ enhanceTen, enhanceMax }) do
			button.AutoButtonColor = not locked
			button.BackgroundTransparency = locked and 0.6 or 0
			button.TextTransparency = locked and 0.5 or 0
		end
		enhanceTen.Text = locked and "🔒\nx10" or "x10\n강화"
		enhanceMax.Text = locked and "🔒\n최대" or "최대\n강화"
	end
	player:GetAttributeChangedSignal("TutorialActive"):Connect(lockMany)
	player:GetAttributeChangedSignal("TutorialEnhanceCost"):Connect(lockMany)
	lockMany()
end
local enhanceButton = makeButton({
	Size = UDim2.new(0, 186, 0, 54), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20, 1, -14),
	Text = "강화하기", TextSize = 18, Font = Enum.Font.GothamBold, BackgroundColor3 = GREEN,
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
task.spawn(function() -- 버튼 위로 빛이 주기적으로 훑고 지나간다
	while enhancePanel.Parent do
		if enhancePanel.Visible then
			E.Shimmer.Position = UDim2.new(-0.1, 0, 0.5, 0)
			TweenService:Create(E.Shimmer, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { Position = UDim2.new(1.1, 0, 0.5, 0) }):Play()
		end
		task.wait(2.2)
	end
end)

function refreshEnhance()
	local level = player:GetAttribute("WeaponLevel") or 0
	local gold = player:GetAttribute("Gold") or 0
	local typeKey = player:GetAttribute("WeaponType") or "Pistol"
	local tierIndex = Config.GetWeaponTierIndex(level)
	local tiers = Config.Weapon.Tiers
	local tier = tiers[tierIndex]
	local stage = Config.GetWeaponStage(level)
	local color = tier.Rainbow and Color3.fromRGB(255, 120, 255) or tier.Color

	enhanceWeapon.Text = string.format("[%d/%d] %s", tier.Index, #tiers, Config.GetWeaponName(typeKey, level))
	enhanceWeapon.TextColor3 = color
	medalStroke.Color = color
	medalGlow.BackgroundColor3 = color
	if E.EnhanceShownTier ~= tierIndex then
		E.EnhanceShownTier = tierIndex
		showMedalWeapon(tierIndex)
	end

	enhanceStage.Text = string.format("+%d", stage)
	enhanceStage.TextColor3 = color
	if E.LastStage and E.LastStage ~= stage then -- 단계가 바뀌면 숫자가 톡 튀어 오른다
		enhanceStage.TextSize = 54
		TweenService:Create(enhanceStage, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = 34 }):Play()
	end
	E.LastStage = stage
	for _, child in ipairs(segmentBar:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	for i = 1, tier.Steps do
		local seg = create("Frame", {
			Size = UDim2.new(1 / tier.Steps, -4, 1, 0), LayoutOrder = i, BorderSizePixel = 0,
			BackgroundColor3 = i <= stage and color or Color3.fromRGB(55, 52, 72),
		}, segmentBar)
		create("UICorner", { CornerRadius = UDim.new(0, 4) }, seg)
	end

	if level >= Config.Weapon.MaxLevel then
		enhanceNext.Text = "<font color='#ffd966'>마지막 무기를 최대로 강화했어요!</font>"
		enhanceInfo.Text = ""
		enhanceButton.Text = "MAX"
		enhanceButton.BackgroundColor3 = GRAY
		return
	end
	local cost = Config.GetEnhanceCost(level)
	local chance = math.floor(Config.GetEnhanceChance(level) * 100 + 0.5)
	if tierIndex < #tiers then
		local nextTier = tiers[tierIndex + 1]
		enhanceNext.Text = string.format("▶ <b>%d단계</b> 더 하면 <font color='#9ad7ff'><b>%s</b></font> 로 진화!", nextTier.MinLevel - level, nextTier.Name)
	else
		enhanceNext.Text = ""
	end
	enhanceInfo.Text = string.format("공격력  <b>x%.2f</b> <font color='#78ff8c'>▶ x%.2f</font>\n성공 확률  <font color='#%s'><b>%d%%</b></font>   <font size='12' color='#aaaabb'>(실패해도 단계 유지)</font>",
		Config.GetDamageMultiplier(level), Config.GetDamageMultiplier(level + 1), chance >= 80 and "78ff8c" or (chance >= 60 and "ffd966" or "ff9a6e"), chance)
	local affordable = gold >= cost
	enhanceButton.Text = string.format("💰 %s G\n강화하기", tostring(cost))
	enhanceButton.BackgroundColor3 = affordable and GREEN or Color3.fromRGB(95, 60, 62)
	E.EnhanceAffordable = affordable
end

RunService.RenderStepped:Connect(function()
	if enhancePanel.Visible and E.EnhanceAffordable and not E.EnhanceBusy then
		local pulse = 1 + 0.02 * math.sin(os.clock() * 4)
		enhanceButton.Size = UDim2.new(0, 186 + (pulse - 1) * 300, 0, 54)
	end
end)

Remotes.Enhance.OnClientEvent:Connect(function(ok, message, summary)
	local oldTier = E.EnhanceShownTier
	refreshEnhance()
	local evolved = oldTier ~= nil and E.EnhanceShownTier ~= nil and E.EnhanceShownTier > oldTier
	do
		local level = player:GetAttribute("WeaponLevel") or 0
		local tierNow = Config.GetWeaponTier(level)
		local stageFrac = (level - tierNow.MinLevel) / math.max(1, tierNow.Steps)
		if evolved then
			SoundBank.Play(sfxParent, "Enh_Evolve")
		elseif summary and summary.Attempts and summary.Attempts > 1 then
			for i = 1, math.min(8, summary.Successes or 0) do
				task.delay((i - 1) * 0.09, function() SoundBank.Play(sfxParent, "Enh_Success", { Pitch = 0.85 + 0.06 * i }) end)
			end
			if (summary.Successes or 0) == 0 then SoundBank.Play(sfxParent, "Enh_Fail") end
		elseif ok then
			SoundBank.Play(sfxParent, "Enh_Success", { Pitch = 0.85 + 0.75 * stageFrac })
		else
			SoundBank.Play(sfxParent, "Enh_Fail")
		end
	end
	enhanceBanner.Visible = true
	enhanceBanner.Position = UDim2.new(0.5, 0, 0, 200)
	enhanceBanner.TextTransparency = 0
	enhanceBanner.TextStrokeTransparency = 0
	if evolved then
		enhanceBanner.Text = "✨ 진화! ✨"
		enhanceBanner.TextColor3 = Color3.fromRGB(255, 225, 100)
		medalStroke.Thickness = 12
		TweenService:Create(medalStroke, TweenInfo.new(0.7), { Thickness = 5 }):Play()
	elseif summary and summary.Attempts > 1 then
		enhanceBanner.Text = string.format("%d연 강화! 성공 %d", summary.Attempts, summary.Successes)
		enhanceBanner.TextColor3 = ok and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 160, 120)
		enhanceBanner.TextSize = 34
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
	if advanced and data.TargetName ~= "모루" and enhancePanel.Visible then
		task.delay(1.2, function() -- 강화 성공 연출을 잠깐 보여준 뒤
			enhancePanel.Visible = false
		end)
	end
end)
end -- (강화창 do 블록 끝)

local gearHooks = {}   -- 장비 창 안의 함수를 바깥에서 부르기 위한 표 (Rebuild: 캐릭터 3D 다시 복제)
local gearPanel   -- (아래 do 블록에서 만든다)
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
	Text = "🛡 장비 · 뽑기", Font = Enum.Font.GothamBlack, TextSize = 24, TextColor3 = Color3.fromRGB(235, 200, 255),
}, gearPanel)
makeButton({
	Size = UDim2.new(0, 64, 0, 30), Position = UDim2.new(1, -74, 0, 12), Text = "닫기", TextSize = 15, BackgroundColor3 = Color3.fromRGB(110, 60, 70),
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
	Size = UDim2.new(0, 210, 0, 24), Position = UDim2.new(0, 135, 0, 390), TextSize = 16, Font = Enum.Font.GothamBlack,
	TextColor3 = Color3.fromRGB(255, 225, 110),
}, gearPanel)

local function makeSlotBox(slotKey, x, y)
	local box = create("TextButton", {
		Size = UDim2.new(0, 104, 0, 100), Position = UDim2.new(0, x, 0, y), BackgroundColor3 = Color3.fromRGB(34, 32, 54), BorderSizePixel = 0, Text = "", AutoButtonColor = false,
	}, gearPanel)
	rounded(box, 12)
	local stroke = create("UIStroke", { Color = Color3.fromRGB(90, 90, 120), Thickness = 2 }, box)
	local icon = makeLabel({ Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 0, 6), TextSize = 32 }, box)
	local name = makeLabel({ Size = UDim2.new(1, -6, 0, 30), Position = UDim2.new(0, 3, 0, 48), TextSize = 11, Font = Enum.Font.GothamBold, TextWrapped = true }, box)
	local level = makeLabel({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -20), TextSize = 13, Font = Enum.Font.GothamBlack }, box)
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
	Size = UDim2.new(1, -20, 0, 214), Position = UDim2.new(0, 10, 0, 10), RichText = true, TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
}, detail)
local enhanceSlotButton = makeButton({
	Size = UDim2.new(1, -24, 0, 50), Position = UDim2.new(0, 12, 1, -112), Text = "강화", TextSize = 18, Font = Enum.Font.GothamBold, BackgroundColor3 = GREEN,
}, detail, function()
	Remotes.Gear:FireServer("Enhance", state.Selected)
end)
create("UIStroke", { Color = Color3.fromRGB(190, 255, 190), ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 2 }, enhanceSlotButton)
gearMessage = makeLabel({
	Size = UDim2.new(1, -16, 0, 40), Position = UDim2.new(0, 8, 1, -54), Font = Enum.Font.GothamBold, TextSize = 14, RichText = true,
}, detail)

local gachaBar = create("Frame", { Size = UDim2.new(1, -36, 0, 128), Position = UDim2.new(0, 18, 1, -142), BackgroundColor3 = Color3.fromRGB(58, 38, 92), BorderSizePixel = 0 }, gearPanel)
rounded(gachaBar, 14)
create("UIStroke", { Color = Color3.fromRGB(255, 210, 120), Thickness = 2 }, gachaBar)
create("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(110, 60, 170), Color3.fromRGB(48, 30, 80)), Rotation = 0 }, gachaBar)
local ticketLabel = makeLabel({
	Size = UDim2.new(0.5, 0, 0, 34), Position = UDim2.new(0, 20, 0, 10), Font = Enum.Font.GothamBlack, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left,
}, gachaBar)
local rateParts = {}
for index, rate in ipairs(Config.Gacha.Rates) do
	table.insert(rateParts, string.format("<font color='#%s'>%s %d%%</font>", Config.Gear.RarityColors[index]:ToHex(), Config.Gear.RarityNames[index], rate))
end
makeLabel({
	Size = UDim2.new(0.44, 0, 0, 60), Position = UDim2.new(0, 20, 0, 52), RichText = true, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	Text = table.concat(rateParts, "  ") .. "\n<font color='#c9c0e0'>같거나 낮은 등급은 골드로 교환 · 티켓은 던전 / 필드 보스에게서 나와요</font>",
}, gachaBar)
local rollOne = makeButton({
	Size = UDim2.new(0, 176, 0, 80), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -218, 0.5, 0),
	Text = "🎰 뽑기 x1\n티켓 1장", TextSize = 20, Font = Enum.Font.GothamBold, BackgroundColor3 = Color3.fromRGB(120, 80, 210),
}, gachaBar, function()
	Remotes.Gear:FireServer("Roll", 1)
end)
create("UIStroke", { Color = Color3.fromRGB(190, 170, 255), ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 2 }, rollOne)
local rollButton = makeButton({
	Size = UDim2.new(0, 200, 0, 80), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
	Text = "🎰 10연 뽑기!\n티켓 10장", TextSize = 22, Font = Enum.Font.GothamBold, BackgroundColor3 = Color3.fromRGB(165, 70, 245),
}, gachaBar, function()
	Remotes.Gear:FireServer("Roll", 10)
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
			ui.Name.Text = slot.Name .. " 비어 있음"
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
		detailText.Text = string.format("<font size='18'><b>%s</b></font>\n<font color='#9a9ab5'>비어 있어요</font>\n\n%s 효과\n<font color='#c9c0e0'>아래 뽑기로 장비를 얻거나, 필드에서 떨어진 장비를 가방(I)에서 장착하세요.</font>", slot.Name, slot.StatName)
		enhanceSlotButton.Text = "—"
		enhanceSlotButton.BackgroundColor3 = GRAY
		detailStroke.Color = Color3.fromRGB(110, 90, 160)
	else
		local color = Config.Gear.RarityColors[rarity]
		detailStroke.Color = color
		local lines = {
			string.format("<font size='18'><b><font color='#%s'>[%s] %s</font></b></font>  <b>+%d</b>", color:ToHex(), Config.Gear.RarityNames[rarity], slot.Names[rarity], level),
			"",
			"<font color='#c9c0e0'>" .. slot.StatName .. "</font>",
		}
		local now = Config.FormatGearStat(slot.Key, Config.GetGearStat(slot.Key, rarity, level))
		if level < maxLevel then
			local cost = Config.GetGearCost(slot.Key, rarity, level)
			local chance = math.floor(Config.GetGearEnhanceChance(level) * 100 + 0.5)
			table.insert(lines, string.format("<b>%s</b>\n<font color='#78ff8c'>▶ %s</font>", now, Config.FormatGearStat(slot.Key, Config.GetGearStat(slot.Key, rarity, level + 1))))
			table.insert(lines, "")
			table.insert(lines, string.format("성공 확률 <b><font color='#%s'>%d%%</font></b>   <font size='12' color='#aaaabb'>(실패해도 유지)</font>", chance >= 80 and "78ff8c" or (chance >= 60 and "ffd966" or "ff9a6e"), chance))
			enhanceSlotButton.Text = string.format("💰 %d G   강화", cost)
			enhanceSlotButton.BackgroundColor3 = gold >= cost and GREEN or Color3.fromRGB(95, 60, 62)
		else
			table.insert(lines, "<b>" .. now .. "</b>")
			table.insert(lines, "\n<font color='#ffd966'>최대 강화 단계!</font>")
			enhanceSlotButton.Text = "MAX"
			enhanceSlotButton.BackgroundColor3 = GRAY
		end
		detailText.Text = table.concat(lines, "\n")
	end

	powerLabel.Text = string.format("⚡ 전투력 %d", player:GetAttribute("Power") or 0)
	ticketLabel.Text = string.format("🎫 티켓 %d장", tickets)
	rollButton.BackgroundColor3 = tickets > 0 and Color3.fromRGB(165, 70, 245) or Color3.fromRGB(80, 70, 100)
	rollOne.BackgroundColor3 = tickets > 0 and Color3.fromRGB(120, 80, 210) or Color3.fromRGB(80, 70, 100)
	if tickets >= 10 then
		rollButton.Text = "🎰 10연 뽑기!\n티켓 10장"
	elseif tickets > 1 then
		rollButton.Text = string.format("🎰 전부 뽑기!\n티켓 %d장", tickets)
	else
		rollButton.Text = "🎰 10연 뽑기\n티켓 10장 필요"
	end
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
	if not result.Roll then -- 장비 강화 결과음 (뽑기는 아래 뽑기 연출이 따로 소리를 낸다)
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
		Name = "RollPopup", Size = UDim2.new(0, 460, 0, 96), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 176),
		BackgroundColor3 = Color3.fromRGB(18, 20, 30), BackgroundTransparency = 0.1, BorderSizePixel = 0, Visible = false, ZIndex = 75,
	}, gui)
	rounded(popup, 14)
	local popScale = create("UIScale", { Scale = 1 }, popup)
	local function half(xScale, color)
		local frame = create("Frame", {
			Size = UDim2.new(0.5, -8, 1, -12), Position = UDim2.new(xScale, xScale == 0 and 6 or 2, 0, 6),
			BackgroundColor3 = color, BackgroundTransparency = 0.75, BorderSizePixel = 0, ZIndex = 76,
		}, popup)
		rounded(frame, 10)
		local stroke = create("UIStroke", { Color = color, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
		local icon = makeLabel({ Size = UDim2.new(0, 56, 1, 0), Position = UDim2.new(0, 4, 0, 0), TextSize = 38, ZIndex = 77 }, frame)
		local title = makeLabel({
			Size = UDim2.new(1, -66, 0, 24), Position = UDim2.new(0, 62, 0, 8), Font = Enum.Font.GothamBlack, TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 77,
		}, frame)
		local desc = makeLabel({
			Size = UDim2.new(1, -66, 0, 40), Position = UDim2.new(0, 62, 0, 32), TextSize = 12, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.fromRGB(215, 215, 230), ZIndex = 77,
		}, frame)
		return { Frame = frame, Stroke = stroke, Icon = icon, Title = title, Desc = desc }
	end
	local buffHalf = half(0, Color3.fromRGB(110, 210, 255))
	local penHalf = half(0.5, Color3.fromRGB(255, 90, 80))
	local token = 0
	Remotes.Dungeon.OnClientEvent:Connect(function(action, data)
		if action ~= "Roll" then return end
		token += 1
		local mine = token
		popup.Visible = true
		popScale.Scale = 0.6
		TweenService:Create(popScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		buffHalf.Title.Text, buffHalf.Desc.Text = "강화 추첨 중…", ""
		penHalf.Title.Text, penHalf.Desc.Text = "", ""
		task.spawn(function()
			for step = 1, 9 do -- 아이콘이 빠르게 돌아간다
				if token ~= mine then return end
				buffHalf.Icon.Text = ICONS[math.random(#ICONS)]
				penHalf.Icon.Text = data.Penalty and PEN_ICONS[math.random(#PEN_ICONS)] or ""
				SoundBank.Play(sfxParent, "Gacha_Tick")
				task.wait(0.06 + step * 0.012)
			end
			if token ~= mine then return end
			local buff = data.Buff
			if buff and buff.Special then -- 레어: 화면이 금빛으로 번쩍 + 흔들림 + 팝업이 커진다
				local flash = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 215, 120), BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 74 }, gui)
				TweenService:Create(flash, TweenInfo.new(0.55), { BackgroundTransparency = 1 }):Play()
				game:GetService("Debris"):AddItem(flash, 0.6)
				player:SetAttribute("ShakeStrength", 0.35)
				player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
				SoundBank.Play(sfxParent, "Gacha_Card")
				TweenService:Create(popScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.22 }):Play()
			end
			if buff then
				local special = buff.Special
				local color = special and Color3.fromRGB(255, 195, 70) or Color3.fromRGB(110, 210, 255)
				buffHalf.Icon.Text = buff.Icon
				buffHalf.Title.Text = (buff.Special and (data.Jackpot and "🌟 확정 레어! " or "★ 레어 ") or "✨ ") .. buff.Name
				buffHalf.Title.TextColor3 = color
				buffHalf.Desc.Text = buff.Desc
				buffHalf.Stroke.Color = color
				buffHalf.Frame.BackgroundColor3 = color
			end
			SoundBank.Play(sfxParent, "Enh_Success")
			if data.Penalty then
				penHalf.Icon.Text = data.Penalty.Icon
				penHalf.Title.Text = "⚠ " .. data.Penalty.Name
				penHalf.Title.TextColor3 = Color3.fromRGB(255, 130, 120)
				penHalf.Desc.Text = string.format("%s · 대신 골드 +%d%%", data.Penalty.Desc, data.Penalty.Gold)
				penHalf.Frame.Visible = true
				task.delay(0.12, function() SoundBank.Play(sfxParent, "Enh_Fail") end)
			else
				penHalf.Icon.Text = "🍀"
				penHalf.Title.Text = "패널티 없음!"
				penHalf.Title.TextColor3 = Color3.fromRGB(150, 255, 170)
				penHalf.Desc.Text = "이번엔 운이 좋았어요"
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
	local popupText = makeLabel({ Size = UDim2.new(1, -20, 0, 26), Position = UDim2.new(0, 10, 0, 6), Font = Enum.Font.GothamBlack, TextSize = 17, ZIndex = 81 }, popup)
	local popupButton = makeButton({
		Size = UDim2.new(1, -24, 0, 38), Position = UDim2.new(0, 12, 0, 38), Text = "⬆ 강한 장비로 자동 장착", TextSize = 18,
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
		task.delay(1.8, function() -- 뽑기 연출이 끝날 즈음 떠오른다
			popupText.Text = string.format("🔥 더 좋은 장비가 나왔어요! (%d부위)", result.Upgrades)
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
		local function pause(seconds) -- 건너뛰기를 누르면 바로 끝나는 대기
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
				makeLabel({ Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 0, 0), Text = string.format("🎰 %d연 뽑기 결과", #result.Rolls), TextSize = 26, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 230, 150), ZIndex = 63 }, grid)
				local counts = {}
				local STATUS = { Equipped = "장착!", Bag = "가방" }
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
						makeLabel({ Size = UDim2.new(1, 0, 0, 56), Position = UDim2.new(0, 0, 0, 10), Text = ICONS[r.Slot] or "🎁", TextSize = 42, ZIndex = 64 }, cardM)
						makeLabel({ Size = UDim2.new(1, -8, 0, 34), Position = UDim2.new(0, 4, 0, 64), Text = r.Name or "", TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = rc, ZIndex = 64 }, cardM)
						makeLabel({ Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, 100), Text = string.format("★ %s", Config.Gear.RarityNames[r.Rarity]), TextSize = 13, Font = Enum.Font.GothamBlack, TextColor3 = rc, ZIndex = 64 }, cardM)
						makeLabel({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -20), Text = STATUS[r.Status] or "분해", TextSize = 12, TextColor3 = Color3.fromRGB(190, 190, 210), ZIndex = 64 }, cardM)
						if r.Rarity >= 3 then -- 영웅 이상은 카드 뒤로 빛 고리가 퍼진다
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
				makeLabel({ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 1, -26), RichText = true, Text = table.concat(parts, "   ") .. "   <font color='#aaaabb' size='13'>(눌러서 닫기)</font>", TextSize = 18, Font = Enum.Font.GothamBold, ZIndex = 63 }, grid)
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
			makeLabel({ Size = UDim2.new(1, 0, 0, 70), Position = UDim2.new(0, 0, 0, 14), Text = ICONS[roll.Slot] or "🎁", TextSize = 56, ZIndex = 63 }, card)
			makeLabel({
				Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 92), Text = string.format("★ %s ★", Config.Gear.RarityNames[rarity]),
				TextSize = rarity >= 4 and 30 or 26, Font = Enum.Font.GothamBlack, TextColor3 = color, ZIndex = 63,
			}, card)
			makeLabel({
				Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 134), Text = roll.Name or "", TextSize = 20,
				Font = Enum.Font.GothamBold, ZIndex = 63,
			}, card)
			makeLabel({
				Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -28), Text = roll.Equipped and "장착했어요!" or "가방에 넣었어요",
				TextSize = 13, TextColor3 = Color3.fromRGB(190, 190, 210), ZIndex = 63,
			}, card)

			skipped = false -- 카드가 뜬 뒤에는 한 번 더 누르면 닫힌다
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
	if advanced and data.TargetName ~= "뽑기 머신" and gearPanel.Visible then
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
	Font = Enum.Font.GothamBlack, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left,
}, partyPanel)

local memberList = create("Frame", {
	Size = UDim2.new(1, -20, 0, 140), Position = UDim2.new(0, 10, 0, 40), BackgroundTransparency = 1,
}, partyPanel)
create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, memberList)

local leaveButton = makeButton({
	Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 186),
	Text = "파티 나가기", BackgroundColor3 = RED,
}, partyPanel, function()
	Remotes.Party:FireServer("Leave")
end)

makeLabel({
	Size = UDim2.new(1, -20, 0, 22), Position = UDim2.new(0, 10, 0, 224),
	Text = "로비 플레이어 (초대)", Font = Enum.Font.GothamBold, TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(190, 190, 210),
}, partyPanel)

local playerList = create("ScrollingFrame", {
	Size = UDim2.new(1, -20, 1, -256), Position = UDim2.new(0, 10, 0, 248),
	BackgroundTransparency = 1, BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 4,
}, partyPanel)
create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, playerList)

local partyData = nil -- 서버가 보내준 현재 파티 {Id, Leader, Members = {{UserId, Name}}}

local function isPartyLeaderOrSolo()
	return partyData == nil or partyData.Leader == player.UserId
end

local function refreshParty()
	local count = partyData and #partyData.Members or 1
	partyTitle.Text = string.format("파티 (%d/%d)", count, Config.Party.MaxSize)

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
				TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14,
			}, row)
			if partyData.Leader == player.UserId and member.UserId ~= player.UserId then
				makeButton({
					Size = UDim2.new(0, 48, 0, 22), Position = UDim2.new(1, -52, 0.5, -11),
					Text = "추방", TextSize = 12, BackgroundColor3 = RED,
				}, row, function()
					Remotes.Party:FireServer("Kick", member.UserId)
				end)
			end
		end
	else
		makeLabel({
			Size = UDim2.new(1, 0, 0, 40), Text = "파티가 없어요.\n아래에서 초대해보세요!",
			TextSize = 14, TextColor3 = Color3.fromRGB(190, 190, 210),
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
				TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14,
			}, row)
			if inParty then
				makeLabel({
					Size = UDim2.new(0, 56, 1, 0), Position = UDim2.new(1, -60, 0, 0),
					Text = "파티중", TextSize = 12, TextColor3 = Color3.fromRGB(150, 150, 170),
				}, row)
			elseif canInvite then
				makeButton({
					Size = UDim2.new(0, 48, 0, 22), Position = UDim2.new(1, -52, 0.5, -11),
					Text = "초대", TextSize = 12, BackgroundColor3 = GREEN,
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
	Font = Enum.Font.GothamBold, TextSize = 17,
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
	Text = "수락", BackgroundColor3 = GREEN,
}, invitePanel, function()
	if pendingInvite then
		Remotes.Party:FireServer("Accept", pendingInvite.UserId)
	end
	closeInvite(false)
end)
makeButton({
	Size = UDim2.new(0, 140, 0, 36), Position = UDim2.new(1, -160, 1, -46),
	Text = "거절", BackgroundColor3 = RED,
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
		inviteLabel.Text = string.format("%s 님이 파티에 초대했어요!", b)
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
	Text = "북쪽 던전 게이트 · 서쪽 허수아비 훈련장 · 동쪽 끝 사냥 필드   |   Shift 달리기 · Q 대시 · R 자동공격 · I 메뉴 · M 음악",
	TextSize = 14, TextColor3 = Color3.fromRGB(220, 220, 235), TextStrokeTransparency = 0.5,
}, lobbyFrame)

local dungeonFrame = create("Frame", { Name = "DungeonFrame", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false }, gui)

local banner = makePanel({
	Name = "WaveBanner", Size = UDim2.new(0, 420, 0, 96), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16),
}, dungeonFrame)
local bannerTitle = makeLabel({
	Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 6),
	Font = Enum.Font.GothamBlack, TextSize = 26,
}, banner)
local bannerSub = makeLabel({
	Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0, 44),
	TextSize = 16, TextColor3 = Color3.fromRGB(210, 210, 230),
}, banner)
local bannerMutator = makeLabel({
	Size = UDim2.new(1, -16, 0, 20), Position = UDim2.new(0, 8, 0, 70),
	TextSize = 13, TextColor3 = Color3.fromRGB(255, 205, 100), Font = Enum.Font.GothamBold,
}, banner)

local bonusBar = makePanel({
	Name = "BonusBar", Size = UDim2.new(0, 420, 0, 22), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 118), Visible = false,
}, dungeonFrame)
local bonusFill = create("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 200, 70), BorderSizePixel = 0 }, bonusBar)
rounded(bonusFill)
local bonusText = makeLabel({ Size = UDim2.new(1, 0, 1, 0), Font = Enum.Font.GothamBold, TextSize = 13, TextStrokeTransparency = 0.4 }, bonusBar)
local limitBar = makePanel({
	Name = "LimitBar", Size = UDim2.new(0, 420, 0, 22), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 144), Visible = false,
}, dungeonFrame)
local limitFill = create("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(110, 210, 120), BorderSizePixel = 0 }, limitBar)
rounded(limitFill)
local limitText = makeLabel({ Size = UDim2.new(1, 0, 1, 0), Font = Enum.Font.GothamBold, TextSize = 13, TextStrokeTransparency = 0.4 }, limitBar)

local bossBar = makePanel({
	Name = "BossBar", Size = UDim2.new(0, 460, 0, 26), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120), Visible = false,
}, dungeonFrame)
local bossFill = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(200, 40, 50), BorderSizePixel = 0 }, bossBar)
rounded(bossFill)
local bossName = makeLabel({
	Size = UDim2.new(1, 0, 1, 0), Font = Enum.Font.GothamBold, TextSize = 15, TextStrokeTransparency = 0.4,
}, bossBar)

local statPanel = makePanel({
	Name = "StatPanel", Size = UDim2.new(0, 380, 0, 170), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16),
}, dungeonFrame)

local statPoints = makeLabel({
	Size = UDim2.new(1, -20, 0, 28), Position = UDim2.new(0, 10, 0, 8),
	Font = Enum.Font.GothamBlack, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left,
}, statPanel)

local perkSummary = makeLabel({
	Size = UDim2.new(1, -20, 0, 40), Position = UDim2.new(0, 10, 0, 40),
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	TextSize = 13, RichText = true, TextColor3 = Color3.fromRGB(200, 200, 220),
}, statPanel)

makeButton({
	Size = UDim2.new(1, -20, 0, 24), Position = UDim2.new(0, 10, 1, -30),
	Text = "던전 나가기", TextSize = 13, BackgroundColor3 = GRAY,
}, statPanel, function()
	Remotes.Dungeon:FireServer("Leave")
end)

local dungeonState = nil
local openDungeonSelect -- 던전 선택창 (아래에서 정의)

local tracks = {}
local playlists = {} -- [이름] = { 오디오 ID... } (곡이 여러 개면 끝날 때마다 다른 곡으로 바뀐다)
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

if next(tracks) == nil and RunService:IsStudio() then
	print("[음악] 배경음악이 비어 있어요. ReplicatedStorage > AudioIds 스크립트에 오디오 ID(숫자)를 적으면 로비 / 필드 / 던전 / 보스 음악이 나와요. (README의 '소리 넣는 법' 참고)")
end

local settings = { Shake = true, Radar = true, ShotVolume = 1 }
local toggleHelp -- 도움말/설정창 (아래에서 정의)

local musicEnabled = true   -- M 키로 켜고 끈다
local currentMusic = nil
local musicScale = 1       -- 설정창에서 조절 (0 ~ 1.5)
local function musicVolume()
	return musicEnabled and Config.Audio.MusicVolume * musicScale or 0
end

local function playMusic(name)
	if name == currentMusic then return end
	currentMusic = name
	for trackName, sound in pairs(tracks) do
		if trackName == name then
			if not sound.IsPlaying then
				sound:Play()
			end
			TweenService:Create(sound, TweenInfo.new(1.5), { Volume = musicVolume() }):Play()
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
			TweenService:Create(sound, TweenInfo.new(0.4), { Volume = musicVolume() }):Play()
		end
	end
	toast(musicEnabled and "🔊 배경음악 켜짐 (M)" or "🔇 배경음악 꺼짐 (M)")
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
			playMusic(tracks.Dungeon and "Dungeon" or (tracks.Field and "Field" or "Lobby")) -- 보스가 나를 노리면 던전 전투 곡으로 바뀐다
		else
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local zoneKey = root and ("Field" .. Config.Field.ZoneOfX(root.Position.X))
			playMusic((zoneKey and tracks[zoneKey]) and zoneKey or (tracks.Field and "Field" or "Lobby")) -- 구역 전용 곡이 있으면 그 곡
		end
	elseif dungeonState and dungeonState.Phase == "Boss" then
		playMusic("Boss")
	else
		playMusic("Dungeon")
	end
end
player:GetAttributeChangedSignal("BossFight"):Connect(function() updateMusic() end)
player:GetAttributeChangedSignal("InDoomArena"):Connect(function() updateMusic() end)
task.spawn(function() -- 필드에서 구역 경계를 넘으면 그 구역 곡으로 (같은 곡이면 아무 일도 안 한다)
	while true do
		task.wait(2)
		if currentZone() == "Field" then updateMusic() end
	end
end)

local function refreshStats()
	statPoints.Text = "특성 (던전 동안만 유지)"
	statPoints.TextColor3 = Color3.new(1, 1, 1)

	local parts = {}
	for _, key in ipairs(Config.Perks.Order) do
		local perk = Config.Perks[key]
		local stacks = player:GetAttribute(perk.Attr) or 0
		if stacks > 0 then
			table.insert(parts, string.format("%s%s %d", perk.Icon, perk.Name, stacks))
		end
	end
	perkSummary.Text = #parts > 0 and ("내 특성: " .. table.concat(parts, "  ·  ")) or "내 특성: 아직 없음"
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
		bonusText.Text = state.BonusLeft <= 3 and "🎲 곧 터진다!!" or string.format("🎲 랜덤 보너스까지 %d초", state.BonusLeft)
	end
	if surviving and state.MonsterLimit then
		local ratio = math.clamp(state.MonstersLeft / state.MonsterLimit, 0, 1)
		TweenService:Create(limitFill, TweenInfo.new(0.5, Enum.EasingStyle.Linear), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
		if state.OverrunLeft then
			limitFill.BackgroundColor3 = Color3.fromRGB(235, 50, 50)
			limitText.Text = string.format("⚠ 몬스터 폭주! %d초 안에 줄이세요!  (%d / %d)", state.OverrunLeft, state.MonstersLeft, state.MonsterLimit)
		else
			limitFill.BackgroundColor3 = ratio >= 0.75 and Color3.fromRGB(240, 150, 50) or Color3.fromRGB(110, 210, 120)
			limitText.Text = string.format("👹 몬스터 %d / %d%s", state.MonstersLeft, state.MonsterLimit, ratio >= 0.75 and "  — 위험!" or "")
		end
	end
	if not state then return end
	bannerMutator.Text = state.MutatorText or ""

	if state.BossRatio then
		bossFill.Size = UDim2.new(math.clamp(state.BossRatio, 0, 1), 0, 1, 0)
		bossName.Text = state.BossName or "BOSS"
	end

	if state.Phase == "Starting" then
		bannerTitle.Text = string.format("%s 입장!", state.TypeName or "던전")
		bannerSub.Text = string.format("[%s] %d초 후 시작! 몰려오는 몬스터를 버텨요", state.DifficultyName or "", state.TimeLeft)
	elseif state.Phase == "Wave" and state.SurviveLeft then
		bannerTitle.Text = string.format("🛡 처치하며 버텨라!  %d초", state.SurviveLeft)
		bannerSub.Text = string.format("%s · %s · 몬스터가 너무 쌓이면 실패! 끝까지 버티면 보스 등장", state.TypeName or "", state.DifficultyName or "", state.MonstersLeft)
	elseif state.Phase == "Wave" then
		bannerTitle.Text = state.TotalWaves == 0 and string.format("🏯 %d층", state.Wave) or string.format("구역 %d / %d", state.Wave, state.TotalWaves)
		bannerSub.Text = string.format("%s · %s · 남은 몬스터 %d · 앞으로 쭉!", state.TypeName or "", state.DifficultyName or "", state.MonstersLeft)
	elseif state.Phase == "StatPhase" then
		bannerTitle.Text = "🎁 보너스 발동!"
		bannerSub.Text = "랜덤 강화가 적용됐어요"
	elseif state.Phase == "Moving" then
		bannerTitle.Text = state.StageText or "다음 방으로 이동하세요"
		bannerSub.Text = "하늘색 빛기둥을 따라가세요"
	elseif state.Phase == "Event" then
		bannerTitle.Text = state.StageText or "이벤트 방"
		bannerSub.Text = "특별한 방이에요!"
	elseif state.Phase == "Boss" then
		bannerTitle.Text = "BOSS"
		bannerSub.Text = string.format("남은 몬스터: %d", state.MonstersLeft)
	end
end

local resultPanel = makePanel({
	Size = UDim2.new(0, 460, 0, 340), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.45, 0), Visible = false,
}, dungeonFrame)
local resultTitle = makeLabel({
	Size = UDim2.new(1, 0, 0, 56), Position = UDim2.new(0, 0, 0, 12), Font = Enum.Font.GothamBlack, TextSize = 36,
}, resultPanel)
local resultInfo = makeLabel({
	Size = UDim2.new(1, -20, 0, 200), Position = UDim2.new(0, 10, 0, 72), TextSize = 17, RichText = true, TextYAlignment = Enum.TextYAlignment.Top,
}, resultPanel)
makeButton({
	Size = UDim2.new(0, 200, 0, 40), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
	Text = "지금 로비로", TextSize = 17,
}, resultPanel, function()
	Remotes.Dungeon:FireServer("Leave")
end)

local resultToken = 0
local function showResult(result)
	resultToken += 1
	local token = resultToken
	resultPanel.Visible = true
	resultTitle.Text = result.Victory and "🏆 던전 클리어!" or "💀 던전 실패"
	resultTitle.TextColor3 = result.Victory and Color3.fromRGB(255, 220, 90) or Color3.fromRGB(255, 110, 110)

	task.spawn(function()
		for remaining = result.ReturnDelay, 1, -1 do
			if token ~= resultToken or not resultPanel.Visible then return end
			local lootLines = {}
			for _, entry in ipairs(result.Loot or {}) do
				table.insert(lootLines, string.format("<font color='#%s' size='15'>%s</font>", Config.Gear.RarityColors[entry.Rarity]:ToHex(), entry.Text))
			end
			resultInfo.Text = string.format(
				"%s\n획득 골드  +%d G   🎫 티켓 +%d\n%s\n%d초 후 로비로 이동",
				(result.Victory and "끝까지 버텨서 보스 격파!" or "버티지 못했어요"), result.Gold, result.Tickets or 0,
				#lootLines > 0 and ("<b>📦 보스 상자</b>\n" .. table.concat(lootLines, "\n")) or "", remaining
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
	local zoneText = zone == "Lobby" and "로비" or zone == "Dungeon" and "던전" or string.format("필드 (최고 %d구역)", player:GetAttribute("MaxZone") or 0)

	local characterLevel = player:GetAttribute("Level") or 1
	local xp = player:GetAttribute("XP") or 0
	local xpNeeded = player:GetAttribute("XPNeeded") or 1
	local maxed = characterLevel >= Config.Level.Max
	local blocked = not maxed and characterLevel >= Config.GetLevelCap(player:GetAttribute("GatePassed") or 0)
	xpFill.Size = UDim2.new((maxed or blocked) and 1 or math.clamp(xp / xpNeeded, 0, 1), 0, 1, 0)
	xpFill.BackgroundColor3 = blocked and Color3.fromRGB(255, 170, 60) or Color3.fromRGB(110, 200, 255)
	local xpText = maxed and "MAX" or blocked and "돌파 필요!" or string.format("%d / %d XP", xp, xpNeeded)

	local keys = (player:GetAttribute("Keys") or 0) -- 쉬움 열쇠
	local keysNormal, keysHard = player:GetAttribute("KeysNormal") or 0, player:GetAttribute("KeysHard") or 0
	local keyCap = Config.Keys.Max + (player:GetAttribute("KeyCapBonus") or 0)
	local keyNext = player:GetAttribute("KeyNext") or 0
	local keyText = string.format("오늘 무료 %d/%d", player:GetAttribute("DungeonFree") or 0, Config.Keys.FreeDaily)

	infoLabel.Text = string.format(
		"🎖 <font color='#8fd8ff'>Lv.%d</font>  <font size='12' color='#aaaacc'>%s</font>\n💰 <font color='#ffd966'>%d G</font>   🎫 <font color='#d9a6ff'>%d</font>\n🗝<font color='#a6f0c8'>%d</font> 🔑<font color='#ffe08a'>%d</font> 🏆<font color='#ff9a9a'>%d</font> <font size='12' color='#aaaacc'>(%s)</font>\n⚡ 전투력 <font color='#ffe16e'>%d</font>\n⚔ <font color='#%s'>%s</font>\n📍 %s",
		characterLevel, xpText,
		player:GetAttribute("Gold") or 0, player:GetAttribute("Tickets") or 0,
		keys, keysNormal, keysHard, keyText,
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
		local bonus = (player:GetAttribute("GearSpeed") or 0) + (player:GetAttribute("TrainSpeed") or 0) + (player:GetAttribute("PetSpeed") or 0) + (player:GetAttribute("LvMove") or 0) -- 신발 장비 + 신속 단련 + 레벨 스탯
		humanoid.WalkSpeed = (sprinting and Config.Player.RunSpeed or Config.Player.WalkSpeed) + bonus
	end
end

player:GetAttributeChangedSignal("GearSpeed"):Connect(applySpeed)
player:GetAttributeChangedSignal("TrainSpeed"):Connect(applySpeed)
player:GetAttributeChangedSignal("PetSpeed"):Connect(applySpeed)

settings.DashCharges = Config.Player.DashCharges  -- 남은 대시 횟수 (스킬바에 표시)
settings.DashRefillAt = 0                        -- 다음 충전 시각

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
	if settings.DashCharges == P.DashCharges then -- 가득 찬 상태에서 처음 쓰면 충전 타이머 시작
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

RunService.RenderStepped:Connect(function(dt)
	local target = player:GetAttribute("DeadeyeActive") and 62 or (sliding and 108 or sprinting and 80 or 70) -- 데드아이: 줌인
	camera.FieldOfView += (target - camera.FieldOfView) * math.min(1, dt * 8)
end)

local autoMode = false
local lockTarget = nil     -- { Kind = "Dummy" | "Monster", Instance, Part }
local nextSearch = 0

local autoLabel = makeLabel({
	Size = UDim2.new(0, 460, 0, 30), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -128),
	BackgroundColor3 = Color3.fromRGB(20, 20, 30), BackgroundTransparency = 0.25,
	Font = Enum.Font.GothamBold, TextSize = 16, Visible = false, RichText = true,
}, gui)
rounded(autoLabel)

local lockHighlight = Instance.new("Highlight")
lockHighlight.FillTransparency = 1
lockHighlight.OutlineColor = Color3.fromRGB(255, 220, 80)
lockHighlight.OutlineTransparency = 0
lockHighlight.Enabled = false
lockHighlight.Parent = workspace

local function targetName(target)
	if not target then return "대상 찾는 중..." end
	if target.Kind == "Dummy" then
		local index = tonumber(string.sub(target.Instance.Name, 6))
		local info = index and Config.Dummy.List[index]
		return info and info.Name or "허수아비"
	end
	return "몬스터"
end

local function updateLockVisual()
	autoLabel.Visible = false -- 아래 R 자동 공격 버튼이 상태를 이미 보여 주므로 가운데 안내 띠는 쓰지 않는다 (잠금 대상은 노란 윤곽선으로 표시)
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
	local result = workspace:Raycast(origin, position - origin, params)
	return result == nil or result.Instance == target.Part or result.Instance:IsDescendantOf(target.Instance)
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

local hitMarker = 0      -- 적중 시 조준점이 색을 바꾸는 시간
local hitMarkerCrit = false
local shake = 0          -- 카메라 흔들림 세기
local crosshairKick = 0 -- 쏠 때마다 조준점이 벌어졌다 돌아오는 연출용

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
	Remotes.Attack:FireServer(worldPoint, manual == true) -- manual: 직접 클릭해서 쏜 것 (자동 공격과 구분: 약점 / 연습 판정용)
end

local function attack(screenPosition)
	local point, instance = getAimPoint(screenPosition)

	if autoMode then
		local target = resolveTarget(instance)
		if target then
			if target.Kind == "Dummy" and not dummyUsable(target.Instance) then
				toast("🛡 이 더미는 방어력이 높아서 지금 전투력으로는 공격이 튕겨 나가요")
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
	toast(autoMode and "🔒 자동 공격 ON — 허수아비/몬스터를 직접 클릭하면 그 대상으로 고정돼요 (R로 끄기)" or "자동 공격 OFF")
end

player:GetAttributeChangedSignal("Zone"):Connect(function()
	if autoMode and player:GetAttribute("Zone") == "Lobby" and not player:GetAttribute("TutorialDoom") then toggleAuto() end -- 첫 군주전(튜토리얼) 중에는 끄지 않는다
end)

player:GetAttributeChangedSignal("AutoOffTick"):Connect(function()
	if autoMode and player:GetAttribute("Zone") == "Lobby" then -- 허수아비는 마을에서만 친다: 필드(군주전)에서는 절대 끄지 않는다
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
	makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = "R", TextSize = 22, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(30, 30, 50) }, keycap)
	local autoText = makeLabel({
		Size = UDim2.new(1, -54, 1, -6), Position = UDim2.new(0, 50, 0, 3), TextSize = 14, Font = Enum.Font.GothamBold, RichText = true,
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
	makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = "R", TextSize = 60, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(30, 30, 50), ZIndex = 32 }, bigKey)
	makeLabel({
		Size = UDim2.new(1, -130, 1, -16), Position = UDim2.new(0, 118, 0, 8), RichText = true, TextSize = 20, ZIndex = 31, TextXAlignment = Enum.TextXAlignment.Left,
		Text = UserInputService.TouchEnabled and "<b>자동 공격!</b>\n<font size='15' color='#cfd3ea'>오른쪽 아래 <b>R 자동 공격</b> 버튼을 누르면\n알아서 쏴 줘요</font>" or "<b>자동 공격!</b>\n<font size='15' color='#cfd3ea'><b>R 키</b>를 누르면 가까운 적을\n알아서 조준해서 쏴 줘요</font>",
	}, hint)
	TweenService:Create(bigKey, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Size = UDim2.new(0, 94, 0, 94), Position = UDim2.new(0, 13, 0.5, -47) }):Play()

	local shownAt = os.clock() + 9   -- 접속 4초 뒤에 한 번 보여 준다
	local used = false
	RunService.RenderStepped:Connect(function()
		if autoMode then used = true end
		autoStroke.Color = autoMode and Color3.fromRGB(110, 255, 150) or Color3.fromRGB(120, 130, 190)
		autoStroke.Thickness = autoMode and 3 or 2
		autoButton.BackgroundColor3 = autoMode and Color3.fromRGB(32, 70, 52) or Color3.fromRGB(34, 36, 58)
		autoText.Text = autoMode and "<font color='#8fffb0'><b>자동 공격</b>\nON</font>" or "<b>자동 공격</b>\n<font color='#9aa0c8'>OFF</font>"
		local zone = currentZone()
		autoButton.Visible = zone == "Lobby" or zone == "Field" or zone == "Dungeon"
		local showHint = not used and os.clock() > shownAt and os.clock() < shownAt + 40 and zone ~= "Dungeon" and not (settings.MenuPanel and settings.MenuPanel.Visible)
		hint.Visible = showHint
	end)
end

local function attackCooldown()
	local speedPoints = player:GetAttribute("SpeedPoints") or 0
	return Config.Player.BaseCooldown * Config.GetPlayerWeapon(player).Cooldown / ((1 + speedPoints * Config.Player.SpeedPerPoint) * (1 + (player:GetAttribute("PetAtkSpeed") or 0))) -- 펫 가속 포함
end

local questState = nil   -- 서버가 보내준 퀘스트/업적/칭호 상태
local rankList = {}      -- 서버가 보내준 전투력 랭킹

do
	local mini = makePanel({
		Name = "RankMini", Size = UDim2.new(0, 270, 0, 138), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 444),
	}, lobbyFrame)
	makeLabel({
		Size = UDim2.new(1, -20, 0, 22), Position = UDim2.new(0, 10, 0, 6), Text = "🏆 전투력 랭킹",
		Font = Enum.Font.GothamBlack, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 225, 120),
	}, mini)
	local body = makeLabel({
		Size = UDim2.new(1, -20, 1, -32), Position = UDim2.new(0, 10, 0, 28), RichText = true, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "집계 중...",
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
		body.Text = #lines > 0 and table.concat(lines, "\n") or "아직 기록이 없어요"
	end)
	Remotes.Rank:FireServer("Request")
end

local menuPanel = makePanel({
	Size = UDim2.new(0, 860, 0, 580),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.55, 0),
	BackgroundColor3 = Color3.fromRGB(16, 18, 30),
	BackgroundTransparency = 0.03, -- 뒤 화면이 비쳐 글자가 섞여 보이지 않게 거의 불투명하게
	Visible = false,
}, gui)
settings.MenuPanel = menuPanel
create("UIStroke", { Color = Color3.fromRGB(110, 130, 220), Thickness = 1.5, Transparency = 0.35 }, menuPanel)

makeLabel({
	Size = UDim2.new(1, -90, 0, 36), Position = UDim2.new(0, 16, 0, 8),
	Text = "📋 메뉴", Font = Enum.Font.GothamBlack, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left,
}, menuPanel)

makeButton({
	Size = UDim2.new(0, 64, 0, 28), Position = UDim2.new(1, -76, 0, 10), Text = "닫기 (I)", TextSize = 13, BackgroundColor3 = GRAY,
}, menuPanel, function()
	menuPanel.Visible = false
end)

local TABS = {
	{ Key = "Inventory", Name = "캐릭터" }, -- 3D 캐릭터 + 장비 칸 + 가방 (메뉴를 열면 가장 먼저 보인다)
	{ Key = "Character", Name = "정보" },
	{ Key = "Weapon", Name = "무기" },
	{ Key = "Growth", Name = "성장" },
	{ Key = "Skill", Name = "스킬" },
	{ Key = "Pet", Name = "펫" },
	{ Key = "Quest", Name = "퀘스트" },
	{ Key = "Ach", Name = "업적" },
	{ Key = "Rank", Name = "랭킹" },
	{ Key = "Shop", Name = "상점" },
}
local currentTab = "Inventory"
local tabButtons = {}

local menuContent = create("ScrollingFrame", {
	Size = UDim2.new(1, -24, 1, -108), Position = UDim2.new(0, 12, 0, 96),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, menuPanel)
create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, menuContent)

local rowOrder = 0
local function newRow(height, color)
	rowOrder += 1
	return makePanel({
		Size = UDim2.new(1, -10, 0, height), LayoutOrder = rowOrder,
		BackgroundColor3 = color or Color3.fromRGB(36, 39, 58),
	}, menuContent)
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
		"🎖 <font color='#8fd8ff'>Lv.%d</font>  (%s)   공격력 +%d%% · 체력 +%d\n⚡ 전투력 <font color='#ffe16e'>%d</font>\n❤ 최대 체력 %d    🎯 치명타 확률 %.1f%%    💨 이동속도 %.1f\n💰 %d G    🎫 티켓 %d장\n🏔 필드 최고 %d구역 돌파    🏰 던전 클리어 %d회",
		menuLevel,
		menuLevel >= Config.Level.Max and "MAX" or string.format("%d / %d XP", player:GetAttribute("XP") or 0, player:GetAttribute("XPNeeded") or 1),
		math.floor((Config.GetLevelDamageMult(menuLevel) - 1) * 100 + 0.5), Config.GetLevelHealth(menuLevel),
		player:GetAttribute("Power") or 0, health, crit, speed,
		player:GetAttribute("Gold") or 0, player:GetAttribute("Tickets") or 0,
		player:GetAttribute("MaxZone") or 0, questState and questState.Stats and questState.Stats.DungeonClears or 0
	), 16)

	sectionTitle("장착 중인 장비")
	local level = player:GetAttribute("WeaponLevel") or 0
	local weaponName, weaponColor = weaponText(level)
	local weaponRow = newRow(40)
	rowText(weaponRow, string.format("🔫 무기   <font color='#%s'>%s</font>", hex(weaponColor), weaponName))

	for _, slot in ipairs(Config.Gear.Slots) do
		local rarity = player:GetAttribute("Gear_" .. slot.Key .. "_R") or 0
		local gearLevel = player:GetAttribute("Gear_" .. slot.Key .. "_L") or 0
		local row = newRow(40)
		if rarity <= 0 then
			rowText(row, string.format("🛡 %s   <font color='#888888'>비어 있음 (보스 티켓으로 뽑기)</font>", slot.Name))
		else
			local color = Config.Gear.RarityColors[rarity]
			rowText(row, string.format("🛡 %s   <font color='#%s'>[%s] %s +%d</font>   %s", slot.Name, hex(color),
				Config.Gear.RarityNames[rarity], slot.Names[rarity], gearLevel,
				Config.FormatGearStat(slot.Key, Config.GetGearStat(slot.Key, rarity, gearLevel))))
		end
	end

	sectionTitle("📖 스탯 설명")
	do
		local glossary = {}
		for _, key in ipairs({ "Health", "Crit", "Speed", "Damage", "Xp", "Luck", "Haste", "Shot" }) do
			local info = Config.StatDesc[key]
			table.insert(glossary, string.format("<b>%s</b>  <font color='#bbbbcc'>%s</font>", info.Name, info.Desc))
		end
		local row = newRow(#glossary * 22 + 16)
		rowText(row, table.concat(glossary, "\n"), 13)
	end

	do -- 환생
		local prestige = player:GetAttribute("Prestige") or 0
		local ready = (player:GetAttribute("Level") or 1) >= Config.Level.Max and prestige < Config.Prestige.Max
		local row = newRow(64)
		rowText(row, string.format("🌟 <b>환생 %d / %d</b>  (영구 공격력 +%d%% · 골드 +%d%%)\n<font size='13' color='#bbbbcc'>레벨 %d 에서 환생하면 레벨이 1로 돌아가고 영구 공격력 +%d%%, 골드 획득량 +%d%%. 장비/무기는 그대로예요. (로비에서)</font>",
			prestige, Config.Prestige.Max, math.floor(prestige * Config.Prestige.DamagePerRank * 100 + 0.5), math.floor(prestige * Config.Prestige.GoldPerRank * 100 + 0.5), Config.Level.Max, Config.Prestige.DamagePerRank * 100, Config.Prestige.GoldPerRank * 100), 14, 190)
		makeButton({
			Size = UDim2.new(0, 160, 0, 36), Position = UDim2.new(1, -172, 0.5, -18),
			Text = prestige >= Config.Prestige.Max and "MAX" or "환생하기", BackgroundColor3 = ready and Color3.fromRGB(200, 150, 40) or GRAY,
		}, row, function()
			Remotes.Meta:FireServer("Prestige")
		end)
	end

	sectionTitle("칭호 (업적을 달성하면 해금, 머리 위 이름표에 표시)")
	local titles = questState and questState.Titles or {}
	local equipped = questState and questState.Equipped
	if #titles == 0 then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>아직 해금한 칭호가 없어요. 업적 탭에서 도전해보세요!</font>")
	end
	for _, title in ipairs(titles) do
		local row = newRow(40)
		rowText(row, string.format("『%s』", title), 16, 150)
		local isEquipped = title == equipped
		makeButton({
			Size = UDim2.new(0, 110, 0, 28), Position = UDim2.new(1, -122, 0.5, -14),
			Text = isEquipped and "해제" or "장착", BackgroundColor3 = isEquipped and RED or GREEN,
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
	local tiers = Config.Weapon.Tiers
	local current = Config.GetWeaponTier(level)
	local stage = Config.GetWeaponStage(level)
	sectionTitle(string.format("🔫 무기 도감 — 무기마다 정해진 횟수만큼 강화하면 다음 무기로 자동 진화해요 (총 %d종)", #tiers))

	local shown = tiers[settings.PreviewTier or current.Index] or current
	local isMine = shown.Index == current.Index
	local classInfo = Config.WeaponTypes[shown.Class]
	local nextTier = tiers[shown.Index + 1]

	local header = newRow(262)
	do
		local viewport = create("ViewportFrame", {
			Size = UDim2.new(0, 270, 0, 238), Position = UDim2.new(0, 12, 0, 12), BackgroundColor3 = Color3.fromRGB(24, 26, 42), BorderSizePixel = 0,
			Ambient = Color3.fromRGB(190, 190, 200), LightColor = Color3.new(1, 1, 1),
		}, header)
		rounded(viewport, 10)
		create("UIStroke", { Color = shown.Rainbow and Color3.fromRGB(255, 120, 255) or shown.Color, Thickness = 2 }, viewport)
		settings.BuildFireDemo(viewport, shown, classInfo)
		makeLabel({ Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -22), Text = isMine and "내 무기 · 발사 시연" or "👀 미리보기 · 발사 시연", TextSize = 11, TextColor3 = Color3.fromRGB(170, 180, 210) }, viewport)
	end

	local SHOT_NAMES = { Ball = "작은 탄환", Bolt = "빛줄기 탄", Orb = "에너지 구체", Cannon = "대형 포탄", Fire = "불꽃 덩이", Rocket = "로켓탄", Rainbow = "무지개 광구" }
	local shotInfo = shown.Shot or { Style = "Ball" }
	local behavior = {}
	if classInfo.Pellets > 1 then table.insert(behavior, string.format("한 번에 %d발이 부채꼴로 퍼짐", classInfo.Pellets)) end
	if classInfo.Splash then table.insert(behavior, string.format("맞은 곳이 폭발 (범위 %d)", classInfo.Splash)) end
	if classInfo.Pierce then table.insert(behavior, string.format("적 %d마리까지 관통", classInfo.Pierce + 1)) end
	if (classInfo.CritBonus or 0) > 0 then table.insert(behavior, string.format("치명타 +%d%%", math.floor(classInfo.CritBonus * 100 + 0.5))) end
	if #behavior == 0 then table.insert(behavior, "곧게 날아가 한 마리를 맞힘") end
	local rate = 1 / math.max(0.05, classInfo.Cooldown * Config.Player.BaseCooldown)
	local status
	if isMine then
		status = string.format("<font color='#ffd966'>+%d / %d</font>  %s", stage, shown.Steps, Config.StageBar(level))
	elseif shown.Index < current.Index then
		status = "<font color='#78ff8c'>✔ 이미 지나온 무기</font>"
	else
		status = string.format("<font color='#ff9a6e'>🔒 +%d 단계부터 (앞으로 %d단계)</font>", shown.MinLevel, math.max(0, shown.MinLevel - level))
	end
	makeLabel({
		Size = UDim2.new(1, -306, 1, -20), Position = UDim2.new(0, 294, 0, 10), RichText = true, TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		Text = string.format(
			"<font size='20'><b><font color='#%s'>[%d/%d] %s</font></b></font>\n%s\n<font color='#bbbbcc'>%s</font>\n\n<b>🔫 공격 방식</b>\n<font color='#dfe6ff'>• 탄 모양: %s\n• %s\n• 초당 약 %.1f발 · 한 발 x%.2f · 사거리 %d</font>\n\n%s",
			hex(shown.Rainbow and Color3.fromRGB(255, 120, 255) or shown.Color), shown.Index, #tiers, shown.Name, status, classInfo.Desc,
			SHOT_NAMES[shotInfo.Style] or "탄환", table.concat(behavior, " · "),
			rate, classInfo.DamageMult, Config.GetTierRange(shown),
			nextTier and string.format("<font color='#9ad7ff'>다음 진화 → %s\n(%s)</font>", nextTier.Name, Config.WeaponTypes[nextTier.Class].Desc) or "<font color='#ffd966'>마지막 무기예요!</font>"
		),
	}, header)

	for _, tier in ipairs(tiers) do
		local owned = tier.Index < current.Index
		local isCurrent = tier.Index == current.Index
		local row = newRow(34, isCurrent and Color3.fromRGB(45, 70, 50) or (owned and Color3.fromRGB(34, 38, 48) or Color3.fromRGB(28, 28, 38)))
		local classOf = Config.WeaponTypes[tier.Class]
		local mark = isCurrent and "▶" or (owned and "✔" or "🔒")
		local nameColor = (owned or isCurrent) and hex(tier.Color) or "777788"
		rowText(row, string.format("%s  <font color='#aaaabb'>%d.</font> <font color='#%s'><b>%s</b></font>   <font size='12' color='#8888aa'>%s · +%d 단계부터</font>",
			mark, tier.Index, nameColor, tier.Name, classOf.Name, tier.MinLevel), 14, 24)
		if (settings.PreviewTier or current.Index) == tier.Index then
			create("UIStroke", { Color = Color3.fromRGB(255, 225, 120), Thickness = 2 }, row)
		end
		local pick = create("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 5 }, row)
		pick.Activated:Connect(function()
			settings.PreviewTier = tier.Index
			settings.DemoClock = 0
			settings.RefreshMenu()
		end)
	end
end

local function buildProgressRows(entries, remoteAction, showTitle)
	if not entries then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>불러오는 중...</font>")
		return
	end
	for _, entry in ipairs(entries) do
		local done = entry.Progress >= entry.Goal
		local row = newRow(66, entry.Claimed and Color3.fromRGB(32, 38, 36) or Color3.fromRGB(40, 40, 58))
		local titleText = showTitle and entry.Title and string.format("   <font color='#9ad7ff'>칭호 『%s』</font>", entry.Title) or ""
		rowText(row, string.format(
			"<font size='16'><b>%s</b></font>%s\n<font color='#bbbbcc'>%s</font>\n<font color='#%s'>%d / %d</font>   <font color='#ffd966'>보상 %s</font>",
			entry.Name, titleText, entry.Desc, done and "78ff8c" or "ffffff", entry.Progress, entry.Goal, entry.Reward
		), 14, 160)

		local label, color, enabled
		if entry.Claimed then
			label, color = "완료", GRAY
		elseif done then
			label, color, enabled = "보상 받기", GREEN, true
		else
			label, color = "진행 중", GRAY
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
	sectionTitle("🏆 전투력 랭킹 TOP 10 (화면 오른쪽 작은 랭킹과 같아요)")
	if #rankList == 0 then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>집계 중이에요...</font>")
	end
	for index, entry in ipairs(rankList) do
		local row = newRow(36, entry.Name == player.DisplayName and Color3.fromRGB(60, 52, 28) or nil)
		local medal = index == 1 and "🥇" or index == 2 and "🥈" or index == 3 and "🥉" or string.format("%d.", index)
		rowText(row, string.format("%s  <b>%s</b>   ⚡ %d", medal, entry.Name, entry.Power), 16)
	end
end

local refreshMenu -- (메뉴 다시 그리기: 아래에서 정의)
local inventoryState = nil   -- 가방 (서버가 보내준 아이템 목록)
local growthState = nil      -- 훈련소 / 돌파 상태
local growthReceivedAt = 0   -- growthState 를 받은 시각(os.clock) - 남은 시간 계산용

local SLOT_NAMES = {}
for _, slot in ipairs(Config.Gear.Slots) do
	SLOT_NAMES[slot.Key] = slot.Name
end

local function buildInventoryTab()
	local state = inventoryState
	if not state then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>가방을 불러오는 중...</font>")
		return
	end

	local header = newRow(92)
	local headerText = rowText(header, string.format(
		"🎒 가방 <b>%d / %d</b>      ✨ 에센스 <font color='#9ad7ff'>%d</font>\n<font size='13' color='#bbbbcc'>칸을 누르면 자세히 보여요. 자동 분해를 켜 두면 낮은 등급은 줍자마자 분해돼요.</font>",
		state.BagCount, state.Capacity, state.Essence
	), 15, 24)
	headerText.Size = UDim2.new(1, -24, 0, 50)
	headerText.TextYAlignment = Enum.TextYAlignment.Top
	makeButton({
		Size = UDim2.new(0, 150, 0, 28), Position = UDim2.new(1, -318, 0, 56),
		Text = "자동 분해: " .. Config.Inventory.AutoScrapNames[state.AutoScrap], TextSize = 13, BackgroundColor3 = Color3.fromRGB(70, 110, 220),
	}, header, function()
		Remotes.Inventory:FireServer("AutoScrap", (state.AutoScrap + 1) % 4)
	end)
	makeButton({
		Size = UDim2.new(0, 150, 0, 28), Position = UDim2.new(1, -474, 0, 56),
		Text = "⚡ 최고 장비 자동 장착", TextSize = 13, BackgroundColor3 = GREEN,
	}, header, function()
		Remotes.Inventory:FireServer("AutoEquip")
	end)
	makeButton({
		Size = UDim2.new(0, 150, 0, 28), Position = UDim2.new(1, -162, 0, 56),
		Text = "희귀 이하 일괄 분해", TextSize = 13, BackgroundColor3 = RED,
	}, header, function()
		Remotes.Inventory:FireServer("ScrapBelow", 2)
	end)

	local equipped, bag, setCounts, byId = {}, {}, {}, {}
	for _, item in ipairs(state.Items) do
		byId[item.Id] = item
		if item.Equipped then
			equipped[item.Slot] = item
			if item.Set then
				setCounts[item.Set] = (setCounts[item.Set] or 0) + 1
			end
		else
			table.insert(bag, item)
		end
	end
	local selectedId = menuContent:GetAttribute("SelectedItem")
	local selected = selectedId and byId[selectedId]
	if not selected then
		selected = equipped.Armor or equipped.Helmet or equipped.Gloves or equipped.Boots or equipped.Ring or equipped.Necklace or bag[1]
	end

	local function rarityOutline(frame, rarity, thick)
		local color = Config.Gear.RarityColors[rarity]
		local stroke = create("UIStroke", { Color = color, Thickness = thick or ({ 2, 2, 3, 3.5, 4.5 })[rarity], ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
		if rarity >= 3 then
			TweenService:Create(stroke, TweenInfo.new(rarity >= 4 and 0.9 or 1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = rarity >= 4 and 0.55 or 0.4 }):Play()
		end
		if rarity >= 5 then
			local gradient = create("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 220, 80)),
					ColorSequenceKeypoint.new(0.4, Color3.fromRGB(90, 255, 120)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(80, 220, 255)),
					ColorSequenceKeypoint.new(0.8, Color3.fromRGB(150, 100, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80)),
				}),
			}, stroke)
			TweenService:Create(gradient, TweenInfo.new(2.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 }):Play()
		end
		return stroke
	end

	local function setPips(count)
		return string.rep("●", math.min(count, 3)) .. string.rep("○", math.max(0, 3 - count))
	end
	-- 세트 장비 표시: 세트색 배경 틴트 + 안쪽 테두리 + 구역 리본 (2부위 이상 맞추면 더 밝고 숨 쉬듯 빛남)
	local function setDecor(tile, setKey, pieces, ribbonPos, ribbonSize, radius)
		local def = setKey and Config.Sets[setKey]
		if not def then return end
		local active = (pieces or 0) >= 2
		local tint = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = def.Color, BorderSizePixel = 0, ZIndex = 0, Active = false }, tile)
		rounded(tint, radius or 8)
		create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, active and 0.4 or 0.62), NumberSequenceKeypoint.new(1, active and 0.8 or 0.92) }) }, tint)
		local inner = create("Frame", { Size = UDim2.new(1, -6, 1, -6), Position = UDim2.new(0, 3, 0, 3), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2, Active = false }, tile)
		rounded(inner, (radius or 8) - 2)
		local stroke = create("UIStroke", { Color = def.Color, Thickness = active and 2 or 1.5, Transparency = active and 0 or 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, inner)
		if active then
			TweenService:Create(stroke, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.6 }):Play()
		end
		local pill = create("Frame", { Size = ribbonSize, Position = ribbonPos, BackgroundColor3 = def.Color, BorderSizePixel = 0, ZIndex = 3, Active = false }, tile)
		rounded(pill, 6)
		makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = def.Zone and (def.Zone .. "구역") or "세트", TextSize = 12, TextColor3 = Color3.fromRGB(20, 20, 30), Font = Enum.Font.GothamBlack, TextWrapped = false, ZIndex = 4 }, pill)
	end

	local SLOT_ICONS = { Armor = "🛡", Gloves = "🧤", Boots = "👢", Weapon = "🔫", Helmet = "⛑", Ring = "💍", Necklace = "📿" }

	local top = newRow(500, Color3.fromRGB(30, 32, 46))

	local viewport = create("ViewportFrame", {
		Size = UDim2.new(0, 230, 0, 330), Position = UDim2.new(0, 108, 0, 12), BackgroundColor3 = Color3.fromRGB(20, 22, 34), BorderSizePixel = 0,
		Ambient = Color3.fromRGB(190, 190, 200), LightColor = Color3.new(1, 1, 1),
	}, top)
	rounded(viewport, 10)
	create("UIStroke", { Color = Color3.fromRGB(90, 110, 170), Thickness = 2 }, viewport)
	local cam = create("Camera", { FieldOfView = 38 }, viewport)
	viewport.CurrentCamera = cam
	local character = player.Character
	if character then
		character.Archivable = true
		local clone = character:Clone()
		for _, descendant in ipairs(clone:GetDescendants()) do
			if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("BillboardGui") or descendant:IsA("ForceField") then
				descendant:Destroy()
			elseif descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end
		clone.Parent = viewport
		local pivot = clone:GetPivot()
		local spin = settings.InvSpin or 0 -- 메뉴가 갱신돼 다시 그려져도 회전 각도를 이어간다
		local connection
		connection = RunService.RenderStepped:Connect(function(dt)
			if not viewport:IsDescendantOf(game) then
				connection:Disconnect()
				return
			end
			spin += dt * 0.9
			settings.InvSpin = spin
			clone:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(0, spin, 0))
			cam.CFrame = CFrame.lookAt(pivot.Position + Vector3.new(0, 1.2, 12.5), pivot.Position + Vector3.new(0, 0.4, 0))
		end)
	end
	makeLabel({ Size = UDim2.new(0, 230, 0, 22), Position = UDim2.new(0, 108, 0, 350), Text = string.format("⚡ 전투력 %d", player:GetAttribute("Power") or 0), TextSize = 16, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 225, 110) }, top)

	do
		local rowsShown = 0
		for _, key in ipairs(Config.Sets.ZoneKeys) do
			local count = setCounts[key] or 0
			if count >= 2 then
				local def = Config.Sets[key]
				local bar = create("Frame", { Size = UDim2.new(0, 230, 0, 26), Position = UDim2.new(0, 108, 0, 378 + rowsShown * 30), BackgroundColor3 = def.Color, BorderSizePixel = 0 }, top)
				rounded(bar, 8)
				create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0.9) }) }, bar)
				local glow = create("UIStroke", { Color = def.Color, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, bar)
				TweenService:Create(glow, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.6 }):Play()
				makeLabel({
					Size = UDim2.new(1, -10, 1, 0), Position = UDim2.new(0, 5, 0, 0), RichText = true, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
					Text = string.format("%s <b>%s</b>  <font color='#%s'>%s</font> %d/3", def.Icon, def.Name, hex(def.Color), setPips(count), count),
				}, bar)
				rowsShown += 1
			end
		end
		if rowsShown == 0 then
			makeLabel({ Size = UDim2.new(0, 230, 0, 30), Position = UDim2.new(0, 108, 0, 378), Text = "같은 세트 2부위↑ 착용 시 세트 효과 발동", TextSize = 12, TextWrapped = true, TextColor3 = Color3.fromRGB(120, 124, 150) }, top)
		end
	end
	local function slotBox(slotKey, x, y)
		local item = equipped[slotKey]
		local rarity = item and item.Rarity or 0
		local box = makeButton({
			Size = UDim2.new(0, 88, 0, 88), Position = UDim2.new(0, x, 0, y), Text = "",
			BackgroundColor3 = item and Color3.fromRGB(46, 48, 68) or Color3.fromRGB(34, 34, 48), AutoButtonColor = true,
		}, top, function()
			if item then
				menuContent:SetAttribute("SelectedItem", item.Id)
				refreshMenu()
			end
		end)
		rounded(box, 10)
		if slotKey == "Weapon" then
			local tier = Config.GetWeaponTier(player:GetAttribute("WeaponLevel") or 0)
			rarityOutline(box, 4, 3.5).Color = tier.Color
			makeLabel({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 6), Text = "🔫", TextSize = 32 }, box)
			makeLabel({ Size = UDim2.new(1, -6, 0, 36), Position = UDim2.new(0, 3, 0, 46), Text = tier.Name, TextSize = 12, TextWrapped = true, TextColor3 = tier.Color, Font = Enum.Font.GothamBold }, box)
		elseif item then
			rarityOutline(box, rarity)
			setDecor(box, item.Set, setCounts[item.Set], UDim2.new(0, 4, 0, 4), UDim2.new(0, 44, 0, 16), 10)
			makeLabel({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 4), Text = SLOT_ICONS[slotKey], TextSize = 32 }, box)
			makeLabel({ Size = UDim2.new(1, -6, 0, 16), Position = UDim2.new(0, 3, 0, 44), Text = Config.ItemDisplayName(item), TextSize = 11, TextWrapped = true, TextColor3 = Config.Gear.RarityColors[rarity], Font = Enum.Font.GothamBold }, box)
			makeLabel({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, 64), Text = string.format("+%d", item.Level), TextSize = 13, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack }, box)
			if item.Unique then
				makeLabel({ Size = UDim2.new(0, 16, 0, 16), Position = UDim2.new(1, -18, 0, 2), Text = "✦", TextSize = 14, TextColor3 = Color3.fromRGB(255, 184, 77) }, box)
			end
		else
			create("UIStroke", { Color = Color3.fromRGB(70, 70, 90), Thickness = 1.5 }, box)
			makeLabel({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 10), Text = SLOT_ICONS[slotKey], TextSize = 30, TextTransparency = 0.6 }, box)
			makeLabel({ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, 56), Text = "비어 있음", TextSize = 12, TextColor3 = Color3.fromRGB(120, 120, 140) }, box)
		end
		return box
	end
	slotBox("Helmet", 10, 12)
	slotBox("Armor", 10, 108)
	slotBox("Gloves", 10, 204)
	slotBox("Necklace", 350, 12)
	slotBox("Ring", 350, 108)
	slotBox("Boots", 350, 204)
	slotBox("Weapon", 350, 300)
	do -- 펫 칸: 펫 레벨 / 외형을 한눈에 (누르면 펫 창)
		local petLevel = player:GetAttribute("PetLevel") or 0
		local look = Config.Pet.Looks[player:GetAttribute("PetLook") or "Orb"] or Config.Pet.Looks.Orb
		local box = makeButton({ Size = UDim2.new(0, 88, 0, 88), Position = UDim2.new(0, 10, 0, 300), Text = "", BackgroundColor3 = petLevel > 0 and Color3.fromRGB(46, 48, 68) or Color3.fromRGB(34, 34, 48), AutoButtonColor = true }, top, function()
			player:SetAttribute("OpenPet", os.clock())
		end)
		rounded(box, 10)
		if petLevel > 0 then
			create("UIStroke", { Color = Color3.fromRGB(255, 200, 90), Thickness = 2.5 }, box)
			makeLabel({ Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 4), Text = look.Icon, TextSize = 30 }, box)
			local nextFn
			for _, fn in ipairs(Config.Pet.Functions) do
				if fn.Level > petLevel then nextFn = fn break end
			end
			makeLabel({ Size = UDim2.new(1, -6, 0, 16), Position = UDim2.new(0, 3, 0, 42), Text = nextFn and string.format("▶ %s Lv.%d", nextFn.Icon, nextFn.Level) or "최대!", TextSize = 11, TextWrapped = true, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(190, 220, 255) }, box) -- 다음에 열리는 펫 기능
			makeLabel({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, 62), Text = string.format("Lv.%d", petLevel), TextSize = 13, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 225, 110) }, box)
		else
			create("UIStroke", { Color = Color3.fromRGB(70, 70, 90), Thickness = 1.5 }, box)
			makeLabel({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 8), Text = "🐾", TextSize = 30, TextTransparency = 0.6 }, box)
			makeLabel({ Size = UDim2.new(1, -4, 0, 30), Position = UDim2.new(0, 2, 0, 52), Text = "펫 기능\n열기 (P)", TextSize = 11, TextWrapped = true, TextColor3 = Color3.fromRGB(150, 150, 175) }, box)
		end
	end
	local detail = create("Frame", { Size = UDim2.new(1, -462, 1, -24), Position = UDim2.new(0, 450, 0, 12), BackgroundColor3 = Color3.fromRGB(24, 26, 38), BorderSizePixel = 0 }, top)
	rounded(detail, 10)
	if selected then
		local color = Config.Gear.RarityColors[selected.Rarity]
		rarityOutline(detail, selected.Rarity)
		local slot = Config.GetGearSlot(selected.Slot)
		local lines = {
			string.format("<font color='#%s' size='18'><b>[%s] %s</b></font>  +%d", hex(color), Config.Gear.RarityNames[selected.Rarity], Config.ItemDisplayName(selected), selected.Level),
			string.format("<font color='#aaaacc' size='12'>%s · 점수 %d%s</font>", slot.Name, selected.Score, selected.Equipped and " · 장착 중" or ""),
			"<font size='13' color='#ddddee'>기본  " .. Config.FormatGearStat(selected.Slot, Config.GetGearStat(selected.Slot, selected.Rarity, selected.Level)) .. "</font>"
				.. (Config.StatDesc[slot.Stat] and ("\n<font size='11' color='#8a8aa8'>   → " .. Config.StatDesc[slot.Stat].Desc .. "</font>") or ""),
		}
		for _, affix in ipairs(selected.Affixes) do
			local info = Config.StatDesc[affix.Stat]
			table.insert(lines, "<font size='13' color='#9ad7ff'>◆ " .. Config.FormatAffix(affix.Stat, affix.Value) .. "</font>"
				.. (info and ("\n<font size='11' color='#8a8aa8'>   → " .. info.Desc .. "</font>") or ""))
		end
		if selected.Unique and Config.Uniques[selected.Unique] then
			table.insert(lines, "<font size='13' color='#ffb84d'>✦ 유니크: " .. Config.Uniques[selected.Unique].Desc .. "</font>")
		end
		if selected.Set and Config.Sets[selected.Set] then
			local setDef = Config.Sets[selected.Set]
			local have = setCounts[selected.Set] or 0
			local lit, dim = "#" .. hex(setDef.Color), "#6c7088"
			if setDef.Zone then
				table.insert(lines, string.format("<font size='12' color='%s'>📍 %d구역 %s · 그 구역 드랍 / 세트 각인</font>", lit, setDef.Zone, Config.Field.ZoneNames[setDef.Zone]))
			end
			for _, tier in ipairs({ 2, 3 }) do
				local parts = {}
				for _, b in ipairs(setDef.Bonuses[tier]) do table.insert(parts, Config.FormatBonus(b.Stat, b.Value)) end
				local on = have >= tier
				table.insert(lines, string.format("<font size='12' color='%s'>%s <b>%d부위</b>  %s</font>", on and lit or dim, on and "✔" or "○", tier, table.concat(parts, ", ")))
			end
			local augInfo = setDef.Aug and Config.AugInfo[setDef.Aug]
			if augInfo then
				local lv = have >= 3 and Config.Sets.AugLevelByPieces[3] or (have >= 2 and Config.Sets.AugLevelByPieces[2] or 0)
				local ac = lv > 0 and ("#" .. hex(augInfo.Color)) or dim
				table.insert(lines, string.format("<font size='12' color='%s'><b>%s %s</b> %s</font>\n  <font color='%s'>%s</font>", ac, augInfo.Icon, augInfo.Name, lv > 0 and ("✔ " .. lv .. "단계") or "○ 2부위 1단계 · 3부위 3단계", lv > 0 and "#cfd6f0" or dim, augInfo.Desc))
			end
		end
		local current = equipped[selected.Slot]
		if current and current.Id ~= selected.Id then
			local diff = selected.Score - current.Score
			table.insert(lines, diff >= 0 and string.format("<font color='#78ff8c'>장착 중인 것보다 ▲ +%d</font>", diff) or string.format("<font color='#ff8c8c'>장착 중인 것보다 ▼ %d</font>", diff))
		end
		local bandH = 0
		if selected.Set and Config.Sets[selected.Set] then
			local setDef = Config.Sets[selected.Set]
			local have = setCounts[selected.Set] or 0
			bandH = 32
			local band = create("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = setDef.Color, BorderSizePixel = 0 }, detail)
			rounded(band, 10)
			create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.85) }) }, band)
			makeLabel({
				Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 10, 0, 0), RichText = true, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
				Text = string.format("%s <b>%s 세트</b>   %s %d/3 <font size='11'>착용</font>", setDef.Icon, setDef.Name, setPips(have), have),
			}, band)
		end
		makeLabel({
			Size = UDim2.new(1, -20, 1, -172 - bandH), Position = UDim2.new(0, 10, 0, 8 + bandH), Text = table.concat(lines, "\n"), TextSize = 14, RichText = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		}, detail)
		do
			local cost = Config.Sets.Imprint.Cost[selected.Rarity]
			local zoneCount = Config.Field.ZoneCount
			local strip = create("Frame", { Size = UDim2.new(1, -20, 0, 98), Position = UDim2.new(0, 10, 1, -146), BackgroundColor3 = Color3.fromRGB(30, 34, 52), BorderSizePixel = 0 }, detail)
			rounded(strip, 8)
			makeLabel({
				Size = UDim2.new(1, -12, 0, 18), Position = UDim2.new(0, 8, 0, 3), TextXAlignment = Enum.TextXAlignment.Left, RichText = true, TextSize = 12,
				Text = string.format("<font color='#9fdcff'><b>🔹 세트 각인</b></font>  <font color='#aab0c8'>구역 조각 %d개로 이 장비를 세트 장비로 (등급·강화·옵션 유지)</font>", cost),
			}, strip)
			for zone = 1, zoneCount do
				local setDef = Config.Sets[Config.Sets.ZoneKeys[zone]]
				local have = state.Shards and state.Shards[zone] or 0
				local already = selected.Set == Config.Sets.ZoneKeys[zone]
				local enough = have >= cost and not already
				local button = makeButton({
					Size = UDim2.new(1 / zoneCount, -4, 0, 70), Position = UDim2.new((zone - 1) / zoneCount, 2, 0, 24), Text = "",
					BackgroundColor3 = enough and Color3.fromRGB(46, 70, 100) or Color3.fromRGB(36, 38, 54), AutoButtonColor = enough,
				}, strip, function()
					if enough then
						Remotes.Inventory:FireServer("Imprint", selected.Id, zone)
					elseif already then
						toast("이미 그 세트예요.")
					else
						toast(string.format("%s 구역 세트 조각이 부족해요 (%d / %d) — 그 구역 몬스터에게서 얻어요", Config.Field.ZoneNames[zone], have, cost))
					end
				end)
				rounded(button, 6)
				create("UIStroke", { Color = setDef.Color, Thickness = enough and 2.5 or 1, Transparency = enough and 0 or 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
				makeLabel({ Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0, 3), Text = setDef.Icon, TextSize = 20 }, button)
				makeLabel({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 27), Text = tostring(zone) .. "구역", TextSize = 10, TextColor3 = setDef.Color, Font = Enum.Font.GothamBold }, button)
				makeLabel({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 41), Text = string.format("%d/%d", have, cost), TextSize = 11, Font = Enum.Font.GothamBlack, TextColor3 = enough and Color3.fromRGB(120, 255, 150) or Color3.fromRGB(170, 170, 190) }, button)
				makeLabel({ Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, 56), Text = already and "착용" or (enough and "각인!" or ""), TextSize = 10, TextColor3 = Color3.fromRGB(255, 225, 110), Font = Enum.Font.GothamBold }, button)
			end
		end
		if not selected.Equipped then
			makeButton({ Size = UDim2.new(0, 96, 0, 30), Position = UDim2.new(0, 10, 1, -40), Text = "장착", TextSize = 14, BackgroundColor3 = GREEN }, detail, function()
				Remotes.Inventory:FireServer("Equip", selected.Id)
			end)
			makeButton({ Size = UDim2.new(0, 96, 0, 30), Position = UDim2.new(0, 112, 1, -40), Text = "분해", TextSize = 14, BackgroundColor3 = RED }, detail, function()
				Remotes.Inventory:FireServer("Scrap", selected.Id)
			end)
		end
		if #selected.Affixes > 0 then
			makeButton({
				Size = UDim2.new(0, 120, 0, 30), Position = UDim2.new(1, -130, 1, -40),
				Text = string.format("재굴림 ✨%d", Config.Inventory.RerollEssence[selected.Rarity]), TextSize = 12, BackgroundColor3 = Color3.fromRGB(70, 110, 220),
			}, detail, function()
				Remotes.Inventory:FireServer("Reroll", selected.Id)
			end)
		end
	else
		makeLabel({ Size = UDim2.new(1, -20, 1, -20), Position = UDim2.new(0, 10, 0, 10), Text = "장비가 없어요.\n필드에서 몬스터를 잡거나 뽑기로 얻어보세요!", TextSize = 15, TextColor3 = Color3.fromRGB(150, 150, 170) }, detail)
	end

	sectionTitle(string.format("🎒 가방 (%d / %d) — 칸을 누르면 위에 자세히 나와요", state.BagCount, state.Capacity))
	local columns = 10
	local rowsNeeded = math.max(1, math.ceil(#bag / columns))
	local gridRow = newRow(rowsNeeded * 76 + 14)
	if #bag == 0 then
		makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = "가방이 비어 있어요", TextSize = 15, TextColor3 = Color3.fromRGB(130, 130, 150) }, gridRow)
	end
	create("UIGridLayout", { CellSize = UDim2.new(0, 68, 0, 68), CellPadding = UDim2.new(0, 8, 0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, gridRow)
	create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10) }, gridRow)
	for order, item in ipairs(bag) do
		local tile = makeButton({
			Text = "", LayoutOrder = order,
			BackgroundColor3 = (selected and selected.Id == item.Id) and Color3.fromRGB(70, 74, 104) or Color3.fromRGB(42, 44, 62), AutoButtonColor = true,
		}, gridRow, function()
			menuContent:SetAttribute("SelectedItem", item.Id)
			refreshMenu()
		end)
		rounded(tile, 8)
		rarityOutline(tile, item.Rarity, (selected and selected.Id == item.Id) and 5 or nil)
		makeLabel({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 4), Text = SLOT_ICONS[item.Slot], TextSize = 26 }, tile)
		makeLabel({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 36), Text = string.format("+%d", item.Level), TextSize = 12, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack }, tile)
		local equippedItem = equipped[item.Slot]
		local compare = ""
		if equippedItem then
			compare = item.Score > equippedItem.Score and "▲" or (item.Score < equippedItem.Score and "▼" or "")
		else
			compare = "▲"
		end
		if compare ~= "" then
			makeLabel({ Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(1, -16, 0, 3), Text = compare, TextSize = 12, TextColor3 = compare == "▲" and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 120, 120), Font = Enum.Font.GothamBlack }, tile)
		end
		if item.Unique then
			makeLabel({ Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(0, 2, 0, 3), Text = "✦", TextSize = 12, TextColor3 = Color3.fromRGB(255, 184, 77) }, tile)
		end
		if item.Set then
			setDecor(tile, item.Set, setCounts[item.Set], UDim2.new(0, 5, 1, -17), UDim2.new(1, -10, 0, 14), 8)
		end
	end
end

local function growthRemaining(endAt)
	return endAt - (growthState.ServerTime + (os.clock() - growthReceivedAt))
end

local function buildGrowthTab()
	local state = growthState
	if not state then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>불러오는 중...</font>")
		return
	end

	local header = newRow(78)
	rowText(header, string.format(
		"⏱ 시간 단축권 <font color='#ffe16e'><b>%s</b></font> 보유      🏋 훈련 슬롯 <b>%d / %d</b> 사용 중\n<font size='13' color='#bbbbcc'>훈련과 돌파는 시간이 지나면 저절로 끝나요 (접속하지 않아도 흘러요). 시간 단축권으로 기다리는 시간을 줄일 수 있고, 퀘스트로도 조금씩 얻어요. 돈을 쓰지 않아도 모두 도달할 수 있어요.</font>",
		Config.FormatDuration(state.TimeSkip), #state.Jobs, state.Slots
	), 15, 24)

	sectionTitle("🏋 훈련소 — 영구적으로 강해져요")
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
		local nextText = level < Config.Growth.MaxLevel and ("  →  " .. Config.FormatTrainEffect(stat, level + 1)) or "  (최대)"
		local status
		if job then
			status = string.format("<font color='#ffd966'>훈련 중 · 남은 시간 %s</font>", Config.FormatDuration(growthRemaining(job.EndAt)))
		elseif level >= Config.Growth.MaxLevel then
			status = "<font color='#78ff8c'>최대 단계!</font>"
		else
			status = string.format("<font color='#bbbbcc'>필요 시간 %s · 💰 %d G</font>", Config.FormatDuration(Config.GetTrainTime(level)), Config.GetTrainGold(level))
		end

		local row = newRow(84)
		rowText(row, string.format("<font size='17'><b>%s %s</b></font>  Lv.%d / %d\n<font color='#ddddee'>%s%s</font>\n%s",
			def.Icon, def.Name, level, Config.Growth.MaxLevel, current, nextText, status), 14, 190)

		if job then
			makeButton({
				Size = UDim2.new(0, 160, 0, 34), Position = UDim2.new(1, -172, 0.5, -17),
				Text = "⏱ 단축권 사용", TextSize = 14, BackgroundColor3 = state.TimeSkip > 0 and Color3.fromRGB(200, 130, 40) or GRAY,
			}, row, function()
				Remotes.Growth:FireServer("Skip", "Train", stat)
			end)
		elseif level < Config.Growth.MaxLevel then
			makeButton({
				Size = UDim2.new(0, 160, 0, 34), Position = UDim2.new(1, -172, 0.5, -17),
				Text = "훈련 시작", TextSize = 15, BackgroundColor3 = GREEN,
			}, row, function()
				Remotes.Growth:FireServer("Train", stat)
			end)
		end
	end

	sectionTitle("🚧 돌파 — 레벨이 막히는 구간을 넘어요")
	local gateIndex
	for index, gate in ipairs(Config.Growth.Gates) do
		if gate > state.GatePassed then
			gateIndex = index
			break
		end
	end

	local gateRow = newRow(92)
	if not gateIndex then
		rowText(gateRow, "<font color='#78ff8c'>모든 돌파를 마쳤어요! 최대 레벨까지 자유롭게 성장할 수 있어요.</font>")
	else
		local gateLevel = Config.Growth.Gates[gateIndex]
		local myLevel = player:GetAttribute("Level") or 1
		local text
		if state.GateJob then
			text = string.format("<font size='17'><b>레벨 %d 돌파 중</b></font>\n<font color='#ffd966'>남은 시간 %s</font>", state.GateJob.Level, Config.FormatDuration(growthRemaining(state.GateJob.EndAt)))
		else
			text = string.format("<font size='17'><b>레벨 %d 돌파</b></font>   (현재 Lv.%d)\n<font color='#bbbbcc'>필요 시간 %s · 💰 %d G</font>\n<font size='13' color='#bbbbcc'>%s</font>",
				gateLevel, myLevel, Config.FormatDuration(Config.Growth.GateTime[gateIndex]), Config.Growth.GateGold[gateIndex],
				myLevel >= gateLevel and "지금 돌파할 수 있어요!" or string.format("레벨 %d 에 도달하면 돌파할 수 있어요", gateLevel))
		end
		rowText(gateRow, text, 14, 190)

		if state.GateJob then
			makeButton({
				Size = UDim2.new(0, 160, 0, 34), Position = UDim2.new(1, -172, 0.5, -17),
				Text = "⏱ 단축권 사용", TextSize = 14, BackgroundColor3 = state.TimeSkip > 0 and Color3.fromRGB(200, 130, 40) or GRAY,
			}, gateRow, function()
				Remotes.Growth:FireServer("Skip", "Gate")
			end)
		else
			makeButton({
				Size = UDim2.new(0, 160, 0, 34), Position = UDim2.new(1, -172, 0.5, -17),
				Text = "돌파 시작", TextSize = 15, BackgroundColor3 = myLevel >= gateLevel and GREEN or GRAY,
			}, gateRow, function()
				Remotes.Growth:FireServer("Gate")
			end)
		end
	end
end

local function auraUnlockText(aura)
	local unlock = aura.Unlock
	if unlock == "Free" then return "기본 제공" end
	if unlock.Ach then
		for _, achievement in ipairs(Config.Achievements) do
			if achievement.Id == unlock.Ach then
				return "업적 달성: " .. achievement.Name
			end
		end
	end
	if unlock.Pass then return Config.Shop.Passes[unlock.Pass].Name .. " 전용" end
	if unlock.Product then return "상점 상품: " .. Config.Shop.Products[unlock.Product].Name end
	return ""
end

local function shopButtonLabel(id)
	if id > 0 then return "구매", GREEN end
	if RunService:IsStudio() then return "테스트 지급", Color3.fromRGB(200, 130, 40) end
	return "준비 중", GRAY
end

local function buildShopTab()
	local note = newRow(52)
	rowText(note, "<font size='13' color='#bbbbcc'>상점은 <b>시간을 줄여주는 것</b>과 편의, 꾸미기를 팔아요. 돈을 쓰지 않아도 모든 성장에 도달할 수 있고, 장비는 필드에서 직접 얻어야 해요.</font>", 13)

	sectionTitle("⭐ 패스")
	for _, key in ipairs(Config.Shop.PassOrder) do
		local def = Config.Shop.Passes[key]
		local owned = key == "VIP" and player:GetAttribute("Vip") == true
		local row = newRow(76)
		rowText(row, string.format("<font size='17'><b>%s</b></font>\n<font size='13' color='#bbbbcc'>%s</font>", def.Name, def.Desc), 14, 170)
		local label, color = shopButtonLabel(def.PassId)
		makeButton({
			Size = UDim2.new(0, 130, 0, 34), Position = UDim2.new(1, -142, 0.5, -17),
			Text = owned and "보유 중" or label, TextSize = 14, BackgroundColor3 = owned and GRAY or color,
		}, row, function()
			if not owned then
				Remotes.Shop:FireServer("Buy", "Pass", key)
			end
		end)
	end

	sectionTitle("🛍 상품")
	local now = os.time()
	for _, key in ipairs(Config.Shop.ProductOrder) do
		local def = Config.Shop.Products[key]
		local extra = ""
		if def.Grant.XpBoost and (player:GetAttribute("XpBoostUntil") or 0) > now then
			extra = string.format("  <font color='#78ff8c'>적용 중 %s</font>", Config.FormatDuration(player:GetAttribute("XpBoostUntil") - now))
		elseif def.Grant.LuckBoost and (player:GetAttribute("LuckBoostUntil") or 0) > now then
			extra = string.format("  <font color='#78ff8c'>적용 중 %s</font>", Config.FormatDuration(player:GetAttribute("LuckBoostUntil") - now))
		end
		local row = newRow(66)
		rowText(row, string.format("<font size='16'><b>%s</b></font>%s\n<font size='13' color='#bbbbcc'>%s</font>", def.Name, extra, def.Desc), 14, 170)
		local label, color = shopButtonLabel(def.ProductId)
		makeButton({
			Size = UDim2.new(0, 130, 0, 32), Position = UDim2.new(1, -142, 0.5, -16), Text = label, TextSize = 14, BackgroundColor3 = color,
		}, row, function()
			Remotes.Shop:FireServer("Buy", "Product", key)
		end)
	end

	local Cosmetics = require(game:GetService("ReplicatedStorage"):WaitForChild("Cosmetics"))
	local function previewCosmetic(kind, key, name)
		local character = player.Character
		if not character then return end
		settings.PreviewToken = (settings.PreviewToken or 0) + 1
		local token = settings.PreviewToken
		local panel = settings.MenuPanel
		if panel then panel.Visible = false end
		Cosmetics.Clear(character, kind)
		Cosmetics.Build(kind, key, character, true)
		toast(string.format("👀 [%s] 미리보기 5초!", name))
		task.delay(5, function()
			if settings.PreviewToken ~= token then return end
			Cosmetics.Clear(character, kind, true)
			local equipped = player:GetAttribute(kind) or ""
			if equipped ~= "" and Config[kind == "Aura" and "Auras" or (kind == "Banner" and "Banners" or "Mounts")][equipped] then
				Cosmetics.Build(kind, equipped, character)
			end
			if panel then panel.Visible = true end
		end)
	end
	local function cosmeticSection(title, kind, tableName)
		sectionTitle(title)
		local list = Config[tableName]
		local current = player:GetAttribute(kind) or ""
		for _, key in ipairs(list.Order) do
			local item = list[key]
			local owned = player:GetAttribute(kind .. "Owned_" .. key) == true
			local row = newRow(60)
			rowText(row, string.format("<font color='#%s' size='16'><b>%s</b></font>\n<font size='13' color='#bbbbcc'>%s</font>",
				hex(item.Color), item.Name, owned and "보유 중" or ("🔒 " .. auraUnlockText(item))), 14, 290)
			makeButton({
				Size = UDim2.new(0, 124, 0, 30), Position = UDim2.new(1, -274, 0.5, -15),
				Text = "👀 미리보기", TextSize = 14, BackgroundColor3 = Color3.fromRGB(70, 90, 160),
			}, row, function()
				previewCosmetic(kind, key, item.Name)
			end)
			if owned then
				local equipped = current == key
				makeButton({
					Size = UDim2.new(0, 124, 0, 30), Position = UDim2.new(1, -142, 0.5, -15),
					Text = equipped and "해제" or "장착", TextSize = 14, BackgroundColor3 = equipped and RED or GREEN,
				}, row, function()
					if kind == "Aura" then
						Remotes.Shop:FireServer("Aura", equipped and "" or key)
					else
						Remotes.Shop:FireServer("Cosmetic", kind, equipped and "" or key)
					end
				end)
			end
		end
	end
	cosmeticSection("✨ 오라 (꾸미기 · 능력치 없음 · 다른 플레이어에게도 보여요)", "Aura", "Auras")
	cosmeticSection("🚩 깃발 (등 뒤에 꽂는 꾸미기 · 능력치 없음)", "Banner", "Banners")
	cosmeticSection("🛹 탈것 (발밑에 떠 있는 꾸미기 · 능력치 / 이동속도 없음)", "Mount", "Mounts")
end

local metaState = nil

local function buildSkillTab()
	sectionTitle("⚔ 스킬 강화 — 골드로 레벨업. 레벨이 오를수록 강해지고 쿨타임이 줄어요. (필드/던전에서 C 치료 · V 궁극기)")
	local U = Config.SkillUpgrade
	for _, key in ipairs(Config.Skills.UpgradeOrder) do
		local cfg = Config.Skills[key]
		local level = metaState and metaState.Skills[key] or 1
		local lv = level - 1
		local detail
		if key == "Barrier" then
			detail = string.format("지속 %.1f초", cfg.Duration + U.BarrierDuration * lv)
		elseif key == "Blast" then
			detail = string.format("범위 %.1f · 공격력 x%.2f", cfg.Radius + U.BlastRadius * lv, cfg.Mult * (1 + U.BlastMult * lv))
		elseif key == "Focus" then
			detail = string.format("NEAR MISS 유지 %.1f초", Config.NearMiss.Duration + U.FocusDuration * lv)
		elseif key == "Heal" then
			detail = string.format("체력 %d%% 회복", math.floor((cfg.Ratio + U.HealRatio * lv) * 100 + 0.5))
		else
			detail = string.format("공격력 x%.2f · 대상 %d마리 (게이지 %d)", cfg.Mult * (1 + U.UltMult * lv), cfg.MaxTargets + math.floor(U.UltTargets * lv + 0.001), cfg.Cost)
		end
		local row = newRow(74)
		rowText(row, string.format("<font size='17'><b>[%s] %s %s</b></font>  <font color='#ffd966'>Lv.%d / %d</font>\n<font color='#bbbbcc'>%s</font>\n<font color='#9ad7ff'>%s%s</font>",
			cfg.Key, cfg.Icon, cfg.Name, level, U.MaxLevel, cfg.Desc, detail, cfg.Passive and "" or string.format(" · 쿨타임 %.1f초", cfg.Cooldown * (1 - U.CooldownPerLevel * lv))), 14, 190)
		local maxed = level >= U.MaxLevel
		makeButton({
			Size = UDim2.new(0, 150, 0, 34), Position = UDim2.new(1, -162, 0.5, -17),
			Text = maxed and "MAX" or string.format("강화 %d G", Config.GetSkillUpgradeCost(level)),
			BackgroundColor3 = maxed and GRAY or GREEN,
		}, row, function()
			if not maxed then
				Remotes.Meta:FireServer("SkillUp", key)
			end
		end)
	end
end

local function buildPetTab() -- 펫 창은 따로 있다 (PetClient): 기능 / 레벨업 / 외형 / 색
	local row = newRow(96)
	rowText(row, "🐾 <b>펫</b>: 골드로 펫 기능을 열고, 레벨을 올릴 때마다 새 기능이 생겨요 (자동 루팅 · 공격 속도 · 보조 사격 ...)\n<font color='#bbbbcc' size='13'>외형은 능력과 상관없는 꾸미기예요. 필드 군주를 쓰러뜨리거나 칭호를 따면 새 외형이 열려요.</font>", 14, 210)
	makeButton({ Size = UDim2.new(0, 190, 0, 44), Position = UDim2.new(1, -202, 0.5, -22), Text = "🐾 펫 창 열기 (P)", TextSize = 16, BackgroundColor3 = Color3.fromRGB(200, 130, 40) }, row, function()
		player:SetAttribute("OpenPet", os.clock())
	end)
end

Remotes.Meta.OnClientEvent:Connect(function(action, data)
	if action == "State" then
		metaState = data
		if menuPanel.Visible and (currentTab == "Skill" or currentTab == "Pet") then
			refreshMenu()
		end
	end
end)

function refreshMenu()
	for _, tab in ipairs(TABS) do
		local active = tab.Key == currentTab
		tabButtons[tab.Key].BackgroundColor3 = active and Color3.fromRGB(70, 104, 206) or Color3.fromRGB(34, 38, 58)
		tabButtons[tab.Key].TextColor3 = active and Color3.fromRGB(255, 232, 160) or Color3.fromRGB(170, 176, 200)
		tabButtons[tab.Key].Font = active and Enum.Font.GothamBlack or Enum.Font.GothamBold
	end

	clearChildren(menuContent)
	rowOrder = 0
	if currentTab == "Character" then
		buildCharacterTab()
	elseif currentTab == "Inventory" then
		buildInventoryTab()
	elseif currentTab == "Growth" then
		buildGrowthTab()
	elseif currentTab == "Shop" then
		buildShopTab()
	elseif currentTab == "Weapon" then
		buildWeaponTab()
	elseif currentTab == "Skill" then
		buildSkillTab()
	elseif currentTab == "Pet" then
		buildPetTab()
	elseif currentTab == "Quest" then
		sectionTitle("📅 오늘의 일일 퀘스트 (매일 바뀌어요)")
		buildProgressRows(questState and questState.Daily, "Claim", false)
	elseif currentTab == "Ach" then
		sectionTitle("🏅 업적 — 달성하면 보상과 칭호를 받아요")
		buildProgressRows(questState and questState.Achievements, "ClaimAch", true)
	elseif currentTab == "Rank" then
		buildRankTab()
	end
end
settings.RefreshMenu = refreshMenu
for _, cosmeticKind in ipairs({ "Aura", "Banner", "Mount" }) do
	player:GetAttributeChangedSignal(cosmeticKind):Connect(function()
		if currentTab == "Shop" and menuPanel.Visible then refreshMenu() end
	end)
end

local function selectTab(key)
	currentTab = key
	if key == "Quest" or key == "Ach" or key == "Character" then
		Remotes.Quest:FireServer("Request")
	elseif key == "Rank" then
		Remotes.Rank:FireServer("Request")
	elseif key == "Inventory" then
		Remotes.Inventory:FireServer("Request")
	elseif key == "Growth" then
		Remotes.Growth:FireServer("Request")
	elseif key == "Skill" or key == "Pet" then
		Remotes.Meta:FireServer("Request")
	end
	refreshMenu()
end

for index, tab in ipairs(TABS) do
	tabButtons[tab.Key] = makeButton({
		Size = UDim2.new(0, 80, 0, 36), Position = UDim2.new(0, 14 + (index - 1) * 84, 0, 50), Text = tab.Name, TextSize = 16,
	}, menuPanel, function()
		selectTab(tab.Key)
	end)
end

local function toggleMenu()
	menuPanel.Visible = not menuPanel.Visible
	if menuPanel.Visible then
		selectTab(currentTab)
	end
end

do -- 상태 카드(HudClient)와 같은 어두운 남색 + 은은한 테두리
	local menuButton = makeButton({
		Name = "MenuButton", Size = UDim2.new(0, 78, 0, 32), Position = UDim2.new(0, 16, 0, 244), Text = "📋 메뉴(I)", TextSize = 12,
		BackgroundColor3 = Color3.fromRGB(34, 40, 70),
	}, gui, toggleMenu)
	create("UIStroke", { Color = Color3.fromRGB(110, 130, 220), Thickness = 1.5, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, menuButton)
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
		if menuPanel.Visible and currentTab == "Inventory" then
			refreshMenu()
		end
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
		if menuPanel.Visible and (currentTab == "Growth" or currentTab == "Shop") then
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

local menuRefreshQueued = false
player.AttributeChanged:Connect(function()
	if not menuPanel.Visible or menuRefreshQueued then return end
	menuRefreshQueued = true
	task.defer(function()
		menuRefreshQueued = false
		if menuPanel.Visible then
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
	Text = "⚔ 던전 선택", Font = Enum.Font.GothamBlack, TextSize = 24,
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
		Text = string.format("<font size='20'><b>%s</b></font>\n\n<font color='#bbbbcc' size='13'>%s</font>\n\n%s\n권장 전투력 %d",
			info.Name, info.Desc, string.format("%d초 버티기 + 보스", Config.Dungeon.GetSurviveSeconds(info.Waves)), info.RecommendedPower),
		TextSize = 15, TextYAlignment = Enum.TextYAlignment.Top,
	}, card)
	typeCards[key] = card
end

makeLabel({
	Size = UDim2.new(1, -28, 0, 22), Position = UDim2.new(0, 14, 0, 236),
	Text = "난이도", Font = Enum.Font.GothamBold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
}, selectPanel)

local difficultyButtons = {}
for index, key in ipairs(Config.Dungeon.Difficulties.Order) do
	local info = Config.Dungeon.Difficulties[key]
	difficultyButtons[key] = makeButton({
		Size = UDim2.new(0, 200, 0, 40), Position = UDim2.new(0, 14 + (index - 1) * 212, 0, 262),
		Text = string.format("%s  %s", info.Name, Config.Keys.TierIcons[info.KeyTier or 1]), TextSize = 18, BackgroundColor3 = GRAY,
	}, selectPanel, function()
		selectedDifficulty = key
		refreshSelect()
	end)
end

local summaryLabel = makeLabel({
	Size = UDim2.new(1, -28, 0, 110), Position = UDim2.new(0, 14, 0, 314), RichText = true,
	TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
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
		"<b>%s · %s</b>\n%s → 보스 <font color='#ff9a9a'>%s</font>\n권장 전투력 <font color='#ffe16e'>%d</font>  (내 전투력 %d)\n골드 x%.1f · 티켓 %d장 · 보스 상자 장비 %d개\n🎟 오늘 무료 입장 <b>%d / %d회</b> · 다 쓰면 <b>%s %d개</b> 필요 (보유 %d개, 더 높은 열쇠도 가능)\n열쇠는 필드 구역 군주가 줘요: 앞 구역 🗝 쉬움 · 중간 🔑 보통 · 뒤 구역 🏆 어려움",
		dungeonType.Name, difficulty.Name, string.format("%d초 버티기", Config.Dungeon.GetSurviveSeconds(dungeonType.Waves)), dungeonType.Boss.Name,
		Config.DungeonPower(dungeonType, difficulty), player:GetAttribute("Power") or 0,
		dungeonType.GoldMult * difficulty.GoldMult, difficulty.Tickets, Config.Loot.DungeonChestCount,
		player:GetAttribute("DungeonFree") or 0, Config.Keys.FreeDaily, Config.Keys.TierNames[difficulty.KeyTier or 1], difficulty.KeyCost,
		(function() local total = 0 for t = difficulty.KeyTier or 1, 3 do total += player:GetAttribute(({ "Keys", "KeysNormal", "KeysHard" })[t]) or 0 end return total end)()
	)
end

makeButton({
	Size = UDim2.new(0, 280, 0, 46), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14),
	Text = "입장하기", TextSize = 20, BackgroundColor3 = GREEN,
}, selectPanel, function()
	selectPanel.Visible = false
	Remotes.Dungeon:FireServer("Start", selectedType, selectedDifficulty)
end)

makeButton({
	Size = UDim2.new(0, 280, 0, 46), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -14),
	Text = "닫기", TextSize = 20, BackgroundColor3 = GRAY,
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
	Text = "⛺ 워프", Font = Enum.Font.GothamBlack, TextSize = 24,
}, warpPanel)
makeLabel({
	Size = UDim2.new(1, -28, 0, 36), Position = UDim2.new(0, 14, 0, 44),
	Text = "도달한 구역의 캠프로 이동할 수 있어요. 필드에서 죽으면 가까웠던 캠프에서 부활해요.",
	TextSize = 13, TextColor3 = Color3.fromRGB(190, 190, 210),
}, warpPanel)

local warpList = create("Frame", { Size = UDim2.new(1, -28, 1, -140), Position = UDim2.new(0, 14, 0, 84), BackgroundTransparency = 1 }, warpPanel)
create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, warpList)

makeButton({
	Size = UDim2.new(1, -28, 0, 36), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14),
	Text = "닫기", TextSize = 16, BackgroundColor3 = GRAY,
}, warpPanel, function()
	warpPanel.Visible = false
end)

local function refreshWarp()
	clearChildren(warpList)
	local reached = math.max(1, player:GetAttribute("MaxZone") or 0)

	local function addRow(order, text, unlocked, zone)
		makeButton({
			Size = UDim2.new(1, 0, 0, 36), LayoutOrder = order, Text = text, TextSize = 15,
			BackgroundColor3 = unlocked and Color3.fromRGB(60, 90, 160) or GRAY, TextXAlignment = Enum.TextXAlignment.Left,
		}, warpList, function()
			if unlocked then
				warpPanel.Visible = false
				Remotes.Warp:FireServer("Go", zone)
			end
		end)
	end

	addRow(0, "  🏠 마을 (로비)", true, 0)
	for zone = 1, Config.Field.ZoneCount do
		local unlocked = zone <= reached
		local zoneSet = Config.Sets[Config.Sets.ZoneKeys[zone]]
		addRow(zone, string.format("  %s 구역 %d · %s   (몬스터 Lv.%d)  %s %s 세트", unlocked and "⛺" or "🔒", zone, Config.Field.ZoneNames[zone], Config.Field.GetZoneLevel(zone), zoneSet.Icon, zoneSet.Name), unlocked, zone)
	end
end

player:GetAttributeChangedSignal("Zone"):Connect(function()
	if currentZone() == "Dungeon" then
		warpPanel.Visible = false
	end
end)

Remotes.Warp.OnClientEvent:Connect(function(action)
	if action == "Open" then
		refreshWarp()
		warpPanel.Visible = true
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
	Font = Enum.Font.GothamBlack, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Right, Visible = false,
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
		comboLabel.Text = string.format("🔥 콤보 x%d\n공격력 +%d%%", combo, math.floor(bonus * 100 + 0.5))
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
local radarState = {} -- [점] = { 크기, 색, 흐림 }: 바뀐 속성만 다시 쓴다 (매 프레임 수십 개를 덮어쓰지 않게)
RunService.RenderStepped:Connect(function(dt)
	radarClock += dt
	if radarClock < 0.05 then return end -- 레이더는 초당 20번만 갱신해도 충분하다
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
local skillReadyAt = {}   -- [skillKey] = 이 시각(os.clock) 이후 사용 가능
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
	makeLabel({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 4), Text = cfg.Icon, TextSize = 24 }, slot)
	makeLabel({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 34), Text = cfg.Name, TextSize = 10 }, slot)
	makeLabel({ Size = UDim2.new(0, 18, 0, 16), Position = UDim2.new(0, 3, 0, 3), Text = cfg.Key, TextSize = 12, Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(255, 220, 90) }, slot)
	local cover = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0,
	}, slot)
	rounded(cover)
	local timer = makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = "", TextSize = 20, Font = Enum.Font.GothamBlack }, slot)
	if UserInputService.TouchEnabled then -- 모바일: 스킬 칸을 눌러서 사용
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
	makeLabel({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 4), Text = "💨", TextSize = 24 }, slot)
	makeLabel({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 34), Text = "대시", TextSize = 10 }, slot)
	makeLabel({ Size = UDim2.new(0, 18, 0, 16), Position = UDim2.new(0, 3, 0, 3), Text = "Q", TextSize = 12, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 220, 90) }, slot)
	local cover = create("Frame", { Size = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0 }, slot)
	rounded(cover)
	local charges = makeLabel({ Size = UDim2.new(0, 20, 0, 18), Position = UDim2.new(1, -22, 0, 3), TextSize = 14, Font = Enum.Font.GothamBlack }, slot)
	local timer = makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = "", TextSize = 20, Font = Enum.Font.GothamBlack }, slot)
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
		toast("스킬은 필드와 던전에서만 쓸 수 있어요.")
		return
	end
	if os.clock() < (skillReadyAt[skillKey] or 0) then return end
	if skillKey == "Ult" then -- 범위 안에 적이 없으면 서버가 거절하니, 미리 눈에 띄게 알려 준다
		if (player:GetAttribute("UltCharge") or 0) < Config.Skills.Ult.Cost then
			toast("🎯 궁극기 게이지가 아직 부족해요! (적을 공격하면 차올라요)")
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
			toast("🎯 데드아이: 반경 " .. Config.Skills.Ult.Radius .. " 안에 적이 있어야 락온할 수 있어요! (캠프 근처는 안전지대라 적이 없어요)")
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
			local big = makeLabel({ Size = UDim2.new(1, 0, 0, 120), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.3, 0), Text = "◎ DEADEYE ◎", Font = Enum.Font.GothamBlack, TextSize = 64, TextColor3 = Color3.fromRGB(255, 60, 60), TextStrokeTransparency = 0, ZIndex = 60 }, gui)
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
			slot.Timer.TextSize = 16
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
	elseif input.KeyCode == Enum.KeyCode.LeftShift then
		sprinting = true
		applySpeed()
	elseif input.KeyCode == Enum.KeyCode.H then
		toggleHelp()
	elseif skillByKey[input.KeyCode] then
		useSkill(skillByKey[input.KeyCode])
	elseif input.KeyCode == Enum.KeyCode.Q then
		slide()
	elseif input.KeyCode == Enum.KeyCode.R then
		toggleAuto()
	elseif input.KeyCode == Enum.KeyCode.I then
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
	elseif input.KeyCode == Enum.KeyCode.LeftShift then
		sprinting = false
		applySpeed()
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
			nextSearch = now + 0.4 -- 대상 탐색은 0.4초에 한 번만
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
		SoundBank.Play(sfxParent, "Hit", { Pitch = 1.1 + math.random() * 0.15 }) -- 치명타 전용 소리는 없앴다: 평소 적중음과 같다 (화면의 노란 / 빨간 숫자가 치명타를 알려 준다)
	else
		SoundBank.Play(sfxParent, "Hit", { Pitch = 0.9 + math.random() * 0.25 })
	end
end)

player:GetAttributeChangedSignal("ShakeTick"):Connect(function() -- 서버가 보내는 화면 흔들림 (운석 충돌 등)
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
makeLabel({ Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 8), Text = "⚙ 설정 / ❓ 도움말", Font = Enum.Font.GothamBlack, TextSize = 22 }, helpPanel)
makeLabel({
	Size = UDim2.new(1, -40, 0, 280), Position = UDim2.new(0, 20, 0, 50), RichText = true, TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	Text = table.concat({
		"<b>이동/공격</b>  WASD 이동 · Shift 달리기 · Q 대시 · 마우스 클릭(누르고 있으면 연사) 공격",
		"<b>자동 공격</b>  R — 가장 가까운 적을 자동으로 조준 (적을 클릭하면 그 대상으로 고정)",
		"<b>스킬</b>  C 응급 치료 · V 궁극기(적을 공격해 게이지 100%를 채우면 사용)  — 필드/던전에서 사용",
		"<b>메뉴</b>  I — 가방 · 무기 · 성장 · 스킬 · 펫 · 퀘스트 · 업적 · 랭킹 · 상점",
		"<b>음악</b>  M — 켜기/끄기",
		"",
		"<b>🎯 게임 흐름</b>",
		"1. 필드 / 던전에서 골드를 모아 무기를 강화하세요 (로비의 허수아비는 대미지 / DPS 연습용, 휴식 구역에 서 있으면 방치 골드가 쌓여요)",
		"2. 동쪽 <b>필드</b>에서 몬스터를 잡아 장비를 얻고 레벨을 올리세요 (황금 고블린을 놓치지 마세요!)",
		"3. 북쪽 <b>던전</b>은 열쇠가 필요해요. 정해진 시간을 버티면 보스가 나와요. 중간중간 랜덤 강화(와 패널티)가 터지고, 보스 상자에서 장비를 얻어요",
		"4. 성장 탭에서 훈련을 걸어두고, 장비 세트/유니크를 모아 전투력을 키우세요",
		"5. 최고 레벨이 되면 <b>환생</b>으로 영구 보너스를 받고 다시 도전할 수 있어요",
	}, "\n"),
}, helpPanel)

local function settingButton(y, labelFn, onClick)
	local button
	button = makeButton({
		Size = UDim2.new(1, -40, 0, 32), Position = UDim2.new(0, 20, 0, y), Text = labelFn(), TextSize = 14, BackgroundColor3 = Color3.fromRGB(55, 65, 100),
	}, helpPanel, function()
		onClick()
		button.Text = labelFn()
	end)
end
local function settingSlider(y, title, getValue, setValue)
	local maxValue = 2
	local caption = makeLabel({
		Size = UDim2.new(1, -40, 0, 18), Position = UDim2.new(0, 20, 0, y), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
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

settingSlider(334, "🔊 배경음악 볼륨", function() return musicScale end, function(value)
	musicScale = value
	for name, sound in pairs(tracks) do
		if name == currentMusic then
			sound.Volume = musicVolume()
		end
	end
end)
settingSlider(380, "🔫 총소리 볼륨", function() return settings.ShotVolume end, function(value)
	settings.ShotVolume = value
end)
settingButton(428, function() return "📳 화면 흔들림: " .. (settings.Shake and "켜짐" or "꺼짐") end, function() settings.Shake = not settings.Shake end)
settingButton(468, function() return "📡 레이더: " .. (settings.Radar and "켜짐" or "꺼짐") end, function() settings.Radar = not settings.Radar end)
makeButton({
	Size = UDim2.new(0, 160, 0, 36), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Text = "닫기 (H)", BackgroundColor3 = GRAY,
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
		Name = "HelpButton", Size = UDim2.new(0, 78, 0, 32), Position = UDim2.new(0, 98, 0, 244), Text = "⚙ 설정(H)", TextSize = 12,
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
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.I)
end

do
	local jd = { Used = 0, Last = 0 } -- (지역 변수 개수 제한 때문에 표 하나로 묶음)

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
	RunService.Heartbeat:Connect(function() -- 땅에 닿아 있으면 점프 횟수 회복
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
			jd.Used = 0
		end
	end)
end
