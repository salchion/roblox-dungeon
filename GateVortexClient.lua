-- GateVortexClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: GateVortexClient)
-- 마을 던전 문의 "소용돌이"를 내 화면에서만 움직인다 (LobbyService 가 부품을 만들고 "GateVortex" 태그를 붙여 둔다).
--   * 팔 6가닥이 천천히 돌고, 바깥 고리가 안쪽으로 줄어들며 사라진다 -> 문 속으로 빨려 들어가는 느낌.
--   * 카메라에서 220칸 안에 있을 때만, 마을에 있을 때만 움직인다 (먼 문 / 던전 / 필드에서는 계산하지 않는다).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local entries = {} -- [model] = { Base = CFrame, Rings = { part } }

local function register(model)
	if entries[model] or not model.PrimaryPart then return end
	local rings = {}
	for _, item in ipairs(model:GetDescendants()) do
		if item.Name == "VortexRing" and item:IsA("BasePart") then table.insert(rings, item) end
	end
	entries[model] = { Base = model.PrimaryPart.CFrame, Rings = rings }
end

local function tryRegister(model)
	task.defer(function()
		if model:IsDescendantOf(workspace) then register(model) end
	end)
end
for _, model in ipairs(CollectionService:GetTagged("GateVortex")) do tryRegister(model) end
CollectionService:GetInstanceAddedSignal("GateVortex"):Connect(tryRegister)
CollectionService:GetInstanceRemovedSignal("GateVortex"):Connect(function(model) entries[model] = nil end)

RunService.RenderStepped:Connect(function()
	if next(entries) == nil or player:GetAttribute("Zone") ~= "Lobby" then return end
	local camera = workspace.CurrentCamera
	if not camera then return end
	local cameraPosition = camera.CFrame.Position
	local t = os.clock()
	for model, entry in pairs(entries) do
		if not model.Parent then
			entries[model] = nil
		elseif (entry.Base.Position - cameraPosition).Magnitude < 220 then
			model:PivotTo(entry.Base * CFrame.Angles(0, 0, t * 1.1))
			for _, ring in ipairs(entry.Rings) do
				local phase = ring:GetAttribute("Phase") or 0
				local diameter = ring:GetAttribute("Diameter") or 12
				local s = 1 - ((t * 0.45 + phase) % 1) -- 1(바깥) -> 0(한가운데)
				local size = math.max(0.3, diameter * (0.15 + 0.85 * s))
				ring.Size = Vector3.new(0.12, size, size)
				ring.Transparency = 0.35 + 0.65 * (1 - s) ^ 1.5
			end
		end
	end
end)
