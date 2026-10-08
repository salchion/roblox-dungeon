-- ClientKit (ReplicatedStorage 안의 ModuleScript, 이름: ClientKit)
-- 클라이언트 스크립트들이 같이 쓰는 UI 도구 (PlayerClient 가 너무 커져서 나눈 스크립트들이 사용한다).
local Kit = {}

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
	local base = { BackgroundColor3 = Color3.fromRGB(20, 20, 30), BackgroundTransparency = 0.2, BorderSizePixel = 0 }
	for key, value in pairs(props) do
		base[key] = value
	end
	local frame = Kit.create("Frame", base, parent)
	Kit.rounded(frame)
	return frame
end

function Kit.makeLabel(props, parent)
	local base = { BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamMedium, TextSize = 16, TextWrapped = true }
	for key, value in pairs(props) do
		base[key] = value
	end
	return Kit.create("TextLabel", base, parent)
end

function Kit.makeButton(props, parent, onClick)
	local base = {
		BackgroundColor3 = Color3.fromRGB(70, 110, 220), TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold,
		TextSize = 15, AutoButtonColor = true, BorderSizePixel = 0,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	local button = Kit.create("TextButton", base, parent)
	Kit.rounded(button, 6)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

return Kit
