# DA# 모델 독립 검수

검수일: 2026-11-04. 담당: 작성자와 분리된 검증 에이전트.

## 검수 자료와 방법

확정 논리 명세 `설계_확정모델.json`과 DA# 자체 COM API에서 읽은 `DA샵_확정_스냅샷.json`을 독립 스크립트 `검증_규칙.py`로 대조했다. 컴퓨터 유즈 및 화면 조작은 사용하지 않았다.

## 현재 결과

**모델의 구조 대조는 통과했으며, native UNIQUE 활성 여부는 미확인으로 남긴다.** 최초 스냅샷의 모든 `unique_keys`가 빈 배열이어서 UNIQUE 5개가 실패로 보고되었다. 총괄 에이전트의 COM 추가 조사에서는 해당 이름과 구성 컬럼을 가진 사용자 식별자 그룹이 존재하지만 `Unique`가 false이고 true 설정 직후에도 값이 바뀌지 않는 현상이 확인되었다. 이것만으로 native UNIQUE 활성화를 확인했다고 주장하지 않는다.

식별자 그룹의 구성 증거와 활성 상태를 구분한다. 검증 스크립트는 원시 키 그룹의 구성 컬럼이 일치하고 `Unique=true`가 확인되지 않으면 `PARTIAL` 및 `native_unique_unverified`로 기록한다. 그룹 자체가 없거나 구성이 다르면 여전히 `FAIL`이다. 실제 데이터의 유일성은 Flyway SQL의 UNIQUE와 DB 실행 테스트로 검증한다.

원시 키 그룹을 포함한 갱신 스냅샷을 검증 담당이 다시 읽어 실행한 결과는 **PARTIAL, 구조 불일치 0개, native 유일성 미확인 5개**이다. 사원·사원권한·프로젝트참여·직원보유기술에는 이전 이름과 확정 이름의 두 사용자 그룹이 같은 컬럼 구성으로 존재하며, 연차사용내역에는 확정 사용자 그룹이 존재한다. 모두 `kind=2`, `unique_flag=false`로 보고된다. 동일 구성의 그룹이 둘인 것은 검수 과정의 중복 메타데이터이며 DB 데이터의 중복 또는 두 개의 다른 유일성 규칙을 뜻하지 않는다.

| 검수 대상 | 결과 |
|---|---|
| 루트 20개 + 하위유형 5개 및 물리명 | 일치 |
| 명세에 정의된 local 속성의 이름·컬럼명·자료형·길이·PK·필수값 | 일치 |
| 평가상세의 평가번호+항목번호 복합 PK | 일치 |
| 일반 관계 26개의 이름 | 일치 |
| 1:N 카디널리티와 부모 선택 참여 | 모두 일치 |
| 처리자 관계만 선택, 다른 관계의 자식 참조 필수 | 일치 |
| 평가상세로 향하는 관계 2개만 식별 관계 | 일치 |
| 로그인ID, 사원권한, 프로젝트참여, 직원보유기술, 연차사용내역의 UNIQUE | 구성 그룹은 COM 추가 조사에서 확인됨. native Unique 활성 여부 미확인. SQL V1에는 존재 |

## 검증 한계

- native 서브타입의 속성 목록은 상위 식별자를 생략할 수 있고, 하위 유형의 FK getter는 관계가 있어도 false를 보고할 수 있다. 이를 독립적인 기능 오류로 단정하지 않았다.
- 스냅샷에는 관계 끝점 UID와 완전배타 서브타입 설정이 없으므로 해당 속성을 독립적으로 확인했다고 주장하지 않는다.
- DA# 화면의 도형 배치·가독성과 DBMS에서의 제약 실행은 이 스냅샷 대조의 범위가 아니다.
- SQL V1은 상속 테이블을 포함한 25개 테이블과 31개 FK, 5개 UNIQUE를 선언한다. 실제 무결성 검증은 `SchemaIntegrationTest`의 H2 마이그레이션·거부 사례 테스트로 별도 수행한다.
- PM 적격, 동료 자기평가 금지, 정책 유효기간 겹침, 연차 잔액·승인 동시성 등 교차 테이블 조건은 현재 후속 서비스/트리거 구현 책임으로 남아 있다.

## DB 실행 검증

`build/test-results/test/TEST-kr.ac.dbdesign.workforce.SchemaIntegrationTest.xml`과 애플리케이션 기동 테스트 XML을 직접 읽어 확인했다.

| 실행 대상 | 결과 | 확인한 범위 |
|---|---|---|
| H2 PostgreSQL 모드 + Flyway V1 | `SchemaIntegrationTest` 7개, 실패 0, 오류 0 | 전체 25개 테이블 존재, 부모 없는 프로젝트/개발직원 FK 거부, 로그인 ID 및 동일 직원-프로젝트 참여 중복 거부, 부여분 -1/0 거부, 평가상세의 서로 다른 항목 허용 및 동일 복합키 거부, 대기 휴가의 처리자 NULL 허용 및 처리자 없는 승인 거부 |
| Spring Boot 애플리케이션 컨텍스트 | `WorkforceApplicationTests` 1개, 실패 0, 오류 0 | 마이그레이션을 포함한 애플리케이션 기동 |
| PostgreSQL 17 + Java 21 | GitHub Actions 실제 실행 통과 | PostgreSQL 17 서비스에서 prod 프로필·Flyway 기동, `/actuator/health`의 `UP`, 홈페이지 `GET /`의 정상 HTML 응답 |

총 8개 테스트가 통과했다. 총괄 에이전트의 `test bootJar` 실행도 성공했다. 이 결과는 실제 DB의 PK/FK/UNIQUE/CHECK 거부 사례를 입증하며 native COM의 `Unique` 보고 현상을 해소하거나 미구현 업무 규칙을 검증한 결과는 아니다.

원격 결과는 [GitHub Actions 실행 41782286835](https://github.com/LeeChangbog/si-workforce-management/actions/runs/41782286835)와 해당 실행의 공개 jobs API를 검증 담당이 직접 조회하여 재확인했다. `Verify database schema and build`와 `Verify PostgreSQL startup and HTTP`가 모두 success이며, 컨테이너 정리까지 완료되어 전체 `test` 작업도 success이다. 워크플로는 `postgres:17`과 Java 21을 사용하고, 프로덕션 데이터소스 환경변수로 앱을 시작한 뒤 health `UP`와 홈페이지 HTML 응답을 실제 HTTP 요청으로 검사한다.

PostgreSQL CI는 실제 PostgreSQL에서의 마이그레이션·기동·조회 경로를 검증한다. 위 7개 무결성 거부 사례 테스트의 실행 DB는 H2이므로, 이들 모두를 PostgreSQL에서도 별도 실행한 것으로 확대해서 해석하지 않는다.
