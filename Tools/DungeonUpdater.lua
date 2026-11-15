-- DungeonUpdater: Roblox Studio 플러그인 (한 번만 설치하면 됨)
-- 툴바의 [던전 업데이트] 버튼을 누르면 GitHub 최신 코드를 받아서 스크립트들을 자동으로 만들고/덮어쓴다.
-- 어떤 스크립트를 어디에 둘지는 저장소의 manifest.json 에 적혀 있어서, 새 스크립트가 생겨도 플러그인을 다시 설치할 필요가 없다.
--
-- 설치: Studio에서 ServerStorage에 Script를 하나 만들고 이 파일 내용을 붙여넣은 뒤
--       Script를 우클릭 -> 저장/내보내기 -> "로컬 플러그인으로 저장..." -> 저장. (그 다음 만든 Script는 지워도 됨)
-- 처음 버튼을 누르면 "raw.githubusercontent.com 접근 허용" 창이 뜨는데 허용을 누르면 된다.
-- 사용: 3D 화면 탭이 보이는 상태에서 [던전 업데이트] 버튼 클릭 (코드 편집 탭이 열려 있으면 버튼이 비활성으로 보임)

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- 코드를 가져올 GitHub 저장소 / 브랜치 (main 에 합쳤으므로 main 에서 받는다)
local REPO = "salchion/roblox-dungeon"
local BRANCH = "main"

local toolbar = plugin:CreateToolbar("Dungeon")
local button = toolbar:CreateButton("던전 업데이트", "GitHub 최신 코드로 스크립트를 업데이트합니다", "")
button.ClickableWhenViewportHidden = true -- 코드 편집 탭이 열려 있어도 누를 수 있게

local function rawUrl(path)
	return string.format("https://raw.githubusercontent.com/%s/%s/%s?t=%d", REPO, BRANCH, path, os.time())
end

-- "ServerScriptService/Modules" 같은 경로의 폴더를 찾고, 없으면 Folder 로 만든다
local function resolveParent(path)
	local parts = string.split(path, "/")
	local current = game:GetService(parts[1])
	for i = 2, #parts do
		local child = current:FindFirstChild(parts[i])
		if not child then
			child = Instance.new("Folder")
			child.Name = parts[i]
			child.Parent = current
		end
		current = child
	end
	return current
end

-- 받기 하나: Studio 의 HTTP 요청 한도(분당 약 500번)에 걸리면 기다렸다 다시 (파일이 160개가 넘어 버튼을 두 번 누르면 한도를 넘었다)
local function fetch(path)
	for attempt = 1, 6 do
		local ok, result = pcall(function()
			return HttpService:GetAsync(rawUrl(path), true)
		end)
		if ok then return true, result end
		if string.find(tostring(result), "Number of requests exceeded", 1, true) and attempt < 6 then
			print(string.format("[업데이트] 요청 한도에 걸려서 15초 기다렸다 다시 받아요 (%s, %d/5)", path, attempt))
			task.wait(15)
		else
			return false, result
		end
	end
	return false, "retry limit"
end

local updateInner -- (아래에서 정의)
local busy = false
local function update()
	if busy then
		warn("[업데이트] 이미 업데이트 중이에요. 끝날 때까지 기다려 주세요.")
		return
	end
	busy = true
	local okRun, err = pcall(function() updateInner() end)
	busy = false
	if not okRun then warn("[업데이트] 오류: " .. tostring(err)) end
end

updateInner = function()
	if RunService:IsRunning() then
		warn("[업데이트] Play 중에는 업데이트할 수 없어요. 정지(■)한 뒤 다시 눌러주세요.")
		return
	end

	-- 1) 파일 목록(manifest.json) 먼저 받기
	local okManifest, manifestText = fetch("manifest.json")
	if not okManifest then
		warn("[업데이트] manifest.json 을 받지 못했어요: " .. tostring(manifestText))
		return
	end
	local manifest = HttpService:JSONDecode(manifestText)

	-- 2) 전부 먼저 내려받는다 (하나라도 실패하면 아무것도 바꾸지 않음)
	local contents = {}
	for _, file in ipairs(manifest.files) do
		local ok, result = fetch(file.path)
		task.wait(0.13) -- (분당 약 460번: 한도 아래로)
		if ok and #result >= 200000 then -- 스크립트 한 개 최대 크기: 넘는 파일이 있으면 아무것도 바꾸지 않는다 (예전엔 중간에 멈춰 일부만 바뀌었다)
			ok, result = false, string.format("파일이 너무 커요 (%d자, 한도 200000자)", #result)
		end
		if not ok then
			warn("[업데이트] 실패: " .. file.path .. " -> " .. tostring(result))
			warn("[업데이트] 아무것도 바꾸지 않았어요. 인터넷/허용 창을 확인하고 다시 눌러주세요.")
			return
		end
		contents[file.path] = result
	end

	-- 3) 스크립트 만들기 / 덮어쓰기
	ChangeHistoryService:SetWaypoint("던전 업데이트 전")
	local created, updated, kept = 0, 0, 0
	for _, file in ipairs(manifest.files) do
		local parent = resolveParent(file.parent)
		local existing = parent:FindFirstChild(file.name)

		if existing and existing.ClassName ~= file.class then
			existing:Destroy() -- 종류가 다르면(예: Script 대신 ModuleScript) 다시 만든다
			existing = nil
		end

		if existing then
			if file.overwrite then
				existing.Source = contents[file.path]
				updated += 1
			else
				kept += 1
			end
		else
			local script = Instance.new(file.class)
			script.Name = file.name
			script.Source = contents[file.path]
			script.Parent = parent
			created += 1
		end
	end
	ChangeHistoryService:SetWaypoint("던전 업데이트 후")

	print(string.format("[업데이트] 완료! 새로 만듦 %d / 업데이트 %d / 유지 %d  (Ctrl+S 로 저장하세요)", created, updated, kept))
end

button.Click:Connect(function()
	task.spawn(update)
end)

