-- WeaponService (ServerScriptService > Modules 안의 ModuleScript, 이름: WeaponService)
-- 무기(총) 종류(권총 / 샷건 / 저격총) + 강화 + 무기 외형 생성.
-- 무기는 서버에서 만들어 캐릭터에 장착하기 때문에 로비의 모든 플레이어에게 그대로 보인다.
-- 강화 레벨(WeaponLevel)이 오를수록 색상 / 크기 / 재질 / 파티클 / 궤적 / 빛이 달라진다.

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))
local SoundBank = require(game:GetService("ReplicatedStorage"):WaitForChild("SoundBank"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Quest = require(script.Parent:WaitForChild("QuestService"))
local Event = require(script.Parent:WaitForChild("EventService"))

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Weapon = {}

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 220, 60)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(80, 255, 100)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(60, 220, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(90, 90, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 255)),
})

local function weld(part0, part1)
	local w = Instance.new("WeldConstraint")
	w.Part0 = part0
	w.Part1 = part1
	w.Parent = part0
end

local function newPart(name, size, color, material, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- 레벨에 맞는 무기(Tool)를 만든다. 총구 방향은 손잡이의 -Z (팔을 뻗은 방향).
-- 무기 50종 = 종류 5 x 시대 10. 구조:
--   1) 종류별 몸체(Bodies)가 실루엣을 만들고 "기준점(앵커)"을 돌려준다: 윗면 선(top) / 총구(muzzle) / 옆 폭(side) / 몸통 높이(mid) / 총열(barrel)
--   2) 시대 장식(EraKit)은 앵커에 붙는다 -> 어떤 무기든 장식이 몸체 안에 묻히거나 허공에 뜨지 않는다 (예전: 고정 좌표라 로켓 / 책에서 묻혔다)
--   3) 시대마다 몸체 색 / 재질 자체가 바뀐다 (예전: 작은 장식만 바뀌어서 시대가 올라도 거의 같아 보였다)
--   4) 빛나는(Neon) 부품은 작은 줄 / 보석 / 구슬만. 넓은 면은 빛나지 않게 (눈부심 방지)
local V = Vector3.new
local STEEL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic
local rgb = Color3.fromRGB
local rad = math.rad

-- 시대별 색 구성: body(몸체) / dark(어두운 부품) / stock(개머리판 / 손잡이) / acc(강조색: 작은 줄 / 보석)
local ERA_PALETTE = {
	{ body = rgb(128, 100, 84), bodyMat = Enum.Material.CorrodedMetal, dark = rgb(58, 48, 42), stock = rgb(116, 76, 46), stockMat = Enum.Material.Wood, acc = rgb(214, 160, 96), accMat = SMOOTH }, -- 녹슨
	{ body = rgb(178, 188, 204), bodyMat = STEEL, dark = rgb(46, 52, 68), stock = rgb(84, 66, 52), stockMat = Enum.Material.Wood, acc = rgb(90, 160, 255), accMat = NEON }, -- 강철
	{ body = rgb(104, 66, 160), bodyMat = SMOOTH, dark = rgb(42, 26, 70), stock = rgb(70, 46, 112), stockMat = SMOOTH, acc = rgb(196, 130, 255), accMat = NEON }, -- 마력
	{ body = rgb(242, 192, 72), bodyMat = STEEL, dark = rgb(84, 58, 28), stock = rgb(150, 34, 46), stockMat = Enum.Material.Fabric, acc = rgb(255, 236, 150), accMat = NEON }, -- 황금
	{ body = rgb(62, 38, 34), bodyMat = STEEL, dark = rgb(30, 18, 16), stock = rgb(96, 42, 30), stockMat = STEEL, acc = rgb(255, 112, 44), accMat = NEON }, -- 불꽃
	{ body = rgb(206, 232, 250), bodyMat = SMOOTH, dark = rgb(54, 86, 126), stock = rgb(150, 204, 238), stockMat = Enum.Material.Ice, acc = rgb(150, 232, 255), accMat = NEON }, -- 빙결
	{ body = rgb(58, 62, 84), bodyMat = STEEL, dark = rgb(24, 24, 34), stock = rgb(40, 42, 60), stockMat = STEEL, acc = rgb(255, 236, 90), accMat = NEON }, -- 번개
	{ body = rgb(48, 26, 70), bodyMat = SMOOTH, dark = rgb(16, 8, 26), stock = rgb(32, 16, 48), stockMat = SMOOTH, acc = rgb(176, 92, 255), accMat = NEON }, -- 암흑
	{ body = rgb(158, 42, 34), bodyMat = STEEL, dark = rgb(46, 16, 12), stock = rgb(236, 216, 186), stockMat = SMOOTH, acc = rgb(255, 172, 60), accMat = NEON }, -- 용
	{ body = rgb(246, 242, 255), bodyMat = STEEL, dark = rgb(92, 82, 142), stock = rgb(255, 214, 120), stockMat = STEEL, acc = rgb(255, 170, 240), accMat = NEON, rainbow = true }, -- 신화
}
local RAINBOW_ACC = { rgb(255, 90, 90), rgb(255, 210, 80), rgb(110, 255, 140), rgb(90, 210, 255), rgb(160, 120, 255), rgb(255, 120, 230) }
local PAGE = rgb(238, 230, 206)
local PART_BUDGET = 40 -- 손잡이 / 총열 표시 외에 붙이는 부품 수의 상한 (가벼운 무기 모델 유지)

local Bodies = {} -- 종류별 몸체: Bodies[종류](c, k, bl) -> 앵커 표

