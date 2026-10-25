-- BossStageClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: BossStageClient)
-- 필드 구역 군주 전투 연출 화면: 등장 배너(이름 / 구역 / 권장 전투력 / 약점 힌트) · 격노 경고 · 승리 배너 · 번쩍임 · 시야 변화 · 군주전 조명 낮춤.
-- 서버(BossStage)가 Remotes.BossStage 로 "Intro" / "Enrage" / "Victory" 를 보낸다. 화면 흔들림은 서버가 ShakeTick 속성으로 알리고 PlayerClient 가 처리한다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Kit = require(ReplicatedStorage:WaitForChild("ClientKit"))
local create, makeLabel = Kit.create, Kit.makeLabel

local player = Players.LocalPlayer

local gui = create("ScreenGui", { Name = "BossStageGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 70 }, player:WaitForChild("PlayerGui"))
local uiScale = create("UIScale", {}, gui)
local function fit()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	uiScale.Scale = math.clamp(math.min(viewport.X / 760, viewport.Y / 440), 0.55, math.max(1, game:GetService("Players").LocalPlayer:GetAttribute("UiMul") or 1))
end
fit()
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit) end
game:GetService("Players").LocalPlayer:GetAttributeChangedSignal("UiMul"):Connect(fit)

-- 번쩍임(전체 화면)
local flash = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 }, gui)
local function doFlash(color, strength)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 1 - strength
	TweenService:Create(flash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

-- 배너: 가운데 위쪽 (왼쪽 카드 / 위쪽 가운데 미션 카드와 겹치지 않게 화면 높이 35% 근처)
local banner = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.36, 0), Size = UDim2.new(0, 560, 0, 150), BackgroundTransparency = 1, Visible = false, ZIndex = 5,
}, gui)
local title = makeLabel({ Size = UDim2.new(1, 0, 0, 62), Position = UDim2.new(0, 0, 0, 0), Text = "", TextSize = 40, Font = Enum.Font.GothamBlack, ZIndex = 6, TextStrokeTransparency = 0.2 }, banner)
local sub = makeLabel({ Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 0, 64), Text = "", TextSize = 18, Font = Enum.Font.GothamBold, ZIndex = 6, TextStrokeTransparency = 0.35 }, banner)
local hint = makeLabel({ Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0, 96), Text = "", TextSize = 15, Font = Enum.Font.GothamMedium, ZIndex = 6, TextStrokeTransparency = 0.45 }, banner)
local bannerToken = 0

local function showBanner(text1, text2, text3, color, seconds)
	bannerToken += 1
	local token = bannerToken
	title.Text, sub.Text, hint.Text = text1, text2 or "", text3 or ""
	title.TextColor3, sub.TextColor3, hint.TextColor3 = color, Color3.fromRGB(240, 235, 225), Color3.fromRGB(255, 225, 130)
	for _, label in ipairs({ title, sub, hint }) do
		label.TextTransparency = 1
		label.TextStrokeTransparency = 1
	end
	banner.Visible = true
	banner.Size = UDim2.new(0, 700, 0, 188) -- 크게 나타났다가 제자리로 (쿵 하는 느낌)
	TweenService:Create(banner, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0, 560, 0, 150) }):Play()
	for _, label in ipairs({ title, sub, hint }) do
		TweenService:Create(label, TweenInfo.new(0.2), { TextTransparency = 0, TextStrokeTransparency = label == title and 0.2 or 0.4 }):Play()
	end
	task.delay(seconds, function()
		if token ~= bannerToken then return end
		for _, label in ipairs({ title, sub, hint }) do
			TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
		task.delay(0.7, function()
			if token == bannerToken then banner.Visible = false end
		end)
	end)
end

local function punchFov(amount)
	local camera = workspace.CurrentCamera
	if not camera then return end
	local base = camera.FieldOfView
	TweenService:Create(camera, TweenInfo.new(0.12), { FieldOfView = base + amount }):Play()
	task.delay(0.15, function()
		TweenService:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base }):Play()
	end)
end

Remotes.BossStage.OnClientEvent:Connect(function(kind, data)
	if typeof(data) ~= "table" then return end
	local zone = tonumber(data.Zone) or 0
	if kind == "Intro" then
		doFlash(Color3.fromRGB(255, 170, 90), 0.35)
		punchFov(10)
		local power = tonumber(data.Power) or 0
		showBanner(
			"👑 " .. tostring(data.Name or "Lord"),
			string.format("Lord of %s  ·  Zone %d", tostring(data.ZoneName or ""), zone),
			string.format("Recommended ⚡%s  ·  Aim at the yellow orb for 3x damage!", tostring(power)),
			Color3.fromRGB(255, 120, 100), 4)
	elseif kind == "Enrage" then
		doFlash(Color3.fromRGB(255, 40, 30), 0.45)
		punchFov(8)
		showBanner("😡 ENRAGED!", "It attacks faster now", "", Color3.fromRGB(255, 70, 60), 2.2)
	elseif kind == "Victory" then
		doFlash(Color3.fromRGB(255, 240, 190), 0.6)
		punchFov(14)
		showBanner("🏆 LORD DEFEATED", tostring(data.Name or ""), data.First and "⭐ First kill!" or "", Color3.fromRGB(255, 220, 110), 3.5)
	end
end)

-- 군주전 조명: 싸우는 동안 노출을 조금 낮춰 분위기를 어둡게 (끝나면 원래대로)
local baseExposure
local function updateLight()
	local fighting = player:GetAttribute("BossFight") == true
	if fighting and baseExposure == nil then
		baseExposure = Lighting.ExposureCompensation
		TweenService:Create(Lighting, TweenInfo.new(1.2), { ExposureCompensation = baseExposure - 0.3 }):Play()
	elseif not fighting and baseExposure ~= nil then
		TweenService:Create(Lighting, TweenInfo.new(1.5), { ExposureCompensation = baseExposure }):Play()
		baseExposure = nil
	end
end
player:GetAttributeChangedSignal("BossFight"):Connect(updateLight)
