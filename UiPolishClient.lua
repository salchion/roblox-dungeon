-- UiPolishClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: UiPolishClient)
-- 모든 화면(PlayerGui)에 공통으로 손맛을 더한다. 다른 스크립트는 건드리지 않는다.
--   1) 큰 창이 열릴 때: 0.15초 동안 살짝 작았다가 커지며 나타난다 (갑자기 툭 뜨지 않게)
--   2) 버튼을 누를 때: 살짝 눌렸다 튀어 오른다 + 작은 "틱" 소리 (모든 버튼이 같은 반응)
--   3) 큰 창이 닫힐 때: 같은 자리의 잔상이 작아지며 흐려진다 (창 자체는 다른 스크립트가 닫은 그대로)
--   4) 모양 통일: 테두리 / 광택이 없는 버튼과 창에만 공통 테마(굵은 외곽선 + 광택 + 둥근 모서리)를 입힌다
-- 이미 자기 UIScale 을 쓰는 창 / 버튼(메뉴 아이콘 줄 등)은 건드리지 않는다 (서로 크기를 덮어쓰지 않게).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local okSound, SoundBank = pcall(function() return require(ReplicatedStorage:WaitForChild("SoundBank", 10)) end)
local sfxParent = game:GetService("SoundService")

local POP_TIME = 0.15
local MIN_WINDOW = 300 -- 이보다 큰 창(가로 / 세로 둘 다)만 "창"으로 본다

local function ownScale(obj, name)
	local scale = obj:FindFirstChild(name)
	if scale then return scale end
	for _, child in ipairs(obj:GetChildren()) do
		if child:IsA("UIScale") then return nil end -- 다른 스크립트의 UIScale 이 있다: 건드리지 않는다
	end
	scale = Instance.new("UIScale")
	scale.Name = name
	scale.Parent = obj
	return scale
end

------------------------------------------------------------
-- 1) 창 열림
------------------------------------------------------------
local watchedWindow = setmetatable({}, { __mode = "k" })
local function popIn(frame)
	if frame.AbsoluteSize.X < MIN_WINDOW or frame.AbsoluteSize.Y < MIN_WINDOW then return end
	local scale = ownScale(frame, "PopScale")
	if not scale then return end
	scale.Scale = 0.9
	TweenService:Create(scale, TweenInfo.new(POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end
-- 닫힐 때: 창 자체는 바로 사라지고(다른 스크립트의 동작 그대로), 같은 자리 / 색의 "잔상"이 0.14초 동안 작아지며 흐려진다
local function ghostOut(frame)
	local screen = frame:FindFirstAncestorOfClass("ScreenGui")
	local size, position = frame.AbsoluteSize, frame.AbsolutePosition
	if not screen or size.X < MIN_WINDOW or size.Y < MIN_WINDOW then return end
	local ghost = Instance.new("Frame")
	ghost.Name = "CloseGhost"
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.Size = UDim2.fromOffset(size.X, size.Y)
	ghost.Position = UDim2.fromOffset(position.X - screen.AbsolutePosition.X + size.X / 2, position.Y - screen.AbsolutePosition.Y + size.Y / 2)
	ghost.BackgroundColor3 = frame.BackgroundColor3
	ghost.BackgroundTransparency = math.max(frame.BackgroundTransparency, 0.15)
	ghost.BorderSizePixel = 0
	ghost.ZIndex = frame.ZIndex + 20
	local corner = frame:FindFirstChildOfClass("UICorner")
	if corner then
		local copy = Instance.new("UICorner")
		copy.CornerRadius = corner.CornerRadius
		copy.Parent = ghost
	end
	ghost.Parent = screen
	TweenService:Create(ghost, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.fromOffset(size.X * 0.9, size.Y * 0.9), BackgroundTransparency = 1,
	}):Play()
	game:GetService("Debris"):AddItem(ghost, 0.2)
end
local function watchWindow(frame)
	if watchedWindow[frame] then return end
	watchedWindow[frame] = true
	local openedAt = 0
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			openedAt = os.clock()
			task.defer(popIn, frame) -- (크기가 정해진 다음 프레임에 잰다)
		elseif os.clock() - openedAt > 0.25 then -- (열리자마자 닫히는 깜빡임에는 잔상을 만들지 않는다)
			ghostOut(frame)
		end
	end)
end

