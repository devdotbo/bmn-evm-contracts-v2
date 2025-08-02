// Deno configuration for Viem atomic swap tests
// Uses proper Deno environment variable handling

import type { Hex, Address } from "viem";

// Load environment variables from .env file
// This requires --allow-read and --allow-env permissions
try {
  const dotenvPath = new URL("../.env", import.meta.url).pathname;
  const dotenvContent = await Deno.readTextFile(dotenvPath);
  
  // Parse .env content manually to avoid external dependencies
  for (const line of dotenvContent.split('\n')) {
    const trimmed = line.trim();
    if (trimmed && !trimmed.startsWith('#')) {
      const [key, ...valueParts] = trimmed.split('=');
      if (key) {
        const value = valueParts.join('=').replace(/^["']|["']$/g, '');
        // Only set if not already set (allows actual env vars to override .env)
        if (!Deno.env.has(key)) {
          Deno.env.set(key, value);
        }
      }
    }
  }
} catch (error) {
  console.warn("Could not load .env file:", error.message);
  console.warn("Using system environment variables only");
}

// Deployment data interface
export interface DeploymentData {
  timestamp: string;
  chains: {
    base?: {
      chainId: number;
      rpcUrl: string;
      contracts: {
        MockUSDC?: Address;
        SimpleEscrowFactory?: Address;
        OneInchAdapter?: Address;
      };
    };
    etherlink?: {
      chainId: number;
      rpcUrl: string;
      contracts: {
        MockXTZ?: Address;
        SimpleEscrowFactory?: Address;
        LightningBridge?: Address;
      };
    };
  };
}

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
  
  // Contract addresses (loaded from deployment.json)
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

// Load deployment data
export async function loadDeploymentData(): Promise<DeploymentData | null> {
  try {
    const deploymentPath = "../deployment.json";
    const data = await Deno.readTextFile(deploymentPath);
    return JSON.parse(data) as DeploymentData;
  } catch (error) {
    console.warn("Could not load deployment.json:", error.message);
    return null;
  }
}

// Get configuration with deployment data
export async function getConfigWithDeployment(): Promise<Config> {
  const baseConfig = getConfig();
  const deployment = await loadDeploymentData();
  
  if (deployment) {
    // Load contract addresses from deployment
    if (deployment.chains.base) {
      baseConfig.factoryAddressBase = deployment.chains.base.contracts.SimpleEscrowFactory;
      baseConfig.usdcAddress = deployment.chains.base.contracts.MockUSDC;
    }
    
    if (deployment.chains.etherlink) {
      baseConfig.factoryAddressEtherlink = deployment.chains.etherlink.contracts.SimpleEscrowFactory;
      baseConfig.xtzAddress = deployment.chains.etherlink.contracts.MockXTZ;
    }
    
    console.log("Loaded contract addresses from deployment.json");
  } else {
    console.warn("No deployment data found, using default addresses");
    // Fallback to default addresses for local testing
    baseConfig.factoryAddressBase = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512" as Address;
    baseConfig.factoryAddressEtherlink = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512" as Address;
    baseConfig.usdcAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3" as Address;
    baseConfig.xtzAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3" as Address;
  }
  
  return baseConfig;
}

// Export default config
export const config = getConfig();
validateConfig(config);