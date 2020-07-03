defmodule RDF.TestSuite do
  defmodule NS do
    use RDF.Vocabulary.Namespace

    defvocab MF,
      base_iri: "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#",
      terms: [],
      strict: false

    defvocab RDFT,
      base_iri: "http://www.w3.org/ns/rdftest#",
      terms: ~w[
        TestTurtleEval
        TestTurtlePositiveSyntax
        TestTurtleNegativeSyntax
        TestTurtleNegativeEval
      ],
      strict: false
  end

  @compile {:no_warn_undefined, RDF.TestSuite.NS.MF}
  @compile {:no_warn_undefined, RDF.TestSuite.NS.RDFT}

  alias NS.MF

  alias RDF.{Turtle, Graph, Description, IRI}

  def dir(format), do: Path.join(RDF.TestData.dir(), String.upcase(format) <> "-TESTS")
  def file(filename, format), do: format |> dir |> Path.join(filename)
  def manifest_path(format), do: file("manifest.ttl", format)

  def manifest_graph(format, opts \\ []) do
    format
    |> manifest_path
    |> Turtle.read_file!(opts)
  end

  def test_cases(format, test_type, opts) do
    format
    |> manifest_graph(opts)
    |> Graph.descriptions()
    |> Enum.filter(fn description ->
      RDF.iri(test_type) in Description.get(description, RDF.type(), [])
    end)
  end

  def test_name(test_case), do: value(test_case, MF.name())

  def test_title(test_case),
    # Unfortunately OTP < 20 doesn't support unicode characters in atoms,
    # so we can't put the description in the test name
    #    do: test_name(test_case) <> ": " <> value(test_case, RDFS.comment)
    do: test_name(test_case)

  def test_input_file(test_case),
    do: test_case |> Description.first(MF.action()) |> IRI.parse()

  def test_output_file(test_case),
    do: test_case |> Description.first(MF.result()) |> IRI.parse()

  def test_input_file_path(test_case, format),
    do: test_input_file(test_case).path |> Path.basename() |> file(format)

  def test_result_file_path(test_case, format),
    do: test_output_file(test_case).path |> Path.basename() |> file(format)

  defp value(description, property),
    do: Description.first(description, property) |> to_string
end
