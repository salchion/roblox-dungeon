-- SkillCueClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: SkillCueClient)
-- 서버가 "둘러싸였나요? F 를 누르세요!" 안내(Tutorial Prompt, Key = "F")를 보내면, V(데드아이)처럼 캐릭터 머리 위에도 큼직한
-- 스킬 아이콘 + "PRESS [ F ]" 를 띄운다. F 를 누르거나 6초가 지나면 사라진다.
-- (PlayerClient 는 지역 변수 한도에 가까워서 따로 뺐다)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local GOLD = Color3.fromRGB(255, 160, 210) -- (죽음의 연꽃: 분홍빛)
local current

local function new(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props) do object[key] = value end
	object.Parent = parent
	return object
end

local function show()
	if current then current:Destroy() end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local cfg = Config.Skills and (Config.Skills.Spirit or Config.Skills.Blast)
	local icon = cfg and cfg.Icon or "🌸"
	local board = new("BillboardGui", {
		Name = "LotusCueBillboard", Adornee = root, Size = UDim2.new(0, 200, 0, 170), StudsOffset = Vector3.new(0, 7.5, 0),
		AlwaysOnTop = true, MaxDistance = 300, ResetOnSpawn = false,
	}, player:WaitForChild("PlayerGui"))
	current = board
	local scale = new("UIScale", { Scale = 1 }, board)
	local ring = new("Frame", { Size = UDim2.new(0, 128, 0, 128), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -4), BackgroundColor3 = GOLD, BackgroundTransparency = 0.7, BorderSizePixel = 0 }, board)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
	local disc = new("Frame", { Size = UDim2.new(0, 96, 0, 96), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), BackgroundColor3 = Color3.fromRGB(44, 22, 40), BackgroundTransparency = 0.05, BorderSizePixel = 0 }, board)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, disc)
	new("UIStroke", { Color = GOLD, Thickness = 3.5 }, disc)
	new("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = icon, TextSize = 58, Font = Enum.Font.GothamBlack, TextColor3 = Color3.new(1, 1, 1) }, disc)
	local pill = new("Frame", { Size = UDim2.new(0, 170, 0, 38), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 116), BackgroundColor3 = Color3.fromRGB(44, 22, 40), BackgroundTransparency = 0.05, BorderSizePixel = 0 }, board)
	new("UICorner", { CornerRadius = UDim.new(0, 10) }, pill)
	new("UIStroke", { Color = GOLD, Thickness = 2 }, pill)
	new("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 19, TextColor3 = Color3.fromRGB(255, 200, 230),
		Text = UserInputService.TouchEnabled and "TAP DEATH LOTUS!" or "PRESS  [ F ]",
	}, pill)
	task.spawn(function()
		local began = os.clock()
		while board.Parent and os.clock() - began < 6 do
			local t = os.clock() - began
			scale.Scale = 1 + 0.1 * math.sin(t * 6)
			ring.BackgroundTransparency = 0.55 + 0.3 * (0.5 + 0.5 * math.sin(t * 6))
			task.wait()
		end
		if board.Parent then board:Destroy() end
		if current == board then current = nil end
	end)
end

Remotes.Tutorial.OnClientEvent:Connect(function(action, data)
	if action == "Prompt" and typeof(data) == "table" and data.Key == "F" then
		show()
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F and current then
		current:Destroy()
		current = nil
	end
end)
