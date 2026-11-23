-- ThreatService (ServerScriptService > Modules 안의 ModuleScript, 이름: ThreatService)
-- 강공격(위협 티어 3)의 판정을 한 곳에 모은다 (11-24 종태 님 + 클로드 합의).
--   1) 완벽 회피: 예고의 마지막 구간(기본 25% / 터치 화면 35%)이 시작될 때 범위 안에 있던 사람이,
--      공격이 들어가는 순간 범위 밖이고 그 구간 안에서 대시를 시작했으면 피해 0 + 보상(NearMiss.Perfect).
--      -> "그냥 범위 밖에 있던 사람" / "일찍 걸어서 나간 사람"은 완벽 회피가 아니다 (학습이 되게).
--   2) 상태이상: T3에 맞으면 Config.Threat.Status.Kind 표대로 화상 / 둔화 / 감전 (StatusService).
--   3) 피해 감소 일부 무시: T3는 방어 피해 감소의 20%를 무시한다 (한 방 상한은 없다 — 11-24 종태 님: 대미지에 % 개념 없이).
-- 각 공격 지점은 세 함수만 부르면 된다: Threat.Arm(예고 시작) / Threat.Hit(맞음) / Threat.Escaped(안 맞음).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Guard = require(script.Parent:WaitForChild("DamageGuard"))
local NearMiss = require(script.Parent:WaitForChild("NearMissService"))
local Status = require(script.Parent:WaitForChild("StatusService"))

local Threat = {}

-- [part] = { Area, Inside = { [humanoid] = true }, Since = os.clock(), Delay = 초 }
local armed = setmetatable({}, { __mode = "k" })

local function windowFor(player, delay)
	local P = Config.Threat.Perfect
	local mobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	return delay * (mobile and P.MobileWindow or P.Window) + P.Extra
end

-- 범위 안인가 (여유 margin 포함). area: { Shape = "Disc", Center, Radius } 또는 { Shape = "Strip", Origin, Dir, Length, Width }
local function inside(area, position, margin)
	margin = margin or 0
	if area.Shape == "Strip" then
		local origin, dir = area.Origin, area.Dir
		if not origin or not dir then return false end
		local rel = position - origin
		local along = rel.X * dir.X + rel.Z * dir.Z
		local side = math.abs(rel.X * dir.Z - rel.Z * dir.X)
		return along >= -margin and along <= (area.Length or 60) + margin and side <= (area.Width or 10) / 2 + margin
	end
	local center = area.Center
	if not center then return false end
	local flat = Vector3.new(position.X - center.X, 0, position.Z - center.Z).Magnitude
	return flat <= (area.Radius or 0) + margin
end

-- 예고 시작할 때 한 번: 마지막 구간이 시작되는 순간의 "범위 안에 있던 사람"을 기록한다
function Threat.Arm(part, area, delay)
	if not part or not area then return end
	local P = Config.Threat.Perfect
	local token = { Area = area, Inside = {}, Since = os.clock(), Delay = delay }
	armed[part] = token
	local lastStart = math.max(0, delay * (1 - P.Window))
	task.delay(lastStart, function()
		if armed[part] ~= token or not part.Parent then return end
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 and inside(area, root.Position, 12) then -- (여유 12칸: 경계에서 대시로 빠지는 경우)
				token.Inside[humanoid] = true
			end
		end
	end)
	task.delay(math.max(0, delay) + 1.2, function() -- (공격이 안 나가도 남지 않게 정리)
		if armed[part] == token then armed[part] = nil end
	end)
	return token
end

-- 맞았다: T3 피해 (감소 일부 무시) + 상태이상
function Threat.Hit(part, entry, amount, key)
	if not entry or not entry.Humanoid then return end
	Guard.Take(entry.Humanoid, amount, Config.Threat.Pierce)
	local character = entry.Humanoid.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if player then
		local kind = Config.Threat.Status.Kind[key]
		if kind then Status.Apply(player, kind, amount) end -- (화상은 이 공격의 피해량 기준: StatusService)
	end
end

-- 안 맞았다: 마지막 구간에 안에 있다가 대시로 빠져나왔으면 완벽 회피 (한 공격에 한 번만)
function Threat.Escaped(part, entry)
	if not entry or not entry.Humanoid then return false end
	local token = armed[part]
	if not token then return false end
	local character = entry.Humanoid.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player or not token.Inside[entry.Humanoid] then return false end
	if NearMiss.SinceDash(player) > windowFor(player, token.Delay or 0) then return false end
	token.Inside[entry.Humanoid] = nil -- (탭마다 여러 번 인정되지 않게)
	NearMiss.Perfect(player)
	return true
end

return Threat