------------------------------------------------------------
-- 2) 버튼 눌림
------------------------------------------------------------
local watchedButton = setmetatable({}, { __mode = "k" })
local lastClick = 0
local function watchButton(button)
	if watchedButton[button] then return end
	watchedButton[button] = true
	local scale
	local function huge() return button.AbsoluteSize.X > 600 or button.AbsoluteSize.Y > 400 end -- (화면을 덮는 투명 버튼 / 큰 판은 눌림 효과 / 소리 없이)
	local function press()
		if huge() then return end
		scale = scale or ownScale(button, "PressScale")
		if scale then TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.93 }):Play() end
	end
	local function release()
		if scale then TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play() end
	end
	button.MouseButton1Down:Connect(press)
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	button.Activated:Connect(function()
		if huge() then return end
		local now = os.clock()
		if okSound and now - lastClick > 0.06 then
			lastClick = now
			pcall(function() SoundBank.Play(sfxParent, "UI_Click", { Pitch = 1.25, Volume = 0.35 }) end)
		end
	end)
end

------------------------------------------------------------
-- 화면 전체를 지켜본다: 지금 있는 것 + 새로 생기는 것
------------------------------------------------------------
------------------------------------------------------------
-- 4) 모양 통일: 화면마다 따로 만든 버튼 / 창 중에 테두리 / 광택이 없는 것만 공통 테마(UiTheme)를 입힌다
--    (이미 자기 테두리나 그라데이션이 있는 것은 그대로 둔다: 일부러 꾸민 모양을 덮어쓰지 않게)
------------------------------------------------------------
local okTheme, Theme = pcall(function() return require(ReplicatedStorage:WaitForChild("UiTheme", 10)) end)
local INK = (okTheme and Theme and Theme.INK) or Color3.fromRGB(16, 12, 34)
local function hasChild(obj, className)
	return obj:FindFirstChildOfClass(className) ~= nil
end
local function styleButton(button)
	if button.BackgroundTransparency >= 0.85 then return end -- (투명 버튼: 아이콘 / 글자만 있는 버튼, 화면을 덮는 버튼)
	if button.AbsoluteSize.X > 600 or button.AbsoluteSize.Y > 400 then return end
	if not hasChild(button, "UICorner") then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = button
	end
	if hasChild(button, "UIStroke") or hasChild(button, "UIGradient") then return end
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.76, 0.76, 0.86))
	gradient.Rotation = 90
	gradient.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color, stroke.Thickness, stroke.ApplyStrokeMode = INK, 2, Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	if button:IsA("TextButton") and button.TextStrokeTransparency >= 1 then
		button.TextStrokeColor3 = INK
		button.TextStrokeTransparency = 0.45
	end
end
local function styleWindow(frame)
	if frame.BackgroundTransparency >= 0.85 then return end
	if frame.AbsoluteSize.X < MIN_WINDOW or frame.AbsoluteSize.Y < MIN_WINDOW then return end
	if frame.AbsoluteSize.X > 1600 then return end -- (화면 전체를 덮는 어두운 막은 창이 아니다)
	if not hasChild(frame, "UICorner") then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 14)
		corner.Parent = frame
	end
	if not hasChild(frame, "UIStroke") then
		local stroke = Instance.new("UIStroke")
		stroke.Color, stroke.Thickness = INK, 3
		stroke.Parent = frame
	end
end

local function consider(obj)
	if obj:IsA("GuiButton") then
		watchButton(obj)
		task.delay(0.1, function() if obj.Parent then pcall(styleButton, obj) end end) -- (크기 / 색이 정해진 뒤에)
	elseif obj:IsA("Frame") and obj.Parent and obj.Parent:IsA("ScreenGui") then -- (화면 바로 아래의 큰 틀만 창으로 본다)
		watchWindow(obj)
		local function tryStyle() if obj.Parent and obj.Visible then pcall(styleWindow, obj) end end
		task.delay(0.1, tryStyle)
		obj:GetPropertyChangedSignal("Visible"):Connect(function() task.defer(tryStyle) end) -- (처음엔 숨어 있던 창은 열릴 때)
	end
end

local function watchGui(gui)
	if not gui:IsA("ScreenGui") then return end
	for _, obj in ipairs(gui:GetDescendants()) do consider(obj) end
	gui.DescendantAdded:Connect(function(obj) task.defer(consider, obj) end)
end

for _, gui in ipairs(playerGui:GetChildren()) do watchGui(gui) end
playerGui.ChildAdded:Connect(watchGui)
