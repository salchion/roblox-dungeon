-- DamageGuard (ServerScriptService > Modules 안의 ModuleScript, 이름: DamageGuard)
-- 플레이어가 받는 모든 피해가 지나가는 곳: 방어력(피해 감소) + 방어 기재(방벽 / 회피 / 불굴 / 완충, 재생은 아래 루프).
--   * 방어력 = 레벨 x LevelDef + 장비 최대 체력 x GearDef  ->  피해 감소 = 방어력 / (방어력 + K)  (최대 MaxReduction)
--   * 한 방 상한은 없다 (2026-11-16 종태 님 결정: 상한 대신 폭풍의 방벽 반감으로 버틴다)
--   * 피해는 전부 적 공격력 / 구역 고정 절대값이다 — 내 최대 체력에 비례하는 피해는 11-24 에 모두 없앴다
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

-- 사망 원인 기록 (DeathLog 가 읽는다): 플레이어마다 최근 피해 5건 = { 출처("스크립트:줄" / "judge" ...), 양, 남은 체력 %, 시각 }
local recent = setmetatable({}, { __mode = "k" })
-- 받는 피해 배율 (필드 2축 신호의 "한 방 %"용): 항상 걸리는 감소만 곱한다 = 방어력 · 유니크 Bulwark · 훈련 질긴 피부 · 초보자 가호 · 특성 강철 위장 · 🛡 방벽
--   (회피 / 불굴 / 완충 / 돌격 방어처럼 확률 · 체력 · 시간에 따라 바뀌는 것은 뺀다). Take 와 같은 순서 / 같은 식
function Guard.TakenMult(player)
	local mult = (1 - Guard.Reduction(player)) * (1 - (player:GetAttribute("GearBulwark") or 0)) * (1 - (player:GetAttribute("TrainBulwark") or 0))
	mult *= 1 - Config.Newbie.Defense * Config.NewbieStrength(player)
	mult *= 1 - math.min(0.5, Config.TalentMod(player, "DmgReduce"))
	if player:GetAttribute("TutorialDoom") ~= true then mult *= math.max(1 - Config.AugSlots.DefenseCap, 1 - Config.Guard.Ward(player:GetAttribute("AugWard") or 0) * (player:GetAttribute("AugMul_AugWard") or 1)) end
	return mult
end

function Guard.Note(humanoid, source, amount)
	local player = humanoid and humanoid.Parent and Players:GetPlayerFromCharacter(humanoid.Parent)
	if not player or not amount or amount <= 0 then return end
	local list = recent[player] or {}
	recent[player] = list
	local left = humanoid.MaxHealth > 0 and math.max(0, humanoid.Health - amount) / humanoid.MaxHealth or 0
	table.insert(list, { Source = source or "?", Amount = math.floor(amount + 0.5), Left = math.floor(left * 100 + 0.5), At = os.clock() })
	while #list > 5 do table.remove(list, 1) end
end
function Guard.RecentOf(player) return recent[player] or {} end
local function callerOf() -- Take 를 부른 곳 ("FieldBossPatterns:812"). DamageGuard 안에서 한 번 더 감싸 부르면 그 바깥 칸의 이름을 쓴다
	for level = 3, 5 do
		local src, line = debug.info(level, "sl")
		if not src then break end
		local name = string.match(src, "([^%.]+)$") or src
		if name ~= "DamageGuard" then return string.format("%s:%d", name, line or 0) end
	end
	return "?"
end

