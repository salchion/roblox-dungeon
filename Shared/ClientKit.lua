-- ClientKit (ReplicatedStorage 안의 ModuleScript, 이름: ClientKit)
-- 클라이언트 스크립트들이 같이 쓰는 UI 도구 (PlayerClient 가 너무 커져서 나눈 스크립트들이 사용한다).
local Theme = require(script.Parent:WaitForChild("UiTheme"))
local Kit = {}
local MIN_TEXT = 12 -- 이보다 작은 글씨는 모바일에서 안 읽힌다

-- 마우스를 올리면 테두리가 살짝 밝아진다 (버튼 공통)
function Kit.hover(button)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(230, 236, 255)
	stroke.Thickness = 1.5
	stroke.Transparency = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	button.MouseEnter:Connect(function() stroke.Transparency = 0.55 end)
	button.MouseLeave:Connect(function() stroke.Transparency = 1 end)
end

function Kit.create(className, props, parent)
	local instance = Instance.new(className)
	for key, value in pairs(props) do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

function Kit.rounded(instance, radius)
	Kit.create("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, instance)
end

function Kit.makePanel(props, parent)
	local base = { BackgroundColor3 = Theme.PANEL, BackgroundTransparency = 0.06, BorderSizePixel = 0 }
	for key, value in pairs(props) do
		base[key] = value
	end
	local frame = Kit.create("Frame", base, parent)
	Kit.rounded(frame, (not props.BackgroundColor3 or (props.Size and props.Size.Y.Offset >= 100)) and 12 or 8)
	if not props.BackgroundColor3 then
		Theme.panelLook(frame) -- (모든 큰 창 공통: 보라 그라데이션 + 굵은 외곽선)
	end
	return frame
end

function Kit.makeLabel(props, parent)
	local base = { BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(240, 242, 250), Font = Enum.Font.GothamMedium, TextSize = 14, TextWrapped = true }
	for key, value in pairs(props) do
		base[key] = value
	end
	if base.TextSize < MIN_TEXT then base.TextSize = MIN_TEXT end
	return Kit.create("TextLabel", base, parent)
end

function Kit.makeButton(props, parent, onClick)
	local base = {
		BackgroundColor3 = Color3.fromRGB(62, 96, 196), TextColor3 = Color3.fromRGB(240, 242, 250), Font = Enum.Font.GothamBold,
		TextSize = 13, AutoButtonColor = true, BorderSizePixel = 0,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	local button = Kit.create("TextButton", base, parent)
	Kit.rounded(button, 10)
	Theme.glossy(button)
	if base.TextSize < MIN_TEXT then button.TextSize = MIN_TEXT end
	Kit.hover(button)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

-- 메달형 아이콘: 이모지를 그냥 올리지 않고 "테두리 고리 + 안쪽 구슬 + 윗면 광택 + (높은 등급은) 바깥 빛"으로 감싼다.
--   o = { Size(숫자, 지름), Position, AnchorPoint, Color(등급 / 강조 색), Icon(글자), TextSize, Tier(0~5), ZIndex, Muted }
--   반환: 메달 틀(Frame), 아이콘 글자(TextLabel)
function Kit.medal(parent, o)
	local d, z, color = o.Size or 48, o.ZIndex or 1, o.Color or Color3.fromRGB(150, 160, 200)
	local tier, muted = o.Tier or 0, o.Muted == true
	local dark, white = Color3.fromRGB(14, 16, 28), Color3.new(1, 1, 1)
	local root = Kit.create("Frame", { Size = UDim2.new(0, d, 0, d), Position = o.Position or UDim2.new(), AnchorPoint = o.AnchorPoint or Vector2.new(), BackgroundTransparency = 1, BorderSizePixel = 0, Active = false, ZIndex = z }, parent)
	if tier >= 3 then -- 바깥에 번지는 은은한 빛 (등급이 높을수록 진하다)
		local glow = Kit.create("Frame", { Size = UDim2.new(1.4, 0, 1.4, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundColor3 = color, BackgroundTransparency = tier >= 5 and 0.72 or (tier == 4 and 0.8 or 0.87), BorderSizePixel = 0, Active = false, ZIndex = z }, root)
		Kit.create("UICorner", { CornerRadius = UDim.new(1, 0) }, glow)
	end
	-- 아래로 살짝 떨어진 그림자 (스티커처럼 떠 보이게)
	local shadow = Kit.create("Frame", { Size = UDim2.new(1, 0, 1, 0), Position = UDim2.new(0, 0, 0, math.max(2, math.floor(d * 0.06))), BackgroundColor3 = Color3.fromRGB(10, 8, 24), BackgroundTransparency = muted and 0.8 or 0.5, BorderSizePixel = 0, Active = false, ZIndex = z }, root)
	Kit.create("UICorner", { CornerRadius = UDim.new(1, 0) }, shadow)
	local ring = Kit.create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = white, BackgroundTransparency = muted and 0.45 or 0, BorderSizePixel = 0, Active = false, ZIndex = z }, root)
	Kit.create("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
	Kit.create("UIGradient", { Rotation = 90, Color = ColorSequence.new(color:Lerp(white, 0.5), color:Lerp(dark, 0.45)) }, ring)
	-- 굵은 남색 바깥 테두리 (게임 아이콘처럼 또렷하게) + 등급이 높을수록 두껍다
	Kit.create("UIStroke", { Color = Color3.fromRGB(22, 18, 44), Thickness = 2.4 + tier * 0.3, Transparency = muted and 0.5 or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ring)
	local inner = Kit.create("Frame", { Size = UDim2.new(0.78, 0, 0.78, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundColor3 = white, BackgroundTransparency = muted and 0.3 or 0, BorderSizePixel = 0, Active = false, ZIndex = z + 1 }, root)
	Kit.create("UICorner", { CornerRadius = UDim.new(1, 0) }, inner)
	Kit.create("UIGradient", { Rotation = 90, Color = ColorSequence.new(color:Lerp(dark, 0.55), color:Lerp(dark, 0.84)) }, inner)
	Kit.create("UIStroke", { Color = color:Lerp(dark, 0.55), Thickness = 1.6, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, inner)
	local gloss = Kit.create("Frame", { Size = UDim2.new(0.62, 0, 0.3, 0), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.1, 0), BackgroundColor3 = white, BorderSizePixel = 0, Active = false, ZIndex = z + 2 }, inner)
	Kit.create("UICorner", { CornerRadius = UDim.new(1, 0) }, gloss)
	Kit.create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.72), NumberSequenceKeypoint.new(1, 1) }) }, gloss)
	local icon = Kit.makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = o.Icon or "", TextSize = o.TextSize or math.floor(d * 0.46), TextWrapped = false, TextTransparency = muted and 0.4 or 0, ZIndex = z + 3, Active = false }, inner)
	return root, icon
