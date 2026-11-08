-- UiTheme (ReplicatedStorage 안의 ModuleScript, 이름: UiTheme)
-- 화면 전체의 "말랑한 사탕 느낌" 공통 색 / 모양: 짙은 남색 + 가는 파란 테두리(딱딱한 느낌) 대신,
-- 보라 계열 그라데이션 + 굵은 검은 외곽선 + 윗면이 밝은 광택 + 둥근 모서리 (참고 게임 같은 모바일 게임 분위기).
-- ClientKit(makePanel / makeButton)과 PlayerClient 가 쓰고, 각 화면 스크립트도 색 이름만 가져다 쓴다.
local Theme = {}

Theme.INK = Color3.fromRGB(16, 12, 34)        -- 굵은 외곽선 색 (거의 검정)
Theme.PANEL = Color3.fromRGB(98, 72, 172)     -- 창 / 카드 바탕 (보라)
Theme.SLOT = Color3.fromRGB(78, 60, 138)      -- 칸(스킬 / 무기 슬롯)
Theme.SLOT_OFF = Color3.fromRGB(46, 36, 82)   -- 잠긴 칸
Theme.SLOT_ON = Color3.fromRGB(48, 128, 92)   -- 켜진 칸(자동 공격 등)

local function add(className, props, parent)
	local instance = Instance.new(className)
	for key, value in pairs(props) do instance[key] = value end
	instance.Parent = parent
	return instance
end

-- 창 / 카드: 위가 밝고 아래가 어두운 보라 + 굵은 외곽선
function Theme.panelLook(frame)
	add("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.6, 0.55, 0.72)), Rotation = 90 }, frame)
	add("UIStroke", { Color = Theme.INK, Thickness = 3, Transparency = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
end

-- 버튼: 윗면이 밝은 광택 + 굵은 외곽선 + 글씨 외곽선 (색은 부르는 쪽이 정한 그대로)
-- 게임 UI 자료 조사에서 가져온 것 (시뮬레이터 / 모바일 RPG 공통):
--   * 두툼한 3D 버튼: 위는 밝고 아래 가장자리로 갈수록 확 어두워진다 (눌러야 할 것처럼 보인다)
--   * 윗면 안쪽의 가는 흰 광택 줄
--   * 굵은 게임 글꼴 (번역된 한글 / 일본어도 같은 굵기로)
Theme.BUTTON_SHADE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(0.55, Color3.new(0.9, 0.9, 0.95)),
	ColorSequenceKeypoint.new(0.86, Color3.new(0.74, 0.74, 0.84)), ColorSequenceKeypoint.new(1, Color3.new(0.56, 0.56, 0.68)),
})
local BOLD = { [Enum.Font.GothamBold] = Enum.FontWeight.Bold, [Enum.Font.GothamBlack] = Enum.FontWeight.ExtraBold, [Enum.Font.GothamMedium] = Enum.FontWeight.SemiBold }
function Theme.gameFont(label)
	local weight = BOLD[label.Font]
	if weight then label.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", weight) end
end
function Theme.shine(button)
	if button:FindFirstChild("TopShine") or button:FindFirstChildOfClass("UIListLayout") or button:FindFirstChildOfClass("UIGridLayout") then return end
	local line = add("Frame", { Name = "TopShine", Size = UDim2.new(1, -16, 0, 2), Position = UDim2.new(0, 8, 0, 3), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.6, BorderSizePixel = 0, Active = false, ZIndex = button.ZIndex }, button)
	add("UICorner", { CornerRadius = UDim.new(1, 0) }, line)
end
function Theme.glossy(button)
	add("UIGradient", { Color = Theme.BUTTON_SHADE, Rotation = 90 }, button)
	add("UIStroke", { Color = Theme.INK, Thickness = 2, Transparency = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
	button.TextStrokeColor3 = Theme.INK
	button.TextStrokeTransparency = 0.45
	Theme.gameFont(button)
	task.defer(function() -- (크기가 정해진 뒤: 낮은 버튼에는 광택 줄을 넣지 않는다)
		if button.Parent and button.BackgroundTransparency < 0.5 and button.AbsoluteSize.Y >= 26 then Theme.shine(button) end
	end)
end

return Theme
