defmodule Pluteus.MusicBrainzFake do
  @moduledoc """
  MusicBrainz as a test needs it: a fixed answer per artist identifier, and no
  request leaving the machine.
  """

  @behaviour Pluteus.Ingest.MusicBrainz

  @person "a1000000-0000-4000-8000-000000000001"
  @group "a1000000-0000-4000-8000-000000000002"
  @orchestra "a1000000-0000-4000-8000-000000000003"
  @character "a1000000-0000-4000-8000-000000000004"
  @missing "a1000000-0000-4000-8000-000000000005"
  @unreachable "a1000000-0000-4000-8000-000000000006"

  def person, do: @person
  def group, do: @group
  def orchestra, do: @orchestra
  def character, do: @character
  def missing, do: @missing
  def unreachable, do: @unreachable

  @impl true
  def artist_type(@person), do: {:ok, "Person"}
  def artist_type(@group), do: {:ok, "Group"}
  def artist_type(@orchestra), do: {:ok, "Orchestra"}
  def artist_type(@character), do: {:ok, "Character"}
  def artist_type(@missing), do: {:error, :not_found}
  def artist_type(@unreachable), do: {:error, :transient, :timeout}
end
