-- TownFlickerClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: TownFlickerClient)
-- 마을의 불빛(따뜻한 색 PointLight, 태그 "TownFlicker")이 촛불처럼 은은하게 일렁인다. 밝기만 ±10% 정도 흔들고 색 / 위치는 그대로.
-- 서버는 태그만 붙인다 (움직임은 각자 화면에서). 저사양 모드에서는 가만히 둔다.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local lights = {} -- [PointLight] = { Base = 원래 밝기, Seed = 불빛마다 다른 값 }

local function add(light)
	if not light:IsA("PointLight") or lights[light] then return end
	lights[light] = { Base = light.Brightness, Seed = math.random() * 100 }
	light.AncestryChanged:Connect(function()
		if not light:IsDescendantOf(game) then lights[light] = nil end
	end)
end

for _, light in ipairs(CollectionService:GetTagged("TownFlicker")) do add(light) end
CollectionService:GetInstanceAddedSignal("TownFlicker"):Connect(add)

local clock = 0
RunService.Heartbeat:Connect(function(dt)
	if player:GetAttribute("LowSpec") then return end
	clock += dt
	for light, info in pairs(lights) do
		if light.Enabled then
			local n = math.noise(clock * 2.2 + info.Seed, info.Seed) * 0.65 + math.noise(clock * 7.5, info.Seed * 2) * 0.35
			light.Brightness = info.Base * (1 + n * 0.2)
		end
	end
end)
