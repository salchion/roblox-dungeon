-- DamageGuard (ServerScriptService > Modules 안의 ModuleScript, 이름: DamageGuard)
-- 플레이어가 받는 모든 피해가 지나가는 곳: 방어력(피해 감소) + 세트 효과 "폭풍의 방벽" 반감.
--   * 방어력 = 레벨 x LevelDef + 장비 최대 체력 x GearDef  ->  피해 감소 = 방어력 / (방어력 + K)  (최대 MaxReduction)
--   * 한 방 상한은 없다 (2026-11-16 종태 님 결정: 상한 대신 폭풍의 방벽 반감으로 버틴다)
-- 몬스터 / 보스가 플레이어에게 주는 피해는 humanoid:TakeDamage 대신 Guard.Take(humanoid, amount) 를 쓴다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Guard = {}

function Guard.Reduction(player)
	local C = Config.Defense
	local defense = (player:GetAttribute("Level") or 1) * C.LevelDef + (player:GetAttribute("GearHealth") or 0) * C.GearDef
	return Config.SoftCap(defense / (defense + C.K), C.MaxReduction) -- (상한에서 잘리지 않고 점점 다가간다: 장비 체력을 더 모아도 방어가 계속 조금씩 오른다)
end

function Guard.Take(humanoid, amount)
	if not humanoid or humanoid.Health <= 0 then return end
	local player = humanoid.Parent and Players:GetPlayerFromCharacter(humanoid.Parent)
	if player then
		if (player:GetAttribute("GearShield") or 0) > 0 then -- 유니크 "Bulwark": 보호막이 있으면 이번 공격을 완전히 막는다
			local okU, Unique = pcall(function() return require(script.Parent:WaitForChild("UniqueService")) end)
			if okU and Unique.TryShield(player) then return end
		end
		amount = amount * (1 - Guard.Reduction(player)) * (1 - (player:GetAttribute("GearBulwark") or 0)) * (1 - (player:GetAttribute("TrainBulwark") or 0)) -- (유니크 "Bulwark" / 훈련 "질긴 피부")
		amount *= 1 - Config.Newbie.Defense * Config.NewbieStrength(player) -- 초보자 가호: 초반에는 받는 피해가 줄어든다
		amount *= 1 - math.min(0.5, Config.TalentMod(player, "DmgReduce")) -- 특성 "강철 위장"
		local rushGuard = Config.TalentMod(player, "RushGuard")
		if rushGuard > 0 then -- 특성 "돌격 방어": 대시 뒤 2초 동안 받는 피해 감소
			local okN, NearMiss = pcall(function() return require(script.Parent:WaitForChild("NearMissService")) end)
			if okN and NearMiss.SinceDash and NearMiss.SinceDash(player) < 2 then amount *= 1 - rushGuard end
		end
		local ward = player:GetAttribute("AugWard") or 0 -- 세트 효과 "폭풍의 방벽": 받는 피해를 % 로 줄인다 (모든 감소가 끝난 뒤 곱한다)
		if player:GetAttribute("TutorialDoom") == true then ward = 0 end -- (튜토리얼 최후의 군주는 지게 되어 있는 장면)
		amount *= 1 - Config.WardReduce(ward)
		if amount > 0 and ward >= 4 then -- 4단계부터: 맞으면 번개로 되받아친다 (3초에 한 번)
			local now = workspace:GetServerTimeNow()
			if now >= (player:GetAttribute("WardBackAt") or 0) then
				player:SetAttribute("WardBackAt", now + 3)
				task.spawn(function()
					local okD, Dungeon = pcall(function() return require(script.Parent:WaitForChild("DungeonService")) end)
					local okF, Field = pcall(function() return require(script.Parent:WaitForChild("FieldService")) end)
					if not okD then return end
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if not root then return end
					local tier = math.min(6, ward)
					local damage = math.max(1, math.floor(Dungeon.ComputeSetBase(player) * ({ [4] = 0.6, [5] = 0.8, [6] = 1.0 })[tier]))
					local okE, Effects = pcall(function() return require(script.Parent:WaitForChild("Effects")) end)
					if okE then Effects.Burst(root.Position, Color3.fromRGB(170, 190, 255), 30) end
					-- (대상 수 4/5/6: AreaDamage 가 마리 수를 못 받아서, 반경을 단계별로 줄여 비슷하게 맞춘다 = 반경 16 기준 x0.8 / 0.9 / 1.0)
					local radius = 16 * ({ [4] = 0.8, [5] = 0.9, [6] = 1.0 })[tier]
					local hit = Dungeon.AreaDamage(player, root.Position, radius, damage)
					if not hit and okF then Field.AreaDamage(player, root.Position, radius, damage) end
				end)
			end
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
