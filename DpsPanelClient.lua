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
title.Text = "🎯 허수아비 DPS"
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
	subText.Text = string.format("최고 %s  ·  한 방 %s", commas(player:GetAttribute("DummyBest")), commas(player:GetAttribute("DummyHit")))
	local mine = lastShown
	task.delay(3.5, function()
		if lastShown == mine then panel.Visible = false end
	end)
end)
