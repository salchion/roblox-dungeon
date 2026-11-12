-- SkillTreeData (ReplicatedStorage 안의 ModuleScript, 이름: SkillTreeData)
-- 스킬 나무 확장: Config 가 Studio 한도(200KB)에 가까워서 따로 뺐다. Config 맨 끝에서 불러 Config 표에 덧붙인다.
--   1) 갈래 단계 Lv.3 / 5 / 7 / 10 (예전 5 / 10): Lv.3 / 7 은 Mods(수치 변화)로만 작동한다 -> Config.SkillMod 가 합쳐 준다
--   2) 스킬 시너지 (디아블로 2 식): 다른 스킬 레벨 1당 이 스킬이 강해진다
-- Mods 키: Damage(피해 배율 +) / Range(범위 배율 +) / Duration(지속 초 +) / Cooldown(쿨타임 배율 -) / Heal(회복 배율 +) / Refund(데드아이 게이지 반환)
--          NearMissTime(NEAR MISS 유지 초 +) / NearMissDmg(스택당 공격력 배율 +) / Floor(끊겨도 남는 스택 +)

return function(Config)
	Config.SkillBranchTiers = { 3, 5, 7, 10 }
	local B = Config.SkillBranch
	B.Spirit[3] = {
		A = { Icon = "🌀", Name = "Wide Arc", Desc = "Range +20%", Mods = { Range = 0.2 } },
		B = { Icon = "🔪", Name = "Keen Edge", Desc = "Damage +20%", Mods = { Damage = 0.2 } },
	}
	B.Spirit[7] = {
		A = { Icon = "🌪", Name = "Whirlwind", Desc = "Spins 1s longer", Mods = { Duration = 1 } },
		B = { Icon = "⚡", Name = "Quickdraw", Desc = "Cooldown -15%", Mods = { Cooldown = -0.15 } },
	}
	B.Ult[3] = {
		A = { Icon = "💢", Name = "Overcharge", Desc = "Damage +20%", Mods = { Damage = 0.2 } },
		B = { Icon = "🔋", Name = "Quick Gauge", Desc = "Gives back 15 gauge after use", Mods = { Refund = 15 } },
	}
	B.Ult[7] = {
		A = { Icon = "☠", Name = "Executioner", Desc = "Damage +35%", Mods = { Damage = 0.35 } },
		B = { Icon = "🔁", Name = "Second Wind", Desc = "Gives back 25 gauge after use", Mods = { Refund = 25 } },
	}
	B.Heal[3] = {
		A = { Icon = "🧪", Name = "Strong Salve", Desc = "Healing +25%", Mods = { Heal = 0.25 } },
		B = { Icon = "✋", Name = "Fast Hands", Desc = "Cooldown -15%", Mods = { Cooldown = -0.15 } },
	}
	B.Heal[7] = {
		A = { Icon = "💗", Name = "Deep Mend", Desc = "Healing +40%", Mods = { Heal = 0.4 } },
		B = { Icon = "⏱", Name = "Rapid Aid", Desc = "Cooldown -20%", Mods = { Cooldown = -0.2 } },
	}
	B.Focus[3] = {
		A = { Icon = "⌛", Name = "Lingering", Desc = "NEAR MISS lasts +2s", Mods = { NearMissTime = 2 } },
		B = { Icon = "🗡", Name = "Sharpened", Desc = "Each NEAR MISS stack gives +15% more attack", Mods = { NearMissDmg = 0.15 } },
	}
	B.Focus[7] = {
		A = { Icon = "🔥", Name = "Battle Trance", Desc = "Each NEAR MISS stack gives +25% more attack", Mods = { NearMissDmg = 0.25 } },
		B = { Icon = "🧱", Name = "Iron Will", Desc = "Keeps 2 more stacks even if broken", Mods = { Floor = 2 } },
	}

	-- 스킬 시너지: From 스킬 레벨 1당(1레벨은 0) Stat 이 Per 만큼. 한 바퀴로 이어진다 (Focus -> Spirit -> Ult -> Heal -> Focus)
	Config.SkillSynergy = {
		Spirit = { From = "Focus", Stat = "Damage", Per = 0.04, Text = "Blade Bloom damage +4% per Focus level" },
		Ult = { From = "Spirit", Stat = "Damage", Per = 0.03, Text = "Dead Eye damage +3% per Blade Bloom level" },
		Heal = { From = "Ult", Stat = "Cooldown", Per = -0.02, Text = "First Aid cooldown -2% per Dead Eye level" },
		Focus = { From = "Heal", Stat = "NearMissTime", Per = 0.15, Text = "NEAR MISS lasts +0.15s per First Aid level" },
	}

	-- 특성 트리 (와우 방식): 레벨 5마다 특성 점수 1 (최대 30). 다섯 줄이고, 위쪽 줄에 점수를 일정 이상 써야 아래 줄이 열린다.
	-- 칸마다 최대 몇 번 찍을 수 있고(Max), "선택" 칸은 두 길 중 하나만 고른다. 마을에서 골드로 초기화할 수 있다.
	-- 값: Per (특성 칸 하나당 PassiveValue 값) / Mods (특성 한 점당 스탯: Config.TalentMod 가 합친다)
	Config.Talents = {
		PointsPerLevels = 5, MaxPoints = 30,
		RowNeed = { 0, 5, 10, 15, 20 }, -- 이 줄을 찍으려면 위쪽 줄에 이만큼 써야 한다
		Order = { "Bloodthirst", "Finisher", "Fortune", "Rush", "Hide", "Golden", "SurviveChoice", "Threshold", "RushGuard", "BossBreaker", "RushCrit", "Treasure2", "Capstone" },
		Bloodthirst = { Row = 1, Icon = "🩸", Name = "Bloodthirst", Max = 5, Per = 0.004, Desc = "Every kill restores 0.4% max HP per point" },
		Finisher = { Row = 1, Icon = "🎯", Name = "Finisher", Max = 5, Per = 0.06, Desc = "+6% damage per point to enemies under 30% HP" },
		Fortune = { Row = 1, Icon = "💎", Name = "Treasure Sense", Max = 5, Per = 0.08, Desc = "+8% gear drop luck per point" },
		Rush = { Row = 2, Icon = "💨", Name = "Rush", Max = 5, Per = 0.06, Desc = "+6% attack per point for 2s after a dash (Q)" },
		Hide = { Row = 2, Icon = "🛡", Name = "Iron Stomach", Max = 3, Mods = { DmgReduce = 0.04 }, Desc = "Take 4% less damage per point" },
		Golden = { Row = 2, Icon = "💰", Name = "Golden Touch", Max = 3, Mods = { Gold = 0.05 }, Desc = "+5% gold per point" },
		SurviveChoice = { Row = 3, Icon = "❤", Name = "Survival Instinct", Max = 1, Choice = {
			A = { Icon = "💗", Name = "Lifeline", Desc = "Bloodthirst heals twice as much while under 30% HP", Mods = { LowHeal = 1 } },
			B = { Icon = "⏳", Name = "Bloodrush", Desc = "Every kill cuts all skill cooldowns by 0.2s", Mods = { KillCdr = 0.2 } } } },
		Threshold = { Row = 3, Icon = "🪓", Name = "Early Finish", Max = 1, Mods = { Threshold = 0.15 }, Desc = "Finisher works under 45% HP instead of 30%" },
		RushGuard = { Row = 3, Icon = "🌀", Name = "Rush Guard", Max = 1, Mods = { RushGuard = 0.3 }, Desc = "Take 30% less damage for 2s after a dash" },
		BossBreaker = { Row = 4, Icon = "👑", Name = "Boss Breaker", Max = 3, Mods = { BossAny = 0.05 }, Desc = "+5% damage per point to bosses and elites at any HP" },
		RushCrit = { Row = 4, Icon = "⚡", Name = "Rush Crit", Max = 3, Mods = { RushCrit = 0.07 }, Desc = "+7% crit chance per point for 2s after a dash" },
		Treasure2 = { Row = 4, Icon = "🗝", Name = "Deep Pockets", Max = 3, Mods = { Luck = 0.1 }, Desc = "+10% gear drop luck per point" },
		Capstone = { Row = 5, Icon = "🌟", Name = "Mastery", Max = 1, Choice = {
			A = { Icon = "☠", Name = "Mercy Kill", Desc = "Non-boss enemies under 10% HP die instantly", Mods = { Execute = 0.1 } },
			B = { Icon = "🔥", Name = "Blood Frenzy", Desc = "Each kill gives +2% attack for 5s (stacks up to 10)", Mods = { Frenzy = 1 } } } },
	}
	function Config.TalentPoints(level)
		local T = Config.Talents
		return math.min(T.MaxPoints, math.floor((level or 1) / T.PointsPerLevels))
	end
	function Config.TalentResetCost(level)
		return 2000 * math.max(1, level or 1)
	end
	-- 특성 칸에 찍은 점수 (선택 칸은 0 / 1) 와 고른 길 (선택 칸만 "A" / "B")
	function Config.TalentRank(player, key)
		return player:GetAttribute("Tal_" .. key) or 0
	end
	-- 특성 한 점당 Mods 를 모두 합친 값 (선택 칸은 고른 길의 Mods)
	function Config.TalentMod(player, stat)
		local total = 0
		for _, key in ipairs(Config.Talents.Order) do
			local node = Config.Talents[key]
			local rank = Config.TalentRank(player, key)
			if rank > 0 then
				local mods = node.Mods
				if node.Choice then
					local side = player:GetAttribute("TalS_" .. key)
					mods = side and node.Choice[side] and node.Choice[side].Mods
				end
				if mods and mods[stat] then total += mods[stat] * rank end
			end
		end
		return total
	end
	function Config.PassiveValue(player, key)
		local node = Config.Talents[key]
		local value = node and node.Per and node.Per * Config.TalentRank(player, key) or 0
		if key == "Fortune" then value += Config.TalentMod(player, "Luck") end
		return value
	end

	-- 갈래(Lv.3 / 7 의 Mods) + 시너지를 합친 값
	function Config.SkillMod(player, key, stat)
		local total = 0
		local branches = Config.SkillBranch[key]
		if branches then
			for _, tier in ipairs(Config.SkillBranchTiers) do
				local side = Config.GetSkillBranch(player, key, tier)
				local def = side and branches[tier] and branches[tier][side]
				if def and def.Mods and def.Mods[stat] then total += def.Mods[stat] end
			end
		end
		local syn = Config.SkillSynergy[key]
		if syn and syn.Stat == stat then
			total += syn.Per * math.max(0, (player:GetAttribute("SkillLv_" .. syn.From) or 1) - 1)
		end
		return total
	end
end
