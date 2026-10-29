-- MonsterLooks (ServerScriptService > Modules 안의 ModuleScript, 이름: MonsterLooks)
-- 몬스터 겉모양 (둥글고 유기적인 새 버전). MonsterTypes.Build 가 먼저 여기서 찾고, 없거나 오류가 나면 예전 모양(Looks)을 쓴다.
-- 각진 상자 대신: 끝이 둥근 "팔다리 / 뿔 / 가시"(가는 원기둥 + 관절 구슬), 눈동자가 있는 눈, 밝은 배 / 어두운 등 같은 2색 음영.
-- 모든 좌표는 몬스터 크기 S 의 배수. 앞 = -Z, 위 = +Y.
-- d(모양, 가로, 높이, 길이, x, y, z, 색, 재질, { Tint, T, CF }) 는 MonsterTypes.Build 가 넘겨 준다 (CF 는 몸체 기준 CFrame, 있으면 x y z / 회전 대신 쓴다).

local BALL, BLOCK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local Glass, Neon, Plastic, Metal, Wood, Slate = Enum.Material.Glass, Enum.Material.Neon, Enum.Material.SmoothPlastic, Enum.Material.Metal, Enum.Material.Wood, Enum.Material.Slate
local BLACK, WHITE = Color3.new(0, 0, 0), Color3.new(1, 1, 1)

local M = {}
local Looks = {}

local function copy(opts)
	local out = {}
	if opts then
		for k, v in pairs(opts) do out[k] = v end
	end
	return out
end

local function V(x, y, z) return Vector3.new(x, y, z) end

-- 도구 상자: d 에 몬스터 크기 S 를 묶어서 쓴다
local function toolkit(d, S)
	local T = {}

	function T.ball(x, y, z, w, h, l, col, mat, opts)
		return d(BALL, S * w, S * h, S * l, S * x, S * y, S * z, col, mat, opts)
	end
	function T.block(x, y, z, w, h, l, col, mat, opts)
		return d(BLOCK, S * w, S * h, S * l, S * x, S * y, S * z, col, mat, opts)
	end

	-- a 에서 b 까지 가는 원기둥 하나 (r = 반지름)
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

	-- 끝이 둥근 팔다리 / 가시: a 에서 b 까지 반지름이 r1 -> r2 로 가늘어진다 (원기둥 segs 개 + 관절 구슬)
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
		if r2 > 0.035 then T.ball(b.X, b.Y, b.Z, r2 * 2, r2 * 2, r2 * 2, col, mat, opts) end
	end

	-- 부품을 아끼는 막대: 원기둥 하나 (반지름은 r1 / r2 의 중간) + 끝에 둥근 구슬 하나 (endBall = false 면 구슬 없음)
	function T.rod(a, b, r1, r2, col, mat, opts, endBall)
		T.seg(a, b, (r1 + r2) / 2, col, mat, opts)
		if endBall ~= false and r2 > 0.03 then T.ball(b.X, b.Y, b.Z, r2 * 2, r2 * 2, r2 * 2, col, mat, opts) end
	end

	-- 휜 뿔 / 엄니: 밑동 -> 끝, bend 만큼 가운데가 휜다 (원기둥 2 + 관절 구슬 1)
	function T.horn(a, b, r, col, mat, bend, opts)
		local mid = (a + b) * 0.5 + (bend or V(0, 0, 0))
		T.seg(a, mid, r * 0.85, col, mat, opts)
		T.ball(mid.X, mid.Y, mid.Z, r * 1.5, r * 1.5, r * 1.5, col, mat, opts)
		T.seg(mid, b, r * 0.4, col, mat, opts)
	end

	-- 눈: 흰자 + 눈동자 (눈동자는 앞(-Z)으로 살짝 튀어나온다). shine = true 면 반짝이는 점 하나 더
	function T.eye(x, y, z, r, white, pupil, shine)
		T.ball(x, y, z, r * 2, r * 2, r * 1.6, white, Plastic)
		T.ball(x * 0.97, y - r * 0.05, z - r * 0.55, r * 1.15, r * 1.3, r * 0.6, pupil or BLACK, Plastic)
		if shine then T.ball(x - r * 0.25 * (x >= 0 and 1 or -1), y + r * 0.35, z - r * 0.75, r * 0.38, r * 0.38, r * 0.3, WHITE, Neon) end
	end
	-- 빛나는 눈: 눈동자 없이 Neon 한 쌍 (어둠 속에서 눈빛이 보인다)
	function T.glow(x, y, z, r, col)
		T.ball(x, y, z, r * 2, r * 2, r * 1.5, col, Neon)
	end
	return T
end

