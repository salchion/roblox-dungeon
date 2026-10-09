# 소리 넣는 법 / 넣을 소리 목록

소리 ID(숫자)를 **ReplicatedStorage > AudioIds** 스크립트의 `Bank = { ... }` 안에 적으면 된다.

```lua
Bank = {
    Crit = 1234567890,
    Aug_Storm = 1111111111,
}
```

- 적은 항목은 가공하지 않고 **그 소리 그대로** 나온다. 안 적은 `★` 항목은 **소리가 나지 않는다** (게임은 문제없이 돈다).
- 너무 크거나 길면 `Shared/SoundBank.lua` 의 해당 항목 `Volume`(음량 배율) / `CustomLength`(끊는 시간, 초) 를 줄이면 된다.
- Studio 에서 **K 키**를 누르면 사운드 테스트 창에서 항목별로 들어볼 수 있다.
- 로블록스 툴박스(오디오)에서 **저작권 없는** 소리를 고르자.

## 우선순위 1 — 플레이 내내 계속 들리는 소리
| 키 | 언제 | 추천 느낌 / 길이 |
|---|---|---|
| Crit | 치명타 | 오버워치 헤드샷 같은 "팅!" · 0.3초 이하 |
| Shot_Shotgun / Shot_Sniper / Shot_Rocket / Shot_Rail | 무기 발사 | 무기마다 확 다른 소리 (샷건 묵직, 저격 크게 "쾅", 로켓 "퐁", 레일건 "위잉-쾅") |
| Boom | 폭발 (몬스터 폭발, 충격파, 처치 폭발) | 묵직한 저음 폭발 · 1초 안쪽 |
| UltShot | 데드아이 연사 한 발 | 아주 짧고 선명하게 (12연발이라 길면 시끄러움) |

## 우선순위 2 — ★ 어그먼트 (플레이 방식이 바뀐 느낌을 소리가 받쳐 준다)
| 키 | 언제 |
|---|---|
| Aug_Get | 어그먼트를 얻는 순간 (몸에서 빛이 퍼짐) · 짜릿한 "파워업" |
| Aug_Synergy | 시너지 발동 · 더 크고 화려한 파워업 |
| Aug_Missile / Aug_MissileHit | 크리 미사일 발사 / 명중 (자주 남: 짧게) |
| Aug_Nova | 처치 폭발 |
| Aug_Blade | 회전 칼날이 벨 때 ("슉" 짧게, 자주 남) |
| Aug_Storm | 낙뢰 (번개 / 천둥) |
| Aug_MeteorFall / Aug_MeteorHit | 유성 낙하 ("휘이이") / 착탄 (쾅, 큰 폭발) |
| Aug_Flame | 불길이 생길 때 ("화륵") |
| Aug_Execute | 처형 (쓱 / 서늘한 타격) |
| Aug_Pulse | 수호 파동 (맑은 울림) |
| Buff_Get | 일반 강화 획득 |
| Penalty_Get | 패널티 발동 (불길한 "두둥") |

## 우선순위 3 — 위기 / 이벤트 / 진행
| 키 | 언제 |
|---|---|
| Player_Hurt | 내가 맞았을 때 (짧은 "윽") |
| Low_Health | 체력 25% 이하 (심장 소리) |
| Warn_Overrun | 던전에서 몬스터가 한도를 넘음 (경고음) |
| Shield_Block | 방패 기사에게 막힘 ("쨍!") |
| Event_Siren | 공습 사이렌 |
| Event_Stampede | 몬스터 대이동 (발굽 / 뿔피리) |
| Event_Elite | 엘리트 부대 출현 (나팔) |
| Event_Goblin | 황금 고블린 출현 (반짝 + 동전) |
| Event_Boss | 침공 사령관 출현 |
| Boss_Spawn / Boss_Enrage | 던전 보스 등장(포효) / 격노 |
| Dungeon_Start / Dungeon_Clear / Dungeon_Fail | 던전 시작 / 클리어(팡파르) / 실패 |
| Quest_Claim | 퀘스트 · 업적 보상 수령 (동전) |
| Rare_Drop | 희귀 이상 장비 획득 |

## 이미 가공음이 있는 것 (원하면 직접 소리로 교체 가능)
LevelUp · Enh_Fail · Enh_Evolve · Gacha_Drop / Gacha_Tick / Gacha_Card / Gacha_Pop1~5 · Shot_Pistol / Revolver / Rifle / Flamer / Cannon

## 배경음악 (AudioIds 에 적는다)
- 곡 하나: `Dungeon = 111,`  /  여러 곡(끝나면 다음 곡): `Dungeon = { 111, 222, 333 },`
- 필드 구역별: `Field1 = ..., Field2 = ..., ... Field8 = ...` (없으면 `Field` → `Lobby`)
- 추천: Doom(최후의 군주) 1곡 → Field1~8 → Dungeon 3~4곡 → Boss 2~3곡 → Lobby 2곡
