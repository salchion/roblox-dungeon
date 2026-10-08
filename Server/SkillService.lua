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

-- 힐: 초록 + (십자가)들이 사방에서 떠오르고, 발밑에서 치유의 빛 기둥과 고리가 번진다 (회복 숫자와 함께)
local function healVisual(position)
	for i = 1, 9 do
		task.delay((i - 1) * 0.06, function()
			local anchor = Instance.new("Part")
			anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
			anchor.Transparency = 1
			anchor.Size = Vector3.new(0.5, 0.5, 0.5)
			local angle = math.random() * math.pi * 2
			local radius = 1 + math.random() * 2.2
			anchor.Position = position + Vector3.new(math.cos(angle) * radius, -1 + math.random() * 1.5, math.sin(angle) * radius)
			anchor.Parent = workspace
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromOffset(46, 46)
			gui.AlwaysOnTop = true
			gui.Parent = anchor
			local plus = Instance.new("TextLabel")
			plus.Size = UDim2.fromScale(1, 1)
			plus.BackgroundTransparency = 1
			plus.Text = "+"
			plus.TextScaled = true
			plus.Font = Enum.Font.GothamBlack
			plus.TextColor3 = Color3.fromRGB(110, 255, 150)
			plus.TextStrokeColor3 = Color3.fromRGB(20, 120, 60)
			plus.TextStrokeTransparency = 0
			plus.Parent = gui
			TweenService:Create(anchor, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = anchor.Position + Vector3.new(0, 6 + math.random() * 2, 0) }):Play()
			TweenService:Create(plus, TweenInfo.new(1.1), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			TweenService:Create(gui, TweenInfo.new(1.1), { Size = UDim2.fromOffset(70, 70) }):Play()
			Debris:AddItem(anchor, 1.2)
		end)
	end
	-- 발밑에서 올라오는 초록 빛 기둥
	local column = Instance.new("Part")
	column.Anchored, column.CanCollide, column.CanQuery, column.CanTouch = true, false, false, false
	column.Shape = Enum.PartType.Cylinder
	column.Material = Enum.Material.Neon
	column.Color = Color3.fromRGB(110, 255, 150)
	column.Transparency = 0.55
	column.Size = Vector3.new(8, 5, 5)
	column.CFrame = CFrame.new(position - Vector3.new(0, 1, 0) + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	column.Parent = workspace
	TweenService:Create(column, TweenInfo.new(0.8), { Size = Vector3.new(12, 1, 1), Transparency = 1 }):Play()
	Debris:AddItem(column, 0.9)
end

handlers.Heal = function(player, root)
	local cfg = S.Heal
	local partyId = player:GetAttribute("PartyId") or 0
	for _, other in ipairs(Players:GetPlayers()) do
		local otherRoot, otherHumanoid = aliveParts(other)
		local sameParty = other == player or (partyId ~= 0 and other:GetAttribute("PartyId") == partyId)
		if otherRoot and sameParty and (otherRoot.Position - root.Position).Magnitude <= cfg.Radius then
			local amount = otherHumanoid.MaxHealth * (cfg.Ratio + U.HealRatio * (skillLevel(player, "Heal") - 1))
			otherHumanoid.Health = math.min(otherHumanoid.MaxHealth, otherHumanoid.Health + amount)
			Effects.Burst(otherRoot.Position, Color3.fromRGB(110, 255, 150), 18)
			Effects.FloatText(otherRoot.Position + Vector3.new(0, 4, 0), string.format("💚 +%d", math.floor(amount)), Color3.fromRGB(130, 255, 160))
			healVisual(otherRoot.Position)
		end
	end
	ring(root.Position, cfg.Radius * 0.6, Color3.fromRGB(110, 255, 150), 0.7)
	ring(root.Position, cfg.Radius * 0.35, Color3.fromRGB(220, 255, 230), 0.5)
	return true
end

-- 데드아이 전용 굵은 빔 (기본 Tracer 는 너무 가늘고 짧아서 안 보였다)
local function thickBeam(from, to, color, thickness, life)
	local distance = (to - from).Magnitude
	if distance < 0.1 then return end
	local beam = Instance.new("Part")
	beam.Anchored, beam.CanCollide, beam.CanQuery, beam.CanTouch = true, false, false, false
	beam.Material = Enum.Material.Neon
	beam.Color = color
	beam.Size = Vector3.new(thickness, thickness, distance)
	beam.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -distance / 2)
	beam.Parent = workspace
	TweenService:Create(beam, TweenInfo.new(life), { Transparency = 1, Size = Vector3.new(thickness * 0.2, thickness * 0.2, distance) }):Play()
	Debris:AddItem(beam, life + 0.05)
end

