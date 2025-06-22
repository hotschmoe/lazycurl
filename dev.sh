#!/bin/bash

# Run the app, capture exit code
cargo run
EXIT_CODE=$?

# Always reset terminal (even if app failed)
reset

exit $EXIT_CODE
