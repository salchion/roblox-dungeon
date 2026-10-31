-- GachaReveal (ReplicatedStorage 안의 ModuleScript, 이름: GachaReveal)
-- 장비 뽑기 결과 카드 연출 (흔들림 -> 등급 공개 -> 신화 별가루). PlayerClient 가 Studio 한도(200KB)에 닿아서 그대로 떼어 냈다.
-- PlayerClient 가 Init 에 화면(gui)과 도우미 함수들을 넘겨 준다. 내용은 예전 PlayerClient 안의 블록과 같다.

local M = {}

function M.Init(deps)
	local Config, Remotes, SoundBank, TweenService = deps.Config, deps.Remotes, deps.SoundBank, deps.TweenService
	local create, gui, makeLabel, rounded, sfxParent = deps.create, deps.gui, deps.makeLabel, deps.rounded, deps.sfxParent
	local ICONS = { Armor = "🛡", Gloves = "🧤", Boots = "👢", Helmet = "⛑", Ring = "💍", Necklace = "📿" }
	local SHAKE = { 0.35, 0.5, 0.85, 1.25, 1.7 }  -- 등급별 흔들리는 시간
	local HOLD = { 1.0, 1.1, 1.6, 2.2, 3.0 }       -- 카드 유지 시간
	local MYTHIC_STARS = { Color3.fromRGB(255, 140, 140), Color3.fromRGB(255, 225, 120), Color3.fromRGB(130, 230, 160), Color3.fromRGB(130, 210, 255), Color3.fromRGB(205, 145, 255) }
	-- 최고 등급(신화)만 보는 연출: 별이 사방으로 흩어지는 ✦ 와 "MYTHIC" 글자 (눈이 아프지 않게 부드러운 색 / 천천히 사라진다)
	local function mythicBurst(parent, position, count, spread)
		for _ = 1, count do
			local angle = math.random() * math.pi * 2
			local dist = spread * (0.5 + math.random() * 0.7)
			local star = create("TextLabel", {
				Size = UDim2.new(0, 24, 0, 24), AnchorPoint = Vector2.new(0.5, 0.5), Position = position, BackgroundTransparency = 1,
				Text = "✦", TextSize = 14 + math.random(0, 14), TextColor3 = MYTHIC_STARS[math.random(#MYTHIC_STARS)], Font = Enum.Font.GothamBlack, ZIndex = 71,
			}, parent)
			TweenService:Create(star, TweenInfo.new(0.9 + math.random() * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = position + UDim2.new(0, math.cos(angle) * dist, 0, math.sin(angle) * dist), TextTransparency = 1, Rotation = math.random(-90, 90),
			}):Play()
			game:GetService("Debris"):AddItem(star, 1.8)
		end
	end
	local function mythicBanner(parent, position)
		local label = makeLabel({
			Size = UDim2.new(0, 360, 0, 50), AnchorPoint = Vector2.new(0.5, 0.5), Position = position, Text = "✦ MYTHIC ✦", TextSize = 20,
			Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 226, 140), TextStrokeTransparency = 0.4, ZIndex = 72,
		}, parent)
		TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = 40 }):Play()
		task.delay(1.8, function()
			if label.Parent then TweenService:Create(label, TweenInfo.new(0.7), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play() end
		end)
		game:GetService("Debris"):AddItem(label, 2.6)
	end
	local lockedUntil, pending = 0, nil -- 신화(최고 등급)가 뜬 직후에는 잠깐 강제로 보게 한다: 이 시간까지는 탭으로 건너뛸 수 없고, 연타로 들어온 다음 결과는 끝난 뒤에 보여 준다
	local reveal
	Remotes.Gear.OnClientEvent:Connect(function(action, result)
		if action == "Result" and result.Roll and os.clock() < lockedUntil then
			local mine = {}
			pending = mine -- 여러 개가 밀려도 마지막 것만 (어차피 앞의 것은 바로 덮어써진다)
			task.delay(lockedUntil - os.clock() + 0.05, function()
				if pending == mine then
					pending = nil
					reveal(action, result)
				end
			end)
			return
		end
		reveal(action, result)
	end)
	reveal = function(action, result)
		local roll = action == "Result" and result.Roll
		if not roll then return end
		local multi = result.Rolls ~= nil and #result.Rolls > 1
		local old = gui:FindFirstChild("GachaReveal")
		if old then old:Destroy() end

		local rarity = roll.Rarity
		local color = Config.Gear.RarityColors[rarity]
		local root = create("TextButton", {
			Name = "GachaReveal", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
			Text = "", AutoButtonColor = false, ZIndex = 60,
		}, gui)
		local skipped = false
		root.Activated:Connect(function() if os.clock() >= lockedUntil then skipped = true end end) -- (신화 강제 감상 시간에는 탭을 무시한다)
		local function fade(object, goal, time, style, direction)
			TweenService:Create(object, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal):Play()
		end
		local function pause(seconds)
			local untilTime = os.clock() + seconds
			while not skipped and root.Parent and os.clock() < untilTime do task.wait() end
		end
		fade(root, { BackgroundTransparency = 0.35 }, 0.2)

		task.spawn(function()
			local capsule = create("Frame", {
				Size = UDim2.new(0, 96, 0, 96), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, -80),
				BackgroundColor3 = Color3.fromRGB(235, 235, 245), BorderSizePixel = 0, ZIndex = 62,
			}, root)
			create("UICorner", { CornerRadius = UDim.new(1, 0) }, capsule)
			local capStroke = create("UIStroke", { Color = Color3.fromRGB(160, 160, 190), Thickness = 4 }, capsule)
			local band = create("Frame", { Size = UDim2.new(1, 0, 0, 8), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = Color3.fromRGB(90, 90, 120), BorderSizePixel = 0, ZIndex = 63 }, capsule)
			create("Frame", { Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(0.2, 0, 0.18, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 63 }, capsule)
			fade(capsule, { Position = UDim2.new(0.5, 0, 0.5, 0) }, 0.5, Enum.EasingStyle.Bounce)
			task.delay(0.4, function() SoundBank.Play(sfxParent, "Gacha_Drop") end)
			pause(0.55)

			local shakeTime = SHAKE[rarity]
			local started = os.clock()
			local hintColor = rarity >= 3 and color or Color3.fromRGB(190, 190, 210)
			local nextTick = 0
			while not skipped and root.Parent and os.clock() - started < shakeTime do
				local t = (os.clock() - started) / shakeTime
				if os.clock() >= nextTick then -- 점점 빨라지는 틱틱 소리
					nextTick = os.clock() + 0.2 - 0.12 * t
					SoundBank.Play(sfxParent, "Gacha_Tick", { Pitch = 0.8 + t * 0.8 })
				end
				capsule.Rotation = math.sin((os.clock() - started) * 40) * (6 + t * 14)
				capStroke.Color = Color3.fromRGB(160, 160, 190):Lerp(hintColor, t)
				capStroke.Thickness = 4 + t * (rarity >= 3 and 10 or 3)
				capsule.Position = UDim2.new(0.5, math.sin(os.clock() * 55) * t * 6, 0.5, 0)
				task.wait()
			end
			if not root.Parent then return end

			capsule:Destroy()
			SoundBank.Play(sfxParent, "Gacha_Pop" .. rarity)
			if rarity == 5 then lockedUntil = os.clock() + (multi and 3.4 or 2.6) end -- 신화: 잠깐(10연 3.4초 / 단일 2.6초) 멈춰서 꼭 보게 한다
			if rarity >= 4 then SoundBank.Play(sfxParent, "Skill_Ult", { Volume = 0.5 }) end
			for i = 1, math.max(1, rarity - 1) do
				task.delay((i - 1) * 0.18, function()
					if not root.Parent then return end
					local ring = create("Frame", {
						Size = UDim2.new(0, 40, 0, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundTransparency = 1, ZIndex = 61,
					}, root)
					create("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
					local stroke = create("UIStroke", { Color = color, Thickness = 8 }, ring)
					fade(ring, { Size = UDim2.new(0, 900, 0, 900) }, 0.9)
					fade(stroke, { Transparency = 1, Thickness = 1 }, 0.9)
				end)
			end
			local flash = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = rarity == 5 and Color3.fromRGB(255, 232, 170) or color, BackgroundTransparency = rarity == 5 and 0.5 or (rarity >= 3 and 0.2 or 0.65), BorderSizePixel = 0, ZIndex = 70 }, root) -- (신화의 번쩍임은 눈이 아프지 않게 부드러운 금빛으로)
			if rarity == 5 then -- 신화: 별이 흩어지고 MYTHIC 글자 + 웅장한 소리 (다른 등급에는 없다)
				SoundBank.Play(sfxParent, "Aug_Synergy", { Volume = 0.6 })
				mythicBurst(root, UDim2.new(0.5, 0, 0.5, 0), 40, 360)
				mythicBanner(root, UDim2.new(0.5, 0, 0.5, -190))
			end
			fade(flash, { BackgroundTransparency = 1 }, 0.5)

			if multi then
				local grid = create("Frame", { Size = UDim2.new(0, 660, 0, 380), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundTransparency = 1, ZIndex = 62 }, root)
				makeLabel({ Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 0, 0), Text = string.format("🎰 %d-Roll Results", #result.Rolls), TextSize = 22, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 230, 150), ZIndex = 63 }, grid)
				local counts = {}
				local chimeAt = 0
				local STATUS = { Equipped = "Equipped!", Bag = "Bag" }
				for index, r in ipairs(result.Rolls) do
					counts[r.Rarity] = (counts[r.Rarity] or 0) + 1
					task.delay((index - 1) * 0.1, function()
						if not root.Parent then return end
						-- 카드마다 같은 소리가 10번 나던 것을 줄였다: 높은 등급 카드만 맑은 소리 (등급마다 다른 음, 0.3초에 하나만), 평범한 카드는 가끔 작은 "틱"
						if r.Rarity >= 3 then
							if os.clock() - (chimeAt or 0) > 0.3 then
								chimeAt = os.clock()
								SoundBank.Play(sfxParent, "Gacha_Pop" .. (r.Rarity - 1), { Volume = 0.55 })
							end
						elseif index % 3 == 1 then
							SoundBank.Play(sfxParent, "Gacha_Tick", { Pitch = 1.1, Volume = 0.7 })
						end
						local col, row = (index - 1) % 5, (index - 1) // 5
						local rc = Config.Gear.RarityColors[r.Rarity]
						local cx, cy = 66 + col * 132, 122 + row * 158
						local cardM = create("Frame", {
							Size = UDim2.new(0, 10, 0, 10), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, cx, 0, cy),
							BackgroundColor3 = Color3.fromRGB(24, 22, 36), BorderSizePixel = 0, ZIndex = 63,
						}, grid)
						rounded(cardM, 12)
						local st = create("UIStroke", { Color = rc, Thickness = ({ 2, 2, 3, 4, 5 })[r.Rarity] }, cardM)
						if r.Rarity == 5 then
							local g = create("UIGradient", { Color = ColorSequence.new({
								ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 80)),
								ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 220, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
							}) }, st)
							task.spawn(function()
								local rot = 0
								while cardM.Parent do rot += 8 g.Rotation = rot task.wait() end
							end)
						end
						fade(cardM, { Size = UDim2.new(0, 120, 0, 146) }, 0.3, Enum.EasingStyle.Back)
						makeLabel({ Size = UDim2.new(1, 0, 0, 56), Position = UDim2.new(0, 0, 0, 10), Text = ICONS[r.Slot] or "🎁", TextSize = 36, ZIndex = 64 }, cardM)
						makeLabel({ Size = UDim2.new(1, -8, 0, 34), Position = UDim2.new(0, 4, 0, 64), Text = r.Name or "", TextSize = 11, Font = Enum.Font.GothamBold, TextColor3 = rc, ZIndex = 64 }, cardM)
						makeLabel({ Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, 100), Text = string.format("★ %s", Config.Gear.RarityNames[r.Rarity]), TextSize = 11, Font = Enum.Font.GothamBlack, TextColor3 = rc, ZIndex = 64 }, cardM)
						makeLabel({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -20), Text = r.Better and string.format("▲ +%d%%", r.Better) or (STATUS[r.Status] or "Scrap"), TextSize = r.Better and 12 or 10, Font = r.Better and Enum.Font.GothamBlack or nil, TextColor3 = r.Better and Color3.fromRGB(120, 255, 150) or Color3.fromRGB(190, 190, 210), ZIndex = 64 }, cardM) -- 지금 장비보다 좋으면 초록 "▲ +N%"
						if r.Rarity == 5 then -- 신화 카드: 별이 흩어지고 위에 MYTHIC 글자
							mythicBurst(grid, UDim2.new(0, cx, 0, cy), 20, 150)
							mythicBanner(grid, UDim2.new(0, cx, 0, cy - 96))
						end
						if r.Rarity >= 3 then
							local ringM = create("Frame", { Size = UDim2.new(0, 40, 0, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, cx, 0, cy), BackgroundTransparency = 1, ZIndex = 61 }, grid)
							create("UICorner", { CornerRadius = UDim.new(1, 0) }, ringM)
							local rs = create("UIStroke", { Color = rc, Thickness = 6 }, ringM)
							fade(ringM, { Size = UDim2.new(0, 260, 0, 260) }, 0.6)
							fade(rs, { Transparency = 1, Thickness = 1 }, 0.6)
						end
					end)
				end
				pause(#result.Rolls * 0.1 + 0.4)
				local parts = {}
				for rarity = 5, 1, -1 do
					if counts[rarity] then
						table.insert(parts, string.format("<font color='#%s'>%s %d</font>", Config.Gear.RarityColors[rarity]:ToHex(), Config.Gear.RarityNames[rarity], counts[rarity]))
					end
				end
				makeLabel({ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 1, -26), RichText = true, Text = table.concat(parts, "   ") .. "   <font color='#aaaabb' size='11'>(tap to close)</font>", TextSize = 15, Font = Enum.Font.GothamBold, ZIndex = 63 }, grid)
				skipped = false
				pause(6)
				if not root.Parent then return end
				fade(root, { BackgroundTransparency = 1 }, 0.25)
				game:GetService("Debris"):AddItem(root, 0.3)
				return
			end

			local card = create("Frame", {
				Size = UDim2.new(0, 60, 0, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
				BackgroundColor3 = Color3.fromRGB(24, 22, 36), BorderSizePixel = 0, ZIndex = 62,
			}, root)
			rounded(card, 16)
			local stroke = create("UIStroke", { Color = color, Thickness = 5 }, card)
			if rarity == 5 then
				local gradient = create("UIGradient", {
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 80)),
						ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 220, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
					}),
				}, stroke)
				task.spawn(function()
					local rotation = 0
					while root.Parent do
						rotation += 6
						gradient.Rotation = rotation
						task.wait()
					end
				end)
			end
			fade(card, { Size = UDim2.new(0, 340, 0, 220) }, 0.45, Enum.EasingStyle.Back)
			pause(0.3)
			if not root.Parent then return end
			makeLabel({ Size = UDim2.new(1, 0, 0, 70), Position = UDim2.new(0, 0, 0, 14), Text = ICONS[roll.Slot] or "🎁", TextSize = 48, ZIndex = 63 }, card)
			makeLabel({
				Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 92), Text = string.format("★ %s ★", Config.Gear.RarityNames[rarity]),
				TextSize = rarity >= 4 and 30 or 26, Font = Enum.Font.GothamBlack, TextColor3 = color, ZIndex = 63,
			}, card)
			makeLabel({
				Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 134), Text = roll.Name or "", TextSize = 17,
				Font = Enum.Font.GothamBold, ZIndex = 63,
			}, card)
			makeLabel({
				Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -28), Text = roll.Equipped and "Equipped!" or "Added to bag",
				TextSize = 11, TextColor3 = Color3.fromRGB(190, 190, 210), ZIndex = 63,
			}, card)
			if roll.Better then -- 지금 장비보다 좋으면 크게 "▲ +N%" (뽑기의 손맛)
				makeLabel({
					Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -54), Text = string.format("▲ +%d%%", roll.Better),
					TextSize = 20, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(120, 255, 150), ZIndex = 63,
				}, card)
			end

			skipped = false
			pause(HOLD[rarity])
			if not root.Parent then return end
			fade(root, { BackgroundTransparency = 1 }, 0.25)
			fade(card, { Size = UDim2.new(0, 60, 0, 40) }, 0.25)
			game:GetService("Debris"):AddItem(root, 0.3)
		end)
	end
end

return M
