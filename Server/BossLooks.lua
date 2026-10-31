-- BossLooks (ServerScriptService > Modules 안의 ModuleScript, 이름: BossLooks)
-- 보스 겉모양 (둥글고 유기적인 새 버전): 필드 구역 군주 8종(Zone1 ~ Zone8) + 던전 보스 3종(Cave / Ice / Fire).
-- Effects.DecorateZoneBoss / DecorateDungeonBoss 가 먼저 여기서 찾고, 없거나 오류가 나면 예전 모양을 쓴다.
-- 몸통(판정용 공, 지름 S)은 그대로 보이며 몸의 중심이 된다. 좌표는 S 의 배수. 앞 = -Z, 위 = +Y, 발밑 = -0.5.
-- d(모양, 가로, 높이, 길이, x, y, z, 색, 재질, { T, CF, Rx, Ry, Rz }) 는 Effects 가 넘겨 준다 (CF 는 몸 기준 CFrame).

local BALL, BLOCK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local Mat = Enum.Material
local Neon, Plastic, Metal, Wood, Slate, Glass, Fabric = Mat.Neon, Mat.SmoothPlastic, Mat.Metal, Mat.Wood, Mat.Slate, Mat.Glass, Mat.Fabric
local BLACK, WHITE = Color3.new(0, 0, 0), Color3.new(1, 1, 1)
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local function V(x, y, z) return Vector3.new(x, y, z) end

local M = {}
local Looks = {}
-- 몸통 공의 재질 / 색 (Effects 가 적용한다)
M.Body = {}
-- 몸에 붙이는 입자 { 색, 개수, 크기(S 배수), 속도, 수명, 가속 }
M.Fx = {}

local function copy(opts)
	local out = {}
	if opts then for k, v in pairs(opts) do out[k] = v end end
	return out
end

local function toolkit(d, S)
	local T = {}
	function T.ball(x, y, z, w, h, l, col, mat, opts)
		return d(BALL, S * w, S * h, S * l, S * x, S * y, S * z, col, mat, opts)
	end
	function T.block(x, y, z, w, h, l, col, mat, opts)
		return d(BLOCK, S * w, S * h, S * l, S * x, S * y, S * z, col, mat, opts)
	end
	-- a 에서 b 까지 원기둥 (r = 반지름)
	function T.seg(a, b, r, col, mat, opts)
		local dir = b - a
		local len = dir.Magnitude
		if len < 0.0001 then return nil end
		local xAxis = dir.Unit
		local up = (math.abs(xAxis.Y) > 0.95) and V(0, 0, 1) or V(0, 1, 0)
		local zAxis = xAxis:Cross(up).Unit
		local yAxis = zAxis:Cross(xAxis)
		local o = copy(opts)
		o.CF = CFrame.fromMatrix((a + b) * 0.5 * S, xAxis, yAxis, zAxis)
		return d(CYL, len * S, r * 2 * S, r * 2 * S, 0, 0, 0, col, mat, o)
	end
	-- 둥근 팔다리: a -> b, 반지름 r1 -> r2 (원기둥 segs 개 + 관절 구슬)
	function T.limb(a, b, r1, r2, col, mat, opts, segs)
		segs = segs or 2
		T.ball(a.X, a.Y, a.Z, r1 * 2, r1 * 2, r1 * 2, col, mat, opts)
		for i = 1, segs do
			local t0, t1 = (i - 1) / segs, i / segs
			local p0, p1 = a:Lerp(b, t0), a:Lerp(b, t1)
			T.seg(p0, p1, r1 + (r2 - r1) * (t0 + t1) / 2, col, mat, opts)
			if i < segs then
				local r = r1 + (r2 - r1) * t1
				T.ball(p1.X, p1.Y, p1.Z, r * 2, r * 2, r * 2, col, mat, opts)
			end
		end
		if r2 > 0.02 then T.ball(b.X, b.Y, b.Z, r2 * 2, r2 * 2, r2 * 2, col, mat, opts) end
	end
	-- 꺾인 팔다리: a -> 관절 j -> b
	function T.arm(a, j, b, r1, r2, col, mat, opts)
		local rj = (r1 + r2) / 2
		T.ball(a.X, a.Y, a.Z, r1 * 2.2, r1 * 2.2, r1 * 2.2, col, mat, opts)
		T.seg(a, j, (r1 + rj) / 2, col, mat, opts)
		T.ball(j.X, j.Y, j.Z, rj * 2.1, rj * 2.1, rj * 2.1, col, mat, opts)
		T.seg(j, b, (rj + r2) / 2, col, mat, opts)
	end
	-- 휜 뿔 / 엄니 / 가시: 밑동 -> 끝, bend 만큼 가운데가 휜다 (원기둥 3 + 관절 2)
	function T.horn(a, b, r, col, mat, bend, opts)
		local m1 = a:Lerp(b, 0.36) + (bend or V(0, 0, 0)) * 0.75
		local m2 = a:Lerp(b, 0.7) + (bend or V(0, 0, 0)) * 0.7
		T.seg(a, m1, r, col, mat, opts)
		T.ball(m1.X, m1.Y, m1.Z, r * 1.9, r * 1.9, r * 1.9, col, mat, opts)
		T.seg(m1, m2, r * 0.7, col, mat, opts)
		T.ball(m2.X, m2.Y, m2.Z, r * 1.3, r * 1.3, r * 1.3, col, mat, opts)
		T.seg(m2, b, r * 0.35, col, mat, opts)
	end
	-- 눈: 흰자 + 눈동자 (+ 반짝임)
	function T.eye(x, y, z, r, white, pupil, shine)
		T.ball(x, y, z, r * 2, r * 2, r * 1.6, white, Plastic)
		T.ball(x * 0.97, y - r * 0.05, z - r * 0.55, r * 1.15, r * 1.3, r * 0.6, pupil or BLACK, Plastic)
		if shine then T.ball(x - r * 0.25 * (x >= 0 and 1 or -1), y + r * 0.35, z - r * 0.75, r * 0.38, r * 0.38, r * 0.3, WHITE, Neon) end
	end
	-- 빛나는 눈 (어둠 속에서 보인다)
	function T.glow(x, y, z, r, col)
		T.ball(x, y, z, r * 2, r * 2, r * 1.5, col, Neon)
	end
	-- 납작한 판 (잎 / 깃털 / 날개막 / 갑옷판): 중심 c, 크기 w x l, 두께 t, 방향 (rx, ry, rz 도)
	function T.plate(c, w, t, l, col, mat, rx, ry, rz, opts)
		local o = copy(opts)
		o.CF = CFrame.new(c * S) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
		return d(BLOCK, S * w, S * t, S * l, 0, 0, 0, col, mat, o)
	end
	return T
