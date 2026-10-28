-- BigHudClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: BigHudClient)
-- 화면 아래 가운데, 무기 바(1~0)와 스킬 바 사이에 큰 "전투력" 숫자 + 레벨 / 경험치 막대를 보여 준다 (모바일 게임 레퍼런스처럼 굵은 외곽선 글씨).
-- 값은 모두 서버가 정한 플레이어 Attribute 에서 읽는다 (서버 호출 없음). 큰 화면(데스크톱)에서만 보이고, 폰은 예전처럼 왼쪽 위 카드 안에 있다.
-- 위치: 스킬 바(아래에서 14 ~ 78) 바로 위. 무기 바는 화면 높이의 77% 지점에 있어서 그 사이 빈 줄에 들어간다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local INK = Color3.fromRGB(10, 12, 24)

local gui = Instance.new("ScreenGui")
gui.Name = "BigHudGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 3
gui.Enabled = false
gui.Parent = playerGui

local function make(class, props, parent)
	local instance = Instance.new(class)
	for key, value in pairs(props) do instance[key] = value end
	instance.Parent = parent
	return instance
end

local function label(props, parent)
	props.BackgroundTransparency = 1
	props.Font = props.Font or Enum.Font.GothamBlack
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextStrokeColor3 = INK
	props.TextStrokeTransparency = props.TextStrokeTransparency or 0
	return make("TextLabel", props, parent)
end

local root = make("Frame", {
	Name = "BigHud", Size = UDim2.new(0, 460, 0, 52), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -86),
	BackgroundTransparency = 1,
}, gui)
local rootScale = make("UIScale", {}, root)

local powerText = label({
	Size = UDim2.new(1, 0, 0, 30), Text = "", TextSize = 28, RichText = true, TextXAlignment = Enum.TextXAlignment.Center,
}, root)

local barBack = make("Frame", {
	Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, 32), BackgroundColor3 = Color3.fromRGB(46, 36, 28), BorderSizePixel = 0,
}, root)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, barBack)
make("UIStroke", { Color = INK, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, barBack)
local barFill = make("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 200, 90), BorderSizePixel = 0 }, barBack)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, barFill)
local fillGradient = make("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 225, 140), Color3.fromRGB(225, 150, 50)), Rotation = 90 }, barFill)
local levelText = label({ Size = UDim2.new(0.45, 0, 1, 0), Position = UDim2.new(0, 10, 0, 0), Text = "", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }, barBack)
local xpText = label({ Size = UDim2.new(0.55, 0, 1, 0), Position = UDim2.new(0.45, -10, 0, 0), Text = "", TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3 }, barBack)

local function comma(n)
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local lastPower = player:GetAttribute("Power") or 0
local lastEarned = -1
local function refresh()
	local level = player:GetAttribute("Level") or 1
	local xp, needed = player:GetAttribute("XP") or 0, math.max(1, player:GetAttribute("XPNeeded") or 1)
	local maxed = level >= Config.Level.Max
	local blocked = not maxed and level >= Config.GetLevelCap(player:GetAttribute("GatePassed") or 0)
	local power = player:GetAttribute("Power") or 0
	powerText.Text = string.format("⚡ <font color='#ffe16e'>%s</font> <font size='15' color='#cfd6f0'>Power</font>", comma(power))
	if maxed then
		-- 최대 레벨 이후: 경험치 막대가 "패러건 막대"로 바뀐다 (디아블로 3 처럼 파란빛 막대가 차서 포인트가 쌓인다). 막대가 다 차면 포인트 +1 이고 다시 0 부터.
		local pxp, pneed = player:GetAttribute("ParagonXp") or 0, math.max(1, player:GetAttribute("ParagonXpNeeded") or 1)
		local earned, left = player:GetAttribute("ParagonEarned") or 0, player:GetAttribute("ParagonLeft") or 0
		local full = earned >= Config.ParagonMaxPoints
		levelText.Text = string.format("Lv %d  ✦ Paragon %d", level, earned)
		barFill.Size = UDim2.new(full and 1 or math.clamp(pxp / pneed, 0, 1), 0, 1, 0)
		fillGradient.Color = ColorSequence.new(Color3.fromRGB(150, 235, 255), Color3.fromRGB(70, 130, 255))
		barBack.BackgroundColor3 = Color3.fromRGB(26, 34, 58)
		if left > 0 then
			xpText.Text = string.format("▲ %d unspent (T)  ·  %s / %s XP", left, comma(pxp), comma(pneed))
		else
			xpText.Text = string.format("%s / %s XP", comma(pxp), comma(pneed))
		end
		if earned > lastEarned and lastEarned >= 0 then -- 포인트를 얻는 순간 막대가 번쩍인다
			barFill.BackgroundColor3 = Color3.new(1, 1, 1)
			TweenService:Create(barFill, TweenInfo.new(0.6), { BackgroundColor3 = Color3.fromRGB(110, 200, 255) }):Play()
			rootScale.Scale = 1.12
			TweenService:Create(rootScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		lastEarned = earned
	else
		levelText.Text = "Lv " .. level
		barBack.BackgroundColor3 = Color3.fromRGB(46, 36, 28)
		barFill.Size = UDim2.new(blocked and 1 or math.clamp(xp / needed, 0, 1), 0, 1, 0)
		fillGradient.Color = blocked and ColorSequence.new(Color3.fromRGB(255, 190, 90), Color3.fromRGB(230, 110, 40)) or ColorSequence.new(Color3.fromRGB(255, 225, 140), Color3.fromRGB(225, 150, 50))
		xpText.Text = blocked and "Breakthrough needed!" or string.format("%s / %s XP", comma(xp), comma(needed))
	end
	if power > lastPower then -- 전투력이 오르면 숫자가 톡 커졌다 돌아온다
		rootScale.Scale = 1.12
		TweenService:Create(rootScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	lastPower = power
end
for _, name in ipairs({ "Level", "XP", "XPNeeded", "GatePassed", "Power", "ParagonXp", "ParagonXpNeeded", "ParagonEarned", "ParagonLeft" }) do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end
refresh()

-- 큰 화면 + 로비 / 필드 / 던전 + 큰 창이 없을 때만 보인다
task.spawn(function()
	while true do
		local zone = player:GetAttribute("Zone")
		gui.Enabled = playerGui:GetAttribute("UiCompact") ~= true and player:GetAttribute("DataReady") == true
			and (zone == "Lobby" or zone == "Field" or zone == "Dungeon")
			and not player:GetAttribute("ModalOpen") and not player:GetAttribute("ChestOpening") and not player:GetAttribute("IntroPlaying")
		task.wait(0.4)
	end
end)
