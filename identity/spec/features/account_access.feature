Feature: Technician and dispatcher account access

  Field staff sign in as technicians, office staff as dispatchers. An
  account's password is never stored, only its hash, and a changed password
  takes effect immediately: the old one stops working.

  Scenario: A technician registers and signs in
    Given a technician account for "jamie@example.test" with password "correct horse battery"
    Then the stored account never holds the password "correct horse battery"
    When "jamie@example.test" signs in with "correct horse battery"
    Then sign-in succeeds

  Scenario: A dispatcher registers and signs in
    Given a dispatcher account for "sam@example.test" with password "correct horse battery"
    When "sam@example.test" signs in with "correct horse battery"
    Then sign-in succeeds

  Scenario: The wrong password is refused
    Given a technician account for "jamie@example.test" with password "correct horse battery"
    When "jamie@example.test" signs in with "guessing my way in"
    Then sign-in fails

  Scenario: An unknown email is refused
    When "nobody@example.test" signs in with "correct horse battery"
    Then sign-in fails

  Scenario: Changing a password retires the old one
    Given a technician account for "jamie@example.test" with password "correct horse battery"
    When the account password is changed to "a different long password"
    And "jamie@example.test" signs in with "correct horse battery"
    Then sign-in fails
    When "jamie@example.test" signs in with "a different long password"
    Then sign-in succeeds

  Scenario: One email cannot hold two accounts
    Given a technician account for "jamie@example.test" with password "correct horse battery"
    When a second dispatcher account is registered for "jamie@example.test"
    Then registration is rejected

  Scenario: A password shorter than eight characters is refused
    When a technician account is registered for "short@example.test" with password "short"
    Then registration is rejected
