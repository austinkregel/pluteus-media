defmodule Pluteus.Repo.Migrations.TakeOnlyWhatCanBeSaidToBeSomething do
  use Ecto.Migration

  # spec-04 §6.3. The category is decided from evidence while the file is still in the
  # inbox, because §4.3 moves it out once the deployment takes it and a file nothing can
  # say the category of is one a person still has to deal with — in the place they put it,
  # where they can put a document beside it or move it somewhere that says what it is.
  #
  # Recorded here rather than derived again at placement: the evidence is the inbox
  # directory, which the file has left by then, and a category decided twice from two
  # readings of different things is two categories.
  #
  # An acquisition placed before this column existed carries nothing in it. That is not a
  # category standing in for one that is missing: those holdings were categorized under
  # the rule this replaces, and what they are is on the work.
  #
  # The stage is for a file the deployment looked at and could not say what it was. It is
  # its own stage because it is the one finding whose subject is still in the inbox and
  # whose answer is a person putting something beside it.
  def change do
    alter table(:acquisitions) do
      add :category, :string
    end

    drop constraint(:ingest_findings, :stage_must_be_known)

    create constraint(:ingest_findings, :stage_must_be_known,
             check:
               "stage IN ('acquire', 'examine', 'identify', 'place', 'normalize', 'analyse', 'purge', 'credit')"
           )
  end
end
