-- FieldSignalClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: FieldSignalClient)
-- 필드 2축 신호를 내 화면에서만 보여 준다 (11-19): 서버가 만든 글자는 그대로 두고, 이 클라이언트에서만 덮어쓴다 (다른 사람 화면에는 그 사람 값이 따로 뜬다)
--   * 구역 간판(ZoneSignGui) 둘째 줄: "⏱ Kill ~%ds · 💥 Hit %d%% HP" (그 구역 일반 몹 평균)
--   * 군주 이름표: "👑 Lord of %s (Zone %d) · ⏱ ~%ds · 💥 %d%% HP"
--   값은 Shared/FieldSignal (내 DPS 평균 / 최대 체력 / 받는 피해 배율). 2초마다, 숫자가 바뀐 글자만 다시 쓴다 (번역기가 바꾼 글자를 계속 되돌리지 않게)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Signal = require(ReplicatedStorage:WaitForChild("FieldSignal"))
local player = Players.LocalPlayer
local F = Config.Field

local written = setmetatable({}, { __mode = "k" }) -- [TextLabel] = 마지막으로 이 스크립트가 쓴 영어 글자
local function put(label, text)
	if not label or not text or written[label] == text then return end
	written[label] = text
	label.Text = text
end

local signs = {} -- 구역 간판 둘째 줄 TextLabel 들 (간판 Gui 는 서버가 만들고 지우지 않는다)
local function addSign(gui)
	if not gui:IsA("BillboardGui") or gui.Name ~= "ZoneSignGui" then return end
	task.defer(function()
		for _, child in ipairs(gui:GetChildren()) do
			if child:IsA("TextLabel") and child.Position.Y.Offset == 46 then -- (FieldService 간판: 0 / 46 / 72 세 줄 중 둘째 줄)
				table.insert(signs, { Gui = gui, Label = child })
			end
		end
	end)
end
for _, d in ipairs(workspace:GetDescendants()) do if d.Name == "ZoneSignGui" then addSign(d) end end
workspace.DescendantAdded:Connect(function(d) if d.Name == "ZoneSignGui" then addSign(d) end end)

while true do
	task.wait(2)
	for i = #signs, 1, -1 do
		local entry = signs[i]
		if not entry.Label.Parent then
			table.remove(signs, i)
		else
			local holder = entry.Gui.Parent
			local zone = holder and holder:IsA("BasePart") and F.ZoneOfX(holder.Position.X)
			local sec, pct = nil, nil
			if zone and zone >= 1 then sec, pct = Signal.Pair(zone, "Mob", player) end
			if sec then put(entry.Label, string.format("⏱ Kill ~%ds · 💥 Hit %d%% HP", sec, pct)) end
		end
	end
	for _, part in ipairs(CollectionService:GetTagged("Monster")) do
		if part:GetAttribute("MobKind") == "Boss" then
			local zone = part:GetAttribute("MobZone")
			local gui = part:FindFirstChildOfClass("BillboardGui")
			local label = gui and gui:FindFirstChildOfClass("TextLabel")
			local sec, pct = nil, nil
			if zone and label then sec, pct = Signal.Pair(zone, "Lord", player) end
			if sec then put(label, string.format("👑 Lord of %s (Zone %d) · ⏱ ~%ds · 💥 %d%% HP", F.ZoneNames[zone] or "", zone, sec, pct)) end
		end
	end
end
