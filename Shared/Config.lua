-- Config (ReplicatedStorage 안의 ModuleScript, 이름: Config)
-- 서버/클라이언트가 같이 쓰는 밸런스 값과 계산 함수. 숫자만 바꿔가며 조절하면 됨.

local Config = {}

Config.StartGold = 300 -- 처음 접속했을 때 지급되는 골드

------------------------------------------------------------
-- 플레이어 기본 능력치 / 스탯 포인트 효과
------------------------------------------------------------
Config.Player = {
	BaseHealth = 100,
	WalkSpeed = 16,
	RunSpeed = 28,          -- Shift를 누르고 있을 때
	DashSpeed = 80,         -- Q 슬라이딩 시작 속도 (점점 느려지며 미끄러짐)
	DashTime = 0.6,         -- 슬라이딩 지속 시간(초)
	DashCooldown = 2.0,     -- 슬라이딩 재사용 대기시간(초)
	BaseDamage = 10,        -- 무기 +0 기준 데미지
	BaseCooldown = 0.35,    -- 기본 공격 간격(초)
	AttackRange = 300,      -- 사거리
	CritMultiplier = 2,     -- 치명타 데미지 배율
	CritPerPoint = 0.04,    -- 치명타 포인트당 확률 +4%
	MaxCritPoints = 15,     -- 치명타 최대 60%
	SpeedPerPoint = 0.08,   -- 공격속도 포인트당 +8%
	HealthPerPoint = 15,    -- 최대 체력 포인트당 +15
}

Config.StatAttributes = {   -- Upgrade 리모트가 받는 이름 -> 플레이어 Attribute
	Crit = "CritPoints",
	Speed = "SpeedPoints",
	Health = "HealthPoints",
}

------------------------------------------------------------
-- 파티
------------------------------------------------------------
Config.Party = {
	MaxSize = 4,
	InviteTimeout = 30,
}

------------------------------------------------------------
-- 던전
------------------------------------------------------------
Config.Dungeon = {
	TotalWaves = 5,          -- 이 웨이브를 모두 깨면 보스 등장
	StartCountdown = 5,      -- 입장 후 첫 웨이브까지 대기(초)
	StatPhaseTime = 30,      -- 웨이브 클리어 후 스탯 분배 시간(초)
	PointsPerWave = 3,       -- 웨이브 클리어마다 지급되는 스탯 포인트
	WaveClearGold = 40,      -- 웨이브 클리어 보너스 골드 (x 웨이브 번호)
	VictoryGold = 400,       -- 보스 처치 보너스 골드
	ReturnDelay = 8,         -- 던전 종료 후 로비 복귀까지 대기(초)

	ArenaRadius = 90,
	SpawnRadius = 65,        -- 몬스터가 나타나는 거리
	ArenaOrigin = Vector3.new(0, 1500, 0), -- 던전 아레나는 로비/필드와 겹치지 않게 아주 높은 하늘 위에 만들어짐
	ArenaSpacing = 500,      -- 파티별 아레나 간격
	MaxArenas = 8,           -- 동시에 열 수 있는 던전 수
}

-- 웨이브별 몬스터 마릿수 (파티 인원이 많을수록 늘어남)
function Config.Dungeon.GetMonsterCount(wave, partySize)
	return math.floor((2 + wave) * (1 + 0.5 * (partySize - 1)))
end

-- 웨이브 번호 -> 몬스터 레벨
function Config.Dungeon.GetWaveMonsterLevel(wave)
	return wave * 2 - 1
end

-- 파티 인원에 따른 몬스터 체력 배율
function Config.Dungeon.GetHealthScale(partySize)
	return 1 + 0.6 * (partySize - 1)
end

------------------------------------------------------------
-- 몬스터 / 보스
------------------------------------------------------------
Config.Monster = {}

function Config.Monster.GetStats(level)
	return {
		Size = math.min(3 + (level - 1) * 0.8, 40),
		MaxHealth = math.floor(40 * 1.22 ^ (level - 1)),
		Speed = 10,
		ShotDamage = 8 + level * 2,
		ShotInterval = math.max(1.2, 2.6 - level * 0.05),
		ShotSpeed = 45,
		Gold = 8 + level * 4, -- 처치 시 파티원 모두에게 지급
	}
end

Config.Boss = {
	Name = "던전의 군주",
	Size = 24,
	MaxHealth = 2500,        -- 1인 기준 (파티 인원 배율 추가)
	Speed = 6,
	ShotDamage = 22,
	ShotInterval = 2.2,      -- 조준 3연발 간격
	ShotSpeed = 55,
	RingInterval = 6,        -- 전방위 탄막 간격
	RingCount = 16,
	EnrageRatio = 0.5,       -- 체력이 이 비율 이하가 되면 광폭화 (발사 간격 x0.6, 쫄병 소환)
	MinionCount = 3,
	MinionLevel = 5,
	Gold = 500,
	Color = Color3.fromRGB(150, 20, 30),
	Tickets = 3,             -- 보스 처치 시 파티원 모두에게 지급되는 장비 뽑기 티켓
}

