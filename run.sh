#!/bin/sh

zig build && zig-out/bin/paletter $@
