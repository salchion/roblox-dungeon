-- WelcomeClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: WelcomeClient)
-- 접속 직후(데이터가 준비되면) 화면 가운데 위쪽에 환영 문구를 잠깐 보여 준다: 이름 / 출석 일수 / 오늘의 한마디.
-- 첫 3초가 비어 보이지 않게, 몇 초 동안 천천히 나타났다가 사라진다. (세션당 한 번)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local TIPS = {
	"Press Q to dash! Narrowly dodge enemy bullets to stack attack power",
	"Press R to auto-aim at the nearest enemy",
	"When you level up, press T to spend stat points (respec for free anytime)",
	"Stand in the rest area to earn gold (even while you're offline)",
	"Starting a dungeon lets you try one random set effect. Defeat a zone lord to unlock it yourself with gold (Y key)",
	"Set gear drops in field zones at a set rate. Wear 1-3 pieces of the same zone's set and effects you unlocked with gold get boosted to Lv.4-6. Preview effects in the J key Codex",
	"Aim directly at a boss's weak-point orb to deal x3 damage",
}

local shown = false
local function show()
	if shown then return end
	shown = true
	local streak = player:GetAttribute("LoginStreak") or 1
	local level = player:GetAttribute("Level") or 1
	local first = level <= 1 and (player:GetAttribute("TutorialActive") == true)
	if first then return end -- 처음 시작하는 튜토리얼 중에는 미션 카드가 가운데에 크게 뜨므로 환영 문구는 건너뛴다 (겹쳐서 가려지던 문제)

	local gui = Instance.new("ScreenGui")
	gui.Name = "WelcomeGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.3, 0)
	panel.Size = UDim2.new(0, 420, 0, 92)
	panel.BackgroundColor3 = Color3.fromRGB(16, 18, 30)
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(120, 140, 230)
	stroke.Thickness = 1.5
	stroke.Transparency = 1
	stroke.Parent = panel

	local function label(y, h, size, color, font, text)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.new(0, 14, 0, y)
		l.Size = UDim2.new(1, -28, 0, h)
		l.Font = font
		l.TextSize = size
		l.TextColor3 = color
		l.TextTransparency = 1
		l.TextWrapped = true
		l.Text = text
		l.Parent = panel
		return l
	end
	local title = label(8, 30, 24, Color3.fromRGB(255, 232, 160), Enum.Font.GothamBlack,
		first and string.format("🎮 Welcome to the world of adventure, %s!", player.DisplayName) or string.format("👋 Welcome back, %s!", player.DisplayName))
	local sub = label(40, 20, 15, Color3.fromRGB(190, 200, 240), Enum.Font.GothamBold,
		first and "Start by shooting the dummy. Click to fire" or string.format("📅 %d-day login streak · Get stronger today!", streak))
	local tip = label(62, 24, 13, Color3.fromRGB(150, 160, 200), Enum.Font.GothamMedium, "💡 " .. TIPS[math.random(#TIPS)])

	local fadeIn = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(panel, fadeIn, { BackgroundTransparency = 0.12 }):Play()
	TweenService:Create(stroke, fadeIn, { Transparency = 0.3 }):Play()
	for _, l in ipairs({ title, sub, tip }) do
		TweenService:Create(l, fadeIn, { TextTransparency = 0 }):Play()
	end
	panel.Position = UDim2.new(0.5, 0, 0.3, 14)
	TweenService:Create(panel, fadeIn, { Position = UDim2.new(0.5, 0, 0.3, 0) }):Play()

	task.delay(4.2, function()
		local fadeOut = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(panel, fadeOut, { BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0.3, -10) }):Play()
		TweenService:Create(stroke, fadeOut, { Transparency = 1 }):Play()
		for _, l in ipairs({ title, sub, tip }) do
			TweenService:Create(l, fadeOut, { TextTransparency = 1 }):Play()
		end
		task.wait(0.9)
		gui:Destroy()
	end)
end

-- 데이터가 준비되면 (DataReady) 바로 보여 준다
if player:GetAttribute("DataReady") then
	show()
else
	player:GetAttributeChangedSignal("DataReady"):Connect(function()
		if player:GetAttribute("DataReady") then show() end
	end)
	task.delay(6, show) -- 혹시 신호를 놓쳐도 한 번은 보여 준다
end