------------------------------------------------------------
-- 무기 강화
------------------------------------------------------------
Config.Weapon = {
	MaxLevel = 15,
	BaseCost = 100,
	CostGrowth = 1.3,
	DamagePerLevel = 0.2,   -- 레벨당 데미지 +20%
	SizePerLevel = 0.06,    -- 레벨당 크기 +6%
	-- 레벨 구간별 외형. MinLevel 이상이면 해당 외형이 적용됨.
	-- Particles: 초당 파티클 수 / Trail: 궤적 / Light: 빛 범위 / Rainbow: 무지개 이펙트
	Tiers = {
		-- Shot: 발사체 외형. Style(Ball/Bolt/Orb/Cannon/Fire/Rainbow) / Size / Length(Bolt만) / Speed(초당 거리) / Impact(착탄 시 터지는 입자 수)
		{ MinLevel = 0,  Name = "낡은 권총", Prefix = "낡은",       Color = Color3.fromRGB(165, 165, 175), Material = Enum.Material.Metal, Particles = 0,  Trail = false, Light = 0,
			Shot = { Style = "Ball", Size = 0.6, Speed = 260, Impact = 0 } },
		{ MinLevel = 3,  Name = "강철 권총", Prefix = "강철",       Color = Color3.fromRGB(90, 160, 255),  Material = Enum.Material.Metal, Particles = 6,  Trail = false, Light = 0,
			Shot = { Style = "Bolt", Size = 0.35, Length = 3, Speed = 320, Impact = 6 } },
		{ MinLevel = 6,  Name = "마력 라이플", Prefix = "마력",     Color = Color3.fromRGB(175, 95, 255),  Material = Enum.Material.Glass, Particles = 12, Trail = true,  Light = 0,
			Shot = { Style = "Orb", Size = 1.3, Speed = 190, Impact = 14 } },
		{ MinLevel = 9,  Name = "황금 캐논", Prefix = "황금",       Color = Color3.fromRGB(255, 200, 50),  Material = Enum.Material.Neon,  Particles = 22, Trail = true,  Light = 10,
			Shot = { Style = "Cannon", Size = 2.4, Speed = 140, Impact = 30 } },
		{ MinLevel = 12, Name = "불꽃의 건", Prefix = "불꽃의",       Color = Color3.fromRGB(255, 70, 40),   Material = Enum.Material.Neon,  Particles = 40, Trail = true,  Light = 16,
			Shot = { Style = "Fire", Size = 2.0, Speed = 160, Impact = 40 } },
		{ MinLevel = 15, Name = "전설의 무지개 건", Prefix = "전설의 무지개", Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.Neon,  Particles = 60, Trail = true,  Light = 20, Rainbow = true,
			Shot = { Style = "Rainbow", Size = 2.2, Speed = 170, Impact = 60 } },
	},
}

------------------------------------------------------------
-- 로비 허수아비 (때릴 때마다 골드). 획득 골드 = GoldPerHit x Multiplier
-- RequiredLevel: 이 무기 강화 레벨 이상이어야 골드가 들어옴 (0이면 제한 없음)
-- List 순서대로 훈련장에 1~10번 허수아비가 놓인다.
------------------------------------------------------------
Config.Dummy = {
	GoldPerHit = 1,
	Spacing = 20,     -- 허수아비 간격 (1열로 나열)
	List = {
		{ Multiplier = 1,   RequiredLevel = 0 },
		{ Multiplier = 1.5, RequiredLevel = 0 },
		{ Multiplier = 2,   RequiredLevel = 1 },
		{ Multiplier = 3,   RequiredLevel = 2 },
		{ Multiplier = 4,   RequiredLevel = 3 },
		{ Multiplier = 6,   RequiredLevel = 5 },
		{ Multiplier = 8,   RequiredLevel = 7 },
		{ Multiplier = 12,  RequiredLevel = 9 },
		{ Multiplier = 18,  RequiredLevel = 12 },
		{ Multiplier = 30,  RequiredLevel = 15 },
	},
}

------------------------------------------------------------
-- 소리. 값은 Roblox 오디오 에셋 ID(숫자). 0이면 그 소리는 재생하지 않음.
-- ID는 이 파일이 아니라 ReplicatedStorage > AudioIds 스크립트에 적는다 (업데이트해도 안 지워짐)
------------------------------------------------------------
local audioIds = script.Parent:FindFirstChild("AudioIds") -- 내 소리 ID는 AudioIds 스크립트에 적는다
local ids = audioIds and require(audioIds) or {}

-- AudioIds 에서 0(비어 있음)으로 둔 항목은 여기 기본값을 쓴다. AudioIds 에 숫자를 적으면 그게 우선.
local defaultIds = {
	Lobby = 119474756800883,   -- 마을 배경음악 (Field 가 비어 있으면 필드에서도 이 곡이 이어서 나옴)
	Dungeon = 139997523791273, -- 던전(웨이브) 배경음악
	Boss = 132347366936691,    -- 보스전 배경음악
	Shot = 86531217997974,     -- 총 쏘는 소리
}
for key, value in pairs(defaultIds) do
	if not ids[key] or ids[key] == 0 then
		ids = table.clone(ids)
		ids[key] = value
	end
end

Config.Audio = {
	MusicVolume = 0.4,
	Music = {
		Lobby = ids.Lobby or 0,      -- 로비 배경음악
		Dungeon = ids.Dungeon or 0,  -- 던전(웨이브) 배경음악
		Boss = ids.Boss or 0,        -- 보스전 배경음악
		Field = ids.Field or 0,      -- 필드 배경음악 (없으면 로비 음악)
	},
	Shot = ids.Shot or 0,            -- 총 쏘는 소리 (무기가 강해질수록 낮고 묵직하게 재생됨)
	ShotVolume = 0.5,
	EnhanceSuccess = ids.EnhanceSuccess or 0, -- 강화 성공 소리
}

