import logging
import streams
import strformat
import strutils
import unittest

import reshape


const tabTable3x3 = """
    a	b	c
    0.1	0.2	0.3
    "	1"	"2	"	"3	3"
"""
const malformedCommaTable2x3 = """
    ä, ¿, ©
    1", "2, 3"
"""
const malformedSpaceTable4x4 = """
 a b c" "

 10 20 30
 1 2 """
const malformedCommaTable101x3 = "a, b, c\n" & repeat("foo\n", 100)
const malformedCommaTable102x3 = malformedCommaTable101x3 & "foo\n"


proc readLines(file: File): seq[string] =
    ## Reads all lines from the given open file.
    file.setFilePos(0)
    return splitLines(readAll(file))[0..^2]  # Remove spurious empty line.


suite "Command line parsing":
    let emptyOpts = parseOpts()
    test "nopad":
        check emptyOpts.pretty == true
        check parseOpts("-p").pretty == false
    test "transpose":
        check emptyOpts.transpose == false
        check parseOpts("-t").transpose == true
    test "out":
        check emptyOpts.outputFile == ""
        expect ArgumentError: discard parseOpts("-o")
        check parseOpts("-o:foo").outputFile == "foo"
        check parseOpts("--out foo").outputFile == "foo"
    test "delim":
        check emptyOpts.delimiter == '\t'
        expect ArgumentError: discard parseOpts("-d")
        check parseOpts("-d::").delimiter == ':'
        expect ArgumentError: discard parseOpts("-d:ð")  # Multi-byte delimiter: error.
        expect ArgumentError: discard parseOpts("--delim ||")  # Multi-byte delimiter: error.
        check parseOpts("--delim ,").delimiter == ','
    test "shape":
        check emptyOpts.newShape == (0, 0)
        expect ArgumentError: discard parseOpts("-s")
        check parseOpts("-s:3x4").newShape == (3, 4)
        check parseOpts("--shape 3x4").newShape == (3, 4)
        expect ValueError: discard parseOpts("--shape 2.5x1")
    test "skipcols":
        check emptyOpts.skipCols == newSeq[int]()
        expect ArgumentError: discard parseOpts("-c")
        check parseOpts("-c:1,4,10").skipCols == @[0, 3, 9]
        check parseOpts("--skipcols 1,4,10").skipCols == @[0, 3, 9]
        expect ValueError: discard parseOpts("--skipcols 1.2,3.4")
        check parseOpts("-c:1").skipCols == @[0]
        check parseOpts("-c:1-1").skipCols == @[0]
        check parseOpts("-c:1-3").skipCols == @[0, 1, 2]
        expect ArgumentError: discard parseOpts("-c:-1")
        expect ArgumentError: discard parseOpts("-c:1-")
        expect ArgumentError: discard parseOpts("-c:0")
        expect ArgumentError: discard parseOpts("-c:-1-1")
        expect ArgumentError: discard parseOpts("-c:1--1")
        check parseOpts("-c:1-1-5").skipCols == @[0, 1, 2, 3, 4]
        check parseOpts("-c:1-2-10").skipCols == @[0, 2, 4, 6, 8]
        check parseOpts("-c:1-1-1").skipCols == @[0]
        check parseOpts("-c:1-5-3").skipCols == @[0]
        expect ArgumentError: discard parseOpts("-c:1--1-1")
        expect ArgumentError: discard parseOpts("-c:1-1--1")
        expect ArgumentError: discard parseOpts("-c:1-1-")
    test "skiprows":
        check emptyOpts.skipRows == newSeq[int]()
        expect ArgumentError: discard parseOpts("-r")
        check parseOpts("-r:1,4,10").skipRows == @[0, 3, 9]
        check parseOpts("--skiprows 1,4,10").skipRows == @[0, 3, 9]
        expect ValueError: discard parseOpts("--skiprows 1.2,3.4")
        check parseOpts("-r:1").skipRows == @[0]
        check parseOpts("-r:1-1").skipRows == @[0]
        check parseOpts("-r:1-3").skipRows == @[0, 1, 2]
        expect ArgumentError: discard parseOpts("-r:-1")
        expect ArgumentError: discard parseOpts("-r:1-")
        expect ArgumentError: discard parseOpts("-r:0")
        expect ArgumentError: discard parseOpts("-r:-1-1")
        expect ArgumentError: discard parseOpts("-r:1--1")
        check parseOpts("-r:1-1-5").skipRows == @[0, 1, 2, 3, 4]
        check parseOpts("-r:1-2-10").skipRows == @[0, 2, 4, 6, 8]
        check parseOpts("-r:1-1-1").skipRows == @[0]
        check parseOpts("-r:1-5-3").skipRows == @[0]
        expect ArgumentError: discard parseOpts("-r:1--1-1")
        expect ArgumentError: discard parseOpts("-r:1-1--1")
        expect ArgumentError: discard parseOpts("-r:1-1-")


