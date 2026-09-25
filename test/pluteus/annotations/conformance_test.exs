defmodule Pluteus.Annotations.ConformanceTest do
  @moduledoc """
  Behavioural conformance with spec-02 §9.

  Each `describe` block states one numbered criterion.
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Annotations
  alias Pluteus.Annotations.Annotation
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Address
  alias Pluteus.Lifecycle
  alias Pluteus.Principals
  alias Pluteus.Storage

  setup do
    {:ok, principal} = Principals.create_principal(%{role: "member"})
    {:ok, %{work: work, expression: recording}} = Catalog.create_work("So What")
    %{principal: principal, work: work, recording: recording}
  end

  describe "1. An annotation carries exactly one of a principal or a derivation" do
    test "an authored one by a principal with no linked agent is accepted", context do
      assert is_nil(context.principal.person_id)

      assert {:ok, note} =
               Annotations.annotate(%{
                 target_id: context.recording.id,
                 body_type: "note",
                 body: %{"text" => "the solo starts here"},
                 principal_id: context.principal.id
               })

      assert Annotation.authored?(note)
    end

    test "one carrying neither is rejected", context do
      assert {:error, changeset} =
               Annotations.annotate(%{
                 target_id: context.recording.id,
                 body_type: "note",
                 body: %{"text" => "whose?"}
               })

      assert %{principal_id: [_ | _]} = errors_on(changeset)
    end

    test "one carrying both is rejected", context do
      derivation = derivation!("whisper", "large-v3+ct2-4.4.0", context.recording.id)

      assert {:error, changeset} =
               Annotations.annotate(%{
                 target_id: context.recording.id,
                 body_type: "transcript",
                 body: %{"text" => "so what"},
                 principal_id: context.principal.id,
                 derivation_id: derivation.id
               })

      assert %{derivation_id: [_ | _]} = errors_on(changeset)
    end

    test "the database refuses both too, not only the changeset", context do
      derivation = derivation!("whisper", "large-v3+ct2-4.4.0", context.recording.id)
      {:ok, res} = Catalog.create_res(%{kind: :annotation})
      now = DateTime.utc_now()

      error =
        assert_raise Postgrex.Error, fn ->
          Repo.insert_all(Annotation, [
            %{
              id: res.id,
              target_id: context.recording.id,
              body_type: "transcript",
              body: %{"text" => "so what"},
              principal_id: context.principal.id,
              derivation_id: derivation.id,
              inserted_at: now,
              updated_at: now
            }
          ])
        end

      assert error.postgres.constraint == "provenance_is_a_principal_or_a_derivation"
    end

    test "a relative identifying a face through a member's login is the agent", context do
      {:ok, %{res: grandmother}} = Catalog.create_named_res(:person, "Amma")

      assert {:ok, tag} =
               Annotations.annotate(%{
                 target_id: context.recording.id,
                 body_type: "note",
                 body: %{"text" => "that is my brother on bass"},
                 principal_id: context.principal.id,
                 agent_id: grandmother.id
               })

      assert tag.agent_kind == :person
    end

    test "a derived one cannot claim an agent; whoever ran the tool is the derivation's",
         context do
      derivation = derivation!("whisper", "large-v3+ct2-4.4.0", context.recording.id)
      {:ok, %{res: someone}} = Catalog.create_named_res(:person, "Ada")

      assert {:error, changeset} =
               Annotations.annotate(%{
                 target_id: context.recording.id,
                 body_type: "transcript",
                 body: %{"text" => "so what"},
                 derivation_id: derivation.id,
                 agent_id: someone.id
               })

      assert %{agent_id: [_ | _]} = errors_on(changeset)
    end
  end

  describe "2. An authored annotation targeting a derived address is rejected" do
    test "a like on a computed segment boundary is refused", context do
      [segment | _] = segment!(context.recording.id, "v1", [{0, 120_000}, {120_000, 240_000}])

      assert {:error, changeset} = like(segment.id, context.principal.id)
      assert %{target_id: [_ | _]} = errors_on(changeset)
    end

    test "the same moment addressed on the recording itself is accepted", context do
      segment!(context.recording.id, "v1", [{0, 120_000}, {120_000, 240_000}])
      moment = moment!(context.recording.id, 134_000)

      assert {:ok, _like} = like(moment.id, context.principal.id)
    end

    test "a derived annotation may target a derived address", context do
      [segment | _] = segment!(context.recording.id, "v1", [{0, 120_000}])
      clap = derivation!("laion/clap-htsat-unfused", "hf-0c1d2e3", context.recording.id)

      assert {:ok, _embedding} =
               Annotations.annotate(%{
                 target_id: segment.id,
                 body_type: "embedding",
                 body: %{"vector" => [0.12, -0.4, 0.9]},
                 derivation_id: clap.id
               })
    end

    test "an address anchoring an authored annotation cannot be made derived", context do
      moment = moment!(context.recording.id, 134_000)
      {:ok, _like} = like(moment.id, context.principal.id)
      segmenter = derivation!("segmenter", "v1", context.recording.id)

      error =
        assert_raise Postgrex.Error, fn ->
          Repo.update_all(from(a in Address, where: a.id == ^moment.id),
            set: [derivation_id: segmenter.id]
          )
        end

      assert error.postgres.constraint == "authored_annotation_targets_the_resource"
    end
  end

  describe "3. Re-segmenting at a new version does not move what an authored annotation means" do
    test "a like at 2:14 still means 2:14; only the segment covering it changes", context do
      segment!(context.recording.id, "v1", [{0, 120_000}, {120_000, 240_000}])
      moment = moment!(context.recording.id, 134_000)
      {:ok, like} = like(moment.id, context.principal.id)

      assert [%Address{start_ms: 120_000, end_ms: 240_000}] =
               Annotations.covering(moment, "segmenter")

      segment!(context.recording.id, "v2", [{0, 130_000}, {130_000, 200_000}, {200_000, 240_000}])

      assert [%Address{start_ms: 130_000, end_ms: 200_000}] =
               Annotations.covering(moment, "segmenter")

      assert Repo.get!(Annotation, like.id).target_id == moment.id
      assert Repo.get!(Address, moment.id).start_ms == 134_000
    end
  end

  describe "4. A derived annotation's version distinguishes builds, and \"before X\" is a query" do
    test "two builds sharing a library version are two versions", context do
      first = derivation!("extractor", "essentia-2.1b6+9f2c1e0", context.recording.id)
      second = derivation!("extractor", "essentia-2.1b6+1a7d3b4", context.recording.id)

      refute first.tool_version_id == second.tool_version_id
    end

    test "before X means before X was first recorded, not before X alphabetically", context do
      a = measured!(context.recording.id, "extractor", "essentia-2.1b6+9f2c1e0", 1)
      b = measured!(context.recording.id, "extractor", "essentia-2.1b6+1a7d3b4", 2)
      c = measured!(context.recording.id, "extractor", "essentia-2.1b6+5c0e8f2", 3)

      assert ids(Annotations.produced_before("extractor", "essentia-2.1b6+5c0e8f2")) ==
               Enum.sort([a.id, b.id])

      assert ids(Annotations.produced_before("extractor", "essentia-2.1b6+1a7d3b4")) == [a.id]
      refute c.id in ids(Annotations.produced_before("extractor", "essentia-2.1b6+5c0e8f2"))
    end

    test "a derivation with no version is refused", context do
      assert {:error, changeset} =
               Annotations.record_derivation(%{
                 tool: "extractor",
                 version: nil,
                 input_id: context.recording.id,
                 parameters: %{},
                 derived_at: DateTime.utc_now()
               })

      assert %{version: [_ | _]} = errors_on(changeset)
    end
  end

  describe "5. An embedding names its model and carries no unrelated extractor version" do
    test "the provenance is the model's, and only the model's", context do
      derivation!("extractor", "essentia-2.1b6+9f2c1e0", context.recording.id)
      clap = derivation!("laion/clap-htsat-unfused", "hf-0c1d2e3", context.recording.id)

      {:ok, embedding} =
        Annotations.annotate(%{
          target_id: context.recording.id,
          body_type: "embedding",
          body: %{"vector" => Enum.map(1..512, &(&1 / 512))},
          derivation_id: clap.id
        })

      provenance = Annotations.present(embedding.id).provenance

      assert provenance.tool == "laion/clap-htsat-unfused"
      assert provenance.version == "hf-0c1d2e3"
    end

    test "an annotation has one derivation and no version field of its own" do
      fields = Enum.map(Annotation.__schema__(:fields), &Atom.to_string/1)

      assert Enum.count(fields, &String.contains?(&1, "derivation")) == 1
      refute Enum.any?(fields, &String.contains?(&1, "version"))
    end
  end

  describe "6. A newer body from a different tool does not supersede an older one" do
    test "two OCR engines both stand, whatever their confidence scores", context do
      earlier = ocr!(context.recording.id, "tesseract", "5.3.4", 1, 0.31)
      later = ocr!(context.recording.id, "paddleocr", "2.8.1", 2, 0.97)

      current = ids(Annotations.current_on(context.recording.id))

      assert earlier.id in current
      assert later.id in current
    end

    test "a newer version of the same tool does supersede", context do
      old = ocr!(context.recording.id, "tesseract", "5.3.4", 1, 0.97)
      new = ocr!(context.recording.id, "tesseract", "5.4.0", 2, 0.31)

      assert ids(Annotations.current_on(context.recording.id)) == [new.id]
      assert ids(Annotations.superseded_on(context.recording.id)) == [old.id]
    end

    test "a re-run at the same version replaces the earlier run", context do
      first = ocr!(context.recording.id, "tesseract", "5.4.0", 1, 0.5)
      rerun = ocr!(context.recording.id, "tesseract", "5.4.0", 2, 0.5)

      assert ids(Annotations.current_on(context.recording.id)) == [rerun.id]
      assert ids(Annotations.superseded_on(context.recording.id)) == [first.id]
    end

    test "an older version run after a newer one supersedes nothing", context do
      ocr!(context.recording.id, "tesseract", "5.3.4", 1, 0.5)
      newer = ocr!(context.recording.id, "tesseract", "5.4.0", 2, 0.5)
      ocr!(context.recording.id, "tesseract", "5.3.4", 3, 0.99)

      assert ids(Annotations.current_on(context.recording.id)) == [newer.id]
    end

    test "a superseded body is kept rather than deleted", context do
      old = ocr!(context.recording.id, "tesseract", "5.3.4", 1, 0.5)
      ocr!(context.recording.id, "tesseract", "5.4.0", 2, 0.5)

      assert %Annotation{} = Repo.get(Annotation, old.id)
    end
  end

  describe "7. A derived annotation never supersedes an authored one" do
    test "a machine transcript does not displace a person's correction", context do
      {:ok, correction} =
        Annotations.annotate(%{
          target_id: context.recording.id,
          body_type: "transcript",
          body: %{"text" => "So what — Miles, 1959"},
          principal_id: context.principal.id
        })

      for {version, minute} <- [{"large-v2", 1}, {"large-v3", 2}, {"large-v3-turbo", 3}] do
        whisper = derivation!("whisper", version, context.recording.id, minute)

        {:ok, _} =
          Annotations.annotate(%{
            target_id: context.recording.id,
            body_type: "transcript",
            body: %{"text" => "so what", "confidence" => 0.99},
            derivation_id: whisper.id
          })
      end

      assert correction.id in ids(Annotations.current_on(context.recording.id))
      refute correction.id in ids(Annotations.superseded_on(context.recording.id))
    end
  end

  describe "8. Stored values are the tool's; re-normalizing needs no access to the media" do
    setup context do
      extractor = derivation!("extractor", "essentia-2.1b6+9f2c1e0", context.recording.id)
      body = %{"loudness" => -14.2, "tempo" => 136.0, "chroma" => [0.1, 0.9, 0.3]}

      {:ok, measured} =
        Annotations.annotate(%{
          target_id: context.recording.id,
          body_type: "features",
          body: body,
          derivation_id: extractor.id
        })

      %{measured: measured, body: body}
    end

    test "the stored body is exactly what the tool produced", %{measured: measured, body: body} do
      assert Repo.get!(Annotation, measured.id).body == body
    end

    test "a new layout is applied to the stored body with the media gone", %{measured: measured} do
      location = "recordings/#{System.unique_integer([:positive])}/so-what.flac"
      :ok = Storage.put(location, "the recording")
      :ok = Storage.delete(location)
      stored = Repo.get!(Annotation, measured.id).body

      loud = Annotations.assemble(stored, [{"loudness", -60, 0, 1.0}, {"tempo", 40, 240, 1.0}])
      tonal = Annotations.assemble(stored, [{"chroma", 0, 1, 2.0}, {"tempo", 40, 240, 0.5}])

      refute Storage.exists?(location)
      assert_in_delta hd(loud), 0.763, 0.001
      assert tonal == [0.2, 1.8, 0.6, 0.24]
    end

    test "a measurement the layout needs and the body lacks fails visibly", %{measured: measured} do
      stored = Repo.get!(Annotation, measured.id).body

      assert_raise KeyError, fn ->
        Annotations.assemble(stored, [{"spectral_flux", 0, 1, 1.0}])
      end
    end

    test "a positional vector is not a body", context do
      extractor = derivation!("extractor", "essentia-2.1b6+9f2c1e0", context.recording.id)

      assert {:error, changeset} =
               Annotations.annotate(%{
                 target_id: context.recording.id,
                 body_type: "features",
                 body: [-14.2, 136.0, 0.1, 0.9, 0.3],
                 derivation_id: extractor.id
               })

      assert %{body: [_ | _]} = errors_on(changeset)
    end
  end

  describe "9. Purging a target purges its derived annotations and retains its authored ones" do
    test "the loudness and the embeddings go; the like and the note stay", context do
      loudness = measured!(context.recording.id, "extractor", "essentia-2.1b6+9f2c1e0", 1)
      [segment | _] = segment!(context.recording.id, "v1", [{0, 240_000}])
      clap = derivation!("laion/clap-htsat-unfused", "hf-0c1d2e3", context.recording.id)

      {:ok, embedding} =
        Annotations.annotate(%{
          target_id: segment.id,
          body_type: "embedding",
          body: %{"vector" => [0.1, 0.2]},
          derivation_id: clap.id
        })

      moment = moment!(context.recording.id, 134_000)
      {:ok, liked} = like(moment.id, context.principal.id)

      {:ok, note} =
        Annotations.annotate(%{
          target_id: context.recording.id,
          body_type: "note",
          body: %{"text" => "played at our wedding"},
          principal_id: context.principal.id
        })

      {:ok, recycling} = Lifecycle.recycle(context.work.id, context.principal.id)
      held = Lifecycle.contents(recycling.id)

      assert loudness.id in held
      assert embedding.id in held
      refute liked.id in held
      refute note.id in held
      refute moment.id in held

      {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())

      assert Repo.get(Annotation, loudness.id) == nil
      assert Repo.get(Annotation, embedding.id) == nil
      assert %Annotation{} = Repo.get(Annotation, liked.id)
      assert %Annotation{} = Repo.get(Annotation, note.id)
      assert %Address{start_ms: 134_000} = Repo.get(Address, moment.id)
    end
  end

  describe "10. An orphaned authored annotation renders, names its target, and raises nothing" do
    test "a face tag outlives the photograph and still says whom and where", context do
      {:ok, %{work: photo, manifestation: print}} =
        Catalog.create_work("Grandma at the lake, 1962")

      {:ok, %{res: grandmother}} = Catalog.create_named_res(:person, "Amma")

      {:ok, %{address: face}} =
        Catalog.create_address(print.id, %{
          selector_type: :spatial,
          x_percent: 25.0,
          y_percent: 20.0,
          width_percent: 15.0,
          height_percent: 20.0
        })

      {:ok, tag} =
        Annotations.annotate(%{
          target_id: face.id,
          body_type: "face",
          body: %{"person_id" => grandmother.id},
          principal_id: context.principal.id
        })

      purge!(photo.id, context.principal.id)

      presented = Annotations.present(tag.id)
      print_id = print.id

      assert presented.body == %{"person_id" => grandmother.id}
      assert presented.provenance.authored_by == context.principal.id
      assert %{id: ^print_id, kind: :manifestation, state: :purged} = presented.target.resource
      assert presented.target.address.x_percent == 25.0
    end

    test "a note on a whole work names the work once it is gone", context do
      {:ok, note} =
        Annotations.annotate(%{
          target_id: context.work.id,
          body_type: "note",
          body: %{"text" => "Dad's favourite"},
          principal_id: context.principal.id
        })

      purge!(context.work.id, context.principal.id)

      work_id = context.work.id

      assert %{resource: %{id: ^work_id, kind: :work, state: :purged}} =
               Annotations.present(note.id).target
    end

    test "one on something only in the bin says when it can still be restored", context do
      {:ok, note} =
        Annotations.annotate(%{
          target_id: context.work.id,
          body_type: "note",
          body: %{"text" => "Dad's favourite"},
          principal_id: context.principal.id
        })

      {:ok, _} = Lifecycle.recycle(context.work.id, context.principal.id)

      assert %{resource: %{state: :recycled, restorable_until: %DateTime{}}} =
               Annotations.present(note.id).target
    end
  end

  describe "12. A body whose subject is a named field carries a field name from the registry" do
    test "an assertion about a field the registry names is accepted", context do
      for assertion <- Annotation.assertions() do
        assert {:ok, absence} = absence(context, context.work.id, "creators", assertion)

        assert absence.body == %{"field" => "creators", "assertion" => assertion}
        assert Annotation.authored?(absence)
      end
    end

    test "a field the registry does not name is refused", context do
      assert {:error, changeset} =
               absence(context, context.work.id, "mood", "known_absent")

      assert %{body: [message]} = errors_on(changeset)
      assert message =~ "mood"
    end

    test "an assertion outside the three §6.5 admits is refused", context do
      assert {:error, changeset} =
               absence(context, context.work.id, "creators", "probably_absent")

      assert %{body: [_ | _]} = errors_on(changeset)
    end

    test "a body naming no field has no subject, and is refused", context do
      assert {:error, changeset} =
               Annotations.annotate(%{
                 target_id: context.work.id,
                 body_type: Annotation.absence(),
                 body: %{"assertion" => "known_absent"},
                 principal_id: context.principal.id
               })

      assert %{body: [_ | _]} = errors_on(changeset)
    end

    test "a field the registry names for another kind is refused about this one", context do
      # `creators` is a work's. An expression is a rendering of the work, and the
      # question of who made it is asked of the work.
      assert {:error, {:absence_not_about, "creators", :expression}} =
               absence(context, context.recording.id, "creators", "sought_not_found")
    end

    test "only a person may write one: a derived body is refused", context do
      derivation = derivation!("describer", "1", context.work.id)

      assert {:error, changeset} =
               Annotations.annotate(%{
                 target_id: context.work.id,
                 body_type: Annotation.absence(),
                 body: %{"field" => "creators", "assertion" => "sought_not_found"},
                 derivation_id: derivation.id
               })

      # A tool that looked and could not has produced a finding (spec-04 §9),
      # which records what the deployment attempted rather than what is so.
      assert %{body: [_ | _]} = errors_on(changeset)
    end
  end

  defp absence(context, target_id, field, assertion) do
    Annotations.annotate(%{
      target_id: target_id,
      body_type: Annotation.absence(),
      body: %{"field" => field, "assertion" => assertion},
      principal_id: context.principal.id
    })
  end

  defp derivation!(tool, version, input_id, minute \\ 0) do
    {:ok, derivation} =
      Annotations.record_derivation(%{
        tool: tool,
        version: version,
        input_id: input_id,
        parameters: %{"sample_rate" => 22_050},
        derived_at: DateTime.add(~U[2026-09-01 00:00:00.000000Z], minute * 60, :second)
      })

    derivation
  end

  defp segment!(recording_id, version, spans) do
    segmenter = derivation!("segmenter", version, recording_id)

    for {start_ms, end_ms} <- spans do
      {:ok, %{address: address}} =
        Annotations.derive_address(segmenter.id, recording_id, %{
          selector_type: :temporal,
          start_ms: start_ms,
          end_ms: end_ms
        })

      address
    end
  end

  defp moment!(recording_id, at_ms) do
    {:ok, %{address: address}} =
      Catalog.create_address(recording_id, %{
        selector_type: :temporal,
        start_ms: at_ms,
        end_ms: at_ms
      })

    address
  end

  defp like(target_id, principal_id) do
    Annotations.annotate(%{
      target_id: target_id,
      body_type: "like",
      body: %{},
      principal_id: principal_id
    })
  end

  defp measured!(target_id, tool, version, minute) do
    derivation = derivation!(tool, version, target_id, minute)

    {:ok, annotation} =
      Annotations.annotate(%{
        target_id: target_id,
        body_type: "features",
        body: %{"loudness" => -14.2},
        derivation_id: derivation.id
      })

    annotation
  end

  defp ocr!(target_id, tool, version, minute, confidence) do
    derivation = derivation!(tool, version, target_id, minute)

    {:ok, annotation} =
      Annotations.annotate(%{
        target_id: target_id,
        body_type: "transcript",
        body: %{"text" => "Letter from Ada", "confidence" => confidence},
        derivation_id: derivation.id
      })

    annotation
  end

  defp purge!(res_id, principal_id) do
    {:ok, recycling} = Lifecycle.recycle(res_id, principal_id)
    {:ok, _} = Lifecycle.purge(recycling, DateTime.utc_now())
  end

  defp ids(annotations), do: annotations |> Enum.map(& &1.id) |> Enum.sort()
end
