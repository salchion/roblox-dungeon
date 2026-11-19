-- ConfigCodex (ReplicatedStorage 안의 ModuleScript, 이름: ConfigCodex)
-- Config.Codex (도감 표): Config.lua 가 Roblox 스크립트 한 개 최대 크기(200,000자)에 닿아 따로 뺐다 (11-19 분할).
--   Config.lua 가 require 해서 Config.Codex 에 넣는다. 다른 Config 값을 참조하지 않는 순수 데이터 표 (뒤에서 Config 가 키를 더 붙이는 것은 그대로).
return {
	Monsters = {
		Slime = { Name = "Slime", Icon = "🟢", Desc = "A squishy droplet. Approaches slowly and shoots one shot at a time." },
		Spitter = { Name = "Spiny Venomworm", Icon = "🐛", Desc = "Spits thorns from afar. Keeps its distance while shooting." },
		Bat = { Name = "Bat", Icon = "🦇", Desc = "Flies around quickly, throwing crescent-moon shots." },
		Mage = { Name = "Mage Ghost", Icon = "👻", Desc = "Fires homing shots from afar. Shoots slowly but relentlessly." },
		Golem = { Name = "Rock Golem", Icon = "🗿", Desc = "Slow but tough, and its smash really hurts." },
		Charger = { Name = "Charging Boar", Icon = "🐗", Desc = "Lowers its tusks and charges. Watch for the tell before the charge and dodge!" },
		Bomber = { Name = "Bomber", Icon = "💣", Desc = "Runs up and explodes. Take it out before it gets close." },
		Imp = { Name = "Sniper Imp", Icon = "😈", Desc = "Hurls fast spears from very far away. Some shots split apart." },
		Turret = { Name = "Magic Turret", Icon = "🔫", Desc = "Stays put and fires beams. Long range." },
		Spider = { Name = "Venom Spider", Icon = "🕷", Desc = "Rushes in fast, firing poison stingers in succession." },
		Wisp = { Name = "Will-o'-Wisp", Icon = "🔥", Desc = "Floats around quickly, emitting ring-shaped shots." },
		Healer = { Name = "Healing Priest", Icon = "💚", Desc = "Heals nearby monsters. Best to take it out first." },
		Totem = { Name = "Curse Totem", Icon = "🗿", Desc = "Fires ring shots in all directions from a fixed spot." },
	},
	Bosses = { "Vine Giant", "Ancient Stag Spirit", "One-Eyed Rock Giant", "Giant Scorpion", "Ice Crystal Lord", "Lava Demon", "Dark Reaper", "Eye of the Abyss" },
}
