# reshape

Reshape delimited text files.

Reads input from a file if the filename is given as the last argument.
Reads from `stdin` stream (e.g. unix pipe) otherwise, until terminated by an EOF signal.
A filename argument of `-` can also be used to switch to `stdin` input.
Note that the whole input is read into memory at once for processing.

## Examples

Transpose:

```sh
printf 'a,b,c'|reshape -d, -t -
a
b
c
```

Reshape:

```sh
printf '%s\n%s\n' 'a,b,c' '1,2,3'|reshape -d, -s3x2 -
a,b
c,1
2,3
```

Output is right-aligned by default (use `-p` or `--nopad` to disable):

```sh
printf '%s\n%s\n%s\n' 'a,b,c' '1,2,3' 'foo,bar,baz'|reshape -d, -
  a,  b,  c
  1,  2,  3
foo,bar,baz
```

Note that unicode symbols are currently not aligned properly:

```sh
printf '%s\n%s\n%s\n' ',a,b,c,d' ',1,2,3,4' ',",",,ß'|reshape -d, -c1 -s3x4
  a,b, c,d
  1,2, 3,4
",", ,ß,
```

## Install

After building the `reshape` binary, put it in one of your `$PATH` directories.

## Build

Release build: `nim c -d:release src/reshape.nim`

Debug build: `nim c src/reshape.nim`

## Test

Run `nimble test` in the source code root directory.

Linux CI (dev branch): [![builds.sr.ht status](https://builds.sr.ht/~adigitoleo/reshape.svg)](https://builds.sr.ht/~adigitoleo/reshape?)

## Use

Run with the `--help` option if built, or check the `printHelp` proc in the code.
Note that short options must not be separated from their arguments by a space.
Use `:` or `=` instead, or append the argument to the option flag directly.
This behaviour is inherited from Nim's [parseopt][parseopt] module.

## Similar solutions

- [BSD's rs command](https://man.netbsd.org/rs.1)
- [transposer](https://github.com/keithhamilton/transposer)
- [Some ideas for transposing files using awk](https://stackoverflow.com/questions/1729824/an-efficient-way-to-transpose-a-file-in-bash)

## TODO

- Support negative values in `--skiprows` and `--skipcols`
  for row/column indices counted backwards from the last row/column.
- Support a range syntax for `--skiprows` and `--skipcols`
- Fix cell padding for tables with unicode characters.

[parseopt]: https://nim-lang.org/docs/parseopt.html
