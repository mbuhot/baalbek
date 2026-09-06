defmodule Server.Spec.CoreJsonApiSteps do
  @moduledoc "Steps for spec/features/core_json_api.feature, making real HTTP requests through `ServerWeb.Endpoint`."

  use Cucumber.StepDefinition
  import ExUnit.Assertions
  import Phoenix.ConnTest

  @endpoint ServerWeb.Endpoint

  step "a customer {string} created through core", %{args: [name]} = context do
    {:ok, customer} = Core.create_customer(%{name: name, email: "ops@widgets.test"})
    Map.put(context, :customer, customer)
  end

  step "a client posts a customer named {string}", %{args: [name]} = context do
    body = %{
      "data" => %{
        "type" => "customer",
        "attributes" => %{"name" => name, "email" => "ops@acme.test"}
      }
    }

    Map.put(context, :conn, post(conn(), "/api/json/core/customers", body))
  end

  step "a client posts a customer with no name", context do
    body = %{"data" => %{"type" => "customer", "attributes" => %{"email" => "ops@acme.test"}}}

    Map.put(context, :conn, post(conn(), "/api/json/core/customers", body))
  end

  step "a client fetches that customer", context do
    Map.put(context, :conn, get(conn(), "/api/json/core/customers/#{context.customer.id}"))
  end

  step "a client fetches a customer id that does not exist", context do
    Map.put(context, :conn, get(conn(), "/api/json/core/customers/#{Ecto.UUID.generate()}"))
  end

  step "a client fetches the OpenAPI document", context do
    Map.put(context, :conn, get(conn(), "/api/json/core/open_api"))
  end

  # `response/2`, not `json_response/2`: AshJsonApi's `open_api` route serves
  # the document with no content-type header, which json_response/2 rejects.
  step "the response status is {int}", %{args: [status]} = context do
    Map.put(context, :body, Jason.decode!(response(context.conn, status)))
  end

  step "the response data type is {string}", %{args: [type]} = context do
    assert context.body["data"]["type"] == type
    context
  end

  step "the error points at {string}", %{args: [pointer]} = context do
    assert Enum.any?(context.body["errors"], &(&1["source"]["pointer"] == pointer))
    context
  end

  step "the created customer is readable through core", context do
    assert {:ok, %Core.Customer{}} = Core.get_customer(context.body["data"]["id"])
    context
  end

  step "the document declares a {string} schema", %{args: [schema]} = context do
    assert Map.has_key?(context.body["components"]["schemas"], schema)
    context
  end

  defp conn do
    Phoenix.ConnTest.build_conn()
    |> Plug.Conn.put_req_header("accept", "application/vnd.api+json")
    |> Plug.Conn.put_req_header("content-type", "application/vnd.api+json")
  end
end
