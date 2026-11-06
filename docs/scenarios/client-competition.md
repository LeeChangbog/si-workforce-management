# 정보 차단벽: 경쟁 발주처의 동시 투입 탐지

## 반영 범위

기존 엔티티와 관계의 정의는 유지하고 `발주처경쟁관계(CLIENT_COMPETITION)` 1개와 발주처에서 오는 식별 관계 `경쟁기준`, `경쟁상대` 2개만 추가했다. 총 26개 테이블, 일반 관계 28개와 상속 관계 5개에 대응하는 FK 33개다. IE 표기이며 기준 DBMS는 PostgreSQL이다.

| 논리명 | 물리명 | 타입 | 제약 |
|---|---|---|---|
| 기준발주처번호 | CLIENT_ID_A | BIGINT | PK, FK → CLIENT.CLIENT_ID, NOT NULL |
| 경쟁발주처번호 | CLIENT_ID_B | BIGINT | PK, FK → CLIENT.CLIENT_ID, NOT NULL |
| 등록일 | REGISTERED_ON | DATE | NOT NULL |
| 해제일 | RELEASED_ON | DATE | NULL 허용, NULL은 현재 유효 |
| 등록사유 | REASON | VARCHAR(200) | NOT NULL |

복합 PK는 `(CLIENT_ID_A, CLIENT_ID_B)`이고 CHECK는 `CLIENT_ID_A < CLIENT_ID_B`, `RELEASED_ON IS NULL OR RELEASED_ON >= REGISTERED_ON`이다. NULL 해제일은 종료 제한이 없다는 뜻이며 등록일부터 유효하다. 두 관계 모두 실선이며 발주처 쪽 `1 (||)`, 경쟁 관계 쪽 `0..N (○<)`이다. 한 발주처가 A 역할 또는 B 역할로 여러 쌍에 등장할 수 있다. 경쟁은 대칭적인 업무 의미를 가지되 한 쌍을 A<B인 한 행으로만 저장한다.

## 시연 순서

1. 새 데모 DB에서 애플리케이션을 한 번 시작해 Flyway V1/V2를 적용한다.
2. 같은 DB의 IntelliJ Database 콘솔이나 PostgreSQL 클라이언트에서 `src/main/resources/db/demo/client_competition_demo.sql`을 한 번 실행한다.
3. `src/main/resources/db/queries/client_competition_violations.sql`을 실행한다.
4. 아래 위반 3건이 나오고 정상 비교 사례가 제외되는지 확인한다.

PostgreSQL CLI 예시는 다음과 같다. 접속 정보는 실제 데모 DB에 맞게 지정한다.

```powershell
psql -h localhost -p 5432 -U workforce -d workforce -v ON_ERROR_STOP=1 --single-transaction -f src/main/resources/db/demo/client_competition_demo.sql
psql -h localhost -p 5432 -U workforce -d workforce -v ON_ERROR_STOP=1 -f src/main/resources/db/queries/client_competition_violations.sql
```

데모 SQL은 Flyway 기본 경로 밖에 있어 자동 적재되지 않는다. 가상 직원 9명과 가상 경영진 1명, 발주처 6개·경쟁 쌍 3개·프로젝트 6개·참여 16개·직무수행이력 16개를 사용한다. 주민등록번호와 비밀번호 필드에는 실제 식별정보나 로그인 가능한 비밀번호를 사용하지 않는다. 고정 데모 키로 적재하므로 새 DB에서 한 번 실행하는 스크립트이며, 기존 업무 DB에 반복 실행하지 않는다. 데모의 명시적 identity 키는 각 테이블의 700000번대에 있으므로 실제 업무 데이터와 혼용하는 용도가 아니다.

| 사번 | 발주처·프로젝트 A | A 투입기간 | 발주처·프로젝트 B | B 투입기간 | 출력 겹친 기간 |
|---|---|---|---|---|---|
| COI001 | A은행 / A은행 차세대 | 2026-03-01~03-31 | B은행 / B은행 모바일 | 2026-03-15~04-15 | 2026-03-15~03-31 |
| COI002 | C보험 / C보험 청구 | 2026-05-01~05-10 | D보험 / D보험 계약 | 2026-05-10~05-20 | 2026-05-10 하루 |
| COI003 | E물류 / E물류 배송 | 2026-06-20~06-30 | F물류 / F물류 창고 | 2026-06-25~07-05 | 2026-06-25~06-30 |

