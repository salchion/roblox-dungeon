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
--   ctx.Fire(origin, direction, speed, damage, size, color, style, opts)   opts: 유도 / 포물선 / 뱀 / 곡선 / 갈라짐 (Effects.MakeShot 참고)
--   ctx.Players() -> { { Root, Humanoid }... }    맞을 수 있는 살아 있는 플레이어들
--   ctx.Alive(part, data) -> bool                 이 몬스터가 아직 살아 있는가
--   ctx.Kill(part, data)                          보상 없이 제거 (자폭용)
--   ctx.FloorY                                     바닥 높이

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Effects = require(script.Parent:WaitForChild("Effects"))
local SoundBank = require(game:GetService("ReplicatedStorage"):WaitForChild("SoundBank"))

local M = {}

-- Range: 이 거리 안에서만 공격 / Keep: 유지하려는 거리 / *Mult: 기본 몬스터 능력치 대비 배율
M.Defs = {
	Slime = {
		Name = "슬라임", Shape = "Ball", Color = Color3.fromRGB(110, 205, 95), Material = Enum.Material.Glass, Transparency = 0.1,
		SizeMult = 1, SpeedMult = 1, HealthMult = 1, DamageMult = 1.2, IntervalMult = 1, ShotSpeedMult = 0.9, GoldMult = 1,
		Attack = "Single", Move = "Approach", Keep = 14, Range = 75,
	},
	Spitter = {
		Name = "가시 독충", Shape = "Ball", Color = Color3.fromRGB(165, 80, 215), Material = Enum.Material.SmoothPlastic,
		SizeMult = 0.95, SpeedMult = 1.1, HealthMult = 0.9, DamageMult = 0.85, IntervalMult = 1.3, ShotSpeedMult = 0.9, GoldMult = 1.1,
		Attack = "Spit", Style = "Needle", Move = "Approach", Keep = 20, Range = 85, Spikes = true,
	},
	Bat = {
		Name = "박쥐", Shape = "Ball", Color = Color3.fromRGB(85, 60, 120), Material = Enum.Material.SmoothPlastic,
		SizeMult = 0.6, SpeedMult = 2.2, HealthMult = 0.55, DamageMult = 0.75, IntervalMult = 0.8, ShotSpeedMult = 1.1, GoldMult = 0.9,
		Attack = "Crescent", Style = "Crescent", Move = "Hover", Keep = 16, Range = 70, Wings = true,
	},
	Mage = {
		Name = "마법사 유령", Shape = "Ball", Color = Color3.fromRGB(115, 185, 225), Material = Enum.Material.Neon, Transparency = 0.25,
		SizeMult = 0.9, SpeedMult = 0.9, HealthMult = 0.8, DamageMult = 0.85, IntervalMult = 2.4, ShotSpeedMult = 0.7, GoldMult = 1.4,
		Attack = "Seeker", Style = "Seeker", Move = "Keep", Keep = 30, Range = 95, Halo = true,
	},
	Golem = {
		Name = "바위 골렘", Shape = "Block", Color = Color3.fromRGB(125, 120, 115), Material = Enum.Material.Slate,
		SizeMult = 1.3, SpeedMult = 0.5, HealthMult = 2.2, DamageMult = 2.1, IntervalMult = 1.8, ShotSpeedMult = 0.55, GoldMult = 1.7,
		Attack = "Slam", Move = "Approach", Keep = 12, Range = 80, Core = true,
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
		SizeMult = 0.7, SpeedMult = 0.9, HealthMult = 0.6, DamageMult = 1.55, IntervalMult = 1.6, ShotSpeedMult = 2.2, GoldMult = 1.3,
		Attack = "Split", Style = "Spear", Move = "Keep", Keep = 55, Range = 130, Horns = true,
	},
	Knight = {
		Name = "방패 기사", Shape = "Block", Color = Color3.fromRGB(120, 140, 175), Material = Enum.Material.Metal,
		SizeMult = 1.15, SpeedMult = 0.7, HealthMult = 2.6, DamageMult = 1.3, IntervalMult = 1.4, ShotSpeedMult = 0.8, GoldMult = 1.8,
		Attack = "Sword", Style = "Spear", Move = "Approach", Keep = 8, Range = 60, Shield = true,
	},
	Turret = {
		Name = "마법 포탑", Shape = "Block", Color = Color3.fromRGB(90, 95, 110), Material = Enum.Material.Metal,
		SizeMult = 1.0, SpeedMult = 0, HealthMult = 1.7, DamageMult = 1.2, IntervalMult = 0.8, ShotSpeedMult = 1.0, GoldMult = 1.4,
		Attack = "Beam", Style = "Needle", Move = "Static", Keep = 0, Range = 110, Barrel = true,
	},
	Spider = {
		Name = "독거미", Shape = "Ball", Color = Color3.fromRGB(60, 50, 60), Material = Enum.Material.SmoothPlastic,
		SizeMult = 0.75, SpeedMult = 1.9, HealthMult = 0.8, DamageMult = 0.95, IntervalMult = 0.7, ShotSpeedMult = 1.1, GoldMult = 1.0,
		Attack = "Burst", Style = "Dart", Move = "Rush", Keep = 0, Range = 45, Legs = true,
	},
	Wisp = {
		Name = "도깨비불", Shape = "Ball", Color = Color3.fromRGB(95, 215, 170), Material = Enum.Material.Neon, Transparency = 0.3,
		SizeMult = 0.55, SpeedMult = 2.4, HealthMult = 0.45, DamageMult = 0.85, IntervalMult = 1.0, ShotSpeedMult = 1.1, GoldMult = 1.1,
		Attack = "Halo", Style = "Halo", Move = "Hover", Keep = 22, Range = 80, Flame = true,
	},
	Healer = {
		Name = "치유 사제", Shape = "Ball", Color = Color3.fromRGB(120, 205, 150), Material = Enum.Material.Neon, Transparency = 0.2,
		SizeMult = 0.95, SpeedMult = 0.8, HealthMult = 1.0, DamageMult = 0.5, IntervalMult = 2.2, ShotSpeedMult = 0.8, GoldMult = 2.2,
		Attack = "Heal", Style = "Orb", Move = "Keep", Keep = 34, Range = 60, Halo = true,
	},
	Totem = {
		Name = "저주 토템", Shape = "Block", Color = Color3.fromRGB(130, 90, 60), Material = Enum.Material.Wood,
		SizeMult = 1.2, SpeedMult = 0, HealthMult = 2.2, DamageMult = 1.1, IntervalMult = 1.8, ShotSpeedMult = 0.7, GoldMult = 1.8,
		Attack = "Ring", Style = "Crystal", Move = "Static", Keep = 0, Range = 100, Totem = true,
	},
}

-- 방패 기사: 정면에서 맞는 공격은 거의 막힌다 (뒤 / 옆에서 쏴야 제대로 들어간다). 막히면 0.12, 아니면 1.
function M.ShieldFactor(part, data, fromPosition)
	local def = data.Def
	if not def or not def.Shield then return 1 end
	local facing = data.Facing or part.CFrame.LookVector
	local toShooter = Vector3.new(fromPosition.X - part.Position.X, 0, fromPosition.Z - part.Position.Z)
	local flatFacing = Vector3.new(facing.X, 0, facing.Z)
	if toShooter.Magnitude < 0.1 or flatFacing.Magnitude < 0.1 then return 1 end
	return (flatFacing.Unit:Dot(toShooter.Unit) > 0.25) and 0.12 or 1
end

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
-- 몸체(body)는 총알이 맞는 "당탁 판정 상자"로만 쓰고 투명하게 둔다. 눈에 보이는 생김새는 여러 부품(머리 / 팔다리 / 날개 ...)을 용접해서 만든다.
-- 몬스터 색이 바뀌는 연출(피격 번쩍임, 돌진 예고)은 body.Color 가 바뀌면 "Tint" 부품들에 전달된다.
local Glass, Neon, Plastic, Metal, Wood, Slate = Enum.Material.Glass, Enum.Material.Neon, Enum.Material.SmoothPlastic, Enum.Material.Metal, Enum.Material.Wood, Enum.Material.Slate
local BALL, BLOCK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local BLACK, WHITE = Color3.new(0, 0, 0), Color3.new(1, 1, 1)

