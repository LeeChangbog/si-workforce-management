-- External careers belong to every employee, including non-developers.
ALTER TABLE external_career DROP CONSTRAINT fk_external_career_developer;
ALTER TABLE external_career ADD CONSTRAINT fk_external_career_employee
    FOREIGN KEY (employee_id) REFERENCES employee (employee_id);
