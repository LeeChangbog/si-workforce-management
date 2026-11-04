package kr.ac.dbdesign.workforce;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;

import java.sql.SQLException;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowable;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE, properties = {
        "spring.datasource.url=jdbc:h2:mem:schema_integrity;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1",
        "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.datasource.username=sa",
        "spring.datasource.password=",
        "spring.flyway.enabled=true"
})
@Transactional
class SchemaIntegrationTest {

    private static final AtomicLong IDS = new AtomicLong(900_000);

    @Autowired
    JdbcTemplate jdbc;

    @Test
    void flywayCreatesTheWholeModelIncludingBothSubtypeFamilies() {
        var tables = jdbc.queryForList("""
                select lower(table_name) from information_schema.tables
                where lower(table_schema) = 'public'
                """, String.class);

        assertThat(tables).containsAll(Set.of(
                "employee", "developer", "non_developer", "access_role", "employee_role",
                "client", "client_contact", "project", "project_participation", "job_role",
                "assignment_history", "skill", "employee_skill", "external_career",
                "project_evaluation", "customer_evaluation", "pm_evaluation", "peer_evaluation",
                "evaluation_item", "evaluation_detail", "leave_type", "leave_policy",
                "leave_request", "annual_leave_grant", "annual_leave_usage"));
    }

    @Test
    void parentReferencesRejectOrphanProjectsAndDevelopers() {
        assertIntegrityState(() -> jdbc.update("""
                insert into project(project_id, project_name, start_on, end_on, project_status, client_id)
                values (?, 'Orphan project', date '2026-01-01', null, 'PLANNED', ?)
                """, nextId(), 8_999_999L), "23503", "23506");

        assertIntegrityState(() -> jdbc.update("""
                insert into developer(employee_id, tech_grade) values ('NO-SUCH-EMPLOYEE', 'SENIOR')
                """), "23503", "23506");
    }

    @Test
    void loginIdIsUniqueEvenWhenEmployeesHaveDifferentPrimaryKeys() {
        String first = createEmployee();
        String login = jdbc.queryForObject(
                "select login_id from employee where employee_id = ?", String.class, first);

        assertIntegrityState(() -> jdbc.update("""
                insert into employee(employee_id, employee_name, resident_no, education,
                                     hired_on, login_id, password_hash, employee_type)
                values (?, 'Second employee', ?, 'BACHELOR', date '2026-01-01', ?, 'demo-hash', 'DEV')
                """, employeeId(), "FAKE-" + UUID.randomUUID(), login), "23505");
    }

    @Test
    void participationIsUniqueForOneDeveloperInOneProject() {
        var participant = createParticipant();

        assertIntegrityState(() -> jdbc.update("""
                insert into project_participation(participation_id, employee_id, project_id)
                values (?, ?, ?)
                """, nextId(), participant.employeeId(), participant.projectId()), "23505");
    }

    @Test
    void annualLeaveGrantAcceptsPositiveMinutesAndRejectsNonpositiveAmounts() {
        var leave = createLeaveFixture();
        insertGrant(nextId(), leave, 480);

        assertIntegrityState(() -> insertGrant(nextId(), leave, -1), "23513");
        assertIntegrityState(() -> insertGrant(nextId(), leave, 0), "23513");
    }

    @Test
    void evaluationDetailUsesEvaluationAndItemTogetherAsItsPrimaryKey() {
        var target = createParticipant();
        long evaluation = nextId();
        jdbc.update("""
                insert into project_evaluation(evaluation_id, evaluation_type, evaluated_on,
                                               writing_status, target_participation_id)
                values (?, 'PEER', null, 'DRAFT', ?)
                """, evaluation, target.participationId());

        String performance = "I" + nextId();
        String communication = "I" + nextId();
        jdbc.update("insert into evaluation_item(item_id, item_name, item_description) values (?, 'Performance', 'Test item')", performance);
        jdbc.update("insert into evaluation_item(item_id, item_name, item_description) values (?, 'Communication', 'Test item')", communication);
        jdbc.update("insert into evaluation_detail(evaluation_id, item_id, score, evaluation_content) values (?, ?, 4, 'First item')", evaluation, performance);
        jdbc.update("insert into evaluation_detail(evaluation_id, item_id, score, evaluation_content) values (?, ?, 5, 'Second item')", evaluation, communication);

        assertThat(jdbc.queryForObject("select count(*) from evaluation_detail where evaluation_id = ?", Integer.class, evaluation))
                .isEqualTo(2);
        assertIntegrityState(() -> jdbc.update("""
                insert into evaluation_detail(evaluation_id, item_id, score, evaluation_content)
                values (?, ?, 3, 'Duplicate item in the same evaluation')
                """, evaluation, performance), "23505");
    }