------------------------------------------------------------
-- 장비 (갑옷 / 장갑 / 신발): 보스 티켓으로 뽑기 -> 골드로 강화
-- 등급(일반~신화)이 높을수록 효과가 크고, 강화 레벨이 오를수록 더 커짐
------------------------------------------------------------
Config.Gear = {
	MaxLevel = 15,
	LevelBonus = 0.08,   -- 강화 1레벨당 효과 +8%
	RarityNames = { "일반", "희귀", "영웅", "전설", "신화" },
	RarityColors = {
		Color3.fromRGB(190, 190, 190),
		Color3.fromRGB(90, 200, 120),
		Color3.fromRGB(170, 90, 255),
		Color3.fromRGB(255, 190, 40),
		Color3.fromRGB(255, 70, 90),
	},
	RarityMaterials = {
		Enum.Material.Leather,
		Enum.Material.Metal,
		Enum.Material.DiamondPlate,
		Enum.Material.Foil,
		Enum.Material.Neon,
	},
	RarityMult = { 1, 1.6, 2.5, 4, 6 },
	Slots = {
		{ Key = "Armor", Name = "갑옷", Stat = "Health", StatName = "최대 체력", Base = 40, BaseCost = 120,
			Names = { "가죽 갑옷", "사슬 갑옷", "강철 갑옷", "미스릴 갑옷", "용린 갑옷" } },
		{ Key = "Gloves", Name = "장갑", Stat = "Crit", StatName = "치명타 확률", Base = 0.02, BaseCost = 100,
			Names = { "천 장갑", "가죽 장갑", "강철 건틀릿", "미스릴 건틀릿", "용발톱 건틀릿" } },
		{ Key = "Boots", Name = "신발", Stat = "Speed", StatName = "이동 속도", Base = 0.6, BaseCost = 100,
			Names = { "낡은 신발", "가죽 장화", "강철 부츠", "미스릴 부츠", "바람의 부츠" } },
	},
}

function Config.GetGearSlot(key)
	for _, slot in ipairs(Config.Gear.Slots) do
		if slot.Key == key then
			return slot
		end
	end
	return nil
end

-- 등급(rarity 1~5)과 강화 레벨에 따른 효과 수치
function Config.GetGearStat(slotKey, rarity, level)
	if rarity <= 0 then return 0 end
	local slot = Config.GetGearSlot(slotKey)
	return slot.Base * Config.Gear.RarityMult[rarity] * (1 + Config.Gear.LevelBonus * level)
end

function Config.FormatGearStat(slotKey, value)
	local slot = Config.GetGearSlot(slotKey)
	if slot.Stat == "Health" then
		return string.format("최대 체력 +%d", math.floor(value + 0.5))
	elseif slot.Stat == "Crit" then
		return string.format("치명타 확률 +%.1f%%", value * 100)
	end
	return string.format("이동 속도 +%.1f", value)
end

function Config.GetGearCost(slotKey, rarity, level)
	local slot = Config.GetGearSlot(slotKey)
	return math.floor(slot.BaseCost * (1 + 0.4 * (rarity - 1)) * 1.28 ^ level)
end

function Config.GetGearEnhanceChance(level)
	return math.max(0.35, 1 - 0.045 * level)
end

Config.Gacha = {
	Rates = { 55, 28, 12, 4, 1 },                  -- 일반 ~ 신화 (%)
	DuplicateGold = { 40, 120, 400, 1500, 6000 },  -- 이미 같거나 더 좋은 장비가 있으면 골드로 교환
}

------------------------------------------------------------
-- 필드: 로비 동쪽으로 길게 이어진 직선 사냥터. 오른쪽(동쪽)으로 갈수록 몬스터가 강해짐.
------------------------------------------------------------
Config.Field = {
	StartX = 150,          -- 필드 시작 x좌표 (로비 동쪽 끝)
	ZoneLength = 700,        -- 구역 하나의 길이: 걸어서 가로지르는 데 1분 가까이 걸리는 큰 사냥터
	ZoneCount = 8,
	Width = 320,
	MonstersPerZone = 22,
	ElitesPerZone = 3,
	CampSafe = 70,             -- 각 구역 입구 캠프 주변 안전지대 반경(몬스터가 노리지 않음)
	RespawnTime = 10,
	AggroRange = 55,
	LeashRange = 110,
	EliteMultiplier = 5,       -- 엘리트 몬스터 체력 배율
	EliteTicketChance = 0.2,   -- 엘리트 처치 시 티켓 획득 확률
	BossRespawn = 120,
	BossTickets = 2,           -- 필드 보스 처치 시 주변 플레이어에게 지급
	ZoneNames = { "초원", "숲", "황무지", "사막", "설원", "화산", "암흑 지대", "심연" },
	-- 구역별로 나오는 몬스터 종류와 비중 (MonsterTypes.lua 의 Defs 이름)
	ZonePools = {
		{ Slime = 5, Bat = 2 },
		{ Slime = 3, Spitter = 3, Bat = 2 },
		{ Spitter = 3, Charger = 3, Golem = 1 },
		{ Charger = 3, Bomber = 3, Spitter = 2 },
		{ Mage = 3, Golem = 2, Bat = 3 },
		{ Bomber = 3, Charger = 3, Mage = 2 },
		{ Mage = 3, Golem = 2, Charger = 2, Bomber = 2 },
		{ Mage = 2, Golem = 3, Charger = 3, Bomber = 3, Spitter = 1 },
	},
	ZoneColors = {
		Color3.fromRGB(90, 150, 80), Color3.fromRGB(50, 110, 60), Color3.fromRGB(140, 115, 80), Color3.fromRGB(215, 190, 120),
		Color3.fromRGB(225, 235, 245), Color3.fromRGB(95, 55, 50), Color3.fromRGB(55, 45, 75), Color3.fromRGB(35, 30, 50),
	},
	ZoneMaterials = {
		Enum.Material.Grass, Enum.Material.Grass, Enum.Material.Ground, Enum.Material.Sand,
		Enum.Material.Snow, Enum.Material.Basalt, Enum.Material.Slate, Enum.Material.Slate,
	},
	Boss = {
		Name = "필드의 지배자",
		Size = 18,
		MaxHealth = 6000,
		Speed = 8,
		ShotDamage = 28,
		ShotInterval = 1.5,
		ShotSpeed = 55,
		Gold = 600,
	},
}

function Config.Field.GetZoneLevel(zone)
	return 1 + (zone - 1) * 3
end

