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
function Theme.glossy(button)
	add("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.76, 0.76, 0.86)), Rotation = 90 }, button)
	add("UIStroke", { Color = Theme.INK, Thickness = 2, Transparency = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
	button.TextStrokeColor3 = Theme.INK
	button.TextStrokeTransparency = 0.45
end

return Theme
