import algorithm
import logging
import os
import parseopt
import sequtils
import streams
import strformat
import strutils
import typetraits
from unicode import toRunes, align

const NimblePkgVersion {.strdefine.} = "Unknown"
const version = NimblePkgVersion
proc printVersion() =
    if version == "Unknown":
        echo "Unknown version of reshape, compiled on {CompileDate} at {CompileTime}".fmt
    else:
        echo "Version {version} of reshape, compiled on {CompileDate} at {CompileTime}".fmt
    quit(QuitSuccess)


proc printHelp() =
    echo """
Usage: reshape [-h|-v][--help|--version]
       reshape [-i] TABLE
       reshape [-p][-t][-u]
               [-d:delim][-c:c1,c2,...][-r:r1,r2,...][-o:file][-s:RxC] TABLE

Options:
-v,--version            print version information
-i,--info               print diagnostic information for TABLE
-p,--nopad              don't pad output cells with leading whitespace
-t,--transpose          transpose TABLE, swap meaning of "rows" and "columns"
-u,--unique             deduplicate rows in TABLE, after `--skip{cols,rows}`
-d,--delim <delim>      split input lines at each occurance of <delim>
-s,--shape <RxC>        reshape TABLE into R rows and C columns, applied last
-c,--skipcols <c1,...>  skip columns <c1,...> in TABLE; use a dash for ranges
-r,--skiprows <r1,...>  skip rows <r1,...> in TABLE; use a dash for ranges
-o,--out <file>         write output to <file> instead of standard output

Operands:
    TABLE               File path or input stream
                        containing tabular input data

Reshape and transform delimited tabular text. When using `--transpose`,
"rows" and "columns" for other options refer to the table before transposing.
The default delimiter is a tab, i.e. `\t`. Reshaping with `--shape` is always
applied after `--skip{rows,cols}`, `--unique` and `--transpose`. For short options,
option arguments must be separated from the flag by a colon or equals sign,
e.g. `-d:,`. Multi-byte delimiters such as unicode characters are not supported.
Tab and space delimiters can be specified with `-d:'\t'` and `-d:'\s'` respectively.
Empty columns are propagated without warning. See reshape(1) for examples."""
    quit(QuitSuccess)


type Shape = tuple[rows, cols: int]
type Opts = tuple[
    inputFile: string,
    outputFile: string,
    info: bool,
    pretty: bool,
    transpose: bool,
    deduplicate: bool,
    delimiter: char,
    newShape: Shape,
    skipCols: seq[int],
    skipRows: seq[int],
]

type ArgumentError* = object of CatchableError


proc chooseInput(filename: string): Stream =
    if "" == filename or "-" == filename:
        return newFileStream(stdin)
    return openFileStream(filename)


func splitCells(row: string, delimiterIndices: seq[int]): seq[string] =
    ## Splits row by removing `char`s at `delimiterIndices`.
    ## Leading or trailing delimiters result in corresponding empty cells.
    if len(delimiterIndices) > 0:
        var cells = newSeq[string](len(delimiterIndices) + 1)
        # First cell.
        if delimiterIndices[0] == 0:
            cells[0] = ""
        else:
            cells[0] = strip(row[0 ..< delimiterIndices[0]])
        # Intermediate cells.
        for i, delimiterIndex in delimiterIndices[0 ..< ^1].pairs:
            cells[i + 1] = strip(row[delimiterIndices[i] + 1 ..< delimiterIndices[i + 1]])
        # Last cell.
        if delimiterIndices[^1] == len(row):
            cells[^1] = ""
        else:
            cells[^1] = strip(row[delimiterIndices[^1] + 1 .. ^1])
        return cells
    else:
        return @[row]


func splitCells(row: string, delimiter: char): seq[string] =
    ## Splits row on delimiter, ignoring delimiters in quoted cells (double quotes only).
    ## Leadaing or trailing delimiters result in corresponding empty cells.
    var
        start: int
        delimiterIndices: seq[int]
        delimiterIndex = -1
        prevQuoteIndex = -1
        nextQuoteIndex = -1
        prevClosingQuoteIndex = -1

    while start < row.high:
        delimiterIndex = row.find(delimiter, start = start)
        start = delimiterIndex + 1
        if delimiterIndex == -1: break
        elif delimiterIndex == 0: delimiterIndices.add(0)
        else:
            prevQuoteIndex = row.rfind(
                '"',
                start = prevClosingQuoteIndex + 1,
                last = delimiterIndex,
            )
            if prevQuoteIndex != -1:
                nextQuoteIndex = row.find('"', start = delimiterIndex)
                if nextQuoteIndex != -1:
                    prevClosingQuoteIndex = nextQuoteIndex
                else:
                    delimiterIndices.add(delimiterIndex)
            else:
                delimiterIndices.add(delimiterIndex)
    return splitCells(row, delimiterIndices)


