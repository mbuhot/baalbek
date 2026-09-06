Feature: The core JSON:API surface

  `server` republishes core's domain over JSON:API, so an out-of-process
  caller reaches the same domain the in-process apps do. This is the contract
  core-api-client is generated from and the PWA consumes, so it is pinned
  here as acceptance criteria rather than left to the client's build.

  Scenario: A client creates a customer over HTTP
    When a client posts a customer named "Acme Facilities"
    Then the response status is 201
    And the response data type is "customer"
    And the created customer is readable through core

  Scenario: A customer with no name is refused
    When a client posts a customer with no name
    Then the response status is 400
    And the error points at "/data/attributes/name"

  Scenario: A client reads back a customer created in process
    Given a customer "Widgets Inc" created through core
    When a client fetches that customer
    Then the response status is 200
    And the response data type is "customer"

  Scenario: An unknown customer id is a 404, not a crash
    When a client fetches a customer id that does not exist
    Then the response status is 404

  Scenario: The OpenAPI document the client is generated from is served
    When a client fetches the OpenAPI document
    Then the response status is 200
    And the document declares a "customer" schema
