-- MonsterTypes (ServerScriptService > Modules 안의 ModuleScript, 이름: MonsterTypes)
-- 몬스터 7종: 생김새 + 움직임 + 공격 방식이 각각 다르다. 던전과 필드가 같이 쓴다.
--   슬라임   : 말랑한 구체. 천천히 다가와서 한 발씩 쏜다
--   가시 독충: 가시가 난 구체. 부채꼴로 3발
--   박쥐     : 작고 빠르게 날아다니며 연사 (체력이 약함)
--   마법사 유령: 멀리서 전방위 탄막
--   바위 골렘: 크고 느리지만 아주 단단하고, 느리고 아픈 큰 포탄
--   돌진 멧돼지: 붉게 예고한 뒤 직선으로 돌진해 들이받는다
--   폭탄병   : 빠르게 달려와서 자폭 (피하거나 먼저 처치)
--
-- 사용: MonsterTypes.Build(...) 로 몸체를 만들고, 매 프레임 MonsterTypes.Update(ctx, part, data, dt, now) 를 부른다.
-- ctx 는 던전/필드가 각자 만들어 주는 "환경" 이다:
--   ctx.GetTarget(position) -> root, distance     가장 가까운 타겟 플레이어
--   ctx.Fire(origin, direction, speed, damage, size, color)
--   ctx.Players() -> { { Root, Humanoid }... }    맞을 수 있는 살아 있는 플레이어들
--   ctx.Alive(part, data) -> bool                 이 몬스터가 아직 살아 있는가
--   ctx.Kill(part, data)                          보상 없이 제거 (자폭용)
--   ctx.FloorY                                     바닥 높이

local Effects = require(script.Parent:WaitForChild("Effects"))

local M = {}

