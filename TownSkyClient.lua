-- TownSkyClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: TownSkyClient)
-- 마을 하늘의 볼거리를 움직인다: 하늘에 걸린 거대한 고리(SkyHalo)는 천천히 돌고, 떠 있는 섬(FloatIsland*)과 광장 위 수정(SkyCrystal)은 위아래로 일렁이며 돈다.
-- 모양은 서버(LobbyDecor 의 "Spectacle" 구역)가 만들어 두고, 여기서는 모델 몇 개의 위치만 매 프레임 옮긴다 (부품 수십 개를 하나씩 건드리지 않는다).
-- Attribute: Spin = 초당 회전(라디안) / Bob = 위아래 흔들림 크기 / Phase = 흔들림 시작 위치. 저사양 모드(LowSpec)에서는 멈춘다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local items = {} -- [Model] = 처음 자리(CFrame)

local function add(model)
	if model:IsA("Model") and not items[model] then
		local ok, pivot = pcall(function() return model:GetPivot() end)
		if ok then items[model] = pivot end
	end
end
for _, model in ipairs(CollectionService:GetTagged("TownSky")) do add(model) end
CollectionService:GetInstanceAddedSignal("TownSky"):Connect(add)
CollectionService:GetInstanceRemovedSignal("TownSky"):Connect(function(model) items[model] = nil end)

local clock = 0
RunService.Heartbeat:Connect(function(dt)
	if player:GetAttribute("LowSpec") then return end
	clock += dt
	for model, home in pairs(items) do
		if not model.Parent then
			items[model] = nil
		else
			local spin = model:GetAttribute("Spin") or 0
			local bob = model:GetAttribute("Bob") or 0
			local phase = model:GetAttribute("Phase") or 0
			local lift = bob > 0 and math.sin(clock * 0.6 + phase) * bob or 0
			model:PivotTo(home * CFrame.Angles(0, clock * spin, 0) + Vector3.new(0, lift, 0))
		end
	end
end)
