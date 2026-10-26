-- SkillService (ServerScriptService > Modules 안의 ModuleScript, 이름: SkillService)
-- 액티브 스킬: 응급 치료 / 정령 소환(F, 지속) / 궁극기(데드아이). (방벽 / 충격파 핸들러는 남아 있지만 Config.Skills.Order 에 없어 쓰이지 않는다)
-- 쿨타임과 게이지는 서버가 검사하고, 클라이언트는 키를 눌렀다고 알려주기만 한다.
-- 궁극기 게이지는 Attribute "UltCharge"(0~100) 로 클라이언트에 보인다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Quest = require(script.Parent:WaitForChild("QuestService"))
local Dungeon = require(script.Parent:WaitForChild("DungeonService"))
local Field = require(script.Parent:WaitForChild("FieldService"))

local S = Config.Skills
print("[SkillService] latest version loaded (Deadeye barrage v3)")

local Skill = {}

local readyAt = setmetatable({}, { __mode = "k" }) -- [player] = { [skillKey] = os.clock() 이후에 사용 가능 }

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

local spiritToken = setmetatable({}, { __mode = "k" }) -- [player] = 지금 도는 정령 묶음 (다시 쓰면 앞 것은 끝난다 / 리셋하면 끝난다)
function Skill.Reset(player)
	spiritToken[player] = nil
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

local BL = require(script.Parent:WaitForChild("BalanceLog")) -- Studio 전용 밸런스 로그
local Meter = require(script.Parent:WaitForChild("DamageMeter")) -- 대미지 미터기

local function damageAt(player, center, radius, mult, source)
	local base = Dungeon.ComputeDamage(player)
	local damage = math.max(1, math.floor(base * mult))
	BL.Ctx = "스킬"
	Meter.Source = source or "Blast" -- 대미지 미터기: 충격파 / 돌풍(F)
	local hit = Dungeon.AreaDamage(player, center, radius, damage) or Field.AreaDamage(player, center, radius, damage) or {}
	Meter.Source = nil
	BL.Ctx = nil
	return hit
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
	Effects.FloatText(root.Position + Vector3.new(0, 4, 0), "🛡 Barrier!", Color3.fromRGB(150, 220, 255))
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

-- 연쇄 번개(F, 저장 이름은 예전 그대로 "Spirit"): 디아블로2 소서리스 체인 라이트닝처럼, 내 손에서 가장 가까운 적으로 번개가 나가고 거기서 주변 적에게 차례로 튄다 (최대 Chain 번).
-- 아직 안 맞은 가까운 적을 먼저 찾고, 없으면 이미 맞은 적(방금 맞은 적 제외)으로 되돌아가 한 번 더 때린다 (그 타격은 위력 60%). 번개 모습은 각자 화면에서 "C" 가 그린다.
handlers.Spirit = function(player, root, _, character)
	local cfg = S.Spirit
	local token = {}
	spiritToken[player] = token
	local scale = cfg.Mult * (1 + U.BlastMult * (skillLevel(player, "Spirit") - 1))
	local all = Dungeon.TargetsIn(player, root.Position, cfg.Range + cfg.Hop, 40) or Field.TargetsIn(player, root.Position, cfg.Range + cfg.Hop, 40) or {}
	local current
	for _, part in ipairs(all) do -- 가장 가까운 적 (목록은 가까운 순)
		if (part.Position - root.Position).Magnitude <= cfg.Range + part.Size.X / 2 then current = part break end
	end
	if not current then return false, "⚡ No enemy nearby" end
	local last = root.Position + Vector3.new(0, 1.5, 0) -- 번개는 내 몸에서 시작
	Effects.Burst(last, Color3.fromRGB(255, 240, 120), 18)
	task.spawn(function()
		local hit = {}
		for hop = 1, cfg.Chain do
			if spiritToken[player] ~= token or not player.Parent or not current or not current.Parent then break end
			local position = current.Position
			local again = hit[current] == true
			Effects.Raw(position, { "C", last, position, hop == 1 })
			BL.Ctx = "스킬"
			Meter.Source = "Spirit" -- 대미지 미터기: 연쇄 번개(F)
			Effects.DamageTint = Color3.fromRGB(255, 240, 120)
			local damage = math.max(1, math.floor(Dungeon.ComputeDamage(player) * scale * (again and 0.6 or 1)))
			local _ = Dungeon.HitPart(player, current, damage) or Field.HitPart(player, current, damage)
			Effects.DamageTint = nil
			Meter.Source = nil
			BL.Ctx = nil
			hit[current] = true
			last = position
			-- 다음: 지금 적에서 가까운, 아직 안 맞은 적. 없으면 이미 맞은 적(지금 적 제외) 중 가장 가까운 적
			local nextPart, best = nil, cfg.Hop
			for _, part in ipairs(all) do
				if part ~= current and part.Parent and not hit[part] then
					local distance = (part.Position - position).Magnitude
					if distance < best then nextPart, best = part, distance end
				end
			end
			if not nextPart then
				best = cfg.Hop
				for _, part in ipairs(all) do
					if part ~= current and part.Parent then
						local distance = (part.Position - position).Magnitude
						if distance < best then nextPart, best = part, distance end
					end
				end
			end
			current = nextPart
			if hop < cfg.Chain and current then task.wait(cfg.HopGap) end
		end
		if spiritToken[player] == token then spiritToken[player] = nil end
	end)
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