------------------------------------------------------------
-- 슬라임: 말랑한 물방울 (유리 몸 + 속의 핵 + 하이라이트 + 녹아 흐르는 방울) 18부품
------------------------------------------------------------
Looks.Slime = function(S, c, T)
	local deep, light = c:Lerp(BLACK, 0.4), c:Lerp(WHITE, 0.45)
	T.ball(0, -0.1, 0, 1.0, 0.78, 1.0, c, Glass, { Tint = true, T = 0.12 })                      -- 젤리 몸
	T.ball(0, -0.34, 0, 1.3, 0.3, 1.3, deep, Glass, { Tint = true, T = 0.2 })                    -- 바닥에 퍼진 치마
	T.ball(0.1, 0.26, 0.04, 0.52, 0.42, 0.52, c, Glass, { Tint = true, T = 0.14 })               -- 머리 위 혹
	T.ball(0, -0.06, 0.1, 0.4, 0.34, 0.4, deep, Plastic, { T = 0.3 })                            -- 속 핵
	T.ball(-0.18, 0.18, -0.25, 0.2, 0.12, 0.1, light, Neon, { T = 0.4 })                         -- 겉 하이라이트
	for _, side in ipairs({ -1, 1 }) do
		T.eye(side * 0.17, 0.0, -0.4, 0.1, Color3.fromRGB(245, 250, 225), BLACK, true)
		T.ball(side * 0.5, -0.38, -0.12, 0.22, 0.22, 0.22, c, Glass, { Tint = true, T = 0.15 })  -- 옆으로 튄 방울
		T.ball(side * 0.3, -0.44, -0.4, 0.14, 0.14, 0.14, c, Glass, { Tint = true, T = 0.2 })    -- 앞에 떨어진 방울
	end
	T.ball(0, -0.16, -0.46, 0.2, 0.06, 0.08, deep, Plastic)                                       -- 입
	T.ball(-0.28, 0.02, 0.2, 0.12, 0.12, 0.12, light, Glass, { T = 0.5 })                         -- 속에 떠 있는 기포
	T.ball(0.2, -0.18, 0.28, 0.09, 0.09, 0.09, light, Glass, { T = 0.5 })
end

------------------------------------------------------------
-- 박쥐: 통통한 털뭉치 몸 + 큰 귀 + 뼈대가 있는 날개막 (26부품)
------------------------------------------------------------
Looks.Bat = function(S, c, T)
	local dark, belly, bone = c:Lerp(BLACK, 0.45), c:Lerp(WHITE, 0.3), c:Lerp(WHITE, 0.15)
	T.ball(0, 0, 0.05, 0.55, 0.62, 0.62, c, Plastic, { Tint = true })                            -- 몸통
	T.ball(0, -0.06, -0.08, 0.38, 0.4, 0.34, belly, Plastic)                                      -- 밝은 배
	T.ball(0, 0.22, -0.3, 0.5, 0.44, 0.46, c, Plastic, { Tint = true })                           -- 머리
	T.ball(0, 0.15, -0.5, 0.26, 0.2, 0.2, belly, Plastic)                                         -- 주둥이
	T.ball(0, 0.18, -0.6, 0.08, 0.06, 0.06, BLACK, Plastic)                                       -- 코
	for _, side in ipairs({ -1, 1 }) do
		T.glow(side * 0.1, 0.28, -0.5, 0.06, Color3.fromRGB(255, 90, 80))                          -- 붉은 눈
		T.rod(V(side * 0.12, 0.38, -0.3), V(side * 0.2, 0.78, -0.26), 0.08, 0.03, dark, Plastic, nil, false) -- 뾰족한 큰 귀
		local shoulder, elbow, wrist = V(side * 0.18, 0.12, 0.05), V(side * 0.62, 0.34, 0.08), V(side * 1.15, 0.2, -0.12)
		T.rod(shoulder, elbow, 0.05, 0.04, bone, Plastic, nil, true)                                -- 날개 뼈대
		T.rod(elbow, wrist, 0.04, 0.03, bone, Plastic, nil, true)
		T.rod(wrist, V(side * 1.35, -0.12, -0.3), 0.025, 0.015, bone, Plastic, nil, false)           -- 손가락 2개
		T.rod(wrist, V(side * 1.0, -0.14, 0.36), 0.025, 0.015, bone, Plastic, nil, false)
		T.block(side * 0.72, -0.01, 0.1, 0.62, 0.02, 0.5, dark, Plastic, { Tint = true, Rz = side * 8 })    -- 날개막 3장
		T.block(side * 1.06, -0.04, 0.0, 0.5, 0.02, 0.5, dark, Plastic, { Tint = true, Rz = side * 12 })
		T.block(side * 0.5, -0.04, 0.3, 0.44, 0.02, 0.4, dark, Plastic, { Tint = true, Rz = side * 6 })
		T.rod(V(side * 0.12, -0.2, 0.2), V(side * 0.14, -0.42, 0.18), 0.045, 0.03, dark, Plastic, nil, false) -- 발
	end
end

