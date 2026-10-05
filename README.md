# Roblox Dungeon

로비(3인칭) → 파티 결성 → 던전(웨이브 + 스탯 분배 + 보스) → 골드로 무기 강화 → 로비에서 과시.

## Roblox Studio 배치

각 `.lua` 파일을 아래 위치에 스크립트로 붙여넣으세요. (이름이 중요합니다)

| 파일 | 종류 | 위치 / 이름 |
|---|---|---|
| `Shared/Config.lua` | ModuleScript | `ReplicatedStorage` / **Config** |
| `Shared/Remotes.lua` | ModuleScript | `ReplicatedStorage` / **Remotes** |
| `GameServer.lua` | Script | `ServerScriptService` / **GameServer** |
| `Server/Effects.lua` | ModuleScript | `ServerScriptService/Modules` / **Effects** |
| `Server/WeaponService.lua` | ModuleScript | `ServerScriptService/Modules` / **WeaponService** |
| `Server/PartyService.lua` | ModuleScript | `ServerScriptService/Modules` / **PartyService** |
| `Server/LobbyService.lua` | ModuleScript | `ServerScriptService/Modules` / **LobbyService** |
| `Server/DungeonService.lua` | ModuleScript | `ServerScriptService/Modules` / **DungeonService** |
| `Server/DataService.lua` | ModuleScript | `ServerScriptService/Modules` / **DataService** |
| `PlayerClient.lua` | LocalScript | `StarterPlayer/StarterPlayerScripts` / **PlayerClient** |

`Modules`는 `ServerScriptService` 안에 직접 만드는 Folder입니다.
로비 맵, 던전 아레나, 무기 모델은 모두 코드로 생성되므로 별도 맵이 필요 없습니다.
저장(골드 / 무기 레벨)을 쓰려면 Studio의 Game Settings → Security → *Enable Studio Access to API Services* 를 켜세요 (꺼져 있어도 저장 없이 동작).

## 게임 흐름

### 로비
- 3인칭 카메라, 마우스 클릭으로 무기 이펙트 발사(데미지 없음, 과시용)
- 머리 위 이름표에 `+N 무기이름`(강화 레벨)이 표시되고 무기 외형도 그대로 보임
- **파티**: 우측 패널에서 로비 플레이어를 초대 → 수락하면 결성. 최대 4인, 파티장은 추방 가능, 파티장이 나가면 다음 사람이 승계
- **던전 게이트**(보라색 포탈): 파티장(또는 솔로 플레이어)이 `E`로 입장 → 로비에 있는 파티원 전원이 함께 이동
- **강화대**(모루) 또는 `무기 강화` 버튼: 강화창 열기

### 던전
1. 5초 카운트다운 후 웨이브 시작 (총 5웨이브, 웨이브마다 몬스터가 더 많고/크고/단단해짐, 인원이 많으면 더 많이 등장)
2. 웨이브 클리어 → **30초 스탯 분배 타임** (스탯 포인트 +3, 체력 완전 회복)
   - 치명타 확률 / 공격 속도 / 최대 체력 — 숫자키 `1` `2` `3` 또는 `+` 버튼
   - 파티원 전원이 `준비 완료`를 누르면 일찍 끝남
3. 모든 웨이브 클리어 후 한 번 더 스탯 타임 → **보스 등장**
   - 조준 3연발 + 전방위 탄막, 체력 50% 이하에서 광폭화(공격 가속 + 쫄병 소환)
4. 보스 처치 = 클리어, 전원 사망 = 실패. 8초 후 로비로 복귀 (스탯 포인트는 초기화)
- 몬스터 처치/웨이브 클리어/보스 처치 골드는 파티원 모두에게 지급

### 무기 강화
- 로비에서 골드로 +1 강화 (최대 +15). 비용은 단계가 오를수록 증가, 성공 확률은 단계가 오를수록 감소(최소 40%), 실패해도 레벨은 유지
- 공격력 +20%/레벨, 크기 +6%/레벨
- 외형 변화 (`Config.Weapon.Tiers`): +0 철검 → +3 강철검(파란색, 반짝임) → +6 마력검(보라 유리, 궤적) → +9 황금 성검(네온, 빛) → +12 불꽃의 검(붉은 네온) → +15 무지개검
- 무기는 서버가 캐릭터에 장착하므로 모든 플레이어에게 보임

## 밸런스 조절
`Shared/Config.lua` 의 숫자만 바꾸면 됩니다 (웨이브 수, 스탯 효과, 강화 비용/확률, 몬스터/보스 능력치 등).
