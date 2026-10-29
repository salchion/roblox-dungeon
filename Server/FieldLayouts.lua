-- FieldLayouts (ServerScriptService > Modules 안의 ModuleScript, 이름: FieldLayouts)
-- 필드 8구역의 지형 배치 (경사로 Stairs / 벽 Baffles). FieldService 가 너무 커져서 (Studio 스크립트 한도 20만 바이트) 따로 뺐다.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local F = Config.Field

-- 구역마다 구조가 완전히 다르다 (지루하지 않게): Stairs = 경사로(At 시작 x / Rise 높이 변화 / Run 길이), Baffles = 길을 막는 벽
--   Baffles 종류: Edge = 한쪽 가장자리에서 벽이 뻗고 반대쪽이 열린 틈(Gap) / Center = 가운데 벽, 양옆이 열려 있음(Gap 씩)
-- 한 구역의 경사로는 올라간 만큼 내려와서 구역 끝(관문 / 캠프)은 항상 0층이다. 첫 경사로는 캠프 안전지대(70) 뒤에서 시작한다.
local ZONE_LAYOUTS = {
	{ -- 1 초원: 완만한 언덕 하나, 탁 트인 길 (입문)
		Stairs = { { At = 120, Rise = 8, Run = 36 }, { At = 230, Rise = -8, Run = 36 } }, -- (구역 길이 340)
		Baffles = { { Offset = 200, Side = 1, Gap = 190 } },
	},
	{ -- 2 숲: 좁은 지그재그 숲길 (네 번 꺾인다) + 끝에 작은 언덕
		Stairs = { { At = 540, Rise = 12, Run = 40 }, { At = 620, Rise = -12, Run = 40 } },
		Baffles = { { Offset = 160, Side = 1, Gap = 85 }, { Offset = 270, Side = -1, Gap = 85 }, { Offset = 380, Side = 1, Gap = 85 }, { Offset = 490, Side = -1, Gap = 85 } },
	},
	{ -- 3 황무지: 평평한 바위 평원 + 가운데 바위 기둥 다섯 개 (돌진 멧돼지가 경사로에서 땅에 파묻히던 문제 때문에 경사로를 없애고, 대신 엄폐물을 늘렸다)
		Stairs = {},
		Baffles = { { Offset = 190, Side = 1, Gap = 150 }, { Offset = 300, Type = "Center", Gap = 110 }, { Offset = 420, Side = -1, Gap = 150 }, { Offset = 530, Type = "Center", Gap = 110 }, { Offset = 640, Side = 1, Gap = 150 } },
	},
	{ -- 4 사막: 출렁이는 모래언덕 (오르락내리락 6번) + 낮은 벽 두 개
		Stairs = { { At = 110, Rise = 14, Run = 40 }, { At = 200, Rise = -14, Run = 40 }, { At = 300, Rise = 18, Run = 50 }, { At = 410, Rise = -18, Run = 50 }, { At = 520, Rise = 14, Run = 40 }, { At = 600, Rise = -14, Run = 40 } },
		Baffles = { { Offset = 255, Side = 1, Gap = 170 }, { Offset = 470, Side = -1, Gap = 170 } },
	},
	{ -- 5 설원: 길고 가파른 눈 덮인 비탈을 한 번에 오르는 고원 + 정상에서 겹쳐진 벽
		Stairs = { { At = 100, Rise = 60, Run = 120 }, { At = 520, Rise = -60, Run = 100 } }, -- (경사로에는 몬스터 / 소품이 없어서 길면 휑하다: 250 / 140 -> 120 / 100)
		Baffles = { { Offset = 400, Side = 1, Gap = 130 }, { Offset = 470, Side = -1, Gap = 130 } },
	},
	{ -- 6 화산: 용암 계단 (크기가 점점 커지는 세 개의 언덕 = 세 번 오르내림)
		Stairs = { { At = 100, Rise = 20, Run = 50 }, { At = 180, Rise = -20, Run = 50 }, { At = 270, Rise = 26, Run = 60 }, { At = 370, Rise = -26, Run = 60 }, { At = 470, Rise = 32, Run = 70 }, { At = 590, Rise = -32, Run = 70 } },
		Baffles = { { Offset = 230, Side = 1, Gap = 150 }, { Offset = 445, Side = -1, Gap = 150 } },
	},
	{ -- 7 암흑 지대: 요새 미로 (좁은 틈의 벽 다섯 개 + 가운데 벽) + 성채 단차
		Stairs = { { At = 120, Rise = 16, Run = 40 }, { At = 620, Rise = -16, Run = 40 } },
		Baffles = { { Offset = 190, Side = 1, Gap = 100 }, { Offset = 270, Side = -1, Gap = 100 }, { Offset = 350, Side = 1, Gap = 100 }, { Offset = 430, Side = -1, Gap = 100 }, { Offset = 510, Side = 1, Gap = 100 }, { Offset = 580, Type = "Center", Gap = 120 } },
	},
	{ -- 8 심연: 중앙 대지(높은 언덕) 하나 + 정상의 기둥, 입구는 탁 트임
		Stairs = { { At = 150, Rise = 36, Run = 90 }, { At = 440, Rise = -36, Run = 90 } },
		Baffles = { { Offset = 330, Type = "Center", Gap = 110 }, { Offset = 600, Side = 1, Gap = 150 } },
	},
}
-- 구역 길이를 700 -> 1400 으로 넓힌 만큼 지형도 채운다: 앞 700 은 위의 원래 배치, 뒤 700 은 구역마다 따로 짠 "다른 배치"(SECOND_HALF)를 이어 붙인다.
-- (올라간 만큼 내려와서 끝 높이가 0 인 배치만 쓴다. 벽은 경사로에서 40 이상 떨어뜨리고, 구역 끝(보스 자리) 가까이에는 두지 않는다. Offset / At 은 뒤 700 의 시작 기준)
local SECOND_HALF = {
	[2] = { -- 숲 뒤쪽: 지그재그 대신 트인 빈터 + 가운데 벽, 가운데에 낮은 둔덕
		Stairs = { { At = 250, Rise = 10, Run = 40 }, { At = 420, Rise = -10, Run = 40 } },
		Baffles = { { Offset = 120, Type = "Center", Gap = 100 }, { Offset = 190, Side = -1, Gap = 110 }, { Offset = 340, Type = "Center", Gap = 90 }, { Offset = 520, Side = 1, Gap = 100 }, { Offset = 610, Side = -1, Gap = 110 } },
	},
	[3] = { -- 황무지 뒤쪽: 완만한 고원 하나 + 긴 벽이 번갈아
		Stairs = { { At = 220, Rise = 10, Run = 50 }, { At = 470, Rise = -10, Run = 50 } },
		Baffles = { { Offset = 110, Side = -1, Gap = 120 }, { Offset = 340, Side = 1, Gap = 120 }, { Offset = 560, Side = -1, Gap = 120 }, { Offset = 650, Type = "Center", Gap = 120 } },
	},
	[4] = { -- 사막 뒤쪽: 모래언덕 6개 대신 큰 언덕 하나 + 낮은 벽
		Stairs = { { At = 230, Rise = 24, Run = 90 }, { At = 400, Rise = -24, Run = 90 } },
		Baffles = { { Offset = 110, Side = -1, Gap = 160 }, { Offset = 560, Side = 1, Gap = 150 } },
	},
	[5] = { -- 설원 뒤쪽: 비탈 대신 얼음 미로(벽 여섯 개) + 작은 턱
		Stairs = { { At = 330, Rise = 14, Run = 40 }, { At = 560, Rise = -14, Run = 40 } },
		Baffles = { { Offset = 120, Side = 1, Gap = 120 }, { Offset = 200, Side = -1, Gap = 120 }, { Offset = 270, Type = "Center", Gap = 100 }, { Offset = 430, Side = 1, Gap = 110 }, { Offset = 500, Side = -1, Gap = 110 }, { Offset = 650, Type = "Center", Gap = 120 } },
	},
	[6] = { -- 화산 뒤쪽: 큰 언덕 하나 + 작은 언덕 하나 (앞쪽과 반대로 큰 것부터)
		Stairs = { { At = 90, Rise = 32, Run = 70 }, { At = 220, Rise = -32, Run = 70 }, { At = 400, Rise = 18, Run = 50 }, { At = 500, Rise = -18, Run = 50 } },
		Baffles = { { Offset = 340, Side = -1, Gap = 150 }, { Offset = 610, Side = 1, Gap = 140 } },
	},
	[7] = { -- 암흑 지대 뒤쪽: 미로 대신 성채 고원 + 고원 위의 벽 셋
		Stairs = { { At = 150, Rise = 22, Run = 50 }, { At = 520, Rise = -22, Run = 50 } },
		Baffles = { { Offset = 270, Type = "Center", Gap = 110 }, { Offset = 350, Side = 1, Gap = 110 }, { Offset = 430, Type = "Center", Gap = 110 }, { Offset = 640, Side = -1, Gap = 120 } },
	},
	[8] = { -- 심연 뒤쪽: 두 단 계단식 대지 + 기둥 벽
		Stairs = { { At = 100, Rise = 20, Run = 60 }, { At = 300, Rise = 20, Run = 60 }, { At = 520, Rise = -40, Run = 80 } },
		Baffles = { { Offset = 200, Side = -1, Gap = 150 }, { Offset = 430, Type = "Center", Gap = 130 }, { Offset = 640, Side = 1, Gap = 140 } },
	},
}
for zone, layout in ipairs(ZONE_LAYOUTS) do
	local baseLength = zone == 1 and 340 or 700
	local copies = math.max(1, math.floor((F.ZoneLengths[zone] or F.ZoneLength) / baseLength + 0.5)) - 1
	if copies > 0 then
		local stairs, baffles = {}, {}
		for _, stair in ipairs(layout.Stairs) do table.insert(stairs, stair) end
		for _, wall in ipairs(layout.Baffles) do table.insert(baffles, wall) end
		local second = SECOND_HALF[zone]
		for copy = 1, copies do
			for _, stair in ipairs(second and second.Stairs or stairs) do
				local clone = table.clone(stair)
				clone.At = stair.At + baseLength * copy
				table.insert(layout.Stairs, clone)
			end
			for _, wall in ipairs(second and second.Baffles or baffles) do
				local clone = table.clone(wall)
				clone.Offset = wall.Offset + baseLength * copy
				table.insert(layout.Baffles, clone)
			end
		end
	end
end

return ZONE_LAYOUTS
