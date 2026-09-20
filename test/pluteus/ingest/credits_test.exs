defmodule Pluteus.Ingest.CreditsTest do
  @moduledoc """
  Credits and their resolution to agents: spec-04 §6.4 and criteria 13, 32 and
  33.
  """

  use Pluteus.DataCase, async: true

  import Pluteus.IngestFixtures

  alias Pluteus.Catalog
  alias Pluteus.Catalog.Credit
  alias Pluteus.Catalog.DigitalItem
  alias Pluteus.Catalog.Res
  alias Pluteus.Ingest
  alias Pluteus.Ingest.Credits
  alias Pluteus.Ingest.Finding
  alias Pluteus.Ingest.MusicBrainz
  alias Pluteus.Ingest.MusicBrainzArtist
  alias Pluteus.Ingest.Place
  alias Pluteus.MusicBrainzFake, as: Fake
  alias Pluteus.Principals

  @t0 ~U[2026-09-18 12:00:00.000000Z]

  setup do
    _system = Principals.system!()
    %{inbox: inbox!()}
  end

  describe "reading credits from tags" do
    test "artists are preferred to the artist display string, and pair with identifiers" do
      tags = %{
        "artist" => "Miles Davis & John Coltrane",
        "artists" => "Miles Davis;John Coltrane",
        "musicbrainz_artistid" => "#{Fake.person()};#{Fake.group()}"
      }

      assert Credits.from_tags(tags, :artist) ==
               [{"Miles Davis", Fake.person()}, {"John Coltrane", Fake.group()}]
    end

    test "counts that disagree pair no identifier with any name" do
      tags = %{
        "artist" => "Miles Davis & John Coltrane",
        "musicbrainz_artistid" => "#{Fake.person()};#{Fake.group()}"
      }

      assert Credits.from_tags(tags, :artist) == [{"Miles Davis & John Coltrane", nil}]
    end

    test "an identifier that is not one pairs none" do
      tags = %{"artist" => "Miles Davis", "musicbrainz_artistid" => "not-an-identifier"}

      assert Credits.from_tags(tags, :artist) == [{"Miles Davis", nil}]
    end

    test "album artists pair with the album artist identifier" do
      tags = %{"album_artist" => "Various Artists", "musicbrainz_albumartistid" => Fake.group()}

      assert Credits.from_tags(tags, :album_artist) == [{"Various Artists", Fake.group()}]
    end
  end

  describe "13. Placement records credits as the tags state them" do
    test "the track's artists on its work, the album artists on the release's", %{inbox: inbox} do
      [track] =
        ingest!(inbox, %{
          "KoB/01.flac" =>
            media!(:flac,
              tags: %{
                "album" => "Kind of Blue",
                "album_artist" => "Miles Davis",
                "artist" => "Miles Davis",
                "track" => "1",
                "MUSICBRAINZ_ARTISTID" => Fake.person()
              }
            )
        })

      assert [
               %Credit{
                 role: :artist,
                 name: "Miles Davis",
                 musicbrainz_id: id,
                 agent_id: artist_id,
                 agent_kind: :artist,
                 provenance: :automatic
               }
             ] =
               Credits.credits_of(work_of(track))

      assert id == Fake.person()
      assert Repo.get!(Res, artist_id).kind == :artist

      assert [%Credit{role: :album_artist, name: "Miles Davis", musicbrainz_id: nil}] =
               Credits.credits_of(release_work_of(track))
    end
  end

  describe "32. Every credit names an artist once placed, narrowed by its MusicBrainz type" do
    test "Person is a person, Group and Orchestra collective agents, Character an artist", %{
      inbox: inbox
    } do
      placed =
        ingest!(inbox, %{
          "a.flac" =>
            track(%{"artist" => "Miles Davis", "MUSICBRAINZ_ARTISTID" => Fake.person()}),
          "b.flac" =>
            track(
              %{"artist" => "Miles Davis Quintet", "MUSICBRAINZ_ARTISTID" => Fake.group()},
              500
            ),
          "c.flac" =>
            track(
              %{
                "artist" => "Berliner Philharmoniker",
                "MUSICBRAINZ_ARTISTID" => Fake.orchestra()
              },
              600
            ),
          "d.flac" =>
            track(%{"artist" => "Hatsune Miku", "MUSICBRAINZ_ARTISTID" => Fake.character()}, 700)
        })

      before_lookup =
        Map.new(placed, fn track ->
          [credit] = Credits.credits_of(work_of(track))
          {credit.name, Repo.get!(Res, credit.agent_id).kind}
        end)

      assert before_lookup == %{
               "Miles Davis" => :artist,
               "Miles Davis Quintet" => :artist,
               "Berliner Philharmoniker" => :artist,
               "Hatsune Miku" => :artist
             }

      {:ok, _} = Credits.resolve_due(client: Fake, interval_ms: 0)

      kinds =
        Map.new(placed, fn track ->
          [credit] = Credits.credits_of(work_of(track))
          {credit.name, Repo.get!(Res, credit.agent_id).kind}
        end)

      assert kinds == %{
               "Miles Davis" => :person,
               "Miles Davis Quintet" => :collective_agent,
               "Berliner Philharmoniker" => :collective_agent,
               "Hatsune Miku" => :artist
             }
    end

    test "the artist is credited as creator and named, before anything is asked", %{inbox: inbox} do
      [track] =
        ingest!(inbox, %{
          "a.flac" => track(%{"artist" => "Miles Davis", "MUSICBRAINZ_ARTISTID" => Fake.person()})
        })

      [credit] = Credits.credits_of(work_of(track))
      assert Catalog.creators_of(work_of(track)) == [credit.agent_id]

      nomens = Catalog.nomens_for(credit.agent_id)

      assert Enum.any?(
               nomens,
               &(&1.nomen_string == "Miles Davis" and &1.provenance == :automatic)
             )

      assert Enum.any?(nomens, &(&1.nomen_string == Fake.person() and &1.scheme == "musicbrainz"))

      {:ok, _} = Credits.resolve_due(client: Fake, interval_ms: 0)

      assert Catalog.creators_of(work_of(track)) == [credit.agent_id]
      assert Repo.get!(Res, credit.agent_id).kind == :person
    end

    test "an artist for a name and an artist for an identifier are never one artist",
         %{inbox: inbox} do
      [tagged, untagged] =
        ingest!(inbox, %{
          "a.flac" =>
            track(%{"artist" => "Miles Davis", "MUSICBRAINZ_ARTISTID" => Fake.person()}),
          "b.flac" => track(%{"artist" => "Miles Davis"}, 500)
        })

      [with_identifier] = Credits.credits_of(work_of(tagged))
      [by_name_only] = Credits.credits_of(work_of(untagged))

      refute with_identifier.agent_id == by_name_only.agent_id
      assert Catalog.nomens_for(by_name_only.agent_id) |> Enum.map(& &1.scheme) == [nil]
    end

    test "two credits of one name with no identifier are one artist", %{inbox: inbox} do
      [first, second] =
        ingest!(inbox, %{
          "a.flac" => track(%{"artist" => "Aya Higuchi"}),
          "b.flac" => track(%{"artist" => "Aya Higuchi"}, 500)
        })

      [one] = Credits.credits_of(work_of(first))
      [two] = Credits.credits_of(work_of(second))

      assert one.agent_id == two.agent_id
      assert Repo.get!(Res, one.agent_id).kind == :artist
    end

    test "one identifier on many tracks, placed before and after it resolved, is one agent",
         %{inbox: inbox} do
      [first] =
        ingest!(inbox, %{
          "a.flac" => track(%{"artist" => "Miles Davis", "MUSICBRAINZ_ARTISTID" => Fake.person()})
        })

      {:ok, [{_, :narrowed}]} = Credits.resolve_due(client: Fake, interval_ms: 0)

      [second] =
        ingest!(
          inbox,
          %{
            "b.flac" =>
              track(%{"artist" => "Miles Davis", "MUSICBRAINZ_ARTISTID" => Fake.person()}, 500)
          },
          DateTime.add(@t0, 3_600)
        )

      assert {:ok, []} = Credits.resolve_due(client: Fake, interval_ms: 0)

      [one] = Credits.credits_of(work_of(first))
      [two] = Credits.credits_of(work_of(second))
      assert one.agent_id == two.agent_id
      assert [_] = Repo.all(MusicBrainzArtist)
    end

    test "a credit with no identifier names an artist, and asks MusicBrainz nothing",
         %{inbox: inbox} do
      [track] = ingest!(inbox, %{"a.flac" => track(%{"artist" => "Aya Higuchi"})})

      {:ok, []} = Credits.resolve_due(client: Fake, interval_ms: 0)

      assert [%Credit{agent_id: artist_id, agent_kind: :artist}] =
               Credits.credits_of(work_of(track))

      assert Repo.get!(Res, artist_id).kind == :artist
      assert Repo.all(MusicBrainzArtist) == []
    end

    test "a credit placed before artists were named acquires one on the next pass",
         %{inbox: inbox} do
      [track] =
        ingest!(inbox, %{
          "a.flac" => track(%{"artist" => "Miles Davis", "MUSICBRAINZ_ARTISTID" => Fake.person()})
        })

      work_id = work_of(track)
      [placed] = Credits.credits_of(work_id)
      unname(placed)

      assert [%Credit{agent_id: nil}] = Credits.credits_of(work_id)

      {:ok, [{_, :narrowed}]} = Credits.resolve_due(client: Fake, interval_ms: 0)

      assert [%Credit{agent_id: artist_id, agent_kind: :person}] = Credits.credits_of(work_id)
      assert artist_id == placed.agent_id
      assert Catalog.creators_of(work_id) == [artist_id]
    end

    test "not found is a finding against the identifier, and is not asked again", %{inbox: inbox} do
      ingest!(inbox, %{
        "a.flac" => track(%{"artist" => "Nobody", "MUSICBRAINZ_ARTISTID" => Fake.missing()})
      })

      {:ok, [{_, :not_found}]} = Credits.resolve_due(client: Fake, interval_ms: 0)

      assert [
               %{
                 stage: :credit,
                 kind: "musicbrainz_artist_not_found",
                 musicbrainz_id: id,
                 permanent: true
               }
             ] =
               Ingest.open_findings()

      assert id == Fake.missing()
      assert {:ok, []} = Credits.resolve_due(client: Fake, interval_ms: 0)
    end

    test "an unreachable MusicBrainz is tried again, and after three a finding", %{inbox: inbox} do
      ingest!(inbox, %{
        "a.flac" => track(%{"artist" => "Somebody", "MUSICBRAINZ_ARTISTID" => Fake.unreachable()})
      })

      assert {:ok, [{_, :transient}]} = Credits.resolve_due(client: Fake, interval_ms: 0)
      assert {:ok, [{_, :transient}]} = Credits.resolve_due(client: Fake, interval_ms: 0)
      assert Ingest.open_findings() == []
      assert {:ok, [{_, :exhausted}]} = Credits.resolve_due(client: Fake, interval_ms: 0)

      assert [%{kind: "transient_failure_exhausted", permanent: false}] = Ingest.open_findings()
      assert {:ok, []} = Credits.resolve_due(client: Fake, interval_ms: 0)
    end
  end

  describe "MusicBrainz is asked at no more than its limit" do
    test "each request after the first waits the interval", %{inbox: inbox} do
      ingest!(inbox, %{
        "a.flac" => track(%{"artist" => "Miles Davis", "MUSICBRAINZ_ARTISTID" => Fake.person()}),
        "b.flac" => track(%{"artist" => "Quintet", "MUSICBRAINZ_ARTISTID" => Fake.group()}, 500)
      })

      {elapsed, {:ok, [_, _]}} =
        :timer.tc(fn -> Credits.resolve_due(client: Fake, interval_ms: 200) end, :millisecond)

      assert elapsed >= 200
    end
  end

  describe "33. No lookup runs in placement, and none without a contact" do
    test "placement records credits and asks MusicBrainz nothing", %{inbox: inbox} do
      ingest!(inbox, %{
        "a.flac" => track(%{"artist" => "Miles Davis", "MUSICBRAINZ_ARTISTID" => Fake.person()})
      })

      assert Repo.all(MusicBrainzArtist) == []
    end

    test "with no contact configured the real client is not used" do
      assert MusicBrainz.contact() == nil
      assert {:error, :no_contact_configured} = Credits.resolve_due()
    end
  end

  defp track(tags, frequency \\ 440) do
    media!(:flac,
      frequency: frequency,
      tags:
        Map.merge(
          %{"album" => "Album #{frequency}", "album_artist" => "Various", "track" => "1"},
          tags
        )
    )
  end

  # A credit as placement wrote one before every credit named an artist. The
  # artist it named stays, as it would in a catalog filled by an earlier
  # release.
  defp unname(credit) do
    credit |> Ecto.Changeset.change(agent_id: nil, agent_kind: nil) |> Repo.update!()
  end

  defp ingest!(inbox, files, from \\ @t0) do
    for {path, bytes} <- files, do: drop!(inbox, path, bytes)
    ids = inbox |> acquire_settled!(from) |> acquired()
    Place.place_due(inbox)
    ids |> Enum.map(&Ingest.get_acquisition!/1) |> Enum.sort_by(& &1.inbox_path)
  end

  defp work_of(acquisition) do
    [expression] = acquisition |> placed!() |> Catalog.expressions_in()
    expression.work_id
  end

  # An acquisition that was not placed says why: its state, and whatever
  # finding held it back. Without that the failure is a nil identifier and
  # nothing to act on.
  defp placed!(%{digital_item_id: nil, id: id}) do
    acquisition = Ingest.get_acquisition!(id)
    findings = Repo.all(from f in Finding, where: f.acquisition_id == ^id)

    flunk("""
    #{acquisition.inbox_path} was acquired but never placed.
      state: #{acquisition.state}
      findings: #{inspect(Enum.map(findings, &{&1.stage, &1.kind, &1.detail}))}
    """)
  end

  defp placed!(acquisition),
    do: Repo.get!(DigitalItem, acquisition.digital_item_id).manifestation_id

  defp release_work_of(track) do
    manifestation = Repo.get!(DigitalItem, track.digital_item_id).manifestation_id
    [%{whole_id: medium}] = Catalog.wholes_of(manifestation)
    [%{whole_id: release}] = Catalog.wholes_of(medium)
    [expression] = Catalog.expressions_in(release)
    expression.work_id
  end
end
