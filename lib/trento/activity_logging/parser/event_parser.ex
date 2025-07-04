defmodule Trento.ActivityLog.Logger.Parser.EventParser do
  @moduledoc """
  Event parser extracts the event relevant information from the context.
  """

  def get_activity_actor(_, %{event: _}), do: "system"
  def get_activity_actor(_, _), do: nil

  def get_activity_metadata(_, %{event: event, metadata: metadata}) do
    %{correlation_id: correlation_id} = metadata

    event
    |> Map.from_struct()
    |> Map.delete(:version)
    |> Map.put(:correlation_id, correlation_id)
  end

  def get_activity_metadata(_, _), do: %{}
end
