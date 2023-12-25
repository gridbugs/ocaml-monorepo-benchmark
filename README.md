# Ocaml Monorepo Benchmark

[![test status](https://github.com/ocaml-dune/ocaml-monorepo-benchmark/actions/workflows/test.yml/badge.svg)](https://github.com/ocaml-dune/ocaml-monorepo-benchmark/actions/workflows/test.yml)

This is a collection of projects relating to a large OCaml monorepo composed of
packages from Opam for the purposes of benchmarking Dune.

This repo contains:

- `generate-duniverse.sh` is a script for generating the duniverse directory needed by the monorepo benchmark
- `generate` contains a tool for generating large monorepos from packgaes in the opam repository
- `benchmark` contains opam and dune files describing a benchmark
- `dune-monorepo-benchmark-runner` contains an executable for benchmarking dune building a monorepo
- `small-monorepo` contains a small monorepo for testing the benchmark runner
- `bench.Dockefile` is a dockerfile for testing the benchmark runner on the full benchmark

## The Benchmark in Dune

The file
[bench/monorepo/bench.Dockerfile](https://github.com/ocaml/dune/blob/main/bench/monorepo/bench.Dockerfile)
in the dune repo downloads a tagged release of this repo and builds and runs the
benchmark runner contained within it:

```dockerfile
...
ENV MONOREPO_BENCHMARK_TAG=2023-08-23.0
RUN wget https://github.com/ocaml-dune/ocaml-monorepo-benchmark/archive/refs/tags/$MONOREPO_BENCHMARK_TAG.tar.gz ...
...
```

The benchmarking server contains duniverse directory generated by the process
described below which is mounted as a docker volume before the benchmark gets
run. This is to avoid situations where packages are unavailable (quite a
frequent occurrence) from preventing the benchmark from running. Read more about
this in [dune's monorepo benchmark docs](https://github.com/ocaml/dune/blob/main/bench/monorepo/README.md).

## Instantiating the Monorepo

Due to its size the monorepo isn't checked into this repo. Instead
[opam-monorepo](https://github.com/tarides/opam-monorepo) is used to assemble the
monorepo from a lockfile. To assemble the monorepo manually, run `opam monorepo
pull` from inside the `benchmark` directory. However, due to the quirks listed
below some additional steps are necessary to get a buildable monorepo. These
steps are performed by `benchmark/Dockerfile` and a convenience script that
produces a "duniverse" directory is provided (`generate-duniverse.sh`). The
resulting "duniverse" directory can be placed inside the `benchmark` directory
(ie. `benchmark/duniverse`).

In one command this is:
```
$ ./generate-duniverse.sh benchmark
```

### Quirks

Some packages in the monorepo are incompatible with building in a monorepo
setting and require patching for them to work. The directory `benchmark/patches`
contains patches that must be applied. Each patch is named `<dir>.diff` where
`dir` is the name of the subdirectory of `duniverse` where the patch must be
applied.

Some packages contain custom configuration scripts that must be run before they
can be build with dune. These were found by a process of trial and error. See
`benchmark/Dockerfile` for details.

Note that patches are not applied when assembling the monorepo and must be
applied before running benchmarks. This is so that patches can be updated and
added without requiring the monorepo to be reassembled.

## Fixing Broken Packages

It's very likely that while generating the duniverse directory the `opam
monorepo pull` step will fail due to the package source archive being
unavailable, or the hash of one of the package archives won't match the one
contained in the opam monorepo lockfile. The monorepo has over 1000 dependencies
and it's up to individual package authors to keep the archives available, so
odds are that at least one of them will have changed their github account name,
deleted a project, updated a project's archive in-place, etc.

### Find the archive

To recover from this, first you'll need to obtain the original package archive.
If you're very lucky the broken package will have already been found by someone
else. Check if the package is already in the [opam-source-archives](https://github.com/ocaml/opam-source-archives/) repo
and if it is then just update the links in
`benchmark/monorepo-bench.opam.locked` (there should be 2) to a permalink to the
archive's location in the opam-source-archives repo.

Otherwise you'll need to dig up a cached version of the archive.
First check the opam package cache. Look in benchmark/monorepo-bench.opam.locked
to find the stored hashes of the archive, then check `https://opam.ocaml.org/cache/md5/<2char>/<all chars>`
or `https://opam.ocaml.org/cache/sha256/<2char>/<all chars>` to attempt to
download the package by hash. For example you can download dune.3.10.0's archive by its
sha256 hash by going to
`https://opam.ocaml.org/cache/sha256/9f/9ff03384a98a8df79852cc674f0b4738ba8aec17029b6e2eeb514f895e710355`.
Sometimes a package won't be in the opam cache. You can try your computer's
local opam cache which by default is in `~/.opam/download-cache`. It's also
organized by hash. For example dune.3.10.0 is in
`~/.opam/download-cache/sha256/9f/9ff03384a98a8df79852cc674f0b4738ba8aec17029b6e2eeb514f895e710355`.
If it's not on your machine ask around to see if anyone else has a cached
version of the package.

### Upload the archive to opam-source-archives

Make a PR to add the source file to
[opam-source-archives](https://github.com/ocaml/opam-source-archives/). Note the
naming convention for files there. The file you downloaded from the cache will
be named after its hash so you'll need to rename it to the package name and
version. Once the PR is merged, update the links in
`benchmark/monorepo-bench.opam.locked` (there should be 2) to a permalink to the
archive's location in the opam-source-archives repo.

### Update the package metadata in opam-repository

Make a PR to update the package metadata in [opam-repository](https://github.com/ocaml/opam-repository)
to change the URL for the source archive to the permalink to the archive in
opam-source-archives.


## Running the Benchmark

You can use the `bench.Dockerfile` to run the whole benchmark. You'll first need
to generate the `duniverse` directory inside the `benchmark` directory by
running `./generate-duniverse.sh benchmark`.

```
$ ./generate-duniverse.sh benchmark
$ docker build . -f bench.Dockerfile --tag=benchmark
$ docker run --rm benchmark make bench
```

Note that this process differs slightly from the way that benchmarks are run in
the dune repo. This is included as a way of testing the full monorepo benchmark
on its own. For info on how the benchmark runs on dune PRs, see the
[documentation in the dune repo](https://github.com/ocaml/dune/tree/main/bench/monorepo).

## Generating the Benchmark Monorepo

The tools in the `generate` directory are for generating the monorepo. This
involves creating the opam file listing package dependencies, opam monorepo
lockfile with more specific package information and deterministic behaviour, and
a dune file listing library dependencies. The process of regenerating the
monorepo involves generating as large a set of co-installable package as
possible according to opam metadata, then using `opam monorepo lock` to verify that they are in-fact
co-installable and generate a lockfile. Finally, the libraries contained
within each package (packages may contain multiple libraries) are enumerated and
added to a dune file as dependencies.

However, despite the metadata in opam about mutual incompatibility of packages,
some libraries fail to build in the presence of other libraries from other
packages. Also, some libraries can't be built from a vendored setting such as a
monorepo. Also some libraries are mutually exclusive with other libraries from
the same package (e.g. multiple implementations of the same interface). For this
reason, the `generate/bench-proj/tools/library-ignore-list.sexp` file lists all
the libraries to be excluded from the library dependencies of the dune project.
This list was constructed manually by a process of trial and error. Whenever the
monorepo is regenerated this list will need to be updated (by hand).

There's more information about monorepo generation in `generate/README.md`.
