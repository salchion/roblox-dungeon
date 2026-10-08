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

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
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
		Attack = "Fan", Style = "Shard", Move = "Approach", Keep = 20, Range = 85, Spikes = true,
	},
	Bat = {
		Name = "박쥐", Shape = "Ball", Color = Color3.fromRGB(85, 60, 120), Material = Enum.Material.SmoothPlastic,
		SizeMult = 0.6, SpeedMult = 2.2, HealthMult = 0.55, DamageMult = 0.6, IntervalMult = 0.7, ShotSpeedMult = 1.3, GoldMult = 0.9,
		Attack = "Burst", Style = "Dart", Move = "Hover", Keep = 16, Range = 70, Wings = true,
	},
	Mage = {
		Name = "마법사 유령", Shape = "Ball", Color = Color3.fromRGB(130, 225, 255), Material = Enum.Material.Neon, Transparency = 0.25,
		SizeMult = 0.9, SpeedMult = 0.9, HealthMult = 0.8, DamageMult = 0.7, IntervalMult = 2.4, ShotSpeedMult = 0.8, GoldMult = 1.4,
		Attack = "Mortar", Move = "Keep", Keep = 30, Range = 95, Halo = true,
	},
	Golem = {
		Name = "바위 골렘", Shape = "Block", Color = Color3.fromRGB(125, 120, 115), Material = Enum.Material.Slate,
		SizeMult = 1.3, SpeedMult = 0.5, HealthMult = 2.2, DamageMult = 1.8, IntervalMult = 1.8, ShotSpeedMult = 0.55, GoldMult = 1.7,
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
		SizeMult = 0.7, SpeedMult = 0.9, HealthMult = 0.6, DamageMult = 1.3, IntervalMult = 1.6, ShotSpeedMult = 2.6, GoldMult = 1.3,
		Attack = "Single", Style = "Spear", Move = "Keep", Keep = 55, Range = 130, Horns = true,
	},
	Knight = {
		Name = "방패 기사", Shape = "Block", Color = Color3.fromRGB(120, 140, 175), Material = Enum.Material.Metal,
		SizeMult = 1.15, SpeedMult = 0.7, HealthMult = 2.6, DamageMult = 1.1, IntervalMult = 1.4, ShotSpeedMult = 0.9, GoldMult = 1.8,
		Attack = "Fan", Style = "Spear", Move = "Approach", Keep = 8, Range = 60, Shield = true,
	},
	Turret = {
		Name = "마법 포탑", Shape = "Block", Color = Color3.fromRGB(90, 95, 110), Material = Enum.Material.Metal,
		SizeMult = 1.0, SpeedMult = 0, HealthMult = 1.7, DamageMult = 1.0, IntervalMult = 0.8, ShotSpeedMult = 1.2, GoldMult = 1.4,
		Attack = "Beam", Move = "Static", Keep = 0, Range = 110, Barrel = true,
	},
	Spider = {
		Name = "독거미", Shape = "Ball", Color = Color3.fromRGB(60, 50, 60), Material = Enum.Material.SmoothPlastic,
		SizeMult = 0.75, SpeedMult = 1.9, HealthMult = 0.8, DamageMult = 0.8, IntervalMult = 0.6, ShotSpeedMult = 1.2, GoldMult = 1.0,
		Attack = "Burst", Style = "Dart", Move = "Rush", Keep = 0, Range = 45, Legs = true,
	},
	Wisp = {
		Name = "도깨비불", Shape = "Ball", Color = Color3.fromRGB(120, 255, 200), Material = Enum.Material.Neon, Transparency = 0.3,
		SizeMult = 0.55, SpeedMult = 2.4, HealthMult = 0.45, DamageMult = 0.7, IntervalMult = 0.9, ShotSpeedMult = 1.4, GoldMult = 1.1,
		Attack = "Burst", Style = "Orb", Move = "Hover", Keep = 22, Range = 80, Flame = true,
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
-- 몸체(body)는 총알이 맞는 "당탁 판정 상자"로만 쓰고 투명하게 둔다. 눈에 보이는 생김새는 여러 부품(머리 / 팔다리 / 날개 ...)을 용접해서 만든다.
-- 몬스터 색이 바뀌는 연출(피격 번쩍임, 돌진 예고)은 body.Color 가 바뀌면 "Tint" 부품들에 전달된다.
local Glass, Neon, Plastic, Metal, Wood, Slate = Enum.Material.Glass, Enum.Material.Neon, Enum.Material.SmoothPlastic, Enum.Material.Metal, Enum.Material.Wood, Enum.Material.Slate
local BALL, BLOCK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local BLACK, WHITE = Color3.new(0, 0, 0), Color3.new(1, 1, 1)

-- 종류별 생김새. S = 몬스터 크기, c = 몸 색. 앞쪽 = -Z, 바닥 = -S/2.
-- d(모양, 가로, 높이, 길이, x, y, z, 색, 재질, { Tint=몸 색 연출 대상, T=투명도, Rx/Ry/Rz=회전(도) })
local Looks = {}

local function eyes(d, S, y, z, spread, color, size)
	for _, side in ipairs({ -1, 1 }) do
		d(BALL, S * size, S * size, S * size * 0.6, side * S * spread, y, z, color or WHITE, Plastic)
		d(BALL, S * size * 0.5, S * size * 0.5, S * size * 0.4, side * S * spread, y, z - S * size * 0.2, BLACK, Plastic)
	end
end

Looks.Slime = function(S, c, d)
	local dark, light = c:Lerp(BLACK, 0.35), c:Lerp(WHITE, 0.55)
	d(BALL, S * 1.0, S * 0.7, S * 1.0, 0, -S * 0.15, 0, c, Glass, { Tint = true, T = 0.12 })           -- 젤리 몸
	d(BALL, S * 0.55, S * 0.4, S * 0.55, S * 0.1, S * 0.2, S * 0.05, c, Glass, { Tint = true, T = 0.12 }) -- 머리 위 말랑한 혹
	d(BALL, S * 0.4, S * 0.3, S * 0.4, 0, -S * 0.12, S * 0.05, dark, Plastic, { T = 0.2 })              -- 몸 속 핵
	d(BALL, S * 0.16, S * 0.1, S * 0.16, -S * 0.2, S * 0.28, -S * 0.2, light, Neon, { T = 0.25 })       -- 윤기 하이라이트
	eyes(d, S, -S * 0.02, -S * 0.43, 0.2, WHITE, 0.2)
	d(BLOCK, S * 0.2, S * 0.05, S * 0.05, 0, -S * 0.2, -S * 0.47, dark, Plastic)                       -- 입
	for i = -1, 1 do -- 바닥에 퍼진 물방울
		d(BALL, S * 0.22, S * 0.1, S * 0.22, i * S * 0.4, -S * 0.46, -S * 0.2 + math.abs(i) * S * 0.1, c, Glass, { Tint = true, T = 0.15 })
	end
end

Looks.Spitter = function(S, c, d) -- 가시 독충: 꿈틀대는 마디 몸 + 등 가시 + 집게턱
	local dark = c:Lerp(BLACK, 0.4)
	d(BALL, S * 0.8, S * 0.7, S * 0.8, 0, -S * 0.12, 0, c, Plastic, { Tint = true })
	d(BALL, S * 0.65, S * 0.58, S * 0.65, 0, -S * 0.18, S * 0.55, c, Plastic, { Tint = true })
	d(BALL, S * 0.5, S * 0.45, S * 0.5, 0, -S * 0.24, S * 1.0, c, Plastic, { Tint = true })
	d(BALL, S * 0.6, S * 0.55, S * 0.6, 0, -S * 0.02, -S * 0.5, dark, Plastic, { Tint = true }) -- 머리
	eyes(d, S, S * 0.05, -S * 0.78, 0.17, Color3.fromRGB(255, 230, 80), 0.16)
	for _, side in ipairs({ -1, 1 }) do -- 집게턱
		d(BLOCK, S * 0.07, S * 0.07, S * 0.34, side * S * 0.14, -S * 0.12, -S * 0.82, Color3.fromRGB(235, 230, 210), Plastic, { Ry = side * 20 })
	end
	for i = 0, 3 do -- 등 가시
		d(BLOCK, S * 0.09, S * 0.4 - i * 0.04 * S, S * 0.09, 0, S * 0.3, -S * 0.35 + i * S * 0.4, Color3.fromRGB(235, 220, 255), Neon, { Rx = -15 })
	end
	for i = 0, 2 do for _, side in ipairs({ -1, 1 }) do -- 짧은 다리
		d(BLOCK, S * 0.3, S * 0.06, S * 0.06, side * S * 0.42, -S * 0.42, -S * 0.1 + i * S * 0.45, dark, Plastic, { Rz = side * -35 })
	end end
end

Looks.Bat = function(S, c, d)
	local dark = c:Lerp(BLACK, 0.4)
	d(BALL, S * 0.55, S * 0.65, S * 0.6, 0, 0, S * 0.05, c, Plastic, { Tint = true })
	d(BALL, S * 0.45, S * 0.42, S * 0.45, 0, S * 0.18, -S * 0.3, c, Plastic, { Tint = true }) -- 머리
	for _, side in ipairs({ -1, 1 }) do
		d(BLOCK, S * 0.1, S * 0.35, S * 0.08, side * S * 0.16, S * 0.46, -S * 0.3, dark, Plastic, { Rz = side * -12 }) -- 큰 귀
		d(BLOCK, S * 0.04, S * 0.05, S * 0.12, side * S * 0.08, -S * 0.0, -S * 0.5, WHITE, Plastic) -- 송곳니
		-- 날개: 팔뼈 + 손가락 뼈 3개 + 막
		d(BLOCK, S * 0.6, S * 0.07, S * 0.07, side * S * 0.5, S * 0.12, S * 0.05, dark, Plastic, { Rz = side * 14 })
		for k = 1, 3 do
			d(BLOCK, S * 0.75, S * 0.04, S * 0.04, side * S * 0.85, S * 0.3 - k * S * 0.17, S * 0.05 + k * S * 0.12, dark, Plastic, { Rz = side * (16 - k * 14), Ry = side * -(k * 9) })
		end
		d(BLOCK, S * 0.8, S * 0.02, S * 0.55, side * S * 0.82, S * 0.06, S * 0.2, c, Plastic, { Tint = true, T = 0.1, Rz = side * -8 })
	end
	eyes(d, S, S * 0.22, -S * 0.5, 0.1, Color3.fromRGB(255, 80, 80), 0.1)
end

Looks.Mage = function(S, c, d) -- 마법사 유령: 꼬리 달린 유령 + 뾰족 모자 + 지팡이
	local robe = c:Lerp(Color3.fromRGB(40, 60, 140), 0.5)
	d(BALL, S * 0.8, S * 0.9, S * 0.8, 0, S * 0.0, 0, c, Neon, { Tint = true, T = 0.3 })
	for i = 1, 3 do -- 아래로 흩날리는 꼬리
		d(BALL, S * (0.62 - i * 0.14), S * (0.5 - i * 0.1), S * (0.62 - i * 0.14), S * 0.05 * i, -S * (0.28 + i * 0.2), S * 0.08 * i, c, Neon, { Tint = true, T = 0.3 + i * 0.12 })
	end
	d(CYL, S * 0.08, S * 0.9, S * 0.9, 0, S * 0.38, 0, robe, Plastic, { Rz = 90 })                  -- 모자 챙
	d(CYL, S * 0.4, S * 0.58, S * 0.58, 0, S * 0.58, 0, robe, Plastic, { Rz = 90 })
	d(CYL, S * 0.3, S * 0.34, S * 0.34, S * 0.04, S * 0.86, 0, robe, Plastic, { Rz = 90 })
	d(BALL, S * 0.12, S * 0.12, S * 0.12, S * 0.07, S * 1.05, 0, Color3.fromRGB(255, 230, 120), Neon)
	eyes(d, S, S * 0.12, -S * 0.36, 0.17, Color3.fromRGB(255, 255, 255), 0.14)
	d(BLOCK, S * 0.06, S * 1.3, S * 0.06, S * 0.52, S * 0.05, -S * 0.2, Color3.fromRGB(110, 75, 50), Wood)       -- 지팡이
	d(BALL, S * 0.22, S * 0.22, S * 0.22, S * 0.52, S * 0.72, -S * 0.2, Color3.fromRGB(150, 230, 255), Neon)
	d(BALL, S * 0.16, S * 0.16, S * 0.16, S * 0.4, -S * 0.08, -S * 0.3, c, Neon, { Tint = true, T = 0.25 })     -- 손
end

Looks.Golem = function(S, c, d)
	local dark, moss = c:Lerp(BLACK, 0.3), Color3.fromRGB(80, 130, 70)
	d(BLOCK, S * 0.85, S * 0.7, S * 0.6, 0, S * 0.05, 0, c, Slate, { Tint = true })                -- 몸통
	d(BLOCK, S * 0.5, S * 0.4, S * 0.45, 0, S * 0.5, -S * 0.02, c, Slate, { Tint = true, Rz = 4 }) -- 머리
	d(BLOCK, S * 0.62, S * 0.12, S * 0.5, 0, S * 0.7, 0, dark, Slate)                                -- 이마 바위
	eyes(d, S, S * 0.52, -S * 0.25, 0.14, Color3.fromRGB(255, 150, 50), 0.1)
	d(BLOCK, S * 0.22, S * 0.28, S * 0.04, 0, S * 0.12, -S * 0.31, Color3.fromRGB(255, 140, 50), Neon, { Rz = 12 }) -- 가슴 균열의 불빛
	for _, side in ipairs({ -1, 1 }) do
		d(BLOCK, S * 0.3, S * 0.6, S * 0.3, side * S * 0.62, -S * 0.02, 0, c, Slate, { Tint = true, Rz = side * 6 }) -- 팔
		d(BLOCK, S * 0.4, S * 0.36, S * 0.4, side * S * 0.68, -S * 0.42, 0, dark, Slate, { Tint = true })            -- 주먹
		d(BLOCK, S * 0.32, S * 0.32, S * 0.32, side * S * 0.5, S * 0.4, 0, dark, Slate, { Rx = 20, Rz = 25 })         -- 어깨 바위
		d(BLOCK, S * 0.34, S * 0.4, S * 0.34, side * S * 0.2, -S * 0.4, 0, c, Slate, { Tint = true })                 -- 다리
		d(BLOCK, S * 0.14, S * 0.04, S * 0.2, side * S * 0.3, S * 0.36, -S * 0.1, moss, Plastic)                      -- 이끼
	end
end

Looks.Charger = function(S, c, d) -- 돌진 멧돼지
	local dark, tusk = c:Lerp(BLACK, 0.45), Color3.fromRGB(245, 240, 225)
	d(BLOCK, S * 0.8, S * 0.62, S * 1.3, 0, S * 0.02, S * 0.12, c, Plastic, { Tint = true })        -- 몸
	d(BLOCK, S * 0.62, S * 0.55, S * 0.5, 0, -S * 0.02, -S * 0.55, c, Plastic, { Tint = true })      -- 머리
	d(CYL, S * 0.28, S * 0.34, S * 0.34, 0, -S * 0.1, -S * 0.88, c:Lerp(WHITE, 0.15), Plastic, { Ry = 90 }) -- 주둥이
	for _, side in ipairs({ -1, 1 }) do
		d(BLOCK, S * 0.08, S * 0.1, S * 0.5, side * S * 0.2, -S * 0.2, -S * 0.95, tusk, Plastic, { Rx = -15, Ry = side * -8 }) -- 엄니
		d(BLOCK, S * 0.2, S * 0.26, S * 0.06, side * S * 0.28, S * 0.3, -S * 0.5, dark, Plastic, { Rz = side * -25 })          -- 귀
		d(BALL, S * 0.13, S * 0.13, S * 0.08, side * S * 0.22, S * 0.08, -S * 0.78, Color3.fromRGB(255, 90, 60), Neon)         -- 붉은 눈
		for _, z in ipairs({ -0.35, 0.55 }) do
			d(BLOCK, S * 0.2, S * 0.35, S * 0.2, side * S * 0.28, -S * 0.38, S * z, dark, Plastic)                                -- 다리
		end
	end
	for i = 0, 3 do -- 등 갈기
		d(BLOCK, S * 0.1, S * 0.22, S * 0.1, 0, S * 0.42, -S * 0.3 + i * S * 0.28, dark, Plastic, { Rx = -12 })
	end
	d(BLOCK, S * 0.06, S * 0.06, S * 0.3, 0, S * 0.12, S * 0.85, dark, Plastic, { Rx = 40 })                                    -- 꼬리
end

Looks.Bomber = function(S, c, d)
	local dark = c:Lerp(BLACK, 0.3)
	d(BALL, S * 0.95, S * 0.95, S * 0.95, 0, -S * 0.02, 0, c, Metal, { Tint = true })               -- 폭탄 몸통
	d(CYL, S * 0.14, S * 0.34, S * 0.34, 0, S * 0.5, 0, dark, Metal, { Rz = 90 })                   -- 꼭지
	d(BLOCK, S * 0.04, S * 0.3, S * 0.04, S * 0.05, S * 0.7, 0, Color3.fromRGB(150, 120, 80), Plastic, { Rz = -20 }) -- 심지
	local fuse = d(BALL, S * 0.2, S * 0.2, S * 0.2, S * 0.12, S * 0.87, 0, Color3.fromRGB(255, 160, 40), Neon)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Rate = 30
	sparks.Lifetime = NumberRange.new(0.3, 0.6)
	sparks.Speed = NumberRange.new(3, 7)
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.LightEmission = 1
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80))
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparks.Parent = fuse
	for _, side in ipairs({ -1, 1 }) do
		d(BALL, S * 0.2, S * 0.14, S * 0.3, side * S * 0.2, -S * 0.48, -S * 0.08, dark, Plastic)           -- 발
		d(BLOCK, S * 0.22, S * 0.06, S * 0.05, side * S * 0.2, S * 0.14, -S * 0.46, Color3.fromRGB(255, 70, 50), Neon, { Rz = side * 22 }) -- 화난 눈
	end
	d(BALL, S * 0.3, S * 0.3, S * 0.05, 0, -S * 0.12, -S * 0.46, Color3.fromRGB(235, 230, 215), Plastic, { T = 0.1 }) -- 해골 표시