Bodies.Pistol = function(c, k, bl) -- 저격총: 길쭉한 몸통 + 긴 총열 + 총구 제동기 + 큰 조준경 + 각진 개머리판
	local p = c.pal
	c.add("Grip", V(0.34, 0.9, 0.42), CFrame.new(0, -0.62, 0.45) * CFrame.Angles(rad(-14), 0, 0), p.stock, p.stockMat)
	c.add("Receiver", V(0.56 * k, 0.6 * k, 2.0), CFrame.new(0, 0.18, 0.15), p.body, p.bodyMat)
	c.add("Mag", V(0.32 * k, 0.6, 0.5), CFrame.new(0, -0.4, -0.45) * CFrame.Angles(rad(10), 0, 0), p.dark, STEEL)
	local mz = -(0.85 + bl)
	c.cyl("BarrelBody", bl, 0.3 * k, CFrame.new(0, 0.2, -(0.85 + bl / 2)), p.dark, STEEL)
	c.cyl("Shroud", bl * 0.5, 0.46 * k, CFrame.new(0, 0.2, -(0.85 + bl * 0.22)), p.body, p.bodyMat)
	c.add("Brake", V(0.38 * k, 0.3 * k, 0.55), CFrame.new(0, 0.2, mz + 0.1), p.dark, STEEL)
	c.add("BrakeLine", V(0.4 * k, 0.07, 0.36), CFrame.new(0, 0.2 + 0.16 * k, mz + 0.1), c.acc(), p.accMat)
	c.cyl("Scope", 1.7, 0.4 * k, CFrame.new(0, 0.2 + 0.62 * k, -0.1), p.dark, STEEL)
	c.cyl("ScopeFront", 0.36, 0.54 * k, CFrame.new(0, 0.2 + 0.62 * k, -0.95), p.dark, STEEL)
	c.cyl("Lens", 0.05, 0.42 * k, CFrame.new(0, 0.2 + 0.62 * k, -1.14), c.acc(), p.accMat)
	c.add("Mount", V(0.18, 0.3 * k, 0.9), CFrame.new(0, 0.2 + 0.36 * k, -0.1), p.dark, STEEL)
	c.add("Stock", V(0.42 * k, 0.42 * k, 1.4), CFrame.new(0, 0.1, 1.75), p.stock, p.stockMat)
	c.add("StockLow", V(0.42 * k, 0.36 * k, 0.9), CFrame.new(0, -0.3 * k, 2.05) * CFrame.Angles(rad(-18), 0, 0), p.stock, p.stockMat)
	c.add("ButtPad", V(0.46 * k, 0.8 * k, 0.16), CFrame.new(0, -0.05, 2.5), p.dark, STEEL)
	return { top = { y = 0.2 + 0.28 * k, z0 = 1.9, z1 = -0.9 }, muzzle = { z = mz, y = 0.2, r = 0.2 * k }, side = 0.25 * k, mid = { y = 0.18 }, barrel = { y = 0.2, z0 = -0.85, z1 = mz, r = 0.18 * k } }
end

Bodies.Shotgun = function(c, k, bl) -- 샷건: 굵은 상하 총열 + 나팔 총구 + 펌프 + 옆구리 탄 4발
	local p = c.pal
	c.add("Grip", V(0.36, 0.9, 0.44), CFrame.new(0, -0.62, 0.5) * CFrame.Angles(rad(-14), 0, 0), p.stock, p.stockMat)
	c.add("Receiver", V(0.62 * k, 0.7 * k, 1.6), CFrame.new(0, 0.15, 0.25), p.body, p.bodyMat)
	local mz = -(0.55 + bl)
	c.cyl("BarrelBody", bl, 0.46 * k, CFrame.new(0, 0.3 * k, -(0.55 + bl / 2)), p.dark, STEEL)
	c.cyl("Tube", bl * 0.9, 0.36 * k, CFrame.new(0, -0.12 * k, -(0.55 + bl * 0.45)), p.body, p.bodyMat)
	c.cyl("Bell", 0.4, 0.72 * k, CFrame.new(0, 0.3 * k, mz + 0.05), p.body, p.bodyMat)
	c.cyl("BellRim", 0.08, 0.76 * k, CFrame.new(0, 0.3 * k, mz - 0.13), c.acc(), p.accMat)
	c.add("Pump", V(0.56 * k, 0.4 * k, 0.8), CFrame.new(0, -0.14 * k, -(0.55 + bl * 0.42)), p.stock, p.stockMat)
	for i = 0, 3 do
		c.cyl("Shell" .. i, 0.4, 0.16 * k, CFrame.new(0.34 * k, 0.3, 0.6 - i * 0.22) * CFrame.Angles(0, 0, rad(90)), i % 2 == 0 and rgb(210, 60, 50) or rgb(235, 200, 80), SMOOTH)
	end
	c.add("Stock", V(0.48 * k, 0.62 * k, 1.3), CFrame.new(0, -0.05, 1.55) * CFrame.Angles(rad(-8), 0, 0), p.stock, p.stockMat)
	c.add("ButtPad", V(0.52 * k, 0.8 * k, 0.16), CFrame.new(0, -0.12, 2.2), p.dark, STEEL)
	return { top = { y = 0.15 + 0.35 * k, z0 = 0.9, z1 = -0.4 }, muzzle = { z = mz, y = 0.3 * k, r = 0.36 * k }, side = 0.31 * k, mid = { y = 0.15 }, barrel = { y = 0.3 * k, z0 = -0.55, z1 = mz, r = 0.23 * k } }
end

Bodies.Rocket = function(c, k, bl) -- 로켓: 굵은 발사관 + 뒤쪽 나팔 + 앞으로 튀어나온 탄두 + 손잡이 2개 + 옆 조준기
	local p = c.pal
	local L, z0 = bl * 1.25, 1.0
	local mz = z0 - L
	c.cyl("Tube", L, 0.84 * k, CFrame.new(0, 0.35, z0 - L / 2), p.body, p.bodyMat)
	c.cyl("FrontCuff", 0.4, 0.98 * k, CFrame.new(0, 0.35, mz + 0.2), p.dark, STEEL)
	c.cyl("BackBell", 0.55, 1.1 * k, CFrame.new(0, 0.35, z0 + 0.2), p.dark, STEEL)
	c.cyl("BellGlow", 0.06, 0.8 * k, CFrame.new(0, 0.35, z0 + 0.49), c.acc(), p.accMat)
	c.add("Warhead", V(0.78 * k, 0.78 * k, 0.78 * k), CFrame.new(0, 0.35, mz - 0.1), c.acc(), p.rainbow and NEON or SMOOTH, { Shape = Enum.PartType.Ball })
	c.cyl("WarCone", 0.5, 0.5 * k, CFrame.new(0, 0.35, mz - 0.45), p.dark, STEEL)
	c.cyl("Stripe", 0.14, 0.88 * k, CFrame.new(0, 0.35, z0 - L * 0.35), c.acc(), p.accMat)
	c.add("Grip", V(0.3, 0.8, 0.36), CFrame.new(0, -0.4, 0.3) * CFrame.Angles(rad(-10), 0, 0), p.stock, p.stockMat)
	c.add("FrontGrip", V(0.26, 0.7, 0.3), CFrame.new(0, -0.3, -0.9), p.stock, p.stockMat)
	c.add("Sight", V(0.3, 0.42, 0.6), CFrame.new(-0.5 * k, 0.35 + 0.36 * k, -0.3), p.dark, STEEL)
	c.add("SightLens", V(0.24, 0.24, 0.05), CFrame.new(-0.5 * k, 0.35 + 0.42 * k, -0.61), c.acc(), p.accMat)
	c.add("ShoulderPad", V(0.6 * k, 0.24, 0.8), CFrame.new(0, 0.35 - 0.5 * k, 0.55), p.stock, p.stockMat)
	return { top = { y = 0.35 + 0.42 * k, z0 = z0 - 0.1, z1 = mz + 0.5 }, muzzle = { z = mz - 0.7, y = 0.35, r = 0.42 * k }, side = 0.42 * k, mid = { y = 0.35 }, barrel = { y = 0.35, z0 = z0, z1 = mz - 0.7, r = 0.42 * k } }
