<img src="rdf-logo.png" align="right" />

# RDF.ex

[![Travis](https://img.shields.io/travis/rdf-elixir/rdf-ex.svg?style=flat-square)](https://travis-ci.org/rdf-elixir/rdf-ex)
[![Hex.pm](https://img.shields.io/hexpm/v/rdf.svg?style=flat-square)](https://hex.pm/packages/rdf)


An implementation of the [RDF](https://www.w3.org/TR/rdf11-primer/) data model in Elixir.

The API documentation can be found [here](https://hexdocs.pm/rdf/). For a guide and more information about RDF.ex and it's related projects, go to <https://rdf-elixir.dev>.

## Features

- fully compatible with the RDF 1.1 specification
- in-memory data structures for RDF descriptions, RDF graphs and RDF datasets
- basic graph pattern matching against the in-memory data structures with streaming-support
- execute [SPARQL] queries against the in-memory data structures via the [SPARQL.ex] package or against any SPARQL endpoint via the [SPARQL.Client] package
- RDF vocabularies as Elixir modules for safe, i.e. compile-time checked and concise usage of IRIs
- most of the important XML schema datatypes for RDF literals
- define custom datatypes for RDF literals, incl. as derivations of XSD datatypes via facets 
- sigils for the most common types of nodes, i.e. IRIs, literals, blank nodes and lists
- a description DSL resembling Turtle in Elixir
- implementations for the [N-Triples], [N-Quads] and [Turtle] serialization formats; [JSON-LD] is implemented in the separate [JSON-LD.ex] package
- validate data against [ShEx] schemas via the [ShEx.ex] package


## Contributing

There's still much to do for a complete RDF ecosystem for Elixir, which means there are plenty of opportunities for you to contribute. Here are some suggestions:

- more serialization formats, like [RDFa], [RDF-XML], [N3], [CSVW], [HDT] etc.
- more XSD datatypes
- improve documentation

see [CONTRIBUTING](CONTRIBUTING.md) for details.


## Consulting and Partnership

If you need help with your Elixir and Linked Data projects, just contact <info@cokron.com> or visit <https://www.cokron.com/kontakt>



## License and Copyright

(c) 2017-2020 Marcel Otto. MIT Licensed, see [LICENSE](LICENSE.md) for details.


[RDF.ex]:               https://hex.pm/packages/rdf
[JSON-LD.ex]:           https://hex.pm/packages/json_ld
[SPARQL.ex]:            https://hex.pm/packages/sparql
[SPARQL.Client]:        https://hex.pm/packages/sparql_client
[ShEx.ex]:              https://hex.pm/packages/shex
[N-Triples]:            https://www.w3.org/TR/n-triples/
[N-Quads]:              https://www.w3.org/TR/n-quads/
[Turtle]:               https://www.w3.org/TR/turtle/
[N3]:                   https://www.w3.org/TeamSubmission/n3/
[JSON-LD]:              https://www.w3.org/TR/json-ld/
[RDFa]:                 https://www.w3.org/TR/rdfa-syntax/
[RDF-XML]:              https://www.w3.org/TR/rdf-syntax-grammar/
[CSVW]:                 https://www.w3.org/TR/tabular-data-model/
[HDT]:                  http://www.rdfhdt.org/
[SPARQL]:               https://www.w3.org/TR/sparql11-overview/
[ShEx]:                 https://shex.io/
