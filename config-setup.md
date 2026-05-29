# How to Set Up Linked build2 Configurations

This document describes how to create and wire three build2 configurations for
a project:

- `@host` -- tools compiled for the build machine (host type)
- `@<config>` -- main target configuration
- `@<config>-external` -- external/third-party dependencies

UUIDs are derived deterministically from each config name (e.g. via md5sum) so
they remain stable across recreations.

---

## 1. Initialize the project skeleton

```sh
bdep init --empty --directory "$PROJECT_DIR"
```

Run only if the project has no `.bdep` directory yet.

---

## 2. Create the configurations

### host

```sh
bpkg cfg-create \
    --uuid <uuid> \
    --name host \
    --directory "$BUILD_DIR_HOST" \
    --type host \
    --wipe \
    cc \
    config.config.load=~host
```

Create once and reuse across reinitializations.

### main

Always wiped and recreated. Link it to `@host` at creation time via
`--host-config`.

```sh
bpkg cfg-create \
    --uuid <uuid> \
    --name $CONFIG_NAME \
    --directory "$BUILD_DIR" \
    --host-config "$BUILD_DIR_HOST" \
    --wipe \
    cc
```

### external

Create once (skip if it already exists).

```sh
bpkg cfg-create \
    --uuid <uuid> \
    --name $CONFIG_NAME_EXT \
    --directory "$BUILD_DIR_EXT" \
    --wipe \
    cc
```

Then register the upstream package repositories. This is required so that
the lockfile enforcement machinery can resolve packages by plain `name/version`
without the `?` prefix (which only works for packages that already have
dependents in the same configuration).

```sh
bpkg rep-add https://pkg.cppget.org/1/stable https://pkg.cppget.org/1/testing \
    -d "$BUILD_DIR_EXT"
bpkg rep-fetch -d "$BUILD_DIR_EXT"
```

---

## 3. Clean dangling links

```sh
bpkg cfg-unlink --directory "$BUILD_DIR"      --dangling
bpkg cfg-unlink --directory "$BUILD_DIR_EXT"  --dangling
bpkg cfg-unlink --directory "$BUILD_DIR_HOST" --dangling
```

---

## 4. Link main to external

Allows the main configuration to resolve dependencies from the external one.

```sh
bpkg cfg-link --directory "$BUILD_DIR" "$BUILD_DIR_EXT" --relative
```

---

## 5. Configure all three

```sh
b configure: "$BUILD_DIR_HOST/" config.config.load=~host

b configure: "$BUILD_DIR/"

b configure: "$BUILD_DIR_EXT/"
```

`config.config.load` only accepts file paths or the special `~host` value.
Compiler settings (MSVC on Windows) are auto-detected and require no extra
flags. Any additional configuration variables (e.g. `config.cxx.std=17`) can
be appended directly to the relevant `b configure:` invocation.

---

## 6. Register the configurations with the project

```sh
bdep config add --directory "$PROJECT_DIR" @host             "$BUILD_DIR_HOST" --no-default --forward
bdep config add --directory "$PROJECT_DIR" @$CONFIG_NAME_EXT "$BUILD_DIR_EXT"  --no-default --no-forward
bdep config add --directory "$PROJECT_DIR" @$CONFIG_NAME     "$BUILD_DIR"      --no-default --no-forward
```

Then promote the main config to default and forwarded:

```sh
bdep config set --directory "$PROJECT_DIR" @$CONFIG_NAME --default --forward
bdep sync
```

Clear `--default --forward` from any previously-default config first:

```sh
bdep config set --directory "$PROJECT_DIR" @$OLD_DEFAULT --no-default --no-forward
```

---

## 7. Initialize packages

```sh
# Fetch external dependencies into @<config>-external
bdep init -d <pkg> ... @$CONFIG_NAME_EXT

# Remove local packages from the external config (keep only third-party deps)
bdep deinit @$CONFIG_NAME_EXT --force -d <pkg> ...
bpkg pkg-drop --directory "$BUILD_DIR_EXT" --keep-unused --drop-dependent --yes <pkg-names> ...

# Initialize local packages in the main config (deps resolved via cfg-link to external)
bdep init @$CONFIG_NAME --no-sync -d <pkg> ...

bdep sync --upgrade --yes -d <pkg> ...
```