end

-- 리본 이름표: 짙은 색 띠 + 굵은 남색 테두리 + 둥근 게임 글꼴 (아이콘 아래 이름에 쓴다)
--   o = { Size, Position, AnchorPoint, Color, Text, TextSize, ZIndex }  반환: 띠(Frame), 글자(TextLabel)
function Kit.ribbon(parent, o)
	local z = o.ZIndex or 2
	local band = Kit.create("Frame", { Size = o.Size, Position = o.Position or UDim2.new(), AnchorPoint = o.AnchorPoint or Vector2.new(), BackgroundColor3 = (o.Color or Color3.fromRGB(90, 110, 200)):Lerp(Color3.fromRGB(20, 18, 40), 0.25), BorderSizePixel = 0, Active = false, ZIndex = z }, parent)
	Kit.create("UICorner", { CornerRadius = UDim.new(0, 6) }, band)
	Kit.create("UIStroke", { Color = Color3.fromRGB(20, 18, 40), Thickness = 2.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, band)
	Kit.create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 170, 185)) }, band)
	local text = Kit.makeLabel({ Size = UDim2.new(1, -6, 1, 0), Position = UDim2.new(0, 3, 0, 0), Text = o.Text or "", TextSize = o.TextSize or 12, Font = Enum.Font.FredokaOne, TextWrapped = true,
		TextColor3 = Color3.new(1, 1, 1), TextStrokeColor3 = Color3.fromRGB(20, 18, 40), TextStrokeTransparency = 0.15, ZIndex = z + 1 }, band)
	return band, text
end

return Kit