-- 종류별 생김새. S = 몬스터 크기, c = 몸 색. 앞쪽 = -Z, 바닥 = -S/2.
-- d(모양, 가로, 높이, 길이, x, y, z, 색, 재질, { Tint=몸 색 연출 대상, T=투명도, Rx/Ry/Rz=회전(도) })
local Looks = {}

-- 눈: 빛나는 Neon 공 하나씩 (부품 2개). 멀리서도 눈빛이 보이게 한다.
local function eyes(d, S, y, z, spread, color, size)
	for _, side in ipairs({ -1, 1 }) do
		d(BALL, S * size, S * size, S * size * 0.7, side * S * spread, y, z, color, Neon)
	end
end

Looks.Slime = function(S, c, d) -- 슬라임: 납작하고 말랑한 물방울 + 속이 비치는 핵 (9부품)
	local dark = c:Lerp(BLACK, 0.35)
	d(BALL, S * 1.0, S * 0.72, S * 1.0, 0, -S * 0.12, 0, c, Glass, { Tint = true, T = 0.12 })              -- 젤리 몸
	d(BALL, S * 1.25, S * 0.2, S * 1.25, 0, -S * 0.42, 0, dark, Glass, { Tint = true, T = 0.2 })            -- 바닥에 퍼진 치마
	d(BALL, S * 0.5, S * 0.4, S * 0.5, S * 0.12, S * 0.3, S * 0.05, c, Glass, { Tint = true, T = 0.12 })    -- 머리 위 혹
	d(BALL, S * 0.34, S * 0.3, S * 0.34, 0, -S * 0.1, S * 0.12, dark, Plastic, { T = 0.25 })                -- 몸 속 핵
	eyes(d, S, S * 0.02, -S * 0.42, 0.18, Color3.fromRGB(235, 245, 200), 0.17)
	d(BLOCK, S * 0.22, S * 0.05, S * 0.05, 0, -S * 0.16, -S * 0.47, dark, Plastic)                          -- 입
	for _, side in ipairs({ -1, 1 }) do
		d(BALL, S * 0.2, S * 0.2, S * 0.2, side * S * 0.55, -S * 0.34, -S * 0.2, c, Glass, { Tint = true, T = 0.15 }) -- 옆으로 튄 물방울
	end
end

Looks.Spitter = function(S, c, d) -- 가시 독충: 길쭉한 3마디 + 등에 솟은 긴 가시 + 꼬리 침 (12부품)
	local dark, bone, venom = c:Lerp(BLACK, 0.4), Color3.fromRGB(225, 215, 195), Color3.fromRGB(170, 230, 90)
	d(BALL, S * 0.75, S * 0.62, S * 0.8, 0, -S * 0.12, S * 0.05, c, Plastic, { Tint = true })
	d(BALL, S * 0.6, S * 0.5, S * 0.6, 0, -S * 0.2, S * 0.6, dark, Plastic, { Tint = true })
	d(BALL, S * 0.42, S * 0.36, S * 0.42, 0, -S * 0.26, S * 1.0, c, Plastic, { Tint = true })
	d(BALL, S * 0.55, S * 0.5, S * 0.55, 0, -S * 0.04, -S * 0.5, dark, Plastic, { Tint = true })            -- 머리
	eyes(d, S, S * 0.04, -S * 0.76, 0.16, Color3.fromRGB(240, 220, 90), 0.14)
	for _, side in ipairs({ -1, 1 }) do
		d(BLOCK, S * 0.07, S * 0.07, S * 0.38, side * S * 0.16, -S * 0.14, -S * 0.86, bone, Plastic, { Ry = side * 25 }) -- 집게턱
	end
	for i = 0, 2 do -- 등 가시 3개: 뒤로 갈수록 작다
		d(BLOCK, S * 0.1, S * (0.55 - i * 0.1), S * 0.1, 0, S * (0.38 - i * 0.04), -S * 0.2 + i * S * 0.42, bone, Plastic, { Rx = -14 })
	end
	d(BLOCK, S * 0.08, S * 0.3, S * 0.08, 0, -S * 0.02, S * 1.3, venom, Neon, { Rx = -50 })                  -- 꼬리 독침 (작은 포인트 색)
end

Looks.Bat = function(S, c, d) -- 박쥐: 큰 귀 + 넓게 펼친 뾰족 날개 (11부품)
	local dark = c:Lerp(BLACK, 0.4)
	d(BALL, S * 0.55, S * 0.65, S * 0.55, 0, 0, S * 0.05, c, Plastic, { Tint = true })
	d(BALL, S * 0.45, S * 0.42, S * 0.45, 0, S * 0.2, -S * 0.3, c, Plastic, { Tint = true })                 -- 머리
	eyes(d, S, S * 0.24, -S * 0.5, 0.1, Color3.fromRGB(235, 90, 80), 0.1)
	for _, side in ipairs({ -1, 1 }) do
		d(BLOCK, S * 0.1, S * 0.4, S * 0.07, side * S * 0.16, S * 0.5, -S * 0.3, dark, Plastic, { Rz = side * -12 }) -- 큰 뾰족 귀
		d(BLOCK, S * 0.8, S * 0.03, S * 0.55, side * S * 0.6, S * 0.1, S * 0.12, dark, Plastic, { Tint = true, Rz = side * 14 }) -- 날개 막
		d(BLOCK, S * 0.6, S * 0.03, S * 0.2, side * S * 1.1, S * 0.2, -S * 0.02, c, Plastic, { Tint = true, Rz = side * 22, Ry = side * 35 }) -- 날개 끝 (앞으로 쓸린 뾰족 끝)
		d(BLOCK, S * 0.04, S * 0.05, S * 0.12, side * S * 0.08, -S * 0.04, -S * 0.52, WHITE, Plastic)           -- 송곳니
	end
end

Looks.Mage = function(S, c, d) -- 마법사 유령: 흐르는 꼬리 + 큰 뾰족 모자 + 빛나는 지팡이 (12부품)
	local robe, gold = c:Lerp(Color3.fromRGB(40, 50, 120), 0.6), Color3.fromRGB(240, 215, 120)
	d(BALL, S * 0.8, S * 0.95, S * 0.8, 0, 0, 0, c, Plastic, { Tint = true, T = 0.3 })
	d(BALL, S * 0.55, S * 0.6, S * 0.55, S * 0.06, -S * 0.5, S * 0.12, c, Plastic, { Tint = true, T = 0.4 })   -- 꼬리 1
	d(BALL, S * 0.3, S * 0.34, S * 0.3, S * 0.12, -S * 0.82, S * 0.24, c, Plastic, { Tint = true, T = 0.55 }) -- 꼬리 2 (점점 흐려진다)
	d(CYL, S * 0.07, S * 0.95, S * 0.95, 0, S * 0.4, 0, robe, Plastic, { Rz = 90 })                         -- 모자 챙
	d(CYL, S * 0.55, S * 0.55, S * 0.55, 0, S * 0.68, 0, robe, Plastic, { Rz = 90 })
	d(CYL, S * 0.4, S * 0.28, S * 0.28, S * 0.05, S * 1.0, 0, robe, Plastic, { Rz = 90, Rx = 0 })           -- 모자 끝
	d(BALL, S * 0.12, S * 0.12, S * 0.12, S * 0.1, S * 1.22, 0, gold, Neon)
	eyes(d, S, S * 0.1, -S * 0.38, 0.16, Color3.fromRGB(235, 250, 255), 0.13)
	d(BLOCK, S * 0.06, S * 1.3, S * 0.06, S * 0.55, S * 0.02, -S * 0.22, Color3.fromRGB(105, 75, 55), Wood)  -- 지팡이
	d(BALL, S * 0.24, S * 0.24, S * 0.24, S * 0.55, S * 0.72, -S * 0.22, Color3.fromRGB(130, 200, 235), Neon)
	d(BALL, S * 0.16, S * 0.16, S * 0.16, S * 0.42, -S * 0.06, -S * 0.3, c, Plastic, { Tint = true, T = 0.2 }) -- 손
end

