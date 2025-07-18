defmodule Trento.Clusters do
  @moduledoc """
  Provides a set of functions to interact with clusters.
  """

  import Ecto.Query

  require Logger
  require Trento.Clusters.Enums.ClusterType, as: ClusterType
  require Trento.Clusters.Enums.FilesystemType, as: FilesystemType
  require Trento.Clusters.Enums.ClusterEnsaVersion, as: ClusterEnsaVersion
  require Trento.Clusters.Enums.HanaArchitectureType, as: HanaArchitectureType
  require Trento.Clusters.Enums.HanaScenario, as: HanaScenario
  require Trento.Operations.Enums.ClusterOperations, as: ClusterOperations
  require Trento.Operations.Enums.ClusterHostOperations, as: ClusterHostOperations

  alias Trento.Hosts.Projections.HostReadModel

  alias Trento.SapSystems.Projections.ApplicationInstanceReadModel

  alias Trento.Clusters.Projections.ClusterReadModel

  alias Trento.Clusters.ClusterEnrichmentData

  alias Trento.Clusters.Commands.SelectChecks

  alias Trento.Clusters.ValueObjects.SapInstance

  alias Trento.SapSystems.Projections.SapSystemReadModel

  alias Trento.Infrastructure.{
    Checks,
    Operations
  }

  alias Trento.Repo

  @checkable_clusters [
    ClusterType.hana_scale_up(),
    ClusterType.hana_scale_out(),
    ClusterType.ascs_ers()
  ]

  @spec by_id(String.t()) :: {:ok, ClusterReadModel.t()} | {:error, :not_found}
  def by_id(id) do
    case Repo.get(ClusterReadModel, id) do
      %ClusterReadModel{} = cluster -> {:ok, cluster}
      nil -> {:error, :not_found}
    end
  end

  @spec get_cluster_by_id(String.t()) :: ClusterReadModel.t() | nil
  def get_cluster_by_id(id) do
    ClusterReadModel
    |> where([c], c.id == ^id and is_nil(c.deregistered_at))
    |> Repo.one()
  end

  @spec select_checks(String.t(), [String.t()]) :: :ok | {:error, any}
  def select_checks(cluster_id, checks) do
    Logger.debug("Selecting checks, cluster: #{cluster_id}")

    with {:ok, command} <- SelectChecks.new(%{cluster_id: cluster_id, checks: checks}) do
      commanded().dispatch(command)
    end
  end

  @spec request_checks_execution(String.t()) ::
          :ok | {:error, any}
  def request_checks_execution(cluster_id) do
    query =
      from(c in ClusterReadModel,
        where: is_nil(c.deregistered_at) and c.id == ^cluster_id
      )

    case Repo.one(query) do
      %ClusterReadModel{} = cluster ->
        Logger.debug("Requesting checks execution, cluster: #{cluster_id}")

        maybe_request_checks_execution(cluster)

      nil ->
        Logger.error("Requested checks execution for a non-existing cluster: #{cluster_id}")

        {:error, :not_found}
    end
  end

  @spec get_all_clusters :: [ClusterReadModel.t()]
  def get_all_clusters do
    from(c in ClusterReadModel,
      order_by: [asc: c.name, asc: c.id],
      preload: [:tags],
      where: is_nil(c.deregistered_at)
    )
    |> enrich_cluster_model_query()
    |> Repo.all()
  end

  @spec get_cluster_id_by_host_id(String.t()) :: String.t() | nil
  def get_cluster_id_by_host_id(host_id) do
    query =
      from c in ClusterReadModel,
        join: h in HostReadModel,
        on: h.cluster_id == c.id,
        where: h.id == ^host_id,
        select: c.id

    Repo.one(query)
  end

  @spec enrich_cluster_model(ClusterReadModel.t()) :: ClusterReadModel.t()
  def enrich_cluster_model(%ClusterReadModel{id: id} = cluster) do
    case Repo.get(ClusterEnrichmentData, id) do
      nil ->
        cluster

      enriched_data ->
        %ClusterReadModel{cluster | cib_last_written: enriched_data.cib_last_written}
    end
  end

  @spec request_clusters_checks_execution :: :ok | {:error, any}
  def request_clusters_checks_execution do
    query =
      from(c in ClusterReadModel,
        select: c.id,
        where: c.type in @checkable_clusters and is_nil(c.deregistered_at)
      )

    query
    |> Repo.all()
    |> Enum.each(fn cluster_id ->
      case request_checks_execution(cluster_id) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error(
            "Failed to request checks execution, cluster: #{cluster_id}, reason: #{reason}"
          )
      end
    end)
  end

  @spec update_cib_last_written(String.t(), String.t()) :: {:ok, Ecto.Schema.t()} | {:error, any}
  def update_cib_last_written(cluster_id, cib_last_written) do
    case Repo.get(ClusterEnrichmentData, cluster_id) do
      nil -> %ClusterEnrichmentData{cluster_id: cluster_id}
      enriched_cluster -> enriched_cluster
    end
    |> ClusterEnrichmentData.changeset(%{cib_last_written: cib_last_written})
    |> Repo.insert_or_update()
  end

  @spec maintenance?(ClusterReadModel.t()) :: boolean()
  def maintenance?(%ClusterReadModel{details: %{maintenance_mode: maintenance_mode}}) do
    maintenance_mode
  end

  @spec resource_managed?(ClusterReadModel.t(), String.t()) :: boolean()
  def resource_managed?(%ClusterReadModel{type: type, details: details}, resource_id)
      when type in [ClusterType.hana_scale_up(), ClusterType.hana_scale_out()] do
    has_resource_managed?(details, resource_id)
  end

  def resource_managed?(
        %ClusterReadModel{type: ClusterType.ascs_ers(), details: %{sap_systems: sap_systems}},
        resource_id
      ) do
    Enum.any?(sap_systems, &has_resource_managed?(&1, resource_id))
  end

  def resource_managed?(_, _), do: false

  @spec get_sap_instances_by_host_id(String.t()) :: [SapInstance.t()]
  def get_sap_instances_by_host_id(host_id) do
    query =
      from c in ClusterReadModel,
        join: h in HostReadModel,
        on: h.cluster_id == c.id,
        where: h.id == ^host_id,
        select: c.sap_instances

    case Repo.one(query) do
      nil -> []
      sap_instances -> sap_instances
    end
  end

  @spec get_cluster_hosts(String.t()) :: [HostReadModel.t()]
  def get_cluster_hosts(cluster_id) do
    query =
      from c in ClusterReadModel,
        where: c.id == ^cluster_id,
        preload: [:hosts]

    case Repo.one(query) do
      nil -> []
      cluster -> Map.get(cluster, :hosts, [])
    end
  end

  @spec request_operation(atom(), String.t(), map()) :: {:ok, String.t()} | {:error, any}
  def request_operation(operation, cluster_id, params)
      when operation in ClusterOperations.values() do
    operation_id = UUID.uuid4()

    # Design decision: in order to keep things simpler, the first node is selected as designated
    # controller (is_dc) on this function. It does not matter in which cluster node the commands
    # are executed, as long as they are executed only in one node.
    # It's fine as long as we don't find a strictly required action where running in real DC is
    # mandatory. But none of the SUSE best practices guides suggest that.
    targets =
      cluster_id
      |> get_cluster_hosts()
      |> Enum.with_index()
      |> Enum.map(fn {%{id: host_id}, index} ->
        arguments = Map.put(params, :is_dc, index == 0)
        %{agent_id: host_id, arguments: arguments}
      end)

    case Operations.request_operation(
           operation_id,
           cluster_id,
           Operations.map_operation(operation),
           targets
         ) do
      :ok -> {:ok, operation_id}
      error -> error
    end
  end

  def request_operation(_, _, _), do: {:error, :operation_not_found}

  @spec request_host_operation(atom(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, any}
  def request_host_operation(operation, cluster_id, host_id)
      when operation in ClusterHostOperations.values() do
    operation_id = UUID.uuid4()

    case Operations.request_operation(
           operation_id,
           cluster_id,
           Operations.map_operation(operation),
           [%{agent_id: host_id, arguments: %{}}]
         ) do
      :ok -> {:ok, operation_id}
      error -> error
    end
  end

  def request_host_operation(_, _, _), do: {:error, :operation_not_found}

  defp has_resource_managed?(%{nodes: nodes}, resource_id) do
    Enum.any?(nodes, fn %{resources: resources} ->
      Enum.find_value(resources, false, fn %{parent: parent} = resource ->
        managed?(resource, resource_id) or managed?(parent, resource_id)
      end)
    end)
  end

  defp managed?(%{id: resource_id, managed: managed}, resource_id), do: managed
  defp managed?(_, _), do: false

  defp commanded,
    do: Application.fetch_env!(:trento, Trento.Commanded)[:adapter]

  @spec enrich_cluster_model_query(Ecto.Query.t()) :: Ecto.Query.t()
  defp enrich_cluster_model_query(query) do
    query
    |> join(:left, [c], e in ClusterEnrichmentData, on: c.id == e.cluster_id)
    |> select_merge([c, e], %{cib_last_written: e.cib_last_written})
  end

  defp maybe_request_checks_execution(%ClusterReadModel{selected_checks: []}),
    do: {:error, :no_checks_selected}

  defp maybe_request_checks_execution(
         %ClusterReadModel{
           id: cluster_id,
           provider: provider,
           type: ClusterType.ascs_ers(),
           sap_instances: sap_instances,
           selected_checks: selected_checks
         } = cluster
       ) do
    sap_instance_sids = SapInstance.get_sap_instance_sids(sap_instances)

    clustered_sap_instances =
      sap_instances
      |> Enum.map(& &1.instance_number)
      |> Enum.uniq()

    hosts_data =
      Repo.all(
        from h in HostReadModel,
          join: a in ApplicationInstanceReadModel,
          on: h.id == a.host_id,
          where:
            h.cluster_id == ^cluster_id and is_nil(h.deregistered_at) and
              a.sid in ^sap_instance_sids and a.instance_number in ^clustered_sap_instances,
          select: %{host_id: h.id, sap_system_id: a.sap_system_id}
      )

    aggregated_ensa_version =
      hosts_data
      |> Enum.map(fn %{sap_system_id: sap_system_id} -> sap_system_id end)
      |> Enum.uniq()
      |> get_cluster_ensa_version()

    env = %Checks.ClusterExecutionEnv{
      provider: provider,
      cluster_type: ClusterType.ascs_ers(),
      ensa_version: aggregated_ensa_version,
      filesystem_type: get_filesystem_type(cluster)
    }

    Checks.request_execution(
      UUID.uuid4(),
      cluster_id,
      env,
      hosts_data,
      selected_checks,
      :cluster
    )
  end

  defp maybe_request_checks_execution(%ClusterReadModel{
         id: cluster_id,
         provider: provider,
         type: ClusterType.hana_scale_up(),
         selected_checks: selected_checks,
         details: details
       }) do
    hosts_data =
      Repo.all(
        from h in HostReadModel,
          select: %{host_id: h.id},
          where: h.cluster_id == ^cluster_id and is_nil(h.deregistered_at)
      )

    env = %Checks.ClusterExecutionEnv{
      provider: provider,
      cluster_type: ClusterType.hana_scale_up(),
      architecture_type: parse_architecture_type(details),
      hana_scenario: parse_hana_scenario(details)
    }

    Checks.request_execution(
      UUID.uuid4(),
      cluster_id,
      env,
      hosts_data,
      selected_checks,
      :cluster
    )
  end

  defp maybe_request_checks_execution(%ClusterReadModel{
         id: cluster_id,
         provider: provider,
         type: cluster_type,
         selected_checks: selected_checks,
         details: details
       }) do
    hosts_data =
      Repo.all(
        from h in HostReadModel,
          select: %{host_id: h.id},
          where: h.cluster_id == ^cluster_id and is_nil(h.deregistered_at)
      )

    env = %Checks.ClusterExecutionEnv{
      provider: provider,
      cluster_type: cluster_type,
      architecture_type: parse_architecture_type(details)
    }

    Checks.request_execution(
      UUID.uuid4(),
      cluster_id,
      env,
      hosts_data,
      selected_checks,
      :cluster
    )
  end

  defp maybe_request_checks_execution(error), do: error

  defp get_filesystem_type(%ClusterReadModel{} = cluster) do
    filesystems_list =
      cluster
      |> Map.get(:details, %{})
      |> Map.get(:sap_systems, [])
      |> Enum.map(fn %{filesystem_resource_based: filesystem_resource_based} ->
        filesystem_resource_based
      end)
      |> Enum.uniq()

    case filesystems_list do
      [true] -> FilesystemType.resource_managed()
      [false] -> FilesystemType.simple_mount()
      _ -> FilesystemType.mixed_fs_types()
    end
  end

  @spec get_cluster_ensa_version([String.t()]) :: ClusterEnsaVersion.t()
  defp get_cluster_ensa_version(sap_system_ids) do
    ensa_versions =
      Repo.all(
        from(s in SapSystemReadModel,
          select: s.ensa_version,
          where: s.id in ^sap_system_ids and is_nil(s.deregistered_at),
          distinct: true
        )
      )

    case ensa_versions do
      [ensa_version] -> ensa_version
      _ -> ClusterEnsaVersion.mixed_versions()
    end
  end

  defp parse_architecture_type(%{architecture_type: "angi"}),
    do: HanaArchitectureType.angi()

  defp parse_architecture_type(_), do: HanaArchitectureType.classic()

  defp parse_hana_scenario(%{hana_scenario: "performance_optimized"}),
    do: HanaScenario.performance_optimized()

  defp parse_hana_scenario(%{hana_scenario: "cost_optimized"}),
    do: HanaScenario.cost_optimized()

  defp parse_hana_scenario(_), do: HanaScenario.unknown()
end
