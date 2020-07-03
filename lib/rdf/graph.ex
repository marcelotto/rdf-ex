defmodule RDF.Graph do
  @moduledoc """
  A set of RDF triples with an optional name.

  `RDF.Graph` implements:

  - Elixir's `Access` behaviour
  - Elixir's `Enumerable` protocol
  - Elixir's `Inspect` protocol
  - the `RDF.Data` protocol

  """

  @behaviour Access

  import RDF.Statement
  alias RDF.{Description, IRI, PrefixMap, Statement}

  @type graph_description :: %{Statement.subject => Description.t}

  @type t :: %__MODULE__{
          name: IRI.t | nil,
          descriptions: graph_description,
          prefixes: PrefixMap.t | nil,
          base_iri: IRI.t | nil
  }

  @type input :: Statement.t | Description.t | t

  @type update_description_fun :: (Description.t -> Description.t)

  @type get_and_update_description_fun :: (Description.t -> {Description.t, input} | :pop)

  defstruct name: nil, descriptions: %{}, prefixes: nil, base_iri: nil


  @doc """
  Creates an empty unnamed `RDF.Graph`.
  """
  @spec new :: t
  def new, do: %RDF.Graph{}

  @doc """
  Creates an `RDF.Graph`.

  If a keyword list is given an empty graph is created.
  Otherwise an unnamed graph initialized with the given data is created.

  See `new/2` for available arguments and the different ways to provide data.

  ## Examples

      RDF.Graph.new({EX.S, EX.p, EX.O})

      RDF.Graph.new(name: EX.GraphName)

  """
  @spec new(input | [input] | keyword) :: t
  def new(data_or_options)

  def new(data_or_options)
      when is_list(data_or_options) and length(data_or_options) != 0 do
    if Keyword.keyword?(data_or_options) do
      new([], data_or_options)
    else
      new(data_or_options, [])
    end
  end

  def new(data), do: new(data, [])

  @doc """
  Creates an `RDF.Graph` initialized with data.

  The initial RDF triples can be provided

  - as a single statement tuple
  - an `RDF.Description`
  - an `RDF.Graph`
  - or a list with any combination of the former

  Available options:

  - `name`: the name of the graph to be created
  - `prefixes`: some prefix mappings which should be stored alongside the graph
    and will be used for example when serializing in a format with prefix support
  - `base_iri`: a base IRI which should be stored alongside the graph
    and will be used for example when serializing in a format with base IRI support

  ## Examples

      RDF.Graph.new({EX.S, EX.p, EX.O})
      RDF.Graph.new({EX.S, EX.p, EX.O}, name: EX.GraphName)
      RDF.Graph.new({EX.S, EX.p, [EX.O1, EX.O2]})
      RDF.Graph.new([{EX.S1, EX.p1, EX.O1}, {EX.S2, EX.p2, EX.O2}])
      RDF.Graph.new(RDF.Description.new(EX.S, EX.P, EX.O))
      RDF.Graph.new([graph, description, triple])
      RDF.Graph.new({EX.S, EX.p, EX.O}, name: EX.GraphName, base_iri: EX.base)

  """
  @spec new(input | [input], keyword) :: t
  def new(data, options)

  def new(%RDF.Graph{} = graph, options) do
    %RDF.Graph{graph | name: options |> Keyword.get(:name) |> coerce_graph_name()}
    |> add_prefixes(Keyword.get(options, :prefixes))
    |> set_base_iri(Keyword.get(options, :base_iri))
  end

  def new(data, options) do
    %RDF.Graph{}
    |> new(options)
    |> add(data)
  end

  @doc """
  Creates an `RDF.Graph` with initial triples.

  See `new/2` for available arguments.
  """
  @spec new(
          Statement.coercible_subject,
          Statement.coercible_predicate,
          Statement.coercible_object | [Statement.coercible_object],
          keyword
        ) :: t
  def new(subject, predicate, objects, options \\ []),
    do: new([], options) |> add(subject, predicate, objects)


  @doc """
  Removes all triples from `graph`.

  This function is useful for getting an empty graph based on the settings of
  another graph, as this function keeps graph name name, base IRI and default
  prefixes as they are and just removes the triples.
  """
  @spec clear(t) :: t
  def clear(%RDF.Graph{} = graph) do
    %RDF.Graph{graph | descriptions: %{}}
  end


  @doc """
  Adds triples to a `RDF.Graph`.
  """
  @spec add(
          t,
          Statement.coercible_subject,
          Statement.coercible_predicate,
          Statement.coercible_object | [Statement.coercible_object]
        ) :: t
  def add(%RDF.Graph{} = graph, subject, predicate, objects),
    do: add(graph, {subject, predicate, objects})

  @doc """
  Adds triples to a `RDF.Graph`.

  When the statements to be added are given as another `RDF.Graph`,
  the graph name must not match graph name of the graph to which the statements
  are added. As opposed to that `RDF.Data.merge/2` will produce a `RDF.Dataset`
  containing both graphs.

  Also when the statements to be added are given as another `RDF.Graph`, the
  prefixes of this graph will be added. In case of conflicting prefix mappings
  the original prefix from `graph` will be kept.
  """
  @spec add(t, input | [input]) :: t
  def add(graph, triples)

  def add(%RDF.Graph{} = graph, {subject, _, _} = statement),
    do: do_add(graph, coerce_subject(subject), statement)

  def add(graph, {subject, predicate, object, _}),
    do: add(graph, {subject, predicate, object})

  def add(graph, triples) when is_list(triples) do
    Enum.reduce triples, graph, fn (triple, graph) ->
      add(graph, triple)
    end
  end

  def add(%RDF.Graph{} = graph, %Description{subject: subject} = description) do
    if Description.count(description) > 0 do
      do_add(graph, subject, description)
    else
      graph
    end
  end

  def add(graph, %RDF.Graph{descriptions: descriptions, prefixes: prefixes}) do
    graph =
      Enum.reduce descriptions, graph, fn ({_, description}, graph) ->
        add(graph, description)
      end

    if prefixes do
      add_prefixes(graph, prefixes, fn _, ns, _ -> ns end)
    else
      graph
    end
  end

  defp do_add(%RDF.Graph{descriptions: descriptions} = graph, subject, statements) do
    %RDF.Graph{graph |
      descriptions:
        Map.update(descriptions, subject, Description.new(statements),
          fn description ->
            Description.add(description, statements)
          end)
    }
  end


  @doc """
  Adds statements to a `RDF.Graph` and overwrites all existing statements with the same subjects and predicates.

  When the statements to be added are given as another `RDF.Graph`, the prefixes
  of this graph will be added. In case of conflicting prefix mappings the
  original prefix from `graph` will be kept.

  ## Examples

      iex> RDF.Graph.new([{EX.S1, EX.P1, EX.O1}, {EX.S2, EX.P2, EX.O2}]) |>
      ...>   RDF.Graph.put([{EX.S1, EX.P2, EX.O3}, {EX.S2, EX.P2, EX.O3}])
      RDF.Graph.new([{EX.S1, EX.P1, EX.O1}, {EX.S1, EX.P2, EX.O3}, {EX.S2, EX.P2, EX.O3}])

  """
  @spec put(t, input | [input]) :: t
  def put(graph, statements)

  def put(%RDF.Graph{} = graph, {subject, _, _} = statement),
    do: do_put(graph, coerce_subject(subject), statement)

  def put(graph, {subject, predicate, object, _}),
    do: put(graph, {subject, predicate, object})

  def put(%RDF.Graph{} = graph, %Description{subject: subject} = description),
    do: do_put(graph, subject, description)

  def put(graph, %RDF.Graph{descriptions: descriptions, prefixes: prefixes}) do
    graph =
      Enum.reduce descriptions, graph, fn ({_, description}, graph) ->
        put(graph, description)
      end

    if prefixes do
      add_prefixes(graph, prefixes, fn _, ns, _ -> ns end)
    else
      graph
    end
  end

  def put(%RDF.Graph{} = graph, statements) when is_map(statements) do
    Enum.reduce statements, graph, fn ({subject, predications}, graph) ->
      put(graph, subject, predications)
    end
  end

  def put(%RDF.Graph{} = graph, statements) when is_list(statements) do
    put(graph, Enum.group_by(statements, &(elem(&1, 0)), fn {_, p, o} -> {p, o} end))
  end

  @doc """
  Add statements to a `RDF.Graph`, overwriting all statements with the same subject and predicate.
  """
  @spec put(t, Statement.coercible_subject, Description.statements | [Description.statements]) :: t
  def put(graph, subject, predications)

  def put(%RDF.Graph{descriptions: descriptions} = graph, subject, predications)
        when is_list(predications) do
    with subject = coerce_subject(subject) do
      # TODO: Can we reduce this case also to do_put somehow? Only the initializer of Map.update differs ...
      %RDF.Graph{graph |
        descriptions:
          Map.update(descriptions, subject, Description.new(subject, predications),
            fn current ->
              Description.put(current, predications)
            end)
      }
    end
  end

  def put(graph, subject, {_predicate, _objects} = predications),
    do: put(graph, subject, [predications])

  defp do_put(%RDF.Graph{descriptions: descriptions} = graph, subject, statements) do
    %RDF.Graph{graph |
      descriptions:
        Map.update(descriptions, subject, Description.new(statements),
          fn current ->
            Description.put(current, statements)
          end)
    }
  end

  @doc """
  Add statements to a `RDF.Graph`, overwriting all statements with the same subject and predicate.

  ## Examples

      iex> RDF.Graph.new(EX.S, EX.P, EX.O1) |> RDF.Graph.put(EX.S, EX.P, EX.O2)
      RDF.Graph.new(EX.S, EX.P, EX.O2)
      iex> RDF.Graph.new(EX.S, EX.P1, EX.O1) |> RDF.Graph.put(EX.S, EX.P2, EX.O2)
      RDF.Graph.new([{EX.S, EX.P1, EX.O1}, {EX.S, EX.P2, EX.O2}])

  """
  @spec put(
          t,
          Statement.coercible_subject,
          Statement.coercible_predicate,
          Statement.coercible_object | [Statement.coercible_object]
        ) :: t
  def put(%RDF.Graph{} = graph, subject, predicate, objects),
    do: put(graph, {subject, predicate, objects})


  @doc """
  Deletes statements from a `RDF.Graph`.
  """
  @spec delete(
          t,
          Statement.coercible_subject,
          Statement.coercible_predicate,
          Statement.coercible_object | [Statement.coercible_object]
        ) :: t
  def delete(graph, subject, predicate, object),
    do: delete(graph, {subject, predicate, object})

  @doc """
  Deletes statements from a `RDF.Graph`.

  Note: When the statements to be deleted are given as another `RDF.Graph`,
  the graph name must not match graph name of the graph from which the statements
  are deleted. If you want to delete only graphs with matching names, you can
  use `RDF.Data.delete/2`.

  """
  @spec delete(t, input | [input]) :: t
  def delete(graph, triples)

  def delete(%RDF.Graph{} = graph, {subject, _, _} = triple),
    do: do_delete(graph, coerce_subject(subject), triple)

  def delete(graph, {subject, predicate, object, _}),
    do: delete(graph, {subject, predicate, object})

  def delete(%RDF.Graph{} = graph, triples) when is_list(triples) do
    Enum.reduce triples, graph, fn (triple, graph) ->
      delete(graph, triple)
    end
  end

  def delete(%RDF.Graph{} = graph, %Description{subject: subject} = description),
    do: do_delete(graph, subject, description)

  def delete(%RDF.Graph{} = graph, %RDF.Graph{descriptions: descriptions}) do
    Enum.reduce descriptions, graph, fn ({_, description}, graph) ->
      delete(graph, description)
    end
  end

  defp do_delete(%RDF.Graph{descriptions: descriptions} = graph,
                 subject, statements) do
    with description when not is_nil(description) <- descriptions[subject],
         new_description = Description.delete(description, statements)
    do
      %RDF.Graph{graph |
        descriptions:
          if Enum.empty?(new_description) do
            Map.delete(descriptions, subject)
          else
            Map.put(descriptions, subject, new_description)
          end
      }
    else
      nil -> graph
    end
  end


  @doc """
  Deletes all statements with the given subjects.
  """
  @spec delete_subjects(
        t,
        Statement.coercible_subject | [Statement.coercible_subject]
      ) :: t
  def delete_subjects(graph, subjects)

  def delete_subjects(%RDF.Graph{} = graph, subjects) when is_list(subjects) do
    Enum.reduce subjects, graph, fn (subject, graph) ->
      delete_subjects(graph, subject)
    end
  end

  def delete_subjects(%RDF.Graph{descriptions: descriptions} = graph, subject) do
    with subject = coerce_subject(subject) do
      %RDF.Graph{graph | descriptions: Map.delete(descriptions, subject)}
    end
  end


  @doc """
  Updates the description of the `subject` in `graph` with the given function.

  If `subject` is present in `graph` with `description` as description,
  `fun` is invoked with argument `description` and its result is used as the new
  description of `subject`. If `subject` is not present in `graph`,
  `initial` is inserted as the description of `subject`. The initial value will
  not be passed through the update function.

  The initial value and the returned objects by the update function will be tried
  te coerced to proper RDF descriptions before added. If the initial or returned
  description is a `RDF.Description` with another subject, the respective
  statements are added with `subject` as subject.

  ## Examples

      iex> RDF.Graph.new({EX.S, EX.p, EX.O}) |>
      ...>   RDF.Graph.update(EX.S,
      ...>     fn description -> Description.add(description, EX.p, EX.O2) end)
      RDF.Graph.new([{EX.S, EX.p, EX.O}, {EX.S, EX.p, EX.O2}])
      iex> RDF.Graph.new({EX.S, EX.p, EX.O}) |>
      ...>   RDF.Graph.update(EX.S,
      ...>     fn _ -> Description.new(EX.S2, EX.p2, EX.O2) end)
      RDF.Graph.new([{EX.S, EX.p2, EX.O2}])
      iex> RDF.Graph.new() |>
      ...>   RDF.Graph.update(EX.S, Description.new({EX.S, EX.p, EX.O}),
      ...>     fn description -> Description.add(description, EX.p, EX.O2) end)
      RDF.Graph.new([{EX.S, EX.p, EX.O}])

  """
  @spec update(
          t,
          Statement.coercible_subject,
          Description.statements | [Description.statements] | nil,
          update_description_fun
        ) :: t
  def update(graph = %RDF.Graph{}, subject, initial \\ nil, fun) do
    subject = coerce_subject(subject)

    case get(graph, subject) do
      nil ->
        if initial do
          add(graph, Description.new(subject, initial))
        else
          graph
        end

      description ->
        description
        |> fun.()
        |> case do
             nil ->
               delete_subjects(graph, subject)

             new_description ->
               graph
               |> delete_subjects(subject)
               |> add(Description.new(subject, new_description))
           end
    end
  end


  @doc """
  Fetches the description of the given subject.

  When the subject can not be found `:error` is returned.

  ## Examples

      iex> RDF.Graph.new([{EX.S1, EX.P1, EX.O1}, {EX.S2, EX.P2, EX.O2}]) |>
      ...>   RDF.Graph.fetch(EX.S1)
      {:ok, RDF.Description.new({EX.S1, EX.P1, EX.O1})}
      iex> RDF.Graph.fetch(RDF.Graph.new, EX.foo)
      :error

  """
  @impl Access
  @spec fetch(t, Statement.coercible_subject) :: {:ok, Description.t} | :error
  def fetch(%RDF.Graph{descriptions: descriptions}, subject) do
    Access.fetch(descriptions, coerce_subject(subject))
  end

  @doc """
  Gets the description of the given subject.

  When the subject can not be found the optionally given default value or `nil` is returned.

  ## Examples

      iex> RDF.Graph.new([{EX.S1, EX.P1, EX.O1}, {EX.S2, EX.P2, EX.O2}]) |>
      ...>   RDF.Graph.get(EX.S1)
      RDF.Description.new({EX.S1, EX.P1, EX.O1})
      iex> RDF.Graph.get(RDF.Graph.new, EX.Foo)
      nil
      iex> RDF.Graph.get(RDF.Graph.new, EX.Foo, :bar)
      :bar

  """
  @spec get(t, Statement.coercible_subject, Description.t | nil) :: Description.t | nil
  def get(%RDF.Graph{} = graph, subject, default \\ nil) do
    case fetch(graph, subject) do
      {:ok, value} -> value
      :error       -> default
    end
  end

  @doc """
  The `RDF.Description` of the given subject.
  """
  @spec description(t, Statement.coercible_subject) :: Description.t | nil
  def description(%RDF.Graph{descriptions: descriptions}, subject),
    do: Map.get(descriptions, coerce_subject(subject))

  @doc """
  All `RDF.Description`s within a `RDF.Graph`.
  """
  @spec descriptions(t) :: [Description.t]
  def descriptions(%RDF.Graph{descriptions: descriptions}),
    do: Map.values(descriptions)


  @doc """
  Gets and updates the description of the given subject, in a single pass.

  Invokes the passed function on the `RDF.Description` of the given subject;
  this function should return either `{description_to_return, new_description}` or `:pop`.

  If the passed function returns `{description_to_return, new_description}`, the
  return value of `get_and_update` is `{description_to_return, new_graph}` where
  `new_graph` is the input `Graph` updated with `new_description` for
  the given subject.

  If the passed function returns `:pop` the description for the given subject is
  removed and a `{removed_description, new_graph}` tuple gets returned.

  ## Examples

      iex> RDF.Graph.new({EX.S, EX.P, EX.O}) |>
      ...>   RDF.Graph.get_and_update(EX.S, fn current_description ->
      ...>     {current_description, {EX.P, EX.NEW}}
      ...>   end)
      {RDF.Description.new(EX.S, EX.P, EX.O), RDF.Graph.new(EX.S, EX.P, EX.NEW)}

  """
  @impl Access
  @spec get_and_update(t, Statement.coercible_subject, get_and_update_description_fun) ::
          {Description.t, input}
  def get_and_update(%RDF.Graph{} = graph, subject, fun) do
    with subject = coerce_subject(subject) do
      case fun.(get(graph, subject)) do
        {old_description, new_description} ->
          {old_description, put(graph, subject, new_description)}
        :pop ->
          pop(graph, subject)
        other ->
          raise "the given function must return a two-element tuple or :pop, got: #{inspect(other)}"
      end
    end
  end


  @doc """
  Pops an arbitrary triple from a `RDF.Graph`.
  """
  @spec pop(t) :: {Statement.t | nil, t}
  def pop(graph)

  def pop(%RDF.Graph{descriptions: descriptions} = graph)
    when descriptions == %{}, do: {nil, graph}

  def pop(%RDF.Graph{descriptions: descriptions} = graph) do
    # TODO: Find a faster way ...
    [{subject, description}] = Enum.take(descriptions, 1)
    {triple, popped_description} = Description.pop(description)
    popped = if Enum.empty?(popped_description),
      do:   descriptions |> Map.delete(subject),
      else: descriptions |> Map.put(subject, popped_description)

    {triple, %RDF.Graph{graph | descriptions: popped}}
  end

  @doc """
  Pops the description of the given subject.

  When the subject can not be found the optionally given default value or `nil` is returned.

  ## Examples

      iex> RDF.Graph.new([{EX.S1, EX.P1, EX.O1}, {EX.S2, EX.P2, EX.O2}]) |>
      ...>   RDF.Graph.pop(EX.S1)
      {RDF.Description.new({EX.S1, EX.P1, EX.O1}), RDF.Graph.new({EX.S2, EX.P2, EX.O2})}
      iex> RDF.Graph.pop(RDF.Graph.new({EX.S, EX.P, EX.O}), EX.Missing)
      {nil, RDF.Graph.new({EX.S, EX.P, EX.O})}

  """
  @impl Access
  @spec pop(t, Statement.coercible_subject) :: {Description.t | nil, t}
  def pop(%RDF.Graph{descriptions: descriptions} = graph, subject) do
    case Access.pop(descriptions, coerce_subject(subject)) do
      {nil, _} ->
        {nil, graph}
      {description, new_descriptions} ->
        {description, %RDF.Graph{graph | descriptions: new_descriptions}}
    end
  end


  @doc """
  The number of subjects within a `RDF.Graph`.

  ## Examples

      iex> RDF.Graph.new([
      ...>   {EX.S1, EX.p1, EX.O1},
      ...>   {EX.S2, EX.p2, EX.O2},
      ...>   {EX.S1, EX.p2, EX.O3}]) |>
      ...>   RDF.Graph.subject_count
      2

  """
  @spec subject_count(t) :: non_neg_integer
  def subject_count(%RDF.Graph{descriptions: descriptions}),
    do: Enum.count(descriptions)

  @doc """
  The number of statements within a `RDF.Graph`.

  ## Examples

      iex> RDF.Graph.new([
      ...>   {EX.S1, EX.p1, EX.O1},
      ...>   {EX.S2, EX.p2, EX.O2},
      ...>   {EX.S1, EX.p2, EX.O3}]) |>
      ...>   RDF.Graph.triple_count
      3

  """
  @spec triple_count(t) :: non_neg_integer
  def triple_count(%RDF.Graph{descriptions: descriptions}) do
    Enum.reduce descriptions, 0, fn ({_subject, description}, count) ->
      count + Description.count(description)
    end
  end

  @doc """
  The set of all subjects used in the statements within a `RDF.Graph`.

  ## Examples

      iex> RDF.Graph.new([
      ...>   {EX.S1, EX.p1, EX.O1},
      ...>   {EX.S2, EX.p2, EX.O2},
      ...>   {EX.S1, EX.p2, EX.O3}]) |>
      ...>   RDF.Graph.subjects
      MapSet.new([RDF.iri(EX.S1), RDF.iri(EX.S2)])
  """
  def subjects(%RDF.Graph{descriptions: descriptions}),
    do: descriptions |> Map.keys |> MapSet.new

  @doc """
  The set of all properties used in the predicates of the statements within a `RDF.Graph`.

  ## Examples

      iex> RDF.Graph.new([
      ...>   {EX.S1, EX.p1, EX.O1},
      ...>   {EX.S2, EX.p2, EX.O2},
      ...>   {EX.S1, EX.p2, EX.O3}]) |>
      ...>   RDF.Graph.predicates
      MapSet.new([EX.p1, EX.p2])
  """
  def predicates(%RDF.Graph{descriptions: descriptions}) do
    Enum.reduce descriptions, MapSet.new, fn ({_, description}, acc) ->
      description
      |> Description.predicates
      |> MapSet.union(acc)
    end
  end

  @doc """
  The set of all resources used in the objects within a `RDF.Graph`.

  Note: This function does collect only IRIs and BlankNodes, not Literals.

  ## Examples

      iex> RDF.Graph.new([
      ...>   {EX.S1, EX.p1, EX.O1},
      ...>   {EX.S2, EX.p2, EX.O2},
      ...>   {EX.S3, EX.p1, EX.O2},
      ...>   {EX.S4, EX.p2, RDF.bnode(:bnode)},
      ...>   {EX.S5, EX.p3, "foo"}
      ...> ]) |> RDF.Graph.objects
      MapSet.new([RDF.iri(EX.O1), RDF.iri(EX.O2), RDF.bnode(:bnode)])
  """
  def objects(%RDF.Graph{descriptions: descriptions}) do
    Enum.reduce descriptions, MapSet.new, fn ({_, description}, acc) ->
      description
      |> Description.objects
      |> MapSet.union(acc)
    end
  end

  @doc """
  The set of all resources used within a `RDF.Graph`.

  ## Examples

      iex> RDF.Graph.new([
      ...>   {EX.S1, EX.p1, EX.O1},
      ...>   {EX.S2, EX.p1, EX.O2},
      ...>   {EX.S2, EX.p2, RDF.bnode(:bnode)},
      ...>   {EX.S3, EX.p1, "foo"}
      ...> ]) |> RDF.Graph.resources
      MapSet.new([RDF.iri(EX.S1), RDF.iri(EX.S2), RDF.iri(EX.S3),
        RDF.iri(EX.O1), RDF.iri(EX.O2), RDF.bnode(:bnode), EX.p1, EX.p2])
  """
  def resources(graph = %RDF.Graph{descriptions: descriptions}) do
    Enum.reduce(descriptions, MapSet.new, fn ({_, description}, acc) ->
      description
      |> Description.resources
      |> MapSet.union(acc)
    end) |> MapSet.union(subjects(graph))
  end

  @doc """
  The list of all statements within a `RDF.Graph`.

  ## Examples

        iex> RDF.Graph.new([
        ...>   {EX.S1, EX.p1, EX.O1},
        ...>   {EX.S2, EX.p2, EX.O2},
        ...>   {EX.S1, EX.p2, EX.O3}
        ...> ]) |> RDF.Graph.triples
        [{RDF.iri(EX.S1), RDF.iri(EX.p1), RDF.iri(EX.O1)},
         {RDF.iri(EX.S1), RDF.iri(EX.p2), RDF.iri(EX.O3)},
         {RDF.iri(EX.S2), RDF.iri(EX.p2), RDF.iri(EX.O2)}]
  """
  @spec triples(t) :: [Statement.t]
  def triples(%RDF.Graph{} = graph), do: Enum.to_list(graph)

  defdelegate statements(graph), to: RDF.Graph, as: :triples


  @doc """
  Checks if the given statement exists within a `RDF.Graph`.
  """
  @spec include?(t, Statement.t) :: boolean
  def include?(%RDF.Graph{descriptions: descriptions},
              triple = {subject, _, _}) do
    with subject = coerce_subject(subject),
         %Description{} <- description = descriptions[subject] do
      Description.include?(description, triple)
    else
      _ -> false
    end
  end

  @doc """
  Checks if a `RDF.Graph` contains statements about the given resource.

  ## Examples

        iex> RDF.Graph.new([{EX.S1, EX.p1, EX.O1}]) |> RDF.Graph.describes?(EX.S1)
        true
        iex> RDF.Graph.new([{EX.S1, EX.p1, EX.O1}]) |> RDF.Graph.describes?(EX.S2)
        false
  """
  @spec describes?(t, Statement.coercible_subject) :: boolean
  def describes?(%RDF.Graph{descriptions: descriptions}, subject) do
    with subject = coerce_subject(subject) do
      Map.has_key?(descriptions, subject)
    end
  end


  @doc """
  Returns a nested map of the native Elixir values of a `RDF.Graph`.

  The optional second argument allows to specify a custom mapping with a function
  which will receive a tuple `{statement_position, rdf_term}` where
  `statement_position` is one of the atoms `:subject`, `:predicate` or `:object`,
  while `rdf_term` is the RDF term to be mapped.

  ## Examples

      iex> [
      ...>   {~I<http://example.com/S1>, ~I<http://example.com/p>, ~L"Foo"},
      ...>   {~I<http://example.com/S2>, ~I<http://example.com/p>, RDF.integer(42)}
      ...> ]
      ...> |> RDF.Graph.new()
      ...> |> RDF.Graph.values()
      %{
        "http://example.com/S1" => %{"http://example.com/p" => ["Foo"]},
        "http://example.com/S2" => %{"http://example.com/p" => [42]}
      }

      iex> [
      ...>   {~I<http://example.com/S1>, ~I<http://example.com/p>, ~L"Foo"},
      ...>   {~I<http://example.com/S2>, ~I<http://example.com/p>, RDF.integer(42)}
      ...> ]
      ...> |> RDF.Graph.new()
      ...> |> RDF.Graph.values(fn
      ...>      {:predicate, predicate} ->
      ...>        predicate
      ...>        |> to_string()
      ...>        |> String.split("/")
      ...>        |> List.last()
      ...>        |> String.to_atom()
      ...>    {_, term} ->
      ...>      RDF.Term.value(term)
      ...>    end)
      %{
        "http://example.com/S1" => %{p: ["Foo"]},
        "http://example.com/S2" => %{p: [42]}
      }

  """
  @spec values(t, Statement.term_mapping) :: map
  def values(graph, mapping \\ &RDF.Statement.default_term_mapping/1)

  def values(%RDF.Graph{descriptions: descriptions}, mapping) do
    Map.new descriptions, fn {subject, description} ->
      {mapping.({:subject, subject}), Description.values(description, mapping)}
    end
  end

  @doc """
  Creates a graph from another one by limiting its statements to those using one of the given `subjects`.

  If `subjects` contains IRIs that are not used in the `graph`, they're simply ignored.

  The optional `properties` argument allows to limit also properties of the subject descriptions.

  If `nil` is passed as the `subjects`, the subjects will not be limited.
  """
  @spec take(t, [Statement.coercible_subject] | nil, [Statement.coercible_predicate] | nil) :: t
  def take(graph, subjects, properties \\ nil)

  def take(%RDF.Graph{} = graph, nil, nil), do: graph

  def take(%RDF.Graph{descriptions: descriptions} = graph, subjects, nil) do
    subjects = Enum.map(subjects, &(coerce_subject/1))
    %RDF.Graph{graph | descriptions: Map.take(descriptions, subjects)}
  end

  def take(%RDF.Graph{} = graph, subjects, properties) do
    graph = take(graph, subjects, nil)
    %RDF.Graph{graph | 
      descriptions: Map.new(graph.descriptions, fn {subject, description} ->
        {subject, Description.take(description, properties)}
      end)
    }
  end


  @doc """
  Checks if two `RDF.Graph`s are equal.

  Two `RDF.Graph`s are considered to be equal if they contain the same triples
  and have the same name. The prefixes of the graph are irrelevant for equality.
  """
  @spec equal?(t | any, t | any) :: boolean
  def equal?(graph1, graph2)

  def equal?(%RDF.Graph{} = graph1, %RDF.Graph{} = graph2) do
    clear_metadata(graph1) == clear_metadata(graph2)
  end

  def equal?(_, _), do: false


  @doc """
  Adds `prefixes` to the given `graph`.

  The `prefixes` mappings can be given as any structure convertible to a
  `RDF.PrefixMap`.

  When a prefix with another mapping already exists it will be overwritten with
  the new one. This behaviour can be customized by providing a `conflict_resolver`
  function. See `RDF.PrefixMap.merge/3` for more on that.
  """
  @spec add_prefixes(
          t,
          PrefixMap.t | map | keyword | nil,
          PrefixMap.conflict_resolver | nil
        ) :: t
  def add_prefixes(graph, prefixes, conflict_resolver \\ nil)

  def add_prefixes(%RDF.Graph{} = graph, nil, _), do: graph

  def add_prefixes(%RDF.Graph{prefixes: nil} = graph, prefixes, _) do
    %RDF.Graph{graph | prefixes: RDF.PrefixMap.new(prefixes)}
  end

  def add_prefixes(%RDF.Graph{} = graph, additions, nil) do
    add_prefixes(%RDF.Graph{} = graph, additions, fn _, _, ns -> ns end)
  end

  def add_prefixes(%RDF.Graph{prefixes: prefixes} = graph, additions, conflict_resolver) do
    %RDF.Graph{graph |
      prefixes: RDF.PrefixMap.merge!(prefixes, additions, conflict_resolver)
    }
  end

  @doc """
  Deletes `prefixes` from the given `graph`.

  The `prefixes` can be a single prefix or a list of prefixes.
  Prefixes not in prefixes of the graph are simply ignored.
  """
  @spec delete_prefixes(t, PrefixMap.t) :: t
  def delete_prefixes(graph, prefixes)

  def delete_prefixes(%RDF.Graph{prefixes: nil} = graph, _), do: graph

  def delete_prefixes(%RDF.Graph{prefixes: prefixes} = graph, deletions) do
    %RDF.Graph{graph | prefixes: RDF.PrefixMap.drop(prefixes, List.wrap(deletions))}
  end

  @doc """
  Clears all prefixes of the given `graph`.
  """
  @spec clear_prefixes(t) :: t
  def clear_prefixes(%RDF.Graph{} = graph) do
    %RDF.Graph{graph | prefixes: nil}
  end

  @doc """
  Sets the base IRI of the given `graph`.

  The `base_iri` can be given as anything accepted by `RDF.IRI.coerce_base/1`.
  """
  @spec set_base_iri(t, IRI.t | nil) :: t
  def set_base_iri(graph, base_iri)

  def set_base_iri(%RDF.Graph{} = graph, nil) do
    %RDF.Graph{graph | base_iri: nil}
  end

  def set_base_iri(%RDF.Graph{} = graph, base_iri) do
    %RDF.Graph{graph | base_iri: RDF.IRI.coerce_base(base_iri)}
  end

  @doc """
  Clears the base IRI of the given `graph`.
  """
  @spec clear_base_iri(t) :: t
  def clear_base_iri(%RDF.Graph{} = graph) do
    %RDF.Graph{graph | base_iri: nil}
  end

  @doc """
  Clears the base IRI and all prefixes of the given `graph`.
  """
  @spec clear_metadata(t) :: t
  def clear_metadata(%RDF.Graph{} = graph) do
    graph
    |> clear_base_iri()
    |> clear_prefixes()
  end


  defimpl Enumerable do
    def member?(graph, triple),  do: {:ok, RDF.Graph.include?(graph, triple)}
    def count(graph),            do: {:ok, RDF.Graph.triple_count(graph)}
    def slice(_graph),           do: {:error, __MODULE__}

    def reduce(%RDF.Graph{descriptions: descriptions}, {:cont, acc}, _fun)
      when map_size(descriptions) == 0, do: {:done, acc}

    def reduce(%RDF.Graph{} = graph, {:cont, acc}, fun) do
      {triple, rest} = RDF.Graph.pop(graph)
      reduce(rest, fun.(triple, acc), fun)
    end

    def reduce(_,       {:halt, acc}, _fun), do: {:halted, acc}
    def reduce(%RDF.Graph{} = graph, {:suspend, acc}, fun) do
      {:suspended, acc, &reduce(graph, &1, fun)}
    end
  end

  defimpl Collectable do
    def into(original) do
      collector_fun = fn
        graph, {:cont, list} when is_list(list)
                             -> RDF.Graph.add(graph, List.to_tuple(list))
        graph, {:cont, elem} -> RDF.Graph.add(graph, elem)
        graph, :done         -> graph
        _graph, :halt        -> :ok
      end

      {original, collector_fun}
    end
  end
end
