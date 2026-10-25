-- DamageGuard (ServerScriptService > Modules 안의 ModuleScript, 이름: DamageGuard)
-- 플레이어가 받는 모든 피해가 지나가는 곳: 방어력(피해 감소) + 한 번에 맞는 피해 상한.
--   * 방어력 = 레벨 x LevelDef + 장비 최대 체력 x GearDef  ->  피해 감소 = 방어력 / (방어력 + K)  (최대 MaxReduction)
--   * 한 방은 최대 체력의 HitCap 을 넘지 못한다 (공격력만 오르고 체력은 안 오르는 후반에 한두 방에 죽는 것을 막는다)
-- 몬스터 / 보스가 플레이어에게 주는 피해는 humanoid:TakeDamage 대신 Guard.Take(humanoid, amount) 를 쓴다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Guard = {}

function Guard.Reduction(player)
	local C = Config.Defense
	local defense = (player:GetAttribute("Level") or 1) * C.LevelDef + (player:GetAttribute("GearHealth") or 0) * C.GearDef
	return math.min(C.MaxReduction, defense / (defense + C.K))
end

function Guard.Take(humanoid, amount)
	if not humanoid or humanoid.Health <= 0 then return end
	local player = humanoid.Parent and Players:GetPlayerFromCharacter(humanoid.Parent)
	if player then
		amount = amount * (1 - Guard.Reduction(player)) * (1 - (player:GetAttribute("GearBulwark") or 0)) -- (유니크 "Bulwark")
		amount *= 1 - Config.Newbie.Defense * Config.NewbieStrength(player) -- 초보자 가호: 초반에는 받는 피해가 줄어든다
		if (player:GetAttribute("RiftLeft") or 0) <= 0 then -- (보스러쉬 중에는 상한이 없다: 체력이 낮은 사람이 상한 덕에 유리해지면 순위가 불공정해진다)
			amount = math.min(amount, humanoid.MaxHealth * Config.Defense.HitCap)
		end
	end
	if amount > 0 then
		humanoid:TakeDamage(amount)
	end
end

-- 화면 표시용: 피해 감소 % 를 Attribute 로 둔다 (스탯 / 메뉴에서 읽을 수 있다)
local function publish(player)
	player:SetAttribute("DamageReduction", math.floor(Guard.Reduction(player) * 1000 + 0.5) / 10)
end
local function watch(player)
	publish(player)
	player:GetAttributeChangedSignal("Level"):Connect(function() publish(player) end)
	player:GetAttributeChangedSignal("GearHealth"):Connect(function() publish(player) end)
end
Players.PlayerAdded:Connect(watch)
for _, player in ipairs(Players:GetPlayers()) do watch(player) end

return Guard
