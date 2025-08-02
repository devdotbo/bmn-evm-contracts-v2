#!/usr/bin/env -S deno run --allow-env --allow-net

/**
 * Simple example of using Viem with Deno
 * This demonstrates the basic patterns for interacting with Ethereum using Viem in a Deno environment
 * 
 * Run with: deno run --allow-env --allow-net example-viem-test.ts
 */

import { 
  createPublicClient, 
  createWalletClient, 
  http, 
  parseEther,
  formatEther,
  type Address 
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { mainnet, sepolia } from "viem/chains";

// Example 1: Create a public client (read-only)
console.log("=== Example 1: Public Client ===");
const publicClient = createPublicClient({
  chain: mainnet,
  transport: http("https://eth.llamarpc.com"), // Free public RPC
});

// Get the latest block number
const blockNumber = await publicClient.getBlockNumber();
console.log(`Latest block number on mainnet: ${blockNumber}`);

// Example 2: Check an address balance
const vitalikAddress = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045" as Address;
const balance = await publicClient.getBalance({ address: vitalikAddress });
console.log(`Vitalik's balance: ${formatEther(balance)} ETH`);

// Example 3: Create a wallet client (for transactions)
console.log("\n=== Example 3: Wallet Client ===");

// Use environment variable or default test key
const privateKey = (Deno.env.get("PRIVATE_KEY") || 
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80") as `0x${string}`;

const account = privateKeyToAccount(privateKey);
console.log(`Wallet address: ${account.address}`);

// Create wallet client for testnet
const walletClient = createWalletClient({
  account,
  chain: sepolia,
  transport: http(), // Will use default Sepolia RPC
});

// Example 4: Environment variables in Deno
console.log("\n=== Example 4: Environment Variables ===");
console.log("Reading environment variables in Deno:");
console.log(`- Using Deno.env.get(): ${Deno.env.get("USER") || "not set"}`);
console.log(`- Checking with Deno.env.has(): USER exists = ${Deno.env.has("USER")}`);

// Example 5: Type safety with Viem
console.log("\n=== Example 5: Type Safety ===");
type TransferEvent = {
  from: Address;
  to: Address;
  value: bigint;
};

// This would be used with contract interactions
console.log("Viem provides full TypeScript support for:");
console.log("- Contract ABIs");
console.log("- Event types");
console.log("- Function parameters");
console.log("- Return types");

// Example 6: Error handling
console.log("\n=== Example 6: Error Handling ===");
try {
  // This will fail with invalid address
  await publicClient.getBalance({ 
    address: "0xinvalid" as Address 
  });
} catch (error) {
  console.log("Caught error (expected):", error.message);
}

console.log("\n✅ All examples completed!");
console.log("\nTo use in your project:");
console.log("1. Import viem: import { createPublicClient, http } from 'viem'");
console.log("2. Create clients with proper chain config");
console.log("3. Use environment variables with Deno.env");
console.log("4. Handle errors appropriately");
console.log("5. Leverage TypeScript for type safety");