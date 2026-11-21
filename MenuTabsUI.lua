-- MenuTabsUI (StarterPlayer > StarterPlayerScripts 안의 ModuleScript, 이름: MenuTabsUI)
-- 메뉴(B) > 캐릭터 / 무기 / 성장(돌파 · 시간 건너뛰기) 탭과 스킬 수치 글자를 그린다.
-- PlayerClient 가 Studio 스크립트 한도(200KB)에 가까워서 함수 본문을 그대로 옮겼다 (동작 변경 없음). 필요한 것은 Init(env) 로 넘겨 받는다.
--   env: Config, Remotes, ReplicatedStorage, player, GREEN, RED, GRAY, MENU, settings, create, makeButton, makeLabel, makePanel, rounded, hex,
--        newRow, rowText, sectionTitle, xpBack, xpFill, attackCooldown(함수), growthRemaining(함수), getQuestState(함수), getGrowthState(함수)
--   questState / growthState 는 PlayerClient 에서 다시 대입되므로, 내보내는 함수를 부를 때마다 get 함수로 새 값을 받아 둔다.

local MenuTabs = {}

function MenuTabs.Init(env)
	local Config, Remotes, ReplicatedStorage, player = env.Config, env.Remotes, env.ReplicatedStorage, env.player
	local GREEN, RED, GRAY, MENU, settings = env.GREEN, env.RED, env.GRAY, env.MENU, env.settings
	local create, makeButton, makeLabel, makePanel, rounded, hex = env.create, env.makeButton, env.makeLabel, env.makePanel, env.rounded, env.hex
	local newRow, rowText, sectionTitle, xpBack, xpFill = env.newRow, env.rowText, env.sectionTitle, env.xpBack, env.xpFill
	local attackCooldown, growthRemaining = env.attackCooldown, env.growthRemaining
	local questState, growthState = nil, nil
	local function sync()
		questState = env.getQuestState()
		growthState = env.getGrowthState()
	end

	local function buildCharacterTab()
		local weaponType = Config.GetPlayerWeapon(player)
		local health = Config.Player.BaseHealth + (player:GetAttribute("HealthPoints") or 0) * Config.Player.HealthPerPoint + (player:GetAttribute("GearHealth") or 0) + (player:GetAttribute("TrainHealth") or 0) + Config.GetLevelHealth(player:GetAttribute("Level") or 1)
		-- 실제 공식(DungeonService.ComputeDamage)과 같게: 훈련 / 펫 치명타 포함, 최대 90%
		local rawCrit = (player:GetAttribute("CritPoints") or 0) * Config.Player.CritPerPoint + (player:GetAttribute("GearCrit") or 0)
			+ (player:GetAttribute("TrainCrit") or 0) + (player:GetAttribute("PetCrit") or 0) + (weaponType.CritBonus or 0)
		local crit = math.min(0.9, rawCrit) * 100
		local critOver = math.max(0, rawCrit - 0.9) * 100 -- 넘친 만큼 치명타 피해로
		local speed = Config.Player.WalkSpeed + (player:GetAttribute("GearSpeed") or 0)

		-- 정보 카드: 레벨 + 경험치 막대 / 전투력 / 능력치 타일 8칸 (예전: 이모지 섞인 글자 덩어리 한 장)
		local menuLevel = player:GetAttribute("Level") or 1
		local function groupDigits(n)
			return (tostring(math.floor(n or 0)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
		end
		local function shortNum(n)
			n = n or 0
			if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
			if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
			return groupDigits(n)
		end
		local summary = newRow(116)
		local xp, xpNeeded = player:GetAttribute("XP") or 0, math.max(1, player:GetAttribute("XPNeeded") or 1)
		local maxed = menuLevel >= Config.Level.Max
		makeLabel({ Size = UDim2.new(0, 120, 0, 34), Position = UDim2.new(0, 14, 0, 10), Text = "Lv." .. menuLevel, TextSize = 26, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(143, 216, 255), TextXAlignment = Enum.TextXAlignment.Left }, summary)
		makeLabel({ Size = UDim2.new(1, -150, 0, 34), Position = UDim2.new(0, 136, 0, 10), Text = "⚡ " .. groupDigits(player:GetAttribute("Power") or 0), TextSize = 24, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 225, 110), TextXAlignment = Enum.TextXAlignment.Right }, summary)
		local xpBack = create("Frame", { Size = UDim2.new(1, -28, 0, 8), Position = UDim2.new(0, 14, 0, 48), BackgroundColor3 = Color3.fromRGB(20, 22, 34), BorderSizePixel = 0 }, summary)
		rounded(xpBack, 4)
		local xpFill = create("Frame", { Size = UDim2.new(maxed and 1 or math.clamp(xp / xpNeeded, 0, 1), 0, 1, 0), BackgroundColor3 = Color3.fromRGB(110, 200, 255), BorderSizePixel = 0 }, xpBack)
		rounded(xpFill, 4)
		makeLabel({ Size = UDim2.new(0.5, 0, 0, 16), Position = UDim2.new(0.5, -14, 0, 58), Text = maxed and "MAX LEVEL" or string.format("%s / %s XP", groupDigits(xp), groupDigits(xpNeeded)), TextSize = 12, TextColor3 = Color3.fromRGB(150, 158, 190), TextXAlignment = Enum.TextXAlignment.Right }, summary)
		-- 진행 칩 (골드 / 티켓 / 최고 구역 / 던전)
		local chips = {
			"💰 " .. shortNum(player:GetAttribute("Gold") or 0), "🎫 " .. groupDigits(player:GetAttribute("Tickets") or 0),
			"🗺 Zone " .. tostring(player:GetAttribute("MaxZone") or 0) .. " / " .. Config.Field.ZoneCount, "🏰 Dungeons " .. groupDigits(questState and questState.Stats and questState.Stats.DungeonClears or 0),
		}
		for i, text in ipairs(chips) do
			local chip = makeLabel({ Size = UDim2.new(0.25, -12, 0, 26), Position = UDim2.new((i - 1) * 0.25, 10, 0, 80), Text = text, TextSize = 12, Font = Enum.Font.GothamBold, BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(26, 28, 44) }, summary)
			rounded(chip, 13)
		end

		-- 능력치: 공격 / 방어 / 유틸 세 장의 카드 (각 줄 = 아이콘 구슬 + 이름 + 큰 값)
		local weaponNow = weaponType
		local critMult = Config.Player.CritMultiplier + (player:GetAttribute("LvCritDmg") or 0) + (player:GetAttribute("TrainCritDmg") or 0) + (player:GetAttribute("GearCritDmg") or 0) + (player:GetAttribute("ParCritDmg") or 0) + critOver / 100
		local D = Config.Defense
		local defense = menuLevel * D.LevelDef + (player:GetAttribute("GearHealth") or 0) * D.GearDef
		local reduction = 1 - (1 - Config.SoftCap(defense / (defense + D.K), D.MaxReduction)) * (1 - (player:GetAttribute("GearBulwark") or 0))
		local moveSpeed = Config.Player.WalkSpeed + (player:GetAttribute("GearSpeed") or 0) + (player:GetAttribute("TrainSpeed") or 0) + (player:GetAttribute("PetSpeed") or 0) + (player:GetAttribute("LvMove") or 0)
		local function pct(v, digits) return string.format(digits and "%.1f%%" or "%d%%", digits and v * 100 or math.floor(v * 100 + 0.5)) end
		local groups = {
			{ "⚔ Offense", Color3.fromRGB(255, 120, 90), {
				{ "⚔", "Attack", groupDigits(Config.BaseAttackEstimate(player) * (1 + (player:GetAttribute("ParAttack") or 0))) },
				{ "🎯", "Crit Chance", string.format("%.1f%%", crit) },
				{ "💥", "Crit Damage", string.format("x%.2f", critMult) },
				{ "⏩", "Attack Speed", string.format("%.1f/s", 1 / math.max(0.05, attackCooldown())) },
				{ "🔫", "Double Shot", pct((player:GetAttribute("LvDouble") or 0) + (player:GetAttribute("TrainDouble") or 0), true) },
				{ "👑", "Boss Damage", "+" .. pct((player:GetAttribute("GearBossDmg") or 0) + (player:GetAttribute("ParBoss") or 0)) },
				{ "📏", "Range", tostring(math.floor(Config.GetRange(player, weaponNow) + 0.5)) },
			} },
			{ "🛡 Defense", Color3.fromRGB(110, 170, 255), {
				{ "❤", "Max HP", groupDigits(health) },
				{ "🛡", "Damage Taken", "-" .. pct(reduction, true) },
				{ "🦇", "Heal on Kill", pct(player:GetAttribute("GearLifeOnKill") or 0, true) },
			} },
			{ "🧭 Utility", Color3.fromRGB(110, 220, 150), {
				{ "💨", "Move Speed", string.format("%.1f", moveSpeed) },
				{ "⏱", "Skill Cooldown", "-" .. pct((function() -- (서버 SkillService.CooldownFor 와 같은 곱셈 곡선 / 바닥: 실제로 줄어드는 비율, 스킬 레벨 제외)
					local function part(v) return 1 / (1 + 1.5 * math.max(0, v or 0)) end
					local factor = part(player:GetAttribute("GearHaste")) * part(player:GetAttribute("PetHaste")) * part(player:GetAttribute("LvHaste"))
					local floorRatio = Config.Skills.CooldownFloor or 0.3
					return 1 - (floorRatio + (1 - floorRatio) * factor)
				end)()) },
				{ "🍀", "Luck", "+" .. pct(player:GetAttribute("GearLuck") or 0) },
				{ "📘", "XP", "+" .. pct((player:GetAttribute("GearXp") or 0) + (player:GetAttribute("PetXp") or 0)) },
				{ "💰", "Gold", "+" .. pct(Config.GoldBonus(player) - 1) },
			} },
		}
		local cardRow = newRow(46 + 7 * 38 + 10, Color3.fromRGB(20, 22, 34))
		for gi, group in ipairs(groups) do
			local card = create("Frame", { Size = UDim2.new(1 / 3, -12, 1, -12), Position = UDim2.new((gi - 1) / 3, 8, 0, 6), BackgroundColor3 = group[2]:Lerp(Color3.fromRGB(22, 24, 38), 0.86), BorderSizePixel = 0 }, cardRow)
			rounded(card, 14)
			create("UIStroke", { Color = group[2], Thickness = 1.5, Transparency = 0.35 }, card)
			makeLabel({ Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 0, 6), Text = group[1], TextSize = 16, Font = Enum.Font.GothamBlack, TextColor3 = group[2] }, card)
			for si, stat in ipairs(group[3]) do
				local y = 44 + (si - 1) * 38
				local orb = create("Frame", { Size = UDim2.new(0, 30, 0, 30), Position = UDim2.new(0, 10, 0, y), BackgroundColor3 = group[2]:Lerp(Color3.fromRGB(20, 22, 34), 0.6), BorderSizePixel = 0 }, card)
				rounded(orb, 15)
				makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = stat[1], TextSize = 15 }, orb)
				makeLabel({ Size = UDim2.new(0.55, -46, 0, 30), Position = UDim2.new(0, 46, 0, y), Text = stat[2], TextSize = 12, TextColor3 = Color3.fromRGB(190, 196, 220), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, card)
				makeLabel({ Size = UDim2.new(0.45, -12, 0, 30), Position = UDim2.new(0.55, 0, 0, y), Text = stat[3], TextSize = 16, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Right }, card)
			end
		end

		sectionTitle("Titles (unlocked via achievements, shown on your nameplate)")
		local titles = questState and questState.Titles or {}
		local equipped = questState and questState.Equipped
		if #titles == 0 then
			local row = newRow(36)
			rowText(row, "<font color='#888888'>No titles unlocked yet. Try the achievements under Quests!</font>")
		end
		for _, title in ipairs(titles) do
			local row = newRow(40)
			rowText(row, string.format("『%s』", title), 16, 150)
			local isEquipped = title == equipped
			makeButton({
				Size = UDim2.new(0, 110, 0, 28), Position = UDim2.new(1, -122, 0.5, -14),
				Text = isEquipped and "Remove" or "Equip", BackgroundColor3 = isEquipped and RED or GREEN,
			}, row, function()
				Remotes.Quest:FireServer("Title", isEquipped and "" or title)
			end)
		end
	end

	local function buildWeaponTab()
		local level = player:GetAttribute("WeaponLevel") or 0
		local order = Config.WeaponTypes.Order
		local equippedKey = Config.ResolveWeaponType(level, player:GetAttribute("WeaponType"))
		local eraTier = Config.GetWeaponTier(level)
		sectionTitle(string.format("🔫 5 Weapon Types — one unlocks per upgrade milestone (every 15). Pick which unlocked weapon to fight with · Now: %s", Config.GetEraName(eraTier.Era)))

		do -- 맨 위: 무기 강화 바로가기 (골드가 모이면 빨간 점 + 초록 버튼). 강화는 마을에서만 된다
			local row = newRow(46, Color3.fromRGB(34, 30, 50))
			local can = MENU.WeaponUpgradable()
			local inLobby = player:GetAttribute("Zone") == "Lobby"
			local maxed = level >= Config.Weapon.MaxLevel
			local okCost, upCost = pcall(Config.GetEnhanceCost, level)
			makeLabel({ Size = UDim2.new(1, -230, 1, 0), Position = UDim2.new(0, 14, 0, 0), RichText = true, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
				Text = maxed and "🔨 <b>Weapon Upgrade</b>  <font color='#ffd966'>MAX</font>"
					or string.format("🔨 <b>Weapon Upgrade</b>  <font color='#bbbbcc'>+%d → +%d</font>  <font color='#ffd966'>💰 %s G</font>", level, level + 1, okCost and tostring(upCost) or "?") }, row)
			local go = makeButton({
				Size = UDim2.new(0, 190, 0, 34), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), TextSize = 12, Font = Enum.Font.GothamBlack,
				Text = maxed and "MAX" or (inLobby and (can and "🔨 Upgrade now!" or "🔨 Open Upgrade") or "Upgrade in town"),
				BackgroundColor3 = (can and GREEN) or ((inLobby and not maxed) and Color3.fromRGB(70, 90, 170) or GRAY),
			}, row, function()
				if inLobby and not maxed then player:SetAttribute("OpenEnhance", os.clock()) end
			end)
			rounded(go, 17)
			if can then
				local dot = makeLabel({ Size = UDim2.new(0, 20, 0, 20), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -2, 0, 2), Text = "!", TextSize = 12, Font = Enum.Font.GothamBlack,
					BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(235, 60, 60), ZIndex = 5 }, go)
				create("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
				create("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.5 }, dot)
			end
		end

		local previewKey = Config.WeaponTypes[settings.PreviewForm or ""] and settings.PreviewForm ~= "Order" and settings.PreviewForm or equippedKey
		local shown = Config.GetLookTier(level, previewKey) -- 그 무기 형 + 지금 시대의 외모 / 탄 색
		local classInfo = Config.WeaponTypes[previewKey]
		local unlocked = Config.IsWeaponUnlocked(level, previewKey)
		local isMine = previewKey == equippedKey

		local header = newRow(262)
		do
			local viewport = create("ViewportFrame", {
				Size = UDim2.new(0, 270, 0, 238), Position = UDim2.new(0, 12, 0, 12), BackgroundColor3 = Color3.fromRGB(24, 26, 42), BorderSizePixel = 0,
				Ambient = Color3.fromRGB(190, 190, 200), LightColor = Color3.new(1, 1, 1),
			}, header)
			rounded(viewport, 10)
			create("UIStroke", { Color = shown.Rainbow and Color3.fromRGB(255, 120, 255) or shown.Color, Thickness = 2 }, viewport)
			settings.BuildFireDemo(viewport, shown, classInfo)
			makeLabel({ Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -22), Text = isMine and "My Weapon · Fire Demo" or "👀 Preview · Fire Demo", TextSize = 9, TextColor3 = Color3.fromRGB(170, 180, 210) }, viewport)
		end

		local SHOT_NAMES = { Ball = "Small Bullet", Bolt = "Light Bolt", Orb = "Energy Orb", Cannon = "Heavy Shell", Fire = "Fireball", Rocket = "Rocket", Rainbow = "Rainbow Orb" }
		local shotInfo = shown.Shot or { Style = "Ball" }
		local behavior = {}
		if classInfo.Pellets > 1 then table.insert(behavior, string.format("Fires %d pellets in a spread", classInfo.Pellets)) end
		if classInfo.Splash then table.insert(behavior, string.format("Explodes on hit (radius %d)", classInfo.Splash)) end
		if classInfo.Pierce then table.insert(behavior, string.format("Pierces up to %d enemies", classInfo.Pierce + 1)) end
		if classInfo.Bounce then table.insert(behavior, string.format("Bounces to %d nearby enemies (within %d)", classInfo.Bounce, classInfo.BounceRange or 34)) end
		if (classInfo.CritBonus or 0) > 0 then table.insert(behavior, string.format("Crit +%d%%", math.floor(classInfo.CritBonus * 100 + 0.5))) end
		if #behavior == 0 then table.insert(behavior, "Flies straight and hits one enemy") end
		local rate = 1 / math.max(0.05, classInfo.Cooldown * Config.Player.BaseCooldown)
		local status
		if isMine then
			status = "<font color='#78ff8c'>▶ In use</font>"
		elseif unlocked then
			status = "<font color='#ffd966'>✔ Unlocked</font>"
		else
			status = string.format("<font color='#ff9a6e'>🔒 Unlocks at +%d (%d to go)</font>", Config.GetUnlockLevel(previewKey), math.max(0, Config.GetUnlockLevel(previewKey) - level))
		end
		local power = Config.WeaponDpsFactor(classInfo)
		local nameColor = hex(shown.Rainbow and Color3.fromRGB(255, 120, 255) or shown.Color)
		makeLabel({
			Size = UDim2.new(1, -366, 1, -64), Position = UDim2.new(0, 294, 0, 10), RichText = true, TextSize = 12, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			Text = string.format(
				"<font size='17'><b><font color='#%s'>%s</font></b></font>  <font size='10' color='#aab0cc'>%s</font>\n%s\n<font color='#ffe9a0'><b>%s</b></font>\n<font color='#bbbbcc'>%s</font>\n\n<b>🔫 Attack Style</b>\n<font color='#dfe6ff'>• Shot type: %s\n• %s\n• About %.1f shots/sec · Firepower %d · Range %d</font>",
				nameColor, classInfo.Name, Config.GetEraName(shown.Era), status, classInfo.Trait, classInfo.Desc,
				SHOT_NAMES[shotInfo.Style] or "Bullet", table.concat(behavior, " · "),
				rate, math.floor(power * 100 + 0.5), classInfo.Range
			),
		}, header)
		if unlocked and not isMine then
			makeButton({
				Size = UDim2.new(0, 190, 0, 40), Position = UDim2.new(1, -202, 1, -52), Text = "🔫 Fight with this weapon", BackgroundColor3 = GREEN,
			}, header, function()
				Remotes.Weapon:FireServer("Equip", previewKey)
				settings.PreviewForm = nil
				task.delay(0.3, function() settings.RefreshMenu() end)
			end)
		end

		-- 목록 대신 < > 화살표로 넘긴다 (+ 아래 무기 구슬 줄: 지금 보는 무기 / 쓰는 무기 / 잠김)
		local function show(key)
			settings.PreviewForm = key
			settings.DemoClock = 0
			settings.RefreshMenu()
		end
		local index = table.find(order, previewKey) or 1
		for _, arrow in ipairs({ { "◀", -1, UDim2.new(0, 16, 0, 108) }, { "▶", 1, UDim2.new(1, -60, 0, 108) } }) do
			local b = makeButton({ Size = UDim2.new(0, 44, 0, 44), Position = arrow[3], Text = arrow[1], TextSize = 18, Font = Enum.Font.GothamBlack, BackgroundColor3 = Color3.fromRGB(46, 50, 84), ZIndex = 6 }, header, function()
				show(order[(index - 1 + arrow[2]) % #order + 1])
			end)
			rounded(b, 22)
			create("UIStroke", { Color = Color3.fromRGB(225, 196, 118), Thickness = 1.5, Transparency = 0.3 }, b)
		end
		local pips = newRow(64, Color3.fromRGB(26, 28, 44))
		local spacing = 64
		for i, key in ipairs(order) do
			local info = Config.WeaponTypes[key]
			local look = Config.GetLookTier(level, key)
			local open = Config.IsWeaponUnlocked(level, key)
			local here = key == previewKey
			local orb = create("TextButton", {
				Size = UDim2.new(0, here and 46 or 38, 0, here and 46 or 38), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, (i - (#order + 1) / 2) * spacing, 0.5, 0),
				BackgroundColor3 = open and look.Color:Lerp(Color3.fromRGB(20, 22, 36), 0.55) or Color3.fromRGB(34, 34, 46), BorderSizePixel = 0, Text = open and (key == equippedKey and "▶" or "") or "🔒",
				TextSize = 14, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(150, 255, 170), AutoButtonColor = true,
			}, pips)
			rounded(orb, here and 23 or 19)
			create("UIStroke", { Color = here and Color3.new(1, 1, 1) or (open and look.Color or Color3.fromRGB(70, 72, 100)), Thickness = here and 3 or 1.5 }, orb)
			if i < #order then
				create("Frame", { Size = UDim2.new(0, spacing - 48, 0, 2), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, (i - (#order + 1) / 2) * spacing + 24, 0.5, 0), BackgroundColor3 = Color3.fromRGB(80, 80, 110), BorderSizePixel = 0 }, pips)
			end
			orb:SetAttribute("Tip", info.Name)
			orb.Activated:Connect(function() show(key) end)
		end
	end

	local function buildGrowthTab() -- (돌파 칸만: 시간 건너뛰기 / 훈련 칸 수는 맨 위 한 줄 buildSkipGaugeRow 가 보여 준다)
		local state = growthState
		if not state then
			local row = newRow(36)
			rowText(row, "<font color='#888888'>Loading...</font>")
			return
		end

		local gateIndex
		for index, gate in ipairs(Config.Growth.Gates) do
			if gate > state.GatePassed then
				gateIndex = index
				break
			end
		end

		if not gateIndex then return end -- 돌파를 다 마쳤으면 이 칸은 아예 보여 주지 않는다
		sectionTitle("🚧 Breakthrough — pass the level caps")
		local gateRow = newRow(92)
		do
			local gateLevel = Config.Growth.Gates[gateIndex]
			local myLevel = player:GetAttribute("Level") or 1
			local text
			if state.GateJob then
				text = string.format("<font size='14'><b>Level %d Breakthrough in progress</b></font>\n<font color='#ffd966'>Time left %s</font>", state.GateJob.Level, Config.FormatDuration(growthRemaining(state.GateJob.EndAt)))
			else
				text = string.format("<font size='14'><b>Level %d Breakthrough</b></font>   (Current Lv.%d)\n<font color='#bbbbcc'>Time needed %s · 💰 %d G</font>\n<font size='11' color='#bbbbcc'>%s</font>",
					gateLevel, myLevel, Config.FormatDuration(Config.Growth.GateTime[gateIndex]), Config.Growth.GateGold[gateIndex],
					myLevel >= gateLevel and "You can break through now!" or string.format("Reach level %d to break through", gateLevel))
			end
			local gateLabel = rowText(gateRow, text, 14, 190)
			local okTree, tree = pcall(function() return require(ReplicatedStorage:FindFirstChild("TrainingTree")) end)
			if state.GateJob and gateLabel and okTree and tree and tree.Live then -- (남은 시간은 매초 글자만 바꾼다)
				local job = state.GateJob
				table.insert(tree.Live, { gateLabel, function()
					local r = growthRemaining(job.EndAt)
					return string.format("<font size='14'><b>Level %d Breakthrough in progress</b></font>\n<font color='#ffd966'>Time left %s</font>", job.Level, Config.FormatDuration(math.max(0, r))), r <= 0
				end })
			end

			if state.GateJob then
				makeButton({
					Size = UDim2.new(0, 160, 0, 34), Position = UDim2.new(1, -172, 0.5, -17),
					Text = "⏱ Use Time Skip", TextSize = 12, BackgroundColor3 = state.TimeSkip > 0 and Color3.fromRGB(200, 130, 40) or GRAY,
				}, gateRow, function()
					Remotes.Growth:FireServer("Skip", "Gate")
				end)
			else
				makeButton({
					Size = UDim2.new(0, 160, 0, 34), Position = UDim2.new(1, -172, 0.5, -17),
					Text = "Start Breakthrough", TextSize = 13, BackgroundColor3 = myLevel >= gateLevel and GREEN or GRAY,
				}, gateRow, function()
					Remotes.Growth:FireServer("Gate")
				end)
			end
		end
	end

	local function buildSkipGaugeRow() -- 성장 탭 맨 위: ⏱ 시간 건너뛰기 보유량 글자 + 그 아래 게이지 (훈련 칸 수는 훈련 나무 제목에 이미 있어서 뺐다)
		local owned = player:GetAttribute("TimeSkip") or 0
		local row = newRow(38, Color3.fromRGB(30, 28, 46))
		makeLabel({ Size = UDim2.new(1, -24, 0, 18), Position = UDim2.new(0, 12, 0, 2), RichText = true, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
			Text = string.format("⏱ Time Skip <font color='#ffe16e'><b>%s</b></font> owned", Config.FormatDuration(owned)) }, row)
		-- 오른쪽: 지금 가진 골드 (성장 칸에서 골드를 쓰는데 골드가 안 보였다). 골드가 바뀌면 바로 따라간다
		local goldLabel = makeLabel({ Size = UDim2.new(0, 220, 0, 18), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 2), RichText = true, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right,
			Text = "" }, row)
		local function showGold()
			local digits = tostring(math.floor(player:GetAttribute("Gold") or 0)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") -- 1,234,567
			goldLabel.Text = string.format("💰 <font color='#ffd966'><b>%s</b></font>", digits)
		end
		showGold()
		local goldConn = player:GetAttributeChangedSignal("Gold"):Connect(showGold)
		goldLabel.Destroying:Connect(function() goldConn:Disconnect() end)
		local cap = math.max(player:GetAttribute("TimeSkipCap") or 0, owned, 1)
		local gaugeBack = makePanel({ Size = UDim2.new(1, -24, 0, 10), Position = UDim2.new(0, 12, 0, 24), BackgroundColor3 = Color3.fromRGB(22, 24, 36) }, row)
		makePanel({ Size = UDim2.new(math.clamp(owned / cap, 0, 1), 0, 1, 0), BackgroundColor3 = Color3.fromRGB(215, 150, 60) }, gaugeBack)
	end

	local function skillStats(key, level) -- { { 이름, 값 글자, 숫자 } ... } (쿨타임은 서버 Skill.CooldownFor 와 같은 계산: 내 쿨감 스탯까지 반영한 실제 값)
		local U = Config.SkillUpgrade
		local cfg = Config.Skills[key]
		local lv = level - 1
		local list = {}
		local function add(name, value, fmt) table.insert(list, { name, string.format(fmt, value), value }) end
		if key == "Barrier" then
			add("Duration", cfg.Duration + U.BarrierDuration * lv, "%.1fs")
		elseif key == "Blast" then
			add("Damage", cfg.Mult * (1 + U.BlastMult * lv), "x%.2f")
			add("Radius", cfg.Radius + U.BlastRadius * lv, "%.1f")
		elseif key == "Focus" then
			add("NEAR MISS duration", Config.NearMiss.Duration + U.FocusDuration * lv, "%.1fs")
			add("Stacks kept", math.floor(Config.NearMiss.MaxStacks * 0.5 * lv / math.max(1, U.MaxLevel - 1)), "%d")
		elseif key == "Spirit" then
			add("Damage per dagger", cfg.Mult * (1 + U.BlastMult * lv), "x%.2f")
		elseif key == "Heal" then
			add("HP restored", math.floor((cfg.Ratio + U.HealRatio * lv) * 100 + 0.5), "%d%%")
		elseif cfg.PerLevel then -- 새 패시브 (피의 갈증 / 마무리 / 돌진 / 보물 감각)
			add(cfg.StatName, cfg.PerLevel * level * (cfg.Scale or 1), cfg.Fmt or "%.2f")
		else
			add("Damage", cfg.Mult * (1 + U.UltMult * lv), "x%.2f")
			add("Targets", cfg.MaxTargets + math.floor(U.UltTargets * lv + 0.001), "%d")
		end
		if not cfg.Passive then
			local S = Config.Skills
			local function part(value) return 1 / (1 + 1.5 * math.max(0, value or 0)) end
			local factor = part(player:GetAttribute("GearHaste")) * part(player:GetAttribute("PetHaste")) * part(player:GetAttribute("LvHaste")) * part(U.CooldownPerLevel * lv)
			local floorRatio = key == "Spirit" and (S.SpiritCooldownFloor or 0.05) or (S.CooldownFloor or 0.3)
			local cooldown = cfg.Cooldown * (floorRatio + (1 - floorRatio) * factor)
			if (key == "Spirit" or key == "Heal") and Config.GetSkillBranch(player, key, 10) == "B" then cooldown *= 0.7 end
			cooldown *= math.max(0.5, 1 + Config.SkillMod(player, key, "Cooldown"))
			add("Cooldown", cooldown, "%.1fs")
		end
		return list
	end

	local function skillDetail(key, level)
		local U = Config.SkillUpgrade
		local cfg = Config.Skills[key]
		local now = skillStats(key, level)
		local lines = {}
		if key == "Spirit" then -- 고정 정보 (레벨로 안 바뀐다)
			table.insert(lines, string.format("<font color='#9aa3b8'>%.1fs · %d daggers every %.2fs</font>", cfg.Duration, cfg.Daggers, cfg.Interval))
		end
		local maxed = level >= U.MaxLevel
		local nextStats = not maxed and skillStats(key, level + 1) or nil
		if nextStats then
			table.insert(lines, string.format("<font color='#ffd966'><b>Next level</b></font><font color='#ffd966'> Lv.%d ▶ Lv.%d</font>", level, level + 1))
		end
		for index, stat in ipairs(now) do
			local line = string.format("<font color='#cfd6e6'>%s</font><font color='#ffffff'>  %s</font>", stat[1], stat[2])
			local after = nextStats and nextStats[index]
			if after and after[2] ~= stat[2] then
				line ..= string.format("<font color='#9aa3b8'>  ▶  </font><font color='#78ff8c'><b>%s</b></font>", after[2])
			end
			table.insert(lines, line)
		end
		return table.concat(lines, "\n")
	end
	local function wrap(fn) return function(...) sync() return fn(...) end end
	return {
		Character = wrap(buildCharacterTab), Weapon = wrap(buildWeaponTab), Growth = wrap(buildGrowthTab),
		SkipGaugeRow = wrap(buildSkipGaugeRow), SkillStats = skillStats, SkillDetail = skillDetail,
	}
end

return MenuTabs
