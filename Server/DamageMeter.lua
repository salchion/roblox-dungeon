-- DamageMeter (ServerScriptService > Modules 안의 ModuleScript, 이름: DamageMeter)
-- 대미지 미터기: 내가 준 피해를 "어디서 나왔는지"(총 / 세트 효과별)로 나눠서 센다. 필드 / 던전 / 허수아비 어디서나.
--   * 전투가 15초 넘게 끊기면 새로 센다 (한 번의 사냥 / 한 판 단위)
--   * 1초마다 바뀐 사람에게만 Attribute "DmgMeter" (JSON 한 줄)로 보낸다 -> DpsPanelClient 가 화면에 그린다. 서버 부담은 작다.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local Meter = {}

local RESET_AFTER = 15 -- 초: 이만큼 피해가 없으면 다음 피해부터 새로 센다
local WINDOW = 10      -- 초: 최근 DPS 를 재는 구간

local states = setmetatable({}, { __mode = "k" }) -- [player] = { Start, Last, Totals = { [source] = n }, Recent = { {t, n} }, Dirty }

function Meter.Add(player, source, amount)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not amount or amount <= 0 then return end
	local now = os.clock()
	local state = states[player]
	if not state or now - state.Last > RESET_AFTER then
		state = { Start = now, Last = now, Totals = {}, Recent = {}, Dirty = true }
		states[player] = state
	end
	state.Last = now
	state.Totals[source] = (state.Totals[source] or 0) + amount
	local recent = state.Recent
	if #recent < 400 then table.insert(recent, { now, amount }) end
	state.Dirty = true
end

local function publish(player, state, now)
	local recent = state.Recent
	local windowTotal, kept = 0, {}
	for _, entry in ipairs(recent) do
		if now - entry[1] <= WINDOW then
			windowTotal += entry[2]
			table.insert(kept, entry)
		end
	end
	state.Recent = kept
	local span = math.clamp(now - math.max(state.Start, now - WINDOW), 1, WINDOW)
	local list, total = {}, 0
	for source, value in pairs(state.Totals) do
		table.insert(list, { source, math.floor(value) })
		total += value
	end
	table.sort(list, function(a, b) return a[2] > b[2] end)
	while #list > 8 do table.remove(list) end
	player:SetAttribute("DmgMeter", HttpService:JSONEncode({ Dps = math.floor(windowTotal / span), Total = math.floor(total), Time = math.floor(now - state.Start), Src = list }))
end

task.spawn(function()
	while true do
		task.wait(1)
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local state = states[player]
			if state and state.Dirty then
				state.Dirty = false
				pcall(publish, player, state, now)
			end
		end
	end
end)

return Meter
