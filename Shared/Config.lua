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
	ArenaOrigin = Vector3.new(3000, 0, 0), -- 던전 아레나는 로비에서 멀리 떨어진 곳에 만들어짐
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
		{ MinLevel = 0,  Name = "낡은 권총",       Color = Color3.fromRGB(165, 165, 175), Material = Enum.Material.Metal, Particles = 0,  Trail = false, Light = 0,
			Shot = { Style = "Ball", Size = 0.6, Speed = 260, Impact = 0 } },
		{ MinLevel = 3,  Name = "강철 권총",       Color = Color3.fromRGB(90, 160, 255),  Material = Enum.Material.Metal, Particles = 6,  Trail = false, Light = 0,
			Shot = { Style = "Bolt", Size = 0.35, Length = 3, Speed = 320, Impact = 6 } },
		{ MinLevel = 6,  Name = "마력 라이플",     Color = Color3.fromRGB(175, 95, 255),  Material = Enum.Material.Glass, Particles = 12, Trail = true,  Light = 0,
			Shot = { Style = "Orb", Size = 1.3, Speed = 190, Impact = 14 } },
		{ MinLevel = 9,  Name = "황금 캐논",       Color = Color3.fromRGB(255, 200, 50),  Material = Enum.Material.Neon,  Particles = 22, Trail = true,  Light = 10,
			Shot = { Style = "Cannon", Size = 2.4, Speed = 140, Impact = 30 } },
		{ MinLevel = 12, Name = "불꽃의 건",       Color = Color3.fromRGB(255, 70, 40),   Material = Enum.Material.Neon,  Particles = 40, Trail = true,  Light = 16,
			Shot = { Style = "Fire", Size = 2.0, Speed = 160, Impact = 40 } },
		{ MinLevel = 15, Name = "전설의 무지개 건", Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.Neon,  Particles = 60, Trail = true,  Light = 20, Rainbow = true,
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

Config.Audio = {
	MusicVolume = 0.4,
	Music = {
		Lobby = ids.Lobby or 0,      -- 로비 배경음악
		Dungeon = ids.Dungeon or 0,  -- 던전(웨이브) 배경음악
		Boss = ids.Boss or 0,        -- 보스전 배경음악
	},
	Shot = ids.Shot or 0,            -- 총 쏘는 소리 (무기가 강해질수록 낮고 묵직하게 재생됨)
	ShotVolume = 0.5,
	EnhanceSuccess = ids.EnhanceSuccess or 0, -- 강화 성공 소리
}

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
