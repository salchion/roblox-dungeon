-- UniqueService (ServerScriptService > Modules 안의 ModuleScript, 이름: UniqueService)
-- 유니크 장비의 "새 능력" (숫자만 오르던 유니크를 눈에 보이는 메커니즘으로 바꿨다). 필드 / 던전 공통.
--   * Time Warp (GearKillCdr)   : 처치할 때마다 모든 스킬 쿨타임이 줄어든다
--   * Slaughterer (GearSlaughter): 10킬마다 내 주변에 학살의 파동 (300% 범위 피해)
--   * Lucky Star (GearStar)     : 처치 시 가끔 행운의 별 -> 5초 동안 행운 +150% (몸에 별빛)
--   * Giant Slayer (GearSunder) : 보스 / 엘리트를 때릴 때마다 균열 중첩 (한 겹당 내 피해 +4%, 최대 10겹, 6초 동안 안 때리면 사라진다)
--   * Bulwark (GearShield)      : 8초마다 보호막이 생겨 공격 한 번을 완전히 막는다
--   * 발동 알림: 유니크가 터지면 캐릭터 위에 그 유니크 이름이 작게 뜬다 (Callout)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local U = {}

U.SLAUGHTER_EVERY = 10
U.STAR_SECONDS = 5
U.STAR_LUCK = 1.5
U.SUNDER_PER = 0.04
U.SUNDER_MAX = 10
U.SHIELD_EVERY = 8

local Effects -- (늦게 불러온다: 서로 부르는 모듈끼리 순환을 피한다)
local function fx()
	if not Effects then
		local ok, mod = pcall(function() return require(script.Parent:WaitForChild("Effects")) end)
		if ok then Effects = mod end
	end
	return Effects
end

local lastCallout = setmetatable({}, { __mode = "k" }) -- [player] = { [key] = 시각 }
function U.Callout(player, key, text, color)
	local now = os.clock()
	local mine = lastCallout[player]
	if not mine then mine = {} lastCallout[player] = mine end
	if now - (mine[key] or 0) < 0.8 then return end -- (자주 터지는 유니크가 글자로 화면을 덮지 않게)
	mine[key] = now
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local E = fx()
	if root and E then
		pcall(E.FloatText, root.Position + Vector3.new(math.random(-2, 2), 6.5, 0), text, color or Color3.fromRGB(255, 200, 110))
	end
end

-- 처치할 때마다 (ComboService.Kill 이 부른다: 필드 / 던전 공통)
local killCount = setmetatable({}, { __mode = "k" })
function U.OnKill(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local heal = Config.PassiveValue(player, "Bloodthirst") -- 패시브 "피의 갈증": 처치마다 최대 체력의 일부 회복
	if heal > 0 then
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * heal) end
	end
	-- 시간 왜곡
	local cdr = player:GetAttribute("GearKillCdr") or 0
	if cdr > 0 then
		local okSkill, Skill = pcall(function() return require(script.Parent:WaitForChild("SkillService")) end)
		if okSkill and Skill.ReduceCooldowns then Skill.ReduceCooldowns(player, cdr) end
	end
	-- 학살자
	if (player:GetAttribute("GearSlaughter") or 0) > 0 and root then
		killCount[player] = (killCount[player] or 0) + 1
		if killCount[player] >= U.SLAUGHTER_EVERY then
			killCount[player] = 0
			local okSkill, Skill = pcall(function() return require(script.Parent:WaitForChild("SkillService")) end)
			if okSkill and Skill.UniqueWave then
				task.spawn(Skill.UniqueWave, player, root.Position, 24, 3.0, "U_Slayer", Color3.fromRGB(255, 70, 60))
				U.Callout(player, "Slayer", "🩸 Slaughter Wave!", Color3.fromRGB(255, 90, 80))
				if player:GetAttribute("AugSyn_Doomfall") == true then -- 조합 "파멸의 낙하": 학살의 파동과 함께 주변에 유성 3개 (300%)
					local center = root.Position
					task.spawn(function()
						local okD, Dungeon = pcall(function() return require(script.Parent:WaitForChild("DungeonService")) end)
						local okF, Field = pcall(function() return require(script.Parent:WaitForChild("FieldService")) end)
						local E = fx()
						if not okD then return end
						local damage = math.max(1, math.floor(Dungeon.ComputeDamage(player) * 3))
						for k = 1, 3 do
							local a = k / 3 * math.pi * 2 + math.random()
							local spot = center + Vector3.new(math.cos(a) * 14, -2.5, math.sin(a) * 14)
							if E then pcall(E.Raw, spot, { "E", spot, 10, 0.9 }) end
							task.delay(0.9, function()
								local hit = Dungeon.AreaDamage(player, spot, 10, damage)
								if not hit and okF and Field.AreaDamage then Field.AreaDamage(player, spot, 10, damage) end
							end)
						end
					end)
				end
			end
		end
	end
	-- 행운의 별
	local star = player:GetAttribute("GearStar") or 0
	if star > 0 and math.random() < star and root then
		player:SetAttribute("StarUntil", workspace:GetServerTimeNow() + U.STAR_SECONDS)
		local E = fx()
		if E then pcall(E.Burst, root.Position + Vector3.new(0, 3, 0), Color3.fromRGB(255, 230, 120), 40) end
		U.Callout(player, "Fortune", "⭐ Lucky Star! Luck +150%", Color3.fromRGB(255, 226, 110))
	end
