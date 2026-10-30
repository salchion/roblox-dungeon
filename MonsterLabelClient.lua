-- MonsterLabelClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: MonsterLabelClient)
-- 몬스터 이름표 색 = "내 전투력 vs 그 구역 권장 전투력". 레벨 숫자 대신 "지금 이 몹을 잡아도 되는가"를 색으로 알려 준다.
--   빨강: 내가 많이 약함 / 주황: 약간 약함 / 흰색: 적정 / 회색: 훨씬 강함 (엘리트는 적정 이상이면 금색)
-- 서버(FieldService)가 몬스터 부품에 MobZone / MobKind Attribute 를 붙여 둔다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local player = Players.LocalPlayer

local RED, ORANGE, WHITE, GRAY, GOLD = Color3.fromRGB(255, 105, 105), Color3.fromRGB(255, 185, 100), Color3.new(1, 1, 1), Color3.fromRGB(165, 168, 180), Color3.fromRGB(255, 220, 90)
local lastColor = setmetatable({}, { __mode = "k" })

-- 폰(터치 화면): 몬스터 체력바가 화면에 비해 너무 두껍고 넓어서, 처음 한 번 줄인다 (서버가 만든 BillboardGui 의 크기만 바꾼다. 보스처럼 폭이 큰 것은 더 줄인다)
local UserInputService = game:GetService("UserInputService")
local COMPACT = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local slimmed = setmetatable({}, { __mode = "k" })
local function slimBar(part)
	if slimmed[part] then return end
	local gui = part:FindFirstChildOfClass("BillboardGui")
	if not gui then return end
	slimmed[part] = true
	local width = gui.Size.X.Offset
	local big = width >= 300
	gui.Size = UDim2.new(0, math.floor(width * (big and 0.5 or 0.62)), 0, big and 22 or 18)
	for _, child in ipairs(gui:GetChildren()) do
		if child:IsA("TextLabel") then
			child.Size = UDim2.new(1, 0, big and 0.66 or 0.72, 0)
		elseif child:IsA("Frame") then
			child.Size = UDim2.new(1, 0, big and 0.26 or 0.2, 0)
			child.Position = UDim2.new(0, 0, big and 0.74 or 0.8, 0)
		end
	end
end

local function colorFor(ratio, elite)
	if ratio < 0.6 then return RED end
	if ratio < 1 then return ORANGE end
	if ratio >= 4 then return GRAY end
	return elite and GOLD or WHITE
end

while true do
	task.wait(0.5)
	local camera = workspace.CurrentCamera
	local power = player:GetAttribute("Power")
	if camera and power then
		local origin = camera.CFrame.Position
		for _, part in ipairs(CollectionService:GetTagged("Monster")) do
			local zone, kind = part:GetAttribute("MobZone"), part:GetAttribute("MobKind")
			if COMPACT then slimBar(part) end
			if zone and (kind == "Normal" or kind == "Elite") and (part.Position - origin).Magnitude < 160 then
				local need = Config.Field.RecommendPower[zone]
				local gui = part:FindFirstChildOfClass("BillboardGui")
				local label = gui and gui:FindFirstChildOfClass("TextLabel")
				if need and label then
					local color = colorFor(power / need, kind == "Elite")
					if lastColor[part] ~= color then
						lastColor[part] = color
						label.TextColor3 = color
					end
				end
			end
		end
	end
end
