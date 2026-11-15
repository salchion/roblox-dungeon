-- BreakService (ServerScriptService > Modules): 보스 그로기(브레이크) — 필드 군주 / 던전 보스 공통
--   약점 명중이 게이지를 채운다 (초당 최대 RatePerSec 점, 안 맞히면 Decay 점/초로 줄어든다). Need 점이 차면 Seconds 동안 그로기:
--   움직임 / 패턴 정지(StaggerUntil + BrokenUntil) + 받는 피해 x DamageMult (약점 노출 x3 과 곱해진다)
--   머리 위 작은 게이지 / "💥 BROKEN" 글자는 서버 빌보드 하나: 그로기가 끝나거나 게이지가 0 이 되면 반드시 지운다
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Break = {}

local function board(part, data)
	if data.BreakBoard and data.BreakBoard.Parent then return data.BreakBoard end
	local gui = Instance.new("BillboardGui")
	gui.Name = "BreakGauge"
	gui.Size = UDim2.new(0, 120, 0, 26)
	gui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 18
	label.TextColor3 = Color3.fromRGB(255, 225, 120)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Parent = part
	data.BreakBoard = gui
	return gui
end

local function clearBoard(data)
	if data.BreakBoard then data.BreakBoard:Destroy() data.BreakBoard = nil end
end

local function paint(part, data)
	local B = Config.Break
	local gui = board(part, data)
	local filled = math.clamp(math.floor(data.BreakPts or 0), 0, B.Need)
	gui.Text.Text = string.rep("◆", filled) .. string.rep("◇", B.Need - filled)
end

-- 약점 명중 1번 (보스 / 군주만)
function Break.WeakHit(part, data)
	local B = Config.Break
	if not (B and B.Enabled) or not part or not part.Parent then return end
	if not (data.IsBoss or data.Kind == "Boss" or data.BossLike) then return end
	local now = os.clock()
	if data.BrokenUntil and now < data.BrokenUntil then return end
	local last = data.BreakAt or now
	data.BreakPts = math.max(0, (data.BreakPts or 0) - B.Decay * (now - last)) -- (안 맞힌 동안 줄어든 만큼)
	data.BreakAt = now
	-- 초당 상한: 직전 1초 안에 얻은 점수를 센다
	if now - (data.BreakWindowAt or 0) >= 1 then data.BreakWindowAt, data.BreakWindowGain = now, 0 end
	if (data.BreakWindowGain or 0) >= B.RatePerSec then return end
	data.BreakWindowGain = (data.BreakWindowGain or 0) + 1
	data.BreakPts += 1
	if data.BreakPts >= B.Need then
		data.BreakPts = 0
		data.BrokenUntil = now + B.Seconds
		data.StaggerUntil = math.max(data.StaggerUntil or 0, data.BrokenUntil)
		part:SetAttribute("StaggerUntil", data.BrokenUntil)
		-- 필드 군주는 MonsterTypes.Update 를 안 탄다: 사격 / 고리 / 패턴 / 바쁨 시각을 그로기만큼 민다
		for _, key in ipairs({ "NextShot", "NextRing", "NextPattern", "BusyUntil" }) do
			if data[key] then data[key] = math.max(data[key], data.BrokenUntil) end
		end
		local gui = board(part, data)
		gui.Text.Text = "💥 BROKEN"
		gui.Text.TextColor3 = Color3.fromRGB(255, 140, 90)
		local until_ = data.BrokenUntil
		task.delay(B.Seconds, function()
			if data.BrokenUntil == until_ then clearBoard(data) end
		end)
	else
		paint(part, data)
		local stamp = now
		task.delay(B.Need / math.max(0.01, B.Decay) + 0.5, function() -- (오래 안 맞히면 게이지 표시를 지운다)
			if data.BreakAt == stamp and not (data.BrokenUntil and os.clock() < data.BrokenUntil) then clearBoard(data) end
		end)
	end
end

-- 받는 피해 배율 (그로기 중이면 DamageMult)
function Break.Mult(data)
	local B = Config.Break
	return (B and B.Enabled and data.BrokenUntil and os.clock() < data.BrokenUntil) and B.DamageMult or 1
end

function Break.IsBroken(data)
	return data.BrokenUntil ~= nil and os.clock() < data.BrokenUntil
end

-- 몬스터가 사라질 때 (빌보드는 부품과 같이 없어지지만 표를 깨끗이)
function Break.Clear(data) clearBoard(data) end

return Break
