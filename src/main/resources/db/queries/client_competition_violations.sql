-- Management-only report query. A server-side MANAGEMENT authorization check
-- must precede execution when this is connected to an authenticated application.
-- This resource is not an HTTP endpoint and does not implement authorization.
-- All DATE interval endpoints are inclusive. Do not add project/assignment-ID
-- ordering filters: client_id_a < client_id_b already chooses the pair direction.
-- overlap_from/to describe the two assignment periods' intersection, as specified;
-- the WHERE clause also requires that intersection to meet the competition period.
SELECT e.employee_id, e.employee_name,
       ca.client_name AS client_a, pa.project_name AS project_a,
       ha.assigned_from AS a_from, ha.assigned_to AS a_to,
       cb.client_name AS client_b, pb.project_name AS project_b,
       hb.assigned_from AS b_from, hb.assigned_to AS b_to,
       GREATEST(ha.assigned_from, hb.assigned_from) AS overlap_from,
       LEAST(ha.assigned_to, hb.assigned_to) AS overlap_to
FROM client_competition cc
JOIN project pa               ON pa.client_id = cc.client_id_a
JOIN project pb               ON pb.client_id = cc.client_id_b
JOIN project_participation ppa ON ppa.project_id = pa.project_id
JOIN project_participation ppb ON ppb.project_id = pb.project_id
                              AND ppb.employee_id = ppa.employee_id
JOIN assignment_history ha    ON ha.participation_id = ppa.participation_id
JOIN assignment_history hb    ON hb.participation_id = ppb.participation_id
JOIN employee e               ON e.employee_id = ppa.employee_id
JOIN client ca                ON ca.client_id = cc.client_id_a
JOIN client cb                ON cb.client_id = cc.client_id_b
WHERE ha.assigned_from <= hb.assigned_to
  AND hb.assigned_from <= ha.assigned_to
  AND cc.registered_on <= LEAST(ha.assigned_to, hb.assigned_to)
  AND (cc.released_on IS NULL
       OR cc.released_on >= GREATEST(ha.assigned_from, hb.assigned_from))
ORDER BY e.employee_id, overlap_from;