proc readShape*(
    input: Stream, delimiter: char, sink: Stream = newStringStream(), warnings = false
    ): Shape =
    ## Guesses the shape of the delimited text given in the input stream.
    ## Quoted delimiters are skipped, and the quote char `"` is an illegal delimiter
    ## (which causes a `ValueError` to be raised). The input is passed on to the
    ## `sink` stream if provided. Optionally logs warnings about malformed rows.
    if delimiter == '"':
        raise newException(ValueError, "delimiter must not be the quote character (U+0022)")
    var
        rowCount: int
        colCount: int
        badRows: seq[int]
        line: string
    while input.readLine(line):
        sink.writeLine(line)
        inc rowCount
        var currentColCount = len(line.splitCells(delimiter))
        if currentColCount >= colCount:
            if currentColCount > colCount:
                if rowCount > 1: badRows.add(rowCount - 1)
                colCount = currentColCount
            else:
                continue
        else:
            badRows.add(rowCount)

        # Track a maximum of 100 malformed rows.
        # The 100'th item is always the last known malformed row.
        # Trailing zero to denotes truncation.
        # Reminder: zero-based indexing.
        if len(badRows) >= 101:
            badRows[99] = badRows[^1]
            badRows[100] = 0
            if len(badRows) == 102: badRows.delete(101)

    if warnings:
        if colCount == 1: warn("delimiter '{delimiter}' not found.".fmt)
        elif len(badRows) > 0:
            var badRowsTrunc =
                if badRows[^1] == 0:
                    badRows[0..^3].join(",") & "..." & $badRows[^2]
                else:
                    badRows.join(",")
            warn("encountered malformed rows: {badRowsTrunc}.".fmt)
    return (rowCount, colCount)


func toSlices(s: seq[int]): seq[Slice[int]] =
    ## Condenses a sequence of integers to a sequence of slices.
    ## Raises a `ValueError` if `s` is not sorted.
    if not isSorted(s): raise newException(ValueError, "sequence must be sorted")
    var sliceBounds = newSeqWith(1, s[0])
    var slices: seq[Slice[int]]
    for i, val in s[0 ..< ^1].pairs:
        var nextVal = s[i + 1]
        if (nextVal - val) > 1:
            sliceBounds.add(val)
            sliceBounds.add(nextVal)
    sliceBounds.add(s[^1])
    for i in countup(0, len(sliceBounds) - 1, 2):
        slices.add(sliceBounds[i] .. sliceBounds[i + 1])
    return slices


proc readTable*(input: Stream, delimiter: char, skipRows, skipCols: seq[int] = @[]):
    seq[seq[string]] =
    ## Reads delimited tabular data from `input` and returns a sequence of rows.
    ## Rows are sequences of cells (strings). Quoted delimiters are skipped.
    ## Raises a `ValueError` if the quote character `"` is used as a delimiter.
    ## Raises an `IOError` if no data can be read from the `input` stream.
    ## Quietly propagates empty cells. Empty cells are also created to complete
    ## malformed rows of the table. They are added to the right of existing cells.
    ## `skipRows` and `skipCols` can be used to exclude the specified rows/columns.
    ## This is done after filling out malformed rows. Rows/columns are zero-indexed.
    if atEnd(input): raise newException(IOError, "input stream must not be exhausted")

    let uniqueSkipCols = deduplicate(sorted(skipCols), isSorted = true)
    let uniqueSkipRows = deduplicate(sorted(skipRows), isSorted = true)
    var stream = newStringStream()
    let shape = readShape(input, delimiter, stream)
    var table = newSeqWith(
        shape.rows - len(uniqueSkipRows),
        newSeq[string](shape.cols - len(uniqueSkipCols)),
    )
    var line: string
    var rowIndex: int
    var newRowIndex: int
    stream.setPosition(0)
    while stream.readLine(line):
        if rowIndex in uniqueSkipRows: inc rowIndex; continue
        var cells = line.splitCells(delimiter)
        if len(uniqueSkipCols) > 0:
            for slice in reversed(toSlices(uniqueSkipCols)):
                when NimMajor == 1 and NimMinor < 6:
                    # https://github.com/nim-lang/Nim/commit/1d6863a7899fd87fd9eb017ae370ef37db18ad32
                    cells.delete(slice.a, slice.b)
                else:
                    cells.delete(slice)
        table[newRowIndex][0 ..< len(cells)] = cells
        inc newRowIndex
        inc rowIndex
    # Make zero-column return the same as zero-row return.
    if len(table) > 0 and len(table[0]) == 0: return newSeq[seq[string]]()
    close stream
    return table


