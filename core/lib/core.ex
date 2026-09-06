defmodule Core do
  @moduledoc """
  The core domain: customers, sites, jobs, and work orders (PLAN.md's
  Component inventory: "Jobs, customers, sites, work orders.").

  Uses `ash_boundary` (PLAN.md's "Boundary enforcement, in-app and
  cross-app" section) instead of a hand-rolled `use Boundary`, so `exports`
  derives from the domain DSL: `Core.Customer`, `Core.Site`, `Core.Job`,
  and `Core.WorkOrder` are each public because they get a domain-level
  `define` below. `Core.Data` (a nested Ecto-Repo sub-boundary) stays
  reachable as a direct child sub-boundary, with no explicit `deps` entry
  needed.
  """

  use Ash.Domain,
    otp_app: :core,
    extensions: [AshBoundary]

  resources do
    resource Core.Customer do
      define :create_customer, action: :create
      define :get_customer, action: :read, get_by: [:id]
      define :list_customers, action: :read
      define :update_customer, action: :update
      define :destroy_customer, action: :destroy
    end

    resource Core.Site do
      define :create_site, action: :create
      define :get_site, action: :read, get_by: [:id]
      define :list_sites, action: :read
      define :update_site, action: :update
      define :destroy_site, action: :destroy
    end

    resource Core.Job do
      define :create_job, action: :create
      define :get_job, action: :read, get_by: [:id]
      define :list_jobs, action: :read
      define :update_job, action: :update
      define :destroy_job, action: :destroy
    end

    resource Core.WorkOrder do
      define :create_work_order, action: :create
      define :get_work_order, action: :read, get_by: [:id]
      define :list_work_orders, action: :read
      define :update_work_order, action: :update
      define :destroy_work_order, action: :destroy
    end
  end
end
