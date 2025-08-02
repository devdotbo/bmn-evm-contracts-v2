import { 
  createPublicClient, 
  createWalletClient, 
  http, 
  parseEther,
  parseUnits,
  formatUnits,
  encodeAbiParameters,
  keccak256,
  type Address,
  type Hash,
  type Hex
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

// Logger utility
class Logger {
  private logFile: string;
  
  constructor(logFile: string) {
    this.logFile = logFile;
    // Reset log file
    Deno.writeTextFileSync(this.logFile, `Atomic Swap Test Log - ${new Date().toISOString()}\n${"=".repeat(80)}\n\n`);
  }
  
  log(message: string, data?: any) {
    const timestamp = new Date().toISOString();
    const logEntry = `[${timestamp}] ${message}${data ? '\n' + JSON.stringify(data, null, 2) : ''}\n`;
    console.log(logEntry);
    Deno.writeTextFileSync(this.logFile, logEntry, { append: true });
  }
  
  error(message: string, error: any) {
    const timestamp = new Date().toISOString();
    const logEntry = `[${timestamp}] ERROR: ${message}\n${error.stack || error.message || error}\n`;
    console.error(logEntry);
    Deno.writeTextFileSync(this.logFile, logEntry, { append: true });
  }
}

// Contract ABIs
const ERC20_ABI = [
  {
    "inputs": [
      { "name": "spender", "type": "address" },
      { "name": "amount", "type": "uint256" }
    ],
    "name": "approve",
    "outputs": [{ "name": "", "type": "bool" }],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{ "name": "account", "type": "address" }],
    "name": "balanceOf",
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      { "name": "to", "type": "address" },
      { "name": "amount", "type": "uint256" }
    ],
    "name": "mint",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "decimals",
    "outputs": [{ "name": "", "type": "uint8" }],
    "stateMutability": "view",
    "type": "function"
  }
] as const;

const FACTORY_ABI = [
  {
    "inputs": [
      { "name": "token", "type": "address" },
      { "name": "sender", "type": "address" },
      { "name": "recipient", "type": "address" },
      { "name": "hashlock", "type": "bytes32" },
      { "name": "timelock", "type": "uint256" },
      { "name": "salt", "type": "bytes32" },
      { "name": "amount", "type": "uint256" }
    ],
    "name": "createEscrowWithFunding",
    "outputs": [{ "name": "escrow", "type": "address" }],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      { "name": "token", "type": "address" },
      { "name": "sender", "type": "address" },
      { "name": "recipient", "type": "address" },
      { "name": "hashlock", "type": "bytes32" },
      { "name": "timelock", "type": "uint256" },
      { "name": "salt", "type": "bytes32" }
    ],
    "name": "computeEscrowAddress",
    "outputs": [{ "name": "", "type": "address" }],
    "stateMutability": "view",
    "type": "function"
  }
] as const;