end

------------------------------------------------------------
-- 필드 1구역 (초원): 꽃을 피운 덩굴 거인 — 이끼 낀 둥근 몸, 꽃잎 왕관, 덩굴 팔과 잎사귀 손, 뿌리 다리
------------------------------------------------------------
M.Body.Zone1 = { Material = Mat.Grass, Color = rgb(96, 142, 72) }
M.Fx.Zone1 = { rgb(255, 240, 160), 8, 0.05, 3, 3, V(0, 1, 0) }
Looks.Zone1 = function(T)
	local moss, mossDark, bark, barkDark = rgb(110, 160, 80), rgb(70, 112, 56), rgb(110, 80, 54), rgb(80, 58, 40)
	local petal, petalIn, gold = rgb(245, 150, 190), rgb(255, 200, 220), rgb(255, 215, 90)
	-- 배의 밝은 이끼 + 등의 어두운 이끼 덩어리
	T.ball(0, -0.06, -0.2, 0.78, 0.7, 0.4, moss, Mat.Grass)
	T.ball(0, 0.14, 0.24, 0.86, 0.66, 0.5, mossDark, Mat.Grass)
	-- 얼굴: 나무 껍질 가면 + 빛나는 눈 + 웃는 입
	T.ball(0, 0.16, -0.38, 0.5, 0.36, 0.2, bark, Wood)
	for _, s in ipairs({ -1, 1 }) do T.glow(s * 0.12, 0.2, -0.47, 0.065, rgb(255, 245, 170)) end
	T.block(0, 0.06, -0.47, 0.18, 0.04, 0.04, barkDark, Wood)
	-- 꽃잎 왕관 (바깥 8장 + 안쪽 6장 + 꽃술)
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		T.plate(V(math.cos(a) * 0.24, 0.6, math.sin(a) * 0.24), 0.2, 0.04, 0.3, petal, Plastic, 0, -math.deg(a), 28)
	end
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2 + 0.3
		T.plate(V(math.cos(a) * 0.13, 0.66, math.sin(a) * 0.13), 0.13, 0.04, 0.2, petalIn, Plastic, 0, -math.deg(a), 40)
	end
	T.ball(0, 0.7, 0, 0.16, 0.12, 0.16, gold, Neon)
	for _, s in ipairs({ -1, 1 }) do
		-- 덩굴 팔: 어깨 -> 팔꿈치 -> 잎사귀 손
		T.arm(V(s * 0.42, 0.18, 0), V(s * 0.78, -0.02, -0.12), V(s * 0.86, -0.3, -0.36), 0.09, 0.06, barkDark, Wood)
		for k = -1, 1 do
			T.plate(V(s * (0.88 + k * 0.06), -0.42, -0.42), 0.12, 0.03, 0.26, moss, Mat.Grass, 30, s * k * 30, 0)
		end
		-- 뿌리 다리 (세 갈래로 땅을 움켜쥔다)
		T.limb(V(s * 0.22, -0.3, 0), V(s * 0.3, -0.5, -0.05), 0.12, 0.09, bark, Wood)
		for k = -1, 1 do
			T.limb(V(s * 0.3, -0.5, -0.05), V(s * (0.36 + k * 0.1), -0.55, -0.05 - 0.16 + math.abs(k) * 0.08), 0.05, 0.02, barkDark, Wood, nil, 1)
		end
	end
	-- 등에 핀 버섯 무리
	for i, p in ipairs({ { -0.18, 0.3, 0.42 }, { 0.12, 0.42, 0.36 }, { 0.26, 0.18, 0.44 } }) do
		local h = 0.08 + i * 0.03
		T.seg(V(p[1], p[2], p[3]), V(p[1], p[2] + h, p[3] + 0.04), 0.025, rgb(235, 225, 200), Plastic)
		T.ball(p[1], p[2] + h, p[3] + 0.04, 0.16, 0.08, 0.16, rgb(220, 90, 70), Plastic)
	end
end

------------------------------------------------------------
-- 필드 2구역 (숲): 고목 사슴령 — 가지처럼 갈라진 거대한 뿔, 뿔에 매달린 반딧불 등불, 이끼 망토, 네 다리
------------------------------------------------------------
M.Body.Zone2 = { Material = Wood, Color = rgb(84, 62, 44) }
M.Fx.Zone2 = { rgb(170, 255, 150), 8, 0.04, 4, 3.5, V(0, 0.5, 0) }
Looks.Zone2 = function(T)
	local bark, barkLight, moss, glowGreen = rgb(66, 48, 34), rgb(104, 80, 58), rgb(74, 128, 70), rgb(160, 255, 150)
	-- 목 + 머리 + 주둥이
	T.limb(V(0, 0.2, -0.32), V(0, 0.44, -0.58), 0.17, 0.14, barkLight, Wood, nil, 1)
	T.ball(0, 0.48, -0.66, 0.34, 0.3, 0.42, barkLight, Wood)
	T.ball(0, 0.4, -0.88, 0.2, 0.17, 0.24, rgb(130, 104, 80), Wood)
	T.ball(0, 0.42, -0.99, 0.08, 0.06, 0.05, rgb(30, 22, 18), Plastic)
	for _, s in ipairs({ -1, 1 }) do
		T.glow(s * 0.11, 0.54, -0.82, 0.045, glowGreen)
		-- 귀
		T.plate(V(s * 0.2, 0.6, -0.6), 0.16, 0.03, 0.08, barkLight, Wood, 0, 0, s * -35)
		-- 갈라진 뿔: 줄기 + 가지 3개
		local base = V(s * 0.1, 0.62, -0.64)
		local top = V(s * 0.5, 1.3, -0.5)
		T.horn(base, top, 0.04, bark, Wood, V(s * 0.12, 0, 0.1))
		T.horn(V(s * 0.24, 0.9, -0.6), V(s * 0.12, 1.24, -0.82), 0.025, bark, Wood, V(0, 0, -0.06))
		T.horn(V(s * 0.38, 1.1, -0.55), V(s * 0.66, 1.36, -0.72), 0.022, bark, Wood, V(0, 0.06, 0))
		T.horn(V(s * 0.46, 1.24, -0.5), V(s * 0.52, 1.5, -0.32), 0.02, bark, Wood, V(0.04, 0, 0))
		-- 뿔에 매달린 반딧불 등불
		T.seg(V(s * 0.6, 1.24, -0.66), V(s * 0.6, 1.08, -0.66), 0.008, rgb(60, 50, 40), Plastic)
		T.ball(s * 0.6, 1.04, -0.66, 0.08, 0.1, 0.08, glowGreen, Neon)
		-- 네 다리 (앞 / 뒤) + 발굽
		for _, z in ipairs({ -0.22, 0.24 }) do -- (몸 밖으로 벌려 서야 다리가 보인다)
			T.arm(V(s * 0.34, -0.14, z), V(s * 0.46, -0.32, z - 0.06), V(s * 0.46, -0.52, z), 0.08, 0.05, bark, Wood)
			T.ball(s * 0.46, -0.54, z, 0.11, 0.06, 0.13, rgb(40, 30, 24), Plastic)
		end
	end
	-- 이끼 망토 (등) + 매달린 이끼 가닥
	T.ball(0, 0.22, 0.12, 0.92, 0.42, 0.78, moss, Mat.Grass)
	for i = -2, 2 do
		T.seg(V(i * 0.14, 0.04, 0.4), V(i * 0.15, -0.18, 0.44), 0.03, moss, Mat.Grass)
	end
	-- 꼬리
	T.ball(0, 0.18, 0.56, 0.14, 0.18, 0.12, rgb(230, 220, 200), Plastic)
