defmodule Pluteus.Principals.ConformanceTest do
  @moduledoc """
  Behavioural conformance with spec-06 §7, for the criteria observable without
  HTTP. Each `describe` block states one numbered criterion.
  """

  use Pluteus.DataCase, async: true

  alias Pluteus.Actor
  alias Pluteus.Administration
  alias Pluteus.Administration.AuditRecord
  alias Pluteus.Annotations
  alias Pluteus.Annotations.Annotation
  alias Pluteus.Catalog
  alias Pluteus.Catalog.Profile
  alias Pluteus.Events
  alias Pluteus.Events.Event
  alias Pluteus.Household
  alias Pluteus.Household.TrustBoundary
  alias Pluteus.Lifecycle
  alias Pluteus.Principals
  alias Pluteus.Principals.Device
  alias Pluteus.Principals.Identity
  alias Pluteus.Principals.Principal

  @issuer "https://auth.household.test"

  setup do
    {:ok, admin} = Principals.create_principal(%{role: "administrator"})
    {:ok, _} = Principals.bind_identity(admin.id, @issuer, "admin@household.test")
    {:ok, ada} = Principals.create_principal(%{role: "member"})
    {:ok, _} = Principals.bind_identity(ada.id, @issuer, "ada@household.test")
    {:ok, bo} = Principals.create_principal(%{role: "member"})
    {:ok, _} = Principals.bind_identity(bo.id, @issuer, "bo@household.test")
    {:ok, %{work: work}} = Catalog.create_work("The Dig")
    %{admin: admin, ada: ada, bo: bo, work: work}
  end

  describe "1. Events, authored annotations and devices reference a principal locally" do
    test "none of them can hold an external identity" do
      for schema <- [Event, Annotation, Device] do
        fields = schema.__schema__(:fields)

        assert :principal_id in fields
        refute :issuer in fields
        refute :subject in fields
      end
    end
  end

  describe "2. A principal accepts a further (iss, sub), and its prior events stay reachable" do
    test "after a provider migration the same principal answers", %{
      admin: admin,
      ada: ada,
      work: work
    } do
      {:ok, _} = Events.record(ada.id, work.id, "played")

      {:ok, _} =
        Administration.add_identity(
          admin,
          ada.id,
          {"https://new-auth.household.test", "ada@household.test"},
          {@issuer, "admin@household.test"}
        )

      moved = Principals.principal_for("https://new-auth.household.test", "ada@household.test")

      assert moved.id == ada.id
      assert [_played] = Events.for_principal(moved.id)
    end
  end

  describe "3. sub alone is never accepted as an identity key" do
    test "the same subject under another issuer names nobody", %{ada: ada} do
      assert Principals.principal_for(@issuer, "ada@household.test").id == ada.id
      assert Principals.principal_for("https://elsewhere.test", "ada@household.test") == nil
    end

    test "the key is the pair, so two issuers may share a subject", %{bo: bo} do
      assert {:ok, _} =
               Principals.bind_identity(bo.id, "https://elsewhere.test", "ada@household.test")
    end
  end

  describe "4. An agent with no principal can create a work and assign a nomen" do
    test "a letter's author, who will never log in", %{work: work} do
      {:ok, %{res: author}} = Catalog.create_named_res(:person, "Ada Kregel, 1921-1998")

      assert {:ok, _} = Catalog.credit_creator(work.id, author.id)
      assert author.id in Catalog.creators_of(work.id)

      assert {:ok, nomen} =
               Catalog.create_nomen(%{
                 res_id: work.id,
                 nomen_string: "the letter about the move",
                 assigner_id: author.id
               })

      assert nomen.assigner_id == author.id

      assert Repo.all(from p in Principal, where: p.person_id == ^author.id) ==
               []
    end
  end

  describe "5. A principal with no linked agent is fully functional" do
    test "it plays, resumes, annotates and writes the catalog", %{ada: ada, work: work} do
      assert is_nil(ada.person_id)

      assert {:ok, _} = Events.record(ada.id, work.id, "played")
      assert {:ok, _} = Events.set_resume_position(ada.id, work.id, 60_000)

      assert {:ok, _} =
               Annotations.annotate(%{
                 target_id: work.id,
                 body_type: "note",
                 body: %{"text" => "watch with Bo"},
                 principal_id: ada.id
               })

      assert {:ok, %{work: _}} = Actor.as(ada.id, fn -> Catalog.create_work("Middlemarch") end)
    end
  end

  describe "6. No playback is recorded without an attributable principal" do
    test "an event naming no principal is refused", %{work: work} do
      assert {:error, changeset} = Events.record(nil, work.id, "played")
      assert %{principal_id: [_ | _]} = errors_on(changeset)
    end
  end

  describe "7. The trust boundary carries no name; the household's name comes from its nomens" do
    test "there is no name to hold" do
      fields = Enum.map(TrustBoundary.__schema__(:fields), &Atom.to_string/1)
      refute Enum.any?(fields, &String.contains?(&1, "name"))
    end

    test "unlinked it is unnamed; linked it is named by the collective agent" do
      assert Household.name(%Profile{}) == :unnamed

      {:ok, %{res: household}} = Catalog.create_named_res(:collective_agent, "the Kregels")
      {:ok, _} = Household.link(household.id)

      assert Household.name(%Profile{}) == {:ok, "the Kregels"}
    end

    test "renaming the household is a naming operation and nothing else" do
      {:ok, %{res: household}} = Catalog.create_named_res(:collective_agent, "the Kregels")
      {:ok, boundary} = Household.link(household.id)

      {:ok, _} =
        Catalog.create_nomen(%{
          res_id: household.id,
          nomen_string: "Kregel house",
          language: "en"
        })

      assert Household.name(%Profile{language: "en"}) == {:ok, "Kregel house"}
      assert Household.boundary().updated_at == boundary.updated_at
    end
  end

  describe "8. With every member gone the collective agent is still credited" do
    test "the home video keeps its author", %{admin: admin, ada: ada, bo: bo} do
      {:ok, %{res: household}} = Catalog.create_named_res(:collective_agent, "the Kregels")
      {:ok, _} = Household.link(household.id)
      {:ok, %{work: video}} = Catalog.create_work("Christmas 2019")
      {:ok, _} = Catalog.credit_creator(video.id, household.id)

      for member <- [ada, bo, admin] do
        {:ok, _} = Administration.retire_principal(admin, member.id)
      end

      assert Enum.filter(Household.members(), &(&1.id in [admin.id, ada.id, bo.id])) == []
      assert household.id in Catalog.creators_of(video.id)
    end
  end

  describe "9. Whoever the provider admits is served as a Member on their first request" do
    test "an identity arriving for the first time becomes a member" do
      assert Principals.principal_for(@issuer, "cousin@elsewhere.test") == nil

      principal = Principals.admit(@issuer, "cousin@elsewhere.test")

      assert principal.role == "member"
      assert Principals.principal_for(@issuer, "cousin@elsewhere.test").id == principal.id
    end

    test "arriving again is the same principal, not another", %{ada: ada} do
      assert Principals.admit(@issuer, "ada@household.test").id == ada.id
    end

    test "a retired principal stays retired though the provider still admits it", %{
      admin: admin,
      bo: bo
    } do
      {:ok, _} = Administration.retire_principal(admin, bo.id)

      refute is_nil(Principals.admit(@issuer, "bo@household.test").retired_at)
    end
  end

  describe "10. Principal A cannot observe principal B's events through any endpoint" do
    test "lists, counts and resumption are each one principal's", %{ada: ada, bo: bo, work: work} do
      {:ok, _} = Events.record(bo.id, work.id, "played")
      {:ok, _} = Events.set_resume_position(bo.id, work.id, 900_000)

      assert Events.for_principal(ada.id) == []
      assert Events.play_count(ada.id, work.id, "played") == 0
      assert Events.resumable(ada.id) == []
    end

    test "nothing in the events module answers without being told whose events" do
      for {function, arity} <- Pluteus.Events.__info__(:functions), arity > 0 do
        assert function in [
                 :for_principal,
                 :play_count,
                 :record,
                 :resumable,
                 :resume_position,
                 :set_resume_position
               ]
      end
    end
  end

  describe "11. A Member may map an identity onto itself, while authenticated, and onto nobody else" do
    test "onto another principal it is refused", %{ada: ada, bo: bo} do
      assert {:error, :not_permitted} =
               Administration.add_identity(
                 ada,
                 bo.id,
                 {"https://ada.example", "bo"},
                 {@issuer, "ada@household.test"}
               )

      assert Principals.principal_for("https://ada.example", "bo") == nil
    end

    test "onto itself, through a mapping it still authenticates by, it is accepted", %{ada: ada} do
      assert {:ok, _} =
               Administration.add_identity(
                 ada,
                 ada.id,
                 {"https://new-auth.household.test", "ada@household.test"},
                 {@issuer, "ada@household.test"}
               )
    end

    test "onto itself, arriving under somebody else's identity, it is refused", %{ada: ada} do
      assert {:error, :not_permitted} =
               Administration.add_identity(
                 ada,
                 ada.id,
                 {"https://new-auth.household.test", "ada@household.test"},
                 {@issuer, "bo@household.test"}
               )
    end
  end

  describe "13. The System principal has no identity mapping" do
    test "one cannot be given to it" do
      {:ok, system} = Principals.create_principal(%{role: "system"})

      assert {:error, changeset} = Principals.bind_identity(system.id, @issuer, "system")
      assert %{principal_id: [_ | _]} = errors_on(changeset)
    end

    test "and there is only ever one" do
      {:ok, _} = Principals.create_principal(%{role: "system"})

      assert {:error, changeset} = Principals.create_principal(%{role: "system"})
      assert %{role: [_ | _]} = errors_on(changeset)
    end
  end

  describe "14. Every Administrator operation is audited, including failures" do
    test "each succeeding operation leaves a record naming actor, subject, operation and time", %{
      admin: admin,
      ada: ada,
      bo: bo,
      work: work
    } do
      {:ok, _} = Administration.set_role(admin, bo.id, "administrator")

      {:ok, _} =
        Administration.add_identity(
          admin,
          bo.id,
          {"https://x.test", "bo"},
          {@issuer, "admin@household.test"}
        )

      {:ok, device} = Principals.bind_device(ada.id, "living-room TV")
      {:ok, _} = Administration.revoke_device(admin, device.id)
      {:ok, recycling} = Lifecycle.recycle(work.id, ada.id)
      {:ok, _} = Administration.empty_deletion(admin, recycling.id)
      {:ok, _} = Administration.retire_principal(admin, bo.id)

      trail = Administration.audit_trail()

      for {operation, subject} <- [
            {"set_role", bo.id},
            {"add_identity", bo.id},
            {"revoke_device", ada.id},
            {"empty_deletion", ada.id},
            {"retire_principal", bo.id}
          ] do
        record = Enum.find(trail, &(&1.operation == operation and &1.subject_id == subject))

        assert %AuditRecord{outcome: :succeeded, occurred_at: %DateTime{}} = record,
               "no record of #{operation}"

        assert record.actor_id == admin.id
      end
    end

    test "a refused attempt is recorded as a failure, with its reason", %{ada: ada, bo: bo} do
      assert {:error, :not_permitted} = Administration.retire_principal(ada, bo.id)

      assert [%AuditRecord{outcome: :failed, reason: ":not_permitted", subject_id: subject}] =
               Enum.filter(Administration.audit_trail(), &(&1.actor_id == ada.id))

      assert subject == bo.id
    end

    test "the System role is never assigned, and that refusal is recorded too", %{
      admin: admin,
      bo: bo
    } do
      assert {:error, :role_not_assignable} = Administration.set_role(admin, bo.id, "system")

      assert [%AuditRecord{operation: "set_role", outcome: :failed}] =
               Enum.filter(Administration.audit_trail(), &(&1.subject_id == bo.id))
    end
  end

  describe "15. Every catalog write records the acting principal" do
    test "a work created by Ada is recorded as Ada's, row by row", %{ada: ada} do
      {:ok, %{work: work}} = Actor.as(ada.id, fn -> Catalog.create_work("Middlemarch") end)

      writes =
        Repo.all(
          from w in "catalog_writes",
            where: w.principal_id == type(^ada.id, UUIDv7),
            select: {w.table_name, w.operation}
        )

      assert {"works", "INSERT"} in writes
      assert {"expressions", "INSERT"} in writes
      assert {"nomens", "INSERT"} in writes

      assert Repo.exists?(
               from w in "catalog_writes",
                 where:
                   w.table_name == "works" and fragment("? ->> 'id' = ?", w.row_key, ^work.id)
             )
    end

    test "a write attributed to nobody is refused" do
      :ok = Actor.set("")

      error = assert_raise Postgrex.Error, fn -> Catalog.create_work("Anonymous") end
      assert error.postgres.message =~ "no acting principal"
    end
  end

  describe "16. An audit record carries nothing about what anyone consumed" do
    test "its fields are who, whom, what, when and whether" do
      assert Enum.sort(AuditRecord.__schema__(:fields)) ==
               Enum.sort(
                 ~w(id actor_id subject_id operation outcome reason occurred_at inserted_at updated_at)a
               )
    end
  end

  describe "13 and 3 together: identities are pairs, and System holds none" do
    test "nothing is keyed on subject alone" do
      refute :subject in Principal.__schema__(:fields)
      assert :issuer in Identity.__schema__(:fields)
    end
  end
end