end

-- 행운의 별이 켜져 있으면 더하는 행운
function U.StarLuck(player)
	return ((player:GetAttribute("StarUntil") or 0) > workspace:GetServerTimeNow()) and U.STAR_LUCK or 0
end

-- 거인 사냥꾼: 보스 / 엘리트를 때릴 때 (Dungeon.MarkMult 가 부른다). 돌려주는 값 = 피해 배율
function U.SunderMult(player, data)
	if (player:GetAttribute("GearSunder") or 0) <= 0 then return 1 end
	if not (data.IsBoss or data.BossLike or data.Kind == "Boss" or data.Elite) then return 1 end
	local now = os.clock()
	data.Sunder = data.Sunder or {}
	local st = data.Sunder[player]
	if not st or now > st.Until then st = { Stacks = 0, Until = 0 } data.Sunder[player] = st end
	local mult = 1 + st.Stacks * U.SUNDER_PER
	if st.Stacks < U.SUNDER_MAX then
		st.Stacks += 1
		if st.Stacks == U.SUNDER_MAX then U.Callout(player, "Giant", "🪓 Sunder x10!", Color3.fromRGB(255, 170, 90)) end
	end
	st.Until = now + 6
	return mult
end

-- 방벽: 막았으면 true (DamageGuard.Take 가 부른다)
function U.TryShield(player)
	if (player:GetAttribute("GearShield") or 0) <= 0 then return false end
	if player:GetAttribute("ShieldUp") ~= true then return false end
	player:SetAttribute("ShieldUp", false)
	player:SetAttribute("ShieldReadyAt", workspace:GetServerTimeNow() + U.SHIELD_EVERY)
	U.Callout(player, "Bulwark", "🛡 Blocked!", Color3.fromRGB(150, 210, 255))
	if player:GetAttribute("AugSyn_Rampart") == true then -- 조합 "터지는 방벽": 막는 순간 보호막이 터져 주변 적을 때린다 (400%)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			task.spawn(function()
				local okD, Dungeon = pcall(function() return require(script.Parent:WaitForChild("DungeonService")) end)
				local okF, Field = pcall(function() return require(script.Parent:WaitForChild("FieldService")) end)
				if not okD then return end
				local damage = math.max(1, math.floor(Dungeon.ComputeDamage(player) * 4))
				local E = fx()
				if E then pcall(E.Burst, root.Position, Color3.fromRGB(150, 210, 255), 50) end
				local hit = Dungeon.AreaDamage(player, root.Position, 18, damage)
				if not hit and okF and Field.AreaDamage then Field.AreaDamage(player, root.Position, 18, damage) end
			end)
		end
	end
	return true
end

-- 보호막이 다시 생기는 시각을 지켜본다 (0.25초마다: 가볍다)
task.spawn(function()
	while true do
		task.wait(0.25)
		local now = workspace:GetServerTimeNow()
		for _, player in ipairs(Players:GetPlayers()) do
			local has = (player:GetAttribute("GearShield") or 0) > 0
			if not has then
				if player:GetAttribute("ShieldUp") ~= nil then player:SetAttribute("ShieldUp", nil) end
			elseif player:GetAttribute("ShieldUp") ~= true and now >= (player:GetAttribute("ShieldReadyAt") or 0) then
				player:SetAttribute("ShieldUp", true)
			end
		end
	end
end)

return U
