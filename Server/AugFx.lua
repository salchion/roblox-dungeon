-- AugFx (ServerScriptService > Modules 안의 ModuleScript, 이름: AugFx)
-- 👑 6부위 각성 8종 + 🔨 칸 +10 전용 효과 14종의 실제 동작 (11-25 확정 · Config.AugSlots / AugAwaken / AugSlotTen)
--   AugService 가 켜 두는 Attribute 만 읽는다: AugAwake_<효과> (6부위 각성) / AugTen_<효과> (그 효과가 든 칸 +10)
--   공격: DungeonService 가 효과마다 한 줄로 부른다 (각성 딜 = 그 효과가 방금 낸 피해 x 0.75 · 추가 동작은 세트 피해(hitMonster attr)로 들어간다)
--   방어: DamageGuard 가 부른다 (무적 / 버팀은 쿨타임마다 한 번 · 세트 방어 감소 상한 55% 는 DamageGuard 에 그대로)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Fx = {}
local api -- DungeonService 가 Init 으로 넣는다 (hitMonster / strikeBolt / launchMissile / launchBlast / dropMeteor / nearestMonsters / augDamage / addIgnite / Effects / sfxAt)
local AW = Config.AugSlots.AwakenMult -- 0.75

local function awake(player, attr) return player:GetAttribute("AugAwake_" .. attr) == true end
local function ten(player, attr) return player:GetAttribute("AugTen_" .. attr) == true end
local function live(run) return run and not run.Destroyed and run.Phase ~= "Ended" end

function Fx.Init(deps) api = deps return Fx end

------------------------------------------------------------ 공격
-- 💥 충격파: 각성 "여진" = 1초 뒤 같은 적들에게 한 번 더 (그 발동 전체의 75%) · +10 = 0.9초에 60% 짜리 충격파 한 번 더
function Fx.Pulse(run, player, blastDamage, blastRadius, targetCount, volleys)
	if not api then return end
	local function fire(delay, mult)
		task.delay(delay, function()
			if not live(run) then return end
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if not root then return end
			local hits = {}
			for _, entry in ipairs(api.nearestMonsters(run, root.Position, 75, targetCount)) do
				api.launchBlast(run, player, root.Position + Vector3.new(0, 3, 0), entry, blastDamage * mult, blastRadius, Color3.fromRGB(160, 255, 210), "AugPulse", hits)
			end
		end)
	end
	if awake(player, "AugPulse") then fire(1.0, AW * volleys) end
	if ten(player, "AugPulse") then fire(0.9, 0.6) end
end