------------------------------------------------------------
-- 독거미: 윤기 나는 배 + 다리 4쌍(관절마다 꺾임) + 눈 여럿 + 독니 (36부품)
------------------------------------------------------------
Looks.Spider = function(S, c, T)
	local dark, shell, venom = c:Lerp(BLACK, 0.3), c:Lerp(WHITE, 0.12), Color3.fromRGB(170, 235, 90)
	T.ball(0, 0.1, 0.42, 0.78, 0.7, 0.9, c, Plastic, { Tint = true })                             -- 큰 배
	T.ball(0, 0.26, 0.34, 0.3, 0.12, 0.5, Color3.fromRGB(200, 60, 60), Plastic)                   -- 등의 붉은 무늬
	T.ball(-0.14, 0.34, 0.46, 0.2, 0.1, 0.24, shell, Glass, { T = 0.5 })                          -- 배 광택
	T.ball(0, 0.04, -0.2, 0.5, 0.42, 0.5, dark, Plastic, { Tint = true })                         -- 머리가슴
	T.ball(0, 0.0, -0.45, 0.26, 0.22, 0.16, dark, Plastic)                                        -- 얼굴
	for _, side in ipairs({ -1, 1 }) do
		T.glow(side * 0.08, 0.1, -0.52, 0.065, Color3.fromRGB(245, 70, 60))                        -- 큰 눈
		T.glow(side * 0.18, 0.12, -0.46, 0.04, Color3.fromRGB(245, 70, 60))                        -- 작은 눈
		T.rod(V(side * 0.07, -0.06, -0.52), V(side * 0.08, -0.34, -0.6), 0.045, 0.02, Color3.fromRGB(235, 228, 205), Plastic, nil, false) -- 독니
		T.ball(side * 0.08, -0.37, -0.6, 0.07, 0.07, 0.07, venom, Neon)                           -- 독 방울
		for i = 0, 3 do -- 다리: 몸 -> 위로 솟는 무릎 -> 땅으로
			local zz = -0.3 + i * 0.22
			local spread = (i - 1.5) * 0.12
			local hip = V(side * 0.18, 0.06, zz)
			local knee = V(side * 0.7, 0.55, zz + spread)
			local foot = V(side * 1.0, -0.42, zz + spread * 2.4)
			T.rod(hip, knee, 0.05, 0.045, dark, Plastic, nil, true)
			T.rod(knee, foot, 0.04, 0.012, dark, Plastic, nil, false)
		end
	end
end

------------------------------------------------------------
-- 돌진 멧돼지: 낮고 단단한 몸 + 어두운 갈기 + 둥글게 휜 엄니 + 짧은 다리 + 꼬리 (30부품)
------------------------------------------------------------
Looks.Charger = function(S, c, T)
	local dark, belly, tusk = c:Lerp(BLACK, 0.5), c:Lerp(WHITE, 0.2), Color3.fromRGB(245, 238, 215)
	T.ball(0, 0.04, 0.2, 0.82, 0.7, 1.35, c, Plastic, { Tint = true })                            -- 몸
	T.ball(0, -0.08, 0.2, 0.62, 0.4, 1.1, belly, Plastic)                                         -- 밝은 배
	T.ball(0, 0.12, -0.5, 0.7, 0.62, 0.58, dark, Plastic, { Tint = true })                        -- 큰 머리
	T.ball(0, -0.02, -0.82, 0.4, 0.3, 0.3, belly, Plastic)                                        -- 주둥이
	T.ball(0, 0.0, -0.99, 0.2, 0.15, 0.1, Color3.fromRGB(70, 40, 40), Plastic)                    -- 코
	for i = 0, 3 do -- 등 갈기: 갈수록 낮아지는 가시
		T.rod(V(0, 0.38, -0.2 + i * 0.3), V(0, 0.38 + 0.26 - i * 0.04, -0.1 + i * 0.3), 0.07, 0.03, dark, Plastic, nil, false)
	end
	for _, side in ipairs({ -1, 1 }) do
		T.glow(side * 0.2, 0.22, -0.76, 0.06, Color3.fromRGB(245, 85, 55))                         -- 성난 눈
		T.horn(V(side * 0.18, -0.02, -0.86), V(side * 0.3, 0.38, -1.05), 0.065, tusk, Plastic, V(side * 0.08, 0.04, -0.08)) -- 위로 휜 엄니
		T.rod(V(side * 0.3, 0.34, -0.42), V(side * 0.4, 0.62, -0.4), 0.09, 0.03, dark, Plastic, nil, false) -- 귀
		T.rod(V(side * 0.3, -0.1, -0.2), V(side * 0.34, -0.5, -0.2), 0.11, 0.1, dark, Plastic, nil, true)   -- 앞다리 (끝 구슬 = 발굽)
		T.rod(V(side * 0.3, -0.1, 0.62), V(side * 0.34, -0.5, 0.66), 0.12, 0.1, dark, Plastic, nil, true)   -- 뒷다리
	end
	T.rod(V(0, 0.15, 0.85), V(0.1, 0.3, 1.2), 0.04, 0.025, dark, Plastic, nil, true)                  -- 꼬리
end