`COI004`는 비경쟁 발주처 A은행/C보험의 동시 투입, `COI005`는 경쟁 발주처이나 투입기간 불일치, `COI006`은 경쟁 해제 후, `COI007`은 경쟁 등록 전의 동시 투입이다. `COI008`과 `COI009`는 서로 다른 직원이 경쟁 프로젝트에 같은 기간 참여한다. 모두 위반 조회에서 제외된다.

현재 등록된 발주처 쌍은 A은행/B은행, C보험/D보험, E물류/F물류다. 마지막 쌍은 2026-04-01~06-30에만 유효하다. 현재 시점의 유효 관계만 조회하는 `released_on IS NULL` 필터를 사용하면 COI003의 과거 위반을 놓치므로 사용하지 않는다.

## 애플리케이션 구현 경계

위 SQL은 대표 조회 시나리오를 실행·검증하기 위한 산출물이며 공개 HTTP API가 아니다. 서버에 연결할 때는 인증된 사용자의 MANAGEMENT 권한을 먼저 확인해야 한다. 현재 앱은 홈 조회만 구현되어 있으므로 투입 등록 시 경고와 경영진 전용 화면·권한 검사는 이번에 구현된 기능으로 보지 않는다. 상세 규칙은 [BR18~BR20](../model/business-rules.md)을 따른다.

기간 경계는 포함한다. 사용자 명세의 `overlap_from/to`는 두 투입기간의 교집합이며, 경쟁 관계 유효기간은 탐지 필터에 사용한다. 경쟁 유효기간까지 잘라낸 실제 위반일 구간과는 구분한다. 하나의 발주처 쌍에 대한 재등록 이력은 복합 PK 제약상 여러 행으로 저장할 수 없으며 이번 범위에서 이력용 엔티티를 추가하지 않는다.

## 성능 향상 실험 계획 — 미실행

최종보고서에서는 대표 조회를 대상으로 직무수행이력을 수만 건 이상 생성하고 같은 DB·통계·하드웨어 조건에서 인덱스 전후를 비교한다. 이번 데모의 16개 이력은 정확성 확인용이며 성능 개선의 근거가 아니다.

| 후보 | 계획 |
|---|---|
| `project(client_id)` | 신규 후보 |
| `project_participation(project_id, employee_id)` | 기존 `uk_project_employee`의 UNIQUE 인덱스가 같은 열·순서이므로 활용. 중복 인덱스 추가 안 함 |
| `assignment_history(participation_id, assigned_from, assigned_to)` | 신규 후보 |

1. 데이터 규모·분포·의도적 위반 비율과 PostgreSQL 버전을 기록한다.
2. 데이터 적재 후 `ANALYZE`하고 기존 PK·UK 인덱스를 포함한 초기 상태를 기록한다.
3. 동일한 대표 SELECT에 `EXPLAIN (ANALYZE, BUFFERS)`를 붙여 예열과 반복 측정을 구분해 저장한다.
4. 새 후보 인덱스를 한 개씩 적용한 뒤 같은 조건으로 반복 측정한다.
5. 결과 행·내용의 동일성을 먼저 확인하고, 실행 계획·중앙값·편차·버퍼 사용량을 비교한다. 반드시 빨라진다고 가정하거나 한 번의 0.001초 차이를 효과로 단정하지 않는다.

새 인덱스와 대용량 적재는 이번 변경에서 실행하지 않았다.

## V1 변경과 기존 DB

사용자 요청에 따라 `V1__initial_schema.sql` 끝에 신규 테이블을 추가했다. 기존 25개 CREATE TABLE 정의는 그대로다. 새 DB와 일회성 H2 개발 DB에서는 변경된 V1이 적용된다. 이전 V1을 적용한 영속 PostgreSQL은 Flyway checksum 불일치가 발생하므로 이 변경을 그대로 재기동하는 업그레이드 절차로 사용하지 않는다. 기존 데이터를 보존해야 하는 배포에서는 별도 버전 마이그레이션을 준비해야 하며, 이번 작업에서는 checksum repair나 DB 초기화를 수행하지 않았다.
