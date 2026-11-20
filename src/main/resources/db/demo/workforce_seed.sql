-- PostgreSQL 17. Run on an empty business database after Flyway V1–V3.
-- All names, identifiers, contact details and employment records are fictional.
BEGIN;

LOCK TABLE employee, client, project, skill, leave_type IN SHARE ROW EXCLUSIVE MODE;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM employee)
        OR EXISTS (SELECT 1 FROM client)
        OR EXISTS (SELECT 1 FROM project)
        OR EXISTS (SELECT 1 FROM skill)
        OR EXISTS (SELECT 1 FROM leave_type) THEN
        RAISE EXCEPTION 'Use an empty business database. Existing data was preserved.';
    END IF;
END $$;

CREATE TEMP TABLE demo_staff ON COMMIT DROP AS
SELECT n, 'DEMO' || lpad(n::text, 3, '0') AS employee_id,
       make_date(2025 - (n - 1) % 23, 1, 1) AS hired_on,
       1 + (n - 1) % 23 AS tenure_years
FROM generate_series(1, 100) AS series(n);

INSERT INTO employee (employee_id, employee_name, resident_no, education, hired_on,
                      login_id, password_hash, employee_type)
SELECT employee_id, '가상사원' || lpad(n::text, 3, '0'), 'DEMO-NO-ID-' || n,
       (ARRAY['학사', '학사', '석사', '전문학사'])[1 + (n - 1) % 4],
       hired_on, lower(employee_id), 'DEMO-LOGIN-DISABLED',
       CASE WHEN n <= 70 THEN 'DEV' ELSE 'NONDEV' END
FROM demo_staff ORDER BY n;

INSERT INTO developer (employee_id, tech_grade)
SELECT employee_id, CASE WHEN tenure_years < 4 THEN 'JUNIOR'
                         WHEN tenure_years < 9 THEN 'MID' ELSE 'SENIOR' END
FROM demo_staff WHERE n <= 70;

INSERT INTO non_developer (employee_id, department_name)
SELECT employee_id, CASE WHEN n <= 80 THEN '마케팅'
                         WHEN n <= 90 THEN '경영관리' ELSE '연구개발' END
FROM demo_staff WHERE n > 70;

INSERT INTO employee_role (granted_on, employee_id, role_id)
SELECT hired_on, employee_id, 'EMPLOYEE' FROM demo_staff
UNION ALL
SELECT DATE '2026-01-01', employee_id, 'MANAGEMENT' FROM demo_staff WHERE n BETWEEN 81 AND 83;

INSERT INTO external_career (company_name, career_description, career_from, career_to, employee_id)
SELECT '가상 이전 직장 ' || (1 + n % 12),
       CASE WHEN n <= 70 THEN '업무 시스템 개발 및 운영' ELSE '사업 지원 및 운영 업무' END,
       (hired_on - INTERVAL '2 years')::date, hired_on - 1, employee_id
FROM demo_staff WHERE n % 3 <> 0;

INSERT INTO skill (skill_name, skill_category) VALUES
('Java', '언어'), ('Python', '언어'), ('JavaScript', '언어'), ('TypeScript', '언어'),
('Spring Boot', '프레임워크'), ('React', '프레임워크'), ('PostgreSQL', 'DBMS'),
('MySQL', 'DBMS'), ('Redis', '데이터 저장소'), ('Docker', '인프라'),
('Git', '협업'), ('JUnit', '테스트');

WITH skill_catalog AS (
    SELECT skill_id, row_number() OVER (ORDER BY skill_name) - 1 AS position FROM skill
)
INSERT INTO employee_skill (proficiency, experienced_from, employee_id, skill_id)
SELECT (ARRAY['BEGINNER', 'INTERMEDIATE', 'ADVANCED'])[1 + (d.n + s.offset_no) % 3],
       greatest(d.hired_on, DATE '2024-01-01'), d.employee_id, sk.skill_id
FROM demo_staff d
CROSS JOIN generate_series(0, 2) AS s(offset_no)
JOIN skill_catalog sk ON sk.position = ((d.n - 1) + s.offset_no * 4) % 12
WHERE d.n <= 70;

INSERT INTO client (client_name, business_no)
SELECT '가상 ' || client_name, 'DEMO-C' || lpad(n::text, 2, '0')
FROM unnest(ARRAY[
    'A은행', 'B은행', 'C보험', 'D보험', 'E물류', 'F물류',
    '하늘전자', '청록에너지', '푸른유통', '나래교육',
    '별빛제조', '새봄모빌리티', '온길통신', '바른식품', '숲문화재단',
    '미래건설', '누리미디어', '이음헬스', '마루여행', '다온공공연구원'
]) WITH ORDINALITY AS names(client_name, n)
ORDER BY n;

INSERT INTO client_contact (contact_name, email, client_id)
SELECT c.client_name || ' 담당 ' || n, 'contact-' || lower(c.business_no) || '-' || n || '@example.test',
       c.client_id
FROM client c CROSS JOIN generate_series(1, 2) AS contacts(n);