suite "Table shape parsing":
    let log = newFileLogger("tests/readShape.log", mode = fmReadWrite)
    addHandler(log)

    test "tabTable3x3":
        info("starting tabTable3x3 test")
        let input = newStringStream(tabTable3x3)
        check readShape(input, '\t', warnings = true) == (3, 3)
        require atEnd(input)

        input.setPosition(0)
        check readShape(input, '.', warnings = true) == (3, 4)  # Suspect delimiter.
        require atEnd(input)

        input.setPosition(0)
        check readShape(input, ',', warnings = true) == (3, 1)  # Missing delimiter.
        require atEnd(input)

        check readLines(log.file)[^2..^1] == @[
            "WARN encountered malformed rows: 1,3.",
            "WARN delimiter ',' not found.",
        ]

        close input

    test "malformedCommaTable2x3":
        info("starting malformedCommaTable2x3 test")
        let input = newStringStream(malformedCommaTable2x3)
        # Malformed second line, bad quoting.
        check readShape(input, ',', warnings = true) == (2, 3)
        require atEnd(input)

        input.setPosition(0)
        expect ValueError: discard readShape(input, '"')  # Illegal delimiter.
        check atEnd(input) == false  # Nothing was read.

        check readLines(log.file)[^1] == "WARN encountered malformed rows: 2."
        close input

    test "malformedSpaceTable4x4":
        info("starting malformedSpaceTable4x4 test")
        let input = newStringStream(malformedSpaceTable4x4)
        # Empty leading/trailing column is counted.
        check readShape(input, ' ', warnings = true) == (4, 4)
        require atEnd(input)

        check readLines(log.file)[^1] == "WARN encountered malformed rows: 2."
        close input

    test "malformedCommaTable101x3":
        info("starting malformedCommaTable101x3 test")
        let input = newStringStream(malformedCommaTable101x3)
        var badRows = newSeq[int](100)
        for i in 2..101: badRows[i - 2] = i
        var badRowString = badRows.join(",")
        check readShape(input, ',', warnings = true) == (101, 3)
        require atEnd(input)

        check readLines(log.file)[^1] == "WARN encountered malformed rows: {badRowString}.".fmt
        close input

    test "malformedCommaTable102x3":
        info("starting malformedCommaTable102x3 test")
        let input = newStringStream(malformedCommaTable102x3)
        var badRows = newSeq[int](100)
        for i in 2..100: badRows[i - 2] = i
        badRows[^1] = 102
        var badRowString = badRows[0..^2].join(",") & "..." & $badRows[^1]
        check readShape(input, ',', warnings = true) == (102, 3)
        require atEnd(input)

        check readLines(log.file)[^1] == "WARN encountered malformed rows: {badRowString}.".fmt
        close input

    close log.file