------------------------------------------------------------
-- 저격 임프: 둥글고 작은 악마 + 휜 뿔 + 박쥐 날개 + 화살촉 꼬리 + 삼지창 (34부품)
------------------------------------------------------------
Looks.Imp = function(S, c, T)
	local dark, horn, belly, gold = c:Lerp(BLACK, 0.5), Color3.fromRGB(50, 28, 38), c:Lerp(WHITE, 0.25), Color3.fromRGB(235, 200, 90)
	T.ball(0, -0.12, 0.02, 0.58, 0.72, 0.52, c, Plastic, { Tint = true })                         -- 몸
	T.ball(0, -0.08, -0.1, 0.38, 0.5, 0.3, belly, Plastic)                                        -- 배
	T.ball(0, 0.3, -0.04, 0.58, 0.5, 0.52, c, Plastic, { Tint = true })                           -- 머리
	T.ball(0, 0.2, -0.28, 0.22, 0.16, 0.14, belly, Plastic)                                       -- 주둥이
	T.block(0, 0.1, -0.34, 0.14, 0.03, 0.03, BLACK, Plastic)                                      -- 입
	for _, side in ipairs({ -1, 1 }) do
		T.eye(side * 0.14, 0.36, -0.28, 0.085, Color3.fromRGB(250, 235, 140), BLACK)
		T.horn(V(side * 0.18, 0.52, -0.02), V(side * 0.34, 0.98, 0.06), 0.065, horn, Plastic, V(side * 0.14, 0.0, 0.0)) -- 휜 뿔
		T.rod(V(side * 0.24, 0.36, 0.0), V(side * 0.44, 0.42, 0.06), 0.06, 0.025, c, Plastic, nil, false) -- 뾰족 귀
		-- 박쥐 날개: 뼈대 1 + 손가락 2 + 막 1
		local a, b = V(side * 0.2, 0.0, 0.14), V(side * 0.78, 0.46, 0.22)
		T.rod(a, b, 0.045, 0.035, dark, Plastic, nil, true)
		T.rod(b, V(side * 1.0, 0.1, 0.0), 0.025, 0.012, dark, Plastic, nil, false)
		T.rod(b, V(side * 0.7, -0.2, 0.42), 0.025, 0.012, dark, Plastic, nil, false)
		T.block(side * 0.62, 0.12, 0.26, 0.5, 0.025, 0.4, dark, Plastic, { T = 0.05, Rz = side * 24 })
		T.rod(V(side * 0.14, -0.42, 0.0), V(side * 0.18, -0.66, -0.06), 0.075, 0.07, dark, Plastic, nil, true) -- 다리 + 발
	end
	T.rod(V(0, -0.3, 0.26), V(0.05, -0.34, 0.62), 0.04, 0.025, dark, Plastic, nil, false)                  -- 꼬리
	T.ball(0.06, -0.3, 0.74, 0.22, 0.22, 0.05, horn, Plastic, { Rz = 45 })                                  -- 화살촉
	T.rod(V(0.46, -0.58, -0.3), V(0.46, 0.56, -0.3), 0.025, 0.025, Color3.fromRGB(125, 92, 62), Wood, nil, false) -- 삼지창 자루
	T.rod(V(0.46, 0.5, -0.3), V(0.46, 0.84, -0.3), 0.022, 0.012, gold, Metal, nil, false)                  -- 삼지창 날
	T.rod(V(0.46, 0.5, -0.3), V(0.58, 0.76, -0.3), 0.018, 0.01, gold, Metal, nil, false)
	T.rod(V(0.46, 0.5, -0.3), V(0.34, 0.76, -0.3), 0.018, 0.01, gold, Metal, nil, false)
end

------------------------------------------------------------
-- 바위 골렘: 웅크린 바위 거인 (둥글게 깎인 바위 덩어리 + 이끼 + 가슴의 불빛 + 땅에 닿는 주먹) (28부품)
------------------------------------------------------------
Looks.Golem = function(S, c, T)
	local dark, light, moss, ember = c:Lerp(BLACK, 0.35), c:Lerp(WHITE, 0.2), Color3.fromRGB(88, 128, 78), Color3.fromRGB(240, 145, 60)
	T.ball(0, 0.02, 0.04, 0.95, 0.78, 0.7, c, Slate, { Tint = true })                              -- 몸통
	T.ball(0, 0.28, 0.14, 0.7, 0.4, 0.5, light, Slate, { Tint = true })                            -- 구부정한 등
	T.ball(0, 0.4, -0.18, 0.4, 0.34, 0.36, dark, Slate, { Tint = true })                           -- 머리
	T.block(0, 0.3, -0.34, 0.26, 0.05, 0.06, ember, Neon)                                          -- 입 (불빛)
	T.block(0, 0.06, -0.33, 0.16, 0.34, 0.05, ember, Neon, { Rz = 14 })                            -- 가슴 균열
	T.block(0.06, -0.06, -0.34, 0.1, 0.18, 0.04, ember, Neon, { Rz = -32 })
	T.ball(0, -0.3, 0.04, 0.8, 0.3, 0.6, dark, Slate)                                              -- 허리
	T.ball(-0.28, 0.62, 0.0, 0.3, 0.08, 0.28, moss, Plastic)                                       -- 어깨 이끼
	T.ball(0.2, 0.5, 0.2, 0.22, 0.06, 0.2, moss, Plastic)
	for _, side in ipairs({ -1, 1 }) do
		T.glow(side * 0.1, 0.44, -0.34, 0.06, ember)
		T.ball(side * 0.56, 0.34, 0.0, 0.46, 0.4, 0.44, dark, Slate)                                -- 어깨 바위
		T.rod(V(side * 0.6, 0.28, 0.0), V(side * 0.7, -0.2, -0.06), 0.16, 0.14, c, Slate, { Tint = true }, true) -- 굵은 팔
		T.ball(side * 0.72, -0.44, -0.08, 0.46, 0.4, 0.44, dark, Slate)                             -- 거대한 주먹
		T.ball(side * 0.76, -0.56, -0.2, 0.14, 0.12, 0.12, light, Slate)                            -- 주먹 마디
		T.rod(V(side * 0.26, -0.3, 0.0), V(side * 0.3, -0.55, 0.0), 0.15, 0.13, c, Slate, { Tint = true }, true)  -- 다리
		T.ball(side * 0.3, -0.58, -0.06, 0.34, 0.14, 0.4, dark, Slate)                              -- 발
	end
