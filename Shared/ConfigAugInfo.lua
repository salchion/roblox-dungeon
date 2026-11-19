-- ConfigAugInfo (ReplicatedStorage 안의 ModuleScript, 이름: ConfigAugInfo)
-- Config.AugInfo (세트 효과 이름 / 설명 표): Config.lua 가 Roblox 스크립트 한 개 최대 크기(200,000자)에 닿아 따로 뺐다 (11-19 분할).
--   Config.lua 가 require 해서 Config.AugInfo 에 넣는다. 다른 Config 값을 참조하지 않는 순수 데이터 표 (뒤에서 Config 가 키를 더 붙이는 것은 그대로).
return {
	AugMissile = { Icon = "🚀", Name = "Crit Missile", Desc = "Every crit fires a salvo of missiles into the enemy you hit", Color = Color3.fromRGB(255, 150, 60) },
	AugNova = { Icon = "☄", Name = "Kill Burst", Desc = "Killing an enemy causes a big explosion that spreads to nearby enemies", Color = Color3.fromRGB(255, 80, 70) },
	AugOrbit = { Icon = "🌀", Name = "Ricochet Blades", Desc = "Every few shots, a blade bounces between enemies, slashing them in a row (faster-firing weapons throw it more often)", Color = Color3.fromRGB(110, 230, 255) },
	AugStorm = { Icon = "⛈", Name = "Lightning Strike", Desc = "Lightning periodically strikes nearby enemies from the sky", Color = Color3.fromRGB(255, 240, 110) },
	AugFlame = { Icon = "🔥", Name = "Ignite", Desc = "Your hits stack burning on the target; the longer you hit it, the hotter it burns", Color = Color3.fromRGB(255, 130, 40) },
	AugExecute = { Icon = "💀", Name = "Execute", Desc = "Low-HP enemies are executed on hit; bosses take more damage the lower their HP", Color = Color3.fromRGB(210, 90, 255) },
	AugMeteor = { Icon = "🌠", Name = "Meteor Shower", Desc = "Meteors fall on the biggest crowd (or on a nearby boss) and hit hard", Color = Color3.fromRGB(255, 190, 90) },
	-- 방어 기재 6종 (세트 효과와 같은 칸을 쓴다. 구역 세트가 없어 4~6단계는 🔷 수호석. 효과는 DamageGuard / GetMaxHealth)
	AugWard = { Icon = "🛡", Name = "Ward", Desc = "Every hit you take is reduced", Color = Color3.fromRGB(120, 180, 255), Defense = true },
	AugBody = { Icon = "❤️", Name = "Iron Body", Desc = "Raises your max HP", Color = Color3.fromRGB(255, 120, 140), Defense = true },
	AugBuffer = { Icon = "⏳", Name = "Cushion", Desc = "Part of each hit is taken over 3s instead of at once — time to dodge or heal", Color = Color3.fromRGB(150, 210, 255), Defense = true },
	AugEvade = { Icon = "🌀", Name = "Evasion", Desc = "A chance to dodge a hit completely", Color = Color3.fromRGB(140, 240, 220), Defense = true },
	AugGrit = { Icon = "🔥", Name = "Grit", Desc = "Take less damage when your HP is low", Color = Color3.fromRGB(255, 160, 90), Defense = true },
	AugRegen = { Icon = "💚", Name = "Regeneration", Desc = "Recover HP every second in combat (pauses 2s after a hit)", Color = Color3.fromRGB(120, 230, 140), Defense = true },
	AugPulse = { Icon = "💥", Name = "Shockwave Shot", Desc = "Explosive shots fly at nearby enemies and burst big on impact", Color = Color3.fromRGB(110, 255, 190) },
}