-- Range: 이 거리 안에서만 공격 / Keep: 유지하려는 거리 / *Mult: 기본 몬스터 능력치 대비 배율
M.Defs = {
	Slime = {
		Name = "슬라임", Shape = "Ball", Color = Color3.fromRGB(110, 205, 95), Material = Enum.Material.Glass, Transparency = 0.1,
		SizeMult = 1, SpeedMult = 1, HealthMult = 1, DamageMult = 1, IntervalMult = 1, ShotSpeedMult = 1, GoldMult = 1,
		Attack = "Single", Move = "Approach", Keep = 14, Range = 75,
	},
	Spitter = {
		Name = "가시 독충", Shape = "Ball", Color = Color3.fromRGB(165, 80, 215), Material = Enum.Material.SmoothPlastic,
		SizeMult = 0.95, SpeedMult = 1.1, HealthMult = 0.9, DamageMult = 0.7, IntervalMult = 1.3, ShotSpeedMult = 1, GoldMult = 1.1,
		Attack = "Fan", Move = "Approach", Keep = 20, Range = 85, Spikes = true,
	},
	Bat = {
		Name = "박쥐", Shape = "Ball", Color = Color3.fromRGB(85, 60, 120), Material = Enum.Material.SmoothPlastic,
		SizeMult = 0.6, SpeedMult = 2.2, HealthMult = 0.55, DamageMult = 0.6, IntervalMult = 0.7, ShotSpeedMult = 1.3, GoldMult = 0.9,
		Attack = "Single", Move = "Hover", Keep = 16, Range = 70, Wings = true,
	},
	Mage = {
		Name = "마법사 유령", Shape = "Ball", Color = Color3.fromRGB(130, 225, 255), Material = Enum.Material.Neon, Transparency = 0.25,
		SizeMult = 0.9, SpeedMult = 0.9, HealthMult = 0.8, DamageMult = 0.7, IntervalMult = 2.4, ShotSpeedMult = 0.8, GoldMult = 1.4,
		Attack = "Ring", Move = "Keep", Keep = 30, Range = 90, Halo = true,
	},
	Golem = {
		Name = "바위 골렘", Shape = "Block", Color = Color3.fromRGB(125, 120, 115), Material = Enum.Material.Slate,
		SizeMult = 1.3, SpeedMult = 0.5, HealthMult = 2.2, DamageMult = 1.8, IntervalMult = 1.8, ShotSpeedMult = 0.55, GoldMult = 1.7,
		Attack = "Heavy", Move = "Approach", Keep = 16, Range = 80, Core = true,
	},
	Charger = {
		Name = "돌진 멧돼지", Shape = "Block", Color = Color3.fromRGB(155, 100, 65), Material = Enum.Material.Wood,
		SizeMult = 1.1, SpeedMult = 1, HealthMult = 1.3, DamageMult = 1.4, IntervalMult = 1, ShotSpeedMult = 1, GoldMult = 1.4,
		Attack = "Charge", Move = "Approach", Keep = 6, Range = 55, Tusks = true,
	},
	Bomber = {
		Name = "폭탄병", Shape = "Ball", Color = Color3.fromRGB(70, 70, 82), Material = Enum.Material.Metal,
		SizeMult = 0.8, SpeedMult = 2, HealthMult = 0.6, DamageMult = 2.5, IntervalMult = 1, ShotSpeedMult = 1, GoldMult = 0.8,
		Attack = "Explode", Move = "Rush", Keep = 0, Range = 999, Fuse = true,
	},
	-- ===== 신규 몬스터 =====
	Imp = {
		Name = "저격 임프", Shape = "Ball", Color = Color3.fromRGB(200, 60, 90), Material = Enum.Material.SmoothPlastic,
		SizeMult = 0.7, SpeedMult = 0.9, HealthMult = 0.6, DamageMult = 1.3, IntervalMult = 1.6, ShotSpeedMult = 2.6, GoldMult = 1.3,
		Attack = "Single", Move = "Keep", Keep = 55, Range = 130, Horns = true,
	},
	Knight = {
		Name = "방패 기사", Shape = "Block", Color = Color3.fromRGB(120, 140, 175), Material = Enum.Material.Metal,
		SizeMult = 1.15, SpeedMult = 0.7, HealthMult = 2.6, DamageMult = 1.1, IntervalMult = 1.4, ShotSpeedMult = 0.9, GoldMult = 1.8,
		Attack = "Fan", Move = "Approach", Keep = 8, Range = 60, Shield = true,
	},
	Turret = {
		Name = "마법 포탑", Shape = "Block", Color = Color3.fromRGB(90, 95, 110), Material = Enum.Material.Metal,
		SizeMult = 1.0, SpeedMult = 0, HealthMult = 1.7, DamageMult = 1.0, IntervalMult = 0.8, ShotSpeedMult = 1.2, GoldMult = 1.4,
		Attack = "Fan", Move = "Static", Keep = 0, Range = 110, Barrel = true,
	},
	Spider = {
		Name = "독거미", Shape = "Ball", Color = Color3.fromRGB(60, 50, 60), Material = Enum.Material.SmoothPlastic,
		SizeMult = 0.75, SpeedMult = 1.9, HealthMult = 0.8, DamageMult = 0.8, IntervalMult = 0.6, ShotSpeedMult = 1.2, GoldMult = 1.0,
		Attack = "Single", Move = "Rush", Keep = 0, Range = 45, Legs = true,
	},
	Wisp = {
		Name = "도깨비불", Shape = "Ball", Color = Color3.fromRGB(120, 255, 200), Material = Enum.Material.Neon, Transparency = 0.3,
		SizeMult = 0.55, SpeedMult = 2.4, HealthMult = 0.45, DamageMult = 0.7, IntervalMult = 0.9, ShotSpeedMult = 1.4, GoldMult = 1.1,
		Attack = "Fan", Move = "Hover", Keep = 22, Range = 80, Flame = true,
	},
	Totem = {
		Name = "저주 토템", Shape = "Block", Color = Color3.fromRGB(130, 90, 60), Material = Enum.Material.Wood,
		SizeMult = 1.2, SpeedMult = 0, HealthMult = 2.2, DamageMult = 0.9, IntervalMult = 1.8, ShotSpeedMult = 0.7, GoldMult = 1.8,
		Attack = "Ring", Move = "Static", Keep = 0, Range = 100, Totem = true,
	},
}

-- 가중치 표(pool)에서 하나 고른다. 예: { Slime = 4, Bat = 2 }
function M.Pick(pool)
	local total = 0
	for _, weight in pairs(pool) do
		total += weight
	end
	local roll = math.random() * total
	local last
	for key, weight in pairs(pool) do
		last = key
		roll -= weight
		if roll <= 0 then
			return key
		end
	end
	return last
end