end

------------------------------------------------------------
-- 가시 독충: 마디마디 이어진 몸 + 등 가시 + 집게턱 + 꼬리 독침 (26부품)
------------------------------------------------------------
Looks.Spitter = function(S, c, T)
	local dark, bone, venom = c:Lerp(BLACK, 0.4), Color3.fromRGB(230, 220, 198), Color3.fromRGB(175, 235, 90)
	T.ball(0, -0.04, 0.12, 0.78, 0.64, 0.8, c, Plastic, { Tint = true })                           -- 배 마디 1
	T.ball(0, -0.12, 0.66, 0.6, 0.5, 0.62, dark, Plastic, { Tint = true })                         -- 마디 2
	T.ball(0, -0.2, 1.06, 0.42, 0.36, 0.46, c, Plastic, { Tint = true })                           -- 마디 3
	T.ball(0, 0.0, -0.46, 0.6, 0.52, 0.56, dark, Plastic, { Tint = true })                         -- 머리
	for i = 0, 2 do -- 등 가시
		local z = -0.05 + i * 0.4
		T.rod(V(0, 0.22 - i * 0.07, z), V(0, 0.62 - i * 0.12, z + 0.1), 0.08 - i * 0.012, 0.03, bone, Plastic, nil, false)
	end
	for _, side in ipairs({ -1, 1 }) do
		T.eye(side * 0.15, 0.08, -0.7, 0.085, Color3.fromRGB(255, 235, 110), BLACK)
		T.rod(V(side * 0.12, -0.14, -0.72), V(side * 0.06, -0.12, -1.04), 0.05, 0.02, bone, Plastic, nil, false) -- 집게턱
		T.rod(V(side * 0.3, -0.12, 0.14), V(side * 0.7, -0.5, 0.2), 0.04, 0.015, dark, Plastic, nil, false)      -- 다리
		T.rod(V(side * 0.24, -0.16, 0.66), V(side * 0.62, -0.5, 0.7), 0.035, 0.015, dark, Plastic, nil, false)
	end
	T.horn(V(0, -0.2, 1.24), V(0, 0.18, 1.6), 0.07, venom, Neon, V(0, 0.12, 0.1))                    -- 꼬리 독침
end

------------------------------------------------------------
-- 도깨비불: 눈물방울 불꽃 + 흩날리는 꼬리불 + 웃는 얼굴 (입자는 MonsterTypes 의 예전 모양이 이미 붙인다: 여기서는 몸만) (19부품)
------------------------------------------------------------
Looks.Wisp = function(S, c, T)
	local core = c:Lerp(WHITE, 0.7)
	T.ball(0, 0.0, 0.0, 0.7, 0.8, 0.7, c, Neon, { Tint = true, T = 0.25 })
	T.ball(0, 0.04, 0.0, 0.42, 0.52, 0.42, core, Neon, { T = 0.3 })                                 -- 밝은 속불
	T.ball(0, 0.34, 0.0, 0.34, 0.5, 0.34, c, Neon, { Tint = true, T = 0.3 })                         -- 위로 솟는 불꽃
	T.ball(0.04, 0.62, 0.0, 0.2, 0.36, 0.2, c, Neon, { Tint = true, T = 0.4 })
	T.ball(0.08, 0.86, 0.0, 0.1, 0.22, 0.1, c, Neon, { Tint = true, T = 0.5 })
	for i = 1, 4 do -- 꼬리불
		local r = 0.5 - i * 0.1
		T.ball(math.sin(i * 1.7) * 0.14, -0.28 - i * 0.18, 0.1 * i, r, r * 1.1, r, c, Neon, { Tint = true, T = 0.3 + i * 0.12 })
	end
	for _, side in ipairs({ -1, 1 }) do
		T.eye(side * 0.15, 0.06, -0.31, 0.075, Color3.fromRGB(235, 255, 245), Color3.fromRGB(20, 60, 50))
		T.ball(side * 0.62, 0.12, 0.1, 0.18, 0.18, 0.18, c, Neon, { T = 0.35 })                      -- 도는 곁불
	end
	T.ball(0, -0.12, -0.32, 0.16, 0.05, 0.05, Color3.fromRGB(20, 60, 50), Plastic)                   -- 웃는 입
end

