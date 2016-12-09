defmodule RDF.NTriples.ReaderTest do
  use ExUnit.Case, async: false

  doctest RDF.NTriples.Reader

  alias RDF.{Graph}

  defmodule EX, do: use RDF.Vocabulary, base_uri: "http://example.org/#"
  defmodule P,  do: use RDF.Vocabulary, base_uri: "http://www.perceive.net/schemas/relationship/"

  @w3c_ntriples_test_suite Path.join(File.cwd!, "test/data/N-TRIPLES-TESTS")

  test "an empty string is deserialized to an empty graph" do
    assert RDF.NTriples.Reader.read!("") == Graph.new
    assert RDF.NTriples.Reader.read!("  \n\r\r\n  ") == Graph.new
  end

  test "reading comments" do
    assert RDF.NTriples.Reader.read!("# just a comment") == Graph.new

    assert RDF.NTriples.Reader.read!("""
      <http://example.org/#S> <http://example.org/#p> _:1 . # a comment
      """) == Graph.new({EX.S, EX.p, RDF.bnode("1")})

    assert RDF.NTriples.Reader.read!("""
      # a comment
      <http://example.org/#S> <http://example.org/#p> <http://example.org/#O> .
      """) == Graph.new({EX.S, EX.p, EX.O})

    assert RDF.NTriples.Reader.read!("""
      <http://example.org/#S> <http://example.org/#p> <http://example.org/#O> .
      # a comment
      """) == Graph.new({EX.S, EX.p, EX.O})

    assert RDF.NTriples.Reader.read!("""
      # Header line 1
      # Header line 2
      <http://example.org/#S1> <http://example.org/#p1> <http://example.org/#O1> .
      # 1st comment
      <http://example.org/#S1> <http://example.org/#p2> <http://example.org/#O2> . # 2nd comment
      # last comment
      """) == Graph.new([
        {EX.S1, EX.p1, EX.O1},
        {EX.S1, EX.p2, EX.O2},
      ])
  end

  test "empty lines" do
    assert RDF.NTriples.Reader.read!("""

      <http://example.org/#spiderman> <http://www.perceive.net/schemas/relationship/enemyOf> <http://example.org/#green_goblin> .
      """) == Graph.new({EX.spiderman, P.enemyOf, EX.green_goblin})

    assert RDF.NTriples.Reader.read!("""
      <http://example.org/#spiderman> <http://www.perceive.net/schemas/relationship/enemyOf> <http://example.org/#green_goblin> .

      """) == Graph.new({EX.spiderman, P.enemyOf, EX.green_goblin})

    assert RDF.NTriples.Reader.read!("""

      <http://example.org/#S1> <http://example.org/#p1> <http://example.org/#O1> .


      <http://example.org/#S1> <http://example.org/#p2> <http://example.org/#O2> .

      """) == Graph.new([
        {EX.S1, EX.p1, EX.O1},
        {EX.S1, EX.p2, EX.O2},
      ])
  end

  test "reading a single triple uris" do
    assert RDF.NTriples.Reader.read!("""
      <http://example.org/#spiderman> <http://www.perceive.net/schemas/relationship/enemyOf> <http://example.org/#green_goblin> .
      """) == Graph.new({EX.spiderman, P.enemyOf, EX.green_goblin})
  end

  test "reading a single triple with a blank node" do
    assert RDF.NTriples.Reader.read!("""
      _:foo <http://example.org/#p> <http://example.org/#O> .
      """) == Graph.new({RDF.bnode("foo"), EX.p, EX.O})
    assert RDF.NTriples.Reader.read!("""
      <http://example.org/#S> <http://example.org/#p> _:1 .
      """) == Graph.new({EX.S, EX.p, RDF.bnode("1")})
    assert RDF.NTriples.Reader.read!("""
      _:foo <http://example.org/#p> _:bar .
      """) == Graph.new({RDF.bnode("foo"), EX.p, RDF.bnode("bar")})
  end

  test "reading a single triple with an untyped string literal" do
    assert RDF.NTriples.Reader.read!("""
      <http://example.org/#spiderman> <http://www.perceive.net/schemas/relationship/realname> "Peter Parker" .
      """) == Graph.new({EX.spiderman, P.realname, RDF.literal("Peter Parker")})
  end

  test "reading a single triple with a typed literal" do
    assert RDF.NTriples.Reader.read!("""
      <http://example.org/#spiderman> <http://example.org/#p> "42"^^<http://www.w3.org/2001/XMLSchema#integer> .
      """) == Graph.new({EX.spiderman, EX.p, RDF.literal(42)})
  end

  test "reading a single triple with a language tagged literal" do
    assert RDF.NTriples.Reader.read!("""
      <http://example.org/#S> <http://example.org/#p> "foo"@en .
      """) == Graph.new({EX.S, EX.p, RDF.literal("foo", language: "en")})
  end

  test "reading multiple triples" do
    assert RDF.NTriples.Reader.read!("""
      <http://example.org/#S1> <http://example.org/#p1> <http://example.org/#O1> .
      <http://example.org/#S1> <http://example.org/#p2> <http://example.org/#O2> .
      """) == Graph.new([
        {EX.S1, EX.p1, EX.O1},
        {EX.S1, EX.p2, EX.O2},
      ])
    assert RDF.NTriples.Reader.read!("""
      <http://example.org/#S1> <http://example.org/#p1> <http://example.org/#O1> .
      <http://example.org/#S1> <http://example.org/#p2> <http://example.org/#O2> .
      <http://example.org/#S2> <http://example.org/#p3> <http://example.org/#O3> .
      """) == Graph.new([
        {EX.S1, EX.p1, EX.O1},
        {EX.S1, EX.p2, EX.O2},
        {EX.S2, EX.p3, EX.O3}
      ])
  end

  describe "the official W3C RDF 1.1 N-Triples Test Suite" do
    # from https://www.w3.org/2013/N-TriplesTests/

    ExUnit.Case.register_attribute __ENV__, :nt_test

    @w3c_ntriples_test_suite
    |> File.ls!
    |> Enum.filter(fn (file) -> Path.extname(file) == ".nt" end)
    |> Enum.each(fn (file) ->
      @nt_test file: Path.join(@w3c_ntriples_test_suite, file)
      if file |> String.contains?("-bad-") do
        test "Negative syntax test: #{file}", context do
          assert {:error, _} = RDF.NTriples.Reader.read_file(context.registered.nt_test[:file])
        end
      else
        test "Positive syntax test: #{file}", context do
          assert {:ok, %RDF.Graph{}} = RDF.NTriples.Reader.read_file(context.registered.nt_test[:file])
        end
      end
    end)

  end

end