------------------------------------------------------------
-- 전투력: 머리 위 이름표 / 리더보드에 표시되어 강함을 과시할 수 있다
------------------------------------------------------------
function Config.GetPower(weaponLevel, critPoints, speedPoints, gearHealth, gearCrit, typeKey, level, gearDamage)
	local P = Config.Player
	level = level or 1
	local weaponType = Config.WeaponTypes[typeKey or "Pistol"] or Config.WeaponTypes.Pistol
	local pellets = weaponType.Pellets > 1 and weaponType.Pellets * 0.6 or 1
	local typeFactor = weaponType.DamageMult * pellets / weaponType.Cooldown
	local damage = P.BaseDamage * Config.GetDamageMultiplier(weaponLevel) * Config.GetLevelDamageMult(level) * (1 + (gearDamage or 0))
	local crit = math.min(0.9, (critPoints or 0) * P.CritPerPoint + (gearCrit or 0) + (weaponType.CritBonus or 0))
	local rate = 1 / (P.BaseCooldown / (1 + (speedPoints or 0) * P.SpeedPerPoint))
	local dps = damage * (1 + crit * (P.CritMultiplier - 1)) * rate * typeFactor
	return math.floor(dps * 10 + ((gearHealth or 0) + Config.GetLevelHealth(level)) * 0.5)
end

------------------------------------------------------------
-- 무기 종류: 각각 강화 레벨이 따로 있고, 골드로 구매하면 로비에서 바꿔 들 수 있다
--   DamageMult: 한 발 데미지 배율 / Cooldown: 공격 간격 배율 / Pellets: 한 번에 나가는 탄 수 / Spread: 퍼짐(도)
--   Range: 사거리 / CritBonus: 치명타 확률 추가 / ShotScale, SpeedScale: 발사체 크기 / 속도 배율
------------------------------------------------------------
Config.WeaponTypes = {
	Order = { "Pistol", "Shotgun", "Sniper" },
	Pistol = {
		Name = "권총", UnlockCost = 0, DamageMult = 1, Cooldown = 1, Range = 300, Pellets = 1, Spread = 0,
		ShotScale = 1, SpeedScale = 1, BarrelLength = 1, BarrelThickness = 1,
		Desc = "균형 잡힌 기본 무기",
	},
	Shotgun = {
		Name = "샷건", UnlockCost = 2500, DamageMult = 0.5, Cooldown = 1.6, Range = 90, Pellets = 6, Spread = 9,
		ShotScale = 0.55, SpeedScale = 1, BarrelLength = 0.75, BarrelThickness = 1.5,
		Desc = "근거리에서 6발이 퍼져 나가는 산탄 (사거리 90)",
	},
	Sniper = {
		Name = "저격총", UnlockCost = 5000, DamageMult = 4, Cooldown = 3, Range = 600, Pellets = 1, Spread = 0,
		ShotScale = 1.4, SpeedScale = 2.4, CritBonus = 0.25, BarrelLength = 1.9, BarrelThickness = 0.7,
		Desc = "느리지만 한 방이 강력, 치명타 +25%, 사거리 600",
	},
}

function Config.GetPlayerWeapon(player)
	return Config.WeaponTypes[player:GetAttribute("WeaponType") or "Pistol"] or Config.WeaponTypes.Pistol
end

-- 무기 종류 + 강화 레벨에 따른 이름. 예: "황금 저격총"
function Config.GetWeaponName(typeKey, level)
	local weaponType = Config.WeaponTypes[typeKey] or Config.WeaponTypes.Pistol
	return Config.GetWeaponTier(level).Prefix .. " " .. weaponType.Name
end

------------------------------------------------------------
-- 던전 종류 / 난이도 (던전 게이트에서 파티장이 고른다)
------------------------------------------------------------
Config.Dungeon.Difficulties = {
	Order = { "Easy", "Normal", "Hard" },
	Easy = { Name = "쉬움", HealthMult = 0.7, DamageMult = 0.7, GoldMult = 0.8, Tickets = 2, KeyCost = 1, LevelOffset = -2, Color = Color3.fromRGB(120, 220, 130) },
	Normal = { Name = "보통", HealthMult = 1, DamageMult = 1, GoldMult = 1, Tickets = 3, KeyCost = 1, LevelOffset = 0, Color = Color3.fromRGB(255, 220, 110) },
	Hard = { Name = "어려움", HealthMult = 1.8, DamageMult = 1.5, GoldMult = 2, Tickets = 5, KeyCost = 2, LevelOffset = 4, Color = Color3.fromRGB(255, 100, 100) },
}