suite "Cell padding":
    test "tabTable3x3":
        let input = newStringStream(tabTable3x3)
        var table = readTable(input, '\t')
        check table == @[
            @["a", "b", "c"],
            @["0.1", "0.2", "0.3"],
            @["\"\t1\"", "\"2\t\"", "\"3\t3\""],
        ]
        padCells(table)
        check table == @[
            @["   a", "   b", "    c"],
            @[" 0.1", " 0.2", "  0.3"],
            @["\"\t1\"", "\"2\t\"", "\"3\t3\""],
        ]

        close input

    test "malformedCommaTable2x3":
        let input = newStringStream(malformedCommaTable2x3)
        var table = readTable(input, ',')
        check table == @[@["ä", "¿", "©"], @["1\", \"2", "3\"", ""]]
        padCells(table)
        # Unicode characters create weird cell sizes, because they have len(char) == 2.
        # Could handle this by using Runes <https://nim-lang.org/docs/unicode.html>?
        check table == @[@["    ä", "¿", "©"], @["1\", \"2", "3\"", "  "]]

        close input

    test "malformedSpaceTable4x4":
        let input = newStringStream(malformedSpaceTable4x4)
        var table = readTable(input, ' ')
        check table == @[
            @["", "a", "b", "c\" \""],
            @["", "", "", ""],
            @["", "10", "20", "30"],
            @["", "1", "2", ""],
        ]
        padCells(table)
        check table == @[
            @["", " a", " b", "c\" \""],
            @["", "  ", "  ", "    "],
            @["", "10", "20", "  30"],
            @["", " 1", " 2", "    "],
        ]

        close input


suite "Row and column skipping":
    test "tabTable3x3":
        let input = newStringStream(tabTable3x3)
        var table = readTable(input, '\t', skipRows = @[2])
        check table == @[@["a", "b", "c"], @["0.1", "0.2", "0.3"]]
        input.setPosition(0)
        table = readTable(input, '\t', skipCols = @[2])
        check table == @[@["a", "b"], @["0.1", "0.2"], @["\"\t1\"", "\"2\t\""]]
        input.setPosition(0)
        table = readTable(input, '\t', skipRows = @[0, 1, 2])
        check table == newSeq[seq[string]]()
        input.setPosition(0)
        table = readTable(input, '\t', skipCols = @[2, 1, 0])
        check table == newSeq[seq[string]]()

        close input

    test "malformedCommaTable2x3":
        let input = newStringStream(malformedCommaTable2x3)
        var table = readTable(input, ',', skipRows = @[0], skipCols = @[1])
        check table == @[@["1\", \"2", ""]]
        input.setPosition(0)
        table = readTable(input, ',', skipRows = @[0, 1], skipCols = @[1])
        check table == newSeq[seq[string]]()
        input.setPosition(0)
        table = readTable(input, ',', skipRows = @[1], skipCols = @[1, 0, 2, 1, 2])
        check table == newSeq[seq[string]]()

        close input

    test "malformedSpaceTable4x4":
        let input = newStringStream(malformedSpaceTable4x4)
        var table = readTable(input, ' ', skipRows = @[1], skipCols = @[0])
        check table == @[@["a", "b", "c\" \""], @["10", "20", "30"], @["1", "2", ""]]
        input.setPosition(0)
        table = readTable(input, ' ', skipRows = @[1], skipCols = @[0, 3])
        check table == @[@["a", "b"], @["10", "20"], @["1", "2"]]
        input.setPosition(0)
        table = readTable(input, ' ', skipRows = @[0, 1, 2, 3], skipCols = @[1])
        check table == newSeq[seq[string]]()

        close input


