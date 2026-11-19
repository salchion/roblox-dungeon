-- ConfigSkills (ReplicatedStorage 안의 ModuleScript, 이름: ConfigSkills)
-- Config.Skills (스킬 표): Config.lua 가 Roblox 스크립트 한 개 최대 크기(200,000자)에 닿아 따로 뺐다 (11-19 분할).
--   Config.lua 가 require 해서 Config.Skills 에 넣는다. 다른 Config 값을 참조하지 않는 순수 데이터 표 (뒤에서 Config 가 키를 더 붙이는 것은 그대로).
return {
	Order = { "Heal", "Spirit", "Ult" }, -- 방벽 / 충격파는 임팩트가 약해서 뺐다 (정의만 남겨둠)
	Barrier = { Name = "Energy Barrier", Icon = "🛡", Key = "Z", KeyCode = "Z", Cooldown = 14, Duration = 3,
		Desc = "A barrier that blocks all damage for 3s" },
	-- F: 블레이드 블룸(롤 카타리나 R 처럼): 2.5초 동안 몸 주위로 단검이 휘돌고, 0.12초마다 주변 적에게 단검이 최대 Daggers 자루씩 날아가 꽂힌다 (움직이며 쏠 수 있다). 한 자루 = 일반 공격 x Mult. 저장 / 슬롯 이름은 예전 그대로 Spirit.
	Spirit = { Name = "Blade Bloom", Icon = "🌸", Key = "F", KeyCode = "F", Cooldown = 10, Duration = 2.5, Interval = 0.12, Daggers = 4, Range = 44, Mult = 0.3, -- (Mult 는 무기의 초당 피해 계수 기준: 무기마다 한 발 위력이 달라도 연꽃 위력은 같다)
		Desc = "Area skill: daggers whirl around you for 2.5s and fly at many nearby enemies, four at a time. You can keep moving and shooting!" },
	Blast = { Name = "Shockwave", Icon = "💥", Key = "F", KeyCode = "F", Cooldown = 8, Radius = 16, Range = 90, Mult = 3,
		Desc = "Explodes where you aim (radius 16, attack x3)" },
	Heal = { Name = "First Aid", Icon = "💚", Key = "C", KeyCode = "C", Cooldown = 30, Radius = 40, Ratio = 0.08,
		Desc = "Restores 8% HP to you and nearby party members (+1%p per skill level)" },
	Ult = { Name = "Deadeye", Icon = "🎯", Key = "V", KeyCode = "V", Cooldown = 3, Radius = 110, Mult = 8, Cost = 100, MaxTargets = 6, Volleys = 12, VolleyGap = 0.09, -- 대상 수 / 일제 사격 횟수를 줄여 렉을 막는다 (빔 / 피해 숫자 / 폭발 효과가 대상 x 횟수만큼 생긴다)
		ShotsPerTarget = 8, ShotGap = 0.03,
		Missiles = 16, PoolMult = 4.5, RepeatDecay = 0.92, -- RepeatDecay: 같은 적에게 미사일이 거듭 맞을수록 한 발 피해가 이 배율씩 줄어든다 (한 마리에 12발이면 합계가 약 5발 분량)
		 -- 미사일 총 발수(대상 수와 상관없이 고정, 대상들에게 번갈아 나눠 간다) / 총 피해 배율 (한 마리면 12발이 전부 그 적에게 꽂힌다)
		Desc = "Single-target ultimate: use it when the gauge is full! Locks onto the biggest enemy in range (boss / elite first) and fires all 16 missiles at it" },
	ChargePerShot = 7,
	CooldownFloor = 0.3,       -- 쿨타임 바닥 비율(점근선): 응급 치료 / 궁극기는 기본의 30% 아래로는 안 내려가지만, 출처가 곱해지는 구조라 어떤 스탯이든 올리면 늘 효과가 있다
	SpiritCooldownFloor = 0.05, -- 블레이드 블룸(F)은 5% (풀파밍하면 약 1.8초, 여운 갈래면 약 1.3초: 지속 2.5초보다 짧아 계속 쓸 수 있다)
	-- 패시브 스킬 (스킬 강화 창에서 골드로 레벨업, 스킬 바에는 안 나온다)
	Focus = { Name = "Aura Focus", Icon = "⚡", Key = "Passive", Cooldown = 0, Passive = true,
		Desc = "The attack bonus built up by NEAR MISS lasts longer. At higher levels, part of the bonus (half at max level) stays even if your streak breaks" },
	UpgradeOrder = { "Heal", "Spirit", "Ult", "Focus" }, -- 스킬 강화 창 / 저장에 쓰는 목록
}
