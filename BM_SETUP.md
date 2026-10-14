# BM 설정 체크리스트 (상품 만들기 → 코드에 번호 넣기 → 테스트)

가격은 코드가 아니라 **Roblox 크리에이터 사이트**에서 정합니다. 코드의 `ProductId` / `PassId` 는 사이트에서 받은 번호를 넣는 자리입니다 (0 이면 "준비 중", Studio 에서는 0 이어도 테스트 지급이 됩니다).
아래 가격은 제안값(추정)이고, 시작은 낮게 하고 반응을 보며 조정하세요.

## 1. 게임 패스 (Game Pass, 영구) — 1개

| 코드 키 (`Config.Shop.Passes`) | 이름 | 설명(영문) | 제안 가격 |
|---|---|---|---|
| `VIP` | VIP Pass | XP +20% · Idle income +20% · Training slot +1 · Training/breakthrough time -20% · Bag +20 slots · Golden aura | 599 |

→ 만든 뒤 번호를 `Config.Shop.Passes.VIP.PassId` 에 넣습니다.

## 2. 개발자 상품 (Developer Product, 소모성) — 17개

| 코드 키 (`Config.Shop.Products`) | 이름 | 설명(영문) | 제안 가격 |
|---|---|---|---|
| `TimeSkip10m` | Time Skip 10 min | Reduces training / breakthrough wait time by 10 min | 29 |
| `TimeSkip1h` | Time Skip 1 hour | Reduces training / breakthrough wait time by 1 hour | 79 |
| `TimeSkip8h` | Time Skip 8 hours | Reduces training / breakthrough wait time by 8 hours | 399 |
| `KeyPack` | 5 Dungeon Keys | For when you want to run more dungeons | 59 |
| `TicketPack` | 5 Gear Roll Tickets | Use tickets to roll for gear | 79 (※ 유료 랜덤 정책 확인 필요) |
| `IdleBooster` | Idle Booster (1 hour) | 2x idle income | 49 |
| `XpBooster` | XP Booster (1 hour) | 2x XP | 49 |
| `LuckBooster` | Luck Booster (1 hour) | Gear drop rarity +50% | 49 |
| `GoldS` | Gold Pack S | 30 minutes of YOUR idle income · max 3 per day | 49 |
| `GoldM` | Gold Pack M | 2 hours of YOUR idle income · max 3 per day | 149 |
| `GoldL` | Gold Pack L | 8 hours of YOUR idle income · max 3 per day | 449 |
| `IdleMult1` | Idle Income +25% | Permanent | 149 |
| `IdleMult2` | Idle Income +50% | Permanent (replaces +25%) | 299 |
| `IdleMult3` | Idle Income +100% | Permanent (replaces the previous tier) | 599 |
| `IdleCap8` | Idle Accrual Cap: 8 Hours | Accrues up to 8 hours while you're away | 99 |
| `IdleCap24` | Idle Accrual Cap: 24 Hours | Accrues up to a full day while you're away | 249 |
| `TrainSlot` | Training slot +1 | Permanent · Train one more at the same time | 299 |

→ 만든 뒤 각 번호를 `Config.Shop.Products.<코드 키>.ProductId` 에 넣습니다.
(영구 상품을 "개발자 상품"으로 파는 경우, 코드가 구매 기록으로 한 번만 반영합니다. 영구 상품이 중복 구매되지 않게 단계 상품은 높은 단계가 덮어쓰는 방식입니다.)

## 3. 하는 순서

1. Roblox 크리에이터 사이트(Creator Hub)에서 이 게임을 열고, **수익화** 메뉴에서 위 상품을 하나씩 만든다 (이름, 설명, 가격 입력). 메뉴 이름은 Roblox 가 바꿀 수 있으니 화면에서 확인.
2. 각 상품의 번호(ID)를 적어 둔다.
3. 번호를 `Shared/Config.lua` 의 `ProductId` / `PassId` 에 넣는다 (또는 번호를 알려 주면 대신 넣는다).
4. 게시 → **본 게임이 아니라 테스트용 복사본 플레이스**에서 먼저 테스트한다.
5. 테스트 결제로 확인할 것:
   - 구매하면 효과가 바로 적용되는가 (골드가 늘었는가 / 열쇠가 늘었는가)
   - 같은 상품을 다시 사면 또 지급되는가 (소모성)
   - 골드 팩을 하루 4번째로 사려고 하면 막히는가
   - 구매 직후 게임을 껐다 켜도 효과가 남아 있는가 (저장)
   - 단계 상품(방치 +25% → +50%)이 덮어쓰는가
6. 문제가 없으면 본 게임에 게시.

## 4. 라이브 전 확인 (정책)

- 티켓으로 장비를 뽑는 구조가 "유료 랜덤 아이템" 규정에 해당하는지, 확률 공개가 필요한지 Roblox 공식 정책에서 확인한다.
- 게임 설명 / 연령 설정 / 썸네일은 크리에이터 사이트에서 설정한다.
