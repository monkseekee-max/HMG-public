#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.resolve(__dirname, "..");
const source = path.join(root, "native", "hmg_embedded_node.cc");
const output = path.join(root, "native", "hmg_embedded.node");
const includeDir = process.env.NODE_INCLUDE_DIR || "/usr/include/node";
const compiler = process.env.CXX || "c++";

fs.mkdirSync(path.dirname(output), { recursive: true });

let args;
if (os.platform() === "win32" && /^cl(\.exe)?$/i.test(path.basename(compiler))) {
  args = [
    "/std:c++17",
    "/LD",
    `/I${includeDir}`,
    source,
    `/Fe:${output}`,
  ];
} else {
  args = [
    "-std=c++17",
    "-shared",
    `-I${includeDir}`,
    source,
    "-o",
    output,
  ];
  if (os.platform() !== "win32") {
    args.splice(2, 0, "-fPIC");
  }
  if (os.platform() === "linux") {
    args.push("-ldl");
  }
  if (os.platform() === "darwin") {
    args.push("-undefined", "dynamic_lookup");
  }
}

const result = spawnSync(compiler, args, {
  cwd: root,
  stdio: "inherit",
});

if (result.status !== 0) {
  process.exit(result.status || 1);
}
