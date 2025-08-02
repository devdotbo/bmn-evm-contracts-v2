import { load } from "@std/dotenv";
import type { Hex, Address } from "viem";

// Load environment variables
await load({ export: true, envPath: "../.env" });

// Configuration interface
export interface Config {
  // RPC URLs
  baseRpc: string;
  etherlinkRpc: string;
  
  // Private keys
  alicePrivateKey: Hex;
  bobPrivateKey: Hex;
  
  // Chain IDs
  baseChainId: number;
  etherlinkChainId: number;
  
  // Contract addresses (optional, can be loaded from deployment)
  factoryAddressBase?: Address;
  factoryAddressEtherlink?: Address;
  usdcAddress?: Address;
  xtzAddress?: Address;
  
  // Test configuration
  logLevel: 'debug' | 'info' | 'warn' | 'error';
  retryAttempts: number;
  retryDelay: number;
}

// Default test accounts (Anvil)
const DEFAULT_ALICE_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const DEFAULT_BOB_KEY = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";

// Get configuration from environment
export function getConfig(): Config {
  return {
    // RPC URLs
    baseRpc: Deno.env.get("BASE_RPC") || "http://localhost:8545",
    etherlinkRpc: Deno.env.get("ETHERLINK_RPC") || "http://localhost:8546",
    
    // Private keys (use defaults for local testing)
    alicePrivateKey: (Deno.env.get("ALICE_KEY") || DEFAULT_ALICE_KEY) as Hex,
    bobPrivateKey: (Deno.env.get("BOB_KEY") || DEFAULT_BOB_KEY) as Hex,
    
    // Chain IDs
    baseChainId: parseInt(Deno.env.get("BASE_CHAIN_ID") || "8453"),
    etherlinkChainId: parseInt(Deno.env.get("ETHERLINK_CHAIN_ID") || "42793"),
    
    // Test configuration
    logLevel: (Deno.env.get("LOG_LEVEL") || "info") as any,
    retryAttempts: parseInt(Deno.env.get("RETRY_ATTEMPTS") || "3"),
    retryDelay: parseInt(Deno.env.get("RETRY_DELAY") || "1000"),
  };
}

// Validate configuration
export function validateConfig(config: Config): void {
  if (!config.baseRpc || !config.etherlinkRpc) {
    throw new Error("RPC URLs must be configured");
  }
  
  if (!config.alicePrivateKey || !config.bobPrivateKey) {
    throw new Error("Private keys must be configured");
  }
  
  if (!config.alicePrivateKey.startsWith("0x") || config.alicePrivateKey.length !== 66) {
    throw new Error("Invalid Alice private key format");
  }
  
  if (!config.bobPrivateKey.startsWith("0x") || config.bobPrivateKey.length !== 66) {
    throw new Error("Invalid Bob private key format");
  }
}

// Export default config
export const config = getConfig();
validateConfig(config);