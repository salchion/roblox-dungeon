-- HudClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: HudClient)
-- 왼쪽 위 상태 카드: 레벨 배지 + 경험치 막대 + 전투력 + 골드 / 티켓 / 열쇠 칩 + 무기 + 위치.
-- 값은 모두 서버가 정한 플레이어 Attribute 에서 읽는다 (서버 호출 없음). 예전의 글자뭉치 패널(PlayerClient)을 대신한다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "HudGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 4
gui.IgnoreGuiInset = true -- 다른 HUD 와 같은 좌표 기준 (위쪽 Roblox 바 아래로 밀리지 않게)
gui.Parent = playerGui

local function make(class, props, parent)
	local instance = Instance.new(class)
	for key, value in pairs(props) do instance[key] = value end
	instance.Parent = parent
	return instance
end

local function round(parent, radius)
	return make("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, parent)
end

local function text(props, parent)
	props.BackgroundTransparency = 1
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextSize = props.TextSize or 13
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return make("TextLabel", props, parent)
end

local function comma(n)
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

------------------------------------------------------------
-- 카드 (240 x 176): 아래의 메뉴 / 설정 버튼 위치는 그대로 두었다
------------------------------------------------------------
local card = make("Frame", {
	Name = "HudCard", Size = UDim2.new(0, 244, 0, 176), Position = UDim2.new(0, 16, 0, 60),
	BackgroundColor3 = Color3.fromRGB(16, 18, 30), BackgroundTransparency = 0.12, BorderSizePixel = 0,
}, gui)
round(card, 12)
make("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(34, 38, 62), Color3.fromRGB(14, 16, 26)), Rotation = 90 }, card)
local cardStroke = make("UIStroke", { Color = Color3.fromRGB(110, 130, 220), Thickness = 1.5, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)

-- 레벨 배지
local badge = make("Frame", { Size = UDim2.new(0, 50, 0, 50), Position = UDim2.new(0, 10, 0, 10), BackgroundColor3 = Color3.fromRGB(70, 120, 230), BorderSizePixel = 0 }, card)
round(badge, 12)
make("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(110, 170, 255), Color3.fromRGB(60, 80, 200)), Rotation = 90 }, badge)
make("UIStroke", { Color = Color3.fromRGB(190, 215, 255), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, badge)
text({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 4), Text = "LV", TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromRGB(220, 235, 255) }, badge)
local levelText = text({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 16), Text = "1", TextSize = 26, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Center }, badge)

-- 이름 + 전투력
text({ Size = UDim2.new(1, -76, 0, 16), Position = UDim2.new(0, 68, 0, 9), Text = player.DisplayName, TextSize = 12, TextColor3 = Color3.fromRGB(175, 185, 220), TextTruncate = Enum.TextTruncate.AtEnd }, card)
local powerText = text({ Size = UDim2.new(1, -76, 0, 26), Position = UDim2.new(0, 68, 0, 24), Text = "⚡ 0", TextSize = 22, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 225, 110), RichText = true }, card)

-- 경험치 막대 (글자를 막대 안에)
local xpBack = make("Frame", { Size = UDim2.new(1, -20, 0, 14), Position = UDim2.new(0, 10, 0, 66), BackgroundColor3 = Color3.fromRGB(34, 38, 58), BorderSizePixel = 0 }, card)
round(xpBack, 7)
local xpFill = make("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(110, 200, 255), BorderSizePixel = 0 }, xpBack)
round(xpFill, 7)
make("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(150, 225, 255), Color3.fromRGB(80, 150, 255)) }, xpFill)
local xpText = text({ Size = UDim2.new(1, 0, 1, 0), Text = "", TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 }, xpBack)
xpText.TextStrokeTransparency = 0.6

-- 자원 칩 3개: 골드 / 티켓 / 열쇠
local function chip(x, width, color)
	local frame = make("Frame", { Size = UDim2.new(0, width, 0, 26), Position = UDim2.new(0, x, 0, 88), BackgroundColor3 = Color3.fromRGB(26, 29, 46), BorderSizePixel = 0 }, card)
	round(frame, 8)
	make("UIStroke", { Color = color, Thickness = 1, Transparency = 0.55, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
	return text({ Size = UDim2.new(1, -8, 1, 0), Position = UDim2.new(0, 6, 0, 0), Text = "", TextSize = 12, RichText = true }, frame)
end
local goldText = chip(10, 106, Color3.fromRGB(255, 215, 90))
local ticketText = chip(120, 54, Color3.fromRGB(215, 160, 255))
local keyText = chip(178, 56, Color3.fromRGB(150, 240, 200))

-- 무기 / 위치
local weaponText = text({ Name = "HudWeaponRow", Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 10, 0, 122), Text = "", TextSize = 12, RichText = true, TextTruncate = Enum.TextTruncate.AtEnd }, card)
local zoneText = text({ Name = "HudZoneRow", Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 10, 0, 146), Text = "", TextSize = 12, TextColor3 = Color3.fromRGB(175, 185, 220), RichText = true }, card)
make("Frame", { Name = "HudSep", Size = UDim2.new(1, -20, 0, 1), Position = UDim2.new(0, 10, 0, 118), BackgroundColor3 = Color3.fromRGB(60, 66, 100), BackgroundTransparency = 0.5, BorderSizePixel = 0 }, card)

local function refresh()
	local level = player:GetAttribute("Level") or 1
	local xp, needed = player:GetAttribute("XP") or 0, player:GetAttribute("XPNeeded") or 1
	local maxed = level >= Config.Level.Max
	local blocked = not maxed and level >= Config.GetLevelCap(player:GetAttribute("GatePassed") or 0)
	levelText.Text = tostring(level)
	xpFill.Size = UDim2.new((maxed or blocked) and 1 or math.clamp(xp / needed, 0, 1), 0, 1, 0)
	xpFill.BackgroundColor3 = blocked and Color3.fromRGB(255, 170, 60) or Color3.fromRGB(110, 200, 255)
	xpText.Text = maxed and "MAX" or blocked and "돌파가 필요해요!" or string.format("%s / %s XP", comma(xp), comma(needed))
	powerText.Text = "⚡ " .. comma(player:GetAttribute("Power") or 0) .. " <font size='11' color='#9aa4cc'>전투력</font>"
	goldText.Text = "💰 <font color='#ffd966'>" .. comma(player:GetAttribute("Gold") or 0) .. "</font>"
	ticketText.Text = "🎫 <font color='#d9a6ff'>" .. comma(player:GetAttribute("Tickets") or 0) .. "</font>"
	local keys = (player:GetAttribute("Keys") or 0) + (player:GetAttribute("KeysNormal") or 0) + (player:GetAttribute("KeysHard") or 0)
	keyText.Text = "🗝 <font color='#a6f0c8'>" .. keys .. "</font>"

	local weaponLevel = player:GetAttribute("WeaponLevel") or 0
	local tier = Config.GetWeaponTier(weaponLevel)
	weaponText.Text = string.format("⚔ <font color='#%s'>%s</font>", tier.Color:ToHex(), Config.FormatWeapon(weaponLevel))

	if not player:GetAttribute("DataReady") then -- 저장된 정보를 불러오는 동안은 멈춘 게 아니라는 걸 바로 알려 준다
		zoneText.Text = "⏳ <font color='#ffe16e'>내 정보를 불러오는 중...</font>"
		return
	end
	local zone = player:GetAttribute("Zone") or "Lobby"
	local zoneName = zone == "Lobby" and "마을" or zone == "Dungeon" and (player:GetAttribute("DungeonLabel") or "던전") or string.format("필드 · 최고 %d구역", player:GetAttribute("MaxZone") or 0)
	zoneText.Text = string.format("📍 %s   <font color='#8fd8ff'>🎟 무료 %d/%d</font>", zoneName, player:GetAttribute("DungeonFree") or 0, Config.Keys.FreeDaily)
end

for _, name in ipairs({ "DataReady", "Level", "XP", "XPNeeded", "GatePassed", "Power", "Gold", "Tickets", "Keys", "KeysNormal", "KeysHard", "WeaponLevel", "Zone", "MaxZone", "DungeonFree", "DungeonLabel" }) do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end
refresh()

-- 레벨업: 배지가 톡 튄다
local lastLevel = player:GetAttribute("Level") or 1
player:GetAttributeChangedSignal("Level"):Connect(function()
	local level = player:GetAttribute("Level") or 1
	if level > lastLevel then
		badge.Size = UDim2.new(0, 64, 0, 64)
		badge.Position = UDim2.new(0, 3, 0, 3)
		TweenService:Create(badge, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0, 50, 0, 50), Position = UDim2.new(0, 10, 0, 10) }):Play()
		cardStroke.Transparency = 0
		TweenService:Create(cardStroke, TweenInfo.new(1.2), { Transparency = 0.35 }):Play()
	end
	lastLevel = level
end)