-- Boss.Weights: 보스 패턴 비중 (Fan 부채꼴 / Ring 전방위 / Spiral 나선 / Meteor 메테오)
Config.Dungeon.Types = {
	Order = { "Cave", "Ice", "Fire" },
	Cave = {
		Name = "고블린 동굴", Desc = "어둡고 좁은 동굴. 입문용 던전", Waves = 5, LevelOffset = 0, GoldMult = 1, RecommendedPower = 0,
		MonsterColor = Color3.fromRGB(110, 160, 70),
		Floor = { Color = Color3.fromRGB(70, 60, 50), Material = Enum.Material.Slate },
		Wall = { Color = Color3.fromRGB(55, 45, 40), Material = Enum.Material.Brick },
		Torch = Color3.fromRGB(255, 150, 70),
		MonsterPool = { Slime = 4, Spitter = 3, Bat = 3 },
		Boss = { Name = "고블린 왕", Color = Color3.fromRGB(70, 130, 50), HealthMult = 1, DamageMult = 1, Weights = { Fan = 3, Ring = 2, Spiral = 1, Meteor = 2 } },
	},
	Ice = {
		Name = "얼음 성채", Desc = "얼어붙은 성. 나선 탄막이 매서운 중급 던전", Waves = 6, LevelOffset = 6, GoldMult = 1.6, RecommendedPower = 400,
		MonsterColor = Color3.fromRGB(110, 200, 240),
		Floor = { Color = Color3.fromRGB(190, 220, 240), Material = Enum.Material.Ice },
		Wall = { Color = Color3.fromRGB(120, 160, 200), Material = Enum.Material.Glacier },
		Torch = Color3.fromRGB(120, 200, 255),
		MonsterPool = { Slime = 2, Spitter = 2, Mage = 3, Golem = 2 },
		Boss = { Name = "서리 군주", Color = Color3.fromRGB(90, 170, 240), HealthMult = 1.6, DamageMult = 1.2, Weights = { Fan = 1, Ring = 3, Spiral = 3, Meteor = 1 } },
	},
	Fire = {
		Name = "화염 신전", Desc = "용암의 신전. 메테오가 쏟아지는 고급 던전", Waves = 7, LevelOffset = 12, GoldMult = 2.5, RecommendedPower = 1200,
		MonsterColor = Color3.fromRGB(240, 100, 50),
		Floor = { Color = Color3.fromRGB(60, 35, 35), Material = Enum.Material.Basalt },
		Wall = { Color = Color3.fromRGB(90, 40, 30), Material = Enum.Material.CrackedLava },
		Torch = Color3.fromRGB(255, 90, 40),
		MonsterPool = { Charger = 3, Bomber = 3, Mage = 2, Golem = 2 },
		Boss = { Name = "화염의 군주", Color = Color3.fromRGB(230, 70, 30), HealthMult = 2.4, DamageMult = 1.5, Weights = { Fan = 1, Ring = 1, Spiral = 2, Meteor = 4 } },
	},
}

------------------------------------------------------------
-- 일일 퀘스트 / 업적 / 칭호
--   Stat 은 카운터(DummyHits, FieldKills, EliteKills, Kills, BossKills, DungeonClears, Enhances, Rolls)
--   또는 현재 값(MaxZone, WeaponLevel, BestRarity, Power)
--   업적을 달성하면 Title(칭호)이 열리고 이름표에 달 수 있다
------------------------------------------------------------
Config.Quests = {
	DailyCount = 4,   -- 하루에 나오는 퀘스트 수 (아래 Pool 에서 날짜마다 무작위 선택)
	Pool = {
		{ Id = "dummy",   Name = "허수아비 연습", Desc = "허수아비를 %d번 때리기",       Stat = "DummyHits",     Goal = 300, Reward = { Gold = 300 } },
		{ Id = "field",   Name = "필드 사냥",     Desc = "필드 몬스터 %d마리 처치",       Stat = "FieldKills",    Goal = 30,  Reward = { Gold = 400, TimeSkip = 300 } },
		{ Id = "elite",   Name = "엘리트 사냥꾼", Desc = "엘리트 몬스터 %d마리 처치",     Stat = "EliteKills",    Goal = 3,   Reward = { Tickets = 1 } },
		{ Id = "dungeon", Name = "던전 도전",     Desc = "던전 %d번 클리어",              Stat = "DungeonClears", Goal = 1,   Reward = { Gold = 600, Tickets = 1, TimeSkip = 600 } },
		{ Id = "boss",    Name = "보스 사냥",     Desc = "보스 %d마리 처치",              Stat = "BossKills",     Goal = 1,   Reward = { Tickets = 2 } },
		{ Id = "enhance", Name = "대장장이",      Desc = "강화에 %d번 성공하기",          Stat = "Enhances",      Goal = 3,   Reward = { Gold = 500 } },
		{ Id = "gacha",   Name = "운 시험",       Desc = "장비 뽑기를 %d번 하기",         Stat = "Rolls",         Goal = 2,   Reward = { Gold = 300 } },
		{ Id = "kills",   Name = "몬스터 청소",   Desc = "몬스터 %d마리 처치 (던전 포함)", Stat = "Kills",         Goal = 60,  Reward = { Gold = 500, TimeSkip = 300 } },
	},
}

Config.Achievements = {
	{ Id = "dummy100",   Name = "초보 사수",       Desc = "허수아비 %d회 타격",          Stat = "DummyHits",     Goal = 100,   Reward = { Gold = 200 },               Title = "초보 사수" },
	{ Id = "dummy2000",  Name = "허수아비 학살자", Desc = "허수아비 %d회 타격",          Stat = "DummyHits",     Goal = 2000,  Reward = { Gold = 1500 },              Title = "허수아비 학살자" },
	{ Id = "kills500",   Name = "사냥꾼",          Desc = "몬스터 %d마리 처치",          Stat = "Kills",         Goal = 500,   Reward = { Gold = 1500 },              Title = "사냥꾼" },
	{ Id = "dungeon1",   Name = "첫 던전",         Desc = "던전 %d회 클리어",            Stat = "DungeonClears", Goal = 1,     Reward = { Gold = 500, Tickets = 1 },  Title = "던전 입문자" },
	{ Id = "dungeon10",  Name = "던전 단골",       Desc = "던전 %d회 클리어",            Stat = "DungeonClears", Goal = 10,    Reward = { Tickets = 3 },              Title = "던전 단골" },
	{ Id = "dungeon50",  Name = "던전 마스터",     Desc = "던전 %d회 클리어",            Stat = "DungeonClears", Goal = 50,    Reward = { Tickets = 10 },             Title = "던전 마스터" },
	{ Id = "boss10",     Name = "보스 헌터",       Desc = "보스 %d마리 처치",            Stat = "BossKills",     Goal = 10,    Reward = { Tickets = 5 },              Title = "보스 헌터" },
	{ Id = "zone4",      Name = "탐험가",          Desc = "필드 %d구역 돌파",            Stat = "MaxZone",       Goal = 4,     Reward = { Gold = 1000 },              Title = "탐험가" },
	{ Id = "zone8",      Name = "심연의 정복자",   Desc = "필드 %d구역 돌파",            Stat = "MaxZone",       Goal = 8,     Reward = { Tickets = 5 },              Title = "심연의 정복자" },
	{ Id = "weapon10",   Name = "강화의 달인",     Desc = "무기 +%d 달성",               Stat = "WeaponLevel",   Goal = 10,    Reward = { Gold = 2000 },              Title = "강화의 달인" },
	{ Id = "weapon15",   Name = "전설의 대장장이", Desc = "무기 +%d 달성",               Stat = "WeaponLevel",   Goal = 15,    Reward = { Tickets = 5 },              Title = "전설의 대장장이" },
	{ Id = "legend",     Name = "행운아",          Desc = "전설 등급 장비 획득",         Stat = "BestRarity",    Goal = 4,     Reward = { Tickets = 3 },              Title = "행운아" },
	{ Id = "myth",       Name = "신화의 주인",     Desc = "신화 등급 장비 획득",         Stat = "BestRarity",    Goal = 5,     Reward = { Tickets = 8 },              Title = "신화의 주인" },
	{ Id = "level10",    Name = "성장하는 모험가", Desc = "캐릭터 레벨 %d 달성",         Stat = "Level",         Goal = 10,    Reward = { Gold = 1000 },              Title = "모험가" },
	{ Id = "level25",    Name = "숙련된 전사",     Desc = "캐릭터 레벨 %d 달성",         Stat = "Level",         Goal = 25,    Reward = { Tickets = 3 },              Title = "숙련자" },
	{ Id = "level50",    Name = "전설의 용사",     Desc = "캐릭터 레벨 %d 달성",         Stat = "Level",         Goal = 50,    Reward = { Tickets = 10 },             Title = "전설의 용사" },
	{ Id = "power1000",  Name = "강자",            Desc = "전투력 %d 달성",              Stat = "Power",         Goal = 1000,  Reward = { Gold = 1500 },              Title = "강자" },
	{ Id = "power10000", Name = "초월자",          Desc = "전투력 %d 달성",              Stat = "Power",         Goal = 10000, Reward = { Tickets = 10 },             Title = "초월자" },
}

