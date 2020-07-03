defmodule RDF.Turtle.Encoder do
  @moduledoc false

  use RDF.Serialization.Encoder

  alias RDF.Turtle.Encoder.State
  alias RDF.{BlankNode, Dataset, Description, Graph, IRI, XSD, Literal, LangString}

  @indentation_char " "
  @indentation 4

  @native_supported_datatypes [
    XSD.Boolean,
    XSD.Integer,
    XSD.Double,
    XSD.Decimal
  ]
  @rdf_type RDF.Utils.Bootstrapping.rdf_iri("type")
  @rdf_nil RDF.Utils.Bootstrapping.rdf_iri("nil")

  # Defines rdf:type of subjects to be serialized at the beginning of the encoded graph
  @top_classes [RDF.Utils.Bootstrapping.rdfs_iri("Class")]

  # Defines order of predicates at the beginning of a resource description
  @predicate_order [
    @rdf_type,
    RDF.Utils.Bootstrapping.rdfs_iri("label"),
    RDF.iri("http://purl.org/dc/terms/title")
  ]
  @ordered_properties MapSet.new(@predicate_order)

  @impl RDF.Serialization.Encoder
  @callback encode(Graph.t() | Dataset.t(), keyword | map) :: {:ok, String.t()} | {:error, any}
  def encode(data, opts \\ []) do
    with base =
           Keyword.get(opts, :base, Keyword.get(opts, :base_iri))
           |> base_iri(data)
           |> init_base_iri(),
         prefixes = Keyword.get(opts, :prefixes) |> prefixes(data) |> init_prefixes(),
         {:ok, state} = State.start_link(data, base, prefixes) do
      try do
        State.preprocess(state)

        {:ok,
         base_directive(base) <>
           prefix_directives(prefixes) <>
           graph_statements(state)}
      after
        State.stop(state)
      end
    end
  end

  defp base_iri(nil, %RDF.Graph{base_iri: base_iri}) when not is_nil(base_iri), do: base_iri
  defp base_iri(nil, _), do: RDF.default_base_iri()
  defp base_iri(base_iri, _), do: RDF.iri(base_iri)

  defp init_base_iri(nil), do: nil

  defp init_base_iri(base_iri) do
    base_iri = to_string(base_iri)

    if String.ends_with?(base_iri, ~w[/ #]) do
      {:ok, base_iri}
    else
      IO.warn("invalid base_iri: #{base_iri}")
      {:bad, base_iri}
    end
  end

  defp prefixes(nil, %RDF.Graph{prefixes: prefixes}) when not is_nil(prefixes), do: prefixes
  defp prefixes(nil, _), do: RDF.default_prefixes()
  defp prefixes(prefixes, _), do: RDF.PrefixMap.new(prefixes)

  defp init_prefixes(prefixes) do
    Enum.reduce(prefixes, %{}, fn {prefix, iri}, reverse ->
      Map.put(reverse, iri, to_string(prefix))
    end)
  end

  defp base_directive(nil), do: ""
  defp base_directive({_, base}), do: "@base <#{base}> .\n"

  defp prefix_directive({ns, prefix}), do: "@prefix #{prefix}: <#{to_string(ns)}> .\n"

  defp prefix_directives(prefixes) do
    case Enum.map(prefixes, &prefix_directive/1) do
      [] -> ""
      prefixes -> Enum.join(prefixes, "") <> "\n"
    end
  end

  defp graph_statements(state) do
    State.data(state)
    |> RDF.Data.descriptions()
    |> order_descriptions(state)
    |> Enum.map(&description_statements(&1, state))
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp order_descriptions(descriptions, state) do
    base_iri = State.base_iri(state)

    group =
      Enum.group_by(descriptions, fn
        %Description{subject: ^base_iri} ->
          :base

        description ->
          with types when not is_nil(types) <- description.predications[@rdf_type] do
            Enum.find(@top_classes, :other, fn top_class ->
              Map.has_key?(types, top_class)
            end)
          else
            _ -> :other
          end
      end)

    ordered_descriptions =
      (@top_classes
       |> Stream.map(fn top_class -> group[top_class] end)
       |> Stream.reject(&is_nil/1)
       |> Stream.map(&sort_description_group/1)
       |> Enum.reduce([], fn class_group, ordered_descriptions ->
         ordered_descriptions ++ class_group
       end)) ++ (group |> Map.get(:other, []) |> sort_description_group())

    case group[:base] do
      [base] -> [base | ordered_descriptions]
      _ -> ordered_descriptions
    end
  end

  defp sort_description_group(descriptions) do
    Enum.sort(descriptions, fn
      %Description{subject: %IRI{}}, %Description{subject: %BlankNode{}} ->
        true

      %Description{subject: %BlankNode{}}, %Description{subject: %IRI{}} ->
        false

      %Description{subject: s1}, %Description{subject: s2} ->
        to_string(s1) < to_string(s2)
    end)
  end

  defp description_statements(description, state, nesting \\ 0) do
    with %BlankNode{} <- description.subject,
         ref_count when ref_count < 2 <-
           State.bnode_ref_counter(state, description.subject) do
      unrefed_bnode_subject_term(description, ref_count, state, nesting)
    else
      _ -> full_description_statements(description, state, nesting)
    end
  end

  defp full_description_statements(subject, description, state, nesting) do
    with nesting = nesting + @indentation do
      subject <> newline_indent(nesting) <> predications(description, state, nesting) <> " .\n"
    end
  end

  defp full_description_statements(description, state, nesting) do
    term(description.subject, state, :subject, nesting)
    |> full_description_statements(description, state, nesting)
  end

  defp blank_node_property_list(description, state, nesting) do
    with indented = nesting + @indentation do
      "[" <>
        newline_indent(indented) <>
        predications(description, state, indented) <>
        newline_indent(nesting) <> "]"
    end
  end

  defp predications(description, state, nesting) do
    description.predications
    |> order_predications()
    |> Enum.map(&predication(&1, state, nesting))
    |> Enum.join(" ;" <> newline_indent(nesting))
  end

  @dialyzer {:nowarn_function, order_predications: 1}
  defp order_predications(predications) do
    sorted_predications =
      @predicate_order
      |> Enum.map(fn predicate -> {predicate, predications[predicate]} end)
      |> Enum.reject(fn {_, objects} -> is_nil(objects) end)

    unsorted_predications =
      Enum.reject(predications, fn {predicate, _} ->
        MapSet.member?(@ordered_properties, predicate)
      end)

    sorted_predications ++ unsorted_predications
  end

  defp predication({predicate, objects}, state, nesting) do
    term(predicate, state, :predicate, nesting) <>
      " " <>
      (objects
       |> Enum.map(fn {object, _} -> term(object, state, :object, nesting) end)
       # TODO: split if the line gets too long
       |> Enum.join(", "))
  end

  defp unrefed_bnode_subject_term(bnode_description, ref_count, state, nesting) do
    if valid_list_node?(bnode_description.subject, state) do
      case ref_count do
        0 ->
          bnode_description.subject
          |> list_term(state, nesting)
          |> full_description_statements(
            list_subject_description(bnode_description),
            state,
            nesting
          )

        1 ->
          nil

        _ ->
          raise "Internal error: This shouldn't happen. Please raise an issue in the RDF.ex project with the input document causing this error."
      end
    else
      case ref_count do
        0 ->
          blank_node_property_list(bnode_description, state, nesting) <> " .\n"

        1 ->
          nil

        _ ->
          raise "Internal error: This shouldn't happen. Please raise an issue in the RDF.ex project with the input document causing this error."
      end
    end
  end

  @dialyzer {:nowarn_function, list_subject_description: 1}
  defp list_subject_description(description) do
    with description = Description.delete_predicates(description, [RDF.first(), RDF.rest()]) do
      if Enum.count(description.predications) == 0 do
        # since the Turtle grammar doesn't allow bare lists, we add a statement
        description |> RDF.type(RDF.List)
      else
        description
      end
    end
  end

  defp unrefed_bnode_object_term(bnode, ref_count, state, nesting) do
    if valid_list_node?(bnode, state) do
      list_term(bnode, state, nesting)
    else
      if ref_count == 1 do
        State.data(state)
        |> RDF.Data.description(bnode)
        |> blank_node_property_list(state, nesting)
      else
        raise "Internal error: This shouldn't happen. Please raise an issue in the RDF.ex project with the input document causing this error."
      end
    end
  end

  defp valid_list_node?(bnode, state) do
    MapSet.member?(State.list_nodes(state), bnode)
  end

  defp list_term(head, state, nesting) do
    head
    |> State.list_values(state)
    |> term(state, :list, nesting)
  end

  defp term(@rdf_type, _, :predicate, _), do: "a"
  defp term(@rdf_nil, _, _, _), do: "()"

  defp term(%IRI{} = iri, state, _, _) do
    based_name(iri, State.base(state)) ||
      prefixed_name(iri, State.prefixes(state)) ||
      "<#{to_string(iri)}>"
  end

  defp term(%BlankNode{} = bnode, state, position, nesting)
       when position in ~w[object list]a do
    if (ref_count = State.bnode_ref_counter(state, bnode)) <= 1 do
      unrefed_bnode_object_term(bnode, ref_count, state, nesting)
    else
      to_string(bnode)
    end
  end

  defp term(%BlankNode{} = bnode, _, _, _),
    do: to_string(bnode)

  defp term(%Literal{literal: %LangString{} = lang_string}, _, _, _) do
    ~s["#{lang_string.value}"@#{lang_string.language}]
  end

  defp term(%Literal{literal: %XSD.String{}} = literal, _, _, _) do
    literal |> Literal.lexical() |> quoted()
  end

  defp term(%Literal{literal: %datatype{}} = literal, state, _, nesting)
       when datatype in @native_supported_datatypes do
    if Literal.valid?(literal) do
      Literal.canonical_lexical(literal)
    else
      typed_literal_term(literal, state, nesting)
    end
  end

  defp term(%Literal{} = literal, state, _, nesting),
    do: typed_literal_term(literal, state, nesting)

  defp term(list, state, _, nesting) when is_list(list) do
    "(" <>
      (list
       |> Enum.map(&term(&1, state, :list, nesting))
       |> Enum.join(" ")) <>
      ")"
  end

  defp based_name(%IRI{} = iri, base), do: based_name(to_string(iri), base)

  defp based_name(iri, {:ok, base}) do
    if String.starts_with?(iri, base) do
      "<#{String.slice(iri, String.length(base)..-1)}>"
    end
  end

  defp based_name(_, _), do: nil

  defp typed_literal_term(%Literal{} = literal, state, nesting),
    do:
      ~s["#{Literal.lexical(literal)}"^^#{
        literal |> Literal.datatype_id() |> term(state, :datatype, nesting)
      }]

  def prefixed_name(iri, prefixes) do
    with {ns, name} <- split_iri(iri) do
      case prefixes[ns] do
        nil -> nil
        prefix -> prefix <> ":" <> name
      end
    end
  end

  defp split_iri(%IRI{} = iri),
    do: iri |> IRI.parse() |> split_iri()

  defp split_iri(%URI{fragment: fragment} = uri) when not is_nil(fragment),
    do: {RDF.iri(%URI{uri | fragment: ""}), fragment}

  defp split_iri(%URI{path: nil}),
    do: nil

  defp split_iri(%URI{path: path} = uri) do
    with [{pos, _}] = Regex.run(~r"[^/]*$"u, path, return: :index),
         {ns_path, name} = String.split_at(path, pos) do
      {RDF.iri(%URI{uri | path: ns_path}), name}
    end
  end

  defp quoted(string) do
    if String.contains?(string, ["\n", "\r"]) do
      ~s["""#{string}"""]
    else
      ~s["#{escape(string)}"]
    end
  end

  defp escape(string) do
    string
    |> String.replace("\\", "\\\\\\\\")
    |> String.replace("\b", "\\b")
    |> String.replace("\f", "\\f")
    |> String.replace("\t", "\\t")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\"", ~S[\"])
  end

  defp newline_indent(nesting),
    do: "\n" <> String.duplicate(@indentation_char, nesting)
end