suite "Transpose":
    test "tabTable3x3":
        let input = newStringStream(tabTable3x3)
        let table = readTable(input, '\t')
        check transpose(table) == @[
            @["a", "0.1", "\"\t1\""],
            @["b", "0.2", "\"2\t\""],
            @["c", "0.3", "\"3\t3\""],
        ]
        check transpose(transpose(table)) == table

        close input

    test "malformedCommaTable2x3":
        let input = newStringStream(malformedCommaTable2x3)
        let table = readTable(input, ',')
        check transpose(table) == @[@["ä", "1\", \"2"], @["¿", "3\""], @["©", ""]]
        check transpose(transpose(table)) == table

        close input

    test "malformedSpaceTable4x4":
        let input = newStringStream(malformedSpaceTable4x4)
        let table = readTable(input, ' ')
        check transpose(table) == @[
            @["", "", "", ""],
            @["a", "", "10", "1"],
            @["b", "", "20", "2"],
            @["c\" \"", "", "30", ""],
        ]
        check transpose(transpose(table)) == table

        close input

    test "malformedCommaTable101x3":
        # TODO: Better tests for large tables?
        let input = newStringStream(malformedCommaTable101x3)
        let table = readTable(input, ',')
        check transpose(transpose(table)) == table

        close input

    test "malformedCommaTable102x3":
        # TODO: Better tests for large tables?
        let input = newStringStream(malformedCommaTable102x3)
        let table = readTable(input, ',')
        check transpose(transpose(table)) == table

        close input

    test "empty table (no-op)":
        expect IOError: discard readTable(newStringStream(""), ',')
        let input = newStringStream("a, b, c")
        let table = readTable(input, ',', skipRows = @[0])
        require table == newSeq[seq[string]]()
        check transpose(table) == newSeq[seq[string]]()

        close input

    test "malformed tables (raw)":
        # Underfull table is filled with empty cells during transpose.
        check transpose(@[@["a", "b", "c"], @["1", "2"]]) == @[
            @["a", "1"], @["b", "2"], @["c", ""]
        ]
        # Malformed table: IndexDefect.
        expect IndexDefect: discard transpose(@[@["a", "b"], @["1", "2", "3"]])


suite "reshape":
    test "tabTable3x3":
        let input = newStringStream(tabTable3x3)
        let table = readTable(input, '\t')
        # Check reshaping to single-row and single-column tables.
        check reshape(table, (rows: 1, cols: 9)) == @[
            @["a", "b", "c", "0.1", "0.2", "0.3", "\"\t1\"", "\"2\t\"", "\"3\t3\""]
        ]
        check reshape(table, (rows: 9, cols: 1)) == @[
            @["a"],
            @["b"],
            @["c"],
            @["0.1"],
            @["0.2"],
            @["0.3"],
            @["\"\t1\""],
            @["\"2\t\""],
            @["\"3\t3\""],
        ]

        close input

    test "malformedCommaTable2x3":
        let input = newStringStream(malformedCommaTable2x3)
        let table = readTable(input, ',')
        check reshape(table, (rows: 3, cols: 2)) == @[
            @["ä", "¿"],
            @["©", "1\", \"2"],
            @["3\"", ""],
        ]
        # Check that we can un-reshape.
        check reshape(reshape(table, (rows: 3, cols: 2)), (rows: 2, cols: 3)) == table

        close input

    test "malformedSpaceTable4x4":
        let input = newStringStream(malformedSpaceTable4x4)
        let table = readTable(input, ' ')
        check reshape(table, (rows: 4, cols: 4)) == @[  # No-op.
            @["", "a", "b", "c\" \""],
            @["", "", "", ""],
            @["", "10", "20", "30"],
            @["", "1", "2", ""],
        ]
        # Reshaping to smaller capacity: ValueError.
        expect ValueError: discard reshape(table, (rows: 2, cols: 4))

        close input

    test "malformed tables (raw)":
        # Underfull table, filled in with empty cells.
        check reshape(@[@["a", "b", "c"], @["1", "2"]], (rows: 3, cols: 2)) == @[
            @["a", "b"], @["c", "1"], @["2", ""]
        ]
        # Malformed table: ValueError.
        expect ValueError: discard reshape(
            @[@["a", "b"], @["1", "2", "3"]], (rows: 3, cols: 2)
        )
        # Overfull table: IndexDefect.
        expect IndexDefect: discard reshape(
            @[@["a", "b", "c"], @["1", "2", "3", "4"]], (rows: 3, cols: 2)
        )
