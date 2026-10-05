-- PlayerClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript)
-- 왼클릭 공격, 조준점, 스탯 표시, 숫자키 1/2/3으로 스탯 포인트 투자

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local attackEvent = ReplicatedStorage:WaitForChild("Attack")
local upgradeEvent = ReplicatedStorage:WaitForChild("Upgrade")

------------------------------------------------------------
-- 화면 UI
------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "HUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true -- 조준점이 정확히 화면 중앙에 오도록
gui.Parent = player:WaitForChild("PlayerGui")

local crosshair = Instance.new("Frame")
crosshair.Size = UDim2.new(0, 6, 0, 6)
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.Position = UDim2.new(0.5, 0, 0.5, 0)
crosshair.BackgroundColor3 = Color3.new(1, 1, 1)
crosshair.BorderSizePixel = 0
crosshair.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = crosshair

local panel = Instance.new("TextLabel")
panel.Size = UDim2.new(0, 280, 0, 120)
panel.Position = UDim2.new(0, 20, 1, -140)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
panel.BackgroundTransparency = 0.35
panel.TextColor3 = Color3.new(1, 1, 1)
panel.Font = Enum.Font.GothamMedium
panel.TextSize = 16
panel.TextXAlignment = Enum.TextXAlignment.Left
panel.TextYAlignment = Enum.TextYAlignment.Top
panel.Parent = gui

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingTop = UDim.new(0, 10)
padding.Parent = panel

local function refresh()
	panel.Text = string.format(
		"스탯 포인트: %d\n[1] 치명타 확률  Lv.%d\n[2] 공격 속도  Lv.%d\n[3] 최대 체력  Lv.%d",
		player:GetAttribute("StatPoints") or 0,
		player:GetAttribute("CritPoints") or 0,
		player:GetAttribute("SpeedPoints") or 0,
		player:GetAttribute("HealthPoints") or 0
	)
end

player.AttributeChanged:Connect(refresh)
refresh()

------------------------------------------------------------
-- 입력
------------------------------------------------------------
local KEY_TO_STAT = {
	[Enum.KeyCode.One] = "Crit",
	[Enum.KeyCode.Two] = "Speed",
	[Enum.KeyCode.Three] = "Health",
}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- 내가 보는 방향만 서버에 보내고, 맞았는지는 서버가 판정
		attackEvent:FireServer(camera.CFrame.LookVector)
	elseif KEY_TO_STAT[input.KeyCode] then
		upgradeEvent:FireServer(KEY_TO_STAT[input.KeyCode])
	end
end)
