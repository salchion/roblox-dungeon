-- UiPolishClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: UiPolishClient)
-- 모든 화면(PlayerGui)에 공통으로 손맛을 더한다. 다른 스크립트는 건드리지 않는다.
--   1) 큰 창이 열릴 때: 0.15초 동안 살짝 작았다가 커지며 나타난다 (갑자기 툭 뜨지 않게)
--   2) 버튼을 누를 때: 살짝 눌렸다 튀어 오른다 + 작은 "틱" 소리 (모든 버튼이 같은 반응)
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
local function watchWindow(frame)
	if watchedWindow[frame] then return end
	watchedWindow[frame] = true
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			task.defer(popIn, frame) -- (크기가 정해진 다음 프레임에 잰다)
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
			pcall(function() SoundBank.Play(sfxParent, "Gacha_Tick", { Pitch = 1.25, Volume = 0.35 }) end)
		end
	end)
end

------------------------------------------------------------
-- 화면 전체를 지켜본다: 지금 있는 것 + 새로 생기는 것
------------------------------------------------------------
local function consider(obj)
	if obj:IsA("GuiButton") then
		watchButton(obj)
	elseif obj:IsA("Frame") and obj.Parent and obj.Parent:IsA("ScreenGui") then -- (화면 바로 아래의 큰 틀만 창으로 본다)
		watchWindow(obj)
	end
end

local function watchGui(gui)
	if not gui:IsA("ScreenGui") then return end
	for _, obj in ipairs(gui:GetDescendants()) do consider(obj) end
	gui.DescendantAdded:Connect(function(obj) task.defer(consider, obj) end)
end

for _, gui in ipairs(playerGui:GetChildren()) do watchGui(gui) end
playerGui.ChildAdded:Connect(watchGui)
