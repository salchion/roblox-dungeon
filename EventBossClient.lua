-- EventBossClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: EventBossClient)
-- 필드 월드 보스(거신)가 나타나 있는 동안, 화면 위쪽에 남은 시간 + 보스 체력을 크게 보여 준다.
-- 제한 시간(Config.Events.Lifetime) 안에 못 잡으면 보스가 땅속으로 사라진다. 빨리 잡을수록 보상이 커진다.
-- 값은 서버가 workspace Attribute 로 알려 준다: BossEventEnd(서버 시각) / BossEventHp(0~1) / BossEventZone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local INK = Color3.fromRGB(16, 12, 34)

local gui = Instance.new("ScreenGui")
gui.Name = "EventBossGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5
gui.Enabled = false
gui.Parent = playerGui

local function make(class, props, parent)
	local instance = Instance.new(class)
	for key, value in pairs(props) do instance[key] = value end
	instance.Parent = parent
	return instance
end

local panel = make("Frame", {
	Size = UDim2.new(0, 400, 0, 62), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 84),
	BackgroundColor3 = Color3.fromRGB(120, 54, 96), BackgroundTransparency = 0.04, BorderSizePixel = 0,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 14) }, panel)
make("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.62, 0.55, 0.7)), Rotation = 90 }, panel)
local stroke = make("UIStroke", { Color = INK, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
local scale = make("UIScale", {}, panel)

local function label(props)
	props.BackgroundTransparency = 1
	props.Font = props.Font or Enum.Font.GothamBlack
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextStrokeColor3 = INK
	props.TextStrokeTransparency = 0.15
	return make("TextLabel", props, panel)
end

local title = label({ Size = UDim2.new(1, -110, 0, 24), Position = UDim2.new(0, 12, 0, 4), Text = "", TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left })
local timer = label({ Size = UDim2.new(0, 100, 0, 28), Position = UDim2.new(1, -108, 0, 3), Text = "", TextSize = 24, TextXAlignment = Enum.TextXAlignment.Right })
local hpBack = make("Frame", { Size = UDim2.new(1, -24, 0, 16), Position = UDim2.new(0, 12, 0, 36), BackgroundColor3 = Color3.fromRGB(46, 30, 52), BorderSizePixel = 0 }, panel)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, hpBack)
make("UIStroke", { Color = INK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, hpBack)
local hpFill = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 120, 90), BorderSizePixel = 0 }, hpBack)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, hpFill)
make("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 170, 120), Color3.fromRGB(220, 70, 70)), Rotation = 90 }, hpFill)
local hpText = label({ Size = UDim2.new(1, 0, 1, 0), Text = "", TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, Parent = hpBack })
hpText.Parent = hpBack

-- 폰(터치 화면): 위쪽 세계 보스 카드가 화면을 너무 많이 가려서 작고 얇게 줄인다
if game:GetService("UserInputService").TouchEnabled and not game:GetService("UserInputService").MouseEnabled then
	panel.Size = UDim2.new(0, 270, 0, 44)
	panel.Position = UDim2.new(0.5, 0, 0, 42)
	stroke.Thickness = 2
	title.Size = UDim2.new(1, -86, 0, 18)
	title.Position = UDim2.new(0, 10, 0, 3)
	title.TextSize = 11
	timer.Size = UDim2.new(0, 76, 0, 20)
	timer.Position = UDim2.new(1, -84, 0, 2)
	timer.TextSize = 16
	hpBack.Size = UDim2.new(1, -20, 0, 10)
	hpBack.Position = UDim2.new(0, 10, 0, 28)
	hpText.TextSize = 8
end

local lastWholeSecond = -1
task.spawn(function()
	while true do
		local endAt = workspace:GetAttribute("BossEventEnd")
		local zone = player:GetAttribute("Zone")
		if type(endAt) == "number" and (zone == "Field" or zone == "Lobby") and not player:GetAttribute("ModalOpen") and not player:GetAttribute("IntroPlaying") then
			gui.Enabled = true
			local left = math.max(0, endAt - workspace:GetServerTimeNow())
			local hp = workspace:GetAttribute("BossEventHp") or 1
			local seconds = math.ceil(left)
			timer.Text = string.format("%d:%02d", seconds // 60, seconds % 60)
			title.Text = string.format("🗿 %s · Zone %s", Config.Events.Name, tostring(workspace:GetAttribute("BossEventZone") or "?"))
			hpFill.Size = UDim2.new(math.clamp(hp, 0, 1), 0, 1, 0)
			hpText.Text = string.format("%d%%", math.floor(hp * 100 + 0.5))
			local urgent = left <= 30
			timer.TextColor3 = urgent and Color3.fromRGB(255, 130, 120) or Color3.new(1, 1, 1)
			stroke.Color = urgent and Color3.fromRGB(190, 40, 50) or INK
			if urgent and seconds ~= lastWholeSecond then -- 30초 안쪽에서는 매초 톡 뛴다
				lastWholeSecond = seconds
				scale.Scale = 1.06
				game:GetService("TweenService"):Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
		else
			gui.Enabled = false
		end
		task.wait(0.25)
	end
end)