-- 🌀 도탄 칼날: 각성 "칼날 폭풍" = 튕길 때마다 주변 2마리에 파편 (튕김마다 75%) · +10 = 마지막 튕김 자리 폭발 80%
function Fx.Orbit(run, player, chain, damage)
	if not api or #chain == 0 then return end
	local wake, finale = awake(player, "AugOrbit"), ten(player, "AugOrbit")
	if not wake and not finale then return end
	for index, entry in ipairs(chain) do
		task.delay((index - 1) * 0.2 + 0.32, function()
			if not live(run) or not entry.Part.Parent then return end
			local at = entry.Part.Position
			if wake then
				local near = api.nearestMonsters(run, at, 16, 2, entry.Part)
				for _, other in ipairs(near) do
					api.hitMonster(run, player, other, damage * AW / math.max(1, #near), nil, Color3.fromRGB(150, 240, 255), "AugOrbit")
				end
			end
			if finale and index == #chain then
				api.Effects.Raw(at, { "N", at, 12, Color3.fromRGB(110, 230, 255) })
				for _, other in ipairs(api.nearestMonsters(run, at, 12, 8)) do
					api.hitMonster(run, player, other, damage * 0.8, nil, Color3.fromRGB(150, 240, 255), "AugOrbit")
				end
			end
		end)
	end
end

-- 🌩 번개: 각성 "뇌운" = 발동 뒤 적 3마리에 낙뢰 (그 발동 전체의 75%) · +10 = 번개마다 2갈래 더 (60%)
function Fx.Storm(run, player, origin, boltDamage, targets, arcs)
	if not api then return end
	if awake(player, "AugStorm") then
		local total = boltDamage * targets * (1 + 0.6 * arcs) * AW
		task.delay(0.35, function()
			if not live(run) then return end
			local list = api.nearestMonsters(run, origin, 75, 3)
			for _, entry in ipairs(list) do api.strikeBolt(run, player, entry, total / math.max(1, #list), "AugStorm") end
		end)
	end
	if ten(player, "AugStorm") then
		for _, entry in ipairs(api.nearestMonsters(run, origin, 75, targets)) do
			for _, fork in ipairs(api.nearestMonsters(run, entry.Part.Position, 30, 2, entry.Part)) do
				api.strikeBolt(run, player, fork, boltDamage * 0.6, "AugStorm")
			end
		end
	end
end

-- 🚀 미사일: 각성 "집중 포화" = 소형 미사일 3발 (그 발동 전체의 75%)
function Fx.Missile(run, player, from, target, level, count)
	if not api or not awake(player, "AugMissile") then return end
	local total = api.augDamage(player) * (0.5 * count * (level >= 5 and 2 or 1) + (level >= 6 and 3 or 0)) * AW
	local list = api.nearestMonsters(run, target.Part.Position, 40, 3)
	if #list == 0 then list = { target } end
	for i = 1, 3 do
		local entry = list[(i - 1) % #list + 1]
		task.delay(0.5 + i * 0.08, function()
			if live(run) and entry.Part.Parent then api.launchMissile(run, player, from, entry, total / 3, "rocket", Color3.fromRGB(255, 170, 90), 1.4, nil, "AugMissile") end
		end)
	end
end

-- 처치 시: 🚀 +10 거대 미사일 (1초에 한 번)
local nextGiant = setmetatable({}, { __mode = "k" })
function Fx.OnKill(run, player, position)
	if not api or not ten(player, "AugMissile") or (player:GetAttribute("AugMissile") or 0) <= 0 then return end
	local now = os.clock()
	if now < (nextGiant[player] or 0) then return end
	nextGiant[player] = now + 1
	local target = api.nearestMonsters(run, position, 60, 1)[1]
	if target then api.launchMissile(run, player, position + Vector3.new(0, 10, 0), target, api.augDamage(player) * 3, "rocket", Color3.fromRGB(255, 80, 40), 3, 14, "AugMissile") end
end

-- 🔮 노바: 각성 "이중 노바" = 마지막 폭발 0.6초 뒤 한 번 더 (그 발동 전체의 75%) · +10 = 1.9초에 40% 짜리 한 번 더
function Fx.Nova(run, player, blast, sizeMult, delays)
	if not api then return end
	local sum, last = 1, 0
	for _, d in ipairs(delays) do sum += d[2] last = math.max(last, d[1]) end
	if awake(player, "AugNova") then
		task.delay(last + 0.6, function() if live(run) then blast(sizeMult, sum * AW) end end)
	end
	if ten(player, "AugNova") then
		task.delay(last + 1.3, function() if live(run) then blast(sizeMult, 0.4) end end)
	end
end

-- 🔥 점화: 각성 "불바다" = 불타던 적이 쓰러지면 그 적에게 들어간 불 피해의 75% 로 폭발 + 주변 3마리에 불 · +10 = 최대 중첩 2배
function Fx.FlameDeath(run, burn, part)
	if not api or not burn.Owner or not awake(burn.Owner, "AugFlame") or (burn.Dealt or 0) <= 0 then return end
	local at = part.Position
	api.Effects.Raw(at, { "N", at, 10, Color3.fromRGB(255, 130, 50) })
	local near = api.nearestMonsters(run, at, 14, 4, part)
	for _, other in ipairs(near) do
		api.hitMonster(run, burn.Owner, other, burn.Dealt * AW / math.max(1, #near), nil, Color3.fromRGB(255, 150, 60), "AugFlame")
		api.addIgnite(run, burn.Owner, other.Part, other.Data, 2)
	end
end
function Fx.StackMult(player) return player and ten(player, "AugFlame") and 2 or 1 end

-- 💀 처형: 각성 "단두대" = 처형한 적 남은 체력의 75% 를 주변 4마리에 나눠서 · +10 = 처형 기준 x1.5
function Fx.Execute(run, player, part, executedHp)
	if not api or not awake(player, "AugExecute") or (executedHp or 0) <= 0 then return end
	local near = api.nearestMonsters(run, part.Position, 16, 4, part)
	for _, other in ipairs(near) do
		api.hitMonster(run, player, other, executedHp * AW / #near, nil, Color3.fromRGB(210, 90, 255), "AugExecute")
	end
end
function Fx.ExecMult(player) return ten(player, "AugExecute") and 1.5 or 1 end

-- ☄ 메테오: 각성 "유성우" = 착탄 뒤 소형 유성 4개 (그 발동 전체의 75%) · +10 = 3번째 발동마다 거대 유성 (한 발 더, 범위 1.5배)
local meteorCount = setmetatable({}, { __mode = "k" })
function Fx.Meteor(run, player, position, radius, damage, level, drops)
	if not api then return end
	if awake(player, "AugMeteor") then
		local each = damage * drops * AW / 4
		for i = 1, 4 do
			local spot = position + Vector3.new(math.cos(i * 1.57) * radius * 0.7, 0, math.sin(i * 1.57) * radius * 0.7)
			task.delay(0.9 + 0.15 * i, function() if live(run) then api.dropMeteor(run, player, spot, radius * 0.6, each, level) end end)
		end
	end
	if ten(player, "AugMeteor") then
		meteorCount[player] = (meteorCount[player] or 0) + 1
		if meteorCount[player] % 3 == 0 then api.dropMeteor(run, player, position, radius * 1.5, damage, level) end
	end
end

------------------------------------------------------------ 방어 (DamageGuard)
local invulnUntil = setmetatable({}, { __mode = "k" })
local cdUntil = setmetatable({}, { __mode = "k" }) -- [player] = { Ward = 시각, Body = 시각 }
local function float(humanoid, text, color)
	local root = humanoid.Parent and humanoid.Parent:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local okE, Effects = pcall(function() return require(script.Parent:WaitForChild("Effects")) end)
	if okE then Effects.FloatText(root.Position + Vector3.new(0, 4, 0), text, color) end
end
local function shield(humanoid, seconds)
	local ff = Instance.new("ForceField")
	ff.Visible = true
	ff.Parent = humanoid.Parent
	game:GetService("Debris"):AddItem(ff, seconds)
end
local function ready(player, key, cd)
	local mine = cdUntil[player]
	if not mine then mine = {} cdUntil[player] = mine end
	local now = os.clock()
	if now < (mine[key] or 0) then return false end
	mine[key] = now + cd
	return true
end

function Fx.Invulnerable(player) return os.clock() < (invulnUntil[player] or 0) end

-- 🌀 회피 +10: 피하면 0.5초 무적
function Fx.OnDodge(player, humanoid)
	if ten(player, "AugEvade") and (player:GetAttribute("AugEvade") or 0) > 0 then
		invulnUntil[player] = math.max(invulnUntil[player] or 0, os.clock() + 0.5)
	end
end

-- ⏳ 완충 +10: 나눠 받는 피해의 30% 가 사라진다
function Fx.BufferKeep(player) return (ten(player, "AugBuffer") and (player:GetAttribute("AugBuffer") or 0) > 0) and 0.7 or 1 end

-- 마지막으로 받는 피해 조정 (DamageGuard.Take 가 TakeDamage 바로 앞에서): 💚 보호막 흡수 → ❤️ 치명상 버팀 → 🛡 30% 아래 무적
function Fx.Absorb(player, humanoid, amount)
	if amount <= 0 then return amount end
	local sh = player:GetAttribute("AugRegenShield") or 0
	if sh > 0 then
		local used = math.min(sh, amount)
		player:SetAttribute("AugRegenShield", sh - used)
		amount -= used
		if amount <= 0 then return 0 end
	end
	if amount >= humanoid.Health and ten(player, "AugBody") and (player:GetAttribute("AugBody") or 0) > 0 and ready(player, "Body", 90) then
		amount = math.max(0, humanoid.Health - 1)
		invulnUntil[player] = os.clock() + 1
		shield(humanoid, 1)
		float(humanoid, "❤️ ENDURE!", Color3.fromRGB(255, 120, 140))
		return amount
	end
	if ten(player, "AugWard") and (player:GetAttribute("AugWard") or 0) > 0 and humanoid.MaxHealth > 0
		and (humanoid.Health - amount) / humanoid.MaxHealth < 0.3 and humanoid.Health - amount > 0 and ready(player, "Ward", 60) then
		invulnUntil[player] = os.clock() + 3
		shield(humanoid, 3)
		float(humanoid, "🛡 WARD!", Color3.fromRGB(140, 200, 255))
	end
	return amount
end

-- 1초마다 (DamageGuard 재생 루프): 🔥 불굴 +10 = 체력 25% 아래 초당 2% 회복 · 💚 재생 +10 = 가득 찬 뒤 넘치는 회복이 보호막 (최대 15%)
function Fx.Tick(player, humanoid, regenRate)
	if not humanoid or humanoid.Health <= 0 or humanoid.MaxHealth <= 0 then return end
	if ten(player, "AugGrit") and (player:GetAttribute("AugGrit") or 0) > 0 and humanoid.Health / humanoid.MaxHealth < 0.25 then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * 0.02)
	end
	local sh = player:GetAttribute("AugRegenShield") or 0
	if ten(player, "AugRegen") and (player:GetAttribute("AugRegen") or 0) > 0 then
		if humanoid.Health >= humanoid.MaxHealth and (regenRate or 0) > 0 then
			player:SetAttribute("AugRegenShield", math.min(humanoid.MaxHealth * 0.15, sh + humanoid.MaxHealth * regenRate))
		end
	elseif sh > 0 then
		player:SetAttribute("AugRegenShield", 0)
	end
end

Players.PlayerRemoving:Connect(function(player) invulnUntil[player] = nil cdUntil[player] = nil end)

return Fx