end

------------------------------------------------------------
-- 필드 3구역 (황무지): 외눈 거인 — 큰 외눈, 엄니 턱, 쇠띠 감은 굵은 팔과 주먹, 등의 녹슨 가시, 쇠사슬
------------------------------------------------------------
M.Body.Zone3 = { Material = Mat.Cobblestone, Color = rgb(116, 100, 86) }
M.Fx.Zone3 = { rgb(190, 160, 120), 10, 0.1, 5, 2.5, V(0, -1, 0) }
Looks.Zone3 = function(T)
	local stone, stoneDark, rust, iron = rgb(128, 112, 96), rgb(90, 78, 68), rgb(140, 82, 52), rgb(80, 82, 90)
	-- 외눈 (흰자 + 노란 홍채 + 동공) + 눈두덩
	T.ball(0, 0.16, -0.4, 0.36, 0.36, 0.2, rgb(240, 236, 220), Plastic)
	T.ball(0, 0.16, -0.48, 0.22, 0.22, 0.08, rgb(255, 190, 70), Neon)
	T.ball(0, 0.16, -0.52, 0.1, 0.14, 0.05, BLACK, Plastic)
	T.plate(V(0, 0.36, -0.4), 0.5, 0.08, 0.16, stoneDark, Slate, -12, 0, 0)
	-- 큰 턱 + 위로 솟은 엄니
	T.ball(0, -0.14, -0.36, 0.56, 0.24, 0.3, stoneDark, Slate)
	for _, s in ipairs({ -1, 1 }) do
		T.horn(V(s * 0.16, -0.12, -0.48), V(s * 0.22, 0.08, -0.56), 0.035, rgb(225, 215, 190), Plastic, V(s * 0.02, 0, -0.03))
		-- 어깨 바위 + 굵은 팔 + 쇠띠 + 큰 주먹
		T.ball(s * 0.5, 0.26, 0, 0.42, 0.36, 0.42, stone, Mat.Rock)
		T.arm(V(s * 0.56, 0.12, -0.02), V(s * 0.76, -0.12, -0.12), V(s * 0.78, -0.32, -0.34), 0.13, 0.11, stone, Mat.Rock)
		T.seg(V(s * 0.66, 0.0, -0.07), V(s * 0.7, -0.05, -0.08), 0.15, iron, Metal)
		T.ball(s * 0.8, -0.38, -0.42, 0.34, 0.3, 0.34, stoneDark, Mat.Rock)
		-- 다리 + 발
		T.limb(V(s * 0.22, -0.3, 0.02), V(s * 0.26, -0.48, 0.0), 0.15, 0.13, stone, Mat.Rock, nil, 1)
		T.ball(s * 0.26, -0.52, -0.06, 0.32, 0.12, 0.38, stoneDark, Mat.Rock)
	end
	-- 등의 녹슨 가시 (두 줄)
	for i = 1, 5 do
		for _, s in ipairs({ -1, 1 }) do
			local z = -0.05 + i * 0.1
			T.horn(V(s * 0.16, 0.3 - i * 0.04, z + 0.2), V(s * 0.24, 0.56 - i * 0.05, z + 0.34), 0.03, rust, Metal, V(0, 0, 0.04))
		end
	end
	-- 허리에 감은 쇠사슬
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		T.ball(math.cos(a) * 0.5, -0.24, math.sin(a) * 0.5, 0.1, 0.06, 0.1, iron, Metal)
	end
end

