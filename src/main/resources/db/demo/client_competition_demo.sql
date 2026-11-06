-- Optional synthetic demo data. Run ONCE after Flyway V1/V2 in a fresh demo DB.
-- Not a Flyway migration; no business demo data is loaded in production by default.
-- All people, businesses and credentials below are fictional/non-login values.
-- Expected report: exactly COI001, COI002 and COI003 (three assignment pairs).

INSERT INTO client (client_id, client_name, business_no) VALUES
(700001, 'A은행', 'DEMO-BANK-A'),
(700002, 'B은행', 'DEMO-BANK-B'),
(700003, 'C보험', 'DEMO-INS-C'),
(700004, 'D보험', 'DEMO-INS-D'),
(700005, 'E물류', 'DEMO-LOG-E'),
(700006, 'F물류', 'DEMO-LOG-F');

INSERT INTO client_competition
    (client_id_a, client_id_b, registered_on, released_on, reason) VALUES
(700001, 700002, DATE '2026-01-01', NULL, '동일 업종: 은행'),
(700003, 700004, DATE '2026-02-01', NULL, '계약상 동시수행 금지'),
(700005, 700006, DATE '2026-04-01', DATE '2026-06-30', '물류 플랫폼 경쟁 관계');

INSERT INTO employee (employee_id, employee_name, resident_no, education,
                      hired_on, login_id, password_hash, employee_type) VALUES
('COI001', '가상개발자01', 'FAKE-COI001', '학사', DATE '2025-01-01', 'demo_coi001', 'DEMO-NOT-A-LOGIN-HASH', 'DEV'),
('COI002', '가상개발자02', 'FAKE-COI002', '학사', DATE '2025-01-01', 'demo_coi002', 'DEMO-NOT-A-LOGIN-HASH', 'DEV'),
('COI003', '가상개발자03', 'FAKE-COI003', '학사', DATE '2025-01-01', 'demo_coi003', 'DEMO-NOT-A-LOGIN-HASH', 'DEV'),
('COI004', '가상개발자04', 'FAKE-COI004', '학사', DATE '2025-01-01', 'demo_coi004', 'DEMO-NOT-A-LOGIN-HASH', 'DEV'),
('COI005', '가상개발자05', 'FAKE-COI005', '학사', DATE '2025-01-01', 'demo_coi005', 'DEMO-NOT-A-LOGIN-HASH', 'DEV'),
('COI006', '가상개발자06', 'FAKE-COI006', '학사', DATE '2025-01-01', 'demo_coi006', 'DEMO-NOT-A-LOGIN-HASH', 'DEV'),
('COI007', '가상개발자07', 'FAKE-COI007', '학사', DATE '2025-01-01', 'demo_coi007', 'DEMO-NOT-A-LOGIN-HASH', 'DEV'),
('COI008', '가상개발자08', 'FAKE-COI008', '학사', DATE '2025-01-01', 'demo_coi008', 'DEMO-NOT-A-LOGIN-HASH', 'DEV'),
('COI009', '가상개발자09', 'FAKE-COI009', '학사', DATE '2025-01-01', 'demo_coi009', 'DEMO-NOT-A-LOGIN-HASH', 'DEV'),
('COI-MGMT01', '가상경영진01', 'FAKE-COI-MGMT01', '학사', DATE '2025-01-01', 'demo_coi_mgmt01', 'DEMO-NOT-A-LOGIN-HASH', 'NONDEV');

INSERT INTO developer (employee_id, tech_grade) VALUES
('COI001', 'SENIOR'), ('COI002', 'SENIOR'), ('COI003', 'SENIOR'),
('COI004', 'SENIOR'), ('COI005', 'SENIOR'), ('COI006', 'SENIOR'),
('COI007', 'SENIOR'), ('COI008', 'SENIOR'), ('COI009', 'SENIOR');

INSERT INTO non_developer (employee_id, department_name)
VALUES ('COI-MGMT01', '경영관리');