INSERT INTO client_competition (client_id_a, client_id_b, registered_on, reason)
SELECT least(a.client_id, b.client_id), greatest(a.client_id, b.client_id),
       DATE '2025-11-01', '정보 차단벽 시연용 가상 경쟁 관계'
FROM (VALUES ('DEMO-C01', 'DEMO-C02'), ('DEMO-C03', 'DEMO-C04'),
             ('DEMO-C05', 'DEMO-C06')) AS pair(a_code, b_code)
JOIN client a ON a.business_no = pair.a_code
JOIN client b ON b.business_no = pair.b_code;

CREATE TEMP TABLE demo_projects ON COMMIT DROP AS
SELECT month_no, slot_no, start_on, start_on + 39 + slot_no % 8 AS end_on,
       'DEMO-C' || lpad((1 + ((month_no - 1) * 10 + slot_no - 1) % 20)::text, 2, '0') AS client_code,
       '시연 ' || to_char(start_on, 'YYYY-MM') || ' ' || lpad(slot_no::text, 2, '0') || ' ' ||
       (ARRAY['시스템 개편', '업무 플랫폼 구축', '데이터 이관', '서비스 고도화',
              '현황 대시보드', '운영 자동화', '고객 포털', '품질 개선',
              '관리 시스템 전환', '업무 통합'])[slot_no] AS project_name
FROM generate_series(1, 12) AS months(month_no)
CROSS JOIN generate_series(1, 10) AS slots(slot_no)
CROSS JOIN LATERAL (
    SELECT (DATE '2025-11-01' + (month_no - 1) * INTERVAL '1 month')::date + slot_no + 3 AS start_on
) dates;

INSERT INTO project (project_name, start_on, end_on, project_status, client_id)
SELECT p.project_name, p.start_on, p.end_on,
       CASE WHEN p.end_on <= DATE '2026-11-20' THEN 'COMPLETED' ELSE 'IN_PROGRESS' END, c.client_id
FROM demo_projects p JOIN client c ON c.business_no = p.client_code
ORDER BY p.month_no, p.slot_no;

-- One shared developer in each of the three first-month competitor pairs.
CREATE TEMP TABLE demo_team ON COMMIT DROP AS
SELECT p.project_id, s.employee_id, members.member_no,
       (ARRAY['PM', 'PL', 'ANALYST', 'DESIGNER', 'PROGRAMMER', 'TESTER'])[members.member_no + 1] AS job_role_id
FROM demo_projects dp
JOIN project p USING (project_name)
CROSS JOIN generate_series(0, 5) AS members(member_no)
JOIN demo_staff s ON s.n = 1 + (
    (dp.month_no - 1) * 6 + (dp.slot_no - 1) * 6 + members.member_no
    - CASE WHEN dp.month_no = 1 AND dp.slot_no IN (2, 4, 6) AND members.member_no = 5
           THEN 6 ELSE 0 END
) % 70;

INSERT INTO project_participation (employee_id, project_id)
SELECT employee_id, project_id FROM demo_team ORDER BY project_id, member_no;

INSERT INTO assignment_history (assigned_from, assigned_to, participation_id, job_role_id)
SELECT p.start_on, least(p.end_on, DATE '2026-11-20'), pp.participation_id, t.job_role_id
FROM demo_team t
JOIN project_participation pp USING (project_id, employee_id)
JOIN project p USING (project_id);

CREATE TEMP TABLE demo_reviewers ON COMMIT DROP AS
SELECT target.participation_id AS target_id, pm.participation_id AS pm_id,
       peer.participation_id AS peer_id, p.end_on,
       (SELECT min(contact_id) FROM client_contact cc WHERE cc.client_id = p.client_id) AS contact_id
FROM project p
JOIN demo_team t ON t.project_id = p.project_id AND t.member_no > 0
JOIN project_participation target ON target.project_id = p.project_id AND target.employee_id = t.employee_id
JOIN demo_team t_pm ON t_pm.project_id = p.project_id AND t_pm.member_no = 0
JOIN project_participation pm ON pm.project_id = p.project_id AND pm.employee_id = t_pm.employee_id
JOIN demo_team t_peer ON t_peer.project_id = p.project_id AND t_peer.member_no = 1 + t.member_no % 5
JOIN project_participation peer ON peer.project_id = p.project_id AND peer.employee_id = t_peer.employee_id
WHERE p.project_status = 'COMPLETED' AND p.end_on + 2 <= DATE '2026-11-20';

INSERT INTO project_evaluation (evaluation_type, evaluated_on, writing_status, target_participation_id)
SELECT kind, r.end_on + 1, 'COMPLETED', r.target_id
FROM demo_reviewers r CROSS JOIN (VALUES ('CUSTOMER'), ('PM'), ('PEER')) AS types(kind)
ORDER BY r.target_id, kind;

INSERT INTO customer_evaluation (evaluation_id, evaluator_contact_id, requester_pm_participation_id,
                                 requested_at, reported_at)
SELECT e.evaluation_id, r.contact_id, r.pm_id,
       r.end_on + TIME '16:00', (r.end_on + 2) + TIME '10:00'