Looks.Golem = function(S, c, d) -- 바위 골렘: 웅크린 거대 어깨 + 낮은 머리 + 땅에 닿는 큰 주먹 (14부품)
	local dark, moss, ember = c:Lerp(BLACK, 0.35), Color3.fromRGB(85, 120, 75), Color3.fromRGB(235, 140, 60)
	d(BLOCK, S * 0.85, S * 0.7, S * 0.6, 0, S * 0.05, 0, c, Slate, { Tint = true })                           -- 몸통
	d(BLOCK, S * 0.4, S * 0.3, S * 0.38, 0, S * 0.42, -S * 0.12, dark, Slate, { Tint = true, Rz = 4 })      -- 어깨 사이에 파묻힌 머리
	eyes(d, S, S * 0.45, -S * 0.32, 0.12, ember, 0.09)
	d(BLOCK, S * 0.22, S * 0.3, S * 0.04, 0, S * 0.08, -S * 0.31, ember, Neon, { Rz = 12 })                  -- 가슴 균열의 불빛
	for _, side in ipairs({ -1, 1 }) do
		d(BLOCK, S * 0.3, S * 0.7, S * 0.3, side * S * 0.62, -S * 0.1, 0, c, Slate, { Tint = true, Rz = side * 8 })       -- 긴 팔
		d(BLOCK, S * 0.46, S * 0.42, S * 0.46, side * S * 0.7, -S * 0.5, -S * 0.04, dark, Slate, { Tint = true })         -- 거대한 주먹
		d(BLOCK, S * 0.42, S * 0.34, S * 0.42, side * S * 0.5, S * 0.42, 0, dark, Slate, { Rx = 20, Rz = side * 25 })     -- 어깨 바위
		d(BLOCK, S * 0.34, S * 0.36, S * 0.34, side * S * 0.2, -S * 0.42, 0, c, Slate, { Tint = true })                   -- 짧은 다리
	end
	d(BLOCK, S * 0.3, S * 0.05, S * 0.3, -S * 0.3, S * 0.62, S * 0.1, moss, Plastic)                          -- 어깨 이끼
end

Looks.Charger = function(S, c, d) -- 돌진 멧돼지: 낮고 긴 몸 + 큰 머리 + 위로 휜 엄니 + 등 갈기 (14부품)
	local dark, tusk = c:Lerp(BLACK, 0.45), Color3.fromRGB(240, 232, 212)
	d(BLOCK, S * 0.8, S * 0.62, S * 1.3, 0, S * 0.04, S * 0.14, c, Plastic, { Tint = true })                  -- 몸
	d(BLOCK, S * 0.66, S * 0.58, S * 0.5, 0, -S * 0.02, -S * 0.56, dark, Plastic, { Tint = true })           -- 머리 (몸보다 어둡다)
	d(BLOCK, S * 0.38, S * 0.28, S * 0.3, 0, -S * 0.1, -S * 0.9, c:Lerp(WHITE, 0.2), Plastic)               -- 주둥이
	d(BLOCK, S * 0.2, S * 0.2, S * 1.1, 0, S * 0.4, S * 0.1, dark, Plastic, { Rx = -8 })                      -- 등 갈기
	eyes(d, S, S * 0.1, -S * 0.82, 0.2, Color3.fromRGB(235, 80, 55), 0.1)
	for _, side in ipairs({ -1, 1 }) do
		d(BLOCK, S * 0.08, S * 0.1, S * 0.5, side * S * 0.2, -S * 0.2, -S * 0.98, tusk, Plastic, { Rx = 28, Ry = side * -8 }) -- 위로 휜 엄니
		d(BLOCK, S * 0.2, S * 0.28, S * 0.06, side * S * 0.3, S * 0.3, -S * 0.5, dark, Plastic, { Rz = side * -25 })   -- 귀
		d(BLOCK, S * 0.22, S * 0.4, S * 0.22, side * S * 0.28, -S * 0.38, -S * 0.35, dark, Plastic)                     -- 앞다리
		d(BLOCK, S * 0.22, S * 0.4, S * 0.22, side * S * 0.28, -S * 0.38, S * 0.6, dark, Plastic)                      -- 뒷다리
	end
end

Looks.Bomber = function(S, c, d) -- 폭탄병: 쇠 구슬 + 허리 띠 + 타는 심지 (10부품, 입자 없음)
	local dark, belt = c:Lerp(BLACK, 0.3), Color3.fromRGB(150, 70, 55)
	d(BALL, S * 0.95, S * 0.95, S * 0.95, 0, -S * 0.02, 0, c, Metal, { Tint = true })                         -- 폭탄 몸통
	d(CYL, S * 0.2, S * 1.0, S * 1.0, 0, -S * 0.12, 0, belt, Metal, { Rz = 90 })                              -- 붉은 허리 띠
	d(CYL, S * 0.16, S * 0.34, S * 0.34, 0, S * 0.5, 0, dark, Metal, { Rz = 90 })                             -- 꼭지
	d(BLOCK, S * 0.05, S * 0.32, S * 0.05, S * 0.05, S * 0.72, 0, Color3.fromRGB(150, 120, 80), Plastic, { Rz = -20 }) -- 심지
	d(BALL, S * 0.22, S * 0.22, S * 0.22, S * 0.12, S * 0.9, 0, Color3.fromRGB(255, 170, 60), Neon)           -- 심지 불꽃
	for _, side in ipairs({ -1, 1 }) do
		d(BALL, S * 0.22, S * 0.14, S * 0.32, side * S * 0.22, -S * 0.48, -S * 0.08, dark, Plastic)             -- 발
		d(BLOCK, S * 0.24, S * 0.07, S * 0.05, side * S * 0.2, S * 0.16, -S * 0.46, Color3.fromRGB(235, 70, 50), Neon, { Rz = side * 22 }) -- 화난 눈
	end
	d(BALL, S * 0.28, S * 0.28, S * 0.05, 0, -S * 0.2, -S * 0.46, Color3.fromRGB(230, 225, 210), Plastic)     -- 해골 표시
end

Looks.Imp = function(S, c, d) -- 저격 임프: 긴 뿔 + 박쥐 날개 + 화살촉 꼬리 + 삼지창 (14부품)
	local dark, horn = c:Lerp(BLACK, 0.45), Color3.fromRGB(45, 25, 35)
	d(BALL, S * 0.55, S * 0.7, S * 0.5, 0, -S * 0.12, 0, c, Plastic, { Tint = true })                         -- 몸
	d(BALL, S * 0.52, S * 0.46, S * 0.48, 0, S * 0.3, -S * 0.04, c, Plastic, { Tint = true })                 -- 머리
	eyes(d, S, S * 0.32, -S * 0.27, 0.14, Color3.fromRGB(240, 225, 90), 0.12)
	for _, side in ipairs({ -1, 1 }) do
		d(BLOCK, S * 0.08, S * 0.5, S * 0.08, side * S * 0.2, S * 0.68, 0, horn, Plastic, { Rz = side * -24 })  -- 긴 뿔
		d(BLOCK, S * 0.7, S * 0.03, S * 0.45, side * S * 0.55, S * 0.12, S * 0.2, dark, Plastic, { Rz = side * 28 }) -- 날개
		d(BLOCK, S * 0.14, S * 0.32, S * 0.14, side * S * 0.14, -S * 0.52, 0, c, Plastic, { Tint = true })      -- 다리
	end
	d(BLOCK, S * 0.05, S * 0.05, S * 0.6, 0, -S * 0.3, S * 0.45, dark, Plastic, { Rx = 25 })                  -- 꼬리
	d(BLOCK, S * 0.22, S * 0.22, S * 0.05, 0, -S * 0.1, S * 0.78, horn, Plastic, { Rz = 45 })                 -- 꼬리 끝 화살촉
	d(BLOCK, S * 0.04, S * 1.0, S * 0.04, S * 0.42, -S * 0.05, -S * 0.3, Color3.fromRGB(120, 90, 60), Wood) -- 삼지창 자루
	d(BLOCK, S * 0.24, S * 0.05, S * 0.05, S * 0.42, S * 0.44, -S * 0.3, horn, Metal)                         -- 삼지창 날
end