------------------------------------------------------------
-- 마법사 유령: 흐르는 로브 꼬리 + 휜 뾰족 모자 + 모자 밑의 빛나는 눈 + 떠 있는 손 + 구슬 지팡이 (30부품)
------------------------------------------------------------
Looks.Mage = function(S, c, T)
	local robe, gold, deep = c:Lerp(Color3.fromRGB(40, 50, 120), 0.6), Color3.fromRGB(240, 215, 120), c:Lerp(BLACK, 0.35)
	T.ball(0, 0.05, 0, 0.78, 0.9, 0.78, c, Plastic, { Tint = true, T = 0.3 })                       -- 몸
	T.ball(0.04, -0.4, 0.1, 0.6, 0.62, 0.6, c, Plastic, { Tint = true, T = 0.4 })                  -- 로브 자락 1
	T.ball(0.1, -0.7, 0.2, 0.4, 0.44, 0.4, c, Plastic, { Tint = true, T = 0.55 })                  -- 자락 2 (점점 흐려진다)
	T.ball(0.16, -0.95, 0.3, 0.22, 0.26, 0.22, c, Plastic, { Tint = true, T = 0.7 })               -- 자락 3
	T.ball(0, 0.1, -0.1, 0.5, 0.5, 0.45, deep, Plastic, { T = 0.1 })                               -- 후드 속 어둠
	T.ball(0, 0.42, 0, 1.0, 0.1, 1.0, robe, Plastic)                                                -- 챙 (넓은 원반)
	T.seg(V(0, 0.46, 0), V(0.02, 0.8, 0), 0.26, robe, Plastic)                                      -- 모자 몸통
	T.seg(V(0.02, 0.8, 0), V(0.1, 1.08, 0), 0.17, robe, Plastic)                                    -- 모자 중간 (휘어진다)
	T.seg(V(0.1, 1.08, 0), V(0.3, 1.26, 0), 0.09, robe, Plastic)                                    -- 모자 끝
	T.ball(0.34, 1.3, 0, 0.14, 0.14, 0.14, gold, Neon)                                              -- 끝의 별
	T.seg(V(-0.3, 0.52, -0.02), V(0.3, 0.52, -0.02), 0.02, gold, Metal)                              -- 모자 금띠
	for _, side in ipairs({ -1, 1 }) do
		T.glow(side * 0.14, 0.14, -0.34, 0.075, Color3.fromRGB(235, 250, 255))                       -- 후드 속 눈
		T.ball(side * 0.5, -0.04, -0.28, 0.18, 0.16, 0.18, c, Plastic, { Tint = true, T = 0.25 })     -- 떠 있는 손
		T.ball(side * 0.5, -0.04, -0.3, 0.1, 0.1, 0.1, Color3.fromRGB(180, 230, 255), Neon, { T = 0.3 }) -- 손의 마력
	end
	T.rod(V(0.58, -0.5, -0.3), V(0.58, 0.82, -0.3), 0.03, 0.03, Color3.fromRGB(105, 75, 55), Wood, nil, false) -- 지팡이
	T.ball(0.58, 0.9, -0.3, 0.26, 0.26, 0.26, Color3.fromRGB(130, 200, 235), Neon)                   -- 지팡이 구슬
	T.ball(0.58, 0.9, -0.3, 0.4, 0.4, 0.4, Color3.fromRGB(130, 200, 235), Glass, { T = 0.7 })        -- 구슬 빛무리
	T.rod(V(0.46, 0.68, -0.3), V(0.7, 0.68, -0.3), 0.02, 0.02, gold, Metal, nil, false)             -- 구슬 받침
	for i = 0, 2 do -- 몸 둘레를 떠도는 룬 조각
		local a = i / 3 * math.pi * 2
		T.ball(math.cos(a) * 0.62, -0.1 + i * 0.1, math.sin(a) * 0.62, 0.07, 0.07, 0.07, Color3.fromRGB(190, 230, 255), Neon, { T = 0.3 })
	end
end

------------------------------------------------------------
-- 폭탄병: 리벳 박힌 쇠 구슬 + 허리띠 + 타들어 가는 심지 + 화난 눈 + 해골 표시 + 작은 발 (28부품)
------------------------------------------------------------
Looks.Bomber = function(S, c, T)
	local dark, belt, rust = c:Lerp(BLACK, 0.35), Color3.fromRGB(160, 72, 55), c:Lerp(Color3.fromRGB(150, 90, 50), 0.35)
	T.ball(0, -0.02, 0, 0.95, 0.95, 0.95, c, Metal, { Tint = true })                                -- 폭탄 몸통
	T.ball(0, 0.08, 0, 0.9, 0.5, 0.9, rust, Metal, { T = 0.6 })                                     -- 녹 얼룩
	T.seg(V(0, -0.2, 0), V(0, -0.06, 0), 0.5, belt, Metal)                                          -- 붉은 허리띠 (세로 축 원반 = 허리를 감는 띠)
	T.seg(V(0, 0.44, 0), V(0, 0.58, 0), 0.13, dark, Metal)                                          -- 꼭지
	T.ball(0, 0.6, 0, 0.3, 0.12, 0.3, dark, Metal)
	T.rod(V(0.02, 0.62, 0), V(0.2, 0.84, 0), 0.025, 0.02, Color3.fromRGB(150, 120, 80), Plastic, nil, false) -- 심지
	T.ball(0.22, 0.88, 0, 0.2, 0.2, 0.2, Color3.fromRGB(255, 180, 70), Neon)                         -- 불꽃
	T.ball(0.22, 0.88, 0, 0.32, 0.32, 0.32, Color3.fromRGB(255, 130, 50), Neon, { T = 0.6 })        -- 불꽃 빛무리
	for i = 0, 5 do -- 허리띠 리벳
		local a = i / 6 * math.pi * 2
		T.ball(math.sin(a) * 0.5, -0.12, -math.cos(a) * 0.5, 0.06, 0.06, 0.06, Color3.fromRGB(210, 210, 215), Metal)
	end
	for _, side in ipairs({ -1, 1 }) do
		T.block(side * 0.2, 0.16, -0.46, 0.24, 0.07, 0.05, Color3.fromRGB(240, 75, 55), Neon, { Rz = side * 22 }) -- 화난 눈
		T.rod(V(side * 0.22, -0.42, -0.04), V(side * 0.24, -0.52, -0.1), 0.1, 0.1, dark, Plastic, nil, true)    -- 발
		T.rod(V(side * 0.45, -0.1, -0.1), V(side * 0.55, 0.18, -0.2), 0.05, 0.05, dark, Metal, nil, true)       -- 팔 (불끈)
	end
	T.ball(0, -0.26, -0.46, 0.3, 0.3, 0.06, Color3.fromRGB(235, 230, 215), Plastic)                  -- 해골 표시
	T.ball(-0.05, -0.26, -0.49, 0.06, 0.07, 0.02, BLACK, Plastic)
	T.ball(0.05, -0.26, -0.49, 0.06, 0.07, 0.02, BLACK, Plastic)
	T.block(0, -0.34, -0.49, 0.1, 0.04, 0.02, BLACK, Plastic)
