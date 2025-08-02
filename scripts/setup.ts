#!/usr/bin/env -S deno run --allow-all

import { ensureDir } from "https://deno.land/std@0.208.0/fs/mod.ts";

console.log("🚀 Setting up Deno atomic swap test environment...\n");

// Create necessary directories
const dirs = ["./abis", "../logs", "../deployments"];

for (const dir of dirs) {
  await ensureDir(dir);
  console.log(`✓ Created directory: ${dir}`);
}

// Create .env file if it doesn't exist
const envPath = "../.env";
const envExists = await Deno.stat(envPath).catch(() => null);

if (!envExists) {
  const envContent = `# Atomic Swap Test Configuration
# Private keys (DO NOT COMMIT!)
ALICE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
BOB_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d

# RPC URLs
BASE_RPC=http://localhost:8545
ETHERLINK_RPC=http://localhost:8546

# Chain IDs
BASE_CHAIN_ID=8453
ETHERLINK_CHAIN_ID=42793

# Test configuration
LOG_LEVEL=info
RETRY_ATTEMPTS=3
RETRY_DELAY=1000
`;
  
  await Deno.writeTextFile(envPath, envContent);
  console.log("✓ Created .env file with defaults");
} else {
  console.log("✓ .env file already exists");
}

// Check if forge is installed
const forgeCheck = await new Deno.Command("which", { args: ["forge"] }).output();
if (!forgeCheck.success) {
  console.error("\n❌ Forge not found! Please install Foundry:");
  console.error("   curl -L https://foundry.paradigm.xyz | bash");
  Deno.exit(1);
}

// Build contracts and copy ABIs
console.log("\n📦 Building contracts...");
const buildResult = await new Deno.Command("forge", {
  args: ["build"],
  cwd: "..",
}).output();

if (!buildResult.success) {
  console.error("❌ Contract build failed!");
  console.error(new TextDecoder().decode(buildResult.stderr));
  Deno.exit(1);
}

console.log("✓ Contracts built successfully");

// Copy ABIs
console.log("\n📋 Copying ABIs...");
const copyResult = await new Deno.Command("bash", {
  args: ["./copy-abis.sh"],
}).output();

if (!copyResult.success) {
  console.error("❌ Failed to copy ABIs!");
  console.error(new TextDecoder().decode(copyResult.stderr));
} else {
  console.log("✓ ABIs copied successfully");
}

// Show next steps
console.log("\n✅ Setup complete!\n");
console.log("Next steps:");
console.log("1. Start local chains: ../scripts/deploy-local.sh");
console.log("2. Run tests: deno task test");
console.log("3. Run atomic swap demo: deno task test:atomic-swap");
console.log("\nFor help, see README.md");