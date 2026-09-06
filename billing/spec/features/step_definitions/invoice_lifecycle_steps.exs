defmodule Billing.Spec.InvoiceLifecycleSteps do
  @moduledoc "Steps for spec/features/invoice_lifecycle.feature, driving the real `Billing.Invoicing` code interface."

  use Cucumber.StepDefinition
  import ExUnit.Assertions

  step "a draft invoice for a completed job", context do
    {:ok, invoice} = Billing.Invoicing.draft_invoice(Ash.UUID.generate())
    Map.put(context, :invoice, invoice)
  end

  step "the invoice has the following charge lines:", context do
    for row <- context.datatable.maps do
      {:ok, _} =
        Billing.Invoicing.add_line_item(
          context.invoice.id,
          row["description"],
          String.to_integer(row["quantity"]),
          Decimal.new(row["unit amount"])
        )
    end

    context
  end

  step "a {string} charge line of {int} at {int} is added",
       %{args: [description, quantity, unit_amount]} = context do
    record(
      context,
      Billing.Invoicing.add_line_item(
        context.invoice.id,
        description,
        quantity,
        Decimal.new(unit_amount)
      )
    )
  end

  step "the invoice is issued", context do
    record(context, Billing.Invoicing.issue_invoice(context.invoice))
  end

  step "the invoice is paid", context do
    record(context, Billing.Invoicing.mark_invoice_paid(context.invoice))
  end

  step "the invoice is voided", context do
    record(context, Billing.Invoicing.void_invoice(context.invoice))
  end

  step "the change is rejected", context do
    assert {:error, %Ash.Error.Invalid{}} = context.last_result
    context
  end

  step "the invoice status is {string}", %{args: [status]} = context do
    assert context.invoice.status == String.to_existing_atom(status)
    context
  end

  step "the invoice total is {int}", %{args: [total]} = context do
    assert Decimal.equal?(context.invoice.total_amount, Decimal.new(total))
    context
  end

  # Keeps :invoice pointing at the last accepted state, so a rejected change
  # leaves the assertions reading the invoice as it stood before it.
  defp record(context, result) do
    context = Map.put(context, :last_result, result)

    case result do
      {:ok, %Billing.Invoicing.Invoice{} = invoice} -> Map.put(context, :invoice, invoice)
      _ -> context
    end
  end
end