end

Looks.Imp = function(S, c, d)
	local dark, horn = c:Lerp(BLACK, 0.45), Color3.fromRGB(40, 20, 30)
	d(BALL, S * 0.55, S * 0.7, S * 0.5, 0, -S * 0.15, 0, c, Plastic, { Tint = true })               -- 몸
	d(BALL, S * 0.5, S * 0.46, S * 0.48, 0, S * 0.28, -S * 0.04, c, Plastic, { Tint = true })        -- 머리
	for _, side in ipairs({ -1, 1 }) do
		d(BLOCK, S * 0.08, S * 0.4, S * 0.08, side * S * 0.18, S * 0.62, 0, horn, Plastic, { Rz = side * -22 })       -- 뿔
		d(BLOCK, S * 0.5, S * 0.03, S * 0.4, side * S * 0.55, S * 0.1, S * 0.2, dark, Plastic, { Rz = side * 25 })    -- 날개
		d(BLOCK, S * 0.5, S * 0.05, S * 0.05, side * S * 0.55, S * 0.2, S * 0.2, horn, Plastic, { Rz = side * 25 })
		d(BLOCK, S * 0.1, S * 0.1, S * 0.3, side * S * 0.35, -S * 0.2, -S * 0.1, c, Plastic, { Tint = true, Rx = -25 }) -- 팔
		d(BLOCK, S * 0.14, S * 0.3, S * 0.14, side * S * 0.14, -S * 0.52, 0, c, Plastic, { Tint = true })             -- 다리
	end
	eyes(d, S, S * 0.3, -S * 0.26, 0.14, Color3.fromRGB(255, 240, 90), 0.13)
	d(BLOCK, S * 0.22, S * 0.05, S * 0.04, 0, S * 0.14, -S * 0.27, WHITE, Plastic)                    -- 이빨 웃음
	d(BLOCK, S * 0.05, S * 0.05, S * 0.6, 0, -S * 0.3, S * 0.45, dark, Plastic, { Rx = 25 })        -- 꼬리
	d(BLOCK, S * 0.2, S * 0.2, S * 0.05, 0, -S * 0.1, S * 0.78, horn, Plastic, { Rz = 45 })          -- 꼬리 끝 화살촉
	d(BLOCK, S * 0.04, S * 0.9, S * 0.04, S * 0.4, -S * 0.1, -S * 0.3, Color3.fromRGB(120, 90, 60), Wood) -- 삼지창
	d(BLOCK, S * 0.22, S * 0.04, S * 0.04, S * 0.4, S * 0.36, -S * 0.3, horn, Metal)
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
	d(BLOCK, S * 0.55, S * 0.75, S * 0.08, -S * 0.2, S * 0.02, -S * 0.36, Color3.fromRGB(190, 200, 225), Metal) -- 방패
	d(BALL, S * 0.2, S * 0.2, S * 0.06, -S * 0.2, S * 0.1, -S * 0.42, gold, Neon)
	d(BLOCK, S * 0.06, S * 0.8, S * 0.04, S * 0.52, S * 0.1, -S * 0.2, Color3.fromRGB(215, 220, 230), Metal, { Rx = -20 }) -- 검
	d(BLOCK, S * 0.2, S * 0.05, S * 0.05, S * 0.52, -S * 0.2, -S * 0.12, gold, Metal)
