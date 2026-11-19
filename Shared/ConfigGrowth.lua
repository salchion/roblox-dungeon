-- ConfigGrowth (ReplicatedStorage 안의 ModuleScript, 이름: ConfigGrowth)
-- Config.Growth (훈련소(성장) 표): Config.lua 가 Roblox 스크립트 한 개 최대 크기(200,000자)에 닿아 따로 뺐다 (11-19 분할).
--   Config.lua 가 require 해서 Config.Growth 에 넣는다. 다른 Config 값을 참조하지 않는 순수 데이터 표 (뒤에서 Config 가 키를 더 붙이는 것은 그대로).
return {
	UnlockZone = 0, -- 성장(훈련) 해금: ClearedZone 이 이 값에 처음 도달하면 한 번 해금 + 보상. 0 = 처음부터 열려 있다 (축하 카드 / 보상 없이) (예전 2: 2구역 클리어)
	UnlockReward = { Gold = 1000, Keys = 1, Tickets = 2, Xp = 300 },
	BaseSlots = 1,
	MaxLevel = 30,
	TimeBase = 120,     -- 0 -> 1 단계 훈련 시간(초)
	TimeGrowth = 1.22,  -- 단계마다 시간이 1.22배 (30단계에서 약 10시간)
	GoldBase = 300,
	GoldGrowth = 1.3,
	-- 훈련 = 특성 나무. Tier 1 은 바로 찍을 수 있고, 아래 칸은 Req(위 칸의 단계)를 채워야 열린다. Max 가 없으면 MaxLevel(30)
	-- 동시에 여러 칸을 훈련할 수 있다 (훈련 칸 수만큼). 효과는 Attribute "Train<키>" 로 전투 계산에 더해진다
	Stats = {
		Order = { "Attack", "Health", "Crit", "Speed", "Double", "CritDmg", "Gold", "AtkSpeed", "Armor", "Regen" },
		Attack = { Name = "Attack Training", Icon = "⚔", Per = 0.025, Tier = 1 }, -- (0.02 -> 0.025: 무기 비중을 줄인 만큼 훈련 비중을 키웠다. 30단계 +75%. 장비 / 펫과 곱해지므로 더 올리면 최대치가 부푼다)
		Health = { Name = "HP Training", Icon = "❤", Per = 12, Tier = 1 },
		Crit = { Name = "Crit Training", Icon = "🎯", Per = 0.012, Max = 10, Tier = 1 },
		Speed = { Name = "Speed Training", Icon = "💨", Per = 1.0, Max = 6, Tier = 1 },
		Double = { Name = "Double Shot", Icon = "🔫", Per = 0.016, Max = 5, Tier = 2, Req = { { Stat = "Attack", Level = 5 } } },
		CritDmg = { Name = "Crit Damage", Icon = "💥", Per = 0.04, Max = 5, Tier = 2, Req = { { Stat = "Crit", Level = 5 } } },
		Gold = { Name = "Gold Sense", Icon = "💰", Per = 0.04, Max = 5, Tier = 2, Req = { { Stat = "Speed", Level = 5 } } }, -- (유틸: 이동 속도 아래)
		AtkSpeed = { Name = "Attack Speed", Icon = "⏩", Per = 0.025, Max = 4, Tier = 3, Req = { { Stat = "CritDmg", Level = 5 }, { Stat = "Double", Level = 5 } } },
		Armor = { Name = "Tough Skin", Icon = "🛡", Per = 0.02, Max = 5, Tier = 2, Req = { { Stat = "Health", Level = 5 } } }, -- 받는 피해 감소 (최대 10%)
		Regen = { Name = "Recovery", Icon = "💗", Per = 0.002, Max = 5, Tier = 3, Req = { { Stat = "Armor", Level = 5 } } }, -- 필드 / 던전에서 초당 최대 체력의 일부를 되찾는다 (최대 1% / 초)
	},
	Gates = {},                            -- (예전: 레벨 10 / 20 / 30 / 40 에서 멈추고 시간 돌파 -> 기다리는 느낌이라 없앴다. 이제 막힘 없이 성장하고 골드는 환생으로 더 번다)
	GateTime = { 1800, 7200, 21600, 43200 }, -- 돌파 시간(초): 30분 / 2시간 / 6시간 / 12시간
	GateGold = { 2000, 10000, 50000, 200000 },
}