------------------------------------------------------------
-- 캐릭터 레벨: 몬스터를 잡으면 경험치(XP). 레벨이 오르면 최대 체력과 공격력이 늘고 체력이 가득 찬다.
------------------------------------------------------------
Config.Level = {
	Max = 50,
	HealthPerLevel = 8,     -- 레벨당 최대 체력 +8
	DamagePerLevel = 0.03,  -- 레벨당 공격력 +3%
}

Config.Xp = {
	FieldPerMonsterLevel = 4,    -- 필드 일반 몬스터: 몬스터 레벨 x 4
	DungeonPerMonsterLevel = 3,  -- 던전 몬스터: 몬스터 레벨 x 3 (던전 종류/난이도 배율이 곱해짐)
	EliteMult = 4,               -- 엘리트는 x4
	FieldBoss = 600,
	DungeonBoss = 400,
	WaveClear = 25,              -- 웨이브 클리어: 25 x 웨이브 번호
	DungeonClear = 150,
}

-- level -> level+1 에 필요한 XP
function Config.GetXpNeeded(level)
	return math.floor(50 * level ^ 1.75)
end

function Config.GetLevelDamageMult(level)
	return 1 + Config.Level.DamagePerLevel * (level - 1)
end

function Config.GetLevelHealth(level)
	return (level - 1) * Config.Level.HealthPerLevel
end

------------------------------------------------------------
-- 장비 아이템 / 가방
--   장비 하나하나가 부위(Slot) + 등급(Rarity 1~5) + 강화 레벨 + 랜덤 옵션(Affixes)을 가진다.
--   필드/던전에서 드롭 -> 가방 -> 장착. 필요 없는 건 분해해서 에센스(재굴림 재료)와 골드로.
------------------------------------------------------------
Config.Inventory = {
	BaseSlots = 30,
	MaxSlots = 150,
	ScrapEssence = { 1, 3, 8, 20, 60 },          -- 등급별 분해 시 에센스
	ScrapGold = { 20, 60, 200, 800, 3000 },      -- 등급별 분해 시 골드
	RerollEssence = { 5, 12, 30, 80, 200 },      -- 등급별 옵션 재굴림 비용(에센스)
	AffixCount = { 0, 1, 2, 3, 4 },              -- 등급별 랜덤 옵션 개수
	AffixRarityScale = { 1, 1.3, 1.7, 2.2, 3.0 },-- 등급별 옵션 수치 배율
	AutoScrapNames = { [0] = "꺼짐", "일반 이하", "희귀 이하", "영웅 이하" },
	AffixOrder = { "Health", "Crit", "Speed", "Damage", "Xp", "Luck" },
	Affixes = {
		Health = { Name = "최대 체력", Base = 30 },
		Crit = { Name = "치명타 확률", Base = 0.012, Percent = true },
		Speed = { Name = "이동 속도", Base = 0.4 },
		Damage = { Name = "공격력", Base = 0.03, Percent = true },
		Xp = { Name = "경험치 획득", Base = 0.04, Percent = true },
		Luck = { Name = "행운 (드롭 등급)", Base = 0.05, Percent = true },
	},
}

function Config.FormatAffix(stat, value)
	local def = Config.Inventory.Affixes[stat]
	if def.Percent then
		return string.format("%s +%.1f%%", def.Name, value * 100)
	elseif stat == "Health" then
		return string.format("%s +%d", def.Name, math.floor(value + 0.5))
	end
	return string.format("%s +%.1f", def.Name, value)
end

-- 아이템 점수: 기본 효과(등급 x 강화) + 옵션. 가방 정렬 / 비교용
function Config.GetItemScore(item)
	local score = Config.Gear.RarityMult[item.Rarity] * 100 * (1 + Config.Gear.LevelBonus * item.Level)
	for _, affix in ipairs(item.Affixes or {}) do
		local def = Config.Inventory.Affixes[affix.Stat]
		if def then
			score += affix.Value / def.Base * 12
		end
	end
	return math.floor(score)
