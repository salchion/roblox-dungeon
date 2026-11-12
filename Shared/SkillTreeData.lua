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

	-- 패시브 스킬 4종 (스킬 바에는 안 나온다, 골드로 1~10레벨). 값 = PerLevel x 레벨. 훈련(피해 감소 / 골드)과 겹치지 않는 새 메커니즘만
	local S = Config.Skills
	S.Bloodthirst = { Name = "Bloodthirst", Icon = "🩸", Key = "Passive", Cooldown = 0, Passive = true, PerLevel = 0.002, StatName = "HP per kill", Fmt = "%.1f%%", Scale = 100,
		Desc = "Every kill restores a little HP (keep killing to stay alive)" }
	S.Finisher = { Name = "Finisher", Icon = "🎯", Key = "Passive", Cooldown = 0, Passive = true, PerLevel = 0.03, StatName = "Damage to enemies under 30% HP", Fmt = "+%.0f%%", Scale = 100,
		Desc = "Deal more damage to enemies under 30% HP" }
	S.Rush = { Name = "Rush", Icon = "💨", Key = "Passive", Cooldown = 0, Passive = true, PerLevel = 0.03, StatName = "Attack for 2s after a dash", Fmt = "+%.0f%%", Scale = 100,
		Desc = "For 2s after a dash (Q), your attack is higher" }
	S.Fortune = { Name = "Treasure Sense", Icon = "💎", Key = "Passive", Cooldown = 0, Passive = true, PerLevel = 0.04, StatName = "Gear drop luck", Fmt = "+%.0f%%", Scale = 100,
		Desc = "Better luck on gear drops (higher rarities come more often)" }
	for _, key in ipairs({ "Bloodthirst", "Finisher", "Rush", "Fortune" }) do
		if not table.find(S.UpgradeOrder, key) then table.insert(S.UpgradeOrder, key) end
	end
	function Config.PassiveValue(player, key)
		local cfg = S[key]
		return cfg and cfg.PerLevel and cfg.PerLevel * (player:GetAttribute("SkillLv_" .. key) or 1) or 0
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
