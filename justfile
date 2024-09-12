default:
    zig build run -- -s foot

run +args:
    zig build run -- -s {{args}}
