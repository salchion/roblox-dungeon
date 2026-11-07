-- BootCoverClient (ReplicatedFirst 안의 LocalScript, 이름: BootCoverClient)
-- 접속하자마자(로블록스 기본 로딩 화면이 끝난 직후) 검은 화면 + "GEAR RUSH" 를 먼저 깐다.
-- 예전엔 오프닝(IntroClient)의 로딩 화면이 뜨기 전 약 1초 동안 마을이 그대로 보였다.
-- 오프닝 화면(IntroGui)이 나타나면 바로 사라진다. 오프닝이 없으면(마을이 아닌 곳 / 오류) 늦어도 30초 뒤에는 걷힌다.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "BootCover"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 2000
local page = Instance.new("Frame")
page.Size = UDim2.new(1, 0, 1, 0)
page.BackgroundColor3 = Color3.fromRGB(12, 12, 20) -- (오프닝 로딩 화면과 같은 색: 이어서 보인다)
page.BorderSizePixel = 0
page.Parent = gui
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 70)
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.new(0.5, 0, 0.36, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextSize = 56
title.TextColor3 = Color3.fromRGB(226, 208, 168)
title.Text = "GEAR RUSH"
title.Parent = page
gui.Parent = playerGui

local done = false
local function finish(fade)
	if done then return end
	done = true
	if fade then
		TweenService:Create(page, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(title, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		task.delay(0.45, function() gui:Destroy() end)
	else
		gui:Destroy()
	end
end

-- 오프닝 화면이 생기면: 한 프레임 뒤(그 화면이 그려진 뒤)에 바로 걷는다
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "IntroGui" then
		task.wait(0.1)
		finish(false)
	end
end)
if playerGui:FindFirstChild("IntroGui") then finish(false) end

task.spawn(function()
	local started = os.clock()
	while not done and os.clock() - started < 30 do
		local zone = player:GetAttribute("Zone")
		if zone ~= nil and zone ~= "Lobby" then break end -- (마을이 아닌 곳에서 시작: 오프닝이 없다)
		task.wait(0.2)
	end
	finish(true)
end)
