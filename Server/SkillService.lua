-- SkillService (ServerScriptService > Modules 안의 ModuleScript, 이름: SkillService)
-- 액티브 스킬: 응급 치료 / 궁극기(데드아이). (방벽 / 충격파 핸들러는 남아 있지만 Config.Skills.Order 에 없어 쓰이지 않는다)
-- 쿨타임과 게이지는 서버가 검사하고, 클라이언트는 키를 눌렀다고 알려주기만 한다.
-- 궁극기 게이지는 Attribute "UltCharge"(0~100) 로 클라이언트에 보인다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Quest = require(script.Parent:WaitForChild("QuestService"))
local Dungeon = require(script.Parent:WaitForChild("DungeonService"))
local Field = require(script.Parent:WaitForChild("FieldService"))

local S = Config.Skills

local Skill = {}

local readyAt = {} -- [player] = { [skillKey] = os.clock() 이후에 사용 가능 }

Players.PlayerRemoving:Connect(function(player)
	readyAt[player] = nil
end)

local function aliveParts(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and humanoid and humanoid.Health > 0 then
		return root, humanoid, character
	end
	return nil
end

-- 공격 1회당 궁극기 게이지 충전 (로비에서는 안 참)
function Skill.AddCharge(player, amount)
	if player:GetAttribute("Zone") == "Lobby" then return end
	local charge = player:GetAttribute("UltCharge") or 0
	player:SetAttribute("UltCharge", math.min(S.Ult.Cost, charge + amount))
end

function Skill.Reset(player)
	player:SetAttribute("UltCharge", 0)
	readyAt[player] = nil
end

-- 충격 고리 이펙트
local function ring(position, radius, color, duration)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.4
	part.Size = Vector3.new(1, 1, 1)
	part.Position = position
	part.Parent = workspace
	TweenService:Create(part, TweenInfo.new(duration), { Size = Vector3.new(radius * 2, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(part, duration + 0.1)
end

local function damageAt(player, center, radius, mult)
	local base = Dungeon.ComputeDamage(player)
	local damage = math.max(1, math.floor(base * mult))
	return Dungeon.AreaDamage(player, center, radius, damage) or Field.AreaDamage(player, center, radius, damage) or {}
end

local U = Config.SkillUpgrade

local function skillLevel(player, key)
	return math.clamp(player:GetAttribute("SkillLv_" .. key) or 1, 1, U.MaxLevel)
end

local handlers = {}

handlers.Barrier = function(player, root, humanoid, character)
	local old = character:FindFirstChildOfClass("ForceField")
	if old then old:Destroy() end
	local field = Instance.new("ForceField")
	field.Visible = true
	field.Parent = character
	Debris:AddItem(field, S.Barrier.Duration + U.BarrierDuration * (skillLevel(player, "Barrier") - 1))
	Effects.Burst(root.Position, Color3.fromRGB(120, 200, 255), 25)
	ring(root.Position, 7, Color3.fromRGB(120, 200, 255), 0.5)
	Effects.FloatText(root.Position + Vector3.new(0, 4, 0), "🛡 방벽!", Color3.fromRGB(150, 220, 255))
	return true
end

handlers.Blast = function(player, root, _, _, aimPoint)
	local cfg = S.Blast
	local lv = skillLevel(player, "Blast") - 1
	local offset = aimPoint - root.Position
	if offset.Magnitude > cfg.Range then
		aimPoint = root.Position + offset.Unit * cfg.Range
	end
	local radius = cfg.Radius + U.BlastRadius * lv
	ring(aimPoint, radius, Color3.fromRGB(255, 160, 60), 0.45)
	Effects.Burst(aimPoint, Color3.fromRGB(255, 190, 90), 60)
	Effects.Tracer(root.Position + Vector3.new(0, 1.5, 0), aimPoint, Color3.fromRGB(255, 200, 100), 0.5)
	damageAt(player, aimPoint, radius, cfg.Mult * (1 + U.BlastMult * lv))
	return true
end

handlers.Heal = function(player, root)
	local cfg = S.Heal
	local partyId = player:GetAttribute("PartyId") or 0
	for _, other in ipairs(Players:GetPlayers()) do
		local otherRoot, otherHumanoid = aliveParts(other)
		local sameParty = other == player or (partyId ~= 0 and other:GetAttribute("PartyId") == partyId)
		if otherRoot and sameParty and (otherRoot.Position - root.Position).Magnitude <= cfg.Radius then
			otherHumanoid.Health = math.min(otherHumanoid.MaxHealth, otherHumanoid.Health + otherHumanoid.MaxHealth * (cfg.Ratio + U.HealRatio * (skillLevel(player, "Heal") - 1)))
			Effects.Burst(otherRoot.Position, Color3.fromRGB(110, 255, 150), 25)
			Effects.FloatText(otherRoot.Position + Vector3.new(0, 4, 0), "💚 회복", Color3.fromRGB(130, 255, 160))
		end
	end
	ring(root.Position, cfg.Radius * 0.6, Color3.fromRGB(110, 255, 150), 0.6)
	return true
end

handlers.Ult = function(player, root)
	local cfg = S.Ult
	if (player:GetAttribute("UltCharge") or 0) < cfg.Cost then
		return false, "궁극기 게이지가 부족해요! (적을 공격하면 차올라요)"
	end
	player:SetAttribute("UltCharge", 0)
	local origin = root.Position
	Effects.FloatText(origin + Vector3.new(0, 6, 0), "🎯 데드아이!", Color3.fromRGB(255, 90, 90))
	Effects.Burst(origin, Color3.fromRGB(255, 220, 120), 60)

	-- 1) 시전 연출: 바닥에서 퍼지는 겹겹의 충격 고리 + 하늘로 솟는 빛 + 화면 흔들림
	for i = 1, 3 do
		task.delay((i - 1) * 0.12, function()
			ring(origin, cfg.Radius * (0.5 + i * 0.25), i == 2 and Color3.fromRGB(255, 220, 120) or Color3.fromRGB(255, 70, 70), 0.9)
		end)
	end
	local aura = Instance.new("Part")
	aura.Anchored, aura.CanCollide, aura.CanQuery, aura.CanTouch = true, false, false, false
	aura.Shape = Enum.PartType.Cylinder
	aura.Material = Enum.Material.Neon
	aura.Color = Color3.fromRGB(255, 120, 90)
	aura.Transparency = 0.5
	aura.Size = Vector3.new(160, 6, 6)
	aura.CFrame = CFrame.new(origin + Vector3.new(0, 80, 0)) * CFrame.Angles(0, 0, math.rad(90))
	aura.Parent = workspace
	TweenService:Create(aura, TweenInfo.new(0.7), { Size = Vector3.new(160, 1, 1), Transparency = 1 }):Play()
	Debris:AddItem(aura, 0.8)
	player:SetAttribute("ShakeStrength", 0.8)
	player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)

	-- 2) 잠깐 뜸을 들인 뒤(표식) 모든 적에게 빛기둥이 한꺼번에 내리꽂힌다
	local mult = cfg.Mult * (1 + U.UltMult * (skillLevel(player, "Ult") - 1))
	task.delay(0.5, function()
		if not player.Parent then return end
		local positions = damageAt(player, origin, cfg.Radius, mult)
		for _, position in ipairs(positions) do
			local pillar = Instance.new("Part")
			pillar.Anchored, pillar.CanCollide, pillar.CanQuery, pillar.CanTouch = true, false, false, false
			pillar.Shape = Enum.PartType.Cylinder
			pillar.Material = Enum.Material.Neon
			pillar.Color = Color3.fromRGB(255, 80, 70)
			pillar.Transparency = 0.15
			pillar.Size = Vector3.new(120, 7, 7)
			pillar.CFrame = CFrame.new(position + Vector3.new(0, 60, 0)) * CFrame.Angles(0, 0, math.rad(90))
			pillar.Parent = workspace
			TweenService:Create(pillar, TweenInfo.new(0.6), { Size = Vector3.new(120, 1, 1), Transparency = 1 }):Play()
			Debris:AddItem(pillar, 0.7)
			ring(position, 9, Color3.fromRGB(255, 120, 80), 0.5)
			Effects.Burst(position, Color3.fromRGB(255, 100, 70), 45)
		end
		player:SetAttribute("ShakeStrength", 1.4)
		player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
		if #positions == 0 then
			Effects.FloatText(origin + Vector3.new(0, 4, 0), "근처에 적이 없었어요...", Color3.fromRGB(200, 200, 200))
		end
	end)
	return true
end

local lastRequest = {}

-- skillKey: "Barrier" | "Blast" | "Heal" | "Ult"
function Skill.Use(player, skillKey, aimPoint)
	if typeof(skillKey) ~= "string" or not table.find(S.Order, skillKey) or not handlers[skillKey] then return end
	local zone = player:GetAttribute("Zone")
	if zone ~= "Field" and zone ~= "Dungeon" then
		Remotes.Notify:FireClient(player, "스킬은 필드와 던전에서만 쓸 수 있어요.")
		return
	end
	local root, humanoid, character = aliveParts(player)
	if not root then return end
	if typeof(aimPoint) ~= "Vector3" or aimPoint ~= aimPoint then
		aimPoint = root.Position + root.CFrame.LookVector * 30
	end

	local now = os.clock()
	local cooldowns = readyAt[player]
	if not cooldowns then
		cooldowns = {}
		readyAt[player] = cooldowns
	end
	if now < (cooldowns[skillKey] or 0) then return end

	local ok, message = handlers[skillKey](player, root, humanoid, character, aimPoint)
	if not ok then
		if message then
			Remotes.Notify:FireClient(player, message)
		end
		return
	end
	local haste = (player:GetAttribute("GearHaste") or 0) + (player:GetAttribute("PetHaste") or 0) + U.CooldownPerLevel * (skillLevel(player, skillKey) - 1)
	local cooldown = S[skillKey].Cooldown * (1 - math.min(0.6, haste))
	cooldowns[skillKey] = now + cooldown
	Effects.PlaySound(root, Config.Audio.Skill, 0.7, skillKey == "Ult" and 0.8 or 1)
	Quest.Add(player, "SkillUses", 1)
	Remotes.Skill:FireClient(player, "Cast", skillKey, cooldown)
end

Remotes.Skill.OnServerEvent:Connect(function(player, action, skillKey, aimPoint)
	if action == "Use" then
		local now = os.clock()
		if now - (lastRequest[player] or 0) < 0.15 then return end
		lastRequest[player] = now
		Skill.Use(player, skillKey, aimPoint)
	end
end)

return Skill
