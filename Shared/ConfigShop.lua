-- ConfigShop (ReplicatedStorage 안의 ModuleScript, 이름: ConfigShop)
-- Config.Shop (상점 상품 표): Config.lua 가 Roblox 스크립트 한 개 최대 크기(200,000자)에 닿아 따로 뺐다 (11-19 분할).
--   Config.lua 가 require 해서 Config.Shop 에 넣는다. 다른 Config 값을 참조하지 않는 순수 데이터 표 (뒤에서 Config 가 키를 더 붙이는 것은 그대로).
return {
	Passes = {
		VIP = {
			Name = "VIP Pass", Desc = "XP +20% · Idle income +20% · Training slot +1 · Training/breakthrough time -20% · Bag +20 slots · Golden aura",
			PassId = 0, Icon = "👑", Benefits = { "XP +20%", "Idle income +20%", "Training slot +1", "Training time -20%", "Bag +20 slots", "Golden Aura" },
		},
	},
	Products = {
		KeyPack = { Name = "5 Dungeon Keys", Desc = "For when you want to run more dungeons", ProductId = 0, Category = "Currency", Icon = "🔑", PaidRandom = true, OddsKind = "Chest", Badge = "Top Pick", Featured = true, Grant = { Keys = 5 } },
		XpBooster = { Name = "XP Booster (1 hour)", Desc = "2x XP", ProductId = 0, Category = "Growth", Icon = "📚", Featured = true, Grant = { XpBoost = 3600 } },
		LuckBooster = { Name = "Luck Booster (1 hour)", Desc = "Gear drop rarity +50%", ProductId = 0, Category = "Growth", Icon = "🍀", PaidRandom = true, OddsKind = "Luck", Grant = { LuckBoost = 3600 } },
		TicketPack = { Name = "5 Gear Roll Tickets", Desc = "Use tickets to roll for gear", ProductId = 0, Category = "Currency", Icon = "🎫", PaidRandom = true, OddsKind = "Gacha", Grant = { Tickets = 5 } },
		GoldS = { Name = "Gold Pack S", Desc = "Instantly get 30 minutes of YOUR idle income · max 3 per day", ProductId = 0, Category = "Currency", Icon = "💰", DailyLimit = 3, Grant = { IdleGold = 30 } },
		GoldM = { Name = "Gold Pack M", Desc = "Instantly get 2 hours of YOUR idle income · max 3 per day", ProductId = 0, Category = "Currency", Icon = "💰", Featured = true, DailyLimit = 3, Grant = { IdleGold = 120 } },
		GoldL = { Name = "Gold Pack L", Desc = "Instantly get 8 hours of YOUR idle income · max 3 per day", ProductId = 0, Category = "Currency", Icon = "💰", Badge = "Best Value", DailyLimit = 3, Grant = { IdleGold = 480 } },
		TimeSkip10m = { Name = "Time Skip 10 min", Desc = "Reduces training / breakthrough wait time by 10 min (the skip bar fills instantly)", ProductId = 0, Category = "Growth", Icon = "⏩", Grant = { TimeSkip = 600 } },
		TimeSkip1h = { Name = "Time Skip 1 hour", Desc = "Reduces training / breakthrough wait time by 1 hour", ProductId = 0, Category = "Growth", Icon = "⏩", Grant = { TimeSkip = 3600 } },
		TimeSkip8h = { Name = "Time Skip 8 hours", Desc = "Reduces training / breakthrough wait time by 8 hours", ProductId = 0, Category = "Growth", Icon = "⏩", Badge = "Best Value", Featured = true, Grant = { TimeSkip = 28800 } },
		IdleBooster = { Name = "Idle Booster (1 hour)", Desc = "2x idle income (applies while online and to offline accrual)", ProductId = 0, Category = "Idle", Icon = "⏱", Badge = "Popular", Featured = true, Grant = { IdleBoost = 3600 } },
		IdleMult1 = { Name = "Idle Income +25%", Desc = "Permanent", ProductId = 0, Category = "Idle", Icon = "📈", Featured = true, Tier = { Group = "IdleMult", Step = 1, Steps = 3 }, Grant = { IdleMult = 1 } },
		IdleMult2 = { Name = "Idle Income +50%", Desc = "Permanent (replaces +25%)", ProductId = 0, Category = "Idle", Icon = "📈", Badge = "Best Value", Tier = { Group = "IdleMult", Step = 2, Steps = 3 }, Grant = { IdleMult = 2 } },
		IdleMult3 = { Name = "Idle Income +100%", Desc = "Permanent (replaces the previous tier)", ProductId = 0, Category = "Idle", Icon = "📈", Badge = "Max Efficiency", Tier = { Group = "IdleMult", Step = 3, Steps = 3 }, Grant = { IdleMult = 3 } },
		IdleCap8 = { Name = "Idle Accrual Cap: 8 Hours", Desc = "Accrues up to 8 hours while you're away (default 4 hours)", ProductId = 0, Category = "Idle", Icon = "🗄", Featured = true, Tier = { Group = "IdleCap", Step = 1, Steps = 2 }, Grant = { IdleCap = 1 } },
		IdleCap24 = { Name = "Idle Accrual Cap: 24 Hours", Desc = "Accrues up to a full day while you're away", ProductId = 0, Category = "Idle", Icon = "🗄", Badge = "Top Pick", Tier = { Group = "IdleCap", Step = 2, Steps = 2 }, Grant = { IdleCap = 2 } },
		TrainSlot = { Name = "Training slot +1", Desc = "Permanent · Train one more at the same time", ProductId = 0, Category = "Growth", Icon = "🏋", Badge = "Popular", Featured = true, Grant = { TrainSlot = 1 } },
	},
	PassOrder = { "VIP" },
	-- 상점 화면 표시용 (효과와 무관): 카테고리 탭. Products 의 Category / Badge / Icon / Featured(추천 탭) / Tier(단계 상품 표시) 도 표시 전용
	Categories = { { Key = "Rec", Name = "🔥 Featured" }, { Key = "Idle", Name = "⏱ Idle" }, { Key = "Growth", Name = "📈 Growth" }, { Key = "Deco", Name = "🎨 Cosmetics" }, { Key = "Currency", Name = "🎫 Currency" } },
	ProductOrder = { "IdleBooster", "IdleMult1", "IdleMult2", "IdleMult3", "IdleCap8", "IdleCap24", "TimeSkip10m", "TimeSkip1h", "TimeSkip8h", "TrainSlot", "KeyPack", "XpBooster", "LuckBooster", "TicketPack", "GoldS", "GoldM", "GoldL" },
	-- VIP 효과 (코드에서 읽는 값). TrainTime: 훈련/돌파 시간 단축 비율
	Vip = { XpBonus = 0.2, KeyCap = 2, KeyRegen = 0.3, Bag = 20, TrainSlots = 1, TrainTime = 0.2 },
	XpBoostMult = 2,
	LuckBoostBonus = 0.5,
}
