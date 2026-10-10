-- WelcomeClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: WelcomeClient)
-- 접속 직후(데이터가 준비되면) 화면 가운데 위쪽에 환영 문구를 잠깐 보여 준다: 이름 / 출석 일수 / 오늘의 한마디.
-- 첫 3초가 비어 보이지 않게, 몇 초 동안 천천히 나타났다가 사라진다. (세션당 한 번)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local TIPS = {
	"Q 키로 대시! 적의 탄을 아슬아슬하게 피하면 공격력이 쌓여요",
	"R 키를 누르면 가까운 적을 자동으로 조준해요",
	"레벨이 오르면 T 키로 스탯 포인트를 올려요 (언제든 무료로 다시 찍을 수 있어요)",
	"휴식 구역에 서 있으면 골드가 쌓여요 (접속을 꺼도 쌓여요)",
	"던전에서는 6초마다 랜덤 세트 조각이 나와요. 같은 세트 2~3개를 모으면 세트 효과가 발동해요",
	"필드 구역에서 세트 장비를 모으거나 세트 조각으로 각인해 2~3부위를 맞추면 효과가 터져요. J 키 도감에서 효과를 미리 볼 수 있어요",
	"보스의 약점 구슬을 직접 조준해서 맞히면 피해가 x3가 돼요",
}

local shown = false
local function show()
	if shown then return end
	shown = true
	local streak = player:GetAttribute("LoginStreak") or 1
	local level = player:GetAttribute("Level") or 1
	local first = level <= 1 and (player:GetAttribute("TutorialActive") == true)

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
		first and string.format("🎮 %s님, 모험의 세계에 오신 걸 환영해요!", player.DisplayName) or string.format("👋 다시 오셨네요, %s님!", player.DisplayName))
	local sub = label(40, 20, 15, Color3.fromRGB(190, 200, 240), Enum.Font.GothamBold,
		first and "먼저 허수아비를 쏴 보세요. 마우스 클릭으로 사격해요" or string.format("📅 %d일 연속 출석 중 · 오늘도 강해져 봐요", streak))
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
