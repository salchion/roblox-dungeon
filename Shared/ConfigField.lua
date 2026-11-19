-- ConfigField (ReplicatedStorage 안의 ModuleScript, 이름: ConfigField)
-- Config.Field (필드(8구역) 밸런스 표): Config.lua 가 Roblox 스크립트 한 개 최대 크기(200,000자)에 닿아 따로 뺐다 (11-19 분할).
--   Config.lua 가 require 해서 Config.Field 에 넣는다. 다른 Config 값을 참조하지 않는 순수 데이터 표 (뒤에서 Config 가 키를 더 붙이는 것은 그대로).
return {
	StartX = 150,          -- 필드 시작 x좌표 (로비 동쪽 끝)
	ZoneLengths = { 340, 1400, 1400, 1400, 1400, 1400, 1400, 1400 }, -- 구역별 길이: 1구역은 작게(군주가 입구 가까이에 있다), 나머지는 두 배로 넓힌 큰 사냥터 (예전 700)
	ZoneLength = 1400,       -- 구역 하나의 길이: 걸어서 가로지르는 데 1분 가까이 걸리는 큰 사냥터
	ZoneCount = 8,
	CampRespawn = false, -- (11-17 종태 님: 필드에서 쓰러지면 마을로 부활) true 면 그 구역 캠프에서 부활 (11-15 에 넣었던 방식)
	Width = 320,
	MonstersPerZone = 22,
	ZoneCountMult = { 1.7, 4.6, 4.5, 3.4, 3.5, 3.8, 4.3, 4.8 }, -- (2구역 이후는 길이가 두 배라 수를 1.6배로: 밀도는 약 80%. 두 배로 하면 서버 / 렌더 부담이 너무 커진다) -- 구역별 몬스터 수 배율 (1구역은 길이가 340이라 22마리로 촘촘하고, 700 길이인 2구역 이후는 배율로 맞춘다: 2구역 22 -> 약 42마리)
	ElitesPerZone = 3,
	CampSafe = 70,             -- 각 구역 입구 캠프 주변 안전지대 반경(몬스터가 노리지 않음)
	RespawnTime = 5,
	MonsterRangeMult = 1.4, -- 일반 몬스터 공격 사정거리 배율 (몬스터가 가까이 오기 전에 죽어서 투사체를 못 쏘던 것을 줄인다)
	SnipeRange = 85,     -- 필드 군주를 이 거리 밖에서 계속 때리면 "심판"(피할 수 없는 강공)이 내려온다 (저격총으로 멀리서 안전하게 잡는 것 방지)
	-- "심판" 피해: 구역별 고정 절대값 (방어 무시. 내 최대 체력 비율이 아니라 강체 / 레벨 / 체력이 실제로 더 버티게). 구역 밖이면 마지막 값.
	-- 근거 = 구역 진입 적정 최대 체력(wall_sim 도달 스냅샷, 레벨 체력 + 장비 + 훈련, 강체 0)의 약 40%, 10 단위 올림:
	-- 1구역 Lv1 286 / 2구역 Lv4 310 / 3구역 Lv11 508 / 4구역 Lv20 614 / 5구역 Lv43 866 / 6구역 Lv67 1302 / 7구역 Lv110 1735 / 8구역 Lv212 2881
	JudgeDamage = { 120, 130, 210, 250, 350, 530, 700, 1160 },
	AggroRange = 80, -- (55 -> 80: 멀리 있는 몬스터도 일찍 알아채고 몰려온다)
	LeashRange = 125,
	EliteMultiplier = 3.5,     -- 엘리트 몬스터 체력 배율 (5였는데 3구역부터 너무 오래 걸려 낮춤)
	EliteTicketChance = 0.2,   -- 엘리트 처치 시 티켓 획득 확률
	BossRespawn = 120,
	-- 구역마다 군주가 다시 나타나는 시간(초): 모두가 같이 쓰는 필드라서, 앞 구역은 자주 / 뒤 구역은 드물게 (뒤로 갈수록 귀한 상대)
	BossRespawnByZone = { 30, 30, 30, 30, 30, 30, 30, 30 }, -- (열쇠는 하루 드랍 한도가 있어서 간격으로 막지 않는다: 어느 구역이든 30초 뒤에 다시 나온다)
	-- 구역 군주를 상대하기 전에 갖춰야 할 권장 전투력 (모자라면 군주를 만났을 때 "무기를 강화하세요" 안내가 뜬다)
	-- 권장 전투력 (화면 안내용 표시값): 4~8구역 = 그 구역 관문에 처음 도달한 순간의 실제 전투력 x 1.10 (A1, 11-16). 1~3구역은 옛 "일반 몬스터 약 3초" 기준값.
	--   몬스터 체력 곡선(ZoneDanger.Health)과 연동되지 않는다: 체력 / 보상을 바꿔도 이 표는 따라가지 않으니, 표시 목표로 쓸 때만 손대면 된다.
	RecommendPower = { 350, 750, 1700, 5500, 12000, 33000, 84000, 310000 }, -- 4~8구역: 관문 도달 시 실제 전투력의 1.10배 (A1). 1~3구역은 예전 값 (화면 목표 / 안내용 표시값만: 몬스터 체력 / 보상과는 무관)
	-- (BossPower 는 심연 도전의 보상 배율 계산에만 쓰이는 옛 값이다. 화면에 보이는 권장 전투력은 위 RecommendPower)
	-- 전투력에 세트 효과가 들어가면서(Config.PowerAug) 같은 사람의 숫자가 커졌다 -> 위 표에 "그 구역 관문에 도달할 때 보통 켜 둔 공격 효과 단계 합"만큼 곱한다 (아래 do 블록).
	--   (11-17 wall_sim 실측, 번 돈의 35% 를 세트 효과에 쓴다고 가정: 관문 도달 시 공격 효과 단계 합 0/1/3/5/8/9/10/13 -> 이 표와 ±1 안이라 그대로.
	--    세트 포함 관문 도달 전투력 451 / 636 / 2,346 / 8,017 / 21,526 / 62,632 / 167,853 / 728,529 -> 권장 ÷ 도달 = 0.78 / 1.34 / 0.98 / 1.10 / 1.03 / 1.10 / 1.16 / 1.04 (3구역부터 의도 1.0~1.15 안))
	RecommendAugLv = { 0, 1, 3, 5, 7, 9, 11, 12 },
	BossPower = { 350, 800, 1600, 3000, 5200, 8500, 13000, 20000 },
	BossTickets = 2,           -- 필드 보스 처치 시 주변 플레이어에게 지급
	-- 구역 관문: 다음 구역으로 가려면 "지금 구역"에서 몬스터를 정해진 수만큼 처치해야 열린다 (엘리트 x3, 보스 x10)
	-- 열면 보상(골드 / 티켓)을 받고, 다음 구역은 몬스터 보상이 크고 장비 등급이 높아진다.
	Gate = {
		KillsNeeded = { 40, 55, 70, 85, 100, 120, 140 }, -- [n] = 구역 n 의 관문(구역 n+1 입구)을 열기 위한 처치 수
		EliteWeight = 3,
		BossWeight = 10,
		RewardGold = 400,      -- x 구역 번호
		RewardTickets = 1,     -- 구역 3부터 +1
	},
	-- 구역이 넘어갈 때마다 난이도가 "확" 뛴다 (레벨 증가에 더해지는 구역 배율). 보상도 같이 크게 오른다.
	ZoneDanger = {
		Health = { 1, 1.5, 2.4, 13, 24, 57, 120, 195 }, -- (4구역 10 -> 13: 로그에서 4구역이 너무 잘 밀린다는 의견)       -- (4구역부터는 일부러 "턱턱 막히게": 세트 / 펫 피해 때문에 로그에서 4구역이 너무 쉽게 밀려 체력 약 1.8 ~ 2.6배)
		Damage = { 1, 1.5, 2.5, 5.6, 7.1, 11, 12.1, 15.5 }, -- (4구역 4.7 -> 5.6: 평균 체력 82~94% 로 위협이 약했다)        -- (2구역부터 약 +15%: 위협감이 약하다는 의견. 1구역은 그대로) (7~8구역은 한두 방에 죽지 않게 낮춤)
		Speed = { 1, 1.05, 1.1, 1.18, 1.26, 1.35, 1.45, 1.55 },
		LordHealth = { [4] = 10 }, -- 군주만 따로: 4구역 군주는 예전 체력 (NEAR MISS 수정으로 공격력이 줄어 이미 더 오래 걸린다)
		Reward = { 1, 1.5, 2.2, 7.2, 9.2, 14.3, 21.6, 33.8 }, -- (4구역 5.8 -> 7.2: 체력을 올린 만큼 보상도) -- (4구역부터는 몬스터 체력을 올린 만큼 보상도 같은 비율로 올림)
	},
	-- 구역별 저격형 몬스터(마법 포탑 / 저격 임프) 피해 배율: 3구역은 "2구역처럼 밀다가 방심하면 죽는" 구역 (4구역 기본 배율 4.7 보다는 낮게: 4구역이 여전히 벽)
	SniperDamage = { [3] = 1.8 },
	SniperTypes = { Turret = true, Imp = true },
	-- 현상금(엘리트 무리): 큰길에서 벗어난 곳에 나타나고 제한 시간 안에 모두 잡으면 근처 모두 보상
	Bounty = { FirstDelay = 60, MinGap = 120, MaxGap = 180, Seconds = 120, PackSize = 3, GoldMult = 3, RewardRadius = 140,
		TicketsByZone = { 1, 1, 1, 2, 2, 2, 3, 3 } },
	MobDamageMult = 1.2,       -- 필드 일반 / 엘리트 몬스터 피해 +20% (체력이 잘 차서 긴장감이 없다는 의견. 군주는 그대로)
	MobShotIntervalMult = 0.8, -- 필드 일반 / 엘리트 몬스터 공격 간격 x0.8 (= 25% 더 자주 쏜다)
	-- 초반 일반 몬스터 / 엘리트만 체력을 더 낮춘다 (군주는 제외): 처음 사냥이 "잘 안 죽어서 답답하다"는 의견. 1구역 x0.45, 2구역 x0.8
	EarlyMobHealth = { 0.45, 0.8 },
	ZoneNames = { "Meadow", "Forest", "Wasteland", "Desert", "Snowfield", "Volcano", "Darklands", "Abyss" },
	-- 구역별로 나오는 몬스터 종류와 비중 (MonsterTypes.lua 의 Defs 이름)
	ZonePools = {
		{ Slime = 5, Bat = 2, Spider = 1 },
		{ Slime = 3, Spitter = 3, Bat = 2, Spider = 2, Wisp = 1 },
		{ Spitter = 2, Charger = 2, Golem = 1, Imp = 3, Turret = 3, Healer = 1 }, -- (3구역: 저격형(포탑 / 임프)을 절반으로. 방심하면 멀리서 꽂혀 죽을 수 있는 압박)
		{ Charger = 3, Bomber = 3, Spitter = 2, Spider = 2, Imp = 2, Healer = 1 },
		{ Mage = 3, Golem = 2, Bat = 3, Wisp = 2 },
		{ Bomber = 3, Charger = 3, Mage = 2, Turret = 2, Totem = 1 },
		{ Mage = 3, Golem = 2, Charger = 2, Bomber = 2, Imp = 2, Totem = 1 },
		{ Mage = 2, Golem = 3, Charger = 3, Bomber = 3, Spitter = 1, Turret = 2, Totem = 2, Wisp = 2 },
	},
	ZoneColors = {
		Color3.fromRGB(90, 150, 80), Color3.fromRGB(50, 110, 60), Color3.fromRGB(140, 115, 80), Color3.fromRGB(190, 168, 108),
		Color3.fromRGB(180, 195, 212), Color3.fromRGB(95, 55, 50), Color3.fromRGB(55, 45, 75), Color3.fromRGB(35, 30, 50),
	},
	ZoneMaterials = {
		Enum.Material.Grass, Enum.Material.Grass, Enum.Material.Ground, Enum.Material.Sand,
		Enum.Material.Snow, Enum.Material.Basalt, Enum.Material.Slate, Enum.Material.Slate,
	},
	-- 구역 군주마다 기본 패턴 비중을 다르게 (slam 내려찍기 / charge 돌진 / spiral 나선). 2~8구역은 여기에 구역 고유 패턴(FieldBossPatterns)이 한 개 더 섞인다.
	BossStyle = {
		[1] = { slam = 3, charge = 2, spiral = 2 },
		[2] = { slam = 0, charge = 3, spiral = 1 }, -- 돌진 + 뿔 질주
		[3] = { slam = 3, charge = 1, spiral = 1 }, -- 내려찍기 + 가끔 돌진(달려듦) + 바위 소나기
		[4] = { slam = 1, charge = 0, spiral = 2 }, -- 나선 + 독 웅덩이
		[5] = { slam = 0, charge = 0, spiral = 3 }, -- 나선 + 얼음 가시줄
		[6] = { slam = 2, charge = 0, spiral = 1 }, -- 내려찍기 + 유성우
		[7] = { slam = 0, charge = 2, spiral = 1 }, -- 돌진 + 순간이동 베기
		[8] = { slam = 1, charge = 1, spiral = 2 }, -- 나선 + 심연 광선
	},
	BossTempo = 0.45, -- 군주 패턴 간격 배율 (1 = 예전 6.5초, 0.45 = 약 2.9초. 0.55 에서 "느리다"는 의견으로 더 자주)
	BossSignatureWeight = 7, -- 구역 고유 패턴이 뽑힐 비중
	-- 구역 군주의 기본 공격 탄 모양 / 색 (Style: Crystal / Spear / Dart / Shard / Halo / Skull / Needle / Bomb / Seeker / Crescent ...). MissileStyle = false 이면 유도탄 없음
	BossShot = {
		[1] = { Style = "Crystal", Color = Color3.fromRGB(235, 110, 100), RingStyle = "Crystal", RingColor = Color3.fromRGB(235, 175, 90), MissileStyle = "Missile", MissileColor = Color3.fromRGB(240, 170, 90) },
		[2] = { Style = "Spear", Color = Color3.fromRGB(150, 215, 110), RingStyle = "Dart", RingColor = Color3.fromRGB(190, 225, 120), MissileStyle = "Seeker", MissileColor = Color3.fromRGB(170, 235, 130) },
		[3] = { Style = "Bomb", Color = Color3.fromRGB(200, 165, 120), RingStyle = "Bomb", RingColor = Color3.fromRGB(215, 180, 130), MissileStyle = false, MissileColor = Color3.fromRGB(215, 180, 130) },
		[4] = { Style = "Needle", Color = Color3.fromRGB(140, 240, 110), RingStyle = "Needle", RingColor = Color3.fromRGB(165, 245, 120), MissileStyle = "Snake", MissileColor = Color3.fromRGB(130, 235, 100) },
		[5] = { Style = "Shard", Color = Color3.fromRGB(150, 220, 255), RingStyle = "Shard", RingColor = Color3.fromRGB(190, 235, 255), MissileStyle = false, MissileColor = Color3.fromRGB(170, 225, 255) },
		[6] = { Style = "Seeker", Color = Color3.fromRGB(255, 135, 55), RingStyle = "Bomb", RingColor = Color3.fromRGB(255, 160, 70), MissileStyle = "Missile", MissileColor = Color3.fromRGB(255, 120, 50) },
		[7] = { Style = "Crescent", Color = Color3.fromRGB(190, 120, 255), RingStyle = "Skull", RingColor = Color3.fromRGB(210, 160, 255), MissileStyle = "Seeker", MissileColor = Color3.fromRGB(200, 130, 255) },
		[8] = { Style = "Halo", Color = Color3.fromRGB(255, 105, 175), RingStyle = "Halo", RingColor = Color3.fromRGB(255, 150, 200), MissileStyle = "Seeker", MissileColor = Color3.fromRGB(255, 110, 180) },
	},
	-- 구역 군주의 움직임 (Speed: 걷는 속도 배율 / Keep: 유지하려는 거리 / Strafe: 좌우로 도는 정도 / Burst: 옆으로 휙 튀어 나가는 순간 속도 배율 / Kite: 가까워지면 물러남)
	BossMove = {
		[2] = { Speed = 1.6, Strafe = 0.8, Burst = 2.4, StrafeSpeed = 30 },            -- 사슴령: 빠르게 돌아다니다 휙 치고 나간다
		[3] = { Speed = 0.9, Strafe = 0.45, Burst = 2.0, StrafeSpeed = 14 },           -- 바위 거인: 묵직하지만 천천히 돌며 가끔 쿵 하고 달려든다
		[4] = { Speed = 1.3, Strafe = 1.0, Burst = 2.8, StrafeSpeed = 30 },            -- 전갈: 멈췄다가 옆으로 확 튀어 나가는 재빠른 움직임
		[5] = { Speed = 1.0, Keep = 34, Kite = true, Strafe = 0.5, StrafeSpeed = 18 }, -- 얼음 군주: 거리를 두고 떠다니며 가까워지면 물러난다
		[6] = { Speed = 1.2, Strafe = 0.6, Burst = 2.4, StrafeSpeed = 24 },            -- 용암 악마: 이글거리며 좌우로 달려든다
		[7] = { Speed = 1.3, Strafe = 0.6, Burst = 2.4, StrafeSpeed = 26 },            -- 사신: 미끄러지듯 / 가끔 빠르게
		[8] = { Speed = 0.9, Keep = 28, Strafe = 0.7, Burst = 1.8, StrafeSpeed = 16 }, -- 심연의 눈: 떠다니며 거리를 유지
	},
	BossSizeMult = { [3] = 1.15, [4] = 0.9, [6] = 1.1, [7] = 0.95, [8] = 1.15 }, -- 군주 크기 배율 (실루엣 변화, 나머지는 1)
	Boss = {
		Name = "Field Overlord",
		Size = 18,
		MaxHealth = 6000,
		Speed = 8,
		ShotDamage = 28,
		ShotInterval = 1.3, -- (1.5 -> 1.3)
		ShotSpeed = 55,
		Gold = 600,
	},
}
