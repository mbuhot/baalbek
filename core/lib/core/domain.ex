defmodule Core.Domain do
  @moduledoc """
  Ash domain grouping `core`'s resources (seed.md §4, "Domain model:
  declarative Ash resources").
  """

  use Ash.Domain,
    otp_app: :core

  resources do
    resource Core.Customer
    resource Core.Site
    resource Core.Job
    resource Core.WorkOrder
  end
end
