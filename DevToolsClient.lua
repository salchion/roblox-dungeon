-- DevToolsClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: DevToolsClient)
-- Studio 에서만 보이는 테스트 버튼: "풀파밍 캐릭터" (서버도 Studio 에서만 처리한다). 실제 게시된 게임에서는 아무것도 만들지 않는다.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "DevToolsGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.Parent = player:WaitForChild("PlayerGui")

local button = Instance.new("TextButton")
button.Name = "DevMaxButton"
button.Size = UDim2.new(0, 190, 0, 30)
button.AnchorPoint = Vector2.new(0.5, 0)
button.Position = UDim2.new(0.5, 0, 0, 4)
button.BackgroundColor3 = Color3.fromRGB(120, 60, 150)
button.BackgroundTransparency = 0.15
button.TextColor3 = Color3.new(1, 1, 1)
button.Font = Enum.Font.GothamBold
button.TextSize = 11
button.Text = "🧪 Full-farmed test character"
button.BorderSizePixel = 0
button.Parent = gui
Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)

local busy = false
button.Activated:Connect(function()
	if busy then return end
	busy = true
	button.Text = "⏳ Applying..."
	Remotes.Meta:FireServer("DevMax")
	task.delay(2, function()
		button.Text = "🧪 Full-farmed test character"
		busy = false
	end)
end)