end

------------------------------------------------------------
-- 전리품: 필드에서 몬스터가 아이템을 떨어뜨린다 (구역이 깊을수록 높은 등급).
-- 던전 열쇠가 없어도 필드에서 충분히 성장할 수 있게 설계 - 던전은 "더 빠른 지름길 + 더 좋은 상자".
------------------------------------------------------------
Config.Loot = {
	PickupRadius = 12,
	DropLifetime = 90,
	DropChance = { Normal = 0.07, Elite = 0.45, Boss = 1, Event = 1 },
	Counts = { Boss = 3, Event = 3 },
	EliteBonus = 1.6,    -- 엘리트: 영웅 이상 가중치 x1.6
	BossBonus = 3,       -- 보스 / 이벤트: x3
	-- 구역별 등급 가중치 (일반, 희귀, 영웅, 전설, 신화)
	ZoneRarity = {
		{ 80, 18, 2, 0, 0 },
		{ 68, 25, 6.5, 0.5, 0 },
		{ 55, 30, 13, 2, 0 },
		{ 45, 33, 18, 4, 0 },
		{ 36, 34, 22, 7.5, 0.5 },
		{ 28, 33, 26, 11.5, 1.5 },
		{ 20, 31, 30, 16, 3 },
		{ 14, 28, 32, 21, 5 },
	},
	-- 던전 보스 상자: 던전 종류별로 위 표의 어느 줄을 쓸지 (난이도에 따라 +-1)
	DungeonRarityRow = { Cave = 3, Ice = 5, Fire = 7 },
	DungeonDifficultyRow = { Easy = -1, Normal = 0, Hard = 1 },
	DungeonChestCount = 3,
}

------------------------------------------------------------
-- 던전 열쇠: 입장 제한. 시간이 지나면 자동으로 차오르니 숙제처럼 매일 접속할 필요가 없다.
------------------------------------------------------------
Config.Keys = {
	Start = 4,
	Max = 6,
	RegenSeconds = 900,   -- 15분마다 1개
}

------------------------------------------------------------
-- 필드 공개 이벤트: 일정 시간마다 어느 구역에 강력한 침공 보스가 나타난다 (모두에게 알림).
-- 같이 싸운 사람은 전리품을 받는다. 필드에서 만나서 함께 싸우는 재미 + 큰 보상.
------------------------------------------------------------
Config.Events = {
	FirstDelay = 90,
	MinInterval = 360,
	MaxInterval = 540,
	Lifetime = 420,
	ContribMin = 0.03,    -- 보스 체력의 3% 이상 피해를 준 사람이 보상 대상
	Name = "침공 사령관",
}

------------------------------------------------------------
-- BM(상점) 설계 - 원칙: "시간을 돈으로 산다". 모든 성장은 돈을 안 써도 시간만 들이면 도달할 수 있고,
--   돈은 그 시간(훈련소/돌파 대기, 열쇠, 부스터)을 줄여준다. 그래서 전투력 성장 속도에도 영향이 있다.
--   PvE 전용이라 다른 플레이어를 해치지 않고, 꾸미기(오라)는 능력치가 없다.
--   ProductId / PassId 를 0 에서 실제 Roblox ID 로 바꾸면 그때부터 판매가 활성화된다. (0 이면 "준비 중")
--   Studio 에서 플레이 테스트할 때는 ID 가 0 이어도 [테스트 지급]으로 효과를 확인할 수 있다.
--   Grant 키: Keys(열쇠) Tickets(뽑기 티켓) XpBoost / LuckBoost(초 단위) Bag(가방 칸) Aura(꾸미기 해금)
------------------------------------------------------------
Config.Shop = {
	Passes = {
		VIP = {
			Name = "VIP 패스", Desc = "경험치 +20% · 훈련 슬롯 +1 · 훈련/돌파 시간 -20% · 열쇠 보관 +2 · 열쇠 회복 30% 빠르게 · 가방 +20칸 · 황금 오라",
			PassId = 0,
		},
	},
	Products = {
		KeyPack = { Name = "던전 열쇠 5개", Desc = "던전을 더 많이 돌고 싶을 때", ProductId = 0, Grant = { Keys = 5 } },
		XpBooster = { Name = "경험치 부스터 (1시간)", Desc = "경험치 2배", ProductId = 0, Grant = { XpBoost = 3600 } },
		LuckBooster = { Name = "행운 부스터 (1시간)", Desc = "장비 드롭 등급 +50%", ProductId = 0, Grant = { LuckBoost = 3600 } },
		BagPlus = { Name = "가방 확장 +10칸", Desc = "영구 적용", ProductId = 0, Grant = { Bag = 10 } },
		TicketPack = { Name = "장비 뽑기 티켓 5장", Desc = "티켓으로 장비를 뽑아요", ProductId = 0, Grant = { Tickets = 5 } },
		TimeSkip1h = { Name = "시간 단축권 1시간", Desc = "훈련 / 돌파 대기 시간을 1시간 줄여요", ProductId = 0, Grant = { TimeSkip = 3600 } },
		TimeSkip8h = { Name = "시간 단축권 8시간", Desc = "훈련 / 돌파 대기 시간을 8시간 줄여요", ProductId = 0, Grant = { TimeSkip = 28800 } },
		TrainSlot = { Name = "훈련 슬롯 +1", Desc = "영구 적용 · 동시에 하나 더 훈련", ProductId = 0, Grant = { TrainSlot = 1 } },
		AuraVoid = { Name = "공허의 오라", Desc = "꾸미기 전용 (능력치 없음)", ProductId = 0, Grant = { Aura = "Void" } },
	},
	PassOrder = { "VIP" },
	ProductOrder = { "TimeSkip1h", "TimeSkip8h", "TrainSlot", "KeyPack", "XpBooster", "LuckBooster", "BagPlus", "TicketPack", "AuraVoid" },
	-- VIP 효과 (코드에서 읽는 값). TrainTime: 훈련/돌파 시간 단축 비율
	Vip = { XpBonus = 0.2, KeyCap = 2, KeyRegen = 0.3, Bag = 20, TrainSlots = 1, TrainTime = 0.2 },
	XpBoostMult = 2,
	LuckBoostBonus = 0.5,
}