Looks.Knight = function(S, c, d)
	local dark, gold = c:Lerp(BLACK, 0.4), Color3.fromRGB(255, 200, 60)
	d(BLOCK, S * 0.7, S * 0.6, S * 0.45, 0, S * 0.0, 0, c, Metal, { Tint = true })                  -- 갑옷 몸통
	d(BLOCK, S * 0.55, S * 0.16, S * 0.4, 0, -S * 0.34, 0, dark, Metal)                              -- 허리 치마
	d(CYL, S * 0.4, S * 0.4, S * 0.4, 0, S * 0.47, 0, c, Metal, { Tint = true, Rz = 90 })           -- 투구
	d(BLOCK, S * 0.3, S * 0.05, S * 0.04, 0, S * 0.5, -S * 0.2, Color3.fromRGB(255, 190, 90), Neon)  -- 투구 눈 틈
	d(BLOCK, S * 0.07, S * 0.3, S * 0.3, 0, S * 0.75, 0, Color3.fromRGB(210, 50, 50), Plastic)      -- 투구 깃털
	for _, side in ipairs({ -1, 1 }) do
		d(BALL, S * 0.28, S * 0.22, S * 0.28, side * S * 0.45, S * 0.28, 0, dark, Metal)             -- 어깨 갑옷
		d(BLOCK, S * 0.2, S * 0.5, S * 0.2, side * S * 0.5, -S * 0.02, 0, c, Metal, { Tint = true })  -- 팔
		d(BLOCK, S * 0.24, S * 0.42, S * 0.24, side * S * 0.18, -S * 0.5 + S * 0.08, 0, c, Metal, { Tint = true }) -- 다리
	end
	d(BLOCK, S * 1.0, S * 0.95, S * 0.1, 0, S * 0.02, -S * 0.52, Color3.fromRGB(190, 200, 225), Metal) -- 정면을 가리는 큰 방패 (정면 공격은 거의 안 들어간다, 뒤로 돌아가서 쏴야 함)
	d(BALL, S * 0.28, S * 0.28, S * 0.06, 0, S * 0.1, -S * 0.6, gold, Neon)
	d(BLOCK, S * 0.06, S * 0.8, S * 0.04, S * 0.52, S * 0.1, -S * 0.2, Color3.fromRGB(215, 220, 230), Metal, { Rx = -20 }) -- 검
	d(BLOCK, S * 0.2, S * 0.05, S * 0.05, S * 0.52, -S * 0.2, -S * 0.12, gold, Metal)
end

Looks.Turret = function(S, c, d) -- 마법 포탑: 넓은 받침 + 삼각 다리 + 돔 머리 + 긴 포신 + 붉은 센서 눈 (12부품)
	local dark = c:Lerp(BLACK, 0.4)
	d(CYL, S * 0.35, S * 1.0, S * 1.0, 0, -S * 0.38, 0, dark, Metal, { Rz = 90 })                             -- 넓은 받침
	for i = 0, 2 do -- 삼각대 다리
		local a = i / 3 * math.pi * 2
		d(BLOCK, S * 0.12, S * 0.55, S * 0.12, math.cos(a) * S * 0.38, -S * 0.2, math.sin(a) * S * 0.38, dark, Metal, { Rz = math.cos(a) * 20, Rx = -math.sin(a) * 20 })
	end
	d(BALL, S * 0.7, S * 0.6, S * 0.7, 0, S * 0.15, 0, c, Metal, { Tint = true })                              -- 돔 머리
	d(BLOCK, S * 0.22, S * 0.22, S * 0.85, 0, S * 0.18, -S * 0.68, Color3.fromRGB(55, 58, 70), Metal)         -- 포신
	d(CYL, S * 0.1, S * 0.32, S * 0.32, 0, S * 0.18, -S * 1.08, dark, Metal, { Ry = 90 })                      -- 포구 링
	d(BALL, S * 0.18, S * 0.18, S * 0.18, 0, S * 0.18, -S * 1.1, Color3.fromRGB(150, 120, 235), Neon)
	d(BALL, S * 0.2, S * 0.2, S * 0.1, 0, S * 0.3, -S * 0.34, Color3.fromRGB(235, 80, 70), Neon)               -- 센서 눈
	for _, side in ipairs({ -1, 1 }) do
		d(BLOCK, S * 0.08, S * 0.45, S * 0.5, side * S * 0.38, S * 0.28, S * 0.05, dark, Metal, { Rz = side * -12 }) -- 옆 방어판
	end
end

Looks.Spider = function(S, c, d) -- 독거미: 큰 배 + 낮은 머리 + 높게 솟은 꺾인 다리 4쌍 (14부품)
	local dark, fang = c:Lerp(BLACK, 0.25), Color3.fromRGB(235, 228, 210)
	d(BALL, S * 0.75, S * 0.65, S * 0.85, 0, S * 0.02, S * 0.4, c, Plastic, { Tint = true })                   -- 큰 배
	d(BALL, S * 0.48, S * 0.4, S * 0.48, 0, -S * 0.04, -S * 0.18, dark, Plastic, { Tint = true })             -- 머리가슴
	eyes(d, S, S * 0.06, -S * 0.38, 0.1, Color3.fromRGB(240, 70, 60), 0.11)
	for _, side in ipairs({ -1, 1 }) do
		d(BLOCK, S * 0.05, S * 0.2, S * 0.05, side * S * 0.08, -S * 0.2, -S * 0.44, fang, Plastic, { Rx = 15 }) -- 송곳니
		for i = 0, 3 do -- 다리: 위로 솟았다 아래로 꺾이는 긴 막대 하나
			local lean = (i - 1.5) * 16
			d(BLOCK, S * 0.8, S * 0.07, S * 0.07, side * S * 0.62, -S * 0.02, -S * 0.2 + i * S * 0.22, dark, Plastic, { Rz = side * -38, Ry = side * lean })
		end
	end
end

Looks.Wisp = function(S, c, d) -- 도깨비불: 눈물방울 모양 불꽃 + 흩날리는 꼬리불 + 도는 곁불 (10부품 + 입자 1)
	d(BALL, S * 0.7, S * 0.8, S * 0.7, 0, S * 0.0, 0, c, Neon, { Tint = true, T = 0.25 })
	d(BALL, S * 0.36, S * 0.46, S * 0.36, 0, S * 0.04, 0, c:Lerp(WHITE, 0.7), Neon, { T = 0.35 })               -- 밝은 속불
	d(BLOCK, S * 0.14, S * 0.45, S * 0.14, 0, S * 0.55, 0, c, Neon, { Tint = true, T = 0.35, Rz = 14 })        -- 위로 솟는 불꽃 끝
	for i = 1, 3 do
		d(BALL, S * (0.5 - i * 0.12), S * (0.55 - i * 0.12), S * (0.5 - i * 0.12), math.sin(i * 1.7) * S * 0.12, -S * (0.3 + i * 0.2), S * 0.12 * i, c, Neon, { Tint = true, T = 0.3 + i * 0.12 })
	end
	for _, side in ipairs({ -1, 1 }) do
		d(BALL, S * 0.14, S * 0.22, S * 0.06, side * S * 0.16, S * 0.08, -S * 0.34, Color3.fromRGB(20, 55, 45), Plastic) -- 눈
	end
	d(BALL, S * 0.16, S * 0.16, S * 0.16, S * 0.6, S * 0.1, S * 0.1, c, Neon, { T = 0.35 })                    -- 곁불
	local glow = Instance.new("ParticleEmitter")
	glow.Rate = 25
	glow.Lifetime = NumberRange.new(0.4, 0.8)
	glow.Speed = NumberRange.new(1, 3)
	glow.SpreadAngle = Vector2.new(180, 180)
	glow.LightEmission = 1
	glow.Color = ColorSequence.new(c)
	glow.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, S * 0.5), NumberSequenceKeypoint.new(1, 0) })
	glow.Parent = d.Body
end

Looks.Healer = function(S, c, d) -- 치유 사제: 둥근 몸 + 긴 로브 + 머리 위 후광 + 십자 + 모은 손 (9부품)
	local cream, green = Color3.fromRGB(235, 240, 225), Color3.fromRGB(130, 220, 160)
	d(BALL, S * 0.75, S * 0.85, S * 0.75, 0, S * 0.08, 0, c, Plastic, { Tint = true, T = 0.2 })
	d(CYL, S * 0.45, S * 1.0, S * 1.0, 0, -S * 0.32, 0, cream, Plastic, { Rz = 90 })                           -- 하얀 로브 자락
	d(CYL, S * 0.05, S * 0.9, S * 0.9, 0, S * 0.7, 0, Color3.fromRGB(245, 225, 140), Neon, { Rz = 90 })        -- 후광
	d(BLOCK, S * 0.1, S * 0.44, S * 0.1, 0, S * 1.1, 0, green, Neon)                                          -- 십자 세로
	d(BLOCK, S * 0.4, S * 0.1, S * 0.1, 0, S * 1.14, 0, green, Neon)                                          -- 십자 가로
	eyes(d, S, S * 0.14, -S * 0.34, 0.15, Color3.fromRGB(250, 250, 235), 0.12)
	for _, side in ipairs({ -1, 1 }) do
		d(BALL, S * 0.16, S * 0.16, S * 0.16, side * S * 0.2, -S * 0.1, -S * 0.38, cream, Plastic)            -- 모은 손
	end
