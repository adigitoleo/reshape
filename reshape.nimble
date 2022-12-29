import strformat

version = "0.4.1"
author = "adigitoleo"
description = "Reshape a delimited text file"
license = "0BSD"

requires "nim >= 1.4.8"

srcdir = "src"
bindir = "build/bin"

bin = @["reshape"]

task release, "Create release commit and tag":
    let name = projectName()
    try:
        exec "test $(git describe --abbrev=0) != v{version}".fmt
    except OSError:
        echo "Aborted: v{version} tag already exists.".fmt
        quit(1)
    echo "Tagging {name} version {version}:".fmt
    echo "Checking git branch..."
    try:
        exec "test $(git symbolic-ref HEAD) = refs/heads/main"
    except OSError:
        echo "Aborted: must be on main branch to tag a new version."
        quit(1)
    echo "Checking git status..."
    try:
        exec "test \"$(git status --porcelain)\" = 'M  {name}.nimble'".fmt
    except OSError:
        echo "Aborted: should (only) have modified (and commited) nimble file."
        quit(1)
    echo "Creating release commit..."
    exec "git commit -m'release: Version {version}'".fmt
    echo "Creating release tag..."
    exec "git tag -a v{version} -m'Version {version}'".fmt
    echo "Done."
