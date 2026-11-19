-- ConfigWeaponTypes (ReplicatedStorage 안의 ModuleScript, 이름: ConfigWeaponTypes)
-- Config.WeaponTypes (무기 종류 표): Config.lua 가 Roblox 스크립트 한 개 최대 크기(200,000자)에 닿아 따로 뺐다 (11-19 분할).
--   Config.lua 가 require 해서 Config.WeaponTypes 에 넣는다. 다른 Config 값을 참조하지 않는 순수 데이터 표 (뒤에서 Config 가 키를 더 붙이는 것은 그대로).
return {
	Order = { "Pistol", "Shotgun", "Rocket", "Rail", "Flamer" }, -- 저격총 모양 라이플 / 샷건 / 로켓 런처 / 레일건 / 마법책 (나머지 옛 종류 정의는 쓰이지 않는다)
	-- 초당 피해 계수 F = 한 발 x 탄 수(산탄은 60%만 맞는다고 계산. 허수아비처럼 붙어서 쏘면 100% 맞으므로 샷건 / 화염방사기는 100% 기준으로 약 1.8배가 되게 잡았다) / 간격. 사거리가 긴 무기는 F 가 1.0 근처, 사거리가 짧은 무기는 F 가 1.5 근처
	Pistol = {
		Name = "Sniper Rifle", Form = "Basic", DamageMult = 0.66, Cooldown = 0.6, Range = 360, Pellets = 1, Spread = 0, CritBonus = 0.15,
		ShotScale = 1, SpeedScale = 1.6, BarrelLength = 1.9, BarrelThickness = 0.7,
		-- 역할: 정밀 단일 대상. 초당 계수 1.10 (다섯 무기 중 단일 대상 최고) + 치명타 +15%, 범위 피해는 없다
		Trait = "Precision · Best single-target damage · Crit +15%", Desc = "Fast, accurate shots with the highest single-target damage. No splash: pick your targets",
	},
	Smg = {
		Name = "Sniper Rifle", Form = "Basic", DamageMult = 1.65, Cooldown = 1.5, Range = 650, Pellets = 1, Spread = 0,
		ShotScale = 1.3, SpeedScale = 2.4, CritBonus = 0.25, BarrelLength = 1.4, BarrelThickness = 0.9,
		Trait = "Long range · Crit +25%", Desc = "Slow but each shot is powerful",
	},
	Revolver = {
		Name = "Bomb", Form = "Steel", DamageMult = 1.12, Cooldown = 1.1, Range = 320, Pellets = 1, Spread = 0,
		ShotScale = 1.15, SpeedScale = 1.1, CritBonus = 0.1, BarrelLength = 0.35, BarrelThickness = 1,
		Trait = "Heavy hitter · Crit +10%", Desc = "A heavy bomb lobbed at the target: slow but hits hard",
	},
	Rifle = {
		Name = "Bow", Form = "Rifle", DamageMult = 0.62, Cooldown = 0.6, Range = 420, Pellets = 1, Spread = 0,
		ShotScale = 0.9, SpeedScale = 1.4, CritBonus = 0.05, BarrelLength = 1.4, BarrelThickness = 0.45,
		Trait = "Fast fire rate · Long range", Desc = "Arrows fly far and true: steady shots from a distance",
	},
	Shotgun = {
		Name = "Shotgun", Form = "Basic", DamageMult = 0.26, Cooldown = 1.1, Range = 70, Pellets = 8, Spread = 12,
		ShotScale = 0.55, SpeedScale = 1.3, BarrelLength = 0.75, BarrelThickness = 1.5,
		-- 역할: 근접 폭발력. 60% 명중 기준 계수 1.13, 바짝 붙어 8알이 다 맞으면 약 1.9 (가장 위험한 거리에서 가장 강하다)
		Trait = "Point-blank burst · 8 pellets · Very short range", Desc = "8 pellets blast out in a wide cone. Up close every pellet hits for huge damage; at range most of them miss",
	},
	Flamer = {
		-- 역할: 연쇄 번개. 단일 대상 계수 0.90 (가장 낮다) 대신 4~7번 튀며 여러 적을 맞힌다 (튈 때마다 80%). (예전 2.72: 단일 대상까지 가장 강해서 다른 무기를 쓸 이유가 없었다)
		Name = "Spell Tome", Form = "Flamer", DamageMult = 1.8, Cooldown = 2.0, Range = 320, Pellets = 1, Spread = 0,
		ShotScale = 1.5, SpeedScale = 0.9, BarrelLength = 0.5, BarrelThickness = 1,
		Trait = "Chain Lightning · Jumps between enemies", Desc = "Lightning strikes the enemy you aim at, then jumps to nearby enemies one after another (4+ jumps, each hit a little weaker)",
	},
	Cannon = {
		Name = "Mortar", Form = "Cannon", DamageMult = 1.5, Cooldown = 1.3, Range = 360, Pellets = 1, Spread = 0, Splash = 7,
		ShotScale = 1.5, SpeedScale = 0.8, BarrelLength = 1.1, BarrelThickness = 1.8,
		Trait = "Small explosion · Slow shots", Desc = "Big shells that burst into a small explosion around the impact (radius 7)",
	},
	Sniper = {
		Name = "Crossbow", Form = "Basic", DamageMult = 1.6, Cooldown = 1.6, Range = 650, Pellets = 1, Spread = 0,
		ShotScale = 1.4, SpeedScale = 2.4, CritBonus = 0.25, BarrelLength = 1.9, BarrelThickness = 0.5,
		Trait = "Long range · Crit +25%", Desc = "Slow but each bolt is powerful",
	},
	Rocket = {
		Name = "Rocket Launcher", Form = "Rocket", DamageMult = 1.6, Cooldown = 1.7, Range = 340, Pellets = 1, Spread = 0, Splash = 15,
		ShotScale = 1.8, SpeedScale = 0.55, BarrelLength = 1.3, BarrelThickness = 1.6,
		-- 역할: 가장 큰 폭발. 단일 대상 계수 0.94 (낮다) 대신 반경 15 안의 적에게 50% 피해
		Trait = "Biggest explosion (radius 15) · Slow shots", Desc = "Slow rockets that explode on impact, hitting every enemy within radius 15 for half damage. Weaker against a single target",
	},
	Rail = {
		Name = "Railgun", Form = "Rail", DamageMult = 1.5, Cooldown = 1.5, Range = 700, Pellets = 1, Spread = 0, Pierce = 8, PierceMult = 0.93,
		ShotScale = 1.2, SpeedScale = 3, BarrelLength = 1.6, BarrelThickness = 0.8,
		-- 역할: 일직선 관통. 계수 1.00 + 앞에 줄 선 적을 최대 9마리까지 꿰뚫는다 (한 마리 지날 때마다 93%)
		Trait = "Piercing laser · Hits up to 9 enemies in a line", Desc = "An instant laser that punches straight through up to 9 enemies lined up in front of you (each one a little weaker). Longest range",
	},
}