INSERT INTO employee_role (emp_role_id, granted_on, employee_id, role_id) VALUES
(740001, DATE '2026-01-01', 'COI001', 'EMPLOYEE'),
(740002, DATE '2026-01-01', 'COI002', 'EMPLOYEE'),
(740003, DATE '2026-01-01', 'COI003', 'EMPLOYEE'),
(740004, DATE '2026-01-01', 'COI004', 'EMPLOYEE'),
(740005, DATE '2026-01-01', 'COI005', 'EMPLOYEE'),
(740006, DATE '2026-01-01', 'COI006', 'EMPLOYEE'),
(740007, DATE '2026-01-01', 'COI007', 'EMPLOYEE'),
(740008, DATE '2026-01-01', 'COI008', 'EMPLOYEE'),
(740009, DATE '2026-01-01', 'COI009', 'EMPLOYEE'),
(740010, DATE '2026-01-01', 'COI-MGMT01', 'EMPLOYEE'),
(740011, DATE '2026-01-01', 'COI-MGMT01', 'MANAGEMENT');

INSERT INTO project (project_id, project_name, start_on, end_on, project_status, client_id) VALUES
(710001, 'A은행 차세대', DATE '2026-01-01', DATE '2026-12-31', 'IN_PROGRESS', 700001),
(710002, 'B은행 모바일', DATE '2026-01-01', DATE '2026-12-31', 'IN_PROGRESS', 700002),
(710003, 'C보험 청구', DATE '2026-01-01', DATE '2026-12-31', 'IN_PROGRESS', 700003),
(710004, 'D보험 계약', DATE '2026-01-01', DATE '2026-12-31', 'IN_PROGRESS', 700004),
(710005, 'E물류 배송', DATE '2026-01-01', DATE '2026-12-31', 'IN_PROGRESS', 700005),
(710006, 'F물류 창고', DATE '2026-01-01', DATE '2026-12-31', 'IN_PROGRESS', 700006);

INSERT INTO project_participation (participation_id, employee_id, project_id) VALUES
(720001, 'COI001', 710001), (720002, 'COI001', 710002),
(720003, 'COI002', 710003), (720004, 'COI002', 710004),
(720005, 'COI003', 710005), (720006, 'COI003', 710006),
(720007, 'COI004', 710001), (720008, 'COI004', 710003),
(720009, 'COI005', 710001), (720010, 'COI005', 710002),
(720011, 'COI006', 710005), (720012, 'COI006', 710006),
(720013, 'COI007', 710005), (720014, 'COI007', 710006),
(720015, 'COI008', 710001), (720016, 'COI009', 710002);

INSERT INTO assignment_history
    (assignment_id, assigned_from, assigned_to, participation_id, job_role_id) VALUES
-- Violation 1: ordinary overlap, ongoing competition.
(730001, DATE '2026-03-01', DATE '2026-03-31', 720001, 'PROGRAMMER'),
(730002, DATE '2026-03-15', DATE '2026-04-15', 720002, 'PROGRAMMER'),
-- Violation 2: the same boundary day counts as an overlap.
(730003, DATE '2026-05-01', DATE '2026-05-10', 720003, 'PROGRAMMER'),
(730004, DATE '2026-05-10', DATE '2026-05-20', 720004, 'PROGRAMMER'),
-- Violation 3: competition has since ended, but was valid during this overlap.
(730005, DATE '2026-06-20', DATE '2026-06-30', 720005, 'PROGRAMMER'),
(730006, DATE '2026-06-25', DATE '2026-07-05', 720006, 'PROGRAMMER'),
-- Allowed: overlapping assignments for noncompeting clients.
(730007, DATE '2026-03-01', DATE '2026-03-31', 720007, 'PROGRAMMER'),
(730008, DATE '2026-03-01', DATE '2026-03-31', 720008, 'PROGRAMMER'),
-- Allowed: competing clients, but disjoint assignments.
(730009, DATE '2026-07-01', DATE '2026-07-10', 720009, 'PROGRAMMER'),
(730010, DATE '2026-07-11', DATE '2026-07-20', 720010, 'PROGRAMMER'),
-- Allowed: the shared assignment period is after competition was released.
(730011, DATE '2026-07-10', DATE '2026-07-20', 720011, 'PROGRAMMER'),
(730012, DATE '2026-07-10', DATE '2026-07-20', 720012, 'PROGRAMMER'),
-- Allowed: the shared assignment period is before competition was registered.
(730013, DATE '2026-03-01', DATE '2026-03-10', 720013, 'PROGRAMMER'),
(730014, DATE '2026-03-01', DATE '2026-03-10', 720014, 'PROGRAMMER'),
-- Allowed: competing clients and matching dates, but different employees.
(730015, DATE '2026-03-01', DATE '2026-03-31', 720015, 'PROGRAMMER'),
(730016, DATE '2026-03-01', DATE '2026-03-31', 720016, 'PROGRAMMER');
