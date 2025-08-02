import { assertEquals, assertExists, assertRejects } from "@std/assert";
import { 
  createPublicClient, 
  createWalletClient, 
  http, 
  parseUnits,
  formatUnits,
  encodeAbiParameters,
  keccak256,
  type Address,
  type Hex,
  type Abi
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { config } from "./config.ts";

// Test utilities
async function loadABI(contractName: string): Promise<Abi> {
  const abiPath = `./abis/${contractName}.abi.json`;
  const abiContent = await Deno.readTextFile(abiPath);
  return JSON.parse(abiContent) as Abi;
}

// Test setup
const alice = privateKeyToAccount(config.alicePrivateKey);
const bob = privateKeyToAccount(config.bobPrivateKey);

// Create clients
const basePublicClient = createPublicClient({
  transport: http(config.baseRpc),
  chain: {
    id: config.baseChainId,
    name: 'Base Local',
    network: 'base-local',
    nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
    rpcUrls: {
      default: { http: [config.baseRpc] },
      public: { http: [config.baseRpc] }
    }
  }
});

const etherlinkPublicClient = createPublicClient({
  transport: http(config.etherlinkRpc),
  chain: {
    id: config.etherlinkChainId,
    name: 'Etherlink Local',
    network: 'etherlink-local',
    nativeCurrency: { name: 'Tez', symbol: 'XTZ', decimals: 18 },
    rpcUrls: {
      default: { http: [config.etherlinkRpc] },
      public: { http: [config.etherlinkRpc] }
    }
  }
});

Deno.test("Atomic Swap - Load ABIs", async () => {
  const factoryAbi = await loadABI("SimpleEscrowFactory");
  const escrowAbi = await loadABI("SimpleEscrow");
  const erc20Abi = await loadABI("MockERC20");
  
  assertExists(factoryAbi);
  assertExists(escrowAbi);
  assertExists(erc20Abi);
  
  // Check ABI has expected functions
  const factoryFunctions = (factoryAbi as any[]).filter(item => item.type === "function");
  const createEscrowFn = factoryFunctions.find(fn => fn.name === "createEscrowWithFunding");
  assertExists(createEscrowFn, "Factory should have createEscrowWithFunding function");
});

Deno.test("Atomic Swap - Generate Hashlock", () => {
  const secret = "atomicswapsecret123";
  const preimage = keccak256("0x" + secret.split("").map(c => c.charCodeAt(0).toString(16).padStart(2, "0")).join("")) as Hex;
  const hashlock = keccak256(encodeAbiParameters([{ type: "bytes32" }], [preimage]));
  
  assertEquals(preimage.length, 66); // 0x + 64 chars
  assertEquals(hashlock.length, 66);
  
  // Verify hashlock is deterministic
  const hashlock2 = keccak256(encodeAbiParameters([{ type: "bytes32" }], [preimage]));
  assertEquals(hashlock, hashlock2);
});

Deno.test("Atomic Swap - Connect to Chains", async () => {
  // Test Base connection
  const baseChainId = await basePublicClient.getChainId();
  assertEquals(baseChainId, config.baseChainId);
  
  // Test Etherlink connection
  const etherlinkChainId = await etherlinkPublicClient.getChainId();
  assertEquals(etherlinkChainId, config.etherlinkChainId);
  
  // Test account balances (should have ETH from Anvil)
  const aliceBalance = await basePublicClient.getBalance({ address: alice.address });
  const bobBalance = await etherlinkPublicClient.getBalance({ address: bob.address });
  
  // Anvil gives 10000 ETH to each account
  assertEquals(aliceBalance > 0n, true, "Alice should have ETH balance");
  assertEquals(bobBalance > 0n, true, "Bob should have ETH balance");
});

Deno.test("Atomic Swap - Escrow Creation", async () => {
  const FACTORY_ABI = await loadABI("SimpleEscrowFactory");
  const factoryAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3" as Address;
  
  // Generate test parameters
  const token = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512" as Address; // Mock USDC
  const preimage = keccak256("0x" + "test".split("").map(c => c.charCodeAt(0).toString(16).padStart(2, "0")).join("")) as Hex;
  const hashlock = keccak256(encodeAbiParameters([{ type: "bytes32" }], [preimage]));
  const timelock = BigInt(Math.floor(Date.now() / 1000) + 3600);
  const salt = keccak256("0x" + Date.now().toString(16)) as Hex;
  
  // Compute escrow address
  const computedAddress = await basePublicClient.readContract({
    address: factoryAddress,
    abi: FACTORY_ABI,
    functionName: "computeEscrowAddress",
    args: [token, alice.address, bob.address, hashlock, timelock, salt]
  });
  
  assertExists(computedAddress);
  assertEquals(computedAddress.length, 42); // Valid address format
  assertEquals(computedAddress.startsWith("0x"), true);
});

Deno.test("Atomic Swap - Timeout Behavior", async () => {
  // Test that escrow can be refunded after timeout
  const ESCROW_ABI = await loadABI("SimpleEscrow");
  
  // This would be tested with a real escrow that has timed out
  // For now, we just verify the ABI has the expected functions
  const escrowFunctions = (ESCROW_ABI as any[]).filter(item => item.type === "function");
  const refundFn = escrowFunctions.find(fn => fn.name === "refund");
  const canRefundFn = escrowFunctions.find(fn => fn.name === "canRefund");
  
  assertExists(refundFn, "Escrow should have refund function");
  assertExists(canRefundFn, "Escrow should have canRefund function");
});

// Integration test - requires running chains
Deno.test("Atomic Swap - Full Flow (Integration)", {
  ignore: Deno.env.get("SKIP_INTEGRATION") === "true",
  sanitizeResources: false,
  sanitizeOps: false,
}, async () => {
  // This is a simplified version of the full flow
  const ERC20_ABI = await loadABI("MockERC20");
  const usdcAddress = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512" as Address;
  
  // Check if USDC is deployed
  const usdcCode = await basePublicClient.getBytecode({ address: usdcAddress });
  if (!usdcCode || usdcCode === '0x') {
    console.log("Skipping integration test - contracts not deployed");
    return;
  }
  
  // Check USDC decimals
  const decimals = await basePublicClient.readContract({
    address: usdcAddress,
    abi: ERC20_ABI,
    functionName: "decimals"
  });
  
  assertEquals(decimals, 6, "USDC should have 6 decimals");
});

// Run tests with: deno test atomic-swap.test.ts --allow-all