    @Test
    void pendingLeaveAllowsNoProcessorButApprovedLeaveRequiresOne() {
        var leave = createLeaveFixture();
        long request = nextId();
        insertRequest(request, leave, "PENDING");

        assertThat(jdbc.queryForObject("select processor_id from leave_request where request_id = ?", String.class, request))
                .isNull();
        assertIntegrityState(() -> jdbc.update("""
                update leave_request set request_status = 'APPROVED' where request_id = ?
                """, request), "23513");
    }

    private String createEmployee() {
        String employee = employeeId();
        jdbc.update("""
                insert into employee(employee_id, employee_name, resident_no, education,
                                     hired_on, login_id, password_hash, employee_type)
                values (?, 'Integrity test employee', ?, 'BACHELOR', date '2026-01-01', ?, 'demo-hash', 'DEV')
                """, employee, "FAKE-" + employee, "login_" + employee);
        return employee;
    }

    private Participant createParticipant() {
        String employee = createEmployee();
        jdbc.update("insert into developer(employee_id, tech_grade) values (?, 'SENIOR')", employee);
        long client = nextId();
        long project = nextId();
        long participation = nextId();
        jdbc.update("insert into client(client_id, client_name, business_no) values (?, 'Integrity test client', ?)", client, "TEST-" + client);
        jdbc.update("""
                insert into project(project_id, project_name, start_on, end_on, project_status, client_id)
                values (?, 'Integrity test project', date '2026-01-01', date '2026-11-01', 'COMPLETED', ?)
                """, project, client);
        jdbc.update("insert into project_participation(participation_id, employee_id, project_id) values (?, ?, ?)", participation, employee, project);
        return new Participant(employee, project, participation);
    }

    private LeaveFixture createLeaveFixture() {
        String employee = createEmployee();
        String leaveType = "L" + nextId();
        long policy = nextId();
        jdbc.update("""
                insert into leave_type(leave_type_id, leave_type_name, legal_class)
                values (?, 'Integrity test annual leave', 'STATUTORY')
                """, leaveType);
        jdbc.update("""
                insert into leave_policy(policy_id, effective_from, effective_to, limit_basis,
                                         limit_quantity, limit_unit, deduct_annual_yn, counting_rule,
                                         policy_description, leave_type_id)
                values (?, date '2026-01-01', null, 'YEAR', 15, 'DAY', 'Y', 'WORKDAY', 'Integrity test policy', ?)
                """, policy, leaveType);
        return new LeaveFixture(employee, policy);
    }

    private void insertGrant(long grant, LeaveFixture leave, int minutes) {
        jdbc.update("""
                insert into annual_leave_grant(grant_id, granted_on, expires_on, granted_minutes,
                                               grant_reason, employee_id, policy_id)
                values (?, date '2026-01-01', date '2026-12-31', ?, 'Integrity test grant', ?, ?)
                """, grant, minutes, leave.employeeId(), leave.policyId());
    }

    private void insertRequest(long request, LeaveFixture leave, String status) {
        jdbc.update("""
                insert into leave_request(request_id, leave_start_at, leave_end_at, requested_minutes,
                                          requested_at, request_status, processed_at, policy_id,
                                          applicant_id, processor_id)
                values (?, timestamp '2026-11-04 09:00:00', timestamp '2026-11-04 18:00:00', 480,
                        timestamp '2026-11-01 09:00:00', ?, null, ?, ?, null)
                """, request, status, leave.policyId(), leave.employeeId());
    }

    private static void assertIntegrityState(Runnable operation, String... expectedStates) {
        Throwable thrown = catchThrowable(operation::run);
        assertThat(thrown).isInstanceOf(DataIntegrityViolationException.class);
        Throwable cause = thrown;
        while (!(cause instanceof SQLException) && cause.getCause() != null) {
            cause = cause.getCause();
        }
        assertThat(cause).isInstanceOf(SQLException.class);
        assertThat(((SQLException) cause).getSQLState()).isIn(expectedStates);
    }

    private static long nextId() {
        return IDS.incrementAndGet();
    }

    private static String employeeId() {
        return "TST" + UUID.randomUUID().toString().replace("-", "").substring(0, 12);
    }

    private record Participant(String employeeId, long projectId, long participationId) {}

    private record LeaveFixture(String employeeId, long policyId) {}
}
