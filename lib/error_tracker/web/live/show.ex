defmodule ErrorTracker.Web.Live.Show do
  @moduledoc false
  use ErrorTracker.Web, :live_view

  import Ecto.Query

  alias ErrorTracker.Error
  alias ErrorTracker.Occurrence
  alias ErrorTracker.Repo
  alias ErrorTracker.Web.Search

  @occurrences_to_navigate 50

  @impl Phoenix.LiveView
  def mount(params = %{"id" => id}, _session, socket) do
    error = Repo.get!(Error, id)

    {:ok,
     assign(socket,
       error: error,
       app: Application.fetch_env!(:error_tracker, :otp_app),
       search: Search.from_params(params)
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    occurrence =
      if occurrence_id = params["occurrence_id"] do
        socket.assigns.error
        |> Ecto.assoc(:occurrences)
        |> Repo.get!(occurrence_id)
      else
        socket.assigns.error
        |> Ecto.assoc(:occurrences)
        |> order_by([o], desc: o.id)
        |> limit(1)
        |> Repo.one()
      end

    socket =
      socket
      |> assign(occurrence: occurrence)
      |> load_related_occurrences()

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("occurrence_navigation", %{"occurrence_id" => id}, socket) do
    occurrence_path =
      occurrence_path(
        socket,
        %Occurrence{error_id: socket.assigns.error.id, id: id},
        socket.assigns.search
      )

    {:noreply, push_patch(socket, to: occurrence_path)}
  end

  @impl Phoenix.LiveView
  def handle_event("resolve", _params, socket) do
    {:ok, updated_error} = ErrorTracker.resolve(socket.assigns.error)

    {:noreply, assign(socket, :error, updated_error)}
  end

  @impl Phoenix.LiveView
  def handle_event("unresolve", _params, socket) do
    {:ok, updated_error} = ErrorTracker.unresolve(socket.assigns.error)

    {:noreply, assign(socket, :error, updated_error)}
  end

  @impl Phoenix.LiveView
  def handle_event("mute", _params, socket) do
    {:ok, updated_error} = ErrorTracker.mute(socket.assigns.error)

    {:noreply, assign(socket, :error, updated_error)}
  end

  @impl Phoenix.LiveView
  def handle_event("unmute", _params, socket) do
    {:ok, updated_error} = ErrorTracker.unmute(socket.assigns.error)

    {:noreply, assign(socket, :error, updated_error)}
  end

  defp load_related_occurrences(socket) do
    current_occurrence = socket.assigns.occurrence
    base_query = Ecto.assoc(socket.assigns.error, :occurrences)

    half_limit = floor(@occurrences_to_navigate / 2)

    previous_occurrences_query = where(base_query, [o], o.id < ^current_occurrence.id)
    next_occurrences_query = where(base_query, [o], o.id > ^current_occurrence.id)
    previous_count = Repo.aggregate(previous_occurrences_query, :count)
    next_count = Repo.aggregate(next_occurrences_query, :count)

    {previous_limit, next_limit} =
      cond do
        previous_count < half_limit and next_count < half_limit ->
          {previous_count, next_count}

        previous_count < half_limit ->
          {previous_count, @occurrences_to_navigate - previous_count - 1}

        next_count < half_limit ->
          {@occurrences_to_navigate - next_count - 1, next_count}

        true ->
          {half_limit, half_limit}
      end

    occurrences =
      [
        related_occurrences(next_occurrences_query, next_limit),
        current_occurrence,
        related_occurrences(previous_occurrences_query, previous_limit)
      ]
      |> List.flatten()
      |> Enum.reverse()

    total_occurrences =
      socket.assigns.error
      |> Ecto.assoc(:occurrences)
      |> Repo.aggregate(:count)

    next_occurrence =
      base_query
      |> where([o], o.id > ^current_occurrence.id)
      |> order_by([o], asc: o.id)
      |> limit(1)
      |> select([:id, :error_id, :inserted_at])
      |> Repo.one()

    prev_occurrence =
      base_query
      |> where([o], o.id < ^current_occurrence.id)
      |> order_by([o], desc: o.id)
      |> limit(1)
      |> select([:id, :error_id, :inserted_at])
      |> Repo.one()

    socket
    |> assign(:occurrences, occurrences)
    |> assign(:total_occurrences, total_occurrences)
    |> assign(:next, next_occurrence)
    |> assign(:prev, prev_occurrence)
  end

  defp related_occurrences(query, num_results) do
    query
    |> order_by([o], desc: o.id)
    |> select([:id, :error_id, :inserted_at])
    |> limit(^num_results)
    |> Repo.all()
  end
end