end

Looks.Turret = function(S, c, d)
	local dark = c:Lerp(BLACK, 0.4)
	d(CYL, S * 0.5, S * 0.9, S * 0.9, 0, -S * 0.3, 0, dark, Metal, { Rz = 90 })                      -- 원통 받침
	for i = 0, 2 do -- 삼각대 다리
		local a = i / 3 * math.pi * 2
		d(BLOCK, S * 0.1, S * 0.5, S * 0.1, math.cos(a) * S * 0.42, -S * 0.3, math.sin(a) * S * 0.42, dark, Metal, { Rz = math.cos(a) * 20, Rx = -math.sin(a) * 20 })
	end
	d(BALL, S * 0.7, S * 0.6, S * 0.7, 0, S * 0.15, 0, c, Metal, { Tint = true })                    -- 포신 머리
	d(BLOCK, S * 0.22, S * 0.22, S * 0.8, 0, S * 0.18, -S * 0.65, Color3.fromRGB(50, 52, 64), Metal)   -- 포신
	d(CYL, S * 0.1, S * 0.3, S * 0.3, 0, S * 0.18, -S * 1.04, dark, Metal, { Ry = 90 })              -- 포구 링
	d(BALL, S * 0.2, S * 0.2, S * 0.2, 0, S * 0.18, -S * 1.06, Color3.fromRGB(150, 110, 255), Neon)
	d(BALL, S * 0.14, S * 0.14, S * 0.1, 0, S * 0.32, -S * 0.3, Color3.fromRGB(255, 80, 80), Neon)   -- 센서 눈
	for _, side in ipairs({ -1, 1 }) do
		d(BLOCK, S * 0.08, S * 0.5, S * 0.08, side * S * 0.4, S * 0.5, S * 0.1, dark, Metal, { Rz = side * -10 }) -- 안테나
	end
