# build2 Command Reference

Short per-command summaries. Each entry links to the corresponding `.cli` file
in `build2-docs/`.

---

## bpkg

[build2-docs/bpkg/bpkg.cli](build2-docs/bpkg/bpkg.cli)

Low-level package dependency manager that operates directly on a single bpkg
configuration. Manages packages, their dependencies, and the repositories from
which they are fetched.

### Configuration commands

| Command | CLI file | Summary |
|---------|----------|---------|
| `cfg-create` | [bpkg/cfg-create.cli](build2-docs/bpkg/cfg-create.cli) | Create a new bpkg configuration directory, loading specified build2 modules and configuration variables. |
| `cfg-info` | [bpkg/cfg-info.cli](build2-docs/bpkg/cfg-info.cli) | Print the current configuration's path, id, UUID, type, name, and mode. |
| `cfg-link` | [bpkg/cfg-link.cli](build2-docs/bpkg/cfg-link.cli) | Link another bpkg configuration with the current one so packages can be resolved across configurations. |
| `cfg-unlink` | [bpkg/cfg-unlink.cli](build2-docs/bpkg/cfg-unlink.cli) | Remove a previously established link between two configurations. Pass `--dangling` to remove links whose target no longer exists. |

### Package commands

| Command | CLI file | Summary |
|---------|----------|---------|
| `pkg-build` | [bpkg/pkg-build.cli](build2-docs/bpkg/pkg-build.cli) | Fetch, configure, and build one or more packages together with all their dependencies. The primary high-level package installation command. |
| `pkg-drop` | [bpkg/pkg-drop.cli](build2-docs/bpkg/pkg-drop.cli) | Drop (remove) specified packages and, optionally, their no-longer-needed dependents from the configuration. |
| `pkg-status` | [bpkg/pkg-status.cli](build2-docs/bpkg/pkg-status.cli) | Print the configured/available status of specified packages, or all held packages if none are specified. |
| `pkg-fetch` | [bpkg/pkg-fetch.cli](build2-docs/bpkg/pkg-fetch.cli) | Fetch a package archive from an archive-based repository, leaving it in the fetched state. |
| `pkg-unpack` | [bpkg/pkg-unpack.cli](build2-docs/bpkg/pkg-unpack.cli) | Unpack a previously fetched archive, or register an external source directory as a package. |
| `pkg-checkout` | [bpkg/pkg-checkout.cli](build2-docs/bpkg/pkg-checkout.cli) | Check out a specific package version from a version-control-based (git) repository. |
| `pkg-configure` | [bpkg/pkg-configure.cli](build2-docs/bpkg/pkg-configure.cli) | Configure an unpacked source package or register a system-provided package, resolving its dependencies within the configuration. |
| `pkg-disfigure` | [bpkg/pkg-disfigure.cli](build2-docs/bpkg/pkg-disfigure.cli) | Disfigure a configured package, returning it to the unpacked state and removing its build artifacts. |
| `pkg-update` | [bpkg/pkg-update.cli](build2-docs/bpkg/pkg-update.cli) | Run the build system `update` operation on specified packages to (re)build them. |
| `pkg-clean` | [bpkg/pkg-clean.cli](build2-docs/bpkg/pkg-clean.cli) | Run the build system `clean` operation on specified packages to remove build artifacts. |
| `pkg-test` | [bpkg/pkg-test.cli](build2-docs/bpkg/pkg-test.cli) | Run the build system `test` operation on specified packages. |
| `pkg-install` | [bpkg/pkg-install.cli](build2-docs/bpkg/pkg-install.cli) | Run the build system `install` operation to install specified packages to a system location. |
| `pkg-uninstall` | [bpkg/pkg-uninstall.cli](build2-docs/bpkg/pkg-uninstall.cli) | Run the build system `uninstall` operation to remove previously installed packages. |
| `pkg-purge` | [bpkg/pkg-purge.cli](build2-docs/bpkg/pkg-purge.cli) | Remove a package's source directory and/or archive from the filesystem and deregister it from the configuration. |
| `pkg-verify` | [bpkg/pkg-verify.cli](build2-docs/bpkg/pkg-verify.cli) | Verify that a local archive file is a structurally valid bpkg package. |
| `pkg-bindist` | [bpkg/pkg-bindist.cli](build2-docs/bpkg/pkg-bindist.cli) | Generate a binary distribution package (e.g. DEB, RPM) for specified packages using their installed files. |

### Repository commands