const ESCROW_ABI = [
  {
    "inputs": [{ "name": "_preimage", "type": "bytes32" }],
    "name": "withdraw",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "refund",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "getDetails",
    "outputs": [
      {
        "components": [
          { "name": "token", "type": "address" },
          { "name": "sender", "type": "address" },
          { "name": "recipient", "type": "address" },
          { "name": "hashlock", "type": "bytes32" },
          { "name": "timelock", "type": "uint256" },
          { "name": "amount", "type": "uint256" },
          { "name": "funded", "type": "bool" },
          { "name": "withdrawn", "type": "bool" },
          { "name": "refunded", "type": "bool" },
          { "name": "preimage", "type": "bytes32" }
        ],
        "name": "",
        "type": "tuple"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  }
] as const;

// Utility functions
async function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function retry<T>(
  fn: () => Promise<T>,
  retries: number = 3,
  delay: number = 1000
): Promise<T> {
  for (let i = 0; i < retries; i++) {
    try {
      return await fn();
    } catch (error) {
      if (i === retries - 1) throw error;
      await sleep(delay);
    }
  }
  throw new Error("Retry failed");
}

// Main atomic swap test
async function testAtomicSwap() {
  const logger = new Logger("../logs/atomic-swap.log");
  logger.log("Starting Atomic Swap Test");
  
  // Configuration
  const BASE_RPC = "http://localhost:8545";
  const ETHERLINK_RPC = "http://localhost:8546";
  
  // Test accounts (Anvil default accounts)
  const alicePrivateKey = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as Hex;
  const bobPrivateKey = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" as Hex;
  
  const alice = privateKeyToAccount(alicePrivateKey);
  const bob = privateKeyToAccount(bobPrivateKey);
  
  logger.log("Test Accounts", {
    alice: alice.address,
    bob: bob.address
  });
  
  // Create clients
  const basePublicClient = createPublicClient({
    transport: http(BASE_RPC)
  });
  
  const etherlinkPublicClient = createPublicClient({
    transport: http(ETHERLINK_RPC)
  });
  
  const baseWalletClient = createWalletClient({
    account: alice,
    transport: http(BASE_RPC)
  });
  
  const etherlinkWalletClient = createWalletClient({
    account: bob,
    transport: http(ETHERLINK_RPC)
  });
  
  try {
    // Load deployment addresses
    logger.log("Loading deployment addresses...");
    
    // Since we don't have deployment.json, we'll use known addresses from the deploy script
    // These are deterministic addresses when using Anvil
    const factoryAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3" as Address; // First deployed contract
    const usdcAddress = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512" as Address; // Second deployed contract (MockERC20)
    const xtzAddress = "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0" as Address; // Third deployed contract (MockERC20)
    
    logger.log("Contract Addresses", {
      factory: factoryAddress,
      usdc: usdcAddress,
      xtz: xtzAddress
    });
    
    // Deploy mock tokens if needed
    logger.log("Setting up test tokens...");
    
    // Mint USDC to Alice on Base
    await baseWalletClient.writeContract({
      address: usdcAddress,
      abi: ERC20_ABI,
      functionName: "mint",
      args: [alice.address, parseUnits("1000", 6)] // 1000 USDC
    });
    
    // Mint XTZ to Bob on Etherlink
    await etherlinkWalletClient.writeContract({
      address: xtzAddress,
      abi: ERC20_ABI,
      functionName: "mint",
      args: [bob.address, parseUnits("100", 18)] // 100 XTZ
    });
    
    await sleep(2000); // Wait for transactions to be mined
    
    // Check balances
    const aliceUsdcBalance = await basePublicClient.readContract({
      address: usdcAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [alice.address]
    });
    
    const bobXtzBalance = await etherlinkPublicClient.readContract({
      address: xtzAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [bob.address]
    });
    
    logger.log("Initial Balances", {
      aliceUsdc: formatUnits(aliceUsdcBalance, 6),
      bobXtz: formatUnits(bobXtzBalance, 18)
    });
    
    // Generate atomic swap parameters
    const preimage = keccak256("0x" + "atomicswapsecret123".split("").map(c => c.charCodeAt(0).toString(16).padStart(2, "0")).join("")) as Hex;
    const hashlock = keccak256(encodeAbiParameters([{ type: "bytes32" }], [preimage]));
    const timelock = BigInt(Math.floor(Date.now() / 1000) + 3600); // 1 hour from now
    const salt = keccak256("0x" + Date.now().toString(16)) as Hex;
    
    logger.log("Swap Parameters", {
      preimage,
      hashlock,
      timelock: timelock.toString(),
      salt
    });
    
    // Swap amounts
    const usdcAmount = parseUnits("100", 6); // 100 USDC
    const xtzAmount = parseUnits("10", 18); // 10 XTZ
    
    logger.log("=== STEP 1: Alice creates escrow on Base ===");
    
    // Alice approves USDC
    await baseWalletClient.writeContract({
      address: usdcAddress,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [factoryAddress, usdcAmount]
    });
    await sleep(2000);
    
    // Alice creates escrow on Base
    const createEscrowTx = await baseWalletClient.writeContract({
      address: factoryAddress,
      abi: FACTORY_ABI,
      functionName: "createEscrowWithFunding",
      args: [
        usdcAddress,
        alice.address,
        bob.address,
        hashlock,
        timelock,
        salt,
        usdcAmount
      ]
    });
    
    logger.log("Alice created escrow on Base", { tx: createEscrowTx });
    await sleep(3000);
    
    // Get escrow address
    const baseEscrowAddress = await basePublicClient.readContract({
      address: factoryAddress,
      abi: FACTORY_ABI,
      functionName: "computeEscrowAddress",
      args: [usdcAddress, alice.address, bob.address, hashlock, timelock, salt]
    });
    
    logger.log("Base escrow address", { escrow: baseEscrowAddress });
    
    // Verify escrow details
    const baseEscrowDetails = await basePublicClient.readContract({
      address: baseEscrowAddress,
      abi: ESCROW_ABI,
      functionName: "getDetails"
    });
    
    logger.log("Base escrow details", baseEscrowDetails);
    
    logger.log("=== STEP 2: Bob creates escrow on Etherlink ===");
    
    // Simulate Bob seeing Alice's escrow and creating corresponding one
    await sleep(2000);
    
    // Bob approves XTZ
    await etherlinkWalletClient.writeContract({
      address: xtzAddress,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [factoryAddress, xtzAmount]
    });
    await sleep(2000);
    
    // Bob creates escrow on Etherlink with same hashlock
    const bobSalt = keccak256("0x" + (Date.now() + 1).toString(16)) as Hex;
    const createEscrowTx2 = await etherlinkWalletClient.writeContract({
      address: factoryAddress,
      abi: FACTORY_ABI,
      functionName: "createEscrowWithFunding",
      args: [
        xtzAddress,
        bob.address,
        alice.address,
        hashlock, // Same hashlock!
        timelock,
        bobSalt,
        xtzAmount
      ]
    });
    
    logger.log("Bob created escrow on Etherlink", { tx: createEscrowTx2 });
    await sleep(3000);
    
    // Get Etherlink escrow address
    const etherlinkEscrowAddress = await etherlinkPublicClient.readContract({
      address: factoryAddress,
      abi: FACTORY_ABI,
      functionName: "computeEscrowAddress",
      args: [xtzAddress, bob.address, alice.address, hashlock, timelock, bobSalt]
    });
    
    logger.log("Etherlink escrow address", { escrow: etherlinkEscrowAddress });
    
    logger.log("=== STEP 3: Alice reveals preimage on Etherlink ===");
    
    // Simulate Alice waiting and then revealing
    await sleep(3000);
    
    // Alice withdraws on Etherlink using the preimage
    const aliceEtherlinkWallet = createWalletClient({
      account: alice,
      transport: http(ETHERLINK_RPC)
    });
    
    const withdrawTx = await aliceEtherlinkWallet.writeContract({
      address: etherlinkEscrowAddress,
      abi: ESCROW_ABI,
      functionName: "withdraw",
      args: [preimage]
    });
    
    logger.log("Alice withdrew on Etherlink", { tx: withdrawTx });
    await sleep(3000);
    
    // Check Alice's XTZ balance
    const aliceXtzBalance = await etherlinkPublicClient.readContract({
      address: xtzAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [alice.address]
    });
    
    logger.log("Alice received XTZ", { balance: formatUnits(aliceXtzBalance, 18) });
    
    logger.log("=== STEP 4: Bob uses preimage on Base ===");
    
    // Bob can now see the preimage from the Etherlink escrow
    const etherlinkDetails = await etherlinkPublicClient.readContract({
      address: etherlinkEscrowAddress,
      abi: ESCROW_ABI,
      functionName: "getDetails"
    });
    
    const revealedPreimage = etherlinkDetails.preimage;
    logger.log("Bob found preimage", { preimage: revealedPreimage });
    
    // Bob withdraws on Base using the revealed preimage
    const bobBaseWallet = createWalletClient({
      account: bob,
      transport: http(BASE_RPC)
    });
    
    const withdrawTx2 = await bobBaseWallet.writeContract({
      address: baseEscrowAddress,
      abi: ESCROW_ABI,
      functionName: "withdraw",
      args: [revealedPreimage]
    });
    
    logger.log("Bob withdrew on Base", { tx: withdrawTx2 });
    await sleep(3000);
    
    // Check Bob's USDC balance
    const bobUsdcBalance = await basePublicClient.readContract({
      address: usdcAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [bob.address]
    });
    
    logger.log("Bob received USDC", { balance: formatUnits(bobUsdcBalance, 6) });
    
    logger.log("=== STEP 5: Verify final balances ===");
    
    // Check all final balances
    const finalAliceUsdc = await basePublicClient.readContract({
      address: usdcAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [alice.address]
    });
    
    const finalAliceXtz = await etherlinkPublicClient.readContract({
      address: xtzAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [alice.address]
    });
    
    const finalBobUsdc = await basePublicClient.readContract({
      address: usdcAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [bob.address]
    });
    
    const finalBobXtz = await etherlinkPublicClient.readContract({
      address: xtzAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [bob.address]
    });
    
    logger.log("Final Balances", {
      alice: {
        usdc: formatUnits(finalAliceUsdc, 6),
        xtz: formatUnits(finalAliceXtz, 18)
      },
      bob: {
        usdc: formatUnits(finalBobUsdc, 6),
        xtz: formatUnits(finalBobXtz, 18)
      }
    });
    
    // Verify swap success
    const swapSuccess = 
      finalAliceUsdc < aliceUsdcBalance && // Alice sent USDC
      finalAliceXtz > 0n && // Alice received XTZ
      finalBobUsdc > 0n && // Bob received USDC
      finalBobXtz < bobXtzBalance; // Bob sent XTZ
    
    if (swapSuccess) {
      logger.log("✅ ATOMIC SWAP COMPLETED SUCCESSFULLY!");
      logger.log("Summary", {
        aliceSentUsdc: formatUnits(aliceUsdcBalance - finalAliceUsdc, 6),
        aliceReceivedXtz: formatUnits(finalAliceXtz, 18),
        bobSentXtz: formatUnits(bobXtzBalance - finalBobXtz, 18),
        bobReceivedUsdc: formatUnits(finalBobUsdc, 6)
      });
    } else {
      logger.error("❌ ATOMIC SWAP FAILED!", { swapSuccess });
    }
    
  } catch (error) {
    logger.error("Test failed", error);
    throw error;
  }
}

// Run the test
if (import.meta.main) {
  testAtomicSwap().catch(console.error);
}