-- 기본 몬스터 능력치(stats)에 몬스터 종류 배율을 곱한다 (stats 를 직접 바꾸고 돌려줌)
function M.ApplyDef(typeKey, stats)
	local def = M.Defs[typeKey]
	stats.Size *= def.SizeMult
	stats.MaxHealth = math.max(1, math.floor(stats.MaxHealth * def.HealthMult))
	stats.Speed *= def.SpeedMult
	stats.ShotDamage = math.max(1, math.floor(stats.ShotDamage * def.DamageMult))
	stats.ShotInterval *= def.IntervalMult
	stats.ShotSpeed *= def.ShotSpeedMult
	stats.Gold = math.max(1, math.floor(stats.Gold * def.GoldMult))
	return stats
end

------------------------------------------------------------
-- 생김새
------------------------------------------------------------
-- 몸체를 만들고 장식(눈, 가시, 날개 ...)을 용접해서 붙인다. 장식은 CanQuery=false 라서 총알은 몸체에만 맞는다.
function M.Build(typeKey, size, color, position, parent)
	local def = M.Defs[typeKey]

	local body = Instance.new("Part")
	body.Name = "Monster"
	body.Anchored = true
	body.CanCollide = false
	body.Material = def.Material
	body.Color = color
	body.Transparency = def.Transparency or 0
	if def.Shape == "Ball" then
		body.Shape = Enum.PartType.Ball
		body.Size = Vector3.new(size, size, size)
	else
		body.Size = Vector3.new(size, size * 0.9, size * 1.15)
	end
	body.CFrame = CFrame.new(position)
	body.Parent = parent
	game:GetService("CollectionService"):AddTag(body, "Monster") -- 클라이언트 레이더용

	local frontZ = def.Shape == "Ball" and size * 0.46 or size * 0.58

	local function decorate(shape, partSize, offset, partColor, material)
		local part = Instance.new("Part")
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.Shape = shape
		part.Size = partSize
		part.Color = partColor
		part.Material = material or Enum.Material.SmoothPlastic
		part.CFrame = body.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = part
		weld.Parent = part
		part.Parent = body
		return part
	end

	-- 눈 (모든 몬스터 공통, 앞쪽 = -Z). 폭탄병은 붉은 눈
	local eyeColor = typeKey == "Bomber" and Color3.fromRGB(255, 70, 50) or Color3.fromRGB(255, 240, 130)
	for _, side in ipairs({ -1, 1 }) do
		decorate(Enum.PartType.Ball, Vector3.new(size * 0.17, size * 0.17, size * 0.17),
			CFrame.new(side * size * 0.2, size * 0.12, -frontZ), eyeColor, Enum.Material.Neon)
	end

	if def.Spikes then
		for _, dir in ipairs({ Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1), Vector3.new(0.7, 0.7, 0), Vector3.new(-0.7, 0.7, 0) }) do
			local unit = dir.Unit
			decorate(Enum.PartType.Block, Vector3.new(size * 0.16, size * 0.16, size * 0.5),
				CFrame.lookAt(unit * size * 0.55, unit * size), Color3.fromRGB(235, 220, 255), Enum.Material.Neon)
		end
	end

	if def.Wings then
		for _, side in ipairs({ -1, 1 }) do
			decorate(Enum.PartType.Block, Vector3.new(size * 1.1, size * 0.08, size * 0.7),
				CFrame.new(side * size * 0.8, size * 0.1, 0) * CFrame.Angles(0, 0, math.rad(side * 22)), Color3.fromRGB(55, 40, 85))
		end
	end

	if def.Halo then
		decorate(Enum.PartType.Cylinder, Vector3.new(size * 0.1, size * 1.0, size * 1.0),
			CFrame.new(0, size * 0.78, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 255, 255), Enum.Material.Neon)
	end

	if def.Core then
		for _, side in ipairs({ -1, 1 }) do
			decorate(Enum.PartType.Block, Vector3.new(size * 0.5, size * 0.5, size * 0.5),
				CFrame.new(side * size * 0.7, size * 0.35, 0), Color3.fromRGB(95, 90, 88), Enum.Material.Slate)
		end
		decorate(Enum.PartType.Ball, Vector3.new(size * 0.3, size * 0.3, size * 0.3),
			CFrame.new(0, -size * 0.05, -frontZ), Color3.fromRGB(255, 140, 50), Enum.Material.Neon)
	end

	if def.Tusks then
		for _, side in ipairs({ -1, 1 }) do
			decorate(Enum.PartType.Block, Vector3.new(size * 0.14, size * 0.14, size * 0.6),
				CFrame.new(side * size * 0.32, -size * 0.2, -frontZ - size * 0.15) * CFrame.Angles(math.rad(-15), 0, 0),
				Color3.fromRGB(245, 240, 225), Enum.Material.SmoothPlastic)
		end
	end

	if def.Horns then
		for _, side in ipairs({ -1, 1 }) do
			decorate(Enum.PartType.Block, Vector3.new(size * 0.12, size * 0.5, size * 0.12),
				CFrame.new(side * size * 0.28, size * 0.55, 0) * CFrame.Angles(0, 0, math.rad(side * -20)), Color3.fromRGB(40, 20, 30), Enum.Material.SmoothPlastic)
		end
	end

	if def.Shield then
		decorate(Enum.PartType.Block, Vector3.new(size * 0.9, size * 1.05, size * 0.12),
			CFrame.new(0, 0, -frontZ - size * 0.1), Color3.fromRGB(190, 200, 225), Enum.Material.Metal)
		decorate(Enum.PartType.Ball, Vector3.new(size * 0.25, size * 0.25, size * 0.25),
			CFrame.new(0, 0, -frontZ - size * 0.2), Color3.fromRGB(255, 200, 60), Enum.Material.Neon)
	end

	if def.Barrel then
		decorate(Enum.PartType.Block, Vector3.new(size * 0.25, size * 0.25, size * 0.9),
			CFrame.new(0, size * 0.2, -frontZ - size * 0.3), Color3.fromRGB(50, 52, 64), Enum.Material.Metal)
		decorate(Enum.PartType.Ball, Vector3.new(size * 0.35, size * 0.35, size * 0.35),
			CFrame.new(0, size * 0.2, -frontZ - size * 0.75), Color3.fromRGB(150, 110, 255), Enum.Material.Neon)
	end

	if def.Legs then
		for i = 0, 3 do
			for _, side in ipairs({ -1, 1 }) do
				decorate(Enum.PartType.Block, Vector3.new(size * 0.7, size * 0.07, size * 0.07),
					CFrame.new(side * size * 0.55, -size * 0.1, (i - 1.5) * size * 0.22) * CFrame.Angles(0, math.rad((i - 1.5) * 12), math.rad(side * -25)),
					Color3.fromRGB(30, 25, 35), Enum.Material.SmoothPlastic)
			end
		end
	end

	if def.Flame then
		local glow = Instance.new("ParticleEmitter")
		glow.Rate = 45
		glow.Lifetime = NumberRange.new(0.4, 0.8)
		glow.Speed = NumberRange.new(1, 3)
		glow.SpreadAngle = Vector2.new(180, 180)
		glow.LightEmission = 1
		glow.Color = ColorSequence.new(Color3.fromRGB(120, 255, 200))
		glow.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.5), NumberSequenceKeypoint.new(1, 0) })
		glow.Parent = body
	end

	if def.Totem then
		for i = 1, 2 do
			decorate(Enum.PartType.Block, Vector3.new(size * 0.8, size * 0.35, size * 0.8),
				CFrame.new(0, size * (0.3 + 0.35 * i), 0), i == 1 and Color3.fromRGB(110, 75, 50) or Color3.fromRGB(150, 60, 60), Enum.Material.Wood)
		end
		decorate(Enum.PartType.Ball, Vector3.new(size * 0.3, size * 0.3, size * 0.3),
			CFrame.new(0, size * 1.25, 0), Color3.fromRGB(255, 80, 80), Enum.Material.Neon)
	end

	if def.Fuse then
		local fuse = decorate(Enum.PartType.Ball, Vector3.new(size * 0.25, size * 0.25, size * 0.25),
			CFrame.new(0, size * 0.55, 0), Color3.fromRGB(255, 160, 40), Enum.Material.Neon)
		local sparks = Instance.new("ParticleEmitter")
		sparks.Rate = 30
		sparks.Lifetime = NumberRange.new(0.3, 0.6)
		sparks.Speed = NumberRange.new(3, 7)
		sparks.SpreadAngle = Vector2.new(60, 60)
		sparks.LightEmission = 1
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80))
		sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		sparks.Parent = fuse
	end

	return body
