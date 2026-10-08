	-- 공속 한계를 뚫은 난사: 적이 적어도 총 48발 이상, 한 발 간격은 0.03초 (화다다다다!). 전체 피해량은 그대로 나눠 맞는다.
	local shotsPer = math.max(cfg.ShotsPerTarget, math.ceil(48 / #targets))
	local perShot = math.max(1, math.floor(Dungeon.ComputeDamage(player) * totalMult / shotsPer))
	local lockGap = 0.14

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

-- 궁극기 데드아이: 범위 안의 적을 하나씩 "딱" 락온(빨간 조준 표시가 줄어들며 고정)한 뒤, 락온한 전원에게 연속으로 난사한다.
-- 락온하는 동안 무적(ForceField) + 화면이 붉게 변한다 (클라이언트가 DeadeyeActive Attribute 를 보고 연출).
handlers.Ult = function(player, root, _, character)
	local cfg = S.Ult
	if (player:GetAttribute("UltCharge") or 0) < cfg.Cost then
		return false, "궁극기 게이지가 부족해요! (적을 공격하면 차올라요)"
	end
	local targets = Dungeon.TargetsIn(player, root.Position, cfg.Radius, 12) or Field.TargetsIn(player, root.Position, cfg.Radius, 12)
	if not targets or #targets == 0 then
		return false, "범위 안에 적이 없어요! (게이지는 그대로예요)"
	end
	player:SetAttribute("UltCharge", 0)

	local origin = root.Position
	local totalMult = cfg.Mult * (1 + U.UltMult * (skillLevel(player, "Ult") - 1))
	local perShot = math.max(1, math.floor(Dungeon.ComputeDamage(player) * totalMult / cfg.ShotsPerTarget))
	local lockGap = 0.14

	local field = Instance.new("ForceField")
	field.Visible = false
	field.Parent = character
	Debris:AddItem(field, #targets * lockGap + 1.0 + #targets * shotsPer * cfg.ShotGap + 0.6)
	player:SetAttribute("DeadeyeActive", true)
	Effects.FloatText(origin + Vector3.new(0, 6, 0), "🎯 데드아이!", Color3.fromRGB(255, 90, 90))
	ring(origin, cfg.Radius * 0.7, Color3.fromRGB(255, 70, 70), 0.9)

	task.spawn(function()
		-- 1) 락온: 적마다 큰 조준 표시가 쏙 줄어들며 고정된다
		local markers = {}
		for index, part in ipairs(targets) do
			if not part.Parent then continue end
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromOffset(150, 150)
			gui.AlwaysOnTop = true
			gui.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 1, 0)
			gui.Parent = part
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Text = "◎"
			label.TextScaled = true
			label.Font = Enum.Font.GothamBlack
			label.TextColor3 = Color3.fromRGB(255, 70, 70)
			label.TextStrokeTransparency = 0.3
			label.Parent = gui
			TweenService:Create(gui, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(46, 46) }):Play()
			Effects.Tracer(root.Position + Vector3.new(0, 1.5, 0), part.Position, Color3.fromRGB(255, 80, 80), 0.18)
			markers[index] = gui
			Debris:AddItem(gui, 4)
			task.wait(lockGap)
		end
		task.wait(0.7) -- 모두 고정된 뒤 숨을 고르는 짧은 정적

		-- 2) 난사: 락온한 적들을 돌아가며 초고속으로 쏟아붓는다 (총구 섬광 + 흔들림 + 몸이 적을 향해 돌아간다)
		local fired = 0
		for _ = 1, shotsPer do
			for index, part in ipairs(targets) do
				if not player.Parent then return end
				local alive = part.Parent and (Dungeon.HitPart(player, part, perShot) or Field.HitPart(player, part, perShot))
				if alive and root.Parent then
					fired += 1
					local from = root.Position + Vector3.new(0, 1.5, 0)
					local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * (part.Size.X * 0.5)
					Effects.Tracer(from, part.Position + jitter, fired % 2 == 0 and Color3.fromRGB(255, 220, 120) or Color3.fromRGB(255, 120, 90), 0.1)
					if fired % 2 == 0 then
						Effects.Burst(part.Position + jitter, Color3.fromRGB(255, 110, 70), 5)
					end
					if fired % 3 == 0 then -- 총소리 / 화면 흔들림은 3발마다 (연속음이 되도록)
						Effects.PlaySound(root, Config.Audio.Shot, 0.5, 1.15 + math.random() * 0.3)
						player:SetAttribute("ShakeStrength", 0.22)
						player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
					end
					if fired % 4 == 1 then
						local flash = Instance.new("Part")
						flash.Anchored, flash.CanCollide, flash.CanQuery, flash.CanTouch = true, false, false, false
						flash.Shape = Enum.PartType.Ball
						flash.Material = Enum.Material.Neon
						flash.Color = Color3.fromRGB(255, 230, 140)
						flash.Size = Vector3.new(2.4, 2.4, 2.4)
						flash.Position = from + (part.Position - from).Unit * 2.5
						flash.Parent = workspace
						TweenService:Create(flash, TweenInfo.new(0.1), { Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 }):Play()
						Debris:AddItem(flash, 0.15)
					end
					local label = markers[index] and markers[index]:FindFirstChildOfClass("TextLabel")
					if label then label.TextColor3 = Color3.fromRGB(255, 255, 255) end
					-- 몸이 쏘는 적 쪽으로 돌아간다 (지금 쏘는 느낌)
					local flat = Vector3.new(part.Position.X - root.Position.X, 0, part.Position.Z - root.Position.Z)
					if flat.Magnitude > 0.5 then
						root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
					end
				end
				task.wait(cfg.ShotGap)
			end
		end
		for _, gui in pairs(markers) do gui:Destroy() end
		player:SetAttribute("DeadeyeActive", false)
		player:SetAttribute("ShakeStrength", 0.9)
		player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
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