| Command | CLI file | Summary |
|---------|----------|---------|
| `rep-add` | [bpkg/rep-add.cli](build2-docs/bpkg/rep-add.cli) | Add one or more package repository URLs to the configuration. |
| `rep-remove` | [bpkg/rep-remove.cli](build2-docs/bpkg/rep-remove.cli) | Remove specified repositories from the configuration. |
| `rep-list` | [bpkg/rep-list.cli](build2-docs/bpkg/rep-list.cli) | List all repositories currently registered in the configuration. |
| `rep-fetch` | [bpkg/rep-fetch.cli](build2-docs/bpkg/rep-fetch.cli) | Fetch the list of available packages from registered repositories, refreshing local package metadata. |
| `rep-info` | [bpkg/rep-info.cli](build2-docs/bpkg/rep-info.cli) | Print metadata about a specified repository (name, type, location, available packages). |
| `rep-create` | [bpkg/rep-create.cli](build2-docs/bpkg/rep-create.cli) | Regenerate `packages.manifest` and (optionally) `signature.manifest` in a local repository directory. |

### Other

| Command | CLI file | Summary |
|---------|----------|---------|
| `help` | [bpkg/help.cli](build2-docs/bpkg/help.cli) | Print help for a command or a help topic (e.g. `argument-grouping`, `repository-types`). |

---

## bdep

[build2-docs/bdep/bdep.cli](build2-docs/bdep/bdep.cli)

Project-level dependency manager used during development. Operates on a bdep
project (which may span multiple packages) and one or more linked bpkg
configurations, coordinating package initialization, synchronization, and
lifecycle across all of them.

### Configuration management

`bdep config` -- [build2-docs/bdep/config.cli](build2-docs/bdep/config.cli)

Manage the set of bpkg configurations associated with a bdep project.

| Subcommand | Summary |
|------------|---------|
| `config add` | Register an existing bpkg configuration directory with the project. |
| `config create` | Create a new bpkg configuration via `bpkg cfg-create` and register it with the project. |
| `config link` | Link the first specified configuration to the second via `bpkg cfg-link`. |
| `config unlink` | Unlink the first specified configuration from the second via `bpkg cfg-unlink`. |
| `config list` | Print the configurations associated with the project (supports `--stdout-format json`). |
| `config move` | Update the recorded directory path for a configuration after it has been moved on disk. |
| `config rename` | Assign a new name to an existing configuration. |
| `config remove` | Remove one or more configurations from the project's set (only possible when no packages are initialized in them). |
| `config set` | Modify the `--default`, `--forward`, and `--auto-sync` flags for one or more configurations. |

### Package lifecycle

| Command | CLI file | Summary |
|---------|----------|---------|
| `init` | [bdep/init.cli](build2-docs/bdep/init.cli) | Initialize one or more packages in one or more build configurations, fetching dependencies and running the first sync. |
| `deinit` | [bdep/deinit.cli](build2-docs/bdep/deinit.cli) | Deinitialize packages from build configurations, dropping them from bpkg and disabling forwarding. |
| `sync` | [bdep/sync.cli](build2-docs/bdep/sync.cli) | Synchronize the project with its build configurations: resolve dependency changes, reconfigure, and rebuild as needed. |
| `fetch` | [bdep/fetch.cli](build2-docs/bdep/fetch.cli) | Run `bpkg rep-fetch` on the project's prerequisite and complement repositories to refresh available package metadata. |

### Build operations

| Command | CLI file | Summary |
|---------|----------|---------|
| `update` | [bdep/update.cli](build2-docs/bdep/update.cli) | Update (build) project packages in one or more configurations. |
| `clean` | [bdep/clean.cli](build2-docs/bdep/clean.cli) | Clean project packages in one or more configurations. |
| `test` | [bdep/test.cli](build2-docs/bdep/test.cli) | Test project packages in one or more configurations. |

### Project creation and publishing

| Command | CLI file | Summary |
|---------|----------|---------|
| `new` | [bdep/new.cli](build2-docs/bdep/new.cli) | Scaffold a new build2 project, package, or source subdirectory from a template (C++ library, executable, bare, etc.). |
| `release` | [bdep/release.cli](build2-docs/bdep/release.cli) | Manage a release: bump the version in `manifest`, commit, tag, and optionally push. Also handles opening the next development cycle. |
| `publish` | [bdep/publish.cli](build2-docs/bdep/publish.cli) | Publish project packages to a `bpkg` archive-based repository (e.g. cppget.org). |
| `ci` | [bdep/ci.cli](build2-docs/bdep/ci.cli) | Submit a CI test request for project packages to a remote CI service. |

### Information and help

| Command | CLI file | Summary |
|---------|----------|---------|
| `status` | [bdep/status.cli](build2-docs/bdep/status.cli) | Print the status of project packages and/or their dependencies across build configurations. |
| `help` | [bdep/help.cli](build2-docs/bdep/help.cli) | Print help for a command or a help topic. |