------------------------------------------------------------
-- 필드 4구역 (사막): 전갈 왕 — 마디진 등딱지, 높이 말아 올린 꼬리와 빛나는 독침, 큰 집게, 다리 6개
------------------------------------------------------------
M.Body.Zone4 = { Material = Mat.Sandstone, Color = rgb(190, 150, 92) }
M.Fx.Zone4 = { rgb(235, 210, 150), 12, 0.1, 6, 2.2, V(2, -0.5, 0) }
Looks.Zone4 = function(T)
	local shell, shellDark, belly, venom = rgb(176, 132, 76), rgb(124, 88, 50), rgb(210, 180, 130), rgb(170, 255, 90)
	-- 등딱지 판 3장 (마디)
	for i = 0, 2 do
		T.ball(0, 0.18 - i * 0.02, -0.2 + i * 0.22, 0.86 - i * 0.12, 0.3, 0.32, i % 2 == 0 and shell or shellDark, Mat.Sandstone)
	end
	-- 머리 + 눈 여러 개
	T.ball(0, 0.06, -0.48, 0.42, 0.24, 0.26, shellDark, Mat.Sandstone)
	for _, p in ipairs({ { -0.08, 0.16 }, { 0.08, 0.16 }, { -0.16, 0.12 }, { 0.16, 0.12 } }) do
		T.glow(p[1], p[2], -0.58, 0.03, rgb(40, 20, 12))
	end
	-- 꼬리: 몸 뒤에서 위로 말려 머리 위까지 (마디 6개, 점점 가늘게) + 독침
	local tail = { V(0, 0.1, 0.48), V(0, 0.38, 0.66), V(0, 0.7, 0.66), V(0, 0.96, 0.5), V(0, 1.1, 0.24), V(0, 1.08, 0.02) }
	for i = 1, #tail - 1 do
		local r = 0.13 - i * 0.015
		T.seg(tail[i], tail[i + 1], r, i % 2 == 0 and shellDark or shell, Mat.Sandstone)
		T.ball(tail[i + 1].X, tail[i + 1].Y, tail[i + 1].Z, r * 2.3, r * 2.3, r * 2.3, shell, Mat.Sandstone)
	end
	T.ball(0, 1.04, -0.06, 0.16, 0.18, 0.2, venom, Neon, { T = 0.1 })
	T.horn(V(0, 1.0, -0.12), V(0, 0.82, -0.26), 0.03, rgb(40, 30, 20), Plastic, V(0, 0, -0.06))
	for _, s in ipairs({ -1, 1 }) do
		-- 집게 팔: 어깨 -> 팔꿈치 -> 집게 몸 + 위 / 아래 집게날
		T.arm(V(s * 0.3, 0.0, -0.44), V(s * 0.62, 0.02, -0.66), V(s * 0.66, 0.0, -0.96), 0.08, 0.07, shell, Mat.Sandstone)
		T.ball(s * 0.66, 0.0, -1.04, 0.26, 0.2, 0.3, shellDark, Mat.Sandstone)
		T.horn(V(s * 0.6, 0.04, -1.14), V(s * 0.52, 0.06, -1.42), 0.05, shell, Mat.Sandstone, V(s * 0.06, 0, 0))
		T.horn(V(s * 0.74, -0.02, -1.14), V(s * 0.66, -0.02, -1.4), 0.04, shellDark, Mat.Sandstone, V(s * -0.06, 0, 0))
		-- 다리 3쌍 (위로 꺾였다 땅을 짚는다)
		for k = 0, 2 do
			local z = -0.16 + k * 0.24
			T.arm(V(s * 0.36, -0.02, z), V(s * 0.66, 0.12, z + 0.02), V(s * 0.8, -0.5, z + 0.06), 0.045, 0.025, shellDark, Mat.Sandstone)
		end
	end
	-- 밝은 배
	T.ball(0, -0.2, 0, 0.7, 0.16, 0.86, belly, Mat.Sandstone)
end

------------------------------------------------------------
-- 필드 5구역 (설원): 수정 군주 — 반투명 얼음 몸, 쇠 가면, 높은 수정 왕관, 어깨 첨탑, 얼음 칼날 팔, 주위를 도는 파편
------------------------------------------------------------
M.Body.Zone5 = { Material = Mat.Ice, Color = rgb(165, 210, 240), Transparency = 0.15 }
M.Fx.Zone5 = { rgb(240, 250, 255), 14, 0.06, 3, 4, V(0, -2, 0) }
Looks.Zone5 = function(T)
	local crystal, deep, steel, core = rgb(196, 234, 255), rgb(120, 180, 225), rgb(130, 150, 176), rgb(170, 245, 255)
	-- 몸 속 빛나는 핵
	T.ball(0, 0.04, 0, 0.36, 0.36, 0.36, core, Neon, { T = 0.2 })
	-- 쇠 가면 + 빛나는 눈 틈
	T.ball(0, 0.2, -0.36, 0.44, 0.36, 0.2, steel, Metal)
	T.block(0, 0.22, -0.46, 0.32, 0.05, 0.04, core, Neon)
	T.plate(V(0, 0.08, -0.45), 0.06, 0.04, 0.16, steel:Lerp(BLACK, 0.3), Metal, 90, 0, 0)
	-- 수정 왕관 (가운데가 가장 높다)
	for i = -3, 3 do
		local h = 0.5 - math.abs(i) * 0.1
		T.plate(V(i * 0.08, 0.5 + h / 2, -0.14 + math.abs(i) * 0.03), 0.06, h, 0.06, i == 0 and core or crystal, Glass, 0, 45, i * -6, { T = 0.15 })
	end
	for _, s in ipairs({ -1, 1 }) do
		-- 어깨 수정 첨탑 무리
		for k = 0, 2 do
			local h = 0.42 - k * 0.1
			T.plate(V(s * (0.42 + k * 0.08), 0.36 + h / 2, -0.02 + k * 0.08), 0.08, h, 0.08, k == 0 and crystal or deep, Glass, k * 10, 45, s * (-18 - k * 10), { T = 0.15 })
		end
		-- 팔 + 얼음 칼날 손
		T.arm(V(s * 0.46, 0.12, 0), V(s * 0.7, -0.08, -0.08), V(s * 0.72, -0.26, -0.28), 0.08, 0.06, deep, Glass, { T = 0.15 })
		T.plate(V(s * 0.72, -0.42, -0.42), 0.04, 0.12, 0.46, crystal, Glass, 30, 0, 0, { T = 0.1 })
		-- 다리 + 얼음 발
		T.limb(V(s * 0.2, -0.3, 0), V(s * 0.22, -0.48, 0), 0.11, 0.09, deep, Glass, { T = 0.15 }, 1)
		T.ball(s * 0.22, -0.52, -0.06, 0.24, 0.1, 0.32, crystal, Glass, { T = 0.1 })
	end
	-- 주위를 도는 얼음 파편 고리
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		T.plate(V(math.cos(a) * 0.86, 0.1 + (i % 2) * 0.24, math.sin(a) * 0.86), 0.06, 0.2, 0.06, crystal, Glass, 30, i * 40, 20, { T = 0.2 })
	end
	-- 서리 망토
	T.plate(V(0, -0.02, 0.36), 0.66, 0.74, 0.04, rgb(140, 190, 235), Fabric, -8, 0, 0)
end

