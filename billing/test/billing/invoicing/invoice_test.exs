defmodule Billing.Invoicing.InvoiceTest do
  @moduledoc """
  Exercises `Billing.Invoicing.Invoice`'s lifecycle (draft -> issued ->
  paid, plus void) and `Billing.Invoicing.InvoiceLineItem` against the
  real `billing` schema/role. Per seed.md §7's governing principle, this
  suite must be a real proof, runnable alone, never stubbed against a fake
  data layer.
  """

  use ExUnit.Case, async: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Billing.Repo)
  end

  defp job_id, do: Ash.UUID.generate()

  defp draft_invoice!(attrs \\ %{}) do
    Billing.Invoicing.Invoice
    |> Ash.Changeset.for_create(:create, Map.merge(%{job_id: job_id()}, attrs))
    |> Ash.create!()
  end

  defp add_line_item!(invoice, attrs \\ %{}) do
    Billing.Invoicing.InvoiceLineItem
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(
        %{
          invoice_id: invoice.id,
          description: "Labour",
          quantity: 1,
          unit_amount: Decimal.new(100)
        },
        attrs
      )
    )
    |> Ash.create!()
  end

  describe "draft invoice" do
    test "create defaults to :draft status, USD currency, zero total" do
      invoice = draft_invoice!()

      assert invoice.status == :draft
      assert invoice.currency == "USD"
      assert Decimal.equal?(invoice.total_amount, Decimal.new(0))
      assert invoice.issued_at == nil
      assert invoice.paid_at == nil
    end

    test "requires a job_id" do
      assert {:error, %Ash.Error.Invalid{}} =
               Billing.Invoicing.Invoice
               |> Ash.Changeset.for_create(:create, %{})
               |> Ash.create()
    end

    test "rejects a status outside the declared set" do
      invoice = draft_invoice!()

      assert {:error, %Ash.Error.Invalid{}} =
               invoice
               |> Ash.Changeset.for_update(:issue, %{})
               |> Ash.Changeset.force_change_attribute(:status, :not_a_real_status)
               |> Ash.update()
    end
  end

  describe "line items" do
    test "can be added while the invoice is draft" do
      invoice = draft_invoice!()

      line_item =
        add_line_item!(invoice, %{description: "Parts", quantity: 2, unit_amount: Decimal.new(50)})

      assert line_item.invoice_id == invoice.id
      assert line_item.quantity == 2
      assert Decimal.equal?(line_item.unit_amount, Decimal.new(50))
    end

    test "cannot be added once the invoice is issued" do
      invoice = draft_invoice!()
      add_line_item!(invoice)
      issued = issue!(invoice)

      assert {:error, %Ash.Error.Invalid{}} =
               Billing.Invoicing.InvoiceLineItem
               |> Ash.Changeset.for_create(:create, %{
                 invoice_id: issued.id,
                 description: "Too late",
                 quantity: 1,
                 unit_amount: Decimal.new(10)
               })
               |> Ash.create()
    end

    test "loading an invoice's line items back" do
      invoice = draft_invoice!()
      add_line_item!(invoice, %{description: "Labour"})
      add_line_item!(invoice, %{description: "Parts"})

      loaded = Ash.load!(invoice, :line_items)
      assert length(loaded.line_items) == 2
    end
  end

  defp issue!(invoice) do
    invoice
    |> Ash.Changeset.for_update(:issue, %{})
    |> Ash.update!()
  end

  describe "issue" do
    test "fails with no line items" do
      invoice = draft_invoice!()

      assert {:error, %Ash.Error.Invalid{}} =
               invoice
               |> Ash.Changeset.for_update(:issue, %{})
               |> Ash.update()
    end

    test "computes total_amount from line items, sets status and issued_at" do
      invoice = draft_invoice!()
      add_line_item!(invoice, %{description: "Labour", quantity: 2, unit_amount: Decimal.new(75)})
      add_line_item!(invoice, %{description: "Parts", quantity: 3, unit_amount: Decimal.new(10)})

      issued = issue!(invoice)

      assert issued.status == :issued
      assert %DateTime{} = issued.issued_at
      # 2*75 + 3*10 = 180
      assert Decimal.equal?(issued.total_amount, Decimal.new(180))
    end

    test "cannot be issued twice" do
      invoice = draft_invoice!()
      add_line_item!(invoice)
      issued = issue!(invoice)

      assert {:error, %Ash.Error.Invalid{}} =
               issued
               |> Ash.Changeset.for_update(:issue, %{})
               |> Ash.update()
    end
  end

  describe "mark_paid" do
    test "succeeds after issue and sets paid_at" do
      invoice = draft_invoice!()
      add_line_item!(invoice)
      issued = issue!(invoice)

      paid =
        issued
        |> Ash.Changeset.for_update(:mark_paid, %{})
        |> Ash.update!()

      assert paid.status == :paid
      assert %DateTime{} = paid.paid_at
    end

    test "fails on a draft invoice (must be issued first)" do
      invoice = draft_invoice!()

      assert {:error, %Ash.Error.Invalid{}} =
               invoice
               |> Ash.Changeset.for_update(:mark_paid, %{})
               |> Ash.update()
    end
  end

  describe "void" do
    test "works from draft" do
      invoice = draft_invoice!()

      voided =
        invoice
        |> Ash.Changeset.for_update(:void, %{})
        |> Ash.update!()

      assert voided.status == :void
    end

    test "works from issued" do
      invoice = draft_invoice!()
      add_line_item!(invoice)
      issued = issue!(invoice)

      voided =
        issued
        |> Ash.Changeset.for_update(:void, %{})
        |> Ash.update!()

      assert voided.status == :void
    end

    test "fails once paid" do
      invoice = draft_invoice!()
      add_line_item!(invoice)
      issued = issue!(invoice)

      paid =
        issued
        |> Ash.Changeset.for_update(:mark_paid, %{})
        |> Ash.update!()

      assert {:error, %Ash.Error.Invalid{}} =
               paid
               |> Ash.Changeset.for_update(:void, %{})
               |> Ash.update()
    end
  end

  describe "Billing.Invoicing code interface" do
    test "draft_invoice/add_line_item/issue_invoice/mark_invoice_paid are exposed via the domain" do
      job = job_id()

      {:ok, invoice} = Billing.Invoicing.draft_invoice(job)
      assert invoice.job_id == job

      {:ok, _line_item} =
        Billing.Invoicing.add_line_item(invoice.id, "Callout fee", 1, Decimal.new(60))

      {:ok, issued} = Billing.Invoicing.issue_invoice(invoice)
      assert issued.status == :issued
      assert Decimal.equal?(issued.total_amount, Decimal.new(60))

      {:ok, paid} = Billing.Invoicing.mark_invoice_paid(issued)
      assert paid.status == :paid
    end
  end
end
