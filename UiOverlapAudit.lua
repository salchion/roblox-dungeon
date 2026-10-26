-- UiOverlapAudit (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: UiOverlapAudit)
-- Studio 에서만 도는 점검 도구: 화면에 동시에 보이는 "창 / 카드 / 버튼" 중 서로 겹치는 것을 찾아 Output 에 한 줄씩 찍는다.
-- 게시된 게임에서는 아무것도 하지 않는다. 사용: Studio 에서 play -> 여러 화면(마을 / 필드 / 던전 / 메뉴 열기)을 돌아다니면
--   [UI 겹침] ... 줄이 찍힌다. 그 줄들을 복사해서 보내 주면 겹치는 것을 한 번에 정리할 수 있다.
-- (같은 창 안의 글자 / 버튼처럼 한쪽이 다른 쪽 안에 들어 있는 것은 겹침으로 세지 않는다. 같은 겹침은 한 번만 찍는다.)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then return end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SKIP_GUIS = { TouchGui = true, EvolveFx = true, HUDFx = true, IntroGui = true, ProximityPrompts = true }
local MIN_W, MIN_H, MIN_OVERLAP = 48, 22, 700
local printed = {}
local printedCount = 0

local function visibleChain(obj, gui)
	local node = obj
	while node and node ~= gui do
		if node:IsA("GuiObject") and not node.Visible then return false end
		node = node.Parent
	end
	return true
end

local function qualifies(obj, viewport)
	if not obj:IsA("GuiObject") then return false end
	if not (obj:IsA("Frame") or obj:IsA("TextButton") or obj:IsA("ImageLabel") or obj:IsA("ImageButton") or obj:IsA("ScrollingFrame")) then return false end
	if obj.BackgroundTransparency >= 0.6 and not obj:IsA("ImageLabel") then return false end
	local size = obj.AbsoluteSize
	if size.X < MIN_W or size.Y < MIN_H then return false end
	if size.X > viewport.X * 0.75 and size.Y > viewport.Y * 0.75 then return false end -- (화면을 덮는 막 / 배경은 제외)
	if size.X >= viewport.X * 0.9 then return false end -- (화면 폭 전체를 덮는 검은 띠 = 연출용 레터박스는 제외)
	return true
end

local function describe(item)
	local r = item.Rect
	return string.format("%s/%s (%d,%d %dx%d)", item.Gui.Name, item.Obj.Name, r.X, r.Y, r.W, r.H)
end

local function scan()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local viewport = camera.ViewportSize
	local items = {}
	for _, gui in ipairs(playerGui:GetChildren()) do
		if gui:IsA("ScreenGui") and gui.Enabled and not SKIP_GUIS[gui.Name] then
			local qualified = {}
			for _, obj in ipairs(gui:GetDescendants()) do
				if qualifies(obj, viewport) and visibleChain(obj, gui) then qualified[obj] = true end
			end
			for obj in pairs(qualified) do
				-- 바깥쪽 창만 센다: 조상 중에 또 다른 "창"이 있으면 그 안의 부품이다
				local nested, node = false, obj.Parent
				while node and node ~= gui do
					if qualified[node] then nested = true break end
					node = node.Parent
				end
				if not nested then
					local pos, size = obj.AbsolutePosition, obj.AbsoluteSize
					table.insert(items, { Gui = gui, Obj = obj, Rect = { X = math.floor(pos.X), Y = math.floor(pos.Y), W = math.floor(size.X), H = math.floor(size.Y) } })
				end
			end
		end
	end
	for i = 1, #items do
		for j = i + 1, #items do
			local a, b = items[i], items[j]
			if a.Gui ~= b.Gui or not (a.Obj:IsDescendantOf(b.Obj) or b.Obj:IsDescendantOf(a.Obj)) then
				local ar, br = a.Rect, b.Rect
				local w = math.min(ar.X + ar.W, br.X + br.W) - math.max(ar.X, br.X)
				local h = math.min(ar.Y + ar.H, br.Y + br.H) - math.max(ar.Y, br.Y)
				if w > 0 and h > 0 and w * h >= MIN_OVERLAP and a.Gui ~= b.Gui then -- (서로 다른 화면(ScreenGui)끼리만: 한 화면 안은 일부러 쌓은 것이 많다)
					local key = a.Gui.Name .. "/" .. a.Obj.Name .. "<>" .. b.Gui.Name .. "/" .. b.Obj.Name
					if not printed[key] and printedCount < 80 then
						printed[key] = true
						printedCount += 1
						print(string.format("[UI 겹침] %s  <->  %s  (겹친 넓이 %d, 화면 %dx%d)", describe(a), describe(b), w * h, viewport.X, viewport.Y))
					end
				end
			end
		end
	end
end

task.spawn(function()
	task.wait(8)
	print("[UI 겹침] 점검을 시작했습니다 (Studio 전용). 마을 / 필드 / 던전 / 메뉴를 돌아다니면 겹치는 곳이 Output 에 찍힙니다.")
	while true do
		pcall(scan)
		task.wait(4)
	end
end)