end

Looks.Totem = function(S, c, d) -- 저주 토템: 3단 기둥 + 얼굴 + 양 날개 + 뿔 + 꼭대기 구슬 (13부품)
	local dark, red, teal = c:Lerp(BLACK, 0.35), Color3.fromRGB(165, 65, 60), Color3.fromRGB(70, 140, 165)
	d(BLOCK, S * 0.75, S * 0.5, S * 0.75, 0, -S * 0.3, 0, c, Wood, { Tint = true })                            -- 아래 토막
	d(BLOCK, S * 0.62, S * 0.5, S * 0.62, 0, S * 0.15, 0, dark, Wood)                                          -- 가운데 토막
	d(BLOCK, S * 0.85, S * 0.5, S * 0.85, 0, S * 0.6, 0, red, Wood, { Tint = true })                           -- 얼굴 토막 (제일 넓다)
	eyes(d, S, S * 0.66, -S * 0.43, 0.2, Color3.fromRGB(240, 210, 90), 0.16)
	d(BLOCK, S * 0.42, S * 0.1, S * 0.05, 0, S * 0.5, -S * 0.44, Color3.new(0.1, 0.05, 0.05), Plastic)        -- 입
	for _, side in ipairs({ -1, 1 }) do
		d(BLOCK, S * 0.7, S * 0.12, S * 0.14, side * S * 0.62, S * 0.15, 0, dark, Wood, { Rz = side * 12 })    -- 양 날개 막대
		d(BLOCK, S * 0.5, S * 0.3, S * 0.05, side * S * 0.7, -S * 0.08, 0, teal, Plastic, { Rz = side * 12 })  -- 날개 깃
		d(BLOCK, S * 0.1, S * 0.45, S * 0.1, side * S * 0.32, S * 1.0, 0, dark, Wood, { Rz = side * -22 })     -- 뿔
	end
	d(BALL, S * 0.28, S * 0.28, S * 0.28, 0, S * 1.05, 0, Color3.fromRGB(235, 90, 80), Neon)                   -- 꼭대기 저주 구슬
end

function M.Build(typeKey, size, color, position, parent)
	local def = M.Defs[typeKey]

	-- 판정용 몸체: 눈에 안 보이는 상자 (총알 / 레이더 / 체력바는 이걸 기준으로 한다)
	local body = Instance.new("Part")
	body.Name = "Monster"
	body.Anchored = true
	body.CanCollide = false
	body.Transparency = 1
	body.Color = color
	if def.Shape == "Ball" then
		body.Shape = Enum.PartType.Ball
		body.Size = Vector3.new(size, size, size)
	else
		body.Size = Vector3.new(size, size * 0.9, size * 1.15)
	end
	body.CFrame = CFrame.new(position)
	body.Parent = parent
	game:GetService("CollectionService"):AddTag(body, "Monster") -- 클라이언트 레이더용

	local skins = {}
	local function d(shape, sx, sy, sz, x, y, z, partColor, material, opts)
		opts = opts or {}
		local part = Instance.new("Part")
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.Shape = shape
		part.Size = Vector3.new(math.max(0.05, sx), math.max(0.05, sy), math.max(0.05, sz))
		part.Color = partColor
		part.Material = material or Plastic
		part.Transparency = opts.T or (def.Transparency and opts.Tint and def.Transparency) or 0
		part.CFrame = body.CFrame * CFrame.new(x, y, z) * CFrame.Angles(math.rad(opts.Rx or 0), math.rad(opts.Ry or 0), math.rad(opts.Rz or 0))
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = part
		weld.Parent = part
		part.Parent = body
		if opts.Tint then
			table.insert(skins, { Part = part, Color = partColor })
		end
		return part
	end
	local build = Looks[typeKey]
	if build then
		-- Wisp 처럼 몸체에 입자를 붙여야 하는 종류가 있어서 d.Body 로 몸체를 알려 준다 (함수 표처럼 쓴다)
		local helper = setmetatable({ Body = body }, { __call = function(_, ...) return d(...) end })
		build(size, color, helper)
	end
	-- 몸 색이 바뀌면(피격 번쩍임 / 예고) 눈에 보이는 몸 부품들도 같이 바뀐다. 원래 색으로 돌아오면 각자 원래 색으로 복원.
	local baseColor = color
	body:GetPropertyChangedSignal("Color"):Connect(function()
		local now = body.Color
		for _, skin in ipairs(skins) do
			if skin.Part.Parent then
				skin.Part.Color = (now == baseColor) and skin.Color or now
			end
		end
	end)
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

-- 몸 기울임(몸체 CFrame 에 곱하는 값 하나뿐이라 서버 부담이 없다): 이동 방향으로 숙이고, 숨 쉬듯 흔들리고, 공격 직전에는 뒤로 젖힌다.
-- moving: 이번 프레임에 움직였는가
local function bodyTilt(data, def, now, dt, moving)
	local target
	if data.RearUntil and now < data.RearUntil then
		target = 0.38 -- 뒤로 젖힘 (앞쪽 = -Z, +X 회전이 머리를 뒤로 넘긴다)
	elseif moving then
		target = def.Move == "Hover" and -0.1 or -0.14
	else
		target = 0
	end
	local lean = (data.Lean or 0) + (target - (data.Lean or 0)) * math.min(1, dt * 10)
	data.Lean = lean
	local sway = 0
	if def.Move ~= "Static" then
		sway = math.sin(now * (moving and 6 or 2) + (data.Phase or 0)) * (moving and 0.07 or 0.025) -- 걸음 / 숨쉬기 좌우 흔들림
	end
	local breath = (moving or def.Move == "Static") and 0 or math.sin(now * 2.2 + (data.Phase or 0)) * 0.03
	return CFrame.Angles(lean + breath, 0, sway)
end

-- 잠깐 색을 바꿔 예고한 뒤 action 실행 (그 사이 죽었으면 취소)
-- 빙빙 돌며 피하는 플레이도 맞도록: 정면 탄 옆으로 양쪽 "옆 탄"을 같이 쏜다.
-- 가만히 서 있으면 옆 탄은 몸 옆을 스치고(정면만 피하면 됨), 옆으로 돌며 달리면 옆 탄이 길목을 막는다.
local FLANK_ANGLE = 13
-- (탄 수를 줄이려고) noFlank 가 true 면 정면 한 발만 쏜다: 호출하는 쪽이 두 번에 한 번만 옆 탄을 붙인다
local function fireFlanked(ctx, part, target, speed, damage, size, color, style, noFlank)
	local aim = target.Position - part.Position
	if aim.Magnitude < 0.1 then return end
	aim = aim.Unit
	ctx.Fire(part.Position, aim, speed, damage, size, color, style)
	if noFlank or (target.Position - part.Position).Magnitude < 10 then return end -- 너무 가까우면 옆 탄은 의미 없다
	local sideDamage = math.max(1, math.floor(damage * 0.7))
	for _, angle in ipairs({ -FLANK_ANGLE, FLANK_ANGLE }) do
		ctx.Fire(part.Position, rotateY(aim, angle), speed, sideDamage, size * 0.85, color, style)
	end
end

local function telegraph(ctx, part, data, color, delay, action)
	part.Color = color
	data.RearUntil = os.clock() + delay -- 공격 직전: 몸을 뒤로 젖힌다 (Update 의 기울임이 읽는다)
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


-- 경사 위에서는 몸을 경사에 맞춰 눕힌다 (큰 몬스터가 경사에 파묻히거나 허공에 뜨지 않게). ctx.Slope(x, size) = 라디안 (필드만 제공)
local function slopeTilt(ctx, position, size)
	local angle = ctx.Slope and ctx.Slope(position.X, size) or 0
	return CFrame.new(position) * CFrame.Angles(0, 0, angle) * CFrame.new(-position)
end

-- 바닥 높이
local function groundOf(ctx, position)
	if ctx.GroundY then
		return ctx.GroundY(position.X, position.Z, position.Y) or ctx.FloorY
	end
	return ctx.FloorY
end

