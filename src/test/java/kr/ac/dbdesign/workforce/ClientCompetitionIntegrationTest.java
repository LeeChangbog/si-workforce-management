package kr.ac.dbdesign.workforce;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.core.io.ClassPathResource;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.jdbc.Sql;
import org.springframework.transaction.annotation.Transactional;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.sql.Date;
import java.sql.SQLException;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowable;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE, properties = {
        "spring.datasource.url=jdbc:h2:mem:competition_integrity;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1",
        "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.datasource.username=sa",
        "spring.datasource.password=",
        "spring.flyway.enabled=true"
})
@Transactional
class ClientCompetitionIntegrationTest {

    private static final AtomicLong IDS = new AtomicLong(30_000_000);
    private static final String TEST_ROLE = "COMP-TEST";
    private static final String VIOLATIONS_SQL = "db/queries/client_competition_violations.sql";

    @Autowired
    JdbcTemplate jdbc;

    @BeforeEach
    void createTestRole() {
        jdbc.update("insert into job_role(job_role_id, job_role_name) values (?, 'Competition test role')", TEST_ROLE);
    }

    @Test
    void bothSidesOfTheCompetitionPairMustReferenceExistingClients() {
        long client = createClient();

        assertIntegrityState(() -> insertCompetition(-900_001, client, "2026-01-01", null), "23503", "23506");
        assertIntegrityState(() -> insertCompetition(client, 9_000_000_000L, "2026-01-01", null), "23503", "23506");
    }

    @Test
    void canonicalPairRejectsSelfReversedAndDuplicateEntries() {
        long a = createClient();
        long b = createClient();
        insertCompetition(a, b, "2026-01-01", null);

        assertIntegrityState(() -> insertCompetition(a, a, "2026-01-01", null), "23513");
        assertIntegrityState(() -> insertCompetition(b, a, "2026-01-01", null), "23513");
        assertIntegrityState(() -> insertCompetition(a, b, "2026-02-01", null), "23505");
    }

    @Test
    void effectiveDatesAllowOpenAndSingleDayIntervalsButRejectReversedDates() {
        long a = createClient();
        long b = createClient();
        long c = createClient();
        insertCompetition(a, b, "2026-06-10", null);
        insertCompetition(a, c, "2026-06-10", "2026-06-10");

        assertThat(jdbc.queryForObject("""
                select released_on from client_competition where client_id_a = ? and client_id_b = ?
                """, LocalDate.class, a, b)).isNull();
        assertIntegrityState(() -> insertCompetition(b, c, "2026-06-10", "2026-06-09"), "23513");
    }

    @Test
    @Sql("classpath:db/demo/client_competition_demo.sql")
    void thePublishedDemoAndPublishedQueryIdentifyExactlyThreeKnownViolations() {
        assertThat(findViolations()).containsExactlyInAnyOrder(
                violation("COI001", "A은행 차세대", "B은행 모바일", "2026-03-15", "2026-03-31"),
                violation("COI002", "C보험 청구", "D보험 계약", "2026-05-10", "2026-05-10"),
                violation("COI003", "E물류 배송", "F물류 창고", "2026-06-25", "2026-06-30"));
    }

    @Test
    void assignmentOverlapOnRegistrationAndReleaseDatesIsIncluded() {
        var scenario = createScenario("2026-06-10", "2026-06-20");
        String first = createEmployee();
        String second = createEmployee();
        assign(first, scenario.a(), "2026-06-01", "2026-06-10");
        assign(first, scenario.b(), "2026-06-10", "2026-06-15");
        assign(second, scenario.a(), "2026-06-15", "2026-06-20");
        assign(second, scenario.b(), "2026-06-20", "2026-06-30");

        assertThat(findViolations()).containsExactlyInAnyOrder(
                violation(first, scenario.a().name(), scenario.b().name(), "2026-06-10", "2026-06-10"),
                violation(second, scenario.a().name(), scenario.b().name(), "2026-06-20", "2026-06-20"));
    }

    @Test
    void overlappingAssignmentsBeforeRegistrationOrAfterReleaseAreAllowed() {
        var scenario = createScenario("2026-06-10", "2026-06-20");
        String before = createEmployee();
        String after = createEmployee();
        assign(before, scenario.a(), "2026-06-01", "2026-06-09");
        assign(before, scenario.b(), "2026-06-05", "2026-06-09");
        assign(after, scenario.a(), "2026-06-21", "2026-06-30");
        assign(after, scenario.b(), "2026-06-25", "2026-06-30");

        assertThat(findViolations()).isEmpty();
    }

    @Test
    void differentEmployeesNoncompetingClientsAndSameClientProjectsAreAllowed() {
        var scenario = createScenario("2026-01-01", null);
        String first = createEmployee();
        String other = createEmployee();
        var sameClientProject = createProject(scenario.a().client());
        assign(first, scenario.a(), "2026-06-01", "2026-06-30");
        assign(first, scenario.c(), "2026-06-01", "2026-06-30");
        assign(first, sameClientProject, "2026-06-01", "2026-06-30");
        assign(other, scenario.b(), "2026-06-01", "2026-06-30");

        assertThat(findViolations()).isEmpty();
    }

    @Test
    void aGapBetweenRepeatedAssignmentsDoesNotBecomeAnArtificialOverlap() {
        var scenario = createScenario("2026-01-01", null);
        String employee = createEmployee();
        assign(employee, scenario.a(), "2026-06-01", "2026-06-05");
        assign(employee, scenario.a(), "2026-06-25", "2026-06-30");
        assign(employee, scenario.b(), "2026-06-10", "2026-06-20");
        assertThat(findViolations()).isEmpty();

        assign(employee, scenario.a(), "2026-06-12", "2026-06-13");
        assertThat(findViolations()).containsExactly(
                violation(employee, scenario.a().name(), scenario.b().name(), "2026-06-12", "2026-06-13"));
    }

