# hello

Development workspace for the `lockfile` build2 package. `libhello` and
`libworld` are example C++ libraries that depend on `fmt`, `spdlog`, and
`entt` -- providing a realistic multi-configuration project for exercising
`lockfile` enforcement.

## Setup

The project uses three linked `bpkg` configurations. Adjust `CONFIG_NAME` for
your compiler (`msvc`, `gcc`, etc.).

```sh
CONFIG_NAME=msvc
BASE=hello  # matches the directory name

# Create configurations
bpkg cfg-create --name host                    --directory ../$BASE-host                    --type host --wipe cc config.config.load=~host
bpkg cfg-create --name $CONFIG_NAME            --directory ../$BASE-$CONFIG_NAME            --wipe cc
bpkg cfg-create --name $CONFIG_NAME-external   --directory ../$BASE-$CONFIG_NAME-external   --wipe cc

# Register package repositories in the external config
bpkg rep-add https://pkg.cppget.org/1/stable https://pkg.cppget.org/1/testing \
  -d ../$BASE-$CONFIG_NAME-external
bpkg rep-fetch -d ../$BASE-$CONFIG_NAME-external

# Link main -> external so dependency resolution flows between them
bpkg cfg-link --directory ../$BASE-$CONFIG_NAME ../$BASE-$CONFIG_NAME-external --relative

# Initialize the bdep project and register all three configurations
bdep init --empty
bdep config add @host                  ../$BASE-host                    --no-default --forward
bdep config add @$CONFIG_NAME-external ../$BASE-$CONFIG_NAME-external   --no-default --no-forward
bdep config add @$CONFIG_NAME          ../$BASE-$CONFIG_NAME            --no-default --no-forward
bdep config set @$CONFIG_NAME          --default --forward

# Fetch third-party deps into external, then drop the local packages from it
bdep init @$CONFIG_NAME-external \
  -d libhello -d libworld -d libhello-tests -d libworld-tests -d lockfile
bdep deinit @$CONFIG_NAME-external --force \
  -d libhello -d libworld -d libhello-tests -d libworld-tests -d lockfile
bpkg pkg-drop -d ../$BASE-$CONFIG_NAME-external --keep-unused --drop-dependent --yes \
  libhello libworld libhello-tests libworld-tests lockfile

# Initialize local packages into the main config (resolves deps via cfg-link)
bdep init @$CONFIG_NAME --no-sync \
  -d libhello -d libworld -d libhello-tests -d libworld-tests -d lockfile
bdep sync --upgrade --yes
```

## Lockfile tests

```sh
bash test-lockfile.sh [--quiet] [--case=N]
```

See [`lockfile/README.md`](lockfile/README.md) for lockfile package documentation.