func transpose*(table: seq[seq[string]]): seq[seq[string]] =
    ## Returns a transposed copy of `table`.
    ## Assumes that each row of `table` has an equal number of cells.
    ## Raises an `IndexDefect` if the number of cells increases.
    if len(table) == 0: return table
    var newTable = newSeqWith(len(table[0]), newSeq[string](len(table)))
    for r, row in table.pairs:
        for c, cell in row.pairs:
            newTable[c][r] = cell
    return newTable


func reshape*(table: seq[seq[string]], newShape: Shape): seq[seq[string]] =
    ## Returns a reshaped copy of `table` by filling a table of shape `newShape`
    ## one row at a time. Assumes that each row of `table` has
    ## an equal number of cells. Raises an `IndexDefect` for overfull inputs.
    ## Raises a `ValueError` if `newShape` contains non-positive integers,
    ## or would result in a different capacity (number of cells).
    if newShape.rows < 1 or newShape.cols < 1:
        raise newException(ValueError, "shape must be a tuple of positive integers")
    if len(table) == 0: return table
    if (newShape.rows * newShape.cols) != (len(table) * len(table[0])):
        raise newException(ValueError, "new shape must retain table capacity")
    var newTable = newSeqWith(newShape.rows, newSeq[string](newShape.cols))
    var rowCursor: int
    var colCursor: int
    for row in table:
        for cell in row:
            newTable[rowCursor][colCursor] = cell
            if newShape.cols - colCursor > 1:
                inc colCursor
            else:
                colCursor = 0
                inc rowCursor
    return newTable


proc padCells*(table: var seq[seq[string]]) =
    ## Pads cells in-place with whitespace to right-align tabular columns.
    ## Raises a `ValueError` if the rows don't all contain the same amount of cells.
    if len(table) == 0: return
    var cellSizes = newSeq[int](len(table[0]))
    for row in table:
        if len(row) != len(cellSizes):
            raise newException(ValueError, "must provide rows of equal length")
        for i, cell in row.pairs:
            var cellSize = len(toRunes(cell))
            if cellSize > cellSizes[i]:
                cellSizes[i] = cellSize
    for row in table.mitems:
        for i, cell in row.mpairs:
            cell = unicode.align(cell, cellSizes[i])


proc printInfo(input: Stream, delimiter: char) =
    let (rows, cols) = readShape(input, delimiter, warnings = true)
    echo "Rows: {rows}".fmt
    echo "Columns: {cols}".fmt


proc validate(key, val: string): string =
    var parsedVal: string
    if len(val) == 2 and val[0] == '\\':
        if val[1] == 't': parsedVal = "\t"
        elif val[1] == ' ' or val[1] == 's': parsedVal = " "
    else: parsedVal = val
    if parsedVal == "":
        raise newException(
            ArgumentError,
            "option {key} requires an argument (use `-{key}=<arg>` or `-{key}:<arg>`)".fmt
        )
    return parsedVal


func validateChar(key, val: string): char =
    var parsedVal = validate(key, val)
    if len(parsedVal) > 1:
        raise newException(
            ArgumentError, "must provide a single-byte delimiter, not '{parsedVal}'.".fmt
        )
    return parsedVal[0]


func validateShape(key: string, val: string): Shape =
    # Unpacking operator would be nice: https://forum.nim-lang.org/t/8793
    var shape = validate(key, val).split('x').map(parseInt)
    if any(shape, proc(x: int): bool = x < 1):
        raise newException(
            ArgumentError, "must provide positive integers for new shape"
        )
    return (rows: shape[0], cols: shape[1])


