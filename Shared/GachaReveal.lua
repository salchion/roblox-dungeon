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
	-- 결과 뒤에서 천천히 도는 빛줄기 (등급이 높을수록 진하고 굵다)
	local function lightRays(parent, color, rarity)
		local holder = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 61 }, parent)
		local bars = {}
		for i = 1, 8 do
			local bar = create("Frame", {
				Size = UDim2.new(0, 2400, 0, 40 + rarity * 14), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Rotation = i * 22.5,
				BackgroundColor3 = color, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 61,
			}, holder)
			create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(1, 1) }) }, bar)
			TweenService:Create(bar, TweenInfo.new(0.5), { BackgroundTransparency = 0.9 - rarity * 0.07 }):Play()
			bars[i] = bar
		end
		task.spawn(function()
			local angle = 0
			while holder.Parent do
				angle += 0.25
				for i, bar in ipairs(bars) do bar.Rotation = i * 22.5 + angle end
				task.wait()
			end
		end)
		return holder
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
		-- 결과 화면은 따로 맨 위 화면에 그린다 (HUD 의 알림 / "더 좋은 장비" 팝업이 결과 위를 덮던 문제)
		local layer = gui.Parent:FindFirstChild("GachaRevealGui")
		if not layer then
			layer = create("ScreenGui", { Name = "GachaRevealGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 50 }, gui.Parent)
		end
		local old = layer:FindFirstChild("GachaReveal")
		if old then old:Destroy() end

		local rarity = roll.Rarity
		local color = Config.Gear.RarityColors[rarity]
		local root = create("TextButton", {
			Name = "GachaReveal", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
			Text = "", AutoButtonColor = false, ZIndex = 60,
		}, layer)
		local skipped = false
		root.Activated:Connect(function() if os.clock() >= lockedUntil then skipped = true end end) -- (신화 강제 감상 시간에는 탭을 무시한다)
		local function fade(object, goal, time, style, direction)
			TweenService:Create(object, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal):Play()
		end
		local function pause(seconds)
			local untilTime = os.clock() + seconds
			while not skipped and root.Parent and os.clock() < untilTime do task.wait() end
		end
		fade(root, { BackgroundTransparency = multi and 0.12 or 0.3 }, 0.2)

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
			-- (10연은 여기서 등급을 미리 보여 주지 않는다: 카드를 뒤집을 때 공개)
			local popRarity = multi and 1 or rarity
			local popColor = multi and Color3.fromRGB(200, 190, 255) or color
			SoundBank.Play(sfxParent, "Gacha_Pop" .. popRarity)
			if popRarity == 5 then lockedUntil = os.clock() + 2.6 end -- 신화: 잠깐(2.6초) 멈춰서 꼭 보게 한다 (10연은 카드를 뒤집을 때)
			if popRarity >= 4 then SoundBank.Play(sfxParent, "Skill_Ult", { Volume = 0.5 }) end
			for i = 1, math.max(1, popRarity - 1) do
				task.delay((i - 1) * 0.18, function()
					if not root.Parent then return end
					local ring = create("Frame", {
						Size = UDim2.new(0, 40, 0, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundTransparency = 1, ZIndex = 61,
					}, root)
					create("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
					local stroke = create("UIStroke", { Color = popColor, Thickness = 8 }, ring)
					fade(ring, { Size = UDim2.new(0, 900, 0, 900) }, 0.9)
					fade(stroke, { Transparency = 1, Thickness = 1 }, 0.9)
				end)
			end
			local flash = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = popRarity == 5 and Color3.fromRGB(255, 232, 170) or popColor, BackgroundTransparency = popRarity == 5 and 0.5 or (popRarity >= 3 and 0.2 or 0.65), BorderSizePixel = 0, ZIndex = 70 }, root) -- (신화의 번쩍임은 눈이 아프지 않게 부드러운 금빛으로)
			if popRarity == 5 then -- 신화: 별이 흩어지고 MYTHIC 글자 + 웅장한 소리 (다른 등급에는 없다)
				SoundBank.Play(sfxParent, "Aug_Synergy", { Volume = 0.6 })
				mythicBurst(root, UDim2.new(0.5, 0, 0.5, 0), 40, 360)
				mythicBanner(root, UDim2.new(0.5, 0, 0.5, -190))
			end
			fade(flash, { BackgroundTransparency = 1 }, 0.5)

			if multi then
				-- 10연: 카드가 뒷면으로 깔린다 -> 한 장씩 뒤집힌다. 높은 등급(전설 / 신화)은 뒷면이 그 색으로 빛나며 떨리다가 마지막에 따로 뒤집힌다 (두근거림)
				-- 화면을 누르면 남은 카드를 한꺼번에 뒤집는다
				local rolls = result.Rolls
				local CW, CH, GAP = 132, 176, 14
				local cols = math.min(5, #rolls)
				local rowsN = math.ceil(#rolls / 5)
				local gridW, gridH = cols * CW + (cols - 1) * GAP, rowsN * CH + (rowsN - 1) * GAP
				local best = 1
				for _, r in ipairs(rolls) do best = math.max(best, r.Rarity) end
				lightRays(root, Config.Gear.RarityColors[best], best)
				local grid = create("Frame", { Size = UDim2.new(0, gridW, 0, gridH + 150), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundTransparency = 1, ZIndex = 62 }, root)
				local fit = create("UIScale", {}, grid) -- (작은 화면: 카드 판 전체를 화면에 맞게 줄인다)
				local function refit()
					local size = root.AbsoluteSize
					fit.Scale = math.min(1, (size.X - 24) / gridW, (size.Y - 24) / (gridH + 150))
				end
				refit()
				root:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
				local title = makeLabel({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 0), Text = string.format("🎰 %d-Roll Results", #rolls), TextSize = 16, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 230, 150), TextStrokeTransparency = 0.3, ZIndex = 63 }, grid)
				fade(title, { TextSize = 28 }, 0.35, Enum.EasingStyle.Back)
				local center = UDim2.new(0, gridW / 2, 0, 48 + gridH / 2)
				local cards = {}
				for index, r in ipairs(rolls) do
					local col, row = (index - 1) % 5, (index - 1) // 5
					local rc = Config.Gear.RarityColors[r.Rarity]
					local pos = UDim2.new(0, col * (CW + GAP) + CW / 2, 0, 48 + row * (CH + GAP) + CH / 2)
					local holder = create("Frame", {
						Size = UDim2.new(0, CW * 0.4, 0, CH * 0.4), AnchorPoint = Vector2.new(0.5, 0.5), Position = center, Rotation = math.random(-25, 25),
						BackgroundColor3 = Color3.fromRGB(46, 34, 84), BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 63,
					}, grid)
					rounded(holder, 12)
					local stroke = create("UIStroke", { Color = Color3.fromRGB(140, 120, 200), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, holder)
					create("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 110, 170)), Rotation = 90 }, holder)
					local backMark = makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = "?", TextSize = 54, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(190, 170, 255), TextTransparency = 0.25, ZIndex = 64 }, holder)
					cards[index] = { Roll = r, Holder = holder, Stroke = stroke, Back = backMark, Color = rc, Pos = pos, Open = false }
					task.delay((index - 1) * 0.05, function()
						if not holder.Parent then return end
						SoundBank.Play(sfxParent, "Gacha_Tick", { Pitch = 1.3 + index * 0.03, Volume = 0.45 })
						fade(holder, { Position = pos, Size = UDim2.new(0, CW, 0, CH), Rotation = 0 }, 0.32, Enum.EasingStyle.Back)
					end)
				end
				local dealDone = os.clock() + #rolls * 0.05 + 0.4 -- (카드가 깔리는 움직임이 끝나는 시각: 건너뛰어도 마지막 정렬은 이 뒤에)
				pause(#rolls * 0.05 + 0.4)

				local counts = {}
				local STATUS = { Equipped = "Equipped!", Bag = "Bag" }
				local function showFace(card)
					local r, rc, holder = card.Roll, card.Color, card.Holder
					card.Back:Destroy()
					holder.BackgroundColor3 = Color3.fromRGB(22, 20, 34):Lerp(rc, 0.22)
					card.Stroke.Color = rc
					card.Stroke.Thickness = ({ 2, 3, 4, 5, 6 })[r.Rarity]
					if r.Rarity == 5 then
						local g = create("UIGradient", { Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 80)),
							ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 220, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
						}) }, card.Stroke)
						task.spawn(function()
							local rot = 0
							while holder.Parent do rot += 8 g.Rotation = rot task.wait() end
						end)
					end
					-- 위쪽에 등급색 빛 (아래로 갈수록 흐려진다)
					local glow = create("Frame", { Size = UDim2.new(1, 0, 0.6, 0), BackgroundColor3 = rc, BorderSizePixel = 0, ZIndex = 64 }, holder)
					-- 금테 안쪽 선 + 왼쪽 위 등급 글자 (카드 게임 느낌)
					local inner = create("Frame", { Size = UDim2.new(1, -10, 1, -10), Position = UDim2.new(0, 5, 0, 5), BackgroundTransparency = 1, ZIndex = 66 }, holder)
					rounded(inner, 9)
					create("UIStroke", { Color = Color3.fromRGB(230, 190, 110), Thickness = 1.5, Transparency = 0.25 }, inner)
					makeLabel({ Size = UDim2.new(0, 40, 0, 26), Position = UDim2.new(0, 8, 0, 6), Text = ({ "C", "R", "E", "L", "M" })[r.Rarity], TextSize = 24, Font = Enum.Font.Fantasy, TextColor3 = rc:Lerp(Color3.fromRGB(255, 230, 160), 0.35), TextStrokeTransparency = 0.3, TextXAlignment = Enum.TextXAlignment.Left, AutoLocalize = false, ZIndex = 67 }, holder)
					create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, r.Rarity >= 3 and 0.45 or 0.75), NumberSequenceKeypoint.new(1, 1) }) }, glow)
					makeLabel({ Size = UDim2.new(1, 0, 0, 60), Position = UDim2.new(0, 0, 0, 12), Text = ICONS[r.Slot] or "🎁", TextSize = 40, ZIndex = 65 }, holder)
					makeLabel({ Size = UDim2.new(1, -8, 0, 34), Position = UDim2.new(0, 4, 0, 72), Text = r.Name or "", TextSize = 12, Font = Enum.Font.GothamBold, TextColor3 = Color3.new(1, 1, 1), ZIndex = 65 }, holder)
					makeLabel({ Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, 108), Text = string.rep("★", r.Rarity), TextSize = 14, Font = Enum.Font.GothamBlack, TextColor3 = rc, TextStrokeTransparency = 0.5, ZIndex = 65 }, holder)
					makeLabel({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, 128), Text = Config.Gear.RarityNames[r.Rarity], TextSize = 11, Font = Enum.Font.GothamBlack, TextColor3 = rc, ZIndex = 65 }, holder)
					makeLabel({ Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -24), Text = r.Better and string.format("▲ +%d%%", r.Better) or (STATUS[r.Status] or "Scrap"), TextSize = r.Better and 14 or 10, Font = r.Better and Enum.Font.GothamBlack or nil, TextColor3 = r.Better and Color3.fromRGB(120, 255, 150) or Color3.fromRGB(170, 170, 190), ZIndex = 65 }, holder) -- 지금 장비보다 좋으면 초록 "▲ +N%"
					if r.Rarity >= 3 then -- 빛줄기가 카드를 한 번 쓸고 지나간다
						local shine = create("Frame", { Size = UDim2.new(0, 34, 1.6, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, -30, 0.5, 0), Rotation = 20, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 66 }, holder)
						fade(shine, { Position = UDim2.new(1, 30, 0.5, 0) }, 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
						game:GetService("Debris"):AddItem(shine, 0.5)
					end
				end
				local function flip(card, quiet)
					if card.Open then return end
					card.Open = true
					local r, holder = card.Roll, card.Holder
					counts[r.Rarity] = (counts[r.Rarity] or 0) + 1
					fade(holder, { Size = UDim2.new(0, 0, 0, CH) }, 0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
					task.delay(0.09, function()
						if not holder.Parent then return end
						showFace(card)
						fade(holder, { Size = UDim2.new(0, CW, 0, CH) }, 0.16, Enum.EasingStyle.Back)
					end)
					if not quiet then
						SoundBank.Play(sfxParent, r.Rarity >= 3 and ("Gacha_Pop" .. (r.Rarity - 1)) or "Gacha_Tick", r.Rarity >= 3 and { Volume = 0.55 } or { Pitch = 1.1, Volume = 0.7 })
					end
					if r.Rarity >= 3 then
						local ringM = create("Frame", { Size = UDim2.new(0, 40, 0, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = card.Pos, BackgroundTransparency = 1, ZIndex = 62 }, grid)
						create("UICorner", { CornerRadius = UDim.new(1, 0) }, ringM)
						local rs = create("UIStroke", { Color = card.Color, Thickness = 6 }, ringM)
						fade(ringM, { Size = UDim2.new(0, 280, 0, 280) }, 0.6)
						fade(rs, { Transparency = 1, Thickness = 1 }, 0.6)
						game:GetService("Debris"):AddItem(ringM, 0.7)
					end
					if r.Rarity == 5 then -- 신화 카드: 별이 흩어지고 위에 MYTHIC 글자
						mythicBurst(grid, card.Pos, 20, 150)
						mythicBanner(grid, card.Pos + UDim2.new(0, 0, 0, -100))
					end
				end

				-- 1) 평범한 카드(일반 ~ 에픽)부터 차례로 뒤집는다
				local big = {}
				for _, card in ipairs(cards) do
					if card.Roll.Rarity >= 4 then
						table.insert(big, card)
						card.Stroke.Color = card.Color -- 뒷면이 등급색으로 빛난다: "뭔가 있다"
						card.Back.TextColor3 = card.Color
					elseif root.Parent then
						flip(card, skipped)
						if not skipped then pause(0.11) end
					end
				end
				-- 2) 전설 / 신화: 떨리다가 크게 뒤집힌다
				for _, card in ipairs(big) do
					if not root.Parent then return end
					if not skipped then
						local started, nextTick = os.clock(), 0
						while not skipped and root.Parent and os.clock() - started < 0.7 do
							local t = (os.clock() - started) / 0.7
							if os.clock() >= nextTick then
								nextTick = os.clock() + 0.14 - 0.08 * t
								SoundBank.Play(sfxParent, "Gacha_Tick", { Pitch = 0.9 + t * 0.9 })
							end
							card.Holder.Rotation = math.sin(os.clock() * 50) * (3 + t * 7)
							card.Stroke.Thickness = 3 + t * 6
							task.wait()
						end
						card.Holder.Rotation = 0
						local flash = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = card.Color, BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 70 }, root)
						fade(flash, { BackgroundTransparency = 1 }, 0.4)
						game:GetService("Debris"):AddItem(flash, 0.5)
						if card.Roll.Rarity >= 4 then SoundBank.Play(sfxParent, "Skill_Ult", { Volume = 0.45 }) end
					end
					flip(card, false)
					if card.Roll.Rarity == 5 then lockedUntil = math.max(lockedUntil, os.clock() + 2.2) end
					pause(0.45)
				end
				for _, card in ipairs(cards) do flip(card, true) end -- (건너뛰기로 남은 카드)
				pause(0.3)
				if not root.Parent then return end

				while root.Parent and os.clock() < dealDone do task.wait() end
				task.wait(0.3) -- (마지막으로 뒤집힌 카드의 크기 움직임이 끝날 때까지)
				if not root.Parent then return end
				-- 3) 마지막 배치: 가장 좋은 장비를 가운데 크게, 나머지는 양옆에 작게 (좋은 것일수록 가운데 가까이)
				local order = table.clone(cards)
				table.sort(order, function(a, b) return a.Roll.Rarity > b.Roll.Rarity end)
				local cx, cy = gridW / 2, 48 + gridH / 2 + 10
				local slots = {}
				for _, dy in ipairs({ -136, 0, 136 }) do
					for _, dx in ipairs({ -164, 164, -268, 268 }) do table.insert(slots, { cx + dx, cy + dy }) end
				end
				table.sort(slots, function(a, b) -- (가운데에 가까운 칸부터)
					local da, db = math.abs(a[1] - cx) + math.abs(a[2] - cy) * 0.6, math.abs(b[1] - cx) + math.abs(b[2] - cy) * 0.6
					return da < db
				end)
				for i, card in ipairs(order) do
					local holder = card.Holder
					if holder.Parent then
						local sc = create("UIScale", { Scale = 1 }, holder)
						if i == 1 then
							fade(holder, { Position = UDim2.new(0, cx, 0, cy) }, 0.45, Enum.EasingStyle.Back)
							fade(sc, { Scale = 1.45 }, 0.45, Enum.EasingStyle.Back)
							local halo = create("Frame", { Size = UDim2.new(0, 60, 0, 60), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, cx, 0, cy), BackgroundColor3 = card.Color, BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 62 }, grid)
							create("UICorner", { CornerRadius = UDim.new(1, 0) }, halo)
							fade(halo, { Size = UDim2.new(0, 330, 0, 330), BackgroundTransparency = 0.82 }, 0.6)
						elseif slots[i - 1] then
							fade(holder, { Position = UDim2.new(0, slots[i - 1][1], 0, slots[i - 1][2]) }, 0.4, Enum.EasingStyle.Quad)
							fade(sc, { Scale = 0.72 }, 0.4, Enum.EasingStyle.Quad)
						end
					end
				end
				SoundBank.Play(sfxParent, "Gacha_Pop" .. math.min(5, best), { Volume = 0.5 })

				local parts = {}
				for rarity = 5, 1, -1 do
					if counts[rarity] then
						table.insert(parts, string.format("<font color='#%s'>%s %d</font>", Config.Gear.RarityColors[rarity]:ToHex(), Config.Gear.RarityNames[rarity], counts[rarity]))
					end
				end
				makeLabel({ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 1, -80), RichText = true, Text = table.concat(parts, "   "), TextSize = 16, Font = Enum.Font.GothamBold, TextStrokeTransparency = 0.4, ZIndex = 63 }, grid)
				-- 아래 버튼: 확인 / 다시 뽑기 (티켓)
				local function bottomButton(text, x, color, onClick)
					local b = create("TextButton", {
						Size = UDim2.new(0, 200, 0, 46), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, x, 1, -4), Text = text, TextSize = 15,
						Font = Enum.Font.GothamBlack, TextColor3 = Color3.new(1, 1, 1), BackgroundColor3 = color, AutoButtonColor = true, ZIndex = 69,
					}, grid)
					rounded(b, 10)
					create("UIStroke", { Color = Color3.fromRGB(230, 190, 110), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
					create("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 190)), Rotation = 90 }, b)
					b.Activated:Connect(onClick)
					return b
				end
				local function close()
					if not root.Parent then return end
					fade(root, { BackgroundTransparency = 1 }, 0.2)
					game:GetService("Debris"):AddItem(root, 0.25)
				end
				bottomButton("OK", -110, Color3.fromRGB(50, 80, 150), close)
				local me = game:GetService("Players").LocalPlayer
				local tickets = me:GetAttribute("Tickets") or 0
				local again = math.min(10, tickets)
				local againButton = bottomButton(again > 0 and string.format("🎰 Roll again  🎫%d", again) or "🎫 No tickets", 110, again > 0 and Color3.fromRGB(60, 140, 80) or Color3.fromRGB(70, 70, 86), function()
					local n = math.min(10, me:GetAttribute("Tickets") or 0)
					if n <= 0 then return end
					Remotes.Gear:FireServer("Roll", n)
				end)
				againButton.AutoButtonColor = again > 0
				skipped = false
				pause(30)
				close()
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
			if rarity >= 2 then lightRays(root, color, rarity) end
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