end

------------------------------------------------------------
-- 마법 포탑: 넓은 받침 + 삼각 다리 + 돔 머리 + 마법 수정 + 긴 포신(고리) + 붉은 센서 + 안테나 (30부품)
------------------------------------------------------------
Looks.Turret = function(S, c, T)
	local dark, glow = c:Lerp(BLACK, 0.4), Color3.fromRGB(160, 125, 240)
	T.seg(V(0, -0.46, 0), V(0, -0.34, 0), 0.5, dark, Metal)                                          -- 넓은 받침
	T.seg(V(0, -0.34, 0), V(0, -0.24, 0), 0.38, c, Metal)                                            -- 받침 윗단
	for i = 0, 2 do -- 삼각대 다리
		local a = i / 3 * math.pi * 2 + 0.4
		T.rod(V(math.cos(a) * 0.5, -0.4, math.sin(a) * 0.5), V(math.cos(a) * 0.2, -0.1, math.sin(a) * 0.2), 0.07, 0.05, dark, Metal, nil, true)
	end
	T.ball(0, 0.18, 0, 0.74, 0.62, 0.74, c, Metal, { Tint = true })                                  -- 돔 머리
	T.seg(V(0, 0.12, 0), V(0, 0.2, 0), 0.38, dark, Metal)                                            -- 머리 띠
	T.ball(0, 0.46, 0.02, 0.26, 0.3, 0.26, glow, Neon, { T = 0.2 })                                  -- 머리 위 마법 수정
	T.ball(0, 0.46, 0.02, 0.4, 0.44, 0.4, glow, Glass, { T = 0.75 })                                 -- 수정 빛무리
	T.rod(V(0, 0.18, -0.3), V(0, 0.2, -0.95), 0.12, 0.1, Color3.fromRGB(58, 62, 74), Metal, nil, false) -- 포신
	for _, z in ipairs({ -0.5, -0.74, -0.96 }) do
		T.seg(V(0, 0.19, z), V(0, 0.19, z - 0.05), 0.15, dark, Metal)                                 -- 포신 고리
	end
	T.ball(0, 0.2, -1.04, 0.18, 0.18, 0.18, glow, Neon)                                              -- 포구의 불빛
	T.ball(0, 0.3, -0.36, 0.2, 0.2, 0.1, Color3.fromRGB(240, 80, 70), Neon)                           -- 붉은 센서
	T.ball(0, 0.3, -0.38, 0.1, 0.1, 0.06, WHITE, Neon)
	for _, side in ipairs({ -1, 1 }) do
		T.block(side * 0.38, 0.22, 0.04, 0.06, 0.4, 0.5, dark, Metal, { Rz = side * -14 })            -- 옆 방어판
		T.ball(side * 0.4, 0.4, 0.06, 0.08, 0.08, 0.08, glow, Neon)                                   -- 방어판 위 불빛
	end
	T.rod(V(-0.2, 0.42, 0.22), V(-0.28, 0.9, 0.3), 0.015, 0.012, dark, Metal, nil, true)            -- 안테나
	T.ball(-0.28, 0.92, 0.3, 0.07, 0.07, 0.07, Color3.fromRGB(240, 80, 70), Neon)
end

