# Project Guidelines

## Overview
This workspace is a monorepo containing several independent Zig projects, primarily focused on learning and re-creating core technologies like Wayland protocols, PostScript interpreters, and HTTP servers.

## Code Style
- **Language**: Zig (latest stable or nightly as configured).
- **Formatting**: Always run `zig fmt` on modified files.
- **Naming**: Follow standard Zig naming conventions (snake_case for functions/variables, CamelCase for types).
- **Error Handling**: Use Zig's error union types (`!T`) and `try`/`catch` mechanisms. Avoid `catch unreachable` unless absolutely certain.

## Architecture

### Sub-projects
- **`gui/`**: A Wayland client implementation. Uses `wayland-protocols` vendored in `zig-pkg`. Currently disabled in the root build.
- **`http_server/`**: A simple HTTP server implementation with Python connection script.
- **`ladder/`**: A word ladder game/solver.
- **`protocol/`**: Core library for the Wayland wire protocol (marshalling/unmarshalling, connection handling).
- **`ps/`**: A PostScript interpreter and lexer.
- **`send_fd/`**: specific example demonstrating file descriptor passing over Unix domain sockets (essential for Wayland).

### Dependency Management
- **Vendoring**: Dependencies are often vendored in `zig-pkg` directories (e.g., in `gui/`).
- **Build System**: Each project has its own `build.zig`. A root `build.zig` orchestrates building most sub-projects.

## Build and Test

### Root Build
The root `build.zig` is configured to build most projects at once.
```bash
zig build
```
*Note: The `gui` project is currently commented out in the root build configuration.*

### Individual Projects
To build or run specific projects, navigate to their directory or use the `-p` flag if supported, but standard practice is:
```bash
cd <project-dir>
zig build
# or to run
zig build run
```

### Testing
Run standard Zig tests:
```bash
zig build test
```

## Conventions
- **Main Entry Points**: typically `src/main.zig`.
- **Root Source**: `src/root.zig` is used for libraries.
- **Wayland Protocols**: The `gui` project manually handles Wayland protocol generation/integration from `zig-pkg`.

## Agent Behavior
- **Role**: Act as an expert Zig systems programmer.
- **Focus**: When working on `protocol`, `gui`, or `send_fd`, keep in mind the context of Wayland implementation details (shared memory, fd passing, wire format).
- **Safety**: Prefer safe Zig patterns (checked arithmetic, optional unpacking) over unsafe pointer casts unless interfacing with C ABI or raw wire formats.
