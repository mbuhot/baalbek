defmodule Server.Api.Job do
  @moduledoc "JSON:API resource for `core`'s `Core.Job`, backed by `Core`'s exported job functions."

  use Ash.Resource,
    domain: Server.Api,
    extensions: [AshJsonApi.Resource]

  json_api do
    type "job"

    routes do
      base "/jobs"

      get :read
      index :read
      post :create
      patch :update
      delete :destroy
    end
  end

  actions do
    read :read do
      primary? true
      description "Lists or fetches jobs via `Core.list_jobs/0` and `Core.get_job/1`."
      manual Server.Api.Job.Manual
    end

    create :create do
      description "Requests a new job at a site via `Core.create_job/1`."
      accept [:title, :description, :status, :scheduled_at, :site_id]
      manual Server.Api.Job.Manual
    end

    update :update do
      description "Updates a job's title, description, status, or schedule via `Core.update_job/2`."
      accept [:title, :description, :status, :scheduled_at]
      manual Server.Api.Job.Manual
    end

    destroy :destroy do
      description "Removes a job via `Core.destroy_job/1`."
      manual Server.Api.Job.Manual
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string,
      allow_nil?: false,
      public?: true,
      description: "A short summary of the requested work."

    attribute :description, :string,
      public?: true,
      description: "Further detail about the requested work."

    attribute :status, :atom do
      constraints one_of: [:requested, :scheduled, :in_progress, :completed, :cancelled]
      default :requested
      allow_nil? false
      public? true
      description "The job's current stage in its lifecycle."
    end

    attribute :scheduled_at, :utc_datetime,
      public?: true,
      description: "When the job is scheduled to be carried out."

    attribute :site_id, :uuid,
      allow_nil?: false,
      public?: true,
      description: "The id of the site where this job takes place."

    attribute :inserted_at, :utc_datetime,
      writable?: false,
      public?: true,
      description: "When this job was created."

    attribute :updated_at, :utc_datetime,
      writable?: false,
      public?: true,
      description: "When this job was last updated."
  end
end
