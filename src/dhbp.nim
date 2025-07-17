import std/[os, sequtils, strutils, json]

import climate

import dhbp/flavors/[slim, regular]

proc isLatest(props: JsonNode): bool =
  newJString("latest") in props.getOrDefault("tags").getElems()

proc isDefault(props: JsonNode): bool =
  props.getOrDefault("default").getBool

proc getTags(version, base, flavor: tuple[key: string, val: JsonNode]): seq[string] =
  result.add([version.key, base.key, flavor.key].join("-"))

proc getSharedTags(
    version, base, flavor: tuple[key: string, val: JsonNode]
): seq[string] =
  var tagBases: seq[string]

  tagBases.add(version.key)

  for tag in version.val.getOrDefault("tags").getElems():
    tagBases.add(tag.getStr())

  for tagBase in tagBases:
    if base.val.isDefault:
      result.add([tagBase, flavor.key].join("-"))

    if flavor.val.isDefault:
      result.add([tagBase, base.key].join("-"))

    if base.val.isDefault and flavor.val.isDefault:
      result.add(tagBase)

proc generateDockerfile(
    version, base, flavor: string,
    labels: openarray[(string, string)],
    dockerfileDir: string,
) =
  var content = ""

  case flavor
  of "slim":
    case base
    of "ubuntu":
      content = slim.ubuntu(version, labels)
    of "alpine":
      content = slim.alpine(version, labels)
    else:
      discard
  of "regular":
    case base
    of "ubuntu":
      content = regular.ubuntu(version, labels)
    of "alpine":
      content = regular.alpine(version, labels)
    else:
      discard
  else:
    discard

  createDir(dockerfileDir)

  writeFile(dockerfileDir / "Dockerfile", content)

proc buildAndPushImage(
    tags: openarray[string], tagPrefix: string, dockerfileDir: string
) =
  const dockerBuildCommand =
    "docker buildx build --push --platform linux/amd64,linux/arm64,linux/arm $# $#"

  var tagLine = ""

  for tag in tags:
    tagLine &= " -t $#:$# " % [tagPrefix, tag]

  discard execShellCmd dockerBuildCommand % [tagLine, dockerfileDir]

proc testImage(image: string, flavor: string) =
  let succeeded =
    case flavor
    of "slim":
      let cmd = "docker run --rm $# nim --version" % image
      execShellCmd(cmd) == 0
    of "regular":
      # Check that nimble at least launches
      let cmd = "docker run --rm $# nimble --version" % image
      execShellCmd(cmd) == 0
    else:
      true

  if not succeeded:
    echo "Failed the image test"

proc showHelp(context: Context): int =
  const helpMessage =
    """Before running the app for the first time, create a multiarch builder:

  $ dhbp setup

Usage:

  $ dhbp build-and-push [--config|-c=config.json] [--all|-a] [--dry|-d] [--save|-s] [<version> <version> ...]

Build and push specific versions:

  $ dhbp build-and-push <version1> <version2> ...

Build and push specific versions and save the Dockerfiles in `Dockerfiles/<version>/<flavor>`:

  $ dhbp build-and-push --save <version1> <version2> ...

Build and push all versions listed in the config file:

  $ dhbp build-and-push --all
  
Use custom config file (by default, `config.json` in the current directory is used):

  $ dhbp build-and-push --config=path/to/custom_config.json <version1> <version2> ...

Dry run (nothing is built or pushed, use to check the config and command args):

  $ dhbp build-and-push --dry <version1> <version2> ...
"""

  echo helpMessage

proc createBuilder(context: Context): int =
  const createDockerBuilderCommand =
    "docker buildx create --use --platform=linux/arm64,linux/amd64 --name multi-platform-builder"
  discard execShellCmd createDockerBuilderCommand