-- 궁극기 데드아이: 범위 안의 모든 적(최대 40마리)을 한꺼번에 락온하고 전원에게 동시에 일제 포격 + 충격파 + 대폭발.
-- 포격 동안 무적(ForceField) + 화면이 붉게 변한다 (클라이언트가 DeadeyeActive Attribute 를 보고 연출).
handlers.Ult = function(player, root, _, character)
	local cfg = S.Ult
	if (player:GetAttribute("UltCharge") or 0) < cfg.Cost then
		return false, "궁극기 게이지가 부족해요! (적을 공격하면 차올라요)"
	end
	local targets = Dungeon.TargetsIn(player, root.Position, cfg.Radius, 40) or Field.TargetsIn(player, root.Position, cfg.Radius, 40)
	if not targets or #targets == 0 then
		return false, "범위 안에 적이 없어요! (게이지는 그대로예요)"
	end
	player:SetAttribute("UltCharge", 0)

	local origin = root.Position
	local totalMult = (cfg.Mult or 8) * (1 + (U.UltMult or 0.15) * (skillLevel(player, "Ult") - 1))
	-- 범위 안의 모든 적을 "동시에" 집중 포격한다: 조준 표시 -> 충격파 -> 전원에게 동시에 빔이 쏟아지는 일제 사격 14회 -> 마지막 대폭발
	local volleys, volleyGap = 14, 0.07
	local perShot = math.max(1, math.floor(Dungeon.ComputeDamage(player) * totalMult / volleys))

	local field = Instance.new("ForceField")
	field.Name = "DeadeyeShield"
	field.Visible = false
	Debris:AddItem(field, 0.6 + volleys * volleyGap + 1.2) -- 먼저 수명을 정해 둔다 (오류가 나도 영구 무적이 되지 않게)
	field.Parent = character
	player:SetAttribute("DeadeyeActive", true)
	Remotes.Notify:FireClient(player, string.format("🎯 데드아이! %d마리 일제 포격", #targets))
	Effects.FloatText(origin + Vector3.new(0, 6, 0), "🎯 데드아이!", Color3.fromRGB(255, 90, 90))
	ring(origin, cfg.Radius, Color3.fromRGB(255, 70, 70), 0.8)
	ring(origin, cfg.Radius * 0.6, Color3.fromRGB(255, 200, 90), 0.6)

	task.spawn(function()
		local bodyOk, bodyErr = pcall(function()
			-- 1) 전원 동시 락온: 조준 표시가 한꺼번에 쏙 줄어들며 고정 + 가는 빨간 선이 전원에게 뻗는다
			local markers = {}
			for index, part in ipairs(targets) do
				if not part.Parent then continue end
				local gui = Instance.new("BillboardGui")
				gui.Size = UDim2.fromOffset(160, 160)
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
				TweenService:Create(gui, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(50, 50) }):Play()
				thickBeam(root.Position + Vector3.new(0, 1.5, 0), part.Position, Color3.fromRGB(255, 60, 60), 0.5, 0.5)
				markers[index] = gui
				Debris:AddItem(gui, 4)
			end
			task.wait(0.6)

			-- 2) 일제 사격: 매 회마다 살아 있는 전원에게 동시에 굵은 빔 + 폭발. 몸은 가장 가까운 적을 향한다
			local fired = 0
			for volley = 1, volleys do
				if not player.Parent or not root.Parent then return end
				local from = root.Position + Vector3.new(0, 1.5, 0)
				for index, part in ipairs(targets) do
					local alive = part.Parent and (Dungeon.HitPart(player, part, perShot) or Field.HitPart(player, part, perShot))
					if alive then
						fired += 1
						pcall(function()
							local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * (part.Size.X * 0.5)
							thickBeam(from, part.Position + jitter, (fired % 2 == 0) and Color3.fromRGB(255, 235, 120) or Color3.fromRGB(255, 110, 80), 1.1, 0.18)
							Effects.Burst(part.Position + jitter, Color3.fromRGB(255, 110, 70), 8)
							local label = markers[index] and markers[index]:FindFirstChildOfClass("TextLabel")
							if label then label.TextColor3 = Color3.fromRGB(255, 255, 255) end
						end)
					end
				end
				pcall(function()
					local flash = Instance.new("Part")
					flash.Anchored, flash.CanCollide, flash.CanQuery, flash.CanTouch = true, false, false, false
					flash.Shape = Enum.PartType.Ball
					flash.Material = Enum.Material.Neon
					flash.Color = Color3.fromRGB(255, 230, 140)
					flash.Size = Vector3.new(7, 7, 7)
					flash.Position = from
					flash.Parent = workspace
					TweenService:Create(flash, TweenInfo.new(0.12), { Size = Vector3.new(0.5, 0.5, 0.5), Transparency = 1 }):Play()
					Debris:AddItem(flash, 0.2)
					if volley % 2 == 1 then
						Effects.PlaySound(root, Config.Audio.Shot, 0.6, 1.1 + math.random() * 0.3)
						ring(root.Position, cfg.Radius * (0.4 + 0.6 * volley / volleys), Color3.fromRGB(255, 120, 80), 0.35)
					end
					player:SetAttribute("ShakeStrength", 0.3)
					player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
					local nearest = targets[1]
					if nearest and nearest.Parent then
						local flat = Vector3.new(nearest.Position.X - root.Position.X, 0, nearest.Position.Z - root.Position.Z)
						if flat.Magnitude > 0.5 then
							root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
						end
					end
				end)
				task.wait(volleyGap)
			end

			-- 3) 마무리 대폭발: 락온했던 모든 위치에서 한꺼번에 터진다
			pcall(function()
				for _, part in ipairs(targets) do
					if part.Parent then
						Effects.Burst(part.Position, Color3.fromRGB(255, 200, 90), 16)
						ring(part.Position, 14, Color3.fromRGB(255, 120, 60), 0.5)
					end
				end
				ring(root.Position, cfg.Radius * 1.1, Color3.fromRGB(255, 240, 200), 0.6)
			end)
			for _, gui in pairs(markers) do gui:Destroy() end
			player:SetAttribute("DeadeyeActive", false)
			player:SetAttribute("ShakeStrength", 0.9)
			player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
		end)
		if not bodyOk then
			if field.Parent then field:Destroy() end
			warn("[Deadeye] error: " .. tostring(bodyErr))
			Remotes.Notify:FireClient(player, "데드아이 오류: " .. tostring(bodyErr))
			player:SetAttribute("DeadeyeActive", false)
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
