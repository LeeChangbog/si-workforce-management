package kr.ac.dbdesign.workforce.dashboard;

import java.time.LocalDate;
import java.util.List;
import java.util.Objects;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DashboardService {

    private static final String SUMMARY_SQL = """
            SELECT
                (SELECT COUNT(*) FROM employee) AS employee_count,
                (SELECT COUNT(*) FROM project) AS project_count,
                (SELECT COUNT(*) FROM project_evaluation) AS evaluation_count,
                (SELECT COUNT(*) FROM leave_request) AS leave_request_count
            """;

    private static final String PROJECTS_SQL = """
            SELECT p.project_id, p.project_name, c.client_name,
                   p.start_on, p.end_on, p.project_status
              FROM project p
              JOIN client c ON c.client_id = p.client_id
             ORDER BY p.start_on DESC, p.project_id DESC
             LIMIT 20
            """;

    private final JdbcTemplate jdbcTemplate;

    public DashboardService(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @Transactional(readOnly = true)
    public DashboardView loadDashboard() {
        DashboardSummary summary = Objects.requireNonNull(
                jdbcTemplate.queryForObject(SUMMARY_SQL, (rs, rowNum) -> new DashboardSummary(
                        rs.getLong("employee_count"),
                        rs.getLong("project_count"),
                        rs.getLong("evaluation_count"),
                        rs.getLong("leave_request_count"))),
                "현황 집계 조회 결과가 없습니다.");

        List<ProjectOverview> projects = jdbcTemplate.query(PROJECTS_SQL, (rs, rowNum) ->
                new ProjectOverview(
                        rs.getLong("project_id"),
                        rs.getString("project_name"),
                        rs.getString("client_name"),
                        rs.getObject("start_on", LocalDate.class),
                        rs.getObject("end_on", LocalDate.class),
                        rs.getString("project_status")));

        return new DashboardView(summary, List.copyOf(projects));
    }

    public record DashboardView(DashboardSummary summary, List<ProjectOverview> projects) {
    }

    public record DashboardSummary(
            long employeeCount,
            long projectCount,
            long evaluationCount,
            long leaveRequestCount) {
    }

    public record ProjectOverview(
            long projectId,
            String projectName,
            String clientName,
            LocalDate startOn,
            LocalDate endOn,
            String status) {

        public String statusLabel() {
            return switch (status) {
                case "PLANNED" -> "예정";
                case "IN_PROGRESS" -> "진행 중";
                case "COMPLETED" -> "완료";
                case "CANCELED" -> "취소";
                default -> status;
            };
        }
    }
}
