-- MonsterLabelClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: MonsterLabelClient)
-- 몬스터 이름표 색 = 필드 2축 신호 (11-19, Shared/FieldSignal): 처치 시간(내 DPS 로 이 몹 체력을 깎는 데 몇 초)과 한 방 %(이 몹 탄 x 받는 피해 배율 / 내 최대 체력) 중 나쁜 쪽.
--   회색: 훨씬 강하다 / 흰색: 적당 / 주황: 버겁다 / 빨강: 위험. 기준: 일반 0.5 / 3 / 8초, 엘리트 1.5 / 9 / 25초 · 한 방 15% / 35%
--   깜빡임 방지: 처치 시간 단계는 넘어선 상태가 1.5초 이어질 때만 바꾸고, 한 방 % 는 경계 ±3%p 를 넘어야 바꾼다
-- 서버(FieldService)가 몬스터 부품에 MobZone / MobKind / MobHp / MobShot Attribute 를 붙여 둔다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Signal = require(ReplicatedStorage:WaitForChild("FieldSignal"))
local player = Players.LocalPlayer

local lastColor = setmetatable({}, { __mode = "k" })
local tierState = setmetatable({}, { __mode = "k" }) -- [part] = { Time, Pending, Since, Hit }

-- 폰(터치 화면): 몬스터 체력바가 화면에 비해 너무 두껍고 넓어서, 처음 한 번 줄인다 (서버가 만든 BillboardGui 의 크기만 바꾼다. 보스처럼 폭이 큰 것은 더 줄인다)
local UserInputService = game:GetService("UserInputService")
local COMPACT = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local slimmed = setmetatable({}, { __mode = "k" })
local function slimBar(part)
	if slimmed[part] then return end
	local gui = part:FindFirstChildOfClass("BillboardGui")
	if not gui then return end
	slimmed[part] = true
	local width = gui.Size.X.Offset
	local big = width >= 300
	gui.Size = UDim2.new(0, math.floor(width * (big and 0.5 or 0.62)), 0, big and 22 or 18)
	for _, child in ipairs(gui:GetChildren()) do
		if child:IsA("TextLabel") then
			child.Size = UDim2.new(1, 0, big and 0.66 or 0.72, 0)
		elseif child:IsA("Frame") then
			child.Size = UDim2.new(1, 0, big and 0.26 or 0.2, 0)
			child.Position = UDim2.new(0, 0, big and 0.74 or 0.8, 0)
		end
	end
end

-- 한 방 % 단계 (경계 ±3%p 를 넘어야 바뀐다)
local function hitTier(pct, current)
	local raw = Signal.HitTier(pct)
	if current == nil or raw == current then return raw end
	local edges = Signal.HitTiers
	if raw > current then
		return (pct >= edges[raw] + 3) and raw or current
	end
	return (pct < edges[current] - 3) and raw or current
end

local function colorFor(part, kind, now)
	local sec = Signal.KillSecFor(part:GetAttribute("MobHp"))
	local pct = Signal.HitPctFor(part:GetAttribute("MobShot"))
	local state = tierState[part]
	local rawTime = Signal.TimeTier(kind, sec)
	if not state then
		state = { Time = rawTime, Hit = Signal.HitTier(pct) }
		tierState[part] = state
	elseif rawTime ~= state.Time then -- (처치 시간 단계: 넘어선 상태가 1.5초 이어질 때만)
		if state.Pending ~= rawTime then
			state.Pending, state.Since = rawTime, now
		elseif now - state.Since >= 1.5 then
			state.Time, state.Pending = rawTime, nil
		end
	else
		state.Pending = nil
	end
	if pct then state.Hit = hitTier(pct, state.Hit) end
	return Signal.Colors[Signal.Severity(state.Time, state.Hit)]
end

while true do
	task.wait(0.5)
	local camera = workspace.CurrentCamera
	if camera then
		local now = os.clock()
		local origin = camera.CFrame.Position
		for _, part in ipairs(CollectionService:GetTagged("Monster")) do
			local zone, kind = part:GetAttribute("MobZone"), part:GetAttribute("MobKind")
			if COMPACT then slimBar(part) end
			if zone and (kind == "Normal" or kind == "Elite") and (part.Position - origin).Magnitude < 160 then
				local gui = part:FindFirstChildOfClass("BillboardGui")
				local label = gui and gui:FindFirstChildOfClass("TextLabel")
				if label and part:GetAttribute("MobHp") then
					local color = colorFor(part, kind, now)
					if lastColor[part] ~= color then
						lastColor[part] = color
						label.TextColor3 = color
					end
				end
			end
		end
	end
end
