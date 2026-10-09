-- ClientKit (ReplicatedStorage 안의 ModuleScript, 이름: ClientKit)
-- 클라이언트 스크립트들이 같이 쓰는 UI 도구 (PlayerClient 가 너무 커져서 나눈 스크립트들이 사용한다).
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
	local base = { BackgroundColor3 = Color3.fromRGB(16, 18, 30), BackgroundTransparency = 0.1, BorderSizePixel = 0 }
	for key, value in pairs(props) do
		base[key] = value
	end
	local frame = Kit.create("Frame", base, parent)
	Kit.rounded(frame, (not props.BackgroundColor3 or (props.Size and props.Size.Y.Offset >= 100)) and 12 or 8)
	if not props.BackgroundColor3 then
		Kit.create("UIStroke", { Color = Color3.fromRGB(110, 130, 220), Thickness = 1.5, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
	end
	return frame
end

function Kit.makeLabel(props, parent)
	local base = { BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(240, 242, 250), Font = Enum.Font.GothamMedium, TextSize = 16, TextWrapped = true }
	for key, value in pairs(props) do
		base[key] = value
	end
	if base.TextSize < MIN_TEXT then base.TextSize = MIN_TEXT end
	return Kit.create("TextLabel", base, parent)
end

function Kit.makeButton(props, parent, onClick)
	local base = {
		BackgroundColor3 = Color3.fromRGB(62, 96, 196), TextColor3 = Color3.fromRGB(240, 242, 250), Font = Enum.Font.GothamBold,
		TextSize = 15, AutoButtonColor = true, BorderSizePixel = 0,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	local button = Kit.create("TextButton", base, parent)
	Kit.rounded(button, 8)
	if base.TextSize < MIN_TEXT then button.TextSize = MIN_TEXT end
	Kit.hover(button)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

return Kit