end

Looks.Spider = function(S, c, d)
	local dark, fang = c:Lerp(BLACK, 0.3), Color3.fromRGB(235, 230, 215)
	d(BALL, S * 0.7, S * 0.6, S * 0.8, 0, S * 0.0, S * 0.35, c, Plastic, { Tint = true })            -- 배
	d(BALL, S * 0.5, S * 0.42, S * 0.5, 0, -S * 0.02, -S * 0.18, dark, Plastic, { Tint = true })      -- 머리가슴
	d(BLOCK, S * 0.2, S * 0.04, S * 0.2, 0, S * 0.3, S * 0.42, Color3.fromRGB(255, 70, 70), Neon, { T = 0.2 }) -- 등의 표식
	for i = 0, 3 do -- 눈 여러 개
		d(BALL, S * 0.07, S * 0.07, S * 0.06, (i % 2 == 0 and -1 or 1) * S * (0.07 + (i // 2) * 0.08), S * 0.08 + (i // 2) * S * 0.06, -S * 0.4, Color3.fromRGB(255, 60, 60), Neon)
	end
	for _, side in ipairs({ -1, 1 }) do
		d(BLOCK, S * 0.05, S * 0.18, S * 0.05, side * S * 0.08, -S * 0.2, -S * 0.46, fang, Plastic)  -- 송곳니
		for i = 0, 3 do -- 다리 4쌍: 허벅지는 위로, 정강이는 아래로 꺾인다
			local z = -S * 0.25 + i * S * 0.2
			local lean = (i - 1.5) * 12
			d(BLOCK, S * 0.5, S * 0.06, S * 0.06, side * S * 0.5, S * 0.12, z, dark, Plastic, { Rz = side * 35, Ry = side * lean })
			d(BLOCK, S * 0.06, S * 0.55, S * 0.06, side * S * 0.82, -S * 0.2, z + lean * 0.004 * S, dark, Plastic, { Rz = side * -12 })
		end
	end
end

Looks.Wisp = function(S, c, d) -- 도깨비불: 불꽃 핵 + 꼬리불 + 도는 작은 불꽃
	d(BALL, S * 0.7, S * 0.8, S * 0.7, 0, S * 0.05, 0, c, Neon, { Tint = true, T = 0.2 })
	d(BALL, S * 0.4, S * 0.5, S * 0.4, 0, S * 0.1, 0, WHITE, Neon, { T = 0.3 })
	for i = 1, 4 do
		d(BALL, S * (0.5 - i * 0.09), S * (0.5 - i * 0.09), S * (0.5 - i * 0.09), math.sin(i) * S * 0.08, -S * (0.2 + i * 0.16), S * (0.1 * i), c, Neon, { Tint = true, T = 0.25 + i * 0.1 })
	end
	d(BLOCK, S * 0.12, S * 0.3, S * 0.12, 0, S * 0.5, 0, c, Neon, { Tint = true, T = 0.3, Rz = 12 })    -- 위로 솟는 불꽃 끝
	for _, side in ipairs({ -1, 1 }) do
		d(BALL, S * 0.14, S * 0.2, S * 0.06, side * S * 0.16, S * 0.12, -S * 0.34, Color3.fromRGB(20, 60, 50), Plastic) -- 눈
		d(BALL, S * 0.14, S * 0.14, S * 0.14, side * S * 0.55, S * 0.1, S * 0.1, c, Neon, { T = 0.3 })    -- 곁불
	end
	local glow = Instance.new("ParticleEmitter")
	glow.Rate = 45
	glow.Lifetime = NumberRange.new(0.4, 0.8)
	glow.Speed = NumberRange.new(1, 3)
	glow.SpreadAngle = Vector2.new(180, 180)
	glow.LightEmission = 1
	glow.Color = ColorSequence.new(Color3.fromRGB(120, 255, 200))
	glow.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, S * 0.5), NumberSequenceKeypoint.new(1, 0) })
	glow.Parent = d.Body