-- 점 p 에서 선분 a-b 까지의 평면 거리
local function distToSegment(p, a, b)
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local ap = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
	local t = math.clamp(ap:Dot(ab) / math.max(ab:Dot(ab), 0.001), 0, 1)
	local closest = ab * t
	return (ap - closest).Magnitude
end

local function disc(position, diameter, color, transparency)
	local d = Instance.new("Part")
	d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
	d.Shape = Enum.PartType.Cylinder
	d.Material = Enum.Material.Neon
	d.Color = color
	d.Transparency = transparency
	d.Size = Vector3.new(0.4, diameter, diameter)
	d.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	d.Parent = workspace
	return d
end

-- 박격포: 바닥에 붉은 경고 원이 차오르다가 하늘에서 운석이 떨어져 폭발 (원 밖으로 피하면 안 맞는다)
local function meteor(ctx, spot, stats, owner, ownerData)
	local ground = groundOf(ctx, spot)
	local radius = 9
	local delay = 1.2
	local ring = disc(Vector3.new(spot.X, ground + 0.3, spot.Z), radius * 2, Color3.fromRGB(255, 60, 50), 0.7)
	local fill = disc(Vector3.new(spot.X, ground + 0.35, spot.Z), 1, Color3.fromRGB(255, 90, 60), 0.4)
	TweenService:Create(fill, TweenInfo.new(delay, Enum.EasingStyle.Linear), { Size = Vector3.new(0.4, radius * 2, radius * 2) }):Play()
	local rock = Instance.new("Part")
	rock.Anchored, rock.CanCollide, rock.CanQuery, rock.CanTouch = true, false, false, false
	rock.Shape = Enum.PartType.Ball
	rock.Material = Enum.Material.Neon
	rock.Color = Color3.fromRGB(255, 140, 50)
	rock.Size = Vector3.new(5, 5, 5)
	rock.Position = Vector3.new(spot.X, ground + 70, spot.Z)
	rock.Parent = workspace
	TweenService:Create(rock, TweenInfo.new(delay, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = Vector3.new(spot.X, ground + 2, spot.Z) }):Play()
	task.delay(delay, function()
		rock:Destroy()
		ring:Destroy()
		fill:Destroy()
		local center = Vector3.new(spot.X, ground, spot.Z)
		Effects.Burst(center + Vector3.new(0, 2, 0), Color3.fromRGB(255, 140, 50), 40)
		local boom = disc(center + Vector3.new(0, 0.5, 0), 2, Color3.fromRGB(255, 170, 70), 0.3)
		TweenService:Create(boom, TweenInfo.new(0.35), { Size = Vector3.new(0.4, radius * 2.2, radius * 2.2), Transparency = 1 }):Play()
		Debris:AddItem(boom, 0.4)
		SoundBank.Play(boom, "Boom", { Volume = 0.8 })
		for _, entry in ipairs(ctx.Players()) do
			local p = entry.Root.Position
			if Vector3.new(p.X - spot.X, 0, p.Z - spot.Z).Magnitude <= radius then
				entry.Humanoid:TakeDamage(math.floor(stats.ShotDamage * 1.2))
			end
		end
	end)
end

-- 충격파: 발밑에서 고리가 퍼진다. 점프해서 넘으면 안 맞는다
local function shockwave(ctx, part, stats)
	local origin = part.Position
	local ground = groundOf(ctx, origin)
	local radius = 24
	local wave = disc(Vector3.new(origin.X, ground + 0.4, origin.Z), 2, Color3.fromRGB(255, 190, 90), 0.2)
	TweenService:Create(wave, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.8, radius * 2, radius * 2), Transparency = 0.9 }):Play()
	Debris:AddItem(wave, 0.55)
	Effects.Burst(Vector3.new(origin.X, ground + 1, origin.Z), Color3.fromRGB(190, 170, 140), 25)
	SoundBank.Play(wave, "Boom", { Volume = 0.7, Pitch = 1.1 })
	task.delay(0.25, function()
		for _, entry in ipairs(ctx.Players()) do
			local p = entry.Root.Position
			local flatDist = Vector3.new(p.X - origin.X, 0, p.Z - origin.Z).Magnitude
			if flatDist <= radius and p.Y - groundOf(ctx, p) < 5 then
				entry.Humanoid:TakeDamage(math.floor(stats.ShotDamage * 1.1))
			end
		end
	end)
end

-- 레이저: 가는 붉은 선이 잠깐 조준한 뒤 굵은 빛줄기가 쏟아진다 (선에서 벗어나면 안 맞는다)
local function laser(ctx, part, data, stats, aimDir, range)
	local origin = part.Position
	local target = origin + aimDir * range
	local length = range
	local function lineAt(thickness, color, transparency)
		local line = Instance.new("Part")
		line.Anchored, line.CanCollide, line.CanQuery, line.CanTouch = true, false, false, false
		line.Material = Enum.Material.Neon
		line.Color = color
		line.Transparency = transparency
		line.Size = Vector3.new(thickness, thickness, length)
		line.CFrame = CFrame.lookAt(origin, target) * CFrame.new(0, 0, -length / 2)
		line.Parent = workspace
		return line
	end
	local warn = lineAt(0.5, Color3.fromRGB(255, 60, 60), 0.35)
	task.delay(0.9, function()
		warn:Destroy()
		if not ctx.Alive(part, data) then return end
		local beam = lineAt(5, Color3.fromRGB(255, 240, 200), 0.1)
		TweenService:Create(beam, TweenInfo.new(0.35), { Transparency = 1, Size = Vector3.new(1, 1, length) }):Play()
		Debris:AddItem(beam, 0.4)
		for _, entry in ipairs(ctx.Players()) do
			if distToSegment(entry.Root.Position, origin, target) <= 3.5 then
				entry.Humanoid:TakeDamage(math.floor(stats.ShotDamage * 1.6))
			end
		end
	end)
end

