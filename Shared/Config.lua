-- Config (ReplicatedStorage 안의 ModuleScript, 이름: Config)
-- 서버/클라이언트가 같이 쓰는 밸런스 값과 계산 함수. 숫자만 바꿔가며 조절하면 됨.

local Config = {}

Config.StartGold = 0 -- 처음 접속했을 때 지급되는 골드 (튜토리얼 보상만으로는 4번째 강화 비용에 못 미치게 0)

------------------------------------------------------------
-- 플레이어 기본 능력치 / 스탯 포인트 효과
------------------------------------------------------------
Config.Player = {
	BaseHealth = 100,
	WalkSpeed = 30,         -- 기본 이동 속도 (달리기 키는 없애서 항상 이 속도로 달린다)
	RunSpeed = 32,          -- (대시 속도 계산에만 쓴다)
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
-- NEAR MISS(대시로 아슬아슬하게 피하기): 연속으로 성공할수록 공격력이 누적해서 올라간다 (마지막 성공 후 Duration 초가 지나면 사라진다)
Config.WeakExposeSeconds = 6.5 -- 보스 약점을 맞혔을 때 약점이 노출되어 피해 x3 가 유지되는 시간(초)
Config.NearMiss = { DamagePerStack = 0.03, MaxStacks = 10, Duration = 8, DecayStep = 4 } -- 최대 +30% (자동 공격만 써도 기본 DPS 에서 손해 보지 않게 낮춤). Duration 뒤에는 DecayStep(4)초마다 1스택씩 줄어든다
function Config.GetNearMissDuration(player) -- 기운 집중 스킬 레벨 반영
	return Config.NearMiss.Duration + Config.SkillUpgrade.FocusDuration * math.max(0, (player:GetAttribute("SkillLv_Focus") or 1) - 1)
end

-- 기운 집중: 줄어들다 멈추는 바닥 스택 (레벨 1 = 0, 최대 레벨 = 최대 스택의 절반): 끊겨도 어느 정도는 남는다
function Config.GetNearMissFloor(player)
	local level = math.max(1, player:GetAttribute("SkillLv_Focus") or 1)
	return math.floor(Config.NearMiss.MaxStacks * 0.5 * (level - 1) / math.max(1, Config.SkillUpgrade.MaxLevel - 1))
end

Config.SkillUpgrade = {
	MaxLevel = 10,
	BaseCost = 400,
	CostGrowth = 1.5,
	CooldownPerLevel = 0.025,   -- 레벨당 쿨타임 -2.5%
	-- 레벨당 증가량 (스킬마다 다름)
	BarrierDuration = 0.4,      -- 방벽 지속시간 +0.4초
	BlastMult = 0.18,           -- 충격파 피해 +18% (기본 대비)
	BlastRadius = 0.8,          -- 충격파 범위 +0.8
	HealRatio = 0.01,           -- 치료량 +1%p (최대 레벨 17%)
	FocusDuration = 0.8,        -- 기운 집중: 레벨당 NEAR MISS 유지 시간 +0.8초 (10레벨 +7.2초)
	UltTargets = 2 / 3,         -- 데드아이 대상 수: 레벨당 +0.67마리 (1레벨 6마리 -> 10레벨 12마리)
	UltMult = 0.15,             -- 궁극기 피해 +15%
}
function Config.GetSkillUpgradeCost(level)
	return math.floor(Config.SkillUpgrade.BaseCost * Config.SkillUpgrade.CostGrowth ^ (level - 1))
end

-- 펫: 골드를 한 번 내서 "펫 기능"을 열면 따라다니는 동료가 생긴다. 골드로 레벨을 올릴 때마다 기능이 하나씩 늘어난다 (자동 루팅 / 공격 속도 / 보조 사격 ...).
-- 외형은 능력과 상관없는 꾸미기: 필드 군주를 쓰러뜨리거나 칭호(업적)를 따면 새 외형이 열리고, 열린 외형 중에서 마음대로 고른다.
Config.Pet = {
	UnlockCost = 5000,       -- 펫 기능 열기 (한 번)
	MaxLevel = 15,
	LevelCostBase = 3000,    -- 레벨 1 -> 2 비용
	LevelCostGrowth = 1.45,  -- 레벨이 오를수록 비용이 늘어난다
	-- 기능: 그 레벨에 도달하면 열린다 (아래 레벨 기능이 모두 합쳐진다). Stats = 플레이어 Attribute 에 더해지는 값
	Functions = {
		{ Level = 1,  Icon = "🐾", Name = "Companion",         Desc = "Your pet follows you · Move speed +1",                 Stats = { PetSpeed = 1 } },
		{ Level = 2,  Icon = "📘", Name = "Learning",         Desc = "XP +5%",                                     Stats = { PetXp = 0.05 } },
		{ Level = 3,  Icon = "💥", Name = "Power",           Desc = "Attack +4%",                                     Stats = { PetDamage = 0.04 } },
		{ Level = 5,  Icon = "🧲", Name = "Auto-Loot",    Desc = "Loot within a 50 radius gets pulled in automatically",  Stats = { PetLoot = 50 } },
		{ Level = 7,  Icon = "🎯", Name = "Focus",         Desc = "Crit chance +4%",                                Stats = { PetCrit = 0.04 } },
		{ Level = 8,  Icon = "🛡", Name = "Guardian",         Desc = "Invincible for 3s when HP drops below 25% (every 90s)", Stats = { PetGuard = 1 } },
		{ Level = 10, Icon = "⏩", Name = "Haste",         Desc = "Attack speed +10%",                                 Stats = { PetAtkSpeed = 0.10 } },
		{ Level = 12, Icon = "🧲", Name = "Wide Loot",    Desc = "Auto-loot radius grows to 100",                Stats = { PetLoot = 50 } },
		{ Level = 13, Icon = "🔫", Name = "Support Fire",    Desc = "Your pet fires a missile at a nearby enemy every 1.6s",    Stats = { PetShoot = 1 } },
		{ Level = 15, Icon = "✨", Name = "Great Awakening",       Desc = "Gold +10% · Skill cooldown -10%",              Stats = { PetGold = 0.10, PetHaste = 0.10 } },
	},
	-- 외형: Unlock = Free / { Zone = N } (필드 N구역 군주를 쓰러뜨림) / { Ach = 업적Id } (그 업적을 달성해 칭호를 얻음)
	LookOrder = { "Orb", "Slime", "Fox", "Bat", "Golem", "Spirit", "Dragon", "Phoenix", "Star" },
	Looks = {
		Orb     = { Name = "Light Orb",     Icon = "🔮", Unlock = "Free", Hint = "From the start" },
		Slime   = { Name = "Slime",     Icon = "🟢", Unlock = { Zone = 1 }, Hint = "Defeat the Zone 1 Lord" },
		Fox     = { Name = "Little Fox",  Icon = "🦊", Unlock = { Zone = 2 }, Hint = "Defeat the Zone 2 Lord" },
		Bat     = { Name = "Bat",       Icon = "🦇", Unlock = { Zone = 3 }, Hint = "Defeat the Zone 3 Lord" },
		Golem   = { Name = "Stone Golem",    Icon = "🪨", Unlock = { Zone = 4 }, Hint = "Defeat the Zone 4 Lord" },
		Spirit  = { Name = "Light Spirit",  Icon = "🧚", Unlock = { Ach = "dungeon10" }, Hint = "Title 『Dungeon Regular』" },
		Dragon  = { Name = "Baby Dragon",    Icon = "🐲", Unlock = { Ach = "boss10" }, Hint = "Title 『Boss Hunter』" },
		Phoenix = { Name = "Phoenix",     Icon = "🔥", Unlock = { Zone = 7 }, Hint = "Defeat the Zone 7 Lord" },
		Star    = { Name = "Shooting Star",     Icon = "⭐", Unlock = { Ach = "zone8" }, Hint = "Title 『Abyss Conqueror』" },
	},
	-- 색: 외형 위에 입히는 색 (처음 몇 개는 기본 제공)
	Colors = {
		Color3.fromRGB(150, 230, 255), Color3.fromRGB(255, 160, 80), Color3.fromRGB(110, 220, 120), Color3.fromRGB(190, 110, 255),
		Color3.fromRGB(255, 110, 150), Color3.fromRGB(255, 225, 110), Color3.fromRGB(235, 235, 245), Color3.fromRGB(100, 140, 255),
	},
}
function Config.GetPetLevelCost(level)
	return math.floor(Config.Pet.LevelCostBase * Config.Pet.LevelCostGrowth ^ (level - 1))
end
-- 이 레벨에서 켜지는 기능들의 능력치 합 { PetSpeed = ..., PetLoot = ... }
function Config.GetPetStats(level)
	local totals = {}
	for _, fn in ipairs(Config.Pet.Functions) do
		if fn.Level <= level then
			for attr, value in pairs(fn.Stats) do
				totals[attr] = (totals[attr] or 0) + value
			end
		end
	end
	return totals
end

------------------------------------------------------------
-- 튜토리얼 미션 (처음 1~5분): 쉬운 목표 -> 즉시 보상을 계속 이어서 보여준다
-- Target: TutorialService.SetTargets 로 넘겨주는 위치 키 (Dummy / Anvil / Gacha / Field / Gate)
-- FreeEnhance: 이 미션 동안 무기 강화가 공짜 + 100% 성공
------------------------------------------------------------
Config.Tutorial = {
	Steps = {
		{ Text = "🎯 Shoot the dummy at the training ground next to the forge! Click the mouse to fire (R key = auto-aim)", Stat = "DummyHits", Goal = 8, Target = "Dummy", TargetName = "Dummy",
			Reward = { Gold = 100 } },
		-- 강화 2번이 끝나면 슬롯 릴이 돌면서 겹치지 않는 부위 장비 3개를 바로 준다 (Reel). 뽑기 머신은 마을에 있다고 카드로 알려 주고, 일일 퀘스트에도 뽑기가 있다.
		{ Text = "Upgrade your weapon at the anvil! The more you upgrade, the stronger it gets, and a new weapon unlocks every 15 levels (free)", Stat = "Enhances", Goal = 2, Target = "Anvil", TargetName = "Anvil", FreeEnhance = true, Reel = true,
			Reward = { Tickets = 1, Gold = 150 } },
		-- 이야기: 필드 군주를 쓰러뜨리면 열쇠가 떨어져 바닥이 갈라지고 -> 던전 -> 던전 보스를 쓰러뜨리면 최후의 군주가 나타나 압도당하고 -> 마을에서 전리품으로 뽑기 / 강화
		{ Text = "Head east to the field and defeat the first zone's Lord (👑)! (You'll get your first gear when you enter the field) ...You sense an ominous presence. Be careful!", Stat = "BossKills", Goal = 1, Target = "Field", TargetName = "Field Entrance", Doom = true,
			Intro = { { Key = "Q", Title = "Q Key: Dash!", Text = "Good to know for the field: press Q to burst forward in your moving direction (2 in a row, recharges every 3s). Narrowly dodge enemy shots for a bonus!", Duration = 6 } },
			IntroAnyZone = true, -- (마을에서 나가는 길에 읽는다. 첫 장비 지급 릴은 필드에 들어선 뒤에 뜬다)
			Reward = { Gold = 300, Xp = 100 } },
		-- 군주가 떨어뜨린 열쇠로 던전이 열린다 (자동으로 들어간다). 던전은 짧게(30초 버티기) + 받는 피해 절반. 보스를 쓰러뜨리면 최후의 군주가 나타나 쓰러진다 (그때 이 미션이 끝난다)
		-- 중간에 졌다면 마을의 던전 게이트에서 다시 들어가도 같은 장면으로 이어진다.
		{ Text = "🗝 The key dropped by the Lord opened a dungeon! Clear the dungeon ...You sense an even greater presence", Stat = "FieldDeaths", Goal = 1, Target = "Gate", TargetName = "Dungeon Gate", Dungeon = true, DungeonDoom = true,
			Reward = { Gold = 4000, Tickets = 10, Keys = 1, Xp = 150 } }, -- 쓰러져도 전리품(재화)은 남는다 -> 아래 미션에서 바로 쓰게 한다
		{ Text = "💀 The Lord vanished, leaving only the words \"I'll be waiting at the end of the 8th land.\" You need to get stronger! Use your loot tickets for a 10-pull at the gacha machine!", Stat = "Rolls", Goal = 10, Target = "Gacha", TargetName = "Gacha Machine", RollMode = "Hero", ShowQuests = true, -- 여기서부터 화면에 오늘의 퀘스트가 나타난다
			Reward = { Gold = 500, Xp = 100 } },
		-- EvolveToTier: 이 번째 무기(3 = 기관단총)가 될 때까지 필요한 강화 횟수를 미션이 시작될 때 계산해서 목표로 쓴다. {무기} = 그 무기 이름
		{ Text = "💰 Use your gold to upgrade your weapon to +15 and unlock the SMG! Once unlocked, you can pick any weapon you like in the Weapons tab", Stat = "Enhances", Goal = 15, EvolveToTier = 2, Target = "Anvil", TargetName = "Anvil",
			Reward = { Tickets = 2, Xp = 150 } },
	},
}

------------------------------------------------------------
-- 환생(프레스티지): 최고 레벨에서 레벨을 1로 되돌리고 영구 공격력 보너스를 얻는다
------------------------------------------------------------
-- 환생: 최고 레벨에서 레벨을 1로 되돌리는 대신 영구 보너스. 골드를 더 벌려면 환생한다 (영구 공격력 + 골드 획득량).
Config.Prestige = { Max = 10, DamagePerRank = 0.05, GoldPerRank = 0.10, Level = 50 } -- Level: 환생할 수 있는 최소 레벨 (최대 레벨을 200 으로 늘려도 환생은 예전처럼 50 부터)
function Config.GoldBonus(player)
	return 1 + (player:GetAttribute("Prestige") or 0) * Config.Prestige.GoldPerRank + (player:GetAttribute("PetGold") or 0) -- 환생 + 펫(대각성)
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
Config.Dungeon.MutatorChance = 0.9 -- 거의 매번 변이가 붙는다 (Visual = 화면 분위기까지 확 바뀐다)
Config.Dungeon.Mutators = {
	Order = { "Giant", "Swift", "Swarm", "Golden", "Furious", "Dark", "Blood", "Elite" },
	Giant = { Name = "Giant", Icon = "🗿", Desc = "Monster HP x1.6, rewards x1.5", HealthMult = 1.6, GoldMult = 1.5 },
	Swift = { Name = "Swift", Icon = "💨", Desc = "Monsters move/attack faster, rewards x1.3", SpeedMult = 1.5, IntervalMult = 0.7, GoldMult = 1.3 },
	Swarm = { Name = "Swarm", Icon = "🐀", Desc = "Monster count x1.6 (HP x0.7), rewards x1.4", CountMult = 1.6, HealthMult = 0.7, GoldMult = 1.4 },
	Golden = { Name = "Golden Day", Icon = "💰", Desc = "Gold/XP x2, monster HP x1.2", HealthMult = 1.2, GoldMult = 2, Visual = "Gold" },
	Furious = { Name = "Frenzy", Icon = "😡", Desc = "Monster attack x1.5, rewards x1.5", DamageMult = 1.5, GoldMult = 1.5, Visual = "Blood" },
	Dark = { Name = "Pitch Black", Icon = "🌑", Desc = "The screen goes dark (fight by the glow of monster eyes), monster HP x1.15, rewards x1.6", HealthMult = 1.15, GoldMult = 1.6, Visual = "Dark" },
	Fog = { Name = "Thick Fog", Icon = "🌫", Desc = "You can't see far, monsters pop out suddenly (speed x1.2), rewards x1.4", SpeedMult = 1.2, GoldMult = 1.4, Visual = "Fog" },
	Blood = { Name = "Blood Moon", Icon = "🩸", Desc = "A red moon rises: monster speed x1.25 · attack x1.25, rewards x1.5", SpeedMult = 1.25, DamageMult = 1.25, GoldMult = 1.5, Visual = "Blood" },
	Elite = { Name = "Elite Day", Icon = "👑", Desc = "Monster count x0.6, HP x2.0 · attack x1.2, rewards x1.7", CountMult = 0.6, HealthMult = 2.0, DamageMult = 1.2, GoldMult = 1.7, Visual = "Elite" },
}

------------------------------------------------------------
-- 액티브 스킬 (오버워치 느낌): 필드 / 던전에서 사용. Z 방벽 · F 충격파 · C 응급 치료 · V 궁극기(게이지)
-- 스킬 데미지 = 일반 공격 데미지 x Mult. 궁극기는 공격할수록(발사 1회 = +ChargePerShot) 게이지가 찬다.
------------------------------------------------------------
Config.Skills = {
	Order = { "Heal", "Ult" }, -- 방벽 / 충격파는 임팩트가 약해서 뺐다 (정의만 남겨둠)
	Barrier = { Name = "Energy Barrier", Icon = "🛡", Key = "Z", KeyCode = "Z", Cooldown = 14, Duration = 3,
		Desc = "A barrier that blocks all damage for 3s" },
	Blast = { Name = "Shockwave", Icon = "💥", Key = "F", KeyCode = "F", Cooldown = 8, Radius = 16, Range = 90, Mult = 3,
		Desc = "Explodes where you aim (radius 16, attack x3)" },
	Heal = { Name = "First Aid", Icon = "💚", Key = "C", KeyCode = "C", Cooldown = 30, Radius = 40, Ratio = 0.08,
		Desc = "Restores 8% HP to you and nearby party members (+1%p per skill level)" },
	Ult = { Name = "Deadeye", Icon = "🎯", Key = "V", KeyCode = "V", Cooldown = 3, Radius = 110, Mult = 8, Cost = 100, MaxTargets = 6, Volleys = 12, VolleyGap = 0.09, -- 대상 수 / 일제 사격 횟수를 줄여 렉을 막는다 (빔 / 피해 숫자 / 폭발 효과가 대상 x 횟수만큼 생긴다)
		ShotsPerTarget = 8, ShotGap = 0.03,
		Missiles = 12, PoolMult = 4, RepeatDecay = 0.82, -- RepeatDecay: 같은 적에게 미사일이 거듭 맞을수록 한 발 피해가 이 배율씩 줄어든다 (한 마리에 12발이면 합계가 약 5발 분량)
		 -- 미사일 총 발수(대상 수와 상관없이 고정, 대상들에게 번갈아 나눠 간다) / 총 피해 배율 (한 마리면 12발이 전부 그 적에게 꽂힌다)
		Desc = "Ultimate: use it when the gauge is full! Locks onto nearby enemies, then fires 12 missiles split between them (nearest 6 first, up to 12 as the skill levels up). Against a single target like a boss, all 12 hit it" },
	ChargePerShot = 4,
	-- 패시브 스킬 (스킬 강화 창에서 골드로 레벨업, 스킬 바에는 안 나온다)
	Focus = { Name = "Aura Focus", Icon = "⚡", Key = "Passive", Cooldown = 0, Passive = true,
		Desc = "The attack bonus built up by NEAR MISS lasts longer. At higher levels, part of the bonus (half at max level) stays even if your streak breaks" },
	UpgradeOrder = { "Heal", "Ult", "Focus" }, -- 스킬 강화 창 / 저장에 쓰는 목록
}

------------------------------------------------------------
-- 보스 변종: 던전에 들어갈 때마다 하나가 뽑혀 보스의 성격이 달라진다
-- Weights: 기본 패턴 비중에 곱해지는 배율 (Fan Ring Spiral Meteor Slam Summon)
Config.Dungeon.BossVariants = {
	Order = { "Berserk", "Arcane", "Titan", "Summoner" },
	Berserk = { Prefix = "Berserk", Color = Color3.fromRGB(255, 60, 40), SpeedMult = 1.8, DamageMult = 1.2, HealthMult = 0.9, SizeMult = 0.9,
		Weights = { Fan = 1.5, Slam = 2.5 }, Desc = "Fast and fierce" },
	Arcane = { Prefix = "Arcane", Color = Color3.fromRGB(150, 90, 255), SpeedMult = 1, DamageMult = 1.1, HealthMult = 1, SizeMult = 1,
		Weights = { Spiral = 2.5, Meteor = 2.5 }, Desc = "Rains down bullet barrages and meteors" },
	Titan = { Prefix = "Giant", Color = Color3.fromRGB(150, 150, 160), SpeedMult = 0.8, DamageMult = 1, HealthMult = 1.5, SizeMult = 1.3,
		Weights = { Slam = 3, Ring = 1.5 }, Desc = "Slow but tough, with powerful shockwaves" },
	Summoner = { Prefix = "Commander", Color = Color3.fromRGB(110, 220, 120), SpeedMult = 1, DamageMult = 1, HealthMult = 0.9, SizeMult = 1,
		Weights = { Summon = 4 }, Desc = "Constantly summons minions" },
}

-- 방 이벤트: 전투 사이에 끼어드는 특별한 방
Config.Dungeon.Events = {
	Order = { "Treasure", "Trap", "Rest" },
	Treasure = { Name = "💎 Treasure Room", Desc = "There's a treasure chest! Get close to open it" },
	Trap = { Name = "☄ Trap Room", Desc = "Meteors are falling! Avoid the red circles (survive to the end for a reward)" },
	Rest = { Name = "⛲ Rest Room", Desc = "The spring fully restores your HP + one more perk" },
}

-- 던전 특성 (뱀파이어 서바이벌식): 웨이브 클리어마다 3개 중 1개를 골라 그 던전 동안만 쌓인다
-- Attr: 플레이어 Attribute(스택 수) / Max: 최대 스택 / Special: 총알이 바뀌는 특수 특성(항상 1개 이상 후보에 포함)
------------------------------------------------------------
Config.Perks = {
	Order = { "Pierce", "Boom", "Chain", "Vamp", "Power", "Rapid", "Crit", "Vital" },
	Pierce = { Name = "Piercing Shot", Icon = "➳", Attr = "PerkPierce", Max = 3, Special = true,
		Desc = "Shots pierce +1 more enemy" },
	Boom   = { Name = "Explosive Shot", Icon = "💥", Attr = "PerkBoom", Max = 3, Special = true,
		Desc = "Explodes around the enemy hit (40% of damage, radius grows per level)" },
	Chain  = { Name = "Chain Lightning", Icon = "⚡", Attr = "PerkChain", Max = 3, Special = true,
		Desc = "Lightning jumps from the enemy hit to +1 nearby enemy (60% of damage)" },
	Vamp   = { Name = "Lifesteal", Icon = "🩸", Attr = "PerkVamp", Max = 3, Special = true,
		Desc = "Restore +1 HP each time a shot hits" },
	Power  = { Name = "Heavy Hit", Icon = "🔥", Attr = "PerkPower", Max = 6,
		Desc = "Attack +18%" },
	Rapid  = { Name = "Rapid Fire", Icon = "⏩", Attr = "SpeedPoints", Max = 10,
		Desc = "Attack speed +8%" },
	Crit   = { Name = "Weak Spot", Icon = "🎯", Attr = "CritPoints", Max = 15,
		Desc = "Crit chance +4%" },
	Vital  = { Name = "Toughness", Icon = "❤", Attr = "HealthPoints", Max = 10,
		Desc = "Max HP +15, instant heal" },
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
	StatPhaseTime = 8,       -- 웨이브 클리어 후 특성 고르는 제한 시간(초). 모두 고르면 바로 다음으로, 시간이 지나면 자동 선택
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

-- 던전 진행: 웨이브 없이 "버티기" (정해진 시간 동안 몬스터가 계속 몰려오고, 버티면 보스). 심연 도전(점수제)과 비슷하지만 보스와 보상이 있다.
-- 버텨야 하는 시간: 쫄 구간이 2분을 넘으면 늘어지므로 최대 100초 (고블린 동굴 90초 / 얼음 97초 / 화염 100초)
function Config.Dungeon.GetSurviveSeconds(waves)
	return 60 -- 쫄 구간은 모든 던전에서 60초 (예전 90~100초는 늘어졌다)
end
Config.Dungeon.BossHealthBase = 2.0      -- 버티기 던전 보스 체력 배율: 랜덤 강화로 강해진 플레이어가 보스를 너무 빨리 잡지 않게
Config.Dungeon.BossHealthPerBonus = 0.12 -- 버티는 동안 터진 랜덤 보너스 1번당 보스 체력 +12% (패널티로 강해진 적 체력 배율도 같이 곱해진다)
Config.Dungeon.MonsterLimit = 40     -- 버티기 중 동시에 살아 있는 몬스터가 이 수(파티면 인원에 비례해 늘어남)를 넘기면 위험, OverrunSeconds 동안 못 줄이면 실패
Config.Dungeon.OverrunSeconds = 6
Config.Dungeon.BonusInterval = 6     -- 이 간격(초)마다 랜덤 강화 / 랜덤 패널티가 터진다 (선택 없이 자동 적용)

-- 랜덤 강화 (고르지 않고 무작위로 하나 걸린다. Perk = 기존 특성을 Stacks 단계만큼 올림 / Weight = 나올 확률 가중치)
Config.RunBuffs = {
	{ Icon = "➳",  Name = "Piercing Shot",       Desc = "Shots pierce +1 more enemy",           Perk = "Pierce", Special = true },
	{ Icon = "💥", Name = "Explosive Shot",       Desc = "Explodes around the enemy hit",                Perk = "Boom",   Special = true },
	{ Icon = "⚡", Name = "Chain Lightning",    Desc = "Lightning jumps from the enemy hit",          Perk = "Chain",  Special = true },
	{ Icon = "🩸", Name = "Lifesteal",         Desc = "Restore HP on every hit",              Perk = "Vamp",   Special = true },
	{ Icon = "🔥", Name = "Heavy Hit",         Desc = "Attack +18%",                        Perk = "Power" },
	{ Icon = "⏩", Name = "Rapid Fire",         Desc = "Attack speed +8%",                      Perk = "Rapid" },
	{ Icon = "🎯", Name = "Weak Spot",         Desc = "Crit chance +4%",                    Perk = "Crit" },
	{ Icon = "❤",  Name = "Toughness",       Desc = "Max HP +15, instant heal",           Perk = "Vital" },
	{ Icon = "💢", Name = "Mega Hit",    Desc = "Attack +36%!",                       Perk = "Power", Stacks = 2, Weight = 0.7, Special = true },
	{ Icon = "🌪", Name = "Bullet Storm",    Desc = "Attack speed +24%!",                    Perk = "Rapid", Stacks = 3, Weight = 0.7, Special = true },
	{ Icon = "👁", Name = "Sniper's Eye",  Desc = "Crit chance +12%!",                  Perk = "Crit",  Stacks = 3, Weight = 0.7, Special = true },
	{ Icon = "🛡", Name = "Steel Heart",    Desc = "Max HP +45, instant heal!",          Perk = "Vital", Stacks = 3, Weight = 0.7, Special = true },
	{ Icon = "✨", Name = "Firepower",    Desc = "Heavy Hit + Rapid Fire + Weak Spot all at once",      Combo = { "Power", "Rapid", "Crit" }, Weight = 0.8, Special = true },
	{ Icon = "💚", Name = "Full Heal",    Desc = "HP is fully restored",                   Effect = "Heal" },
	{ Icon = "🔰", Name = "Shield",       Desc = "Invincible for 10s",                     Effect = "Shield" },
	{ Icon = "⭐", Name = "Ultimate Charge",  Desc = "Ultimate gauge fills up",          Effect = "Ult", Weight = 0.8 },
	{ Icon = "💰", Name = "Golden Touch",      Desc = "Gold +20% this dungeon",                Effect = "Gold" },
	{ Icon = "📘", Name = "Spring of Experience",    Desc = "Gain a big chunk of XP",               Effect = "Xp" },
	{ Icon = "🎫", Name = "Lucky Ticket",  Desc = "Gear ticket +1",                       Effect = "Ticket", Weight = 0.35, Special = true },
}

-- 세트 효과 (구역 세트 2부위 = 1단계 / 3부위 = 3단계): 수치가 아니라 "플레이 방식"이 바뀌는 효과. 필드 / 던전 / 심연 어디서나 작동한다.
Config.AugInfo = {
	AugMissile = { Icon = "🚀", Name = "Crit Missile", Desc = "Every crit launches an extra missile that blasts nearby enemies", Color = Color3.fromRGB(255, 150, 60) },
	AugNova = { Icon = "☄", Name = "Kill Burst", Desc = "Killing an enemy causes a big explosion that spreads to nearby enemies", Color = Color3.fromRGB(255, 80, 70) },
	AugOrbit = { Icon = "🌀", Name = "Ricochet Blades", Desc = "Every few shots, a blade bounces between enemies, slashing them in a row (faster-firing weapons throw it more often)", Color = Color3.fromRGB(110, 230, 255) },
	AugStorm = { Icon = "⛈", Name = "Lightning Strike", Desc = "Lightning periodically strikes nearby enemies from the sky", Color = Color3.fromRGB(255, 240, 110) },
	AugFlame = { Icon = "🔥", Name = "Flame Zone", Desc = "Flames linger where an enemy died, burning those who pass", Color = Color3.fromRGB(255, 130, 40) },
	AugExecute = { Icon = "💀", Name = "Execute", Desc = "Enemies (bosses excluded) with very low HP are executed the moment they're hit", Color = Color3.fromRGB(210, 90, 255) },
	AugMeteor = { Icon = "🌠", Name = "Meteor Shower", Desc = "Meteors periodically fall where enemies are most clustered", Color = Color3.fromRGB(255, 190, 90) },
	AugPulse = { Icon = "💥", Name = "Shockwave Shot", Desc = "Explosive shots fly at nearby enemies and burst big on impact", Color = Color3.fromRGB(110, 255, 190) },
}

-- 세트 효과 단계별 수치 (서버 DungeonService 의 공식과 같다. 바꿀 때는 같이 바꾼다). 돌려주는 값: 설명 글자, 한 번 맞을 때 "내 공격력의 몇 배"
local AUG_LEVEL = {
	AugMissile = function(l) return string.format("on crit, %d extra missiles (60%% of the crit damage each)", 1 + l), 0.6 end,
	AugNova = function(l) return string.format("kill → explosion, radius %d, hits up to 8 enemies", 12 + 3 * l), 1.2 + 0.6 * l end,
	AugOrbit = function(l) return string.format("every %d shots a blade bounces across %d enemies", ({ 6, 6, 5, 5, 4, 4 })[math.min(l, 6)], l + 2), 0.9 + 0.4 * l end,
	AugStorm = function(l) return string.format("every %.1fs lightning hits %d enemies", math.max(1.2, 3.4 - 0.5 * l), 2 + l), 1.5 + 0.5 * l end,
	AugFlame = function(l) return string.format("flames radius %d for %ds, damage every 0.5s", 7 + 2 * l, 5 + l), 0.25 + 0.1 * l end,
	AugExecute = function(l) return string.format("enemies below %d%% HP are executed (not bosses)", math.floor(math.min(0.4, 0.1 + 0.06 * l) * 100 + 0.5)), nil end,
	AugMeteor = function(l) return string.format("every %.1fs a meteor, radius %d", math.max(3, 8.5 - 1.5 * l), 14 + 2 * l), 2.2 + 0.8 * l end,
	AugPulse = function(l) return string.format("every %.1fs shock shots at %d enemies, burst radius %d", math.max(2.2, 4.8 - 0.8 * l), 2 + l, 10 + 2 * l), 1.4 + 0.6 * l end,
}
-- 지금 내 공격력으로 한 번 맞힐 때의 대략적인 피해 (치명타 / 콤보 제외, 클라이언트에서 계산)
function Config.BaseAttackEstimate(player)
	local weaponLevel = player:GetAttribute("WeaponLevel") or 0
	local weaponType = Config.GetPlayerWeapon(player)
	return Config.Player.BaseDamage * Config.GetDamageMultiplier(weaponLevel) * weaponType.DamageMult
		* Config.GetLevelDamageMult(player:GetAttribute("Level") or 1)
		* (1 + (player:GetAttribute("GearDamage") or 0) + (player:GetAttribute("TrainDamage") or 0) + (player:GetAttribute("PetDamage") or 0))
end
-- 4셋 / 5셋 / 6셋에서 새로 생기는 효과 (수치만 오르는 게 아니라 투사체 / 지속 효과가 늘어난다. 서버 DungeonService 와 같이 바꾼다)
local AUG_EXTRA = {
	AugMissile = { [4] = "missiles explode (splash)", [5] = "+ second salvo 0.45s later", [6] = "+ a giant missile at the toughest enemy" },
	AugNova = { [4] = "explodes again 0.5s later", [5] = "wider blast + third explosion", [6] = "+ leaves flames behind" },
	AugOrbit = { [4] = "2 blades at once", [5] = "3 blades at once", [6] = "4 blades at once" },
	AugStorm = { [4] = "lightning arcs to 1 nearby enemy", [5] = "arcs to 2", [6] = "arcs to 3" },
	AugFlame = { [4] = "flames appear in 2 places", [5] = "burns 40% longer", [6] = "big explosion when the flames die" },
	AugExecute = { [4] = "executed enemies explode", [5] = "bigger explosion", [6] = "+ heal 4% HP per execution" },
	AugMeteor = { [4] = "2 meteors per cast", [5] = "3 meteors", [6] = "4 meteors, bigger" },
	AugPulse = { [4] = "fires twice (0.45s apart)", [5] = "fires 3 times", [6] = "+3 more targets" },
}
function Config.AugLevelLine(attr, level)
	local fn = AUG_LEVEL[attr]
	if not fn then return "", nil end
	local text, mult = fn(level)
	local extra = AUG_EXTRA[attr] and AUG_EXTRA[attr][level]
	if extra then text = text .. " · ★" .. extra end
	return text, mult
end

-- 세트 효과 시너지: 두 어그먼트를 모두 가지면 숨은 추가 효과가 켜진다 (획득하는 순간 알림 + 오라 폭발)
Config.AugSynergies = {
	Order = { "Inferno", "StormEye", "BladeMissile", "Reaper" },
	Inferno      = { Need = { "AugNova", "AugFlame" },      Icon = "🌋", Name = "Sea of Flames",    Desc = "Kill Burst is 30% wider and flames burn 1.5x longer" },
	StormEye     = { Need = { "AugStorm", "AugMeteor" },    Icon = "🌩", Name = "Eye of the Storm", Desc = "Each time a meteor lands, extra lightning strikes nearby enemies" },
	BladeMissile = { Need = { "AugOrbit", "AugMissile" },   Icon = "🗡", Name = "Homing Blades", Desc = "Blades occasionally launch a missile when they slash" },
	Reaper       = { Need = { "AugExecute", "AugMissile" }, Icon = "☠", Name = "Reaper's Scythe", Desc = "When an execute happens, 2 missiles burst out" },
}

-- 랜덤 패널티 (적이 강해지는 대신 골드를 더 준다. 누적되지만 상한이 있다)
Config.RunPenalties = {
	{ Icon = "🪨", Name = "Tough Enemies",   Desc = "Enemy HP +25%",           HealthMult = 1.25, Gold = 0.15 },
	{ Icon = "😡", Name = "Fierce Enemies",   Desc = "Enemy attack +30%",         DamageMult = 1.30, Gold = 0.15 },
	{ Icon = "💨", Name = "Fast Enemies",     Desc = "Enemy move speed +12%",      SpeedMult = 1.12, Gold = 0.15 },
	{ Icon = "🐺", Name = "Swarm",      Desc = "Enemies swarm in more often",   CountMult = 1.25, Gold = 0.20 },
	{ Icon = "🔫", Name = "Lightspeed Fire",   Desc = "Enemy fire interval -15%",      IntervalMult = 0.85, Gold = 0.20 },
	{ Icon = "🛡", Name = "Ironclad Legion",   Desc = "Enemy HP +40%, attack +10%", HealthMult = 1.40, DamageMult = 1.10, Gold = 0.30 },
	{ Icon = "☠",  Name = "Nightmare Aura", Desc = "Enemy HP/attack +15%, speed +5%", HealthMult = 1.15, DamageMult = 1.15, SpeedMult = 1.05, Gold = 0.30 },
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
		Speed = 12.5,
		ShotDamage = 8 + level * 2,
		ShotInterval = math.max(1.2, 2.6 - level * 0.05),
		ShotSpeed = 45,
		Gold = 8 + level * 4, -- 처치 시 파티원 모두에게 지급
	}
end

Config.Boss = {
	Name = "Dungeon Lord",
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
------------------------------------------------------------
-- 경제 기준표 (ECONOMY.md 참고): 모든 골드 수입 / 지출을 "내 공격력 배율(GetDamageMultiplier)" 하나에 맞춘다.
--   활동 수입(분당) = IncomeBase x 공격력 배율   (필드 / 던전 / 방치 / 직접 허수아비가 이 값의 일정 비율이 되도록 계수를 맞춤)
--   무기 강화 한 단계 비용 = IncomeBase x 공격력 배율 x 그 단계에 걸리길 바라는 분(StepMinutes)
--   -> 강해질수록 수입도 비용도 같은 비율로 커져서, 무기 한 단계에 걸리는 시간(분)이 일정하다. (진화 한 번 = 단계 수 x 분)
------------------------------------------------------------
Config.Economy = {
	IncomeBase = 1500,        -- 공격력 배율 1.0(처음 무기)일 때 열심히 플레이한 분당 골드
	StepMinutesEarly = 0.4,   -- 초반 무기 강화 한 단계에 걸리길 바라는 분 (15단계 = 약 4분)
	StepMinutesLate = 0.9,    -- 강화 단계 LateLevel 이후 (10단계 = 약 6분)
	LateLevel = 600,
	FieldGoldMult = 2.6,      -- 필드 몬스터 처치 골드 배율 (구역 보상표 x 이 값)
	DungeonGoldMult = 0.6,    -- 던전 골드 배율 (던전은 처치 수가 많아서 낮춘다)
}

Config.Weapon = {
	WeaponCount = 100,
	LevelScale = 326 / 1090, -- 위력 / 크기 / 성공률 공식은 이 비율로 줄인 "유효 단계"를 쓴다 (단계가 많아져도 최종 위력은 그대로). 1090 = 아래 StepsFor 의 총합
}
-- 무기 하나가 가진 강화 단계 수: 처음 무기들은 오래 키우고(첫 무기 10단계), 뒤로 갈수록 빨리 넘어간다
-- (이 무기의 마지막 단계에서 강화에 성공하면 다음 무기로 진화)
function Config.Weapon.StepsFor(index)
	if index <= 10 then return 15 end -- 처음 10개 무기는 15단계씩 (초반에 무기가 너무 빨리 바뀌지 않게)
	if index <= 30 then return 12 end -- 11~30번째 무기는 12단계씩
	return 10                         -- 이후 무기는 10단계씩. 총합 = 150 + 240 + 700 = 1090 (LevelScale 의 1090 과 맞춘다)
end

-- 무기 사다리: 10개 시대 x 10개 종류 = 100종. 시대마다 색 / 재질 / 효과 / 발사체가 크게 바뀌고,
-- 시대 안에서는 권총 -> 기관단총 -> 리볼버 -> 라이플 -> 샷건 -> 화염방사기 -> 플라즈마 캐논 -> 저격총 -> 로켓 런처 -> 레일건 순서로 바뀐다 (CLASS_ORDER).
-- Shot: 발사체 외형. Style(Ball/Bolt/Orb/Cannon/Fire/Rocket/Rainbow) / Size / Length(Bolt/Rocket) / Speed(초당 거리) / Impact(착탄 입자 수)

-- 시대 특징(화면에서 보이는 모습 설명): 새 시대의 무기로 진화하면 탄 / 꼬리 / 착탄 연출이 이렇게 바뀐다. (피해를 퍼뜨리는 효과는 세트 효과 / 던전 특성 / 무기 종류와 겹쳐서 넣지 않는다)
local ERA_PERKS = {
	{ Name = "Rusty Bullets", Icon = "🔫", Desc = "Dull gray-brown shots and dust. Where every weapon begins" },
	{ Name = "Blue Steel Shots", Icon = "🔷", Desc = "Clean white-blue streak shots with short spark ticks" },
	{ Name = "Mana Orbs", Icon = "🔮", Desc = "Particles orbit purple orbs, trailing a star tail" },
	{ Name = "Golden Comet", Icon = "☄", Desc = "A comet-like golden tail with glittering gold dust" },
	{ Name = "Flame Droplets", Icon = "🔥", Desc = "Fiery heads with pointed tails and rising embers" },
	{ Name = "Frozen Crystals", Icon = "❄", Desc = "Sky-blue crystal shards and snowflake mist, bursting into ice fragments" },
	{ Name = "Lightning Links", Icon = "⚡", Desc = "Zigzag flickering lightning links and flying sparks" },
	{ Name = "Dark Spheres", Icon = "🌑", Desc = "Dark purple spheres with smoke tails and spreading void ripples" },
	{ Name = "Dragon Fireball", Icon = "🐉", Desc = "A fireball trailing a long S-curved tail, dragon flames" },
	{ Name = "Mythic Rainbow", Icon = "🌈", Desc = "Rainbow ribbon shots and stardust, with star bursts on impact" },
}

-- 탄 크기 / 길이는 "무기 번호 + 그 무기 안의 진행도" 하나로 이어서 커진다 (진화해도 크기가 다시 줄어들지 않는다). 번호가 높을수록 항상 같거나 더 크다.
Config.Weapon.ShotBias = { Ball = 1, Bolt = 0.9, Orb = 1, Cannon = 1, Rocket = 0.85, Fire = 1, Rainbow = 1 }
function Config.Weapon.VisualProgress(tier, stage)
	return tier.Index + (stage or 0) / math.max(1, tier.Steps) -- 1.0 ~ 100.99
end
function Config.Weapon.ShotSize(tier, stage)
	return (0.55 + 0.022 * Config.Weapon.VisualProgress(tier, stage)) * (Config.Weapon.ShotBias[tier.Shot.Style] or 1)
end

local ERAS = {
	{ Prefix = "Rusty",   Color = Color3.fromRGB(165, 165, 175), Material = Enum.Material.Metal,  Particles = 0,  Trail = false, Light = 0,
		Shot = { Style = "Ball", Size = 0.6, Speed = 260, Impact = 0 } },
	{ Prefix = "Steel",   Color = Color3.fromRGB(90, 160, 255),  Material = Enum.Material.Metal,  Particles = 6,  Trail = false, Light = 0,
		Shot = { Style = "Bolt", Size = 0.35, Length = 3, Speed = 320, Impact = 6 } },
	{ Prefix = "Arcane",   Color = Color3.fromRGB(175, 95, 255),  Material = Enum.Material.Glass,  Particles = 12, Trail = true,  Light = 0,
		Shot = { Style = "Orb", Size = 1.3, Speed = 190, Impact = 14 } },
	{ Prefix = "Golden",   Color = Color3.fromRGB(255, 200, 50),  Material = Enum.Material.Neon,   Particles = 22, Trail = true,  Light = 10,
		Shot = { Style = "Cannon", Size = 2.4, Speed = 140, Impact = 30 } },
	{ Prefix = "Flame",   Color = Color3.fromRGB(255, 70, 40),   Material = Enum.Material.Neon,   Particles = 40, Trail = true,  Light = 16,
		Shot = { Style = "Rocket", Size = 1.6, Length = 4, Speed = 150, Impact = 70 } },
	{ Prefix = "Frozen",   Color = Color3.fromRGB(140, 225, 255), Material = Enum.Material.Ice,    Particles = 30, Trail = true,  Light = 14,
		Shot = { Style = "Bolt", Size = 0.5, Length = 4.5, Speed = 360, Impact = 40 } },
	{ Prefix = "Lightning",   Color = Color3.fromRGB(255, 240, 90),  Material = Enum.Material.Neon,   Particles = 45, Trail = true,  Light = 18,
		Shot = { Style = "Bolt", Size = 0.45, Length = 7, Speed = 440, Impact = 50 } },
	{ Prefix = "Dark",   Color = Color3.fromRGB(100, 50, 160),  Material = Enum.Material.Neon,   Particles = 50, Trail = true,  Light = 14,
		Shot = { Style = "Orb", Size = 1.9, Speed = 200, Impact = 55 } },
	{ Prefix = "Dragon",   Color = Color3.fromRGB(255, 120, 60),  Material = Enum.Material.Neon,   Particles = 55, Trail = true,  Light = 20,
		Shot = { Style = "Fire", Size = 2.4, Speed = 180, Impact = 80 } },
	{ Prefix = "Mythic", Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.Neon,   Particles = 70, Trail = true,  Light = 24, Rainbow = true,
		Shot = { Style = "Rainbow", Size = 2.6, Speed = 190, Impact = 90 } },
}
-- 시대 안에서 뒤로 갈수록 "한 방 / 폭발 / 관통" 같은 묵직한 무기가 오고, 기본 화력(DPS)도 조금씩 올라간다
local CLASS_ORDER = { "Pistol", "Smg", "Revolver", "Rifle", "Shotgun", "Flamer", "Cannon", "Sniper", "Rocket", "Rail" }
local CLASS_NAMES = {
	Pistol = "Pistol", Revolver = "Revolver", Smg = "SMG", Shotgun = "Shotgun", Rifle = "Rifle",
	Sniper = "Sniper Rifle", Rocket = "Rocket Launcher", Rail = "Railgun", Flamer = "Flamethrower", Cannon = "Plasma Cannon",
}
-- 무기 이름: 종류 x 시대마다 전부 다른 이름 (접두사만 바뀌는 게 아니라 무기 자체가 다른 이름 / 다른 모양)
local WEAPON_NAMES = {
	Pistol = { "Rusty Pistol", "Steel Pistol", "Arcane Hand Cannon", "Golden Ace", "Flame Igniter", "Frost Spike Pistol", "Lightning Trigger", "Shadow Fang", "Dragonfang Pistol", "Mythic Astra" },
	Smg = { "Rusty SMG", "Steel Repeater", "Arcane Whisper SMG", "Golden Storm SMG", "Flame Rapid-Fire", "Frost Rapid-Fire", "Discharge SMG", "Shadow Rapid-Fire", "Dragonflame SMG", "Mythic Spray" },
	Revolver = { "Rusty Revolver", "Steel Six-Shooter", "Arcane Magnum", "Golden Hunter", "Inferno Revolver", "Icebreaker Revolver", "Thunder Revolver", "Cursed Revolver", "Dragon's Magnum", "Eternal Revolver" },
	Rifle = { "Rusty Rifle", "Steel Carbine", "Arcane Rifle", "Golden Ranger", "Flame Rifle", "Frost Rifle", "Shock Rifle", "Shadow Rifle", "Dragonscale Rifle", "Mythic Galaxy Rifle" },
	Shotgun = { "Rusty Shotgun", "Steel Pump Shotgun", "Arcane Double-Barrel", "Golden Shredder", "Flame Scattergun", "Glacier Scattergun", "Lightning Scattergun", "Slaughterer Shotgun", "Dragon Blunderbuss", "Mythic Blunderbuss" },
	Flamer = { "Rusty Flamethrower", "Steel Sprayer", "Arcane Flame Sprayer", "Golden Furnace", "Flame Inferno Torch", "Frostfire Sprayer", "Plasma Torch", "Hellfire Sprayer", "Dragon's Breath", "Star Flame" },
	Cannon = { "Rusty Plasma Cannon", "Steel Cannon", "Arcane Cannon", "Golden Cannon", "Volcano Cannon", "Frost Cannon", "Thunder Cannon", "Dark Cannon", "Dragon Cannon", "Star Breaker" },
	Sniper = { "Rusty Sniper", "Steel Long-Range Sniper", "Arcane Sniper", "Golden Eagle Sniper", "Flame Sniper", "Snowfield Sniper", "Lightning Sniper", "Assassin's Sniper", "Dragon Eye Sniper", "Galaxy Sniper" },
	Rocket = { "Rusty Rocket Launcher", "Steel Bazooka", "Arcane Launcher", "Golden Missile", "Flame Rocket", "Frost Missile", "Lightning Missile", "Dark Missile", "Dragon Rocket", "Comet Launcher" },
	Rail = { "Rusty Railgun", "Steel Gauss Gun", "Arcane Railgun", "Golden Railgun", "Flame Railgun", "Frost Railgun", "Electromagnetic Railgun", "Void Railgun", "Dragon Core Railgun", "Mythic Railgun" },
}

-- Tiers[i] = i번째 무기 (MinLevel = 이 무기가 되는 최소 강화 단계). 이름은 시대 + 종류.
Config.Weapon.Tiers = {}
local totalSteps = 0
for index = 1, Config.Weapon.WeaponCount do
	local era = ERAS[(index - 1) // #CLASS_ORDER + 1]
	local class = CLASS_ORDER[(index - 1) % #CLASS_ORDER + 1]
	local inEra = (index - 1) % #CLASS_ORDER -- 0~9: 시대 안에서 뒤로 갈수록 탄이 조금씩 커진다
	local shot = table.clone(era.Shot)
	local name = WEAPON_NAMES[class][(index - 1) // #CLASS_ORDER + 1]
	local entry = {
		Index = index, MinLevel = totalSteps, Steps = Config.Weapon.StepsFor(index),
		Name = name, Prefix = era.Prefix, Class = class, Era = (index - 1) // #CLASS_ORDER + 1,
		Color = era.Color, Material = era.Material, Particles = era.Particles, Trail = era.Trail, Light = era.Light,
		Rainbow = era.Rainbow, Shot = shot, Perk = ERA_PERKS[(index - 1) // #CLASS_ORDER + 1],
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
	ManualFraction = 0, -- (직접 쏘는 골드는 없앴다: 방치 수입이 있으니 불필요) 예전 값 0.11: -- 직접 쏠 때 허수아비 골드(분당) = 이 값 x Economy.IncomeBase x 공격력 배율. 방치 수입의 약 1/3 (직접 쏘기는 초반 체험용). 탄 수 / 연사로 더 벌지 않는다
	EraGoldMult = 1.4,     -- 무기 세대(10종 단위)가 오를 때마다 허수아비 골드 x1.4 (업그레이드할수록 골드도 늘게)
	PowerRef = 600,        -- 전투력 기준값 (이 값일 때 배율 약 x2)
	PowerExp = 0.55,       -- 전투력이 오를수록 골드가 어떻게 늘어나는지 (1 이면 정비례, 작을수록 완만)
	-- 허수아비는 하나. 이름 / 기본 배율만 있다 (방어력 없음: 누구나 때려서 골드를 번다)
	List = {
		{ Name = "Golden Training Dummy", Multiplier = 1, RequiredPower = 0 },
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
	Lobby = 71174590381361,    -- 마을 배경음악 (Field 가 비어 있으면 필드에서도 이 곡이 이어서 나옴)
	Dungeon = 111737108754664, -- 던전(웨이브) 배경음악
	Field = 1845092181,        -- 필드 배경음악
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
	MusicVolume = 0.054, -- 설정창 슬라이더 100% 기준 (예전 0.18 에서 슬라이더를 30% 로 낮춰 두었을 때의 소리 = 테스트해 보니 이 정도가 알맞았다)
	TrackScale = { Lobby = 0.7 }, -- 곡마다 크기 배율 (마을은 잔잔하게 작게)
	Music = {
		Lobby = ids.Lobby or 0,      -- 로비 배경음악
		Dungeon = ids.Dungeon or 0,  -- 던전(웨이브) 배경음악
		Boss = ids.Boss or 0,        -- 보스전 배경음악
		Field = ids.Field or 0,      -- 필드 배경음악 (없으면 로비 음악)
		Doom = ids.Doom or 0,        -- 최후의 군주와의 결투 음악 (0이면 보스전 음악을 더 빠르게 틀어 준다)
	},
	Shot = ids.Shot or 0,            -- 총 쏘는 소리 (무기가 강해질수록 낮고 묵직하게 재생됨)
	ShotVolume = 0.06, -- 총소리 기본 크기 (예전 0.3 에서 슬라이더를 20% 로 낮춰 두었을 때의 소리)
	EnhanceSuccess = ids.EnhanceSuccess or 0, -- 강화 성공 소리
	Hit = ids.Hit or 0,              -- 적중음
	Kill = ids.Kill or 0,            -- 처치음
	Skill = ids.Skill or 0,          -- 스킬음
	Bank = bankIds,                  -- 소리별 직접 지정 ID (AudioBank 스크립트 + AudioIds 의 Bank. 있으면 SoundBank 의 가공음 대신 사용)
}
-- 배경음악은 숫자 하나 대신 목록 { 111, 222, 333 } 으로 적을 수 있다: 곡이 끝나면 다음(다른) 곡이 이어진다 (AudioIds 에서).
-- 필드는 Field1 ~ Field8 로 구역마다 다른 곡도 가능 (없으면 Field).
for zone = 1, 8 do
	Config.Audio.Music["Field" .. zone] = ids["Field" .. zone] or 0
end

------------------------------------------------------------
-- 장비 (갑옷 / 장갑 / 신발): 보스 티켓으로 뽑기 -> 골드로 강화
-- 등급(일반~신화)이 높을수록 효과가 크고, 강화 레벨이 오를수록 더 커짐
------------------------------------------------------------
Config.Gear = {
	MaxLevel = 15,
	LevelBonus = 0.08,   -- 강화 1레벨당 효과 +8%
	RarityNames = { "Common", "Rare", "Epic", "Legendary", "Mythic" },
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
		{ Key = "Armor", Name = "Armor", Stat = "Health", StatName = "Max HP", Base = 40, BaseCost = 120,
			Names = { "Leather Armor", "Chainmail", "Steel Armor", "Mithril Armor", "Dragonscale Armor" } },
		{ Key = "Gloves", Name = "Gloves", Stat = "Crit", StatName = "Crit Chance", Base = 0.02, BaseCost = 100,
			Names = { "Cloth Gloves", "Leather Gloves", "Steel Gauntlets", "Mithril Gauntlets", "Dragonclaw Gauntlets" } },
		{ Key = "Boots", Name = "Boots", Stat = "Speed", StatName = "Move Speed", Base = 0.6, BaseCost = 100,
			Names = { "Worn Shoes", "Leather Boots", "Steel Boots", "Mithril Boots", "Boots of Wind" } },
		{ Key = "Helmet", Name = "Helmet", Stat = "Damage", StatName = "Attack", Base = 0.03, BaseCost = 130,
			Names = { "Leather Cap", "Iron Helm", "Steel Helm", "Mithril Helm", "Dragonhorn Crown" } },
		{ Key = "Ring", Name = "Ring", Stat = "Haste", StatName = "Skill Cooldown Reduction", Base = 0.02, BaseCost = 140,
			Names = { "Copper Ring", "Silver Ring", "Gold Ring", "Gem Ring", "Ring of Time" } },
		{ Key = "Necklace", Name = "Necklace", Stat = "Luck", StatName = "Luck", Base = 0.05, BaseCost = 140,
			Names = { "String Necklace", "Silver Necklace", "Gold Necklace", "Gem Necklace", "Starlight Necklace" } },
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
		return string.format("Max HP +%d", math.floor(value + 0.5))
	elseif slot.Stat == "Speed" then
		return string.format("Move Speed +%.1f", value)
	end
	-- 나머지는 비율(%) 효과: 치명타 확률 / 공격력 / 스킬 쿨타임 감소 / 행운 ...
	return string.format("%s +%.1f%%", slot.StatName, value * 100)
end

-- 강화 비용: 부위와 강화 단계로만 정해진다 (끼고 있는 장비의 등급은 상관없다: 일부러 낮은 등급을 끼고 싸게 강화하는 걸 막는다). 등급 값은 호환용으로만 받는다.
function Config.GetGearCost(slotKey, _rarity, level)
	local slot = Config.GetGearSlot(slotKey)
	return math.floor(slot.BaseCost * 1.8 * 1.28 ^ level) -- (1.8 = 예전 영웅 등급 기준)
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
	ZoneLengths = { 340, 700, 700, 700, 700, 700, 700, 700 }, -- 구역별 길이: 1구역은 작게(군주가 입구 가까이에 있다), 나머지는 큰 사냥터
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
	EliteMultiplier = 3.5,     -- 엘리트 몬스터 체력 배율 (5였는데 3구역부터 너무 오래 걸려 낮춤)
	EliteTicketChance = 0.2,   -- 엘리트 처치 시 티켓 획득 확률
	BossRespawn = 120,
	-- 구역마다 군주가 다시 나타나는 시간(초): 모두가 같이 쓰는 필드라서, 앞 구역은 자주 / 뒤 구역은 드물게 (뒤로 갈수록 귀한 상대)
	BossRespawnByZone = { 60, 90, 150, 210, 300, 420, 600, 900 },
	-- 구역 군주를 상대하기 전에 갖춰야 할 권장 전투력 (모자라면 군주를 만났을 때 "무기를 강화하세요" 안내가 뜬다)
	-- 권장 전투력 (화면 안내용): 그 구역 일반 몬스터를 약 3초에 잡는 전투력. 몬스터 체력 곡선(ZoneDanger.Health)을 바꾸면 같이 다시 계산한다.
	RecommendPower = { 350, 750, 1700, 5800, 21000, 83000, 290000, 780000 },
	-- (BossPower 는 심연 도전의 보상 배율 계산에만 쓰이는 옛 값이다. 화면에 보이는 권장 전투력은 위 RecommendPower)
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
		Health = { 1, 1.5, 2.4, 5.5, 12, 26, 50, 75 },       -- (3구역부터 몹이 잘 안 죽던 것을 완화: 실제 전투력 곡선에 맞춘 값)
		Damage = { 1, 1.3, 2.2, 3.4, 5.2, 8, 9, 12 },        -- (7~8구역은 한두 방에 죽지 않게 낮춤)
		Speed = { 1, 1.05, 1.1, 1.18, 1.26, 1.35, 1.45, 1.55 },
		Reward = { 1, 1.5, 2.2, 3.2, 4.6, 6.5, 9, 13 },
	},
	ZoneNames = { "Meadow", "Forest", "Wasteland", "Desert", "Snowfield", "Volcano", "Darklands", "Abyss" },
	-- 구역별로 나오는 몬스터 종류와 비중 (MonsterTypes.lua 의 Defs 이름)
	ZonePools = {
		{ Slime = 5, Bat = 2, Spider = 1 },
		{ Slime = 3, Spitter = 3, Bat = 2, Spider = 2, Wisp = 1 },
		{ Spitter = 3, Charger = 3, Golem = 1, Imp = 2, Turret = 1, Healer = 1 },
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
	Boss = {
		Name = "Field Overlord",
		Size = 18,
		MaxHealth = 6000,
		Speed = 8,
		ShotDamage = 28,
		ShotInterval = 1.5,
		ShotSpeed = 55,
		Gold = 600,
	},
}

-- 구역별 길이를 쓰는 좌표 계산 (서버 / 클라이언트 공용)
function Config.Field.ZoneStart(zone)
	local x = Config.Field.StartX
	for i = 1, zone - 1 do x += Config.Field.ZoneLengths[i] or Config.Field.ZoneLength end
	return x
end
function Config.Field.ZoneEnd(zone)
	return Config.Field.ZoneStart(zone) + (Config.Field.ZoneLengths[zone] or Config.Field.ZoneLength)
end
function Config.Field.TotalLength()
	return Config.Field.ZoneEnd(Config.Field.ZoneCount) - Config.Field.StartX
end
function Config.Field.ZoneOfX(x)
	for zone = 1, Config.Field.ZoneCount do
		if x < Config.Field.ZoneEnd(zone) then return zone end
	end
	return Config.Field.ZoneCount
end

function Config.Field.GetZoneLevel(zone)
	return 1 + (zone - 1) * 3
end

------------------------------------------------------------
-- 전투력: 머리 위 이름표 / 리더보드에 표시되어 강함을 과시할 수 있다
------------------------------------------------------------
function Config.GetPower(weaponLevel, critPoints, speedPoints, gearHealth, gearCrit, typeKey, level, gearDamage)
	local P = Config.Player
	level = level or 1
	local weaponType = Config.WeaponTypes[Config.ResolveWeaponType(weaponLevel, typeKey)]
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
	-- 초당 피해 계수 F = 한 발 x 탄 수(산탄은 60%만 맞는다고 계산. 허수아비처럼 붙어서 쏘면 100% 맞으므로 샷건 / 화염방사기는 100% 기준으로 약 1.8배가 되게 잡았다) / 간격. 사거리가 긴 무기는 F 가 1.0 근처, 사거리가 짧은 무기는 F 가 1.5 근처
	Pistol = {
		Name = "Pistol", Form = "Basic", DamageMult = 1.0, Cooldown = 1, Range = 300, Pellets = 1, Spread = 0,
		ShotScale = 1, SpeedScale = 1, BarrelLength = 1, BarrelThickness = 1,
		Trait = "The most balanced weapon", Desc = "Solid fundamentals with no weak points",
	},
	Smg = {
		Name = "SMG", Form = "Smg", DamageMult = 0.44, Cooldown = 0.4, Range = 190, Pellets = 1, Spread = 0,
		ShotScale = 0.7, SpeedScale = 1.1, BarrelLength = 0.8, BarrelThickness = 0.9,
		Trait = "Very fast fire rate · Short range", Desc = "A gun that pours out shots at a blistering fire rate",
	},
	Revolver = {
		Name = "Revolver", Form = "Steel", DamageMult = 1.12, Cooldown = 1.1, Range = 320, Pellets = 1, Spread = 0,
		ShotScale = 1.15, SpeedScale = 1.1, CritBonus = 0.1, BarrelLength = 0.9, BarrelThickness = 1.2,
		Trait = "Heavy hitter · Crit +10%", Desc = "Slow but hits hard",
	},
	Rifle = {
		Name = "Rifle", Form = "Rifle", DamageMult = 0.62, Cooldown = 0.6, Range = 420, Pellets = 1, Spread = 0,
		ShotScale = 0.9, SpeedScale = 1.4, CritBonus = 0.05, BarrelLength = 1.4, BarrelThickness = 0.9,
		Trait = "Fast fire rate · Long range", Desc = "Accurate sustained fire at long range",
	},
	Shotgun = {
		Name = "Shotgun", Form = "Basic", DamageMult = 0.36, Cooldown = 1.2, Range = 80, Pellets = 6, Spread = 9,
		ShotScale = 0.55, SpeedScale = 1, BarrelLength = 0.75, BarrelThickness = 1.5,
		Trait = "Point-blank burst damage · Very short range", Desc = "6 pellets fan out in a spread (fewer hit at range)",
	},
	Flamer = {
		Name = "Flamethrower", Form = "Flamer", DamageMult = 0.25, Cooldown = 0.4, Range = 45, Pellets = 3, Spread = 16,
		ShotScale = 0.9, SpeedScale = 0.6, BarrelLength = 0.7, BarrelThickness = 1.4,
		Trait = "Highest firepower · Shortest range", Desc = "Sprays flames in a fan (get up close and burn them)",
	},
	Cannon = {
		Name = "Plasma Cannon", Form = "Cannon", DamageMult = 1.5, Cooldown = 1.3, Range = 360, Pellets = 1, Spread = 0, Splash = 7,
		ShotScale = 1.5, SpeedScale = 0.8, BarrelLength = 1.1, BarrelThickness = 1.8,
		Trait = "Small explosion · Slow shots", Desc = "Big plasma shots that cause a small explosion around the impact (radius 7)",
	},
	Sniper = {
		Name = "Sniper Rifle", Form = "Basic", DamageMult = 1.6, Cooldown = 1.6, Range = 650, Pellets = 1, Spread = 0,
		ShotScale = 1.4, SpeedScale = 2.4, CritBonus = 0.25, BarrelLength = 1.9, BarrelThickness = 0.7,
		Trait = "Long range · Crit +25%", Desc = "Slow but each shot is powerful",
	},
	Rocket = {
		Name = "Rocket Launcher", Form = "Rocket", DamageMult = 1.7, Cooldown = 1.5, Range = 340, Pellets = 1, Spread = 0, Splash = 12,
		ShotScale = 1.8, SpeedScale = 0.55, BarrelLength = 1.3, BarrelThickness = 1.6,
		Trait = "Wide explosion · Crowd clearing", Desc = "Explodes on impact, damaging nearby enemies too (radius 12)",
	},
	Rail = {
		Name = "Railgun", Form = "Rail", DamageMult = 1.45, Cooldown = 1.4, Range = 700, Pellets = 1, Spread = 0, Bounce = 2, BounceRange = 34, BounceMult = 0.85,
		ShotScale = 1.2, SpeedScale = 3, BarrelLength = 1.6, BarrelThickness = 0.8,
		Trait = "Bounces to 3 nearby enemies · Longest range", Desc = "Ultra-fast shot that bounces from the target to the 2 nearest enemies around it (within 34)",
	},
}

-- 무기 종류의 "초당 피해 계수": 한 발 피해 x 탄 수 / 공격 간격 (산탄 / 화염은 60%만 맞는다고 계산 — 전투력 공식과 같은 가정).
-- 종류 순서(권총 -> 기관단총 -> ... -> 레일건)대로 1.00 -> 1.36 으로 커지고, 시대가 바뀔 때 x1.4 가 붙어서 "공격 속도가 느려지는 무기"로 진화해도 DPS 는 항상 오른다.
function Config.WeaponDpsFactor(weaponType)
	local pellets = weaponType.Pellets > 1 and weaponType.Pellets * 0.6 or 1
	return weaponType.DamageMult * pellets / weaponType.Cooldown
end

-- 무기 종류 10형은 강화 단계로 해금된다 (Tiers 1~10 의 MinLevel = 0 / 15 / 30 ... 135). 어떤 형으로 싸울지는 플레이어가 고른다.
-- 시대(Era)는 무기의 외모 / 탄 색만 바꾸고, 강화 단계가 오를수록 위력(GetDamageMultiplier)이 오른다.
function Config.GetUnlockLevel(typeKey)
	for index, key in ipairs(Config.WeaponTypes.Order) do
		if key == typeKey then return Config.Weapon.Tiers[index].MinLevel end
	end
	return 0
end

function Config.IsWeaponUnlocked(level, typeKey)
	return (level or 0) >= Config.GetUnlockLevel(typeKey)
end

function Config.GetUnlockedCount(level)
	local count = 0
	for index in ipairs(Config.WeaponTypes.Order) do
		if (level or 0) >= Config.Weapon.Tiers[index].MinLevel then count += 1 end
	end
	return count
end

-- 고른 무기가 아직 잠겨 있으면(또는 이상한 값이면) 권총
function Config.ResolveWeaponType(level, typeKey)
	if typeof(typeKey) == "string" and typeKey ~= "Order" and Config.WeaponTypes[typeKey] and Config.IsWeaponUnlocked(level, typeKey) then
		return typeKey
	end
	return "Pistol"
end

-- 그 무기 형 + 지금 시대의 외모 정보 (색 / 재질 / 탄 모양). Tiers[(시대-1)*10 + 형 번호]
function Config.GetLookTier(level, typeKey)
	local era = Config.GetWeaponTier(level).Era
	local count = #Config.WeaponTypes.Order
	for index, key in ipairs(Config.WeaponTypes.Order) do
		if key == typeKey then return Config.Weapon.Tiers[(era - 1) * count + index] end
	end
	return Config.Weapon.Tiers[(era - 1) * count + 1]
end

-- 다음 큰 변화: 아직 잠긴 무기 형이 있으면 그 해금, 다 풀었으면 다음 시대. 없으면 nil.
function Config.GetNextMilestone(level)
	level = level or 0
	local order = Config.WeaponTypes.Order
	local unlocked = Config.GetUnlockedCount(level)
	if unlocked < #order then
		local tier = Config.Weapon.Tiers[unlocked + 1]
		return { Kind = "Form", Level = tier.MinLevel, Name = Config.WeaponTypes[order[unlocked + 1]].Name, Key = order[unlocked + 1], Era = tier.Era }
	end
	local era = Config.GetWeaponTier(level).Era
	local tier = Config.Weapon.Tiers[era * #order + 1]
	if tier then
		return { Kind = "Era", Level = tier.MinLevel, Name = Config.GetEraName(tier.Era), Era = tier.Era, Tier = tier }
	end
	return nil
end

function Config.GetTierWeapon(tier)
	return Config.WeaponTypes[tier.Class] or Config.WeaponTypes.Pistol
end

-- 지금 시대의 특성
function Config.GetWeaponPerk(level)
	return Config.GetWeaponTier(level).Perk
end

function Config.GetPlayerWeapon(player)
	local level = player:GetAttribute("WeaponLevel") or 0
	return Config.WeaponTypes[Config.ResolveWeaponType(level, player:GetAttribute("WeaponType"))]
end

function Config.GetEraName(era)
	local data = ERAS[era]
	return data and (data.Prefix .. " Era") or ""
end

-- 무기 이름: 형 이름만 (접두사 없음). 시대는 따로 표시한다.
function Config.GetWeaponName(typeKey, _level)
	local weaponType = Config.WeaponTypes[typeKey] or Config.WeaponTypes.Pistol
	return weaponType.Name
end

------------------------------------------------------------
-- 던전 종류 / 난이도 (던전 게이트에서 파티장이 고른다)
------------------------------------------------------------
Config.Dungeon.Difficulties = {
	Order = { "Easy", "Normal", "Hard" },
	Easy = { Name = "Easy", PowerMult = 0.6, KeyTier = 1, HealthMult = 0.7, DamageMult = 0.7, GoldMult = 0.8, Tickets = 2, KeyCost = 1, LevelOffset = -2, Color = Color3.fromRGB(120, 220, 130) },
	Normal = { Name = "Normal", PowerMult = 1, KeyTier = 2, HealthMult = 1, DamageMult = 1, GoldMult = 1, Tickets = 3, KeyCost = 2, LevelOffset = 0, Color = Color3.fromRGB(255, 220, 110) },
	Hard = { Name = "Hard", PowerMult = 2.2, KeyTier = 3, HealthMult = 1.8, DamageMult = 1.5, GoldMult = 2, Tickets = 5, KeyCost = 3, LevelOffset = 4, Color = Color3.fromRGB(255, 100, 100) },
}

-- 던전 경험치 배율: 골드 배율(유형 x 난이도 = 최대 5~10배)과 따로 정한다. 예전에는 골드 배율을 경험치에도 그대로 곱해서 어려운 던전에서 필드의 약 10배 속도로 레벨이 올랐다.
Config.Dungeon.XpMult = { Easy = 0.8, Normal = 1.0, Hard = 1.4 }

-- 던전 권장 전투력 (난이도 배율 반영, 50 단위)
function Config.DungeonPower(dungeonType, difficulty)
	return math.floor((dungeonType.RecommendedPower or 0) * (difficulty.PowerMult or 1) / 50 + 0.5) * 50
end

-- Boss.Weights: 보스 패턴 비중 (Fan 부채꼴 / Ring 전방위 / Spiral 나선 / Meteor 메테오)
Config.Dungeon.Types = {
	Order = { "Cave", "Ice", "Fire" },
	Cave = {
		Name = "Goblin Cave", Desc = "🐀 Swarm! Weak but overwhelming in number, and the Goblin King keeps summoning minions (beginner)", Theme = { Health = 0.8, Damage = 0.9, Speed = 1.0, Spawn = 1.35, Burst = 1.3 }, Waves = 5, LevelOffset = 0, GoldMult = 1, RecommendedPower = 700,
		MonsterColor = Color3.fromRGB(110, 160, 70),
		Floor = { Color = Color3.fromRGB(70, 60, 50), Material = Enum.Material.Slate },
		Wall = { Color = Color3.fromRGB(55, 45, 40), Material = Enum.Material.Brick },
		Torch = Color3.fromRGB(255, 150, 70),
		Terrain = { Ground = Enum.Material.Mud, Mountain = Enum.Material.Rock, Accent = Enum.Material.Slate },
		MonsterPool = { Slime = 4, Bat = 3, Spider = 3, Imp = 2, Spitter = 1, Healer = 1 },
		Boss = { Name = "Goblin King", Color = Color3.fromRGB(70, 130, 50), HealthMult = 1, DamageMult = 1, Weights = { Fan = 1.5, Slam = 2, Summon = 3, SideAdds = 3, Lanes = 1, Rush = 3.5, CoinRain = 3 } }, -- 고블린 왕: 돌진 / 금화 폭격 / 부하 소환
	},
	Ice = {
		Name = "Ice Fortress", Desc = "❄ Bullet hell! Many enemies shoot from afar, and the Frost Lord unleashes spiral / all-direction barrages (intermediate)", Theme = { Health = 1.0, Damage = 1.2, Speed = 0.9, Spawn = 0.9, Burst = 1.0 }, Waves = 6, LevelOffset = 6, GoldMult = 1.6, RecommendedPower = 2000,
		MonsterColor = Color3.fromRGB(110, 200, 240),
		Floor = { Color = Color3.fromRGB(112, 140, 172), Material = Enum.Material.Slate }, -- (너무 하얗고 쨍해서 눈부시던 것을 어두운 청회색으로)
		Wall = { Color = Color3.fromRGB(78, 106, 146), Material = Enum.Material.Glacier },
		Torch = Color3.fromRGB(120, 200, 255),
		Terrain = { Ground = Enum.Material.Slate, Mountain = Enum.Material.Glacier, Accent = Enum.Material.Slate },
		MonsterPool = { Spitter = 3, Mage = 4, Turret = 2, Wisp = 3, Golem = 1, Healer = 2 },
		Boss = { Name = "Frost Lord", Color = Color3.fromRGB(90, 170, 240), HealthMult = 1.6, DamageMult = 1.2, Weights = { Fan = 1, Ring = 3, Spiral = 4, Sweep = 2, Slam = 0.5, SpikeLines = 4 } }, -- 서리 군주: 탄막 / 얼음 가시 줄기
	},
	Fire = {
		Name = "Flame Temple", Desc = "🔥 Charges and explosions! Charging enemies are tough and fast, and the Flame Lord rains down meteors and shockwaves (advanced)", Theme = { Health = 1.25, Damage = 1.0, Speed = 1.15, Spawn = 1.0, Burst = 1.0 }, Waves = 7, LevelOffset = 12, GoldMult = 2.5, RecommendedPower = 4500,
		MonsterColor = Color3.fromRGB(240, 100, 50),
		Floor = { Color = Color3.fromRGB(60, 35, 35), Material = Enum.Material.Basalt },
		Wall = { Color = Color3.fromRGB(90, 40, 30), Material = Enum.Material.CrackedLava },
		Torch = Color3.fromRGB(255, 90, 40),
		Terrain = { Ground = Enum.Material.Basalt, Mountain = Enum.Material.Slate, Accent = Enum.Material.CrackedLava },
		MonsterPool = { Charger = 4, Bomber = 4, Imp = 2, Golem = 2, Spider = 1, Totem = 1, Healer = 1 },
		Boss = { Name = "Flame Lord", Color = Color3.fromRGB(230, 70, 30), HealthMult = 2.4, DamageMult = 1.5, Weights = { Meteor = 3, Slam = 2, Lanes = 3, Sweep = 2, Dive = 4, EmberFall = 3.5 } }, -- 화염 군주: 급강하 / 불씨 폭격 / 화염 줄기
	},
}

-- 보스러쉬(옛 심연 도전): 보스급이 일정 간격으로 하나씩 나타난다. 점수 = 버틴 시간 x 준 피해, 주간 전체 순위.
Config.Dungeon.Types.Rift = {
	Name = "Boss Rush", Desc = "Bosses arrive one after another! Score = seconds survived x damage dealt", Waves = 0, Endless = true, TimeLimit = 600, LevelOffset = 4, GoldMult = 1, RecommendedPower = 0,
	MonsterColor = Color3.fromRGB(255, 80, 150),
	Floor = { Color = Color3.fromRGB(46, 30, 66), Material = Enum.Material.Slate },
	Wall = { Color = Color3.fromRGB(80, 40, 100), Material = Enum.Material.Slate },
	Torch = Color3.fromRGB(255, 80, 150),
	Terrain = { Ground = Enum.Material.Slate, Mountain = Enum.Material.Basalt, Accent = Enum.Material.Glacier },
	MonsterPool = { Slime = 2, Spitter = 2, Bat = 2, Mage = 2, Golem = 1, Charger = 2, Bomber = 2, Spider = 2, Imp = 2, Turret = 1, Wisp = 2, Totem = 1 },
	Boss = { Name = "Abyss Gatekeeper", Color = Color3.fromRGB(255, 80, 150), HealthMult = 1, DamageMult = 1, Weights = { Fan = 1, Ring = 1, Spiral = 1, Meteor = 1, Slam = 2, Summon = 2, Lanes = 2, Sweep = 2, SideAdds = 1.5 } },
}

-- 방어력(피해 감소): 레벨 + 장비 체력에서 생기고, 몬스터 / 보스가 주는 모든 피해에 적용된다 (Server/DamageGuard.lua)
Config.Defense = {
	LevelDef = 2,        -- 레벨당 방어력
	GearDef = 0.08,      -- 장비 최대 체력 1당 방어력
	K = 500,             -- 피해 감소 = 방어력 / (방어력 + K): 레벨 200 + 장비 약 1000 이면 약 49%
	MaxReduction = 0.6,  -- 최대 60%
	HitCap = 0.25,       -- 한 번에 맞는 피해는 최대 체력의 25% 까지
}

Config.Rift = {
	Duration = 600,       -- 최대 버티는 시간(초): 이 시간이 지나면 끝난다
	FreeAttempts = 2,     -- 하루 입장 횟수 (UTC 날짜 기준 초기화)
	FirstBoss = 6,        -- 첫 보스가 나오기까지(시작 후 초)
	IntervalStart = 15,   -- 보스 등장 간격(초): 처음에는 느긋하게
	IntervalMin = 8,      -- 점점 짧아져서 이 값에서 멈춘다
	IntervalStep = 0.7,   -- 보스가 하나 나올 때마다 줄어드는 간격(초)
	MaxAlive = 10,        -- 동시에 쌓일 수 있는 보스 수 (서버 부담 + 끝이 나게 하는 장치)
	BossHp = 7000000,     -- 첫 보스 체력 (모두 같다: 풀파밍 캐릭터 DPS 약 34만 기준 약 20초). 장비가 강한 사람이 더 빨리 잡고 더 많이 쌓아서 점수가 높다
	HpGrowth = 1.12,      -- 보스가 하나 나올 때마다 체력 x1.12
	DamageStart = 0.07,   -- 보스 탄 한 발 피해 = 내 최대 체력의 7%에서 시작
	DamageStep = 0.012,   -- 보스마다 +1.2%p
	DamageCap = 0.22,
	GimmickZone = 5,      -- 쫄병 / 탄막 기믹 강도 (필드 구역 환산)
	RewardMult = 30,      -- 등급 보상 골드 배율 (8구역을 끝낸 사람 기준)
	RankShown = 10,       -- 순위표에 보여 주는 인원
	Tiers = {             -- 준 피해 합계 -> 등급 보상 (순위와 별개로 누구나 받는다)
		{ Min = 0,  Name = "Bronze",   Icon = "🥉", Gold = 200,   Tickets = 0, TimeSkip = 0 },
		{ Min = 3000000,   Name = "Silver",   Icon = "🥈", Gold = 600,   Tickets = 0, TimeSkip = 300 },
		{ Min = 15000000,  Name = "Gold",     Icon = "🥇", Gold = 1500,  Tickets = 1, TimeSkip = 600 },
		{ Min = 50000000,  Name = "Platinum", Icon = "💠", Gold = 3500,  Tickets = 2, TimeSkip = 900 },
		{ Min = 150000000, Name = "Diamond",  Icon = "💎", Gold = 8000,  Tickets = 4, TimeSkip = 1800 },
		{ Min = 400000000, Name = "Master",   Icon = "👑", Gold = 15000, Tickets = 6, TimeSkip = 3600 },
	},
}

function Config.GetRiftTier(dealt)
	local tier = Config.Rift.Tiers[1]
	for _, candidate in ipairs(Config.Rift.Tiers) do
		if dealt >= candidate.Min then tier = candidate end
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
		{ Id = "dummy",   Name = "Dummy Practice", Desc = "Hit the dummy %d times",       Stat = "DummyHits",     Goal = 300, Reward = { Gold = 300 } },
		{ Id = "field",   Name = "Field Hunt",     Desc = "Defeat %d field monsters",       Stat = "FieldKills",    Goal = 30,  Reward = { Gold = 400, TimeSkip = 300 } },
		{ Id = "elite",   Name = "Elite Hunter", Desc = "Defeat %d elite monsters",     Stat = "EliteKills",    Goal = 3,   Reward = { Tickets = 1 } },
		{ Id = "dungeon", Name = "Dungeon Run",     Desc = "Clear %d dungeon(s)",              Stat = "DungeonClears", Goal = 1,   Reward = { Gold = 600, Tickets = 1, TimeSkip = 600 }, Always = true },
		{ Id = "boss",    Name = "Boss Hunt",     Desc = "Defeat %d boss(es)",              Stat = "BossKills",     Goal = 1,   Reward = { Tickets = 2 } },
		{ Id = "enhance", Name = "Blacksmith",      Desc = "Succeed at upgrading %d times",          Stat = "Enhances",      Goal = 3,   Reward = { Gold = 500 }, Always = true },
		{ Id = "gacha",   Name = "Test Your Luck",       Desc = "Roll for gear %d times",         Stat = "Rolls",         Goal = 2,   Reward = { Gold = 300 } },
		{ Id = "goblin",  Name = "Golden Hunt",     Desc = "Defeat %d Golden Goblin(s)",       Stat = "GoblinKills",   Goal = 1,   Reward = { Gold = 800, Tickets = 1 } },
		{ Id = "skills",  Name = "Skill Practice",     Desc = "Use skills %d times",          Stat = "SkillUses",     Goal = 20,  Reward = { Gold = 400 } },
		{ Id = "rift",    Name = "Boss Rush",     Desc = "Enter the Boss Rush %d times", Stat = "RiftRuns",      Goal = 2,   Reward = { Gold = 700, TimeSkip = 600 } },
		-- 첫날 전용 (처음 접속한 날만 나온다): 스탯 / 펫이 있다는 걸 알려 주는 퀘스트
		{ Id = "statpts", Name = "Allocate Stats",     Desc = "Spend %d stat points (T key / Stats button)", Stat = "StatPoints", Goal = 3, Reward = { Gold = 300 }, FirstDay = true },
		{ Id = "petpeek", Name = "Meet Your Pet",       Desc = "Open the pet window (P key / Growth > Pet)",       Stat = "PetPeek",    Goal = 1, Reward = { Gold = 300, Tickets = 1 }, FirstDay = true },
		{ Id = "kills",   Name = "Monster Cleanup",   Desc = "Defeat %d monsters (dungeons included)", Stat = "Kills",         Goal = 60,  Reward = { Gold = 500, TimeSkip = 300 } },
	},
}

Config.Achievements = {
	{ Id = "dummy100",   Name = "Rookie Shooter",       Desc = "Hit the dummy %d times",          Stat = "DummyHits",     Goal = 100,   Reward = { Gold = 200 },               Title = "Rookie Shooter" },
	{ Id = "dummy2000",  Name = "Dummy Slayer", Desc = "Hit the dummy %d times",          Stat = "DummyHits",     Goal = 2000,  Reward = { Gold = 1500 },              Title = "Dummy Slayer" },
	{ Id = "kills500",   Name = "Hunter",          Desc = "Defeat %d monsters",          Stat = "Kills",         Goal = 500,   Reward = { Gold = 1500 },              Title = "Hunter" },
	{ Id = "dungeon1",   Name = "First Dungeon",         Desc = "Clear %d dungeon(s)",            Stat = "DungeonClears", Goal = 1,     Reward = { Gold = 500, Tickets = 1 },  Title = "Dungeon Newbie" },
	{ Id = "dungeon10",  Name = "Dungeon Regular",       Desc = "Clear %d dungeon(s)",            Stat = "DungeonClears", Goal = 10,    Reward = { Tickets = 3 },              Title = "Dungeon Regular" },
	{ Id = "dungeon50",  Name = "Dungeon Master",     Desc = "Clear %d dungeon(s)",            Stat = "DungeonClears", Goal = 50,    Reward = { Tickets = 10 },             Title = "Dungeon Master" },
	{ Id = "goblin1",    Name = "Golden Hunter",     Desc = "Defeat %d Golden Goblin(s)",     Stat = "GoblinKills",   Goal = 1,     Reward = { Gold = 1000 },              Title = "Lucky Hunter" },
	{ Id = "goblin20",   Name = "Golden Thief",       Desc = "Defeat %d Golden Goblin(s)",     Stat = "GoblinKills",   Goal = 20,    Reward = { Tickets = 5 },              Title = "Golden Thief" },
	{ Id = "skill200",   Name = "Skill Master",     Desc = "Use skills %d times",              Stat = "SkillUses",     Goal = 200,   Reward = { Tickets = 3 },              Title = "Skill Master" },
	{ Id = "rift2500",   Name = "Boss Hunter",   Desc = "Defeat %d bosses in one Boss Rush run",         Stat = "RiftBoss",      Goal = 5,  Reward = { Tickets = 4 },              Title = "Boss Hunter" },
	{ Id = "rift9000",   Name = "Limit Breaker",     Desc = "Defeat %d bosses in one Boss Rush run",         Stat = "RiftBoss",      Goal = 15,  Reward = { Tickets = 12 },             Title = "Limit Breaker" },
	{ Id = "riftdepth5",  Name = "Survivor",     Desc = "Survive %d seconds in the Boss Rush",           Stat = "RiftTime",     Goal = 300,     Reward = { Tickets = 3 },              Title = "Survivor" },
	{ Id = "riftdepth15", Name = "Unbreakable",     Desc = "Survive %d seconds in the Boss Rush",           Stat = "RiftTime",     Goal = 600,    Reward = { Tickets = 10 },             Title = "Unbreakable" },
	{ Id = "prestige1",  Name = "The Reborn",   Desc = "Rebirth x%d",                    Stat = "Prestige",      Goal = 1,     Reward = { Tickets = 5 },              Title = "Reborn" },
	{ Id = "prestige5",  Name = "Samsara Master",     Desc = "Rebirth x%d",                    Stat = "Prestige",      Goal = 5,     Reward = { Tickets = 15 },             Title = "Samsara Master" },
	{ Id = "boss10",     Name = "Boss Hunter",       Desc = "Defeat %d boss(es)",            Stat = "BossKills",     Goal = 10,    Reward = { Tickets = 5 },              Title = "Boss Hunter" },
	{ Id = "zone4",      Name = "Explorer",          Desc = "Clear field zone %d",            Stat = "MaxZone",       Goal = 4,     Reward = { Gold = 1000 },              Title = "Explorer" },
	{ Id = "zone8",      Name = "Abyss Conqueror",   Desc = "Clear field zone %d",            Stat = "MaxZone",       Goal = 8,     Reward = { Tickets = 5 },              Title = "Abyss Conqueror" },
	{ Id = "weapon10",   Name = "Weapon Collector",     Desc = "Reach weapon upgrade level %d (about the 10th weapon)", Stat = "WeaponLevel",   Goal = Config.Weapon.Tiers[10].MinLevel, Reward = { Gold = 2000 },              Title = "Upgrade Master" },
	{ Id = "weapon50",   Name = "Legend Wielder",    Desc = "Reach weapon upgrade level %d (about the 50th weapon)", Stat = "WeaponLevel",   Goal = Config.Weapon.Tiers[50].MinLevel, Reward = { Tickets = 6 },              Title = "Legend Wielder" },
	{ Id = "weapon15",   Name = "Legendary Blacksmith", Desc = "Upgrade all the way to the last weapon (level %d)",       Stat = "WeaponLevel",   Goal = Config.Weapon.MaxLevel, Reward = { Tickets = 20 },             Title = "Legendary Blacksmith" },
	{ Id = "legend",     Name = "Lucky One",          Desc = "Obtain Legendary gear",         Stat = "BestRarity",    Goal = 4,     Reward = { Tickets = 3 },              Title = "Lucky One" },
	{ Id = "myth",       Name = "Mythic Master",     Desc = "Obtain Mythic gear",         Stat = "BestRarity",    Goal = 5,     Reward = { Tickets = 8 },              Title = "Mythic Master" },
	{ Id = "level10",    Name = "Growing Adventurer", Desc = "Reach character level %d",         Stat = "Level",         Goal = 10,    Reward = { Gold = 1000 },              Title = "Adventurer" },
	{ Id = "level25",    Name = "Skilled Warrior",     Desc = "Reach character level %d",         Stat = "Level",         Goal = 25,    Reward = { Tickets = 3 },              Title = "Veteran" },
	{ Id = "level50",    Name = "Legendary Hero",     Desc = "Reach character level %d",         Stat = "Level",         Goal = 50,    Reward = { Tickets = 10 },             Title = "Legendary Hero" },
	{ Id = "power1000",  Name = "Powerhouse",            Desc = "Reach %d Power",              Stat = "Power",         Goal = 1000,  Reward = { Gold = 1500 },              Title = "Powerhouse" },
	{ Id = "power10000", Name = "Transcendent",          Desc = "Reach %d Power",              Stat = "Power",         Goal = 10000, Reward = { Tickets = 10 },             Title = "Transcendent" },
}

------------------------------------------------------------
-- 캐릭터 레벨: 몬스터를 잡으면 경험치(XP). 레벨이 오르면 최대 체력과 공격력이 늘고 체력이 가득 찬다.
------------------------------------------------------------
Config.Level = {
	Max = 200,              -- (50 -> 200: 찍고 싶은 스탯이 부족하다는 의견. 50 이후는 필요 경험치 곡선이 완만하고 레벨당 공격력도 작다)
	LateStart = 50,         -- 이 레벨 이후는 "후반" 곡선
	LateDamagePerLevel = 0.004, -- 50 레벨 이후 레벨당 공격력 +0.4% (200레벨에서 총 +60%; 경제 기준 공격력 배율이 부풀지 않게)
	EarlyBoostUntil = 6,    -- 이 레벨까지는 경험치 x3 (처음 몇 분 안에 레벨업이 연달아 터지게)
	EarlyBoost = 3,
	HealthPerLevel = 8,     -- 레벨당 최대 체력 +8
	DamagePerLevel = 0.03,  -- 레벨당 공격력 +3%
}

-- 레벨 스탯: 레벨이 오를 때마다 포인트 1개 (레벨 1 = 0개). 공격력 / 체력이 아니라 "플레이 스타일"을 고르는 특수 스탯이고,
-- 언제든 마음대로 빼서 다시 넣을 수 있다 (무료). 한 스탯에 몰빵해도 되고 골고루 나눠도 된다.
Config.LevelStats = {
	PointsPerLevel = 1,
	Order = { "Move", "Range", "Double", "Haste", "CritDmg" },
	Move  = { Name = "Move Speed",   Icon = "👟", Per = 0.3,  Desc = "Move speed +0.3 per point" },
	Range = { Name = "Range",    Icon = "🎯", Per = 0.04, Desc = "Weapon range +4% per point" },
	Double = { Name = "Double Shot", Icon = "🔫", Per = 0.007, Desc = "+0.7% chance per point to fire a second shot right after the first (\"bang-bang\")", Note = "Double Shot: each time you shoot, there's a chance the same shot fires again 0.09s later (same power). With all 49 points, about 34%." },
	Haste = { Name = "Skill Cooldown", Icon = "⏱", Per = 0.01, Desc = "Skill cooldown -1% per point" },
	CritDmg = { Name = "Crit Damage", Icon = "💥", Per = 0.015, Desc = "Crit damage +1.5%p per point (base 2x)", Note = "Crit Damage: crits hit even harder. With all 49 points, crits go from 2x to about 2.7x. Combine with crit chance gear / pet / Double Shot for a big-hit build." },
	-- 스탯 하나에 넣을 수 있는 최대 포인트 (포인트가 199개로 늘어도 한 스탯이 한계를 넘지 않게: 더블샷 확률 100% 초과 같은 일 방지)
	Cap = { Move = 40, Range = 50, Double = 60, Haste = 50, CritDmg = 60 },
	-- 최대 레벨(200)을 찍은 뒤에는 골드로 포인트를 더 살 수 있다 (골드 사용처). n 번째(0부터) 포인트 비용 = Base x Growth^n. 살 수 있는 총 개수는 아래 MaxGoldPoints.
	GoldPoint = { Base = 200000, Growth = 1.07 },
	OtherExtraShotValue = 0.5, -- 장비 옵션 / 던전 특성으로 늘어난 탄 한 발의 가치 (예전에는 100%여서 탄이 늘면 딜이 그대로 배수로 늘었다)
}
function Config.GetLevelStatPoints(level)
	return math.max(0, ((level or 1) - 1) * Config.LevelStats.PointsPerLevel)
end
-- 골드로 살 수 있는 포인트 수 = 모든 스탯 한계 합 - 레벨로 얻는 포인트 (모두 사면 전 스탯이 한계까지 찬다)
do
	local capTotal = 0
	for _, key in ipairs(Config.LevelStats.Order) do capTotal += Config.LevelStats.Cap[key] end
	Config.LevelStats.MaxGoldPoints = math.max(0, capTotal - Config.GetLevelStatPoints(Config.Level.Max))
end
function Config.GetLevelGoldPointCost(bought)
	return math.floor(Config.LevelStats.GoldPoint.Base * Config.LevelStats.GoldPoint.Growth ^ bought)
end
-- 포인트 -> 실제 효과 문자열 / 값
function Config.LevelStatValue(key, points)
	local def = Config.LevelStats[key]
	return points * def.Per
end
function Config.LevelStatText(key, points)
	local value = Config.LevelStatValue(key, points)
	if key == "Move" then return string.format("Move Speed +%.1f", value)
	elseif key == "Range" then return string.format("Range +%d%%", math.floor(value * 100 + 0.5))
	elseif key == "Double" then return string.format("Double Shot chance %.1f%%", value * 100)
	elseif key == "Haste" then return string.format("Cooldown -%d%%", math.floor(value * 100 + 0.5))
	else return string.format("Crit damage +%d%%p", math.floor(value * 100 + 0.5)) end
end
-- 무기 사정거리 (레벨 스탯 반영)
function Config.GetRange(player, weaponType)
	return weaponType.Range * (1 + (player:GetAttribute("LvRange") or 0))
end

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
	if level <= Config.Level.LateStart then
		return math.floor(50 * level ^ 1.75)
	end
	-- 50 레벨 이후: 50 레벨 필요량에서 완만하게 늘어난다 (200 레벨 직전 약 30만). 50 -> 200 총합 약 2천5백만 XP
	local base = 50 * Config.Level.LateStart ^ 1.75
	return math.floor(base * (level / Config.Level.LateStart) ^ 1.35)
end

function Config.GetLevelDamageMult(level)
	local early = math.min(level, Config.Level.LateStart) - 1
	local late = math.max(0, level - Config.Level.LateStart)
	return 1 + Config.Level.DamagePerLevel * early + Config.Level.LateDamagePerLevel * late
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
	AutoScrapNames = { [0] = "Off", "Common or lower", "Rare or lower", "Epic or lower", "Smart (Recommended)" },
	AffixOrder = { "Health", "Crit", "Speed", "Damage", "Xp", "Luck" },
	Affixes = {
		Health = { Name = "Max HP", Base = 30 },
		Crit = { Name = "Crit Chance", Base = 0.012, Percent = true },
		Speed = { Name = "Move Speed", Base = 0.4 },
		Damage = { Name = "Attack", Base = 0.03, Percent = true },
		Xp = { Name = "XP Gain", Base = 0.04, Percent = true },
		Luck = { Name = "Luck (Drop Rarity)", Base = 0.05, Percent = true },
	},
}

-- 세트 장비 (영웅 등급 이상에 붙을 수 있음): 같은 세트 2부위 / 3부위를 끼면 보너스
-- Bonuses[2], Bonuses[3] = { {Stat, Value}, ... }   Stat: Health Crit Speed Damage Xp Luck + Haste(스킬 쿨타임 감소) Shot(탄 +N발)
Config.Sets = {
	Order = { "Hunter", "Guardian", "Gale", "Sage" },
	SetChance = { [3] = 0.30, [4] = 0.45, [5] = 0.60 }, -- 등급별로 세트가 붙을 확률
	Hunter = { Name = "Hunter's Emblem", Color = Color3.fromRGB(255, 170, 70),
		Bonuses = { [2] = { { Stat = "Damage", Value = 0.08 } }, [3] = { { Stat = "Crit", Value = 0.10 }, { Stat = "Damage", Value = 0.07 } } } },
	Guardian = { Name = "Guardian's Oath", Color = Color3.fromRGB(110, 190, 255),
		Bonuses = { [2] = { { Stat = "Health", Value = 120 } }, [3] = { { Stat = "Health", Value = 250 }, { Stat = "Haste", Value = 0.10 } } } },
	Gale = { Name = "Gale Wind", Color = Color3.fromRGB(120, 255, 170),
		Bonuses = { [2] = { { Stat = "Speed", Value = 2 } }, [3] = { { Stat = "Speed", Value = 3 }, { Stat = "Haste", Value = 0.15 } } } },
	Sage = { Name = "Sage's Wisdom", Color = Color3.fromRGB(200, 140, 255),
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
-- 구역 세트마다 컨셉이 하나씩 있다: 그 구역 군주를 잡으면 열리고 골드로 활성화한다 (아래 AugCost / AugSlotZones). 던전 주사위의 세트 조각은 예전 방식 그대로 단계를 준다
Config.Sets.ZoneAug = { "AugPulse", "AugOrbit", "AugStorm", "AugMissile", "AugNova", "AugFlame", "AugExecute", "AugMeteor" }
Config.Sets.AugLevelByPieces = { [2] = 1, [3] = 3 }
-- 세트 효과는 장비가 아니라 "골드로 활성화"한다: 그 구역 군주를 잡으면 열리고, 골드로 1~3단계까지 올린다.
-- 동시에 켤 수 있는 개수(슬롯)는 처음 1개이고 구역을 클리어할수록 늘어난다 (AugSlotZones[n] = n번째 슬롯이 열리는 클리어 구역).
-- 최후의 군주 결전 (8구역 군주를 쓰러뜨리면 8구역 끝에 포탈이 열린다): 튜토리얼에서 만났던 군주와 이번에는 진짜로 싸운다
Config.FinalLord = {
	Health = 56000000,        -- 8구역 권장 전투력(780,000) x 0.4(대략의 초당 피해) x 180초. 권장 전투력이면 약 3분 반 (이동 / 회피 시간 포함)
	PortalCooldown = 45,      -- 같은 사람이 다시 들어가기까지 (초)
	RewardGold = 3000000,
	RewardTickets = 40,
	Phase2 = 0.7, Phase3 = 0.35, -- 체력이 이 비율 아래로 내려가면 다음 단계 (패턴이 늘고 빨라진다)
}
Config.Sets.AugSlotZones = { 0, 4, 7 }
Config.Sets.AugCostMult = { 1, 2.5, 6 } -- 1단계 / 2단계 / 3단계 비용 배수
function Config.Sets.AugCost(zone, level)
	local base = math.floor(1500 * 1.75 ^ (zone - 1) / 100 + 0.5) * 100
	return base * (Config.Sets.AugCostMult[level] or 8)
end
-- 도감: 몬스터 / 구역 군주 / 세트 장비 설명 (몬스터 이름은 MonsterTypes.Defs 와 같다)
Config.Codex = {
	Monsters = {
		Slime = { Name = "Slime", Icon = "🟢", Desc = "A squishy droplet. Approaches slowly and shoots one shot at a time." },
		Spitter = { Name = "Spiny Venomworm", Icon = "🐛", Desc = "Spits thorns from afar. Keeps its distance while shooting." },
		Bat = { Name = "Bat", Icon = "🦇", Desc = "Flies around quickly, throwing crescent-moon shots." },
		Mage = { Name = "Mage Ghost", Icon = "👻", Desc = "Fires homing shots from afar. Shoots slowly but relentlessly." },
		Golem = { Name = "Rock Golem", Icon = "🗿", Desc = "Slow but tough, and its smash really hurts." },
		Charger = { Name = "Charging Boar", Icon = "🐗", Desc = "Lowers its tusks and charges. Watch for the tell before the charge and dodge!" },
		Bomber = { Name = "Bomber", Icon = "💣", Desc = "Runs up and explodes. Take it out before it gets close." },
		Imp = { Name = "Sniper Imp", Icon = "😈", Desc = "Hurls fast spears from very far away. Some shots split apart." },
		Knight = { Name = "Shield Knight", Icon = "🛡", Desc = "Blocks almost all frontal attacks. Shoot from the side or behind." },
		Turret = { Name = "Magic Turret", Icon = "🔫", Desc = "Stays put and fires beams. Long range." },
		Spider = { Name = "Venom Spider", Icon = "🕷", Desc = "Rushes in fast, firing poison stingers in succession." },
		Wisp = { Name = "Will-o'-Wisp", Icon = "🔥", Desc = "Floats around quickly, emitting ring-shaped shots." },
		Healer = { Name = "Healing Priest", Icon = "💚", Desc = "Heals nearby monsters. Best to take it out first." },
		Totem = { Name = "Curse Totem", Icon = "🗿", Desc = "Fires ring shots in all directions from a fixed spot." },
	},
	Bosses = { "Vine Giant", "Ancient Stag Spirit", "One-Eyed Rock Giant", "Giant Scorpion", "Ice Crystal Lord", "Lava Demon", "Dark Reaper", "Eye of the Abyss" },
}

Config.Sets.ZoneKeys = {}
do
	local zoneSets = {
		{ Name = "Meadow's Guard", Prefix = "Meadow", Color = Color3.fromRGB(130, 220, 110), Icon = "🌾",
			B2 = { { Stat = "Health", Value = 80 } }, B3 = { { Stat = "Health", Value = 150 }, { Stat = "Speed", Value = 1.5 } } },
		{ Name = "Forest's Blessing", Prefix = "Forest", Color = Color3.fromRGB(80, 200, 120), Icon = "🌲",
			B2 = { { Stat = "Xp", Value = 0.10 } }, B3 = { { Stat = "Xp", Value = 0.18 }, { Stat = "Luck", Value = 0.15 } } },
		{ Name = "Will of the Ruins", Prefix = "Ruins", Color = Color3.fromRGB(200, 170, 120), Icon = "🏚",
			B2 = { { Stat = "Damage", Value = 0.06 } }, B3 = { { Stat = "Damage", Value = 0.10 }, { Stat = "Health", Value = 150 } } },
		{ Name = "Desert Sun", Prefix = "Desert", Color = Color3.fromRGB(255, 210, 90), Icon = "🏜",
			B2 = { { Stat = "Crit", Value = 0.06 } }, B3 = { { Stat = "Crit", Value = 0.10 }, { Stat = "Damage", Value = 0.06 } } },
		{ Name = "Frost's Breath", Prefix = "Frost", Color = Color3.fromRGB(150, 225, 255), Icon = "❄",
			B2 = { { Stat = "Haste", Value = 0.08 } }, B3 = { { Stat = "Haste", Value = 0.12 }, { Stat = "Health", Value = 200 } } },
		{ Name = "Lava Heart", Prefix = "Lava", Color = Color3.fromRGB(255, 110, 50), Icon = "🌋",
			B2 = { { Stat = "Damage", Value = 0.10 } }, B3 = { { Stat = "Damage", Value = 0.15 }, { Stat = "Crit", Value = 0.08 } } },
		{ Name = "Dark Pact", Prefix = "Dark", Color = Color3.fromRGB(180, 110, 255), Icon = "🦇",
			B2 = { { Stat = "Luck", Value = 0.20 } }, B3 = { { Stat = "Luck", Value = 0.30 }, { Stat = "Damage", Value = 0.10 } } },
		{ Name = "Abyss Dominion", Prefix = "Abyss", Color = Color3.fromRGB(255, 80, 140), Icon = "🌀",
			B2 = { { Stat = "Damage", Value = 0.15 } }, B3 = { { Stat = "Damage", Value = 0.22 }, { Stat = "Haste", Value = 0.15 }, { Stat = "Shot", Value = 1 } } },
	}
	for zone, def in ipairs(zoneSets) do
		local key = "Zone" .. zone
		Config.Sets[key] = { Name = def.Name, Prefix = def.Prefix, Icon = def.Icon, Color = def.Color, Zone = zone, Bonuses = { [2] = def.B2, [3] = def.B3 }, Aug = Config.Sets.ZoneAug[zone] }
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
	Split = { Name = "Splitting Bullets", Desc = "Fires +1 extra shot", Effects = { { Stat = "Shot", Value = 1 } } },
	Chrono = { Name = "Time Warp", Desc = "Skill cooldown -25%", Effects = { { Stat = "Haste", Value = 0.25 } } },
	Slayer = { Name = "Slaughterer", Desc = "Attack +25%", Effects = { { Stat = "Damage", Value = 0.25 } } },
	Fortune = { Name = "Lucky Star", Desc = "Luck +50%, XP +30%", Effects = { { Stat = "Luck", Value = 0.5 }, { Stat = "Xp", Value = 0.3 } } },
}

Config.BonusNames = { Health = "Max HP", Crit = "Crit Chance", Speed = "Move Speed", Damage = "Attack", Xp = "XP", Luck = "Luck", Haste = "Skill Cooldown Reduction", Shot = "Shot Count" }
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
	Health = { Name = "Max HP", Desc = "How much damage you can take. Higher means fewer deaths" },
	Crit = { Name = "Crit Chance", Desc = "Chance for an attack to crit (2x damage)" },
	Speed = { Name = "Move Speed", Desc = "Walking and running speed" },
	Damage = { Name = "Attack", Desc = "Increases the damage of all your attacks (gun & skills)" },
	Xp = { Name = "XP Gain", Desc = "Earn more XP from monsters so you level up faster" },
	Luck = { Name = "Luck", Desc = "Raises the chance that gear dropped by field monsters is high rarity (Epic or above)" },
	Haste = { Name = "Skill Cooldown Reduction", Desc = "Use First Aid · Ultimate more often (max 60%)" },
	Shot = { Name = "Extra Shots", Desc = "More shots fire at once (in a fan)" },
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

-- 옵션 수치 범위: 재굴림하면 이 범위(등급이 높을수록 큼) 안에서 다시 뽑는다 (서버 InventoryService 의 rollAffixValue 와 같은 식: 기준 x 등급배율 x 0.7 ~ 1.3)
function Config.AffixRange(stat, rarity)
	local def = Config.Inventory.Affixes[stat]
	local base = def.Base * Config.Inventory.AffixRarityScale[rarity]
	return base * 0.7, base * 1.3
end

function Config.FormatAffixRange(stat, rarity)
	local def = Config.Inventory.Affixes[stat]
	local lo, hi = Config.AffixRange(stat, rarity)
	if def.Percent then
		return string.format("%.1f~%.1f%%", lo * 100, hi * 100)
	elseif stat == "Health" then
		return string.format("%d~%d", math.floor(lo + 0.5), math.floor(hi + 0.5))
	end
	return string.format("%.1f~%.1f", lo, hi)
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
-- 탄막 기믹 (예측 사격): 한 방향으로 계속 움직이면 맞게 만든다. 필드는 구역 번호, 던전은 난이도 / 심연 깊이를 "구역"으로 환산해서 쓴다.
Config.Gimmick = {
	LeadFromZone = 3,     -- 이 구역부터 슬라임 / 기사의 탄 중 두 번에 한 번은 내 움직임을 예측해서 쏜다
	LeadAlwaysZone = 5,   -- 이 구역부터는 항상 예측해서 쏜다
	LeadMaxTime = 0.55,   -- 최대 몇 초 앞을 예측하는가 (너무 길면 피할 수 없다)
	LeadStrength = 0.85,  -- 예측 강도 (1 = 정확히 예측)
	DungeonZone = { Easy = 2, Normal = 4, Hard = 6 }, -- 던전 난이도 -> 비슷한 필드 구역
}

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
	-- 열쇠는 한 종류. 던전 입장 비용: 쉬움 1개 / 보통 2개 / 어려움 3개 (Difficulties.KeyCost).
	-- 군주를 잡으면 낮은 확률로 나온다 (뒤 구역일수록 확률 / 개수가 높다). 예전의 3단계 열쇠는 접속할 때 개수만큼 환산해 합친다 (보통 x2, 어려움 x3).
	TierNames = { "Key", "Key", "Key" },
	TierIcons = { "🔑", "🔑", "🔑" },
	DropByZone = {
		{ Tier = 1, Chance = 0.10, Count = 1 }, { Tier = 1, Chance = 0.16, Count = 1 },
		{ Tier = 1, Chance = 0.10, Count = 1 }, { Tier = 1, Chance = 0.15, Count = 1 }, { Tier = 1, Chance = 0.20, Count = 1 },
		{ Tier = 1, Chance = 0.12, Count = 2 }, { Tier = 1, Chance = 0.18, Count = 2 }, { Tier = 1, Chance = 0.25, Count = 2 },
	},
	DailyDropCapByTier = { 20, 0, 0 }, -- 하루에 군주 드랍으로 얻을 수 있는 열쇠 최대 개수 (UTC 날짜 기준)
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
	Name = "Colossus",   -- 구역마다 몇 분에 한 번 나타나는 필드 월드 보스 (돌 거인): 모두 같이 잡으면 장비 + 세트 조각 + 티켓
}

------------------------------------------------------------
-- BM(상점) 설계 - 원칙: "시간을 돈으로 산다". 모든 성장은 돈을 안 써도 시간만 들이면 도달할 수 있고,
--   돈은 그 시간(훈련소/돌파 대기, 열쇠, 부스터)을 줄여준다. 그래서 전투력 성장 속도에도 영향이 있다.
--   PvE 전용이라 다른 플레이어를 해치지 않고, 꾸미기(오라)는 능력치가 없다.
--   ProductId / PassId 를 0 에서 실제 Roblox ID 로 바꾸면 그때부터 판매가 활성화된다. (0 이면 "준비 중")
--   Studio 에서 플레이 테스트할 때는 ID 가 0 이어도 [테스트 지급]으로 효과를 확인할 수 있다.
--   Grant 키: Keys(열쇠) Tickets(뽑기 티켓) XpBoost / LuckBoost(초 단위) Bag(가방 칸) Aura(꾸미기 해금)
------------------------------------------------------------
-- 방치 수입 (휴식 구역): 휴식 구역 원 안에 서 있으면 수입 + 접속을 끊어도 한도까지 적립. BM 은 "효율 / 한도"만 늘려 준다.
Config.Idle = {
	Fraction = 0.34,          -- 방치 수입(분당) = 이 값 x Economy.IncomeBase x 공격력 배율(무기 단계) x (1 + 장비/훈련/펫 공격력 보너스) x 환생 x 방치 배율. 활동 수입의 약 1/3
	Radius = 18,              -- 훈련장 중심에서 이 거리 안에 있으면 방치 중
	OfflineEfficiency = 0.6,  -- 오프라인 적립은 접속 중 방치의 60%
	BaseCapHours = 4,         -- 오프라인 적립 한도 (기본). 하루 2~3번 접속하는 사람이 반나절 비워도 대부분 받도록 4시간
	BoostBonus = 1.0,         -- 방치 부스터 활성 중 배율 +100% (= x2)
	MultTiers = { 0.25, 0.5, 1.0 }, -- 영구 방치 배율 상품 단계 (+25% / +50% / +100%, 단계는 덮어쓰는 방식이라 가장 높은 것 하나만 적용)
	CapTiers = { 4, 20 },     -- 오프라인 적립 한도 상품 단계: 기본 4시간 + 4 = 8시간 / + 20 = 24시간
	VipBonus = 0.2,           -- VIP 패스: 방치 배율 +20%
}

Config.Shop = {
	Passes = {
		VIP = {
			Name = "VIP Pass", Desc = "XP +20% · Idle income +20% · Training slot +1 · Training/breakthrough time -20% · Set effect slot +1 · Bag +20 slots · Golden aura",
			PassId = 0, Icon = "👑", Benefits = { "XP +20%", "Idle income +20%", "Training slot +1", "Training time -20%", "Set effect slot +1", "Bag +20 slots", "Golden Aura" },
		},
	},
	Products = {
		KeyPack = { Name = "5 Dungeon Keys", Desc = "For when you want to run more dungeons", ProductId = 0, Category = "Currency", Icon = "🔑", Badge = "Top Pick", Featured = true, Grant = { Keys = 5 } },
		XpBooster = { Name = "XP Booster (1 hour)", Desc = "2x XP", ProductId = 0, Category = "Growth", Icon = "📚", Featured = true, Grant = { XpBoost = 3600 } },
		LuckBooster = { Name = "Luck Booster (1 hour)", Desc = "Gear drop rarity +50%", ProductId = 0, Category = "Growth", Icon = "🍀", Grant = { LuckBoost = 3600 } },
		BagPlus = { Name = "Bag Expansion +10 Slots", Desc = "Permanent", ProductId = 0, Category = "Growth", Icon = "🎒", Grant = { Bag = 10 } },
		TicketPack = { Name = "5 Gear Roll Tickets", Desc = "Use tickets to roll for gear", ProductId = 0, Category = "Currency", Icon = "🎫", Grant = { Tickets = 5 } },
		TimeSkip10m = { Name = "Time Skip 10 min", Desc = "Reduces training / breakthrough wait time by 10 min (the skip bar fills instantly)", ProductId = 0, Category = "Growth", Icon = "⏩", Grant = { TimeSkip = 600 } },
		AugSlot = { Name = "Set effect slot +1", Desc = "Permanent · Run one more set effect at the same time (max +2)", ProductId = 0, Category = "Growth", Icon = "🌟", Badge = "NEW", Featured = true, Grant = { AugSlot = 1 } },
		TimeSkip1h = { Name = "Time Skip 1 hour", Desc = "Reduces training / breakthrough wait time by 1 hour", ProductId = 0, Category = "Growth", Icon = "⏩", Grant = { TimeSkip = 3600 } },
		TimeSkip8h = { Name = "Time Skip 8 hours", Desc = "Reduces training / breakthrough wait time by 8 hours", ProductId = 0, Category = "Growth", Icon = "⏩", Badge = "Best Value", Featured = true, Grant = { TimeSkip = 28800 } },
		IdleBooster = { Name = "Idle Booster (1 hour)", Desc = "2x idle income (applies while online and to offline accrual)", ProductId = 0, Category = "Idle", Icon = "⏱", Badge = "Popular", Featured = true, Grant = { IdleBoost = 3600 } },
		IdleMult1 = { Name = "Idle Income +25%", Desc = "Permanent", ProductId = 0, Category = "Idle", Icon = "📈", Featured = true, Tier = { Group = "IdleMult", Step = 1, Steps = 3 }, Grant = { IdleMult = 1 } },
		IdleMult2 = { Name = "Idle Income +50%", Desc = "Permanent (replaces +25%)", ProductId = 0, Category = "Idle", Icon = "📈", Badge = "Best Value", Tier = { Group = "IdleMult", Step = 2, Steps = 3 }, Grant = { IdleMult = 2 } },
		IdleMult3 = { Name = "Idle Income +100%", Desc = "Permanent (replaces the previous tier)", ProductId = 0, Category = "Idle", Icon = "📈", Badge = "Max Efficiency", Tier = { Group = "IdleMult", Step = 3, Steps = 3 }, Grant = { IdleMult = 3 } },
		IdleCap8 = { Name = "Idle Accrual Cap: 8 Hours", Desc = "Accrues up to 8 hours while you're away (default 4 hours)", ProductId = 0, Category = "Idle", Icon = "🗄", Featured = true, Tier = { Group = "IdleCap", Step = 1, Steps = 2 }, Grant = { IdleCap = 1 } },
		IdleCap24 = { Name = "Idle Accrual Cap: 24 Hours", Desc = "Accrues up to a full day while you're away", ProductId = 0, Category = "Idle", Icon = "🗄", Badge = "Top Pick", Tier = { Group = "IdleCap", Step = 2, Steps = 2 }, Grant = { IdleCap = 2 } },
		TrainSlot = { Name = "Training slot +1", Desc = "Permanent · Train one more at the same time", ProductId = 0, Category = "Growth", Icon = "🏋", Badge = "Popular", Featured = true, Grant = { TrainSlot = 1 } },
		AuraVoid = { Name = "Void Aura", Desc = "Cosmetic only (no stats)", ProductId = 0, Category = "Deco", Icon = "✨", Badge = "NEW", Grant = { Aura = "Void" } },
		BannerDragon = { Name = "Dragon Banner", Desc = "Cosmetic banner worn on your back (no stats)", ProductId = 0, Category = "Deco", Icon = "🚩", Grant = { Banner = "Dragon" } },
		MountCarpet = { Name = "Magic Carpet", Desc = "Cosmetic mount floating under your feet (no stats)", ProductId = 0, Category = "Deco", Icon = "🛹", Grant = { Mount = "Carpet" } },
		MountPhoenix = { Name = "Phoenix", Desc = "Cosmetic flame-winged mount (no stats)", ProductId = 0, Category = "Deco", Icon = "🔥", Badge = "NEW", Featured = true, Grant = { Mount = "Phoenix" } },
	},
	PassOrder = { "VIP" },
	-- 상점 화면 표시용 (효과와 무관): 카테고리 탭. Products 의 Category / Badge / Icon / Featured(추천 탭) / Tier(단계 상품 표시) 도 표시 전용
	Categories = { { Key = "Rec", Name = "🔥 Featured" }, { Key = "Idle", Name = "⏱ Idle" }, { Key = "Growth", Name = "📈 Growth" }, { Key = "Deco", Name = "🎨 Cosmetics" }, { Key = "Currency", Name = "🎫 Currency" } },
	ProductOrder = { "IdleBooster", "IdleMult1", "IdleMult2", "IdleMult3", "IdleCap8", "IdleCap24", "AugSlot", "TimeSkip10m", "TimeSkip1h", "TimeSkip8h", "TrainSlot", "KeyPack", "XpBooster", "LuckBooster", "BagPlus", "TicketPack", "AuraVoid", "BannerDragon", "MountCarpet", "MountPhoenix" },
	-- VIP 효과 (코드에서 읽는 값). TrainTime: 훈련/돌파 시간 단축 비율
	Vip = { XpBonus = 0.2, KeyCap = 2, KeyRegen = 0.3, Bag = 20, TrainSlots = 1, TrainTime = 0.2, AugSlots = 1 },
	XpBoostMult = 2,
	LuckBoostBonus = 0.5,
}

-- 오라: 캐릭터 주변에 반짝이는 꾸미기 (다른 플레이어에게도 보임). 능력치 없음.
-- Unlock: Free / { Ach = 업적Id } / { Pass = 패스이름 } / { Product = 상품이름 }
Config.Auras = {
	Order = { "Spark", "Frost", "Flame", "Gold", "Void" },
	Spark = { Name = "Sparkle Aura", Color = Color3.fromRGB(255, 255, 255), Unlock = "Free" },
	Frost = { Name = "Frost Aura", Color = Color3.fromRGB(130, 210, 255), Unlock = { Ach = "zone4" } },
	Flame = { Name = "Flame Aura", Color = Color3.fromRGB(255, 110, 50), Unlock = { Ach = "boss10" } },
	Gold = { Name = "Golden Aura", Color = Color3.fromRGB(255, 215, 90), Unlock = { Pass = "VIP" } },
	Void = { Name = "Void Aura", Color = Color3.fromRGB(170, 70, 255), Unlock = { Product = "AuraVoid" } },
}

-- 깃발: 등 뒤에 꽂는 꾸미기. 탈것: 발밑에 떠 있는 꾸미기 (둘 다 능력치 / 이동속도 없음, 다른 플레이어에게도 보임)
Config.Banners = {
	Order = { "Scout", "Hero", "Gold", "Dragon" },
	Scout = { Name = "Trainee Banner", Color = Color3.fromRGB(90, 150, 255), Unlock = "Free" },
	Hero = { Name = "Hero's Banner", Color = Color3.fromRGB(230, 70, 70), Unlock = { Ach = "zone4" } },
	Gold = { Name = "Golden Banner", Color = Color3.fromRGB(255, 205, 70), Unlock = { Pass = "VIP" } },
	Dragon = { Name = "Dragon Banner", Color = Color3.fromRGB(150, 60, 230), Sparks = true, Unlock = { Product = "BannerDragon" } },
}
Config.Mounts = {
	Order = { "Board", "Cloud", "Carpet", "Phoenix" },
	Board = { Name = "Hoverboard", Color = Color3.fromRGB(80, 220, 255), Style = "Board", Unlock = "Free" },
	Cloud = { Name = "Cloud", Color = Color3.fromRGB(190, 225, 255), Style = "Cloud", Unlock = { Ach = "boss10" } },
	Carpet = { Name = "Magic Carpet", Color = Color3.fromRGB(190, 50, 90), Style = "Carpet", Unlock = { Product = "MountCarpet" } },
	Phoenix = { Name = "Phoenix", Color = Color3.fromRGB(255, 100, 40), Style = "Phoenix", Unlock = { Product = "MountPhoenix" } },
}

------------------------------------------------------------
-- 성장 (시간이 걸리는 영구 성장) - 훈련소 + 돌파
--   * 훈련소: 공격 / 체력 / 치명타 / 이속을 영구적으로 키운다. 단계마다 실제 시간이 걸리고 슬롯 수만큼 동시에 훈련.
--   * 돌파: 레벨이 Gates 에 도달하면 더 오르려면 돌파(시간 + 골드)를 거쳐야 한다.
--   * 시간 단축권(TimeSkip): 위 두 가지의 남은 시간을 줄인다. 퀘스트로 조금씩 무료로 얻고, 상점에서도 판다 (BM).
--   -> 돈을 안 써도 시간만 들이면 모두 도달 가능. 돈은 시간만 줄여준다.
------------------------------------------------------------
Config.Growth = {
	UnlockZone = 2, -- 성장(훈련) 해금: ClearedZone 이 이 값에 처음 도달하면 한 번 해금 + 보상
	UnlockReward = { Gold = 1000, Keys = 1, Tickets = 2, Xp = 300 },
	BaseSlots = 1,
	MaxLevel = 30,
	TimeBase = 120,     -- 0 -> 1 단계 훈련 시간(초)
	TimeGrowth = 1.22,  -- 단계마다 시간이 1.22배 (30단계에서 약 10시간)
	GoldBase = 300,
	GoldGrowth = 1.3,
	Stats = {
		Order = { "Attack", "Health", "Crit", "Speed" },
		Attack = { Name = "Attack Training", Icon = "⚔", Per = 0.02 },
		Health = { Name = "HP Training", Icon = "❤", Per = 12 },
		Crit = { Name = "Crit Training", Icon = "🎯", Per = 0.004 },
		Speed = { Name = "Speed Training", Icon = "💨", Per = 0.12 },
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
		return string.format("Attack +%.0f%%", value * 100)
	elseif stat == "Health" then
		return string.format("Max HP +%d", math.floor(value + 0.5))
	elseif stat == "Crit" then
		return string.format("Crit chance +%.1f%%", value * 100)
	end
	return string.format("Move Speed +%.1f", value)
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
		return string.format("%dh %02dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm %02ds", minutes, secs)
	end
	return string.format("%ds", secs)
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

-- 화면에 보이는 무기 표시: "권총 · 녹슨 시대 +3강"
function Config.FormatWeapon(level, typeKey)
	local tier = Config.GetWeaponTier(level)
	local key = Config.ResolveWeaponType(level, typeKey)
	return string.format("%s · %s +%d", Config.WeaponTypes[key].Name, Config.GetEraName(tier.Era), math.floor(level or 0))
end

-- level -> level+1 강화 비용 (사다리 전체에서 조금씩 올라간다)
function Config.GetEnhanceCost(level)
	local E = Config.Economy
	local minutes = E.StepMinutesEarly + (E.StepMinutesLate - E.StepMinutesEarly) * math.min(1, level / E.LateLevel)
	return math.max(1, math.floor(E.IncomeBase * Config.GetDamageMultiplier(level) * minutes))
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
