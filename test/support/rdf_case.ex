defmodule RDF.Test.Case do
  use ExUnit.CaseTemplate

  use RDF.Vocabulary.Namespace
  defvocab EX, base_iri: "http://example.com/", terms: [], strict: false

  defvocab FOAF, base_iri: "http://xmlns.com/foaf/0.1/", terms: [], strict: false

  alias RDF.{Dataset, Graph, Description, IRI}
  import RDF, only: [iri: 1]

  using do
    quote do
      alias RDF.{Dataset, Graph, Description, IRI, XSD}
      alias unquote(__MODULE__).{EX, FOAF}

      import RDF, only: [iri: 1, literal: 1, bnode: 1]
      import unquote(__MODULE__)

      import RDF.Sigils

      @compile {:no_warn_undefined, RDF.Test.Case.EX}
      @compile {:no_warn_undefined, RDF.Test.Case.FOAF}
    end
  end

  ###############################
  # RDF.Description

  def description, do: Description.new(EX.Subject)
  def description(content), do: Description.add(description(), content)

  def description_of_subject(%Description{subject: subject}, subject),
    do: true

  def description_of_subject(_, _),
    do: false

  def empty_description(%Description{predications: predications}),
    do: predications == %{}

  def description_includes_predication(desc, {predicate, object}) do
    desc.predications
    |> Map.get(predicate, %{})
    |> Enum.member?({object, nil})
  end

  ###############################
  # RDF.Graph

  def graph, do: unnamed_graph()

  def unnamed_graph, do: Graph.new()

  def named_graph(name \\ EX.GraphName), do: Graph.new(name: name)

  def unnamed_graph?(%Graph{name: nil}), do: true
  def unnamed_graph?(_), do: false

  def named_graph?(%Graph{name: %IRI{}}), do: true
  def named_graph?(_), do: false
  def named_graph?(%Graph{name: name}, name), do: true
  def named_graph?(_, _), do: false

  def empty_graph?(%Graph{descriptions: descriptions}),
    do: descriptions == %{}

  def graph_includes_statement?(graph, {subject, _, _} = statement) do
    graph.descriptions
    |> Map.get(iri(subject), %{})
    |> Enum.member?(statement)
  end

  ###############################
  # RDF.Dataset

  def dataset, do: unnamed_dataset()

  def unnamed_dataset, do: Dataset.new()

  def named_dataset(name \\ EX.DatasetName), do: Dataset.new(name: name)

  def unnamed_dataset?(%Dataset{name: nil}), do: true
  def unnamed_dataset?(_), do: false

  def named_dataset?(%Dataset{name: %IRI{}}), do: true
  def named_dataset?(_), do: false
  def named_dataset?(%Dataset{name: name}, name), do: true
  def named_dataset?(_, _), do: false

  def empty_dataset?(%Dataset{graphs: graphs}), do: graphs == %{}

  def dataset_includes_statement?(dataset, {_, _, _} = statement) do
    dataset
    |> Dataset.default_graph()
    |> graph_includes_statement?(statement)
  end

  def dataset_includes_statement?(dataset, {subject, predicate, objects, nil}),
    do: dataset_includes_statement?(dataset, {subject, predicate, objects})

  def dataset_includes_statement?(
        dataset,
        {subject, predicate, objects, graph_context}
      ) do
    dataset.graphs
    |> Map.get(iri(graph_context), named_graph(graph_context))
    |> graph_includes_statement?({subject, predicate, objects})
  end
end