-- 데드아이 타격 연출: 커지며 사라지는 네온 구 (맞은 자리 번쩍임 / 총구 화염)
local function flashBall(position, color, size, life)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Anchored, ball.CanCollide, ball.CanQuery, ball.CanTouch = true, false, false, false
	ball.Material = Enum.Material.Neon
	ball.Color = color
	ball.Transparency = 0.1
	ball.Size = Vector3.new(size * 0.3, size * 0.3, size * 0.3)
	ball.CFrame = CFrame.new(position)
	ball.Parent = workspace
	TweenService:Create(ball, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(size, size, size), Transparency = 1 }):Play()
	Debris:AddItem(ball, life + 0.05)
end

-- 바닥으로 퍼지는 충격 고리 (마지막 대폭발용)
local function groundRing(position, color, radius, life)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch = true, false, false, false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.4, 2, 2)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.2, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(ring, life + 0.05)
end

-- 궁극기 데드아이: 범위 안의 모든 적(가까운 최대 12마리)을 한꺼번에 락온하고 전원에게 동시에 일제 포격 + 충격파 + 대폭발.
-- 포격 동안 무적(ForceField) + 화면이 붉게 변한다 (클라이언트가 DeadeyeActive Attribute 를 보고 연출).
handlers.Ult = function(player, root, _, character)
	local cfg = S.Ult
	if (player:GetAttribute("UltCharge") or 0) < cfg.Cost then
		return false, "Not enough Ultimate gauge! (It fills as you attack enemies)"
	end
	local maxTargets = (cfg.MaxTargets or 6) + math.floor((U.UltTargets or 0) * (skillLevel(player, "Ult") - 1) + 0.001)
	local targets = Dungeon.TargetsIn(player, root.Position, cfg.Radius, maxTargets) or Field.TargetsIn(player, root.Position, cfg.Radius, maxTargets)
	if not targets or #targets == 0 then
		return false, "No enemies in range! (Your gauge is unchanged)"
	end
	player:SetAttribute("UltCharge", 0)

	local origin = root.Position
	local totalMult = (cfg.Mult or 8) * 0.75 * (1 + (U.UltMult or 0.15) * (skillLevel(player, "Ult") - 1))
	-- 범위 안의 모든 적을 "동시에" 집중 포격한다: 조준 표시 -> 충격파 -> 전원에게 동시에 빔이 쏟아지는 일제 사격 14회 -> 마지막 대폭발
	local volleys, volleyGap = cfg.Volleys or 12, cfg.VolleyGap or 0.09
	-- 데드아이는 "한 발 피해"가 아니라 무기의 초당 피해 계수(WeaponDpsFactor)에 맞춘다: 한 발 위력이 작은 연사 무기로 진화해도 데드아이가 약해지지 않게
	local weaponType = Config.GetPlayerWeapon(player)
	local baseShot = Dungeon.ComputeDamage(player) / weaponType.DamageMult * Config.WeaponDpsFactor(weaponType)
	local perShot = math.max(1, math.floor(baseShot * totalMult / volleys))

	local field = Instance.new("ForceField")
	field.Name = "DeadeyeShield"
	field.Visible = false
	Debris:AddItem(field, 0.5 + 12 * 0.07 + 1.3 + 1.2) -- 먼저 수명을 정해 둔다 (오류가 나도 영구 무적이 되지 않게)
	field.Parent = character
	player:SetAttribute("DeadeyeActive", true)
	Remotes.Notify:FireClient(player, string.format("🎯 Deadeye! Barrage on %d enemies", #targets))
	Effects.FloatText(origin + Vector3.new(0, 6, 0), "🎯 Deadeye!", Color3.fromRGB(255, 90, 90))

	task.spawn(function()
		local bodyOk, bodyErr = pcall(function()
			-- 1) 전원 동시 락온: 조준 표시가 돌면서 한꺼번에 맞춰진다
			local markers = {}
			player:SetAttribute("ShakeStrength", 0.25) -- 시작할 때 약한 흔들림
			player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
			do local feet = root.Position - Vector3.new(0, 2.5, 0); Effects.Raw(feet, { "R", feet, 16, Color3.fromRGB(150, 225, 255) }) end
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
				label.Rotation = -120
				label.Parent = gui
				TweenService:Create(gui, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(50, 50) }):Play()
				TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
				markers[index] = gui
				Debris:AddItem(gui, 4)
			end
			-- 락온 "띠띠띠띠": 점점 높아지는 짧은 경고음 네 번
			for beep = 1, 4 do
				pcall(function() SoundBank.Play(root, "Ult_Lock", { Pitch = 0.85 + 0.12 * beep, Volume = 1.4 }) end)
				task.wait(0.11)
			end

			-- 2) 미사일 일제 발사: 총 발수는 고정(Config.Skills.Ult.Missiles). 대상들에게 번갈아 한 발씩 나가므로 적이 많으면 퍼지고, 한 마리면 전부 그 적에게 꽂힌다.
			--    작은 미사일이 옆으로 퍼져 솟았다가 내리꽂힌다. 미사일은 각자 화면에서 그리고(Effects.Raw "M"), 피해는 도착하는 순간 들어간다.
			local missileCount, missileGap = cfg.Missiles or 12, 0.07
			local perMissile = math.max(1, math.floor(baseShot * totalMult * (cfg.PoolMult or 4) / missileCount))
			local lastLanding = 0
			local hitsOn = {} -- 이번 데드아이에서 적마다 몇 발 맞았는지 (거듭 맞을수록 피해가 줄어든다)
			local decay = cfg.RepeatDecay or 0.82
			for shotNumber = 1, missileCount do
				if not player.Parent or not root.Parent then return end
				-- 이미 죽은 적의 몫은 살아 있는 다른 적에게 넘긴다 (기본 공격에 먼저 죽어도 데드아이 총 피해가 유지된다)
				local alive = {}
				for _, candidate in ipairs(targets) do
					if candidate.Parent then table.insert(alive, candidate) end
				end
				if #alive == 0 then break end
				local index = (shotNumber - 1) % #targets + 1
				local original = targets[index]
				local part = original.Parent and original or alive[(shotNumber - 1) % #alive + 1]
				local shoulder = root.Position + Vector3.new((math.random() - 0.5) * 3, 3 + math.random() * 1.5, (math.random() - 0.5) * 3)
				Effects.Burst(shoulder, Color3.fromRGB(190, 235, 255), 18) -- 발사 불꽃 (크게)
				if shotNumber % 3 == 1 then -- 세 발마다 발밑에서 충격 고리가 퍼진다
					local feet = root.Position - Vector3.new(0, 2.5, 0)
					Effects.Raw(feet, { "R", feet, 10 + shotNumber, Color3.fromRGB(120, 215, 255) })
				end
				pcall(function() SoundBank.Play(root, "Ult_Launch", { Pitch = 0.85 + math.random() * 0.3, Volume = 1 }) end)
				pcall(function() SoundBank.Play(root, "Ult_Missile", { Pitch = 0.9 + math.random() * 0.3, Volume = 1.3 }) end) -- (총소리 볼륨 설정에 묶이지 않게 이름을 안 붙인다)
				local target = part.Position
				-- 옆으로 약 45도 각도로 부채꼴로 퍼져 올라간다 (높이는 낮춰서 꺾여 내리꽂히는 장면이 화면에 담기게)
				local flat = Vector3.new(target.X - shoulder.X, 0, target.Z - shoulder.Z)
				flat = flat.Magnitude > 1 and flat.Unit or Vector3.new(0, 0, -1)
				local side = (CFrame.Angles(0, math.rad((math.random() - 0.5) * 170), 0) * CFrame.new(flat)).Position
				local reach = 16 + math.random() * 16
				local mid = shoulder + side * reach + Vector3.new(0, reach * (0.85 + math.random() * 0.4), 0)
				local flight = 1.0 + math.random() * 0.2
				Effects.Raw(shoulder, { "M", shoulder, part, mid, flight, 0.85, "icbm", Color3.fromRGB(90, 200, 255) })
				lastLanding = math.max(lastLanding, os.clock() + flight)
				task.delay(flight, function()
					if not player.Parent then return end
					local hitPart = part
					if not hitPart.Parent then -- 날아가는 사이에 죽었다: 살아 있는 다른 적에게 피해를 넘긴다
						local others = {}
						for _, candidate in ipairs(targets) do
							if candidate.Parent then table.insert(others, candidate) end
						end
						hitPart = #others > 0 and others[math.random(#others)] or nil
					end
					if not hitPart then return end
					BL.Ctx = "데드아이"
					local previousHits = hitsOn[hitPart] or 0
					hitsOn[hitPart] = previousHits + 1
					local damage = math.max(1, math.floor(perMissile * decay ^ previousHits)) -- 같은 적에게 거듭 맞을수록 줄어든다
					Effects.DamageTint = Color3.fromRGB(90, 200, 255) -- 데드아이 피해 숫자는 하늘색으로 크게
					Meter.Source = "Ult" -- 대미지 미터기: 데드아이(V)
					local landed = Dungeon.HitPart(player, hitPart, damage) or Field.HitPart(player, hitPart, damage)
					Meter.Source = nil
					Effects.DamageTint = nil
					BL.Ctx = nil
					pcall(function() SoundBank.Play(hitPart, "Ult_Hit", { Pitch = 0.85 + math.random() * 0.4, Volume = 1 }) end) -- 미사일마다 "쾅"
					local label = markers[index] and markers[index]:FindFirstChildOfClass("TextLabel")
					if landed and label then label.TextColor3 = Color3.fromRGB(255, 255, 255) end
				end)
				task.wait(missileGap)
			end
			task.wait(math.max(0, lastLanding - os.clock()) + 0.05) -- 마지막 미사일이 꽂힐 때까지

			-- 3) 마무리 대폭발: 락온했던 모든 위치에서 한꺼번에 터진다
			pcall(function() SoundBank.Play(root, "Ult_Finale", { Volume = 1 }) end)
			player:SetAttribute("UltFinaleTick", (player:GetAttribute("UltFinaleTick") or 0) + 1) -- 클라이언트가 보고 화면이 "쿵" 하고 조여졌다 풀린다
			pcall(function()
				for _, part in ipairs(targets) do
					if part.Parent then
						Effects.Burst(part.Position, Color3.fromRGB(140, 215, 255), 16)
						flashBall(part.Position, Color3.fromRGB(170, 225, 255), math.clamp(part.Size.X * 2.2, 6, 14), 0.35)
						groundRing(part.Position - Vector3.new(0, part.Size.Y / 2 - 0.2, 0), Color3.fromRGB(90, 200, 255), math.clamp(part.Size.X * 2.5, 8, 18), 0.45)
					end
				end
			end)
			for _, gui in pairs(markers) do gui:Destroy() end
			player:SetAttribute("DeadeyeActive", false)
		end)
		if not bodyOk then
			if field.Parent then field:Destroy() end
			warn("[Deadeye] error: " .. tostring(bodyErr))
			Remotes.Notify:FireClient(player, "Deadeye error: " .. tostring(bodyErr))
			player:SetAttribute("DeadeyeActive", false)
		end
	end)
	return true
