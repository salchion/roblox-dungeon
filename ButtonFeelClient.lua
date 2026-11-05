-- ButtonFeelClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: ButtonFeelClient)
-- 화면 전체 손맛 / 가독성 보정 (개별 화면 코드는 건드리지 않는다):
--   1) 모든 버튼: 누르는 순간 살짝 작아졌다가 떼면 통통 튀며 돌아온다.
--      (투명한 클릭 영역 / 화면 전체를 덮는 막 / 속성 "NoPress" 가 켜진 버튼은 제외)
--   2) 월드에 떠 있는 글자(BillboardGui: 이름표 / 떠오르는 글자)에 밝은 글자는 어두운 외곽선을 더해 배경에 묻히지 않게 한다.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PRESS_IN = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_OUT = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function pressable(button)
	if button:GetAttribute("NoPress") then return false end
	local size = button.AbsoluteSize
	if size.X > 700 or size.Y > 450 then return false end -- 화면을 덮는 막 / 큰 영역
	if button.BackgroundTransparency >= 0.99 and button:IsA("TextButton") and button.Text == "" then return false end -- 눈에 안 보이는 클릭 영역
	return true
end

local function pressScale(button)
	local scale = button:FindFirstChild("PressScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "PressScale"
		scale.Parent = button
	end
	return scale
end

local function attachButton(button)
	if button:GetAttribute("PressWired") then return end
	button:SetAttribute("PressWired", true)
	button.MouseButton1Down:Connect(function()
		if not pressable(button) then return end
		TweenService:Create(pressScale(button), PRESS_IN, { Scale = 0.94 }):Play()
	end)
	local function release()
		local scale = button:FindFirstChild("PressScale")
		if scale and scale.Scale ~= 1 then
			TweenService:Create(scale, PRESS_OUT, { Scale = 1 }):Play()
		end
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
end

local function brightEnough(color)
	return (color.R * 0.3 + color.G * 0.59 + color.B * 0.11) > 0.45
end

local function fixWorldText(label)
	if label.TextStrokeTransparency < 0.95 or label.BackgroundTransparency < 0.99 or label.TextTransparency > 0.6 then return end
	if not label:FindFirstAncestorWhichIsA("BillboardGui") then return end
	if not brightEnough(label.TextColor3) then return end
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.45
end

local function handle(instance)
	if instance:IsA("GuiButton") then
		attachButton(instance)
	elseif instance:IsA("TextLabel") then
		task.defer(fixWorldText, instance)
	end
end

for _, descendant in ipairs(playerGui:GetDescendants()) do
	handle(descendant)
end
playerGui.DescendantAdded:Connect(handle)