end

Bodies.Rail = function(c, k, bl) -- 레일건: 갈라진 두 갈래 레일 + 가속 고리 + 투명 에너지 셀 + 꼬리 지느러미
	local p = c.pal
	c.add("Grip", V(0.34, 0.9, 0.42), CFrame.new(0, -0.62, 0.45) * CFrame.Angles(rad(-14), 0, 0), p.stock, p.stockMat)
	c.add("Receiver", V(0.66 * k, 0.7 * k, 2.0), CFrame.new(0, 0.2, 0.25), p.body, p.bodyMat)
	c.add("Back", V(0.5 * k, 0.5 * k, 0.9), CFrame.new(0, 0.12, 1.65), p.stock, p.stockMat)
	local mz = -(0.75 + bl)
	for side = -1, 1, 2 do
		c.add("Prong" .. side, V(0.16 * k, 0.42 * k, bl), CFrame.new(side * 0.24 * k, 0.2, -(0.75 + bl / 2)), p.dark, STEEL)
		c.add("Strip" .. side, V(0.05, 0.1 * k, bl * 0.92), CFrame.new(side * 0.16 * k, 0.2, -(0.75 + bl / 2)), c.acc(), p.accMat)
	end
	for i = 1, 3 do
		c.cyl("Ring" .. i, 0.1, (0.95 - i * 0.08) * k, CFrame.new(0, 0.2, -(0.75 + bl * i / 4)), p.body, p.bodyMat)
	end
	c.cyl("Cell", 1.0, 0.42 * k, CFrame.new(0, 0.2 + 0.52 * k, 0.3), rgb(200, 236, 255), Enum.Material.Glass, { Transparency = 0.5 })
	c.cyl("CellCore", 0.8, 0.22 * k, CFrame.new(0, 0.2 + 0.52 * k, 0.3), c.acc(), p.accMat)
	for side = -1, 1, 2 do
		c.add("Fin" .. side, V(0.08, 0.6 * k, 0.8), CFrame.new(side * 0.36 * k, 0.2 + 0.3 * k, 1.0) * CFrame.Angles(0, 0, rad(side * -18)), p.body, p.bodyMat)
	end
	return { top = { y = 0.2 + 0.35 * k, z0 = 1.3, z1 = -0.6 }, muzzle = { z = mz, y = 0.2, r = 0.3 * k }, side = 0.33 * k, mid = { y = 0.2 }, barrel = { y = 0.2, z0 = -0.75, z1 = mz, r = 0.3 * k } }
end

Bodies.Flamer = function(c, k) -- 마법책: 두꺼운 표지 + 책장 덩어리 + 모서리 쇠장식 + 위에 떠 있는 마법 구슬 (쏘는 곳 = 구슬)
	local p = c.pal
	local at = CFrame.new(0, 0.45, -0.85) * CFrame.Angles(rad(-8), 0, 0)
	for side = -1, 1, 2 do
		local leaf = at * CFrame.Angles(0, 0, rad(side * -10))
		c.add("Cover" .. side, V(1.05 * k, 0.16, 1.45 * k), leaf * CFrame.new(side * 0.54 * k, 0, 0), p.body, p.bodyMat)
		c.add("Pages" .. side, V(0.94 * k, 0.22, 1.32 * k), leaf * CFrame.new(side * 0.5 * k, 0.17, 0), PAGE, Enum.Material.Fabric)
		c.add("Rune" .. side, V(0.5 * k, 0.03, 0.5 * k), leaf * CFrame.new(side * 0.5 * k, 0.29, 0), c.acc(), p.accMat, { Transparency = 0.15 })
		c.add("Corner" .. side, V(0.3 * k, 0.2, 0.3 * k), leaf * CFrame.new(side * 0.95 * k, 0.02, -0.6 * k), p.stock, STEEL)
	end
	c.add("Spine", V(0.22 * k, 0.26, 1.48 * k), at * CFrame.new(0, -0.06, 0), p.dark, STEEL)
	c.add("Strap", V(0.12, 0.6, 0.12), at * CFrame.new(0, -0.3, 0.72 * k), p.stock, Enum.Material.Leather)
	local orb = at * CFrame.new(0, 1.05 * k, -0.1)
	c.add("Orb", V(0.46 * k, 0.46 * k, 0.46 * k), orb, c.acc(), NEON, { Shape = Enum.PartType.Ball })
	c.add("OrbShell", V(0.72 * k, 0.72 * k, 0.72 * k), orb, p.acc, Enum.Material.Glass, { Shape = Enum.PartType.Ball, Transparency = 0.55 })
	for side = -1, 1, 2 do
		c.add("Moon" .. side, V(0.14 * k, 0.14 * k, 0.14 * k), orb * CFrame.new(side * 0.55 * k, 0.1 * side, 0), p.acc, NEON, { Shape = Enum.PartType.Ball })
	end
	c.add("Grip", V(0.3, 0.7, 0.3), CFrame.new(0, -0.4, 0.1), p.dark, STEEL)
	local orbPos = orb.Position
	return { top = { y = 0.75, z0 = 0.0, z1 = -1.3 }, muzzle = { z = -1.4, y = 1.25, r = 0.2 * k }, side = 0.14 * k, mid = { y = 0.45 },
		barrel = { y = orbPos.Y, z0 = orbPos.Z, z1 = orbPos.Z - 0.5, r = 0.1 }, hideBarrel = true, noRings = true }
end