    @Test
    void returnedOverlapIsTheAssignmentIntersectionAsSpecifiedByThePublishedQuery() {
        var scenario = createScenario("2026-06-10", "2026-06-20");
        String employee = createEmployee();
        assign(employee, scenario.a(), "2026-06-01", "2026-06-30");
        assign(employee, scenario.b(), "2026-06-05", "2026-06-25");

        // Competition validity filters the row; the user-specified result retains the assignment overlap.
        assertThat(findViolations()).containsExactly(
                violation(employee, scenario.a().name(), scenario.b().name(), "2026-06-05", "2026-06-25"));
    }

    @Test
    void anUnreleasedCompetitionRemainsEffectiveForLaterAssignments() {
        var scenario = createScenario("2026-01-01", null);
        String employee = createEmployee();
        assign(employee, scenario.a(), "2026-12-01", "2026-12-20");
        assign(employee, scenario.b(), "2026-12-15", "2026-12-31");

        assertThat(findViolations()).containsExactly(
                violation(employee, scenario.a().name(), scenario.b().name(), "2026-12-15", "2026-12-20"));
    }

    @Test
    void clientPairDirectionDoesNotImposeAnOrderOnProjectOrAssignmentIds() {
        long clientA = createClient();
        long clientB = createClient();
        insertCompetition(clientA, clientB, "2026-01-01", null);
        var projectB = createProject(clientB);
        var projectA = createProject(clientA);
        String employee = createEmployee();
        assign(employee, projectB, "2026-06-10", "2026-06-20");
        assign(employee, projectA, "2026-06-01", "2026-06-30");
        assertThat(projectA.id()).isGreaterThan(projectB.id());

        assertThat(findViolations()).containsExactly(
                violation(employee, projectA.name(), projectB.name(), "2026-06-10", "2026-06-20"));
    }

    private List<Violation> findViolations() {
        String sql;
        try (var stream = new ClassPathResource(VIOLATIONS_SQL).getInputStream()) {
            sql = new String(stream.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        return jdbc.query(sql, (rs, row) -> new Violation(
                rs.getString("employee_id"), rs.getString("project_a"), rs.getString("project_b"),
                rs.getDate("overlap_from").toLocalDate(), rs.getDate("overlap_to").toLocalDate()));
    }

    private Scenario createScenario(String registered, String released) {
        long a = createClient();
        long b = createClient();
        long c = createClient();
        insertCompetition(a, b, registered, released);
        return new Scenario(createProject(a), createProject(b), createProject(c));
    }

    private long createClient() {
        long id = IDS.incrementAndGet();
        jdbc.update("insert into client(client_id, client_name, business_no) values (?, ?, ?)",
                id, "Competition client " + id, "CC-" + id);
        return id;
    }

    private Project createProject(long client) {
        long id = IDS.incrementAndGet();
        String name = "Competition project " + id;
        jdbc.update("""
                insert into project(project_id, project_name, start_on, end_on, project_status, client_id)
                values (?, ?, date '2026-01-01', date '2026-12-31', 'IN_PROGRESS', ?)
                """, id, name, client);
        return new Project(id, name, client);
    }

    private String createEmployee() {
        String id = "CC" + UUID.randomUUID().toString().replace("-", "").substring(0, 12);
        jdbc.update("""
                insert into employee(employee_id, employee_name, resident_no, education,
                                     hired_on, login_id, password_hash, employee_type)
                values (?, 'Competition test employee', ?, 'BACHELOR', date '2026-01-01', ?, 'demo-hash', 'DEV')
                """, id, "FAKE-" + id, "login_" + id);
        jdbc.update("insert into developer(employee_id, tech_grade) values (?, 'SENIOR')", id);
        return id;
    }

    private void assign(String employee, Project project, String from, String through) {
        var existing = jdbc.queryForList("""
                select participation_id from project_participation where employee_id = ? and project_id = ?
                """, Long.class, employee, project.id());
        long participation;
        if (existing.isEmpty()) {
            participation = IDS.incrementAndGet();
            jdbc.update("insert into project_participation(participation_id, employee_id, project_id) values (?, ?, ?)",
                    participation, employee, project.id());
        } else {
            participation = existing.getFirst();
        }
        jdbc.update("""
                insert into assignment_history(assignment_id, assigned_from, assigned_to, participation_id, job_role_id)
                values (?, ?, ?, ?, ?)
                """, IDS.incrementAndGet(), Date.valueOf(from), Date.valueOf(through), participation, TEST_ROLE);
    }

    private void insertCompetition(long a, long b, String registered, String released) {
        jdbc.update("""
                insert into client_competition(client_id_a, client_id_b, registered_on, released_on, reason)
                values (?, ?, ?, ?, 'Independent integrity test')
                """, a, b, Date.valueOf(registered), released == null ? null : Date.valueOf(released));
    }

    private static Violation violation(String employee, String projectA, String projectB, String from, String through) {
        return new Violation(employee, projectA, projectB, LocalDate.parse(from), LocalDate.parse(through));
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

    private record Project(long id, String name, long client) {}
    private record Scenario(Project a, Project b, Project c) {}
    private record Violation(String employee, String projectA, String projectB, LocalDate from, LocalDate through) {}
}
