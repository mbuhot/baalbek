Feature: Raising an invoice for a completed job

  A dispatcher raises an invoice against a job that field work has completed.
  The invoice is drafted empty, charge lines are added while it is a draft,
  and issuing it freezes the total. Payment follows issue, never precedes it.

  Background:
    Given a draft invoice for a completed job

  Scenario: A new invoice starts empty and unissued
    Then the invoice status is "draft"
    And the invoice total is 0

  Scenario: Issuing freezes the total from the charge lines
    Given the invoice has the following charge lines:
      | description | quantity | unit amount |
      | Labour      | 2        | 75          |
      | Parts       | 3        | 10          |
    When the invoice is issued
    Then the invoice status is "issued"
    And the invoice total is 180

  Scenario: An invoice with no charge lines cannot be issued
    When the invoice is issued
    Then the change is rejected
    And the invoice status is "draft"

  Scenario: Charge lines cannot be added once the invoice is issued
    Given the invoice has the following charge lines:
      | description | quantity | unit amount |
      | Callout     | 1        | 60          |
    And the invoice is issued
    When a "Forgotten part" charge line of 1 at 25 is added
    Then the change is rejected
    And the invoice total is 60

  Scenario: An invoice must be issued before it can be paid
    When the invoice is paid
    Then the change is rejected
    And the invoice status is "draft"

  Scenario: A paid invoice can no longer be voided
    Given the invoice has the following charge lines:
      | description | quantity | unit amount |
      | Callout     | 1        | 60          |
    And the invoice is issued
    And the invoice is paid
    When the invoice is voided
    Then the change is rejected
    And the invoice status is "paid"