------------------------------------------------------------
-- 필드 6구역 (화산): 용암 마왕 — 갈라진 흑요석 피부의 용암 균열, 휘어진 큰 뿔, 박쥐 날개, 발톱, 불꽃 꼬리
------------------------------------------------------------
M.Body.Zone6 = { Material = Mat.Basalt, Color = rgb(56, 38, 34) }
M.Fx.Zone6 = { rgb(255, 130, 50), 16, 0.07, 6, 2.5, V(0, 5, 0) }
Looks.Zone6 = function(T)
	local hide, hideLight, horn, lava, ember = rgb(52, 36, 34), rgb(86, 58, 50), rgb(210, 196, 170), rgb(255, 120, 40), rgb(255, 190, 90)
	-- 용암 균열 (몸에 감긴 빛나는 줄)
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2
		T.plate(V(math.cos(a) * 0.47, math.sin(i * 2.3) * 0.18, math.sin(a) * 0.47), 0.04, 0.3, 0.03, lava, Neon, 0, -math.deg(a) + 90, i * 23)
	end
	-- 머리: 앞으로 내민 턱 + 이글거리는 눈 + 이빨
	T.ball(0, 0.28, -0.38, 0.42, 0.34, 0.34, hideLight, Mat.Basalt)
	for _, s in ipairs({ -1, 1 }) do
		T.glow(s * 0.11, 0.34, -0.53, 0.05, ember)
		T.horn(V(s * 0.06, 0.12, -0.52), V(s * 0.06, 0.04, -0.56), 0.02, horn, Plastic)
		-- 큰 뿔: 옆으로 나갔다 위로 휜다
		T.horn(V(s * 0.16, 0.42, -0.36), V(s * 0.5, 0.86, -0.24), 0.06, horn, Plastic, V(s * 0.16, -0.1, 0))
		-- 어깨 갑판 + 팔 + 발톱 손
		T.ball(s * 0.48, 0.24, 0, 0.32, 0.26, 0.32, hideLight, Mat.Basalt)
		T.arm(V(s * 0.5, 0.12, -0.02), V(s * 0.72, -0.1, -0.16), V(s * 0.7, -0.3, -0.38), 0.09, 0.07, hide, Mat.Basalt)
		for k = -1, 1 do
			T.horn(V(s * 0.7, -0.32, -0.42), V(s * (0.7 + k * 0.06), -0.42, -0.56), 0.02, horn, Plastic, V(0, -0.02, 0))
		end
		-- 박쥐 날개: 뼈대 3개 + 빛나는 날개막 2장
		local shoulder = V(s * 0.3, 0.36, 0.3)
		local tips = { V(s * 1.1, 0.96, 0.46), V(s * 1.2, 0.5, 0.56), V(s * 0.96, 0.08, 0.6) }
		for _, tip in ipairs(tips) do
			T.seg(shoulder, tip, 0.025, horn, Plastic)
		end
		for k = 1, 2 do
			local a, b = tips[k], tips[k + 1]
			local mid = (shoulder + a + b) * (1 / 3)
			local span = (a - b).Magnitude
			T.plate(mid, 0.03, span * 0.8, (mid - shoulder).Magnitude * 1.25, lava:Lerp(hide, 0.45), Neon, 0, s * -55, s * (k == 1 and 30 or 70), { T = 0.35 })
		end
		-- 다리 (짐승처럼 꺾인 뒷다리) + 발톱
		T.arm(V(s * 0.22, -0.26, 0.04), V(s * 0.3, -0.34, -0.12), V(s * 0.28, -0.5, 0.02), 0.11, 0.07, hide, Mat.Basalt)
		T.ball(s * 0.28, -0.53, -0.04, 0.2, 0.08, 0.26, hideLight, Mat.Basalt)
	end
	-- 꼬리 + 끝의 불꽃
	local tail = { V(0, -0.1, 0.44), V(0, -0.26, 0.74), V(0, -0.2, 1.0), V(0, 0.02, 1.16) }
	for i = 1, #tail - 1 do
		T.seg(tail[i], tail[i + 1], 0.07 - i * 0.015, hide, Mat.Basalt)
	end
	T.ball(0, 0.06, 1.2, 0.18, 0.24, 0.18, lava, Neon, { T = 0.1 })
end

------------------------------------------------------------
-- 필드 7구역 (암흑 지대): 사신 — 두건 쓴 망토, 텅 빈 얼굴의 보라 눈, 길쭉한 해골 손, 큰 낫, 떠도는 해골 등불
------------------------------------------------------------
M.Body.Zone7 = { Material = Fabric, Color = rgb(30, 24, 46) }
M.Fx.Zone7 = { rgb(120, 80, 190), 14, 0.14, 3, 3, V(0, 1.5, 0) }
Looks.Zone7 = function(T)
	local cloak, cloakLight, void, violet, bone = rgb(26, 20, 40), rgb(48, 38, 72), rgb(6, 4, 10), rgb(185, 125, 255), rgb(220, 212, 196)
	-- 두건 (몸 위로 크게) + 텅 빈 얼굴 + 눈
	T.ball(0, 0.38, -0.08, 0.66, 0.66, 0.66, cloakLight, Fabric)
	T.ball(0, 0.62, 0.06, 0.32, 0.4, 0.32, cloakLight, Fabric) -- 뾰족한 두건 끝
	T.ball(0, 0.34, -0.32, 0.4, 0.42, 0.2, void, Plastic)
	for _, s in ipairs({ -1, 1 }) do T.glow(s * 0.08, 0.38, -0.42, 0.04, violet) end
	-- 망토 자락 (너덜너덜하게 아래로 길게)
	for i = 0, 8 do
		local a = math.pi * 0.2 + i / 8 * math.pi * 1.6
		local len = 0.42 + (i % 3) * 0.1
		T.plate(V(math.sin(a) * 0.42, -0.36 - len * 0.3, math.cos(a) * 0.42), 0.16, len, 0.03, cloak, Fabric, 0, math.deg(a), (i % 2 == 0) and 6 or -6)
	end
	for _, s in ipairs({ -1, 1 }) do
		-- 소매 + 해골 손 (긴 손가락 3)
		T.limb(V(s * 0.36, 0.16, -0.06), V(s * 0.6, -0.04, -0.3), 0.11, 0.09, cloak, Fabric, nil, 1)
		T.ball(s * 0.62, -0.08, -0.36, 0.1, 0.08, 0.1, bone, Plastic)
		for k = -1, 1 do
			T.horn(V(s * 0.62, -0.1, -0.4), V(s * (0.62 + k * 0.05), -0.22, -0.5), 0.012, bone, Plastic, V(0, 0, -0.03))
		end
	end
	-- 큰 낫 (오른손): 긴 자루 + 휜 날 + 날 끝 빛
	local hand = V(0.62, -0.08, -0.36)
	T.seg(hand + V(0, -0.6, 0.16), hand + V(0, 1.1, -0.36), 0.025, rgb(70, 56, 46), Wood)
	local top = hand + V(0, 1.1, -0.36)
	T.horn(top, top + V(-0.62, -0.18, -0.12), 0.05, rgb(200, 205, 215), Metal, V(0, 0.16, -0.06))
	T.horn(top + V(-0.02, -0.04, 0), top + V(-0.56, -0.24, -0.1), 0.02, violet, Neon, V(0, 0.12, -0.04))
	-- 떠도는 해골 등불 3개
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2 + 0.6
		local p = V(math.cos(a) * 0.95, 0.3 + (i % 2) * 0.3, math.sin(a) * 0.95)
		T.ball(p.X, p.Y, p.Z, 0.16, 0.15, 0.16, bone, Plastic)
		for _, s in ipairs({ -1, 1 }) do T.glow(p.X + s * 0.035, p.Y + 0.01, p.Z - 0.07, 0.02, violet) end
		T.ball(p.X, p.Y + 0.12, p.Z, 0.1, 0.1, 0.1, violet, Neon, { T = 0.3 })
	end
