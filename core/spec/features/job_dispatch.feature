Feature: Dispatching field-service work

  A dispatcher records a customer, the site the customer wants work at, and
  a job at that site. The job is scheduled, then carried out as one or more
  work orders. Every job belongs to a site, and every work order to a job —
  work is never recorded free-floating.

  Background:
    Given a customer "Acme Facilities"
    And the customer has a site "Warehouse 1"

  Scenario: A new job starts as requested
    When a job "Fix conveyor" is requested at "Warehouse 1"
    Then the job status is "requested"
    And the job belongs to the site "Warehouse 1"

  Scenario: A requested job is scheduled, worked, and completed
    Given a job "Fix conveyor" is requested at "Warehouse 1"
    When the job is moved to "scheduled"
    And the job is moved to "in_progress"
    And the job is moved to "completed"
    Then the job status is "completed"

  Scenario: A status outside the known set is refused
    Given a job "Fix conveyor" is requested at "Warehouse 1"
    When the job is moved to "teleported"
    Then the change is rejected
    And the job status is "requested"

  Scenario: A job is carried out over more than one visit
    Given a job "Fix conveyor" is requested at "Warehouse 1"
    When the following work orders are opened against the job:
      | summary         |
      | Initial visit   |
      | Follow-up visit |
    Then the job has 2 work orders
    And every work order status is "open"

  Scenario: Work cannot be recorded without a job
    When a work order "Orphan visit" is opened against no job
    Then the change is rejected
