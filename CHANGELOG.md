## [Unreleased]

## [0.1.0] - 2025-11-17

- Initial release
- Thread-safe progress counter using atomic database operations
- `ProgressCounter::Model` with `incr`, `incr_and_done?`, and `done?` methods
- **Truly atomic** fan-in detection: comparison happens in database via `UPDATE...RETURNING`
- Polymorphic association support via `progressable`
- Rails generator for migration (`rails generate progress_counter:migration`)
- Support for multiple counter types per progressable object
- SQL injection protection via parameterized queries
- Comprehensive test suite with 23 passing tests
- Full documentation with fan-out/fan-in examples
- Supports PostgreSQL, SQLite 3.35+, and MariaDB 10.5+
