defmodule Server.Api do
  @moduledoc """
  The JSON:API-exposed domain for `core`'s Customer/Site/Job/WorkOrder resources.

  Each resource here is a thin Ash resource of its own, backed by
  `Ash.DataLayer.Simple` (Ash's default for resources whose actions are all
  manual — see `Ash.DataLayer.Simple`'s docs). Every action delegates to
  `core`'s own exported domain functions (`Core.create_customer/1`, etc.),
  never to `Core`'s internals — see each resource's `Manual` module.
  """

  use Ash.Domain, extensions: [AshJsonApi.Domain]

  resources do
    resource Server.Api.Customer
    resource Server.Api.Site
    resource Server.Api.Job
    resource Server.Api.WorkOrder
  end
end