------------------------------------------------------------
-- 치유 사제: 두건 쓴 둥근 몸 + 길게 퍼지는 하얀 로브 + 후광 + 십자 + 모은 손 + 가슴의 치유 구슬 (28부품)
------------------------------------------------------------
Looks.Healer = function(S, c, T)
	local cream, green, gold = Color3.fromRGB(240, 244, 232), Color3.fromRGB(130, 225, 165), Color3.fromRGB(250, 228, 140)
	T.ball(0, 0.12, 0, 0.74, 0.8, 0.74, c, Plastic, { Tint = true, T = 0.15 })                       -- 몸
	T.ball(0, -0.3, 0, 0.9, 0.5, 0.9, cream, Plastic)                                                -- 로브 윗자락
	T.ball(0, -0.52, 0, 1.1, 0.3, 1.1, cream, Plastic)                                               -- 로브 아랫자락
	T.seg(V(0, -0.2, 0), V(0, -0.12, 0), 0.47, green, Plastic)                                       -- 초록 허리 장식띠
	T.ball(0, 0.26, -0.06, 0.62, 0.6, 0.58, cream, Plastic)                                          -- 두건
	T.ball(0, 0.22, -0.2, 0.44, 0.4, 0.3, c:Lerp(BLACK, 0.4), Plastic, { T = 0.1 })                  -- 두건 속 그늘
	T.ball(0, 0.78, 0, 0.8, 0.06, 0.8, gold, Neon, { T = 0.35 })                                      -- 후광 원반
	T.block(0, 1.15, 0, 0.1, 0.44, 0.1, green, Neon)                                                  -- 십자 세로
	T.block(0, 1.2, 0, 0.38, 0.1, 0.1, green, Neon)                                                   -- 십자 가로
	T.ball(0, 0.0, -0.34, 0.22, 0.22, 0.14, green, Neon, { T = 0.2 })                                -- 가슴 치유 구슬
	T.ball(0, 0.0, -0.34, 0.34, 0.34, 0.2, green, Glass, { T = 0.75 })
	for _, side in ipairs({ -1, 1 }) do
		T.eye(side * 0.12, 0.22, -0.34, 0.07, Color3.fromRGB(250, 250, 235), Color3.fromRGB(60, 120, 90))
		T.rod(V(side * 0.4, 0.1, -0.1), V(side * 0.16, -0.08, -0.36), 0.07, 0.08, cream, Plastic, nil, true) -- 모은 팔 + 손
		T.ball(side * 0.5, -0.3, 0.2, 0.2, 0.34, 0.2, cream, Plastic, { T = 0.3 })                    -- 날리는 로브 끝
	end
	for i = 0, 2 do -- 떠도는 치유의 빛
		local a = i / 3 * math.pi * 2
		T.ball(math.cos(a) * 0.6, 0.35 + i * 0.12, math.sin(a) * 0.6, 0.08, 0.08, 0.08, green, Neon, { T = 0.25 })
	end
end

------------------------------------------------------------
-- 저주 토템: 조각된 나무 기둥 3단 + 얼굴 + 날개 + 뿔 + 해골 + 빛나는 룬 + 꼭대기 저주 구슬 (30부품)
------------------------------------------------------------
Looks.Totem = function(S, c, T)
	local dark, red, teal, rune = c:Lerp(BLACK, 0.35), Color3.fromRGB(165, 65, 60), Color3.fromRGB(70, 150, 170), Color3.fromRGB(120, 235, 200)
	T.seg(V(0, -0.52, 0), V(0, -0.06, 0), 0.4, c, Wood, { Tint = true })                              -- 아래 토막
	T.seg(V(0, -0.06, 0), V(0, 0.36, 0), 0.33, dark, Wood)                                            -- 가운데 토막
	T.seg(V(0, 0.36, 0), V(0, 0.88, 0), 0.45, red, Wood, { Tint = true })                             -- 얼굴 토막 (제일 넓다)
	T.ball(0, -0.52, 0, 0.9, 0.16, 0.9, dark, Wood)                                                   -- 밑동 뿌리
	T.ball(0, 0.9, 0, 0.9, 0.14, 0.9, dark, Wood)                                                     -- 얼굴 머리 덮개
	T.block(0, 0.58, -0.43, 0.46, 0.1, 0.06, Color3.new(0.08, 0.04, 0.04), Plastic)                   -- 입
	for i = -2, 2 do T.block(i * 0.08, 0.58, -0.46, 0.05, 0.12, 0.03, Color3.fromRGB(240, 232, 210), Plastic) end -- 이빨
	T.block(0, 0.18, -0.34, 0.1, 0.24, 0.03, rune, Neon)                                              -- 룬 (가운데 토막)
	T.block(0, -0.2, -0.4, 0.26, 0.08, 0.03, rune, Neon)                                              -- 룬 (아래)
	T.ball(0, 1.0, 0, 0.3, 0.3, 0.3, Color3.fromRGB(240, 92, 82), Neon)                               -- 꼭대기 저주 구슬
	T.ball(0, 1.0, 0, 0.46, 0.46, 0.46, Color3.fromRGB(240, 92, 82), Glass, { T = 0.75 })
	for _, side in ipairs({ -1, 1 }) do
		T.glow(side * 0.2, 0.7, -0.44, 0.075, Color3.fromRGB(245, 215, 90))                            -- 눈
		T.rod(V(side * 0.34, 0.3, 0), V(side * 0.9, 0.34, 0), 0.07, 0.06, dark, Wood, nil, true)       -- 양 날개 막대
		T.block(side * 0.7, 0.1, 0, 0.5, 0.34, 0.05, teal, Plastic, { Rz = side * 14 })                -- 날개 깃
		T.block(side * 0.76, -0.06, 0, 0.3, 0.2, 0.05, teal:Lerp(BLACK, 0.2), Plastic, { Rz = side * 22 })
		T.horn(V(side * 0.3, 0.86, 0), V(side * 0.46, 1.2, 0.02), 0.07, dark, Wood, V(side * 0.1, 0, 0)) -- 뿔
		T.ball(side * 0.4, -0.2, -0.3, 0.18, 0.16, 0.14, Color3.fromRGB(235, 228, 205), Plastic)       -- 기둥 아래 해골 장식
	end
end

function M.Has(typeKey)
	return Looks[typeKey] ~= nil
end

-- d: MonsterTypes.Build 가 넘겨 주는 부품 만들기 함수, S: 몬스터 크기, c: 몸 색
function M.Build(typeKey, S, c, d)
	local look = Looks[typeKey]
	if not look then return false end
	look(S, c, toolkit(d, S))
	return true
end

return M
