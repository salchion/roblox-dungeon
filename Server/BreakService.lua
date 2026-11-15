-- BreakService (ServerScriptService > Modules): 보스 그로기(브레이크) — 필드 군주 / 던전 보스 공통
--   보스 / 군주를 때리면 게이지가 찬다: 일반 사격(자동 사격 포함) / 스킬 / 질풍 대시 충격파 / 약점 구슬 명중
--   Need 점이 차면 Seconds 동안 그로기: 움직임 / 패턴 정지(StaggerUntil + BrokenUntil) + 받는 피해 x DamageMult (약점 노출 x3 과 곱해진다)
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

-- 머리 위 게이지: Cells 칸(◆◇◇◇) 비율 표시. 점수는 소수로도 쌓이므로(사격 적립) 칸은 내림으로 칠한다.
-- 다만 첫 한 발에도 "찼다"는 게 보이도록 0 이 아니면 최소 1칸은 칠한다.
local function paint(part, data)
	local B = Config.Break
	local gui = board(part, data)
	local cells = math.max(1, B.Cells or 4)
	local pts = math.max(0, data.BreakPts or 0)
	local filled = math.min(cells, math.floor(pts / math.max(0.01, B.Need) * cells))
	if pts > 0 and filled < 1 then filled = 1 end
	gui.Text.Text = string.rep("◆", filled) .. string.rep("◇", cells - filled)
	gui.Text.TextColor3 = Color3.fromRGB(255, 225, 120) -- (그로기가 끝난 직후 다시 찰 때 주황색이 남지 않게 매번 되돌린다)
end

local function bossLike(data)
	return data ~= nil and (data.IsBoss == true or data.Kind == "Boss" or data.BossLike == true)
end

-- 한 번 맞았을 때 얻는 점수 (kind = "Gun" | "Skill" | "Weak")
--   Gun  : 맞힌 간격 x 초당 RatePerSec 점을 모아 넘긴다 (한 번에 최대 GunBankMax 점). 연사 / 단발 무기가 같은 속도로 찬다
--   Skill: 스킬 / 질풍 대시 충격파 / 약점 구슬 = SkillBonus 점. 같은 보스에 SkillCooldown 초에 한 번만 (연꽃처럼 여러 번 때리는 스킬이 혼자 다 채우지 않게)
local function gainFor(data, kind, now)
	local B = Config.Break
	if kind == "Skill" or kind == "Weak" then
		if now < (data.BreakSkillAt or 0) then return 0 end
		data.BreakSkillAt = now + (B.SkillCooldown or 1)
		return B.SkillBonus or 2
	end
	local rate = math.max(0.01, B.RatePerSec or 2)
	local bankMax = math.max(1, B.GunBankMax or 5)
	local last = data.BreakGunAt
	data.BreakGunAt = now
	if not last then return 1 end -- 첫 탄은 1점 (오래 쉬었다가 쏜 첫 탄이 몰아서 차지 않게)
	return math.min(bankMax, rate * math.min(now - last, bankMax / rate))
end

-- 그로기 발동: Seconds 동안 정지 + 받는 피해 배율 (Break.Mult 가 읽는다)
local function fire(part, data, now)
	local B = Config.Break
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
end

-- 보스 / 군주를 맞혔을 때 (필드 / 던전의 모든 피해 경로가 부른다). kind 를 안 주면 일반 사격("Gun")
function Break.Hit(part, data, kind)
	local B = Config.Break
	if not (B and B.Enabled) or not part or not part.Parent or not bossLike(data) then return end
	local now = os.clock()
	if data.BrokenUntil and now < data.BrokenUntil then return end -- 이미 그로기 중: 게이지를 새로 채우지 않는다
	local last = data.BreakAt or now
	data.BreakAt = now
	data.BreakPts = math.max(0, (data.BreakPts or 0) - B.Decay * (now - last)) -- (안 맞힌 동안 줄어든 만큼)
	local gain = gainFor(data, kind or "Gun", now)
	if gain <= 0 then return end
	data.BreakPts += gain
	if data.BreakPts >= B.Need then
		data.BreakPts = 0
		data.BreakGunAt, data.BreakSkillAt = nil, nil -- (남은 적립으로 그로기가 연달아 터지지 않게)
		fire(part, data, now)
	else
		paint(part, data)
		local stamp = now
		local fadeIn = math.min(6, (data.BreakPts / math.max(0.01, B.Decay)) + 0.5) -- (게이지가 0 이 될 때쯤, 길어도 6초 뒤에 표시를 지운다)
		task.delay(fadeIn, function()
			if data.BreakAt == stamp and not (data.BrokenUntil and os.clock() < data.BrokenUntil) then clearBoard(data) end
		end)
	end
end

-- 하위 호환: 약점 구슬 명중 (예전 호출 그대로). 점수는 스킬과 같은 몫으로 준다
function Break.WeakHit(part, data)
	Break.Hit(part, data, "Weak")
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