function M.Update(ctx, part, data, dt, now)
	local def = data.Def
	local stats = data.Stats
	local target, distance = ctx.GetTarget(part.Position)
	if not target then return end

	local toTarget = flat(target.Position - part.Position)
	local direction = toTarget.Magnitude > 0.1 and toTarget.Unit or Vector3.new(0, 0, -1)
	local position = part.Position
	-- 벽 때문에 플레이어가 안 보이면 곧장 가지 않고 길(방 사이 통로 / 벽의 틈)을 따라 돌아서 간다
	if ctx.NextStep and ctx.LineOfSight and not ctx.LineOfSight(position, target.Position) then
		local waypoint = ctx.NextStep(data, position, target.Position)
		if waypoint then
			local toWaypoint = flat(waypoint - position)
			if toWaypoint.Magnitude > 0.5 then
				direction = toWaypoint.Unit
			end
		end
	end

	-- 돌진 중: 정해둔 방향으로 곧장 달리면서 닿으면 피해 (한 번만)
	if data.ChargeUntil and now < data.ChargeUntil then
		local chargeNext = position + data.ChargeDir * 75 * dt
		if not ctx.Walkable or ctx.Walkable(chargeNext.X, chargeNext.Z) then
			position = chargeNext
		else
			data.ChargeUntil = nil -- 벽에 부딪히면 돌진이 끝난다
		end
		position = snapToGround(ctx, position, stats.Size)
		part.CFrame = slopeTilt(ctx, position, stats.Size) * CFrame.lookAt(position, position + data.ChargeDir)
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
		part.CFrame = slopeTilt(ctx, position, stats.Size) * CFrame.lookAt(position, position + direction) * bodyTilt(data, def, now, dt, false)
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
	-- 박진감: 곧장 걸어오지 않고 좌우로 흔들리며 접근하고, 가까워지면 가끔 확 덮치는 돌진 가속
	if (def.Move == "Approach" or def.Move == "Rush") and distance > 8 then
		local sideways = Vector3.new(-direction.Z, 0, direction.X)
		move += sideways * math.sin(now * 3.2 + data.Phase) * speed * 0.45 * dt
		if distance < 45 and now >= (data.NextLunge or 0) then
			data.LungeUntil = now + 0.5
			data.NextLunge = now + 2.5 + math.random() * 2.5
		end
		if data.LungeUntil and now < data.LungeUntil then
			move += direction * speed * 1.6 * dt
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
	local moving = move.X ~= 0 or move.Z ~= 0
	if def.Move ~= "Hover" then
		position = snapToGround(ctx, position, stats.Size)
		-- 통통 튀며 다가온다 (걷는 느낌보다 훨씬 역동적): 종류마다 튀는 높이가 다르다
		if def.Move ~= "Static" and def.Move ~= "Keep" then
			local hop = (def.Shape == "Ball" and 0.5 or 0.22) * stats.Size
			position += Vector3.new(0, math.abs(math.sin(now * 6 + data.Phase)) * hop, 0)
		end
	end
	local lookDirection = direction
	if def.Shield then
		-- 방패 기사: 몸을 천천히(초당 약 60도) 돌려서 정면이 플레이어를 향한다 -> 옆 / 뒤로 빠르게 돌아가면 방패 없는 곳을 때릴 수 있다
		local facing = data.Facing or direction
		local delta = math.atan2(direction.X, direction.Z) - math.atan2(facing.X, facing.Z)
		delta = (delta + math.pi) % (2 * math.pi) - math.pi
		facing = CFrame.Angles(0, math.clamp(delta, -1.05 * dt, 1.05 * dt), 0):VectorToWorldSpace(facing)
		data.Facing = facing
		lookDirection = facing
	end
	part.CFrame = ((def.Move == "Hover") and CFrame.identity or slopeTilt(ctx, position, stats.Size)) * CFrame.lookAt(position, position + lookDirection) * bodyTilt(data, def, now, dt, moving)

	-- 치유 사제: 일정 간격마다 주변 아군(보스 제외)의 체력을 채운다. 먼저 잡아야 하는 몬스터.
	if def.Attack == "Heal" then
		if now >= (data.NextHeal or 0) and ctx.Monsters then
			data.NextHeal = now + 2.5
			local healed = 0
			for otherPart, otherData in pairs(ctx.Monsters()) do
				if healed >= 5 then break end
				if otherPart ~= part and otherPart.Parent and not otherData.BossLike and not otherData.IsBoss and otherData.Health > 0 and otherData.Health < otherData.MaxHealth
					and (otherPart.Position - part.Position).Magnitude <= 34 then
					local amount = math.max(1, math.floor(otherData.MaxHealth * 0.12))
					otherData.Health = math.min(otherData.MaxHealth, otherData.Health + amount)
					otherData.HealthFill.Size = UDim2.new(math.max(otherData.Health, 0) / otherData.MaxHealth, 0, 1, 0)
					Effects.Burst(otherPart.Position, Color3.fromRGB(120, 255, 170), 8)
					Effects.FloatText(otherPart.Position + Vector3.new(0, otherPart.Size.Y / 2 + 2, 0), "+" .. amount, Color3.fromRGB(120, 255, 170))
					healed += 1
				end
			end
			if healed > 0 then
				part.Color = Color3.fromRGB(255, 255, 255)
				task.delay(0.25, function() if part.Parent then part.Color = data.BaseColor end end)
			end
		end
		return
	end

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
		data.ShotN = (data.ShotN or 0) + 1
		local noFlank = data.ShotN % 2 == 1 -- 옆 탄은 두 번에 한 번만
		telegraph(ctx, part, data, Color3.fromRGB(255, 220, 80), 0.4, function()
			local current = ctx.GetTarget(part.Position)
			if current then
				fireFlanked(ctx, part, current, stats.ShotSpeed, stats.ShotDamage, math.max(1.5, stats.Size / 4), nil, def.Style, noFlank)
			end
		end)

	elseif def.Attack == "Spit" then
		-- 가시 독충: 좌우로 꿈틀대는 뱀 탄 두 줄(반대 위상) / 바늘 두 묶음을 번갈아 쏜다
		data.ShotN = (data.ShotN or 0) + 1
		local snake = data.ShotN % 2 == 1
		telegraph(ctx, part, data, Color3.fromRGB(215, 190, 255), 0.45, function()
			local current = ctx.GetTarget(part.Position)
			if not current then return end
			local aim = (current.Position - part.Position).Unit
			local size = math.max(1.4, stats.Size / 3.6)
			if snake then
				for _, sign in ipairs({ 1, -1 }) do
					ctx.Fire(part.Position, aim, stats.ShotSpeed * 0.8, stats.ShotDamage, size, Color3.fromRGB(165, 205, 90), "Snake", { Kind = "sine", Amp = 7 * sign, Freq = 3.4, Life = 3.5 })
				end
			else
				for _, angle in ipairs({ -9, 9 }) do
					ctx.Fire(part.Position, rotateY(aim, angle), stats.ShotSpeed * 1.1, stats.ShotDamage, size, Color3.fromRGB(205, 150, 235), "Needle")
				end
			end
		end)

	elseif def.Attack == "Crescent" then
		-- 박쥐: 좌우에서 휘어 들어오는 초승달 한 쌍 (집게처럼 모인다). 세 번에 한 번은 빠른 표창 두 발.
		data.ShotN = (data.ShotN or 0) + 1
		local darts = data.ShotN % 3 == 0
		telegraph(ctx, part, data, Color3.fromRGB(255, 220, 80), 0.3, function()
			local current = ctx.GetTarget(part.Position)
			if not current then return end
			local aim = (current.Position - part.Position).Unit
			local size = math.max(1.4, stats.Size / 3)
			if darts then
				for i = 0, 1 do
					task.delay(i * 0.15, function()
						if not ctx.Alive(part, data) then return end
						local now2 = ctx.GetTarget(part.Position)
						if now2 then
							ctx.Fire(part.Position, (now2.Position - part.Position).Unit, stats.ShotSpeed * 1.2, stats.ShotDamage, size * 0.8, Color3.fromRGB(150, 120, 200), "Dart")
						end
					end)
				end
			else
				for _, sign in ipairs({ 1, -1 }) do
					ctx.Fire(part.Position, rotateY(aim, sign * 26), stats.ShotSpeed * 0.85, stats.ShotDamage, size, Color3.fromRGB(175, 145, 225), "Crescent", { Kind = "curve", W = -sign * 1.0, Life = 2.6 })
				end
			end
		end)

	elseif def.Attack == "Seeker" then
		-- 마법사 유령: 느리게 꺾으며 쫓아오는 유도 구슬 한 발. 두 번에 한 번은 운석 두 개도 같이 떨어뜨린다.
		data.ShotN = (data.ShotN or 0) + 1
		local withMeteor = data.ShotN % 2 == 0
		telegraph(ctx, part, data, Color3.fromRGB(255, 140, 90), 0.55, function()
			local current = ctx.GetTarget(part.Position)
			if not current then return end
			local gentle = data.Zone == 1 -- 1구역은 더 느리게 꺾는다
			ctx.Fire(part.Position + Vector3.new(0, 1.5, 0), (current.Position - part.Position).Unit, stats.ShotSpeed * (gentle and 0.75 or 0.9), math.floor(stats.ShotDamage * 1.1), 2.3, Color3.fromRGB(135, 190, 235), "Seeker",
				{ Kind = "homing", Turn = gentle and 0.9 or 1.6, Life = 3.5 })
			if withMeteor then
				for i = 0, 1 do
					task.delay(0.4 + i * 0.4, function()
						if not ctx.Alive(part, data) then return end
						local c2 = ctx.GetTarget(part.Position)
						if not c2 then return end
						meteor(ctx, c2.Position + Vector3.new((math.random() - 0.5) * 16, 0, (math.random() - 0.5) * 16), stats)
					end)
				end
			end
		end)

	elseif def.Attack == "Split" then
		-- 저격 임프: 날다가 목표 앞에서 세 갈래 표창으로 갈라지는 창
		telegraph(ctx, part, data, Color3.fromRGB(255, 120, 150), 0.5, function()
			local current = ctx.GetTarget(part.Position)
			if not current then return end
			local delta = current.Position - part.Position
			local aim = delta.Unit
			local speed = stats.ShotSpeed
			local splitTime = math.clamp(0.55 * delta.Magnitude / speed, 0.4, 0.9)
			ctx.Fire(part.Position, aim, speed, math.floor(stats.ShotDamage * 0.8), math.max(1.6, stats.Size / 3.5), Color3.fromRGB(235, 120, 150), "Spear", {
				Kind = "split", SplitTime = splitTime,
				Child = { Count = 3, Spread = 11, Speed = speed * 0.8, Damage = math.max(1, math.floor(stats.ShotDamage * 0.55)), Size = math.max(1.2, stats.Size / 4.5), Color = Color3.fromRGB(235, 140, 160), Style = "Dart" },
			})
		end)

	elseif def.Attack == "Sword" then
		-- 방패 기사: 창 두 자루 / 커다란 검기(초승달) 한 번을 번갈아
		data.ShotN = (data.ShotN or 0) + 1
		local wave = data.ShotN % 2 == 0
		telegraph(ctx, part, data, Color3.fromRGB(255, 200, 255), 0.5, function()
			local current = ctx.GetTarget(part.Position)
			if not current then return end
			local aim = (current.Position - part.Position).Unit
			if wave then
				ctx.Fire(part.Position, aim, stats.ShotSpeed * 0.75, math.floor(stats.ShotDamage * 1.2), math.max(2.6, stats.Size / 2.4), Color3.fromRGB(190, 205, 235), "Crescent")
			else
				for _, angle in ipairs({ -9, 9 }) do
					ctx.Fire(part.Position, rotateY(aim, angle), stats.ShotSpeed, stats.ShotDamage, math.max(1.3, stats.Size / 4), Color3.fromRGB(190, 205, 235), "Spear")
				end
			end
		end)

	elseif def.Attack == "Halo" then
		-- 도깨비불: 후광 고리 두 개를 연달아 (두 번째는 새로 조준). 세 번에 한 번은 살짝 휘는 세 갈래.
		data.ShotN = (data.ShotN or 0) + 1
		local swirl = data.ShotN % 3 == 0
		telegraph(ctx, part, data, Color3.fromRGB(190, 255, 235), 0.35, function()
			for i = 0, 1 do
				task.delay(i * 0.25, function()
					if not ctx.Alive(part, data) then return end
					local current = ctx.GetTarget(part.Position)
					if not current then return end
					local aim = (current.Position - part.Position).Unit
					local size = math.max(1.6, stats.Size / 2.6)
					if swirl then
						if i == 0 then
							for _, sign in ipairs({ -1, 1 }) do
								ctx.Fire(part.Position, rotateY(aim, sign * 14), stats.ShotSpeed * 0.7, stats.ShotDamage, size, Color3.fromRGB(110, 215, 185), "Halo", { Kind = "curve", W = -sign * 0.5, Life = 3 })
							end
						end
					else
						ctx.Fire(part.Position, aim, stats.ShotSpeed * 0.75, stats.ShotDamage, size, Color3.fromRGB(110, 215, 185), "Halo")
					end
				end)
			end
		end)

	elseif def.Attack == "Fan" then
		telegraph(ctx, part, data, Color3.fromRGB(255, 200, 255), 0.45, function()
			local current = ctx.GetTarget(part.Position)
			if not current then return end
			local aim = (current.Position - part.Position).Unit
			for _, angle in ipairs({ -10, 10 }) do
				ctx.Fire(part.Position, rotateY(aim, angle), stats.ShotSpeed, stats.ShotDamage, math.max(1.3, stats.Size / 4), Color3.fromRGB(210, 120, 255), def.Style)
			end
		end)

	elseif def.Attack == "Ring" then
		-- 저주 토템: 수정 6개의 고리. 매번 바람개비처럼 휘어 돈다 (방향은 번갈아). 8 -> 6발, 더 느리게.
		data.ShotN = (data.ShotN or 0) + 1
		local bend = (data.ShotN % 2 == 0) and 0.35 or -0.35
		telegraph(ctx, part, data, Color3.new(1, 1, 1), 0.6, function()
			local offset = math.random() * math.pi * 2
			for i = 0, 5 do
				local angle = offset + (i / 6) * math.pi * 2
				local ringDirection = Vector3.new(math.cos(angle), 0, math.sin(angle))
				local origin = Vector3.new(part.Position.X, (ctx.GroundY and ctx.GroundY(part.Position.X, part.Position.Z, part.Position.Y) or ctx.FloorY) + 3, part.Position.Z) + ringDirection * (stats.Size / 2 + 1)
				ctx.Fire(origin, ringDirection, 21, math.max(1, math.floor(stats.ShotDamage * 0.8)), 2.3, Color3.fromRGB(135, 215, 235), "Crystal", { Kind = "curve", W = bend, Life = 3.5 })
			end
		end)

	elseif def.Attack == "Heavy" then
		telegraph(ctx, part, data, Color3.fromRGB(255, 150, 60), 0.7, function()
			local current = ctx.GetTarget(part.Position)
			if current then
				fireFlanked(ctx, part, current, stats.ShotSpeed, stats.ShotDamage, math.max(3.5, stats.Size / 2.5), Color3.fromRGB(255, 130, 40))
			end
		end)

	elseif def.Attack == "Burst" then
		telegraph(ctx, part, data, Color3.fromRGB(255, 220, 80), 0.3, function()
			for i = 0, 1 do -- 3연발 -> 2연발
				task.delay(i * 0.16, function()
					if not ctx.Alive(part, data) then return end
					local current = ctx.GetTarget(part.Position)
					if current then
						ctx.Fire(part.Position, rotateY((current.Position - part.Position).Unit, (i - 0.5) * 12), stats.ShotSpeed * 1.1, math.max(1, math.floor(stats.ShotDamage * 0.85)), math.max(1.2, stats.Size / 4), Color3.fromRGB(150, 120, 190), def.Style)
					end
				end)
			end
		end)

	elseif def.Attack == "Mortar" then
		telegraph(ctx, part, data, Color3.fromRGB(255, 120, 80), 0.5, function()
			for i = 0, 2 do
				task.delay(i * 0.35, function()
					if not ctx.Alive(part, data) then return end
					local current = ctx.GetTarget(part.Position)
					if not current then return end
					local base = current.Position
					meteor(ctx, base + Vector3.new((math.random() - 0.5) * 16, 0, (math.random() - 0.5) * 16), stats)
				end)
			end
		end)

	elseif def.Attack == "Slam" then
		if distance > 34 then
			-- 바위 골렘: 멀리서는 포물선으로 던지는 폭탄 두 개 (착지 지점에 경고 표시, 작은 범위 폭발). 직선 대포 3발보다 훨씬 읽기 쉽다.
			telegraph(ctx, part, data, Color3.fromRGB(255, 150, 60), 0.7, function()
				for i = 0, 1 do
					task.delay(i * 0.45, function()
						if not ctx.Alive(part, data) then return end
						local current = ctx.GetTarget(part.Position)
						if not current then return end
						local landing = current.Position + Vector3.new((math.random() - 0.5) * (i == 0 and 4 or 16), -2.8, (math.random() - 0.5) * (i == 0 and 4 or 16))
						local reach = flat(landing - part.Position).Magnitude
						local dur = math.clamp(reach / math.max(stats.ShotSpeed, 12), 1.3, 2.4)
						local aoe = 8
						local color = Color3.fromRGB(235, 140, 70)
						Effects.Warn(landing, aoe, dur, color)
						ctx.Fire(part.Position + Vector3.new(0, stats.Size * 0.4, 0), flat(landing - part.Position), stats.ShotSpeed, stats.ShotDamage, 3.4, color, "Bomb",
							{ Kind = "lob", Target = landing, Dur = dur, Height = 9 + reach * 0.22, AoE = aoe })
					end)
				end
			end)
		else
			telegraph(ctx, part, data, Color3.fromRGB(255, 190, 70), 0.8, function()
				shockwave(ctx, part, stats)
			end)
		end

	elseif def.Attack == "Beam" then
		-- 마법 포탑: 레이저 선과 바늘 연발을 번갈아 쏜다
		data.ShotN = (data.ShotN or 0) + 1
		if data.ShotN % 2 == 0 then
			data.NextAttack = now + stats.ShotInterval * 1.4
			telegraph(ctx, part, data, Color3.fromRGB(190, 170, 255), 0.4, function()
				for i = 0, 2 do
					task.delay(i * 0.2, function()
						if not ctx.Alive(part, data) then return end
						local current = ctx.GetTarget(part.Position)
						if current then
							ctx.Fire(part.Position + Vector3.new(0, stats.Size * 0.2, 0), rotateY((current.Position - part.Position).Unit, (i - 1) * 7), stats.ShotSpeed * 1.5, stats.ShotDamage, 1.8, Color3.fromRGB(190, 170, 240), "Needle")
						end
					end)
				end
			end)
		else
			data.NextAttack = now + stats.ShotInterval * 2
			laser(ctx, part, data, stats, direction, def.Range)
		end

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
