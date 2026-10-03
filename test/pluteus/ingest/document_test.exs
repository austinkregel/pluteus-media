defmodule Pluteus.Ingest.DocumentTest do
  @moduledoc """
  Reading a metadata document's fields (spec-04 §6.9 criterion 35), and refusing one that
  reaches outside itself or will not parse (§11).
  """

  use ExUnit.Case, async: true

  alias Pluteus.Ingest.Document

  describe "the fields a document states" do
    test "a field is its element, folded, and its text" do
      assert {:ok, fields} =
               Document.fields(
                 ~s(<ComicInfo><Title>Issue One</Title><Number>1</Number></ComicInfo>)
               )

      assert fields == %{"title" => "Issue One", "number" => "1"}
    end

    test "surrounding whitespace is not part of a value" do
      document = """
      <ComicInfo>
        <Title>
          Issue One
        </Title>
      </ComicInfo>
      """

      assert {:ok, %{"title" => "Issue One"}} = Document.fields(document)
    end

    test "a namespace prefix does not change a field's name" do
      document =
        ~s(<ci:ComicInfo xmlns:ci="urn:x"><ci:Title>Issue One</ci:Title></ci:ComicInfo>)

      assert {:ok, %{"title" => "Issue One"}} = Document.fields(document)
    end

    test "a field stated twice keeps the first" do
      document = ~s(<ComicInfo><Title>First</Title><Title>Second</Title></ComicInfo>)

      assert {:ok, %{"title" => "First"}} = Document.fields(document)
    end

    test "a field holding elements states no value" do
      # A tag is a value, so an element carrying structure contributes nothing rather than
      # contributing its descendants' text run together.
      document =
        ~s(<ComicInfo><Pages><Page Image="0"/><Page Image="1"/></Pages><Title>One</Title></ComicInfo>)

      assert {:ok, fields} = Document.fields(document)
      assert fields == %{"title" => "One"}
    end

    test "an empty field states no value" do
      assert {:ok, fields} = Document.fields(~s(<ComicInfo><Title></Title></ComicInfo>))
      assert fields == %{}
    end

    test "an internal entity is expanded, since it names nothing outside the document" do
      document = """
      <?xml version="1.0"?>
      <!DOCTYPE ComicInfo [ <!ENTITY series "Excitebike Weekly"> ]>
      <ComicInfo><Series>&series;</Series></ComicInfo>
      """

      assert {:ok, %{"series" => "Excitebike Weekly"}} = Document.fields(document)
    end
  end

  describe "a document that reaches outside itself" do
    test "an external entity is refused, naming what it reached for" do
      document = """
      <?xml version="1.0"?>
      <!DOCTYPE ComicInfo [ <!ENTITY leak SYSTEM "file:///etc/passwd"> ]>
      <ComicInfo><Title>&leak;</Title></ComicInfo>
      """

      assert {:error, {:names_outside_itself, ["file:///etc/passwd"]}} =
               Document.fields(document)
    end

    test "a host is refused the same way a file is" do
      document = """
      <?xml version="1.0"?>
      <!DOCTYPE ComicInfo [ <!ENTITY leak SYSTEM "http://192.0.2.1/collect"> ]>
      <ComicInfo><Title>&leak;</Title></ComicInfo>
      """

      assert {:error, {:names_outside_itself, ["http://192.0.2.1/collect"]}} =
               Document.fields(document)
    end

    test "a doctype naming an external document is refused" do
      document = """
      <?xml version="1.0"?>
      <!DOCTYPE ComicInfo SYSTEM "file:///etc/passwd">
      <ComicInfo><Title>Issue One</Title></ComicInfo>
      """

      assert {:error, {:names_outside_itself, ["file:///etc/passwd"]}} =
               Document.fields(document)
    end

    test "nothing it named reaches the fields or the refusal" do
      # /etc/passwd begins `root:` on every system this runs on, so its absence from the
      # whole answer is what says the file was never opened.
      document = """
      <?xml version="1.0"?>
      <!DOCTYPE ComicInfo [ <!ENTITY leak SYSTEM "file:///etc/passwd"> ]>
      <ComicInfo><Title>&leak;</Title></ComicInfo>
      """

      assert File.read!("/etc/passwd") =~ "root:"
      assert {:error, refusal} = Document.fields(document)
      refute inspect(refusal) =~ "root:"
    end
  end

  describe "a document that will not parse" do
    test "nested entity definitions are refused rather than expanded" do
      # Six levels of ten references each is a megabyte from a few hundred bytes, and the
      # next level is ten megabytes.
      document = """
      <?xml version="1.0"?>
      <!DOCTYPE ComicInfo [
        <!ENTITY a "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">
        <!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">
        <!ENTITY c "&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;">
        <!ENTITY d "&c;&c;&c;&c;&c;&c;&c;&c;&c;&c;">
        <!ENTITY e "&d;&d;&d;&d;&d;&d;&d;&d;&d;&d;">
        <!ENTITY f "&e;&e;&e;&e;&e;&e;&e;&e;&e;&e;">
      ]>
      <ComicInfo><Title>&f;</Title></ComicInfo>
      """

      assert {:error, {:unparseable, _complaint}} = Document.fields(document)
    end

    test "an unclosed element is refused" do
      assert {:error, {:unparseable, _complaint}} =
               Document.fields(~s(<ComicInfo><Title>Issue One</ComicInfo>))
    end

    test "bytes that are not markup at all are refused" do
      assert {:error, {:unparseable, _complaint}} = Document.fields(<<0xFF, 0xD8, 0xFF, 0xE0>>)
    end
  end
end
