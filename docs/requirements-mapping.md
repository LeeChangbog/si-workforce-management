# 요구사항과 구현 범위

현재 MVP는 `GET /`에서 전체 등록 건수와 프로젝트·발주처 조인 목록을 조회한다. 아래 표의 ‘설계 반영’은 테이블 구조의 준비 상태를 의미하며, 해당 업무 화면이나 서버 검증의 구현 완료를 의미하지 않는다.

| 요구사항 | 설계의 주요 테이블 | 현재 MVP | 후속 구현 |
|---|---|---|---|
| URQ001 조직 및 업무 현황 | `employee`, `developer`, `non_developer`, `project` | 사원·프로젝트 전체 건수 조회 | 업무 규모에 맞는 가상 시연 데이터 |
| URQ002 프로젝트 정보 | `project`, `client` | 최근 착수 프로젝트 20개와 발주처·기간·상태 조회 | 프로젝트 등록·수정·검색 |
| URQ003 직원·경력·기술 | `employee`, `developer`, `non_developer`, `external_career`, `skill`, `employee_skill` | 사원 전체 건수 조회 | 사원 상세·기술·경력 관리 |
| URQ004 회원 관리 | `employee` | 설계 반영 | 회원가입, 사번 자동 발급, 로그인 ID 중복 안내, 본인 정보 수정 |
| URQ005 투입 관리 | `project_participation`, `assignment_history`, `job_role` | 설계 반영 | 직무·투입 기간 등록 및 검증 |
| URQ006 현재 투입 현황 | `project`, `project_participation`, `assignment_history` | 프로젝트·발주처 목록만 제공 | 기준일별 참여 인원·직무 조회 |
| URQ007 참여 이력·경력 | `project_participation`, `assignment_history`, `external_career` | 설계 반영 | 과거 기준일 조회, 경력 기간 중복 제거 |
| URQ008 조회 권한 | `access_role`, `employee_role` | 설계 반영 | 인증, 본인/경영진 조회 권한 적용 |
| URQ009 프로젝트 평가 | `project_evaluation`, `evaluation_item`, `evaluation_detail` | 평가 전체 건수 조회 | 항목별 작성·완료 및 종료 프로젝트 검증 |
| URQ010 고객 평가 | `customer_evaluation`, `client_contact`, `project_participation` | 설계 반영 | 고객 소속 확인, PM 의뢰·보고 절차 |
| URQ011 동료 평가 | `peer_evaluation`, `project_participation` | 설계 반영 | 동일 프로젝트·자기 평가 금지 검증 |
| URQ012 PM 평가 | `pm_evaluation`, `project_participation`, `assignment_history` | 설계 반영 | 해당 프로젝트 PM 직무 자격 검증 |
| 추가 기능: 휴가 | `leave_type`, `leave_policy`, `leave_request`, `annual_leave_grant`, `annual_leave_usage` | 휴가 신청 전체 건수 조회 | 신청·승인·차감·취소, 프로젝트 공백 조회 |

## 데이터 해석

- 홈의 사원·프로젝트·평가·휴가 신청 수는 각각 테이블의 전체 레코드 수다. 진행 중인 프로젝트 수, 완료 평가 수, 승인 휴가 수로 해석하지 않는다.
- 프로젝트 목록은 `project.client_id = client.client_id`로 조인하며 `start_on DESC, project_id DESC` 순서로 최대 20개를 표시한다. 등록된 프로젝트가 없으면 빈 상태를 표시한다.
- 홈 조회의 DB 연결·스키마 오류는 예외를 통해 드러난다. 장애를 0건으로 바꾸거나 가상 응답으로 대체하지 않는다.
- 일반 직원의 타인 상세 조회 제한은 후속 인증·권한 구현의 요구사항이다. 현재 공개 홈에는 개인 상세정보·주민등록번호·로그인 정보가 표시되지 않는다.

## 구현 시 유지할 제약

- 사원과 프로젝트 평가는 상위 테이블과 유형별 하위 테이블로 관리한다. 상위 discriminator와 하위 유형이 일치하고, 필요한 하위 유형은 정확히 하나 존재해야 한다.
- 로그인 ID, 사원·권한, 프로젝트·개발직원, 개발직원·기술 조합의 유일성을 유지한다.
- 프로젝트별 투입 인원은 사번 또는 참여번호의 `DISTINCT`로 집계한다. 겹치는 프로젝트 투입 기간을 경력으로 단순 합산하지 않는다.
- 동료·PM·고객 평가의 동일 프로젝트 조건, PM 직무 자격, 고객 담당자의 발주처 일치는 관련 행을 함께 확인하는 검증이 필요하다.
- 고객평가는 의뢰 PM·의뢰일시·보고일시를 추적하며 의뢰 PM이 보고도 주관한다고 가정한다.
- 휴가 신청·부여·사용 원장은 분 단위로 저장한다. 승인·차감은 하나의 트랜잭션으로 처리하고 신청자와 부여 대상, 만료일, 잔량을 확인한다.
- 사원 100명, 개발자 70명, 월평균 프로젝트 10개는 초기 업무 규모다. 고정 행 수 제한으로 구현하지 않는다.

## 시연 확장 후보

현재 홈의 프로젝트·발주처 조회는 두 테이블 조인이다. 이후 기준일별 프로젝트 투입 인원·직무 조회, 휴가와 투입 기간이 겹치는 직원 조회를 추가할 수 있다. 대표 시나리오의 성능 향상은 데이터 규모·실행 계획·반복 측정 결과로 검증한다.

이 문서는 팀 요구사항 12개와 추가 휴가 설계를 요약한 공개용 매핑이다. 원본 과제 PDF와 요구사항 스프레드시트는 저장소에 포함하지 않는다.