end

------------------------------------------------------------
-- 필드 8구역 (심연): 심연의 눈 — 몸 전체가 하나의 큰 눈 (눈꺼풀 / 세로 동공 / 이빨 고리), 끝이 빛나는 촉수, 줄기 위의 작은 눈들
------------------------------------------------------------
M.Body.Zone8 = { Material = Slate, Color = rgb(42, 30, 60) }
M.Fx.Zone8 = { rgb(255, 110, 190), 10, 0.08, 3, 3.5, V(0, 2, 0) }
Looks.Zone8 = function(T)
	local flesh, fleshDark, pink, sclera = rgb(74, 46, 96), rgb(44, 28, 62), rgb(255, 110, 190), rgb(245, 238, 250)
	-- 큰 눈 (흰자 + 분홍 홍채 + 세로 동공 + 반짝임)
	T.ball(0, 0.08, -0.32, 0.6, 0.6, 0.36, sclera, Plastic)
	T.ball(0, 0.08, -0.46, 0.36, 0.36, 0.14, pink, Neon)
	T.ball(0, 0.08, -0.52, 0.08, 0.28, 0.06, BLACK, Plastic)
	T.ball(-0.1, 0.18, -0.54, 0.06, 0.06, 0.04, WHITE, Neon)
	-- 위 / 아래 눈꺼풀
	T.plate(V(0, 0.38, -0.34), 0.64, 0.1, 0.34, fleshDark, Slate, -24, 0, 0)
	T.plate(V(0, -0.2, -0.36), 0.6, 0.08, 0.3, fleshDark, Slate, 20, 0, 0)
	-- 눈 아래 이빨 고리
	for i = -3, 3 do
		T.horn(V(i * 0.07, -0.26, -0.4), V(i * 0.08, -0.36, -0.46), 0.02, rgb(235, 225, 215), Plastic)
	end
	-- 촉수 6개: 아래로 굽이치며 퍼진다 (끝이 빛난다)
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		local dir = V(math.cos(a), 0, math.sin(a))
		local p0 = dir * 0.36 + V(0, -0.26, 0)
		local p1 = dir * 0.62 + V(0, -0.44, 0) + V(-dir.Z, 0, dir.X) * 0.1
		local p2 = dir * 0.92 + V(0, -0.5, 0) - V(-dir.Z, 0, dir.X) * 0.1
		local p3 = dir * 1.14 + V(0, -0.38, 0)
		T.seg(p0, p1, 0.08, flesh, Slate)
		T.ball(p1.X, p1.Y, p1.Z, 0.15, 0.15, 0.15, flesh, Slate)
		T.seg(p1, p2, 0.06, fleshDark, Slate)
		T.ball(p2.X, p2.Y, p2.Z, 0.11, 0.11, 0.11, fleshDark, Slate)
		T.seg(p2, p3, 0.035, flesh, Slate)
		T.ball(p3.X, p3.Y, p3.Z, 0.09, 0.09, 0.09, pink, Neon)
	end
	-- 줄기 위의 작은 눈 4개 (위로 솟아 사방을 본다)
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2 + 0.4
		local base = V(math.cos(a) * 0.28, 0.36, math.sin(a) * 0.28)
		local tip = V(math.cos(a) * 0.62, 0.86 + (i % 2) * 0.14, math.sin(a) * 0.62)
		T.horn(base, tip, 0.035, flesh, Slate, V(0, 0.08, 0))
		T.ball(tip.X, tip.Y, tip.Z, 0.17, 0.17, 0.17, sclera, Plastic)
		local look = (V(0, tip.Y, 0) - tip)
		look = V(look.X, 0, look.Z).Unit * -1
		T.ball(tip.X + look.X * 0.07, tip.Y, tip.Z + look.Z * 0.07, 0.08, 0.08, 0.06, pink, Neon)
	end
end