end

Looks.Totem = function(S, c, d)
	local dark, red = c:Lerp(BLACK, 0.35), Color3.fromRGB(190, 60, 60)
	d(BLOCK, S * 0.75, S * 0.5, S * 0.75, 0, -S * 0.3, 0, c, Wood, { Tint = true })                  -- 아래 토막
	d(BLOCK, S * 0.65, S * 0.5, S * 0.65, 0, S * 0.15, 0, dark, Wood)                                -- 가운데 토막
	d(BLOCK, S * 0.8, S * 0.5, S * 0.8, 0, S * 0.6, 0, red, Wood, { Tint = true })                   -- 얼굴 토막
	eyes(d, S, S * 0.66, -S * 0.4, 0.2, Color3.fromRGB(255, 220, 80), 0.18)
	d(BLOCK, S * 0.4, S * 0.1, S * 0.05, 0, S * 0.5, -S * 0.41, Color3.new(0.1, 0.05, 0.05), Plastic)  -- 입
	for _, side in ipairs({ -1, 1 }) do
		d(BLOCK, S * 0.5, S * 0.12, S * 0.12, side * S * 0.55, S * 0.1, 0, dark, Wood, { Rz = side * 15 })  -- 양 날개 막대
		for k = 0, 2 do
			d(BLOCK, S * 0.08, S * 0.35, S * 0.04, side * (S * 0.5 + k * S * 0.12), -S * 0.1, 0, k % 2 == 0 and red or Color3.fromRGB(80, 160, 200), Plastic) -- 깃털
		end
		d(BLOCK, S * 0.1, S * 0.4, S * 0.1, side * S * 0.3, S * 1.0, 0, dark, Wood, { Rz = side * -20 })    -- 뿔
	end
	d(BALL, S * 0.3, S * 0.3, S * 0.3, 0, S * 1.05, 0, Color3.fromRGB(255, 80, 80), Neon)           -- 꼭대기 저주 구슬
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
				ctx.Fire(part.Position, current.Position - part.Position, stats.ShotSpeed, stats.ShotDamage, math.max(1.5, stats.Size / 4), nil, def.Style)
			end
		end)

	elseif def.Attack == "Fan" then
		telegraph(ctx, part, data, Color3.fromRGB(255, 200, 255), 0.45, function()
			local current = ctx.GetTarget(part.Position)
			if not current then return end
			local aim = (current.Position - part.Position).Unit
			for _, angle in ipairs({ -15, 0, 15 }) do
				ctx.Fire(part.Position, rotateY(aim, angle), stats.ShotSpeed, stats.ShotDamage, math.max(1.3, stats.Size / 4), Color3.fromRGB(210, 120, 255), def.Style)
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

	elseif def.Attack == "Burst" then
		telegraph(ctx, part, data, Color3.fromRGB(255, 220, 80), 0.3, function()
			for i = 0, 2 do
				task.delay(i * 0.13, function()
					if not ctx.Alive(part, data) then return end
					local current = ctx.GetTarget(part.Position)
					if current then
						ctx.Fire(part.Position, current.Position - part.Position, stats.ShotSpeed * 1.25, math.max(1, math.floor(stats.ShotDamage * 0.7)), math.max(1.2, stats.Size / 4), nil, def.Style)
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
			telegraph(ctx, part, data, Color3.fromRGB(255, 150, 60), 0.7, function()
				local current = ctx.GetTarget(part.Position)
				if current then
					ctx.Fire(part.Position, current.Position - part.Position, stats.ShotSpeed, stats.ShotDamage, math.max(3.5, stats.Size / 2.5), Color3.fromRGB(255, 130, 40))
				end
			end)
		else
			telegraph(ctx, part, data, Color3.fromRGB(255, 190, 70), 0.8, function()
				shockwave(ctx, part, stats)
			end)
		end

	elseif def.Attack == "Beam" then
		data.NextAttack = now + stats.ShotInterval * 2
		laser(ctx, part, data, stats, direction, def.Range)

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