proc buildAndPushImages(context: Context): int =
  const
    labels =
      {"authors": "https://github.com/nim-lang/docker-images/graphs/contributors"}
    tagPrefix = "nimlang/nim"
    dockerfilesDir = "Dockerfiles"

  var
    configFile = "config.json"
    buildAll = false
    buildLatest = false
    dryRun = false
    save = false
    targets: seq[string] = @[]

  context.opt("config", "c"):
    configFile = val

  context.flag("all", "a"):
    buildAll = true

  context.flag("latest", "l"):
    buildLatest = true

  context.flag("dry", "d"):
    dryRun = true

  context.flag("save", "s"):
    save = true

  context.args:
    targets = args

  let
    config = parseFile(configFile)
    versions = config["versions"]
    bases = config["bases"]
    flavors = config["flavors"]

  for version in versions.pairs:
    if buildAll or version.key in targets or (buildLatest and version.val.isLatest):
      for base in bases.pairs:
        for flavor in flavors.pairs:
          let
            dockerfileDir = dockerfilesDir / version.key / flavor.key / base.key
            tags = getTags(version, base, flavor)

          echo "Building and pushing $# from $#... " % [tags[0], dockerfileDir]

          generateDockerfile(version.key, base.key, flavor.key, labels, dockerfileDir)

          if not dryRun:
            buildAndPushImage(tags, tagPrefix, dockerfileDir)

          if save:
            echo "Saving Dockerfile to $#..." % dockerfileDir
          else:
            removeDir(dockerfileDir)

          echo "Done!"

          # Anything before this is broken and too old to fix.
          if version.key >= "0.16.0":
            echo "Testing $#... " % tags[0]

            if not dryRun:
              testImage("$#:$#" % [tagPrefix, tags[0]], flavor.key)

            echo "Done!"

proc generateTagListMd(context: Context): int =
  const
    repoLocation = "https://github.com/nim-lang/docker-images/blob/develop"
    dockerfilesDir = "Dockerfiles"

  var configFile = "config.json"

  let
    config = parseFile(configFile)
    versions = config["versions"]
    bases = config["bases"]
    flavors = config["flavors"]

  for version in versions.pairs:
    for base in bases.pairs:
      for flavor in flavors.pairs:
        let
          dockerfileDir = [dockerfilesDir, version.key, flavor.key, base.key].join("/")
          tags = getTags(version, base, flavor)
          sharedTags = getSharedTags(version, base, flavor)

        echo(
          "- [$#]($#)" % [
            tags.mapIt("`" & it & "`").join(", "),
            [repoLocation, dockerfileDir, "Dockerfile"].join("/"),
          ]
        )

        if len(sharedTags) > 0:
          echo(
            "    - [$#]($#)" % [
              sharedTags.mapIt("`" & it & "`").join(", "),
              [repoLocation, dockerfileDir, "Dockerfile"].join("/"),
            ]
          )

proc generateDockerhubLibraryFile(context: Context): int =
  var
    configFile = "config.json"
    gitCommit = ""

  context.arg:
    gitCommit = arg
  do:
    quit "`commit` argument is mandatory"

  const dockerfilesDir = "Dockerfiles"

  let
    config = parseFile(configFile)
    versions = config["versions"]
    bases = config["bases"]
    flavors = config["flavors"]

  echo """# this file is generated via https://github.com/moigagoo/dhbp.git

Maintainers: Constantine Molchanov <moigagoo@duck.com> (@moigagoo),
             Akito <the@akito.ooo> (@theAkito)

GitRepo: https://github.com/nim-lang/docker-images.git
GitCommit: $#""" %
    gitCommit

  for version in versions.pairs:
    for base in bases.pairs:
      for flavor in flavors.pairs:
        let
          dockerfileDir = [dockerfilesDir, version.key, flavor.key, base.key].join("/")
          tags = getTags(version, base, flavor)
          sharedTags = getSharedTags(version, base, flavor)

        echo ""
        echo "Tags: $#" % tags.join(", ")

        if len(sharedTags) > 0:
          echo "SharedTags: $#" % sharedTags.join(", ")

        echo "Architectures: amd64, arm32v7, arm64v8"
        echo "Directory: $#" % dockerfileDir

const commands = {
  "build-and-push": buildAndPushImages,
  "setup": createBuilder,
  "generate-tag-list-md": generateTagListMd,
  "generate-dockerhub-library-file": generateDockerhubLibraryFile,
}

when isMainModule:
  quit parseCommands(commands, defaultHandler = showHelp)
