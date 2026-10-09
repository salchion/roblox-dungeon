-- Config (ReplicatedStorage 안의 ModuleScript, 이름: Config)
-- 서버/클라이언트가 같이 쓰는 밸런스 값과 계산 함수. 숫자만 바꿔가며 조절하면 됨.

local Config = {}

Config.StartGold = 100 -- 처음 접속했을 때 지급되는 골드

------------------------------------------------------------
-- 플레이어 기본 능력치 / 스탯 포인트 효과
------------------------------------------------------------
Config.Player = {
	BaseHealth = 100,
	WalkSpeed = 19,
	RunSpeed = 32,          -- Shift를 누르고 있을 때
	DashSpeed = 135,        -- Q 대시 속도 (순간 폭발적으로 튀어 나감)
	DashTime = 0.24,        -- 대시 지속 시간(초): 짧고 굵게
	DashCooldown = 3.0,     -- 대시 1회 충전에 걸리는 시간(초) = 대시 쿨타임
	DashCharges = 2,        -- 연속으로 쓸 수 있는 횟수 (공중에서도 가능)
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
-- 스킬 강화 (골드) / 펫 (알 부화) / 무한의 탑 기록
------------------------------------------------------------
Config.SkillUpgrade = {
	MaxLevel = 10,
	BaseCost = 400,
	CostGrowth = 1.5,
	CooldownPerLevel = 0.025,   -- 레벨당 쿨타임 -2.5%
	-- 레벨당 증가량 (스킬마다 다름)
	BarrierDuration = 0.4,      -- 방벽 지속시간 +0.4초
	BlastMult = 0.18,           -- 충격파 피해 +18% (기본 대비)
	BlastRadius = 0.8,          -- 충격파 범위 +0.8
	HealRatio = 0.03,           -- 치료량 +3%p
	UltMult = 0.15,             -- 궁극기 피해 +15%
}
function Config.GetSkillUpgradeCost(level)
	return math.floor(Config.SkillUpgrade.BaseCost * Config.SkillUpgrade.CostGrowth ^ (level - 1))
end

-- 펫: 알을 골드로 부화 -> 같은 펫이 또 나오면 펫 레벨업(최대 5). 하나를 장착하면 따라다니며 능력치를 준다.
-- Stat: Damage(공격력) / Crit(치명타) / Xp(경험치) / Speed(이동속도) / Haste(스킬 쿨타임 감소)
Config.Pets = {
	EggCost = 4000,
	MaxLevel = 5,
	LevelBonus = 0.5,   -- 펫 레벨 1당 효과 +50% (기본 대비)
	RarityNames = { "일반", "희귀", "영웅", "전설" },
	RarityWeights = { 55, 30, 12, 3 },
	RarityColors = { Color3.fromRGB(190, 190, 200), Color3.fromRGB(90, 170, 255), Color3.fromRGB(190, 110, 255), Color3.fromRGB(255, 180, 50) },
	Order = { "Slimey", "Foxy", "Batty", "Rocky", "Sprite", "Dragon", "Phoenix", "Star" },
	Slimey = { Name = "말랑 슬라임", Rarity = 1, Color = Color3.fromRGB(110, 220, 120), Stat = "Xp", Value = 0.06 },
	Foxy = { Name = "꼬마 여우", Rarity = 1, Color = Color3.fromRGB(255, 160, 80), Stat = "Speed", Value = 1.5 },
	Batty = { Name = "박쥐 친구", Rarity = 2, Color = Color3.fromRGB(150, 110, 200), Stat = "Crit", Value = 0.03 },
	Rocky = { Name = "돌멩이 골렘", Rarity = 2, Color = Color3.fromRGB(150, 150, 160), Stat = "Damage", Value = 0.05 },
	Sprite = { Name = "빛의 정령", Rarity = 3, Color = Color3.fromRGB(150, 230, 255), Stat = "Haste", Value = 0.06 },
	Dragon = { Name = "아기 용", Rarity = 3, Color = Color3.fromRGB(255, 90, 70), Stat = "Damage", Value = 0.09 },
	Phoenix = { Name = "불사조", Rarity = 4, Color = Color3.fromRGB(255, 140, 40), Stat = "Crit", Value = 0.06 },
	Star = { Name = "별똥별 요정", Rarity = 4, Color = Color3.fromRGB(255, 240, 120), Stat = "Damage", Value = 0.14 },
}
function Config.GetPetValue(key, level)
	local pet = Config.Pets[key]
	return pet.Value * (1 + Config.Pets.LevelBonus * (level - 1))
end
function Config.FormatPetStat(key, level)
	local pet = Config.Pets[key]
	local value = Config.GetPetValue(key, level)
	local names = { Damage = "공격력", Crit = "치명타 확률", Xp = "경험치", Speed = "이동속도", Haste = "스킬 쿨타임 감소" }
	if pet.Stat == "Speed" then
		return string.format("%s +%.1f", names[pet.Stat], value)
	end
	return string.format("%s +%d%%", names[pet.Stat], math.floor(value * 100 + 0.5))
end

------------------------------------------------------------
-- 골든 타임: 주기적으로 짧은 시간 동안 경험치 / 골드 보너스 (서버 전체)
------------------------------------------------------------
Config.Golden = {
	FirstDelay = 420,    -- 서버 시작 후 첫 골든 타임까지 (초)
	Interval = 1500,     -- 골든 타임이 끝난 뒤 다음까지 (초)
	Duration = 300,      -- 지속 시간 (초)
	XpMult = 2,
	GoldMult = 1.5,
}
function Config.IsGoldenTime()
	return (workspace:GetAttribute("GoldenUntil") or 0) > os.time()
end

------------------------------------------------------------
-- 튜토리얼 미션 (처음 1~5분): 쉬운 목표 -> 즉시 보상을 계속 이어서 보여준다
-- Target: TutorialService.SetTargets 로 넘겨주는 위치 키 (Dummy / Anvil / Gacha / Field / Gate)
-- FreeEnhance: 이 미션 동안 무기 강화가 공짜 + 100% 성공
------------------------------------------------------------
Config.Tutorial = {
	Steps = {
		-- 첫 미션: 언덕 위에서 마을을 한 바퀴 둘러본다 (이동은 잠겨 있고 시점만 돌릴 수 있다). Goal = 10단계 (한 바퀴 ≈ 300°)
		{ Text = "👀 마을을 둘러보세요! 마우스 우클릭을 누른 채 돌리거나 ◀ ▶ 키로 시점을 한 바퀴 돌려보세요 (이동은 잠시 잠겨요)", Stat = "Look", Goal = 10, Look = true, MinSeconds = 26,
			-- 게임 소개 카드 (이동이 잠긴 동안 읽는다): 어떤 게임인지 / 조작 / 강해지는 길 / 방치
			Intro = {
				{ Key = "🎮", Title = "어서 와요!", Text = "몬스터를 쏴서 강해지고, 구역마다 있는 군주를 쓰러뜨려 가장 끝의 심연(구역 8)까지 나아가는 슈터 RPG예요", Duration = 6 },
				{ Key = "🖱", Title = "조작은 간단해요", Text = "마우스 클릭 = 조준 사격 · R = 자동 공격 · Q = 대시 · V = 궁극기. 하나씩 직접 해볼 거예요", Duration = 6 },
				{ Key = "📈", Title = "이렇게 강해져요", Text = "무기 강화 → 장비 뽑기 → 성장(훈련) → 던전 → 환생. 군주를 쓰러뜨릴 때마다 새 구역이 열려요", Duration = 6 },
				{ Key = "💤", Title = "방치로도 자라요", Text = "훈련은 접속하지 않아도 시간이 지나면 저절로 끝나고, 심연 도전은 한 번 해두면 소탕으로 매일 보상을 받아요", Duration = 6 },
			},
			Reward = { Gold = 50 } },
		{ Text = "마우스를 눌러 허수아비를 쏘세요! (R 키 = 자동 조준)", Stat = "DummyHits", Goal = 8, Target = "Dummy", TargetName = "허수아비",
			Reward = { Gold = 100 } },
		{ Text = "모루에서 무기를 강화하세요! (처음 3번은 무료)", Stat = "Enhances", Goal = 1, Target = "Anvil", TargetName = "모루", FreeEnhance = true,
			Reward = { Gold = 50 } },
		{ Text = "계속 강화해보세요! 강화할수록 총이 변해요 (권총은 10번 강화하면 다음 무기로 진화)", Stat = "Enhances", Goal = 2, Target = "Anvil", TargetName = "모루", FreeEnhance = true,
			Reward = { Tickets = 1, Gold = 100 } },
		{ Text = "뽑기 머신에서 장비를 뽑아보세요! (티켓 1장)", Stat = "Rolls", Goal = 1, Target = "Gacha", TargetName = "뽑기 머신", RollMode = "Lowest",
			Reward = { Gold = 300 } },
		-- 이야기: 필드는 아직 너무 강하다 -> 쓰러져서 마을로 -> 성장(훈련) -> 던전에서 장비 -> 10연 뽑기 -> 다시 필드는 쉽다
		{ Text = "동쪽 필드로 나가서 첫 구역의 군주(👑)를 쓰러뜨리세요! ...어딘가 불길한 기운이 느껴져요. 무슨 일이 일어날지도 몰라요. 조심하세요!", Stat = "FieldDeaths", Goal = 1, Target = "Field", TargetName = "필드 입구", Doom = true,
			Reward = { Gold = 300, Keys = 1, Xp = 100 } },
		{ Text = "아직 너무 약해요! 메뉴(I) → 성장 탭에서 훈련을 시작하세요. 훈련하면 영구적으로 강해져요", Stat = "Trains", Goal = 1, Highlight = "Menu",
			-- 완료한 뒤 차례로: 방치(시간으로 자라는 것)가 무엇인지 알려준다
			Outro = {
				{ Key = "⏱", Title = "훈련은 저절로 끝나요", Text = "방금 시작한 훈련은 시간이 지나면 저절로 끝나요. 게임을 꺼 둬도 시간은 흘러요", Duration = 7 },
				{ Key = "🎫", Title = "시간 단축권", Text = "퀘스트나 상점에서 얻는 시간 단축권을 쓰면 바로 끝낼 수 있어요. 슬롯이 비면 또 훈련을 걸어 두세요", Duration = 7 },
			},
			Reward = { Gold = 400, Xp = 100 } },
		{ Text = "북쪽 던전 게이트에서 던전에 들어가 웨이브를 2번 막아내세요! (열쇠 1개, 달성 후 던전에서 나오면 티켓 10장 보상!)", Stat = "DungeonWaves", Goal = 2, Target = "Gate", TargetName = "던전 게이트", AfterDungeon = true,
			-- 던전을 처음 소개하는 안내 카드 (이 미션이 시작될 때 차례로 한 번): 성장을 배운 직후 "장비를 얻는 곳"으로 던전을 알려준다
			Intro = {
				{ Key = "🏰", Title = "던전이란?", Text = "북쪽 성벽의 문으로 들어가는 전투 공간이에요. 웨이브를 막아내고 보스를 쓰러뜨리면 장비 티켓과 보스 상자(장비)를 얻어요", Duration = 8 },
				{ Key = "🎟", Title = "하루 무료 입장 3번", Text = "던전은 하루에 3번까지 무료로 들어갈 수 있어요. 매일 초기화돼요", Duration = 7 },
				{ Key = "🗝", Title = "더 들어가고 싶다면?", Text = "무료 입장을 다 쓰면 열쇠가 필요해요. 열쇠는 필드 구역 군주(👑)를 쓰러뜨리면 낮은 확률로 나와요", Duration = 8 },
				{ Key = "🚪", Title = "문마다 난이도가 달라요", Text = "오른쪽 문일수록 강하고 보상이 커요. 문이 더 크고 어둡고 불길이 거세져요. 지금은 맨 왼쪽 문부터 시작해요!", Duration = 8 },
			},
			Reward = { Tickets = 10, Gold = 600, Xp = 200 } },
		{ Text = "🎰 뽑기 머신에서 10연 뽑기를 하세요! (티켓 10장) — 장비가 한꺼번에 강해져요", Stat = "Rolls", Goal = 10, Target = "Gacha", TargetName = "뽑기 머신", RollMode = "Hero",
			Reward = { Gold = 500 } },
		-- EvolveToTier: 이 번째 무기(3 = 기관단총)가 될 때까지 필요한 강화 횟수를 미션이 시작될 때 계산해서 목표로 쓴다. {무기} = 그 무기 이름
		{ Text = "💰 던전에서 모은 골드로 무기를 강화해서 {무기}까지 진화시키세요! 연사가 확 달라져서 필드가 쉬워져요", Stat = "Enhances", Goal = 10, EvolveToTier = 3, Target = "Anvil", TargetName = "모루",
			Reward = { Tickets = 2, Xp = 150 } },
		{ Text = "이제 다시 필드로! 강해진 힘으로 몬스터 15마리를 처치하세요", Stat = "Kills", Goal = 15, Target = "Field", TargetName = "필드 입구",
			Outro = {
				{ Key = "🎉", Title = "튜토리얼 끝!", Text = "이제 직접 키워 봐요. 앞으로는 군주를 쓰러뜨려 다음 구역을 열고, 장비와 무기를 키워서 더 깊은 구역으로 가요", Duration = 8 },
				{ Key = "📅", Title = "매일 할 일", Text = "🌀 동쪽 광장 분홍 포탈에서 심연 도전(소탕) · 🏰 던전 무료 입장 3번 · 📋 일일 퀘스트 (메뉴 I)", Duration = 8 },
				{ Key = "💤", Title = "방치 요소", Text = "⏱ 훈련 슬롯을 항상 채워 두기 · ⚡ 심연 소탕은 내 최고 점수가 기준! 직접 점수를 올릴수록 방치 보상이 커져요", Duration = 8 },
				{ Key = "🌟", Title = "먼 목표", Text = "구역 8 심연의 군주 → 최고 레벨 → 환생(영구 공격력 + 골드 획득량). 이제 마음껏 즐겨요!", Duration = 8 },
			},
			Reward = { Gold = 1000, Keys = 1, Tickets = 2, Xp = 300 } },
	},
}

------------------------------------------------------------
-- 환생(프레스티지): 최고 레벨에서 레벨을 1로 되돌리고 영구 공격력 보너스를 얻는다
------------------------------------------------------------
-- 환생: 최고 레벨에서 레벨을 1로 되돌리는 대신 영구 보너스. 골드를 더 벌려면 환생한다 (영구 공격력 + 골드 획득량).
Config.Prestige = { Max = 10, DamagePerRank = 0.05, GoldPerRank = 0.10 }
function Config.GoldBonus(player)
	return 1 + (player:GetAttribute("Prestige") or 0) * Config.Prestige.GoldPerRank
end

Config.Dungeon = {} -- 아래에서 여러 블록이 채우고, "던전" 절에서 기본 값이 합쳐진다

------------------------------------------------------------
-- 연속 처치 콤보 / 출석 보상 / 던전 변이(매번 달라지는 규칙)
------------------------------------------------------------
Config.Combo = {
	Window = 4,           -- 다음 처치까지 허용 시간(초)
	DamagePerStack = 0.01,
	MaxStacks = 50,       -- 최대 +50% 공격력
	UltPerKill = 4,       -- 처치마다 궁극기 게이지
}

Config.Daily = {
	Rewards = { -- 연속 출석 1~7일차 (이후 반복)
		{ Gold = 300 },
		{ Gold = 500, Keys = 1 },
		{ Gold = 800, Tickets = 1 },
		{ Gold = 1200, Keys = 1 },
		{ Gold = 1800, Tickets = 1 },
		{ Gold = 2500, Keys = 2 },
		{ Gold = 5000, Tickets = 3, Keys = 2 },
	},
}

-- 던전마다 확률로 붙는 변이: 위험이 커지면 보상도 커진다
Config.Dungeon.MutatorChance = 0.65
Config.Dungeon.Mutators = {
	Order = { "Giant", "Swift", "Swarm", "Golden", "Furious" },
	Giant = { Name = "거대화", Icon = "🗿", Desc = "몬스터 체력 x1.6, 보상 x1.5", HealthMult = 1.6, GoldMult = 1.5 },
	Swift = { Name = "신속", Icon = "💨", Desc = "몬스터 이동/공격이 빠름, 보상 x1.3", SpeedMult = 1.5, IntervalMult = 0.7, GoldMult = 1.3 },
	Swarm = { Name = "떼거지", Icon = "🐀", Desc = "몬스터 수 x1.6 (체력 x0.7), 보상 x1.4", CountMult = 1.6, HealthMult = 0.7, GoldMult = 1.4 },
	Golden = { Name = "황금의 날", Icon = "💰", Desc = "골드/경험치 x2, 몬스터 체력 x1.2", HealthMult = 1.2, GoldMult = 2 },
	Furious = { Name = "광폭", Icon = "😡", Desc = "몬스터 공격력 x1.5, 보상 x1.5", DamageMult = 1.5, GoldMult = 1.5 },
}

------------------------------------------------------------
-- 액티브 스킬 (오버워치 느낌): 필드 / 던전에서 사용. Z 방벽 · F 충격파 · C 응급 치료 · V 궁극기(게이지)
-- 스킬 데미지 = 일반 공격 데미지 x Mult. 궁극기는 공격할수록(발사 1회 = +ChargePerShot) 게이지가 찬다.
------------------------------------------------------------
Config.Skills = {
	Order = { "Heal", "Ult" }, -- 방벽 / 충격파는 임팩트가 약해서 뺐다 (정의만 남겨둠)
	Barrier = { Name = "에너지 방벽", Icon = "🛡", Key = "Z", KeyCode = "Z", Cooldown = 14, Duration = 3,
		Desc = "3초 동안 모든 피해를 막는 방벽" },
	Blast = { Name = "충격파", Icon = "💥", Key = "F", KeyCode = "F", Cooldown = 8, Radius = 16, Range = 90, Mult = 3,
		Desc = "조준한 곳에 폭발 (범위 16, 공격력 x3)" },
	Heal = { Name = "응급 치료", Icon = "💚", Key = "C", KeyCode = "C", Cooldown = 30, Radius = 40, Ratio = 0.2,
		Desc = "나와 주변 파티원의 체력 20% 회복" },
	Ult = { Name = "데드아이", Icon = "🎯", Key = "V", KeyCode = "V", Cooldown = 3, Radius = 110, Mult = 8, Cost = 100, ShotsPerTarget = 8, ShotGap = 0.03,
		Desc = "궁극기: 게이지가 가득 차면 사용! 주변 적을 하나씩 딱 락인한 뒤 공속 한계를 뚫고 전부에게 화다다다다 난사한다 (최대 12마리, 공격력 x8)" },
	ChargePerShot = 4,
}

------------------------------------------------------------
-- 보스 변종: 던전에 들어갈 때마다 하나가 뽑혀 보스의 성격이 달라진다
-- Weights: 기본 패턴 비중에 곱해지는 배율 (Fan Ring Spiral Meteor Slam Summon)
Config.Dungeon.BossVariants = {
	Order = { "Berserk", "Arcane", "Titan", "Summoner" },
	Berserk = { Prefix = "광폭한", Color = Color3.fromRGB(255, 60, 40), SpeedMult = 1.8, DamageMult = 1.2, HealthMult = 0.9, SizeMult = 0.9,
		Weights = { Fan = 1.5, Slam = 2.5 }, Desc = "빠르고 거칠다" },
	Arcane = { Prefix = "비전의", Color = Color3.fromRGB(150, 90, 255), SpeedMult = 1, DamageMult = 1.1, HealthMult = 1, SizeMult = 1,
		Weights = { Spiral = 2.5, Meteor = 2.5 }, Desc = "탄막과 운석을 쏟아낸다" },
	Titan = { Prefix = "거대한", Color = Color3.fromRGB(150, 150, 160), SpeedMult = 0.8, DamageMult = 1, HealthMult = 1.5, SizeMult = 1.3,
		Weights = { Slam = 3, Ring = 1.5 }, Desc = "느리지만 단단하고 충격파가 강하다" },
	Summoner = { Prefix = "군단장", Color = Color3.fromRGB(110, 220, 120), SpeedMult = 1, DamageMult = 1, HealthMult = 0.9, SizeMult = 1,
		Weights = { Summon = 4 }, Desc = "부하를 끊임없이 불러낸다" },
}

-- 방 이벤트: 전투 사이에 끼어드는 특별한 방
Config.Dungeon.Events = {
	Order = { "Treasure", "Trap", "Rest" },
	Treasure = { Name = "💎 보물방", Desc = "보물 상자가 있어요! 가까이 가면 열려요" },
	Trap = { Name = "☄ 함정방", Desc = "운석이 쏟아져요! 빨간 원을 피하세요 (끝까지 버티면 보상)" },
	Rest = { Name = "⛲ 휴식방", Desc = "샘물이 체력을 모두 회복시켜 줘요 + 특성 한 번 더" },
}

-- 던전 특성 (뱀파이어 서바이벌식): 웨이브 클리어마다 3개 중 1개를 골라 그 던전 동안만 쌓인다
-- Attr: 플레이어 Attribute(스택 수) / Max: 최대 스택 / Special: 총알이 바뀌는 특수 특성(항상 1개 이상 후보에 포함)
------------------------------------------------------------
Config.Perks = {
	Order = { "Multi", "Pierce", "Boom", "Chain", "Vamp", "Power", "Rapid", "Crit", "Vital" },
	Multi  = { Name = "분산탄", Icon = "🔱", Attr = "PerkMulti", Max = 4, Special = true,
		Desc = "한 번에 나가는 탄이 +1발, 부채꼴로 흩어져 나간다" },
	Pierce = { Name = "관통탄", Icon = "➳", Attr = "PerkPierce", Max = 3, Special = true,
		Desc = "탄이 적을 +1마리 더 관통한다" },
	Boom   = { Name = "폭발탄", Icon = "💥", Attr = "PerkBoom", Max = 3, Special = true,
		Desc = "맞은 적 주변에 폭발 (피해의 40%, 단계마다 범위 증가)" },
	Chain  = { Name = "연쇄 번개", Icon = "⚡", Attr = "PerkChain", Max = 3, Special = true,
		Desc = "맞은 적에게서 근처 적 +1마리로 번개가 튄다 (피해의 60%)" },
	Vamp   = { Name = "흡혈", Icon = "🩸", Attr = "PerkVamp", Max = 3, Special = true,
		Desc = "탄이 맞을 때마다 체력 +1 회복" },
	Power  = { Name = "강타", Icon = "🔥", Attr = "PerkPower", Max = 6,
		Desc = "공격력 +18%" },
	Rapid  = { Name = "속사", Icon = "⏩", Attr = "SpeedPoints", Max = 10,
		Desc = "공격 속도 +8%" },
	Crit   = { Name = "급소", Icon = "🎯", Attr = "CritPoints", Max = 15,
		Desc = "치명타 확률 +4%" },
	Vital  = { Name = "강인함", Icon = "❤", Attr = "HealthPoints", Max = 10,
		Desc = "최대 체력 +15, 즉시 회복" },
	ChoiceCount = 3,
	PowerPerStack = 0.18,
	BoomRatio = 0.4,
	ChainRatio = 0.6,
	FanAngle = 7,           -- 분산탄 사이 각도(도)
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
local dungeonBase = {
	TotalWaves = 5,          -- 이 웨이브를 모두 깨면 보스 등장
	StartCountdown = 5,      -- 입장 후 첫 웨이브까지 대기(초)
	StatPhaseTime = 15,      -- 웨이브 클리어 후 특성 고르는 제한 시간(초). 모두 고르면 바로 다음으로, 시간이 지나면 자동 선택
	PointsPerWave = 3,       -- (사용 안 함: 던전 특성 선택으로 대체됨)
	WaveClearGold = 40,      -- 웨이브 클리어 보너스 골드 (x 웨이브 번호)
	VictoryGold = 400,       -- 보스 처치 보너스 골드
	ReturnDelay = 8,         -- 던전 종료 후 로비 복귀까지 대기(초)

	ArenaLength = 1000,      -- 시작방에서 보스방까지 +X 방향으로 쭉 이어지는 길이
	ArenaWidth = 300,        -- 좌우 폭 (길이 이 안에서 굽이친다)
	SpawnRadius = 65,        -- 몬스터가 나타나는 거리
	ArenaOrigin = Vector3.new(0, 1500, 0), -- 던전 아레나는 로비/필드와 겹치지 않게 아주 높은 하늘 위에 만들어짐
	ArenaSpacing = 420,      -- 파티별 아레나 간격 (Z 방향으로 나란히)
	MaxArenas = 8,           -- 동시에 열 수 있는 던전 수
}
for key, value in pairs(dungeonBase) do -- 위쪽(특성 / 변이 / 이벤트)에서 먼저 만든 Config.Dungeon 에 기본 값을 합친다
	Config.Dungeon[key] = value
end

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
		Speed = 12.5,
		ShotDamage = 8 + level * 2,
		ShotInterval = math.max(1.2, 2.6 - level * 0.05),
		ShotSpeed = 45,
		Gold = 8 + level * 4, -- 처치 시 파티원 모두에게 지급
	}
end

Config.Boss = {
	Name = "던전의 군주",
	Size = 30,
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
	WeaponCount = 100,
	BaseCost = 100,
	CostGrowth = 1.0118,    -- 강화 1회마다 비용 x1.0118 (단계가 820까지 늘어서, 끝 비용은 예전과 비슷하게 맞춘 값)
	LevelScale = 326 / 820, -- 위력 / 크기 / 성공률 공식은 이 비율로 줄인 "유효 단계"를 쓴다 (단계가 많아져도 최종 위력은 그대로)
}
-- 무기 하나가 가진 강화 단계 수: 처음 무기들은 오래 키우고(첫 무기 10단계), 뒤로 갈수록 빨리 넘어간다
-- (이 무기의 마지막 단계에서 강화에 성공하면 다음 무기로 진화)
function Config.Weapon.StepsFor(index)
	if index <= 10 then return 10 end -- 처음 10개 무기는 10단계씩
	return 8                          -- 이후 무기도 전부 8단계 (5강화로 휙 넘어가지 않게)
end

-- 무기 사다리: 10개 시대 x 10개 종류 = 100종. 시대마다 색 / 재질 / 효과 / 발사체가 크게 바뀌고,
-- 시대 안에서는 권총 -> 리볼버 -> 기관단총 -> 샷건 -> 라이플 -> 저격총 -> 로켓 런처 -> 레일건 -> 화염방사기 -> 플라즈마 캐논 순서로 바뀐다.
-- Shot: 발사체 외형. Style(Ball/Bolt/Orb/Cannon/Fire/Rocket/Rainbow) / Size / Length(Bolt/Rocket) / Speed(초당 거리) / Impact(착탄 입자 수)
local ERAS = {
	{ Prefix = "녹슨",   Color = Color3.fromRGB(165, 165, 175), Material = Enum.Material.Metal,  Particles = 0,  Trail = false, Light = 0,
		Shot = { Style = "Ball", Size = 0.6, Speed = 260, Impact = 0 } },
	{ Prefix = "강철",   Color = Color3.fromRGB(90, 160, 255),  Material = Enum.Material.Metal,  Particles = 6,  Trail = false, Light = 0,
		Shot = { Style = "Bolt", Size = 0.35, Length = 3, Speed = 320, Impact = 6 } },
	{ Prefix = "마력",   Color = Color3.fromRGB(175, 95, 255),  Material = Enum.Material.Glass,  Particles = 12, Trail = true,  Light = 0,
		Shot = { Style = "Orb", Size = 1.3, Speed = 190, Impact = 14 } },
	{ Prefix = "황금",   Color = Color3.fromRGB(255, 200, 50),  Material = Enum.Material.Neon,   Particles = 22, Trail = true,  Light = 10,
		Shot = { Style = "Cannon", Size = 2.4, Speed = 140, Impact = 30 } },
	{ Prefix = "불꽃",   Color = Color3.fromRGB(255, 70, 40),   Material = Enum.Material.Neon,   Particles = 40, Trail = true,  Light = 16,
		Shot = { Style = "Rocket", Size = 1.6, Length = 4, Speed = 150, Impact = 70 } },
	{ Prefix = "빙결",   Color = Color3.fromRGB(140, 225, 255), Material = Enum.Material.Ice,    Particles = 30, Trail = true,  Light = 14,
		Shot = { Style = "Bolt", Size = 0.5, Length = 4.5, Speed = 360, Impact = 40 } },
	{ Prefix = "번개",   Color = Color3.fromRGB(255, 240, 90),  Material = Enum.Material.Neon,   Particles = 45, Trail = true,  Light = 18,
		Shot = { Style = "Bolt", Size = 0.45, Length = 7, Speed = 440, Impact = 50 } },
	{ Prefix = "암흑",   Color = Color3.fromRGB(100, 50, 160),  Material = Enum.Material.Neon,   Particles = 50, Trail = true,  Light = 14,
		Shot = { Style = "Orb", Size = 1.9, Speed = 200, Impact = 55 } },
	{ Prefix = "용의",   Color = Color3.fromRGB(255, 120, 60),  Material = Enum.Material.Neon,   Particles = 55, Trail = true,  Light = 20,
		Shot = { Style = "Fire", Size = 2.4, Speed = 180, Impact = 80 } },
	{ Prefix = "신화의", Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.Neon,   Particles = 70, Trail = true,  Light = 24, Rainbow = true,
		Shot = { Style = "Rainbow", Size = 2.6, Speed = 190, Impact = 90 } },
}
-- 시대 안에서 뒤로 갈수록 "한 방 / 폭발 / 관통" 같은 묵직한 무기가 오고, 기본 화력(DPS)도 조금씩 올라간다
local CLASS_ORDER = { "Pistol", "Smg", "Revolver", "Rifle", "Shotgun", "Flamer", "Cannon", "Sniper", "Rocket", "Rail" }
local CLASS_NAMES = {
	Pistol = "권총", Revolver = "리볼버", Smg = "기관단총", Shotgun = "샷건", Rifle = "라이플",
	Sniper = "저격총", Rocket = "로켓 런처", Rail = "레일건", Flamer = "화염방사기", Cannon = "플라즈마 캐논",
}
-- 무기 이름: 종류 x 시대마다 전부 다른 이름 (접두사만 바뀌는 게 아니라 무기 자체가 다른 이름 / 다른 모양)
local WEAPON_NAMES = {
	Pistol = { "녹슨 권총", "강철 피스톨", "마력 핸드캐논", "황금 에이스", "불꽃 점화기", "서리송곳 권총", "번개 방아쇠", "그림자 송곳니", "용송곳니 피스톨", "신화의 아스트라" },
	Smg = { "녹슨 기관단총", "강철 연발총", "마력 속삭임 SMG", "황금 폭풍 SMG", "화염 연사기", "서리 연사기", "방전 기관단총", "그림자 연사기", "용염 기관단총", "신화의 스프레이" },
	Revolver = { "녹슨 리볼버", "강철 육혈포", "마력 마그넘", "황금 헌터", "인페르노 리볼버", "얼음깨기 리볼버", "천둥 리볼버", "저주받은 리볼버", "용의 마그넘", "이터널 리볼버" },
	Rifle = { "녹슨 라이플", "강철 카빈", "마력 소총", "황금 레인저", "불꽃 라이플", "서리 소총", "전격 라이플", "그림자 라이플", "용린 라이플", "신화의 은하 라이플" },
	Shotgun = { "녹슨 샷건", "강철 펌프 샷건", "마력 쌍열 샷건", "황금 파쇄총", "화염 산탄총", "빙하 산탄총", "번개 산탄총", "학살자 샷건", "용의 산탄포", "신화의 산탄포" },
	Flamer = { "녹슨 화염방사기", "강철 분사기", "마력 불꽃 분사기", "황금 용광로", "불꽃 인페르노 토치", "서리 불꽃 분사기", "플라즈마 토치", "지옥불 분사기", "용의 숨결", "별의 화염" },
	Cannon = { "녹슨 플라즈마 캐논", "강철 대포", "마력 캐논", "황금 대포", "화산포", "빙결포", "천둥포", "암흑 캐논", "용포", "별 파괴포" },
	Sniper = { "녹슨 저격총", "강철 장거리 저격총", "마력 저격총", "황금 독수리 저격총", "불꽃 저격총", "설원 저격총", "번개 저격총", "암살자의 저격총", "용안 저격총", "은하 저격총" },
	Rocket = { "녹슨 로켓 런처", "강철 바주카", "마력 런처", "황금 미사일", "화염 로켓", "빙결 미사일", "번개 미사일", "암흑 미사일", "용의 로켓", "혜성 런처" },
	Rail = { "녹슨 레일건", "강철 가우스 건", "마력 레일건", "황금 레일건", "불꽃 레일건", "서리 레일건", "전자기 레일건", "공허 레일건", "용핵 레일건", "신화의 레일건" },
}

-- Tiers[i] = i번째 무기 (MinLevel = 이 무기가 되는 최소 강화 단계). 이름은 시대 + 종류.
Config.Weapon.Tiers = {}
local totalSteps = 0
for index = 1, Config.Weapon.WeaponCount do
	local era = ERAS[(index - 1) // #CLASS_ORDER + 1]
	local class = CLASS_ORDER[(index - 1) % #CLASS_ORDER + 1]
	local inEra = (index - 1) % #CLASS_ORDER -- 0~9: 시대 안에서 뒤로 갈수록 탄이 조금씩 커진다
	local shot = table.clone(era.Shot)
	shot.Size *= 1 + 0.04 * inEra
	local name = WEAPON_NAMES[class][(index - 1) // #CLASS_ORDER + 1]
	local entry = {
		Index = index, MinLevel = totalSteps, Steps = Config.Weapon.StepsFor(index),
		Name = name, Prefix = era.Prefix, Class = class, Era = (index - 1) // #CLASS_ORDER + 1,
		Color = era.Color, Material = era.Material, Particles = era.Particles, Trail = era.Trail, Light = era.Light,
		Rainbow = era.Rainbow, Shot = shot,
	}
	-- 예전 코드가 tier.Names[종류] 로 이름을 찾는 곳이 있어서, 어떤 키로 찾아도 이 무기 이름을 돌려준다
	entry.Names = setmetatable({}, { __index = function() return name end })
	Config.Weapon.Tiers[index] = entry
	totalSteps += entry.Steps
end
Config.Weapon.MaxLevel = totalSteps - 1 -- 마지막 무기까지 강화한 단계

------------------------------------------------------------
-- 로비 허수아비 (때릴 때마다 골드): 허수아비는 하나. 내 전투력이 높을수록 한 대당 골드가 많이 나온다.
--   획득 골드 = GoldPerHit x (1 + (전투력 / PowerRef) ^ PowerExp) x 무기 한 발 위력 x 무기 세대 보너스
------------------------------------------------------------
Config.Dummy = {
	GoldPerHit = 2,
	EraGoldMult = 1.4,     -- 무기 세대(10종 단위)가 오를 때마다 허수아비 골드 x1.4 (업그레이드할수록 골드도 늘게)
	PowerRef = 600,        -- 전투력 기준값 (이 값일 때 배율 약 x2)
	PowerExp = 0.55,       -- 전투력이 오를수록 골드가 어떻게 늘어나는지 (1 이면 정비례, 작을수록 완만)
	-- 허수아비는 하나. 이름 / 기본 배율만 있다 (방어력 없음: 누구나 때려서 골드를 번다)
	List = {
		{ Name = "황금 훈련 허수아비", Multiplier = 1, RequiredPower = 0 },
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
	EnhanceSuccess = 119142651784821, -- 강화 성공 소리 (무기 / 장비)
}
for key, value in pairs(defaultIds) do
	if not ids[key] or ids[key] == 0 then
		ids = table.clone(ids)
		ids[key] = value
	end
end

-- 항목별 효과음 ID: AudioBank(업데이트로 관리) 위에 AudioIds 의 Bank(직접 적은 값)를 덮어쓴다
local bankIds = {}
do
	local bankModule = script.Parent:FindFirstChild("AudioBank")
	local okBank, bank = pcall(function() return bankModule and require(bankModule) or {} end)
	if okBank and typeof(bank) == "table" then
		for key, value in pairs(bank) do
			bankIds[key] = value
		end
	end
	if typeof(ids.Bank) == "table" then
		for key, value in pairs(ids.Bank) do
			bankIds[key] = value
		end
	end
end

Config.Audio = {
	MusicVolume = 0.18,
	Music = {
		Lobby = ids.Lobby or 0,      -- 로비 배경음악
		Dungeon = ids.Dungeon or 0,  -- 던전(웨이브) 배경음악
		Boss = ids.Boss or 0,        -- 보스전 배경음악
		Field = ids.Field or 0,      -- 필드 배경음악 (없으면 로비 음악)
	},
	Shot = ids.Shot or 0,            -- 총 쏘는 소리 (무기가 강해질수록 낮고 묵직하게 재생됨)
	ShotVolume = 0.3,
	EnhanceSuccess = ids.EnhanceSuccess or 0, -- 강화 성공 소리
	Hit = ids.Hit or 0,              -- 적중음
	Kill = ids.Kill or 0,            -- 처치음
	Skill = ids.Skill or 0,          -- 스킬음
	Bank = bankIds,                  -- 소리별 직접 지정 ID (AudioBank 스크립트 + AudioIds 의 Bank. 있으면 SoundBank 의 가공음 대신 사용)
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
		{ Key = "Helmet", Name = "투구", Stat = "Damage", StatName = "공격력", Base = 0.03, BaseCost = 130,
			Names = { "가죽 모자", "철 투구", "강철 투구", "미스릴 투구", "용뿔 왕관" } },
		{ Key = "Ring", Name = "반지", Stat = "Haste", StatName = "스킬 쿨타임 감소", Base = 0.02, BaseCost = 140,
			Names = { "구리 반지", "은 반지", "금 반지", "보석 반지", "시간의 반지" } },
		{ Key = "Necklace", Name = "목걸이", Stat = "Luck", StatName = "행운", Base = 0.05, BaseCost = 140,
			Names = { "끈 목걸이", "은 목걸이", "금 목걸이", "보석 목걸이", "별빛 목걸이" } },
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
	elseif slot.Stat == "Speed" then
		return string.format("이동 속도 +%.1f", value)
	end
	-- 나머지는 비율(%) 효과: 치명타 확률 / 공격력 / 스킬 쿨타임 감소 / 행운 ...
	return string.format("%s +%.1f%%", slot.StatName, value * 100)
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
	ZoneCountMult = { 1, 1, 1.4, 1.7, 2.0, 2.3, 2.6, 3.0 }, -- 구역별 몬스터 수 배율 (3구역부터 점점 더 많다)
	ElitesPerZone = 3,
	CampSafe = 70,             -- 각 구역 입구 캠프 주변 안전지대 반경(몬스터가 노리지 않음)
	RespawnTime = 10,
	AggroRange = 55,
	LeashRange = 110,
	EliteMultiplier = 5,       -- 엘리트 몬스터 체력 배율
	EliteTicketChance = 0.2,   -- 엘리트 처치 시 티켓 획득 확률
	BossRespawn = 120,
	-- 구역마다 군주가 다시 나타나는 시간(초): 모두가 같이 쓰는 필드라서, 앞 구역은 자주 / 뒤 구역은 드물게 (뒤로 갈수록 귀한 상대)
	BossRespawnByZone = { 60, 90, 150, 210, 300, 420, 600, 900 },
	-- 구역 군주를 상대하기 전에 갖춰야 할 권장 전투력 (모자라면 군주를 만났을 때 "무기를 강화하세요" 안내가 뜬다)
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
		Health = { 1, 1.7, 3.5, 7, 14, 28, 55, 100 },
		Damage = { 1, 1.3, 2.2, 3.4, 5.2, 8, 12, 18 },
		Speed = { 1, 1.05, 1.1, 1.18, 1.26, 1.35, 1.45, 1.55 },
		Reward = { 1, 1.5, 2.2, 3.2, 4.6, 6.5, 9, 13 },
	},
	ZoneNames = { "초원", "숲", "황무지", "사막", "설원", "화산", "암흑 지대", "심연" },
	-- 구역별로 나오는 몬스터 종류와 비중 (MonsterTypes.lua 의 Defs 이름)
	ZonePools = {
		{ Slime = 5, Bat = 2, Spider = 1 },
		{ Slime = 3, Spitter = 3, Bat = 2, Spider = 2, Wisp = 1 },
		{ Spitter = 3, Charger = 3, Golem = 1, Imp = 2, Turret = 1 },
		{ Charger = 3, Bomber = 3, Spitter = 2, Spider = 2, Imp = 2 },
		{ Mage = 3, Golem = 2, Bat = 3, Knight = 2, Wisp = 2 },
		{ Bomber = 3, Charger = 3, Mage = 2, Turret = 2, Totem = 1 },
		{ Mage = 3, Golem = 2, Charger = 2, Bomber = 2, Knight = 2, Imp = 2, Totem = 1 },
		{ Mage = 2, Golem = 3, Charger = 3, Bomber = 3, Spitter = 1, Knight = 2, Turret = 2, Totem = 2, Wisp = 2 },
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
	Order = { "Pistol", "Smg", "Revolver", "Rifle", "Shotgun", "Flamer", "Cannon", "Sniper", "Rocket", "Rail" },
	Pistol = {
		Name = "권총", Form = "Basic", DamageMult = 1.0, Cooldown = 1, Range = 300, Pellets = 1, Spread = 0,
		ShotScale = 1, SpeedScale = 1, BarrelLength = 1, BarrelThickness = 1,
		Desc = "균형 잡힌 기본 무기",
	},
	Revolver = {
		Name = "리볼버", Form = "Steel", DamageMult = 1.08, Cooldown = 1.0, Range = 320, Pellets = 1, Spread = 0,
		ShotScale = 1.15, SpeedScale = 1.1, CritBonus = 0.1, BarrelLength = 0.9, BarrelThickness = 1.2,
		Desc = "느리지만 묵직한 한 방, 치명타 +10%",
	},
	Smg = {
		Name = "기관단총", Form = "Smg", DamageMult = 0.416, Cooldown = 0.4, Range = 220, Pellets = 1, Spread = 0,
		ShotScale = 0.7, SpeedScale = 1.1, BarrelLength = 0.8, BarrelThickness = 0.9,
		Desc = "엄청난 연사 속도로 쏟아붓는 총",
	},
	Shotgun = {
		Name = "샷건", Form = "Basic", DamageMult = 0.387, Cooldown = 1.2, Range = 90, Pellets = 6, Spread = 9,
		ShotScale = 0.55, SpeedScale = 1, BarrelLength = 0.75, BarrelThickness = 1.5,
		Desc = "근거리에서 6발이 퍼져 나가는 산탄 (사거리 90)",
	},
	Rifle = {
		Name = "라이플", Form = "Rifle", DamageMult = 0.84, Cooldown = 0.75, Range = 400, Pellets = 1, Spread = 0,
		ShotScale = 0.9, SpeedScale = 1.4, CritBonus = 0.05, BarrelLength = 1.4, BarrelThickness = 0.9,
		Desc = "멀리까지 정확한 중속 연사",
	},
	Sniper = {
		Name = "저격총", Form = "Basic", DamageMult = 1.792, Cooldown = 1.4, Range = 600, Pellets = 1, Spread = 0,
		ShotScale = 1.4, SpeedScale = 2.4, CritBonus = 0.25, BarrelLength = 1.9, BarrelThickness = 0.7,
		Desc = "느리지만 한 방이 강력, 치명타 +25%, 사거리 600",
	},
	Rocket = {
		Name = "로켓 런처", Form = "Rocket", DamageMult = 1.848, Cooldown = 1.4, Range = 350, Pellets = 1, Spread = 0, Splash = 12,
		ShotScale = 1.8, SpeedScale = 0.55, BarrelLength = 1.3, BarrelThickness = 1.6,
		Desc = "맞은 곳이 폭발해서 주변 적에게도 피해 (범위 12)",
	},
	Rail = {
		Name = "레일건", Form = "Rail", DamageMult = 1.904, Cooldown = 1.4, Range = 700, Pellets = 1, Spread = 0, Pierce = 2,
		ShotScale = 1.2, SpeedScale = 3, BarrelLength = 1.6, BarrelThickness = 0.8,
		Desc = "일직선으로 적을 3마리까지 관통하는 초고속 탄",
	},
	Flamer = {
		Name = "화염방사기", Form = "Flamer", DamageMult = 0.2, Cooldown = 0.4, Range = 55, Pellets = 4, Spread = 16,
		ShotScale = 0.9, SpeedScale = 0.6, BarrelLength = 0.7, BarrelThickness = 1.4,
		Desc = "짧은 거리에서 불길을 뿜는 근접 무기 (사거리 60)",
	},
	Cannon = {
		Name = "플라즈마 캐논", Form = "Cannon", DamageMult = 1.488, Cooldown = 1.2, Range = 380, Pellets = 1, Spread = 0, Splash = 7,
		ShotScale = 1.5, SpeedScale = 0.8, BarrelLength = 1.1, BarrelThickness = 1.8,
		Desc = "큼직한 플라즈마 탄, 맞은 곳 주변에 작은 폭발 (범위 7)",
	},
}

-- (무기 종류끼리 연사 속도 차이를 줄였다: 초당 약 2~7발. 초당 피해량(DPS)은 그대로 유지하도록 한 발 피해를 맞췄다)
-- 지금 들고 있는 무기의 종류 능력치 (무기는 강화 단계에 따라 자동으로 바뀐다)
function Config.GetPlayerWeapon(player)
	local tier = Config.GetWeaponTier(player:GetAttribute("WeaponLevel") or 0)
	return Config.WeaponTypes[tier.Class] or Config.WeaponTypes.Pistol
end

-- 무기 이름 (typeKey 는 예전 호환용으로 무시: 이름은 강화 단계로만 정해진다)
function Config.GetWeaponName(_typeKey, level)
	return Config.GetWeaponTier(level).Name
end

------------------------------------------------------------
-- 던전 종류 / 난이도 (던전 게이트에서 파티장이 고른다)
------------------------------------------------------------
Config.Dungeon.Difficulties = {
	Order = { "Easy", "Normal", "Hard" },
	Easy = { Name = "쉬움", KeyTier = 1, HealthMult = 0.7, DamageMult = 0.7, GoldMult = 0.8, Tickets = 2, KeyCost = 1, LevelOffset = -2, Color = Color3.fromRGB(120, 220, 130) },
	Normal = { Name = "보통", KeyTier = 2, HealthMult = 1, DamageMult = 1, GoldMult = 1, Tickets = 3, KeyCost = 1, LevelOffset = 0, Color = Color3.fromRGB(255, 220, 110) },
	Hard = { Name = "어려움", KeyTier = 3, HealthMult = 1.8, DamageMult = 1.5, GoldMult = 2, Tickets = 5, KeyCost = 1, LevelOffset = 4, Color = Color3.fromRGB(255, 100, 100) },
}

-- Boss.Weights: 보스 패턴 비중 (Fan 부채꼴 / Ring 전방위 / Spiral 나선 / Meteor 메테오)
Config.Dungeon.Types = {
	Order = { "Cave", "Ice", "Fire", "Tower" },
	Cave = {
		Name = "고블린 동굴", Desc = "어둡고 좁은 동굴. 입문용 던전", Waves = 5, LevelOffset = 0, GoldMult = 1, RecommendedPower = 0,
		MonsterColor = Color3.fromRGB(110, 160, 70),
		Floor = { Color = Color3.fromRGB(70, 60, 50), Material = Enum.Material.Slate },
		Wall = { Color = Color3.fromRGB(55, 45, 40), Material = Enum.Material.Brick },
		Torch = Color3.fromRGB(255, 150, 70),
		Terrain = { Ground = Enum.Material.Mud, Mountain = Enum.Material.Rock, Accent = Enum.Material.Slate },
		MonsterPool = { Slime = 4, Spitter = 3, Bat = 3, Spider = 2, Imp = 1 },
		Boss = { Name = "고블린 왕", Color = Color3.fromRGB(70, 130, 50), HealthMult = 1, DamageMult = 1, Weights = { Fan = 3, Ring = 2, Spiral = 1, Meteor = 2, Slam = 2, Summon = 1, Lanes = 2.5, Sweep = 2, SideAdds = 1 } },
	},
	Ice = {
		Name = "얼음 성채", Desc = "얼어붙은 성. 나선 탄막이 매서운 중급 던전", Waves = 6, LevelOffset = 6, GoldMult = 1.6, RecommendedPower = 400,
		MonsterColor = Color3.fromRGB(110, 200, 240),
		Floor = { Color = Color3.fromRGB(190, 220, 240), Material = Enum.Material.Ice },
		Wall = { Color = Color3.fromRGB(120, 160, 200), Material = Enum.Material.Glacier },
		Torch = Color3.fromRGB(120, 200, 255),
		Terrain = { Ground = Enum.Material.Snow, Mountain = Enum.Material.Glacier, Accent = Enum.Material.Ice },
		MonsterPool = { Slime = 2, Spitter = 2, Mage = 3, Golem = 2, Wisp = 2, Knight = 2, Turret = 1 },
		Boss = { Name = "서리 군주", Color = Color3.fromRGB(90, 170, 240), HealthMult = 1.6, DamageMult = 1.2, Weights = { Fan = 1, Ring = 3, Spiral = 3, Meteor = 1, Slam = 2, Summon = 2, Lanes = 2.5, Sweep = 2.5, SideAdds = 1.5 } },
	},
	Fire = {
		Name = "화염 신전", Desc = "용암의 신전. 메테오가 쏟아지는 고급 던전", Waves = 7, LevelOffset = 12, GoldMult = 2.5, RecommendedPower = 1200,
		MonsterColor = Color3.fromRGB(240, 100, 50),
		Floor = { Color = Color3.fromRGB(60, 35, 35), Material = Enum.Material.Basalt },
		Wall = { Color = Color3.fromRGB(90, 40, 30), Material = Enum.Material.CrackedLava },
		Torch = Color3.fromRGB(255, 90, 40),
		Terrain = { Ground = Enum.Material.Basalt, Mountain = Enum.Material.Slate, Accent = Enum.Material.CrackedLava },
		MonsterPool = { Charger = 3, Bomber = 3, Mage = 2, Golem = 2, Imp = 2, Totem = 1, Spider = 2 },
		Boss = { Name = "화염의 군주", Color = Color3.fromRGB(230, 70, 30), HealthMult = 2.4, DamageMult = 1.5, Weights = { Fan = 1, Ring = 1, Spiral = 2, Meteor = 4, Slam = 3, Summon = 1, Lanes = 3, Sweep = 3, SideAdds = 1 } },
	},
	-- 무한의 탑: 끝이 없는 웨이브. 층(웨이브)이 오를수록 강해지고, 쓰러질 때까지 도전. 최고 층이 기록으로 남는다.
	Tower = {
		Name = "무한의 탑", Desc = "끝없이 이어지는 웨이브. 최고 층 기록에 도전! 5층마다 티켓", Waves = 0, Endless = true, LevelOffset = 4, GoldMult = 1.5, RecommendedPower = 600,
		MonsterColor = Color3.fromRGB(190, 120, 255),
		Floor = { Color = Color3.fromRGB(60, 50, 80), Material = Enum.Material.Slate },
		Wall = { Color = Color3.fromRGB(70, 55, 100), Material = Enum.Material.Slate },
		Torch = Color3.fromRGB(190, 120, 255),
		Terrain = { Ground = Enum.Material.Slate, Mountain = Enum.Material.Basalt, Accent = Enum.Material.Glacier },
		MonsterPool = { Slime = 2, Spitter = 2, Bat = 2, Mage = 2, Golem = 1, Charger = 2, Bomber = 2, Spider = 2, Imp = 2, Knight = 2, Turret = 1, Wisp = 2, Totem = 1 },
		Boss = { Name = "탑의 수호자", Color = Color3.fromRGB(180, 100, 255), HealthMult = 1, DamageMult = 1, Weights = { Fan = 1, Ring = 1, Spiral = 1, Meteor = 1, Slam = 2, Summon = 2, Lanes = 2, Sweep = 2, SideAdds = 1.5 } },
	},
}

-- 심연 도전(점수 도전): 90초 동안 버티며 점수를 쌓는다. 최고 점수가 "소탕" 보상의 한계를 정한다 (방치 + 손맛)
Config.Dungeon.Types.Rift = {
	Name = "심연 도전", Desc = "90초 점수 도전! 처치 + 콤보 + 아슬아슬한 회피로 점수를 쌓아요", Waves = 0, Endless = true, TimeLimit = 90, LevelOffset = 4, GoldMult = 1, RecommendedPower = 0,
	MonsterColor = Color3.fromRGB(255, 80, 150),
	Floor = { Color = Color3.fromRGB(46, 30, 66), Material = Enum.Material.Slate },
	Wall = { Color = Color3.fromRGB(80, 40, 100), Material = Enum.Material.Slate },
	Torch = Color3.fromRGB(255, 80, 150),
	Terrain = { Ground = Enum.Material.Slate, Mountain = Enum.Material.Basalt, Accent = Enum.Material.Glacier },
	MonsterPool = { Slime = 2, Spitter = 2, Bat = 2, Mage = 2, Golem = 1, Charger = 2, Bomber = 2, Spider = 2, Imp = 2, Knight = 2, Turret = 1, Wisp = 2, Totem = 1 },
	Boss = { Name = "심연의 문지기", Color = Color3.fromRGB(255, 80, 150), HealthMult = 1, DamageMult = 1, Weights = { Fan = 1, Ring = 1, Spiral = 1, Meteor = 1, Slam = 2, Summon = 2, Lanes = 2, Sweep = 2, SideAdds = 1.5 } },
}

Config.Rift = {
	Duration = 90,        -- 도전 시간(초)
	FreeAttempts = 3,     -- 하루 무료 도전(또는 소탕) 횟수 (UTC 날짜 기준 초기화)
	SweepRate = 0.7,      -- 소탕 보상 = 내 최고 점수 등급 보상의 70%
	KillScore = 10,       -- 처치 1마리 기본 점수 (+ 현재 콤보, 최대 60)
	NearMissScore = 60,   -- NEAR MISS(대시로 아슬아슬하게 피하기) 1회
	WaveBonus = 100,      -- 웨이브 클리어 보너스 x 웨이브 번호
	BossScore = 200,
	Tiers = {             -- 점수 등급별 보상 (직접 도전의 보상 = 그 판의 등급 / 소탕 = 최고 점수 등급의 70%)
		{ Min = 0,    Name = "브론즈",   Icon = "🥉", Gold = 200,   Tickets = 0, TimeSkip = 0 },
		{ Min = 500,  Name = "실버",     Icon = "🥈", Gold = 600,   Tickets = 0, TimeSkip = 300 },
		{ Min = 1200, Name = "골드",     Icon = "🥇", Gold = 1500,  Tickets = 1, TimeSkip = 600 },
		{ Min = 2500, Name = "플래티넘", Icon = "💠", Gold = 3500,  Tickets = 2, TimeSkip = 900 },
		{ Min = 5000, Name = "다이아",   Icon = "💎", Gold = 8000,  Tickets = 4, TimeSkip = 1800 },
		{ Min = 9000, Name = "마스터",   Icon = "👑", Gold = 15000, Tickets = 6, TimeSkip = 3600 },
	},
}
function Config.GetRiftTier(score)
	local tier = Config.Rift.Tiers[1]
	for _, candidate in ipairs(Config.Rift.Tiers) do
		if score >= candidate.Min then tier = candidate end
	end
	return tier
end

-- 던전 목록: 던전마다 입구(게이트)가 따로 있고, 캐릭터 레벨이 되면 난이도 순서대로 입장할 수 있다 (메뉴에서 고르지 않는다)
-- Type / Diff: 위의 던전 종류 / 난이도 조합. MinLevel: 입장에 필요한 캐릭터 레벨 (파티원 모두).
Config.Dungeon.List = {
	{ Type = "Cave", Diff = "Easy", MinLevel = 1 },
	{ Type = "Cave", Diff = "Normal", MinLevel = 8 },
	{ Type = "Ice", Diff = "Easy", MinLevel = 14 },
	{ Type = "Ice", Diff = "Normal", MinLevel = 20 },
	{ Type = "Fire", Diff = "Easy", MinLevel = 26 },
	{ Type = "Fire", Diff = "Normal", MinLevel = 32 },
	{ Type = "Fire", Diff = "Hard", MinLevel = 40 },
	{ Type = "Tower", Diff = "Normal", MinLevel = 10 },
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
		{ Id = "goblin",  Name = "황금 사냥",     Desc = "황금 고블린 %d마리 처치",       Stat = "GoblinKills",   Goal = 1,   Reward = { Gold = 800, Tickets = 1 } },
		{ Id = "skills",  Name = "스킬 연습",     Desc = "스킬을 %d번 사용하기",          Stat = "SkillUses",     Goal = 20,  Reward = { Gold = 400 } },
		{ Id = "rift",    Name = "심연 도전",     Desc = "심연 도전(소탕 포함) %d번 하기", Stat = "RiftRuns",      Goal = 2,   Reward = { Gold = 700, TimeSkip = 600 } },
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
	{ Id = "goblin1",    Name = "황금 사냥꾼",     Desc = "황금 고블린 %d마리 처치",     Stat = "GoblinKills",   Goal = 1,     Reward = { Gold = 1000 },              Title = "행운의 사냥꾼" },
	{ Id = "goblin20",   Name = "황금 도둑",       Desc = "황금 고블린 %d마리 처치",     Stat = "GoblinKills",   Goal = 20,    Reward = { Tickets = 5 },              Title = "황금 도둑" },
	{ Id = "skill200",   Name = "스킬 마스터",     Desc = "스킬 %d회 사용",              Stat = "SkillUses",     Goal = 200,   Reward = { Tickets = 3 },              Title = "스킬 마스터" },
	{ Id = "rift2500",   Name = "심연의 도전자",   Desc = "심연 도전 %d점 달성",         Stat = "RiftBest",      Goal = 2500,  Reward = { Tickets = 4 },              Title = "심연의 도전자" },
	{ Id = "rift9000",   Name = "한계 돌파자",     Desc = "심연 도전 %d점 달성",         Stat = "RiftBest",      Goal = 9000,  Reward = { Tickets = 12 },             Title = "한계 돌파자" },
	{ Id = "tower10",    Name = "탑의 도전자",     Desc = "무한의 탑 %d층 도달",         Stat = "TowerBest",     Goal = 10,    Reward = { Tickets = 3 },              Title = "탑의 도전자" },
	{ Id = "tower30",    Name = "탑의 정복자",     Desc = "무한의 탑 %d층 도달",         Stat = "TowerBest",     Goal = 30,    Reward = { Tickets = 10 },             Title = "탑의 정복자" },
	{ Id = "prestige1",  Name = "다시 태어난 자",   Desc = "환생 %d회",                    Stat = "Prestige",      Goal = 1,     Reward = { Tickets = 5 },              Title = "환생자" },
	{ Id = "prestige5",  Name = "윤회의 달인",     Desc = "환생 %d회",                    Stat = "Prestige",      Goal = 5,     Reward = { Tickets = 15 },             Title = "윤회의 달인" },
	{ Id = "boss10",     Name = "보스 헌터",       Desc = "보스 %d마리 처치",            Stat = "BossKills",     Goal = 10,    Reward = { Tickets = 5 },              Title = "보스 헌터" },
	{ Id = "zone4",      Name = "탐험가",          Desc = "필드 %d구역 돌파",            Stat = "MaxZone",       Goal = 4,     Reward = { Gold = 1000 },              Title = "탐험가" },
	{ Id = "zone8",      Name = "심연의 정복자",   Desc = "필드 %d구역 돌파",            Stat = "MaxZone",       Goal = 8,     Reward = { Tickets = 5 },              Title = "심연의 정복자" },
	{ Id = "weapon10",   Name = "무기 수집가",     Desc = "무기 강화 %d단계 달성 (무기 약 10번째)", Stat = "WeaponLevel",   Goal = Config.Weapon.Tiers[10].MinLevel, Reward = { Gold = 2000 },              Title = "강화의 달인" },
	{ Id = "weapon50",   Name = "전설을 쥔 자",    Desc = "무기 강화 %d단계 달성 (무기 약 50번째)", Stat = "WeaponLevel",   Goal = Config.Weapon.Tiers[50].MinLevel, Reward = { Tickets = 6 },              Title = "전설을 쥔 자" },
	{ Id = "weapon15",   Name = "전설의 대장장이", Desc = "마지막 무기까지 강화 (%d단계)",       Stat = "WeaponLevel",   Goal = Config.Weapon.MaxLevel, Reward = { Tickets = 20 },             Title = "전설의 대장장이" },
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
	EarlyBoostUntil = 6,    -- 이 레벨까지는 경험치 x3 (처음 몇 분 안에 레벨업이 연달아 터지게)
	EarlyBoost = 3,
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

-- 세트 장비 (영웅 등급 이상에 붙을 수 있음): 같은 세트 2부위 / 3부위를 끼면 보너스
-- Bonuses[2], Bonuses[3] = { {Stat, Value}, ... }   Stat: Health Crit Speed Damage Xp Luck + Haste(스킬 쿨타임 감소) Shot(탄 +N발)
Config.Sets = {
	Order = { "Hunter", "Guardian", "Gale", "Sage" },
	SetChance = { [3] = 0.30, [4] = 0.45, [5] = 0.60 }, -- 등급별로 세트가 붙을 확률
	Hunter = { Name = "사냥꾼의 증표", Color = Color3.fromRGB(255, 170, 70),
		Bonuses = { [2] = { { Stat = "Damage", Value = 0.08 } }, [3] = { { Stat = "Crit", Value = 0.10 }, { Stat = "Damage", Value = 0.07 } } } },
	Guardian = { Name = "수호자의 맹세", Color = Color3.fromRGB(110, 190, 255),
		Bonuses = { [2] = { { Stat = "Health", Value = 120 } }, [3] = { { Stat = "Health", Value = 250 }, { Stat = "Haste", Value = 0.10 } } } },
	Gale = { Name = "질풍의 바람", Color = Color3.fromRGB(120, 255, 170),
		Bonuses = { [2] = { { Stat = "Speed", Value = 2 } }, [3] = { { Stat = "Speed", Value = 3 }, { Stat = "Haste", Value = 0.15 } } } },
	Sage = { Name = "현자의 지혜", Color = Color3.fromRGB(200, 140, 255),
		Bonuses = { [2] = { { Stat = "Xp", Value = 0.15 } }, [3] = { { Stat = "Xp", Value = 0.25 }, { Stat = "Luck", Value = 0.25 } } } },
}

-- 유니크 (신화 등급에서만, 일정 확률): 플레이 방식을 바꾸는 고정 효과
-- 구역 전용 세트: 필드 구역마다 그 구역에서만 떨어지는 장비 세트가 있다. 이름 앞에 구역 이름이 붙고 같은 세트 2 / 3부위를 끼면 보너스.
-- (구역 N 의 일반 / 엘리트 / 보스 드랍 중 ZoneSetChance 확률로 그 구역 세트 장비가 나온다 -> 갖고 싶으면 그 구역으로 가야 한다)
Config.Sets.ZoneSetChance = 0.5
-- 세트 각인: 뽑기로 얻은 장비는 세트가 안 붙는 게 보통이다. 필드에서 모은 "세트 조각"을 써서 아무 장비나 그 구역의 세트 장비로 바꿀 수 있다
--   (등급 / 강화 / 옵션은 그대로, 세트만 바뀐다). 조각은 구역마다 따로 쌓이고 그 구역 몬스터에게서만 나온다 -> 세트를 맞추려면 필드를 돌아야 한다.
Config.Sets.Imprint = {
	Cost = { 6, 12, 24, 48, 96 },          -- 등급별 필요 세트 조각 (그 구역 조각)
	DropNormal = 0.55,                     -- 일반 몬스터가 조각 1개를 떨굴 확률
	DropElite = { 3, 5 },                  -- 엘리트가 떨구는 조각 수 (최소, 최대)
	DropBoss = 25,                         -- 구역 군주
	DropGoblin = 10,                       -- 황금 고블린
	DropEvent = 20,                        -- 공개 이벤트 보스
}
Config.Sets.ZoneKeys = {}
do
	local zoneSets = {
		{ Name = "초원의 수호", Prefix = "초원", Color = Color3.fromRGB(130, 220, 110), Icon = "🌾",
			B2 = { { Stat = "Health", Value = 80 } }, B3 = { { Stat = "Health", Value = 150 }, { Stat = "Speed", Value = 1.5 } } },
		{ Name = "숲의 축복", Prefix = "숲", Color = Color3.fromRGB(80, 200, 120), Icon = "🌲",
			B2 = { { Stat = "Xp", Value = 0.10 } }, B3 = { { Stat = "Xp", Value = 0.18 }, { Stat = "Luck", Value = 0.15 } } },
		{ Name = "폐허의 의지", Prefix = "폐허", Color = Color3.fromRGB(200, 170, 120), Icon = "🏚",
			B2 = { { Stat = "Damage", Value = 0.06 } }, B3 = { { Stat = "Damage", Value = 0.10 }, { Stat = "Health", Value = 150 } } },
		{ Name = "사막의 태양", Prefix = "사막", Color = Color3.fromRGB(255, 210, 90), Icon = "🏜",
			B2 = { { Stat = "Crit", Value = 0.06 } }, B3 = { { Stat = "Crit", Value = 0.10 }, { Stat = "Damage", Value = 0.06 } } },
		{ Name = "서리의 숨결", Prefix = "서리", Color = Color3.fromRGB(150, 225, 255), Icon = "❄",
			B2 = { { Stat = "Haste", Value = 0.08 } }, B3 = { { Stat = "Haste", Value = 0.12 }, { Stat = "Health", Value = 200 } } },
		{ Name = "용암의 심장", Prefix = "용암", Color = Color3.fromRGB(255, 110, 50), Icon = "🌋",
			B2 = { { Stat = "Damage", Value = 0.10 } }, B3 = { { Stat = "Damage", Value = 0.15 }, { Stat = "Crit", Value = 0.08 } } },
		{ Name = "암흑의 서약", Prefix = "암흑", Color = Color3.fromRGB(180, 110, 255), Icon = "🦇",
			B2 = { { Stat = "Luck", Value = 0.20 } }, B3 = { { Stat = "Luck", Value = 0.30 }, { Stat = "Damage", Value = 0.10 } } },
		{ Name = "심연의 지배", Prefix = "심연", Color = Color3.fromRGB(255, 80, 140), Icon = "🌀",
			B2 = { { Stat = "Damage", Value = 0.15 } }, B3 = { { Stat = "Damage", Value = 0.22 }, { Stat = "Haste", Value = 0.15 }, { Stat = "Shot", Value = 1 } } },
	}
	for zone, def in ipairs(zoneSets) do
		local key = "Zone" .. zone
		Config.Sets[key] = { Name = def.Name, Prefix = def.Prefix, Icon = def.Icon, Color = def.Color, Zone = zone, Bonuses = { [2] = def.B2, [3] = def.B3 } }
		Config.Sets.ZoneKeys[zone] = key
	end
end

-- 아이템 이름 (구역 전용 세트면 앞에 구역 이름: "[용암] 화염 투구")
function Config.ItemDisplayName(item)
	local name = Config.GetGearSlot(item.Slot).Names[item.Rarity]
	local set = item.Set and Config.Sets[item.Set]
	if set and set.Prefix then
		return string.format("%s %s %s", set.Icon, set.Prefix, name)
	end
	return name
end

Config.Uniques = {
	Order = { "Split", "Chrono", "Slayer", "Fortune" },
	Chance = 0.30,
	Split = { Name = "분열의 총탄", Desc = "발사하는 탄이 +1발", Effects = { { Stat = "Shot", Value = 1 } } },
	Chrono = { Name = "시간 왜곡", Desc = "스킬 쿨타임 -25%", Effects = { { Stat = "Haste", Value = 0.25 } } },
	Slayer = { Name = "학살자", Desc = "공격력 +25%", Effects = { { Stat = "Damage", Value = 0.25 } } },
	Fortune = { Name = "행운의 별", Desc = "행운 +50%, 경험치 +30%", Effects = { { Stat = "Luck", Value = 0.5 }, { Stat = "Xp", Value = 0.3 } } },
}

Config.BonusNames = { Health = "최대 체력", Crit = "치명타 확률", Speed = "이동 속도", Damage = "공격력", Xp = "경험치", Luck = "행운", Haste = "스킬 쿨타임 감소", Shot = "탄 수" }
function Config.FormatBonus(stat, value)
	local name = Config.BonusNames[stat] or stat
	if stat == "Health" then
		return string.format("%s +%d", name, math.floor(value + 0.5))
	elseif stat == "Speed" then
		return string.format("%s +%.1f", name, value)
	elseif stat == "Shot" then
		return string.format("%s +%d", name, math.floor(value + 0.5))
	end
	return string.format("%s +%d%%", name, math.floor(value * 100 + 0.5))
end

-- 스탯 설명 (인벤토리 / 정보 탭에서 "이게 뭔데?"를 풀어준다)
Config.StatDesc = {
	Health = { Name = "최대 체력", Desc = "버틸 수 있는 피해량. 높을수록 덜 죽어요" },
	Crit = { Name = "치명타 확률", Desc = "공격이 치명타(피해 2배)로 터질 확률" },
	Speed = { Name = "이동 속도", Desc = "걷고 달리는 속도" },
	Damage = { Name = "공격력", Desc = "내 모든 공격(총·스킬)의 피해량이 늘어나요" },
	Xp = { Name = "경험치 획득", Desc = "몬스터를 잡을 때 경험치를 더 받아 레벨업이 빨라져요" },
	Luck = { Name = "행운", Desc = "필드 몬스터가 떨어뜨리는 장비가 높은 등급(영웅 이상)으로 나올 확률이 올라가요" },
	Haste = { Name = "스킬 쿨타임 감소", Desc = "응급 치료 · 궁극기를 더 자주 쓸 수 있어요 (최대 60%)" },
	Shot = { Name = "추가 탄", Desc = "한 번 쏠 때 나가는 탄이 늘어나요 (부채꼴)" },
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
	if item.Unique then score += 80 end
	if item.Set then score += 30 end
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
-- 던전 입장 제한: 하루 무료 입장 FreeDaily 회 (UTC 날짜 기준 초기화) + 열쇠. 열쇠는 시간이 지나도 차지 않고
-- 필드 구역 군주를 잡을 때 낮은 확률(BossDropChance)로만 나온다 (+ 출석 / 미션 / 상점 보상). 열쇠가 있으면 무료 횟수를 다 써도 더 들어갈 수 있다.
Config.Keys = {
	Start = 1,
	Max = 30,
	RegenSeconds = 0,     -- 0 = 시간 회복 없음
	FreeDaily = 3,
	BossDropChance = 0.15,  -- (구역별 값이 없을 때 쓰는 기본값)
	-- 구역별 열쇠 드랍 확률: 앞 구역 군주는 자주 나오는 대신 열쇠가 잘 안 나오고, 뒤 구역 군주는 드문 대신 잘 나온다 (앞 구역 반복 사냥으로 열쇠를 쓸어 담지 못하게)
	BossDropByZone = { 0.04, 0.06, 0.09, 0.13, 0.18, 0.25, 0.33, 0.45 },
	DailyDropCap = 8,       -- (예전 값)
	-- 열쇠는 던전 난이도와 같은 3단계: 쉬움 / 보통 / 어려움 열쇠. 앞 구역 군주는 낮은 단계, 뒤 구역 군주는 높은 단계 열쇠를 준다 (높은 열쇠는 낮은 난이도에도 쓸 수 있다).
	TierNames = { "쉬움 열쇠", "보통 열쇠", "어려움 열쇠" },
	TierIcons = { "🗝", "🔑", "🏆" },
	DropByZone = {
		{ Tier = 1, Chance = 0.10 }, { Tier = 1, Chance = 0.16 },
		{ Tier = 2, Chance = 0.10 }, { Tier = 2, Chance = 0.15 }, { Tier = 2, Chance = 0.20 },
		{ Tier = 3, Chance = 0.12 }, { Tier = 3, Chance = 0.18 }, { Tier = 3, Chance = 0.25 },
	},
	DailyDropCapByTier = { 8, 5, 3 }, -- 하루에 군주 드랍으로 얻을 수 있는 단계별 열쇠 최대 개수 (UTC 날짜 기준)
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
		BannerDragon = { Name = "용의 깃발", Desc = "등 뒤에 꽂는 꾸미기 깃발 (능력치 없음)", ProductId = 0, Grant = { Banner = "Dragon" } },
		MountCarpet = { Name = "마법 양탄자", Desc = "발밑에 떠 있는 탈것 꾸미기 (능력치 없음)", ProductId = 0, Grant = { Mount = "Carpet" } },
		MountPhoenix = { Name = "불사조", Desc = "불꽃 날개 탈것 꾸미기 (능력치 없음)", ProductId = 0, Grant = { Mount = "Phoenix" } },
	},
	PassOrder = { "VIP" },
	ProductOrder = { "TimeSkip1h", "TimeSkip8h", "TrainSlot", "KeyPack", "XpBooster", "LuckBooster", "BagPlus", "TicketPack", "AuraVoid", "BannerDragon", "MountCarpet", "MountPhoenix" },
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

-- 깃발: 등 뒤에 꽂는 꾸미기. 탈것: 발밑에 떠 있는 꾸미기 (둘 다 능력치 / 이동속도 없음, 다른 플레이어에게도 보임)
Config.Banners = {
	Order = { "Scout", "Hero", "Gold", "Dragon" },
	Scout = { Name = "수련생 깃발", Color = Color3.fromRGB(90, 150, 255), Unlock = "Free" },
	Hero = { Name = "용사의 깃발", Color = Color3.fromRGB(230, 70, 70), Unlock = { Ach = "zone4" } },
	Gold = { Name = "황금 깃발", Color = Color3.fromRGB(255, 205, 70), Unlock = { Pass = "VIP" } },
	Dragon = { Name = "용의 깃발", Color = Color3.fromRGB(150, 60, 230), Sparks = true, Unlock = { Product = "BannerDragon" } },
}
Config.Mounts = {
	Order = { "Board", "Cloud", "Carpet", "Phoenix" },
	Board = { Name = "호버보드", Color = Color3.fromRGB(80, 220, 255), Style = "Board", Unlock = "Free" },
	Cloud = { Name = "구름", Color = Color3.fromRGB(190, 225, 255), Style = "Cloud", Unlock = { Ach = "boss10" } },
	Carpet = { Name = "마법 양탄자", Color = Color3.fromRGB(190, 50, 90), Style = "Carpet", Unlock = { Product = "MountCarpet" } },
	Phoenix = { Name = "불사조", Color = Color3.fromRGB(255, 100, 40), Style = "Phoenix", Unlock = { Product = "MountPhoenix" } },
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
	Gates = {},                            -- (예전: 레벨 10 / 20 / 30 / 40 에서 멈추고 시간 돌파 -> 기다리는 느낌이라 없앴다. 이제 막힘 없이 성장하고 골드는 환생으로 더 번다)
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
	level = math.clamp(math.floor(level or 0), 0, Config.Weapon.MaxLevel)
	local low, high = 1, #tiers
	while low < high do -- 이진 탐색: MinLevel 이 level 이하인 마지막 무기
		local mid = (low + high + 1) // 2
		if tiers[mid].MinLevel <= level then
			low = mid
		else
			high = mid - 1
		end
	end
	return tiers[low]
end

-- 강화 단계 -> 지금 몇 번째 무기인지 (1~100)
function Config.GetWeaponTierIndex(level)
	return Config.GetWeaponTier(level).Index
end

-- 지금 무기 안에서의 강화 단계 (0 ~ Steps-1). 마지막 단계에서 강화에 성공하면 다음 무기로 바뀐다.
function Config.GetWeaponStage(level)
	local tier = Config.GetWeaponTier(level)
	return math.max(0, math.floor(level or 0) - tier.MinLevel)
end

-- 진행 막대 글자: "▰▰▰▱▱▱▱▱▱▱"
function Config.StageBar(level)
	local tier = Config.GetWeaponTier(level)
	local stage = Config.GetWeaponStage(level)
	return string.rep("▰", stage) .. string.rep("▱", tier.Steps - stage)
end

-- 화면에 보이는 무기 표시: "[1/100] 녹슨 권총 +3/10"
function Config.FormatWeapon(level)
	local tier = Config.GetWeaponTier(level)
	return string.format("[%d/%d] %s +%d/%d", tier.Index, Config.Weapon.WeaponCount, tier.Name, Config.GetWeaponStage(level), tier.Steps)
end

-- level -> level+1 강화 비용 (사다리 전체에서 조금씩 올라간다)
function Config.GetEnhanceCost(level)
	return math.floor(Config.Weapon.BaseCost * Config.Weapon.CostGrowth ^ level)
end

-- level -> level+1 강화 성공 확률 (실패해도 단계는 내려가지 않고 골드만 소모)
function Config.GetEnhanceChance(level)
	return math.max(0.5, 0.95 - 0.0015 * level * Config.Weapon.LevelScale)
end

-- 공격력 배율: 단계가 오를수록 가파르게 + 시대가 바뀔 때마다 한 번 더 (시대 안에서 무기 종류가 바뀌어도 항상 "더 세졌다"가 느껴지게)
function Config.GetDamageMultiplier(level)
	local era = Config.GetWeaponTier(level).Era
	local effective = level * Config.Weapon.LevelScale -- 단계가 820까지 늘어도 최종 위력은 예전(326단계)과 같다
	return (1 + 0.04 * effective + 0.00012 * effective * effective) * 1.4 ^ (era - 1)
end

-- 무기 모형 크기 배율 (너무 커지지 않게 완만하게)
function Config.GetWeaponScale(level)
	return 1 + 0.22 * math.log(1 + level * Config.Weapon.LevelScale)
end

return Config