FROM project_evaluation e JOIN demo_reviewers r ON r.target_id = e.target_participation_id
WHERE e.evaluation_type = 'CUSTOMER';

INSERT INTO pm_evaluation (evaluation_id, evaluator_participation_id)
SELECT e.evaluation_id, r.pm_id
FROM project_evaluation e JOIN demo_reviewers r ON r.target_id = e.target_participation_id
WHERE e.evaluation_type = 'PM';

INSERT INTO peer_evaluation (evaluation_id, evaluator_participation_id)
SELECT e.evaluation_id, r.peer_id
FROM project_evaluation e JOIN demo_reviewers r ON r.target_id = e.target_participation_id
WHERE e.evaluation_type = 'PEER';

INSERT INTO evaluation_detail (evaluation_id, item_id, score, evaluation_content)
SELECT e.evaluation_id, i.item_id, 70 + (e.target_participation_id + length(i.item_id)) % 30,
       CASE i.item_id WHEN 'PERFORMANCE' THEN '시연용 평가: 계획에 맞춰 담당 업무를 수행함'
                      ELSE '시연용 평가: 진행 상황과 변경 내용을 팀에 공유함' END
FROM project_evaluation e CROSS JOIN evaluation_item i
WHERE i.item_id IN ('PERFORMANCE', 'COMMUNICATION');

INSERT INTO leave_type (leave_type_id, leave_type_name, legal_class)
VALUES ('DEMO_ANNUAL', '시연용 연차휴가', 'CONTRACT');

INSERT INTO leave_policy (effective_from, effective_to, limit_basis, limit_quantity, limit_unit,
                          deduct_annual_yn, counting_rule, policy_description, leave_type_id)
VALUES (DATE '2026-01-01', DATE '2026-12-31', 'YEAR', 25, 'DAY', 'Y', 'WORKDAY',
        '시연용 사내 정책. 1월 1일 현재 만 근속연수로 기본 15일에 3년차부터 2년마다 1일을 가산(상한 25일). 1일은 480분.',
        'DEMO_ANNUAL');

INSERT INTO annual_leave_grant (granted_on, expires_on, granted_minutes, grant_reason, employee_id, policy_id)
SELECT lp.effective_from, lp.effective_to, least(lp.limit_quantity::integer, 15 + (s.tenure_years - 1) / 2) * 480,
       '2026년 정기 지급 / 만 ' || s.tenure_years || '년 근속', s.employee_id, lp.policy_id
FROM demo_staff s CROSS JOIN leave_policy lp
WHERE lp.leave_type_id = 'DEMO_ANNUAL';

WITH demo_requests AS (
    SELECT s.employee_id,
           CASE WHEN n % 10 = 0 THEN DATE '2026-11-23' + (n / 10 - 1) % 5
                ELSE DATE '2026-01-05' + (n - 1) / 5 * 7 + (n - 1) % 5 END AS leave_day,
           CASE n % 10 WHEN 0 THEN 'PENDING' WHEN 1 THEN 'REJECTED' WHEN 2 THEN 'CANCELED'
                       ELSE 'APPROVED' END AS status
    FROM demo_staff s
)
INSERT INTO leave_request (leave_start_at, leave_end_at, requested_minutes, requested_at,
                           request_status, processed_at, policy_id, applicant_id, processor_id)
SELECT r.leave_day + TIME '09:00', r.leave_day + TIME '17:00', 480,
       (r.leave_day - 7) + TIME '09:00', r.status,
       CASE WHEN r.status IN ('APPROVED', 'REJECTED') THEN (r.leave_day - 5) + TIME '10:00' END,
       lp.policy_id, r.employee_id,
       CASE WHEN r.status IN ('APPROVED', 'REJECTED')
            THEN CASE WHEN r.employee_id = 'DEMO081' THEN 'DEMO082' ELSE 'DEMO081' END END
FROM demo_requests r CROSS JOIN leave_policy lp
WHERE lp.leave_type_id = 'DEMO_ANNUAL';

INSERT INTO annual_leave_usage (used_minutes, request_id, grant_id)
SELECT req.requested_minutes, req.request_id, g.grant_id
FROM leave_request req
JOIN annual_leave_grant g ON g.employee_id = req.applicant_id AND g.policy_id = req.policy_id
WHERE req.request_status = 'APPROVED';

DO $$
BEGIN
    IF (SELECT count(*) FROM employee) <> 100
        OR (SELECT count(*) FROM developer) <> 70
        OR (SELECT count(*) FROM non_developer) <> 30
        OR (SELECT count(*) FROM project) <> 120
        OR (SELECT count(*) FROM (
            SELECT date_trunc('month', start_on) FROM project
            GROUP BY 1 HAVING count(*) = 10
        ) months) <> 12
        OR (SELECT count(*) FROM annual_leave_grant) <> 100
        OR (SELECT count(DISTINCT employee_id) FROM annual_leave_grant) <> 100 THEN
        RAISE EXCEPTION 'The required employee, project or annual leave counts do not match.';
    END IF;
END $$;

COMMIT;