func validateSkips(key: string, val: string): seq[int] =
    var input = validate(key, val).split(',')
    var parsedInput: seq[int]
    for s in input:
        let dashPos = s.find({'-'})
        if dashPos == 0:
            raise newException(
                ArgumentError, "indices for skipped rows/columns must be positive"
            )
        if dashPos == len(s) - 1:
            raise newException(ArgumentError, "must include endpoint of skipped range")
        if dashPos > 0:
            let start = parseInt(s[0 ..< dashPos])
            let stepDashPos = s.find({'-'}, dashPos + 2)
            var step, stop: int
            if stepDashPos == len(s) - 1:
                raise newException(
                    ArgumentError, "must include endpoint of skipped range"
                )
            if stepDashPos > 0:
                step = parseInt(s[dashPos + 1 ..< stepDashPos])
                stop = parseInt(s[stepDashPos + 1 .. ^1])
            else:
                step = 1
                stop = parseInt(s[dashPos + 1 .. ^1])
            if start > stop:
                raise newException(ArgumentError, "range endpoints must obey a < b")
            if step < 1:
                raise newException(ArgumentError, "range step must be positive")
            parsedInput.insert(toSeq(countup(start, stop, step)))
        else:
            parsedInput.add(parseInt(s))
    if any(parsedInput, proc(x: int): bool = x < 1):
        raise newException(
            ArgumentError, "indices for skipped rows/columns must be positive"
        )
    return parsedInput.map(proc(x: int): int = x - 1)


proc parseOpts*(cmdline = ""): Opts =
    ## Parses command line options from the input string, or `stdin` by default.
    ## Raises an `ArgumentError` on illegal combinations or argument values.
    var parser = initOptParser(
        cmdline,
        shortNoVal = {'h', 'v', 'i', 'p', 't', 'u'},
        longNoVal = @["help", "version", "info", "nopad", "transpose", "unique"],
    )
    # Set defaults.
    var opts: Opts
    opts.pretty = true
    opts.transpose = false
    opts.deduplicate = false
    opts.delimiter = '\t'

    for kind, key, val in getopt(parser):
        case kind
        of cmdLongOption, cmdShortOption:
            case key
                # Process options without arguments.
                of "help", "h": printHelp()
                of "version", "v": printVersion()
                of "info", "i": opts.info = true
                of "nopad", "p": opts.pretty = false
                of "transpose", "t": opts.transpose = true
                of "unique", "u": opts.deduplicate = true
                # Process options with arguments.
                of "out", "o": opts.outputFile = validate(key, val)
                of "delim", "d": opts.delimiter = validateChar(key, val)
                of "shape", "s": opts.newShape = validateShape(key, val)
                of "skipcols", "c": opts.skipCols = validateSkips(key, val)
                of "skiprows", "r": opts.skipRows = validateSkips(key, val)
                else:
                    if kind == cmdLongOption:
                        raise newException(ArgumentError, "invalid option '--{key}'".fmt)
                    elif kind == cmdShortOption:
                        raise newException(ArgumentError, "invalid option '-{key}'".fmt)
        of cmdArgument: opts.inputFile = key
        of cmdEnd: assert(false)
    return opts


proc main() =
    let opts = parseOpts()
    let input = chooseInput(opts.inputFile)
    let logger = newConsoleLogger(); addHandler(logger)
    if opts.info:
        printInfo(input, opts.delimiter)
        close input
        quit(QuitSuccess)

    let table = readTable(
        input,
        opts.delimiter,
        skipRows = opts.skiprows,
        skipCols = opts.skipcols,
    )
    close input

    var newTable = if opts.deduplicate: deduplicate(table) else: table
    newTable = if opts.transpose: transpose(newTable) else: newTable
    if opts.newShape.rows > 0 and opts.newShape.cols > 0:
        newTable = reshape(newTable, opts.newShape)
    if opts.pretty:
        padCells(newTable)
    var output = if opts.outputFile == "":
        stdout
    else:
        if fileExists(opts.outputFile):
            raise newException(IOError, "file '{opts.outputFile}' already exists".fmt)
        open(opts.outputFile, mode = fmWrite)
    for row in newTable:
        writeLine(output, row.join($opts.delimiter))
    close output


if isMainModule: main()
