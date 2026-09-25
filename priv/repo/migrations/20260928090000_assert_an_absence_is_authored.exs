defmodule Pluteus.Repo.Migrations.AssertAnAbsenceIsAuthored do
  use Ecto.Migration

  # spec-02 §6.5. A body whose subject is a named field of its target says that
  # the field holds no value and what a person established about it. Only a
  # person may write one: a tool that looked and failed has produced a finding
  # (spec-04 §9), which is a record of what the deployment attempted.
  @assertions ~w(sought_not_found known_unknowable known_absent)

  def up do
    create constraint(:annotations, :an_absence_assertion_is_authored,
             check: "body_type <> 'absence' OR principal_id IS NOT NULL"
           )

    # Without the field name the assertion has no subject: "not found" about a
    # photograph says nothing. The three values are the whole of what §6.5
    # admits, and spec-10 §5.2 makes them the three states no deployment may
    # infer from the catalog's silence.
    create constraint(:annotations, :an_absence_assertion_names_a_field,
             check: """
             body_type <> 'absence' OR (
               body->>'field' IS NOT NULL
               AND body->>'assertion' IN (#{in_list(@assertions)})
             )
             """
           )
  end

  def down do
    drop constraint(:annotations, :an_absence_assertion_names_a_field)
    drop constraint(:annotations, :an_absence_assertion_is_authored)
  end

  defp in_list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