-- 오라: 캐릭터 주변에 반짝이는 꾸미기 (다른 플레이어에게도 보임). 능력치 없음.
-- Unlock: Free / { Ach = 업적Id } / { Pass = 패스이름 } / { Product = 상품이름 }
Config.Auras = {
	Order = { "Spark", "Frost", "Flame", "Gold", "Void" },
	Spark = { Name = "반짝이 오라", Color = Color3.fromRGB(255, 255, 255), Unlock = "Free" },
	Frost = { Name = "서리 오라", Color = Color3.fromRGB(130, 210, 255), Unlock = { Ach = "zone4" } },
	Flame = { Name = "불꽃 오라", Color = Color3.fromRGB(255, 110, 50), Unlock = { Ach = "boss10" } },
	Gold = { Name = "황금 오라", Color = Color3.fromRGB(255, 215, 90), Unlock = { Pass = "VIP" } },
	Void = { Name = "공허의 오라", Color = Color3.fromRGB(170, 70, 255), Unlock = { Product = "AuraVoid" } },
}

------------------------------------------------------------
-- 성장 (시간이 걸리는 영구 성장) - 훈련소 + 돌파
--   * 훈련소: 공격 / 체력 / 치명타 / 이속을 영구적으로 키운다. 단계마다 실제 시간이 걸리고 슬롯 수만큼 동시에 훈련.
--   * 돌파: 레벨이 Gates 에 도달하면 더 오르려면 돌파(시간 + 골드)를 거쳐야 한다.
--   * 시간 단축권(TimeSkip): 위 두 가지의 남은 시간을 줄인다. 퀘스트로 조금씩 무료로 얻고, 상점에서도 판다 (BM).
--   -> 돈을 안 써도 시간만 들이면 모두 도달 가능. 돈은 시간만 줄여준다.
------------------------------------------------------------
Config.Growth = {
	BaseSlots = 1,
	MaxLevel = 30,
	TimeBase = 120,     -- 0 -> 1 단계 훈련 시간(초)
	TimeGrowth = 1.22,  -- 단계마다 시간이 1.22배 (30단계에서 약 10시간)
	GoldBase = 300,
	GoldGrowth = 1.3,
	Stats = {
		Order = { "Attack", "Health", "Crit", "Speed" },
		Attack = { Name = "공격 단련", Icon = "⚔", Per = 0.02 },
		Health = { Name = "체력 단련", Icon = "❤", Per = 12 },
		Crit = { Name = "치명 단련", Icon = "🎯", Per = 0.004 },
		Speed = { Name = "신속 단련", Icon = "💨", Per = 0.12 },
	},
	Gates = { 10, 20, 30, 40 },            -- 이 레벨에서 멈추고 돌파가 필요
	GateTime = { 1800, 7200, 21600, 43200 }, -- 돌파 시간(초): 30분 / 2시간 / 6시간 / 12시간
	GateGold = { 2000, 10000, 50000, 200000 },
}

function Config.GetTrainTime(level)
	return math.floor(Config.Growth.TimeBase * Config.Growth.TimeGrowth ^ level)
end

function Config.GetTrainGold(level)
	return math.floor(Config.Growth.GoldBase * Config.Growth.GoldGrowth ^ level)
end

function Config.FormatTrainEffect(stat, level)
	local def = Config.Growth.Stats[stat]
	local value = def.Per * level
	if stat == "Attack" then
		return string.format("공격력 +%.0f%%", value * 100)
	elseif stat == "Health" then
		return string.format("최대 체력 +%d", math.floor(value + 0.5))
	elseif stat == "Crit" then
		return string.format("치명타 확률 +%.1f%%", value * 100)
	end
	return string.format("이동 속도 +%.1f", value)
end

-- 돌파를 몇 번째까지 마쳤는지(gatePassed = 마친 돌파 레벨, 0이면 없음)에 따라 지금 오를 수 있는 최대 레벨
function Config.GetLevelCap(gatePassed)
	for _, gate in ipairs(Config.Growth.Gates) do
		if gate > gatePassed then
			return gate
		end
	end
	return Config.Level.Max
end

-- 남은 시간(초)을 "2시간 05분" 처럼 보기 좋게
function Config.FormatDuration(seconds)
	seconds = math.max(0, math.floor(seconds))
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	local secs = seconds % 60
	if hours > 0 then
		return string.format("%d시간 %02d분", hours, minutes)
	elseif minutes > 0 then
		return string.format("%d분 %02d초", minutes, secs)
	end
	return string.format("%d초", secs)
end

function Config.GetWeaponTier(level)
	local tiers = Config.Weapon.Tiers
	for i = #tiers, 1, -1 do
		if level >= tiers[i].MinLevel then
			return tiers[i]
		end
	end
	return tiers[1]
end

-- level -> level+1 강화 비용
function Config.GetEnhanceCost(level)
	return math.floor(Config.Weapon.BaseCost * Config.Weapon.CostGrowth ^ level)
end

-- level -> level+1 강화 성공 확률 (실패해도 레벨은 내려가지 않고 골드만 소모)
function Config.GetEnhanceChance(level)
	return math.max(0.4, 1 - 0.04 * level)
end

function Config.GetDamageMultiplier(level)
	return 1 + Config.Weapon.DamagePerLevel * level
end

function Config.GetWeaponScale(level)
	return 1 + Config.Weapon.SizePerLevel * level
end

return Config
