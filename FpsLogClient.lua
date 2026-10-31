-- FpsLogClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: FpsLogClient)
-- 프레임 드랍을 출력 창(스튜디오) / F9 개발자 콘솔(게임)에 남긴다.
--   * 한 프레임이 0.2초 넘게 멈추면 바로: [FPS] ⚠ 끊김 0.31초 · 장소 · 방금 열린 창
--   * 15초마다 요약 (느렸을 때만): 평균 FPS / 가장 느린 1초 FPS / 끊김 수 / 최악 프레임 / 메모리
--   * 문제가 없으면 1분에 한 번만 짧게 "정상" 을 남긴다
-- 화면에는 아무것도 띄우지 않는다 (게임에 영향 없음).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HITCH = 0.2         -- 이보다 긴 프레임은 바로 알림
local SLOW_FRAME = 1 / 20 -- 이보다 긴 프레임은 "끊김" 으로 센다 (50ms)
local SUMMARY_EVERY = 15
local QUIET_EVERY = 60
local WARMUP = 10         -- 접속 직후 로딩 중 끊김은 무시

-- 최근에 열린 창 (ScreenGui 켜짐 / 창 Frame 보임) 을 시각과 함께 기억
local recentOpen = {}
local function noteOpen(name)
	recentOpen[name] = os.clock()
end
local function watchGuiObject(obj, label)
	if obj:IsA("GuiObject") then
		obj:GetPropertyChangedSignal("Visible"):Connect(function()
			if obj.Visible then noteOpen(label .. "/" .. obj.Name) end
		end)
	end
end
local function watchScreenGui(gui)
	if not gui:IsA("ScreenGui") then return end
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled then noteOpen(gui.Name) end
	end)
	for _, child in ipairs(gui:GetChildren()) do watchGuiObject(child, gui.Name) end
	gui.ChildAdded:Connect(function(child)
		noteOpen(gui.Name .. "/" .. child.Name)
		watchGuiObject(child, gui.Name)
	end)
end
for _, gui in ipairs(playerGui:GetChildren()) do watchScreenGui(gui) end
playerGui.ChildAdded:Connect(function(gui)
	noteOpen(gui.Name)
	watchScreenGui(gui)
end)

local function context()
	local now = os.clock()
	local opened = {}
	for name, at in pairs(recentOpen) do
		if now - at < 3 then
			table.insert(opened, name)
		elseif now - at > 30 then
			recentOpen[name] = nil
		end
	end
	local text = "장소 " .. tostring(player:GetAttribute("Zone") or "?")
	if player:GetAttribute("InDoomArena") then text ..= "(둠)" end
	if #opened > 0 then
		table.sort(opened)
		text ..= " · 방금 열린 창: " .. table.concat(opened, ", ", 1, math.min(#opened, 4))
	end
	return text
end

local function memoryMb()
	local ok, mb = pcall(function() return Stats:GetTotalMemoryUsageMb() end)
	return ok and math.floor(mb) or -1
end

local started = os.clock()
local frames, total, slow, worst = 0, 0, 0, 0
local secFrames, secTime, worstSecFps = 0, 0, math.huge
local lastSummary, lastQuiet, lastHitchLog = os.clock(), os.clock(), 0

print("[FPS] 프레임 기록 시작 (끊김 0.2초 이상은 바로, 느릴 때 15초마다 요약)")

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	if now - started < WARMUP then return end

	frames += 1
	total += dt
	if dt > SLOW_FRAME then slow += 1 end
	if dt > worst then worst = dt end

	secFrames += 1
	secTime += dt
	if secTime >= 1 then
		worstSecFps = math.min(worstSecFps, secFrames / secTime)
		secFrames, secTime = 0, 0
	end

	if dt >= HITCH and now - lastHitchLog > 1 then
		lastHitchLog = now
		warn(string.format("[FPS] ⚠ 끊김 %.2f초 · %s", dt, context()))
	end

	if now - lastSummary >= SUMMARY_EVERY and total > 0 then
		local avg = frames / total
		local minFps = worstSecFps == math.huge and avg or worstSecFps
		if avg < 50 or minFps < 40 or slow >= 3 then
			print(string.format("[FPS] %d초 요약: 평균 %.0f · 가장 느린 1초 %.0f · 끊김(50ms+) %d번 · 최악 %dms · 메모리 %dMB · %s",
				SUMMARY_EVERY, avg, minFps, slow, math.floor(worst * 1000), memoryMb(), context()))
			lastQuiet = now
		elseif now - lastQuiet >= QUIET_EVERY then
			print(string.format("[FPS] 정상: 평균 %.0f · 메모리 %dMB · 장소 %s", avg, memoryMb(), tostring(player:GetAttribute("Zone") or "?")))
			lastQuiet = now
		end
		lastSummary = now
		frames, total, slow, worst = 0, 0, 0, 0
		worstSecFps = math.huge
	end
end)