------------------------------------------------------------
-- 던전 (고블린 동굴): 고블린 왕 — 불룩한 배, 큰 귀와 코, 보석 왕관, 엄니, 굵은 팔, 가시 곤봉, 망토, 금화 자루
------------------------------------------------------------
M.Body.Cave = { Material = Plastic, Color = rgb(98, 150, 66) }
Looks.Cave = function(T)
	local skin, skinDark, belly, gold, wood, cape = rgb(98, 150, 66), rgb(66, 108, 46), rgb(150, 190, 110), rgb(240, 196, 76), rgb(110, 78, 50), rgb(150, 40, 46)
	-- 밝은 배 + 배꼽
	T.ball(0, -0.06, -0.24, 0.7, 0.66, 0.3, belly, Plastic)
	-- 머리 (턱 + 큰 코 + 눈 + 엄니)
	T.ball(0, 0.62, -0.08, 0.5, 0.44, 0.46, skin, Plastic)
	T.ball(0, 0.5, -0.24, 0.42, 0.22, 0.3, skinDark, Plastic)
	T.ball(0, 0.62, -0.34, 0.16, 0.14, 0.2, skinDark, Plastic)
	for _, s in ipairs({ -1, 1 }) do
		T.eye(s * 0.11, 0.72, -0.28, 0.06, rgb(255, 235, 120), rgb(160, 30, 20), true)
		T.plate(V(s * 0.12, 0.8, -0.28), 0.14, 0.03, 0.05, skinDark, Plastic, 0, 0, s * -20) -- 화난 눈썹
		T.horn(V(s * 0.1, 0.48, -0.36), V(s * 0.14, 0.62, -0.42), 0.03, rgb(240, 232, 210), Plastic)
		-- 뾰족하고 큰 귀
		T.horn(V(s * 0.22, 0.66, -0.06), V(s * 0.6, 0.82, 0.04), 0.07, skin, Plastic, V(0, 0.04, 0))
	end
	-- 보석 왕관 (테 + 뾰족 5개 + 보석)
	T.seg(V(0, 0.84, -0.08), V(0, 0.92, -0.08), 0.21, gold, Metal)
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2 - math.pi / 2
		T.horn(V(math.cos(a) * 0.19, 0.92, -0.08 + math.sin(a) * 0.19), V(math.cos(a) * 0.2, 1.06, -0.08 + math.sin(a) * 0.2), 0.03, gold, Metal)
	end
	T.ball(0, 0.88, -0.29, 0.07, 0.07, 0.04, rgb(230, 50, 70), Neon)
	for _, s in ipairs({ -1, 1 }) do
		-- 굵은 팔 + 큰 주먹 + 금팔찌
		T.arm(V(s * 0.46, 0.3, 0), V(s * 0.66, 0.04, -0.06), V(s * 0.68, -0.18, -0.24), 0.13, 0.11, skin, Plastic)
		T.seg(V(s * 0.67, -0.06, -0.14), V(s * 0.68, -0.12, -0.18), 0.12, gold, Metal)
		T.ball(s * 0.7, -0.26, -0.3, 0.26, 0.24, 0.26, skinDark, Plastic)
		-- 짧은 다리 + 큰 발
		T.limb(V(s * 0.2, -0.32, 0.02), V(s * 0.22, -0.46, 0), 0.13, 0.12, skin, Plastic, nil, 1)
		T.ball(s * 0.22, -0.5, -0.06, 0.28, 0.1, 0.36, skinDark, Plastic)
	end
	-- 허리띠 + 금 버클
	T.seg(V(0, -0.16, 0), V(0, -0.08, 0), 0.47, rgb(86, 58, 38), Fabric)
	T.ball(0, -0.12, -0.46, 0.14, 0.12, 0.05, gold, Metal)
	-- 붉은 망토
	T.plate(V(0, 0.04, 0.36), 0.8, 0.86, 0.04, cape, Fabric, -10, 0, 0)
	T.plate(V(0, 0.46, 0.3), 0.7, 0.1, 0.16, rgb(235, 225, 200), Fabric, -10, 0, 0) -- 털 깃
	-- 가시 곤봉 (오른손에서 위로)
	local hand = V(0.7, -0.26, -0.3)
	T.limb(hand, hand + V(0.12, 0.84, -0.06), 0.05, 0.08, wood, Wood, nil, 1)
	local head = hand + V(0.14, 0.98, -0.06)
	T.ball(head.X, head.Y, head.Z, 0.34, 0.38, 0.34, wood, Wood)
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		local dir = V(math.cos(a), math.sin(i * 1.7) * 0.4, math.sin(a))
		T.horn(head + dir.Unit * 0.14, head + dir.Unit * 0.27, 0.025, rgb(176, 176, 182), Metal)
	end
	-- 등의 금화 자루
	T.ball(-0.2, 0.18, 0.5, 0.38, 0.42, 0.32, rgb(150, 118, 70), Fabric)
	T.ball(-0.16, 0.42, 0.5, 0.12, 0.06, 0.12, gold, Metal)
end

------------------------------------------------------------
-- 던전 (얼음 성채): 서리 군주 — 반투명 얼음 갑옷 속 빛나는 핵, 뿔 달린 투구, 수정 어깨갑, 빛나는 얼음 대검, 망토
------------------------------------------------------------
M.Body.Ice = { Material = Neon, Color = rgb(110, 210, 240) }
Looks.Ice = function(T)
	local ice, steel, steelDark, glowc, cape = rgb(180, 220, 245), rgb(120, 146, 180), rgb(74, 92, 126), rgb(170, 250, 255), rgb(90, 140, 205)
	-- 흉갑 (투명 얼음) + 금속 테
	T.ball(0, 0.08, -0.06, 0.82, 0.84, 0.7, ice, Glass, { T = 0.5 })
	T.seg(V(0, -0.22, 0), V(0, -0.14, 0), 0.44, steel, Metal)
	T.plate(V(0, 0.14, -0.4), 0.06, 0.5, 0.06, steel, Metal, 0, 0, 0)
	-- 투구: 둥근 투구 + 눈 틈 + 뿔 + 가운데 볏
	T.ball(0, 0.62, -0.02, 0.4, 0.4, 0.42, steel, Metal)
	T.block(0, 0.62, -0.22, 0.28, 0.05, 0.04, glowc, Neon)
	T.plate(V(0, 0.84, -0.02), 0.04, 0.16, 0.42, ice, Glass, 0, 0, 0, { T = 0.1 })
	for _, s in ipairs({ -1, 1 }) do
		T.horn(V(s * 0.18, 0.72, -0.02), V(s * 0.46, 1.02, 0.1), 0.04, ice, Glass, V(s * 0.08, -0.06, 0), { T = 0.1 })
		-- 수정 어깨갑 (둥근 판 + 수정 3개)
		T.ball(s * 0.48, 0.38, 0, 0.36, 0.26, 0.36, steel, Metal)
		for k = 0, 2 do
			T.plate(V(s * (0.46 + k * 0.07), 0.56 + (2 - k) * 0.04, -0.06 + k * 0.08), 0.06, 0.3 - k * 0.06, 0.06, ice, Glass, 0, 45, s * (-12 - k * 16), { T = 0.15 })
		end
		-- 팔 (철갑) + 건틀릿
		T.arm(V(s * 0.5, 0.24, 0), V(s * 0.62, -0.02, -0.06), V(s * 0.6, -0.22, -0.28), 0.1, 0.09, steelDark, Metal)
		T.ball(s * 0.6, -0.28, -0.32, 0.2, 0.2, 0.2, steel, Metal)
		-- 다리 + 철장화
		T.limb(V(s * 0.2, -0.28, 0.02), V(s * 0.22, -0.46, 0), 0.12, 0.11, steelDark, Metal, nil, 1)
		T.ball(s * 0.22, -0.5, -0.06, 0.26, 0.1, 0.34, steel, Metal)
		-- 망토 반쪽
		T.plate(V(s * 0.2, 0.06, 0.4), 0.42, 0.92, 0.04, cape, Fabric, -8, 0, s * 4)
	end
	-- 얼음 대검 (오른손, 앞으로 세워 든다): 손잡이 + 가드 + 빛나는 날
	local hand = V(0.6, -0.28, -0.32)
	T.seg(hand + V(0, -0.12, 0), hand + V(0, 0.08, 0), 0.03, rgb(60, 50, 40), Wood)
	T.plate(hand + V(0, 0.1, 0), 0.36, 0.05, 0.08, steel, Metal, 0, 0, 0)
	T.plate(hand + V(0, 0.82, 0), 0.12, 1.36, 0.04, glowc, Neon, 0, 0, 0, { T = 0.1 })
	T.plate(hand + V(0, 0.82, 0), 0.2, 1.4, 0.02, ice, Glass, 0, 0, 0, { T = 0.4 })
	-- 주위를 도는 고드름
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		T.plate(V(math.cos(a) * 0.96, 0.2 + (i % 2) * 0.3, math.sin(a) * 0.96), 0.06, 0.26, 0.06, ice, Glass, 0, 45, 0, { T = 0.2 })
	end
