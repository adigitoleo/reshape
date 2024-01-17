# reshape

Reshape delimited text files.

Reads input from a file if the filename is given as the last argument.
Reads from `stdin` stream (e.g. unix pipe) otherwise, until terminated by an EOF signal.
A filename argument of `-` can also be used to switch to `stdin` input.
Note that the whole input is read into memory at once for processing.

## Features

This utility can process tabular data by
- transposing rows with columns
- reshaping the data, e.g. turning a 4x4 table into a 8x2 table,
- skipping selected rows/columns (individual or ranges),
- deduplicating repeated rows,
- padding cells to right-align table columns,
- and printing information about input tables (e.g. number of rows/columns, number of malformed rows)

For some usage examples, refer to the [manual page](./doc/reshape.1.mdoc).
If you have [installed](#Install) `reshape`, you should be able to read it from `man reshape`.
Otherwise the manual page source can be rendered on most Unix systems using `man -l /path/to/reshape.1.mdoc`.

## Install

After building the `reshape` binary, put it in one of your `$PATH` directories.
The manual page in the `doc` folder should also be copied into the appropriate manual page folder for your system.

## Build

Building reshape requires a Nim compiler (version 1.4.8 or later).

Release build: `nim c -d:release src/reshape.nim`

Debug build: `nim c src/reshape.nim`

## Test

The test suite requires [unittest2](https://github.com/status-im/nim-unittest2).

Run `nimble test` in the source code root directory.

Linux CI (dev build): [![builds.sr.ht status](https://builds.sr.ht/~adigitoleo/reshape.svg)](https://builds.sr.ht/~adigitoleo/reshape)

## Use

Run with the `--help` option if built, or check the `printHelp` proc in the code.
Note that short options must not be separated from their arguments by a space.
Use `:` or `=` instead, or append the argument to the option flag directly.
This behaviour is inherited from Nim's [parseopt][parseopt] module.

## Contribute

Please submit patches or suggestions to my [public inbox](https://lists.sr.ht/~adigitoleo/public-inbox).
Patches should be submitted against the HEAD of the `dev` branch on SourceHut.
**Pull Requests on the GitHub mirror are not monitored.**

## Similar solutions

- [BSD's rs command](https://man.netbsd.org/rs.1)
- [transposer](https://github.com/keithhamilton/transposer)
- [GNU datamash](https://www.gnu.org/software/datamash/)
- [Some ideas for transposing files using awk](https://stackoverflow.com/questions/1729824/an-efficient-way-to-transpose-a-file-in-bash)

## TODO

- More high-level tests (test examples from manual page?)
- extract/generate help proc text from the mdoc source?
- documentation for `--skip{rows,cols}=1-2-3` (start-step-stop) syntax
- better upfront error handling
- fix: bad rows warning prints last row nr twice in some cases, e.g. `reshape
  -d',' -i` of [this file](https://github.com/Patol75/PyDRex/blob/main/src/pydrex/data/thirdparty/Kaminski2001_GBMshear.scsv)

[parseopt]: https://nim-lang.org/docs/parseopt.html