end

local lastRequest = setmetatable({}, { __mode = "k" })

-- skillKey: "Barrier" | "Blast" | "Heal" | "Ult"
function Skill.Use(player, skillKey, aimPoint)
	if typeof(skillKey) ~= "string" or not table.find(S.Order, skillKey) or not handlers[skillKey] then return end
	local zone = player:GetAttribute("Zone")
	if zone ~= "Field" and zone ~= "Dungeon" then
		Remotes.Notify:FireClient(player, "Skills can only be used in the field and dungeons.")
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
	local haste = (player:GetAttribute("GearHaste") or 0) + (player:GetAttribute("PetHaste") or 0) + (player:GetAttribute("LvHaste") or 0) + U.CooldownPerLevel * (skillLevel(player, skillKey) - 1)
	local cooldown = S[skillKey].Cooldown * (1 - math.min(0.6, haste))
	cooldowns[skillKey] = now + cooldown
	if skillKey == "Spirit" then
		pcall(function() SoundBank.Play(root, "Aug_Storm", { Volume = 0.9 }) end) -- 번개 소리
	else
		SoundBank.Play(root, skillKey == "Ult" and "Skill_Ult" or "Skill_Heal")
	end
	Quest.Add(player, "SkillUses", 1)
	BL.Count(player, skillKey, 1) -- (밸런스 로그: Ult = 궁극기, 나머지 = 스킬)
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
