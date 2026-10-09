-- MonsterSmoothClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: MonsterSmoothClient)
-- 서버가 몬스터(고정된 부품)를 움직이면 위치가 약 20번/초로만 도착해서 화면에서 툭툭 순간이동처럼 보인다.
-- 내 화면에서만, 도착한 위치를 향해 부드럽게 따라가게 해서 끊김을 없앤다. (서버 판정 / 맞는 위치는 그대로)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local FOLLOW = 22 -- 클수록 빨리 따라간다 (약 0.05초 뒤처짐)
local MAX_DIST = 220 -- 이보다 먼 몬스터는 어차피 작게 보여서 그대로 둔다
local SNAP = 25 -- 한 번에 이만큼 이상 움직이면(순간이동 / 리스폰) 따라가지 않고 바로 맞춘다

local bodies = {}
local state = setmetatable({}, { __mode = "k" }) -- [몸체] = { Shown = 내가 마지막으로 쓴 위치, Goal = 서버가 보낸 위치 }

local function track(part)
	if part:IsA("BasePart") then bodies[part] = true end
end
for _, part in ipairs(CollectionService:GetTagged("Monster")) do track(part) end
CollectionService:GetInstanceAddedSignal("Monster"):Connect(track)
CollectionService:GetInstanceRemovedSignal("Monster"):Connect(function(part)
	bodies[part] = nil
	state[part] = nil
end)

RunService.PreRender:Connect(function(dt)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local origin = root.Position
	local alpha = 1 - math.exp(-FOLLOW * dt)
	for part in pairs(bodies) do
		if not part.Parent then
			bodies[part] = nil
		elseif part.Anchored and (part.Position - origin).Magnitude < MAX_DIST then
			local now = part.CFrame
			local s = state[part]
			if not s then
				state[part] = { Shown = now, Goal = now }
			else
				if now ~= s.Shown then s.Goal = now end -- 서버에서 새 위치가 도착했다
				if (s.Goal.Position - s.Shown.Position).Magnitude > SNAP then
					s.Shown = s.Goal
				else
					s.Shown = s.Shown:Lerp(s.Goal, alpha)
				end
				if s.Shown ~= now then part.CFrame = s.Shown end
			end
		else
			state[part] = nil
		end
	end
end)