------------------ 시대 장식 (앵커 기준: 크고 또렷한 실루엣) ------------------
-- a = 앵커, t = 윗면 선, along(f) = 윗면 선의 뒤(0) ~ 앞(1) 위치
local EraKit = {}
EraKit[1] = function(c, a, k, along) -- 녹슨: 감은 천 테이프 + 녹 얼룩
	local t, sd = a.top, a.side
	local cloth, rust = rgb(150, 140, 120), rgb(150, 80, 40)
	c.cyl("Tape", 0.26, sd * 2 + 0.06, CFrame.new(0, a.mid.y, along(0.35)), cloth, Enum.Material.Fabric)
	c.cyl("Tape2", 0.18, sd * 2 + 0.05, CFrame.new(0, a.mid.y, along(0.6)), cloth, Enum.Material.Fabric)
	c.add("Rust1", V(sd * 1.6, 0.06, 0.35), CFrame.new(0, t.y + 0.01, along(0.2)), rust, Enum.Material.CorrodedMetal)
	c.add("Rust2", V(0.06, 0.25, 0.4), CFrame.new(sd + 0.01, a.mid.y, along(0.8)), rust, Enum.Material.CorrodedMetal)
end
EraKit[2] = function(c, a, k, along) -- 강철: 등줄기 레일 + 푸른 줄 + 리벳
	local t, sd, len = a.top, a.side, a.top.z0 - a.top.z1
	c.add("TopRail", V(0.22, 0.1, len * 0.8), CFrame.new(0, t.y + 0.05, along(0.5)), c.pal.dark, STEEL)
	for side = -1, 1, 2 do
		c.add("SideLine" .. side, V(0.04, 0.08, len * 0.7), CFrame.new(side * (sd + 0.02), a.mid.y + 0.08, along(0.5)), c.acc(), c.pal.accMat)
	end
	for i = 0, 2 do
		c.add("Rivet" .. i, V(0.1, 0.1, 0.1), CFrame.new(sd + 0.03, a.mid.y - 0.12, along(0.25 + i * 0.25)), rgb(220, 228, 240), STEEL, { Shape = Enum.PartType.Ball })
	end
end
EraKit[3] = function(c, a, k, along) -- 마력: 위에 솟은 수정 3개 + 옆면 룬 마름모
	local t, sd = a.top, a.side
	for i = 0, 2 do
		c.add("Crystal" .. i, V(0.28 * k, 0.7 * k, 0.28 * k), CFrame.new((i - 1) * 0.4 * k, t.y + 0.6 * k + (i == 1 and 0.25 or 0), along(0.45)) * CFrame.Angles(0, rad(45), rad((i - 1) * -20)), c.acc(), c.pal.accMat, { Transparency = 0.1 })
	end
	for i = 0, 1 do
		for side = -1, 1, 2 do
			c.add("Rune" .. i .. side, V(0.04, 0.22 * k, 0.22 * k), CFrame.new(side * (sd + 0.03), a.mid.y, along(0.25 + i * 0.45)) * CFrame.Angles(rad(45), 0, 0), c.acc(), c.pal.accMat)
		end
	end
end
EraKit[4] = function(c, a, k, along) -- 황금: 금 테두리 + 등의 금 왕관 볏 + 큰 루비 + 총구 금테 + 작은 금 날개
	local t, sd, m, len = a.top, a.side, a.muzzle, a.top.z0 - a.top.z1
	local gold = rgb(255, 214, 90)
	for side = -1, 1, 2 do
		c.add("GoldTrim" .. side, V(0.05, 0.16, len * 0.8), CFrame.new(side * (sd + 0.03), a.mid.y + 0.1, along(0.5)), gold, SMOOTH)
	end
	for i = 0, 2 do
		c.add("Crown" .. i, V(0.1, (0.32 + (i == 1 and 0.16 or 0)) * k, 0.3 * k), CFrame.new(0, t.y + 0.16 * k + (i == 1 and 0.08 * k or 0), along(0.35 + i * 0.13)), gold, SMOOTH, { Wedge = true })
	end
	c.add("Ruby", V(0.36 * k, 0.36 * k, 0.36 * k), CFrame.new(sd + 0.1, a.mid.y + 0.05, along(0.3)), rgb(230, 40, 70), NEON, { Shape = Enum.PartType.Ball })
	c.cyl("GoldBand", 0.16, m.r * 2 + 0.08, CFrame.new(0, m.y, m.z + 0.2), gold, SMOOTH)
	for side = -1, 1, 2 do
		c.add("GoldWing" .. side, V(0.06, 0.6 * k, 1.0 * k), CFrame.new(side * (sd + 0.14), t.y + 0.12, along(0.88)) * CFrame.Angles(0, 0, rad(side * -40)), gold, SMOOTH, { Wedge = true })
	end
end
EraKit[5] = function(c, a, k, along) -- 불꽃: 등에 솟은 불꽃 지느러미 3장 + 총구 불씨 띠 + 옆 통풍구
	local t, sd, m = a.top, a.side, a.muzzle
	for i = 0, 2 do
		c.add("FlameFin" .. i, V(0.14, (0.7 + i * 0.16) * k, 0.9 * k), CFrame.new(0, t.y + (0.35 + i * 0.08) * k, along(0.25 + i * 0.25)), i % 2 == 0 and rgb(255, 110, 40) or rgb(255, 180, 60), NEON, { Wedge = true, Transparency = 0.05 })
	end
	c.cyl("EmberRing", 0.14, m.r * 2 + 0.06, CFrame.new(0, m.y, m.z + 0.25), rgb(255, 150, 60), NEON)
	for side = -1, 1, 2 do
		c.add("Vent" .. side, V(0.04, 0.2, 0.5), CFrame.new(side * (sd + 0.02), a.mid.y, along(0.7)), rgb(255, 120, 50), NEON)
	end
end
EraKit[6] = function(c, a, k, along) -- 빙결: 등에서 솟은 얼음 결정 무리 + 총구 고드름 + 서리 덮개
	local t, sd, m, len = a.top, a.side, a.muzzle, a.top.z0 - a.top.z1
	local ice = rgb(200, 240, 255)
	for i = 0, 3 do
		local s = i % 2 == 0 and 1 or -1
		c.add("IceSpike" .. i, V(0.24 * k, (0.75 + (i % 2) * 0.35) * k, 0.24 * k), CFrame.new(s * 0.16 * k, t.y + 0.4 * k, along(0.2 + i * 0.2)) * CFrame.Angles(rad(-25), rad(45), rad(s * 18)), ice, Enum.Material.Ice, { Transparency = 0.15 })
	end
	for side = -1, 1, 2 do
		c.add("Icicle" .. side, V(0.12 * k, 0.4 * k, 0.12 * k), CFrame.new(side * m.r * 0.6, m.y - m.r - 0.12 * k, m.z + 0.3) * CFrame.Angles(0, rad(45), 0), ice, Enum.Material.Ice, { Transparency = 0.15 })
	end
	c.add("Frost", V(sd * 2 + 0.06, 0.12, len * 0.5), CFrame.new(0, t.y + 0.02, along(0.5)), rgb(235, 250, 255), Enum.Material.Ice, { Transparency = 0.35 })
