-- ButtonFeelClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: ButtonFeelClient)
-- (이름은 예전 그대로 둔다: 이미 설치된 스크립트를 덮어쓰려고. 버튼 눌림 / 팝업 효과는 UiPolishClient 가 이미 하므로 여기서는 하지 않는다.)
-- 월드에 떠 있는 글자(BillboardGui: 이름표 / 떠오르는 글자)에 밝은 글자는 어두운 외곽선을 더해 배경에 묻히지 않게 한다.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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
	if instance:IsA("TextLabel") then
		task.defer(fixWorldText, instance)
	end
end

-- 화면(PlayerGui) + 월드(workspace): 몬스터 이름표 / 떠오르는 글자 BillboardGui 는 대부분 월드의 부품 아래에 있다
for _, root in ipairs({ playerGui, workspace }) do
	for _, descendant in ipairs(root:GetDescendants()) do
		handle(descendant)
	end
	root.DescendantAdded:Connect(handle)
end
