defmodule Pluteus.Consumption do
  @moduledoc """
  Each principal's own consumption data beyond its events: stars, ratings,
  playlists, the play queue, bookmarks and what it is playing now (spec-07
  §6.5, §6.6).

  spec-06 §6.3 forbids one principal observing another's consumption through
  any surface. As in `Pluteus.Events`, that is a property of this module's
  shape: every function takes the principal whose data it reads or writes as
  its first argument, and none reads across principals. A playlist asked for
  under a principal it does not belong to is not found, which is what the
  surfaces answer too (§4.5, §6.6).
  """

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Pluteus.Consumption.NowPlaying
  alias Pluteus.Consumption.Playlist
  alias Pluteus.Consumption.PlaylistEntry
  alias Pluteus.Consumption.PlayQueue
  alias Pluteus.Consumption.PlayQueueEntry
  alias Pluteus.Consumption.Rating
  alias Pluteus.Consumption.Star
  alias Pluteus.Events
  alias Pluteus.Events.ResumePosition
  alias Pluteus.Repo

  # Stars and ratings

  @doc """
  Stars a res. Starring one already starred keeps when it was first starred.
  """
  @spec star(Ecto.UUID.t(), Ecto.UUID.t(), DateTime.t()) ::
          {:ok, Star.t()} | {:error, Ecto.Changeset.t()}
  def star(principal_id, res_id, now \\ DateTime.utc_now()) do
    %Star{}
    |> Star.changeset(%{principal_id: principal_id, res_id: res_id, starred_at: now})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:principal_id, :res_id])
  end

  @spec unstar(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def unstar(principal_id, res_id) do
    Repo.delete_all(
      from s in Star, where: s.principal_id == ^principal_id and s.res_id == ^res_id
    )

    :ok
  end

  @doc """
  When the principal starred each of `res_ids` that it has starred.
  """
  @spec starred_at(Ecto.UUID.t(), [Ecto.UUID.t()]) :: %{Ecto.UUID.t() => DateTime.t()}
  def starred_at(principal_id, res_ids) do
    Map.new(
      Repo.all(
        from s in Star,
          where: s.principal_id == ^principal_id and s.res_id in ^res_ids,
          select: {s.res_id, s.starred_at}
      )
    )
  end

  @doc """
  Everything the principal has starred, most recent first.
  """
  @spec starred(Ecto.UUID.t()) :: [Star.t()]
  def starred(principal_id) do
    Repo.all(
      from s in Star,
        where: s.principal_id == ^principal_id,
        order_by: [desc: s.starred_at, asc: s.res_id]
    )
  end

  @doc """
  Rates a res from one to five, or clears its rating with zero, as Subsonic's
  `setRating` does.
  """
  @spec rate(Ecto.UUID.t(), Ecto.UUID.t(), integer()) ::
          {:ok, Rating.t() | nil} | {:error, Ecto.Changeset.t()}
  def rate(principal_id, res_id, 0) do
    Repo.delete_all(
      from r in Rating, where: r.principal_id == ^principal_id and r.res_id == ^res_id
    )

    {:ok, nil}
  end

  def rate(principal_id, res_id, rating) do
    %Rating{}
    |> Rating.changeset(%{principal_id: principal_id, res_id: res_id, rating: rating})
    |> Repo.insert(
      on_conflict: {:replace, [:rating, :updated_at]},
      conflict_target: [:principal_id, :res_id]
    )
  end

  @spec ratings(Ecto.UUID.t(), [Ecto.UUID.t()]) :: %{Ecto.UUID.t() => 1..5}
  def ratings(principal_id, res_ids) do
    Map.new(
      Repo.all(
        from r in Rating,
          where: r.principal_id == ^principal_id and r.res_id in ^res_ids,
          select: {r.res_id, r.rating}
      )
    )
  end

  # Playlists

  @doc """
  The principal's playlists, each with its entries in order.
  """
  @spec playlists(Ecto.UUID.t()) :: [Playlist.t()]
  def playlists(principal_id) do
    Repo.all(
      from p in Playlist,
        where: p.principal_id == ^principal_id,
        order_by: p.id,
        preload: :entries
    )
  end

  @doc """
  One of the principal's playlists with its entries in order, or nil where it
  has none by that identifier, including where another principal has one.
  """
  @spec playlist(Ecto.UUID.t(), Ecto.UUID.t()) :: Playlist.t() | nil
  def playlist(principal_id, playlist_id) do
    Repo.one(
      from p in Playlist,
        where: p.principal_id == ^principal_id and p.id == ^playlist_id,
        preload: :entries
    )
  end

  @spec create_playlist(Ecto.UUID.t(), String.t(), [Ecto.UUID.t()]) ::
          {:ok, Playlist.t()} | {:error, term()}
  def create_playlist(principal_id, name, res_ids) do
    Multi.new()
    |> Multi.insert(
      :playlist,
      Playlist.changeset(%Playlist{}, %{principal_id: principal_id, name: name})
    )
    |> Multi.run(:entries, fn repo, %{playlist: playlist} ->
      {:ok, write_entries(repo, playlist.id, res_ids)}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{playlist: playlist}} -> {:ok, playlist(principal_id, playlist.id)}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Changes one of the principal's playlists: its `name` and `comment`, and its
  entries, either replaced whole by `songs` or edited by removing the entries
  at `remove` (positions in the full list) and then appending `append`.
  """
  @spec update_playlist(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          {:ok, Playlist.t()} | {:error, :not_found | term()}
  def update_playlist(principal_id, playlist_id, changes) do
    Repo.transaction(fn ->
      case playlist(principal_id, playlist_id) do
        nil -> Repo.rollback(:not_found)
        playlist -> revise(playlist, changes)
      end
    end)
  end

  defp revise(playlist, changes) do
    current = Enum.map(playlist.entries, & &1.res_id)

    songs =
      case changes do
        %{songs: songs} ->
          songs

        _edit ->
          remove = MapSet.new(Map.get(changes, :remove, []))

          kept =
            for {res_id, position} <- Enum.with_index(current),
                position not in remove,
                do: res_id

          kept ++ Map.get(changes, :append, [])
      end

    {:ok, _} =
      playlist
      |> Playlist.changeset(Map.take(changes, [:name, :comment]))
      |> Ecto.Changeset.force_change(:updated_at, DateTime.utc_now())
      |> Repo.update()

    Repo.delete_all(from e in PlaylistEntry, where: e.playlist_id == ^playlist.id)
    write_entries(Repo, playlist.id, songs)
    playlist(playlist.principal_id, playlist.id)
  end

  defp write_entries(repo, playlist_id, res_ids) do
    {count, _} =
      repo.insert_all(
        PlaylistEntry,
        res_ids
        |> Enum.with_index()
        |> Enum.map(fn {res_id, position} ->
          %{playlist_id: playlist_id, position: position, res_id: res_id}
        end)
      )

    count
  end

  @spec delete_playlist(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, :not_found}
  def delete_playlist(principal_id, playlist_id) do
    case Repo.delete_all(
           from p in Playlist, where: p.principal_id == ^principal_id and p.id == ^playlist_id
         ) do
      {1, _} -> :ok
      {0, _} -> {:error, :not_found}
    end
  end

  # The play queue

  @doc """
  Saves the principal's play queue: `res_ids` in order, the entry at
  `current_index` current, `position_ms` into it. An empty queue clears it.
  """
  @spec save_play_queue(
          Ecto.UUID.t(),
          [Ecto.UUID.t()],
          non_neg_integer() | nil,
          non_neg_integer(),
          String.t()
        ) :: {:ok, PlayQueue.t() | nil} | {:error, :current_outside_queue}
  def save_play_queue(principal_id, [], _current_index, _position_ms, _client) do
    Repo.delete_all(from q in PlayQueue, where: q.principal_id == ^principal_id)
    {:ok, nil}
  end

  def save_play_queue(principal_id, res_ids, current_index, position_ms, client) do
    if current_index && current_index not in 0..(length(res_ids) - 1)//1 do
      {:error, :current_outside_queue}
    else
      {:ok, _} =
        Repo.transaction(fn ->
          write_queue(principal_id, res_ids, current_index, position_ms, client)
        end)

      {:ok, play_queue(principal_id)}
    end
  end

  defp write_queue(principal_id, res_ids, current_index, position_ms, client) do
    now = DateTime.utc_now()

    Repo.insert_all(
      PlayQueue,
      [
        %{
          principal_id: principal_id,
          current_index: current_index,
          position_ms: position_ms,
          changed_by: client,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: {:replace, [:current_index, :position_ms, :changed_by, :updated_at]},
      conflict_target: [:principal_id]
    )

    Repo.delete_all(from e in PlayQueueEntry, where: e.principal_id == ^principal_id)

    Repo.insert_all(
      PlayQueueEntry,
      res_ids
      |> Enum.with_index()
      |> Enum.map(fn {res_id, position} ->
        %{principal_id: principal_id, position: position, res_id: res_id}
      end)
    )
  end

  @spec play_queue(Ecto.UUID.t()) :: PlayQueue.t() | nil
  def play_queue(principal_id) do
    Repo.one(from q in PlayQueue, where: q.principal_id == ^principal_id, preload: :entries)
  end

  # Bookmarks

  @doc """
  Sets a bookmark, which is the principal's resume position with a comment
  (spec-07 §6.5).
  """
  @spec bookmark(Ecto.UUID.t(), Ecto.UUID.t(), non_neg_integer(), String.t() | nil) ::
          {:ok, ResumePosition.t()} | {:error, Ecto.Changeset.t()}
  def bookmark(principal_id, res_id, position_ms, comment) do
    %ResumePosition{}
    |> ResumePosition.changeset(%{
      principal_id: principal_id,
      res_id: res_id,
      position_ms: position_ms,
      comment: comment
    })
    |> Repo.insert(
      on_conflict: {:replace, [:position_ms, :comment, :updated_at]},
      conflict_target: [:principal_id, :res_id]
    )
  end

  @spec bookmarks(Ecto.UUID.t()) :: [ResumePosition.t()]
  def bookmarks(principal_id), do: Events.resumable(principal_id)

  @spec delete_bookmark(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, :not_found}
  def delete_bookmark(principal_id, res_id) do
    case Repo.delete_all(
           from r in ResumePosition,
             where: r.principal_id == ^principal_id and r.res_id == ^res_id
         ) do
      {1, _} -> :ok
      {0, _} -> {:error, :not_found}
    end
  end

  # Now playing, and plays

  @doc """
  Records that the principal is playing `res_id` now on `client`, replacing
  what that client was playing. This is not an event.
  """
  @spec playing(Ecto.UUID.t(), String.t(), Ecto.UUID.t(), DateTime.t()) :: :ok
  def playing(principal_id, client, res_id, now \\ DateTime.utc_now()) do
    {1, _} =
      Repo.insert_all(
        NowPlaying,
        [
          %{
            principal_id: principal_id,
            client: client,
            res_id: res_id,
            started_at: now,
            inserted_at: now,
            updated_at: now
          }
        ],
        on_conflict: {:replace, [:res_id, :started_at, :updated_at]},
        conflict_target: [:principal_id, :client]
      )

    :ok
  end

  @spec now_playing(Ecto.UUID.t()) :: [NowPlaying.t()]
  def now_playing(principal_id) do
    Repo.all(
      from n in NowPlaying,
        where: n.principal_id == ^principal_id,
        order_by: [desc: n.started_at]
    )
  end

  @doc """
  Records that the principal played `res_id` through on `client`: a playback
  event (spec-01 §11). The client is no longer playing it now.
  """
  @spec played(Ecto.UUID.t(), String.t(), Ecto.UUID.t(), DateTime.t()) ::
          {:ok, Events.Event.t()} | {:error, term()}
  def played(principal_id, client, res_id, at \\ DateTime.utc_now()) do
    Repo.transaction(fn ->
      case Events.record(principal_id, res_id, "played", at) do
        {:ok, event} ->
          Repo.delete_all(
            from n in NowPlaying,
              where:
                n.principal_id == ^principal_id and n.client == ^client and n.res_id == ^res_id
          )

          event

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end
end