end
EraKit[7] = function(c, a, k, along) -- 번개: 테슬라 코일 2개 + 코일 사이 지그재그 번개 + 옆 번개 무늬
	local t, sd = a.top, a.side
	for i = 0, 1 do
		local z = along(0.3 + i * 0.4)
		c.cyl("Coil" .. i, 0.55 * k, 0.3 * k, CFrame.new(0, t.y + 0.3 * k, z) * CFrame.Angles(rad(90), 0, 0), rgb(200, 140, 70), STEEL)
		c.add("CoilTop" .. i, V(0.3 * k, 0.3 * k, 0.3 * k), CFrame.new(0, t.y + 0.65 * k, z), c.acc(), NEON, { Shape = Enum.PartType.Ball })
	end
	for i = 0, 2 do
		c.add("Zig" .. i, V(0.06, 0.06, 0.42 * k), CFrame.new(0, t.y + 0.68 * k + (i % 2) * 0.14, along(0.38 + i * 0.12)) * CFrame.Angles(rad(i % 2 == 0 and 30 or -30), 0, 0), c.acc(), NEON)
	end
	for side = -1, 1, 2 do
		c.add("Bolt" .. side, V(0.04, 0.3, 0.12), CFrame.new(side * (sd + 0.02), a.mid.y, along(0.75)) * CFrame.Angles(rad(25), 0, 0), c.acc(), NEON)
	end
end
EraKit[8] = function(c, a, k, along) -- 암흑: 위에 뜬 허공 구슬 + 검은 가시 볏 + 아래로 늘어진 촉수
	local t, sd = a.top, a.side
	local z = along(0.45)
	c.add("VoidOrb", V(0.6 * k, 0.6 * k, 0.6 * k), CFrame.new(0, t.y + 0.75 * k, z), rgb(14, 4, 26), SMOOTH, { Shape = Enum.PartType.Ball })
	c.add("VoidGlow", V(0.9 * k, 0.9 * k, 0.9 * k), CFrame.new(0, t.y + 0.75 * k, z), c.acc(), NEON, { Shape = Enum.PartType.Ball, Transparency = 0.72 })
	for i = 0, 3 do
		c.add("Spike" .. i, V(0.12, 0.65 * k, 0.5 * k), CFrame.new(0, t.y + 0.3 * k, along(0.12 + i * 0.24)), c.pal.dark, SMOOTH, { Wedge = true })
	end
	for side = -1, 1, 2 do
		c.add("Tendril" .. side, V(0.1, 0.1, 0.9 * k), CFrame.new(side * sd * 0.8, a.mid.y - 0.35 * k, along(0.3)) * CFrame.Angles(rad(-40), rad(side * 15), 0), rgb(70, 30, 110), SMOOTH)
	end
end
EraKit[9] = function(c, a, k, along) -- 용: 뒤로 휜 뿔 한 쌍 + 등 비늘 + 노란 눈 + 총구 아래 용 턱
	local t, sd, m = a.top, a.side, a.muzzle
	for side = -1, 1, 2 do
		c.add("HornA" .. side, V(0.2 * k, 0.2 * k, 0.8 * k), CFrame.new(side * sd * 0.7, t.y + 0.2 * k, along(0.15)) * CFrame.Angles(rad(35), rad(side * -15), 0), c.pal.stock, SMOOTH)
		c.add("HornB" .. side, V(0.15 * k, 0.15 * k, 0.7 * k), CFrame.new(side * sd * 0.8, t.y + 0.5 * k, along(0) + 0.3 * k) * CFrame.Angles(rad(70), rad(side * -15), 0), c.pal.stock, SMOOTH)
		c.add("Eye" .. side, V(0.16 * k, 0.16 * k, 0.16 * k), CFrame.new(side * (sd + 0.03), a.mid.y + 0.12, along(0.92)), rgb(255, 210, 60), NEON, { Shape = Enum.PartType.Ball })
	end
	for i = 0, 3 do
		c.add("Scale" .. i, V(0.34 * k, 0.4 * k, 0.45 * k), CFrame.new(0, t.y + 0.12 * k, along(0.3 + i * 0.17)), rgb(110, 24, 20), STEEL, { Wedge = true })
	end
	c.add("Jaw", V(m.r * 1.6, 0.22 * k, 0.5 * k), CFrame.new(0, m.y - m.r - 0.05, m.z + 0.2) * CFrame.Angles(rad(180), 0, 0), c.pal.stock, SMOOTH, { Wedge = true })
end
EraKit[10] = function(c, a, k, along) -- 신화: 뒤에서 위로 활짝 펼친 흰 날개(깃 3장씩) + 떠 있는 후광(빛 구슬 6개) + 옆 보석
	local t, sd = a.top, a.side
	local z = along(0.55)
	for i = 0, 5 do
		local ang = i / 6 * math.pi * 2
		c.add("Halo" .. i, V(0.14 * k, 0.14 * k, 0.14 * k), CFrame.new(math.cos(ang) * 0.42 * k, t.y + 0.85 * k, z + math.sin(ang) * 0.42 * k), rgb(255, 236, 150), NEON, { Shape = Enum.PartType.Ball })
	end
	for side = -1, 1, 2 do
		for j = 0, 2 do
			local L = (1.5 - j * 0.32) * k
			c.add("Feather" .. side .. j, V(0.08, 0.3 * k, L), CFrame.new(side * (sd + 0.05), t.y + 0.05, along(0.75)) * CFrame.Angles(0, 0, rad(side * -(30 + j * 22))) * CFrame.Angles(rad(-55), 0, 0) * CFrame.new(0, 0, L / 2),
				j == 2 and c.acc() or rgb(255, 255, 255), j == 2 and NEON or SMOOTH)
		end
	end
	c.add("Core", V(0.3 * k, 0.3 * k, 0.3 * k), CFrame.new(sd + 0.1, a.mid.y, along(0.3)), c.acc(), NEON, { Shape = Enum.PartType.Ball })
end