function Guard.Take(humanoid, amount, pierce)
	if not humanoid or humanoid.Health <= 0 then return end
	local player = humanoid.Parent and Players:GetPlayerFromCharacter(humanoid.Parent)
	if player then
		if (player:GetAttribute("GearShield") or 0) > 0 then -- 유니크 "Bulwark": 보호막이 있으면 이번 공격을 완전히 막는다
			local okU, Unique = pcall(function() return require(script.Parent:WaitForChild("UniqueService")) end)
			if okU and Unique.TryShield(player) then return end
		end
		local reduce = Guard.Reduction(player)
		if pierce and pierce > 0 then reduce *= 1 - pierce end -- (강공격 T3: 피해 감소의 일부를 무시한다 — Config.Threat.Pierce)
		amount = amount * (1 - reduce) * (1 - (player:GetAttribute("GearBulwark") or 0)) * (1 - (player:GetAttribute("TrainBulwark") or 0)) -- (유니크 "Bulwark" / 훈련 "질긴 피부")
		amount *= 1 - Config.Newbie.Defense * Config.NewbieStrength(player) -- 초보자 가호: 초반에는 받는 피해가 줄어든다
		amount *= 1 - math.min(0.5, Config.TalentMod(player, "DmgReduce")) -- 특성 "강철 위장"
		local rushGuard = Config.TalentMod(player, "RushGuard")
		if rushGuard > 0 then -- 특성 "돌격 방어": 대시 뒤 2초 동안 받는 피해 감소
			local okN, NearMiss = pcall(function() return require(script.Parent:WaitForChild("NearMissService")) end)
			if okN and NearMiss.SinceDash and NearMiss.SinceDash(player) < 2 then amount *= 1 - rushGuard end
		end
		-- 방어 기재 (세트 효과 칸을 같이 쓴다: Config.Guard). 튜토리얼 최후의 군주는 지게 되어 있는 장면이라 끈다
		local G = Config.Guard
		local off = player:GetAttribute("TutorialDoom") == true
		local function lv(attr) return off and 0 or (player:GetAttribute(attr) or 0) end
		local function mul(attr) return player:GetAttribute("AugMul_" .. attr) or 1 end -- (칸 강화 +3%/단계 · +5 방어 +20% · 방어 2번째 60%: AugService)
		if math.random() < G.Evade(lv("AugEvade")) * mul("AugEvade") then -- 🌀 회피: 이번 공격을 통째로 피한다
			local root = humanoid.Parent and humanoid.Parent:FindFirstChild("HumanoidRootPart")
			if root then
				local okE, Effects = pcall(function() return require(script.Parent:WaitForChild("Effects")) end)
				if okE then Effects.FloatText(root.Position + Vector3.new(0, 4, 0), "MISS!", Color3.fromRGB(140, 240, 220)) end
			end
			return
		end
		local keep = 1 - G.Ward(lv("AugWard")) * mul("AugWard") -- 🛡 방벽: 받는 피해 % 감소
		local lo, hi = G.Grit(lv("AugGrit")) -- 🔥 불굴: 체력이 낮을수록 덜 받는다
		local ratio = humanoid.MaxHealth > 0 and humanoid.Health / humanoid.MaxHealth or 1
		if ratio < 0.25 then keep *= 1 - hi * mul("AugGrit") elseif ratio < 0.5 then keep *= 1 - lo * mul("AugGrit") end
		amount *= math.max(1 - Config.AugSlots.DefenseCap, keep) -- (세트 방어 효과 감소 총합 상한 55%)
		player:SetAttribute("LastHurtAt", workspace:GetServerTimeNow()) -- (💚 재생은 맞은 뒤 2초 쉰다)
		Guard.Note(humanoid, callerOf(), amount)
		local buffer = math.min(0.9, G.Buffer(lv("AugBuffer")) * mul("AugBuffer")) -- ⏳ 완충: 일부를 3초(0.5초 x 6번)에 나눠 받는다
		if buffer > 0 and amount > 0 then
			local later = amount * buffer
			amount -= later
			task.spawn(function()
				for _ = 1, 6 do
					task.wait(0.5)
					if humanoid.Parent and humanoid.Health > 0 then humanoid:TakeDamage(later / 6) end
				end
			end)
		end
	end
	if amount > 0 and player and amount >= humanoid.Health and (player:GetAttribute("RunLastStand") or 0) > 0 then
		-- 🔰 버티기 (던전 드래프트): 죽을 만큼의 한 방을 체력 1로 버티고 2초 무적
		player:SetAttribute("RunLastStand", player:GetAttribute("RunLastStand") - 1)
		humanoid.Health = 1
		local ff = Instance.new("ForceField")
		ff.Visible = true
		ff.Parent = humanoid.Parent
		game:GetService("Debris"):AddItem(ff, 2)
		local root = humanoid.Parent:FindFirstChild("HumanoidRootPart")
		if root then
			local okE, Effects = pcall(function() return require(script.Parent:WaitForChild("Effects")) end)
			if okE then Effects.FloatText(root.Position + Vector3.new(0, 4, 0), "LAST STAND!", Color3.fromRGB(255, 220, 120)) end
		end
		return
	end
	if amount > 0 then
		humanoid:TakeDamage(amount)
	end
end

-- 💚 재생: 필드 / 던전에서 1초마다 최대 체력의 % 회복 (맞은 뒤 2초는 쉰다)
task.spawn(function()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			local okT, taken = pcall(Guard.TakenMult, player) -- 받는 피해 배율 (FieldSignal 이 읽는다)
			if okT and taken then
				taken = math.floor(taken * 1000 + 0.5) / 1000
				if player:GetAttribute("TakenMult") ~= taken then player:SetAttribute("TakenMult", taken) end
			end
			local level = player:GetAttribute("AugRegen") or 0
			local zone = player:GetAttribute("Zone")
			local runRegen = zone == "Dungeon" and (player:GetAttribute("RunRegen") or 0) or 0 -- (🌿 드래프트 재생: 던전 안에서만, 맞은 뒤에도 쉬지 않는다)
			local rested = workspace:GetServerTimeNow() - (player:GetAttribute("LastHurtAt") or 0) >= 2
			local rate = ((level > 0 and rested) and Config.Guard.Regen(level) * (player:GetAttribute("AugMul_AugRegen") or 1) or 0) + runRegen
			if rate > 0 and (zone == "Field" or zone == "Dungeon") then
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
					humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * rate)
				end
			end
		end
	end
end)

-- (11-24 종태 님: "대미지에 퍼센트 개념은 없었으면 좋겠어") 내 최대 체력 비율로 주는 피해는 모두 없앴다.
--   예전 Guard.TakeRatio / BaseMaxHealth (최후의 군주 · 보스러쉬 링)는 각자 고정 절대값으로 바뀌었고, 함수도 지웠다.

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
