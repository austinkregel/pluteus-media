defmodule Pluteus.CatalogFixtures do
  @moduledoc """
  Catalogue entries drawn from LRM's own worked examples.

  Real names carry the complications the model exists to handle: two
  bibliographic identities behind one person, a transliteration derived from a
  Cyrillic original, one day written in three calendars, a kin term belonging to
  no language at all. Placeholder strings exercise none of it, and a naming
  model that only ever sees them is untested where it matters.
  """

  alias Pluteus.Catalog

  @doc """
  A person under two bibliographic identities, as LRM §5.5 describes them.

  Agatha Christie published detective fiction under her own name and romance
  novels as Mary Westmacott. Each identity carries its own ISNI, so one person
  holds two — which is why an identifier cannot be a column on the person.
  """
  def agatha_christie! do
    {:ok, person} = Catalog.create_res(%{kind: :person})

    detective =
      nomen!(person.id, %{
        nomen_string: "Christie, Agatha, 1890-1976",
        scheme: "lc-naco",
        language: "en",
        script: "Latn",
        context_of_use: "detective fiction"
      })

    romance =
      nomen!(person.id, %{
        nomen_string: "Westmacott, Mary, 1890-1976",
        scheme: "lc-naco",
        language: "en",
        script: "Latn",
        context_of_use: "romance novels"
      })

    detective_isni =
      nomen!(person.id, %{
        nomen_string: "0000000121022127",
        scheme: "isni",
        context_of_use: "detective fiction"
      })

    romance_isni =
      nomen!(person.id, %{
        nomen_string: "0000000366130900",
        scheme: "isni",
        context_of_use: "romance novels"
      })

    %{
      person: person,
      detective: detective,
      romance: romance,
      detective_isni: detective_isni,
      romance_isni: romance_isni
    }
  end

  @doc """
  A name in Cyrillic and the Latin transliteration built from it (LRM-R17).

  The derived form records the standard it was produced under, so a later reader
  can tell a transliteration from an independently chosen Latin name.
  """
  def anna_pavlova! do
    {:ok, person} = Catalog.create_res(%{kind: :person})

    cyrillic =
      nomen!(person.id, %{
        nomen_string: "Анна Павловна Павлова",
        language: "ru",
        script: "Cyrl"
      })

    latin =
      nomen!(person.id, %{
        nomen_string: "Anna Pavlovna Pavlova",
        language: "ru",
        script: "Latn",
        script_conversion: "ISO 9",
        derived_from_id: cyrillic.id
      })

    %{person: person, cyrillic: cyrillic, latin: latin}
  end

  @doc """
  One day written in three calendars, the case §7.4 names directly.

  Calendar preference is not a separate mechanism: these are nomens of a
  time-span, chosen by the same resolution that chooses a title.
  """
  def first_march_2015! do
    {:ok, time_span} = Catalog.create_res(%{kind: :time_span})

    %{
      time_span: time_span,
      gregorian_en:
        nomen!(time_span.id, %{
          nomen_string: "March 1, 2015",
          scheme: "gregorian",
          language: "en"
        }),
      gregorian_it:
        nomen!(time_span.id, %{
          nomen_string: "1 marzo 2015",
          scheme: "gregorian",
          language: "it"
        }),
      hebrew:
        nomen!(time_span.id, %{
          nomen_string: "10 Adar 5775",
          scheme: "hebrew",
          language: "he"
        }),
      indian_civil:
        nomen!(time_span.id, %{
          nomen_string: "1936 Phalguna 10",
          scheme: "indian-civil",
          language: "hi"
        })
    }
  end

  @doc """
  One organisation named in four languages, from LRM's nomen examples.
  """
  def united_nations! do
    {:ok, agent} = Catalog.create_res(%{kind: :collective_agent})

    names =
      Map.new(
        [
          {"en", "United Nations"},
          {"fr", "Nations Unies"},
          {"it", "Nazioni Unite"},
          {"de", "Vereinigte Nationen"}
        ],
        fn {language, string} ->
          {language, nomen!(agent.id, %{nomen_string: string, language: language})}
        end
      )

    %{agent: agent, names: names}
  end

  @doc """
  A kin term in the household's own vocabulary, and one person's variant on it.

  The household name carries no language and no assigner, which §7.2 and §7.3
  make the unmarked case rather than missing data.
  """
  def kin_term! do
    {:ok, grandmother} = Catalog.create_res(%{kind: :person})
    {:ok, child} = Catalog.create_res(%{kind: :person})

    %{
      grandmother: grandmother,
      child: child,
      household:
        nomen!(grandmother.id, %{
          nomen_string: "Amma",
          language: nil,
          context_of_use: "maternal grandmother"
        }),
      childs_own:
        nomen!(grandmother.id, %{
          nomen_string: "Amma-ji",
          language: nil,
          assigner_id: child.id,
          context_of_use: "maternal grandmother"
        })
    }
  end

  @doc """
  A work with its first expression and manifestation, as §6.2 requires.
  """
  def work! do
    {:ok, %{work: work}} = Catalog.create_work("Anatomy of the human body")
    work
  end

  @doc """
  Attaches a nomen to a res, returning the nomen.
  """
  def nomen!(res_id, attrs) do
    {:ok, nomen} = Catalog.create_nomen(Map.put(attrs, :res_id, res_id))
    nomen
  end
end
