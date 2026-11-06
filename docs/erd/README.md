# ERD 산출물

`SI_workforce_통합_ERD.drawio`는 diagrams.net에서 편집 가능한 4페이지 도면이다. 각 페이지의 SVG와 PNG도 함께 제공한다.

- 00_overview: 26개 테이블과 모든 일반 관계 28개, 상속 관계 5개의 개요. 개요는 PK/FK를 표시하고, 새 발주처경쟁관계에는 모든 속성과 CHECK도 표시한다.
- 01_staff_project: 직원, 권한, 개발직원, 기술, 외부 경력, 프로젝트와 투입 이력, 발주처 경쟁관계 상세.
- 02_evaluation: 프로젝트 평가의 3개 하위 유형, 고객 의뢰 PM, 평가 상세.
- 03_leave: 정책 버전, 신청, 부여·사용 원장과 선택 처리자.

사원/평가 상속은 각각 완전배타이다. 상속별로 1 : 0..1이며, 상위 하나당 정확히 한 하위 유형이 존재하도록 서버 트랜잭션에서 검증한다. 기본 관계의 자식은 부모 한 개를 참조하고, 부모는 자식 0..N개를 가질 수 있다. 휴가 처리자만 0..1명이다.

상세 도면에는 해당 업무 밖의 참조 테이블 일부가 생략되며 전체 연결은 통합 개요에서 확인한다. [NULL]은 선택 속성이다. FK 역할명은 자식 테이블의 속성명으로 표시한다. 1:N 선의 양쪽 필수 참여는 사용하지 않는다.

SQL의 TIMESTAMP를 논리 모델의 일시 속성에 대응시켰다. PostgreSQL용 초기 스키마 V1과 같은 물리명을 사용한다. 법정 휴가 한도·근무일 환산·PM 적격성·동료 자기 평가 금지·같은 프로젝트/소유자 검증은 정의서 및 앱 트랜잭션 규칙을 함께 참조한다.

도면은 로컬 Python·SVG/XML·Pillow로 생성했다. DA# 모델 파일과 draw.io·SVG·PNG는 같은 폴더에 제공한다.

# DA# 현재 파일 확인 범위

`SI_통합_ERD.damx`는 DA# 자체 API로 갱신한 논리 모델입니다. 21개 루트, 5개 하위유형, 28개 일반 관계를 반영했습니다. 저장 후 파일을 닫고 다시 열어 신규 5개 속성의 타입·PK/FK·필수값과 관계 수를 재확인했습니다. 새 관계는 통합 주제영역과 `04_정보차단벽` 상세 주제영역에서 볼 수 있습니다. 기존 4개 주제영역을 유지하고 상세 주제영역 하나를 추가했으며, draw.io는 기존의 4페이지입니다.

추가 전후 COM 스냅샷 비교로 기존 25개 테이블과 26개 일반 관계의 정의가 유지됨을 확인했습니다. 신규 두 관계의 부모/자식·FK 역할명·식별 여부·1:0..N은 [경쟁관계 native 감사](../model/competition-native-audit.json)에 기록했습니다. CHECK 식은 native 엔티티 설명과 모델 메타데이터에 기록하고 SQL V1에서 강제합니다.

DA# API의 기존 `KeyGroup.Unique`는 설정 후에도 `false`를 반환하므로 DA# 파일만으로 기존 유일 제약 활성화를 확인할 수 없습니다. 유일성은 Flyway DDL의 `UNIQUE`와 DB 테스트를 기준으로 확인하며, 이전 검수의 자세한 결과는 [native 검증 기록](../model/native-audit.md)에 있습니다. native 화면 배치는 화면 조작으로 검수하지 않았으며, 시각 검수본은 위 draw.io·SVG·PNG입니다.


## 발주처 경쟁관계 추가 (2026-11-06)

기존 25개 테이블과 26개 일반 관계, 상속 5개의 정의는 그대로 유지했다. 발주처경쟁관계 `CLIENT_COMPETITION` 하나와 발주처에서 이어지는 식별 관계 `경쟁기준`·`경쟁상대` 두 개만 추가했다. 현재 합계는 루트 21 + 하위유형 5 = 테이블 26개, 일반 관계 28개 + 상속 5 = 물리 FK 33개다. 기존 네 페이지와 기존 엔터티 배치를 유지했으며 00·01 페이지의 빈 공간에 새 엔터티를 추가했다.

경쟁 관계인 발주처 쌍. 발주처 간 셀프 M:N을 해소하는 교차 엔티티. 한 쌍은 한 방향(A<B)으로만 저장한다.

| 속성 | 물리명 | 타입 | NULL | 키/역할 |
| --- | --- | --- | --- | --- |
| 기준발주처번호 | CLIENT_ID_A | BIGINT | 불가 | PK·FK → CLIENT.CLIENT_ID, CLIENT A |
| 경쟁발주처번호 | CLIENT_ID_B | BIGINT | 불가 | PK·FK → CLIENT.CLIENT_ID, CLIENT B |
| 등록일 | REGISTERED_ON | DATE | 불가 | |
| 해제일 | RELEASED_ON | DATE | 허용 | NULL = 현재 유효 |
| 등록사유 | REASON | VARCHAR(200) | 불가 | |

복합 PK는 `(CLIENT_ID_A, CLIENT_ID_B)`다. 두 식별 실선 관계는 각각 부모 `1 (||)` : 자식 `0..N (○<)`이며, 발주처의 참여는 선택이고 경쟁관계 행의 두 발주처 참조는 필수다. 선의 `CLIENT A`·`CLIENT B` 역할명과 두 PK/FK 속성을 함께 표시했다. 새 속성의 `[NN]`은 NOT NULL, `[NULL]`은 NULL 허용이다.

```sql
CHECK (CLIENT_ID_A < CLIENT_ID_B)
CHECK (RELEASED_ON IS NULL OR RELEASED_ON >= REGISTERED_ON)
```

`model-definition.json`과 `../model/schema.json`은 같은 논리 모델이다. 기존 배열 구조는 유지하며, `entity_metadata.발주처경쟁관계`에 물리 타입·nullable·복합 PK·FK 역할·정확한 CHECK 식과 참여 제약을 명시했다. 기존 entities·relations·subtypes 항목은 변경하지 않고 새 항목만 덧붙였다.

로컬 재생성: Python에서 `python docs/erd/generate_erd.py`를 실행한다(Pillow, Malgun Gothic 글꼴 필요). 생성기는 SVG·PNG·draw.io만 갱신하며 이 README의 수기 검증 기록을 덮어쓰지 않는다.