local function buildTool(level, typeKey)
	typeKey = Config.ResolveWeaponType(level, typeKey)
	local tier = Config.GetLookTier(level, typeKey) -- 고른 무기 형 + 지금 시대의 외모
	local scale = Config.GetWeaponScale(level)
	local weaponType = Config.WeaponTypes[typeKey] or Config.WeaponTypes.Pistol
	local bodyLength = 1.8 * scale * weaponType.BarrelLength * (typeKey == "Shotgun" and 1.2 or 1)
	local colorSeq = tier.Rainbow and RAINBOW or ColorSequence.new(tier.Color)
	local pal = ERA_PALETTE[tier.Era] or ERA_PALETTE[2]
	local k = math.min(scale, 1.7)

	local tool = Instance.new("Tool")
	tool.Name = "Weapon"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = Config.FormatWeapon(level, typeKey)

	local handle = newPart("Handle", V(0.4, 0.6, 1.2), pal.dark, STEEL, tool)

	-- 부품을 붙이는 도구 모음
	local rainbowIndex = 0
	local c = { pal = pal, used = 0 }
	function c.acc()
		if pal.rainbow then
			rainbowIndex += 1
			return RAINBOW_ACC[(rainbowIndex - 1) % #RAINBOW_ACC + 1]
		end
		return pal.acc
	end
	function c.add(name, size, offset, color, material, extra)
		if c.used >= PART_BUDGET then return nil end -- 예산이 차면 생략 (뒤쪽 장식이 먼저 사라진다)
		c.used += 1
		local part
		if extra and extra.Wedge then
			part = Instance.new("WedgePart")
			part.Name, part.Size, part.Color, part.Material = name, size, color, material or STEEL
			part.CanCollide, part.CanQuery, part.CanTouch, part.Massless = false, false, false, true
			part.Parent = tool
		else
			part = newPart(name, size, color, material or STEEL, tool)
		end
		if extra and extra.Shape then part.Shape = extra.Shape end
		if extra and extra.Transparency then part.Transparency = extra.Transparency end
		part.CFrame = handle.CFrame * offset
		weld(handle, part)
		return part
	end
	function c.cyl(name, length, diameter, offset, color, material, extra)
		local data = { Shape = Enum.PartType.Cylinder, Transparency = extra and extra.Transparency }
		return c.add(name, V(length, diameter, diameter), offset * CFrame.Angles(0, rad(90), 0), color, material, data)
	end

	local anchors = (Bodies[typeKey] or Bodies.Pistol)(c, k, bodyLength)

	-- 총구 표시용 "Barrel" (발사 위치 Tip / 꼬리 / 반짝이가 여기 붙는다). 보이는 총열은 몸체가 따로 그린다
	local b = anchors.barrel
	local barrelLength = math.max(0.3, b.z0 - b.z1)
	local barrel = newPart("Barrel", V(b.r * 2, b.r * 2, barrelLength), tier.Color, SMOOTH, tool)
	barrel.Transparency = 1
	barrel.CFrame = handle.CFrame * CFrame.new(0, b.y, (b.z0 + b.z1) / 2)
	weld(handle, barrel)

	-- 강화 단계 띠: 이 무기 안에서 단계가 오를수록 총열에 빛 띠가 하나씩 늘어난다 (최대 3개)
	local stage = Config.GetWeaponStage(level)
	local steps = math.max(1, Config.GetWeaponTier(level).Steps)
	if not anchors.noRings then
		for i = 1, math.min(3, math.floor(stage * 4 / steps)) do
			local z = b.z0 + (b.z1 - b.z0) * (0.2 + 0.18 * i)
			c.cyl("StageRing" .. i, 0.09, b.r * 2 + 0.06, CFrame.new(0, b.y, z), c.acc(), pal.accMat)
		end
	end

	-- 시대 장식
	local t = anchors.top
	local len = t.z0 - t.z1
	local function along(f) return t.z0 - len * f end
	if EraKit[tier.Era] then EraKit[tier.Era](c, anchors, k, along) end

	local tip = Instance.new("Attachment")
	tip.Name = "Tip"
	tip.Position = Vector3.new(0, 0, -barrelLength / 2)
	tip.Parent = barrel

	local base = Instance.new("Attachment")
	base.Name = "Base"
	base.Position = Vector3.new(0, 0, barrelLength / 2)
	base.Parent = barrel

	-- 총구 화염 (발사할 때 Weapon.PlayShot 에서 잠깐 터짐)
	local muzzle = Instance.new("ParticleEmitter")
	muzzle.Name = "Muzzle"
	muzzle.Rate = 0
	muzzle.Lifetime = NumberRange.new(0.06, 0.12)
	muzzle.Speed = NumberRange.new(4, 10)
	muzzle.SpreadAngle = Vector2.new(25, 25)
	muzzle.EmissionDirection = Enum.NormalId.Front
	muzzle.LightEmission = 1
	muzzle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9 * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	muzzle.Color = colorSeq
	muzzle.Parent = tip

	local flash = Instance.new("PointLight")
	flash.Name = "MuzzleLight"
	flash.Enabled = false
	flash.Range = 12
	flash.Brightness = 3
	flash.Color = tier.Rainbow and Color3.fromRGB(255, 255, 255) or tier.Color
	flash.Parent = tip

	if tier.Particles > 0 then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Sparkle"
		emitter.Rate = math.min(tier.Particles, 30)
		emitter.Lifetime = NumberRange.new(0.4, 0.9)
		emitter.Speed = NumberRange.new(0.5, 2)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Shape = Enum.ParticleEmitterShape.Box
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3 * scale),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.LightEmission = 1
		emitter.Color = colorSeq
		emitter.Parent = barrel
	end

	if tier.Trail then
		local trail = Instance.new("Trail")
		trail.Attachment0 = base
		trail.Attachment1 = tip
		trail.Lifetime = 0.4
		trail.Color = colorSeq
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Parent = barrel
	end

	if tier.Light > 0 then
		local light = Instance.new("PointLight")
		light.Range = tier.Light * 0.6 -- (몸체 색이 시대를 보여 주므로 빛은 은은하게: 눈부심 방지)
		light.Brightness = 0.8
		light.Color = tier.Rainbow and Color3.fromRGB(255, 255, 255) or tier.Color
		light.Parent = barrel
	end

	return tool
end