end
M.Fx.Ice = { rgb(235, 248, 255), 12, 0.06, 3, 4, V(0, -2, 0) }

------------------------------------------------------------
-- 던전 (화염 신전): 불사조 — 긴 목과 날카로운 부리, 깃털 볏, 깃털이 한 장씩 갈라진 큰 날개, 공작 같은 꼬리깃, 금 발톱
------------------------------------------------------------
M.Body.Fire = { Material = Neon, Color = rgb(238, 108, 40) }
M.Fx.Fire = { rgb(255, 150, 50), 22, 0.09, 6, 2.6, V(0, 6, 0) }
Looks.Fire = function(T)
	local flame, flameHot, gold, deep = rgb(255, 140, 50), rgb(255, 210, 110), rgb(255, 205, 70), rgb(220, 70, 30)
	-- 가슴 깃털 (밝은 배)
	T.ball(0, 0.02, -0.26, 0.6, 0.66, 0.3, flameHot, Neon, { T = 0.1 })
	-- 목 (휘어 올라간다) + 머리 + 부리 + 눈
	T.limb(V(0, 0.28, -0.34), V(0, 0.56, -0.62), 0.12, 0.09, flame, Neon, nil, 2)
	T.ball(0, 0.64, -0.72, 0.26, 0.24, 0.3, flame, Neon)
	T.horn(V(0, 0.62, -0.86), V(0, 0.52, -1.06), 0.05, gold, Metal, V(0, 0.03, 0))
	for _, s in ipairs({ -1, 1 }) do
		T.eye(s * 0.08, 0.68, -0.84, 0.035, rgb(255, 250, 220), rgb(40, 16, 10), true)
	end
	-- 깃털 볏 (뒤로 흩날린다)
	for i = -2, 2 do
		T.horn(V(i * 0.03, 0.74, -0.7), V(i * 0.1, 0.98 - math.abs(i) * 0.06, -0.56 + math.abs(i) * 0.05), 0.025, i == 0 and gold or flameHot, Neon, V(0, 0.04, 0.04))
	end
	for _, s in ipairs({ -1, 1 }) do
		-- 날개: 어깨에서 갈라진 깃털 7장 (위로 펼친다, 바깥쪽일수록 길고 투명)
		local shoulder = V(s * 0.34, 0.28, 0.1)
		for k = 0, 6 do
			local t = k / 6
			local tip = V(s * (0.7 + t * 0.7), 0.95 - t * 0.85, 0.2 + t * 0.4)
			local mid = (shoulder + tip) * 0.5
			local len = (tip - shoulder).Magnitude
			local dir = (tip - shoulder).Unit
			local roll = math.deg(math.atan2(dir.Y, math.abs(dir.X))) * s
			T.plate(mid, len, 0.03, 0.16 - t * 0.04, k % 2 == 0 and flame or deep, Neon, 0, s * -18, roll, { T = 0.1 + t * 0.25 })
		end
		T.limb(shoulder, V(s * 0.72, 0.62, 0.22), 0.07, 0.05, flame, Neon, nil, 1)
		-- 다리 + 금 발톱
		T.limb(V(s * 0.14, -0.34, -0.02), V(s * 0.16, -0.5, -0.04), 0.05, 0.035, gold, Metal, nil, 1)
		for k = -1, 1 do
			T.horn(V(s * 0.16, -0.5, -0.04), V(s * (0.16 + k * 0.07), -0.55, -0.16), 0.02, gold, Metal, V(0, -0.02, 0))
		end
	end
	-- 꼬리깃: 부채꼴로 길게 9장 (끝에 둥근 깃 무늬)
	for i = -4, 4 do
		local a = math.rad(i * 13)
		local tip = V(math.sin(a) * 1.0, -0.12 - math.abs(i) * 0.03, 0.4 + math.cos(a) * 0.9)
		local base = V(0, -0.06, 0.38)
		T.seg(base, tip, 0.03, i % 2 == 0 and flame or deep, Neon, { T = 0.15 })
		T.ball(tip.X, tip.Y, tip.Z, 0.14, 0.06, 0.18, gold, Neon, { T = 0.1 })
	end
end

function M.Has(key)
	return Looks[key] ~= nil
end

-- d: Effects 가 넘겨 주는 부품 만들기 함수, S: 보스 크기
function M.Build(key, S, _, d)
	local look = Looks[key]
	if not look then return false end
	look(toolkit(d, S))
	return true
end

return M
