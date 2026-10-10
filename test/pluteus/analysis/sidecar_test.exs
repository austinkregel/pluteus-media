defmodule Pluteus.Analysis.SidecarTest do
  @moduledoc """
  The analysing sidecar, over its real HTTP interface: spec-04 §8.2, §8.3 and
  criteria 22 and 31.

  The sidecar runs as its own service, which the app service depends on.
  """

  use Pluteus.DataCase, async: true

  import Pluteus.IngestFixtures

  alias Pluteus.Analysis
  alias Pluteus.Analysis.Native
  alias Pluteus.Analysis.Sidecar
  alias Pluteus.Annotations
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Normalize
  alias Pluteus.Ingest.Place
  alias Pluteus.Principals
  alias Pluteus.Storage
  alias Pluteus.StorageFixtures

  @t0 ~U[2026-09-18 12:00:00.000000Z]

  setup do
    _system = Principals.system!()
    %{inbox: inbox!()}
  end

  test "it describes itself without analysing anything" do
    assert {:ok, %{name: "pluteus-sidecar", version: version, schema_version: 1}} =
             Sidecar.describe()

    assert version =~ "librosa"
  end

  test "it measures what the native tool does not, by name", %{inbox: inbox} do
    ingest!(inbox, %{"a.flac" => media!(:flac, duration: 5)})
    [input] = Analysis.inputs()
    {:ok, description} = Analysis.describe(Sidecar)

    {:ok, derivation} = Analysis.analyse(Sidecar, input, description)

    [annotation] =
      Enum.filter(Annotations.current_on(input.input_id), &(&1.body_type == "measurements"))

    m = annotation.body

    assert derivation.input_id == input.input_id

    {strongest, _} =
      m
      |> Enum.filter(fn {name, _} -> String.starts_with?(name, "cqt_chroma_") end)
      |> Enum.max_by(&elem(&1, 1))

    assert strongest == "cqt_chroma_a"
    assert m["key_pitch_class"] in 0..11
    assert m["key_mode_major"] in [0, 1]
    assert is_number(m["tempo_bpm"])
    assert is_integer(m["beat_count"])
    assert is_binary(m["acoustic_fingerprint"]) and m["acoustic_fingerprint"] != ""
    assert_in_delta m["fingerprint_duration_s"], 5.0, 0.1
  end

  test "a path outside its storage roots is refused as a permanent failure" do
    assert {:error, :permanent, %{"detail" => %{"refused" => _}}} =
             Sidecar.analyse(%{
               path: "/etc/passwd",
               stream_index: nil,
               start_ms: nil,
               end_ms: nil
             })
  end

  test "bytes that do not decode are a permanent failure" do
    location = StorageFixtures.stored!("noise.flac", undecodable(500))

    assert {:error, :permanent, %{"detail" => %{"undecodable" => _}}} =
             Sidecar.analyse(%{
               path: Storage.path(location),
               stream_index: nil,
               start_ms: nil,
               end_ms: nil
             })
  end

  describe "22. The native and sidecar tools' measurements of one input both stand" do
    test "each names its own tool and version", %{inbox: inbox} do
      ingest!(inbox, %{"a.flac" => media!(:flac, duration: 3)})
      [input] = Analysis.inputs()

      for tool <- [Native, Sidecar] do
        {:ok, description} = Analysis.describe(tool)
        {:ok, _} = Analysis.analyse(tool, input, description)
      end

      provenance =
        input.input_id
        |> Annotations.current_on()
        |> Enum.filter(&(&1.body_type == "measurements"))
        |> Enum.map(&Annotations.present(&1.id).provenance)
        |> Enum.map(&{&1.tool, &1.version})
        |> Enum.sort()

      {:ok, %{version: sidecar_version}} = Sidecar.describe()
      assert provenance == [{"pluteus-native", "1"}, {"pluteus-sidecar", sidecar_version}]
    end
  end

  describe "31. The sidecar holds no database credentials and cannot write to storage" do
    setup do
      %{service: sidecar_service(File.read!(Path.expand("../../../docker-compose.yml", __DIR__)))}
    end

    test "it is given nothing that names or reaches the database", %{service: service} do
      for secret <- ~w(DATABASE POSTGRES PGPASSWORD PGUSER password db:5432) do
        refute service =~ secret
      end

      assert service =~ ~r/networks:\n\s+- analysis\n/
      refute service =~ ~r/-\s+default/
    end

    test "its network routes nowhere beyond the containers on it" do
      compose = File.read!(Path.expand("../../../docker-compose.yml", __DIR__))

      assert compose =~ ~r/\n  analysis:\n(?:\s+#.*\n)*\s+internal: true\n/
    end

    test "every storage mount is read-only and its own filesystem is too", %{service: service} do
      mounts = Regex.scan(~r/^\s+- (\.\/[^\n]+)$/m, service) |> Enum.map(&List.last/1)

      assert [_ | _] = mounts
      assert Enum.all?(mounts, &String.ends_with?(&1, ":ro"))
      assert service =~ "read_only: true"
    end
  end

  # The block of the compose file describing the sidecar service: from its key
  # to the next key at the same indentation.
  defp sidecar_service(compose) do
    [_, block] = Regex.run(~r/\n  sidecar:\n((?:    .*\n|\s*\n)+)/, compose)
    block
  end

  defp ingest!(inbox, files) do
    for {path, bytes} <- files, do: drop!(inbox, path, bytes)
    ids = inbox |> acquire_settled!(@t0) |> acquired()
    Place.place_due(inbox)
    Normalize.normalize_due(fn _class -> nil end)

    ids
    |> Enum.map(&Ingest.get_acquisition!/1)
    |> Enum.map(&Repo.get!(DigitalItem, &1.digital_item_id))
  end
end