------------------------------------------------------------
-- 머리 위 이름표: 이름 + 무기 강화 레벨 (다른 플레이어에게 과시)
------------------------------------------------------------
local function updateNameplate(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then return end

	local gui = head:FindFirstChild("Nameplate")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "Nameplate"
		gui.Size = UDim2.new(0, 190, 0, 42)
		gui.StudsOffset = Vector3.new(0, 4.4, 0) -- 머리 위로 높이 (총 / 조준점과 겹치지 않게)
		gui.MaxDistance = 70
		gui.Parent = head

		local function addLabel(name, y, height, font)
			local label = Instance.new("TextLabel")
			label.Name = name
			label.Size = UDim2.new(1, 0, height, 0)
			label.Position = UDim2.new(0, 0, y, 0)
			label.BackgroundTransparency = 1
			label.Font = font
			label.TextScaled = true
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0.3
			label.Parent = gui
		end
		-- 머리 위에는 이름과 전투력만 (무기 / 구역 기록은 메뉴에서 본다)
		addLabel("PlayerName", 0, 0.45, Enum.Font.GothamBold)
		addLabel("Power", 0.45, 0.55, Enum.Font.GothamBlack)
	end

	local inParty = (player:GetAttribute("PartyId") or 0) ~= 0

	local title = player:GetAttribute("Title") or ""
	gui.PlayerName.Text = (inParty and "[Party] " or "") .. (title ~= "" and ("『" .. title .. "』 ") or "") .. player.DisplayName
	gui.Power.Text = string.format("⚡ Power %d", player:GetAttribute("Power") or 0)
	gui.Power.TextColor3 = Color3.fromRGB(255, 225, 110)
end

Weapon.UpdateNameplate = updateNameplate

------------------------------------------------------------
-- 진화 미리보기: 종류 x 단계별 총 모델을 ReplicatedStorage.WeaponPreviews 에 만들어 둔다
-- (클라이언트가 복제해서 강화창 / 무기 탭의 3D 미리보기에 쓴다. 이름: <종류>_<단계번호>)
------------------------------------------------------------
function Weapon.BuildPreviews()
	local rs = game:GetService("ReplicatedStorage")
	local old = rs:FindFirstChild("WeaponPreviews")
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "WeaponPreviews"
	do
		for index, tier in ipairs(Config.Weapon.Tiers) do
			local tool = buildTool(Config.Weapon.Tiers[(tier.Era - 1) * #Config.WeaponTypes.Order + 1].MinLevel, tier.Class) -- 그 시대가 시작되는 단계 (그 시대의 외모)
			local model = Instance.new("Model")
			model.Name = "W" .. index
			for _, child in ipairs(tool:GetChildren()) do
				child.Parent = model
			end
			model.PrimaryPart = model:FindFirstChild("Handle")
			tool:Destroy()
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
				elseif d:IsA("PointLight") then
					d:Destroy()
				end
			end
			model.Parent = folder
		end
	end
	folder.Parent = rs
end

------------------------------------------------------------
-- 장착 / 갱신
------------------------------------------------------------
function Weapon.Attach(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local old = character:FindFirstChild("Weapon")
	if old then
		old:Destroy()
	end

	local tool = buildTool(player:GetAttribute("WeaponLevel") or 0, player:GetAttribute("WeaponType") or "Pistol")
	humanoid:EquipTool(tool)
end

function Weapon.Refresh(player)
	Weapon.Attach(player)
	updateNameplate(player)
end

function Weapon.GetTipPosition(player)
	local character = player.Character
	local tool = character and character:FindFirstChild("Weapon")
	local barrel = tool and tool:FindFirstChild("Barrel")
	local tip = barrel and barrel:FindFirstChild("Tip")
	return tip and tip.WorldPosition or nil
end

-- 사운드 재생 (ID가 0이면 아무것도 안 함)
local function playSoundAt(parent, soundId, volume, pitch, name)
	if not soundId or soundId == 0 then return end
	local sound = Instance.new("Sound")
	sound.Name = name or "Sfx" -- 총소리는 "GunShot": 클라이언트가 이 이름을 보고 내 설정 볼륨을 적용한다
	sound.SoundId = "rbxassetid://" .. soundId
	sound.Volume = volume
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMaxDistance = 90
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 3)
end

local lastPitchIndex = setmetatable({}, { __mode = "k" })
local shotCount, lastShotSound = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" }) -- 발사음 변주용
local SHOT_PITCH_PATTERN = { 1.0, 1.25, 0.84, 1.5, 0.75, 1.12, 0.94, 1.34, 0.7, 1.18, 1.42, 0.88, 1.06, 1.3, 0.78, 1.5 } -- 여덟 박자: 높고 낮음이 확실히 오르내린다

-- 발사 연출: 칼 휘두르기 대신 총구 화염 + 반동(총이 뒤로 살짝 밀림) + 발사음.
-- 팔은 기본 애니메이션의 "무기를 앞으로 든 자세"를 그대로 유지한다.
function Weapon.PlayShot(player)
	local character = player.Character
	local tool = character and character:FindFirstChild("Weapon")
	local barrel = tool and tool:FindFirstChild("Barrel")
	local tip = barrel and barrel:FindFirstChild("Tip")
	if not tip then return end

	-- 총구 불꽃 / 반동은 총 종류(라이플 / 저격총 / 로켓 / 레일건)만: 마법책은 총처럼 번쩍이거나 튀지 않는다
	local isGun = Config.ResolveWeaponType(player:GetAttribute("WeaponLevel") or 0, player:GetAttribute("WeaponType")) ~= "Flamer"
	local muzzle = isGun and tip:FindFirstChild("Muzzle")
	if muzzle then
		muzzle:Emit(6)
	end
	local light = isGun and tip:FindFirstChild("MuzzleLight")
	if light then
		light.Enabled = true
		task.delay(0.05, function()
			if light.Parent then
				light.Enabled = false
			end
		end)
	end

	-- 반동: 손과 총을 잇는 RightGrip의 위치를 잠깐 뒤로 밀었다가 되돌림
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	local grip = isGun and hand and hand:FindFirstChild("RightGrip")
	if grip then
		local rest = grip:GetAttribute("RestC1")
		if not rest then
			rest = grip.C1
			grip:SetAttribute("RestC1", rest)
		end
		local kick = TweenService:Create(grip, TweenInfo.new(0.04), { C1 = rest * CFrame.Angles(math.rad(6), 0, 0) * CFrame.new(0, 0, -0.35) })
		kick.Completed:Connect(function()
			if grip.Parent then
				TweenService:Create(grip, TweenInfo.new(0.1), { C1 = rest }):Play()
			end
		end)
		kick:Play()
	end

	-- 무기가 강할수록 낮고 묵직한 소리
	-- 무기 종류마다 다른 소리 (SoundBank: 같은 기본 소리를 피치 / 잔향 / 왜곡 / 겹치기로 가공). 세대가 높을수록 살짝 낮고 묵직하게
	local level = player:GetAttribute("WeaponLevel") or 0
	local tier = Config.GetLookTier(level, Config.ResolveWeaponType(level, player:GetAttribute("WeaponType")))
	local eraFactor = math.max(0.8, 1.08 - 0.03 * (tier.Era - 1))
	-- 똑같은 소리가 "탕탕탕탕" 반복되지 않게: 쏠 때마다 높낮이 / 크기가 조금씩 달라지고(네 박자 패턴 + 무작위),
	-- 아주 빠르게 연사할 때는 일부 발사음을 건너뛰거나 작게 해서 소리가 뭉개지지 않고 리듬이 생긴다
	local now = os.clock()
	local count = (shotCount[player] or 0) + 1
	shotCount[player] = count
	local gap = now - (lastShotSound[player] or 0)
	if gap < 0.06 and count % 2 == 0 then return end -- 아주 빠른 연사(0.06초 미만)만 두 발에 한 발 (예전 0.1초: 기관단총 소리가 절반 빠져 묻혔다)
	lastShotSound[player] = now
	-- 박자가 일정하면 지루하므로: 높낮이를 무작위로 고르되 바로 앞과 같은 음은 피하고, 가끔 아주 낮은 "쿵" / 높은 "탕" 강조음을 섞는다
	local index = math.random(#SHOT_PITCH_PATTERN)
	if index == lastPitchIndex[player] then index = index % #SHOT_PITCH_PATTERN + 1 end
	lastPitchIndex[player] = index
	local pitch = eraFactor * SHOT_PITCH_PATTERN[index] * (0.9 + math.random() * 0.2)
	local volume = 0.85 + math.random() * 0.3 -- (예전 0.65~1.25 x 연사 0.85: 작게 나는 발사음이 많아 묻혔다)
	if math.random() < 0.14 then
		pitch *= (math.random() < 0.5) and 0.72 or 1.38
		volume *= 1.2
	end
	Effects.GunSound(barrel.Position, tier.Class, pitch, volume, tier.Era) -- 소리는 근처 플레이어 화면에서 재생 (서버가 소리 부품을 만들지 않는다)
end

------------------------------------------------------------
-- 강화: 골드를 내고 확률적으로 +1. 실패해도 레벨은 내려가지 않음.
-- 반환: ok(성공 여부), message
------------------------------------------------------------
function Weapon.Enhance(player)
	if player:GetAttribute("Zone") ~= "Lobby" then
		return false, "Weapons can only be upgraded in the lobby.", true
	end

	local level = player:GetAttribute("WeaponLevel") or 0
	if level >= Config.Weapon.MaxLevel then
		return false, "You maxed out the final weapon!", true
	end

	-- 튜토리얼 미션 중에는 +3까지 무료 + 100% 성공
	if player:GetAttribute("TutorialFree") == true and level >= 3 then -- 무료 강화는 딱 3번: 미션이 넘어가는 짧은 사이에 광클해서 골드로 한 번 더 강화되지 않게 막는다
		return false, "✨ Free upgrades end here! Check your next mission", true
	end
	local free = player:GetAttribute("TutorialFree") == true and level < 3
	local cost = free and 0 or Config.GetEnhanceCost(level)
	local sure = free
	local tutorialCost = player:GetAttribute("TutorialEnhanceCost")
	if tutorialCost and not free then -- 진화 미션: 비용을 낮추고 100% 성공
		cost = math.min(cost, tutorialCost)
		sure = true
	end
	local gold = player:GetAttribute("Gold") or 0
	if gold < cost then
		return false, string.format("💰 Not enough gold. (%d needed) Earn gold from field hunting, dungeons, the Boss Rush, or idle income", cost), true
	end

	player:SetAttribute("Gold", gold - cost)

	if sure or math.random() < Config.GetEnhanceChance(level) then
		-- 단계가 오르면 GameServer 가 무기 종류를 맞추고 모델도 갱신한다. 마지막 단계를 넘으면 다음 무기로 진화한다.
		player:SetAttribute("WeaponLevel", level + 1)
		Quest.Add(player, "Enhances", 1)
		local before, after = Config.GetWeaponTier(level), Config.GetWeaponTier(level + 1)
		local unlockedBefore, unlockedAfter = Config.GetUnlockedCount(level), Config.GetUnlockedCount(level + 1)
		local newForm = unlockedAfter > unlockedBefore and Config.WeaponTypes.Order[unlockedAfter] or nil
		local newEra = after.Era > before.Era
		local evolved = newForm ~= nil or newEra -- 새 무기 형이 해금되거나 시대가 바뀔 때만 큰 연출
		if newEra and after.Index >= 4 then
			Event.Announce(string.format("📢 %s's weapon evolved into [%s]!", player.DisplayName, Config.GetEraName(after.Era)))
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			Effects.Burst(root.Position, after.Color, evolved and 120 or 30)
			if evolved then
				Effects.FloatText(root.Position + Vector3.new(0, 5, 0), "⭐ " .. (newForm and Config.WeaponTypes[newForm].Name or Config.GetEraName(after.Era)), after.Color)
			end
		end
		if newForm then
			local info = Config.WeaponTypes[newForm]
			return true, string.format("🔓 %s unlocked! (%s) Pick it in the Weapons tab", info.Name, info.Trait), false, true, cost
		elseif newEra then
			local perkText = after.Perk and string.format(" · New era 『%s %s』!", after.Perk.Icon, after.Perk.Name) or ""
			return true, string.format("🎉 Evolved to %s! Your weapon look and bullet color changed%s", Config.GetEraName(after.Era), perkText), false, true, cost
		end
		return true, string.format("Upgrade success! +%d", level + 1), false, false, cost
	end
	return false, "Upgrade failed... (only the gold was lost)", false, false, cost
end

-- 해금한 무기 형 중에서 싸울 무기를 고른다
function Weapon.Equip(player, typeKey)
	local info = Config.WeaponTypes[typeKey]
	if typeKey == "Order" or typeof(info) ~= "table" then
		return false, "Unknown weapon."
	end
	local level = player:GetAttribute("WeaponLevel") or 0
	if not Config.IsWeaponUnlocked(level, typeKey) then
		return false, string.format("%s unlocks at +%d.", info.Name, Config.GetUnlockLevel(typeKey))
	end
	if player:GetAttribute("WeaponType") == typeKey then
		return true, string.format("You are already holding %s.", info.Name)
	end
	player:SetAttribute("WeaponType", typeKey)
	return true, string.format("%s equipped! (%s)", info.Name, info.Trait)
end

function Weapon.Buy()
	return false, "Weapon types unlock through upgrade levels! Pick one in the Weapons tab."
end

return Weapon
