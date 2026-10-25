-- DpsPanelClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: DpsPanelClient)
-- 허수아비를 칠 때만 오른쪽에 작은 패널이 나타나 DPS / 최고 기록 / 마지막 한 방을 보여 준다 (3.5초 동안 안 치면 사라진다).
-- 서버(DummyService)가 DummyDps / DummyBest / DummyHit / DummyTick 속성을 갱신한다.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "DpsPanelGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "DpsPanel"
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -16, 0.36, 0)
panel.Size = UDim2.new(0, 168, 0, 70)
panel.BackgroundColor3 = Color3.fromRGB(16, 18, 30)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 217, 102)
stroke.Thickness = 1.5
stroke.Transparency = 0.35
stroke.Parent = panel

local function label(y, h, size, color, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.new(0, 10, 0, y)
	l.Size = UDim2.new(1, -20, 0, h)
	l.Font = font or Enum.Font.GothamBold
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = panel
	return l
end
local title = label(4, 16, 12, Color3.fromRGB(170, 180, 215))
title.Text = "🎯 Dummy DPS"
local dpsText = label(18, 30, 26, Color3.fromRGB(255, 217, 102), Enum.Font.GothamBlack)
local subText = label(48, 18, 12, Color3.fromRGB(200, 205, 230))

local function commas(n)
	return (tostring(math.floor(n or 0)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local lastShown = 0
player:GetAttributeChangedSignal("DummyTick"):Connect(function()
	lastShown = os.clock()
	panel.Visible = true
	dpsText.Text = commas(player:GetAttribute("DummyDps"))
	subText.Text = string.format("Best %s  ·  Max hit %s", commas(player:GetAttribute("DummyBest")), commas(player:GetAttribute("DummyHit")))
	local mine = lastShown
	task.delay(3.5, function()
		if lastShown == mine then panel.Visible = false end
	end)
end)

------------------------------------------------------------
-- 대미지 미터기 (필드 / 던전 / 허수아비): 총과 세트 효과가 각각 얼마나 피해를 줬는지 나눠서 보여 준다
-- 서버(DamageMeter)가 1초마다 Attribute "DmgMeter" (JSON) 를 갱신한다. 15초 동안 피해가 없으면 사라진다.
------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local MAX_ROWS = 6
local ROW_H = 18
local meter = Instance.new("Frame")
meter.Name = "DamageMeter"
meter.Position = UDim2.new(0, 16, 0.47, 0) -- 왼쪽 가운데 (위: 퀘스트 카드 / 아래: 알림 카드 사이)
meter.Size = UDim2.new(0, 224, 0, 52)
meter.BackgroundColor3 = Color3.fromRGB(16, 18, 30)
meter.BackgroundTransparency = 0.15
meter.BorderSizePixel = 0
meter.Visible = false
meter.Parent = gui
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = meter
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(150, 160, 230)
	st.Thickness = 1.5
	st.Transparency = 0.4
	st.Parent = meter
end
local function meterLabel(parent, x, y, w, h, size, color, align, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.new(0, x, 0, y)
	l.Size = UDim2.new(w, w == 1 and -x * 2 or 0, 0, h)
	l.Font = font or Enum.Font.GothamBold
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.RichText = true
	l.Parent = parent
	return l
end
local meterTitle = meterLabel(meter, 10, 4, 1, 16, 12, Color3.fromRGB(170, 180, 215))
local meterDps = meterLabel(meter, 10, 20, 1, 26, 20, Color3.fromRGB(255, 217, 102), nil, Enum.Font.GothamBlack)
local rows = {}
for i = 1, MAX_ROWS do
	local y = 50 + (i - 1) * ROW_H
	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = Color3.fromRGB(110, 130, 220)
	bar.BackgroundTransparency = 0.7
	bar.BorderSizePixel = 0
	bar.Position = UDim2.new(0, 8, 0, y + 1)
	bar.Size = UDim2.new(0, 0, 0, ROW_H - 3)
	bar.Parent = meter
	local name = meterLabel(meter, 12, y, 0, ROW_H, 12, Color3.fromRGB(230, 232, 245))
	name.Size = UDim2.new(0, 130, 0, ROW_H)
	local value = meterLabel(meter, 0, y, 0, ROW_H, 12, Color3.fromRGB(200, 205, 230), Enum.TextXAlignment.Right)
	value.Position = UDim2.new(1, -78, 0, y)
	value.Size = UDim2.new(0, 70, 0, ROW_H)
	rows[i] = { Bar = bar, Name = name, Value = value }
end

local function sourceName(source)
	if source == "Gun" then return "🔫 Gun" end
	local info = Config.AugInfo[source]
	if info then return info.Icon .. " " .. info.Name end
	return tostring(source)
end
local function short(n)
	if n >= 1e9 then return string.format("%.1fB", n / 1e9) end
	if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
	return tostring(math.floor(n))
end

local meterToken = 0
player:GetAttributeChangedSignal("DmgMeter"):Connect(function()
	local ok, data = pcall(function() return HttpService:JSONDecode(player:GetAttribute("DmgMeter") or "") end)
	if not ok or typeof(data) ~= "table" then return end
	local list = data.Src or {}
	local total = math.max(1, data.Total or 1)
	meterTitle.Text = string.format("⚔ Damage Meter  <font color='#8c93b8'>%ds · total %s</font>", data.Time or 0, short(total))
	meterDps.Text = short(data.Dps or 0) .. " <font size='12' color='#c8cce0'>DPS</font>"
	local shown = 0
	for i, row in ipairs(rows) do
		local entry = list[i]
		if entry then
			shown = i
			local share = (entry[2] or 0) / total
			row.Name.Text = sourceName(entry[1])
			row.Value.Text = string.format("%s <font color='#8c93b8'>%d%%</font>", short(entry[2] or 0), math.floor(share * 100 + 0.5))
			row.Bar.Size = UDim2.new(share, -16 * share, 0, ROW_H - 3)
			local info = Config.AugInfo[entry[1]]
			row.Bar.BackgroundColor3 = info and info.Color or Color3.fromRGB(255, 217, 102)
			row.Name.Visible, row.Value.Visible, row.Bar.Visible = true, true, true
		else
			row.Name.Visible, row.Value.Visible, row.Bar.Visible = false, false, false
		end
	end
	meter.Size = UDim2.new(0, 224, 0, 54 + shown * ROW_H)
	meter.Visible = not player:GetAttribute("ModalOpen")
	meterToken += 1
	local mine = meterToken
	task.delay(15, function()
		if meterToken == mine then meter.Visible = false end
	end)
end)