end

------------------------------------------------------------
-- 움직임 + 공격 (매 프레임)
------------------------------------------------------------
local function rotateY(vector, degrees)
	return CFrame.Angles(0, math.rad(degrees), 0):VectorToWorldSpace(vector)
end

local function flat(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

-- 잠깐 색을 바꿔 예고한 뒤 action 실행 (그 사이 죽었으면 취소)
local function telegraph(ctx, part, data, color, delay, action)
	part.Color = color
	task.delay(delay, function()
		if not ctx.Alive(part, data) then return end
		part.Color = data.BaseColor
		action()
	end)
end

local function explode(ctx, part, data)
	local center = part.Position
	local damage = data.Stats.ShotDamage
	for _, entry in ipairs(ctx.Players()) do
		-- 벽 너머에서는 폭발 피해를 주지 않는다
		if (entry.Root.Position - center).Magnitude <= 16 and (not ctx.LineOfSight or ctx.LineOfSight(center, entry.Root.Position)) then
			entry.Humanoid:TakeDamage(damage)
		end
	end
	Effects.Burst(center, Color3.fromRGB(255, 130, 50), 55)
	ctx.Kill(part, data)
end

-- 지형이 울퉁불퉁하면(ctx.GroundY 가 있으면) 몬스터를 땅 높이에 맞춘다. lift: 땅에서 더 띄울 높이(박쥐 등)
local function snapToGround(ctx, position, size, lift)
	if not ctx.GroundY then return position end
	local ground = ctx.GroundY(position.X, position.Z, position.Y)
	if not ground then return position end
	return Vector3.new(position.X, ground + size / 2 + (lift or 0), position.Z)
end

function M.Update(ctx, part, data, dt, now)
	local def = data.Def
	local stats = data.Stats
	local target, distance = ctx.GetTarget(part.Position)
	if not target then return end

	local toTarget = flat(target.Position - part.Position)
	local direction = toTarget.Magnitude > 0.1 and toTarget.Unit or Vector3.new(0, 0, -1)
	local position = part.Position

	-- 돌진 중: 정해둔 방향으로 곧장 달리면서 닿으면 피해 (한 번만)
	if data.ChargeUntil and now < data.ChargeUntil then
		local chargeNext = position + data.ChargeDir * 75 * dt
		if not ctx.Walkable or ctx.Walkable(chargeNext.X, chargeNext.Z) then
			position = chargeNext
		else
			data.ChargeUntil = nil -- 벽에 부딪히면 돌진이 끝난다
		end
		position = snapToGround(ctx, position, stats.Size)
		part.CFrame = CFrame.lookAt(position, position + data.ChargeDir)
		if not data.ChargeHit then
			for _, entry in ipairs(ctx.Players()) do
				if (flat(entry.Root.Position - position)).Magnitude <= stats.Size / 2 + 3 then
					entry.Humanoid:TakeDamage(math.floor(stats.ShotDamage * 1.5))
					data.ChargeHit = true
					break
				end
			end
		end
		return
	end
	data.ChargeUntil = nil

	-- 돌진 준비 동작 중에는 제자리에서 대상을 노려본다
	if data.WindupUntil and now < data.WindupUntil then
		part.CFrame = CFrame.lookAt(position, position + direction)
		return
	end

	-- 폭탄병: 가까워지면 도화선이 타들어가며 번쩍이다가 폭발
	if data.FuseAt then
		part.Color = (math.floor(now * 10) % 2 == 0) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(255, 70, 50)
		if now >= data.FuseAt then
			explode(ctx, part, data)
		end
		return
	end

	-- 이동
	local move = Vector3.zero
	local speed = stats.Speed
	if def.Move == "Rush" then
		move = direction * speed * dt
	elseif def.Move == "Keep" then
		if distance < def.Keep - 4 then
			move = -direction * speed * 0.9 * dt
		elseif distance > def.Keep + 6 then
			move = direction * speed * dt
		end
	elseif def.Move == "Static" then
		-- 포탑 / 토템: 제자리에서 조준만 한다
	elseif def.Move == "Hover" then
		if distance > def.Keep then
			move = direction * speed * dt
		end
		-- 좌우로 흔들리며 날아다니고 위아래로 출렁임
		local side = Vector3.new(-direction.Z, 0, direction.X)
		move += side * math.sin(now * 2 + data.Phase) * speed * 0.6 * dt
		local bob = 4 + math.sin(now * 3 + data.Phase) * 1.4
		if ctx.GroundY then
			position = snapToGround(ctx, position, stats.Size, bob)
		else
			position = Vector3.new(position.X, ctx.FloorY + stats.Size / 2 + bob, position.Z)
		end
	else -- Approach
		if distance > stats.Size / 2 + def.Keep then
			move = direction * speed * dt
		end
	end
	-- 벽 / 절벽은 지나가지 못한다 (막히면 그 방향으로는 움직이지 않는다)
	if ctx.Walkable then
		local nextPosition = position + move
		if not ctx.Walkable(nextPosition.X, nextPosition.Z) then
			-- 한 축씩 따로 시도해서 벽을 따라 미끄러지듯 움직인다
			if ctx.Walkable(nextPosition.X, position.Z) then
				move = Vector3.new(move.X, move.Y, 0)
			elseif ctx.Walkable(position.X, nextPosition.Z) then
				move = Vector3.new(0, move.Y, move.Z)
			else
				move = Vector3.zero
			end
		end
	end
	position += move
	if def.Move ~= "Hover" then
		position = snapToGround(ctx, position, stats.Size)
	end
	part.CFrame = CFrame.lookAt(position, position + direction)

	-- 공격
	if def.Attack == "Explode" then
		if distance <= 9 then
			data.FuseAt = now + 0.7
		end
		return
	end
	if distance > def.Range or now < data.NextAttack then return end
	-- 벽 너머로는 공격하지 않는다
	if ctx.LineOfSight and not ctx.LineOfSight(part.Position, target.Position) then return end
	data.NextAttack = now + stats.ShotInterval

	if def.Attack == "Single" then
		telegraph(ctx, part, data, Color3.fromRGB(255, 220, 80), 0.4, function()
			local current = ctx.GetTarget(part.Position)
			if current then
				ctx.Fire(part.Position, current.Position - part.Position, stats.ShotSpeed, stats.ShotDamage, math.max(1.5, stats.Size / 4))
			end
		end)

	elseif def.Attack == "Fan" then
		telegraph(ctx, part, data, Color3.fromRGB(255, 200, 255), 0.45, function()
			local current = ctx.GetTarget(part.Position)
			if not current then return end
			local aim = (current.Position - part.Position).Unit
			for _, angle in ipairs({ -15, 0, 15 }) do
				ctx.Fire(part.Position, rotateY(aim, angle), stats.ShotSpeed, stats.ShotDamage, math.max(1.3, stats.Size / 4), Color3.fromRGB(210, 120, 255))
			end
		end)

	elseif def.Attack == "Ring" then
		telegraph(ctx, part, data, Color3.new(1, 1, 1), 0.6, function()
			local offset = math.random() * math.pi * 2
			for i = 0, 7 do
				local angle = offset + (i / 8) * math.pi * 2
				local ringDirection = Vector3.new(math.cos(angle), 0, math.sin(angle))
				local origin = Vector3.new(part.Position.X, (ctx.GroundY and ctx.GroundY(part.Position.X, part.Position.Z, part.Position.Y) or ctx.FloorY) + 3, part.Position.Z) + ringDirection * (stats.Size / 2 + 1)
				ctx.Fire(origin, ringDirection, 26, math.max(1, math.floor(stats.ShotDamage * 0.8)), 2, Color3.fromRGB(150, 235, 255))
			end
		end)

	elseif def.Attack == "Heavy" then
		telegraph(ctx, part, data, Color3.fromRGB(255, 150, 60), 0.7, function()
			local current = ctx.GetTarget(part.Position)
			if current then
				ctx.Fire(part.Position, current.Position - part.Position, stats.ShotSpeed, stats.ShotDamage, math.max(3.5, stats.Size / 2.5), Color3.fromRGB(255, 130, 40))
			end
		end)

	elseif def.Attack == "Charge" then
		data.NextAttack = now + 4
		data.WindupUntil = now + 0.7
		telegraph(ctx, part, data, Color3.fromRGB(255, 60, 40), 0.7, function()
			local current = ctx.GetTarget(part.Position)
			local aim = current and flat(current.Position - part.Position) or direction
			data.ChargeDir = aim.Magnitude > 0.1 and aim.Unit or direction
			data.ChargeUntil = os.clock() + 0.5
			data.ChargeHit = false
		end)
	end
end

return M
